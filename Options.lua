local ADDON, ns = ...
local L = ns.L

-- ----------------------------------------------------------------------
-- Settings panel — Esc → Options → AddOns → PremadeIQ
--
-- Custom canvas layout (full control over the body) registered through
-- the modern Settings API. ``Settings.RegisterCanvasLayoutCategory`` was
-- added in 10.0 and is the only supported path on retail 11.0+; the old
-- InterfaceOptions_AddCategory is gone in Midnight.
--
-- All controls bind directly to ``ns.Privacy`` and ``ns.Database`` —
-- changes take effect immediately, no Apply button. The OnShow hook
-- refreshes everything from current state, so opening the panel always
-- reflects the live SavedVariables.
-- ----------------------------------------------------------------------

-- Explicit grid. Everything in this file starts at LEFT_MARGIN, and the left
-- column has to stop before the right one begins — the two used to be implied by
-- scattered magic numbers, which is how a 300-unit drift went unnoticed.
local LEFT_MARGIN    = 16
local RIGHT_COLUMN_X = 350
local COLUMN_GUTTER  = 14
local LEFT_COLUMN_W  = RIGHT_COLUMN_X - LEFT_MARGIN - COLUMN_GUTTER   -- 320
local STEPPER_ROW_H  = 24

local panel = CreateFrame("Frame", "PremadeIQOptionsPanel", UIParent)
panel:Hide()
panel.name = "PremadeIQ"  -- legacy field, still read in some code paths

-- Title block
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("PremadeIQ")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetPoint("RIGHT", -16, 0)
subtitle:SetJustifyH("LEFT")
subtitle:SetTextColor(0.7, 0.7, 0.7)

-- ---- Language ------------------------------------------------------
-- The addon follows the game client by default. This exists because the owner
-- runs a Russian client while 45% of the people using the addon read English:
-- without it there is no way to see, or screenshot, what they actually get.
local languageRow

local function cycleLanguage(delta)
    local codes = ns.LANGUAGE_CODES or { "auto" }
    local current = (ns.Database and ns.Database:GetSetting("language")) or "auto"
    local index = 1
    for i, code in ipairs(codes) do
        if code == current then index = i break end
    end
    index = index + delta
    if index < 1 then index = #codes elseif index > #codes then index = 1 end
    local chosen = codes[index]
    if ns.Database then ns.Database:SetSetting("language", chosen) end
    if ns.ApplyLanguage then ns.ApplyLanguage(chosen) end
    -- Re-label this very panel immediately. Everything else in the addon reads
    -- the dictionary lazily, so it needs no prompting.
    if panel.ApplyStrings then panel:ApplyStrings() end
end

