local ADDON, ns = ...

-- Odds line: "how do the two teams compare, before the fighting starts".
--
-- Everything here happens OFFLINE. The addon cannot ask the server anything
-- during a match — WoW only flushes SavedVariables on /reload or logout, so a
-- round trip would cost two interface reloads — which is why the server ships
-- a winrate table ahead of time (PlayerStats.lua, written by the Uploader) and
-- the addon does nothing but look names up and average them.
--
-- The arithmetic is two differences and one sigmoid:
--
--   d_wr   our mean winrate minus theirs, over the players we can find,
--          in percentage points
--   d_new  our share of players the database has never seen minus theirs,
--          in percentage points
--   p      1 / (1 + exp(-(wr*d_wr + new*d_new)))
--
-- The coefficients arrive in the same file rather than living here, so a
-- recalibration is a server deploy instead of an addon release, and an addon
-- can never run a model fitted against a differently-shaped cache.
--
-- Calibrated 2026-09-06 (tools/forecast_calibration.py) on STARTING rosters —
-- the same partial scoreboard this code reads — and validated out-of-fold on
-- them: 72% of matches called correctly, and the percentages mean what they
-- say (worst gap between "promised 80%" and "won 80.9%" was 2.4 points).
-- That last part is why a number is shown at all instead of a vague verdict.
--
-- Two things deliberately absent:
--   * per-player winrates. The file has them, the UI never shows them: an
--     in-game ally rating ("you're 31%, leave") is not what this project is.
--   * the premade signal. It was measured and dropped — on starting rosters it
--     moved nothing the sample could resolve, and shipping it would have meant
--     handing the gated rosters to every contributor.

local Forecast = {}
ns.Forecast = Forecast

-- Below this many scoreboard rows on a side, the share-of-strangers half of
-- the model is a rumour: three rows can be 100% strangers by accident. The
-- known-player floor (min_known) comes from the server, but this one is about
-- the scoreboard still loading, which only the addon can see.
local MIN_SIDE_ROWS = 10

-- Fallback if the shipped file predates the field. Same value the server
-- currently sends; kept in sync by nothing but this comment, which is fine —
-- it only matters for a file too old to carry its own floor.
local DEFAULT_MIN_KNOWN = 8

local function statsTable()
    local s = PremadeIQ_PlayerStats
    if type(s) ~= "table" then return nil end
    if type(s.players) ~= "table" or type(s.model) ~= "table" then return nil end
    return s
end

-- "Name-Realm" -> realm, name. The cache is grouped by realm (it halves the
-- file), and rows for the viewer's own realm arrive as a bare "Name", so those
-- resolve against the viewer's realm — the same rule PremadeAlert.normName
-- uses to compare a scoreboard row with the catalog.
local function splitName(name, myRealm)
    local short, realm = name:match("^([^%-]+)%-(.+)$")
    if short then return realm, short end
    return myRealm, name
end

-- Exposed for the test; also the single place that knows the file's shape.
function Forecast.LookupIn(stats, name, myRealm)
    if not stats or type(name) ~= "string" or name == "" then return nil end
    local realm, short = splitName(name, myRealm)
    local bucket = realm and stats.players[realm]
    local wr = bucket and bucket[short]
    return (type(wr) == "number") and wr or nil
end

