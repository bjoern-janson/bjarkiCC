local _, ns = ...
local UI = { bars={} }
ns.UI = UI
local gold = {1, .81, .36}
local titles = {player='Player DR',target='Target DR',focus='Focus DR',cooldown='Enemy cooldowns'}
local order = {'player','target','focus','cooldown'}
local stageColors = {{.25,1,.3},{1,.8,.15},{1,.2,.15}}

function UI.FormatTime(seconds)
    if seconds >= 60 then return math.ceil(seconds/60)..'m' end
    if seconds <= 0 then return '0' end
    -- Enemy cooldown estimates retain their existing countdown formatting.
    if seconds < 5 then return string.format('%.1f', seconds) end
    return tostring(math.floor(seconds))
end

function UI.FormatDRTime(seconds)
    if seconds <= 0 then return '0' end
    -- The DR timer still becomes visible at 5s, but only uses decimals below 3s.
    if seconds < 3 then return string.format('%.1f', seconds) end
    return tostring(math.floor(seconds))
end

local function demoRows(key, now)
    local remaining = 20 - (now % 20)
    if key == 'cooldown' then
        return {
            {spellID=853,category='stun',started=now-12,duration=60,remaining=48,earlyRemaining=33},
            {spellID=408,category='kidney',started=now-6,duration=20,remaining=14,earlyRemaining=14},
            {spellID=122,category='root',started=now-15,duration=25,remaining=10,earlyRemaining=6},
        }
    end
    return {
        {spellID=853,category='stun',stage=1,remaining=remaining,started=now+remaining-20,duration=20},
        {spellID=408,category='kidney',stage=2,remaining=remaining,started=now+remaining-20,duration=20},
        {spellID=5782,category='fear',stage=3,remaining=remaining,started=now+remaining-20,duration=20},
        {spellID=122,category='root',stage=1,remaining=remaining,started=now+remaining-20,duration=20},
    }
end

