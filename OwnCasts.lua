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
local function names(unit)
    local found = {}
    for _, api in ipairs({UnitFullName or false, UnitName or false}) do
        if type(api) == 'function' then
            local ok, rawName, rawRealm = pcall(api, unit)
            if ok then
                local name, realm = Safe.String(rawName), Safe.String(rawRealm)
                if name and name ~= '' then
                    found[name] = true
                    if realm and realm ~= '' then found[name .. '-' .. realm] = true end
                end
            end
        end
    end
    return found
end
local function destination(targetName)
    local selected
    for _, unit in ipairs({'target', 'focus'}) do
        if type(UnitGUID) ~= 'function' then return nil end
        local ok, rawGUID = pcall(UnitGUID, unit)
        if not ok or not Safe.Readable(rawGUID) then return nil end
        local knownNames = names(unit)
        -- An existing unit with an unreadable name could be another same-name
        -- destination. Refuse that ambiguity instead of selecting the other.
        if rawGUID ~= nil and not next(knownNames) then return nil end
        if knownNames[targetName] then
            local guid = playerGUID(rawGUID)
            if not guid or Safe.Boolean(Safe.Call(UnitIsPlayer, unit)) ~= true then return nil end
            if selected and selected ~= guid then return nil end
            selected = guid
        end
    end
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