-- Pure core: takes the stats table explicitly so a test can hand it a fixture
-- instead of setting a global. Returns nil whenever there is not enough to say
-- honestly — a missing file, a half-loaded scoreboard, or too few known
-- players on either side.
--
-- `roster` is what PremadeAlert's scan already collected: one entry per
-- readable row, { name = , faction = }. Rows whose faction went secret carry
-- no side and are skipped: counting them would move BOTH the winrate and the
-- stranger share of whichever side we guessed.
function Forecast.ComputeFrom(stats, roster, mine, myRealm)
    if not stats or type(roster) ~= "table" then return nil end
    if mine ~= 0 and mine ~= 1 then return nil end

    local sides = {
        [0] = { n = 0, known = 0, sum = 0 },
        [1] = { n = 0, known = 0, sum = 0 },
    }
    for _, row in ipairs(roster) do
        local f = row.faction
        local side = (f == 0 or f == 1) and sides[f] or nil
        if side and type(row.name) == "string" then
            side.n = side.n + 1
            local wr = Forecast.LookupIn(stats, row.name, myRealm)
            if wr then
                side.known = side.known + 1
                side.sum = side.sum + wr
            end
        end
    end

    local us, them = sides[mine], sides[1 - mine]
    local minKnown = tonumber(stats.min_known) or DEFAULT_MIN_KNOWN
    -- Second return value explains the silence: /piq odds prints it, so "no
    -- line appeared" can be told apart from "the scoreboard is still loading"
    -- without reading the code.
    local why = { usN = us.n, usKnown = us.known, themN = them.n,
                  themKnown = them.known, minKnown = minKnown,
                  minRows = MIN_SIDE_ROWS }
    if us.n < MIN_SIDE_ROWS or them.n < MIN_SIDE_ROWS then return nil, why end
    if us.known < minKnown or them.known < minKnown then return nil, why end

    -- Values in the cache are already whole percents, so the difference of the
    -- two means is already in percentage points — no rescaling here.
    local dWr = (us.sum / us.known) - (them.sum / them.known)
    local dNew = ((us.n - us.known) / us.n - (them.n - them.known) / them.n) * 100

    local m = stats.model
    local z = (tonumber(m.wr) or 0) * dWr + (tonumber(m.new) or 0) * dNew
    local p = 1 / (1 + math.exp(-z))

    local pct = math.floor(p * 100 + 0.5)
    return {
        us = pct,
        them = 100 - pct,
        accuracy = tonumber(m.accuracy) or 0,
        -- The two inputs, kept so the UI can SHOW its working. A bare
        -- percentage is unarguable and therefore useless: seeing "average
        -- winrate 50 vs 52, strangers 26% vs 21%" is what lets a player judge
        -- whether the number deserves any weight in this particular match.
        ourWr = us.sum / us.known,
        theirWr = them.sum / them.known,
        ourNew = (us.n - us.known) / us.n * 100,
        theirNew = (them.n - them.known) / them.n * 100,
        ourKnown = us.known,
        theirKnown = them.known,
        ourN = us.n,
        theirN = them.n,
    }
end

-- The viewer's own team in the scoreboard's own 0=Horde/1=Alliance space.
--
-- GetBattlefieldArenaFaction is what Blizzard's own scoreboard uses
-- (Blizzard_PVPMatch/PVPMatchResults.lua), and it is the only one that is right
-- under MERCENARY mode, where UnitFactionGroup reports the character's faction
-- rather than the team actually being played. Getting this backwards does not
-- degrade the forecast — it MIRRORS it, turning a 62% into a 38%, which is
-- worse than saying nothing. Same helper as PremadeTargets.currentSide.
local function currentSide()
    if GetBattlefieldArenaFaction then
        local ok, value = pcall(GetBattlefieldArenaFaction)
        if ok and type(value) == "number"
                and not (issecretvalue and issecretvalue(value)) then
            return value
        end
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Alliance" then return 1 end
    if faction == "Horde" then return 0 end
    return nil
end

-- Live entry point: reads the shipped file and the viewer's realm.
-- `mine` is only a fallback — the caller derives it from UnitFactionGroup,
-- which is wrong for mercenaries.
function Forecast:ForMatch(roster, mine)
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    local side = currentSide()
    if side ~= 0 and side ~= 1 then side = mine end
    return Forecast.ComputeFrom(statsTable(), roster, side,
                                (realm ~= "" and realm) or nil)
end

-- Read both teams off the scoreboard: name and side, nothing else.
--
-- The automatic path gets this for free from the premade scan, but that scan
-- only runs on the alert's timer train. A manual /piq odds has to be able to
-- ask at any moment, so it does its own pass — deliberately a copy of the four
-- lines that matter rather than a refactor of the alert's scan, which carries
-- the taint-safety and throttling rules that only apply to ITS timing.
function Forecast:ScanBoard()
    if not (C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        return nil
    end
    -- Without factionEnum = -1 the scoreboard returns our half only, and the
    -- forecast needs both (PremadeAlert documents the -1 at length).
    if SetBattlefieldScoreFaction then pcall(SetBattlefieldScoreFaction, -1) end
    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
    local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    local roster = {}
    for i = 1, n do
        local info = C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i)
        local name = info and info.name
        if type(name) == "string" and name ~= ""
                and not (issecretvalue and issecretvalue(name)) then
            roster[#roster + 1] = {
                name = name,
                faction = (not (issecretvalue and issecretvalue(info.faction)))
                          and info.faction or nil,
            }
        end
    end
    return roster
end

