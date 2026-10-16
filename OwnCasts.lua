local _, ns = ...
local Safe = ns.Safe
local OwnCasts = {}
ns.OwnCasts = OwnCasts
local PENDING_TTL, MAX_PENDING = 15, 32

-- Only targeted, direct CC. AoE, ground effects, procs, traps and pet orders
-- cannot identify their victims from the player's SENT target name.
local direct = {}
for _, id in ipairs({
    339,1062,5195,5196,9852,9853, -- Entangling Roots
    5211,6798,8983,9005,9823,9827, -- Bash, Pounce
    853,5588,5589,10308,20066, -- Hammer of Justice, Repentance
    1833,408,8643,1776,1777,8629,11285,11286,6770,2070,11297, -- Rogue CC
    12809, -- Concussion Blow
    2637,18657,18658,118,12824,12825,12826,28271,28272, -- Hibernate, Polymorph
    19503,19386,24132,24133,19306,20909,20910,1242634, -- Hunter direct CC
    1513,14326,14327,5782,6213,6215, -- Scare Beast, Fear
    605,10911,10912,8056,8058,10472,10473, -- Mind Control, Frost Shock
}) do direct[id] = id end
-- Reviewed cast -> effect IDs. Never infer DR from the cooldown registry.
direct[20252], direct[20616], direct[20617] = 20253, 20614, 20615 -- Intercept

local function identity(value)
    value = Safe.String(value)
    if value and #value <= 128 and value:match('^Cast%-%w[%w%-]*$') then return value end
end
local function playerGUID(value)
    value = Safe.String(value)
    if value and #value <= 128 and value:match('^Player%-%w[%w%-]*$') then return value end
end
local function spell(value)
    value = Safe.Number(value)
    if value and value > 0 and value == math.floor(value) then return value end
end
-- Character spelling stays exact. Realm names can arrive either with spaces
-- or in the normalized no-space form used by qualified player names.
local function normalizedName(value)
    local name, realm = value:match('^([^%-]+)%-(.+)$')
    if name then return name .. '-' .. realm:gsub('%s', '') end
    return value
end
local function names(unit)
    local found, display = {}, {}
    local function add(value)
        if #value <= 256 then
            found[normalizedName(value)] = true
            display[value] = true
        end
    end
    for _, api in ipairs({UnitFullName or false, UnitName or false}) do
        if type(api) == 'function' then
            local ok, rawName, rawRealm = pcall(api, unit)
            if ok then
                local name, realm = Safe.String(rawName), Safe.String(rawRealm)
                if name and name ~= '' and #name <= 128 then
                    add(name)
                    if realm and realm ~= '' and #realm <= 128 then
                        add(name .. '-' .. realm)
                        -- Forever was observed sending "Björn Janson" when
                        -- UnitName returned "Björn", "Janson". Build that
                        -- exact alias from readable fields; never split or
                        -- guess a realm from arbitrary spaces in the event.
                        add(name .. ' ' .. realm)
                    end
                end
            end
        end
    end
    return found, display
end
local function displayName(value)
    -- Only previously guarded ordinary strings enter this function. Control
    -- codes and WoW markup never enter the copyable diagnostic text.
    return value:sub(1,128):gsub('[%c|]', '?')
