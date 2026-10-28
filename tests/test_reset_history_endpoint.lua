-- Conditional bounded source-contract stress: native server legality of two
-- accepted Preparations inside two seconds is NOT established by these fixtures.
-- All activations use Main events or the real shared bus; no state is rewritten.
local setup=assert(loadfile((TEST_DIR or ADDON_DIR..'/tests')..'/world_recovery_support.lua'))()
local checks,groups,failures=0,{},{}
local function check(value,why)checks=checks+1;assert(value,why)end
local function count(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function test(name,fn)
 local ok,err=pcall(fn);groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(err) or nil}
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function fresh()
 local H=setup();H.units.target='Player-1-R';H.hostile.target=true
 function H.fire(event,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...)end
 function H.aura(at,id,start,expiry,added,shared,stamp)
  H.time(at);local a={spellId=5277,isHelpful=true,auraInstanceID=id}
  if start then a.duration=expiry-start;a.expirationTime=expiry end
  if shared then assert(H.publish('target',H.units.target,a,stamp or at,added))
  elseif added then H.fire('UNIT_AURA','target',{addedAuras={a}})
  else H.auras.target={[5277]=a};H.fire('UNIT_AURA','target',{isFullUpdate=true});H.auras.target=nil end
 end
 function H.row(at)for _,r in ipairs(H.ns.model:GetCooldowns(at,nil,true))do if r.spellID==5277 then return r end end end
 function H.app()return H.ns.CooldownEvidence.helpfulApplications['Player-1-R:5277']end
 function H.reset(at,id)
  H.time(at);H.fire('UNIT_SPELLCAST_SUCCEEDED','target',id or ('Reset-'..at),14185)
  check(H.row(at)==nil,'accepted reset clears the current cooldown')
 end
 function H.cycles()
  H.reset(102);H.aura(103,nil,nil,nil,true)
  check(assert(H.row(103)).timingEstimated,'first fresh occurrence is estimated')
  H.reset(104);H.aura(105,nil,nil,nil,true)
  check(assert(H.row(105)).timingEstimated,'second fresh occurrence is estimated')
  return H.row(105).claimID
 end
 function H.clean()check(H.ns.EvidenceBus.stats.errors==0,'shared-bus fixture has no consumer errors')end
 return H
end
local function remainsEstimated(H,at,claim,start)
 local row=assert(H.row(at))
 check(row.claimID==claim and row.started==start and row.timingEstimated,
  'historical native timing must not rewrite the independently accepted estimate')
 check(H.app().instance~=81,'historical native must not acquire current application ownership')
end
local function refines(H,at,claim,start,id,finish)
 H.aura(at,id,start,finish,false)
 local row=assert(H.row(at))
 check(row.claimID==claim and row.started==start and not row.timingEstimated,
  'fresh native timing must refine the same accepted claim')
 check(H.app().instance==id,'fresh native becomes the current application ID')
end
for _,shared in ipairs({false,true})do
 for _,oldEnd in ipairs({115,115.05,114.9})do
  test('retained old endpoint after two untimed resets '..tostring(shared)..' '..oldEnd,function()
   local H=fresh();H.aura(100,81,100,115,true);H.aura(102,81,102,115,false)
   local claim=H.cycles();H.aura(105.1,81,104,oldEnd,false,shared)
   remainsEstimated(H,105.1,claim,105)
   refines(H,105.2,claim,105,82,120);H.clean()
  end)
 end
end
for _,shared in ipairs({false,true})do
 test('unknown old primary endpoint can learn first readable timing '..tostring(shared),function()
  local H=fresh();H.aura(100,81,nil,nil,true)
  local claim=H.cycles();H.aura(105.1,81,104,119,false,shared)
  local row=assert(H.row(105.1))
  check(row.claimID==claim and row.started==104 and not row.timingEstimated,
   'primary native with no prior readable endpoint can refine its first clock')
  check(H.app().instance==81,'compatible first native clock gains current ownership');H.clean()
 end)
