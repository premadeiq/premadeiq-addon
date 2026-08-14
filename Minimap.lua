local ADDON, ns = ...
local L = ns.L

-- ----------------------------------------------------------------------
-- Minimap button — a way into the settings without typing /piq options.
--
-- Hand-rolled rather than LibDBIcon: that would pull in LibDataBroker too, and
-- both would have to be vendored into Libs/, registered in Libs.xml, carried
-- into the public mirror and the packager. The whole button is under a hundred
-- lines, so the dependencies are not worth it.
--
-- The addon ALSO registers ## AddonCompartmentFunc in the .toc, which is
-- Blizzard's own supported entry point and costs nothing. Between the two,
-- someone who hates minimap buttons can switch this one off and still reach the
-- settings from the addon menu.
-- ----------------------------------------------------------------------

local BUTTON_SIZE  = 32
local ICON_SIZE    = 20
local DEFAULT_ANGLE = 200      -- degrees; lower-left, where WoW's own buttons sit

local rad, deg = math.rad, math.deg
local cos, sin, atan, pi = math.cos, math.sin, math.atan, math.pi

-- Two-argument arctangent, spelled portably.
--
-- `math.atan2` exists in WoW's Lua 5.1/LuaJIT but was removed in 5.4, which is
-- what CI runs these tests on. The obvious fallback `math.atan2 or math.atan` is
-- WRONG: Lua 5.4's math.atan does take two arguments, but LuaJIT's takes exactly
-- one and silently ignores the second — so the fallback would quietly return the
-- angle of y alone wherever it was actually used. Deriving it by quadrant works
-- the same everywhere and has no such trapdoor.
local atan2 = math.atan2 or function(y, x)
    if x > 0 then return atan(y / x) end
    if x < 0 then
        if y >= 0 then return atan(y / x) + pi end
        return atan(y / x) - pi
    end
    if y > 0 then return pi / 2 end
    if y < 0 then return -pi / 2 end
    return 0
end

-- Where the button sits for a given angle, as an offset from the minimap centre.
-- Pure maths, kept separate so it can be tested without a game client.
function ns.MinimapButtonPosition(angle, radius)
    local a = rad(angle or 0)
    return cos(a) * (radius or 0), sin(a) * (radius or 0)
end

-- The inverse: which angle does a cursor at (px, py) sit at, relative to the
-- centre (cx, cy). This is where the atan2 trap lives, so it is a named function
-- with a test rather than three lines inlined in a drag handler.
function ns.MinimapButtonAngle(cx, cy, px, py)
    local dx, dy = px - cx, py - cy
    if dx == 0 and dy == 0 then return nil end
    local a = deg(atan2(dy, dx))
    if a < 0 then a = a + 360 end
    return a
end

-- Settings live in PremadeIQ_DB.settings, which does not exist while this file
-- executes — Database:Init runs on ADDON_LOADED. Same defensive accessor pattern
-- PremadeTargets uses; never ns.Database:GetSetting at file scope.
local function getSetting(key, default)
    local db = ns.Database and ns.Database.db
    local settings = db and db.settings
    if settings == nil or settings[key] == nil then return default end
    return settings[key]
end

local function setSetting(key, value)
    if ns.Database and ns.Database.SetSetting then
        ns.Database:SetSetting(key, value)
    end
end

local Minimap_ = {}
ns.MinimapButton = Minimap_
local button

local function currentRadius()
    -- Read the size every time: Edit Mode lets the player resize the minimap,
    -- and a radius captured at load would strand the button off the edge.
    local mm = _G.Minimap
    local width = (mm and mm.GetWidth and mm:GetWidth()) or 140
    return (width / 2) + 5
end

local function applyPosition(angle)
    if not button then return end
    local x, y = ns.MinimapButtonPosition(angle, currentRadius())
    button:ClearAllPoints()
    button:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

local function onDragUpdate(self)
    local mm = _G.Minimap
    if not mm then return end
    local cx, cy = mm:GetCenter()
    if not cx then return end
    -- GetCursorPosition returns SCREEN pixels while GetCenter is in frame units.
    -- Without dividing by the effective scale the button lags and jumps wherever
    -- the UI scale is not 1 — which on a 3440x1440 client it never is.
    local scale = mm:GetEffectiveScale()
    if not scale or scale == 0 then return end
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    local angle = ns.MinimapButtonAngle(cx, cy, px, py)
    if not angle then return end
    setSetting("minimapAngle", angle)
    applyPosition(angle)
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("PremadeIQ " .. (ns.VERSION and ("v" .. ns.VERSION) or ""))
    GameTooltip:AddLine(L["MinimapTooltipClick"], 1, 1, 1)
    GameTooltip:AddLine(L["MinimapTooltipDrag"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Minimap_:Create()
    if button or not _G.Minimap then return button end
    -- NAMED on purpose: button collectors (SexyMap and friends) find minimap
    -- buttons by name, and an anonymous one is invisible to them.
    button = CreateFrame("Button", "PremadeIQMinimapButton", _G.Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    -- Explicit strata/level, or the button ends up beneath the minimap's own
    -- textures and blobs.
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    -- Our own logo, not a Blizzard icon. The previous path
    -- (Interface\Icons\achievement_bg_kill_10_fc_bgs) is not an icon the client
    -- has, so it resolved to the green question mark — the texture the game
    -- shows for anything it cannot find. There is no error and no warning for
    -- this: a bad texture path is silently the question mark, which is why it
    -- shipped.
    --
    -- No SetTexCoord here. The usual 0.08-0.92 trim exists to shave the border
    -- baked into Blizzard's square icon art; ours is already a circle with a
    -- transparent surround, and trimming it would just crop the shield.
    icon:SetTexture("Interface\\AddOns\\PremadeIQ\\Media\\logo.tga")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function()
        -- Left AND right both open the settings. Collapsing the targets panel
        -- from here is impossible without a secure snippet: its body is a
        -- SecureHandler frame that only a restricted handler may show or hide,
        -- so an insecure call would leave an empty frame out of combat and
        -- trigger ADDON_ACTION_BLOCKED inside one.
        if ns.OpenOptions then ns.OpenOptions() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return button
end

-- Apply visibility + position from the saved settings. Safe to call repeatedly;
-- the options checkbox and the "wipe database" flow both do.
function Minimap_:Refresh()
    if getSetting("minimapButton", true) == false then
        if button then button:Hide() end
        return
    end
    if not button then self:Create() end
    if not button then return end
    applyPosition(tonumber(getSetting("minimapAngle", DEFAULT_ANGLE)) or DEFAULT_ANGLE)
    button:Show()
end

function Minimap_:SetShown(shown)
    setSetting("minimapButton", shown and true or false)
    self:Refresh()
end
