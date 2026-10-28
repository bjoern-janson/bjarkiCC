-- CC39-CD1/CD2/CD3: observed native timing is not current application authority.
-- Public Main events / shared-bus input, real TOC modules, unchanged client fixture.
-- State reads below diagnose ownership/bounds only; no production state is written.
-- These source-contract fixtures do not establish native client event cadence.
local fixtureDir=TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup=assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local checks,groups,failures,active=0,{},{},nil
local function check(value,why)checks=checks+1;assert(value,why)end
local function close(a,b)return type(a)=='number' and math.abs(a-b)<.0000001 end
local function count(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function scalar(t)
 local out={};for k,v in pairs(t or {})do if type(v)~='table' then out[k]=v end end;return out
end
local function fresh()
 local H=setup();active=H;H.trace={}
 H.units.target='Player-1-Authority';H.units.focus=H.units.target
 H.hostile.target=true;H.hostile.focus=true
 function H.fire(event,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...)end
 function H.aura(source,at,id,started,expiry,added,stamp)
  H.time(at);local aura={spellId=5277,isHelpful=true,auraInstanceID=id}
  if started then aura.duration=expiry-started;aura.expirationTime=expiry end
  if source=='shared' then H.publish('target',H.units.target,aura,stamp or at,added)
  elseif added then H.fire('UNIT_AURA',source,{addedAuras={aura}})
  else H.auras[source]={[5277]=aura};H.fire('UNIT_AURA',source,{isFullUpdate=true});H.auras[source]=nil end
 end
 function H.rows(at)
  local rows={};for _,row in ipairs(H.ns.model:GetCooldowns(at,nil,true))do
   if row.spellID==5277 and row.guid==H.units.target then rows[#rows+1]=row end
  end;return rows
 end
 function H.row(at)return H.rows(at)[1]end
 function H.app()return H.ns.CooldownEvidence.helpfulApplications[H.units.target..':5277']end
 function H.native(id)return H.ns.CooldownEvidence.seenHelpful[H.units.target..':5277:instance:'..id]end
 function H.record(label,at)
  local row=H.row(at);local E=H.ns.CooldownEvidence
  H.trace[#H.trace+1]={label=label,row=row and {claimID=row.claimID,started=row.started,
   timingEstimated=row.timingEstimated,remaining=row.remaining,claim=row.claim},
   application=scalar(H.app()),native=scalar(H.native(81)),
   unknown=scalar(E.unknownHelpful[H.units.target..':5277'])}
 end
 function H.reset(at)
  H.time(at);H.fire('UNIT_SPELLCAST_SUCCEEDED','target','Authority-Reset-'..at,14185)
  check(#H.rows(at)==0,'accepted Preparation removes the pre-reset Evasion row')
 end
 return H
end
local function group(name,fn)
 active=nil;local ok,err=pcall(fn)
 local busErrors=active and active.ns.EvidenceBus.stats.errors or 0
 if ok and busErrors~=0 then ok=false;err='shared bus consumer errors: '..busErrors end
 groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(err) or nil,
  busErrors=busErrors,trace=active and active.trace}
 if not ok then failures[#failures+1]=name..': '..tostring(err)end
end
local function estimated(H,at,claim,started,why)
 local rows=H.rows(at);check(#rows==1,'exactly one accepted Evasion occurrence remains')
 local row=rows[1]
 check(row.claimID==claim and close(row.started,started) and row.timingEstimated,why)
 check(row.claim.basis=='first-sighting' and #row.claim.revisions==0,
  'rejected native timing cannot publish a timing correction')
 return row
end
local function precise(H,at,claim,started,why)
 local rows=H.rows(at);check(#rows==1,'one precise Evasion occurrence is published')
 local row=rows[1]
 check(row.claimID==claim and close(row.started,started) and not row.timingEstimated,why)
 return row
end
local function prime(sampleSource,untimed)
 local H=fresh();H.aura('target',100,81,not untimed and 100 or nil,115,true)
 check(#H.rows(100)==1,'initial native occurrence accepted')
 if sampleSource then H.aura(sampleSource,102,81,102,117,false)end
 H.reset(102);return H
end
local function anonymous(H,source,at)
 H.aura(source,at,nil,nil,nil,true);local row=assert(H.row(at),'independent anonymous positive accepted')
 estimated(H,at,row.claimID,at,'independent post-reset positive starts an estimated occurrence')
 return row.claimID
end

-- CD1: changing from reset-pending to an anonymous accepted occurrence must
-- preserve the veto carried by timing already sampled before the reset.
for _,before in ipairs({'target','focus','shared'})do
 for _,after in ipairs({'target','focus','shared'})do
  group('CD1 sampled endpoint cannot refine anonymous occurrence '..before..' '..after,function()
   local H=prime(before);local owner=H.native(81).identity
   local claim=anonymous(H,after,103);H.record('post-reset anonymous estimate',103)
   H.aura(after,103.1,81,102,117,false);H.record('repeated pre-reset sampled boundary',103.1)
   estimated(H,103.1,claim,103,'pre-reset sampled boundary must not refine the new anonymous estimate')
   check(H.app().instance~=81,'rejected historical timing cannot acquire current native association')
   check(H.native(81).identity==owner,'historical witness owner remains unchanged')
  end)
 end
end

-- Conditional bounded source-contract stress: two accepted Preparations this
-- close do not establish legal server timing. A second untimed reset/use must
-- not erase previously sampled native timing that remains within history TTL.
for _,source in ipairs({'target','shared'})do
 group('CD1 sampled endpoint survives two anonymous reset cycles '..source,function()
  local H=prime('focus');anonymous(H,'target',103)
  H.reset(104);local claim=anonymous(H,'target',105)
  H.aura(source,105.1,81,104,117,false);H.record('sampled endpoint after two anonymous reset cycles',105.1)
  estimated(H,105.1,claim,105,'untimed reset cycles must not erase retained sampled native evidence')
  check(H.app().instance~=81,'old sampled native cannot acquire ownership after untimed cycles')
  H.aura('focus',105.2,81,104,120,false)
  precise(H,105.2,claim,104,'genuinely newer native endpoint can still refine after untimed cycles')
 end)
end

-- CD2: both delayed delivery and a locally inferred start later than the
-- first sighting fail Model's timing-repair precondition. Neither failure
-- may grant a historical native ID ownership of the accepted estimate.
for _,source in ipairs({'target','focus','shared'})do
 group('CD2 delayed failed repair cannot authorize old native endpoint '..source,function()
  local H=prime();local owner=H.native(81).identity;local claim=anonymous(H,'target',105)
  H.aura('shared',105.1,81,104,120,false,104);H.record('delayed timing repair rejected',105.1)
  estimated(H,105.1,claim,105,'delayed earlier observation cannot immediately refine the estimate')
  local provisional=H.app().instance
  H.aura(source,105.2,81,102,115,false);H.record('old endpoint after failed repair',105.2)
  estimated(H,105.2,claim,105,'failed delayed repair must not let the unchanged old endpoint refine later')
  check(provisional~=81 and H.app().instance~=81,'failed repair must not bind historical native ownership')
  check(H.native(81).identity==owner,'failed association never rewrites historical witness owner')
 end)
end
for _,delta in ipairs({.01,.05,.1})do
 group('CD2 later-start failed repair cannot authorize old native endpoint '..delta,function()
  local H=prime();local claim=anonymous(H,'target',105)
  H.aura('target',105.2,81,105+delta,120,false);H.record('later-start timing repair rejected',105.2)
  estimated(H,105.2,claim,105,'start later than first sighting cannot refine its estimate')
  local provisional=H.app().instance
  H.aura('focus',105.3,81,102,115,false);H.record('old endpoint after later-start failed repair',105.3)
  estimated(H,105.3,claim,105,'failed later-start repair must not let an unchanged old endpoint refine later')
  check(provisional~=81 and H.app().instance~=81,'failed local repair must not bind historical native ownership')
 end)
end

-- CD3: repeat an identical duration/expiry tuple at a later observation clock.
-- Clipping a tolerated future start on its first read cannot create new proof.
for _,source in ipairs({'target','focus','shared'})do
 for _,delta in ipairs({0,.000001,.01,.05,.1})do
  group('CD3 sampled tuple stays old across future-start clipping '..source..' '..delta,function()
   local H=fresh();H.aura('target',100,81,100,115,true)
   H.aura(source,102,81,102+delta,117,true);H.record('native tuple sampled before reset',102)
   H.reset(102);H.aura(source,102.2,81,102+delta,117,true)
   H.record('identical tuple after observation clock advanced',102.2)
   check(#H.rows(102.2)==0,'same pre-reset tuple must not reopen merely because clipping changed')
   H.aura('focus',103,82,103,118,true)
   local row=assert(H.row(103),'fresh distinct native remains eligible after rejected replay')
   precise(H,103,row.claimID,103,'rejected sampled replay cannot consume reset permission')
  end)
 end
end

for _,id in ipairs({81,82})do
 group('fresh native endpoint refines estimate with stable correction provenance '..id,function()
  local H=prime('focus');local owner=H.native(81).identity
  local claim=anonymous(H,'target',103)
  H.aura('shared',103.1,id,103,118,false);H.record('fresh endpoint repairs estimate',103.1)
  local row=precise(H,103.1,claim,103,'genuinely fresh native endpoint refines the same claim')
  check(H.app().instance==id,'successful repair binds the compatible native ID')
  check(row.claim.basis=='aura-start' and #row.claim.revisions==1,'one readable clock correction is published')
  local revision=row.claim.revisions[1]
  check(revision.reason=='same-aura-timestamp' and revision.before==103 and revision.after==103,
   'basis improvement is recorded even when estimated and precise timestamps agree')
  local witnessed=false;for _,w in ipairs(row.claim.witnesses)do
   if w.kind=='readable-aura-start' and w.origin=='Portraits readable aura' then witnessed=true end
  end
  check(witnessed,'correction provenance names the readable shared evidence')
  H.aura('focus',103.2,id,103,118,false)
  row=precise(H,103.2,claim,103,'duplicate fresh timing keeps the same corrected claim')
  check(#row.claim.revisions==1,'duplicate timing does not manufacture another correction')
  check(H.native(81).identity==owner,'successful reuse does not rewrite the original historical owner')
 end)
end
for _,source in ipairs({'target','focus','shared'})do
 group('unsampled genuinely later start and newer endpoint remain admissible '..source,function()
  local H=prime();H.aura(source,102.2,81,102.01,117.01,false)
  local row=assert(H.row(102.2),'new later application is accepted without an added notification')
  precise(H,102.2,row.claimID,102.01,'later start with genuinely newer endpoint identifies a new occurrence')
 end)
 group('unknown historical endpoint permits first readable clock '..source,function()
  local H=prime(nil,true);local claim=anonymous(H,'target',105)
  H.aura(source,105.1,81,104,119,false)
  precise(H,105.1,claim,104,'historical primary without any known endpoint can refine its first readable clock')
  check(H.app().instance==81,'successful first clock binds current native association')
 end)
end
group('unchanged old endpoint remains blocked without a failed repair',function()
 local H=prime();local claim=anonymous(H,'target',105)
 H.aura('focus',105.2,81,102,115,false)
 estimated(H,105.2,claim,105,'unchanged historical endpoint is insufficient on its own')
end)
group('failed repair does not poison subsequent valid same-native refinement',function()
 local H=prime();local claim=anonymous(H,'target',105)
 H.aura('shared',105.1,81,104,120,false,104)
 H.aura('focus',105.2,81,105,121,false)
 precise(H,105.2,claim,105,'a later valid repair can establish historical native reuse')
 check(H.app().instance==81,'only the successful repair establishes association')
end)
group('distinct new native is not limited by another native historical endpoint',function()
 local H=fresh();H.aura('target',100,81,100,200,true);H.reset(102)
 local claim=anonymous(H,'target',105);H.aura('focus',105.1,82,105,110,false)
 precise(H,105.1,claim,105,'distinct native can refine with a shorter endpoint than historical native')
end)
for _,source in ipairs({'focus','shared'})do
 group('legitimate endpoint shortening survives reset authority '..source,function()
  local H=fresh();H.aura('target',100,81,100,130,true)
  local original=assert(H.row(100)).claimID
  H.aura(source,101,81,100,115,false)
  precise(H,101,original,100,'duration shortening preserves the original precise cooldown claim')
  check(H.app().expiry==115,'latest compatible shortening replaces the old longer endpoint')
  H.reset(102);local claim=anonymous(H,'target',105)
  H.aura(source,105.1,81,104,120,false)
  precise(H,105.1,claim,104,'endpoint newer than legitimate shortening can refine a later occurrence')
 end)
end
group('sampled replay rejection leaves independent anonymous reset admission available',function()
 local H=prime('focus');H.aura('focus',102.2,81,102,117,true)
 check(#H.rows(102.2)==0,'already sampled exact-equality boundary remains rejected')
 local claim=anonymous(H,'target',103)
 estimated(H,103,claim,103,'rejected historical tuple cannot consume independent anonymous reset permission')
end)
group('native witness TTL retains below480 and expires at480 seconds',function()
 local H=fresh();H.aura('target',100,81,100,115,true)
 H.aura('target',579.999,82,579.999,594.999,true)
 check(H.native(81)~=nil,'history is retained immediately below the480 second boundary')
 H.aura('target',580,83,580,595,true)
 check(H.native(81)==nil,'history expires at exactly480 seconds')
end)
group('native evidence and continuity remain bounded with scalar witnesses',function()
 local H=fresh()
 for i=1,257 do
  H.units.target='Player-1-AuthorityCap'..i;local at=100+i*.1
  H.aura('target',at,i,at,at+15,true)
 end
 local E=H.ns.CooldownEvidence
 check(count(E.seenHelpful)==256,'257 distinct actors retain at most256 native witnesses')
 check(count(E.helpfulApplications)<=256 and count(E.unknownHelpful)<=256,'application continuity maps stay bounded')
 for _,w in pairs(E.seenHelpful)do
  for _,value in pairs(w)do check(type(value)~='table','retained native witnesses contain scalar history only')end
 end
end)
TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
