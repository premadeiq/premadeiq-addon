local ADDON, ns = ...

-- SavedVariable schema (v3):
-- PremadeIQ_DB = {
--   schemaVersion = 3,
--   leaders = { "Name-Realm", ... },
--   players = {
--     [guid] = { name, class, faction, lastSeen, samples = { ... } }
--   },
--   matches = { count, lastMapID, lastMapName, lastBracket, lastEndedAt },
--   matchLog = { {
--     endedAt, mapID, mapName, bracket, duration, winner, teamSize,
--     startRoster, leaderGUID,
--     -- startedAt: when WE entered (PVP_MATCH_ACTIVE). Distinct from
--     -- endedAt - duration, which is when the BATTLE started; on a late
--     -- join the two are minutes apart. nil when unknown.
--     startedAt,
--     -- v3 added: periodic in-match scoreboards taken every 300s
--     snapshots = { { takenAt, players = [{guid, dmg, heal, kb, deaths, objective, faction}, ...] }, ... },
--   }, ... },
--   privacy = { firstSeenAt, welcomeSeen },
--   settings = { debug=false, uploaderHintShown=false },
--   -- Live match context parked so it survives a /reload (Collector.lua).
--   -- Written on PVP_MATCH_ACTIVE for EBGs, read back on the next
--   -- PLAYER_ENTERING_WORLD, dropped when the match really ends. Absent
--   -- outside a match. NOT part of schemaVersion: it is optional state, and
--   -- Init creates missing keys lazily, so no migration is involved.
--   activeMatch = { startedAt, battleStart, instanceMapID, savedAt,
--                   isRated, isBlitz, isEpic, matchType },
-- }

local SCHEMA_VERSION   = 3
local MAX_SAMPLES      = 30    -- per encountered player, ring buffer
local MAX_SAMPLES_SELF = 500   -- our own player — keep a much longer history
local MAX_MATCH_LOG    = 200

-- Retention caps for the `players` table (see Database:Prune). These bound the
-- only unbounded part of the DB, keeping the SavedVariables file small so WoW
-- doesn't hang for seconds serializing it on logout.
local MAX_PLAYERS         = 4000  -- hard cap, evicting least-recently-seen
local MAX_PLAYER_AGE_DAYS = 30    -- also drop anyone not seen within this window
local PRUNE_VERSION       = 1     -- recorded in db.pruneVersion after a sweep

local Database = {}
ns.Database = Database

-- Migrate PremadeIQ_DB from any older schema to SCHEMA_VERSION.
-- Idempotent: safe to call on already-current DB.
local function migrate(db)
    -- Old field name `version` → `schemaVersion`
    if db.version and not db.schemaVersion then
        db.schemaVersion = db.version
        db.version = nil
    end

    local from = db.schemaVersion or 1

    if from < 2 then
        -- v1 → v2: settings table, ensure matchLog exists
        db.settings = db.settings or {}
        db.matchLog = db.matchLog or {}
        db.schemaVersion = 2
    end

    if from < 3 then
        -- v2 → v3: snapshots field added to matchLog entries. No data
        -- transform — existing entries simply have no snapshots (server
        -- treats missing as "no timeline available for this match").
        db.schemaVersion = 3
    end
end

function Database:Init()
    if type(PremadeIQ_DB) ~= "table" then PremadeIQ_DB = {} end
    local db = PremadeIQ_DB

    migrate(db)

    db.leaders  = db.leaders  or {}
    db.players  = db.players  or {}
    db.matches  = db.matches  or { count = 0 }
    db.matchLog = db.matchLog or {}
    db.settings = db.settings or {}

    self.db = db
end

function Database:AddSample(guid, meta, sample)
    local p = self.db.players[guid]
    if not p then
        p = { samples = {} }
        self.db.players[guid] = p
    end
    p.name     = meta.name     or p.name
    p.class    = meta.class    or p.class
    p.faction  = meta.faction  or p.faction
    p.lastSeen = meta.lastSeen or p.lastSeen

    table.insert(p.samples, sample)
    local cap = (guid == UnitGUID("player")) and MAX_SAMPLES_SELF or MAX_SAMPLES
    while #p.samples > cap do
        table.remove(p.samples, 1)
    end
