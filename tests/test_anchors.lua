local ns = {}
local dir = ADDON_DIR or 'work/bjarkiCC'
assert(loadfile(dir..'/Bootstrap.lua'))('bjarkiCC',ns)
local combat = false
InCombatLockdown = function() return combat end
local function frame(left,bottom,width,height,scale)
    local f={left=left,bottom=bottom,width=width,height=height,scale=scale or 1,visible=true,writes=0}
    function f:GetLeft() return self.left end
    function f:GetRight() return self.left+self.width end
    function f:GetTop() return self.bottom+self.height end
    function f:GetBottom() return self.bottom end
    function f:GetCenter() return self.left+self.width/2,self.bottom+self.height/2 end
    function f:GetEffectiveScale() return self.scale end
    function f:IsVisible() return self.visible end
    function f:ClearAllPoints() assert(not combat); self.writes=self.writes+1 end
    function f:SetPoint(...) assert(not combat); self.point={...}; self.writes=self.writes+1 end
    function f:StartMoving() assert(not combat); self.moving=true end
    function f:StopMovingOrSizing() self.moving=false end
    return f
end
UIParent=frame(0,0,1000,800,.8)
PlayerFrame=frame(100,300,200,80,1)
TargetFrame=frame(400,300,200,80,.8)
FocusFrame=frame(700,300,200,80,.6)
local playerPortrait=frame(105,310,60,60,1)
local targetPortrait=frame(530,310,60,60,.8)
local focusPortrait=frame(830,310,60,60,.6)
PlayerFrame.PlayerFrameContainer={PlayerPortraitMask=playerPortrait}
TargetFrame.TargetFrameContainer={PortraitMask=targetPortrait}
FocusFrame.TargetFrameContainer={PortraitMask=focusPortrait}
ns.db={locked=false,bars={}}
for _,key in ipairs({'player','target','focus','cooldown'}) do
    ns.db.bars[key]={anchorKind='portrait',offsetX=key=='player' and 0 or 10,offsetY=key=='player' and 8 or 0,x=0,y=-100,size=28}
end
assert(loadfile(dir..'/Anchors.lua'))('bjarkiCC',ns)
local A=ns.Anchors
local bars={}
for _,key in ipairs({'player','target','focus','cooldown'}) do
    local bar=frame(200,200,90,28,.8); bar.key=key; bars[key]=bar
    A.Apply(bar)
