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

function Core.FilterRoster(rows, catalogIndex, myFaction, realm)
    local players, seen = {}, {}
    if type(rows) ~= "table" or type(catalogIndex) ~= "table" then return players end

    for _, row in ipairs(rows) do
        if type(row) == "table" and validName(row.name) then
            local key = Core.NormalizeName(row.name, realm)
            local catalogEntry = key and catalogIndex[key]
            local isEnemy = myFaction ~= nil and row.faction ~= nil and row.faction ~= myFaction
            if catalogEntry and isEnemy and not seen[key] then
                seen[key] = true
                players[#players + 1] = {
                    name = row.name,
                    canonicalName = key,
                    classToken = row.classToken,
                    role = row.role,
                    faction = row.faction,
                    isLeader = catalogEntry.isLeader and true or false,
                    groups = catalogEntry.groups,
                }
            end
        end
    end

    table.sort(players, function(a, b)
        if a.isLeader ~= b.isLeader then return a.isLeader end
        return a.canonicalName < b.canonicalName
    end)
    return players
end

function Core.TargetMacro(targetName)
    if not validName(targetName) then return nil end
    return "/cleartarget\n/targetexact " .. targetName
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

function Core.PlayerSignature(players)
    local names = {}
    for i, player in ipairs(players or {}) do
        names[i] = tostring(player.name or "")
    end
    return table.concat(names, "\31")
end

function Core.ShouldDeferSecureUpdate(inCombat, currentSignature, players)
    return inCombat and currentSignature ~= Core.PlayerSignature(players)
end