end
local function resolution(reason, targetName, aliases)
    OwnCasts.resolutionCounts[reason] = math.min(2147483647, OwnCasts.resolutionCounts[reason] + 1)
    local summary = {reason, 'SENT=[' .. displayName(targetName) .. ']'}
    for _, alias in ipairs(aliases) do
        local shown = {}
        for value in pairs(alias.names or {}) do shown[#shown + 1] = displayName(value) end
        table.sort(shown)
        while #shown > 4 do shown[#shown] = nil end
        summary[#summary + 1] = alias.unit .. ' [' .. alias.status .. '; '
            .. (#shown > 0 and table.concat(shown, ', ') or 'names unavailable') .. ']'
    end
    OwnCasts.lastResolution = table.concat(summary, '; '):sub(1,1024)
end
local function destination(targetName)
    local groups, aliases, unavailable = {}, {}, false
    for _, unit in ipairs({'target', 'focus'}) do
        local alias = {unit=unit, status='identity unavailable'}
        aliases[#aliases + 1] = alias
        local ok, rawGUID = false, nil
        if type(UnitGUID) == 'function' then ok, rawGUID = pcall(UnitGUID, unit) end
        if not ok or not Safe.Readable(rawGUID) then
            unavailable = true
        elseif rawGUID == nil then
            alias.status = 'absent'
        else
            local guid = Safe.String(rawGUID)
            if not guid or #guid > 128 or guid == '' then
                unavailable = true
            else
                local knownNames, display = names(unit)
                alias.names, alias.status = display, playerGUID(guid) and 'player identity' or 'non-player identity'
                local group = groups[guid]
                if not group then group = {names={}, units={}}; groups[guid] = group end
                for value in pairs(knownNames) do group.names[value] = true end
                group.units[#group.units + 1] = unit
            end
        end
    end
    if unavailable then resolution('guidUnavailable', targetName, aliases); return nil end
    -- Aliases of one readable GUID share their readable names. An unreadable
    -- distinct identity still could be the intended same-name destination.
    for _, group in pairs(groups) do
        if not next(group.names) then resolution('nameUnavailable', targetName, aliases); return nil end
    end
    local selected, wanted = nil, normalizedName(targetName)
    for guid, group in pairs(groups) do
        if group.names[wanted] then
            local isPlayer, notPlayer = false, false
            for _, unit in ipairs(group.units) do
                local value = Safe.Boolean(Safe.Call(UnitIsPlayer, unit))
                if value == true then isPlayer = true elseif value == false then notPlayer = true end
            end
            if not playerGUID(guid) or not isPlayer or notPlayer then
                resolution('notPlayer', targetName, aliases); return nil
            end
            if selected and selected ~= guid then resolution('ambiguous', targetName, aliases); return nil end
            selected = guid
        end
    end
    resolution(selected and 'resolved' or 'nameMismatch', targetName, aliases)
    return selected
end
local function prune(now)
    for castID, record in pairs(OwnCasts.pending) do
        if now < record.sentAt or now - record.sentAt >= PENDING_TTL then OwnCasts.pending[castID] = nil end
    end
end
local function enabled()
    if not ns.db or ns.db.ownCastEstimates ~= true then
        OwnCasts.pending = {}
        return false
    end
    return true
end
function OwnCasts.Init()
    OwnCasts.pending = {}
    OwnCasts.stats = {captured = 0, estimated = 0, unresolved = 0, failed = 0}
    OwnCasts.resolutionCounts = {resolved=0, guidUnavailable=0, nameUnavailable=0, nameMismatch=0, notPlayer=0, ambiguous=0}
    OwnCasts.lastResolution = nil
end
function OwnCasts.Sent(unit, targetName, castGUID, spellID, now)
    if Safe.String(unit) ~= 'player' or not enabled() then return false end
    targetName, castGUID, spellID, now = Safe.String(targetName), identity(castGUID), spell(spellID), Safe.Number(now)
    if not targetName or targetName == '' or #targetName > 256 or not castGUID or not spellID or not now then return false end
    prune(now)
    local effectID = direct[spellID]
    local category = effectID and ns.Data.auraCategory[effectID]
    if not category then return false end
    local guid = destination(targetName)
    if not guid then OwnCasts.stats.unresolved = OwnCasts.stats.unresolved + 1; return false end
    if OwnCasts.pending[castGUID] then return false end
    local count, oldestID, oldestTime = 0
    for key, record in pairs(OwnCasts.pending) do
        count = count + 1
        if not oldestTime or record.sentAt < oldestTime then oldestID, oldestTime = key, record.sentAt end
    end
    if count >= MAX_PENDING then OwnCasts.pending[oldestID] = nil end
    OwnCasts.pending[castGUID] = {guid = guid, spellID = spellID, effectID = effectID, category = category, sentAt = now}
    OwnCasts.stats.captured = OwnCasts.stats.captured + 1
    return true
end
function OwnCasts.Succeeded(unit, castGUID, spellID, now)
    if Safe.String(unit) ~= 'player' or not enabled() then return false end
    castGUID, spellID, now = identity(castGUID), spell(spellID), Safe.Number(now)
    if not castGUID or not spellID or not now then return false end
    prune(now)
    local record = OwnCasts.pending[castGUID]
    if not record or record.spellID ~= spellID then return false end
    OwnCasts.pending[castGUID] = nil
    local estimated = ns.model:EstimateDR(record.guid, record.effectID, record.category, now, castGUID, record.sentAt)
    if estimated then OwnCasts.stats.estimated = OwnCasts.stats.estimated + 1 end
    return estimated
end
function OwnCasts.Failed(unit, castGUID, spellID, now)
    if Safe.String(unit) ~= 'player' or not enabled() then return false end
    castGUID, spellID, now = identity(castGUID), spell(spellID), Safe.Number(now)
    if not castGUID or not spellID or not now then return false end
    prune(now)
    local record = OwnCasts.pending[castGUID]
    if not record or record.spellID ~= spellID then return false end
    OwnCasts.pending[castGUID] = nil
    OwnCasts.stats.failed = OwnCasts.stats.failed + 1
    return true
end