end
assert(bars.player.point[2]==playerPortrait and bars.target.point[2]==targetPortrait and bars.focus.point[2]==focusPortrait,'each DR bar anchors to its visible portrait, not padded native bounds')
assert(bars.player.point[1]=='BOTTOMLEFT' and bars.player.point[3]=='TOPLEFT' and bars.player.point[4]==0 and bars.player.point[5]==8,'player bar sits immediately above its portrait')
assert(bars.focus.point[1]=='LEFT' and bars.focus.point[3]=='RIGHT' and bars.focus.point[4]==10 and bars.focus.point[5]==0,'target and focus bars center beside their portraits')
assert(bars.cooldown.point[2]==UIParent and bars.cooldown.point[1]=='CENTER','cooldowns stay independently movable')
assert(PlayerFrame.writes==0 and TargetFrame.writes==0 and FocusFrame.writes==0,'native frames never modified')
local bar=bars.player
local writes=bar.writes
A.Apply(bar)
assert(bar.writes==writes,'unchanged anchors are not rewritten each render')
-- Scale-aware offsets: dragged BOTTOMLEFT is (160,160) physical pixels;
-- portrait TOPLEFT is (105,370); divide delta by addon scale .8.
assert(A.StartDrag(bar) and bar.moving,'unlocked bars begin dragging')
A.Apply(bar,true)
assert(bar.writes==writes,'render cannot snap a drag back to its old offset')
A.StopDrag(bar)
assert(not bar.moving and not bar.dragging,'drag ends cleanly')
assert(math.abs(ns.db.bars.player.offsetX-68.75)<.001 and math.abs(ns.db.bars.player.offsetY+262.5)<.001,'offsets converted across effective scales')
assert(bar.point[2]==playerPortrait and bar.point[4]==ns.db.bars.player.offsetX,'drag reattaches instead of becoming screen-absolute')
local ox,oy=ns.db.bars.player.offsetX,ns.db.bars.player.offsetY
A.StopDrag(bar)
assert(ns.db.bars.player.offsetX==ox and ns.db.bars.player.offsetY==oy,'ordinary icon mouse-up does not overwrite position')
ns.db.bars.player.reverse=true
A.Apply(bar)
assert(bar.point[1]=='BOTTOMRIGHT' and bar.point[4]==ox+28,'reverse rows keep the first icon at the same position')
ns.db.bars.player.vertical=true
A.Apply(bar)
assert(bar.point[1]=='BOTTOMLEFT','reverse columns anchor their first icon edge')
ns.db.locked=true
assert(not A.StartDrag(bar),'locked bars do not move')
ns.db.locked=false
combat=true
writes=bar.writes
ns.db.bars.player.offsetX=42
A.Apply(bar,true)
assert(bar.writes==writes and bar.anchorPending,'layout changes wait until combat ends')
assert(not A.StartDrag(bar),'combat cannot begin a drag')
combat=false
A.Apply(bar)
assert(not bar.anchorPending and bar.point[4]==42,'queued offset applies after combat')
assert(A.Visible(bars.focus),'visible native frame permits its DR bar')
FocusFrame.visible=false
assert(not A.Visible(bars.focus),'hidden focus frame hides live DR bar')
local oldFocus=FocusFrame
FocusFrame=nil
A.Apply(bars.focus)
assert(not A.Visible(bars.focus) and bars.focus.point[2]==UIParent,'missing frame provides setup fallback, no floating live DR')
assert(not A.StartDrag(bars.focus),'missing unit frame cannot save a misleading unit offset')
FocusFrame=frame(500,100,200,80,1)
A.Apply(bars.focus)
assert(bars.focus.point[2]==FocusFrame and A.Visible(bars.focus),'late-created or replacement native frame rebinds')
assert(oldFocus.writes==0 and FocusFrame.writes==0,'no hooks or writes to native focus frames')
-- Combat starting mid-drag discards unsaved movement and restores the saved
-- frame-relative anchor once combat ends; it must not become a floating bar.
assert(A.StartDrag(bar))
combat=true
A.StopDrag(bar)
assert(not bar.dragging and bar.anchorPending and ns.db.bars.player.offsetX==42,'combat interruption preserves prior saved offset')
combat=false
A.Apply(bar)
assert(bar.point[2]==playerPortrait and bar.point[4]==42,'interrupted drag recovers its portrait anchor')
-- Reject inaccessible coordinates before doing arithmetic or saving them.
local secret={}
issecretvalue=function(v) return v==secret end
bar.GetLeft=function() return secret end
ns.db.bars.player.reverse=false; ns.db.bars.player.vertical=false
assert(A.StartDrag(bar))
A.StopDrag(bar)
assert(ns.db.bars.player.offsetX==42,'protected geometry does not overwrite offsets')
issecretvalue=nil
-- Global portrait names remain supported by older Classic frame layouts.
TargetFrame.TargetFrameContainer=nil
TargetFramePortrait=targetPortrait
A.Apply(bars.target)
assert(bars.target.point[2]==targetPortrait,'legacy portrait global is a supported fallback')
-- A mask may stay visible under an overlay parent while the unit frame hides.
TargetFrame.visible=false; targetPortrait.visible=true
assert(not A.Visible(bars.target),'native unit frame, not reparented portrait visibility, controls live DR visibility')
TargetFrame.visible=true
-- Existing custom offsets retain their original frame reference without drift.
ns.db.bars.target.anchorKind='frame'
ns.db.bars.target.offsetX,ns.db.bars.target.offsetY=13,-27
A.Apply(bars.target)
assert(bars.target.point[2]==TargetFrame and bars.target.point[1]=='TOPLEFT' and bars.target.point[3]=='TOPRIGHT' and bars.target.point[4]==13 and bars.target.point[5]==-27,'custom legacy placement retains the original coordinate system')
-- Portrait orientation changes keep the first icon fixed beside the aperture.
ns.db.bars.focus.vertical=true; ns.db.bars.focus.reverse=false
FocusFrame.TargetFrameContainer={PortraitMask=focusPortrait}
A.Apply(bars.focus)
assert(bars.focus.point[1]=='TOPLEFT' and bars.focus.point[5]==14,'vertical row starts half an icon above the portrait center')
ns.db.bars.focus.reverse=true
A.Apply(bars.focus)
assert(bars.focus.point[1]=='BOTTOMLEFT' and bars.focus.point[5]==-14,'reversed column retains its first icon center')
-- Replacing an aperture during combat must not leave an old floating live bar.
local replacementPortrait=frame(820,320,60,60,.6)
FocusFrame.TargetFrameContainer.PortraitMask=replacementPortrait
combat=true
A.Apply(bars.focus)
assert(not A.Visible(bars.focus) and bars.focus.anchorPending,'changed portrait waits for safe rebind without showing stale placement')
combat=false
A.Apply(bars.focus)
assert(A.Visible(bars.focus) and bars.focus.point[2]==replacementPortrait,'replacement portrait binds after combat')
assert(playerPortrait.writes==0 and targetPortrait.writes==0 and focusPortrait.writes==0,'portrait regions never modified')
-- Visible health bars provide the new mirrored placement reference.
local playerHealth=frame(170,340,120,18,1)
local targetHealth=frame(410,340,115,18,.8)
local focusHealth=frame(710,340,115,18,.6)
PlayerFrame.PlayerFrameContent={PlayerFrameContentMain={HealthBarsContainer={HealthBar=playerHealth}}}
TargetFrame.TargetFrameContent={TargetFrameContentMain={HealthBarsContainer={HealthBar=targetHealth}}}
FocusFrame.TargetFrameContent={TargetFrameContentMain={HealthBarsContainer={HealthBar=focusHealth}}}
for _,key in ipairs({'player','target','focus'}) do
    local settings=ns.db.bars[key]
    settings.anchorKind='health'; settings.offsetX=key=='player' and 24 or -24; settings.offsetY=24
    settings.vertical=false; settings.reverse=key~='player'
    A.Apply(bars[key])