end
test('fresh unrelated native is not constrained by a historical long endpoint',function()
 local H=fresh();H.aura(100,81,100,200,true)
 local claim=H.cycles();refines(H,105.1,claim,105,82,110);H.clean()
end)
test('existing immediate-reset boundary still restricts historical primary reuse',function()
 local H=fresh();H.aura(100,81,100,115,true)
 H.reset(102);H.aura(103,82,103,130,true)
 check(H.app().instance==82 and H.app().expiry==130,'intermediate native has distinct larger endpoint')
 H.reset(104);H.aura(105,nil,nil,nil,true)
 local claim=assert(H.row(105)).claimID;H.aura(105.1,81,104,120,false)
 remainsEstimated(H,105.1,claim,105)
 refines(H,105.2,claim,105,83,121);H.clean()
end)
test('latest legitimate shortening replaces the historical maximum',function()
 local H=fresh();H.aura(100,81,100,130,true);H.aura(101,81,100,115,false)
 check(H.app().expiry==115,'compatible fresh endpoint shortening is retained')
 local claim=H.cycles();refines(H,105.1,claim,104,81,120);H.clean()
end)
test('delayed longer shared endpoint cannot undo the latest shortening',function()
 local H=fresh();H.aura(100,81,100,130,true);H.aura(101,81,100,115,false)
 H.aura(101.1,81,100,130,false,true,100.5)
 check(H.app().expiry==115,'old source does not undo the latest compatible shortening')
 local claim=H.cycles();refines(H,105.1,claim,104,81,120);H.clean()
end)
test('delayed shorter shared endpoint cannot lower retained native history',function()
 local H=fresh();H.aura(100,81,100,115,true);H.aura(101,81,100,120,false)
 H.aura(101.1,81,100,115,false,true,100.5)
 check(H.app().expiry==120,'old source does not lower current endpoint')
 local claim=H.cycles();H.aura(105.1,81,104,120,false)
 remainsEstimated(H,105.1,claim,105);refines(H,105.2,claim,105,82,121);H.clean()
end)
test('equal observation time retains the larger compatible endpoint',function()
 local H=fresh();H.aura(100,81,100,115,true);H.aura(101,81,100,120,false)
 H.aura(101.1,81,100,115,false,true,101)
 check(H.app().expiry==120,'equal-time endpoint disagreement conserves later end')
 local claim=H.cycles();H.aura(105.1,81,104,118,false)
 remainsEstimated(H,105.1,claim,105);refines(H,105.2,claim,105,82,121);H.clean()
end)
test('compatible ID-less correction updates the known native endpoint',function()
 local H=fresh();H.aura(100,81,100,115,true);H.aura(101,nil,100,120,false)
 check(H.app().instance==81 and H.app().expiry==120,'optional ID loss retains compatible native application')
 local claim=H.cycles();H.aura(105.1,81,104,120,false)
 remainsEstimated(H,105.1,claim,105);refines(H,105.2,claim,105,82,121);H.clean()
end)
test('historical native correction aliases cannot become primary owners',function()
 local H=fresh();H.aura(100,nil,100,115,true);H.aura(101,81,100,115,false)
 local owner=H.ns.CooldownEvidence.seenHelpful['Player-1-R:5277:instance:81'].identity
 check(owner~='Player-1-R:5277:instance:81','fixture native is an alias of original ID-less occurrence')
 local claim=H.cycles();H.aura(105.1,81,104,120,false)
 remainsEstimated(H,105.1,claim,105);refines(H,105.2,claim,105,82,121)
 check(H.ns.CooldownEvidence.seenHelpful['Player-1-R:5277:instance:81'].identity==owner,
  'retained historical alias owner remains immutable');H.clean()
end)
test('safely reused primary records its new endpoint before further untimed resets',function()
 local H=fresh();H.aura(100,81,100,115,true)
 local owner=H.ns.CooldownEvidence.seenHelpful['Player-1-R:5277:instance:81'].identity
 H.reset(102);H.aura(103,nil,nil,nil,true)
 refines(H,103.1,H.row(103).claimID,103,81,118)
 H.reset(104);H.aura(105,nil,nil,nil,true);H.reset(106);H.aura(107,nil,nil,nil,true)
 local claim=assert(H.row(107)).claimID;H.aura(107.1,81,106,118,false)
 remainsEstimated(H,107.1,claim,107);refines(H,107.2,claim,107,82,122)
 check(H.ns.CooldownEvidence.seenHelpful['Player-1-R:5277:instance:81'].identity==owner,
  'safe primary reuse does not rewrite original dedup ownership');H.clean()
end)
test('direct reset namespace records native endpoint and rejects incompatible old correction',function()
 local H=fresh();H.aura(100,81,100,115,true)
 local owner=H.ns.CooldownEvidence.seenHelpful['Player-1-R:5277:instance:81'].identity
 H.reset(102);H.aura(103,81,103,118,true)
 local direct=assert(H.row(103));check(not direct.timingEstimated,'reused native receives direct precise reset namespace')
 H.aura(103.1,81,100,115,false)
 check(H.app().expiry==118,'old incompatible native timing cannot overwrite current endpoint')
 H.reset(104);H.aura(105,nil,nil,nil,true);H.reset(106);H.aura(107,nil,nil,nil,true)
 local claim=assert(H.row(107)).claimID;H.aura(107.1,81,106,118,false)
 remainsEstimated(H,107.1,claim,107);refines(H,107.2,claim,107,82,122)
 check(H.ns.CooldownEvidence.seenHelpful['Player-1-R:5277:instance:81'].identity==owner,
  'namespace renewal keeps original raw native dedup owner');H.clean()
end)
test('retained history uses existing scalar bounded witness records and TTL',function()
 local H=fresh();H.aura(100,81,100,115,true)
 for i=1,300 do
  local now=100+i*.2
  H.reset(now,'Bounded-Reset-'..i);H.aura(now,i+1000,now,now+15,true)
 end
 local E=H.ns.CooldownEvidence
 check(count(E.seenHelpful)<=256,'native history stays within existing 256 witness bound')
 check(count(E.helpfulApplications)<=256 and count(E.unknownHelpful)<=256,'continuity maps stay bounded')
 for _,w in pairs(E.seenHelpful)do
  for _,value in pairs(w)do check(type(value)~='table','native witness history has only scalar values')end
 end
 H.aura(1000,9999,1000,1015,true)
 check(count(E.seenHelpful)==1,'all old witness records and their endpoint history expire through existing TTL')
 H.clean()
end)
TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
