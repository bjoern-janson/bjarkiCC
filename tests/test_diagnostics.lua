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
assert(report:find('DR stage reset: 18s after CC ends',1,true),
 'status distinguishes retained stage history from the application countdown')
assert(report:find('DR timer: 20s from last observed application',1,true), 'status names the independent display countdown')
assert(ns.model.resetSeconds == 20 and ns.model.stageResetSeconds == 18, 'Main passes both configured clocks into the model')
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
assert(ns.BuildStatus():find('reportedDuration=unknown',1,true), 'remaining-time expiry is not logged as a reported duration')
C_LossOfControl.GetActiveLossOfControlData=function()
 return {spellID=2637,auraInstanceID=999,startTime=204,duration=20,timeRemaining=18}
end
now=205; frame.scripts.OnEvent(frame,'LOSS_OF_CONTROL_UPDATE')
assert(#ns.drTrace==beforePolls+1 and ns.BuildStatus():find('reportedDuration=20.000',1,true),
 'new explicit reported duration is a diagnostic transition even with unchanged identity/start')
now=205.2; frame.scripts.OnEvent(frame,'LOSS_OF_CONTROL_UPDATE')
assert(#ns.drTrace==beforePolls+1,'stable reported duration does not fill diagnostic history')
-- Feed normalized observations to the real model so status distinguishes an
-- absent baseline, a pending sequence, and evidence learned on its third CC.
SlashCmdList.BJARKICC('clear')
now=1000; aura=nil
C_UnitAuras={GetAuraDataByIndex=function() end}
C_LossOfControl={GetActiveLossOfControlDataCount=function() return 0 end}
frame.scripts.OnEvent(frame,'UNIT_AURA','player')
local function observeDuration(at,key,duration)
 now=at
 local effects=key and {[key]={category='incapacitate',spellID=2637,
  appliedAt=at,expires=at+duration,applicationSource='loc',reportedDuration=duration}} or {}
 ns.model:Observe('Player-1-TRACE',effects,at,true)
 ns.RecordDRObservation('Player-1-TRACE',effects,at,true,'loc')
end
observeDuration(1001,'a:1001',20)
assert(ns.BuildStatus():find('Full-duration baseline: not learned; sequence 1/3.',1,true),
 'status must distinguish missing baseline from a correction failure')
observeDuration(1002)
observeDuration(1004,'a:1004',10)
assert(ns.BuildStatus():find('Full-duration baseline: not learned; sequence 2/3.',1,true),
 'two samples cannot be presented as a learned full duration')
observeDuration(1006)
observeDuration(1008,'a:1008',5)
local learnedReport=ns.BuildStatus()
assert(learnedReport:find('Full-duration baseline: 20.000s (observed-halving-chain).',1,true),
 'status exposes learned duration and its actual evidence source')
assert(learnedReport:find('fullBaseline=20.000 baselineSource=observed-halving-chain',1,true),
 'recent trace must retain baseline acquisition before any later correction')
local learnedTraceCount=#ns.drTrace
now=1008.2
ns.RecordDRObservation('Player-1-TRACE',{['a:1008']={category='incapacitate',spellID=2637,
 appliedAt=1008,expires=1013,applicationSource='loc',reportedDuration=5}},now,true,'loc')
assert(#ns.drTrace==learnedTraceCount,'unchanged baseline evidence must not create polling noise')
-- Exercise diagnostics through real protected API failure handling. Failed
-- observations must not become hit evidence, and /clear must reset the report.
SlashCmdList.BJARKICC('clear')
C_UnitAuras.GetAuraDataByIndex=function() error('Access denied |test\nmessage',0) end
now=1100; frame.scripts.OnEvent(frame,'UNIT_AURA','player')
local failedReport=ns.BuildStatus()
assert(failedReport:find('API failures (guarded details):',1,true),
 'a cumulative error count must identify the failing operation')
assert(failedReport:find('GetAuraDataByIndex',1,true)
 and failedReport:find('Access denied ?test?message',1,true),
 'the report identifies the API and sanitizes readable error text')
assert(failedReport:find('War Stomp DR: confirmed applications only; no cast estimate.',1,true),
 'status makes the confirmed-hit requirement explicit')
assert(#ns.model:GetDR('Player-1-TRACE',now)==0,'API failures cannot synthesize a hit')
SlashCmdList.BJARKICC('clear')
C_UnitAuras.GetAuraDataByIndex=function() error({},0) end
now=1101; frame.scripts.OnEvent(frame,'UNIT_AURA','player')
assert(ns.BuildStatus():find('[message unavailable]',1,true),
 'non-string errors remain reportable without formatting their payload')
C_UnitAuras.GetAuraDataByIndex=function() end
SlashCmdList.BJARKICC('clear')
assert(not ns.BuildStatus():find('API failures (guarded details):',1,true),
 'clearing tracking removes stale error details')
-- Retain the two-second offensive probe in history after it ends, so no /run
-- macro or perfectly timed status capture is required to see its outcome.
UnitGUID=function(unit) if unit=='focus' then return 'Player-1-Enemy' end end
UnitIsPlayer=function() return true end
C_UnitAuras={GetAuraDataByIndex=function() error('restricted enumeration',0) end,
 GetUnitAuraBySpellID=function() return {spellId=20549,auraInstanceID=1300,expirationTime=1202,duration=2} end}
C_LossOfControl={GetActiveLossOfControlDataCountByUnit=function() return 0 end,
 GetActiveLossOfControlDataByUnit=function() end}
now=1200; frame.scripts.OnEvent(frame,'UNIT_AURA','focus')
assert(ns.BuildStatus():find('lookup20549=confirmed; ByUnit=complete; records=0',1,true),
 'trace must retain exact positive and empty ByUnit evidence together')
local probeCount=#ns.drTrace
now=1200.2; frame.scripts.OnEvent(frame,'UNIT_AURA','focus')
assert(#ns.drTrace==probeCount,'stable probe outcomes cannot fill the trace')
C_UnitAuras.GetAuraDataByIndex=function() end
C_UnitAuras.GetUnitAuraBySpellID=function() return nil end
now=1203; frame.scripts.OnEvent(frame,'UNIT_AURA','focus')
assert(ns.BuildStatus():find('lookup20549=confirmed; ByUnit=complete; records=0',1,true),
 'completed stun probe remains available after the latest scan becomes empty')
SlashCmdList.BJARKICC('clear')
assert(not ns.BuildStatus():find('lookup20549=',1,true),'clear resets the probe history')
print('diagnostics: real observation transitions, deduplication, bounded history and reset passed')
