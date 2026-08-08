local ADDON, ns = ...

local Collector = {}
ns.Collector = Collector

-- Whitelist of Epic Battleground *instance* map ids — the service collects
-- ONLY these. Mirror of the server's integrity.EBG_MAP_NAMES; if Blizzard
-- ships a new Epic BG, BOTH tables need the new id. Legacy ids 1334/1478
-- are deliberately absent: a modern 12.x client never produces them, they
-- only exist in historical DB rows.
--
-- ns-level (not file-local) on purpose: Collector gates the snapshot with
-- it and Main.lua gates the PVP_MATCH_COMPLETE handler — one source of
-- truth, no per-file copies to drift apart.
ns.EBG_INSTANCE_IDS = {
    [30]   = true,  -- Альтеракская долина
    [628]  = true,  -- Остров Завоеваний
    [1191] = true,  -- Ашран
    [2118] = true,  -- Битва за озеро Ледяных Оков
    [2197] = true,  -- Месть Коррака (сезонный Альтерак)
    [2799] = true,  -- Зубец убийцы (Deephaul Ravine)
}

function ns.IsEBGInstanceID(id)
    return id ~= nil and ns.EBG_INSTANCE_IDS[id] == true
end

-- Match context populated on PVP_MATCH_ACTIVE, finalised on PVP_MATCH_COMPLETE.
local ctx = {}