end
assert(bars.player.point[2]==playerHealth and bars.target.point[2]==targetHealth and bars.focus.point[2]==focusHealth,'rows use the visible health region instead of portrait or padded native bounds')
assert(bars.player.point[1]=='BOTTOMLEFT' and bars.player.point[3]=='TOPLEFT' and bars.player.point[4]==24 and bars.player.point[5]==24,'player begins inset above health left edge, clear of the leader crown')
assert(bars.target.point[1]=='BOTTOMRIGHT' and bars.target.point[3]=='TOPRIGHT' and bars.target.point[4]==-24 and bars.target.point[5]==24,'target begins inset above health right edge')
-- Both horizontal growth directions keep the first icon beside the portrait.
ns.db.bars.target.reverse=false
A.Apply(bars.target)
assert(bars.target.point[1]=='BOTTOMLEFT' and bars.target.point[4]==-52,'reversing target growth keeps the first icon fixed above health right')
ns.db.bars.player.reverse=true
A.Apply(bars.player)
assert(bars.player.point[1]=='BOTTOMRIGHT' and bars.player.point[4]==52,'reversing player growth keeps the first icon fixed above health left')
ns.db.bars.player.reverse=false
ns.db.bars.target.reverse=true
A.Apply(bars.target)
local rowPoint=bars.target.point
bars.target.width=152
A.Apply(bars.target)
assert(bars.target.point==rowPoint,'adding icons changes row length without moving its first anchor')
ns.db.bars.target.vertical=true
A.Apply(bars.target)
assert(bars.target.point[1]=='BOTTOMLEFT' and bars.target.point[4]==-52 and bars.target.point[5]==24,'reversed target column begins at the same first icon')
ns.db.bars.target.reverse=false
A.Apply(bars.target)
assert(bars.target.point[1]=='TOPLEFT' and bars.target.point[4]==-52 and bars.target.point[5]==52,'normal target column begins at the same first icon')
-- The drag position is saved relative to the actual health region across scales.
bar.GetLeft=function(self) return self.left end
bar.left,bar.bottom=250,220
ns.db.bars.player.vertical=false
A.Apply(bar)
assert(A.StartDrag(bar))
A.StopDrag(bar)
assert(math.abs(ns.db.bars.player.offsetX-37.5)<.001 and math.abs(ns.db.bars.player.offsetY+227.5)<.001,'health offsets convert the dragged edge from native scale to addon scale')
assert(bar.point[2]==playerHealth and bar.point[4]==37.5,'drag ends on the health anchor instead of UIParent')
-- Classic globals and frame.healthbar are supported when nested regions differ.
TargetFrame.TargetFrameContent=nil
TargetFrameHealthBar=targetHealth
A.Apply(bars.target)
assert(bars.target.point[2]==targetHealth,'legacy health global remains supported')
TargetFrameHealthBar=nil
TargetFrame.healthbar=targetHealth
A.Apply(bars.target)
assert(bars.target.point[2]==targetHealth,'frame healthbar property remains supported')
TargetFrame.healthbar=nil
ns.db.bars.target.vertical=false; ns.db.bars.target.reverse=true
A.Apply(bars.target)
assert(bars.target.point[2]==targetPortrait and bars.target.point[3]=='TOPLEFT' and bars.target.point[5]==4,'missing health falls back above inward portrait corner with a small gap')
TargetFramePortrait=nil
A.Apply(bars.target)
assert(bars.target.point[2]==TargetFrame and bars.target.point[3]=='TOPRIGHT' and bars.target.point[5]==4,'missing portrait also falls back above the native frame')
-- A new region cannot leave a stale live bar attached to its predecessor.
local replacementHealth=frame(720,350,115,18,.6)
FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar=replacementHealth
combat=true
A.Apply(bars.focus)
assert(bars.focus.anchorPending and not A.Visible(bars.focus),'health replacement during combat hides stale attachment until safe rebind')
combat=false
A.Apply(bars.focus)
assert(bars.focus.point[2]==replacementHealth and A.Visible(bars.focus),'replacement health binds after combat')
FocusFrame.visible=false
assert(not A.Visible(bars.focus),'health visibility never overrides hidden native unit frame')
assert(playerHealth.writes==0 and targetHealth.writes==0 and focusHealth.writes==0 and replacementHealth.writes==0,'health regions are read-only anchor references')
-- New columns use native TOP center anchoring, so growing their height
-- cannot move the first icon away from the portrait.
for _,pair in ipairs({{'player',playerPortrait},{'target',targetPortrait},{'focus',focusPortrait}}) do
 local key,region=pair[1],pair[2]
 if key=='target' then TargetFrame.TargetFrameContainer={PortraitMask=targetPortrait} end
 if key=='focus' then FocusFrame.TargetFrameContainer={PortraitMask=focusPortrait}; FocusFrame.visible=true end
 local settings=ns.db.bars[key]
 settings.anchorKind='portrait-top'; settings.offsetX=0; settings.offsetY=8; settings.vertical=true; settings.reverse=true
 A.Apply(bars[key],true)
 assert(bars[key].point[2]==region and bars[key].point[1]=='BOTTOM' and bars[key].point[3]=='TOP'
  and bars[key].point[4]==0 and bars[key].point[5]==8,'portrait-centered column uses native relative anchoring across scales')
 local point=bars[key].point
 bars[key].height=150; A.Apply(bars[key])
 assert(bars[key].point==point,'adding categories leaves the portrait attachment fixed')
