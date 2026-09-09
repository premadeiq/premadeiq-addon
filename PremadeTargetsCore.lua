local ADDON, ns = ...

local Core = {}
ns.PremadeTargetsCore = Core

local function validName(name)
    return type(name) == "string" and name ~= "" and not name:find("[\r\n]")
end

function Core.NormalizeName(name, realm)
    if not validName(name) then return nil end
    if name:find("-", 1, true) then return name end
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

-- ── Personal watchlist ───────────────────────────────────────────────────
-- Players the OWNER of this client chose to keep an eye on. Purely local: it
-- lives in its own SavedVariable, never reaches the server, and never touches
-- the premade verdict, the counters or the catalog. Modelled on PremadeAlert's
-- ``lookupRaidLead`` — a separate, independent table rather than something
-- mixed into the catalog index, because the catalog index is CACHED on the
-- catalog's generated_at (PremadeTargets:RebuildCatalog) and would not notice an
-- edit to this list at all — never, for a client running the neutral stub
-- catalog whose generated_at is 0.
Core.WATCH_MAX = 200

-- Turn whatever the player pasted into the key the scoreboard will produce.
--
-- Deliberately NOT Core.NormalizeName: that one takes a scoreboard string, which
-- is already clean. Pasted text is not. Measured failure modes, all silent:
--   "Bob "                -> key "Bob -Realm", macro "/targetexact Bob -Realm"
--   "bob"                 -> key "bob-Realm", never equal to the board's "Bob-…"
--   "Bob-Twisting Nether" -> kept verbatim, board says "Bob-TwistingNether"
--   "|Hplayer:Bob|h[Bob]|h" (a chat link) -> escapes into the macro and the UI
--
-- Returns (key, nil) or (nil, reason).
function Core.NormalizeWatchInput(raw, realm)
    if type(raw) ~= "string" then return nil, "empty" end
    local s = raw:gsub("[\r\n\t]", " ")
    -- Chat hyperlink: |Hplayer:Name-Realm:…|h[Name]|h — take the payload, which
    -- carries the realm; the bracketed display half usually does not.
    local linked = s:match("|Hplayer:([^:|]+)")
    if linked then s = linked end
    s = s:gsub("|%a", ""):gsub("|", "")   -- strip any remaining escape sequences
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^%[", ""):gsub("%]$", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil, "empty" end

    local name, rlm = s:match("^(.-)%-(.*)$")
    if name then
        name = name:gsub("%s+$", "")
        -- WoW writes cross-realm names with the realm's spaces removed, and the
        -- collector mirrors that (Collector.lua). Match it or nothing lines up.
        rlm = rlm:gsub("%s", "")
    else
        name, rlm = s, (type(realm) == "string" and realm:gsub("%s", "")) or ""
    end
    if name == "" or name:find("%s") or rlm == "" then return nil, "malformed" end

    -- Capitalise the first letter ONLY when it is ASCII. strupper in WoW's Lua
    -- is byte-wise, so it mangles UTF-8: a Cyrillic name must be pasted in its
    -- exact spelling, and the tooltip says so.
    local first = name:sub(1, 1)
    if first:match("%a") then name = first:upper() .. name:sub(2) end
    return name .. "-" .. rlm, nil
end

-- ``{ [key] = true }`` for the roster filter. Defensive about the shape: the
-- SavedVariable may be absent (first run) or hand-edited.
function Core.WatchIndex(watch, realm)
    local index = {}
    local players = type(watch) == "table" and watch.players or nil
    if type(players) ~= "table" then return index end
    for key, rec in pairs(players) do
        local name = (type(rec) == "table" and rec.name) or key
        local k = Core.NormalizeName(name, realm)
        if k then index[k] = true end
    end
    return index
end

-- Mutation lives here, not in the options UI, so it is testable: the Lua test
-- harness loads this file alone, with no WoW API at all.
-- Returns (true, key) or (false, reason) where reason is
-- "empty" | "malformed" | "duplicate" | "full".
function Core.AddWatch(watch, raw, realm)
    if type(watch) ~= "table" then return false, "empty" end
    watch.players = type(watch.players) == "table" and watch.players or {}
    local key, reason = Core.NormalizeWatchInput(raw, realm)
    if not key then return false, reason end
    if watch.players[key] then return false, "duplicate" end
    local n = 0
    for _ in pairs(watch.players) do n = n + 1 end
    if n >= Core.WATCH_MAX then return false, "full" end
    watch.players[key] = { name = key }
    return true, key
