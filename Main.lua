local _, ns = ...
local S = ns.Safe
local frame = CreateFrame('Frame')
ns.eventFrame, ns.eventErrors = frame, {}
local initialized, scanElapsed, drawElapsed, dirty = false, 0, 0, true

local function resetTracking()
    ns.model = ns.Model.New(ns.db.resetSeconds)
    ns.Observer.Init()
    ns.OwnCasts.Init()
    dirty = true
end

local function register(event)
    local ok = pcall(frame.RegisterEvent,frame,event)
    if not ok then ns.eventErrors[#ns.eventErrors+1] = event end
end

function ns.BuildStatus()
    local version, build, interface = 'unknown','unknown','unknown'
    local now = S.Number(S.Call(GetTime))
    if type(GetBuildInfo)=='function' then
        local ok,v,b,_,i=pcall(GetBuildInfo)
        if ok then version=S.String(v) or version; build=S.String(b) or build; interface=S.Number(i) or interface end
    end
    local lines={
        'bjarkiCC '..ns.version,
        'Client: '..version..' build '..build..' / interface '..interface,
        'Rules: '..ns.Data.profile..'; reset '..ns.db.resetSeconds..'s',
        'DR timer: last observed application; removal does not restart it',
        'Mode: '..(ns.demo and 'TEST (synthetic display)' or 'live observation'),
        'Combat log: deliberately not registered (restricted on Forever)',
    }
    for _,unit in ipairs({'player','target','focus'}) do
        local state=ns.Observer.GetUnitState(unit)
        lines[#lines+1]=unit..': '..(state.status or 'unknown')..'; sensor '..(state.sensor or 'none')
        if state.coverageNote then lines[#lines+1]='  '..state.coverageNote end
        if state.reason then lines[#lines+1]='  '..state.reason end
        local function coverage(value)
            if value == nil then return 'not sampled' end
            return value and 'complete' or 'partial/restricted'
        end
        lines[#lines+1]='  Auras: '..coverage(state.auraComplete)..'; mapped '..(state.mappedAuras or 0)
        lines[#lines+1]='  Unit LoC: '..(state.byUnitAvailable and coverage(state.byUnitComplete) or 'unavailable')..'; mapped '..(state.mappedLoC or 0)
        if state.unmappedSpellIDs and #state.unmappedSpellIDs>0 then
            local ids={}; for _,id in ipairs(state.unmappedSpellIDs) do ids[#ids+1]=tostring(id) end
            lines[#lines+1]='  Readable unmapped aura IDs: '..table.concat(ids,', ')
        end
        if now and state.guid then
            for _, row in ipairs(ns.model:GetDR(state.guid, now, ns.db.ownCastEstimates)) do
                lines[#lines+1]=string.format('  DR %s: stage %d; started %.3f; remaining %.3f; %s%s',
                    row.category, row.stage, row.started, row.remaining,
                    row.estimated and 'own-cast estimate' or 'observed application',
                    row.uncertain and '; uncertain' or '')
                if row.timeEstimated then lines[#lines+1]='    Application observed; timing retained from own-cast estimate.' end
            end
        end
        local bar=ns.UI.bars[unit]
        lines[#lines+1]='  Frame: '..(bar and bar.anchorFrame and ({player='PlayerFrame',target='TargetFrame',focus='FocusFrame'})[unit] or 'unavailable')
            ..(bar and bar.anchorPending and ' (layout pending until combat ends)' or '')
    end
    local stats=ns.Observer.stats or {}
    local keys={}; for key in pairs(stats) do keys[#keys+1]=key end; table.sort(keys)
    for _,key in ipairs(keys) do lines[#lines+1]=key..': '..tostring(stats[key]) end
    lines[#lines+1]='Own-cast DR estimates: '..(ns.db.ownCastEstimates and 'enabled (always uncertain)' or 'disabled')
    local ownStats=ns.OwnCasts.stats or {}
    local ownKeys={}; for key in pairs(ownStats) do ownKeys[#ownKeys+1]=key end; table.sort(ownKeys)
    for _,key in ipairs(ownKeys) do lines[#lines+1]='ownCast.'..key..': '..tostring(ownStats[key]) end
    if #ns.eventErrors>0 then lines[#lines+1]='Unavailable events: '..table.concat(ns.eventErrors,', ') end
    lines[#lines+1]='Enemy timers require readable spell, identity and hostility. No observations is not proof of readiness.'
    lines[#lines+1]='Static and simulated tests passed; this report does not establish live DR correctness.'
    return table.concat(lines,'\n')
end

function ns.ShowStatus()
    ns.Print('Diagnostics opened. Ctrl+A, Ctrl+C copies the report.')
    if not ns.statusPanel then
        local panel=CreateFrame('Frame','bjarkiCCDiagnostics',UIParent,'BackdropTemplate')
        panel:SetSize(580,470); panel:SetPoint('CENTER'); panel:SetFrameStrata('FULLSCREEN_DIALOG')
        panel:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
        panel:SetBackdropColor(.04,.04,.04,.98); panel:SetBackdropBorderColor(.7,.55,.2,1)
        panel:EnableMouse(true)
        local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormal')
        title:SetPoint('TOPLEFT',18,-16); title:SetText('bjarkiCC diagnostics - Ctrl+A, Ctrl+C to copy')
        local close=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate')
        close:SetSize(24,24); close:SetPoint('TOPRIGHT',-10,-10); close:SetText('X')
        close:SetScript('OnClick',function() panel:Hide() end)
        local scroll=CreateFrame('ScrollFrame',nil,panel,'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT',18,-48); scroll:SetPoint('BOTTOMRIGHT',-34,18)
        local edit=CreateFrame('EditBox',nil,scroll)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject('ChatFontNormal'); edit:SetWidth(508); edit:SetHeight(600)
        edit:SetScript('OnEscapePressed',function() panel:Hide() end)
        scroll:SetScrollChild(edit); panel.edit=edit
        if UISpecialFrames then table.insert(UISpecialFrames,'bjarkiCCDiagnostics') end
        ns.statusPanel=panel
    end
    ns.statusPanel:Show(); ns.statusPanel.edit:SetText(ns.BuildStatus()); ns.statusPanel.edit:HighlightText(); ns.statusPanel.edit:SetFocus()
end

local function help()
    ns.Print('/bcc opens settings; test, lock, unlock, status, reset, clear; cooldown <spellID> <seconds|default>; used <spellID>.')
end

function ns.Command(message)
    if not initialized then return end
    message=S.String(message) or ''
    local command,rest=message:match('^%s*(%S*)%s*(.-)%s*$')
    command=command:lower()
    if command=='' or command=='options' then ns.UI.OpenOptions()
    elseif command=='test' then
        ns.demo=not ns.demo; ns.UI.Update(GetTime()); ns.Print(ns.demo and 'Test mode ON: synthetic icons.' or 'Live observation restored.')
    elseif command=='lock' or command=='unlock' then
        ns.db.locked=command=='lock'; ns.UI.ApplyLayout(); ns.Print(ns.db.locked and 'Bars locked.' or 'Drag outside combat: DR offsets follow their unit frames.')
    elseif command=='reset' then ns.ResetPositions(); ns.UI.ApplyLayout(); ns.Print('Bar positions reset.')
    elseif command=='clear' then resetTracking(); ns.UI.Update(GetTime()); ns.Print('Tracking history cleared.')
    elseif command=='status' then ns.ShowStatus()
    elseif command=='cooldown' then
        local idText,value=rest:match('^(%d+)%s+(%S+)$')
        local id=tonumber(idText); local canonical=id and ns.Data.castToSpell[id]
        if not canonical then ns.Print('Use a known spell ID, e.g. /bcc cooldown 853 45'); return end
        if value=='default' then ns.db.cooldownOverrides[canonical]=nil
        else
            local seconds=tonumber(value)
            if not S.Number(seconds) or seconds<1 or seconds>900 then ns.Print('Cooldown must be 1-900 seconds, or default.'); return end
            ns.db.cooldownOverrides[canonical]=seconds
        end
        ns.Print(ns.Data.spells[canonical].name..' timing updated for future casts.')
    elseif command=='used' then
        local id=tonumber(rest)
        if not id or not ns.Data.castToSpell[id] then ns.Print('Use a known spell ID, e.g. /bcc used 853'); return end
        local guid=S.String(S.Call(UnitGUID,'target'))
        local hostile=S.Boolean(S.Call(UnitCanAttack,'player','target'))
        local player=S.Boolean(S.Call(UnitIsPlayer,'target'))
        if not guid or not hostile or not player then ns.Print('Select an identifiable hostile player first.'); return end
        local name=S.String(S.Call(UnitName,'target')) or 'Target'
        ns.model:Cast(guid,name,id,GetTime(),nil,true,ns.db.cooldownOverrides)
        ns.UI.Update(GetTime()); ns.Print('Manually marked '..ns.Data.spells[ns.Data.castToSpell[id]].name..'.')
    else help() end
end

frame:SetScript('OnEvent',function(_,event,...)
    if event=='ADDON_LOADED' then
        local name=S.String(...)
        if name~=ns.name or initialized then return end
        ns.InitializeDB(); resetTracking(); ns.UI.Init()
        initialized=true
        ns.Observer.Scan(GetTime()); ns.UI.Update(GetTime())
        ns.Print('Forever beta '..ns.version..' loaded. /bcc for settings, /bcc test to position bars.')
    elseif initialized then
        if event=='UNIT_SPELLCAST_SENT' then
            local unit,targetName,castGUID,spellID=...
            ns.OwnCasts.Sent(unit,targetName,castGUID,spellID,GetTime())
        elseif event=='UNIT_SPELLCAST_SUCCEEDED' then
            local unit,castGUID,spellID=...
            ns.Observer.OnCast(unit,castGUID,spellID,GetTime())
            ns.OwnCasts.Succeeded(unit,castGUID,spellID,GetTime())
        elseif event=='UNIT_SPELLCAST_FAILED' or event=='UNIT_SPELLCAST_INTERRUPTED' then
            local unit,castGUID,spellID=...
            ns.OwnCasts.Failed(unit,castGUID,spellID,GetTime())
        elseif event=='UNIT_AURA' or event=='LOSS_OF_CONTROL_ADDED' or event=='LOSS_OF_CONTROL_UPDATE' then
            local unit=S.String(...)
            if not unit or unit=='player' or unit=='target' or unit=='focus' then
                -- Sample synchronously: a short CC can start and end between
                -- render ticks. Render remains throttled independently.
                ns.Observer.Scan(GetTime())
            end
        elseif event=='PLAYER_ENTERING_WORLD' then resetTracking()
        elseif event=='PLAYER_REGEN_ENABLED' then ns.UI.ApplyLayout(); dirty=true
        elseif event=='PLAYER_REGEN_DISABLED' then
            for _,bar in pairs(ns.UI.bars) do ns.Anchors.StopDrag(bar) end
        elseif event=='PLAYER_TARGET_CHANGED' or event=='PLAYER_FOCUS_CHANGED' then
            ns.Observer.Scan(GetTime()); dirty=true
        elseif event=='PLAYER_DEAD' then
            local state=ns.Observer.GetUnitState('player')
            if state.guid then ns.model:Forget(state.guid) end
            dirty=true
        else dirty=true end
    end
end)

frame:SetScript('OnUpdate',function(_,elapsed)
    if not initialized then return end
    scanElapsed,drawElapsed=scanElapsed+elapsed,drawElapsed+elapsed
    if scanElapsed>=.2 or (dirty and scanElapsed>=.05) then
        scanElapsed,dirty=0,false; ns.Observer.Scan(GetTime())
    end
    if drawElapsed>=.1 then drawElapsed=0; ns.UI.Update(GetTime()) end
end)

-- No combat-log or secret native SpellDiminish event registration.
for _,event in ipairs({'ADDON_LOADED','PLAYER_ENTERING_WORLD','PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED',
    'PLAYER_REGEN_ENABLED','PLAYER_REGEN_DISABLED','UNIT_AURA',
    'LOSS_OF_CONTROL_ADDED','LOSS_OF_CONTROL_UPDATE','UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_SUCCEEDED',
    'UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED','PLAYER_DEAD','PLAYER_ALIVE'}) do register(event) end
SLASH_BJARKICC1='/bcc'
SLASH_BJARKICC2='/bjarkicc'
SlashCmdList.BJARKICC=ns.Command