end
-- Center-based dragging still converts native and addon scales correctly.
ns.db.locked=false
bars.focus.left,bars.focus.bottom,bars.focus.width,bars.focus.height=200,200,28,90
assert(A.StartDrag(bars.focus),'centered portrait column remains movable')
A.StopDrag(bars.focus)
assert(math.abs(ns.db.bars.focus.offsetX+431)<.001 and math.abs(ns.db.bars.focus.offsetY+77.5)<.001,
 'dragged bottom-center is saved against portrait top-center across scales')
assert(bars.focus.point[1]=='BOTTOM' and bars.focus.point[2]==focusPortrait,
 'drag restores the portrait-relative column attachment')
-- Side grids attach using only native relative points; the mirrored player
-- placement leaves the space between paired unit frames clear.
for _,pair in ipairs({{'player',playerPortrait},{'target',targetPortrait},{'focus',focusPortrait}}) do
 local key,region=pair[1],pair[2]
 local settings=ns.db.bars[key]
 settings.anchorKind='unit-side'; settings.offsetX=key=='player' and -18 or 18; settings.offsetY=0
 A.Apply(bars[key],true)
 assert(bars[key].point[2]==region and bars[key].point[1]==(key=='player' and 'TOPRIGHT' or 'TOPLEFT')
  and bars[key].point[3]==(key=='player' and 'TOPLEFT' or 'TOPRIGHT')
  and bars[key].point[4]==settings.offsetX and bars[key].point[5]==0,'DR grid sits beside its native frame at every scale')
end
bars.focus.left,bars.focus.bottom,bars.focus.width,bars.focus.height=200,200,59,59
assert(A.StartDrag(bars.focus),'side grid remains movable')
A.StopDrag(bars.focus)
assert(math.abs(ns.db.bars.focus.offsetX+467.5)<.001 and math.abs(ns.db.bars.focus.offsetY+18.5)<.001,
 'side-grid top corner saves its offset against the portrait edge across scales')
assert(bars.focus.point[1]=='TOPLEFT' and bars.focus.point[2]==focusPortrait,
 'drag restores the side-grid native anchor')
print('anchors: health and portrait geometry, legacy placement, scaling, dragging, visibility, missing frames and combat deferral passed')
