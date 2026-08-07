local ADDON, ns = ...

local Core = {}
ns.PremadeTargetsCore = Core

local function validName(name)
    return type(name) == "string" and name ~= "" and not name:find("[\r\n]")
end

function Core.NormalizeName(name, realm)
    if not validName(name) then return nil end
    if name:find("-", 1, true) then return name end
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function addGroup(entry, groupId, label)
    if groupId == nil or not validName(label) or entry._groupSet[groupId] then return end
    entry._groupSet[groupId] = true
    entry.groups[#entry.groups + 1] = label
end

function Core.BuildCatalogIndex(catalog, realm)
    local index = {}
    if type(catalog) ~= "table" or type(catalog.leaders) ~= "table" then
        return index
    end

    local function getEntry(name)
        local key = Core.NormalizeName(name, realm)
        if not key then return nil end
        local entry = index[key]
        if not entry then
            entry = {
                catalogName = name,
                isLeader = false,
                groups = {},
                _groupSet = {},
            }
            index[key] = entry
        end
        return entry
    end

    local groupNames = {}
    for _, leader in ipairs(catalog.leaders) do
        if type(leader) == "table" then
            local groupId = leader.leader_id or leader.guid or leader.name
            if groupId ~= nil and validName(leader.name) then
                if leader.guid == groupId or not groupNames[groupId] then
                    groupNames[groupId] = leader.name
                end
            end
        end
    end

    local function addMembers(members, groupId, groupLabel)
        if type(members) ~= "table" then return end
        for _, member in ipairs(members) do
            if type(member) == "table" then
                local entry = getEntry(member.name)
                if entry then addGroup(entry, groupId, groupLabel) end
            end
        end
    end

    for _, leader in ipairs(catalog.leaders) do
        if type(leader) == "table" then
            local groupId = leader.leader_id or leader.guid or leader.name
            local groupLabel = groupNames[groupId] or leader.name
            local entry = getEntry(leader.name)
            if entry then
                entry.isLeader = true
                addGroup(entry, groupId, groupLabel)
            end
            addMembers(leader.confirmed_members, groupId, groupLabel)
        end
    end

    for _, entry in pairs(index) do
        table.sort(entry.groups)
        entry._groupSet = nil
    end
    return index
end

-- Both teams, tagged with which side of the scoreboard they sit on.
--
-- `mySide` is the viewer's own team in the scoreboard's 0=Horde/1=Alliance
-- space (GetBattlefieldArenaFaction — see PremadeTargets.lua). A row whose
-- `faction` is missing is dropped rather than guessed: PremadeAlert can afford
-- the permissive "unreadable → treat as enemy" fallback because over-warning is
-- harmless there, but here the same guess would file a teammate under the enemy
-- heading, which is worse than not listing them at all.
--
-- `myCanonicalName`, when known, drops the viewer's own row: a button that
-- targets yourself is useless, and owners do appear in the catalog.
function Core.FilterRoster(rows, catalogIndex, mySide, realm, myCanonicalName)
    local players, seen = {}, {}
    if type(rows) ~= "table" or type(catalogIndex) ~= "table" then return players end
    if mySide == nil then return players end

    for _, row in ipairs(rows) do
        if type(row) == "table" and validName(row.name) then
            local key = Core.NormalizeName(row.name, realm)
            local catalogEntry = key and catalogIndex[key]
            local sideKnown = row.faction ~= nil
            if catalogEntry and sideKnown and not seen[key] and key ~= myCanonicalName then
                seen[key] = true
                players[#players + 1] = {
                    name = row.name,
                    canonicalName = key,
                    classToken = row.classToken,
                    faction = row.faction,
                    side = (row.faction == mySide) and "ally" or "enemy",
                    isLeader = catalogEntry.isLeader and true or false,
                    groups = catalogEntry.groups,
                }
            end
        end
    end

    -- Enemies first (the side you act on), then your own team; leaders head each
    -- section, the rest stay alphabetical so the grid does not reshuffle between
    -- scans.
    table.sort(players, function(a, b)
        if a.side ~= b.side then return a.side == "enemy" end
        if a.isLeader ~= b.isLeader then return a.isLeader end
        return a.canonicalName < b.canonicalName
    end)
    return players
end

function Core.TargetMacro(targetName)
    if not validName(targetName) then return nil end
    return "/cleartarget\n/targetexact " .. targetName
end

-- Right-click: set focus without losing the current target. /targetlasttarget
-- restores whatever we had selected before the macro ran.
function Core.FocusMacro(targetName)
    if not validName(targetName) then return nil end
    return "/targetexact " .. targetName .. "\n/focus\n/targetlasttarget"
end

function Core.ComputeLayout(count, maxColumns)
    count = math.max(0, math.floor(tonumber(count) or 0))
    maxColumns = math.max(1, math.floor(tonumber(maxColumns) or 1))
    if count == 0 then return {}, 0, 0 end

    local columns = math.min(count, maxColumns)
    local rows = math.ceil(count / columns)
    local layout = {}
    for i = 1, count do
        layout[i] = {
            column = ((i - 1) % columns) + 1,
            row = math.floor((i - 1) / columns) + 1,
        }
    end
    return layout, columns, rows
end

-- Side is part of the signature: the same player moving between the enemy and
-- ally sections has to count as a changed secure state, otherwise the deferred
-- combat update would decide nothing happened and leave them under the wrong
-- heading.
function Core.PlayerSignature(players)
    local parts = {}
    for i, player in ipairs(players or {}) do
        parts[i] = tostring(player.name or "") .. "\30" .. tostring(player.side or "")
    end
    return table.concat(parts, "\31")
end

function Core.ShouldDeferSecureUpdate(inCombat, currentSignature, players)
    return inCombat and currentSignature ~= Core.PlayerSignature(players)
end