end

function Core.RemoveWatch(watch, key)
    local players = type(watch) == "table" and watch.players or nil
    if type(players) ~= "table" or key == nil or players[key] == nil then
        return false
    end
    players[key] = nil
    return true
end

function Core.WatchCount(watch)
    local players = type(watch) == "table" and watch.players or nil
    if type(players) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(players) do n = n + 1 end
    return n
end

-- Sorted keys, so the options list does not reshuffle between openings.
function Core.WatchList(watch)
    local players = type(watch) == "table" and watch.players or nil
    local out = {}
    if type(players) ~= "table" then return out end
    for key in pairs(players) do out[#out + 1] = key end
    table.sort(out)
    return out
end

local function addGroup(entry, groupId, label)
    if groupId == nil or not validName(label) or entry._groupSet[groupId] then return end
    entry._groupSet[groupId] = true
    entry.groups[#entry.groups + 1] = label
end

-- The "likely" tier (catalog rev 7): real shared history that has not reached
-- the server's confirmation bar. Kept in its OWN list on purpose — the UI reads
-- `#groups > 0` as "this is a premade member", and a maybe must never answer
-- that question yes.
local function addLikelyGroup(entry, groupId, label)
    if groupId == nil or not validName(label) or entry._likelySet[groupId] then return end
    entry._likelySet[groupId] = true
    entry.likelyGroups[#entry.likelyGroups + 1] = label
end

function Core.BuildCatalogIndex(catalog, realm)
    local index = {}
    -- Only the catalog itself is required. `leaders` used to be mandatory here,
    -- which would have thrown the whole index away for an owner who has marked
    -- only solo raid leaders and no premades yet — the two arrays are separate.
    if type(catalog) ~= "table" then
        return index
    end

    local function getEntry(name)
        local key = Core.NormalizeName(name, realm)
        if not key then return nil end
        local entry = index[key]
        if not entry then
            entry = {
                catalogName = name,
                isLeader = false,
                isLikely = false,
                groups = {},
                likelyGroups = {},
                _groupSet = {},
                _likelySet = {},
            }
            index[key] = entry
        end
        return entry
    end

    local groupNames = {}
    if type(catalog.leaders) == "table" then
    for _, leader in ipairs(catalog.leaders) do
        if type(leader) == "table" then
            local groupId = leader.leader_id or leader.guid or leader.name
            if groupId ~= nil and validName(leader.name) then
                if leader.guid == groupId or not groupNames[groupId] then
                    groupNames[groupId] = leader.name
                end
            end
        end
    end

    local function addMembers(members, groupId, groupLabel, likely)
        if type(members) ~= "table" then return end
        for _, member in ipairs(members) do
            if type(member) == "table" then
                local entry = getEntry(member.name)
                if entry then
                    if likely then
                        -- A confirmed pair is never also likely (the server
                        -- resolves that), but an alt seen under two leaders can
                        -- be: confirmed wins and the maybe stays silent.
                        if #entry.groups == 0 then entry.isLikely = true end
                        addLikelyGroup(entry, groupId, groupLabel)
                    else
                        entry.isLikely = false
                        addGroup(entry, groupId, groupLabel)
                    end
                end
            end
        end
    end

    for _, leader in ipairs(catalog.leaders) do
        if type(leader) == "table" then
            local groupId = leader.leader_id or leader.guid or leader.name
            local groupLabel = groupNames[groupId] or leader.name
            local entry = getEntry(leader.name)
            if entry then
                entry.isLeader = true
                addGroup(entry, groupId, groupLabel)
            end
            addMembers(leader.confirmed_members, groupId, groupLabel)
            addMembers(leader.likely_members, groupId, groupLabel, true)
        end
    end
    end

    -- Solo raid leaders ride in their OWN array. The server split them out so an
    -- already-installed addon could not read one as a premade leader and
    -- announce a premade (catalog rev 5) — so here they must never pick up
    -- `isLeader`, and never a group.
    --
    -- They are NOT mutually exclusive with premade membership: the server only
    -- bars kind="raid_lead" from being a roster's LEADER, so the same person is
    -- freely a confirmed member of somebody else's premade. Measured on live
    -- data, 21 of 47 raid-lead characters are. getEntry hands back that very
    -- same entry, which is exactly why it must be the only way an entry is ever
    -- created: a hand-rolled table without `groups`/`_groupSet` would blow up
    -- addGroup and the sort below — and that error escapes the pcall in
    -- RefreshFromScoreboard and wedges every later scan.
    if type(catalog.raid_leads) == "table" then
        for _, rl in ipairs(catalog.raid_leads) do
            if type(rl) == "table" then
                local entry = getEntry(rl.name)
                if entry then entry.isRaidLead = true end
            end
        end
    end

    for _, entry in pairs(index) do
        table.sort(entry.groups)
        entry._groupSet = nil
    end
    return index
end

-- Both teams, tagged with which side of the scoreboard they sit on.
--
-- `mySide` is the viewer's own team in the scoreboard's 0=Horde/1=Alliance
-- space (GetBattlefieldArenaFaction — see PremadeTargets.lua). A row whose
-- `faction` is missing is dropped rather than guessed: PremadeAlert can afford
-- the permissive "unreadable → treat as enemy" fallback because over-warning is
-- harmless there, but here the same guess would file a teammate under the enemy
-- heading, which is worse than not listing them at all.
--
-- `myCanonicalName`, when known, drops the viewer's own row: a button that
-- targets yourself is useless, and owners do appear in the catalog.
--
-- `watchIndex` is the owner's PERSONAL list (Core.WatchIndex): a second,
-- independent reason for a row to appear, carrying no claim about premades.
function Core.FilterRoster(rows, catalogIndex, mySide, realm, myCanonicalName,
                           watchIndex)
    local players, seen = {}, {}
    if type(rows) ~= "table" or type(catalogIndex) ~= "table" then return players end
    if mySide == nil then return players end

    for _, row in ipairs(rows) do
        if type(row) == "table" and validName(row.name) then
            local key = Core.NormalizeName(row.name, realm)
            local catalogEntry = key and catalogIndex[key]
            -- The personal list is a SECOND, independent reason to list someone.
            -- It never merges into the catalog entry: a watched player we know
            -- nothing else about must not inherit "premade member" from anyone.
            local watched = (key ~= nil and type(watchIndex) == "table"
                             and watchIndex[key]) and true or false
            local sideKnown = row.faction ~= nil
            if (catalogEntry or watched) and sideKnown and key
                    and not seen[key] and key ~= myCanonicalName then
                seen[key] = true
                players[#players + 1] = {
                    name = row.name,
                    canonicalName = key,
                    classToken = row.classToken,
                    faction = row.faction,
                    side = (row.faction == mySide) and "ally" or "enemy",
                    isLeader = (catalogEntry and catalogEntry.isLeader) and true or false,
                    groups = catalogEntry and catalogEntry.groups or nil,
                    -- One tier below a confirmed member: shared history that
                    -- has not cleared the bar. Separate field AND separate
                    -- group list, so no existing "is this a premade member"
                    -- check answers yes for a maybe.
                    isLikely = (catalogEntry and catalogEntry.isLikely) and true or false,
                    likelyGroups = catalogEntry and catalogEntry.likelyGroups or nil,
                    isWatched = watched,
                    -- Marked "takes raid lead, runs no premade". Independent of
                    -- the premade fields above and never a substitute for them:
                    -- the same person is often both.
                    isRaidLead = (catalogEntry and catalogEntry.isRaidLead) and true or false,
                    -- Known to the catalog at all? Drives the row's label: a
                    -- watch-only row must not be captioned "premade member".
                    inCatalog = catalogEntry and true or false,
                }
            end
        end
    end

    -- Enemies first (the side you act on), then your own team; leaders head each
    -- section, the rest stay alphabetical so the grid does not reshuffle between
    -- scans.
    table.sort(players, function(a, b)
        if a.side ~= b.side then return a.side == "enemy" end
        if a.isLeader ~= b.isLeader then return a.isLeader end
        return a.canonicalName < b.canonicalName
    end)
    return players
end

function Core.TargetMacro(targetName)
    if not validName(targetName) then return nil end
    return "/cleartarget\n/targetexact " .. targetName
end

-- Right-click: set focus without losing the current target. /targetlasttarget
-- restores whatever we had selected before the macro ran.
function Core.FocusMacro(targetName)
    if not validName(targetName) then return nil end
    return "/targetexact " .. targetName .. "\n/focus\n/targetlasttarget"
end

function Core.ComputeLayout(count, maxColumns)
    count = math.max(0, math.floor(tonumber(count) or 0))
    maxColumns = math.max(1, math.floor(tonumber(maxColumns) or 1))
    if count == 0 then return {}, 0, 0 end

    local columns = math.min(count, maxColumns)
    local rows = math.ceil(count / columns)
    local layout = {}
    for i = 1, count do
        layout[i] = {
            column = ((i - 1) % columns) + 1,
            row = math.floor((i - 1) / columns) + 1,
        }
    end
    return layout, columns, rows
end

-- Side is part of the signature: the same player moving between the enemy and
-- ally sections has to count as a changed secure state, otherwise the deferred
-- combat update would decide nothing happened and leave them under the wrong
-- heading.
function Core.PlayerSignature(players)
    local parts = {}
    for i, player in ipairs(players or {}) do
        -- isWatched belongs here for the same reason `side` does: toggling it
        -- changes what the row renders, and a signature that misses the change
        -- sends ApplyPlayers down the "nothing to do" branch — which actively
        -- discards the update it had queued for after combat.
        parts[i] = tostring(player.name or "") .. "\30" .. tostring(player.side or "")
                   .. "\30" .. (player.isWatched and "w" or "")
                   .. "\30" .. (player.isRaidLead and "r" or "")
                   .. "\30" .. (player.isLikely and "l" or "")
    end
    return table.concat(parts, "\31")
end

function Core.ShouldDeferSecureUpdate(inCombat, currentSignature, players)
    return inCombat and currentSignature ~= Core.PlayerSignature(players)
end

-- ── When to recompute the odds, and when to stop ─────────────────────────
-- The forecast is fitted on STARTING rosters, so it has to be computed while
-- the scoreboard is still filling and then left alone. Recomputing all match
-- turns a forecast into a description: the losing side empties out first, so
-- the number would creep toward an outcome already visible on the objectives
-- and look prescient for it.
--
-- Pure so it can be tested — the UI file it is called from needs the whole WoW
-- frame API to load.
--
--   peak, stable   what the caller remembers between scans
--   seen           how full the board is NOW; the CALLER decides what to
--                  measure — see UpdateForecast, which passes the smaller of
--                  the two sides rather than the row count, because one half
--                  filling while the other empties leaves a total unmoved
--   haveForecast   whether a number already exists
--
-- Returns: recompute, lockIfForecast, peak, stable.
--
-- `lockIfForecast` rather than `lock` on purpose: whether there is anything to
-- freeze is only known AFTER the recompute, and freezing an empty forecast
-- would end the match with no number at all.
Core.FORECAST_STABLE_SCANS = 8

function Core.ForecastScanGate(peak, stable, seen, haveForecast)
    peak, stable = peak or 0, stable or 0

    if seen > peak then
        -- Still filling: nothing is settled, so keep recomputing.
        return true, false, seen, 0
    end

    if seen < peak then
        -- The board is SHRINKING — people are leaving and the starting roster
        -- is already gone. Freeze what we have; recompute only if we have
        -- nothing, because a late number beats no number and there will be no
        -- fuller board to wait for.
        return not haveForecast, true, peak, stable
    end

    -- Unchanged: it may simply have stopped filling. Count the quiet scans and
    -- freeze once there have been enough of them.
    stable = stable + 1
    return true, stable >= Core.FORECAST_STABLE_SCANS, peak, stable
end
