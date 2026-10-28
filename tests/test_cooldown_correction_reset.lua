-- Catch optional-ID duration corrections becoming new uses, and a pre-reset
-- ID-less event swallowing a genuine post-reset activation. Real Main events
-- and public cooldown rows use only the established client-boundary fixture.
local fixtureDir = TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup = assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local checks, groups, failures = 0, {}, {}
local function check(value, why) assert(value, why); checks=checks+1 end
local function close(a,b) return math.abs(a-b)<.00001 end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function fresh()
 local H=setup(); H.units.target='Player-1-R'; H.units.focus='Player-1-O'
 H.hostile.target=true; H.hostile.focus=true
 function H.fire(event,...) H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...) end
 function H.cast(id,at,castID,unit)
  H.time(at); H.fire('UNIT_SPELLCAST_SUCCEEDED',unit or 'target',castID,id)
 end
 function H.aura(id,at,instance,start,duration,added,unit)
  unit=unit or 'target'; H.time(at)
  local aura={spellId=id,isHelpful=true,auraInstanceID=instance}
  if start then aura.duration=duration or 15; aura.expirationTime=start+aura.duration end
  if added then H.fire('UNIT_AURA',unit,{addedAuras={aura}})
  else
   H.auras[unit]={[id]=aura}; H.fire('UNIT_AURA',unit,{isFullUpdate=true}); H.auras[unit]=nil
  end
 end
 function H.public(id,at,unit)
  for _,row in ipairs(H.ns.model:GetCooldowns(at,nil,true)) do
   if row.spellID==id and row.guid==H.units[unit or 'target'] then return row end
  end
 end
 return H
