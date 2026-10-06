local ADDON, ns = ...
local L = ns.L

-- In-game warning for a mercenary crew with no known leader: people who keep
-- entering battles as mercenaries together (catalog `merc_crews`, server
-- premades.merc_crews). The site calls such a battle a possible premade; this
-- says the same in the match, once per crew.
--
-- It rides on the targets panel's scoreboard scan (PremadeTargets.lua hands
-- every filtered roster to OnPlayers), so it reads sides the way the panel
-- does and costs no scan of its own. PremadeAlert.lua is not touched: only its
-- public ShowPlainBanner, and `_crownRes`, which it sets when its own premade
-- banner went up this match — then this one stays in chat and leaves the
-- screen to the stronger claim.
local MercCrewAlert = { _fired = {}, _over = false }
ns.MercCrewAlert = MercCrewAlert

local function prnt(msg)
    print("|cff33ff99PremadeIQ|r " .. msg)
end

-- Same ring buffer PremadeAlert writes (PremadeIQ_DB.alertLog, 100 lines).
local function dbg(line)
    local db = ns.Database and ns.Database.db
    if not db then return end
    db.alertLog = db.alertLog or {}
    db.alertLog[#db.alertLog + 1] = date("%H:%M:%S") .. " " .. line
    while #db.alertLog > 100 do table.remove(db.alertLog, 1) end
end

-- A new match (or a world change): every crew may warn again.
function MercCrewAlert:Reset()
    self._fired = {}
    self._over = false
end

-- The match is over. The scoreboard keeps updating on the results screen, and
-- without this the warning would sound a second time there.
function MercCrewAlert:Finish()
    self._over = true
end

function MercCrewAlert:OnPlayers(players)
    if self._over then return end
    if ns.Database and ns.Database:GetSetting("premadeAlert") == false then return end
    local Core = ns.PremadeTargetsCore
    if not Core or not Core.CrewHits then return end
    local hits = Core.CrewHits(players)
    local fresh = false
    for _, hit in ipairs(hits) do
        if not self._fired[hit.id] then
            self._fired[hit.id] = true
            fresh = true
            dbg("CREW id=" .. tostring(hit.id) .. " n=" .. tostring(hit.n))
        end
    end
    if not fresh then return end
    local line = L["MercCrewDetected"]
    prnt("|cffffcc00" .. line .. "|r")
    local pa = ns.PremadeAlert
    if pa and pa._crownRes == nil and pa.ShowPlainBanner then
        pa:ShowPlainBanner(line)
        if not ns.Database or ns.Database:GetSetting("premadeSound") ~= false then
            PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
        end
    end
end
