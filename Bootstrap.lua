local addonName, ns = ...
ns.name, ns.version = addonName, '0.4.17.31-foundation-v15-fixes-test'
ns.Safe = {}
local S = ns.Safe

-- Protection checks precede truthiness, comparison, formatting and indexing.
function S.Readable(value)
    if type(issecretvalue) == 'function' then
        local ok, hidden = pcall(issecretvalue, value)
        if not ok or hidden then return false end
    end
    if type(value) == 'table' and type(issecrettable) == 'function' then
        local ok, hidden = pcall(issecrettable, value)
        if not ok or hidden then return false end
    end
    if type(canaccessvalue) == 'function' then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or not accessible then return false end
    end
    return true
end

function S.Number(value)
    if not S.Readable(value) or type(value) ~= 'number' then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function S.String(value)
    if S.Readable(value) and type(value) == 'string' then return value end
end

function S.Boolean(value)
    if S.Readable(value) and type(value) == 'boolean' then return value end
end

function S.Call(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if ok and S.Readable(result) then return result end
end

function S.Field(value, key)
    if not S.Readable(value) or type(value) ~= 'table' then return nil end
    local ok, result = pcall(function() return value[key] end)
    if ok and S.Readable(result) then return result end
end

local placements = { player={-230,-165}, target={230,-165}, focus={230,-230}, cooldown={0,-170} }
local portraitOffsets = { player={0,8}, target={10,0}, focus={10,0} }
local healthOffsets = { player={24,24}, target={-24,24}, focus={-24,24} }
local function defaultUnitPlacement(bar, key)
    bar.anchorKind = 'unit-side'
    bar.offsetX, bar.offsetY = key == 'player' and -18 or 18, 0
    bar.vertical, bar.reverse, bar.maxIcons = false, key == 'player', 4
end
local function bounded(v, default, low, high)
    v = S.Number(v)
    if not v then return default end
    return math.max(low, math.min(high, v))
end
local function bool(v, default)
    if type(v) == 'boolean' then return v end
    return default
end

function ns.InitializeDB()
    local db = type(bjarkiCCDB) == 'table' and bjarkiCCDB or {}
    local savedSchema = S.Number(db.schema) or 0
    local migrateVisualDefaults = savedSchema < 2
    local migrateUnitOffsets = savedSchema < 7
    local migrateCooldownDefault = savedSchema < 8
    db.locked = bool(db.locked, true)
    db.targetOnly = bool(db.targetOnly, false)
    db.interrupts = bool(db.interrupts, false)
    db.ownCastEstimates = bool(db.ownCastEstimates, true)
    -- Keep user-requested AoE estimates for candidates selected
    -- during own War Stomp/Iron Grenade casts. Independent of actual hits.
    db.aoeCastEstimates = bool(db.aoeCastEstimates, true)
    -- Off unless explicitly enabled. This native visual witness does not feed DR.
    db.nativeStunWitness = bool(db.nativeStunWitness, false)
    db.showNames = nil -- Discard the removed caster-name display option.
    db.showDRText = bool(db.showDRText, false)
    db.resetSeconds = bounded(db.resetSeconds, 20, 10, 30)
    db.stageResetSeconds = bounded(db.stageResetSeconds, 18, 10, 30)
    -- Display-only enemy GCD flashes. Never enter DR/cooldown inference.
    local gcd = type(db.gcd) == 'table' and db.gcd or {}
    local gcdBool = {enabled=true,casts=true,buffs=true,debuffs=true,name=false}
    for key, default in pairs(gcdBool) do gcd[key] = bool(gcd[key], default) end
    gcd.size = math.floor(bounded(gcd.size, 36, 24, 50))
    gcd.offset = math.floor(bounded(gcd.offset, 5, 0, 30))
    gcd.nameSize = math.floor(bounded(gcd.nameSize, 9, 8, 16))
    gcd.tenths = math.floor(bounded(gcd.tenths, 15, 5, 40))
    db.gcd = gcd
    db.categories = type(db.categories) == 'table' and db.categories or {}
    for _, category in ipairs(ns.Data.categories) do
        db.categories[category.key] = bool(db.categories[category.key], true)
    end
    db.disabledSpells = type(db.disabledSpells) == 'table' and db.disabledSpells or {}
    db.cooldownOverrides = type(db.cooldownOverrides) == 'table' and db.cooldownOverrides or {}
    for id, seconds in pairs(db.cooldownOverrides) do
        if type(id) ~= 'number' or not S.Number(seconds) or seconds < 1 or seconds > 900 then
            db.cooldownOverrides[id] = nil
        end
    end
    db.bars = type(db.bars) == 'table' and db.bars or {}
    for key, position in pairs(placements) do
        local bar = type(db.bars[key]) == 'table' and db.bars[key] or {}
        if key == 'cooldown' and migrateCooldownDefault then
            -- The old free bar default (0,-280) sat over the native cast bar.
            -- Move only the untouched legacy anchor, never a dragged position.
            local legacyPosition = (bar.x == nil or S.Number(bar.x) == 0)
                and (bar.y == nil or S.Number(bar.y) == -280)
            if legacyPosition then
                -- An unchanged default-on bar is not an explicit choice to use
                -- an unverified combat feed. Leave customized/explicitly
                -- positioned bars enabled, and keep user-disabled bars off.
                local untouchedAppearance =
                    (bar.size == nil or S.Number(bar.size) == 32
                        or (migrateVisualDefaults and S.Number(bar.size) == 40))
                    and (bar.gap == nil or S.Number(bar.gap) == 3
                        or (migrateVisualDefaults and S.Number(bar.gap) == 8))
                    and (bar.vertical == nil or bar.vertical == false)
                    and (bar.reverse == nil or bar.reverse == false)
                    and (bar.maxIcons == nil or S.Number(bar.maxIcons) == 12)
                bar.x, bar.y = 0, -170
                if untouchedAppearance and bar.enabled ~= false then bar.enabled = false end
            end
        end
        if migrateVisualDefaults then
            if S.Number(bar.size) == (key == 'cooldown' and 40 or 36) then
                bar.size = key == 'cooldown' and 32 or 28
            end
            if S.Number(bar.gap) == 8 then bar.gap = 3 end
            bar.label = false
        end
        bar.enabled = bool(bar.enabled, key ~= 'cooldown')
        bar.label = bool(bar.label, false)
        bar.vertical = bool(bar.vertical, key ~= 'cooldown')
        bar.reverse = bool(bar.reverse, key ~= 'cooldown')
        bar.size = bounded(bar.size, key == 'cooldown' and 32 or 28, 24, 72)
        bar.gap = bounded(bar.gap, 3, 0, 30)
        bar.maxIcons = key ~= 'cooldown' and 4 or math.floor(bounded(bar.maxIcons, 12, 3, 30))
        bar.x = bounded(bar.x, position[1], -10000, 10000)
        bar.y = bounded(bar.y, position[2], -10000, 10000)
        if key ~= 'cooldown' then
            if migrateUnitOffsets then
                defaultUnitPlacement(bar, key)
            else
                if bar.anchorKind ~= 'frame' and bar.anchorKind ~= 'portrait'
                    and bar.anchorKind ~= 'health' and bar.anchorKind ~= 'portrait-top' and bar.anchorKind ~= 'unit-side' then
                    defaultUnitPlacement(bar, key)
                end
                local defaults = bar.anchorKind == 'frame' and {6,-8}
                    or bar.anchorKind == 'portrait' and portraitOffsets[key]
                    or bar.anchorKind == 'health' and healthOffsets[key]
                    or bar.anchorKind == 'unit-side' and {key == 'player' and -18 or 18,0} or {0,8}
                bar.offsetX = bounded(bar.offsetX, defaults[1], -10000, 10000)
                bar.offsetY = bounded(bar.offsetY, defaults[2], -10000, 10000)
            end
        end
        db.bars[key] = bar
    end
    db.schema = 8
    bjarkiCCDB, ns.db = db, db
end

function ns.ResetPositions()
    for key, position in pairs(placements) do
        local bar = ns.db.bars[key]
        bar.x, bar.y = position[1], position[2]
        if key ~= 'cooldown' then
            defaultUnitPlacement(bar, key)
        end
    end
end

function ns.Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage('|cffffd36abjarkiCC|r: ' .. message)
    end
end
