local root = assert(ADDON_DIR)
local function fresh()
 local ns = {}
 local env = {identity={player='Player-Self'}, auras={}, exact={}, loc={}, byloc={}, calls={index=0, exact=0, loc=0, byloc=0}}
 local secret={}
 _G.issecretvalue=function(x)return x==secret end
 _G.issecrettable=function(x)return x==secret end
 _G.canaccessvalue=function(x)return x~=secret end
 _G.UnitGUID=function(u)return env.identity[u] end
 _G.UnitIsPlayer=function(u)return env.identity[u]~=nil end
 _G.UnitCanAttack=function(p,u)return u~='player' and env.identity[u]~=nil end
 _G.UnitName=function(u)return u end
 _G.C_Secrets=nil
 _G.C_UnitAuras={GetAuraDataByIndex=function(u,i)
  env.calls.index=env.calls.index+1
  local a=env.auras[u] or {}
  if a.secretAt and i>=a.secretAt then return secret end
  return a[i]
 end,GetUnitAuraBySpellID=function(u,id)
  env.calls.exact=env.calls.exact+1
  return (env.exact[u] or {})[id]
 end}
 _G.C_LossOfControl={GetActiveLossOfControlDataCount=function()
  env.calls.loc=env.calls.loc+1
  return env.loc.secret and secret or #env.loc
 end,GetActiveLossOfControlData=function(i)return env.loc[i] end,
 GetActiveLossOfControlDataCountByUnit=function(u)
  env.calls.byloc=env.calls.byloc+1
  local list=env.byloc[u] or {};return list.secret and secret or #list
 end,GetActiveLossOfControlDataByUnit=function(u,i)return (env.byloc[u] or {})[i] end}
 assert(loadfile(root..'/Bootstrap.lua'))('test',ns)
 assert(loadfile(root..'/Data.lua'))('test',ns)
 assert(loadfile(root..'/Model.lua'))('test',ns)
 assert(loadfile(root..'/Observer.lua'))('test',ns)
 ns.model=ns.Model.New(20,18)
 ns.Observer.Init()
 env.ns=ns
 return env,ns
end
local function aura(id,instance,start,duration)
 return {spellId=id,auraInstanceID=instance,expirationTime=start and start+duration or nil,duration=duration,isHarmful=true}
end
local function loc(id,instance,start,duration)
 return {spellID=id,auraInstanceID=instance,startTime=start,duration=duration}
end
local function count(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
return {fresh=fresh,aura=aura,loc=loc,count=count}
