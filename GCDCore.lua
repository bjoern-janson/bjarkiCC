-- Compact, display-only enemy GCD flash feed adapted from Forever Simple GCD 0.3.0.
-- Original by tarolg (MIT); see THIRD_PARTY_NOTICES.txt.
-- This module never feeds hidden enemy spell data to bjarkiCC's DR/cooldown model.
local _, root = ...
local Safe = root.Safe
local GCD = {}
root.GCD = GCD

GCD.COLORS = { cast={.95,.76,.35}, buff={.3,.85,.35}, debuff={.9,.25,.2} }
GCD.POSITIONS = {'left'}
GCD.POSITION_LABELS = {left='Left'}

function GCD.Public(value)
    return Safe.Readable(value)
end
function GCD.Yes(value) return Safe.Boolean(value) == true end
function GCD.Number(value) return Safe.Number(value) ~= nil end
function GCD.Text(value) return Safe.String(value) ~= nil end

local defaults = {
    enabled=true, casts=true, buffs=true, debuffs=true,
    size=36, offset=5, name=false, nameSize=9, tenths=15,
}
GCD.DEFAULTS = defaults
local options = {enabled=true,casts=true,buffs=true,debuffs=true,name=true,size=true,offset=true,nameSize=true,tenths=true}

function GCD.Get(key)
    if key == 'plates' then key='enabled' end
    if key == 'position' then return 'left' end
    local db = root.db and root.db.gcd
    if db and db[key] ~= nil then return db[key] end
    return defaults[key]
end
function GCD.Seconds() return GCD.Get('tenths')/10 end

function GCD.Set(key,value)
    local db = root.db and root.db.gcd
    if not db or not options[key] then return false end
    -- Changing secure aura hosts and native buttons is a structural operation.
    -- Unknown combat state is not permission to mutate them.
    if type(InCombatLockdown)=='function' then
        local locked = Safe.Boolean(Safe.Call(InCombatLockdown))
        if locked ~= false then
            if root.Print then root.Print('Change GCD flash settings outside combat.') end
            return false
        end
    end
    if type(value) ~= type(defaults[key]) then return false end
    if type(value) == 'number' then
        if value ~= value or value == math.huge or value == -math.huge or value ~= math.floor(value) then return false end
        if key == 'size' then value=math.max(24,math.min(50,value))
        elseif key == 'nameSize' then value=math.max(8,math.min(16,value))
        elseif key == 'offset' then value=math.max(0,math.min(30,value))
        elseif key == 'tenths' then value=math.max(5,math.min(40,value)) end
    end
    if db[key] == value then return true end
    db[key]=value
    if GCD.PlatesApply then GCD.PlatesApply({key == 'enabled' and 'plates' or key}) end
    if GCD.FlashApply then GCD.FlashApply({key}) end
    return true
end

function GCD.Start()
    if GCD.StartPlates then GCD.StartPlates() end
end
function GCD.Status()
    local count = GCD.PlateCount and GCD.PlateCount() or 0
    return string.format('GCD flashes %s; %d hostile plates; %dpx; leftward; casts=%s buffs=%s duel-debuffs=%s',
        GCD.Get('enabled') and 'ON' or 'OFF',count,GCD.Get('size'),
        GCD.Get('casts') and 'on' or 'off',GCD.Get('buffs') and 'on' or 'off',
        GCD.Get('debuffs') and 'on' or 'off')
end
