local ns = {Safe={}, Data={categoryByKey={stun={name='Stun',short='STUN'}}}}
local path=(ADDON_DIR or 'work/bjarkiCC')..'/UI.lua'
local f=io.open(path); assert(f,'UI is not implemented yet'); f:close()
assert(loadfile(path))('bjarkiCC',ns)
ns.db={categories={stun=true,fear=false},targetOnly=false,interrupts=false,disabledSpells={},bars={},stageResetSeconds=18}
ns.Observer={GetUnitState=function(unit) return {guid=unit=='target' and 'B' or 'A'} end}
ns.model={
 GetDR=function(self,guid,now) return {{category='stun',stage=1,active=false,remaining=10,started=10},{category='fear',stage=2,active=false,remaining=10,started=10}} end,
 GetCooldowns=function(self,now,guid)
  local rows={{guid='A',spellID=853,interrupt=false},{guid='B',spellID=408,interrupt=false},{guid='B',spellID=1766,interrupt=true}}
  if not guid then return rows end
  local out={}; for _,r in ipairs(rows) do if r.guid==guid then out[#out+1]=r end end
  return out
 end}
assert(#ns.UI.GetRows('player',0)==1,'DR category disabled must hide row')
assert(#ns.UI.GetRows('focus',0)==1,'focus uses the DR category filters')
ns.model.GetDR=function() return {
 {category='stun',stage=3,active=true,remaining=25,started=25},
 {category='fear',stage=2,active=false,remaining=10,started=10},
 {category='kidney',stage=2,active=false,remaining=.01,started=0,duration=20},
 {category='root',stage=1,active=false,remaining=0,started=0},
 {category='incapacitate',stage=1,estimated=true,remaining=20}} end
local visible=ns.UI.GetRows('player',0)
assert(#visible==1 and visible[1].category=='kidney',
 'only ended categories with a positive reset window can occupy display slots')
assert(visible[1].remaining==.01 and visible[1].duration==20 and visible[1].started==0,
 'display clocks retain application age')
assert(#ns.UI.GetRows('cooldown',0)==2,'interrupts opt-in')
ns.db.targetOnly=true
assert(#ns.UI.GetRows('cooldown',0)==1,'target-only must filter by GUID')
ns.db.disabledSpells[408]=true
assert(#ns.UI.GetRows('cooldown',0)==0,'per-spell disable must hide')
ns.db.interrupts=true
assert(ns.UI.GetRows('cooldown',0)[1].spellID==1766,'enabled interrupts retained')
ns.Observer.GetUnitState=function() return {} end
assert(#ns.UI.GetRows('cooldown',0)==0,'target-only with no identity must show no other enemies')
assert(ns.UI.FormatTime(12.2)=='12' and ns.UI.FormatTime(12.8)=='12',
 'whole seconds truncate like the updated native-style portrait countdown')
assert(ns.UI.FormatTime(9.999)=='9' and ns.UI.FormatTime(10)=='10',
 'whole-second text changes at the integer boundary')
assert(ns.UI.FormatTime(5)=='5' and ns.UI.FormatTime(5.9)=='5' and ns.UI.FormatTime(4.9)=='4.9',
 'decimal precision begins strictly below five seconds')
assert(ns.UI.FormatTime(4.44)=='4.4' and ns.UI.FormatTime(.24)=='0.2',
 'short countdowns display one decimal')
assert(ns.UI.FormatTime(4.96)=='5.0' and ns.UI.FormatTime(.04)=='0.0',
 'decimal text rounds normally without shifting expiry or clamping tenths')
assert(ns.UI.FormatTime(-.2)=='0' and ns.UI.FormatTime(0)=='0',
 'expired countdown text never becomes negative')
assert(ns.UI.FormatTime(125)=='3m','long cooldowns use compact minutes')
ns.demo=true
local demo=ns.UI.GetRows('player',3)
assert(#demo>0,'demo independent of live unit state')
ns.demo=false
assert(#ns.UI.GetRows('player',3)==0,'demo never enters live model')
print('ui: category/ability/target filtering and isolated demo passed')
