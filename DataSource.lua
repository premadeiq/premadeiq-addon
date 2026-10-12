-- DataSource.lua — keep the Uploader's data through an addon update.
--
-- The Uploader writes four data files: catalog, winrates, guild map, upload
-- cursor. An addon manager replaces this folder on every update, and the zip
-- ships neutral stubs of those files, so each update used to leave the addon
-- running on empty data until the Uploader ran again — no premade panel, no
-- odds line, only match recording.
--
-- Since Uploader 0.9.15 the same files also live in PremadeIQ_Data, a
-- load-on-demand folder of ours that no addon manager owns, under different
-- global names (PremadeIQData_*), so neither copy can overwrite the other. Here
-- we load it and keep whichever copy is newer under the usual PremadeIQ_*
-- names, so every reader stays as it was. Runs while the files load: the first
-- reader is ADDON_LOADED, which comes after.
--
-- docs/plans/2026-10-13-data-survives-curseforge-updates.md

local _, ns = ...

local DataSource = {}
ns.DataSource = DataSource

DataSource.ADDON = "PremadeIQ_Data"
DataSource.SETS = { "KnownPremades", "PlayerStats", "GuildMap" }

-- How new a copy is: its generated_at (a stub carries 0). -1 when there is no
-- table at all — a data file with a syntax error simply leaves its global unset.
local function stamp(t)
    if type(t) ~= "table" then return -1 end
    return tonumber(t.generated_at) or 0
end

-- The newer of two copies, and which one it was. A tie goes to the data
-- folder: both are written together, and the data folder is the one an addon
-- update cannot have replaced with a stub.
function DataSource.Pick(main, data)
    local sm, sd = stamp(main), stamp(data)
    if sd >= 0 and sd >= sm then return data, "data" end
    if sm >= 0 then return main, "addon" end
    return nil, nil
end

-- Upload cursors are per account (installId), so merge rather than pick: each
-- account keeps the cursor written last, the data folder winning a tie.
function DataSource.MergeCursors(main, data)
    if type(main) ~= "table" and type(data) ~= "table" then return main end
    local out = { version = (type(data) == "table" and data.version)
                         or (type(main) == "table" and main.version) or 1,
                  cursors = {} }
    for _, src in ipairs({ data, main }) do
        if type(src) == "table" and type(src.cursors) == "table" then
            for id, c in pairs(src.cursors) do
                if type(c) == "table" then
                    local have = out.cursors[id]
                    if not have or (tonumber(c.writtenAt) or 0) > (tonumber(have.writtenAt) or 0) then
                        out.cursors[id] = c
                    end
                end
            end
        end
    end
    return out
end

-- Load PremadeIQ_Data. Returns loaded, reason (Blizzard's own reason code:
-- MISSING, DISABLED, INTERFACE_VERSION, CORRUPT...). A folder the player — or
-- the patch-day "out of date addons" button — switched off is still loaded,
-- the way Blizzard loads its own: enable for this load, then put the checkbox
-- back as it was (AddOnUtil.LoadAddOn with restoreEnabledState). It is data,
-- not code, and it is never switched off on purpose.
function DataSource.Load()
    local C = C_AddOns
    if not (C and C.DoesAddOnExist and C.LoadAddOn) then return false, "API" end
    if not C.DoesAddOnExist(DataSource.ADDON) then return false, "MISSING" end
    if C.IsAddOnLoaded and C.IsAddOnLoaded(DataSource.ADDON) then return true end
    local ok, loaded, reason = pcall(C.LoadAddOn, DataSource.ADDON)
    if ok and loaded then return true end
    reason = ok and reason or "ERROR"
    if reason == "DISABLED" and AddOnUtil and AddOnUtil.LoadAddOn then
        local ok2, loaded2, reason2 = pcall(AddOnUtil.LoadAddOn, DataSource.ADDON, true)
        if ok2 and loaded2 then return true, "DISABLED" end
        reason = ok2 and reason2 or reason
    end
    return false, reason
end

-- Choose a copy of every set, publish it under the usual name, and drop the
-- data-folder tables so the copy not chosen can be collected (~2 MB).
function DataSource.Apply(env)
    env = env or _G
    local used = {}
    for _, name in ipairs(DataSource.SETS) do
        local main, data = env["PremadeIQ_" .. name], env["PremadeIQData_" .. name]
        local chosen, from = DataSource.Pick(main, data)
        env["PremadeIQ_" .. name] = chosen
        env["PremadeIQData_" .. name] = nil
        used[name] = from
    end
    local us = DataSource.MergeCursors(env.PremadeIQ_UploadState, env.PremadeIQData_UploadState)
    used.UploadState = (type(env.PremadeIQData_UploadState) == "table") and "data"
                    or (type(env.PremadeIQ_UploadState) == "table" and "addon") or nil
    env.PremadeIQ_UploadState = us
    env.PremadeIQData_UploadState = nil
    return used
end

local loaded, reason = DataSource.Load()
DataSource.loaded, DataSource.reason = loaded, reason
DataSource.used = DataSource.Apply()
