local ADDON, ns = ...

-- Deserter detection — start vs end roster comparison.
--
-- Whole detector is built around one observation: the WoW client gives
-- us the full BG scoreboard at PVP_MATCH_COMPLETE. If we *also* capture a
-- start roster shortly after PVP_MATCH_ACTIVE, the diff is the set of
-- players who entered but didn't finish — i.e. deserters.
--
-- Start-roster source (12.0.x): OWN TEAM via raid/party unit tokens, whose
-- GUIDs are plain. The live scoreboard can't be used for this — its GUIDs go
-- secret seconds into a busy Epic and the SavedVariables serializer drops the
-- secret strings, so a scoreboard-built roster ships GUID-less and the server
-- diff matches nothing (prod confirmed: 0 deserters from the scoreboard-diff
-- path). The scoreboard is still read opportunistically for bonus names while
-- its GUIDs are momentarily plain. See collectOwnTeam().
--
-- Final classification ("really a deserter vs just disconnected") is
-- the server's job: it cross-references match.winner against the
-- missing player's faction and only flags rows whose faction lost.
-- That's the entire heuristic — no chat parsing, no polling, no aura
-- watch. Behavior emerges from pattern: someone who serial-deserts
-- shows up in many other reporters' diffs over time.
--
-- One catch: the scoreboard isn't fully populated *immediately* after
-- PVP_MATCH_ACTIVE — some opponents take a few seconds to be cached
-- client-side. We force a refresh and capture at +6s, which is empirically
-- enough on retail 12.x for the roster to be complete.
--
-- Late-join guard: if PVP_MATCH_ACTIVE fires for us but the match has
-- already been running for more than 60 seconds (queue popped us into
-- an in-progress battle), our startRoster would be missing the actual
-- starters and we'd false-positive every player who left before we
-- joined. In that case we tag startRoster with lateJoin=true so the
-- server skips deserter computation for this report.

local Deserter = {}
ns.Deserter = Deserter

-- Multi-shot capture: 4s, 8s, 14s. Earlier attempts catch most matches
-- (scoreboard usually populates within 3-5s). Later attempts cover
-- network-laggy clients and lazy server fills. We always keep the
-- LARGEST capture seen so any attempt that finds <previous_max is
-- discarded. Empirical (over 6 captured matches in pre-deploy SV):
-- single +6s shot caught 1/6 with content; multi-shot brings it to ≥5/6.
local CAPTURE_DELAYS_SEC      = { 4, 8, 14 }
local LATE_JOIN_THRESHOLD_SEC = 60

local pendingTimers = {}             -- list of NewTimer handles to cancel on Reset
local startRoster   = nil            -- { lateJoin, takenAt, players, attempts, lastN }


-- Player's own faction the way the scoreboard encodes it: 0=Horde, 1=Alliance.
local function myFaction()
    local g = UnitFactionGroup("player")
    if g == "Alliance" then return 1 end
    if g == "Horde" then return 0 end
    return nil
end

-- Own team's starting roster via raid/party unit tokens. This is the reliable
-- source in retail 12.0.x: scoreboard GUIDs turn into "secret values" within
-- seconds of PVP_MATCH_ACTIVE on a busy Epic, and the SavedVariables serializer
-- then DROPS those secret strings outright — so a scoreboard-built startRoster
-- arrives at the server with no GUIDs and the diff finds nothing (prod: the
-- scoreboard-diff source produced 0 deserters across 909 matches). Raid unit
-- GUIDs are plain and survive serialization. Covers exactly the case that
-- matters: an own-side starter who left and is gone from the final scoreboard
-- (the server flags missing losing-side starters as deserters).
local function collectOwnTeam(byGuid)
    local n = GetNumGroupMembers() or 0
    if n == 0 then return end
    local mine = myFaction()
    local prefix = IsInRaid() and "raid" or "party"
    local function add(unit)
        local guid = UnitGUID(unit)
        if type(guid) == "string" and guid ~= "" and not byGuid[guid] then
            local name, realm = UnitName(unit)
            if name and realm and realm ~= "" then name = name .. "-" .. realm end
            byGuid[guid] = { guid = guid, name = name, faction = mine }
        end
    end
    for i = 1, n do add(prefix .. i) end
    add("player")   -- party prefix omits self; harmless dup-guard under raid
end

