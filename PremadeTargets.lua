local ADDON, ns = ...
local L = ns.L
local Core = ns.PremadeTargetsCore

local Targets = {
    MAX_BUTTONS = 40,
    MAX_COLUMNS = 3,
    BUTTON_WIDTH = 152,
    BUTTON_HEIGHT = 22,
    BUTTON_GAP = 3,
    PANEL_PADDING = 7,
    HEADER_HEIGHT = 24,
    SCAN_THROTTLE_SEC = 1.0,
    -- Asking the server for fresh scoreboard data is rate-limited separately
    -- from reading the cache it fills: the ticker/startup burst request, the
    -- UPDATE_BATTLEFIELD_SCORE handler only consumes. Coupling the two made a
    -- request-then-immediately-read-the-old-cache pattern that also swallowed
    -- the response event under the scan throttle.
    REQUEST_THROTTLE_SEC = 2.0,
    TICK_SEC = 2.0,
    -- Short burst while the scoreboard fills at match start; the ticker covers
    -- everything after it. Spaced >= SCAN_THROTTLE_SEC apart so each attempt
    -- survives the throttle without needing force.
    STARTUP_BURST = { 0.5, 1.5, 3, 6, 10 },
    _buttons = {},
    _signature = "",
    _lastScanAt = 0,
    _lastRequestAt = 0,
    _scanning = false,
    _headerStale = false,
    _headerCount = 0,
    _pendingSignature = nil,
    _timers = {},
    _generation = 0,
    _ticker = nil,
}
ns.PremadeTargets = Targets

-- Marker appended to the header while a roster update waits for combat to end.
local STALE_MARK = "•"

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function playerFaction()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Alliance" then return 1 end
    if faction == "Horde" then return 0 end
    return nil
end

local function displayName(name)
    if Ambiguate then
        local ok, value = pcall(Ambiguate, name, "none")
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return name
end

local function targetName(name)
    if Ambiguate then
        local ok, value = pcall(Ambiguate, name, "none")
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return name
end

local function copyPlayers(players)
    local copy = {}
    for i, player in ipairs(players or {}) do copy[i] = player end
    return copy
end

local function savePanelPosition(panel)
    if InCombatLockdown and InCombatLockdown() then return end
    local point, _, relativePoint, x, y = panel:GetPoint()
    PremadeIQ_DB = PremadeIQ_DB or {}
    PremadeIQ_DB.premadeTargetsPos = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function restorePanelPosition(panel)
    local pos = PremadeIQ_DB and PremadeIQ_DB.premadeTargetsPos
    panel:ClearAllPoints()
    if type(pos) == "table" and type(pos.point) == "string" then
        panel:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -260, 40)
    end
end

-- Idle look. Leaders get a warm, slightly brighter plate so they read as the
-- priority entry without needing the star to be spotted first.
local function applyIdleStyle(button)
    if button.playerInfo and button.playerInfo.isLeader then
        button:SetBackdropColor(0.17, 0.14, 0.07, 0.86)
        button:SetBackdropBorderColor(0.62, 0.50, 0.22, 0.75)
    else
        button:SetBackdropColor(0.11, 0.11, 0.14, 0.82)
        button:SetBackdropBorderColor(0.30, 0.30, 0.36, 0.55)
    end
end

local function applyHoverStyle(button)
    button:SetBackdropColor(0.22, 0.22, 0.28, 0.94)
    button:SetBackdropBorderColor(0.95, 0.78, 0.36, 0.95)
end

