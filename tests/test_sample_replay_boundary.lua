-- CC40-CD1: incompatible observations must not erase replay protection across
-- an accepted reset. Expectations come from occurrence ownership: a pre-reset
-- tuple is not a new use and cannot refine an independently admitted new use.
-- Conversely, accepted compatible correction and genuinely new timing retain
-- their established authority. All writes enter real Main events or the real
-- public bus. The unchanged full-TOC client fixture simulates client APIs only.
local fixtureDir=TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup=assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local groups,failures,checks,active={},{},0,nil
local G='Player-1-ReplayBoundary'
local function check(ok,why)checks=checks+1;assert(ok,why)end
local function close(a,b)return a and math.abs(a-b)<.000001 end
local function scalarCopy(t)
 local result={};for k,v in pairs(t or {})do if type(v)~='table' then result[k]=v end end
 return result
end
local function fresh()
 local H=setup();active=H;H.trace={}
 H.units.target=G;H.units.focus=G;H.hostile.target=true;H.hostile.focus=true
 function H.fire(event,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...)end
 function H.observe(at,id,start,finish,added,stamp,unit)
  H.time(at);unit=unit or 'target'
  local aura={spellId=5277,isHelpful=true,auraInstanceID=id}
  if start then aura.duration=finish-start;aura.expirationTime=finish end
  if stamp then
   check(H.publish(unit,H.units[unit],aura,stamp,added),'schema-valid source report reaches the real bus')
  elseif added then H.fire('UNIT_AURA',unit,{addedAuras={aura}})
  else
   H.auras[unit]={[5277]=aura};H.fire('UNIT_AURA',unit,{isFullUpdate=true});H.auras[unit]=nil
  end
 end
 function H.row(at,guid)
  local found
  for _,row in ipairs(H.ns.model:GetCooldowns(at,guid or G,true))do
   if row.spellID==5277 then check(not found,'at most one public Evasion row');found=row end
  end
  return found
 end
 function H.precise(at,start,claim)
  local row=H.row(at)
  check(row and close(row.started,start) and not row.timingEstimated,'expected precise public start '..start)
  if claim then check(row.claimID==claim,'correction preserves occurrence claim')end
  return row
 end
 function H.capture(label,at)
  local row=H.row(at);local E=H.ns.CooldownEvidence
  H.trace[#H.trace+1]={label=label,row=row and {claimID=row.claimID,started=row.started,
   estimated=row.timingEstimated,revisions=row.claimRevisionCount,remaining=row.remaining},
   application=scalarCopy(E.helpfulApplications[G..':5277']),
   native=scalarCopy(E.seenHelpful[G..':5277:instance:81']),
   unknown=scalarCopy(E.unknownHelpful[G..':5277'])}
 end
 function H.reset(at)
  H.capture('before Preparation',at)
  H.time(at);H.fire('UNIT_SPELLCAST_SUCCEEDED','focus','Replay-Reset-'..at,14185)
  check(not H.row(at),'accepted Preparation retires the previous Evasion')
  H.capture('after Preparation',at)
 end
 function H.anonymous(at)
  H.observe(at,nil,nil,nil,true)
  local row=H.row(at)
  check(row and row.timingEstimated and close(row.started,at),'independent added positive creates an estimate')
  check(row.claimID~=H.original,'independent new use owns a new claim')
  return {claimID=row.claimID,started=row.started,revisions=row.claimRevisionCount}
 end
 function H.retired(at,current)
  H.capture('after replay offer',at)
  local row=H.row(at)
  if current then
   check(row and row.claimID==current.claimID and row.timingEstimated
    and close(row.started,current.started) and row.claimRevisionCount==current.revisions,
    'pre-reset tuple cannot refine or revise the independent post-reset estimate')
  else check(not row,'pre-reset tuple cannot reopen the retired cooldown')end
 end
 H.observe(100,81,100,115,true)
 H.original=H.precise(100,100).claimID
 return H
