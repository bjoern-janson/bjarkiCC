-- Regression intent: public cooldown timing must reflect the published 120..300
-- Evasion range, and only an accepted Preparation may reopen affected evidence.
-- Real modules/events run through the unchanged world-recovery client fixture.
local fixtureDir = TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup = assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local checks, groups, failures = 0, {}, {}
local function check(value, why) assert(value, why); checks=checks+1 end
local function close(a,b) return math.abs(a-b)<.00001 end
local function fresh()
 local H=setup(); local ns=H.ns
 H.units.target='Player-1-R'; H.units.focus='Player-1-O'
 H.hostile.target=true; H.hostile.focus=true
 local function fire(event,...) ns.eventFrame.scripts.OnEvent(ns.eventFrame,event,...) end
 function H.cast(id,stamp,guid,unit)
  H.time(stamp); fire('UNIT_SPELLCAST_SUCCEEDED',unit or 'target',guid,id)
 end
 function H.add(id,stamp,instance,start,duration,unit)
  H.time(stamp); local aura={spellId=id,isHelpful=true,auraInstanceID=instance}
  if start then aura.duration=duration or 15; aura.expirationTime=start+aura.duration end
  fire('UNIT_AURA',unit or 'target',{addedAuras={aura}})
 end
 function H.exact(id,stamp,instance,start,duration)
  H.time(stamp); local aura={spellId=id,isHelpful=true,auraInstanceID=instance}
  if start then aura.duration=duration or 15; aura.expirationTime=start+aura.duration end
  H.auras.target={[id]=aura}; ns.CooldownEvidence.OnUnitSeen('target',stamp)
  H.auras.target=nil
 end
 function H.updated(id,stamp,instance,start,duration)
  H.time(stamp); H.auras.target={[id]={spellId=id,isHelpful=true,auraInstanceID=instance,
   duration=duration or 15,expirationTime=start+(duration or 15)}}
  fire('UNIT_AURA','target',{updatedAuraInstanceIDs={instance}})
  H.auras.target=nil
 end
 function H.public(id,stamp,guid)
  for _,row in ipairs(ns.model:GetCooldowns(stamp)) do
   if row.spellID==id and row.guid==(guid or H.units.target) then return row end
  end
  return nil
 end
 return H
