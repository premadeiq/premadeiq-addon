local ADDON, ns = ...
local L = ns.L

-- Single source of truth for the version is the .toc (## Version:) — the
-- old hardcoded constant here drifted 13 releases behind it unnoticed.
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata
                 and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?"

local f = CreateFrame("Frame", "PremadeIQFrame")
ns.frame = f

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PVP_MATCH_ACTIVE")
f:RegisterEvent("PVP_MATCH_COMPLETE")
f:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")

local snapshotDone = false

-- time() of the last PVP_MATCH_ACTIVE. Guards the PLAYER_ENTERING_WORLD
-- leave-reset against the opening-load transition: on AV/Epic Midnight maps a
-- PEW fires within ~1s of the match going active while IsBattleground() still
-- reads false (the world is still loading), and resetting then cancels the
-- just-scheduled scan/capture trains and zeroes their match clocks — silently
-- killing the premade alert (and deserter capture) for the whole match.
-- Raising the grace only delays stale-state cleanup, which the next match's
-- OnMatchActive performs anyway; 15s buys headroom against a stuttering load
-- screen with no realistic downside (no real leave-and-rejoin completes a fresh
-- PVP_MATCH_ACTIVE that fast). See docs/plan-2026-06-18-alert-reset-fix.md.
local lastMatchActiveAt = 0
local PEW_LEAVE_GRACE_SEC = 15

local function prnt(msg)
    print("|cff33ff99PremadeIQ|r " .. msg)
end

-- ---------------------------------------------------------------------
-- Onboarding: the address, and when to bring it up
--
-- The addon ships with an empty premade list (the public zip carries a
-- neutral KnownPremades stub) and cannot fetch anything itself — the list
-- arrives with the Uploader. A player who never installs it sees a feature
-- that silently does nothing, so the two moments where that becomes
-- obvious (entering an Epic BG, finishing one) say so once, quietly.
-- ---------------------------------------------------------------------

-- A copyable address box. WoW cannot open a browser for us, so the most a
-- link can be is text the player can select — an edit box with the text
-- pre-selected is the closest thing to a clickable link the client allows.
StaticPopupDialogs["PREMADEIQ_LINK"] = {
    text = "PremadeIQ",           -- replaced per show: the language is switchable
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

local function showLinkDialog()
    StaticPopupDialogs["PREMADEIQ_LINK"].text = "PremadeIQ — " .. L["UploaderCopyTitle"]
    StaticPopup_Show("PREMADEIQ_LINK", nil, nil, L["UploaderURLBare"])
end
ns.ShowUploaderLink = showLinkDialog

-- Has an Uploader ever written its watermark for any character on this
-- account? That is the honest test for "is this player connected at all" —
-- an empty catalog alone cannot tell "never installed it" from "installed,
-- but access lapsed", and those need different advice.
local function uploaderSeen()
    local st = PremadeIQ_UploadState
    if type(st) ~= "table" or type(st.cursors) ~= "table" then return false end
    for _ in pairs(st.cursors) do return true end
    return false
end
ns.UploaderSeen = uploaderSeen

local CATALOG_HINT_EVERY_SEC = 7 * 24 * 60 * 60

-- One line on entering an Epic BG, at most once a week. Called from both
-- entry points (match start and context restore after a /reload mid-match),
-- so the timestamp is written next to the print, not by the caller.
local function maybeCatalogHint()
    if ns.Database and ns.Database:GetSetting("premadeAlert") == false then return end

    local nlead = 0
    if ns.PremadeAlert then nlead = ns.PremadeAlert:CatalogInfo() or 0 end
    if nlead > 0 then return end          -- catalog is there, nothing to say

    local last = tonumber(ns.Database and ns.Database:GetSetting("catalogHintAt")) or 0
    if time() - last < CATALOG_HINT_EVERY_SEC then return end

    if uploaderSeen() then
        prnt("|cff888888" .. L["CatalogHintStale"] .. "|r")
    else
        prnt("|cff888888" .. (L["CatalogHintNoUploader"]):format(L["UploaderURLBare"]) .. "|r")
    end
    if ns.Database then ns.Database:SetSetting("catalogHintAt", time()) end
end

f:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ns.Database:Init()
        -- Locales resolved themselves from the game client while the files
        -- were loading, because SavedVariables did not exist yet. Now they
        -- do, so re-apply the player's own choice. The strings table is
        -- rebuilt IN PLACE, so every file that captured it still sees it.
        if ns.ApplyLanguage then
            ns.ApplyLanguage(ns.Database:GetSetting("language") or "auto")
        end
        ns.Privacy:Init()
        prnt(("v%s loaded. %s: %d"):format(
            VERSION, L["Players in DB"], ns.Database:CountPlayers()))
        if ns.PremadeAlert then
            local n, tier = ns.PremadeAlert:CatalogInfo()
            if n and n > 0 then
                prnt((L["PremadeCatalogLoaded"]):format(n, tier or "?"))
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        snapshotDone = false
        -- Trim the player DB once per session, now that UnitGUID("player") is
        -- available (it's nil back on ADDON_LOADED). Keeps SavedVariables small.
        ns.Database:PruneIfReady()
        ns.Privacy:MaybeShowWelcome()
        -- Minimap button: PLAYER_ENTERING_WORLD is the first point where
        -- both SavedVariables and the Minimap frame are certain to exist.
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
        if C_PvP.IsBattleground and C_PvP.IsBattleground() then
            -- Back inside a battleground on a PEW: either the opening load or
            -- a /reload mid-match. The latter wiped the Collector's context
            -- and PVP_MATCH_ACTIVE will not fire again, so rebuild it from the
            -- record parked in SavedVariables. All the guarding lives in
            -- RestoreContext (instance id + battle fingerprint + freshness);
            -- a refusal is a silent no-op that leaves today's behaviour.
            -- Doing it HERE and not at snapshot time is deliberate: we are
            -- still in the instance, so GetInstanceInfo and
            -- GetActiveMatchDuration both answer honestly.
            if ns.Collector and ns.Collector:RestoreContext() then
                -- The restored context knows it is an EBG again, so the
                -- services that gate on that can run for the rest of the match.
                if ns.Deserter then ns.Deserter:OnMatchActive() end
                if ns.PremadeAlert then ns.PremadeAlert:OnMatchActive() end
                maybeCatalogHint()
            end
        else
            -- Left the BG (clean end, kick, or disconnect). Reset the start-
            -- roster cache so a stale capture from the prior match can't leak
            -- into the next one — BUT only if no match went active in the last
            -- few seconds. A PEW with IsBattleground()==false right after
            -- PVP_MATCH_ACTIVE is the opening-load transition, not a leave;
            -- resetting then kills the just-scheduled scan/capture trains.
            -- Skipping the transient reset is safe: the next match's
            -- OnMatchActive fully re-inits per-match state regardless. (Even if
            -- a PEW somehow preceded PVP_MATCH_ACTIVE, the reset would land
            -- before OnMatchActive's rebuild, which stays authoritative.) An
            -- early desert within GRACE leaves stale state that simply
            -- self-heals at the next OnMatchActive.
            if time() - lastMatchActiveAt > PEW_LEAVE_GRACE_SEC then
                if ns.Deserter then ns.Deserter:Reset() end
                if ns.PremadeAlert then ns.PremadeAlert:Reset() end
                -- Also tear down the Collector's per-match tickers: on an
                -- abnormal exit SnapshotMatch never runs, so without this the
                -- crown ticker keeps polling in the open world (stale isEBG).
                if ns.Collector then ns.Collector:Reset() end
            end
        end

    elseif event == "PVP_MATCH_ACTIVE" then
        -- Stamp before the IsEBGMatch() gate: the PEW leave-reset guard must
        -- know about ANY match start, incl. the brief pre-GetInstanceInfo window.
        lastMatchActiveAt = time()
        ns.Collector:OnMatchActive()
        -- EBG-only service: arenas / normal BGs / blitz never start the
        -- roster capture or the premade scan. (If GetInstanceInfo was nil
        -- on ACTIVE, Collector's 2s retry late-starts these itself.)
        if ns.Collector:IsEBGMatch() then
            if ns.Deserter then ns.Deserter:OnMatchActive() end
            if ns.PremadeAlert then ns.PremadeAlert:OnMatchActive() end
            maybeCatalogHint()
        end

    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        -- Gate on the CURRENT match being an EBG. Without this, entering a
        -- normal BG right after an Epic leaves stale state live: the non-EBG
        -- OnMatchActive is skipped, PLAYER_ENTERING_WORLD doesn't reset
        -- (IsBattleground() is true), and the previous match's capture/scan
        -- windows would chew on the wrong scoreboard.
        if ns.Collector:IsEBGMatch() then
            -- Free re-capture trigger for the deserter snapshot during the
            -- match's opening phase. No-op if quorum already reached or if
            -- we're past the 30-sec capture window.
            if ns.Deserter then ns.Deserter:OnBattlefieldScoreUpdate() end
            -- Baseline roster probe: rides the same free updates instead of
            -- running its own poll loop, and no-ops once captured.
            ns.Collector:OnBattlefieldScoreUpdate()
            -- Same free trigger for the premade alert: catches a late-arriving
            -- enemy roster the instant it populates, not just at fixed ticks.
            if ns.PremadeAlert then ns.PremadeAlert:OnBattlefieldScoreUpdate() end
        end

    elseif event == "PVP_MATCH_COMPLETE" then
        if not snapshotDone then
            -- Write gate: ctx verdict from ACTIVE, OR the live instance id
            -- read RIGHT NOW (before the 1.4s snapshot delay). The
            -- disjunction covers both edge cases: /reload mid-match (ctx
            -- empty, live read still inside the BG) and the post-match
            -- teleport race (live read already in a capital, ctx remembers).
            local liveID  = select(8, GetInstanceInfo())
            local allowed = ns.Collector:IsEBGMatch() or ns.IsEBGInstanceID(liveID)
            snapshotDone = true
            if allowed then
                -- After /reload ctx is empty and only liveID admitted us —
                -- hand it to the Collector so the +1.4s snapshot survives
                -- an early post-match teleport.
                ns.Collector:AdoptInstanceID(liveID)
                ns.Collector:ScheduleSnapshotMatch(function(n)
                    prnt(("%s: %d"):format(L["Match recorded"], n))
                    -- "Match recorded" means "kept in memory", and a player who
                    -- has never uploaded reads it as "sent". WoW only flushes
                    -- SavedVariables on /reload or logout, so the Uploader finds
                    -- nothing and looks broken. Said once per match, and only
                    -- while no upload has ever happened on this account.
                    if not uploaderSeen() then
                        prnt("|cff888888" .. L["MatchNeedsReload"] .. "|r")
                    end
                end)
            else
                ns.Collector:Debug(("COMPLETE skipped: non-EBG (instance=%s)")
                    :format(tostring(liveID)))
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

SLASH_PREMADEIQ1 = "/piq"
SLASH_PREMADEIQ2 = "/premadeiq"

local function cmdStatus()
    local pCount = ns.Database:CountPlayers()
    local sCount = ns.Database:CountSamples()
    local mCount = ns.Database.db.matches.count or 0
    if pCount == 0 then
        prnt(L["No data yet"])
    else
        prnt(("%s: %d | %s: %d | %s: %d"):format(
            L["Players in DB"], pCount,
            L["Samples"], sCount,
            L["Matches"], mCount))
    end
    -- Catalog state on demand, so the premade-alert feed can be verified
    -- without waiting for the login line to scroll past.
    if ns.PremadeAlert then
        local n, tier = ns.PremadeAlert:CatalogInfo()
        if n and n > 0 then
            prnt((L["PremadeCatalogLoaded"]):format(n, tier or "?"))
        else
            prnt((L["PremadeCatalogMissing"]):format(L["UploaderURLBare"]))
        end
    end
end

local function cmdSnapshot()
    if not (C_PvP.IsBattleground and C_PvP.IsBattleground()) then
        prnt(L["Not in a BG"])
        return
    end
    ns.Collector:ScheduleSnapshotMatch(function(n)
        prnt(("manual snapshot: %d rows"):format(n))
    end)
end

local function cmdReset(arg)
    if arg == "confirm" then
        PremadeIQ_DB = nil
        ns.Database:Init()
        ns.Privacy:Init()
        prnt(L["DB reset"])
    else
        prnt(L["Confirm reset"])
    end
end

local function cmdDebug(arg)
    if arg == "on" then
        ns.Database:SetSetting("debug", true)
        prnt(L["Debug on"])
    elseif arg == "off" then
        ns.Database:SetSetting("debug", false)
        prnt(L["Debug off"])
    else
        prnt(("debug: %s"):format(tostring(ns.Database:GetSetting("debug") or false)))
    end
end

local function cmdUploader()
    prnt(L["UploaderURL"])
    prnt(L["DiscordURL"])
    -- The chat line is for reading; the dialog is for copying. Chat text
    -- cannot be selected in this client, so without the box the address has
    -- to be retyped by hand into a browser.
    showLinkDialog()
end

SlashCmdList["PREMADEIQ"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""

    if cmd == "" or cmd == "status" or cmd == "stats" then
        cmdStatus()
    elseif cmd == "snapshot" then
        cmdSnapshot()
    elseif cmd == "premade" or cmd == "premades" then
        if ns.PremadeAlert then ns.PremadeAlert:ManualScan() end
    elseif cmd == "copy" then
        if ns.PremadeAlert then ns.PremadeAlert:CopyLast() end
    elseif cmd == "reset" then
        cmdReset(arg)
    elseif cmd == "debug" then
        cmdDebug(arg)
    elseif cmd == "uploader" then
        cmdUploader()
    elseif cmd == "version" then
        prnt(("v%s"):format(VERSION))
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        if ns.OpenOptions then
            ns.OpenOptions()
        else
            prnt(L["No options panel"])
        end
    else
        print(L["CmdHelp"])
    end
end

ns.VERSION = VERSION
_G.PIQ_NS = ns

-- Addon-menu entry points. Blizzard looks these up as globals by the names
-- given in the .toc, so they cannot live on the namespace table.
function _G.PremadeIQ_OnCompartmentClick()
    if ns.OpenOptions then ns.OpenOptions() end
end

function _G.PremadeIQ_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("PremadeIQ " .. (ns.VERSION and ("v" .. ns.VERSION) or ""))
    GameTooltip:AddLine(ns.L["MinimapTooltipClick"], 1, 1, 1)
    GameTooltip:Show()
end

function _G.PremadeIQ_OnCompartmentLeave()
    GameTooltip:Hide()
end
