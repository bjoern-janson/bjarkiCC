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
    UnitCanAttack=function(_,unit)
        if fixture[unit] then return fixture[unit].hostile~=false end
    end
    UnitCanAssist=function(_,unit)
        if fixture[unit] then return fixture[unit].friendly==true end
    end
    ns.db={ownCastEstimates=true,aoeCastEstimates=true}; ns.model=ns.Model.New(20); ns.OwnCasts.Init()
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
    for _,id in ipairs({2094,6789,1766,1499,19577,122,8122,100,999999}) do
        eq(ns.OwnCasts.Sent('player','Enemy','Cast-'..id,id,10),false,'excluded spell '..id)
    end
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-1',20252,10),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-1',20252,11),true)
    eq(rows()[1].spellID,20253); eq(rows()[1].category,'stun')
end)
test('War Stomp and grenade create visibly marked, unconfirmed shared-stun guesses',function()
    reset()
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-bash',5211,10),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-bash',5211,10.1),true)
    eq(rows(nil,10.1)[1].stage,1)
    eq(ns.OwnCasts.Sent('player','', 'Cast-stomp',20549,11),true)
    eq(rows(nil,11)[1].stage,1,'sending area cast cannot advance a stage')
    eq(ns.OwnCasts.Succeeded('player','Cast-stomp',20549,11.5),true)
    local r=rows(nil,11.5)[1]
    eq(r.stage,2); eq(r.spellID,20549); eq(r.category,'stun')
    eq(r.estimateKind,'aoe'); eq(r.estimated,true); eq(r.uncertain,true)
    eq(ns.model.units['Player-1-A'],nil,'possible hit cannot become observed application')
    eq(ns.OwnCasts.stats.estimated,1,'direct estimates remain separate')
    eq(ns.OwnCasts.stats.aoeEstimated,2,'target and focus are both possible, not asserted, victims')
    eq(ns.OwnCasts.Sent('player','', 'Cast-grenade',4068,12),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-grenade',4068,12.1),true)
    r=rows(nil,12.1)[1]
    eq(r.stage,3); eq(r.spellID,4068); eq(r.estimateKind,'aoe')
    eq(ns.OwnCasts.Sent('player','', 'Cast-immune',20549,13),true)
    -- The target is predicted immune, but a separately tracked focus could
    -- still advance to stage three. Its speculative hit must never shift
    -- the first target's established clock.
    eq(ns.OwnCasts.Succeeded('player','Cast-immune',20549,13.5),true)
    r=rows(nil,13.5)[1]
    eq(r.stage,3); eq(r.started,12.1,'immune target cannot have its existing timer prolonged')
end)

