-- Predictions use correlated player events; these fixtures do not prove a hit.
local ns = {}
local secret = setmetatable({}, {__index=function() error('secret indexed') end,
    __tostring=function() error('secret formatted') end, __lt=function() error('secret compared') end})
issecretvalue = function(v) return rawequal(v,secret) end
issecrettable = issecretvalue
canaccessvalue = function(v) return not rawequal(v,secret) end
assert(loadfile(ADDON_DIR .. '/Bootstrap.lua'))('bjarkiCC',ns)
assert(loadfile(ADDON_DIR .. '/Data.lua'))('bjarkiCC',ns)
assert(loadfile(ADDON_DIR .. '/Model.lua'))('bjarkiCC',ns)
assert(loadfile(ADDON_DIR .. '/OwnCasts.lua'))('bjarkiCC',ns)
local fixture
local function eq(a,b,label) assert(a==b,(label or 'value')..': expected '..tostring(b)..', got '..tostring(a)) end
local function reset()
    fixture={target={guid='Player-1-A',name='Enemy',realm='RealmOne'},focus={guid='Player-1-B',name='Other',realm='RealmTwo'}}
    UnitGUID=function(unit) return fixture[unit] and fixture[unit].guid end
    UnitName=function(unit) if fixture[unit] then return fixture[unit].name,fixture[unit].realm end end
    UnitFullName=UnitName
    UnitIsPlayer=function(unit) return fixture[unit] and fixture[unit].isPlayer~=false end
    ns.db={ownCastEstimates=true}; ns.model=ns.Model.New(20); ns.OwnCasts.Init()
end
local function rows(guid,now) return ns.model:GetDR(guid or 'Player-1-A',now or 11) end
local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end
test('outgoing cast waits for success and remains an estimate',function()
    reset(); eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10),true); eq(#rows(),0)
    eq(ns.OwnCasts.Succeeded('player','Cast-1',853,11),true)
    local r=rows()[1]; eq(r.estimated,true); eq(r.uncertain,true); eq(r.started,11); eq(r.spellID,853)
    eq(ns.model.units['Player-1-A'],nil)
    eq(ns.OwnCasts.Succeeded('player','Cast-1',853,12),false); eq(rows(nil,12)[1].stage,1)
end)
test('focus destination survives current-target switches',function()
    reset(); eq(ns.OwnCasts.Sent('player','Other-RealmTwo','Cast-1',118,10),true)
    fixture.target={guid='Player-1-C',name='Third'}; fixture.focus=nil
    eq(ns.OwnCasts.Succeeded('player','Cast-1',118,12),true)
    eq(#rows('Player-1-C',12),0); eq(rows('Player-1-B',12)[1].spellID,118)
end)
test('ambiguous names are refused while a shared GUID is unambiguous',function()
    reset(); fixture.focus.name='Enemy'
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10),false)
    eq(ns.OwnCasts.Sent('player','Enemy-RealmOne','Cast-2',853,10),true)
    fixture.focus.guid='Player-1-A'
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-3',853,10),true)
end)
test('failure, interruption, orphan success and timeout never seed a prediction',function()
    reset(); eq(ns.OwnCasts.Succeeded('player','Cast-1',853,10),false)
    ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10)
    eq(ns.OwnCasts.Failed('player','Cast-1',853,10.2),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-1',853,11),false)
    ns.OwnCasts.Sent('player','Enemy','Cast-2',118,10)
    eq(ns.OwnCasts.Succeeded('player','Cast-2',118,25),false); eq(#rows(nil,25),0)
end)
test('success must match the original spell and cast identity',function()
    reset(); ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10)
    eq(ns.OwnCasts.Succeeded('target','Cast-1',853,11),false)
    eq(ns.OwnCasts.Succeeded('player','Cast-2',853,11),false)
    eq(ns.OwnCasts.Succeeded('player','Cast-1',118,11),false)
    eq(ns.OwnCasts.Succeeded('player','Cast-1',853,11),true)
end)
test('only reviewed direct CC can estimate a destination',function()
    reset()
    for _,id in ipairs({2094,6789,1766,1499,19577,122,8122,20549,100,999999}) do
        eq(ns.OwnCasts.Sent('player','Enemy','Cast-'..id,id,10),false,'excluded spell '..id)
    end
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',20252,10),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-1',20252,11),true)
    eq(rows()[1].spellID,20253); eq(rows()[1].category,'stun')
end)
test('disabled estimates cannot leave pending casts for a later enable',function()
    reset(); ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10)
    ns.db.ownCastEstimates=false
    eq(ns.OwnCasts.Succeeded('player','Cast-1',853,11),false)
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-2',853,11),false)
    ns.db.ownCastEstimates=true
    eq(ns.OwnCasts.Succeeded('player','Cast-1',853,12),false); eq(#rows(nil,12),0)
end)
test('secret and malformed inputs never become identities or arithmetic',function()
    reset()
    for _,args in ipairs({{secret,'Enemy','Cast-1',853,10},{'player',secret,'Cast-1',853,10},
        {'player','Enemy',secret,853,10},{'player','Enemy','Cast-1',secret,10},
        {'player','Enemy','Cast-1',853,secret},{'player','Enemy','Cast-1',853,math.huge},
        {'player','Enemy','',853,10},{'player','Enemy','not-a-cast',853,10}}) do
        eq(ns.OwnCasts.Sent(unpack(args)),false)
    end
    fixture.target.guid=secret; eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10),false)
    reset(); fixture.target.name=secret; eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10),false)
    reset(); fixture.focus.name=secret; eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10),false)
    reset(); fixture.target.isPlayer=false; eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',853,10),false)
end)
test('pending casts stay bounded and an API error fails closed',function()
    reset()
    for i=1,100 do ns.OwnCasts.Sent('player','Enemy','Cast-'..i,853,10+i/100) end
    local count=0; for _ in pairs(ns.OwnCasts.pending) do count=count+1 end; eq(count,32)
    UnitGUID=function() error('not readable') end
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-101',853,12),false)
end)
local failed=0
for _,case in ipairs(tests) do
    local ok,err=pcall(case[2]); if ok then print('PASS '..case[1]) else failed=failed+1; print('FAIL '..case[1]..': '..tostring(err)) end
end
print(string.format('OwnCasts: %d passed, %d failed',#tests-failed,failed))
assert(failed==0,'own-cast boundary tests failed')