end

function Database:CountPlayers()
    local n = 0
    for _ in pairs(self.db.players) do n = n + 1 end
    return n
end

function Database:CountSamples()
    local n = 0
    for _, p in pairs(self.db.players) do
        n = n + (#(p.samples or {}))
    end
    return n
end

function Database:IsLeader(nameRealm)
    for _, v in ipairs(self.db.leaders or {}) do
        if v == nameRealm then return true end
    end
    return false
end

function Database:IncrementMatch(info)
    info = info or {}
    self.db.matches.count       = (self.db.matches.count or 0) + 1
    self.db.matches.lastMapID   = info.mapID
    self.db.matches.lastMapName = info.mapName
    self.db.matches.lastBracket = info.bracket
    self.db.matches.lastEndedAt = info.endedAt or time()

    self.db.matchLog = self.db.matchLog or {}
    table.insert(self.db.matchLog, {
        endedAt  = info.endedAt or time(),
        mapID    = info.mapID, mapName = info.mapName,
        bracket  = info.bracket, duration = info.duration,
        -- When the REPORTER entered the match (addon ≥ 0.9.33). `duration` is
        -- the battle's length, which on a late join starts before we did —
        -- shipping both lets the server bound our actual presence instead of
        -- guessing it from `endedAt - duration`. nil when unknown (/reload
        -- mid-match); the server then keeps its old duration-based guess.
        startedAt = info.startedAt,
        -- GUID of our raid leader at snapshot time; nil if not in a group
        -- or no rank-2 member (solo BG, etc.). Server stores on Match
        -- and increments per-player leader_count.
        leaderGUID = info.leaderGUID,
        winner   = info.winner, teamSize = info.teamSize,
        -- { lateJoin, takenAt, players: [{guid, name, faction}, ...] }
        -- May be nil if Deserter module didn't capture (low-pop match,
        -- /reload mid-game, late join).
        startRoster = info.startRoster,
        -- Periodic in-match scoreboards (every 300s). Used server-side to
        -- recover metrics for players who left before the final scoreboard.
        -- May be empty list for short matches (one tick window) or nil for
        -- pre-0.8.0 captures.
        snapshots = info.snapshots,
        -- Group-leader ("crown") signals, addon ≥ 0.9.25.
        -- enemyCrownMax = max simultaneously visible crowned enemies over the
        -- match (enemy identity is secret in 12.x — a count is all there is).
        -- allyCrowns = [{guid, name}] every group leader on OUR side (raid
        -- lead + home-party leads, fully readable). nil when not captured
        -- (/reload mid-match, pre-0.9.25 client).
        -- enemyCrownSecret (addon ≥ 0.9.37) = peak enemies whose leadership
        -- read back as a SECRET value. 12.1 made UnitLeadsAnyGroup secret
        -- for units with secret identity, i.e. every enemy in a BG. > 0 ⇒
        -- enemyCrownMax is a floor under an unknown, so "0 crowns" must NOT
        -- be served as "this team had no group leaders".
        enemyCrownMax    = info.enemyCrownMax,
        enemyCrownSecret = info.enemyCrownSecret,
        allyCrowns       = info.allyCrowns,
        -- Scoreboard rows still unreadable (secret) at capture time, addon
        -- ≥ 0.9.32. The server skips its desertion heuristic when this is > 0.
        statsSecret   = info.statsSecret,
        -- Baseline roster by NAME (addon ≥ 0.9.33): who was on the board once
        -- it had demonstrably finished loading. nil when no trustworthy
        -- baseline could be taken. { ageSec, rowsH, rowsA, players }
        baseline      = info.baseline,
    })
    while #self.db.matchLog > MAX_MATCH_LOG do
        table.remove(self.db.matchLog, 1)
    end

    -- Keep the player table bounded as fresh rows arrive (the player GUID is
    -- known mid-match). The big session-start sweep runs from PLAYER_ENTERING_WORLD.
    self:Prune()