end
local function group(name,kind,fn)
 active=nil;local ok,err=pcall(fn)
 local busErrors=active and active.ns.EvidenceBus:Status().errors or 0
 if busErrors~=0 then ok=false;err='shared bus callback errors: '..busErrors end
 groups[#groups+1]={name=name,kind=kind,ok=ok,error=not ok and tostring(err) or nil,
  busErrors=busErrors,trace=active and active.trace}
 if not ok then failures[#failures+1]=name..': '..tostring(err)end
end

-- The near-future raw start is admitted at102, clipped then, but is readable
-- without clipping after the reset. A newer incompatible shorter sample must
-- not turn that already-seen tuple into evidence of another occurrence.
for _,route in ipairs({'local','shared'})do
 for _,handoff in ipairs({false,true})do
  for _,second in ipairs({'none','older','equal','newer'})do
   group(route..'/'..(handoff and 'anonymous' or 'direct')..'/'..second,'replay',function()
    local H=fresh()
    H.observe(102,81,102.05,117,false,route=='shared' and 102 or nil)
    if second~='none' then
     local stamp=second=='older' and 101.99 or second=='equal' and 102
      or route=='shared' and 102.01 or nil
     H.observe(102.01,81,102.01,116.5,false,stamp)
    end
    H.precise(102.01,100,H.original)
    H.reset(102.01)
    local current=handoff and H.anonymous(102.1) or nil
    H.observe(102.2,81,102.05,117,false,route=='shared' and 102.2 or nil,'focus')
    H.retired(102.2,current)
   end)
  end
 end
end

-- Conditional protocol control: the bus admits a source clock ahead of the
-- local reset. This is source-ordering coverage, not measured live frequency.
for _,handoff in ipairs({false,true})do
 group('source-lead/'..(handoff and 'anonymous' or 'direct'),'replay',function()
  local H=fresh()
  H.observe(102,81,102.35,117,false,102.3)
  H.observe(102.01,81,102.4,116.5,false,102.4)
  H.precise(102.01,100,H.original);H.reset(102.01)
  local current=handoff and H.anonymous(102.5) or nil
  H.observe(102.6,81,102.35,117,false)
  H.retired(102.6,current)
 end)
end

-- Clock precedence must track the latest smaller report as well as protecting
-- earlier sampled endpoints. A compatible report between the two source clocks
-- is older than the latest sample and cannot erase its replay protection.
for _,handoff in ipairs({false,true})do
 for _,correction in ipairs({
  {name='older-between-samples',stamp=102.35,finish=116,allowed=false},
  {name='equal-clock-shorter',stamp=102.4,finish=116,allowed=false},
  {name='newer-clock-shorter',stamp=102.5,finish=116,allowed=true},
  {name='newer-clock-equal-endpoint',stamp=102.5,finish=117,allowed=false},
  {name='newer-clock-longer',stamp=102.5,finish=118,allowed=false},
 })do
  group('correction/'..(handoff and 'anonymous' or 'direct')..'/'..correction.name,'correction',function()
   local H=fresh()
   H.observe(102,81,102.35,117,false,102.3)
   H.observe(102.01,81,102.4,116.5,false,102.4)
   H.observe(102.02,81,100,correction.finish,false,correction.stamp)
   H.precise(102.02,100,H.original);H.reset(102.03)
   local current=handoff and H.anonymous(102.5) or nil
   H.observe(102.6,81,102.35,117,false)
   if correction.allowed then
    H.capture('after compatible shortening and fresh offer',102.6)
    local row=H.precise(102.6,102.35,current and current.claimID)
    check(row.claimID~=H.original,'accepted shortened boundary permits a distinct post-reset use')
   else H.retired(102.6,current)end
  end)
 end
end

for _,handoff in ipairs({false,true})do
 group('genuinely-later-start/'..(handoff and 'anonymous' or 'direct'),'admission',function()
  local H=fresh();H.observe(101,81,101,131,false);H.reset(102)
  local current=handoff and H.anonymous(103.1) or nil
  H.observe(103.2,81,103,118,false)
  local row=H.precise(103.2,103,current and current.claimID)
  check(row.claimID~=H.original,'genuinely later occurrence survives an incompatible long sample')
 end)
 group('new-endpoint-within-window/'..(handoff and 'anonymous' or 'direct'),'admission',function()
  local H=fresh();H.observe(102,81,102.05,117,false)
  H.observe(102.01,81,102.01,116.5,false);H.reset(102.01)
  local current=handoff and H.anonymous(102.1) or nil
  H.observe(102.2,81,102.05,119,false)
  H.precise(102.2,102.05,current and current.claimID)
 end)
 group('distinct-native/'..(handoff and 'anonymous' or 'direct'),'admission',function()
  local H=fresh();H.observe(102,81,102.05,117,false)
  H.observe(102.01,81,102.01,116.5,false);H.reset(102.01)
  local current=handoff and H.anonymous(102.1) or nil
  H.observe(102.2,82,102.05,117,not handoff)
  H.precise(102.2,102.05,current and current.claimID)
 end)
end

group('unreadable-future-time-is-not-a-sample','admission',function()
 local H=fresh();H.observe(102,81,102.2,117,false)
 H.precise(102,100,H.original);H.reset(102.01)
 H.observe(102.3,81,102.2,117,false)
 H.precise(102.3,102.2)
end)

for _,optionalID in ipairs({false,true})do
 group('compatible-shortening/'..(optionalID and 'optional-id' or 'native'),'correction',function()
  local H=fresh();H.observe(101,81,100,120,false)
  local id=81;if optionalID then id=nil end
  H.observe(101.1,id,100,112,false)
  H.precise(101.1,100,H.original);H.reset(102)
  H.observe(103,81,103,112,false)
  check(not H.row(103),'unchanged shortened endpoint cannot reopen')
  H.observe(104,81,104,114,false)
  H.precise(104,104)
 end)
end

group('bounded-scalar-history-and-expiry','bounds',function()
 local H=fresh()
 for i=1,600 do
  H.units.target='Player-1-Bound'..i
  local at=110+i*.01;H.observe(at,i,at,at+15,true)
  H.observe(at+.001,i,at+.001,at+20,false)
  H.observe(at+.002,i,at+.002,at+19,false)
 end
 local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
 local E=H.ns.CooldownEvidence
 check(count(E.seenHelpful)<=256,'native history remains capped at256')
 check(count(E.helpfulApplications)<=256,'application history remains capped at256')
 check(count(E.unknownHelpful)<=256,'anonymous continuity remains capped at256')
 for _,map in ipairs({E.seenHelpful,E.helpfulApplications,E.unknownHelpful})do
  for _,record in pairs(map)do
   for _,value in pairs(record)do check(type(value)~='table','history remains scalar with no per-record tuple list')end
  end
 end
 H.units.target=G;H.observe(1000,9999,1000,1015,true)
 check(count(E.seenHelpful)==1 and count(E.helpfulApplications)==1,'480-second history expires on later observation')
 H.precise(1000,1000)
end)

TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
