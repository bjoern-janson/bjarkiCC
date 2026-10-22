local T = dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local results = {}
local function save(name, ns, guid, key, extra)
 local actor=ns.model.units[guid]
 local s=actor.categories.stun
 local e=actor.effects[key]
 local rows=ns.model:GetDR(guid,extra and extra.at or actor.seen,false)
 local r={name=name,stage=s.stage,appliedAt=s.appliedAt,stageEndAt=s.stageEndAt,
  stageResetAt=s.stageResetAt,stageResetPending=s.stageResetPending,activeCount=s.activeCount,
  witnessExpires=s.witness and s.witness.expires,effectExpires=e and e.expires,
  effectStart=e and e.appliedAt,effectSource=e and e.applicationSource,
  active=rows[1] and rows[1].active,remaining=rows[1] and rows[1].remaining,
  key=s.applicationKey}
 for k,v in pairs(extra or {}) do r[k]=v end
 results[#results+1]=r
end
local G='Player-Enemy'
local function direct()
 local e,ns=T.fresh()
 local function put(start,expiry,now,source,key,complete)
  ns.model:Observe(G,{[key or 'a:1']={category='stun',spellID=5211,appliedAt=start,
    expires=expiry,applicationSource=source or 'loc'}},now,complete~=false)
 end
 return e,ns,put
end
do
 local _,ns,put=direct()
 put(10,10.3,10.1)
 put(10.4,nil,10.5)
 save('direct-refresh-without-expiry',ns,G,'a:1',{at=10.5,expectedPending=true,expectedActive=true})
end
do
 local e,ns=T.fresh()
 e.identity.target=G; e.auras.target={secretAt=1}
 e.byloc.target={T.loc(5211,1,10,.3)}
 ns.Observer.Scan(10.1)
 e.byloc.target={T.loc(5211,1,10.4,nil)}
 ns.Observer.Scan(10.5)
 save('observer-refresh-without-expiry',ns,G,'a:1',{at=10.5,expectedPending=true,expectedActive=true})
end
do
 local _,ns,put=direct()
 put(10,nil,10.1)
 put(10,20,10.3,'aura')
 save('direct-weaker-aura-fills-missing-loc-expiry',ns,G,'a:1',
  {classification='exploratory-not-a-confirmed-bug',reason='No accepted expiry existed; end authority rule is not established.'})
end
do
 local e,ns=T.fresh()
 e.identity.target=G; e.auras.target={secretAt=1}
 e.byloc.target={T.loc(5211,1,10,nil)}
 ns.Observer.Scan(10.1)
 e.byloc.target={};e.auras.target={T.aura(5211,1,10,10),secretAt=2}
 ns.Observer.Scan(10.3)
 save('observer-weaker-aura-fills-missing-loc-expiry',ns,G,'a:1',
  {classification='exploratory-not-a-confirmed-bug',reason='No accepted expiry existed; end authority rule is not established.'})
end
do
 for _,token in ipairs({'target','focus','player'}) do
  for _,expiry in ipairs({11,20}) do
   local e,ns=T.fresh()
   local guid=token=='player' and 'Player-Self' or G
   e.identity[token]=guid;e.auras[token]={secretAt=1}
   local function loc(rows)
    if token=='player' then e.loc=rows else e.byloc[token]=rows end
   end
   loc({T.loc(5211,1,10,3)})
   ns.Observer.Scan(10.1)
   e.auras[token]={T.aura(5211,1,10,expiry-10),secretAt=2}
   loc({T.loc(5211,1,10,nil)})
   ns.Observer.Scan(10.3)
   local label='authority/'..token..'/aura-expiry-'..expiry
   save(label,ns,guid,'a:1',{at=10.3,expectedExpiry=13,weakAuraExpiry=expiry,
    expectedStage=1,expectedReset=31})
   -- Keep scans at 0.2s cadence, but allow no fabricated removal from an
   -- unreadable interval. End with an actual complete empty aura snapshot.
   e.auras[token]={secretAt=1};loc({secret=true})
   local absentAt=expiry==11 and 14.1 or 20.1
   local i=1
   while 10.3+i*.2 < absentAt-.001 do ns.Observer.Scan(10.3+i*.2);i=i+1 end
   e.auras[token]={};loc({})
   ns.Observer.Scan(absentAt)
   local nextStart=expiry==11 and 30 or 33
   i=1
   while absentAt+i*.2 < nextStart do ns.Observer.Scan(absentAt+i*.2);i=i+1 end
   e.auras[token]={secretAt=1};loc({T.loc(5211,2,nextStart,2)})
   ns.Observer.Scan(nextStart+.1)
   save(label..'/next-application',ns,guid,'a:2',{at=nextStart+.1,
    expectedStage=expiry==11 and 2 or 1,scanGaps=ns.Observer.stats.scanGaps})
  end
 end
end
do
 local e,ns=T.fresh()
 e.auras.player={secretAt=1}
 e.loc={T.loc(5211,1,10,nil)}
 e.byloc.player={T.loc(5211,nil,10,10)}
 ns.Observer.Scan(10.1)
 save('observer-two-loc-aliases-richer-fallback',ns,'Player-Self','a:1',{expectedExpiry=20})
end
do
 local e,ns=T.fresh()
 e.auras.player={secretAt=1}
 e.loc={T.loc(5211,1,10,3)}
 e.byloc.player={T.loc(5211,nil,10,3)}
 ns.Observer.Scan(10.1)
 e.loc={T.loc(5211,1,10,nil)}
 e.byloc.player={T.loc(5211,nil,10,6)}
 ns.Observer.Scan(10.3)
 save('observer-two-loc-aliases-corrected-fallback',ns,'Player-Self','a:1',{expectedExpiry=16})
 e.auras.player={secretAt=1};e.loc={secret=true};e.byloc.player={secret=true}
 for i=1,33 do ns.Observer.Scan(10.3+i*.2) end
 e.auras.player={};e.loc={};e.byloc.player={}
 ns.Observer.Scan(17.1)
 for i=1,74 do ns.Observer.Scan(17.1+i*.2) end
 e.auras.player={secretAt=1};e.loc={T.loc(5211,2,32,2)}
 ns.Observer.Scan(32.1)
 save('observer-two-loc-aliases-corrected-fallback/next-application',ns,'Player-Self','a:2',
  {at=32.1,expectedStage=2,scanGaps=ns.Observer.stats.scanGaps})
end
do
 local _,ns,put=direct()
 put(10,20,10.1)
 put(10,14,10.3)
 save('direct-shortening-control',ns,G,'a:1',{expectedExpiry=14})
 put(10,23,10.5)
 save('direct-extension-control',ns,G,'a:1',{expectedExpiry=23})
 put(9,30,10.7)
 save('direct-stale-start-control',ns,G,'a:1',{expectedExpiry=23})
 put(10,31,10.9,'aura')
 save('direct-weaker-aura-control',ns,G,'a:1',{expectedExpiry=23})
 put(11,13,11.1)
 put(10,40,11.3)
 save('direct-refresh-stale-start-control',ns,G,'a:1',{expectedExpiry=13,expectedStage=2})
end
return results
