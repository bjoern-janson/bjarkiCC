-- A native tuple already observed before accepted Preparation is historical
-- evidence, even if another unit token or sensor repeats it after that reset.
-- Baseline .38 passes this control. It protects the equal-time admission fix
-- from relabeling an old observation as a new independent positive.
local fixtureDir = TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup = assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local groups, failures, checks, active = {}, {}, 0, nil
local function check(ok,why) assert(ok,why); checks=checks+1 end
local function fresh()
 local H=setup(); active=H; H.trace={}
 H.units.target='Player-1-Replay'; H.units.focus=H.units.target
 H.hostile.target=true; H.hostile.focus=true
 function H.fire(event,...) H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...) end
 function H.aura(source,at,native,start,finish,added)
  H.time(at)
  local aura={spellId=5277,isHelpful=true,auraInstanceID=native,
   duration=finish-start,expirationTime=finish}
  if source=='shared' then H.publish('target',H.units.target,aura,at,added)
  elseif added then H.fire('UNIT_AURA',source,{addedAuras={aura}})
  else
   H.auras[source]={[5277]=aura}; H.fire('UNIT_AURA',source,{isFullUpdate=true})
   H.auras[source]=nil
  end
 end
 function H.reset(at)
  H.time(at); H.fire('UNIT_SPELLCAST_SUCCEEDED','target','Reset-Replay',14185)
 end
 function H.rows(at)
  local rows={}
  for _,row in ipairs(H.ns.model:GetCooldowns(at,nil,true)) do
   if row.spellID==5277 and row.guid==H.units.target then rows[#rows+1]=row end
  end
  return rows
 end
 function H.record(label,at)
  local rows=H.rows(at); local row=rows[1]
  H.trace[#H.trace+1]={label=label,count=#rows,claim=row and row.claimID,
   started=row and row.started,estimated=row and row.timingEstimated}
 end
 function H.one(at,claim,start)
  local rows=H.rows(at)
  check(#rows==1,'expected exactly one public Evasion row')
  check(rows[1].started==start and not rows[1].timingEstimated,'readable occurrence retains its original start')
  if claim then check(rows[1].claimID==claim,'sensor replay cannot replace the occurrence claim') end
  return rows[1]
 end
 return H
end
local function group(name,fn)
 active=nil
 local ok,why=pcall(fn)
 local busErrors=active and active.ns.EvidenceBus.stats.errors or 0
 if ok and busErrors~=0 then ok=false; why='shared bus callback errors: '..busErrors end
 groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(why) or nil,
  busErrors=busErrors,trace=active and active.trace}
 if not ok then failures[#failures+1]=name..': '..tostring(why) end
end

for _,beforeSource in ipairs({'target','focus','shared'}) do
 for _,afterSource in ipairs({'target','focus','shared'}) do
  for _,beforeAdded in ipairs({true,false}) do
   group((beforeAdded and 'added' or 'exact')..' tuple before reset '..beforeSource..' then '..afterSource,function()
    local H=fresh()
    H.aura('target',100,81,100,115,true)
    local oldClaim=H.one(100,nil,100).claimID
    -- This tuple has already been seen by the same actor before Preparation;
    -- the native aura continues the existing precise occurrence at100.
    H.aura(beforeSource,102,81,102,117,beforeAdded)
    H.one(102,oldClaim,100); H.record('tuple observed before reset',102)
    H.reset(102)
    check(#H.rows(102)==0,'accepted reset retires the pre-reset occurrence')
    H.record('accepted reset',102)
    H.aura(afterSource,102,81,102,117,true)
    H.record('same tuple added replay after reset',102)
    check(#H.rows(102)==0,'already-observed native tuple cannot become fresh evidence after reset')
    H.aura(afterSource,102.1,81,102,117,false)
    check(#H.rows(102.1)==0,'later exact replay of the same tuple remains retired')
    -- Suppression must leave reset permission available. Distinct native82
    -- is unambiguous under both baseline .38 and the candidate contract.
    H.aura(afterSource,102.1,82,102,117,true)
    local current=H.one(102.1,nil,102)
    check(current.claimID~=oldClaim,'fresh distinct native gets a new occurrence claim')
    H.record('distinct native positive retains reset permission',102.1)
    for _,source in ipairs({'target','focus','shared'}) do
     H.aura(source,102.2,81,102,117,true)
     H.one(102.2,current.claimID,102)
     H.aura(source,102.3,82,102,117,false)
     local row=H.one(102.3,current.claimID,102)
     check(#row.claim.witnesses<=4 and row.claimRevisionCount<=4,
      'duplicate sensor explanations stay within the public claim bounds')
    end
    H.reset(102.4)
    H.one(102.4,current.claimID,102)
   end)
  end
 end
end

TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