end
local function group(name,fn)
 local ok,why=pcall(fn)
 groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(why) or nil}
 if not ok then failures[#failures+1]=name..': '..tostring(why) end
end

group('optional identity loss conserves a precise claim under duration correction',function()
 for _,instance in ipairs({false,'secret',81}) do
  local H=fresh(); H.aura(5277,100,81,100,15,true)
  local before=assert(H.public(5277,100))
  H.aura(5277,103,instance=='secret' and H.hidden or instance or nil,103,12,false)
  local row=assert(H.public(5277,103))
  check(row.claimID==before.claimID and row.started==100,
   'same endpoint115 with duration12 retains start100 and original claim despite optional ID loss')
  check(row.remaining==297 and row.earlyRemaining==117,'duration correction preserves original cooldown interval')
 end
end)

group('optional identity loss cannot resurrect a reset duration correction',function()
 for _,instance in ipairs({false,'secret',81}) do
  local H=fresh(); H.aura(5277,100,81,100,15,true)
  H.cast(14185,102,'Cast-Preparation'); check(not H.public(5277,102),'reset retires Evasion')
  H.aura(5277,103,instance=='secret' and H.hidden or instance or nil,103,12,false)
  check(not H.public(5277,103),'unchanged endpoint115 cannot reopen reset application when ID is unavailable')
  H.aura(5277,104,nil,104,10.95,false)
  check(not H.public(5277,104),'earlier endpoint also cannot reopen reset application')
  H.aura(5277,105,nil,105,15,false)
  local row=assert(H.public(5277,105),'independently later start105/end120 remains a new timed application')
  check(row.started==105,'new boundaries establish actual new start')
 end
end)

group('endpoint tolerance preserves continuity and distinct positive evidence',function()
 local H=fresh(); H.aura(5277,100,81,100,15,true)
 local before=H.public(5277,100)
 H.aura(5277,103,nil,103,12.05,false)
 check(H.public(5277,103).claimID==before.claimID,'endpoint rounding within0.1 retains original claim')
 H.cast(14185,104,'Cast-Preparation')
 H.aura(5277,105,nil,105,10.1,false)
 check(not H.public(5277,105),'endpoint within tolerance of accepted115.05 remains pre-reset correction')
 H.aura(5277,106,82,106,9.05,true)
 local row=assert(H.public(5277,106),'different native ID and added positive proves independent application')
 check(row.started==106,'independent positive uses its own start even with matching old endpoint')
 H=fresh(); H.aura(5277,100,81,100,15,true); H.cast(14185,102,'Cast-Preparation')
 H.aura(5277,103,nil,103,12,true)
 check(H.public(5277,103).started==103,'fresh anonymous added positive remains independent evidence')
end)

group('compatible endpoint freshness survives optional identity loss and late shared records',function()
 local H=fresh(); H.aura(5277,100,81,100,15,true)
 local claim=H.public(5277,100).claimID
 H.aura(5277,101,nil,100,20,false)
 H.time(101.5); H.publish('target',H.units.target,{spellId=5277,duration=15,expirationTime=115},100.5,false)
 check(H.public(5277,101.5).claimID==claim and H.public(5277,101.5).started==100,
  'late shared duration correction cannot create a new claim')
 H.cast(14185,102,'Cast-Preparation')
 H.aura(5277,103,nil,103,17,false)
 check(not H.public(5277,103),'old publication cannot replace newest compatible endpoint120')
 H.aura(5277,104,nil,104,18,false)
 check(H.public(5277,104).started==104,'start104/end122 is a genuine later application')
end)

group('late incompatible optional-ID correction cannot replace a fresher compatible endpoint',function()
 local H=fresh(); H.aura(5277,100,81,100,15,true)
 local claim=H.public(5277,100).claimID
 H.aura(5277,103.1,nil,100,20,false)
 H.time(103.5); H.publish('target',H.units.target,{spellId=5277,duration=13,expirationTime=115},102.1,false)
 local row=assert(H.public(5277,103.5))
 check(row.claimID==claim and row.started==100,'older optional-ID timing cannot supersede fresher endpoint correction')
 H.cast(14185,104,'Cast-Preparation')
 H.aura(5277,105,nil,105,15,false)
 check(not H.public(5277,105),'latest compatible endpoint120 survives delayed obsolete duration correction')
 H.aura(5277,106,nil,106,15,false)
 check(H.public(5277,106).started==106,'genuinely newer endpoint remains eligible after stale correction')
end)

group('fresh later start103 and endpoint118 remain independent timed evidence',function()
 for _,instance in ipairs({false,81,82}) do
  local H=fresh(); H.aura(5277,100,81,100,15,true)
  local claim=H.public(5277,100).claimID; H.cast(14185,102,'Cast-Preparation')
  H.aura(5277,103,instance or nil,103,15,false)
  local row=assert(H.public(5277,103),'start103/end118 proves a later application')
  check(row.started==103 and row.claimID~=claim,'both genuinely newer boundaries remain admissible')
 end
end)

group('rejected stale optional-ID correction cannot poison subsequent genuine evidence',function()
 for _,mode in ipairs({'ordinary-new','distinct-native','added-anonymous'}) do
  local H=fresh(); H.aura(5277,100,81,100,15,true)
  local claim=H.public(5277,100).claimID
  H.aura(5277,103.1,nil,100,20,false)
  H.time(103.5); H.publish('target',H.units.target,{spellId=5277,duration=13,expirationTime=115},102.1,false)
  check(H.public(5277,103.5).claimID==claim,'stale incompatible optional-ID report is rejected')
  H.aura(5277,103.6,mode=='distinct-native' and 82 or nil,102,15,mode=='added-anonymous')
  local row=assert(H.public(5277,103.6),'newer independent evidence is still eligible')
  check(row.started==102 and row.claimID~=claim,
   'rejected old start102 alias does not consume later genuine start102/end117 identity')
 end
end)

group('equal observation time conserves compatible endpoint independent of sensor order',function()
 for _,reverse in ipairs({false,true}) do
  local H=fresh(); H.aura(5277,100,81,100,15,true)
  local claim=H.public(5277,100).claimID
  local function donor()
   H.time(103); H.publish('target',H.units.target,{spellId=5277,duration=13,expirationTime=115},103,false)
  end
  if reverse then donor(); H.aura(5277,103,nil,100,20,false)
  else H.aura(5277,103,nil,100,20,false); donor() end
  local row=assert(H.public(5277,103))
  check(row.claimID==claim and row.started==100,
   'equal-time ordinary missing-ID observations retain claim1/start100 in either delivery order')
  local application=assert(H.ns.CooldownEvidence.helpfulApplications[H.units.target..':5277'])
  check(application.expiry==120 and application.expiryObservedAt==103,
   'equal-time correction order conserves compatible endpoint120 and its observation clock')
  H.cast(14185,104,'Cast-Preparation'); H.aura(5277,105,nil,105,15,false)
  check(not H.public(5277,105),'equal-time obsolete endpoint cannot authorize post-reset resurrection')
 end
end)

group('equal observation time still permits independently later application boundaries',function()
 for _,mode in ipairs({'ordinary-new','distinct-native','added-anonymous','compatible-older-end'}) do
  local H=fresh(); H.aura(5277,100,81,100,15,true)
  local claim=H.public(5277,100).claimID
  H.aura(5277,103,nil,100,20,false)
  if mode=='compatible-older-end' then
   H.aura(5277,103,nil,100,15,false)
   local row=assert(H.public(5277,103))
   check(row.claimID==claim and row.started==100,'equal-time compatible older endpoint preserves occurrence')
   check(H.ns.CooldownEvidence.helpfulApplications[H.units.target..':5277'].expiry==120,
    'equal-time compatible shortening cannot roll back retained later endpoint')
  else
   local duration=mode=='ordinary-new' and 20 or 13
   H.aura(5277,103,mode=='distinct-native' and 82 or nil,102,duration,mode=='added-anonymous')
   local row=assert(H.public(5277,103),'independent equal-time evidence remains admissible')
   check(row.claimID~=claim and row.started==102,
    'later start102/end122 or distinct nativeID/added positive proves a separate occurrence')
  end
 end
end)

group('post-reset successful cast separates fallback matching for all optional ID combinations',function()
 for _,firstNative in ipairs({false,true}) do
  for _,secondNative in ipairs({false,true}) do
   for _,delta in ipairs({.1,.2,2}) do
    local H=fresh(); H.cast(5277,100,firstNative and 'Cast-First' or nil)
    local before=H.public(5277,100)
    H.cast(14185,100.05,'Cast-Preparation'); check(not H.public(5277,100.05),'Preparation resets first use')
    H.cast(5277,100+delta,secondNative and 'Cast-Second' or nil)
    local row=assert(H.public(5277,100+delta),'fresh post-reset successful cast must survive fallback dedup')
    check(close(row.started,100+delta) and row.claimID~=before.claimID,'second use has a fresh exact claim')
    H.cast(5277,100+delta+.01,secondNative and 'Cast-Second' or nil)
    check(H.public(5277,100+delta+.01).claimID==row.claimID,'post-reset duplicate success remains one claim')
    if firstNative then
     H.cast(5277,100+delta+.3,'Cast-First')
     check(H.public(5277,100+delta+.3).claimID==row.claimID,'pre-reset native ID stays deduplicated')
    end
    H.cast(14185,100+delta+.4,'Cast-Preparation')
    check(H.public(5277,100+delta+.4).claimID==row.claimID,'duplicate Preparation never reopens reset permission')
   end
  end
 end
end)

group('post-reset helpful positives remain accepted refinable and deduplicated',function()
 for _,firstNative in ipairs({false,true}) do
  for _,auraNative in ipairs({false,true}) do
   for _,delta in ipairs({.1,.2,2}) do
    local H=fresh(); H.cast(5277,100,firstNative and 'Cast-First' or nil)
    local before=H.public(5277,100)
    H.cast(14185,100.05,'Cast-Preparation')
    H.aura(5277,100+delta,auraNative and 82 or nil,nil,nil,true)
    local row=assert(H.public(5277,100+delta),'fresh added aura survives old ID-less fallback event')
    check(row.claimID~=before.claimID and row.timingEstimated,'new positive creates one estimated application')
    H.aura(5277,100+delta+.2,auraNative and 82 or nil,nil,nil,true)
    check(H.public(5277,100+delta+.2).claimID==row.claimID,'repeated added positive stays one claim')
    H.aura(5277,100+delta+.3,auraNative and 82 or nil,100+delta-.01,15,false)
    local refined=assert(H.public(5277,100+delta+.3))
    check(refined.claimID==row.claimID and close(refined.started,100+delta-.01)
     and not refined.timingEstimated,'readable clock refines accepted post-reset identity')
    H.aura(5277,104+delta,nil,nil,nil,false)
    check(H.public(5277,104+delta).claimID==row.claimID,'ordinary later sighting cannot renew again')
   end
  end
 end
end)

group('equal-time accepted reset order separates successful cast and helpful positives',function()
 for _,mode in ipairs({'cast-native','cast-nil','aura-native','aura-nil'}) do
  local H=fresh(); H.cast(5277,100,nil)
  local before=H.public(5277,100)
  H.cast(14185,100,'Cast-Preparation')
  if mode=='cast-native' then H.cast(5277,100,'Cast-Second')
  elseif mode=='cast-nil' then H.cast(5277,100,nil)
  else H.aura(5277,100,mode=='aura-native' and 82 or nil,nil,nil,true) end
  local row=assert(H.public(5277,100),'accepted reset order distinguishes post-reset use at same GetTime')
  check(row.claimID~=before.claimID and row.started==100,'equal-time second occurrence has separate claim')
 end
end)

group('retiring pre-reset matching preserves unrelated spell caster and Cold Snap controls',function()
 local H=fresh(); H.cast(22812,100,nil); H.cast(5277,100,nil,'focus'); H.cast(5277,100,nil)
 local unrelated=H.public(22812,100).claimID; local other=H.public(5277,100,'focus').claimID
 H.cast(14185,100.05,'Cast-Preparation')
 H.cast(22812,100.1,'Cast-Unrelated'); H.cast(5277,100.1,'Cast-Other','focus')
 check(H.public(22812,100.1).claimID==unrelated,'unrelated spell fallback still attaches later ID')
 check(H.public(5277,100.1,'focus').claimID==other,'other caster fallback still attaches later ID')
 H.cast(5277,100.1,'Cast-New')
 check(assert(H.public(5277,100.1),'affected spell must survive reset-aware fallback matching').started==100.1,
  'affected spell receives new post-reset use')
 H=fresh(); H.cast(122,100,nil); H.cast(5277,100,nil)
 local evasion=H.public(5277,100).claimID
 H.cast(12472,100.05,'Cast-ColdSnap'); check(not H.public(122,100.05),'Cold Snap resets its own tracked family')
 H.cast(122,100.1,'Cast-NewNova'); check(H.public(122,100.1).started==100.1,'Cold Snap permits fast new affected use')
 H.cast(5277,100.1,'Cast-OldEvasion')
 check(H.public(5277,100.1).claimID==evasion,'Cold Snap preserves unrelated Evasion fallback')
end)

group('rejected reset and ordinary no-reset duplicate still preserve fallback matching',function()
 local H=fresh(); H.cast(5277,100,nil); local claim=H.public(5277,100).claimID
 H.hostile.target=false; H.cast(14185,100.05,'Cast-Rejected'); H.hostile.target=true
 H.cast(5277,100.1,'Cast-LaterIdentity')
 check(H.public(5277,100.1).claimID==claim and H.public(5277,100.1).started==100,
  'rejected reset cannot retire fallback identity matching')
 H.cast(5277,100.4,'Cast-LaterIdentity')
 check(H.public(5277,100.4).claimID==claim,'later attached native ID remains deduplicated')
 H=fresh(); H.cast(5277,100,nil); claim=H.public(5277,100).claimID
 H.cast(5277,100.1,'Cast-LaterIdentity')
 check(H.public(5277,100.1).claimID==claim,'without reset later native ID is same occurrence')
 H.aura(5277,100.11,82,nil,nil,true)
 check(H.public(5277,100.11).claimID==claim,'without reset near aura corroborates accepted cast')
 H=fresh(); H.cast(5277,100,nil); claim=H.public(5277,100).claimID
 H.cast(14185,100.05,H.hidden); H.cast(5277,100.1,'Cast-LaterIdentity')
 check(H.public(5277,100.1).claimID==claim,'secret reset identity cannot retire fallback')
end)

group('late pre-reset shared records stay rejected after successful fallback repair',function()
 local H=fresh(); H.cast(5277,100,nil); H.cast(14185,100.05,'Cast-Preparation')
 H.time(100.1); H.publish('target',H.units.target,{spellId=5277,auraInstanceID=81},100,true)
 check(not H.public(5277,100.1),'delayed old shared positive cannot consume accepted reset')
 H.publish('target',H.units.target,{spellId=5277,auraInstanceID=82},100.1,true)
 local row=assert(H.public(5277,100.1),'fresh shared positive remains admissible')
 H.time(100.2); H.publish('target',H.units.target,{spellId=5277,auraInstanceID=81,duration=15,
  expirationTime=115},100,false)
 check(H.public(5277,100.2).claimID==row.claimID and H.public(5277,100.2).started==100.1,
  'late pre-reset shared timing cannot rewrite repaired claim')
end)

group('repeated fast reset corrections keep bounded state',function()
 local H=fresh(); H.cast(5277,100,nil)
 for i=1,400 do
  local at=100+i*.1
  H.cast(14185,at,'Cast-Reset-'..i)
  H.cast(5277,at+.01,'Cast-Evasion-'..i)
 end
 local row=assert(H.public(5277,140.01))
 check(close(row.started,140.01),'latest fast post-reset successful use remains tracked')
 local caster=H.ns.model.casters[H.units.target]
 check(count(caster.recent)<=2 and count(caster.castIDs)<=128,'recent matching and native IDs remain bounded')
 check(count(H.ns.CooldownEvidence.unknownHelpful)<=256,'reset continuity remains bounded')
 check(count(H.ns.CooldownEvidence.helpfulApplications)<=256,'application continuity remains bounded')
 check(#H.ns.model.claimActivity<=64,'claim explanation history remains bounded')
end)

TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