function UI.GetRows(key, now)
    if ns.demo then return demoRows(key, now) end
    if not ns.model or not ns.Observer then return {} end
    local out, rows = {}, {}
    if key == 'cooldown' then
        local target = ns.Observer.GetUnitState('target')
        if ns.db.targetOnly and not target.guid then return out end
        rows = ns.model:GetCooldowns(now, ns.db.targetOnly and target.guid or nil)
        for _, row in ipairs(rows) do
            if not ns.db.disabledSpells[row.spellID] and (not row.interrupt or ns.db.interrupts) then
                out[#out+1] = row
            end
        end
    else
        local state = ns.Observer.GetUnitState(key)
        if not state.guid then return out end
        rows = ns.model:GetDR(state.guid, now, ns.db.ownCastEstimates, ns.db.aoeCastEstimates)
        for _, row in ipairs(rows) do
            -- Retained stage history belongs to the model; expired application
            -- countdowns must not occupy icon slots or inflate the overflow.
            if row.remaining > 0 and ns.db.categories[row.category] ~= false then out[#out+1] = row end
        end
    end
    return out
end

local function font(parent, template, size)
    local text = parent:CreateFontString(nil, 'OVERLAY', template or 'GameFontNormal')
    if size then text:SetFont(STANDARD_TEXT_FONT, size, 'OUTLINE') end
    return text
end

local function backdrop(frame, alpha)
    frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    frame:SetBackdropColor(.045,.04,.035, alpha or .95)
    frame:SetBackdropBorderColor(.48,.38,.18,1)
end

-- Anchoring to native unit frames can make dimensions secret during CC. These
-- textures stretch natively; unlike BackdropTemplate they never divide a
-- GetWidth/GetHeight result in an OnSizeChanged callback.
local function setBorderColor(frame,r,g,b,a)
    local opacity = a or 1
    if frame._borderR == r and frame._borderG == g and frame._borderB == b
        and frame._borderA == opacity then return end
    for _,edge in ipairs(frame.borderTextures) do edge:SetVertexColor(r,g,b,opacity) end
    frame._borderR, frame._borderG, frame._borderB, frame._borderA = r,g,b,opacity
end

-- The native Cooldown widget advances its own swipe. Reasserting an unchanged
-- start and duration every render tick is unnecessary and may reset its artwork.
local function updateNativeClock(icon, started, duration)
    if icon._clockStart ~= started or icon._clockDuration ~= duration then
        icon.swipe:SetCooldown(started, duration)
        icon._clockStart, icon._clockDuration = started, duration
    end
end

local function setTextIfChanged(region, value)
    if region._displayText ~= value then
        region:SetText(value)
        region._displayText = value
    end
end

local function panelBackground(frame,alpha)
    frame.panelBackground=frame:CreateTexture(nil,'BACKGROUND')
    frame.panelBackground:SetAllPoints(frame)
    frame.panelBackground:SetColorTexture(.045,.04,.035,alpha or 1)
end

local function solidPanel(frame,alpha,borderParent)
    panelBackground(frame,alpha)
    frame.borderTextures={}
    for i=1,4 do
        local edge=(borderParent or frame):CreateTexture(nil,'OVERLAY')
        edge:SetColorTexture(1,1,1,1)
        frame.borderTextures[i]=edge
    end
    local top,bottom,left,right=unpack(frame.borderTextures)
    top:SetPoint('TOPLEFT',frame,'TOPLEFT',0,0); top:SetPoint('TOPRIGHT',frame,'TOPRIGHT',0,0); top:SetHeight(1)
    bottom:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',0,0); bottom:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',0,0); bottom:SetHeight(1)
    left:SetPoint('TOPLEFT',frame,'TOPLEFT',0,0); left:SetPoint('BOTTOMLEFT',frame,'BOTTOMLEFT',0,0); left:SetWidth(1)
    right:SetPoint('TOPRIGHT',frame,'TOPRIGHT',0,0); right:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',0,0); right:SetWidth(1)
    setBorderColor(frame,.48,.38,.18,1)
end

local function showPanel(frame,shown)
    frame.panelBackground:SetShown(shown)
    for _,edge in ipairs(frame.borderTextures) do edge:SetShown(shown) end
end

local function tooltip(owner, row, key)
    if not UI.tip then UI.tip = CreateFrame('GameTooltip','bjarkiCCTooltip',UIParent,'GameTooltipTemplate') end
    local tip, cat = UI.tip, ns.Data.categoryByKey[row.category]
    tip:SetOwner(owner, 'ANCHOR_RIGHT')
    local ability = ns.Data.spells[row.spellID]
    tip:SetText(ability and ability.name or (cat and cat.name or 'Crowd control'), gold[1],gold[2],gold[3])
    if key == 'cooldown' then
        if ns.demo then
            tip:AddLine('SAMPLE ONLY: no enemy cast was observed.',1,.58,.34,true)
        elseif row.anonymous then
            tip:AddLine('CC landed on you. CASTER UNKNOWN; this does not identify the attacker.',1,.68,.31,true)
            tip:AddLine('Cooldown start approximates the landed effect, not a confirmed cast time.',.75,.75,.75,true)
        elseif row.evidenceSource == 'helpful-aura' then
            tip:AddLine('Readable self-only helpful aura; cooldown is an inference.',1,.78,.42,true)
            if row.timingEstimated then
                tip:AddLine('Aura start was not readable: timer begins at first sighting.',1,.62,.31,true)
            end
        else
            tip:AddLine(row.manual and 'Manually marked use' or 'Readable successful cast event',.7,.7,.7)
        end
        tip:AddLine('Estimated remaining: '..math.ceil(row.remaining)..'s',1,.85,.4)
        if row.earlyRemaining and row.earlyRemaining < row.remaining then
            tip:AddLine('May be ready in '..math.ceil(row.earlyRemaining)..'s with talents.',1,.65,.25,true)
        end
        if not ns.demo and row.claimID then
            tip:AddLine('Claim #'..row.claimID..' | '..(row.claimBasis or 'estimated'),.68,.82,.94,true)
            if (row.claimRevisionCount or 0)>0 then
                tip:AddLine('Revised from newer evidence. /bcc why '..row.spellID,.65,.86,.65,true)
            else
                tip:AddLine('Reasoning: /bcc why '..row.spellID,.62,.70,.75,true)
            end
        end
        tip:AddLine('Talents and unseen resets can change this timer.',.7,.7,.7,true)
        if not ns.demo then
            tip:AddLine('Automatic enemy cast events may be unavailable on Forever.',1,.65,.35,true)
        end
    else
        tip:AddLine('Next duration: '..(row.uncertain and 'unknown' or ({'50%','25%','immune'})[row.stage]),1,1,1)
        if row.uncertain then
            tip:AddLine(row.resetEvidence=='matching-full-duration'
                and ('Border shows stage '..row.stage..' after a full-duration match; reset remains inferred.')
                or (row.estimated or row.stageEstimated)
                and ('Border shows estimated stage '..row.stage..'; actual DR is unknown.')
                or ('Border shows observed stage '..row.stage..'; earlier CC may be missing.'),1,.55,.25,true)
        end
        if row.resetEvidence=='matching-full-duration' then
            tip:AddLine('Full-duration match: '..row.resetBaselineDuration..'s for this player and spell. Earlier stage history was corrected.',1,.55,.25,true)
            if row.resetBaselineSource=='observed-halving-chain' then
                tip:AddLine('Baseline learned from three consecutive full/half/quarter observations (provisional profile).',1,.55,.25,true)
            end
        end
        tip:AddLine(row.remaining>0 and ('Application countdown: '..UI.FormatDRTime(row.remaining)..'s')
            or 'Application countdown finished; DR stage is still retained.',1,.85,.4,true)
        tip:AddLine('Starts on application. Breaking or removing CC does not restart it.',.7,.7,.7,true)
        if not row.estimated then
            if row.stageRemaining then
                local basis=row.stageResetSource=='observed-end' and 'observed disappearance'
                    or row.stageResetSource=='unseen-end-estimate' and 'unseen end (bounded estimate)'
                    or 'predicted CC end'
                tip:AddLine('Estimated stage reset in '..math.ceil(row.stageRemaining)..'s ('..basis..').',1,.85,.4,true)
            else
                tip:AddLine('Stage reset waits for a readable CC end.',.7,.7,.7,true)
            end
        end
        if row.estimated then
            if row.estimateKind == 'aoe' then
                tip:AddLine('Unconfirmed AoE cast. Target/focus are POSSIBLE victims only.',1,.55,.25,true)
                tip:AddLine('War Stomp/Grenade/Mortar may miss, be immune, or affect another player. This is not observed DR.',1,.55,.25,true)
            else
                tip:AddLine('Estimate from your cast. Application was not confirmed; it may have missed or been immune.',1,.55,.25,true)
            end
        else
            if row.stageEstimated then
                tip:AddLine('Current application observed. Earlier applications remain inferred; observed stage '..row.observedStage..'.',1,.55,.25,true)
            end
            if row.timeEstimated then
                tip:AddLine('Application observed; timing is estimated from your earlier cast.',1,.55,.25,true)
            elseif row.uncertain and not row.stageEstimated and not row.resetEvidence then
                tip:AddLine('Observation started late or data was unavailable.',1,.55,.25,true)
            end
        end
        tip:AddLine('Stage resets '..ns.db.stageResetSeconds..'s after CC ends (provisional estimate).',.7,.7,.7,true)
    end
    tip:Show()
end

-- Stage pips live in the icon's text layer, above the native swipe.
-- They indicate the same stage as the existing border and never introduce
-- additional inference about CC applications or next duration.
local function updateStagePips(icon, stage, uncertain, enabled)
    local count = (enabled and (stage == 1 or stage == 2 or stage == 3)) and stage or 0
    if icon._pipCount ~= count then
        for i, pip in ipairs(icon.stagePips) do pip:SetShown(i <= count) end
        icon._pipCount = count
    end
    local opacity = uncertain and .55 or 1
    if icon._pipOpacity ~= opacity then
        for _, pip in ipairs(icon.stagePips) do pip:SetAlpha(opacity) end
        icon._pipOpacity = opacity
    end
end

local function makeIcon(bar)
    local icon = CreateFrame('Frame',nil,bar)
    icon.texture = icon:CreateTexture(nil,'ARTWORK')
    icon.texture:SetPoint('TOPLEFT',2,-2); icon.texture:SetPoint('BOTTOMRIGHT',-2,2)
    icon.texture:SetTexCoord(.07,.93,.07,.93)
    icon.swipe = CreateFrame('Cooldown',nil,icon,'CooldownFrameTemplate')
    icon.swipe:SetAllPoints(icon.texture)
    icon.swipe:SetDrawEdge(false)
    icon.swipe:SetHideCountdownNumbers(true)
    icon.swipe:SetReverse(true)
    icon.textLayer=CreateFrame('Frame',nil,icon)
    icon.textLayer:SetAllPoints(icon)
    icon.textLayer:SetFrameLevel(icon.swipe:GetFrameLevel()+1)
    local atlas='UI-HUD-ActionBar-IconFrame'
    if ns.Safe.Call(C_Texture and C_Texture.GetAtlasInfo,atlas) then
        panelBackground(icon,1)
        icon.actionBorder=icon.textLayer:CreateTexture(nil,'OVERLAY')
        icon.actionBorder:SetAtlas(atlas,false)
        icon.actionBorder:SetPoint('TOPLEFT',icon,'TOPLEFT',0,0)
        icon.borderTextures={icon.actionBorder}
    else
        -- Keep an outline on clients without the new artwork, without geometry reads.
        solidPanel(icon,1,icon.textLayer)
    end
    icon.time=font(icon.textLayer,nil,16); icon.time:SetPoint('CENTER',0,0)
    icon.state=font(icon.textLayer,nil,10); icon.state:SetPoint('TOPRIGHT',-1,-1)
    icon.stagePips = {}
    if bar.key ~= 'cooldown' then
        for i=1,3 do
            local pip=icon.textLayer:CreateTexture(nil,'OVERLAY')
            pip:SetColorTexture(gold[1],gold[2],gold[3],1)
            pip:Hide()
            icon.stagePips[i]=pip
        end
    end
    icon:EnableMouse(true)
    icon:SetScript('OnEnter',function(self) if self.row then tooltip(self,self.row,bar.key) end end)
    icon:SetScript('OnLeave',function() if UI.tip then UI.tip:Hide() end end)
    icon:SetScript('OnMouseDown',function(_,button)
        if button=='LeftButton' then ns.Anchors.StartDrag(bar) end
    end)
    icon:SetScript('OnMouseUp',function() ns.Anchors.StopDrag(bar) end)
    return icon
end

function UI.Init()
    for _, key in ipairs(order) do
        local bar = CreateFrame('Frame','bjarkiCC_'..key,UIParent)
        solidPanel(bar,.5)
        bar.key, bar.icons = key, {}
        bar:SetMovable(true); bar:SetClampedToScreen(true); bar:SetFrameStrata('MEDIUM')
        bar:RegisterForDrag('LeftButton'); bar:EnableMouse(true)
        bar:SetScript('OnDragStart',ns.Anchors.StartDrag)
        bar:SetScript('OnDragStop',ns.Anchors.StopDrag)
        bar.title=font(bar,nil,10); bar.title:SetPoint('BOTTOMLEFT',bar,'TOPLEFT',0,5)
        bar.title:SetTextColor(.8,.8,.8)
        bar.overflow=font(bar,nil,10)
        bar.overflow:SetTextColor(.8,.8,.8)
        UI.bars[key]=bar
    end
    UI.ApplyLayout()
end

function UI.ApplyLayout()
    for _,key in ipairs(order) do
        local bar, settings = UI.bars[key], ns.db.bars[key]
        if bar then
            if ns.db.locked then ns.Anchors.StopDrag(bar) end
            ns.Anchors.Apply(bar, true)
            bar:EnableMouse(not ns.db.locked)
            showPanel(bar,not ns.db.locked)
        end
    end
    UI.Update(GetTime())
end

local function textureFor(row)
    local spell = ns.Data.spells[row.spellID]
    if C_Spell and C_Spell.GetSpellTexture then
        local texture = ns.Safe.Call(C_Spell.GetSpellTexture,row.spellID)
        if ns.Safe.Number(texture) or ns.Safe.String(texture) then return texture end
    end
    local category = ns.Data.categoryByKey[row.category]
    return (spell and spell.icon) or (category and category.icon) or 'Interface\\Icons\\INV_Misc_QuestionMark'
end

function UI.Update(now)
    if not ns.db then return end
    if UI.options and UI.options.RefreshActions then UI.options.RefreshActions() end
    for _,key in ipairs(order) do
        local bar, settings = UI.bars[key], ns.db.bars[key]
        if bar then
            ns.Anchors.Apply(bar)
            if not settings.enabled then
                bar:Hide()
            else
                local rows = UI.GetRows(key,now)
                local grid = key ~= 'cooldown'
                local count = math.min(#rows,grid and 4 or settings.maxIcons)
                local setup=ns.demo or not ns.db.locked
                bar:SetShown(setup or (count>0 and ns.Anchors.Visible(bar)))
                bar.title:SetText(key == 'cooldown'
                    and (ns.demo and 'Enemy cooldowns (SAMPLE)' or 'Enemy cooldowns (experimental)')
                    or (titles[key]..(ns.demo and ' (test)' or '')))
                bar.title:SetShown(setup)
                local step=settings.size+settings.gap
                local span=settings.size+math.max(count-1,0)*step
                local width, height
                if grid then
                    local side=settings.size*2+settings.gap
                    width, height = side, side
                else
                    width = settings.vertical and settings.size or math.max(span,count==0 and 96 or 1)
                    height = settings.vertical and span or settings.size
                end
                if bar._renderWidth ~= width or bar._renderHeight ~= height then
                    bar:SetSize(width,height)
                    bar._renderWidth, bar._renderHeight = width,height
                end
                bar.overflow:SetShown(not grid and #rows>count)
                bar.overflow:SetText('+'..(#rows-count))
                bar.overflow:ClearAllPoints()
                if settings.vertical then
                    bar.overflow:SetPoint(settings.reverse and 'BOTTOM' or 'TOP',bar,settings.reverse and 'TOP' or 'BOTTOM',0,settings.reverse and 5 or -5)
                else
                    bar.overflow:SetPoint(settings.reverse and 'RIGHT' or 'LEFT',bar,settings.reverse and 'LEFT' or 'RIGHT',settings.reverse and -5 or 5,0)
                end
                for i=1,count do
                    local row=rows[i]
                    if not bar.icons[i] then bar.icons[i]=makeIcon(bar) end
                    local icon=bar.icons[i]
                    icon.row=row; icon:Show()
                    if icon._renderSize ~= settings.size then
                        icon:SetSize(settings.size,settings.size)
                        -- Native action buttons use a 46x45 bevel on a 45x45 button.
                        -- Derive it from saved size, not protected frame dimensions.
                        if icon.actionBorder then icon.actionBorder:SetSize(settings.size*46/45,settings.size) end
                        icon.time:SetFont(STANDARD_TEXT_FONT,math.floor(settings.size*.47),'OUTLINE')
                        icon.time:SetTextColor(1,1,1)
                        icon.state:SetFont(STANDARD_TEXT_FONT,math.max(9,math.floor(settings.size*.3)),'OUTLINE')
                        local pipSize=math.max(3,math.floor(settings.size*.14+.5))
                        local pipInset=math.max(2,math.floor(settings.size*.07+.5))
                        local pipGap=math.max(1,math.floor(settings.size*.035+.5))
                        for j,pip in ipairs(icon.stagePips) do
                            pip:SetSize(pipSize,pipSize)
                            pip:ClearAllPoints()
                            pip:SetPoint('BOTTOMLEFT',icon,'BOTTOMLEFT',
                                pipInset+(j-1)*(pipSize+pipGap),pipInset)
                        end
                        icon._renderSize=settings.size
                    end
                    local layoutKey=table.concat({settings.size,settings.gap,settings.vertical and 1 or 0,
                        settings.reverse and 1 or 0,i,key},":")
                    if icon._layoutKey ~= layoutKey then
                        icon:ClearAllPoints()
                        local offset=(i-1)*step
                        if grid then
                            local point=key=='player' and 'TOPRIGHT' or 'TOPLEFT'
                            icon:SetPoint(point,bar,point,((i-1)%2)*step*(key=='player' and -1 or 1),-math.floor((i-1)/2)*step)
                        elseif settings.vertical then
                            icon:SetPoint(settings.reverse and 'BOTTOM' or 'TOP',bar,settings.reverse and 'BOTTOM' or 'TOP',0,settings.reverse and offset or -offset)
                        else
                            icon:SetPoint(settings.reverse and 'RIGHT' or 'LEFT',bar,settings.reverse and 'RIGHT' or 'LEFT',settings.reverse and -offset or offset,0)
                        end
                        icon._layoutKey=layoutKey
                    end
                    -- Keep spell texture resolution dynamic when the client
                    -- makes an initially unavailable public icon accessible.
                    icon.texture:SetTexture(textureFor(row))
                    if key=='cooldown' then
                        setTextIfChanged(icon.time,UI.FormatTime(row.remaining))
                        local maybe=row.earlyRemaining and row.earlyRemaining<=0
                        setTextIfChanged(icon.state,(row.anonymous or maybe) and '?' or (row.manual and 'M' or ''))
                        icon.state:SetShown(maybe or row.anonymous==true or row.manual==true)
                        icon.state:SetTextColor(1,.82,.36)
                        setBorderColor(icon,1,1,1,1)
                        icon.swipe:Show(); updateNativeClock(icon,row.started,row.duration)
                    else
                        setTextIfChanged(icon.time,row.remaining>0 and row.remaining<=5 and UI.FormatDRTime(row.remaining) or '')
                        -- Keep all uncertain DR rows visually consistent:
                        -- color shows the estimated stage; the tooltip and
                        -- diagnostics distinguish unconfirmed AoE hits.
                        setTextIfChanged(icon.state,row.uncertain and '' or ({'50%','25%','IMM'})[row.stage])
                        local pctVisible=not row.uncertain and ns.db.showDRText
                        icon.state:SetShown(pctVisible)
                        if icon._percentLayout ~= pctVisible then
                            icon.state:ClearAllPoints()
                            icon.state:SetPoint(pctVisible and 'BOTTOM' or 'TOPRIGHT',
                                pctVisible and 0 or -1,pctVisible and 1 or -1)
                            icon.time:ClearAllPoints()
                            icon.time:SetPoint('CENTER',0,pctVisible and 4 or 0)
                            icon._percentLayout=pctVisible
                        end
                        local color=stageColors[row.stage]
                        icon.state:SetTextColor(color[1],color[2],color[3])
                        setBorderColor(icon,color[1],color[2],color[3],1)
                        -- Percentage labels already carry stage information and
                        -- occupy the bottom edge on smaller default icon sizes.
                        updateStagePips(icon,row.stage,row.uncertain,not pctVisible)
                        icon.swipe:SetShown(row.remaining>0)
                        if row.remaining>0 then updateNativeClock(icon,row.started,row.duration) end
                    end
                end
                for i=count+1,#bar.icons do bar.icons[i]:Hide(); bar.icons[i].row=nil end
            end
        end
    end
end

local function label(parent,text,x,y,width)
    local t=font(parent,'GameFontHighlightSmall')
    t:SetPoint('TOPLEFT',x,y); t:SetWidth(width or 520); t:SetJustifyH('LEFT'); t:SetText(text)
    return t
end

local function button(parent,text,x,y,width,onClick)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
    b:SetSize(width or 130,24); b:SetPoint('TOPLEFT',x,y); b:SetText(text); b:SetScript('OnClick',onClick)
    return b
end

local function check(parent,text,x,y,get,set)
    local b=CreateFrame('CheckButton',nil,parent,'UICheckButtonTemplate')
    b:SetSize(24,24); b:SetPoint('TOPLEFT',x,y)
    local t=font(b,'GameFontHighlightSmall'); t:SetPoint('LEFT',b,'RIGHT',3,0); t:SetText(text)
    b:SetScript('OnShow',function(self) self:SetChecked(get()) end)
    b:SetScript('OnClick',function(self) set(self:GetChecked() and true or false); self:SetChecked(get()); UI.ApplyLayout() end)
    b:SetChecked(get()); return b
end

local function slider(parent,text,x,y,low,high,get,set,width)
    local title=label(parent,text,x,y,width or 240)
    local s=CreateFrame('Slider',nil,parent,'BackdropTemplate')
    s:SetPoint('TOPLEFT',x,y-22); s:SetSize(width or 230,14); s:SetOrientation('HORIZONTAL')
    s:SetMinMaxValues(low,high); s:SetValueStep(1); s:SetObeyStepOnDrag(true)
    backdrop(s,.8); s:SetThumbTexture('Interface\\Buttons\\UI-SliderBar-Button-Horizontal')
    local syncing=false
    local function syncValue()
        local value=get()
        syncing=true; s:SetValue(value); syncing=false
        title:SetText(text..': '..value)
    end
    s:SetScript('OnValueChanged',function(_,v)
        if syncing then return end
        set(math.floor(v+.5))
        -- Setters may reject or normalize a request, and need not return a
        -- success flag. The getter is the authoritative displayed value.
        syncValue(); UI.ApplyLayout()
    end)
    s:SetScript('OnShow',syncValue)
    syncValue()
    return s
end

function UI.OpenOptions()
    if UI.options then UI.options:Show(); return end
    local panel=CreateFrame('Frame','bjarkiCCOptions',UIParent,'BackdropTemplate')
    UI.options=panel; panel:SetSize(500,430); panel:SetPoint('CENTER'); panel:SetFrameStrata('DIALOG')
    backdrop(panel); panel:SetMovable(true); panel:SetClampedToScreen(true); panel:EnableMouse(true)
    panel:RegisterForDrag('LeftButton'); panel:SetScript('OnDragStart',panel.StartMoving); panel:SetScript('OnDragStop',panel.StopMovingOrSizing)
    if UISpecialFrames then table.insert(UISpecialFrames,'bjarkiCCOptions') end
    local title=label(panel,'bjarkiCC',18,-18,440); title:SetTextColor(gold[1],gold[2],gold[3])
    button(panel,'X',462,-10,24,function() panel:Hide() end)
    local pages={}
    for i=1,4 do
        pages[i]=CreateFrame('Frame',nil,panel); pages[i]:SetPoint('TOPLEFT',18,-94); pages[i]:SetPoint('BOTTOMRIGHT',-18,54)
        if i>1 then pages[i]:Hide() end
    end
    for i,text in ipairs({'Display','DR','Cooldowns','GCD flashes'}) do
        button(panel,text,18+(i-1)*118,-52,112,function() for j,p in ipairs(pages) do p:SetShown(i==j) end end)
    end
    local preview,move
    local function refreshActions()
        preview:SetText(ns.demo and 'End preview' or 'Preview')
        move:SetText(ns.db.locked and 'Move bars' or 'Lock bars')
    end
    preview=button(panel,'Preview',18,-392,110,function() ns.demo=not ns.demo; UI.Update(GetTime()); refreshActions() end)
    move=button(panel,'Move bars',136,-392,110,function() ns.db.locked=not ns.db.locked; UI.ApplyLayout(); refreshActions() end)
    button(panel,'Reset positions',254,-392,110,function() ns.ResetPositions(); UI.ApplyLayout() end)
    button(panel,'Close',372,-392,110,function() panel:Hide() end)
    panel:SetScript('OnShow',refreshActions)
    panel.RefreshActions=refreshActions
    refreshActions()

    local page=pages[1]
    for i,key in ipairs(order) do
        local settings=ns.db.bars[key]
        local y=-(i-1)*50
        check(page,key=='cooldown' and 'Enemy CDs (beta)' or titles[key],0,y-7,
            function() return settings.enabled end,function(v) settings.enabled=v end)
        if key=='cooldown' then
            check(page,'Vertical',164,y-7,function() return settings.vertical end,function(v) settings.vertical=v end)
        else
            label(page,'2 x 2',164,y-7,90)
        end
        slider(page,'Size',280,y,24,72,function() return settings.size end,function(v) settings.size=v end,170)
    end
    check(page,'DR percentages',0,-211,function() return ns.db.showDRText end,function(v) ns.db.showDRText=v end)
    label(page,'DR bars follow player, target and focus frames.\nUnlock outside combat to adjust their offsets.',6,-254,450)

    page=pages[2]
    label(page,'Tracked categories',6,0,450)
    for i,category in ipairs(ns.Data.categories) do
        local key=category.key
        check(page,category.name,6+((i-1)%2)*240,-28-math.floor((i-1)/2)*30,
            function() return ns.db.categories[key] end,function(v) ns.db.categories[key]=v end)
    end
    check(page,'Estimate my CC casts when auras are hidden',6,-183,
        function() return ns.db.ownCastEstimates end,function(v) ns.db.ownCastEstimates=v; ns.OwnCasts.Init() end)
    slider(page,'Application countdown (s)',6,-218,10,30,function() return ns.db.resetSeconds end,function(v)
        if v~=ns.db.resetSeconds then
            ns.db.resetSeconds=v; ns.ResetTracking()
        end
    end,210)
    slider(page,'Stage reset after CC (s)',246,-218,10,30,function() return ns.db.stageResetSeconds end,function(v)
        if v~=ns.db.stageResetSeconds then
            ns.db.stageResetSeconds=v; ns.ResetTracking()
        end
    end,210)
    label(page,'Green / yellow / red: stages 1 / 2 / 3. Hover for estimate uncertainty.',6,-266,450)
    check(page,'Estimate Stomp / Grenade / Mortar',6,-288,
        function() return ns.db.aoeCastEstimates end
        ,function(v) ns.db.aoeCastEstimates=v; ns.OwnCasts.Init(); UI.Update(GetTime()) end)

    page=pages[3]
    check(page,'Only current target',0,0,function() return ns.db.targetOnly end,function(v) ns.db.targetOnly=v end)
    check(page,'Include interrupts',240,0,function() return ns.db.interrupts end,function(v) ns.db.interrupts=v end)
    local scroll=CreateFrame('ScrollFrame',nil,page,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',4,-42); scroll:SetPoint('BOTTOMRIGHT',-28,36)
    local child=CreateFrame('Frame',nil,scroll); child:SetWidth(420); scroll:SetScrollChild(child)
    local abilities={}; for _,spell in pairs(ns.Data.spells) do abilities[#abilities+1]=spell end
    table.sort(abilities,function(a,b) return a.name<b.name end)
    for i,spell in ipairs(abilities) do
        local id=spell.id
        local timing=spell.cdMin==spell.cdMax and tostring(spell.cdMax) or spell.cdMin..'-'..spell.cdMax
        check(child,spell.name..'  (~'..timing..'s)',0,-(i-1)*29,
            function() return not ns.db.disabledSpells[id] end,function(v) ns.db.disabledSpells[id]=not v end)
    end
    child:SetHeight(#abilities*29+10)
    label(page,'Experimental: automatic enemy casts are not verified on Forever.\nNo icon does not mean an ability is ready.',6,-265,450)

    page=pages[4]
    if ns.GCD then
    check(page,'Show compact GCD flashes on enemy nameplates',0,0,
        function() return ns.GCD.Get('enabled') end,function(v) ns.GCD.Set('enabled',v) end)
    check(page,'Enemy successful casts (gold)',0,-37,
        function() return ns.GCD.Get('casts') end,function(v) ns.GCD.Set('casts',v) end)
    check(page,'New enemy buffs (green)',0,-73,
        function() return ns.GCD.Get('buffs') end,function(v) ns.GCD.Set('buffs',v) end)
    check(page,'My new debuffs on likely duel opponent (red)',0,-109,
        function() return ns.GCD.Get('debuffs') end,function(v) ns.GCD.Set('debuffs',v) end)
    check(page,'Show names below icons (may overlap in dense fights)',0,-145,
        function() return ns.GCD.Get('name') end,function(v) ns.GCD.Set('name',v) end)
    slider(page,'Icon size',0,-191,24,50,
        function() return ns.GCD.Get('size') end,function(v) ns.GCD.Set('size',v) end,205)
    slider(page,'Flash duration (tenths)',235,-191,5,40,
        function() return ns.GCD.Get('tenths') end,function(v) ns.GCD.Set('tenths',v) end,205)
    label(page,'36px default. All recent flashes grow LEFT, not down.\nSecret enemy casts are DRAWN only; they do not advance DR.\nUse /bcc gcd preview on visible nameplates.',5,-255,460)
    end
    panel:Show()
end