local function tryCapture(attempt)
    if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        return
    end
    pcall(function()
        -- Each attempt re-pumps the scoreboard request — the first one
        -- on +0s rarely returns full data, but +4/+8/+14 give the server
        -- enough wall-clock time to populate the cache between calls.
        if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
        local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
        if startRoster then
            startRoster.attempts = (startRoster.attempts or 0) + 1
            startRoster.lastN    = n
        end
        local byGuid = {}
        -- Scoreboard rows = bonus coverage (enemy side, cross-realm names) while
        -- guids are still plain; often empty seconds in, which is exactly why
        -- the own-team raid capture below is the primary source. Tainted-
        -- execution guard: another addon may have pumped the score table through
        -- SortBattlefieldScoreData() and tainted the rows — type-check filters those.
        for i = 1, n do
            local info = C_PvP and C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i) or nil
            local guid = info and info.guid
            if type(guid) == "string" and guid ~= "" and not byGuid[guid] then
                byGuid[guid] = {
                    guid    = guid,
                    name    = (type(info.name) == "string" and info.name) or nil,
                    faction = info.faction,
                }
            end
        end
        -- Own team via raid tokens — plain GUIDs, the dependable source.
        collectOwnTeam(byGuid)

        local players = {}
        for _, p in pairs(byGuid) do players[#players + 1] = p end
        if #players == 0 then return end
        if startRoster and #players <= #startRoster.players then return end
        startRoster = {
            takenAt  = startRoster and startRoster.takenAt or time(),
            lateJoin = startRoster and startRoster.lateJoin or false,
            players  = players,
            attempts = startRoster and startRoster.attempts or 1,
            lastN    = n,
        }
    end)
end

function Deserter:OnMatchActive()
    -- Detect late-join: if the active match has already been running
    -- for a while, our startRoster won't reflect the real starting set.
    local age = (C_PvP and C_PvP.GetActiveMatchDuration
                  and C_PvP.GetActiveMatchDuration()) or 0
    local lateJoin = (age > LATE_JOIN_THRESHOLD_SEC)

    startRoster = {
        takenAt  = time(),
        lateJoin = lateJoin,
        players  = {},
        attempts = 0,
        lastN    = 0,
    }

    -- Cancel any leftover timers from a prior /reload or rejoin.
    for _, t in ipairs(pendingTimers) do pcall(function() t:Cancel() end) end
    pendingTimers = {}

    -- Schedule the multi-shot capture train. Each timer also calls
    -- RequestBattlefieldScoreData itself, so we get N independent
    -- chances for the server to fill the cache.
    for _, delay in ipairs(CAPTURE_DELAYS_SEC) do
        local d = delay
        local t = C_Timer.NewTimer(d, function() tryCapture(d) end)
        table.insert(pendingTimers, t)
    end
end

-- UPDATE_BATTLEFIELD_SCORE event hook: the WoW client pushes us this
-- event whenever the score cache changes (either by our request or the
-- internal UI ticker). Use it as a free re-capture trigger during the
-- first ~30 sec of the match — costs nothing if startRoster is already
-- saturated, helps a lot when our +4/+8/+14 timers all happened during
-- an empty cache window.
function Deserter:OnBattlefieldScoreUpdate()
    if not startRoster then return end
    -- Our own raid/party is the reliable source (collectOwnTeam fills it on the
    -- first capture); scoreboard enemy rows are an optional bonus, not worth a
    -- 30s event-driven recapture train. Stop as soon as we hold our whole group.
    -- (The old fixed quorum of 60 was unreachable once raid tokens — ≤40 in an
    -- Epic — became the primary source, so this used to run the full window.)
    local groupN = GetNumGroupMembers() or 0
    if groupN > 0 and #startRoster.players >= groupN then return end
    -- Only run while still in the early phase (don't keep picking up
    -- late joiners well into the match).
    if (time() - (startRoster.takenAt or 0)) > 30 then return end
    tryCapture(0)
end

function Deserter:OnMatchComplete()
    -- No-op: end-of-match scoreboard is already captured by Collector,
    -- and the server diffs that against startRoster shipped in the
    -- match payload.
end

function Deserter:GetRoster()
    return startRoster
end

function Deserter:Reset()
    for _, t in ipairs(pendingTimers) do pcall(function() t:Cancel() end) end
    pendingTimers = {}
    startRoster   = nil
end
