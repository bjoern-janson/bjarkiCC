-- CC38-CD2: an independently added same-native positive after an accepted
-- reset may start at the same GetTime, provided its endpoint is genuinely newer.
-- Ordinary exact-only equality stays ambiguous until an added positive arrives.
-- These tests deliberately narrow the old audit probe's exact-equality demand.
-- Only client boundaries use the unchanged fixture; stimuli enter real Main
-- events / the public shared bus, and behavior is read from GetCooldowns.
local fixtureDir = TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup = assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local checks, groups, failures = 0, {}, {}
local function check(value, why) assert(value, why); checks=checks+1 end
local function close(a,b) return type(a)=='number' and math.abs(a-b)<.00001 end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local active
local function fresh()
 local H=setup(); active=H
 H.units.target='Player-1-R'; H.hostile.target=true
 function H.fire(event,...) H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...) end
 function H.reset(at,id)
  H.time(at); H.fire('UNIT_SPELLCAST_SUCCEEDED','target',id or 'Reset-EqualNative',14185)
 end
 function H.aura(origin,at,instance,start,finish,added,observed)
  H.time(at)
  local aura={spellId=5277,isHelpful=true,auraInstanceID=instance}
  if start then aura.duration=finish-start; aura.expirationTime=finish end
  if origin=='shared' then H.publish('target',H.units.target,aura,observed or at,added)
  elseif added then H.fire('UNIT_AURA','target',{addedAuras={aura}})
  else
   H.auras.target={[5277]=aura}; H.fire('UNIT_AURA','target',{isFullUpdate=true})
   H.auras.target=nil
  end
 end
 function H.rows(at)
  local rows={}
  for _,row in ipairs(H.ns.model:GetCooldowns(at,nil,true)) do
   if row.spellID==5277 and row.guid==H.units.target then rows[#rows+1]=row end
  end
  return rows
 end
 function H.row(at) return H.rows(at)[1] end
 function H.snapshot(at)
  local rows=H.rows(at); local row=rows[1]
  return {count=#rows,claim=row and row.claimID,started=row and row.started,
   estimated=row and row.timingEstimated,remaining=row and row.remaining,
   earlyRemaining=row and row.earlyRemaining}
 end
 return H
end
local function group(name,fn)
 active=nil
 local ok,why=pcall(fn)
 local busErrors=active and active.ns.EvidenceBus.stats.errors or 0
 if ok and busErrors~=0 then ok=false; why='shared bus callback errors: '..busErrors end
 groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(why) or nil,busErrors=busErrors}
 if not ok then failures[#failures+1]=name..': '..tostring(why) end
end
local function primed(untimed)
 local H=fresh()
 H.aura('local',100,81,not untimed and 100 or nil,115,true)
 local before=assert(H.row(100),'initial public Evasion row exists')
 H.reset(102)
 check(#H.rows(102)==0,'accepted Preparation removes the old public Evasion row')
 return H,before.claimID
end
local function oneNew(H,at,oldClaim,start)
 local rows=H.rows(at)
 check(#rows==1,'expected exactly one post-reset public Evasion row; got '..#rows)
 local row=rows[1]
 check(row.claimID~=oldClaim,'post-reset positive owns a new claim')
 check(close(row.started,start) and not row.timingEstimated,'new claim uses the readable application start')
 return row.claimID
end
local function same(H,at,claim,start)
 local rows=H.rows(at)
 check(#rows==1 and rows[1].claimID==claim and close(rows[1].started,start),
  'replay/correction must retain exactly one row and the same claim/start')
end

for _,origin in ipairs({'local','shared'}) do
 group(origin..' added equal-time reused native starts one new occurrence',function()
  local H,old=primed()
  H.aura(origin,102,81,102,117,true)
  local claim=oneNew(H,102,old,102)
  check(H.row(102).remaining==300 and H.row(102).earlyRemaining==120,
   'new readable occurrence projects the full Evasion cooldown range')
  for _,replayOrigin in ipairs({'local','shared'}) do
   H.aura(replayOrigin,102,81,102,117,true); same(H,102,claim,102)
   H.aura(replayOrigin,103,81,102,117,false); same(H,103,claim,102)
  end
  H.reset(103.1) -- Same native cast ID: a replay cannot reset twice.
  same(H,103.1,claim,102)
 end)

 group(origin..' exact-only equal start stays conservative',function()
  local H=primed()
  H.aura(origin,102,81,102,117,false)
  check(#H.rows(102)==0,'equal-start ordinary report does not independently spend reset permission')
  H.aura(origin,102.1,81,102,117,false)
  check(#H.rows(102.1)==0,'later observation of the same equal-start tuple is still ambiguous')
 end)

 group(origin..' exact-only equality does not poison later added proof',function()
  local H,old=primed()
  H.aura(origin,102,81,102,117,false)
  check(#H.rows(102)==0,'ordinary equality remains blocked before added proof')
  H.aura(origin,102,81,102,117,true)
  local claim=oneNew(H,102,old,102)
  H.aura(origin,103,81,102,117,false); same(H,103,claim,102)
 end)

 group(origin..' old endpoints cannot reopen a reused native',function()
  local H=primed()
  for _,finish in ipairs({115,114.9,115.05}) do
   H.aura(origin,102,81,102,finish,true)
   check(#H.rows(102)==0,'unchanged, older, or tolerance-close endpoint cannot prove a new occurrence')
  end
 end)

 group(origin..' missing old endpoint keeps reused native uncertain',function()
  local H=primed(true)
  H.aura(origin,102,81,102,117,false)
  check(#H.rows(102)==0,'new readable timing alone cannot disambiguate an unknown old endpoint')
  H.aura(origin,102,81,102,117,true)
  check(#H.rows(102)==0,'same reused native still lacks the required old-endpoint comparison')
  H.aura(origin,102,nil,102,117,true)
  check(#H.rows(102)==1 and H.row(102).started==102,
   'an independent anonymous added positive still uses accepted reset permission')
 end)

 group(origin..' older application start stays blocked',function()
  local H=primed()
  H.aura(origin,102,81,101.99,117,true)
  check(#H.rows(102)==0,'a start before the accepted reset is old even with a later endpoint')
 end)

 group(origin..' strictly later start remains admissible',function()
  local H,old=primed()
  H.aura(origin,102.01,81,102.01,117.01,false)
  local claim=oneNew(H,102.01,old,102.01)
  H.aura(origin,103,81,102.01,117.01,false); same(H,103,claim,102.01)
 end)

 group(origin..' distinct and absent native IDs preserve equal-time admission',function()
  for _,instance in ipairs({82,false}) do
   local H,old=primed()
   H.aura(origin,102,instance or nil,102,117,true)
   local claim=oneNew(H,102,old,102)
   H.aura(origin,103,instance or nil,102,117,false); same(H,103,claim,102)
  end
 end)

 group(origin..' equal-time accepted row conserves correction and replay ownership',function()
  local H,old=primed()
  local owners={}
  for key,witness in pairs(H.ns.CooldownEvidence.seenHelpful) do owners[key]=witness.identity end
  H.aura(origin,102,81,102,117,true)
  local claim=oneNew(H,102,old,102)
  H.aura(origin,103,81,103,117,false); same(H,103,claim,102)
  H.aura(origin,103.1,nil,103,117,false); same(H,103.1,claim,102)
  H.aura(origin,103.2,81,100,115,false); same(H,103.2,claim,102)
  for key,owner in pairs(owners) do
   check(H.ns.CooldownEvidence.seenHelpful[key].identity==owner,
    'new occurrence cannot acquire the historical native or correction alias owner')
  end
  H.reset(104,'Reset-AfterCorrection')
  H.aura(origin,104,81,104,117,false)
  check(#H.rows(104)==0,'duration correction keeps endpoint117 authoritative through a later reset')
 end)
end

group('future shared observation stays rejected and cannot consume reset permission',function()
 local H,old=primed()
 H.aura('shared',102,81,102,117,true,103)
 check(#H.rows(102)==0,'shared timestamp beyond the allowed future window is rejected')
 H.aura('local',102,82,102,117,true)
 oneNew(H,102,old,102)
end)

group('modeled reset cycles with colliding rounded starts keep separate occurrences',function()
 -- Stress only: two accepted Preparation events this close are not evidence
 -- of legal native server timing. Distinct cycles must not share one alias.
 local H,old=primed()
 H.aura('local',102.01,81,102.01,117.01,true)
 local first=oneNew(H,102.01,old,102.01)
 H.reset(102.015,'Reset-RoundedCollision')
 check(#H.rows(102.015)==0,'second accepted modeled reset retires the first new occurrence')
 H.aura('local',102.02,81,102.02,118.02,true)
 local second=oneNew(H,102.02,first,102.02)
 H.aura('shared',102.03,81,102.01,117.01,false)
 same(H,102.03,second,102.02)
end)

group('repeated modeled reset cycles retain bounded evidence and explanation state',function()
 local H=fresh(); H.aura('local',100,81,100,115,true)
 for i=1,400 do
  local at=100+i*.2
  H.reset(at,'Reset-Bounded-'..i)
  H.aura(i%2==0 and 'shared' or 'local',at,81+i,at,at+15,true)
  check(#H.rows(at)==1,'each distinct-native modeled cycle retains a public row')
 end
 local E=H.ns.CooldownEvidence
 check(count(E.seenHelpful)<=256,'seen native and correction identities stay bounded at256')
 check(count(E.unknownHelpful)<=256,'anonymous/reset continuity stays bounded at256')
 check(count(E.helpfulApplications)<=256,'application continuity stays bounded at256')
 check(#H.ns.model.claimActivity<=64,'explanation activity stays bounded at64')
 local caster=H.ns.model.casters[H.units.target]
 check(count(caster.castIDs)<=128,'native cast identities stay bounded at128')
 local row=assert(H.row(180))
 check(#row.claim.witnesses<=4 and row.claimRevisionCount<=4,'public claim sources and revisions stay bounded')
end)

TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