end

-- ---------------------------------------------------------------------------
-- Retention: keep PremadeIQ_DB small.
--
-- `players` is the only unbounded part of the DB — every player seen in any
-- Epic BG (~80/match) is recorded forever, so a long-running install grows into
-- tens of MB (prod: 29,587 rows → ~46 MB). WoW rewrites the entire
-- SavedVariables file on logout, turning that into a multi-second hang on exit
-- (and a slow load on login).
--
-- These rows exist ONLY to feed the Uploader; the in-game premade alert reads
-- KnownPremades.lua, not this table — so once shipped, the addon has no use for
-- old rows. We keep a rolling window: players seen within MAX_PLAYER_AGE_DAYS,
-- capped at MAX_PLAYERS by most-recent lastSeen. Our own character is never
-- evicted (it carries the long self-history).
--
-- Returns nil when UnitGUID("player") isn't available yet (so the caller can
-- retry on a later event); otherwise before, after, removedByAge, removedByCap.
-- skipAge: when the upload handshake gave us a trusted cursor, PruneUploaded has
-- already removed everything confirmed-uploaded, so we skip the age window (it
-- would re-introduce the offline-Uploader data-loss risk) and keep only the
-- MAX_PLAYERS cap as a hard ceiling.
function Database:Prune(skipAge)
    local db = self.db
    if not db or not db.players then return end
    local selfGUID = UnitGUID("player")
    if not selfGUID then return end  -- self-GUID gate: defer until known

    local cutoff = time() - MAX_PLAYER_AGE_DAYS * 86400
    local before = 0
    for _ in pairs(db.players) do before = before + 1 end

    -- 1) Age sweep — drop players not seen within the window (a missing
    --    lastSeen counts as oldest). Clearing the current key during pairs()
    --    is allowed in Lua. Self is exempt. Skipped when a trusted upload
    --    cursor already drove a precise prune.
    local removedAge = 0
    if not skipAge then
        for guid, p in pairs(db.players) do
            if guid ~= selfGUID and (tonumber(p.lastSeen) or 0) < cutoff then
                db.players[guid] = nil
                removedAge = removedAge + 1
            end
        end
    end

    -- 2) Count cap — if still over MAX_PLAYERS, evict least-recently-seen.
    local removedCap = 0
    local remaining = 0
    for _ in pairs(db.players) do remaining = remaining + 1 end
    if remaining > MAX_PLAYERS then
        local list = {}
        for guid, p in pairs(db.players) do
            if guid ~= selfGUID then
                list[#list + 1] = { guid = guid, ls = tonumber(p.lastSeen) or 0 }
            end
        end
        table.sort(list, function(a, b) return a.ls < b.ls end)  -- oldest first
        local keep = MAX_PLAYERS - (db.players[selfGUID] and 1 or 0)
        for i = 1, (#list - keep) do
            db.players[list[i].guid] = nil
            removedCap = removedCap + 1
        end
    end

    db.pruneVersion = PRUNE_VERSION
    local after = before - removedAge - removedCap

    if self:GetSetting("debug") and (removedAge + removedCap) > 0 then
        print(("|cff33ff99PremadeIQ|r pruned %d→%d players (age %d, cap %d)")
            :format(before, after, removedAge, removedCap))
    end
    return before, after, removedAge, removedCap
end

-- Precise prune: delete samples the server has CONFIRMED (endedAt <= cursor) for
-- every player except self. A sample with no endedAt is kept (we can't prove it
-- was uploaded). A player left with no samples is dropped. The cursor comes from
-- the Uploader handshake (UploadState.lua). Returns removedSamples, removedPlayers.
function Database:PruneUploaded(cursor)
    local db = self.db
    if not db or not db.players then return 0, 0 end
    local selfGUID = UnitGUID("player")
    local removedSamples, removedPlayers = 0, 0
    for guid, p in pairs(db.players) do
        if guid ~= selfGUID and type(p.samples) == "table" then
            local kept = {}
            for _, s in ipairs(p.samples) do
                local e = tonumber(s.endedAt)
                if e == nil or e > cursor then
                    kept[#kept + 1] = s
                else
                    removedSamples = removedSamples + 1
                end
            end
            if #kept == 0 then
                db.players[guid] = nil
                removedPlayers = removedPlayers + 1
            else
                p.samples = kept
            end
        end
    end
    return removedSamples, removedPlayers
end

-- Stable per-account token the Uploader echoes back in UploadState.lua so a
-- shared addon folder across WoW accounts can't cross-wire cursors. Not crypto —
-- realm + GUID tail + a seeded random, generated once and kept in the SV.
local function newInstallId()
    -- NOTE: math.randomseed is NOT exposed in the WoW Lua sandbox (only
    -- math.random, which is already auto-seeded) — calling it throws. The realm
    -- + character-GUID tail is already unique per SV; time() + a random suffix
    -- make it collision-proof.
    local guid  = UnitGUID("player") or ""
    local tail  = guid:match("(%x+)$") or "x"
    local realm = (GetRealmName() or "?"):gsub("%s+", "")
    return ("%s-%s-%x-%x"):format(
        realm, tail, (time() or 0) % 0x7FFFFFFF, math.random(0, 0x7FFFFFFF))
end

-- Read the trusted sample cursor for THIS account out of UploadState.lua (written
-- by the Uploader). nil unless the installId matches and the value is a plausible
-- number. Monotonic (never moves backwards) and clamped against a corrupt/future
-- value so a bad file can't tell us to wipe the whole DB.
local function trustedCursor(db)
    local us = PremadeIQ_UploadState
    if type(us) ~= "table" or type(us.cursors) ~= "table" then return nil end
    if not db.installId then return nil end
    local entry = us.cursors[db.installId]
    if type(entry) ~= "table" then return nil end
    local c = tonumber(entry.samplesUploadedThrough)
    if not c then return nil end
    local prev = tonumber(db.lastSamplesUploadedThrough) or 0
    if c < prev then c = prev end                  -- monotonic
    if c > time() + 86400 then c = prev end         -- implausible future → ignore
    return c
end

-- One sweep per session, fired from PLAYER_ENTERING_WORLD once UnitGUID("player")
-- is available (nil on ADDON_LOADED). Generates the installId, runs the precise
-- upload-cursor prune when we have a trusted cursor (else the age heuristic), and
-- always applies the MAX_PLAYERS ceiling. Records one diagnostic line.
function Database:PruneIfReady()
    if self._prunedThisSession then return true end
    local db = self.db
    if not db then return false end
    if not UnitGUID("player") then return false end  -- GUID not ready; retry later

    if not db.installId then db.installId = newInstallId() end
    self._prunedThisSession = true

    local before = self:CountPlayers()

    local cursor = trustedCursor(db)
    local removedSamples, removedUploaded = 0, 0
    if cursor then
        db.lastSamplesUploadedThrough = cursor
        removedSamples, removedUploaded = self:PruneUploaded(cursor)
    end

    -- Backstop: always cap the count; apply the age window ONLY when no trusted
    -- cursor (with one, PruneUploaded already did the precise work).
    local _, _, removedAge, removedCap = self:Prune(cursor ~= nil)
    removedAge, removedCap = removedAge or 0, removedCap or 0

    local after = self:CountPlayers()
    if before ~= after or removedSamples > 0 then
        db.collectorLog = db.collectorLog or {}
        db.collectorLog[#db.collectorLog + 1] = date("%H:%M:%S")
            .. (" prune: %d→%d players (uploaded %d/%d, age %d, cap %d)"):format(
                before, after, removedUploaded, removedSamples, removedAge, removedCap)
        while #db.collectorLog > 50 do table.remove(db.collectorLog, 1) end
    end
    return true
end

-- Settings helpers
function Database:GetSetting(key)
    return self.db.settings and self.db.settings[key]
end

function Database:SetSetting(key, value)
    self.db.settings = self.db.settings or {}
    self.db.settings[key] = value
end