-- ---- Debug checkbox -------------------------------------------------
local cbDebug = CreateFrame("CheckButton", "PremadeIQDebugCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbDebug:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
cbDebug:SetScript("OnClick", function(self)
    ns.Database:SetSetting("debug", self:GetChecked() and true or false)
end)

-- ---- Premade alert checkbox -----------------------------------------
-- Defaults ON: unset (nil) is treated as enabled, so the checkbox reads
-- ``~= false``. Stored false only when the user explicitly disables it.
local cbPremade = CreateFrame("CheckButton", "PremadeIQPremadeCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbPremade:SetPoint("TOPLEFT", cbDebug, "BOTTOMLEFT", 0, -4)
cbPremade:SetScript("OnClick", function(self)
    ns.Database:SetSetting("premadeAlert", self:GetChecked() and true or false)
end)

-- ---- Premade sound checkbox -----------------------------------------
local cbPremadeSound = CreateFrame("CheckButton", "PremadeIQPremadeSoundCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbPremadeSound:SetPoint("TOPLEFT", cbPremade, "BOTTOMLEFT", 0, -4)
cbPremadeSound:SetScript("OnClick", function(self)
    ns.Database:SetSetting("premadeSound", self:GetChecked() and true or false)
end)

-- ---- Win-chance line checkbox ---------------------------------------
-- Defaults ON, like the alert above. Not a performance switch — the whole
-- forecast is ~1 MB of cached winrates and a fraction of a millisecond per
-- scan, on rows the panel already read. It is here because a probability on
-- screen is a matter of taste: some people want the read, others want to play
-- the battleground without one.
local cbForecast = CreateFrame("CheckButton", "PremadeIQForecastCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbForecast:SetPoint("TOPLEFT", cbPremadeSound, "BOTTOMLEFT", 0, -4)
cbForecast:SetScript("OnClick", function(self)
    ns.Database:SetSetting("forecast", self:GetChecked() and true or false)
    -- Apply immediately: waiting for the next scoreboard scan would look like
    -- the switch did nothing.
    if ns.PremadeTargets then
        ns.PremadeTargets:ResetForecast()
        ns.PremadeTargets:RenderOdds()
    end
end)

-- ---- Minimap button checkbox ----------------------------------------
-- Minimap buttons are a matter of taste, and an argument costs more than a
-- checkbox. Defaults ON: only an explicit false hides it.
local cbMinimap = CreateFrame("CheckButton", "PremadeIQMinimapCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbMinimap:SetPoint("TOPLEFT", cbForecast, "BOTTOMLEFT", 0, -4)
cbMinimap:SetScript("OnClick", function(self)
    if ns.MinimapButton then ns.MinimapButton:SetShown(self:GetChecked()) end
end)

-- ---- Targets panel sizing -------------------------------------------
-- Stepper rows rather than sliders or a dropdown: UIDropDownMenu is gone in
-- retail 11.0+, and UIPanelButtonTemplate is the one control this file already
-- proves is alive. Values are read lazily inside refreshTargetsRow / OnShow —
-- never at file scope, where ns.Database.db does not exist yet.
local targetsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
targetsHeader:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 0, -24)
targetsHeader:SetTextColor(1, 0.82, 0)

-- A row is a real Frame spanning the whole left column, with the caption and the
-- buttons INSIDE it.
--
-- It used to hand back the minus button as `anchorFrame`, and that button sits
-- 150 units right of the caption — so every block that anchored to a row started
-- 150 further right than the one above, and the drift accumulated: the columns
-- row landed at +150, its buttons at +300, and the stats/reset/links blocks
-- inherited +300 and collided with the watchlist column. Anchoring to the row
-- itself is what keeps the column a column.
--
-- The height is not decoration: a Frame without one is 0 tall, BOTTOMLEFT equals
-- TOPLEFT, and the rows would stack on top of each other instead.
-- Rows register here so applyStrings() can re-label them after a language
-- change; their caption and tooltip live inside the helper, out of its reach.
local stepperRows = {}

-- `labelKey`/`tooltipKey` are locale KEYS, not finished strings: a row built
-- from a resolved string would freeze the language the same way the rest of this
-- panel used to. `getValue` takes no arguments — the previous signature passed
-- ns.PremadeTargets in, which is meaningless for a row that is not about the
-- targets panel and rendered "-" whenever that module had not come up.
local function makeStepperRow(anchor, offsetY, labelKey, tooltipKey, onStep, getValue,
                              valueWidth)
    local row = { labelKey = labelKey, tooltipKey = tooltipKey,
                  getValue = getValue, onStep = onStep, valueWidth = valueWidth }
    stepperRows[#stepperRows + 1] = row

    local frame = CreateFrame("Frame", nil, panel)
    frame:SetSize(LEFT_COLUMN_W, STEPPER_ROW_H)
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)

    local caption = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    caption:SetPoint("LEFT", frame, "LEFT", 0, 0)
    caption:SetJustifyH("LEFT")
    row.caption = caption

    local minus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("LEFT", frame, "LEFT", 150, 0)
    minus:SetText("-")

    local value = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 8, 0)
    -- 56 fits "150%" and "6"; language names do not. Callers that show words
    -- pass their own width rather than having the label clipped or run under
    -- the plus button.
    value:SetWidth(row.valueWidth or 56)
    value:SetJustifyH("CENTER")
    row.value = value

    local plus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("LEFT", value, "RIGHT", 8, 0)
    plus:SetText("+")

    row.frame = frame
    row.anchorFrame = frame

    function row:Refresh()
        self.value:SetText(self.getValue() or "-")
    end

    -- Caption and tooltip re-read the dictionary, so a language switch lands
    -- here too when the panel is next opened.
    function row:RefreshText()
        self.caption:SetText(L[self.labelKey])
        for _, button in ipairs({ minus, plus }) do
            button.tooltipText = L[self.tooltipKey]
        end
    end

    minus:SetScript("OnClick", function() row.onStep(-1); row:Refresh() end)
    plus:SetScript("OnClick", function() row.onStep(1); row:Refresh() end)
    for _, button in ipairs({ minus, plus }) do
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L[row.tooltipKey], nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return row
end

local scaleRow = makeStepperRow(
    targetsHeader, -10, "OptTargetsScale", "OptTargetsScaleTooltip",
    function(delta)
        if ns.PremadeTargets then ns.PremadeTargets:AdjustScale(delta) end
    end,
    function()
        local t = ns.PremadeTargets
        if not t then return nil end
        return ("%d%%"):format(math.floor(t:ScaleSetting() * 100 + 0.5))
    end
)

local columnsRow = makeStepperRow(
    scaleRow.anchorFrame, -2, "OptTargetsColumns", "OptTargetsColumnsTooltip",
    function(delta)
        if ns.PremadeTargets then ns.PremadeTargets:AdjustColumns(delta) end
    end,
    function()
        local t = ns.PremadeTargets
        return t and tostring(t:ColumnSetting()) or nil
    end
)

-- Language sits at the TOP of the panel, under the subtitle — it governs the
-- whole addon, not the targets panel this helper was written for. It is built
-- down here only because makeStepperRow has to exist first; the checkbox column
-- is re-anchored below it so the reading order still matches the screen.
languageRow = makeStepperRow(
    subtitle, -14, "OptLanguage", "OptLanguageTooltip",
    cycleLanguage,
    function()
        local code = (ns.Database and ns.Database:GetSetting("language")) or "auto"
        local names = ns.LANGUAGE_NAMES or {}
        return names[code] or code
    end,
    120
)
cbDebug:SetPoint("TOPLEFT", languageRow.anchorFrame, "BOTTOMLEFT", 0, -10)

-- ---- Stats block ----------------------------------------------------
local statsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
statsHeader:SetPoint("TOPLEFT", columnsRow.anchorFrame, "BOTTOMLEFT", 0, -20)
statsHeader:SetTextColor(1, 0.82, 0)

local statsBody = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
statsBody:SetPoint("TOPLEFT", statsHeader, "BOTTOMLEFT", 0, -6)
statsBody:SetWidth(LEFT_COLUMN_W)
statsBody:SetJustifyH("LEFT")
statsBody:SetSpacing(2)

-- ---- Reset button ---------------------------------------------------
local btnReset = CreateFrame("Button", "PremadeIQResetBtn", panel,
    "UIPanelButtonTemplate")
btnReset:SetPoint("TOPLEFT", statsBody, "BOTTOMLEFT", 0, -10)
btnReset:SetSize(180, 22)
btnReset:SetScript("OnClick", function()
    StaticPopup_Show("PREMADEIQ_OPTIONS_RESET")
end)

StaticPopupDialogs["PREMADEIQ_OPTIONS_RESET"] = {
    text       = L["OptResetConfirm"],
    button1    = YES,
    button2    = NO,
    OnAccept   = function()
        PremadeIQ_DB = nil
        ns.Database:Init()
        ns.Privacy:Init()
        print("|cff33ff99PremadeIQ|r " .. L["DB reset"])
        -- The wipe takes the minimap angle and toggle with it. Without this the
        -- button keeps its old position for the session and then snaps to the
        -- default on the next login, with nothing to explain why.
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
        if panel:IsShown() then
            local h = panel:GetScript("OnShow")
            if h then h(panel) end
        end
    end,
    timeout       = 0,
    whileDead     = true,
    hideOnEscape  = true,
    preferredIndex = 3,
}

-- ---- Links / version footer ----------------------------------------
local linksHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
linksHeader:SetPoint("TOPLEFT", btnReset, "BOTTOMLEFT", 0, -20)
linksHeader:SetTextColor(1, 0.82, 0)

local linksBody = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
linksBody:SetPoint("TOPLEFT", linksHeader, "BOTTOMLEFT", 0, -6)
linksBody:SetWidth(LEFT_COLUMN_W)
linksBody:SetNonSpaceWrap(true)
linksBody:SetJustifyH("LEFT")
linksBody:SetSpacing(2)

local versionTxt = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
versionTxt:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 12)
versionTxt:SetText(("v%s"):format(ns.VERSION or "?"))

-- ---- Personal watchlist ----------------------------------------------
-- Players the owner of THIS client chose to keep an eye on. Local only: it
-- lives in its own SavedVariable, the uploader's parser is anchored to
-- PremadeIQ_DB and never reaches it, and nothing here feeds the premade
-- verdict, the counters or the catalog.
--
-- Lives in a RIGHT COLUMN, not below the existing controls: the Settings canvas
-- is roughly 665x568 and does not scroll, and the left column already reaches
-- y ~= -440. A block appended underneath would simply be off-screen.
--
-- Everything is read lazily (OnShow / on click), never at file scope:
-- SavedVariables are not populated yet while these Lua files execute.
local watchHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
watchHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_COLUMN_X, -56)
watchHeader:SetTextColor(1, 0.82, 0)

local watchHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
watchHint:SetPoint("TOPLEFT", watchHeader, "BOTTOMLEFT", 0, -6)
watchHint:SetWidth(290)
watchHint:SetJustifyH("LEFT")
watchHint:SetSpacing(2)

local watchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
watchBox:SetSize(200, 20)
watchBox:SetPoint("TOPLEFT", watchHint, "BOTTOMLEFT", 6, -10)
watchBox:SetAutoFocus(false)
watchBox:SetMaxLetters(64)

local watchAdd = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
watchAdd:SetSize(72, 22)
watchAdd:SetPoint("LEFT", watchBox, "RIGHT", 8, 0)

local watchStatus = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
watchStatus:SetPoint("TOPLEFT", watchBox, "BOTTOMLEFT", -6, -6)
watchStatus:SetWidth(290)
watchStatus:SetJustifyH("LEFT")

-- Scrolling list: the cap is 200 entries, which no fixed-height frame can show.
-- Named on purpose: UIPanelScrollFrameTemplate declares its scrollbar as
-- "$parentScrollBar", and $parent on an anonymous frame has nothing to expand to.
local watchScroll = CreateFrame("ScrollFrame", "PremadeIQWatchScroll", panel,
                                "UIPanelScrollFrameTemplate")
watchScroll:SetPoint("TOPLEFT", watchStatus, "BOTTOMLEFT", 6, -8)
watchScroll:SetSize(270, 300)

watchScroll.scrollBarHideable = true

local watchContent = CreateFrame("Frame", nil, watchScroll)
watchContent:SetSize(270, 300)
watchScroll:SetScrollChild(watchContent)

local watchRows = {}

local function watchTable()
    if type(PremadeIQ_Watch) ~= "table" then
        PremadeIQ_Watch = { version = 1, players = {} }
    end
    if type(PremadeIQ_Watch.players) ~= "table" then
        PremadeIQ_Watch.players = {}
    end
    return PremadeIQ_Watch
end

-- The panel is built from secure buttons, so a roster change cannot be applied
-- during combat. RefreshFromScoreboard is the right door: unlike RefreshLayout
-- it is not gated on combat, and ApplyPlayers defers the secure work itself and
-- replays it on PLAYER_REGEN_ENABLED. Calling RefreshLayout here would be a
-- silent no-op for the whole fight.
local function watchApply()
    local targets = ns.PremadeTargets
    if targets and targets.RefreshFromScoreboard then
        targets:RefreshFromScoreboard(true, false)
    end
end

local refreshWatch

local function watchRow(i)
    local row = watchRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, watchContent)
    row:SetSize(250, 18)
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWidth(210)
    row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.del:SetSize(20, 20)
    row.del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.del:SetScript("OnClick", function(self)
        local Core = ns.PremadeTargetsCore
        if Core and Core.RemoveWatch(watchTable(), self.key) then
            refreshWatch()
            watchApply()
        end
    end)
    watchRows[i] = row
    return row
