local _, ns = ...
-- Positive, readable witnesses only. This module has no DR authority and does
-- not inspect secret spell IDs from GCD flashes or native DR event payloads.
-- Named recipients NEVER become supposed casters unless the aura itself can
-- only be activated on the caster (the reviewed small allowlist in Data.lua).
local Evidence = {}
ns.CooldownEvidence = Evidence
local Safe = ns.Safe
local MAX_AURA_EVENT_ITEMS = 64
local MAX_SEEN_AURAS = 256
local SEEN_TTL = 480
local MAX_UNKNOWN = 256
local HELPFUL_TIME_TOLERANCE = 0.1
local LOC_TIME_TOLERANCE = 0.001
local MAX_LOC_APPLICATIONS, LOC_APPLICATION_TTL = 160, 360

local function integer(value)
    local x = Safe.Number(value)
    if x and x > 0 and x == math.floor(x) then return x end
end

local function currentTime(value)
    local x = Safe.Number(value)
    if x and x >= 0 then return x end
end

local function safeField(value, field)
    return Safe.Field(value, field)
end

local function playerGUID(value)
    local guid = Safe.String(value)
    if guid and #guid <= 128 and guid:match('^Player%-[%w%-]+$') then return guid end
end

local function eligibleToken(token)
    local unit = Safe.String(token)
    if unit == 'target' or unit == 'focus' then return unit end
    local suffix = unit and unit:match('^nameplate(%d+)$')
    if suffix and tonumber(suffix) and tonumber(suffix) <= 200 then return unit end
end

local function hostilePlayerGUID(unit)
    unit = eligibleToken(unit)
    if not unit then return nil end
    local guid = playerGUID(Safe.Call(UnitGUID, unit))
    if not guid then return nil end
    if Safe.Boolean(Safe.Call(UnitCanAttack, 'player', unit)) ~= true then return nil end
    -- GUID is positive player identity. A readable contradiction still vetoes.
    if Safe.Boolean(Safe.Call(UnitIsPlayer, unit)) == false then return nil end
    return guid
end

local function pruneSeen(now)
    local count, oldestKey, oldestTime = 0
    for key, stamp in pairs(Evidence.seenHelpful) do
        if now - stamp >= SEEN_TTL then
            Evidence.seenHelpful[key] = nil
        else
            count = count + 1
            if not oldestTime or stamp < oldestTime then oldestKey, oldestTime = key, stamp end
        end
    end
    while count > MAX_SEEN_AURAS do
        if not oldestKey then break end
        Evidence.seenHelpful[oldestKey] = nil
        count = count - 1
        oldestKey, oldestTime = nil, nil
        for key, stamp in pairs(Evidence.seenHelpful) do
            if not oldestTime or stamp < oldestTime then oldestKey, oldestTime = key, stamp end
        end
    end
    -- Continuity metadata is bounded independently of the per-witness keys.
    count, oldestKey, oldestTime = 0, nil, nil
    for key, application in pairs(Evidence.helpfulApplications) do
        if now - application.seen >= SEEN_TTL then
            Evidence.helpfulApplications[key] = nil
        else
            count = count + 1
            if not oldestTime or application.seen < oldestTime then
                oldestKey, oldestTime = key, application.seen
            end
        end
    end
    while count > MAX_SEEN_AURAS do
        Evidence.helpfulApplications[oldestKey] = nil
        count, oldestKey, oldestTime = count - 1, nil, nil
        for key, application in pairs(Evidence.helpfulApplications) do
            if not oldestTime or application.seen < oldestTime then
                oldestKey, oldestTime = key, application.seen
            end
        end
    end
end

local function helpfulTime(aura, now)
    local expiry = currentTime(safeField(aura, 'expirationTime'))
    local duration = currentTime(safeField(aura, 'duration'))
    if expiry and expiry > 0 and duration and duration > 0 and duration <= 300 then
        local started = expiry - duration
        if started >= 0 and started <= now + HELPFUL_TIME_TOLERANCE
            and now - started <= duration + HELPFUL_TIME_TOLERANCE then
            return math.min(started,now), false
        end
    end
    return now, true -- first sighting, NOT a confirmed cast time
end

local function activeHelpful(guid, canonical, now)
    local caster = ns.model.casters[guid]
    local row = caster and caster.cooldowns[canonical]
    if row and row.evidenceSource == 'helpful-aura'
        and type(row.evidenceIdentity) == 'string'
        and now < row.started + row.duration then return row end
end