local function showTooltip(button)
    local player = button.playerInfo
    if not player then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(player.canonicalName or player.name)
    GameTooltip:AddLine(player.isLeader and L["PremadeTargetLeader"] or L["PremadeTargetMember"], 1, 0.82, 0)
    if player.groups and #player.groups > 0 then
        GameTooltip:AddLine(L["PremadeTargetGroups"] .. ": " .. table.concat(player.groups, ", "), 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(L["PremadeTargetClick"], 0.5, 1, 0.5, true)
    GameTooltip:Show()
end

local function makeButton(index, panel)
    local button = CreateFrame(
        "Button",
        "PremadeIQTargetButton" .. index,
        panel,
        "SecureActionButtonTemplate,BackdropTemplate"
    )
    button:SetSize(Targets.BUTTON_WIDTH, Targets.BUTTON_HEIGHT)
    -- SecureActionButton_OnClick (Blizzard SecureTemplates.lua) decides which
    -- click edge fires the action from the "useOnKeyDown" attribute, falling
    -- back to the ActionButtonUseKeyDown CVar when the attribute is unset.
    -- With that CVar on (the current default) a button registered for "AnyUp"
    -- only ever sees down=false, `clickAction` evaluates false and the click is
    -- swallowed silently — which is exactly why these buttons did nothing.
    -- Pin the attribute to the edge we register for so the two always agree,
    -- whatever the user's CVar says.
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    applyIdleStyle(button)
    button:Hide()

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", button, "LEFT", 7, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -5, 0)
    label:SetJustifyH("LEFT")
    button.label = label

    button:SetScript("OnEnter", function(self)
        applyHoverStyle(self)
        showTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        applyIdleStyle(self)
        GameTooltip:Hide()
    end)
    return button
end

function Targets:Initialize()
    if self._panel then return true end
    if InCombatLockdown and InCombatLockdown() then
        self._needsInitialize = true
        return false
    end

    local panel = CreateFrame("Frame", "PremadeIQTargetsPanel", UIParent, "BackdropTemplate")
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.86)
    panel:SetBackdropBorderColor(0.52, 0.45, 0.32, 0.90)
    restorePanelPosition(panel)
    panel:SetScript("OnDragStart", function(self)
        if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:StopMovingOrSizing()
        savePanelPosition(self)
    end)

    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", self.PANEL_PADDING, -6)
    header:SetJustifyH("LEFT")
    header:SetTextColor(1, 0.82, 0.15)
    panel.header = header

    self._panel = panel
    self._buttons = {}
    for i = 1, self.MAX_BUTTONS do
        self._buttons[i] = makeButton(i, panel)
    end
    panel:Hide()
    self._needsInitialize = nil
    return true
end

function Targets:ApplyPlayers(players)
    players = players or {}
    local signature = Core.PlayerSignature(players)

    if not self:Initialize() then
        self._pendingPlayers = copyPlayers(players)
        self._pendingSignature = signature
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        if signature ~= self._signature then
            -- Secure attributes are frozen in combat: remember the newest
            -- roster and flag the header. Skip the copy when the pending set
            -- already matches — scoreboard events fire far faster than rosters
            -- actually change.
            if signature ~= self._pendingSignature then
                self._pendingPlayers = copyPlayers(players)
                self._pendingSignature = signature
            end
            self:SetHeaderStale(true)
        else
            -- The roster came back to what is already on the buttons. Any
            -- pending update is now obsolete — dropping it matters, because
            -- otherwise leaving combat would apply that older roster over a
            -- display that is already correct.
            self._pendingPlayers = nil
            self._pendingSignature = nil
            self:SetHeaderStale(false)
        end
        return false
    end

    local count = math.min(#players, self.MAX_BUTTONS)
    local layout, columns, rows = Core.ComputeLayout(count, self.MAX_COLUMNS)
    for i, button in ipairs(self._buttons) do
        if i <= count then
            local player = players[i]
            local secureName = targetName(player.name)
            local macro = Core.TargetMacro(secureName)
            local focusMacro = Core.FocusMacro(secureName)
            local pos = layout[i]
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT",
                self._panel,
                "TOPLEFT",
                self.PANEL_PADDING + (pos.column - 1) * (self.BUTTON_WIDTH + self.BUTTON_GAP),
                -(self.HEADER_HEIGHT + self.PANEL_PADDING + (pos.row - 1) * (self.BUTTON_HEIGHT + self.BUTTON_GAP))
            )
            button:SetAttribute("type1", macro and "macro" or nil)
            button:SetAttribute("macrotext1", macro)
            button:SetAttribute("type2", focusMacro and "macro" or nil)
            button:SetAttribute("macrotext2", focusMacro)
            button.playerInfo = player
            applyIdleStyle(button)
            button.label:SetText((player.isLeader and "★ " or "") .. displayName(player.name))
            local color = player.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[player.classToken]
            if color then
                button.label:SetTextColor(color.r, color.g, color.b)
            else
                button.label:SetTextColor(0.92, 0.92, 0.92)
            end
            button:Show()
        else
            button:SetAttribute("type1", nil)
            button:SetAttribute("macrotext1", nil)
            button:SetAttribute("type2", nil)
            button:SetAttribute("macrotext2", nil)
            button.playerInfo = nil
            button:Hide()
        end
    end

    self._signature = signature
    self._pendingPlayers = nil
    self._pendingSignature = nil
    self._players = copyPlayers(players)
    self._headerCount = count
    -- Cleared on BOTH branches below, including the hidden/zero-player one, so
    -- the marker can never survive a successful application.
    self._headerStale = false

    if count == 0 then
        self:RenderHeader()
        self._panel:Hide()
    else
        local width = self.PANEL_PADDING * 2
            + columns * self.BUTTON_WIDTH
            + math.max(0, columns - 1) * self.BUTTON_GAP
        local height = self.HEADER_HEIGHT + self.PANEL_PADDING * 2
            + rows * self.BUTTON_HEIGHT
            + math.max(0, rows - 1) * self.BUTTON_GAP
        self._panel:SetSize(width, height)
        self:RenderHeader()
        self._panel:Show()
    end
    return true
