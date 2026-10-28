-- Behavioral regressions for lost derived helpful evidence at world entry.
-- Real CC modules/bus/model; only native WoW API boundaries are simulated.
local fresh=assert(loadfile((TEST_DIR or ADDON_DIR..'/tests')..'/world_recovery_support.lua'))()
local G='Player-1-DerivedEnemy'
local A='Player-1-FriendlyAnchor'
local checks,failures=0,0
WORLD_RECOVERY_RESULTS={}
local function case(name,fn)
 local ok,why=pcall(fn)
 checks=checks+1
 WORLD_RECOVERY_RESULTS[#WORLD_RECOVERY_RESULTS+1]={name=name,passed=ok,error=not ok and tostring(why) or nil}
 if not ok then failures=failures+1;print('FAIL world recovery: '..name..': '..tostring(why)) end
end
local function aura(id,instance,start,duration)
 return {spellId=id or 22812,isHelpful=true,auraInstanceID=instance or 900,
  duration=duration,expirationTime=start and duration and start+duration or nil}
end
local function setup(unit,value)
 local H=fresh()
 H.ns.db.bars.cooldown.enabled=true; H.ns.db.targetOnly=false
 H.units[unit=='focustarget' and 'focus' or 'target']=A
 H.units[unit]=G;H.hostile[unit]=true;H.auras[unit]={[22812]=value or aura(22812,900,98,12)}
 return H
end
for _,unit in ipairs({'targettarget','focustarget'}) do
 for _,order in ipairs({'publisher-first','consumer-first'}) do
  case(unit..' '..order..' keeps current snapshot',function()
   local H=setup(unit)
   if order=='publisher-first' then H.publish(unit,G,H.auras[unit][22812]);assert(H.row(G),'shared witness accepted') end
   H.world()
   if order=='consumer-first' then H.publish(unit,G,H.auras[unit][22812]) end
   local row=H.row(G);assert(row and row.started==98 and not row.timingEstimated,'world reset must retain fresh derived cooldown timing')
   assert(#H.ns.UI.GetRows('cooldown',100)==1,'one visible cooldown, without duplicate sensors')
   H.publish(unit,G,H.auras[unit][22812]);assert(H.row(G)==row and row.started==98,'repeat publication preserves occurrence')
  end)
 end
end
case('expired prior-world bus record is not replayed',function()
 local H=setup('targettarget')
 H.time(97);H.publish('targettarget',G,aura(22812,800,85,12));assert(H.row(G))
 H.time(100);H.auras.targettarget={};H.world()
 assert(not H.row(G),'no old bus replay when current snapshot is empty')
end)
case('recent prior-world bus record is not replayed',function()
 local H=setup('targettarget');H.publish('targettarget',G,H.auras.targettarget[22812]);assert(H.row(G))
 H.auras.targettarget={};H.world();assert(not H.row(G),'same-time bus history is not current aura proof')
end)
case('rebinding uses new current recipient only',function()
 local H=setup('targettarget');H.publish('targettarget',G,H.auras.targettarget[22812])
 local other='Player-1-NewRecipient';H.units.targettarget=other;H.auras.targettarget[22812]=aura(22812,901,99,12)
 H.world();assert(not H.row(G),'old recipient cleared');assert(H.row(other) and H.row(other).started==99,'new recipient seeded')
end)
for _,mode in ipairs({'error','secret','missing-api','missing-guid','nonplayer-guid','friendly','readable-npc'}) do
 case(mode..' current derived snapshot fails closed',function()
  local H=setup('targettarget');H.publish('targettarget',G,H.auras.targettarget[22812])
  if mode=='missing-api' then C_UnitAuras.GetUnitAuraBySpellID=nil
  elseif mode=='missing-guid' then H.units.targettarget=nil
  elseif mode=='nonplayer-guid' then H.units.targettarget='Creature-1-Enemy'
  elseif mode=='friendly' then H.hostile.targettarget=false
  elseif mode=='readable-npc' then H.players.targettarget=false
  else H.blocked.targettarget=mode end
  H.world();assert(not H.row(G),'unavailable current evidence must not resurrect old bus record')
 end)
end
case('same identity later exact time refines initial snapshot estimate',function()
 local H=setup('targettarget',aura(22812,900));H.world()
 local row=assert(H.row(G));assert(row.started==100 and row.timingEstimated,'untimed first sighting is an estimate')
 H.time(101);H.publish('targettarget',G,aura(22812,900,98,12))
 assert(H.row(G)==row and row.started==98 and not row.timingEstimated,'same occurrence corrects estimate')
 assert(#H.ns.UI.GetRows('cooldown',101)==1,'correction does not duplicate cooldown')
end)
case('different valid identity keeps normal new activation behavior',function()
 local H=setup('targettarget');H.world();local old=assert(H.row(G));assert(old.started==98)
 H.time(165);H.publish('targettarget',G,aura(22812,901,165,12),165,true)
 assert(H.row(G) and H.row(G).started==165,'later distinct activation remains accepted')
end)
case('same GUID on both derived tokens deduplicates',function()
 local H=setup('targettarget');H.units.focus=A;H.units.focustarget=G;H.hostile.focustarget=true;H.auras.focustarget=H.auras.targettarget
 H.world();assert(H.row(G) and #H.ns.UI.GetRows('cooldown',100)==1,'one actor occurrence across derived aliases')
 assert(H.ns.CooldownEvidence.stats.helpfulAccepted==1,'one activation accepted')
end)
case('world pass leaves no replay queue or periodic derived reads',function()
 local H=setup('targettarget');H.world();assert(H.row(G),'first pass recovers')
 local count=#H.queries;H.time(101);H.ns.eventFrame.scripts.OnUpdate(H.ns.eventFrame,.25)
 assert(#H.queries==count,'ordinary poll does not add derived helpful reads')
end)
case('repeated world entries clear old actors and seed only current bounded inputs',function()
 local H=setup('targettarget')
 for i=1,300 do
  H.time(100+i);H.units.targettarget='Player-1-'..i;H.auras.targettarget[22812]=aura(22812,1000+i,99+i,12);H.world()
  local n=0;for _ in pairs(H.ns.model.casters)do n=n+1 end;assert(n==1,'world reset never accumulates actor history')
  local seen=0;for _ in pairs(H.ns.CooldownEvidence.seenHelpful)do seen=seen+1 end;assert(seen==1,'world reset never accumulates witness history')
 end
end)
case('general derived aura-event and unit-seen contracts remain scoped',function()
 local H=setup('targettarget')
 H.ns.CooldownEvidence.OnUnitSeen('targettarget',100)
 H.ns.CooldownEvidence.OnAuraEvent('targettarget',{addedAuras={H.auras.targettarget[22812]}},100)
 assert(not H.row(G),'new derived eligibility is world-entry only')
end)
case('existing target and nameplate helpful paths remain valid',function()
 local H=setup('target');H.world();assert(H.row(G) and H.row(G).started==98)
 local other='Player-1-Nameplate';H.units.nameplate1=other;H.hostile.nameplate1=true;H.auras.nameplate1={[22812]=aura(22812,902,98,12)}
 H.ns.CooldownEvidence.OnUnitSeen('nameplate1',100);assert(H.row(other),'nameplate evidence remains supported')
end)
assert(failures==0,tostring(failures)..' of '..checks..' world recovery cases failed')
print('world recovery: '..checks..' cases passed')