test('same target/focus GUID receives one area estimate, not a double stage',function()
    reset(); fixture.focus.guid=fixture.target.guid
    eq(ns.OwnCasts.Sent('player','', 'Cast-stomp',20549,10),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-stomp',20549,10.5),true)
    eq(rows(nil,10.5)[1].stage,1)
    eq(ns.OwnCasts.stats.aoeEstimated,1)
    eq(ns.OwnCasts.Succeeded('player','Cast-stomp',20549,11),false)
    eq(rows(nil,11)[1].stage,1,'duplicate success never redirects/replays')
end)

test('AoE targets are snapped at SENT and START, not redirected by target swaps',function()
    reset(); fixture.focus=nil
    eq(ns.OwnCasts.Sent('player','', 'Cast-nade',4068,10),true)
    fixture.target={guid='Player-1-C',name='Third',realm='R'}
    eq(ns.OwnCasts.Succeeded('player','Cast-nade',4068,10.5),true)
    eq(rows('Player-1-A',10.5)[1].spellID,4068)
    eq(#rows('Player-1-C',10.5),0)
    reset(); fixture.focus=nil
    eq(ns.OwnCasts.Started('player','Cast-stomp',20549,10),true)
    fixture.target.guid='Player-1-C'
    eq(ns.OwnCasts.Succeeded('player','Cast-stomp',20549,10.5),true)
    eq(rows('Player-1-A',10.5)[1].spellID,20549)
    eq(#rows('Player-1-C',10.5),0)
end)

test('success-only AoE fallback uses currently selected player, still only an estimate',function()
    reset(); fixture.focus=nil
    eq(ns.OwnCasts.Succeeded('player','Cast-solo',4068,10),true)
    local r=rows(nil,10)[1]
    eq(r.estimated,true); eq(r.estimateKind,'aoe'); eq(r.spellID,4068)
    eq(ns.OwnCasts.stats.aoeSuccessOnly,1)
    eq(ns.OwnCasts.lastAoE.source,'success-only')
    eq(ns.OwnCasts.Succeeded('player','Cast-solo',4068,11),false)
    eq(rows(nil,11)[1].started,10)
end)

test('item-use success without normal cast GUID is deduplicated and remains uncertain',function()
    reset(); fixture.focus=nil
    eq(ns.OwnCasts.Succeeded('player',nil,4068,10),true)
    eq(ns.OwnCasts.stats.aoeNoCastGUID,1)
    eq(rows(nil,10)[1].stage,1)
    eq(ns.OwnCasts.Succeeded('player',nil,4068,10.1),false)
    eq(rows(nil,10.1)[1].stage,1)
    eq(ns.OwnCasts.Succeeded('player',nil,4068,11),true)
    eq(rows(nil,11)[1].stage,2)
    eq(ns.OwnCasts.stats.aoeNoCastGUID,2)
end)

test('AoE failure, cancellation and orphan stale successes cannot make a guess',function()
    reset()
    eq(ns.OwnCasts.Sent('player','', 'Cast-cancel',4068,10),true)
    eq(ns.OwnCasts.Failed('player','Cast-cancel',4068,10.1),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-cancel',4068,10.2),false)
    eq(#rows('Player-1-A',10.2),0)
    eq(ns.OwnCasts.Failed('player','Cast-orphan',20549,10.2),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-orphan',20549,10.3),false)
    eq(ns.OwnCasts.stats.aoeFailed,2)
    eq(ns.OwnCasts.Succeeded('target','Cast-other',4068,10.3),false)
    eq(ns.OwnCasts.Succeeded('player',secret,4068,10.3),false)
    eq(#rows('Player-1-A',10.3),0)
end)

test('AoE friend, nonplayer and explicitly nonhostile tokens never become candidates',function()
    reset()
    fixture.target.hostile=false; fixture.focus.friendly=true
    eq(ns.OwnCasts.Sent('player','', 'Cast-stomp',20549,10),false)
    eq(ns.OwnCasts.Succeeded('player','Cast-stomp',20549,10.5),false)
    eq(#rows('Player-1-A',10.5),0)
    eq(ns.OwnCasts.stats.aoeNoCandidates,1)
    reset(); fixture.target.isPlayer=false; fixture.focus.guid='Creature-1-NPC'
    eq(ns.OwnCasts.Succeeded('player','Cast-no-victim',4068,10),false)
    eq(#rows('Player-1-A',10),0)
end)

test('area estimates are optional and follow the master estimate switch',function()
    reset(); ns.db.aoeCastEstimates=false
    eq(ns.OwnCasts.Sent('player','', 'Cast-stomp',20549,10),false)
    eq(ns.OwnCasts.Succeeded('player','Cast-stomp',20549,10.5),false)
    eq(#rows('Player-1-A',10.5),0)
    ns.db.aoeCastEstimates=true
    eq(ns.OwnCasts.Sent('player','', 'Cast-grenade',4068,11),true)
    ns.db.ownCastEstimates=false
    eq(ns.OwnCasts.Succeeded('player','Cast-grenade',4068,11.2),false)
    eq(#rows('Player-1-A',11.2),0)
end)

test('confirmed target stun wins over AoE guess instead of advancing observed stage',function()
    reset(); fixture.focus=nil
    eq(ns.OwnCasts.Sent('player','', 'Cast-stomp',20549,10),true)
    ns.model:Observe('Player-1-A',{hit={category='stun',spellID=20549,
        appliedAt=10.1,expires=12.1,applicationSource='aura'}},10.1,true)
    eq(ns.OwnCasts.Succeeded('player','Cast-stomp',20549,10.2),false)
    local r=rows(nil,10.2)[1]
    eq(r.estimated,false); eq(r.stage,1)
    eq(r.spellID,20549)
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
test('readable names from one alias resolve another alias of the same GUID',function()
    reset(); fixture.focus.guid=fixture.target.guid; fixture.focus.name=secret
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-alias',853,10),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-alias',853,10.1),true)
    eq(rows(nil,10.1)[1].stage,1)
    eq(ns.OwnCasts.resolutionCounts.resolved,1)
    assert(ns.OwnCasts.lastResolution:find('resolved',1,true))
end)
test('realm whitespace is normalized without changing character spelling or realm identity',function()
    reset(); fixture.target.name='Björn'; fixture.target.realm='Test Realm'; fixture.focus=nil
    eq(ns.OwnCasts.Sent('player','Björn-TestRealm','Cast-realm-1',118,10),true)
    eq(ns.OwnCasts.Sent('player','Björn-Test Realm','Cast-realm-2',118,10),true)
    eq(ns.OwnCasts.Sent('player','Bjorn-TestRealm','Cast-realm-3',118,10),false)
    eq(ns.OwnCasts.Sent('player','Björn-OtherRealm','Cast-realm-4',118,10),false)
    eq(ns.OwnCasts.resolutionCounts.nameMismatch,2)
end)
test('Forever space-qualified SENT name resolves the readable character and realm',function()
    reset(); fixture.target.name='Björn'; fixture.target.realm='Janson'
    fixture.focus={guid=fixture.target.guid,name='Björn',realm='Janson'}
    eq(ns.OwnCasts.Sent('player','Björn Janson','Cast-forever-name',118,10),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-forever-name',118,11.5),true)
    local r=rows(nil,11.5)[1]
    eq(r.estimated,true); eq(r.stage,1); eq(r.started,11.5); eq(r.remaining,20)
    eq(ns.OwnCasts.stats.captured,1); eq(ns.OwnCasts.stats.unresolved,0)
    eq(ns.OwnCasts.Sent('player','Björn Janson','Cast-forever-next',118,15),true)
    eq(ns.OwnCasts.Succeeded('player','Cast-forever-next',118,16.5),true)
    r=rows(nil,16.5)[1]; eq(r.stage,2); eq(r.started,16.5); eq(r.remaining,20)
    eq(ns.OwnCasts.Sent('player','Bjorn Janson','Cast-wrong-spelling',118,17),false)
    eq(ns.OwnCasts.Sent('player','Björn OtherRealm','Cast-wrong-realm',118,17),false)
    fixture.focus={guid='Player-1-B',name='Björn',realm='Janson'}
    eq(ns.OwnCasts.Sent('player','Björn Janson','Cast-ambiguous-qualified',118,17),false)
    eq(ns.OwnCasts.resolutionCounts.ambiguous,1)
end)
test('unknown distinct identities and ambiguous names remain unresolved',function()
    reset(); fixture.focus.name=secret
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-hidden-name',853,10),false)
    eq(ns.OwnCasts.resolutionCounts.nameUnavailable,1)
    fixture.focus.guid=secret
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-hidden-guid',853,10),false)
    eq(ns.OwnCasts.resolutionCounts.guidUnavailable,1)
    fixture.focus={guid='Player-1-B',name='Enemy',realm='RealmTwo'}
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-ambiguous',853,10),false)
    eq(ns.OwnCasts.resolutionCounts.ambiguous,1)
    fixture.target.isPlayer=false
    eq(ns.OwnCasts.Sent('player','Enemy-RealmOne','Cast-nonplayer',853,10),false)
    eq(ns.OwnCasts.resolutionCounts.notPlayer,1)
end)
test('destination diagnostics are bounded and contain only readable display values',function()
    reset(); fixture.focus.name=secret; fixture.focus.realm=secret
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-diagnostic',853,10),false)
    assert(type(ns.OwnCasts.lastResolution)=='string' and #ns.OwnCasts.lastResolution<=1024)
    assert(ns.OwnCasts.lastResolution:find('nameUnavailable',1,true))
    assert(ns.OwnCasts.lastResolution:find('Enemy',1,true))
    fixture.target.name=string.rep('A',2000)
    eq(ns.OwnCasts.Sent('player','Enemy','Cast-diagnostic-long',853,10),false)
    assert(#ns.OwnCasts.lastResolution<=1024)
    ns.OwnCasts.Init(); eq(ns.OwnCasts.lastResolution,nil)
    for _,count in pairs(ns.OwnCasts.resolutionCounts) do eq(count,0) end
end)
local failed=0
for _,case in ipairs(tests) do
    local ok,err=pcall(case[2]); if ok then print('PASS '..case[1]) else failed=failed+1; print('FAIL '..case[1]..': '..tostring(err)) end
end
print(string.format('OwnCasts: %d passed, %d failed',#tests-failed,failed))
assert(failed==0,'own-cast boundary tests failed')