end

-- Header is a FontString on a NON-secure frame, so SetText/SetTextColor stay
-- legal in combat lockdown — that is what lets us flag a deferred update while
-- the secure buttons themselves cannot be touched. Always re-rendered from the
-- base string + count so the marker can never be appended twice.
function Targets:RenderHeader()
    local panel = self._panel
    if not panel or not panel.header then return end
    local text = L["PremadeTargetsHeader"] .. " (" .. (self._headerCount or 0) .. ")"
    if self._headerStale then
        panel.header:SetText(text .. " " .. STALE_MARK)
        panel.header:SetTextColor(0.80, 0.66, 0.28)
    else
        panel.header:SetText(text)
        panel.header:SetTextColor(1, 0.82, 0.15)
    end
end

function Targets:SetHeaderStale(stale)
    stale = stale and true or false
    if self._headerStale == stale then return end
    self._headerStale = stale
    self:RenderHeader()
end

function Targets:RebuildCatalog()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    local catalog = PremadeIQ_KnownPremades
    local generated = type(catalog) == "table" and catalog.generated_at or nil
    if self._catalogIndex and self._catalogGenerated == generated and self._catalogRealm == realm then
        return self._catalogIndex
    end
    self._catalogIndex = Core.BuildCatalogIndex(catalog, realm)
    self._catalogGenerated = generated
    self._catalogRealm = realm
    return self._catalogIndex
end

-- `requestData` asks the server for a fresh scoreboard; without it we only read
-- the cache the client already holds. The UPDATE_BATTLEFIELD_SCORE handler
-- consumes without requesting, so a response can never be swallowed by the
-- scan throttle that our own request had just armed.
function Targets:RefreshFromScoreboard(force, requestData)
    if not self:Initialize() then return false end
    if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        return self:ApplyPlayers({})
    end

    local now = GetTime and GetTime() or 0
    if not force and now - self._lastScanAt < self.SCAN_THROTTLE_SEC then return false end
    if self._scanning then return false end
    -- Both flags are set BEFORE SetBattlefieldScoreFaction, which fires
    -- UPDATE_BATTLEFIELD_SCORE synchronously — that is what stops the handler
    -- from re-entering this function.
    self._lastScanAt = now
    self._scanning = true

    if requestData and now - (self._lastRequestAt or 0) >= self.REQUEST_THROTTLE_SEC then
        self._lastRequestAt = now
        if SetBattlefieldScoreFaction then pcall(SetBattlefieldScoreFaction, -1) end
        if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
    end

    local rows = {}
    local count = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    for i = 1, count do
        local info = C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i)
        if info then
            local name = info.name
            local faction = info.faction
            local classToken = info.classToken
            local role = info.role
            if not secret(name) and type(name) == "string" and name ~= "" then
                rows[#rows + 1] = {
                    name = name,
                    faction = not secret(faction) and faction or nil,
                    classToken = not secret(classToken) and classToken or nil,
                    role = not secret(role) and role or nil,
                }
            end
        end
    end

    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    -- Clear _scanning even if filtering or application throws: leaving it set
    -- would wedge every future scan behind the re-entry guard above.
    local ok, players = pcall(
        Core.FilterRoster, rows, self:RebuildCatalog(), playerFaction(), realm
    )
    self._scanning = false
    if not ok then return false end
    return self:ApplyPlayers(players)