end
local function group(name,fn)
 local ok,why=pcall(fn)
 groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(why) or nil}
 if not ok then failures[#failures+1]=name..': '..tostring(why) end
end

group('Evasion public range and rank canonicalization',function()
 local H=fresh(); H.cast(26669,100,'Cast-Rank')
 local row=assert(H.public(5277,100))
 check(row.started==100 and row.remaining==300,'rank Evasion keeps 300 second upper bound')
 check(row.earlyRemaining==120,'Evasion earliest-ready estimate is 120 seconds')
 check(not H.public(26669,100),'rank does not create another cooldown row')
end)

group('anonymous positive admits at 120.1 and preserves duplicates',function()
 local H=fresh(); H.add(5277,100)
 local first=assert(H.public(5277,100)); check(first.timingEstimated,'first anonymous activation estimated')
 H.add(26669,219.8)
 check(H.public(5277,219.8).claimID==first.claimID,'too-early new positive cannot renew')
 H.add(26669,220.1)
 local row=assert(H.public(5277,220.1))
 check(row.started==220.1 and row.claimID~=first.claimID,'new anonymous rank positive at +120.1 renews canonical row')
 check(row.remaining==300 and row.earlyRemaining==120,'renewal uses entire legal cooldown interval')
 check(H.ns.CooldownEvidence.stats.unknownRenewed==1,'one accepted anonymous renewal')
 H.add(5277,220.1); H.exact(5277,220.2)
 check(H.public(5277,220.2).claimID==row.claimID,'duplicate and ordinary exact sighting do not renew')
 local decision=H.ns.Claims.LastDecision(H.ns.model,5277)
 check(decision.status=='issued','latest claim is active after accepted renewal')
 local retired=false
 for _,v in ipairs(H.ns.model.claimActivity) do
  if v.claimID==first.claimID and v.status=='retired' and v.reason=='superseded-by-new-use' then retired=true end
 end
 check(retired,'renewal retires prior claim')
end)

group('ordinary anonymous sighting never supplies cooldown renewal',function()
 local H=fresh(); H.add(5277,100)
 local claim=H.public(5277,100).claimID
 H.exact(5277,220.1)
 check(H.public(5277,220.1).claimID==claim,'minimum elapsed does not authorize ordinary sighting')
 H.exact(5277,401)
 check(not H.public(5277,401),'expiry does not authorize anonymous ordinary replay')
end)

group('near cast and later timing refinement remain a single claim',function()
 local H=fresh(); H.cast(5277,100,'Cast-Evasion')
 local claim=H.public(5277,100).claimID
 H.add(26669,100.3)
 check(H.public(5277,100.3).claimID==claim and H.public(5277,100.3).started==100,'near cast aura corroborates only')
 H.add(5277,102)
 check(H.public(5277,102).claimID==claim,'early positive cannot bypass a confirmed cast')
 H=fresh(); H.add(5277,100,81)
 claim=H.public(5277,100).claimID
 H.add(26669,100.2,81,99,15)
 local row=H.public(5277,100.2)
 check(row.claimID==claim and row.started==99 and not row.timingEstimated,'same aura timing improves existing claim')
 check(row.claimRevisionCount==1,'timestamp repair records one bounded revision')
end)

group('cooldown overrides control both renewal gate and interval',function()
 for _,duration in ipairs({60,240}) do
  local H=fresh(); H.ns.db.cooldownOverrides[5277]=duration; H.add(5277,100)
  local claim=H.public(5277,100).claimID
  H.add(5277,100+duration-.2)
  check(H.public(5277,100+duration-.2).claimID==claim,'override minimum rejects early positive')
  H.add(26669,100+duration+.1)
  local row=H.public(5277,100+duration+.1)
  check(close(row.started,100+duration+.1) and row.remaining==duration and row.earlyRemaining==duration,
   'override controls canonical renewal and exact interval')
 end
end)

group('Preparation retires exactly its tracked family for its caster',function()
 local H=fresh(); local ids={5277,1766,408,2094,1776}; local claims={}
 for _,id in ipairs(ids) do H.cast(id,400,'Cast-A-'..id); claims[id]=H.public(id,400).claimID end
 H.cast(22812,400,'Cast-Unrelated'); H.cast(5277,400,'Cast-Other', 'focus')
 local before=H.ns.Observer.stats.acceptedCasts
 H.cast(14185,401,'Cast-Preparation')
 check(H.ns.Observer.stats.acceptedCasts==before+1,'real Main path accepts Preparation')
 for _,id in ipairs(ids) do
  check(not H.public(id,401),'Preparation clears affected cooldown '..id)
  local decision=H.ns.Claims.LastDecision(H.ns.model,id)
  check(decision.claimID==claims[id] and decision.status=='retired' and decision.reason=='reset-spell-witness',
   'reset retires affected claim '..id)
 end
 check(H.public(22812,401).started==400,'unrelated same-caster cooldown retained')
 check(H.public(5277,401,H.units.focus).started==400,'other caster retains Evasion')
end)

group('rejected and duplicate Preparation grant no extra reset',function()
 local H=fresh(); H.add(5277,100)
 local claim=H.public(5277,100).claimID
 H.hostile.target=false; H.cast(14185,101,'Cast-Rejected'); H.hostile.target=true
 check(H.public(5277,101).claimID==claim,'hostility rejected reset keeps original cooldown')
 H.add(5277,102)
 check(H.public(5277,102).claimID==claim,'rejected reset cannot authorize anonymous renewal')
 H.cast(14185,103,H.hidden)
 check(H.public(5277,103).claimID==claim,'secret reset identity cannot clear cooldown')
 H.cast(14185,104,'Cast-Preparation'); check(not H.public(5277,104),'accepted reset clears cooldown')
 H.add(5277,106); local renewed=assert(H.public(5277,106))
 check(renewed.started==106 and renewed.claimID~=claim,'new anonymous positive accepted after reset')
 H.cast(14185,107,'Cast-Preparation')
 check(H.public(5277,107).claimID==renewed.claimID,'duplicate reset cast cannot clear new cooldown')
 H.add(5277,108)
 check(H.public(5277,108).claimID==renewed.claimID,'duplicate reset cannot replenish permission')
end)

group('reset permits new anonymous activation but no ordinary replay',function()
 local H=fresh(); H.add(5277,100)
 H.cast(14185,101,'Cast-Preparation'); check(not H.public(5277,101),'reset clears initial anonymous activation')
 H.exact(5277,102)
 check(not H.public(5277,102),'ordinary anonymous exact sighting cannot consume reset')
 H.add(26669,103)
 local row=assert(H.public(5277,103))
 check(row.started==103,'fresh anonymous rank addedAuras consumes accepted reset')
 H.add(5277,103.1); H.exact(5277,103.2)
 check(H.public(5277,103.2).claimID==row.claimID,'permission consumed once despite aliases')
end)

group('reset does not replay old native identities or pre-reset timestamps',function()
 local H=fresh(); H.add(5277,100,81)
 H.cast(14185,101,'Cast-Preparation'); check(not H.public(5277,101),'reset removes strong activation')
 H.exact(5277,102,81); H.add(26669,102.1,81)
 check(not H.public(5277,102.1),'known stale instance remains deduplicated after reset')
 H.add(5277,102.2,82,100,15)
 check(not H.public(5277,102.2),'readable pre-reset timestamp cannot resurrect cooldown under another ID')
 H.exact(5277,102.3,83)
 check(not H.public(5277,102.3),'ordinary identity change cannot consume reset')
 H.add(5277,103,84)
 check(H.public(5277,103).started==103,'fresh new identity can activate after rejected stale reports')
end)

group('cast-only reset anchors ordinary sightings and new cast consumes permission',function()
 local H=fresh(); H.cast(5277,100,'Cast-Evasion'); H.cast(14185,101,'Cast-Preparation')
 check(not H.public(5277,101),'reset clears cast-only activation')
 H.exact(5277,102)
 check(not H.public(5277,102),'cast-only reset prevents first anonymous ordinary replay')
 H.cast(26669,103,'Cast-NewEvasion'); local row=assert(H.public(5277,103))
 H.add(5277,105)
 check(H.public(5277,105).claimID==row.claimID,'accepted ability cast consumes obsolete reset permission')
end)

group('sub-second reset breaks only pre-reset helpful near-cast dedup',function()
 local H=fresh(); H.add(5277,100)
 H.cast(14185,100.05,'Cast-Preparation'); check(not H.public(5277,100.05),'sub-second reset clears old use')
 H.add(5277,100.1)
 local row=assert(H.public(5277,100.1),'fresh post-reset positive is not old near-cast corroboration')
 check(row.started==100.1,'sub-second reset admits actual new helpful positive')
 H.add(5277,100.11)
 check(H.public(5277,100.11).claimID==row.claimID,'post-reset near duplicate remains one activation')
end)

group('reset permissions stay local to caster and spell',function()
 local H=fresh(); H.add(5277,100); H.add(22812,100)
 H.add(5277,100,nil,nil,nil,'focus')
 local unrelated=H.public(22812,100).claimID
 local other=H.public(5277,100,H.units.focus).claimID
 H.cast(14185,101,'Cast-Preparation')
 H.add(22812,103); H.add(5277,103,nil,nil,nil,'focus')
 check(H.public(22812,103).claimID==unrelated,'reset does not reopen unrelated self-only spell')
 check(H.public(5277,103,H.units.focus).claimID==other,'reset cannot reopen another caster')
 H.add(5277,103)
 check(H.public(5277,103).started==103,'affected caster and spell do reopen')
end)

group('shared reset positives require freshness and explicit new application',function()
 local H=fresh(); H.add(5277,100)
 H.cast(14185,101,'Cast-Preparation')
 H.time(102)
 H.publish('target',H.units.target,{spellId=5277},100,true)
 check(not H.public(5277,102),'delayed pre-reset publication cannot consume permission')
 H.publish('target',H.units.target,{spellId=5277},102,false)
 check(not H.public(5277,102),'ordinary shared report cannot consume permission')
 H.time(103); H.publish('target',H.units.target,{spellId=26669},103,true)
 local row=assert(H.public(5277,103))
 check(row.started==103,'fresh explicit shared added-positive can consume permission')
 H.publish('target',H.units.target,{spellId=5277},103,true)
 check(H.public(5277,103).claimID==row.claimID,'same bus activation remains deduplicated')
end)

group('saturation preserves strong identities except missing reset barriers',function()
 local H=fresh()
 for i=1,256 do
  H.units.target='Player-1-Saturation-'..i; H.add(5277,100)
 end
 local count=0; for _ in pairs(H.ns.CooldownEvidence.unknownHelpful) do count=count+1 end
 check(count==256,'ordinary positive history reaches the existing256 cap')
 H.units.target='Player-1-Fresh'; H.add(22812,101,900)
 check(H.public(22812,101)~=nil,'unrelated strong-ID positive remains supported at anonymous capacity')
 H.cast(14185,102,'Cast-CapacityPreparation')
 H.add(5277,103,901)
 check(not H.public(5277,103),'missing reset anchor fails closed for affected caster and spell')
 H.add(22812,104,902,104)
 check(H.public(22812,104).started==104,'reset saturation does not suppress unrelated strong-ID activation')
 H.units.target='Player-1-OtherFresh'; H.add(5277,105,903)
 check(H.public(5277,105)~=nil,'another caster strong-ID activation remains supported')
 count=0; for _ in pairs(H.ns.CooldownEvidence.unknownHelpful) do count=count+1 end
 check(count==256,'reset and strong-ID saturation cannot grow anonymous continuity map')
 count=0; for _ in pairs(H.ns.model.casters) do count=count+1 end
 check(count<=128,'saturated evidence retains existing caster cap')
 H.units.target='Player-1-Fresh'; H.cast(5277,106,'Cast-PostSaturation')
 local claim=assert(H.public(5277,106)).claimID
 H.add(5277,108,904)
 check(H.public(5277,108).claimID==claim,'saturation keeps affected aura conservative after accepted cast')
 H.ns.model:PruneCooldowns(500)
 check(H.ns.model.casters[H.units.target]==nil,'caster retirement releases fallback marker')
 H.time(501); H.ns.Command('clear'); H.add(5277,501,905)
 check(H.public(5277,501).started==501,'tracking reset releases fallback with fresh positive')
end)

group('many reset cycles retain bounded witness and claim state',function()
 local H=fresh(); H.add(5277,100)
 for i=1,1200 do
  local at=100+i*2
  H.cast(14185,at,'Cast-Cycle-'..i)
  H.add(5277,at+.1)
 end
 check(close(H.public(5277,2500.1).started,2500.1),'last accepted positive survives many reset cycles')
 local E=H.ns.CooldownEvidence
 local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
 check(count(E.unknownHelpful)==1,'many resets retain one continuity record')
 check(count(E.helpfulApplications)==1,'many resets retain one active application record')
 check(count(E.seenHelpful)<=256,'many reset cycles retain bounded native and anonymous keys')
 check(#H.ns.model.claimActivity<=64,'many reset cycles retain bounded claim activity')
 check(count(H.ns.model.casters)<=128,'many reset cycles retain bounded casters')
 check(count(H.ns.model.casters[H.units.target].castIDs)<=128,'many resets retain bounded cast identities')
end)

group('unrelated accepted casts do not consume anonymous continuity capacity',function()
 local H=fresh()
 for i=1,400 do
  H.units.target='Player-1-CastOnly-'..i; H.cast(22812,100,'Cast-Unrelated-'..i)
 end
 local count=0; for _ in pairs(H.ns.CooldownEvidence.unknownHelpful) do count=count+1 end
 check(count==0,'ordinary accepted casts allocate no anonymous/reset continuity records')
 H.units.target='Player-1-Positive'; H.add(5277,101,81)
 check(H.public(5277,101).started==101,'strong helpful identity works after many unrelated casts')
end)

group('post-reset explicit new start can refresh a retained native ID',function()
 local H=fresh(); H.add(5277,100,81,100)
 H.cast(14185,101,'Cast-Preparation')
 check(not H.public(5277,101),'reset retires initially timed native identity')
 H.add(5277,101.1,81,100)
 check(not H.public(5277,101.1),'old explicit start cannot reopen retained native ID')
 H.exact(5277,101.2,81)
 check(not H.public(5277,101.2),'untimed exact retained native ID cannot reopen')
 H.add(5277,102,81,102)
 local row=assert(H.public(5277,102),'new post-reset application start reopens same native ID')
 check(row.started==102 and not row.timingEstimated,'post-reset same-ID application uses explicit start')
 H.add(5277,102.1,81,102)
 check(H.public(5277,102.1).claimID==row.claimID,'same-ID new start duplicate stays deduplicated')
 H.add(5277,102.2,81,100)
 check(H.public(5277,102.2).started==102,'old timed native replay cannot retime accepted new application')
end)

group('post-reset reused-ID exact timing needs both new boundaries',function()
 local H=fresh(); H.add(5277,100,81,100)
 H.cast(14185,101,'Cast-Preparation')
 H.updated(5277,102,81,102,13)
 check(not H.public(5277,102),'unchanged expiry plus shorter duration is not another application')
 H.updated(5277,102.1,81,102,12)
 check(not H.public(5277,102.1),'earlier expiry plus later reconstructed start is not another application')
 H.updated(5277,103,81,103,15)
 local row=assert(H.public(5277,103),'updated/exact positive with new post-reset clock reopens retained ID')
 check(row.started==103 and not row.timingEstimated,'exact fallback uses readable new application clock')
 H.exact(5277,103.1,81,103,15)
 check(H.public(5277,103.1).claimID==row.claimID,'exact replay of new clock stays one claim')
end)

group('missing prior endpoint conserves the uncertain reused identity',function()
 local H=fresh(); H.add(5277,100,81)
 H.cast(14185,101,'Cast-Preparation')
 H.updated(5277,102,81,102,15)
 check(not H.public(5277,102),'one newly readable clock cannot disambiguate unknown prior same-ID endpoint')
 H.exact(5277,102.1)
 check(not H.public(5277,102.1),'ordinary anonymous sighting remains blocked with missing prior endpoint')
 H.add(5277,103)
 local row=assert(H.public(5277,103),'independent fresh added-positive can still consume reset')
 H.exact(5277,103.1,81,102,15)
 check(H.public(5277,103.1).claimID==row.claimID and H.public(5277,103.1).started==102,
  'later precise observation can correct independently accepted post-reset activation')
end)

group('superseded helpful endpoint cannot authorize a later reused-ID reset',function()
 local H=fresh(); H.add(5277,100,81,100)
 H.cast(5277,200,'Cast-LaterEvasion'); H.cast(14185,201,'Cast-Preparation')
 H.updated(5277,202,81,202,15)
 check(not H.public(5277,202),'old helpful clock superseded by a distinct cast cannot prove current reset refresh')
 H.add(5277,203,82,203,15)
 check(H.public(5277,203).started==203,'different independent native identity remains eligible')
end)

group('compatible endpoint extension survives reset independently of start refinement',function()
 for _,hiddenID in ipairs({false,true}) do
  local H=fresh(); H.add(5277,100,81,100,15)
  local claim=H.public(5277,100).claimID
  if hiddenID then H.exact(5277,101,nil,100,20) else H.updated(5277,101,81,100,20) end
  check(H.public(5277,101).claimID==claim and H.public(5277,101).started==100,
   'compatible endpoint correction preserves precise application and claim')
  H.cast(14185,102,'Cast-Preparation')
  H.updated(5277,103,81,103,17)
  check(not H.public(5277,103),'post-reset unchanged corrected endpoint is not a fresh application')
  H.updated(5277,104,81,104,18)
  check(H.public(5277,104).started==104,'genuinely newer post-reset boundaries remain admissible')
 end
end)

group('older shared endpoint cannot roll back latest compatible correction',function()
 local H=fresh(); H.add(5277,100,81,100,15)
 H.updated(5277,101,81,100,20)
 H.time(101.1); H.publish('target',H.units.target,{spellId=5277,auraInstanceID=81,
  duration=15,expirationTime=115},100.5,false)
 H.cast(14185,102,'Cast-Preparation')
 H.updated(5277,103,81,103,17)
 check(not H.public(5277,103),'late delivery of older endpoint cannot reopen duration-only correction')
end)

group('incompatible same-ID application clock cannot replace reset endpoint authority',function()
 local H=fresh(); H.add(5277,100,81,100,15)
 H.updated(5277,101,81,101,30)
 check(H.public(5277,101).started==100,'different readable start is not a correction of accepted application')
 H.cast(14185,102,'Cast-Preparation')
 H.updated(5277,103,81,103,15)
 check(H.public(5277,103).started==103,'conflicting clock did not overwrite accepted reset endpoint')
end)

group('later compatible shortening supplies current reset endpoint',function()
 local H=fresh(); H.add(5277,100,81,100,20)
 H.updated(5277,101,81,100,12)
 H.cast(14185,102,'Cast-Preparation')
 H.updated(5277,103,81,103,9)
 check(not H.public(5277,103),'unchanged current shortened endpoint cannot reopen')
 H.updated(5277,104,81,104,10)
 local row=H.public(5277,104)
 check(row and row.started==104,'new boundaries beyond latest shortening are admissible')
end)

TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS

