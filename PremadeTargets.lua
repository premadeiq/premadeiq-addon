local ADDON, ns = ...
local L = ns.L
local Core = ns.PremadeTargetsCore

local Targets = {
    -- 40v40 is the largest Epic battleground, so 80 rows is the hard ceiling of
    -- what a scoreboard can ever produce. Secure buttons can only be created out
    -- of combat, hence the whole pool up front.
    MAX_BUTTONS = 80,
    DEFAULT_COLUMNS = 3,
    MIN_COLUMNS = 1,
    MAX_COLUMNS = 6,
    -- Floor, not the width: the real column width is measured from the longest
    -- name on screen so a cross-realm Name-Realm never gets clipped.
    MIN_BUTTON_WIDTH = 152,
    LABEL_PADDING = 18,
    MIN_PANEL_WIDTH = 320,
    BUTTON_HEIGHT = 22,
    BUTTON_GAP = 3,
    PANEL_PADDING = 7,
    HEADER_HEIGHT = 24,
    SECTION_HEADER_HEIGHT = 17,
    -- Height reserved for the odds line under the header. Only added to
    -- the layout when there IS a forecast, so a panel without one keeps
    -- exactly its old geometry.
    ODDS_HEIGHT = 16,
    SECTION_GAP = 6,
    MIN_SCALE = 0.70,
    MAX_SCALE = 1.50,
    SCALE_STEP = 0.05,
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
    _sectionHeaders = {},
    _signature = "",
    _lastScanAt = 0,
    _lastRequestAt = 0,
    _scanning = false,
    _headerStale = false,
    _headerCounts = { enemy = 0, ally = 0 },
    _pendingSignature = nil,
    _timers = {},
    _generation = 0,
    _ticker = nil,
}
ns.PremadeTargets = Targets

-- Marker appended to the header while a roster update waits for combat to end.
local STALE_MARK = "•"

-- Enemies first: that is the side you act on. Rows carrying no side at all are
-- treated as enemies, which keeps pre-side callers (and the older fixtures)
-- rendering exactly as they used to.
local SECTIONS = { "enemy", "ally" }

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

-- The viewer's own team in the scoreboard's own 0=Horde/1=Alliance space.
-- GetBattlefieldArenaFaction is what Blizzard's scoreboard itself uses
-- (Blizzard_PVPMatch/PVPMatchResults.lua), so it is right under mercenary mode —
-- where UnitFactionGroup reports the character's faction, not the team actually
-- being played — and in non-factional matches where the value is a team index.
-- UnitFactionGroup stays as the fallback for the moments the battlefield API has
-- nothing to say (outside a match, or before the scoreboard exists).
local function currentSide()
    if GetBattlefieldArenaFaction then
        local ok, value = pcall(GetBattlefieldArenaFaction)
        if ok and type(value) == "number" and not secret(value) then return value end
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Alliance" then return 1 end
    if faction == "Horde" then return 0 end
    return nil
end

-- Own canonical name, used only to drop the viewer's own row from the list.
-- UnitName is SecretWhenUnitIdentityRestricted, so a secret value here simply
-- means "exclude nobody" rather than letting a tainted string reach the string
-- library inside Core.NormalizeName.
local function ownCanonicalName(realm)
    if not UnitName then return nil end
    local ok, name = pcall(UnitName, "player")
    if not ok or secret(name) or type(name) ~= "string" or name == "" then return nil end
    return Core.NormalizeName(name, realm)
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

-- ASCII only. The 12.0.x UI font draws Latin-1 but not U+2605 BLACK STAR or
-- U+00B7 MIDDLE DOT — both came out as empty boxes in game.
local LEADER_MARK = "* "
-- Personal-watchlist mark. Same ASCII-only constraint as LEADER_MARK, and
-- deliberately different in shape so the two never read as the same claim: the
-- star means "we know this leader", the arrow means "you asked to watch them".
local WATCH_MARK  = "> "
-- Marked "takes raid lead, runs no premade". Neutral on purpose — a plain fact,
-- not an accusation, and visibly not the premade star.
local RAID_LEAD_MARK = "~ "
-- One tier below a confirmed member (catalog rev 7): the server has shared
-- history for them, just not enough of it. A question mark, because that is
-- exactly the claim — we are asking, not telling.
local LIKELY_MARK = "? "

local function labelText(player)
    -- One mark, strongest claim first. A raid leader who is ALSO a known premade
    -- member is a member here: that is the stronger statement, and the tilde
    -- would read as "runs no premade" while contradicting their own tooltip.
    local inPremade = player.groups and #player.groups > 0
    local mark = (player.isLeader and LEADER_MARK)
              or (player.isRaidLead and not inPremade and RAID_LEAD_MARK)
              -- Below a confirmed member and below an owner-made raid-lead
              -- mark: both of those are things we know, this one is a maybe.
              or (player.isLikely and not inPremade and LIKELY_MARK)
              or (player.isWatched and not player.inCatalog and WATCH_MARK)
              or ""
    return mark .. displayName(player.name)
end

local function copyPlayers(players)
    local copy = {}
    for i, player in ipairs(players or {}) do copy[i] = player end
    return copy
end

-- Settings live in PremadeIQ_DB.settings, the same table the options panel uses.
-- Read straight from the SavedVariable rather than through ns.Database: this
-- module's ADDON_LOADED handler is registered before Main.lua's, so Database:Init
-- has not run yet the first time the panel builds itself. Writes prefer the
-- Database accessor when it is live so both paths stay in sync.
local function getSetting(key, default)
    local db = PremadeIQ_DB
    local settings = (type(db) == "table") and db.settings or nil
    local value = settings and settings[key]
    if value == nil then return default end
    return value
end

local function setSetting(key, value)
    if ns.Database and ns.Database.SetSetting and ns.Database.db then
        ns.Database:SetSetting(key, value)
        return
    end
    PremadeIQ_DB = PremadeIQ_DB or {}
    PremadeIQ_DB.settings = PremadeIQ_DB.settings or {}
    PremadeIQ_DB.settings[key] = value
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

local function saveTrayPosition(tray)
    if InCombatLockdown and InCombatLockdown() then return end
    local point, _, relativePoint, x, y = tray:GetPoint()
    PremadeIQ_DB = PremadeIQ_DB or {}
    PremadeIQ_DB.premadeTargetsTrayPos = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function restoreTrayPosition(tray)
    local pos = PremadeIQ_DB and PremadeIQ_DB.premadeTargetsTrayPos
    tray:ClearAllPoints()
    if type(pos) == "table" and type(pos.point) == "string" then
        tray:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        -- Same corner the panel defaults to, so the first minimize leaves the
        -- button where the panel just was.
        tray:SetPoint("RIGHT", UIParent, "RIGHT", -260, 40)
    end
end

