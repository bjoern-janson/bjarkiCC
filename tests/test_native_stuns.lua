-- Native aura-slot construction is simulated. This DOES NOT prove WoW
-- exposes otherwise-secret hostile stun auras on the live client.
local ns={db={nativeStunWitness=false},Safe={},UI={bars={
    target={key="target"},focus={key="focus"},
}}}
function ns.Safe.Boolean(v) if type(v)=="boolean" then return v end end
function ns.Safe.String(v) if type(v)=="string" then return v end end
function ns.Safe.Call(fn,...) if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...); if ok then return value end end

local combat=false
InCombatLockdown=function() return combat end
AuraContainerSortMethod={AuraInstanceIDOnly=7}
AuraContainerSortDirection={Reverse=3}
local created, auraContainers={},{}
local frameMethods={}
function frameMethods:SetSize(w,h) self.w,self.h=w,h end
function frameMethods:SetPoint(...) self.point={...} end
function frameMethods:SetFrameStrata(strata) self.strata=strata end
function frameMethods:SetAllPoints(relative) self.allPoints=relative end
function frameMethods:SetUnit(unit) self.unit=unit end
function frameMethods:SetEnabled(enabled) self.enabled=enabled; self.enabledWrites=(self.enabledWrites or 0)+1 end
function frameMethods:SetShown(shown) self.shown=shown end
function frameMethods:Show() self.shown=true end
function frameMethods:Hide() self.shown=false end
function frameMethods:SetTexCoord(...) self.texcoord={...} end
function frameMethods:SetIcon(icon) self.icon=icon end
function frameMethods:SetDurationCooldown(cd) self.cd=cd end
function frameMethods:CreateTexture() return setmetatable({kind="Texture",parent=self},{__index=frameMethods}) end
function frameMethods:CreateFontString() return setmetatable({kind="FontString",parent=self},{__index=frameMethods}) end
function frameMethods:SetText(text) self.text=text end
function frameMethods:SetTextColor(...) self.textColor={...} end
function frameMethods:EnableMouse(v) self.mouse=v end
function frameMethods:SetReverse(v) self.reverse=v end
function frameMethods:SetDrawBling(v) self.bling=v end
function frameMethods:SetDrawEdge(v) self.edge=v end
function frameMethods:SetHideCountdownNumbers(v) self.hideNumbers=v end
function frameMethods:SetCountdownMillisecondsThreshold(v) self.threshold=v end
function frameMethods:UpdateAllAuras() self.refreshes=(self.refreshes or 0)+1 end
function frameMethods:AddAuraSlot(key,filter,opts)
    self.auraOptions=opts
    self.auraFilter=filter
    self.auraSlotName=key
    -- WoW creates a batch in advance, regardless of whether an aura exists.
    -- Visible-state checks on its buttons are deliberately inaccessible.
    local button=setmetatable({kind="NativeAuraButton",parent=self},{
        __index=function(t,k)
            if k=="IsShown" or k=="IsVisible" then error("secure visibility forbidden") end
            return frameMethods[k]
        end
    })
    opts.initializeFrame(button)
    self.nativeButton=button
    return button
end
CreateFrame=function(kind,name,parent,template)
    local obj=setmetatable({kind=kind,parent=parent,template=template},
        {__index=frameMethods})
    created[#created+1]=obj
    if kind=="AuraContainer" then auraContainers[#auraContainers+1]=obj end
    return obj
end
UIParent={}
ns.model={Observe=function() error("native witness must never feed DR history") end,
    EstimateDR=function() error("native witness cannot create estimate") end}
local path=(ADDON_DIR or "work/bjarkiCC").."/NativeStuns.lua"
assert(loadfile(path))("bjarkiCC",ns)
local native=ns.NativeStuns
native.Init()
assert(native.initialized,"native witness constructs outside combat")
assert(#auraContainers==2,"one container per target/focus")
assert(#created<=12,"witness creates a bounded number of frames")
for i,unit in ipairs({"target","focus"}) do
    local container=auraContainers[i]
    assert(container.unit==unit)
    assert(container.auraSlotName=="SharedStun" and container.auraFilter=="HARMFUL|INCLUDE_NAME_PLATE_ONLY")
    assert(container.auraOptions.sortMethod==7 and container.auraOptions.sortDirection==3)
    local ids=container.auraOptions.candidateFilters.includeSpellIDs
    assert(ids[5211] and ids[6798] and ids[8983] and ids[20549] and ids[4068],
        "exact known Bash/Stomp/Grenade auras only")
    assert(not ids[2637] and not ids[118] and not ids[5782],
        "unrelated forms, incapacitate or fear must not appear as stun evidence")
    assert(container.enabled==false and container.shown==false)
    local button=container.nativeButton
    assert(button.icon and button.cd and button.cd.threshold==5)
    assert(button.cd.hideNumbers==false)
    local label=button.icon and button.cd and button.parent.nativeButton
    assert(label==button,"native button owns aura chrome")
end
assert(native.Status():find("OFF",1,true),"feature defaults disabled")
assert(not ns.db.nativeStunWitness,"building native containers cannot opt in")
ns.db.nativeStunWitness=true
local ok,message=native.Refresh()
assert(ok and message=="ready")
assert(native.Status():find("ON",1,true))
assert(auraContainers[1].enabled and auraContainers[2].enabled)
assert(auraContainers[1].shown and auraContainers[2].shown)
native.Refresh(true)
assert(auraContainers[1].refreshes==1 and auraContainers[2].refreshes==1,
    "explicit same-token rebind asks the native engine to refresh once")
local before=auraContainers[1].enabledWrites
combat=true
ns.db.nativeStunWitness=false
local wasApplied,why=native.Refresh()
assert(not wasApplied and why:find("deferred"),"combat cannot structurally disable secure containers")
assert(auraContainers[1].enabledWrites==before and native.pending)
combat=false
assert(native.Refresh(true) and not auraContainers[1].enabled and not native.pending)
assert(native.Status():find("OFF",1,true))

-- Graceful failure with client API absent, no addon fatal load error.
local ns2={Safe=ns.Safe,db={nativeStunWitness=true},UI=ns.UI}
AuraContainerSortMethod=nil
assert(loadfile(path))("bjarkiCC",ns2)
ns2.NativeStuns.Init()
assert(ns2.NativeStuns.initialized)
assert(ns2.NativeStuns.Status():find("native aura sorting unavailable",1,true))
print("native-stuns: isolated, exact-filtered native visuals never assert a DR hit")
