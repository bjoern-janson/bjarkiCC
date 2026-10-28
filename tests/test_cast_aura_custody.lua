-- Regression: cast corroboration must retain aura custody without revising cast timing.
local setup=assert(loadfile((TEST_DIR or ((ADDON_DIR or '.')..'/tests'))..'/world_recovery_support.lua'))()
local groups={}
for _,initial in ipairs({'native-owned','cast-first','late-native'})do
 for _,anonymous in ipairs({false,true})do
  for _,idless in ipairs({false,true})do
   for _,fresh in ipairs({false,true})do
    local H=setup();local G='Player-1-RootCorroboration';H.units.target=G;H.hostile.target=true
    local function fire(e,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,e,...)end
    local function aura(at,id,start,finish,added)
     H.time(at);local a={spellId=5277,isHelpful=true,auraInstanceID=id}
     if start then a.duration=finish-start;a.expirationTime=finish end
     if added then fire('UNIT_AURA','target',{addedAuras={a}})
     else H.auras.target={[5277]=a};fire('UNIT_AURA','target',{isFullUpdate=true});H.auras.target=nil end
    end
    local function cast(at,id)H.time(at);fire('UNIT_SPELLCAST_SUCCEEDED','target','Cast-'..at..'-'..id,id)end
    local function row(at)
     for _,r in ipairs(H.ns.model:GetCooldowns(at,G,true))do if r.spellID==5277 then return r end end
    end
    local function copy(t)local d={};for k,v in pairs(t or {})do if type(v)~='table' then d[k]=v end end;return d end
    local trace={}
    local function capture(label,at)
     trace[#trace+1]={label=label,row=copy(row(at)),
      application=copy(H.ns.CooldownEvidence.helpfulApplications[G..':5277']),
      unknown=copy(H.ns.CooldownEvidence.unknownHelpful[G..':5277'])}
    end
    if initial=='cast-first' then cast(100,5277);aura(100.2,81,100,115,true)
    else
     local id=initial=='native-owned' and 81 or nil
     aura(100,id,100,115,true);cast(100.2,5277)
     if initial=='late-native' then aura(100.4,81,100,115,false)end
    end
    local original=assert(row(100.4));assert(original.evidenceSource=='cast')
    capture('linked aura and cast',100.4)
    aura(102,81,102,117,false);capture('pre-reset sample',102)
    assert(row(102).started==original.started,'incompatible sample must not retime cast')
    cast(102,14185);assert(not row(102),'reset must retire cooldown');capture('reset',102)
    local estimate
    if anonymous then
     aura(103,nil,nil,nil,true);estimate=assert(row(103))
     assert(estimate.timingEstimated and estimate.started==103 and estimate.claimID~=original.claimID)
    end
    local id=idless and nil or 81
    if idless then id=nil end
    aura(103.1,id,fresh and 103 or 102,fresh and 118 or 117,false)
    local final=row(103.1);capture('replay or fresh control',103.1)
    local correct
    if estimate then
     correct=final and final.claimID==estimate.claimID and final.started==103
      and final.timingEstimated==(not fresh) and final.claimRevisionCount==(fresh and 1 or 0)
    elseif fresh then correct=final and final.started==103 and not final.timingEstimated
    else correct=not final end
    groups[#groups+1]={initial=initial,anonymous=anonymous,idless=idless,fresh=fresh,
     correct=correct==true,busErrors=H.ns.EvidenceBus.stats.errors,trace=trace}
   end
  end
 end
end
local failures={}
for _,g in ipairs(groups)do if not g.correct or g.busErrors~=0 then failures[#failures+1]=g.initial..' anonymous='..tostring(g.anonymous)..' idless='..tostring(g.idless)..' fresh='..tostring(g.fresh) end end
TEST_RESULTS={groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
