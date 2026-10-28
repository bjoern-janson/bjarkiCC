-- Conditional public-source ordering regression. A delayed shared report is
-- delivered after newer local timing; this is not proof of a normal live-client
-- trigger. The review-only real Portraits replay models an explicit public-bus
-- consumer disconnect/reconnect. All inputs here use Main events or the real
-- bus, and world_recovery_support.lua remains unchanged. Evidence tables are
-- read only for diagnostics; admission is checked through public cooldown rows.
local setup=assert(loadfile((TEST_DIR or ADDON_DIR..'/tests')..'/world_recovery_support.lua'))()
local checks,groups,failures,active=0,{},{},nil
local G='Player-1-SampleClock'
local function check(ok,why) checks=checks+1;assert(ok,why) end
local function fresh(firstEnd)
 local H=setup();active=H;H.trace={}
 H.units.target=G;H.units.focus=G;H.hostile.target=true;H.hostile.focus=true
 function H.fire(event,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...)end
 function H.rows(at)
  local rows={}
  for _,row in ipairs(H.ns.model:GetCooldowns(at,nil,true))do
   if row.guid==G and row.spellID==5277 then rows[#rows+1]=row end
  end
  return rows
 end
 function H.record(label,at)
  local rows=H.rows(at);local r=rows[1]
  local a=H.ns.CooldownEvidence.helpfulApplications[G..':5277']
  local k=H.ns.CooldownEvidence.unknownHelpful[G..':5277']
  H.trace[#H.trace+1]={label=label,count=#rows,claim=r and r.claimID,
   started=r and r.started,expiry=a and a.expiry,expiryObservedAt=a and a.expiryObservedAt,
   sampleExpiry=a and a.sampleExpiry,sampleObservedAt=a and a.sampleObservedAt,
   resetSampleExpiry=k and k.resetSampleExpiry}
 end
 function H.aura(at,start,finish,added,stamp,id)
  H.time(at)
  local a={spellId=5277,isHelpful=true,auraInstanceID=id or 81,
   duration=finish-start,expirationTime=finish}
  if id==false then a.auraInstanceID=nil end
  if stamp then
   check(H.publish('target',G,a,stamp,added),'shared input accepted by the real bus')
  elseif added then
   -- Event timing can be readable while the independent exact query is not.
   H.blocked.target='error';H.fire('UNIT_AURA','target',{addedAuras={a}});H.blocked.target=nil
  else
   H.auras.target={[5277]=a};H.fire('UNIT_AURA','target',{isFullUpdate=true});H.auras.target=nil
  end
 end
 function H.one(at,claim,start)
  local rows=H.rows(at)
  check(#rows==1,'expected one public Evasion row')
  check(rows[1].started==start and not rows[1].timingEstimated,'readable occurrence has the expected precise start')
  if claim then check(rows[1].claimID==claim,'old observation preserves the current occurrence claim')end
  return rows[1]
 end
 function H.resetAndOffer(finish,expected)
  H.record('before reset',151)
  H.time(152);H.fire('UNIT_SPELLCAST_SUCCEEDED','focus','Reset-SampleClock',14185)
  check(#H.rows(152)==0,'accepted Preparation retires the old occurrence')
  H.record('accepted reset',152)
  H.aura(152,152,finish,true)
  H.record('equal-time added positive',152)
  if expected then
   local row=H.one(152,nil,152)
   check(row.claimID~=H.oldClaim,'new post-reset occurrence owns a distinct claim')
  else
   check(#H.rows(152)==0,'newer pre-reset boundary protects against equal-time replay')
   H.aura(152.1,152,finish,true,nil,82)
   H.one(152.1,nil,152)
  end
 end
 H.aura(150,149,firstEnd or 164,true)
 H.oldClaim=H.one(150,nil,149).claimID;H.record('initial native positive',150)
 return H
end
local function test(name,fn)
 active=nil
 local ok,err=pcall(fn)
 local errors=active and active.ns.EvidenceBus:Status().errors or 0
 if ok and errors~=0 then ok=false;err='shared bus reported callback errors' end
 groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(err) or nil,
  busErrors=errors,trace=active and active.trace}
 if not ok then failures[#failures+1]=name..': '..tostring(err)end
end

test('no delayed report leaves equal-time reuse available',function()
 local H=fresh();H.resetAndOffer(167,true)
end)
test('older longer report cannot initialize a blocking sample',function()
 local H=fresh();H.aura(150.2,149,180,false,149.5)
 H.one(150.2,H.oldClaim,149);H.resetAndOffer(167,true)
end)
test('older identical endpoint does not change admission',function()
 local H=fresh();H.aura(150.2,149,164,false,149.5);H.resetAndOffer(167,true)
end)
test('fresh ordinary sample already rejects an older longer report',function()
 local H=fresh();H.aura(150.1,149,164,false)
 H.aura(150.2,149,180,false,149.5);H.resetAndOffer(167,true)
end)
test('equal source time retains the larger native endpoint',function()
 local H=fresh();H.aura(150.2,149,180,false,150)
 H.aura(150.3,149,164,false,150);H.resetAndOffer(167,false)
end)
test('newer incompatible native sample still protects replay',function()
 local H=fresh();H.aura(150.2,150.2,180,false)
 H.one(150.2,H.oldClaim,149);H.resetAndOffer(167,false)
end)
test('older compatible report cannot displace a newer incompatible sample',function()
 local H=fresh();H.aura(150.2,150.2,180,false)
 H.aura(150.3,149,170,false,150.1)
 H.one(150.3,H.oldClaim,149);H.resetAndOffer(175,false)
end)
test('equal-time disagreement preserves the larger incompatible sample',function()
 local H=fresh();H.aura(150.2,150.2,180,false)
 H.aura(150.3,149,164,false,150.2);H.resetAndOffer(167,false)
end)
test('fresh native shortening supersedes the older long sample',function()
 local H=fresh();H.aura(150.2,150.2,180,false)
 H.aura(150.4,149,164,false)
 H.aura(150.5,150.2,180,false,150.2);H.resetAndOffer(167,true)
end)
test('fresh optional-ID shortening supersedes the older native sample',function()
 local H=fresh();H.aura(150.2,150.2,180,false)
 H.aura(150.4,149,164,false,nil,false)
 H.aura(150.5,150.2,180,false,150.2);H.resetAndOffer(167,true)
end)
test('older optional-ID report cannot undo fresh accepted shortening',function()
 local H=fresh(180);H.aura(150.2,149,164,false,nil,false)
 H.aura(150.4,149,180,false,150.1,false);H.resetAndOffer(167,true)
end)

TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