-- A missing aura-instance ID and application timestamp make repeated exact
-- lookups indistinguishable. Only an explicit new *addedAuras* notification
-- after the earliest plausible cooldown can start another identity cycle.
-- No timeout alone permits a new estimated activation.
local function unknownIdentity(guid, canonical, now, newApplication)
    local key = guid..':'..canonical
    local known = Evidence.unknownHelpful[key]
    local caster = ns.model.casters[guid]
    local row = caster and caster.cooldowns[canonical]
    local cast = row and row.evidenceSource == 'cast' and row
    if not known then
        local count = 0
        for _ in pairs(Evidence.unknownHelpful) do count = count + 1 end
        if count >= MAX_UNKNOWN then
            Evidence.stats.unknownCapacityRejected = Evidence.stats.unknownCapacityRejected + 1
            return nil -- Fail closed instead of inventing a new activation.
        end
        if cast then
            -- The accepted cast is an activation anchor; the later sighting
            -- is not. Retain that anchor even after the cast/seen-key expires
            -- so an ordinary anonymous sighting cannot manufacture renewal.
            known = {generation=0, lastActivation=cast.started}
            Evidence.unknownHelpful[key] = known
            if not newApplication then
                -- Let Model link near-concurrent provenance, without committing
                -- this proposed identity if it rejects the aura activation.
                return 'unknown-cycle:1', {generation=1,lastActivation=now}, false
            end
        else
            return 'unknown-cycle:1', {generation=1,lastActivation=now}, false
        end
    elseif cast and cast.started > known.lastActivation then
        known.lastActivation = cast.started -- another accepted cast superseded it
    end
    if newApplication then
        local ability = ns.Data.spells[canonical]
        local earliest = ability and ability.cdMin or 1
        local override = ns.db and ns.db.cooldownOverrides
            and Safe.Number(ns.db.cooldownOverrides[canonical])
        if override and override > 0 then earliest = override end
        local current = activeHelpful(guid, canonical, now)
        local lastActivation = current and current.started or known.lastActivation
        if now - lastActivation < math.max(.5, earliest - HELPFUL_TIME_TOLERANCE) then
            if cast and now < cast.started + cast.duration then
                -- Model owns the near-cast provenance window. Offer the report
                -- only as an ordinary sighting of this still-active cast, so
                -- it can link provenance but cannot admit an early activation.
                local proposed = {generation=known.generation+1,lastActivation=now}
                return 'unknown-cycle:'..proposed.generation, proposed, false, true
            end
            return nil
        end
        local proposed = {generation=known.generation+1,lastActivation=now}
        return 'unknown-cycle:'..proposed.generation, proposed, true
    else
        return nil -- another sighting is not another application
    end
end

local function rememberHelpful(guid, canonical, key, instance, now, activatedAt)
    local applicationKey = guid..':'..canonical
    local known = Evidence.helpfulApplications[applicationKey]
    if not known or known.identity ~= key then
        known = {identity=key}
        Evidence.helpfulApplications[applicationKey] = known
    end
    known.instance = instance or known.instance
    known.seen = math.max(known.seen or now, now)
    if activatedAt then
        -- Strong identities also establish the last activation for later
        -- anonymous added-aura events. Losing their identity must not open a
        -- fresh anonymous cycle or let an old cycle bypass the renewal gate.
        local unknown = Evidence.unknownHelpful[applicationKey]
        if unknown then
            unknown.lastActivation = activatedAt
        else
            local count = 0
            for _ in pairs(Evidence.unknownHelpful) do count = count + 1 end
            if count < MAX_UNKNOWN then
                Evidence.unknownHelpful[applicationKey] = {generation=0,lastActivation=activatedAt}
            end
        end
    end
end

-- Optional identity fields can disappear between sensors. Keep the original
-- claim key for an active application, while remembering any stronger ID that
-- becomes readable. A different readable ID, later exact start or explicit
-- new application still takes the normal new-witness path.
local function continuingHelpful(guid, canonical, instance, started, approximate, now, newApplication)
    local row = activeHelpful(guid, canonical, now)
    if not row then return nil end
    local known = Evidence.helpfulApplications[guid..':'..canonical]
    local priorInstance = known and known.identity == row.evidenceIdentity and known.instance
        or tonumber(row.evidenceIdentity:match(':instance:(%d+)$'))
    if instance and priorInstance then
        if instance == priorInstance then return row.evidenceIdentity end
        return nil
    end
    if newApplication then return nil end
    if not approximate then
        if row.timingEstimated then
            if started > row.started + HELPFUL_TIME_TOLERANCE then return nil end
        elseif math.abs(started - row.started) > HELPFUL_TIME_TOLERANCE then
            return nil
        end
    end
    return row.evidenceIdentity
end

