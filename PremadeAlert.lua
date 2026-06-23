local ADDON, ns = ...
local L = ns.L

-- In-game premade alert.
--
-- On entering a battleground we cross-reference the enemy roster against
-- the known-premade catalog the Uploader wrote into KnownPremades.lua
-- (PremadeIQ_KnownPremades). If known premade leaders (and, for PATRON
-- tier, their members) are on the opposing side, we announce it.
--
-- Why this works inside Midnight's restrictions: C_PvP.GetScoreInfo's
-- `name`, `faction`, `className` and `raceName` fields are flagged
-- NeverSecret = true in the API (Blizzard_APIDocumentationGenerated/
-- PvpInfoDocumentation.lua → PVPScoreInfo), so they stay plain even deep
-- into an active match. `guid`, by contrast, reads as a secret value
-- within seconds of PVP_MATCH_ACTIVE on a busy Epic. So we match the
-- enemy roster by normalised Name-Realm (preferring guid only while it's
-- still plain), gate the enemy side on `faction`, and guard every read
-- with issecretvalue() as insurance. The earlier guid-only matching
-- silently missed every premade because the guids were already secret in
-- the opening window (alertLog showed str=0 sec=77 hit=0).
--
-- Tier is implicit in the data shape: a leader entry with a ``members``
-- table came from a PATRON payload; without it, the catalog only carried
-- leaders (CONTRIBUTOR). The addon renders whatever it was given — all
-- gating already happened server-side.

local PremadeAlert = {}
ns.PremadeAlert = PremadeAlert

-- Scoreboard isn't fully cached the instant PVP_MATCH_ACTIVE fires; scan
-- repeatedly through the opening minutes. Mirrors Deserter's capture train.
--
-- The ENEMY team isn't shown until a few seconds AFTER the gates open, and on
-- an 80-player Epic the roster populates progressively — alertLog showed even
-- our own half crawling 16→35 over ~50s. So the enemy half (the side we scan
-- for) can appear well past the first minute. We run a long timer train AND
-- re-scan on every UPDATE_BATTLEFIELD_SCORE through the window. The announce
-- is one-shot (the `fired` guard), so the moment the enemy roster lands and a
-- premade matches, we fire and stop — the later ticks cost nothing on a hit.
-- (Matching is by name now, so a row going guid-secret no longer costs a hit.)
local SCAN_DELAYS_SEC = { 4, 8, 14, 22, 32, 45, 60, 80, 105, 135, 170 }

-- How long after PVP_MATCH_ACTIVE we keep honouring UPDATE_BATTLEFIELD_SCORE
-- re-scans. Generous, because the enemy roster can land a minute-plus into the
-- match (see SCAN_DELAYS_SEC). The one-shot `fired` guard stops re-scans as
-- soon as we announce, so a long window only matters when there's no premade.
local SCAN_WINDOW_SEC = 180

-- Minimum gap between scans. UPDATE_BATTLEFIELD_SCORE fires many times a second
-- on an 80-player Epic; without this we'd scan the whole scoreboard AND issue a
-- SetBattlefieldScoreFaction (itself a synchronous score-update the entire UI
-- reprocesses) on every one — a per-frame storm that visibly lags the client.
-- One scan per this interval is plenty to catch a roster that loads over seconds.
local SCAN_THROTTLE_SEC = 1.5

-- A known leader on the enemy side = a POSSIBLE premade; a leader with this many
-- of their known regulars also present = a CONFIRMED premade (an organised
-- group, not a lone queue). "More than 5 of their players" → 6+.
--
-- LEADERLESS path: even with NO marked leader present, this many of one premade's
-- CONFIRMED regulars (server-attributed single-winner, faction-readable enemy
-- only) on the enemy side also fires — catches a premade whose leader sat out or
-- queued on an unmarked alt. Same threshold; treated as CONFIRMED (red).
local CONFIRM_MIN_MEMBERS = 6