end

function Targets:OnPlayerRegenEnabled()
    if self._needsInitialize then self:Initialize() end
    if self._pendingPlayers then
        local players = self._pendingPlayers
        self._pendingPlayers = nil
        self._pendingSignature = nil
        return self:ApplyPlayers(players)
    end
    return self:RefreshFromScoreboard(true, true)
end

-- C_Timer.After gives no handle, so its callbacks outlive the match that
-- scheduled them — a 120s one could fire inside the NEXT battleground and scan
-- it, or clear the panel out in the world. Everything scheduled here is a
-- cancelable NewTimer, and each callback also checks the match generation, so
-- a timer that slips through cancellation is still inert.
function Targets:CancelScheduled()
    for i = #self._timers, 1, -1 do
        local timer = self._timers[i]
        if timer and timer.Cancel then pcall(timer.Cancel, timer) end
        self._timers[i] = nil
    end
end

function Targets:ScheduleStartupBurst()
    self:CancelScheduled()
    self._generation = self._generation + 1
    local generation = self._generation
    for _, delay in ipairs(self.STARTUP_BURST) do
        local timer = C_Timer.NewTimer(delay, function()
            if generation ~= self._generation then return end
            self:RefreshFromScoreboard(true, true)
        end)
        self._timers[#self._timers + 1] = timer
    end
end

function Targets:StopTicker()
    if self._ticker then
        if self._ticker.Cancel then pcall(self._ticker.Cancel, self._ticker) end
        self._ticker = nil
    end
end

function Targets:StartTicker()
    self:StopTicker()
    local generation = self._generation
    self._ticker = C_Timer.NewTicker(self.TICK_SEC, function()
        -- Self-cancel covers abnormal exits (kick, disconnect, manual leave)
        -- where PVP_MATCH_COMPLETE never arrives and the ticker would
        -- otherwise wake forever.
        if generation ~= self._generation
            or not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
            self:StopTicker()
            return
        end
        if InCombatLockdown and InCombatLockdown() then return end
        self:RefreshFromScoreboard(false, true)
    end)
end

function Targets:Reset()
    self:CancelScheduled()
    self:StopTicker()
    self._generation = self._generation + 1
    self._lastScanAt = 0
    self._lastRequestAt = 0
    self._pendingPlayers = nil
    self._pendingSignature = nil
    return self:ApplyPlayers({})
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PVP_MATCH_ACTIVE")
eventFrame:RegisterEvent("PVP_MATCH_COMPLETE")
eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then Targets:Initialize() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Landing outside a battleground is the reliable signal that a match
        -- ended without PVP_MATCH_COMPLETE (kick, disconnect, manual leave).
        -- PLAYER_LEAVING_WORLD is not usable here: it fires before the
        -- destination is known, so cancelling on it would kill a live match's
        -- timers during an ordinary loading screen.
        if C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground() then
            Targets:ScheduleStartupBurst()
            Targets:StartTicker()
        else
            Targets:CancelScheduled()
            Targets:StopTicker()
            Targets:RefreshFromScoreboard(true, false)
        end
    elseif event == "PVP_MATCH_ACTIVE" then
        Targets._lastScanAt = 0
        Targets._lastRequestAt = 0
        Targets:ScheduleStartupBurst()
        Targets:StartTicker()
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        -- Consume only: the data is already in the client cache, and issuing
        -- another request here would re-arm the throttle against the very
        -- response we are handling.
        Targets:RefreshFromScoreboard(false, false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Targets:OnPlayerRegenEnabled()
    elseif event == "PVP_MATCH_COMPLETE" then
        Targets:Reset()
    end
end)