local function acceptHelpful(guid, aura, now, newApplication, origin)
    -- The publisher and local scanner may observe the same effect. Their
    -- reports are one causal witness, not multiple independent confirmations.
    origin = origin or 'CC local aura'
    if type(aura) ~= 'table' or Safe.Boolean(safeField(aura,'isHelpful')) ~= true then
        Evidence.stats.helpfulRejected = Evidence.stats.helpfulRejected + 1
        return false
    end
    local effectID = integer(safeField(aura,'spellId'))
    local canonical = effectID and ns.Data.helpfulCooldownAuras[effectID]
    if not canonical then return false end
    local instance = integer(safeField(aura,'auraInstanceID'))
    local started, approximate = helpfulTime(aura, now)
    pruneSeen(now)
    local continuing = continuingHelpful(guid, canonical, instance, started,
        approximate, now, newApplication == true)
    local identity, proposedUnknown, renewedUnknown, castCorroborationOnly
    if instance then
        identity = 'instance:'..instance
    elseif not approximate then
        identity = 'start:'..math.floor(started*10+.5)
    elseif not continuing then
        identity, proposedUnknown, renewedUnknown, castCorroborationOnly =
            unknownIdentity(guid, canonical, now, newApplication == true)
        if not identity then
            Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
            return false
        end
    end
    local rawKey = identity and guid..':'..canonical..':'..identity
    local key = continuing or rawKey
    -- Expired keys are pruned BEFORE deduplication; an exact identity can only
    -- be replayed after TTL if the API truly reports it again. Anonymous
    -- reapplications still demand a positive added-aura event (above).
    if continuing or Evidence.seenHelpful[key] then
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        if continuing then
            rememberHelpful(guid, canonical, key, instance, now)
            -- A stronger alias must also remain deduplicated if an older
            -- sensor reports it after a later genuine application.
            if rawKey then Evidence.seenHelpful[rawKey] = now end
            pruneSeen(now)
        end
        -- A later exact timestamp can refine a first-sighting estimate, but
        -- only for this same aura identity. Duplicate sensors add provenance.
        if ns.model.CorroborateHelpful
            and ns.model:CorroborateHelpful(guid,canonical,key,now,origin) then
            Evidence.stats.helpfulProvenanceLinked = Evidence.stats.helpfulProvenanceLinked + 1
        end
        if not approximate and ns.model.RefineHelpfulTime
            and ns.model:RefineHelpfulTime(guid,canonical,key,started,now,origin) then
            rememberHelpful(guid, canonical, key, instance, now, started)
            pruneSeen(now)
            Evidence.stats.helpfulTimingRefined = Evidence.stats.helpfulTimingRefined + 1
        end
        return false
    end
    -- Keep rejected strong identities deduplicated, but a proposed anonymous
    -- cycle must remain available for the next genuinely accepted application.
    if not proposedUnknown then
        Evidence.seenHelpful[key] = now
        pruneSeen(now)
    end
    Evidence.stats.helpfulPositive = Evidence.stats.helpfulPositive + 1
    local accepted = ns.model:Cast(guid, nil, canonical, started,
        'helpful-aura:'..key, false, ns.db.cooldownOverrides,
        'helpful-aura', approximate, {
            identity=key, origin=origin, observedAt=now,
            newApplication=newApplication == true and not castCorroborationOnly,
        })
    if accepted then
        if proposedUnknown then
            Evidence.unknownHelpful[guid..':'..canonical] = proposedUnknown
            Evidence.seenHelpful[key] = now
            if renewedUnknown then
                Evidence.stats.unknownRenewed = Evidence.stats.unknownRenewed + 1
            end
        end
        rememberHelpful(guid, canonical, key, instance, now, started)
        pruneSeen(now)
        Evidence.stats.helpfulAccepted = Evidence.stats.helpfulAccepted + 1
    else
        Evidence.stats.helpfulAlreadyTracked = Evidence.stats.helpfulAlreadyTracked + 1
    end
    return accepted == true
end

local function exactHelpful(unit, guid, now)
    local api = C_UnitAuras
    if type(api) ~= 'table' or type(api.GetUnitAuraBySpellID) ~= 'function' then return end
    -- Fixed allowlist; no broad combat aura enumeration or name-based matching.
    for effectID in pairs(ns.Data.helpfulCooldownAuras) do
        local aura = Safe.Call(api.GetUnitAuraBySpellID, unit, effectID)
        if type(aura) == 'table' then
            local actual = integer(safeField(aura,'spellId'))
            if actual == effectID then acceptHelpful(guid, aura, now, false, 'CC exact lookup') end
        end
    end
end