-- Chat lines for /piq odds: the forecast, or why there isn't one.
function Forecast:Report()
    local L = ns.L
    local stats = statsTable()
    if not stats then return { L["ForecastNoCache"] } end
    local roster = Forecast:ScanBoard()
    if not roster then return { L["ForecastNotInBG"] } end
    local f, why = Forecast:ForMatch(roster, nil)
    if f then
        return {
            L["ForecastOdds"]:format(f.us, f.them),
            L["ForecastNote"]:format(f.accuracy),
        }
    end
    if not why then return { L["ForecastNotInBG"] } end
    return { L["ForecastNoData"]:format(
        why.usKnown, why.usN, why.themKnown, why.themN, why.minKnown) }
end

-- ── The standalone panel ──────────────────────────────────────────────────
-- Shown only when there is NO premade banner to ride along with, which is most
-- matches. The banner carries the odds when it appears, so the two never stack.
--
-- Deliberately smaller and quieter than the premade banner: this is context,
-- not an alarm. No sound, no mouse (EnableMouse off — it can never eat a click
-- or steal WASD mid-fight), and it fades on its own.
local PANEL_WIDTH    = 340
local PANEL_HOLD_SEC = 12      -- fully visible before the fade starts
local PANEL_FADE_SEC = 3       -- ~15s on screen in total

local function ensurePanel()
    if Forecast._panel then return Forecast._panel end
    local f = CreateFrame("Frame", "PremadeIQOddsPanel", UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:SetWidth(PANEL_WIDTH)
    -- Below where the premade banner sits, so the two never overlap even if a
    -- future change lets both appear at once.
    f:SetPoint("TOP", UIParent, "TOP", 0, -260)
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0, 0, 0, 0.75)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOP", f, "TOP", 0, -9)
    head:SetWidth(PANEL_WIDTH - 24)
    head:SetJustifyH("CENTER")
    f.head = head

    local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOP", head, "BOTTOM", 0, -4)
    note:SetWidth(PANEL_WIDTH - 24)
    note:SetJustifyH("CENTER")
    f.note = note

    local ag = f:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetStartDelay(PANEL_HOLD_SEC)
    a:SetDuration(PANEL_FADE_SEC)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.fade = ag

    f:Hide()
    Forecast._panel = f
    return f
end

function Forecast:ShowPanel(f)
    if not f then return end
    local L = ns.L
    local panel = ensurePanel()
    panel.head:SetText(L["ForecastOdds"]:format(f.us, f.them))
    if f.us >= 50 then
        panel.head:SetTextColor(0.25, 0.88, 0.44)   -- favoured: green
    else
        panel.head:SetTextColor(0.98, 0.48, 0.52)   -- underdog: red
    end
    panel.note:SetText(L["ForecastNote"]:format(f.accuracy))
    panel:SetHeight(9 + panel.head:GetStringHeight() + 4
                    + panel.note:GetStringHeight() + 11)
    panel.fade:Stop()
    panel:SetAlpha(1)
    panel:Show()
    panel.fade:Restart()
end

function Forecast:HidePanel()
    if self._panel then
        self._panel.fade:Stop()
        self._panel:Hide()
    end
end

-- One panel per match. The scan train calls in repeatedly as the scoreboard
-- fills, and the first call that has enough data is the one that shows.
function Forecast:AnnounceOnce(f)
    if not f or self._announced then return end
    self._announced = true
    self:ShowPanel(f)
end

-- The odds already reached the player some other way — they were on the premade
-- banner. Claim the slot so the panel does not repeat them.
--
-- This matters because the banner is one-shot and fires the moment a premade is
-- recognised, which can be seconds into the match, while the forecast needs a
-- fuller scoreboard. So the banner can legitimately go out WITHOUT the odds; in
-- that case nothing is marked, the scans keep going, and the panel delivers them
-- late rather than never.
function Forecast:MarkShown()
    self._announced = true
end

function Forecast:Shown()
    return self._announced and true or false
end

-- Called on PVP_MATCH_ACTIVE: a new match may show its own panel.
function Forecast:Reset()
    self._announced = nil
    self:HidePanel()
end

-- Whether a cache is installed at all, and how many characters it holds —
-- for /piq status, so "no odds line" can be told apart from "no data".
function Forecast:Info()
    local s = statsTable()
    if not s then return 0, 0 end
    local realms, chars = 0, 0
    for _, bucket in pairs(s.players) do
        realms = realms + 1
        for _ in pairs(bucket) do chars = chars + 1 end
    end
    return realms, chars
end