-- guid → entry { isLeader, leaderName, leaderId, name, memberOf, confirmedOf }
-- and normalised-name → same entry. memberOf/confirmedOf are sets of leader_ids
-- (ALERT- and CONFIRMED-tier membership). Rebuilt when the catalog's
-- generated_at changes (the Uploader wrote a fresh file). The name map is the
-- primary matcher now that guids go secret in-match; the guid map is a precise
-- shortcut while it lasts. leaderNameById maps a leader_id → display name (for
-- the leaderless headline, where the leader isn't present to read a name off).
local lookup = nil
local lookupName = nil
local lookupGen = nil
local leaderNameById = nil

local fired = false           -- one auto-announce per match
local matchStart = 0          -- time() of the last PVP_MATCH_ACTIVE
local lastLog = nil           -- dedup consecutive identical scan log lines
local lastScanAt = 0          -- GetTime() of the last scan (throttle)
local scanning = false        -- re-entrancy guard: SetBattlefieldScoreFaction
                              -- fires UPDATE_BATTLEFIELD_SCORE *synchronously*,
                              -- which re-enters detect() → C stack overflow
PremadeAlert._timers = {}

local function prnt(msg)
    print("|cff33ff99PremadeIQ|r " .. msg)
end

-- Diagnostic ring buffer persisted in PremadeIQ_DB.alertLog (a registered
-- SavedVariable, flushed to disk on /reload or logout). Lets us reconstruct
-- exactly what detect() saw after the fact — catalog state, scoreboard rows,
-- secret-vs-plain guids, catalog hits, enemy matches — without depending on
-- the player reading chat live. When /piq debug is on it also echoes to chat.
local function dbg(line)
    local db = ns.Database and ns.Database.db
    if not db then return end
    db.alertLog = db.alertLog or {}
    db.alertLog[#db.alertLog + 1] = date("%H:%M:%S") .. " " .. line
    while #db.alertLog > 100 do table.remove(db.alertLog, 1) end
    if ns.Database.GetSetting and ns.Database:GetSetting("debug") then
        prnt("|cff888888" .. line .. "|r")
    end
end

local function secret(v)
    return issecretvalue and issecretvalue(v)
end

-- Canonical match key for a player name. The catalog stores "Name-Realm"
-- (the same shape the scoreboard returns for cross-realm players); rows on
-- the viewer's own realm come back as a bare "Name", so we append our own
-- realm to make the two comparable. Case is left as-is — both sides are
-- Blizzard-canonical, and Lua's string.lower wouldn't fold the accented
-- characters common in these names anyway.
local function normName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then
        return name
    end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name  -- no realm available; bare name as a last resort
end

-- Build guid→entry and name→entry from PremadeIQ_KnownPremades. One entry per
-- player, reachable by both guid and name. memberOf / confirmedOf are sets of
-- leader_ids: a player can belong to several premades, and can also be a leader
-- themselves — every flag accumulates onto the same entry so the live counter
-- attributes each present player to each premade they belong to. confirmedOf
-- (PATRON-only confirmed_members) drives the leaderless path; absent below
-- PATRON or on a pre-0.8.2 catalog, which simply disables leaderless detection.
local function ensureLookup()
    local cat = PremadeIQ_KnownPremades
    if type(cat) ~= "table" or type(cat.leaders) ~= "table" then
        lookup, lookupName, lookupGen, leaderNameById = {}, {}, nil, {}
        return
    end
    if lookup ~= nil and lookupGen == cat.generated_at then
        return
    end
    lookup, lookupName, leaderNameById = {}, {}, {}
    lookupGen = cat.generated_at

    -- Find the existing entry for this player (by guid, then name) or make a
    -- fresh one, and (re)register it under both keys so later passes find it.
    local function getOrCreate(guid, name)
        local e
        if type(guid) == "string" then e = lookup[guid] end
        if not e then
            local k = normName(name)
            if k then e = lookupName[k] end
        end
        if not e then e = { name = name, isLeader = false, memberOf = {} } end
        if type(guid) == "string" then lookup[guid] = e end
        local k = normName(name)
        if k then lookupName[k] = e end
        return e
    end

    for _, ldr in ipairs(cat.leaders) do
        -- Stable group key; fall back to the guid on a pre-0.8.2 catalog so the
        -- present-leader path keeps working (leaderless just stays off then).
        local lid = ldr.leader_id or ldr.guid
        local le = getOrCreate(ldr.guid, ldr.name)
        le.isLeader = true
        le.leaderName = ldr.name
        le.leaderId = lid
        le.name = ldr.name
        -- Group display name: prefer the marked persona's own row (guid == lid).
        if ldr.guid == lid or not leaderNameById[lid] then
            leaderNameById[lid] = ldr.name
        end
        if type(ldr.members) == "table" then
            for _, m in ipairs(ldr.members) do
                local me = getOrCreate(m.guid, m.name)
                me.memberOf[lid] = true
            end
        end
        if type(ldr.confirmed_members) == "table" then
            for _, m in ipairs(ldr.confirmed_members) do
                local me = getOrCreate(m.guid, m.name)
                me.confirmedOf = me.confirmedOf or {}
                me.confirmedOf[lid] = true
            end
        end
    end
end

-- Player's own faction as the scoreboard encodes it: 0=Horde, 1=Alliance.
local function myFaction()
    local g = UnitFactionGroup("player")
    if g == "Alliance" then return 1 end
    if g == "Horde" then return 0 end
    return nil
end

-- Treat a row as the enemy unless we can positively confirm it's our side.
-- If faction is unreadable (secret) we still warn — over-warning beats a
-- silent miss, and it keeps a tainted compare from ever happening.
local function isEnemy(faction, mine)
    if mine == nil then return true end
    if secret(faction) then return true end
    return faction ~= mine
end

-- Returns a result table { confirmed, leaderlessOnly, leaders = { {name, count,
-- confirmed, leaderAbsent}, ... } } of enemy-side premades: each present leader
-- (and how many of their regulars are here), plus any LEADERLESS premade — a
-- leader NOT present but with >= CONFIRM_MIN_MEMBERS of their CONFIRMED regulars
-- (faction-readable enemies) on the board. Returns nil when we can't scan, and
-- { leaders = {} } when nothing matched.
local function detectImpl()
    -- Always-populated diagnostic snapshot of this scan attempt. autoScan /
    -- ManualScan log it; the field names map 1:1 to the dbg line below.
    -- str/sec = plain/secret guids, nm = plain names (the matchable field).
    local diag = { bg = false, cat = 0, n = 0, str = 0, sec = 0, nm = 0, hit = 0, enemy = 0, ldr = 0, lless = 0, mine = -1 }
    PremadeAlert._diag = diag

    if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        return nil
    end
    diag.bg = true

    ensureLookup()
    for _ in pairs(lookup) do diag.cat = diag.cat + 1 end
    if not next(lookup) and not next(lookupName) then return nil end

    local mine = myFaction()
    diag.mine = (mine == nil) and -1 or mine
    -- GetScoreInfo / GetNumBattlefieldScores only return rows for the faction
    -- last selected via SetBattlefieldScoreFaction; the default after
    -- PVP_MATCH_ACTIVE is the LOCAL faction, so the enemy half — the exact
    -- side we scan for — is invisible (alertLog showed n≈38 on misses vs n≈75
    -- on the one match that fired). Passing no faction unfilters to BOTH sides,
    -- the same call Blizzard's own scoreboard makes when switching team tabs.
    --
    -- The "show all factions" tab in Blizzard's own scoreboard passes
    -- factionEnum = -1 (PVPMatchResults.xml; 1 = Alliance, 0 = Horde). A bare
    -- call (nil) does NOT unfilter — alertLog proved it: n stayed ≈35 = our
    -- team only. We re-issue -1 on every scan because issuing it once at the
    -- n=0 opening tick didn't stick. The scanning-guard in detect() absorbs the
    -- synchronous UPDATE_BATTLEFIELD_SCORE this fires, so re-entry is harmless.
    if SetBattlefieldScoreFaction then pcall(SetBattlefieldScoreFaction, -1) end
    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
    local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    diag.n = n
    if n == 0 then return nil end

    -- Collect every enemy-side catalog player present (deduped by entry), the
    -- leaders among them (leader_id → display label), and which present players
    -- were READABLE-faction enemies — the leaderless path requires that, since a
    -- secret-faction member could actually be on our own side.
    local present, presentLeaders, seen, enemyReadable = {}, {}, {}, {}
    for i = 1, n do
        local info = C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i)
        if info then
            local guid = info.guid
            local name = info.name
            local plainGuid = (type(guid) == "string") and not secret(guid)
            local plainName = (type(name) == "string") and name ~= "" and not secret(name)

            if type(guid) == "string" and secret(guid) then diag.sec = diag.sec + 1 end
            if plainGuid then diag.str = diag.str + 1 end
            if plainName then diag.nm = diag.nm + 1 end

            -- Resolve a catalog entry: prefer the precise guid while it's
            -- still plain, else fall back to the (NeverSecret) name.
            local entry
            if plainGuid then entry = lookup[guid] end
            if entry == nil and plainName then
                local key = normName(name)
                if key then entry = lookupName[key] end
            end

            if entry then
                diag.hit = diag.hit + 1
                -- Dedup by entry identity and gate on faction (enemy only).
                if not seen[entry] and isEnemy(info.faction, mine) then
                    diag.enemy = diag.enemy + 1
                    seen[entry] = true
                    present[#present + 1] = entry
                    -- Positively-readable enemy faction (not the permissive
                    -- secret→enemy fallback) — gates the leaderless count.
                    if (not secret(info.faction)) and mine ~= nil
                            and info.faction ~= mine then
                        enemyReadable[entry] = true
                    end
                    if entry.isLeader then
                        presentLeaders[entry.leaderId] =
                            (plainName and name) or entry.name or entry.leaderName
                    end
                end
            end
        end
    end

    -- Tally per premade (keyed by leader_id): present regulars (ALERT-tier
    -- memberOf, permissive faction — the present-leader path) and present
    -- CONFIRMED regulars (confirmedOf, readable-enemy only — the leaderless path).
    local memberCount, confirmedCount = {}, {}
    for _, e in ipairs(present) do
        if not e.isLeader then
            if e.memberOf then
                for lid in pairs(e.memberOf) do
                    memberCount[lid] = (memberCount[lid] or 0) + 1
                end
            end
            if e.confirmedOf and enemyReadable[e] then
                for lid in pairs(e.confirmedOf) do
                    confirmedCount[lid] = (confirmedCount[lid] or 0) + 1
                end
            end
        end
    end

    local out, confirmed, anyPresent = {}, false, false
    -- Present leaders: a known leader on the board is a premade regardless of
    -- count (possible → confirmed once enough of their regulars are here too).
    for lid, label in pairs(presentLeaders) do
        anyPresent = true
        local count = memberCount[lid] or 0
        local isConfirmed = count >= CONFIRM_MIN_MEMBERS
        confirmed = confirmed or isConfirmed
        out[#out + 1] = { name = label, count = count, confirmed = isConfirmed }
    end
    -- Leaderless premades: the leader is NOT on the board, but >= the threshold
    -- of their CONFIRMED regulars are. Always confirmed — a 6-strong stack of a
    -- known premade's regulars is a strong signal even without the leader.
    for lid, count in pairs(confirmedCount) do
        if not presentLeaders[lid] and count >= CONFIRM_MIN_MEMBERS then
            confirmed = true
            diag.lless = diag.lless + 1
            out[#out + 1] = {
                name = leaderNameById[lid] or "?",
                count = count, confirmed = true, leaderAbsent = true,
            }
        end
    end

    if #out == 0 then return { leaders = {} } end
    table.sort(out, function(a, b) return a.count > b.count end)
    diag.ldr = #out
    -- leaderlessOnly drives a distinct headline when NO marked leader is present
    -- at all (only the regulars gave the premade away).
    return { leaders = out, confirmed = confirmed, leaderlessOnly = not anyPresent }
end

-- Re-entrancy guard around detectImpl. SetBattlefieldScoreFaction() inside it
-- fires UPDATE_BATTLEFIELD_SCORE synchronously → OnBattlefieldScoreUpdate →
-- autoScan → detect() again, recursing until a C stack overflow. The flag
-- makes that inner re-entry a no-op; pcall guarantees the flag always resets.
local function detect()
    if scanning then return nil end
    scanning = true
    local ok, res = pcall(detectImpl)
    scanning = false
    if not ok then
        dbg("detect error: " .. tostring(res))
        return nil
    end
    return res
end

-- Compact, deduped scan-result line for the diagnostic log.
local function logDiag(tag)
    local d = PremadeAlert._diag or {}
    local line = ("%s bg=%s cat=%d n=%d str=%d sec=%d nm=%d hit=%d enemy=%d ldr=%d lless=%d mine=%d"):format(
        tag, tostring(d.bg), d.cat or 0, d.n or 0, d.str or 0,
        d.sec or 0, d.nm or 0, d.hit or 0, d.enemy or 0, d.ldr or 0, d.lless or 0, d.mine or -1)
    if line ~= lastLog then
        dbg(line)
        lastLog = line
    end
end

-- Headline for a result: a leaderless premade (no marked leader present) gets
-- its own wording; otherwise confirmed = red, possible = amber.
local function headlineFor(res)
    if res.leaderlessOnly then return L["PremadeNoLeader"] end
    return res.confirmed and L["PremadeDetected"] or L["PremadePossible"]
end

-- One result line, picking the leaderless wording when the leader isn't present.
local function leaderLineFor(ld)
    local fmt = ld.leaderAbsent and L["PremadeNoLeaderLine"] or L["PremadeLeaderLine"]
    return fmt:format(ld.name, ld.count)
end

-- Broadcast-ready one-liner for the copy dialog — what the user pastes into
-- /rw or raid chat themselves. "Headline — Leader X: 8 — Leader Y: 2".
local function buildCopyText(res)
    local parts = { headlineFor(res) }
    for _, ld in ipairs(res.leaders) do
        parts[#parts + 1] = leaderLineFor(ld)
    end
    return table.concat(parts, " — ")
end

-- On-demand copy dialog: a highlighted, pre-selected edit box. We never send
-- chat from insecure code (blocked in 12.0.x with ADDON_ACTION_BLOCKED); the
-- user Ctrl+C's and pastes manually, which sidesteps that entirely. Opened via
-- /piq copy (and on demand) — never auto-popped, so it can't steal WASD focus
-- mid-fight.
StaticPopupDialogs["PREMADEIQ_COPY"] = {
    text = "PremadeIQ — " .. L["PremadeCopyHint"],
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 350,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(dialog, data)
        local eb = dialog.editBox or dialog.EditBox
        if eb then
            eb:SetText(data or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    EditBoxOnEnterPressed  = function(eb) eb:GetParent():Hide() end,
}

function PremadeAlert:ShowCopyDialog(text)
    if not text or text == "" then return end
    StaticPopup_Show("PREMADEIQ_COPY", nil, nil, text)
end

-- /piq copy — reopen the copy dialog for the most recent alert.
function PremadeAlert:CopyLast()
    if self._copyText and self._copyText ~= "" then
        self:ShowCopyDialog(self._copyText)
    else
        prnt(L["PremadeCopyNone"])
    end
end

-- Auto-appearing copy button. Lives in the MAIN addon (the one every player
-- downloads), not the owner-only Leader toolbar — so everyone who gets a
-- premade alert can copy it. Shown when an alert fires, hidden on match reset.
-- It's a BUTTON, not the focus-grabbing edit dialog: it can't steal WASD
-- mid-fight. Clicking it (the user's chosen moment) opens the copy dialog.
-- Draggable; position persists in PremadeIQ_DB.copyBtnPos.
local function ensureCopyButton()
    if PremadeAlert._copyBtn then return PremadeAlert._copyBtn end
    local b = CreateFrame("Button", "PremadeIQCopyButton", UIParent, "UIPanelButtonTemplate")
    b:SetSize(190, 26)
    b:SetText(L["PremadeCopyBtn"])
    b:SetFrameStrata("HIGH")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")  -- left = copy, right = close
    local pos = PremadeIQ_DB and PremadeIQ_DB.copyBtnPos
    if pos and pos.point then
        b:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        -- Default: just under the centre-screen RaidWarning banner.
        b:SetPoint("TOP", UIParent, "TOP", 0, -190)
    end
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        PremadeIQ_DB = PremadeIQ_DB or {}
        PremadeIQ_DB.copyBtnPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            PremadeAlert:HideCopyButton()  -- dismiss on demand
        else
            PremadeAlert:CopyLast()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["PremadeCopyBtnTip"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    PremadeAlert._copyBtn = b
    return b
end

function PremadeAlert:ShowCopyButton()
    ensureCopyButton():Show()
end

function PremadeAlert:HideCopyButton()
    if self._copyBtn then self._copyBtn:Hide() end
end

function PremadeAlert:Announce(res)
    local header = headlineFor(res)
    -- Confirmed = red, possible = amber.
    local hex = res.confirmed and "ff2020" or "ffcc00"
    prnt("|cff" .. hex .. header .. "|r")
    -- One line per leader: who they are + how many of their players are here
    -- (or the leaderless wording when the leader isn't on the board).
    for _, ld in ipairs(res.leaders) do
        prnt("|cffffd100" .. leaderLineFor(ld) .. "|r")
    end

    -- Big centre-screen banner (the /rw-style frame) so it's impossible to miss
    -- in a noisy Epic chat. Header alone is enough; the names stay in chat.
    if RaidNotice_AddMessage and RaidWarningFrame then
        local colour = res.confirmed and { r = 1, g = 0.13, b = 0.13 }
                                      or { r = 1, g = 0.8, b = 0 }
        pcall(RaidNotice_AddMessage, RaidWarningFrame, header, colour)
    end

    if not ns.Database or ns.Database:GetSetting("premadeSound") ~= false then
        PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end

    -- Stash a broadcast-ready line and tell the user how to grab it.
    self._copyText = buildCopyText(res)
    self:ShowCopyButton()
    prnt("|cff888888" .. L["PremadeCopyTip"] .. "|r")

    self._last = { res = res, at = time() }
end

-- Auto path: respects the per-match guard, the user's toggle, and the scan
-- throttle (UPDATE_BATTLEFIELD_SCORE fires far faster than we need to scan).
local function autoScan()
    if fired then return end
    if ns.Database and ns.Database:GetSetting("premadeAlert") == false then return end
    local now = GetTime()
    if now - lastScanAt < SCAN_THROTTLE_SEC then return end
    lastScanAt = now
    local res = detect()
    logDiag("scan")
    if not res or #res.leaders == 0 then return end  -- no leader → not a premade
    fired = true
    PremadeAlert:Announce(res)
    dbg(("ANNOUNCE leaders=%d confirmed=%s"):format(#res.leaders, tostring(res.confirmed)))
end

function PremadeAlert:OnMatchActive()
    fired = false
    matchStart = time()
    lastLog = nil
    lastScanAt = 0
    self:HideCopyButton()   -- fresh match: drop any stale button until we re-detect
    for _, t in ipairs(self._timers) do pcall(function() t:Cancel() end) end
    self._timers = {}
    -- Log catalog state at match start: a `leaders=0` here means the catalog
    -- never loaded (the file isn't being read), which no amount of scanning
    -- can fix. A non-zero count shifts the investigation to the scan lines.
    ensureLookup()
    local lk = 0
    for _ in pairs(lookup) do lk = lk + 1 end
    local nlead, tier = self:CatalogInfo()
    dbg(("MATCH_ACTIVE catalog_leaders=%d lookup=%d tier=%s"):format(
        nlead or 0, lk, tostring(tier)))
    for _, d in ipairs(SCAN_DELAYS_SEC) do
        local delay = d
        self._timers[#self._timers + 1] = C_Timer.NewTimer(delay, autoScan)
    end
end

-- Free re-scan trigger: the client pushes UPDATE_BATTLEFIELD_SCORE whenever
-- the score cache changes. We piggy-back on it during the opening window so
-- a late-arriving enemy roster gets caught the moment it appears, instead of
-- only at our fixed timer ticks. No-op once we've already announced.
function PremadeAlert:OnBattlefieldScoreUpdate()
    if fired then return end
    if matchStart == 0 or (time() - matchStart) > SCAN_WINDOW_SEC then return end
    autoScan()
end

function PremadeAlert:Reset()
    fired = false
    matchStart = 0
    lastScanAt = 0
    self:HideCopyButton()   -- left the BG: tuck the button away
    for _, t in ipairs(self._timers) do pcall(function() t:Cancel() end) end
    self._timers = {}
end

-- Manual path (/piq premade): always announces, ignores the per-match
-- guard, and reports when nothing matched so the command never looks dead.
function PremadeAlert:ManualScan()
    local res = detect()
    lastLog = nil  -- force a fresh line for the manual probe
    logDiag("manual")
    if res == nil then
        if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
            prnt(L["Not in a BG"])
        else
            prnt(L["PremadeNone"])
        end
        return
    end
    if #res.leaders == 0 then
        prnt(L["PremadeNone"])
        return
    end
    self:Announce(res)
end

-- (#leaders, tier) from the loaded catalog — used for the load message.
function PremadeAlert:CatalogInfo()
    local cat = PremadeIQ_KnownPremades
    if type(cat) ~= "table" or type(cat.leaders) ~= "table" then
        return 0, nil
    end
    return #cat.leaders, cat.tier
end