function Evidence.OnUnitSeen(unit, now)
    now = currentTime(now)
    if not now then return end
    local guid = hostilePlayerGUID(unit)
    if guid then exactHelpful(unit, guid, now) end
end

function Evidence.OnAuraEvent(unit, updateInfo, now)
    now = currentTime(now)
    if not now then return end
    local guid = hostilePlayerGUID(unit)
    if not guid then return end
    Evidence.stats.helpfulEvents = Evidence.stats.helpfulEvents + 1
    local added = safeField(updateInfo, 'addedAuras')
    if type(added) == 'table' and Safe.Readable(added) then
        local count = Safe.Number(Safe.Call(function() return #added end))
        if count and count >= 0 and count <= MAX_AURA_EVENT_ITEMS then
            for i = 1, count do
                local aura = safeField(added,i)
                if aura then acceptHelpful(guid,aura,now,true,'CC added aura') end
            end
        end
    end
    -- New-onset event tables can be wholly secret. Exact helpful lookups are
    -- guarded positive witnesses; nil or an error never implies buff removal.
    exactHelpful(unit,guid,now)
end

-- Optional, one-way Portraits -> CC positive evidence. The publisher already
-- checked that the recipient was an identifiable hostile player, but no
-- helpful-buff recipient is promoted to a caster outside the self-cast allowlist.
-- This subscriber never re-emits evidence (prevents circular confirmation).
function Evidence.OnSharedAura(record)
    Evidence.stats.sharedReceived = Evidence.stats.sharedReceived + 1
    if not ns.model or not ns.db or type(record) ~= 'table'
        or Safe.String(safeField(record,'source')) ~= 'bjarkiPortraits'
        or Safe.String(safeField(record,'kind')) ~= 'aura-positive' then
        Evidence.stats.sharedRejected = Evidence.stats.sharedRejected + 1
        return false
    end
    local guid = playerGUID(safeField(record,'recipientGUID'))
    local at = currentTime(safeField(record,'observedAt'))
    local now = currentTime(Safe.Call(GetTime))
    if not guid or not at or not now or at > now + .5 or now - at > 8 then
        Evidence.stats.sharedRejected = Evidence.stats.sharedRejected + 1
        return false
    end
    local unit = Safe.String(safeField(record,'unit'))
    if unit ~= 'target' and unit ~= 'focus' and unit ~= 'targettarget'
        and unit ~= 'focustarget' then
        Evidence.stats.sharedRejected = Evidence.stats.sharedRejected + 1
        return false
    end
    local aura = {
        spellId=safeField(record,'spellId'),
        isHelpful=safeField(record,'isHelpful'),
        auraInstanceID=safeField(record,'auraInstanceID'),
        duration=safeField(record,'duration'),
        expirationTime=safeField(record,'expirationTime'),
    }
    -- Use the time of observation, not the later subscription/replay time;
    -- normal positive cast dedup then merges duplicates from both addons.
    local accepted = acceptHelpful(guid, aura, at,
        Safe.Boolean(safeField(record,'newApplication')) == true,
        'Portraits readable aura')
    if accepted then Evidence.stats.sharedAccepted = Evidence.stats.sharedAccepted + 1 end
    return accepted
end

function Evidence.ConnectShared(now)
    if not ns.EvidenceBus or type(ns.EvidenceBus.Subscribe) ~= 'function' then return false end
    return ns.EvidenceBus:Subscribe('bjarkiCC.cooldown-evidence',
        Evidence.OnSharedAura, currentTime(now))
end

local function locTimeMatches(known, started)
    if not started then return true end
    if not known.started then return started <= known.firstSeen + LOC_TIME_TOLERANCE end
    return math.abs(started - known.started) <= LOC_TIME_TOLERANCE
end

-- Native IDs identify an aura, not every activation of that aura. Conversely,
-- losing/gaining the optional ID does not itself prove another activation.
-- Keep one bounded application record per accepted identity, outside DR state:
-- Main can dispatch this consumer either before or after Observer.Scan.
local function continuingLoC(effectID, nativeKey, started, effects)
    local exact, latest
    for _, known in ipairs(Evidence.locApplications) do
        if known.spellID == effectID and nativeKey and nativeKey == known.nativeKey then
            if not latest or known.firstSeen > latest.firstSeen then latest = known end
            if started and locTimeMatches(known, started) then exact = known end
        end
    end
    if exact then return exact end
    if latest then
        -- Missing/stale timing cannot reset a known application. A newer
        -- explicit boundary can; its identity receives a separate claim.
        if not started or started <= (latest.started or latest.firstSeen) + LOC_TIME_TOLERANCE then
            return latest
        end
        -- A newer start may already have been counted while this native ID
        -- was hidden. Check that fallback before creating another witness.
    end
    local candidate, count = nil, 0
    for _, known in ipairs(Evidence.locApplications) do
        if known.spellID == effectID
            and not (nativeKey and known.nativeKey and nativeKey ~= known.nativeKey)
            and locTimeMatches(known, started) then
            candidate, count = known, count + 1
        end
    end
    if count > 1 then return nil, true end
    if candidate and nativeKey and not candidate.nativeKey then
        -- Do not let iteration order assign one of several current native
        -- IDs to the same fallback and make the others look newly applied.
        for key, other in pairs(effects) do
            if key ~= nativeKey and not other.fallbackIdentity
                and other.spellID == effectID and locTimeMatches(candidate, currentTime(other.appliedAt)) then
                return nil, true
            end
        end
    end
    return candidate
end

function Evidence.OnPlayerLoC(now)
    now = currentTime(now)
    if not now or not ns.Observer or not ns.Observer.ReadPlayerLoCEffects then return end
    Evidence.stats.locChecks = Evidence.stats.locChecks + 1
    local effects = ns.Observer.ReadPlayerLoCEffects(now)
    for i = #Evidence.locApplications, 1, -1 do
        if now - Evidence.locApplications[i].seen >= LOC_APPLICATION_TTL then
            table.remove(Evidence.locApplications, i)
        end
    end
    -- Native positives are processed first so an additional fallback in the
    -- same snapshot cannot create an order-dependent extra application.
    local keys = {}
    for key in pairs(effects or {}) do if type(key) == 'string' then keys[#keys+1] = key end end
    table.sort(keys, function(a,b)
        local af, bf = effects[a].fallbackIdentity == true, effects[b].fallbackIdentity == true
        if af ~= bf then return not af end
        return a < b
    end)
    for _, key in ipairs(keys) do
        local effect = effects[key]
        local effectID = integer(effect.spellID)
        local canonical = effectID and ns.Data.locCooldownEffects[effectID]
        local started = currentTime(effect.appliedAt)
        -- Match Model's admissible timestamp window before changing identity.
        -- A rejected old timestamp must not poison a later valid calibration.
        if canonical and (not started or now - started <= 120) then
            local nativeKey = not effect.fallbackIdentity and key or nil
            local known, ambiguous = continuingLoC(effectID, nativeKey, started, effects)
            if known then
                known.seen = now
                known.nativeKey = nativeKey or known.nativeKey
                if not known.started and started then
                    ns.model:RefineUnattributedTime(canonical, known.witness, started, now)
                    known.started = started
                end
                Evidence.stats.locDuplicateOrInvalid = Evidence.stats.locDuplicateOrInvalid + 1
            elseif not ambiguous and #Evidence.locApplications < MAX_LOC_APPLICATIONS then
                Evidence.nextLoCWitness = Evidence.nextLoCWitness + 1
                local witness = 'player-loc:'..effectID..':application:'..Evidence.nextLoCWitness
                Evidence.locApplications[#Evidence.locApplications+1] = {
                    spellID=effectID, nativeKey=nativeKey, started=started,
                    firstSeen=now, seen=now, witness=witness,
                }
                -- Per victim/application identity; NEVER synthesize a caster.
                if ns.model:WitnessUnattributedCooldown(canonical, started or now, now,
                    witness, ns.db.cooldownOverrides, started == nil) then
                    Evidence.stats.locAccepted = Evidence.stats.locAccepted + 1
                else
                    Evidence.stats.locDuplicateOrInvalid = Evidence.stats.locDuplicateOrInvalid + 1
                end
            else
                -- Capacity or unresolved identity fails closed until expiry or
                -- positive evidence disambiguates; it never guesses a caster.
                Evidence.stats.locDuplicateOrInvalid = Evidence.stats.locDuplicateOrInvalid + 1
            end
        end
    end
end

function Evidence.Init()
    Evidence.seenHelpful = {}
    Evidence.unknownHelpful = {}
    Evidence.helpfulApplications = {}
    Evidence.locApplications, Evidence.nextLoCWitness = {}, 0
    Evidence.stats = {
        helpfulEvents = 0, helpfulPositive = 0, helpfulAccepted = 0,
        helpfulDuplicate = 0, helpfulAlreadyTracked = 0, helpfulRejected = 0,
        locChecks = 0, locAccepted = 0, locDuplicateOrInvalid = 0,
        unknownRenewed = 0, unknownCapacityRejected = 0,
        helpfulTimingRefined = 0, helpfulProvenanceLinked = 0,
        sharedReceived = 0, sharedAccepted = 0,
        sharedRejected = 0,
    }
end