-- Idle look. Leaders get a warm, slightly brighter plate so they read as the
-- priority entry without needing the star to be spotted first. Your own team is
-- cool-toned instead: same information, visibly not the side you shoot at.
local function applyIdleStyle(button)
    local player = button.playerInfo
    local ally = player and player.side == "ally"
    if player and player.isLeader then
        if ally then
            button:SetBackdropColor(0.08, 0.13, 0.20, 0.86)
            button:SetBackdropBorderColor(0.32, 0.56, 0.82, 0.80)
        else
            button:SetBackdropColor(0.17, 0.14, 0.07, 0.86)
            button:SetBackdropBorderColor(0.62, 0.50, 0.22, 0.75)
        end
    elseif ally then
        button:SetBackdropColor(0.08, 0.10, 0.15, 0.82)
        button:SetBackdropBorderColor(0.24, 0.36, 0.52, 0.55)
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
    -- Caption priority. It reads both facts rather than picking a lane, because
    -- "takes raid lead" and "premade member" are NOT mutually exclusive: the
    -- server only bars a raid_lead from LEADING a roster, so the same person is
    -- often a confirmed member of somebody else's premade (21 of 47 on live
    -- data). A flat chain would caption those "runs no premade" — and the
    -- Premades: line further down this very tooltip would contradict it.
    -- A row that is here ONLY because the owner listed it stays neutral: we
    -- know nothing of the sort about them.
    local inPremade = player.groups and #player.groups > 0
    local caption
    if player.isLeader then
        caption = L["PremadeTargetLeader"]
    elseif inPremade then
        caption = L["PremadeTargetMember"]
    elseif player.isRaidLead then
        caption = L["PremadeTargetRaidLead"]
    elseif player.isLikely then
        caption = L["PremadeTargetLikely"]
    else
        caption = L["PremadeTargetWatched"]
    end
    GameTooltip:AddLine(caption, 1, 0.82, 0)
    -- Secondary facts, only when they are not already the caption.
    if player.isRaidLead and (player.isLeader or inPremade) then
        GameTooltip:AddLine(L["PremadeTargetRaidLeadAlso"], 0.8, 0.8, 0.8)
    end
    if player.isWatched and (player.isLeader or inPremade or player.isRaidLead) then
        GameTooltip:AddLine(L["PremadeTargetWatched"], 0.75, 0.9, 0.75)
    end
    if player.side == "ally" then
        GameTooltip:AddLine(L["PremadeTargetSideAlly"], 0.55, 0.75, 1)
    else
        GameTooltip:AddLine(L["PremadeTargetSideEnemy"], 1, 0.62, 0.52)
    end
    if player.groups and #player.groups > 0 then
        GameTooltip:AddLine(L["PremadeTargetGroups"] .. ": " .. table.concat(player.groups, ", "), 0.8, 0.8, 0.8, true)
    end
    -- Whose premade they MIGHT belong to. Separate line and separate wording
    -- from the confirmed one above: reusing "Groups" would state as fact the
    -- very thing this tier exists to hedge.
    if player.likelyGroups and #player.likelyGroups > 0
            and not (player.groups and #player.groups > 0) then
        GameTooltip:AddLine(
            L["PremadeTargetLikelyWith"] .. ": " .. table.concat(player.likelyGroups, ", "),
            0.75, 0.75, 0.7, true)
    end
    GameTooltip:AddLine(L["PremadeTargetClick"], 0.5, 1, 0.5, true)
    GameTooltip:Show()
end

local function makeButton(index, parent)
    local button = CreateFrame(
        "Button",
        "PremadeIQTargetButton" .. index,
        parent,
        "SecureActionButtonTemplate,BackdropTemplate"
    )
    button:SetSize(Targets.MIN_BUTTON_WIDTH, Targets.BUTTON_HEIGHT)
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
    -- The button is a single 22px row: without this an overlong name wraps into
    -- a clipped second line instead of staying on one.
    if label.SetWordWrap then label:SetWordWrap(false) end
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

-- One line for chat, carrying the same working as the tooltip. What the player
-- pastes is then arguable by the people reading it, which a bare "44%" is not.
--
-- Declared ABOVE Initialize on purpose: a `local function` is invisible to
-- anything defined earlier in the file, so the copy handler created inside
-- Initialize would have captured a nil global instead (the same trap that
-- once silently dropped the solo-raid-lead line in PremadeAlert).
local function oddsCopyText(f)
    return L["ForecastCopyFull"]:format(
        f.us, f.them, math.floor(f.ourWr + 0.5), math.floor(f.theirWr + 0.5),
        math.floor(f.ourNew + 0.5), math.floor(f.theirNew + 0.5), f.accuracy)
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

    -- Win chances for this match, under the header. On the panel itself and
    -- NOT inside `body`: body is a secure frame, and this has to stay
    -- writable during combat lockdown — which is most of a battleground.
    local odds = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    odds:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    odds:SetJustifyH("LEFT")
    odds:Hide()
    panel.odds = odds

    -- Mouse target sitting exactly over that line: hover explains where the
    -- number came from, click copies it for chat. A FontString cannot take
    -- mouse input itself, hence the frame. It is a plain (non-secure) frame, so
    -- both scripts stay legal in combat — which is when this is read.
    local hit = CreateFrame("Frame", nil, panel)
    hit:SetPoint("TOPLEFT", odds, "TOPLEFT", -2, 2)
    hit:SetPoint("BOTTOMRIGHT", odds, "BOTTOMRIGHT", 2, -2)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(frame)
        local f = self._forecast
        if not f then return end
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(L["ForecastTipTitle"], 1, 0.82, 0.15)
        GameTooltip:AddLine(L["ForecastTipSides"]:format(f.us, f.them), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["ForecastTipWr"]:format(
            math.floor(f.ourWr + 0.5), math.floor(f.theirWr + 0.5)), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["ForecastTipNew"]:format(
            math.floor(f.ourNew + 0.5), math.floor(f.theirNew + 0.5)), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["ForecastTipKnown"]:format(
            f.ourKnown, f.ourN, f.theirKnown, f.theirN), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["ForecastTipAcc"]:format(f.accuracy), 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine(L["ForecastTipCopy"], 0.5, 0.75, 1)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hit:SetScript("OnMouseUp", function()
        local f = self._forecast
        if f and ns.PremadeAlert then
            ns.PremadeAlert:ShowCopyDialog(oddsCopyText(f))
        end
    end)
    hit:Hide()
    panel.oddsHit = hit

    self._panel = panel

    -- Everything collapsible lives under `body`, and `body` is deliberately
    -- created from a secure template. Hiding a frame that parents
    -- SecureActionButtons is a protected action, so the collapse click has to
    -- run inside a restricted snippet — and RestrictedFrames only resolves a
    -- usable frame handle in combat when the target frame is itself protected
    -- (GetPossiblyForbiddenHandleFrame). A plain Frame here would raise
    -- "Invalid frame handle" during exactly the lockdown the button exists for.
    local body = CreateFrame("Frame", "PremadeIQTargetsBody", panel, "SecureHandlerBaseTemplate")
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    self._body = body

    local toggle = CreateFrame("Button", "PremadeIQTargetsToggle", panel, "SecureHandlerClickTemplate")
    toggle:SetSize(18, 18)
    toggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -4)
    toggle:RegisterForClicks("AnyUp")
    -- SetFrameRef itself throws in combat, which is fine: Initialize is already
    -- gated on being out of combat.
    toggle:SetFrameRef("body", body)
    toggle:SetAttribute("_onclick", [[
        self:GetFrameRef("body"):Hide()
    ]])
    -- PostClick, never OnClick: SecureHandlerClickTemplate keeps its own
    -- dispatch in OnClick, and overwriting it would stop the snippet above from
    -- ever running. Everything PostClick does (swapping panel for tray, saving
    -- the setting) touches unprotected frames only and is legal mid-combat.
    toggle:SetScript("PostClick", function() Targets:OnMinimized() end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["PremadeTargetsMinimize"])
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local caret = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    caret:SetPoint("CENTER", toggle, "CENTER", 0, 0)
    caret:SetTextColor(1, 0.82, 0.15)
    caret:SetText("X")
    toggle.caret = caret
    self._toggle = toggle

    -- Minimized state is a separate little button, the way REZAL Raid Caller
    -- does it: the panel goes away entirely rather than shrinking to a header
    -- strip. The tray hangs off UIParent, not the panel — a child would be
    -- hidden along with the very frame it is meant to replace — and it keeps its
    -- own dragged position, so folding and unfolding never moves the panel.
    --
    -- Two frames, deliberately: the tray itself must stay UNPROTECTED, because
    -- showing and hiding it mid-combat is the entire point, and a frame built
    -- from SecureHandlerClickTemplate is protected (that template inherits
    -- SecureFrameTemplate, protected="true") — Show/Hide on it would be blocked
    -- in exactly the lockdown we need. So the visible tray is a plain Frame and
    -- a protected click-catcher sits on top of it to run the snippet.
    local tray = CreateFrame("Frame", "PremadeIQTargetsTray", UIParent, "BackdropTemplate")
    tray:SetSize(72, 22)
    tray:SetFrameStrata("HIGH")
    tray:SetClampedToScreen(true)
    tray:SetMovable(true)
    tray:EnableMouse(true)
    tray:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    tray:SetBackdropColor(0.05, 0.05, 0.07, 0.86)
    tray:SetBackdropBorderColor(0.52, 0.45, 0.32, 0.90)
    restoreTrayPosition(tray)
    local trayLabel = tray:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trayLabel:SetPoint("CENTER", tray, "CENTER", 0, 0)
    trayLabel:SetTextColor(1, 0.82, 0.15)
    tray.label = trayLabel
    tray:Hide()
    self._tray = tray

    -- Restoring has to un-hide `body`, which is protected, so the click needs a
    -- snippet; the insecure PostClick half only swaps which frame is visible.
    -- Dragging lives here too — this button covers the tray, so it is what the
    -- mouse actually reaches — but it moves its unprotected parent, never
    -- itself.
    local trayClick = CreateFrame("Button", "PremadeIQTargetsTrayButton", tray,
        "SecureHandlerClickTemplate")
    trayClick:SetAllPoints(tray)
    trayClick:RegisterForClicks("AnyUp")
    trayClick:RegisterForDrag("LeftButton")
    trayClick:SetFrameRef("body", body)
    trayClick:SetAttribute("_onclick", [[
        self:GetFrameRef("body"):Show()
    ]])
    trayClick:SetScript("PostClick", function() Targets:OnRestored() end)
    trayClick:SetScript("OnDragStart", function()
        if not (InCombatLockdown and InCombatLockdown()) then tray:StartMoving() end
    end)
    trayClick:SetScript("OnDragStop", function()
        if InCombatLockdown and InCombatLockdown() then return end
        tray:StopMovingOrSizing()
        saveTrayPosition(tray)
    end)
    trayClick:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["PremadeTargetsHeader"])
        GameTooltip:AddLine(L["PremadeTargetsTrayHint"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    trayClick:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self._trayClick = trayClick

    -- Off-screen ruler used to size columns to the longest name actually shown.
    local measure = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measure:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    if measure.Hide then measure:Hide() end
    self._measure = measure

    self._sectionHeaders = {}
    for _, side in ipairs(SECTIONS) do
        local sectionHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sectionHeader:SetJustifyH("LEFT")
        if side == "ally" then
            sectionHeader:SetTextColor(0.55, 0.75, 1)
        else
            sectionHeader:SetTextColor(1, 0.62, 0.52)
        end
        if sectionHeader.Hide then sectionHeader:Hide() end
        self._sectionHeaders[side] = sectionHeader
    end

    self._buttons = {}
    for i = 1, self.MAX_BUTTONS do
        self._buttons[i] = makeButton(i, body)
    end

    if self:IsMinimized() then body:Hide() end
    self:ApplyScale()
    self:RenderTray()
    panel:Hide()
    self._needsInitialize = nil
    return true
end

function Targets:IsMinimized()
    return getSetting("targetsMinimized", false) == true
end

-- Tray caption doubles as the whole readout while minimized, so it carries the
-- same counts as the panel header.
function Targets:RenderTray()
    local tray = self._tray
    if not tray or not tray.label then return end
    local counts = self._headerCounts or { enemy = 0, ally = 0 }
    local text = "PIQ " .. (counts.enemy or 0)
    if (counts.ally or 0) > 0 then text = text .. " / " .. counts.ally end
    tray.label:SetText(text)
end

-- Both of these run from PostClick, after the secure snippet has already
-- hidden/shown `body` (the only protected frame involved). Everything here
-- touches unprotected frames, so minimizing works mid-combat.
function Targets:OnMinimized()
    setSetting("targetsMinimized", true)
    self:UpdateVisibility()
end

function Targets:OnRestored()
    setSetting("targetsMinimized", false)
    self:UpdateVisibility()
end

-- Panel and tray are mutually exclusive, and neither shows when there is
-- nothing to list — a lone tray button in an empty battleground would be noise.
function Targets:UpdateVisibility()
    local panel, tray = self._panel, self._tray
    if not panel then return end
    local counts = self._headerCounts or { enemy = 0, ally = 0 }
    -- Inside a battleground the panel always has something to say: even with
    -- nobody worth tracking on the board, the odds line belongs here. Staying
    -- visible is also what makes the odds reachable at all — this runs at the
    -- END of ApplyPlayers, which bails out early during combat lockdown, so a
    -- panel that is hidden when the fighting starts can never appear again
    -- until it ends.
    local hasRows = ((counts.enemy or 0) + (counts.ally or 0)) > 0
        or (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground())
    self:RenderTray()
    if not hasRows then
        panel:Hide()
        if tray then tray:Hide() end
    elseif self:IsMinimized() then
        panel:Hide()
        if tray then tray:Show() end
    else
        panel:Show()
        if tray then tray:Hide() end
    end
end

function Targets:ColumnSetting()
    local columns = tonumber(getSetting("targetsColumns", self.DEFAULT_COLUMNS)) or self.DEFAULT_COLUMNS
    columns = math.floor(columns)
    if columns < self.MIN_COLUMNS then columns = self.MIN_COLUMNS end
    if columns > self.MAX_COLUMNS then columns = self.MAX_COLUMNS end
    return columns
end

function Targets:ScaleSetting()
    local scale = tonumber(getSetting("targetsScale", 1.0)) or 1.0
    if scale < self.MIN_SCALE then scale = self.MIN_SCALE end
    if scale > self.MAX_SCALE then scale = self.MAX_SCALE end
    return scale
end

-- Scaling the panel drags its secure children along, so it waits for combat to
-- end rather than risking a blocked action. OnPlayerRegenEnabled applies this
-- before the roster, because that branch returns early.
function Targets:ApplyScale()
    local panel = self._panel
    if not panel then return false end
    if InCombatLockdown and InCombatLockdown() then
        self._pendingScale = true
        return false
    end
    self._pendingScale = nil
    local scale = self:ScaleSetting()
    if panel.SetScale then panel:SetScale(scale) end
    -- The tray follows the same setting: it is the panel while minimized.
    if self._tray and self._tray.SetScale then self._tray:SetScale(scale) end
    return true
end

-- Column width is measured, not assumed: `displayName` keeps the realm suffix,
-- and a name like Mæhælænæbæs-TwistingNether is far wider than the old fixed
-- 152px plate, which silently truncated it with an ellipsis.
function Targets:MeasureButtonWidth(players)
    local width = self.MIN_BUTTON_WIDTH
    local ruler = self._measure
    if not ruler or not ruler.SetText or not ruler.GetStringWidth then return width end
    for _, player in ipairs(players or {}) do
        ruler:SetText(labelText(player))
        local measured = ruler:GetStringWidth()
        if type(measured) == "number" then
            local needed = math.ceil(measured + self.LABEL_PADDING)
            if needed > width then width = needed end
        end
    end
    return width
end

local function splitSections(players)
    local grouped = { enemy = {}, ally = {} }
    for _, player in ipairs(players or {}) do
        local side = (player.side == "ally") and "ally" or "enemy"
        local list = grouped[side]
        list[#list + 1] = player
    end
    return grouped
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
            -- Plain FontStrings stay writable in lockdown, and the odds are
            -- the half of this panel that has to keep moving during a fight.
            self:RenderOdds()
        else
            -- The roster came back to what is already on the buttons. Any
            -- pending update is now obsolete — dropping it matters, because
            -- otherwise leaving combat would apply that older roster over a
            -- display that is already correct.
            self._pendingPlayers = nil
            self._pendingSignature = nil
            self:SetHeaderStale(false)
            self:RenderOdds()
        end
        return false
    end

    local count = math.min(#players, self.MAX_BUTTONS)
    local grouped = splitSections(players)
    local columns = self:ColumnSetting()
    local buttonWidth = self:MeasureButtonWidth(players)
    local index = 0
    local widestColumns = 0
    local y = self.HEADER_HEIGHT + self.PANEL_PADDING
    if self._forecast then y = y + self.ODDS_HEIGHT end

    for _, side in ipairs(SECTIONS) do
        local list = grouped[side]
        local sectionHeader = self._sectionHeaders[side]
        if #list > 0 and index < self.MAX_BUTTONS then
            if sectionHeader then
                sectionHeader:ClearAllPoints()
                sectionHeader:SetPoint("TOPLEFT", self._body, "TOPLEFT", self.PANEL_PADDING, -y)
                if side == "ally" then
                    sectionHeader:SetText(L["PremadeTargetsAllySection"] .. " (" .. #list .. ")")
                else
                    sectionHeader:SetText(L["PremadeTargetsEnemySection"] .. " (" .. #list .. ")")
                end
                sectionHeader:Show()
            end
            y = y + self.SECTION_HEADER_HEIGHT

            local layout, usedColumns, rows = Core.ComputeLayout(#list, columns)
            if usedColumns > widestColumns then widestColumns = usedColumns end
            for i, player in ipairs(list) do
                index = index + 1
                local button = self._buttons[index]
                if button then
                    local secureName = targetName(player.name)
                    local macro = Core.TargetMacro(secureName)
                    local focusMacro = Core.FocusMacro(secureName)
                    local pos = layout[i]
                    button:SetSize(buttonWidth, self.BUTTON_HEIGHT)
                    button:ClearAllPoints()
                    button:SetPoint(
                        "TOPLEFT",
                        self._body,
                        "TOPLEFT",
                        self.PANEL_PADDING + (pos.column - 1) * (buttonWidth + self.BUTTON_GAP),
                        -(y + (pos.row - 1) * (self.BUTTON_HEIGHT + self.BUTTON_GAP))
                    )
                    button:SetAttribute("type1", macro and "macro" or nil)
                    button:SetAttribute("macrotext1", macro)
                    button:SetAttribute("type2", focusMacro and "macro" or nil)
                    button:SetAttribute("macrotext2", focusMacro)
                    button.playerInfo = player
                    applyIdleStyle(button)
                    button.label:SetText(labelText(player))
                    local color = player.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[player.classToken]
                    if color then
                        button.label:SetTextColor(color.r, color.g, color.b)
                    else
                        button.label:SetTextColor(0.92, 0.92, 0.92)
                    end
                    button:Show()
                end
            end
            y = y + rows * self.BUTTON_HEIGHT
                + math.max(0, rows - 1) * self.BUTTON_GAP
                + self.SECTION_GAP
        elseif sectionHeader then
            sectionHeader:Hide()
        end
    end

    for i = index + 1, #self._buttons do
        local button = self._buttons[i]
        -- Only clear buttons that actually carry something: with an 80-strong
        -- pool the blind version issued hundreds of pointless SetAttribute calls
        -- on every scan, and scans run up to once a second.
        if button.playerInfo then
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
    self._headerCounts = { enemy = #grouped.enemy, ally = #grouped.ally }
    -- Cleared on BOTH branches below, including the hidden/zero-player one, so
    -- the marker can never survive a successful application.
    self._headerStale = false

    if count > 0 then
        local width = math.max(
            self.PANEL_PADDING * 2
                + widestColumns * buttonWidth
                + math.max(0, widestColumns - 1) * self.BUTTON_GAP,
            self.MIN_PANEL_WIDTH
        )
        self._panel:SetSize(width, y - self.SECTION_GAP + self.PANEL_PADDING)
    else
        -- Nobody to list, but the panel still carries the odds. Height is the
        -- header plus that one line; without this the frame keeps whatever
        -- size the last populated roster left it at.
        self._panel:SetSize(self.MIN_PANEL_WIDTH,
                            self.HEADER_HEIGHT + self.ODDS_HEIGHT + self.PANEL_PADDING)
    end
    self:RenderHeader()
    self:RenderOdds()
    -- Never a bare Show(): the panel stays hidden while the user has it
    -- minimized, otherwise the next scoreboard tick would pop it back open.
    self:UpdateVisibility()
    return true
end

-- Header is a FontString on a NON-secure frame, so SetText/SetTextColor stay
-- legal in combat lockdown — that is what lets us flag a deferred update while
-- the secure buttons themselves cannot be touched, and what keeps the counts
-- readable while the body is collapsed. Always re-rendered from the base string
-- + counts so the marker can never be appended twice.
function Targets:RenderHeader()
    local panel = self._panel
    if not panel or not panel.header then return end
    local counts = self._headerCounts or { enemy = 0, ally = 0 }
    -- A side with nobody on it is left out entirely rather than printed as
    -- "enemy 0" — the panel below already omits that section.
    local parts = {}
    if (counts.enemy or 0) > 0 then
        parts[#parts + 1] = L["PremadeTargetsEnemyShort"] .. " " .. counts.enemy
    end
    if (counts.ally or 0) > 0 then
        parts[#parts + 1] = L["PremadeTargetsAllyShort"] .. " " .. counts.ally
    end
    local text = L["PremadeTargetsHeader"]
    if #parts > 0 then text = text .. ": " .. table.concat(parts, ", ") end
    if self._headerStale then
        panel.header:SetText(text .. " " .. STALE_MARK)
        panel.header:SetTextColor(0.80, 0.66, 0.28)
    else
        panel.header:SetText(text)
        panel.header:SetTextColor(1, 0.82, 0.15)
    end
end

-- Win chances for this match, under the header.
--
-- This panel is the right home for them: it is already on screen for the whole
-- battleground and it does not fade, unlike the premade banner — which appears
-- once, early, and often before the enemy half of the scoreboard has even
-- loaded (so the forecast has nothing to say at that moment).
--
-- Like the header, a plain FontString on the non-secure panel, so SetText stays
-- legal in combat lockdown.
function Targets:RenderOdds()
    local panel = self._panel
    if not panel or not panel.odds then return end
    local f = self._forecast
    if not f then
        -- Inside a battleground the panel stays up, so say why the number is
        -- missing instead of leaving a bare header: the scoreboard fills over
        -- the opening minute, and silence there reads as "broken".
        if C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground() then
            panel.odds:SetText(L["ForecastPending"])
            panel.odds:SetTextColor(0.55, 0.55, 0.55)
            panel.odds:Show()
        else
            panel.odds:Hide()
        end
        if panel.oddsHit then panel.oddsHit:Hide() end
        return
    end
    -- Two states, and the difference matters: until the scoreboard settles the
    -- number is still moving, and once locked it is the one the model was
    -- actually calibrated for.
    local key = self._forecastLocked and "ForecastPanelDone" or "ForecastPanelWorking"
    panel.odds:SetText(L[key]:format(
        f.us, f.them,
        math.floor(f.ourWr + 0.5), math.floor(f.theirWr + 0.5),
        math.floor(f.ourNew + 0.5), math.floor(f.theirNew + 0.5)))
    if f.us >= 50 then
        panel.odds:SetTextColor(0.25, 0.88, 0.44)
    else
        panel.odds:SetTextColor(0.98, 0.48, 0.52)
    end
    panel.odds:Show()
    if panel.oddsHit then panel.oddsHit:Show() end
end

-- Recompute from the rows this scan already read. Free: the scoreboard pass and
-- its throttling are the panel's, and the forecast is arithmetic over names.
--
-- Claiming the "already delivered" slot keeps the standalone panel from saying
-- the same thing twice — it exists for matches where this panel never appears.
-- Scans with no growth in the scoreboard before the forecast is locked. The
-- panel scans about every two seconds, so this is roughly fifteen seconds of a
-- board that has stopped filling.
local FORECAST_STABLE_SCANS = 8

function Targets:UpdateForecast(rows, side)
    if not ns.Forecast then return end
    if getSetting("forecast", true) == false then
        if self._forecast ~= nil then self._signature = nil end
        self._forecast = nil
        return
    end
    -- Locked: the number was computed on the roster the model was calibrated
    -- for, and re-computing it later would quietly turn a forecast into a
    -- description.
    --
    -- The model is fitted on STARTING rosters (match_baseline_rows). Applying
    -- it to a mid-battle scoreboard is applying it outside the ground it was
    -- measured on — and the drift flatters us: the losing side empties out
    -- first, so the number would creep toward an outcome that is already
    -- visible on the objectives, and look prescient for it.
    if self._forecastLocked then return end

    local seen = #rows
    if seen > (self._forecastPeakRows or 0) then
        self._forecastPeakRows = seen
        self._forecastStable = 0
    else
        self._forecastStable = (self._forecastStable or 0) + 1
    end

    local before = self._forecast
    self._forecast = ns.Forecast:ForMatch(rows, side)
    if self._forecast then ns.Forecast:MarkShown() end

    -- Lock once the board has a forecast AND has stopped growing: either it sat
    -- still for long enough, or it started SHRINKING, which means people are
    -- leaving and the starting roster is already gone.
    if self._forecast
        and ((self._forecastStable or 0) >= FORECAST_STABLE_SCANS
             or seen < (self._forecastPeakRows or 0)) then
        self._forecastLocked = true
        self._signature = nil          -- the label changes, so re-render
    end

    -- Appearing or disappearing changes the layout, so a scan that only moved
    -- the odds still has to re-apply. ApplyPlayers is signature-guarded and
    -- would otherwise skip it.
    if (before == nil) ~= (self._forecast == nil) then self._signature = nil end
end

-- New match: the previous one's number must not carry over, and the lock has
-- to open again.
function Targets:ResetForecast()
    self._forecast = nil
    self._forecastLocked = nil
    self._forecastPeakRows = nil
    self._forecastStable = nil
    self._signature = nil
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

-- The owner's personal watchlist, as a lookup for the roster filter.
--
-- Rebuilt on every scan on purpose — NOT cached like the catalog above. That
-- cache is keyed on the catalog's generated_at, which an edit to this list does
-- not touch, so a cached watch index would never pick up a newly added name (and
-- on a client running the neutral stub catalog, generated_at is 0 forever).
-- The list is capped at Core.WATCH_MAX entries, so rebuilding costs nothing.
--
-- Read defensively: PremadeTargets handles ADDON_LOADED BEFORE Main.lua does
-- (load order in the .toc), so nothing may assume some Init has run.
function Targets:WatchIndex(realm)
    local watch = type(PremadeIQ_Watch) == "table" and PremadeIQ_Watch or nil
    if not watch then return nil end
    return Core.WatchIndex(watch, realm)
end

-- `requestData` asks the server for a fresh scoreboard; without it we only read
-- the cache the client already holds. The UPDATE_BATTLEFIELD_SCORE handler
-- consumes without requesting, so a response can never be swallowed by the
-- scan throttle that our own request had just armed.
function Targets:RefreshFromScoreboard(force, requestData)
    if not self:Initialize() then return false end
    if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        -- Out of the battleground: drop the odds too, or the next match opens
        -- showing the previous one's chances.
        self:ResetForecast()
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
            if not secret(name) and type(name) == "string" and name ~= "" then
                rows[#rows + 1] = {
                    name = name,
                    faction = not secret(faction) and faction or nil,
                    classToken = not secret(classToken) and classToken or nil,
                }
            end
        end
    end

    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    -- Odds first: they need the raw rows, and they must be computed even when
    -- the roster filter below finds nobody worth listing.
    self:UpdateForecast(rows, currentSide())
    -- Built BEFORE the pcall, not inside its argument list. An argument is
    -- evaluated by the caller, so a throw in RebuildCatalog escaped the pcall
    -- entirely, skipped the `_scanning = false` below, and left the re-entry
    -- guard latched — one bad catalog silently killed every later scan until
    -- /reload. Any error in here now lands in the pcall like the rest.
    local ok, catalogIndex = pcall(self.RebuildCatalog, self)
    if not ok then
        self._scanning = false
        return false
    end
    -- Clear _scanning even if filtering or application throws: leaving it set
    -- would wedge every future scan behind the re-entry guard above.
    local players
    ok, players = pcall(
        Core.FilterRoster, rows, catalogIndex, currentSide(), realm,
        ownCanonicalName(realm), self:WatchIndex(realm)
    )
    self._scanning = false
    if not ok then return false end
    return self:ApplyPlayers(players)
end

function Targets:OnPlayerRegenEnabled()
    if self._needsInitialize then self:Initialize() end
    -- Before the roster branch: that one returns early, and a scale change
    -- parked during combat would otherwise be dropped on the floor.
    if self._pendingScale then self:ApplyScale() end
    if self._pendingPlayers then
        local players = self._pendingPlayers
        self._pendingPlayers = nil
        self._pendingSignature = nil
        return self:ApplyPlayers(players)
    end
    return self:RefreshFromScoreboard(true, true)
end

-- Re-apply the current roster with new sizing settings. Out of combat only;
-- the options panel is the sole caller.
function Targets:RefreshLayout()
    if not self._panel then return false end
    self:ApplyScale()
    if InCombatLockdown and InCombatLockdown() then return false end
    -- The buttons already carry this roster, so the signature would suppress a
    -- plain re-apply: clear it to force the geometry through.
    self._signature = ""
    return self:ApplyPlayers(self._players or {})
end

function Targets:AdjustScale(delta)
    local value = self:ScaleSetting() + (tonumber(delta) or 0) * self.SCALE_STEP
    -- Round to the step so repeated clicks cannot drift into 0.8500000001.
    value = math.floor(value * 100 + 0.5) / 100
    if value < self.MIN_SCALE then value = self.MIN_SCALE end
    if value > self.MAX_SCALE then value = self.MAX_SCALE end
    setSetting("targetsScale", value)
    self:RefreshLayout()
    return value
end

function Targets:AdjustColumns(delta)
    local value = self:ColumnSetting() + (tonumber(delta) or 0)
    if value < self.MIN_COLUMNS then value = self.MIN_COLUMNS end
    if value > self.MAX_COLUMNS then value = self.MAX_COLUMNS end
    setSetting("targetsColumns", value)
    self:RefreshLayout()
    return value
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
        Targets:ResetForecast()
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
