-- An accepted reset plus an independent added positive separates uses even
-- when the precise anonymous timestamps share the same rounded identity.
local setup=assert(loadfile((TEST_DIR or ADDON_DIR..'/tests')..'/world_recovery_support.lua'))()
local checks,groups,failures=0,{},{}
local function check(value,why)checks=checks+1;assert(value,why)end
local function near(a,b)return type(a)=='number' and math.abs(a-b)<1e-8 end
local function count(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function test(name,fn)
 local ok,err=pcall(fn);groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(err) or nil}
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function fresh(shared)
 local H=setup();H.units.target='Player-1-R';H.hostile.target=true
 function H.fire(event,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...)end
 function H.aura(at,id,start,expiry,added,stamp)
  H.time(at)
  local a={spellId=5277,isHelpful=true,auraInstanceID=id=='secret' and H.hidden or id}
  if start then a.duration=expiry-start;a.expirationTime=expiry end
  if shared or stamp then H.publish('target',H.units.target,a,stamp or at,added)
  elseif added then H.fire('UNIT_AURA','target',{addedAuras={a}})
  else H.auras.target={[5277]=a};H.fire('UNIT_AURA','target',{isFullUpdate=true});H.auras.target=nil end
 end
 function H.reset(at,id)H.time(at);H.fire('UNIT_SPELLCAST_SUCCEEDED','target',id or 'Cast-Reset',14185)end
 function H.row(at)for _,r in ipairs(H.ns.model:GetCooldowns(at,nil,true))do if r.spellID==5277 then return r end end end
 return H
end
local cases={
 {'same clock corrected',102,102,102,nil,true,false,false},
 {'same clock corrected shared',102,102,102,nil,true,true,false},
 {'30ms corrected',102,102.01,102.03,nil,true,false,false},
 {'secret optional ID',102,102.01,102.03,'secret',true,false,false},
 {'no correction',nil,102.01,102.03,nil,true,false,false},
 {'distinct native ID',102,102.01,102.03,82,true,false,false},
 {'untimed added',102,102.01,102.03,nil,false,false,false},
 {'outside rounded bucket',102,102.01,102.06,nil,true,false,false},
 {'initial anonymous 30ms',nil,100.01,100.03,nil,true,false,true},
 {'initial anonymous equal time',nil,100,100,nil,true,false,true},
 {'initial anonymous untimed',nil,100.01,100.03,nil,false,false,true},
}
for _,c in ipairs(cases)do
 test(c[1],function()
  local correction,reset,activation,id,precise,shared,anonymous=c[2],c[3],c[4],c[5],c[6],c[7],c[8]
  local H=fresh(shared);local initialID=81;if anonymous then initialID=nil end
  H.aura(100,initialID,100,115,true)
  local old=assert(H.row(100)).claimID
  if correction then
   H.aura(correction,nil,correction,115,false)
   check(H.row(correction).claimID==old and H.row(correction).started==100,'duration-only correction keeps original occurrence')
  end
  H.reset(reset);check(H.row(reset)==nil,'accepted reset clears old cooldown')
  H.aura(activation,id,precise and activation or nil,activation+15,true)
  local r=H.row(activation)
  check(r~=nil,'independent post-reset added positive must have a cooldown')
  check(r.claimID~=old and near(r.started,activation),'new occurrence starts at its own activation')
  local claim=r.claimID
  H.aura(activation+.01,id,precise and activation or nil,activation+15,true)
  check(H.row(activation+.01).claimID==claim,'duplicate added positive stays one occurrence')
  H.aura(activation+1,id,precise and activation or nil,activation+15,false)
  check(H.row(activation+1).claimID==claim,'ordinary lookup keeps accepted occurrence')
  H.aura(activation+1.5,id,precise and activation or nil,activation+15,true)
  check(H.row(activation+1.5).claimID==claim,'delayed duplicate added positive stays one occurrence')
  H.aura(activation+2,81,100,115,false,100)
  check(H.row(activation+2).claimID==claim and near(H.row(activation+2).started,activation),'old pre-reset source sample cannot rewrite accepted occurrence')
 end)
