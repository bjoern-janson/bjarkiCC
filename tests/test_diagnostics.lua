-- Real event/observer/model flow; only the game UI boundary is stubbed.
local ns, frame = {}, {scripts={}}
function frame:SetScript(event,fn) self.scripts[event]=fn end
function frame:RegisterEvent() end
CreateFrame=function() return frame end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
local now, aura = 100, nil
GetTime=function() return now end
GetBuildInfo=function() return '1.60.1','70425','',16001 end
UnitGUID=function(unit) if unit=='player' then return 'Player-1-TRACE' end end
UnitIsPlayer=function(unit) return unit=='player' end
UnitName=function(unit) if unit=='player' then return 'Tester' end end
issecretvalue=function() return false end
canaccessvalue=function() return true end
C_UnitAuras={GetAuraDataByIndex=function(unit,index) if unit=='player' and index==1 then return aura end end}
ns.UI={bars={},Init=function() end,Update=function() end}
local dir=ADDON_DIR or 'work/bjarkiCC'
for _,name in ipairs({'Bootstrap','Data','Model','Observer','OwnCasts','Main'}) do
 assert(loadfile(dir..'/'..name..'.lua'))('bjarkiCC',ns)
end
frame.scripts.OnEvent(frame,'ADDON_LOADED','bjarkiCC')
assert(type(ns.drTrace)=='table','recent observation history must initialize with the addon')
local initial=#ns.drTrace
now=101
aura={spellId=2637,auraInstanceID=10,expirationTime=121,duration=20}
frame.scripts.OnEvent(frame,'UNIT_AURA','player')
local report=ns.BuildStatus()
assert(report:find('DR stage reset: 20s after CC ends',1,true),
 'status distinguishes retained stage history from the application countdown')
assert(report:find('Recent DR observations',1,true),'status includes recent transition evidence')
assert(report:find('a:10 spell=2637 start=101.000 end=121.000',1,true),'trace preserves the actual guarded witness identity and application timing')
assert(report:find('incapacitate observed=1 shown=1 start=101.000',1,true),'trace records counted stage next to input evidence')
assert(#ns.drTrace==initial+1,'one new witness produces one trace entry')
now=101.2; frame.scripts.OnEvent(frame,'UNIT_AURA','player')
assert(#ns.drTrace==initial+1,'unchanged polls must not fill the history')
aura=nil; now=102; frame.scripts.OnEvent(frame,'UNIT_AURA','player')
assert(#ns.drTrace==initial+2,'removal must remain distinguishable from new applications')
assert(ns.BuildStatus():find('effects=none',1,true),'empty source evidence is explicit')
-- The log stays finite, and status only includes the newest entries.
for i=1,100 do
 now=102+i
 aura={spellId=2637,auraInstanceID=100+i,expirationTime=now+10,duration=10}
 frame.scripts.OnEvent(frame,'UNIT_AURA','player')
end
assert(#ns.drTrace==48,'diagnostic history is bounded independently of polling time')
local traceLines=0
for line in ns.BuildStatus():gmatch('[^\n]+') do if line:find('  t=',1,true)==1 then traceLines=traceLines+1 end end
assert(traceLines==24,'copyable status retains enough changes to include the earlier full-duration application')
SlashCmdList.BJARKICC('clear')
assert(#ns.drTrace==0,'clear resets diagnostic history alongside tracking')
local secret=setmetatable({}, {__tostring=function() error('protected payload was formatted') end})
issecretvalue=function(value) return rawequal(value,secret) end
canaccessvalue=function(value) return not rawequal(value,secret) end
aura={spellId=secret,auraInstanceID=secret,expirationTime=secret,duration=secret}
now=203; frame.scripts.OnEvent(frame,'UNIT_AURA','player')
assert(ns.BuildStatus():find('effects=none',1,true),'secret aura fields never enter the observation log')
C_UnitAuras=nil
C_LossOfControl={GetActiveLossOfControlDataCount=function() return 1 end,
 GetActiveLossOfControlData=function() return {spellID=2637,auraInstanceID=999,startTime=204,timeRemaining=20} end}
now=204; frame.scripts.OnEvent(frame,'LOSS_OF_CONTROL_ADDED')
local beforePolls=#ns.drTrace
for _,time in ipairs({204.2,204.4,204.6,204.8}) do
 now=time; frame.scripts.OnEvent(frame,'LOSS_OF_CONTROL_UPDATE')
end
assert(#ns.drTrace==beforePolls,'coarse remaining-time updates cannot evict useful transitions with derived-expiry noise')
print('diagnostics: real observation transitions, deduplication, bounded history and reset passed')
