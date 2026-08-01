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

f:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ns.Database:Init()
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
        if not (C_PvP.IsBattleground and C_PvP.IsBattleground()) then
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
            prnt(L["PremadeCatalogMissing"])
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
