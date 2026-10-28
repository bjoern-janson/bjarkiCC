-- Provenance-only reports must not replace an established promoted occurrence owner.
local setup=assert(loadfile((TEST_DIR or ((ADDON_DIR or '.')..'/tests'))..'/world_recovery_support.lua'))()
local groups,failures={},{}
for _,idKind in ipairs({'missing','different','same'})do
 local H=setup();local G='Player-1-Handoff42';H.units.target=G;H.hostile.target=true
 local function event(name,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,name,...)end
 local function aura(at,id,start,finish,added)
  H.time(at);local a={spellId=5277,isHelpful=true,auraInstanceID=id}
  if start then a.duration=finish-start;a.expirationTime=finish end
  if added then event('UNIT_AURA','target',{addedAuras={a}})
  else H.auras.target={[5277]=a};event('UNIT_AURA','target',{isFullUpdate=true});H.auras.target=nil end
 end
 local function cast(at,id)H.time(at);event('UNIT_SPELLCAST_SUCCEEDED','target','Handoff-'..at..'-'..id,id)end
 local function scalars(t)local d={};for k,v in pairs(t or {})do if type(v)~='table' then d[k]=v end end;return d end
 local trace={}
 local function snap(label,at)
  local row
  for _,r in ipairs(H.ns.model:GetCooldowns(at,G,true))do if r.spellID==5277 then row=r end end
  local private=H.ns.model.casters[G] and H.ns.model.casters[G].cooldowns[5277]
  trace[#trace+1]={label=label,row=scalars(row),private=scalars(private),
   application=scalars(H.ns.CooldownEvidence.helpfulApplications[G..':5277']),
   native=scalars(H.ns.CooldownEvidence.seenHelpful[G..':5277:instance:81'])}
 end
 aura(100,81,100,115,true);cast(100.2,5277)
 snap('promoted',100.2)
 aura(100.4,idKind=='same' and 81 or idKind=='different' and 82 or nil,100.3,115.3,false)
 snap('near cast provenance handoff',100.4)
 aura(102,81,102,117,false);snap('sampled',102)
 cast(102,14185);aura(103,nil,nil,nil,true);snap('independent estimate',103)
 aura(103.1,81,102,117,false);snap('replay',103.1)
 local final=trace[#trace].row
 local ok=final.started==103 and final.timingEstimated and final.claimRevisionCount==0
  and final.claimID==trace[#trace-1].row.claimID and H.ns.EvidenceBus.stats.errors==0
 groups[#groups+1]={idKind=idKind,trace=trace,ok=ok}
 if not ok then failures[#failures+1]=idKind..': provenance handoff lost owned sample and let old timing refine a new claim' end
end
TEST_RESULTS={groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
