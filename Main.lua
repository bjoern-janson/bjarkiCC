local _, ns = ...
local S = ns.Safe
local frame = CreateFrame('Frame')
ns.eventFrame, ns.eventErrors = frame, {}
local initialized, scanElapsed, drawElapsed, dirty = false, 0, 0, true
ns.drTrace = {}

-- Observer calls this only with guarded, normalized application evidence.
-- Keep changes rather than polling noise; no raw API values enter this log.
function ns.RecordDRObservation(guid, effects, now, complete, sensor, diagnostics)
    local function stamp(value) return value and string.format('%.3f',value) or 'unknown' end
    local keys, witnesses, identities, stages, stageDetails = {}, {}, {}, {}, {}
    for key in pairs(effects) do keys[#keys+1]=key end
    table.sort(keys)
    for i=1,math.min(6,#keys) do
        local key, effect = keys[i], effects[keys[i]]
        local identity=key..' spell='..effect.spellID..' start='..stamp(effect.appliedAt)
        identities[#identities+1]=identity..' reportedDuration='..stamp(effect.reportedDuration)
        witnesses[#witnesses+1]=identity..' end='..stamp(effect.expires)..' reportedDuration='..stamp(effect.reportedDuration)
    end
    if #keys>6 then witnesses[#witnesses+1]='+'..(#keys-6)..' witnesses' end
    for _,row in ipairs(ns.model:GetDR(guid,now,true)) do
        stages[#stages+1]=row.category..' observed='..(row.observedStage or row.stage)..' shown='..row.stage
            ..' start='..stamp(row.started)..(row.estimated and ' cast-estimate' or (row.stageEstimated and ' inferred-history' or ' observed'))
            ..(row.resetEvidence and (' correction='..row.resetEvidence..' baseline='..stamp(row.resetBaselineDuration)) or '')
            ..' fullBaseline='..stamp(row.fullDurationBaseline)..' baselineSource='..(row.fullDurationBaselineSource or 'none')
            ..' sequence='..(row.durationCandidateStep or 0)
        stageDetails[#stageDetails+1]=stages[#stages]..' stageReset='..stamp(row.stageResetAt)
            ..(row.stageResetSource and (' '..row.stageResetSource) or '')
    end
    local probe=''
    if diagnostics and diagnostics.stompLookup then
        local loc=diagnostics.byUnitComplete
        probe=' | lookup20549='..diagnostics.stompLookup..'; ByUnit='
            ..(loc==nil and 'not-sampled' or (loc and 'complete' or 'restricted'))
            ..'; records='..(diagnostics.byUnitCount or 'unknown')
    end
    if diagnostics and diagnostics.graspLookup then
        probe=probe..'; graspLookup='..diagnostics.graspLookup
    end
    if diagnostics and diagnostics.grenadeLookup then
        probe=probe..'; grenadeLookup='..diagnostics.grenadeLookup
    end
    if diagnostics and diagnostics.eventWitnesses then
        probe=probe..'; auraEventAoE='..diagnostics.eventWitnesses
            ..'; conflict='..tostring(diagnostics.eventConflict == true)
    end
    if diagnostics and diagnostics.aliasCoverage then
        probe=probe..'; alias='..diagnostics.aliasUnit..':'..diagnostics.aliasCoverage
            ..'; aliasMapped='..(diagnostics.aliasMapped or 0)
    end
    if diagnostics and diagnostics.castLookup then
        probe=probe..'; castLookup='..diagnostics.castLookup
            ..'; queries='..(diagnostics.castLookupQueries or 0)
            ..'; hits='..(diagnostics.castLookupHits or 0)
    end
    local detail=sensor..' complete='..tostring(complete)..' effects='..(#witnesses>0 and table.concat(witnesses,'; ') or 'none')..probe
        ..' | DR='..(#stageDetails>0 and table.concat(stageDetails,'; ') or 'none')
    detail=detail:sub(1,1536)
    -- A fallback end computed as now + timeRemaining can drift on every poll.
    -- Include it as context, but only identity/start/reported-duration/stage/coverage changes log.
    local signature=sensor..':'..tostring(complete)..':'..#keys..':'..table.concat(identities,';')..'|'..table.concat(stages,';')..probe
    for i=#ns.drTrace,1,-1 do
        if ns.drTrace[i].guid==guid then
            if ns.drTrace[i].signature==signature then return end
            break
        end
    end
    ns.drTrace[#ns.drTrace+1]={guid=guid,at=now,detail=detail,signature=signature}
    if #ns.drTrace>48 then table.remove(ns.drTrace,1) end
end

local function resetTracking()
    ns.drTrace = {}
    ns.model = ns.Model.New(ns.db.resetSeconds, ns.db.stageResetSeconds)
    ns.Observer.Init()
    ns.OwnCasts.Init()
    dirty = true
end

local function register(event)
    local ok = pcall(frame.RegisterEvent,frame,event)
    if not ok then ns.eventErrors[#ns.eventErrors+1] = event end
end

-- The native DR CVAR is global client configuration, not an addon-private
-- setting. Never toggle it implicitly on login or while in combat.
local NATIVE_CVAR = "spellDiminishPVPEnemiesEnabled"
local function nativeDRSupport()
    local fn = C_SpellDiminish and C_SpellDiminish.IsSystemSupported
    local supported = S.Boolean(S.Call(fn))
    local active = S.String(S.Call(C_CVar and C_CVar.GetCVar, NATIVE_CVAR))
    local eventValid = S.Boolean(S.Call(C_EventUtils and C_EventUtils.IsEventValid,
        "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED"))
    return supported, active, eventValid
end

local function nativeLabel(value)
    return value == nil and "unknown" or tostring(value)
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
        'Rules: '..ns.Data.profile,
        'DR timer: '..ns.db.resetSeconds..'s from last observed application; removal does not restart it',
        'DR stage reset: '..ns.db.stageResetSeconds..'s after CC ends (provisional estimate; separate from countdown)',
        'Mode: '..(ns.demo and 'TEST (synthetic display)' or 'live observation'),
        'Combat log: deliberately not registered (restricted on Forever)',
        'Enemy cooldown HUD: '..(ns.db.bars.cooldown.enabled and 'ENABLED (experimental)' or 'OFF by default (unverified enemy cast feed)'),
        'Enemy cooldown icons require readable success events or manual marks; empty icons do not prove readiness.',
        'Secure native stun visual: '..(ns.NativeStuns and ns.NativeStuns.Status() or 'not installed'),
    }
    local nativeSupported, nativeCVar, nativeEventValid = nativeDRSupport()
    lines[#lines+1]='Native DR feed: supported='..nativeLabel(nativeSupported)
        ..'; cvar='..nativeLabel(nativeCVar)..'; eventValid='..nativeLabel(nativeEventValid)
        ..'; opt-in only (/bcc native on|off|status)'
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
            ..(state.byUnitCount and ('; records '..state.byUnitCount) or '')
        if state.stompLookup then lines[#lines+1]='  Exact War Stomp lookup: '..state.stompLookup end
        if state.graspLookup then lines[#lines+1]="  Exact Nature's Grasp lookup: "..state.graspLookup end
        if state.grenadeLookup then lines[#lines+1]='  Exact Iron Grenade lookup: '..state.grenadeLookup end
        if state.eventWitnesses then lines[#lines+1]='  Readable AoE event: '..state.eventWitnesses
            ..'; conflicting scan '..tostring(state.eventConflict == true) end
        if state.aliasCoverage then lines[#lines+1]='  Shared-GUID alias: '..state.aliasUnit
            ..'; coverage '..state.aliasCoverage..'; mapped '..(state.aliasMapped or 0) end
        if state.castLookup then lines[#lines+1]='  Cast-guided exact lookup: '..state.castLookup
            ..'; queries '..(state.castLookupQueries or 0)
            ..'; positive hits '..(state.castLookupHits or 0) end
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
                if row.stageEstimated then
                    lines[#lines+1]=string.format('    Observed stage %d; displayed stage %d includes earlier inferred applications.',row.observedStage,row.stage)
                end
                if row.timeEstimated then lines[#lines+1]='    Application observed; timing retained from own-cast estimate.' end
                if row.resetEvidence=='matching-full-duration' then
                    lines[#lines+1]=string.format('    Stage correction: matching full duration (%.3fs); reset inferred, server timing unknown.',row.resetBaselineDuration)
                    if row.resetBaselineSource=='observed-halving-chain' then
                        lines[#lines+1]='    Baseline evidence: observed full/half/quarter sequence.'
                    end
                    if row.resetPreviousStage then lines[#lines+1]='    Count before correction: '..row.resetPreviousStage..'.' end
                end
                if not row.estimated then
                    lines[#lines+1]=row.fullDurationBaseline
                        and string.format('    Full-duration baseline: %.3fs (%s).',row.fullDurationBaseline,row.fullDurationBaselineSource or 'unknown')
                        or ('    Full-duration baseline: not learned; sequence '..(row.durationCandidateStep or 0)..'/3.')
                    lines[#lines+1]=row.stageResetAt and string.format('    Stage reset: %.3f; remaining %.3f (%s; provisional estimate).',
                        row.stageResetAt,row.stageRemaining or 0,row.stageResetSource or 'unknown end')
                        or '    Stage reset: awaiting readable CC end.'
                end
            end
        end
        local bar=ns.UI.bars[unit]
        lines[#lines+1]='  Frame: '..(bar and bar.anchorFrame and ({player='PlayerFrame',target='TargetFrame',focus='FocusFrame'})[unit] or 'unavailable')
            ..(bar and bar.anchorPending and ' (layout pending until combat ends)' or '')
    end
    local stats=ns.Observer.stats or {}
    local lastNative = ns.Observer.nativeLast
    if lastNative then
        lines[#lines+1]='Last native DR event: unit='..nativeLabel(lastNative.unit)
            ..' reason='..nativeLabel(lastNative.reason)
            ..' category='..nativeLabel(lastNative.category)
            ..' start='..nativeLabel(lastNative.start)
            ..' duration='..nativeLabel(lastNative.duration)
            ..' countdown='..nativeLabel(lastNative.countdown)
            ..' immune='..nativeLabel(lastNative.immune)
            ..' (diagnostics only; no hit or stage inferred)'
    end
    local lastOwn=ns.Observer.ownCCLast
    if lastOwn then
        lines[#lines+1]='Last own CC cast event: '..lastOwn.family..' '..lastOwn.phase
            ..' spell='..lastOwn.spellID..' at='..nativeLabel(lastOwn.time)
            ..' (cast event, not proven hit)'
    end
    local keys={}; for key in pairs(stats) do keys[#keys+1]=key end; table.sort(keys)
    for _,key in ipairs(keys) do lines[#lines+1]=key..': '..tostring(stats[key]) end
    local rejects = ns.Observer.castRejects or {}
    local rejectKeys = {}
    for reason in pairs(rejects) do rejectKeys[#rejectKeys+1] = reason end
    table.sort(rejectKeys)
    for _, reason in ipairs(rejectKeys) do
        lines[#lines+1] = 'castReject.'..reason..': '..rejects[reason]
    end
    local failures=ns.Observer.apiFailures or {}
    local operations={}; for operation in pairs(failures) do operations[#operations+1]=operation end
    table.sort(operations)
    if #operations>0 then
        lines[#lines+1]='API failures (guarded details):'
        -- Only bounded, sanitized records created by Observer enter this view.
        for _,operation in ipairs(operations) do
            local failure=failures[operation]
            lines[#lines+1]='  '..operation..': '..failure.count
                ..(failure.lastUnit and ('; last unit='..failure.lastUnit) or '')
            lines[#lines+1]='    first readable: '..(failure.firstMessage or '[message unavailable]')
            if failure.lastMessage~=failure.firstMessage then
                lines[#lines+1]='    latest readable: '..(failure.lastMessage or '[message unavailable]')
            end
        end
    end
    lines[#lines+1]='Own-cast DR estimates: '..(ns.db.ownCastEstimates and 'enabled (always uncertain)' or 'disabled')
    lines[#lines+1]='War Stomp DR: confirmed applications only; no cast estimate.'
    local ownStats=ns.OwnCasts.stats or {}
    local ownKeys={}; for key in pairs(ownStats) do ownKeys[#ownKeys+1]=key end; table.sort(ownKeys)
    for _,key in ipairs(ownKeys) do lines[#lines+1]='ownCast.'..key..': '..tostring(ownStats[key]) end
    for _,key in ipairs({'resolved','guidUnavailable','nameUnavailable','nameMismatch','notPlayer','ambiguous'}) do
        lines[#lines+1]='ownCast.resolve.'..key..': '..tostring((ns.OwnCasts.resolutionCounts or {})[key] or 0)
    end
    if ns.OwnCasts.lastResolution then lines[#lines+1]='ownCast.lastResolution: '..ns.OwnCasts.lastResolution end
    if #ns.drTrace>0 then
        lines[#lines+1]='Recent DR observations (latest 24 changes; guarded evidence):'
        for i=math.max(1,#ns.drTrace-23),#ns.drTrace do
            local entry, aliases=ns.drTrace[i],{}
            for _,unit in ipairs({'player','target','focus'}) do
                if ns.Observer.GetUnitState(unit).guid==entry.guid then aliases[#aliases+1]=unit end
            end
            lines[#lines+1]=string.format('  t=%.3f %s %s',entry.at,#aliases>0 and table.concat(aliases,'/') or 'previous unit',entry.detail)
        end
    end
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
    ns.Print('/bcc opens settings; test, lock, unlock, status, reset, clear; aura on|off|status; native on|off|status; cooldowns on|off|status; cooldown <spellID> <seconds|default>; used <spellID>.')
end

function ns.Command(message)
    if not initialized then return end
    message=S.String(message) or ''
    local command,rest=message:match('^%s*(%S*)%s*(.-)%s*$')
    command=command:lower()
    if command=='' or command=='options' then ns.UI.OpenOptions()
    elseif command=='test' then
        ns.demo=not ns.demo; ns.UI.Update(GetTime()); ns.Print(ns.demo and 'Test mode ON: SAMPLE icons, not observed enemy casts.' or 'Live observation restored.')
    elseif command=='lock' or command=='unlock' then
        ns.db.locked=command=='lock'; ns.UI.ApplyLayout(); ns.Print(ns.db.locked and 'Bars locked.' or 'Drag outside combat: DR offsets follow their unit frames.')
    elseif command=='reset' then ns.ResetPositions(); ns.UI.ApplyLayout(); ns.Print('Bar positions reset.')
    elseif command=='clear' then resetTracking(); ns.UI.Update(GetTime()); ns.Print('Tracking history cleared.')
    elseif command=='status' then ns.ShowStatus()
    elseif command=='aura' then
        local option=rest:lower()
        if option=='on' or option=='off' then
            ns.db.nativeStunWitness=(option=='on')
            local ok,reason=ns.NativeStuns.Refresh()
            ns.Print(ns.NativeStuns.Status())
            ns.Print(option=='on' and 'Native stun AURA display requested. An actual visible icon is a matching aura, not a confirmed DR stage.' or 'Native stun aura display disabled.')
            if not ok then ns.Print(reason or 'Aura display will reconcile after combat.') end
        elseif option=='status' or option=='' then
            ns.Print(ns.NativeStuns.Status())
            ns.Print('This secure widget does NOT expose a hit to Lua or advance DR. Only a live duel can verify Blizzard actually displays an aura.')
        else
            ns.Print('Usage: /bcc aura on|off|status')
        end
    elseif command=='native' then
        local option=rest:lower()
        local supported, active, eventValid=nativeDRSupport()
        if option=='on' or option=='off' then
            if type(C_CVar)~='table' or type(C_CVar.SetCVar)~='function' then
                ns.Print('Native DR CVar setter unavailable on this client.')
                return
            end
            if S.Boolean(S.Call(InCombatLockdown))~=false then
                ns.Print('Change the native DR option outside combat.')
                return
            end
            if option=='on' and supported~=true then
                ns.Print('Native DR IsSystemSupported did not return true. No setting changed.')
                return
            end
            local wanted=option=='on' and '1' or '0'
            local ok,result=pcall(C_CVar.SetCVar,NATIVE_CVAR,wanted)
            local newSupported,newValue,newEvent=nativeDRSupport()
            if not ok or S.Boolean(result)==false or newValue~=wanted then
                ns.Print('Native DR setting not confirmed; supported='..nativeLabel(newSupported)
                    ..' cvar='..nativeLabel(newValue)..' eventValid='..nativeLabel(newEvent))
            else
                ns.Print('Native DR '..(option=='on' and 'ENABLED' or 'DISABLED')
                    ..' in client settings. This changes a WoW CVar, not bjarkiCC DR math.')
            end
            ns.Print('Use /bcc native status after a real Bash/Grenade. Native events may be secret or absent.')
        elseif option=='status' or option=='' then
            local stats=ns.Observer.stats or {}
            ns.Print('Native DR supported='..nativeLabel(supported)
                ..'; cvar='..nativeLabel(active)..'; eventValid='..nativeLabel(eventValid))
            ns.Print('Native events='..(stats.nativeDREvents or 0)
                ..'; readable category='..(stats.nativeDRReadable or 0)
                ..'; restricted='..(stats.nativeDRRestricted or 0)
                ..'; player Bash sent/succeeded='..(stats.ownBashSent or 0)..'/'..(stats.ownBashSucceeded or 0)
                ..'; Iron Grenade='..(stats.ownGrenadeSent or 0)..'/'..(stats.ownGrenadeSucceeded or 0)
                ..'; War Stomp='..(stats.ownStompSent or 0)..'/'..(stats.ownStompSucceeded or 0))
            local last=ns.Observer.nativeLast
            if last then ns.Print('Last native event: unit='..nativeLabel(last.unit)
                ..' category='..nativeLabel(last.category)
                ..' start='..nativeLabel(last.start)..' duration='..nativeLabel(last.duration)
                ..' countdown='..nativeLabel(last.countdown)
                ..' immune='..nativeLabel(last.immune)
                ..' (never counted as a hit)') end
        else
            ns.Print('Usage: /bcc native on|off|status')
        end
    elseif command=='cooldowns' then
        local option=rest:lower()
        if option=='on' or option=='off' then
            ns.db.bars.cooldown.enabled=(option=='on')
            ns.UI.ApplyLayout()
            ns.Print(option=='on' and 'Enemy cooldown HUD ON (experimental; only readable enemy successes or manual marks).' or 'Enemy cooldown HUD OFF. DR trackers unchanged.')
        elseif option=='status' then
            local stats=ns.Observer.stats or {}
            ns.Print('Enemy cooldown HUD: '..(ns.db.bars.cooldown.enabled and 'on (experimental)' or 'off')..'.')
            ns.Print('Event counts since tracking reset: other-unit cast START='..(stats.castStartsOther or 0)
                ..', SUCCEEDED='..(stats.castSuccessOther or 0)
                ..', accepted automatic cooldowns='..(stats.acceptedCasts or 0)
                ..'. These counts do not establish complete enemy cast coverage.')
        else
            ns.Print('Usage: /bcc cooldowns on|off|status')
        end
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
        -- Build secure aura hosts out of combat. Do not read their protected
        -- selected-aura state; they are a separate native visual witness.
        if ns.NativeStuns then ns.NativeStuns.Init() end
        initialized=true
        ns.Observer.Scan(GetTime()); ns.UI.Update(GetTime())
        ns.Print('Forever beta '..ns.version..' loaded. /bcc for settings, /bcc test to position bars.')
    elseif initialized then
        if event=='UNIT_SPELLCAST_START' or event=='UNIT_SPELLCAST_CHANNEL_START' then
            ns.Observer.NoteCastStart(...)
        elseif event=='UNIT_SPELLCAST_SENT' then
            local unit,targetName,castGUID,spellID=...
            ns.Observer.NoteOwnCCCast('Sent',unit,spellID,GetTime())
            ns.OwnCasts.Sent(unit,targetName,castGUID,spellID,GetTime())
        elseif event=='UNIT_SPELLCAST_SUCCEEDED' then
            local unit,castGUID,spellID=...
            ns.Observer.NoteOwnCCCast('Succeeded',unit,spellID,GetTime())
            ns.Observer.OnCast(unit,castGUID,spellID,GetTime())
            ns.OwnCasts.Succeeded(unit,castGUID,spellID,GetTime())
        elseif event=='UNIT_SPELLCAST_FAILED' or event=='UNIT_SPELLCAST_INTERRUPTED' then
            local unit,castGUID,spellID=...
            ns.OwnCasts.Failed(unit,castGUID,spellID,GetTime())
        elseif event=='UNIT_AURA' then
            local unit, updateInfo=...
            local token=S.String(unit)
            if not token or token=='player' or token=='target' or token=='focus' then
                -- A readable positive event can capture short-lived AoE CC even
                -- when the following indexed scan has already become secret.
                ns.Observer.OnAuraEvent(unit,updateInfo,GetTime())
            end
        elseif event=='LOSS_OF_CONTROL_ADDED' or event=='LOSS_OF_CONTROL_UPDATE' then
            local unit=S.String(...)
            if not unit or unit=='player' or unit=='target' or unit=='focus' then
                ns.Observer.Scan(GetTime())
            end
        elseif event=='UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED' then
            ns.Observer.OnNativeDR(...)
        elseif event=='PLAYER_ENTERING_WORLD' then resetTracking()
        elseif event=='PLAYER_REGEN_ENABLED' then
            ns.UI.ApplyLayout()
            if ns.NativeStuns then ns.NativeStuns.Refresh(true) end
            dirty=true
        elseif event=='PLAYER_REGEN_DISABLED' then
            for _,bar in pairs(ns.UI.bars) do ns.Anchors.StopDrag(bar) end
        elseif event=='PLAYER_TARGET_CHANGED' or event=='PLAYER_FOCUS_CHANGED' then
            ns.Observer.Scan(GetTime())
            if ns.NativeStuns then ns.NativeStuns.Refresh(true) end
            dirty=true
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

-- Native DR event is diagnostics-only. Its secret payload never enters the model.
for _,event in ipairs({'ADDON_LOADED','PLAYER_ENTERING_WORLD','PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED',
    'PLAYER_REGEN_ENABLED','PLAYER_REGEN_DISABLED','UNIT_AURA',
    'UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED',
    'LOSS_OF_CONTROL_ADDED','LOSS_OF_CONTROL_UPDATE','UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_START',
    'UNIT_SPELLCAST_CHANNEL_START','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED','PLAYER_DEAD','PLAYER_ALIVE'}) do register(event) end
SLASH_BJARKICC1='/bcc'
SLASH_BJARKICC2='/bjarkicc'
SlashCmdList.BJARKICC=ns.Command
