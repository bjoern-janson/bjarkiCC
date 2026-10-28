-- A pre-reset sample cannot become fresh evidence when its optional ID is
-- lost, or when the original claim was promoted to successful-cast evidence.
-- Exercise the real Main / public bus paths; model and evidence state are
-- observed only through public cooldown output and never assigned by tests.
local fixtureDir=TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup=assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local groups,failures,checks={},{},0
local function check(ok,why)checks=checks+1;assert(ok,why)end
for _,route in ipairs({'target','shared'})do
 for _,anonymous in ipairs({false,true})do
  for _,mode in ipairs({'native-control','id-missing','id-secret','cast-promoted','cast-promoted-fresh','id-missing-fresh'})do
   local H=setup();local guid='Player-1-ResetCustody';H.units.target=guid;H.hostile.target=true
   local function fire(event,...)H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,event,...)end
   local function aura(at,id,start,expiry,added)
    H.time(at);local a={spellId=5277,isHelpful=true,auraInstanceID=id}
    if start then a.duration=expiry-start;a.expirationTime=expiry end
    if route=='shared' then check(H.publish('target',guid,a,at,added),'valid public observation')
    elseif added then fire('UNIT_AURA','target',{addedAuras={a}})
    else H.auras.target={[5277]=a};fire('UNIT_AURA','target',{isFullUpdate=true});H.auras.target=nil end
   end
   local function row(at)
    local found
    for _,r in ipairs(H.ns.model:GetCooldowns(at,guid,true))do if r.spellID==5277 then
     check(not found,'one public row per cooldown');found=r
    end end
    return found
   end
   local name=route..'/'..mode..'/anonymous='..tostring(anonymous)
   local ok,err=pcall(function()
    aura(100,81,100,115,true);local original=assert(row(100))
    local promote=mode:match('cast%-promoted')~=nil
    if promote then H.time(100.2);fire('UNIT_SPELLCAST_SUCCEEDED','target','Cast-Evasion',5277)end
    aura(102,81,102,117,false);local sampled=assert(row(102))
    check(sampled.claimID==original.claimID and sampled.started==(promote and 100.2 or 100),
     'incompatible aura timing cannot alter the accepted application or cast clock')
    check(sampled.evidenceSource==(promote and 'cast' or 'helpful-aura'),'successful cast retains source authority')
    H.time(102);fire('UNIT_SPELLCAST_SUCCEEDED','target','Cast-Preparation',14185)
    check(not row(102),'accepted reset retires previous cooldown')
    local estimate
    if anonymous then
     aura(103,nil,nil,nil,true);estimate=assert(row(103))
     check(estimate.started==103 and estimate.timingEstimated and estimate.claimID~=original.claimID,
      'independent added positive creates a new estimated occurrence')
    end
    local id=81
    if mode:match('id%-missing') then id=nil elseif mode=='id-secret' then id=H.hidden end
    local fresh=mode:match('fresh')~=nil
    aura(103.1,id,fresh and 103 or 102,fresh and 118 or 117,false)
    local final=row(103.1)
    if estimate then
     check(final and final.claimID==estimate.claimID,'refinement preserves new claim identity')
     check(final.started==103 and final.timingEstimated==(not fresh)
      and final.claimRevisionCount==(fresh and 1 or 0),
      'only genuinely later timing can refine the independent estimate')
    elseif fresh then
     check(final and final.started==103 and not final.timingEstimated and final.claimID~=original.claimID,
      'genuinely later ordinary timing can establish a new occurrence')
    else check(not final,'previously sampled tuple cannot reopen a reset cooldown')end
   end)
   local errors=H.ns.EvidenceBus.stats.errors
   if errors~=0 then ok=false;err='bus callback errors' end
   groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(err) or nil,busErrors=errors}
   if not ok then failures[#failures+1]=name..': '..tostring(err)end
  end
 end
end
TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