-- Diagnostic ring buffer (PremadeIQ_DB.collectorLog) — same pattern as
-- PremadeAlert's alertLog. Records gate decisions (skipped matches, nil
-- instance ids) so a silently-dropped match is reconstructable from
-- SavedVariables instead of depending on the player watching chat.
local function dbg(line)
    local db = ns.Database and ns.Database.db
    if not db then return end
    db.collectorLog = db.collectorLog or {}
    db.collectorLog[#db.collectorLog + 1] = date("%H:%M:%S") .. " " .. line
    while #db.collectorLog > 50 do table.remove(db.collectorLog, 1) end
    if ns.Database.GetSetting and ns.Database:GetSetting("debug") then
        print("|cff33ff99PremadeIQ|r |cff888888" .. line .. "|r")
    end
end

-- Mid-match snapshot cadence. Long Epic BGs swap players in/out before
-- the final scoreboard, so we sample periodically to (a) catch metrics
-- for players who leave mid-match and (b) build a rough timeline of
-- damage/heal/deaths progression. 300s = 5 min picks up most swaps
-- without flooding storage on hour-long stall-wars (~18 snapshots).
--
-- DISABLED in 0.8.2: retail 12.0.x marks ALL live scoreboard data
-- (guid included) as secret values during an active match. The Lua
-- serializer drops secret strings from SavedVariables outright, so
-- snapshots arrive at the server with no guid and zeroed numbers —
-- useless for off-board metric recovery. The code is kept in place
-- for when we wire an alternative source (combat log parser, or a
-- secure-context hook). Setting interval to 0 disables the ticker.
local MID_SNAPSHOT_INTERVAL = 0

-- ── Baseline roster ──────────────────────────────────────────────────────
-- What survives the secret-value regime: PVPScoreInfo marks `name`, `faction`,
-- `raceName`, `className` and `classToken` as NeverSecret (see
-- Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua), while `guid`
-- and every combat number may be secret mid-match. So we cannot recover a
-- leaver's metrics — but we CAN record WHO was on the board before the
-- substitutions started, by name, for both teams.
--
-- One baseline per match, taken once the scoreboard has demonstrably finished
-- loading. That is enough to answer "did this player join late?", which the
-- server needs for two things: the late-join badge, and the late-join veto in
-- its desertion heuristic (whose only current source, startRoster, is built
-- from raid unit tokens and therefore covers our own side only).
--
-- Thresholds are deliberately conservative — a false "joined late" is worse
-- than no answer, and the ENEMY half of an Epic scoreboard can take a minute
-- or more to populate client-side (see PremadeAlert's scan-window comments).
-- "Both sides look full" is NOT the test: a side that is down a player sits at
-- 39. We require a stable, near-complete board confirmed twice in a row.
local BASELINE_MIN_AGE_SEC   = 120   -- match must be at least this old
local BASELINE_MIN_ROWS_SIDE = 38    -- rows visible on EACH side
local BASELINE_CONFIRM_TICKS = 2     -- consecutive observations that agree

-- =========================================================================
-- Group-leader ("crown") tracking — the premade tell that needs no names.
--
-- ``UnitLeadsAnyGroup(unit)`` answers "does this unit lead the group it is
-- in" for ANY unit token, enemies included — it is what draws the crown on
-- the Blizzard target frame (TargetFrameMixin:CheckPartyLeader). Inside a
-- BG every party that queued TOGETHER keeps its home-party leader flagged,
-- so the count of crowned enemies visible at one time is a lower bound on
-- how many pre-formed groups the other team brought. One crown is just
-- their raid lead; two or more means grouped players.
--
-- What 12.x secrecy leaves us (verified live, 2026-07): leadership IS
-- readable on enemy nameplate units with no interaction, but enemy
-- identity (name/guid) is secret both mid-match AND post-match — so the
-- enemy side contributes a COUNT only. Our own raid is fully readable, so
-- ally crowns ship as guid+name; one report from the other faction of the
-- same match names OUR enemies on the server side.
--
-- C_NamePlate.GetNamePlates() returns nothing useful inside PvP instances,
-- so we keep our own registry fed by NAME_PLATE_UNIT_ADDED/REMOVED (which
-- do fire there) and poll it on a short ticker.
-- =========================================================================

local CROWN_TICK_SEC   = 2    -- nameplate poll cadence
local ALLY_SWEEP_TICKS = 30   -- ally raid sweep every Nth tick (~60s)

local plateUnits = {}         -- unitToken -> true (event-fed registry)

local plateWatcher = CreateFrame("Frame")
plateWatcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plateWatcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
plateWatcher:SetScript("OnEvent", function(_, event, unit)
    if not unit then return end
    plateUnits[unit] = (event == "NAME_PLATE_UNIT_ADDED") and true or nil
end)

-- true only for a PROVEN non-secret truthy value. Secrets are truthy in
-- Lua, so a bare ``if v`` would misread every secret as a yes.
local function notSecretTrue(v)
    if issecretvalue and issecretvalue(v) then return false end
    return v and true or false
end

-- Deliberately NOT UnitCanAttack (hostility drops the moment the match
-- completes) and secret-guarded per check: a secret answer means "not
-- proven friendly", never "friendly" — the opposite reading silently
-- discards every enemy whose identity checks come back secret.
local function isFriendlyUnit(unit)
    return notSecretTrue(UnitIsUnit(unit, "player"))
        or notSecretTrue(UnitInRaid(unit))
        or notSecretTrue(UnitInParty(unit))
end

-- One poll: how many enemy players with a visible nameplate lead a group.
-- UnitIsPlayer left unguarded on purpose: secret (= can't tell) passes,
-- a plain false (NPC) is excluded — a crowned NPC can't happen anyway.
local function pollEnemyCrowns()
    local crowns = 0
    for u in pairs(plateUnits) do
        if UnitExists(u) then
            if not isFriendlyUnit(u) and UnitIsPlayer(u)
                and notSecretTrue(UnitLeadsAnyGroup(u)) then
                crowns = crowns + 1
            end
        else
            plateUnits[u] = nil        -- stale token (missed REMOVED)
        end
    end
    return crowns
end

-- Our own raid is fully readable: collect every group leader (raid lead
-- and home-party leads alike) as guid+name into ctx.allyCrowns. Repeat
-- sweeps merge by GUID, so mid-match lead changes accumulate rather than
-- overwrite.
local function sweepAllyCrowns()
    local crowns = ctx.allyCrowns
    if not crowns or not IsInRaid() then return end
    for i = 1, (GetNumGroupMembers() or 0) do
        local u = "raid" .. i
        if UnitExists(u) and notSecretTrue(UnitLeadsAnyGroup(u)) then
            local guid = UnitGUID(u)
            local name = GetUnitName(u, true)   -- "Name-Realm" cross-realm, bare same-realm
            if guid and name
                and not (issecretvalue and (issecretvalue(guid) or issecretvalue(name))) then
                if not name:find("-", 1, true) then
                    local realm = GetRealmName()
                    if realm and realm ~= "" then
                        name = name .. "-" .. realm:gsub(" ", "")
                    end
                end
                crowns[guid] = name
            end
        end
    end
end

-- =========================================================================
-- Surviving a /reload  (see docs/plans/plan-2026-08-08-startedat-persistence.md)
--
-- ``ctx`` is a file local, so a /reload inside a battleground wipes it and
-- PVP_MATCH_ACTIVE never fires a second time. Everything the match context
-- knew is gone — most damagingly ``startedAt``, which the server needs to
-- tell a legitimate back-to-back match from one reporter claiming to be in
-- two matches at once. Prod 08.08: match 1786139321 was quarantined as
-- temporal_overlap for exactly this reason, and 5 of the 18 snapshots in the
-- owner's collectorLog ring show the tell-tale "adopted instance=… from
-- COMPLETE handler" line.
--
-- So the fragile parts get parked in SavedVariables (which WoW flushes on
-- ReloadUI — the same property the owner-only live overlay relies on) and
-- read back on the PLAYER_ENTERING_WORLD that follows.
-- =========================================================================

-- Tolerance when matching the parked battle fingerprint against the live one.
-- Both ends are ``time() - GetActiveMatchDuration()``; they can disagree by
-- the second-rounding of that API plus the delay of whoever reads it later.
-- ~7s is the realistic worst case, so 15 is comfortable. Deliberately NOT
-- wider: two different Epics can start within a minute of each other when the
-- queue pops in waves, and a loose fingerprint would adopt the wrong match's
-- start time.
local ACTIVE_MATCH_FINGERPRINT_TOL = 15

-- When WE consider a parked record too old to mean anything. Mirrors the
-- server's absolute duration ceiling (integrity._MAX_DURATION_SEC).
local ACTIVE_MATCH_MAX_AGE_SEC = 21600

-- Start of the BATTLE, or nil when the API won't say. This is NOT a stand-in
-- for startedAt: on a late join the battle began minutes before we arrived,
-- which is the very error the 0.9.33 fix removed. It is used only as a
-- fingerprint — a value that is stable within one match and differs between
-- matches.
local function battleStartStamp()
    local dur = C_PvP and C_PvP.GetActiveMatchDuration and C_PvP.GetActiveMatchDuration()
    if type(dur) ~= "number" or dur < 0 then return nil end
    return time() - math.floor(dur)
end

local function persistActiveMatch()
    local db = ns.Database and ns.Database.db
    if not db then return end
    db.activeMatch = {
        startedAt     = ctx.startedAt,
        battleStart   = battleStartStamp(),
        instanceMapID = ctx.instanceMapID,
        savedAt       = time(),
        -- Bracket fields too: without them a post-reload match uploads as
        -- plain "BG" instead of "EPIC". Free to carry, we are writing anyway.
        isRated       = ctx.isRated,
        isBlitz       = ctx.isBlitz,
        isEpic        = ctx.isEpic,
        matchType     = ctx.matchType,
    }
end

local function clearActiveMatch()
    local db = ns.Database and ns.Database.db
    if db then db.activeMatch = nil end
end

-- Rebuild ctx from the parked record after a /reload. Called from the
-- PLAYER_ENTERING_WORLD handler while we are still INSIDE the battleground:
-- GetInstanceInfo and GetActiveMatchDuration are both valid there, unlike at
-- snapshot time when the post-match teleport may already have happened.
--
-- Every gate must pass. A refusal costs nothing — it just leaves the old
-- behaviour, where the server falls back to the duration-derived window.
function Collector:RestoreContext()
    if ctx.startedAt then return false end        -- context is alive already
    local db = ns.Database and ns.Database.db
    local saved = db and db.activeMatch
    if not (saved and saved.startedAt) then return false end

    local now = time()
    if now - (saved.savedAt or 0) > ACTIVE_MATCH_MAX_AGE_SEC then
        dbg("restore skipped: parked record is stale")
        clearActiveMatch()
        return false
    end
    if saved.startedAt >= now then
        dbg("restore skipped: parked startedAt is not in the past")
        return false
    end

    local liveID = select(8, GetInstanceInfo())
    if liveID == nil or liveID ~= saved.instanceMapID then
        dbg(("restore skipped: instance %s != parked %s")
            :format(tostring(liveID), tostring(saved.instanceMapID)))
        return false
    end

    -- The fingerprint is what makes this safe. Without it we could inherit
    -- the previous match's startedAt after leaving one battle and entering
    -- another on the same map.
    local liveStart = battleStartStamp()
    if liveStart == nil or saved.battleStart == nil
        or math.abs(liveStart - saved.battleStart) > ACTIVE_MATCH_FINGERPRINT_TOL then
        dbg(("restore skipped: battle fingerprint %s vs parked %s")
            :format(tostring(liveStart), tostring(saved.battleStart)))
        return false
    end

    ctx.startedAt     = saved.startedAt
    ctx.instanceMapID = saved.instanceMapID
    ctx.isEBG         = ns.IsEBGInstanceID(saved.instanceMapID)
    ctx.mapName       = ctx.mapName or GetRealZoneText()
    ctx.isRated       = saved.isRated
    ctx.isBlitz       = saved.isBlitz
    ctx.isEpic        = saved.isEpic
    ctx.matchType     = saved.matchType
    ctx.premadeGUIDs  = ctx.premadeGUIDs or {}
    ctx.snapshots     = ctx.snapshots or {}
    dbg(("restored context: instance=%d startedAt=-%ds")
        :format(saved.instanceMapID, now - saved.startedAt))
    return true
end

function Collector:OnMatchActive()
    -- Stop any leftover ticker from a previous match that ended uncleanly
    -- (DC, /reload). Ticker holds a closure on stale ctx — leaking it would
    -- write snapshots for the new match using the prior match's startedAt.
    if ctx.snapshotTicker then
        ctx.snapshotTicker:Cancel()
        ctx.snapshotTicker = nil
    end
    if ctx.crownTicker then
        ctx.crownTicker:Cancel()
        ctx.crownTicker = nil
    end
    -- Instance map id (GetInstanceInfo, 8th return) is the ONLY id space we
    -- use — it's what the server whitelists. The old fallback to
    -- C_Map.GetBestMapForUnit (UiMapID — a DIFFERENT id space) silently fed
    -- the server ids it could never recognise and got ~3% of real Epics
    -- quarantined as non_ebg_map (prod: uiMap 91/169/113/572/2397 rows with
    -- 40-player teams). PVP_MATCH_ACTIVE fires after the loading screen, so
    -- GetInstanceInfo is expected to be valid here.
    local instanceMapID = select(8, GetInstanceInfo())
    ctx = {
        startedAt  = time(),
        instanceMapID = instanceMapID,
        isEBG      = ns.IsEBGInstanceID(instanceMapID),
        mapName    = GetRealZoneText(),
        -- Bracket / type (best-effort across Midnight API variants)
        isRated    = (C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground()) or false,
        isBlitz    = (C_PvP.IsSoloRBG and C_PvP.IsSoloRBG())
                      or (C_PvP.IsInBrawl and C_PvP.IsInBrawl()) or false,
        isEpic     = (C_PvP.IsBattlegroundEnlistmentBonus and C_PvP.IsBattlegroundEnlistmentBonus()) or nil,
        matchType  = (C_PvP.GetCurrentMatchType and C_PvP.GetCurrentMatchType()) or nil,
        -- Premade detection: lock the party GUIDs we entered with
        premadeGUIDs = {},
        -- Mid-match snapshots {takenAt, players: [{guid, dmg, heal, kb, deaths, objective, faction}]}
        snapshots  = {},
    }
    -- Park the parts of ctx that a /reload would otherwise destroy. See
    -- RestoreContext below for why this exists and what guards the read back.
    if ctx.isEBG then persistActiveMatch() end

    -- Everyone in our party/raid at match start = presumed premade
    local n = GetNumGroupMembers() or 0
    if n > 0 then
        local unitPrefix = IsInRaid() and "raid" or "party"
        for i = 1, n do
            local g = UnitGUID(unitPrefix .. i)
            if g then ctx.premadeGUIDs[g] = true end
        end
        local me = UnitGUID("player")
        if me then ctx.premadeGUIDs[me] = true end
    end

    -- Start periodic mid-match snapshot ticker. C_Timer.NewTicker repeats
    -- indefinitely until :Cancel() — we cancel on PVP_MATCH_COMPLETE and on
    -- any subsequent OnMatchActive (so a missed COMPLETE event from a
    -- DC/reload can't double-fire). When MID_SNAPSHOT_INTERVAL is 0 the
    -- feature is disabled — see comment on the constant for why.
    if MID_SNAPSHOT_INTERVAL > 0 then
        ctx.snapshotTicker = C_Timer.NewTicker(MID_SNAPSHOT_INTERVAL, function()
            Collector:TakeMidSnapshot()
        end)
    end

    -- Crown tracking (see section header above). The ticker starts for every
    -- match but its body gates on ctx.isEBG, so the nil-retry late-start
    -- path picks it up automatically without extra wiring. ``ctx`` is read
    -- through the upvalue at tick time: after the end-of-match reset the
    -- surviving ticks see the fresh empty context and no-op.
    wipe(plateUnits)
    ctx.enemyCrownMax = 0
    ctx.allyCrowns    = {}
    local crownTick = 0
    ctx.crownTicker = C_Timer.NewTicker(CROWN_TICK_SEC, function()
        if not ctx.isEBG then return end
        crownTick = crownTick + 1
        local crowns = pollEnemyCrowns()
        if crowns > (ctx.enemyCrownMax or 0) then
            ctx.enemyCrownMax = crowns
            if ns.PremadeAlert and ns.PremadeAlert.OnEnemyCrowns then
                ns.PremadeAlert:OnEnemyCrowns(crowns)
            end
        end
        -- First ally sweep ~2s in (roster may still settle — later sweeps
        -- merge by GUID), then roughly once a minute.
        if crownTick % ALLY_SWEEP_TICKS == 1 then
            sweepAllyCrowns()
        end
    end)

    if not ctx.isEBG then
        if instanceMapID == nil then
            -- Uncertainty, not a verdict: GetInstanceInfo SHOULD be valid on
            -- PVP_MATCH_ACTIVE, but if a timing case ever returns nil we retry
            -- once. A whitelist hit late-starts the roster/alert modules
            -- (safe at +2s: Deserter's capture train runs to +14s,
            -- PremadeAlert's scan train starts at +4s and runs to +170s).
            dbg("ACTIVE instance=nil — retry in 2s")
            local myCtx = ctx
            C_Timer.After(2, function()
                if myCtx ~= ctx then return end  -- a different match took over
                local id = select(8, GetInstanceInfo())
                if ns.IsEBGInstanceID(id) then
                    ctx.instanceMapID, ctx.isEBG = id, true
                    dbg(("ACTIVE retry: instance=%d — EBG, late start"):format(id))
                    if ns.Deserter then ns.Deserter:OnMatchActive() end
                    if ns.PremadeAlert then ns.PremadeAlert:OnMatchActive() end
                else
                    dbg(("ACTIVE retry: instance=%s — not EBG"):format(tostring(id)))
                end
            end)
        else
            dbg(("non-EBG match (instance=%d) — collection off"):format(instanceMapID))
        end
    end
end

function Collector:GetMatchContext()
    return ctx
end

-- True when the CURRENT match was recognised as an Epic BG on
-- PVP_MATCH_ACTIVE (or by the nil-retry above). Main.lua gates the
-- Deserter/PremadeAlert event handlers and the COMPLETE snapshot on this.
function Collector:IsEBGMatch()
    return ctx.isEBG == true
end

-- Main.lua logs its gate decisions into the same collectorLog ring buffer.
function Collector:Debug(line)
    dbg(line)
end

-- /reload mid-match wipes ctx; the COMPLETE handler then admits the match
-- via its own live GetInstanceInfo read. Stash that id here so the actual
-- snapshot (+1.4s later, possibly already teleported out) still has an
-- instance id to fall back on — otherwise the hard guard below would drop
-- a legitimate Epic.
function Collector:AdoptInstanceID(id)
    if ns.IsEBGInstanceID(id) and not ctx.isEBG then
        ctx.instanceMapID, ctx.isEBG = id, true
        dbg(("adopted instance=%d from COMPLETE handler"):format(id))
    end
end

-- Returns the GUID of the raid leader on our side, or nil if we're not
-- in a group or no rank-2 member is found. ``GetRaidRosterInfo(i)`` rank
-- field: 0 = none, 1 = assist, 2 = leader. Iterates raid first (epic BG),
-- falls back to party (small BGs / arenas — leader concept still exists).
local function findRaidLeaderGUID()
    local n = GetNumGroupMembers() or 0
    if n == 0 then return nil end
    if IsInRaid() then
        for i = 1, n do
            local _, rank = GetRaidRosterInfo(i)
            if rank == 2 then
                return UnitGUID("raid"..i)
            end
        end
    else
        -- Party: leader is whoever returns true for UnitIsGroupLeader.
        if UnitIsGroupLeader and UnitIsGroupLeader("player") then
            return UnitGUID("player")
        end
        for i = 1, n - 1 do
            local unit = "party"..i
            if UnitIsGroupLeader and UnitIsGroupLeader(unit) then
                return UnitGUID(unit)
            end
        end
    end
    return nil
end

-- Retail 12.0.x marks live in-match scoreboard numbers as "secret
-- values" — reading them in insecure code is fine, but any arithmetic
-- on them taints the call site ("attempt to perform arithmetic on a
-- secret number value"). The final post-match snapshot escapes this
-- because Blizzard drops the protection on PVP_MATCH_COMPLETE, but
-- our 300s-interval mid-match captures hit it head-on.
--
-- ``issecretvalue`` is a built-in Lua helper Blizzard exposes for
-- exactly this case. We guard every numeric read with it and fall
-- back to 0, so a tainted field doesn't kill the whole snapshot —
-- the row still ships with whatever fields are readable. nil is
-- treated as 0 to keep the call site branchless.
local function safeNum(v)
    if v == nil then return 0 end
    if issecretvalue and issecretvalue(v) then return 0 end
    return v
end

-- Mid-match snapshot: lightweight scoreboard capture taken every
-- MID_SNAPSHOT_INTERVAL seconds while the match is active. Stores only
-- the volatile numeric fields (dmg/heal/kb/deaths/objective) keyed by
-- GUID — no race/class/spec/name (those don't change mid-match and are
-- already in the final snapshot).
--
-- Lazy refresh: we still need a server-side score poke so rows are
-- populated, but the 0.7s settle delay is shorter than the final
-- snapshot — mid-match accuracy doesn't matter to the second.
function Collector:TakeMidSnapshot()
    if RequestBattlefieldScoreData then
        RequestBattlefieldScoreData()
    end
    C_Timer.After(0.7, function()
        local numScores = GetNumBattlefieldScores() or 0
        if numScores == 0 then return end

        local takenAt = time()
        local players = {}
        for i = 1, numScores do
            local info = C_PvP.GetScoreInfo(i)
            if info and info.guid then
                local obj = 0
                if info.stats then
                    for _, s in ipairs(info.stats) do
                        -- safeNum returns 0 for secret values, so the
                        -- arithmetic below stays untainted regardless.
                        obj = obj + safeNum(s.pvpStatValue)
                    end
                end
                table.insert(players, {
                    guid      = info.guid,
                    dmg       = safeNum(info.damageDone),
                    heal      = safeNum(info.healingDone),
                    kb        = safeNum(info.killingBlows),
                    deaths    = safeNum(info.deaths),
                    objective = obj,
                    faction   = info.faction,
                })
            end
        end
        if #players > 0 then
            ctx.snapshots = ctx.snapshots or {}
            table.insert(ctx.snapshots, {
                takenAt = takenAt,
                players = players,
            })
        end
    end)
end

-- Canonical scoreboard name: WoW elides the realm for same-realm players, so
-- append ours to match the cross-realm "Name-Realm" form the rest of the
-- pipeline (and the final snapshot) uses. Without this the baseline would not
-- line up with the final scoreboard and every local player would read as a
-- late join.
local function scoreName(name)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetRealmName()
    if realm and realm ~= "" then
        return name .. "-" .. realm:gsub(" ", "")
    end
    return nil   -- no realm to qualify with: unusable as an identity
end

-- One probe of the baseline condition. Returns true once the baseline has been
-- captured (or was already), so the caller can stop probing.
--
-- Runs off the scoreboard updates the addon already receives — no independent
-- polling loop competing with the premade scan for the same (expensive)
-- SetBattlefieldScoreFaction refresh.
function Collector:TryCaptureBaseline()
    if ctx.baseline or not ctx.isEBG then return ctx.baseline ~= nil end
    -- Kicked / left / grace-window: the reset can arrive late, so re-check.
    if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        return false
    end
    -- Never once the match is over. AdoptInstanceID flips ctx.isEBG on
    -- PVP_MATCH_COMPLETE, and ScheduleSnapshotMatch's refresh() then fires
    -- UPDATE_BATTLEFIELD_SCORE synchronously — so without this gate a context
    -- that missed the match (crashed client, addon enabled mid-match, and
    -- until now a /reload) captures the FINAL scoreboard and files it as "who
    -- was here at the start". Measured on the owner's SavedVariables before
    -- the fix: 15 of 50 baselines had ageSec > 600, up to 3156s.
    -- The damage is on the server: a baseline containing everyone who
    -- survived silently disables the late-join veto that protects the
    -- deserter heuristic (routers/samples.py) and the late-join badge
    -- (routers/dashboard.py), and it is shared with every other reporter of
    -- that match.
    if C_PvP.IsMatchComplete and C_PvP.IsMatchComplete() then
        return false
    end
    -- SetBattlefieldScoreFaction fires UPDATE_BATTLEFIELD_SCORE synchronously,
    -- which re-enters this function — guard, exactly as PremadeAlert does.
    if ctx.baselineBusy then return false end
    -- Age is MATCH age, never "time since we started watching": a reporter who
    -- joined late must not mistake their own arrival for the match start.
    local age = C_PvP.GetActiveMatchDuration and C_PvP.GetActiveMatchDuration()
    if type(age) ~= "number" or age < BASELINE_MIN_AGE_SEC then return false end

    ctx.baselineBusy = true
    if SetBattlefieldScoreFaction then pcall(SetBattlefieldScoreFaction, -1) end
    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
    local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    local rows, seen = { [0] = 0, [1] = 0 }, {}
    for i = 1, n do
        local info = C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i)
        if info and (info.faction == 0 or info.faction == 1) then
            local nm = scoreName(info.name)   -- nil when secret/unqualifiable
            if nm and not seen[nm] then
                seen[nm] = info.faction
                rows[info.faction] = rows[info.faction] + 1
            end
        end
    end
    ctx.baselineBusy = false

    if rows[0] < BASELINE_MIN_ROWS_SIDE or rows[1] < BASELINE_MIN_ROWS_SIDE then
        ctx.baselineStreak = 0
        return false
    end
    -- Require the near-complete board to hold across consecutive observations
    -- so one lucky read of a still-filling cache cannot become the baseline.
    ctx.baselineStreak = (ctx.baselineStreak or 0) + 1
    if ctx.baselineStreak < BASELINE_CONFIRM_TICKS then return false end

    local players = {}
    for nm, faction in pairs(seen) do
        players[#players + 1] = { n = nm, f = faction }
    end
    ctx.baseline = {
        ageSec  = math.floor(age),
        rowsH   = rows[0],
        rowsA   = rows[1],
        players = players,
    }
    -- name → row, so the final snapshot can staple guids on in O(1).
    ctx.baselineByName = {}
    for _, row in ipairs(players) do ctx.baselineByName[row.n] = row end
    dbg(("baseline captured age=%ds rows=%d/%d players=%d")
        :format(math.floor(age), rows[0], rows[1], #players))
    return true
end

-- Called from the UPDATE_BATTLEFIELD_SCORE handler (Main.lua). Cheap no-op
-- once the baseline exists, which is the common case for most of a match.
function Collector:OnBattlefieldScoreUpdate()
    if ctx.baseline then return end
    self:TryCaptureBaseline()
end

-- ── Scoreboard readiness ─────────────────────────────────────────────────
-- Retail 12.0.x can hand back the final scoreboard with the combat numbers
-- still flagged as SECRET values. They are truthy, so `x or 0` does not catch
-- them; the SavedVariables serializer then drops them and the row reaches the
-- server as all-zero — indistinguishable from a player who did nothing. Prod
-- evidence: three consecutive matches where the viewer's own row read
-- 0/0/0/0 while honorGained and honorableKills came through fine, and one AV
-- where 20 of 40 rows on one side were empty. Those rows then tripped the
-- server's desertion heuristic against players who had played the whole game.
--
-- So: probe before capturing, and count the two failure shapes separately —
-- SECRET (we could not read it) vs a plain zero (we read it, it really is 0).
-- Only the first is worth waiting for; the second is legitimate data.
local READY_RETRY_DELAY_SEC = 1.5
local READY_MAX_ATTEMPTS    = 4

local function scoreboardReadiness()
    local n = GetNumBattlefieldScores() or 0
    local secretRows, zeroRows = 0, 0
    for i = 1, n do
        local info = C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i)
        if info then
            local isSecret = false
            for _, v in ipairs({ info.damageDone, info.healingDone,
                                 info.killingBlows, info.deaths }) do
                if issecretvalue and issecretvalue(v) then isSecret = true end
            end
            if isSecret then
                secretRows = secretRows + 1
            elseif safeNum(info.damageDone) == 0 and safeNum(info.healingDone) == 0
                    and safeNum(info.killingBlows) == 0 and safeNum(info.deaths) == 0 then
                zeroRows = zeroRows + 1
            end
        end
    end
    return n, secretRows, zeroRows
end

-- Public entry point used at match end.
--
-- Why this wrapper exists: the WoW client caches scoreboard rows
-- lazily — only the team(s) whose pane the player has actually
-- viewed during the match get populated. On EBG maps with a fast
-- post-match teleport (AV / IoC) the player typically never opens
-- the enemy pane, so an immediate ``GetNumBattlefieldScores()``
-- returns only the player's own faction (40 rows instead of 80).
--
-- Fix: explicitly poke the server with ``RequestBattlefieldScoreData()``
-- twice with a short gap so both teams' rows make it into the
-- client cache, then iterate. Two refreshes (vs one) cover the
-- case where the first response only contained the team that was
-- last viewed; the second forces a full re-population.
function Collector:ScheduleSnapshotMatch(callback)
    local function refresh()
        -- Unfilter to BOTH factions before requesting. RequestBattlefieldScoreData
        -- alone does NOT lift the per-faction filter — only SetBattlefieldScoreFaction(-1)
        -- shows both sides (the same call Blizzard's own scoreboard makes for the
        -- "all factions" tab; PremadeAlert proved a bare request leaves only the
        -- locally-viewed half). Empirically ~1% of matches still arrived single-
        -- faction without this; cheap belt-and-suspenders on an already-complete match.
        if SetBattlefieldScoreFaction then pcall(SetBattlefieldScoreFaction, -1) end
        if RequestBattlefieldScoreData then
            RequestBattlefieldScoreData()
        end
    end
    refresh()
    C_Timer.After(0.7, function()
        refresh()
        C_Timer.After(0.7, function()
            -- Wait for the secret flags to come off before writing anything.
            -- We never re-run SnapshotMatch after a write: AddSample appends
            -- (Database.lua) and endedAt is time() taken inside, so a second
            -- pass would duplicate every row AND register a second match.
            -- Hence the retry lives here, strictly before the capture.
            local function attempt(k)
                local rows, secretRows, zeroRows = scoreboardReadiness()
                dbg(("ready attempt=%d rows=%d secret=%d zero=%d")
                    :format(k, rows, secretRows, zeroRows))
                if secretRows > 0 and k < READY_MAX_ATTEMPTS then
                    refresh()
                    C_Timer.After(READY_RETRY_DELAY_SEC, function() attempt(k + 1) end)
                    return
                end
                -- Out of attempts (or nothing secret left): capture regardless.
                -- A partly-unreadable scoreboard still beats losing the match,
                -- and statsSecret tells the server how much to trust it.
                local n = self:SnapshotMatch(secretRows)
                if callback then callback(n) end
            end
            attempt(1)
        end)
    end)
end

-- Snapshot: iterate all score rows and push each row as a sample.
-- ``statsSecret`` (optional): how many scoreboard rows still read as secret
-- when ScheduleSnapshotMatch gave up waiting. Shipped with the match so the
-- server knows this capture is partly ours, not the players' — it refuses to
-- infer desertion from a scoreboard we could not read. A direct call
-- (/piq snapshot) passes nothing and the field stays nil = "unknown".
function Collector:SnapshotMatch(statsSecret)
    local numScores = GetNumBattlefieldScores() or 0
    if numScores == 0 then return 0 end

    local endedAt  = time()
    -- Prefer C_PvP.GetActiveMatchWinner (more reliable across 12.0), fall back
    -- to legacy GetBattlefieldWinner. Both return 0=Horde, 1=Alliance, nil=unknown.
    local winner
    if C_PvP and C_PvP.IsMatchComplete and C_PvP.IsMatchComplete()
        and C_PvP.GetActiveMatchWinner then
        winner = C_PvP.GetActiveMatchWinner()
    end
    if winner == nil then winner = GetBattlefieldWinner() end
    local duration = (C_PvP.GetActiveMatchDuration and C_PvP.GetActiveMatchDuration())
                      or (ctx.startedAt and (endedAt - ctx.startedAt))
                      or nil
    -- Map id: instance id ONLY (the id space the server whitelists). Prefer
    -- the live read while we're still inside the BG; if the post-match
    -- teleport already moved us (live id = capital / not whitelisted), fall
    -- back to the instance id captured on PVP_MATCH_ACTIVE. Never UiMapID —
    -- the old C_Map.GetBestMapForUnit fallback mixed id spaces and got real
    -- Epics quarantined server-side as non_ebg_map.
    local liveID  = select(8, GetInstanceInfo())
    local mapID   = (ns.IsEBGInstanceID(liveID) and liveID)
                  or ctx.instanceMapID
    local mapName = (mapID and GetRealZoneText(mapID))
                  or ctx.mapName or ""

    -- Hard guard: never write a non-EBG match, whatever path led here.
    -- The PVP_MATCH_COMPLETE handler already gates, but /piq snapshot
    -- (cmdSnapshot → ScheduleSnapshotMatch directly) and any future
    -- event-order bug land in this function too — the server quarantine
    -- must stay defense-in-depth, not the primary filter.
    if not ns.IsEBGInstanceID(mapID) then
        dbg(("snapshot refused: non-EBG instance %s"):format(tostring(mapID)))
        return 0
    end

    -- Team size counters
    local teamSize = { [0] = 0, [1] = 0 }

    local added = 0
    for i = 1, numScores do
        local info = C_PvP.GetScoreInfo(i)
        if info and info.guid then
            if info.faction == 0 or info.faction == 1 then
                teamSize[info.faction] = teamSize[info.faction] + 1
            end

            -- Keep raw map-specific stats as a flat array of values. safeNum
            -- on both the stored value and the sum: a secret pvpStatValue
            -- would taint the arithmetic here (killing the whole capture) and
            -- would be dropped by the SavedVariables serializer anyway.
            local rawStats, objectivePoints = {}, 0
            if info.stats then
                for _, s in ipairs(info.stats) do
                    local v = safeNum(s.pvpStatValue)
                    table.insert(rawStats, { id = s.pvpStatID, v = v, name = s.name })
                    objectivePoints = objectivePoints + v
                end
            end

            local won
            if winner ~= nil then
                won = (info.faction == winner)
            end

            local sample = {
                mapID      = mapID,
                mapName    = mapName,
                duration   = duration,
                bracket    = ctx.isBlitz and "BLITZ"
                          or ctx.isRated and "RATED"
                          or ctx.isEpic  and "EPIC"
                          or "BG",
                matchType  = ctx.matchType,
                endedAt    = endedAt,

                -- safeNum, not `or 0`: a SECRET number is truthy, so `or 0`
                -- lets it through, and the SavedVariables serializer then
                -- drops it — the row reaches the server with the field
                -- missing and defaults to 0 anyway. Being explicit keeps the
                -- capture honest (and untainted); statsSecret below records
                -- how much of the scoreboard we could not actually read.
                dmg        = safeNum(info.damageDone),
                heal       = safeNum(info.healingDone),
                kb         = safeNum(info.killingBlows),
                hk         = safeNum(info.honorableKills),
                deaths     = safeNum(info.deaths),
                honor      = safeNum(info.honorGained),
                rating     = safeNum(info.rating),
                ratingChange = safeNum(info.ratingChange),
                role       = info.role,
                spec       = info.talentSpec,
                objective  = objectivePoints,     -- quick aggregate
                rawStats   = rawStats,            -- full breakdown for future analysis
                faction    = info.faction,
                race       = info.raceName,       -- localized; server has en_US + ru_RU lookup
                premade    = ctx.premadeGUIDs and ctx.premadeGUIDs[info.guid] or false,
                won        = won,
            }

            -- Same-realm players come from C_PvP.GetScoreInfo with a bare
            -- ``name`` (no "-Realm" suffix); only cross-realm players get
            -- the full "Name-Realm" form. The server-side enricher needs
            -- the realm to resolve a Blizzard slug, so we append the local
            -- realm ourselves when WoW elides it. Spaces are stripped to
            -- match the cross-realm convention WoW already uses.
            local fullName = info.name or ""
            if fullName ~= "" and not fullName:find("-", 1, true) then
                local realm = GetRealmName()
                if realm and realm ~= "" then
                    fullName = fullName .. "-" .. realm:gsub(" ", "")
                end
            end

            local meta = {
                name     = fullName,
                class    = info.classToken,
                faction  = info.faction,
                lastSeen = endedAt,
            }

            -- Attach this match's guid to the baseline row of the same name.
            -- Guids are readable again at match end, and resolving them HERE
            -- keeps it match-local: no historical name→guid lookup that could
            -- collide across renames, connected realms or reused names.
            -- Players who left before the end simply keep a nil guid.
            if ctx.baselineByName and fullName ~= "" then
                local row = ctx.baselineByName[fullName]
                if row then row.g = info.guid end
            end

            ns.Database:AddSample(info.guid, meta, sample)
            added = added + 1
        end
    end

    -- startRoster (captured by Deserter:OnMatchActive at +6s after
    -- PVP_MATCH_ACTIVE) ships alongside the match so the server can
    -- diff it against the final scoreboard and infer who left.
    local startRoster = ns.Deserter and ns.Deserter:GetRoster() or nil

    -- Raid leader on our side at the moment of snapshot. Captured at
    -- the same instant as the scoreboard so the GUID corresponds to
    -- whoever actually held the lead role going into the final scoring
    -- (a mid-match promotion / DC won't confuse the result).
    local leaderGUID = findRaidLeaderGUID()

    -- Stop the mid-snapshot ticker (match is over). Take one final mid
    -- snapshot synchronously here so a player who left in the last
    -- 5-minute window still has at least one numeric line — without this
    -- the gap between last tick and end can swallow up to 5 minutes of
    -- evidence for late-leavers. Note: this is the *snapshot timeline*
    -- entry, separate from the final scoreboard rows being added above.
    if ctx.snapshotTicker then
        ctx.snapshotTicker:Cancel()
        ctx.snapshotTicker = nil
    end
    local snapshots = ctx.snapshots or {}

    -- Freeze crown tracking: one last ally sweep at the same instant as the
    -- scoreboard (leadership can change mid-match), stop the poll ticker,
    -- and flatten the guid-keyed set into an array for the payload.
    sweepAllyCrowns()
    if ctx.crownTicker then
        ctx.crownTicker:Cancel()
        ctx.crownTicker = nil
    end
    local allyCrowns
    if ctx.allyCrowns and next(ctx.allyCrowns) then
        allyCrowns = {}
        for guid, name in pairs(ctx.allyCrowns) do
            allyCrowns[#allyCrowns + 1] = { guid = guid, name = name }
        end
    end

    ns.Database:IncrementMatch({
        mapID       = mapID,
        mapName     = mapName,
        bracket     = ctx.isBlitz and "BLITZ" or ctx.isRated and "RATED" or ctx.isEpic and "EPIC" or "BG",
        duration    = duration,
        -- When WE entered this match (addon ≥ 0.9.33), not when the battle
        -- started. The two differ on a late join: C_PvP.GetActiveMatchDuration
        -- measures the BATTLE, so `endedAt - duration` can reach back before we
        -- were even here — and the server's "one reporter can't be in two
        -- matches at once" check then quarantines a perfectly real back-to-back
        -- match. nil after a /reload mid-game (ctx is wiped and OnMatchActive
        -- won't fire again): the server falls back to duration, as before.
        startedAt   = ctx.startedAt,
        winner      = winner,
        teamSize    = teamSize,
        endedAt     = endedAt,
        startRoster = startRoster,
        leaderGUID  = leaderGUID,
        snapshots   = snapshots,
        -- Crown signals (addon ≥ 0.9.25): count-only for enemies (identity
        -- is secret), guid+name for our own side. nil/0 when not captured.
        enemyCrownMax = ctx.enemyCrownMax,
        allyCrowns    = allyCrowns,
        -- Capture quality (addon ≥ 0.9.32): rows whose combat numbers were
        -- still SECRET when we captured. > 0 ⇒ the server does not judge
        -- anyone by this scoreboard. nil for a manual /piq snapshot.
        statsSecret   = statsSecret,
        -- Who was on the board before substitutions started (addon ≥ 0.9.33),
        -- names only — the one thing that stays readable mid-match. nil when
        -- the scoreboard never demonstrably finished loading (short match,
        -- /reload mid-game, late join): absent evidence beats invented.
        baseline      = ctx.baseline,
    })

    if ns.Deserter then ns.Deserter:Reset() end

    -- Drop the parked record only when this really was the end of the match.
    -- `/piq snapshot` (Main.lua) runs the exact same path mid-battle, and
    -- clearing here unconditionally would throw away the one thing that lets
    -- the REAL snapshot recover its startedAt after a /reload.
    if not (C_PvP.IsMatchComplete and C_PvP.IsMatchComplete()) then
        -- Manual mid-match snapshot: ctx is about to be wiped below, so
        -- re-park what a later restore will need.
        persistActiveMatch()
    else
        clearActiveMatch()
    end

    -- Clear context for next match
    ctx = {}
    return added
end


-- Abandon the current match WITHOUT uploading: cancel the per-match tickers and
-- clear context. Called from the PLAYER_ENTERING_WORLD leave-reset (Main.lua)
-- for an ABNORMAL exit (kick / disconnect / leave with no PVP_MATCH_COMPLETE) —
-- otherwise the crown ticker keeps polling nameplates out in the open world with
-- a stale ``ctx.isEBG == true`` and fires spurious "enemy group leaders" alerts.
-- SnapshotMatch (the clean end) already does this teardown inline; this is the
-- path for when SnapshotMatch never runs.
function Collector:Reset()
    if ctx.snapshotTicker then
        ctx.snapshotTicker:Cancel()
        ctx.snapshotTicker = nil
    end
    if ctx.crownTicker then
        ctx.crownTicker:Cancel()
        ctx.crownTicker = nil
    end
    ctx = {}
end
