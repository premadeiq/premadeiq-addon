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
subtitle:SetText(L["OptionsSubtitle"])
subtitle:SetTextColor(0.7, 0.7, 0.7)

-- ---- Debug checkbox -------------------------------------------------
local cbDebug = CreateFrame("CheckButton", "PremadeIQDebugCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbDebug:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
cbDebug.Text:SetText(L["OptDebug"])
cbDebug.tooltipText = L["OptDebugTooltip"]
cbDebug:SetScript("OnClick", function(self)
    ns.Database:SetSetting("debug", self:GetChecked() and true or false)
end)

-- ---- Premade alert checkbox -----------------------------------------
-- Defaults ON: unset (nil) is treated as enabled, so the checkbox reads
-- ``~= false``. Stored false only when the user explicitly disables it.
local cbPremade = CreateFrame("CheckButton", "PremadeIQPremadeCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbPremade:SetPoint("TOPLEFT", cbDebug, "BOTTOMLEFT", 0, -4)
cbPremade.Text:SetText(L["OptPremadeAlert"])
cbPremade.tooltipText = L["OptPremadeAlertTooltip"]
cbPremade:SetScript("OnClick", function(self)
    ns.Database:SetSetting("premadeAlert", self:GetChecked() and true or false)
end)

-- ---- Premade sound checkbox -----------------------------------------
local cbPremadeSound = CreateFrame("CheckButton", "PremadeIQPremadeSoundCB", panel,
    "InterfaceOptionsCheckButtonTemplate")
cbPremadeSound:SetPoint("TOPLEFT", cbPremade, "BOTTOMLEFT", 0, -4)
cbPremadeSound.Text:SetText(L["OptPremadeSound"])
cbPremadeSound.tooltipText = L["OptPremadeSoundTooltip"]
cbPremadeSound:SetScript("OnClick", function(self)
    ns.Database:SetSetting("premadeSound", self:GetChecked() and true or false)
end)

-- ---- Stats block ----------------------------------------------------
local statsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
statsHeader:SetPoint("TOPLEFT", cbPremadeSound, "BOTTOMLEFT", 0, -24)
statsHeader:SetText(L["OptStatsHeader"])
statsHeader:SetTextColor(1, 0.82, 0)

local statsBody = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
statsBody:SetPoint("TOPLEFT", statsHeader, "BOTTOMLEFT", 0, -6)
statsBody:SetJustifyH("LEFT")
statsBody:SetSpacing(2)

-- ---- Reset button ---------------------------------------------------
local btnReset = CreateFrame("Button", "PremadeIQResetBtn", panel,
    "UIPanelButtonTemplate")
btnReset:SetPoint("TOPLEFT", statsBody, "BOTTOMLEFT", 0, -10)
btnReset:SetSize(180, 22)
btnReset:SetText(L["OptResetBtn"])
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
linksHeader:SetText(L["OptLinksHeader"])
linksHeader:SetTextColor(1, 0.82, 0)

local linksBody = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
linksBody:SetPoint("TOPLEFT", linksHeader, "BOTTOMLEFT", 0, -6)
linksBody:SetJustifyH("LEFT")
linksBody:SetSpacing(2)
linksBody:SetText(
    L["UploaderURL"] .. "\n" ..
    L["DiscordURL"]
)

local versionTxt = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
versionTxt:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 12)
versionTxt:SetText(("v%s"):format(ns.VERSION or "?"))

-- ---- Refresh on show ------------------------------------------------
panel:SetScript("OnShow", function()
    cbDebug:SetChecked(ns.Database and ns.Database:GetSetting("debug") == true)
    -- Premade toggles default ON: only an explicit ``false`` unchecks them.
    cbPremade:SetChecked(not ns.Database or ns.Database:GetSetting("premadeAlert") ~= false)
    cbPremadeSound:SetChecked(not ns.Database or ns.Database:GetSetting("premadeSound") ~= false)

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
