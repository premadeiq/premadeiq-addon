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
    _buttons = {},
    _signature = "",
    _lastScanAt = 0,
    _scanning = false,
}
ns.PremadeTargets = Targets

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
    if not self:Initialize() then
        self._pendingPlayers = copyPlayers(players)
        return false
    end

    if Core.ShouldDeferSecureUpdate(
        InCombatLockdown and InCombatLockdown(),
        self._signature,
        players
    ) then
        self._pendingPlayers = copyPlayers(players)
        return false
    end

    if InCombatLockdown and InCombatLockdown() then return true end

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

    self._signature = Core.PlayerSignature(players)
    self._pendingPlayers = nil
    self._players = copyPlayers(players)

    if count == 0 then
        self._panel:Hide()
    else
        local width = self.PANEL_PADDING * 2
            + columns * self.BUTTON_WIDTH
            + math.max(0, columns - 1) * self.BUTTON_GAP
        local height = self.HEADER_HEIGHT + self.PANEL_PADDING * 2
            + rows * self.BUTTON_HEIGHT
            + math.max(0, rows - 1) * self.BUTTON_GAP
        self._panel:SetSize(width, height)
        self._panel.header:SetText(L["PremadeTargetsHeader"] .. " (" .. count .. ")")
        self._panel:Show()
    end
    return true
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

function Targets:RefreshFromScoreboard(force)
    if not self:Initialize() then return false end
    if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        return self:ApplyPlayers({})
    end

    local now = GetTime and GetTime() or 0
    if not force and now - self._lastScanAt < self.SCAN_THROTTLE_SEC then return false end
    if self._scanning then return false end
    self._lastScanAt = now
    self._scanning = true

    if SetBattlefieldScoreFaction then pcall(SetBattlefieldScoreFaction, -1) end
    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end

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
    local players = Core.FilterRoster(rows, self:RebuildCatalog(), playerFaction(), realm)
    self._scanning = false
    return self:ApplyPlayers(players)
end

function Targets:OnPlayerRegenEnabled()
    if self._needsInitialize then self:Initialize() end
    if self._pendingPlayers then
        local players = self._pendingPlayers
        self._pendingPlayers = nil
        return self:ApplyPlayers(players)
    end
    return self:RefreshFromScoreboard(true)
end

function Targets:Reset()
    self._lastScanAt = 0
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
        C_Timer.After(2, function() Targets:RefreshFromScoreboard(true) end)
    elseif event == "PVP_MATCH_ACTIVE" then
        Targets._lastScanAt = 0
        for _, delay in ipairs({ 1, 4, 8, 15, 30, 60, 120 }) do
            C_Timer.After(delay, function() Targets:RefreshFromScoreboard(true) end)
        end
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        Targets:RefreshFromScoreboard(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Targets:OnPlayerRegenEnabled()
    elseif event == "PVP_MATCH_COMPLETE" then
        Targets:Reset()
    end
end)