end
test('ordinary rounded alias cannot spend reset or later acquire new occurrence ownership',function()
 local H=fresh();H.aura(100,81,100,115,true);H.aura(102,nil,102,115,false)
 local alias='Player-1-R:5277:start:1020'
 check(H.ns.CooldownEvidence.seenHelpful[alias]~=nil,'correction alias was witnessed')
 H.reset(102.01)
 H.aura(102.02,nil,102.02,115,false)
 check(H.row(102.02)==nil,'ordinary duration correction cannot spend reset')
 H.aura(102.03,nil,102.03,117.03,true)
 local row=H.row(102.03);check(row~=nil,'old alias cannot suppress new positive')
 local claim=row.claimID
 H.aura(102.04,81,102,115,false)
 H.aura(102.05,nil,102,115,false)
 check(H.row(102.05).claimID==claim and near(H.row(102.05).started,102.03),'old native and anonymous aliases cannot rewrite new claim')
 local app=H.ns.CooldownEvidence.helpfulApplications['Player-1-R:5277']
 check(app.instance~=81,'old native alias cannot acquire new occurrence ownership')
 check(H.ns.CooldownEvidence.seenHelpful[alias]~=nil,'historical alias remains deduplicated')
end)
test('same-clock old correction alias cannot replace new occurrence endpoint',function()
 local H=fresh();H.aura(100,81,100,115,true);H.aura(102,nil,102,115,false)
 H.reset(102);H.aura(102,nil,102,117,true)
 local row=H.row(102);check(row~=nil,'same-clock independent positive remains visible')
 H.aura(102.1,nil,102,115,false)
 check(H.row(102.1).claimID==row.claimID,'old correction alias does not create another occurrence')
 H.reset(103,'Cast-Reset-Second')
 H.aura(104,nil,104,117,false)
 check(H.row(104)==nil,'old alias cannot replace endpoint117 and authorize false post-reset renewal')
end)
test('same-bucket current endpoint corrections retain authority',function()
 local H=fresh();H.aura(100,81,100,115,true);H.aura(102,nil,102,115,false)
 H.reset(102);H.aura(102,nil,102,117,true)
 local row=H.row(102);check(row~=nil,'independent positive remains visible')
 H.aura(102.1,nil,102,118,false)
 check(H.row(102.1).claimID==row.claimID,'current endpoint extension stays the same occurrence')
 H.reset(103,'Cast-Reset-Second');H.aura(104,nil,104,118,false)
 check(H.row(104)==nil,'current corrected endpoint remains authoritative across the next reset')
 H.aura(105,nil,105,119,false)
 check(H.row(105)~=nil and H.row(105).started==105,'genuinely later boundaries remain accepted')
end)
test('known pre-reset primary endpoint cannot refine a fresh estimated occurrence',function()
 for _,oldEnd in ipairs({115,115.05,114.9}) do
  local H=fresh();H.aura(100,81,100,115,true)
  local old=assert(H.row(100)).claimID
  H.aura(102,81,102,115,false)
  check(H.row(102).claimID==old and H.row(102).started==100,'known native duration correction retains old occurrence')
  H.reset(102);check(H.row(102)==nil,'accepted reset clears old occurrence')
  H.aura(103,nil,nil,nil,true)
  local row=assert(H.row(103))
  check(row.claimID~=old and row.started==103 and row.timingEstimated,'independent untimed positive owns a fresh estimated claim')
  H.aura(103.1,81,102,oldEnd,false)
  local after=assert(H.row(103.1))
  check(after.claimID==row.claimID and after.started==103 and after.timingEstimated,
   'historical primary native endpoint cannot retime the fresh estimate')
  local app=H.ns.CooldownEvidence.helpfulApplications['Player-1-R:5277']
  check(app.instance~=81,'historical primary native ID cannot acquire the fresh occurrence')
  H.aura(103.2,82,103,118,false);after=assert(H.row(103.2))
  check(after.claimID==row.claimID and after.started==103 and not after.timingEstimated,
   'new native timing refines the same claim after historical replay is rejected')
  H.aura(104,82,103,118,false)
  check(H.row(104).claimID==row.claimID and H.row(104).started==103,'later new-native replay retains its accepted timing')
 end
end)
test('repeated same-time reset and positive pairs remain distinct and bounded',function()
 local H=fresh();H.aura(100,nil,100,115,true)
 local old=assert(H.row(100)).claimID
 for i=1,400 do
  H.reset(100,'Cast-Reset-'..i);check(H.row(100)==nil,'each accepted reset clears cooldown')
  H.aura(100,nil,100,115,true)
  local row=H.row(100);check(row~=nil and row.claimID~=old,'each ordered reset/use pair creates a distinct claim')
  old=row.claimID
  H.aura(100,nil,100,115,true);check(H.row(100).claimID==old,'duplicate positive cannot create another claim')
 end
 local E=H.ns.CooldownEvidence;local caster=H.ns.model.casters[H.units.target]
 check(count(E.seenHelpful)<=256,'seen witness cap remains bounded')
 check(count(E.helpfulApplications)<=256 and count(E.unknownHelpful)<=256,'continuity caps remain bounded')
 check(count(caster.castIDs)<=128 and count(caster.recent)<=2,'native and recent matching caps remain bounded')
 check(#H.ns.model.claimActivity<=64,'claim explanation cap remains bounded')
end)
TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