end

refreshWatch = function()
    local Core = ns.PremadeTargetsCore
    if not Core then return end
    local watch = watchTable()
    local keys = Core.WatchList(watch)
    local y = 0
    for i, key in ipairs(keys) do
        local row = watchRow(i)
        row.key = key
        row.del.key = key
        row.text:SetText(key)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", watchContent, "TOPLEFT", 0, -y)
        row:Show()
        y = y + 18
    end
    for i = #keys + 1, #watchRows do
        watchRows[i]:Hide()
    end
    watchContent:SetHeight(math.max(y, 1))
    watchStatus:SetText(("%s: |cffffffff%d|r / %d"):format(
        L["OptWatchCount"], #keys, Core.WATCH_MAX))
end

local function watchSubmit()
    local Core = ns.PremadeTargetsCore
    if not Core then return end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    local ok, info = Core.AddWatch(watchTable(), watchBox:GetText(), realm)
    if ok then
        watchBox:SetText("")
        refreshWatch()
        watchApply()
    else
        local msg = (info == "duplicate" and L["OptWatchDuplicate"])
                 or (info == "full" and L["OptWatchFull"])
                 or L["OptWatchBadName"]
        watchStatus:SetText("|cffff8080" .. msg .. "|r")
    end
    watchBox:ClearFocus()
end

watchAdd:SetScript("OnClick", watchSubmit)
watchBox:SetScript("OnEnterPressed", watchSubmit)
watchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Every visible string, applied from the CURRENT language.
--
-- These used to be set once at file scope, which froze them to whatever
-- language the game client had at load. A /reload does not fix that: it
-- repeats the same order (files execute, then SavedVariables, then
-- ADDON_LOADED), so the panel would keep rebuilding itself in the client's
-- language — including, absurdly, the language picker itself.
function panel:ApplyStrings()
    subtitle:SetText(L["OptionsSubtitle"])
    cbDebug.Text:SetText(L["OptDebug"])
    cbPremade.Text:SetText(L["OptPremadeAlert"])
    cbPremadeSound.Text:SetText(L["OptPremadeSound"])
    cbForecast.Text:SetText(L["OptForecast"])
    cbMinimap.Text:SetText(L["OptMinimapButton"])
    targetsHeader:SetText(L["OptTargetsHeader"])
    statsHeader:SetText(L["OptStatsHeader"])
    btnReset:SetText(L["OptResetBtn"])
    linksHeader:SetText(L["OptLinksHeader"])
    watchHeader:SetText(L["OptWatchHeader"])
    watchHint:SetText(L["OptWatchHint"])
    watchAdd:SetText(L["OptWatchAdd"])
    cbDebug.tooltipText = L["OptDebugTooltip"]
    cbPremade.tooltipText = L["OptPremadeAlertTooltip"]
    cbPremadeSound.tooltipText = L["OptPremadeSoundTooltip"]
    cbForecast.tooltipText = L["OptForecastTooltip"]
    cbMinimap.tooltipText = L["OptMinimapButtonTooltip"]
    linksBody:SetText(L["UploaderURL"] .. "\n" .. L["DiscordURL"])
    for _, row in ipairs(stepperRows) do row:RefreshText() end
end
local function applyStrings() panel:ApplyStrings() end

-- ---- Refresh on show ------------------------------------------------
panel:SetScript("OnShow", function()
    applyStrings()
    cbDebug:SetChecked(ns.Database and ns.Database:GetSetting("debug") == true)
    -- Premade toggles default ON: only an explicit ``false`` unchecks them.
    cbPremade:SetChecked(not ns.Database or ns.Database:GetSetting("premadeAlert") ~= false)
    cbPremadeSound:SetChecked(not ns.Database or ns.Database:GetSetting("premadeSound") ~= false)
    cbForecast:SetChecked(not ns.Database or ns.Database:GetSetting("forecast") ~= false)
    cbMinimap:SetChecked(not ns.Database
        or ns.Database:GetSetting("minimapButton") ~= false)
    languageRow:Refresh()
    scaleRow:Refresh()
    columnsRow:Refresh()

    local players = ns.Database and ns.Database:CountPlayers() or 0
    local samples = ns.Database and ns.Database:CountSamples() or 0
    local matches = (ns.Database and ns.Database.db
                     and ns.Database.db.matches and ns.Database.db.matches.count) or 0
    statsBody:SetText(
        ("%s: |cffffffff%d|r\n%s: |cffffffff%d|r\n%s: |cffffffff%d|r"):format(
            L["Players in DB"], players,
            L["Samples"],       samples,
            L["Matches"],       matches))
    versionTxt:SetText(("v%s"):format(ns.VERSION or "?"))
    refreshWatch()
end)

-- ---- Register with the modern Settings API -------------------------
-- Do NOT overwrite category.ID with a string — Settings.RegisterCanvas…
-- auto-assigns a numeric id, and ``Settings.OpenToCategory`` ultimately
-- calls C_SettingsUtil.OpenSettingsPanel(id) which only accepts ints
-- (range -2147483648..2147483647). Pinning a string ID raised
--   bad argument #1 to 'OpenSettingsPanel' … outside expected range
-- on /piq options. We just hold on to the category object itself.
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "PremadeIQ")
    Settings.RegisterAddOnCategory(category)
    ns._OptionsCategory = category
end

-- Programmatic open — used by /piq options.
function ns.OpenOptions()
    if Settings and Settings.OpenToCategory and ns._OptionsCategory then
        -- Pass the numeric id from GetID(), not the category object —
        -- OpenToCategory in retail 11.0+ forwards directly to
        -- OpenSettingsPanel which is strict about the type.
        Settings.OpenToCategory(ns._OptionsCategory:GetID())
    end
end
