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

-- Fallback when the shipped file carries no usable floor of its own. Same value
-- the server currently sends; kept in sync by nothing but this comment, which
-- is fine — it only matters for a file that failed to bring its own.
local DEFAULT_MIN_KNOWN = 8

-- The shape this code knows how to read. The server stamps the same number
-- (player_stats.STATS_VERSION) and bumps it when the file changes in a way an
-- old addon must REFUSE to read — which only works if somebody actually looks,
-- so this is that somebody. tests/test_stats_version_contract.py keeps the two
-- numbers equal.
--
-- Order of a future bump matters: server first, addon in the release that
-- follows. The other way round every player of the new addon goes silent until
-- the deploy lands.
local STATS_FILE_VERSION = 1

-- Past this age the cache stops describing the battlegrounds being played:
-- players who took a break drop out of the server's 60-day activity window,
-- newcomers are missing entirely, and everyone new reads as a "stranger".
--
-- 45 days rather than something tighter because a still `generated_at` does not
-- have to mean a broken Uploader: the file is only rewritten when the server's
-- content version moves, and that is derived from the newest match in the
-- database — a quiet week legitimately freezes the timestamp with everything
-- working. This catches "the Uploader has not run in a month and a half", not
-- "the owner went on holiday".
local STALE_SEC = 45 * 86400

-- Is this file something to compute from? Exposed (and taking `now`) so the
-- test can hand it a fixture instead of a global and a clock.
--
-- Every rejection here is the same message to the player — "no winrate data,
-- the Uploader ships it" — because every one of them has the same fix.
function Forecast.UsableStats(s, now)
    if type(s) ~= "table" then return nil end
    if type(s.players) ~= "table" or type(s.model) ~= "table" then return nil end
    if tonumber(s.version) ~= STATS_FILE_VERSION then return nil end

    -- A zero model is what the stub shipped inside the addon package carries
    -- (package_addon.PLAYER_STATS_STUB), so that an install without an Uploader
    -- computes nothing rather than running made-up coefficients. Without this
    -- check it does not compute nothing — it computes a confident-looking
    -- "50% — 50%", because a zero coefficient times anything is a coin flip.
    local m = s.model
    if type(m.wr) ~= "number" or m.wr == 0 then return nil end
    if type(m.new) ~= "number" then return nil end

    local generatedAt = tonumber(s.generated_at)
    if not generatedAt or generatedAt <= 0 then return nil end
    if now then
        -- Clamped for the same reason Database:CatalogFreshness clamps: a
        -- client clock behind the server's must not read as a fresh file, and
        -- one ahead of it must not read as an ancient one.
        local age = now - generatedAt
        if age > STALE_SEC then return nil end
    end
    return s
end

local function statsTable()
    return Forecast.UsableStats(PremadeIQ_PlayerStats,
                               (type(time) == "function") and time() or nil)
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
    -- A floor below 1 is not a floor: it lets a side through with nobody known
    -- and turns the mean below into 0/0. The writer fills the field in with a
    -- zero when the server sends no floor at all (stats_writer.render_stats_lua),
    -- so "present but useless" is a real shape, not a hypothetical one.
    local minKnown = tonumber(stats.min_known)
    if not minKnown or minKnown < 1 then minKnown = DEFAULT_MIN_KNOWN end
    -- Second return value explains the silence: /piq odds prints it, so "no
    -- line appeared" can be told apart from "the scoreboard is still loading"
    -- without reading the code.
    local why = { usN = us.n, usKnown = us.known, themN = them.n,
                  themKnown = them.known, minKnown = minKnown,
                  minRows = MIN_SIDE_ROWS }
    if us.n < MIN_SIDE_ROWS or them.n < MIN_SIDE_ROWS then return nil, why end
    if us.known < minKnown or them.known < minKnown then return nil, why end
    -- Belt and braces before the two means below: minKnown is >= 1 by now, so
    -- this cannot fire — but a division by zero in Lua does not raise, it
    -- returns a nan that travels silently into string.format("%d").
    if us.known < 1 or them.known < 1 then return nil, why end

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
--
-- Epic battlegrounds ONLY, and this is the gate for every caller. Everything
-- underneath the number is epic-shaped: the winrates were collected there (the
-- server quarantines every other map), and the coefficients were fitted on
-- 40-a-side starting rosters. In a 15-a-side Arathi the row floor is cleared
-- within seconds and the addon would happily show a number carrying a "72%
-- accurate" caption that nobody ever measured there.
function Forecast:Evaluate(roster, mine)
    if not (ns.IsEpicBGNow and ns.IsEpicBGNow()) then return nil end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    local side = currentSide()
    if side ~= 0 and side ~= 1 then side = mine end
    return Forecast.ComputeFrom(statsTable(), roster, side,
                                (realm ~= "" and realm) or nil)
end

-- The "Show win chances" switch in the options. Read here rather than passed
-- in, because here is the only place that sees every display: the panel line,
-- the premade banner and the standalone pop-up all arrive through ForMatch.
-- It used to be checked in the panel alone, so turning the feature off silenced
-- one of the three and left the other two appearing.
local function forecastEnabled()
    local db = PremadeIQ_DB
    local settings = (type(db) == "table") and db.settings or nil
    return (settings and settings.forecast) ~= false
end

-- Everything that DISPLAYS odds by itself comes through here.
--
-- /piq odds deliberately does not: it goes straight to Evaluate. Someone who
-- typed the command is asking this once, and answering "you turned that off"
-- to a direct question is worse than answering it.
function Forecast:ForMatch(roster, mine)
    if not forecastEnabled() then return nil end
    return Forecast:Evaluate(roster, mine)
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
--
-- Three separate silences, and telling them apart is the whole point of the
-- command: "not in a battleground", "in one, but not an epic" and "in an epic,
-- still reading the board" call for three different reactions from the player.
-- ForMatch collapses all of them into nil, so the first two are answered here,
-- before it is asked.
function Forecast:Report()
    local L = ns.L
    local stats = statsTable()
    if not stats then return { L["ForecastNoCache"] } end
    local roster = Forecast:ScanBoard()
    if not roster then return { L["ForecastNotInBG"] } end
    if not (ns.IsEpicBGNow and ns.IsEpicBGNow()) then
        return { L["ForecastNotEBG"] }
    end
    local f, why = Forecast:Evaluate(roster, nil)
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
