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

local function eligibleToken(token, includeDerived)
    local unit = Safe.String(token)
    if unit == 'target' or unit == 'focus' then return unit end
    if includeDerived and (unit == 'targettarget' or unit == 'focustarget') then return unit end
    local suffix = unit and unit:match('^nameplate(%d+)$')
    if suffix and tonumber(suffix) and tonumber(suffix) <= 200 then return unit end
end

local function hostilePlayerGUID(unit, includeDerived)
    unit = eligibleToken(unit, includeDerived)
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
    for key, witness in pairs(Evidence.seenHelpful) do
        local stamp = witness.seen
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
        for key, witness in pairs(Evidence.seenHelpful) do
            local stamp = witness.seen
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

local function rememberSeen(key, identity, now)
    local witness = Evidence.seenHelpful[key]
    if witness then
        witness.seen = math.max(witness.seen, now)
    else
        -- A correction alias belongs to the occurrence that first admitted
        -- it. A later occurrence cannot acquire that historical ownership.
        Evidence.seenHelpful[key] = {seen=now, identity=identity}
    end
end

local function helpfulTime(aura, now)
    local expiry = currentTime(safeField(aura, 'expirationTime'))
    local duration = currentTime(safeField(aura, 'duration'))
    if expiry and expiry > 0 and duration and duration > 0 and duration <= 300 then
        local started = expiry - duration
        if started >= 0 and started <= now + HELPFUL_TIME_TOLERANCE
            and now - started <= duration + HELPFUL_TIME_TOLERANCE then
            return math.min(started,now), false, expiry
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
        if known.resetPending then
            local proposed = {generation=known.generation+1,lastActivation=now,
                resetAt=known.resetAt, resetSerial=known.resetSerial,
                resetInstance=known.resetInstance, resetExpiry=known.resetExpiry,
                resetSampleExpiry=known.resetSampleExpiry,
                resetSampleObservedAt=known.resetSampleObservedAt}
            return 'unknown-cycle:'..proposed.generation, proposed, true
        end
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
                local proposed = {generation=known.generation+1,lastActivation=now,
                    resetSerial=known.resetSerial}
                return 'unknown-cycle:'..proposed.generation, proposed, false, true
            end
            return nil
        end
        local proposed = {generation=known.generation+1,lastActivation=now,
            resetSerial=known.resetSerial}
        return 'unknown-cycle:'..proposed.generation, proposed, true
    else
        return nil -- another sighting is not another application
    end
end

local function rememberSample(record, expiry, now, compatible)
    if record and expiry
        and (not record.expiryObservedAt or now > record.expiryObservedAt
            or (now == record.expiryObservedAt and expiry >= record.expiry))
        and (not record.sampleObservedAt or now > record.sampleObservedAt
            or (now == record.sampleObservedAt and expiry >= record.sampleExpiry)) then
        -- Latest source precedence and replay protection have different jobs.
        -- Incompatible shorter reads cannot erase an already sampled boundary;
        -- accepted compatible timing can still correct it under these clocks.
        local prior = record.sampleReplayExpiry or record.sampleExpiry or expiry
        record.sampleReplayExpiry = compatible and expiry or math.max(prior, expiry)
        record.sampleExpiry, record.sampleObservedAt = expiry, now
    end
end

local function clearsResetSample(expiry, started, resetAt, sampleExpiry, sampleObservedAt)
    -- An already sampled tuple can infer a future start only within the
    -- tolerance accepted by helpfulTime. Shared source time may be ahead of
    -- the reset clock, so keep that window as well. A genuinely later start
    -- can clear the accepted endpoint without clearing an incompatible sample.
    return not sampleExpiry or expiry > sampleExpiry + HELPFUL_TIME_TOLERANCE
        or started > math.max(resetAt, sampleObservedAt or resetAt) + HELPFUL_TIME_TOLERANCE
end

local function rememberHelpful(guid, canonical, key, instance, now, activatedAt, expiry)
    local applicationKey = guid..':'..canonical
    local known = Evidence.helpfulApplications[applicationKey]
    if not known or known.identity ~= key then
        known = {identity=key}
        Evidence.helpfulApplications[applicationKey] = known
    end
    known.instance = instance or known.instance
    -- Keep this native ID's last compatible endpoint with its bounded witness,
    -- even when an intervening untimed application replaces reset metadata.
    -- This is timing evidence only; the witness's original owner never changes.
    local nativeKey = known.instance and (guid..':'..canonical..':instance:'..known.instance)
    local native = nativeKey and Evidence.seenHelpful[nativeKey]
    if native and expiry and (not native.expiryObservedAt or now > native.expiryObservedAt
        or (now == native.expiryObservedAt and expiry >= native.expiry)) then
        native.expiry, native.expiryObservedAt = expiry, now
    end
    if expiry and (not known.expiryObservedAt or now > known.expiryObservedAt
        or (now == known.expiryObservedAt and expiry >= known.expiry)) then
        -- Endpoint corrections have their own observation clock. An older
        -- shared report cannot roll back the current compatible boundary;
        -- equal-time disagreement conserves the later endpoint.
        known.expiry, known.expiryObservedAt = expiry, now
    end
    rememberSample(known, expiry, now, true)
    rememberSample(native, expiry, now, true)
    known.seen = math.max(known.seen or now, now)
    if activatedAt then
        -- Strong identities also establish the last activation for later
        -- anonymous added-aura events. Losing their identity must not open a
        -- fresh anonymous cycle or let an old cycle bypass the renewal gate.
        local unknown = Evidence.unknownHelpful[applicationKey]
        if unknown then
            unknown.lastActivation = activatedAt
            unknown.resetPending = nil
        else
            local count = 0
            for _ in pairs(Evidence.unknownHelpful) do count = count + 1 end
            if count < MAX_UNKNOWN then
                Evidence.unknownHelpful[applicationKey] = {generation=0,lastActivation=activatedAt}
            end
        end
    end
end

-- Corroborating a cast does not create an activation, but its associated aura
-- still needs bounded identity/sample custody. Never reassign an old witness
-- or replace a native ID that already belongs to this occurrence.
local function rememberCastHelpful(guid, canonical, row, key, witness, instance,
    started, approximate, expiry, now, proposedUnknown)
    if not row or row.evidenceSource ~= 'cast' or type(row.evidenceIdentity) ~= 'string'
        or now >= row.started + row.duration then return false end
    local owner = row.evidenceIdentity
    local applicationKey = guid..':'..canonical
    local application = Evidence.helpfulApplications[applicationKey]
    if application and application.identity ~= owner then return false end
    local ownedNative = instance and application and application.instance == instance
    if witness and witness.identity ~= owner and not ownedNative then return false end
    local priorInstance = application and application.instance
        or tonumber(owner:match(':instance:(%d+)$'))
    if instance and priorInstance and instance ~= priorInstance then return false end
    local compatibleExpiry = not approximate
        and (math.abs(started - row.started) <= HELPFUL_TIME_TOLERANCE
            or (application and application.expiry and expiry
                and math.abs(expiry - application.expiry) <= HELPFUL_TIME_TOLERANCE)) and expiry or nil
    -- An unaccepted anonymous proposal is not an extra identity cycle. Reserve
    -- its generation only when Model actually chose it as the cast's owner.
    if not proposedUnknown or key == owner then rememberSeen(key, owner, now) end
    rememberHelpful(guid, canonical, owner, instance, now, row.started, compatibleExpiry)
    if proposedUnknown and key == owner then
        local known = Evidence.unknownHelpful[applicationKey]
        if known then known.generation = math.max(known.generation, proposedUnknown.generation) end
    end
    application = Evidence.helpfulApplications[applicationKey]
    rememberSample(application, expiry, now)
    local nativeKey = application.instance and (applicationKey..':instance:'..application.instance)
    rememberSample(nativeKey and Evidence.seenHelpful[nativeKey], expiry, now)
    pruneSeen(now)
    return true
end

-- Optional identity fields can disappear between sensors. Keep the original
-- claim key for an active application, while remembering any stronger ID that
-- becomes readable. A different readable ID, later exact start or explicit
-- new application still takes the normal new-witness path.
local function continuingHelpful(guid, canonical, instance, started, approximate, now, newApplication, expiry)
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
        elseif math.abs(started - row.started) > HELPFUL_TIME_TOLERANCE
            and not (known and known.identity == row.evidenceIdentity and known.expiry and expiry
                and math.abs(expiry - known.expiry) <= HELPFUL_TIME_TOLERANCE) then
            -- Losing an optional ID can change expiry-duration without moving
            -- the application endpoint. Preserve the precise occurrence.
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
    local started, approximate, expiry = helpfulTime(aura, now)
    local application = Evidence.helpfulApplications[guid..':'..canonical]
    local current = activeHelpful(guid, canonical, now)
    local caster = ns.model.casters[guid]
    local sampleOwner = caster and caster.cooldowns[canonical]
    if not approximate and instance and sampleOwner and application
        and now < sampleOwner.started + sampleOwner.duration
        and application.identity == sampleOwner.evidenceIdentity and instance == application.instance then
        -- A readable boundary may be a correction rather than another activation.
        -- Keep its observation separate from accepted timing, so another sensor
        -- cannot replay it as a new occurrence across an equal-time reset.
        -- Cast promotion preserves this occurrence's sample custody, but does
        -- not grant the aura any authority to revise the successful-cast clock.
        rememberSample(application, expiry, now)
        -- Retain this ID's sampled boundary through intervening untimed uses.
        -- Its scalar history has the same cap and lifetime as its native witness.
        rememberSample(Evidence.seenHelpful[guid..':'..canonical..':instance:'..instance], expiry, now)
    end
    if not newApplication and not instance and not approximate and current and not current.timingEstimated
        and application and application.identity == current.evidenceIdentity
        and application.expiry and math.abs(expiry - application.expiry) > HELPFUL_TIME_TOLERANCE
        and application.expiryObservedAt and (now < application.expiryObservedAt
            or (now == application.expiryObservedAt and expiry < application.expiry))
        and math.abs(started - current.started) > HELPFUL_TIME_TOLERANCE then
        -- A delayed ordinary report cannot replace fresher compatible timing
        -- merely because ID loss and duration imply another application start.
        -- Equal-time disagreement conserves the later endpoint as below;
        -- genuinely newer start AND endpoint still prove a new occurrence.
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        return false
    end
    local known = Evidence.unknownHelpful[guid..':'..canonical]
    if caster and caster.helpfulResetBlocked and caster.helpfulResetBlocked[canonical] then
        Evidence.stats.unknownCapacityRejected = Evidence.stats.unknownCapacityRejected + 1
        return false -- Required reset barrier could not fit; unrelated IDs remain eligible.
    end
    local resetAt = known and known.resetAt
    if resetAt and (now < resetAt or (not approximate and started < resetAt)
        or (known.resetPending and approximate and not newApplication)) then
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        return false
    end
    -- A reused native ID needs a genuinely newer application clock. Losing
    -- that optional ID on an ordinary sighting cannot turn a duration-only
    -- correction into a new occurrence either. Independent added positives
    -- and distinct readable IDs still follow their existing admission paths.
    if resetAt and known.resetPending and not approximate and known.resetExpiry
        and expiry <= known.resetExpiry + HELPFUL_TIME_TOLERANCE
        and ((instance and instance == known.resetInstance) or (not instance and not newApplication)) then
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        return false
    end
    local resetTimedApplication = resetAt and known.resetPending
        and not approximate and started > resetAt
    local resetApplication = resetAt and known.resetPending
        and (newApplication == true or resetTimedApplication)
    pruneSeen(now)
    local continuing = continuingHelpful(guid, canonical, instance, started,
        approximate, now, newApplication == true, expiry)
    if resetAt and not instance and not approximate and not newApplication
        and (not continuing or current.timingEstimated)
        and not clearsResetSample(expiry, started, resetAt,
            known.resetSampleExpiry, known.resetSampleObservedAt) then
        -- Losing an optional ID cannot make an already sampled tuple fresh.
        -- This also guards precision offered to an independent untimed use
        -- after resetPending was consumed. Established precise corrections,
        -- explicit added positives and genuinely later timing keep their paths.
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        return false
    end
    local identity, preciseAlias, proposedUnknown, renewedUnknown, castCorroborationOnly
    if instance then
        identity = 'instance:'..instance
        local nativeWitness = Evidence.seenHelpful[guid..':'..canonical..':'..identity]
        if resetApplication and not approximate and instance == known.resetInstance and known.resetExpiry
            and expiry > known.resetExpiry + HELPFUL_TIME_TOLERANCE
            and clearsResetSample(expiry, started, resetAt, known.resetSampleExpiry, known.resetSampleObservedAt)
            and nativeWitness
            and clearsResetSample(expiry, started, resetAt,
                nativeWitness.sampleReplayExpiry or nativeWitness.sampleExpiry, nativeWitness.sampleObservedAt) then
            -- Retain the original native-ID key. An ordered added positive
            -- can prove reset/use even at equal GetTime; an ordinary sighting
            -- still needs a later start. The bounded reset cycle also keeps
            -- distinct accepted uses from colliding in one rounded time bucket.
            identity = 'reset-cycle:'..known.resetSerial..':instance:'..instance
        end
    elseif not approximate then
        identity = 'start:'..math.floor(started*10+.5)
        preciseAlias = guid..':'..canonical..':'..identity
        local resetIdentity = known and known.resetSerial
            and ('reset-cycle:'..known.resetSerial..':'..identity)
        if resetApplication or (resetIdentity and current
            and current.evidenceIdentity == guid..':'..canonical..':'..resetIdentity) then
            -- Reset/use ordering separates occurrences even at equal GetTime.
            -- Keep the original precise alias; namespace only the independently
            -- positive post-reset occurrence inside the existing bounded set.
            identity = resetIdentity
        end
    elseif not continuing then
        identity, proposedUnknown, renewedUnknown, castCorroborationOnly =
            unknownIdentity(guid, canonical, now, newApplication == true)
        if not identity then
            Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
            return false
        end
    end
    local rawKey = identity and guid..':'..canonical..':'..identity
    local rawWitness = rawKey and Evidence.seenHelpful[rawKey]
    local oldAlias = preciseAlias and Evidence.seenHelpful[preciseAlias]
    if continuing and not newApplication and oldAlias and oldAlias.identity ~= continuing
        and known and known.resetExpiry and application and application.identity == continuing
        and application.expiry and application.expiry > known.resetExpiry + HELPFUL_TIME_TOLERANCE
        and expiry <= known.resetExpiry + HELPFUL_TIME_TOLERANCE then
        -- A same-bucket old correction still carries the pre-reset endpoint.
        -- Do not let the current reset namespace grant it endpoint ownership;
        -- fresh corrections to the new occurrence keep their ordinary path.
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        return false
    end
    if continuing and rawWitness and rawWitness.identity ~= continuing
        and not (instance and application and application.identity == continuing
            and application.instance == instance)
        and not (instance and (rawWitness.identity == rawKey or (known and instance == known.resetInstance))
            and current and current.timingEstimated
            and not approximate and resetAt and started >= resetAt
            and (not known.resetExpiry or expiry > known.resetExpiry + HELPFUL_TIME_TOLERANCE)
            and (instance ~= known.resetInstance or clearsResetSample(expiry, started, resetAt,
                known.resetSampleExpiry, known.resetSampleObservedAt))
            and (not rawWitness.expiry or expiry > rawWitness.expiry + HELPFUL_TIME_TOLERANCE)
            and clearsResetSample(expiry, started, resetAt,
                rawWitness.sampleReplayExpiry or rawWitness.sampleExpiry, rawWitness.sampleObservedAt)) then
        -- An independently accepted post-reset estimate can still learn a
        -- primary native ID's first precise clock, or genuinely later known
        -- boundaries. Its old endpoint and correction aliases cannot lend
        -- historical ownership to the independently accepted occurrence.
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        return false -- Historical correction/native aliases cannot change ownership.
    end
    local key = continuing or rawKey
    if sampleOwner and sampleOwner.evidenceSource == 'cast' and application
        and application.identity == sampleOwner.evidenceIdentity and not approximate
        and started <= sampleOwner.started + HELPFUL_TIME_TOLERANCE
        and application.expiry and math.abs(expiry - application.expiry) <= HELPFUL_TIME_TOLERANCE
        and rememberCastHelpful(guid, canonical, sampleOwner, key, rawWitness,
            instance, started, approximate, expiry, now, proposedUnknown) then
        -- A promoted cast can postdate its aura's original start. Its already
        -- accepted endpoint still proves continuity when a native ID arrives;
        -- the older aura start must never replace the successful-cast clock.
        if ns.model:CorroborateHelpful(guid, canonical, sampleOwner.evidenceIdentity, now, origin) then
            Evidence.stats.helpfulProvenanceLinked = Evidence.stats.helpfulProvenanceLinked + 1
        end
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        return false
    end
    -- Expired keys are pruned BEFORE deduplication; an exact identity can only
    -- be replayed after TTL if the API truly reports it again. Anonymous
    -- reapplications still demand a positive added-aura event (above).
    if continuing or Evidence.seenHelpful[key] then
        Evidence.stats.helpfulDuplicate = Evidence.stats.helpfulDuplicate + 1
        if sampleOwner and sampleOwner.evidenceSource == 'cast' and rawWitness
            and (rawWitness.identity == sampleOwner.evidenceIdentity
                or (instance and application and application.identity == sampleOwner.evidenceIdentity
                    and application.instance == instance)) then
            rememberCastHelpful(guid, canonical, sampleOwner, key, rawWitness,
                instance, started, approximate, expiry, now, proposedUnknown)
        end
        if sampleOwner and sampleOwner.evidenceSource == 'cast'
            and now < sampleOwner.started + sampleOwner.duration and instance and not approximate then
            -- Rejected native reports retain their own sampled history only.
            -- They cannot replace the current application's ID or endpoint.
            rememberSample(Evidence.seenHelpful[guid..':'..canonical..':instance:'..instance], expiry, now)
        end
        local timingRefined = false
        if continuing then
            local row = activeHelpful(guid, canonical, now)
            local application = Evidence.helpfulApplications[guid..':'..canonical]
            if row and row.timingEstimated and not approximate
                and ((instance and (not application or application.identity ~= key or application.instance ~= instance))
                    or (rawKey and not rawWitness)) then
                -- A rejected precise report must not commit a new native ID or
                -- correction alias that would authorize its historical readings.
                timingRefined = ns.model.RefineHelpfulTime
                    and ns.model:RefineHelpfulTime(guid,canonical,key,started,now,origin) == true
                if not timingRefined then return false end
            end
            local compatibleExpiry = not approximate and row and not row.timingEstimated
                and (math.abs(started - row.started) <= HELPFUL_TIME_TOLERANCE
                    or (application and application.identity == key and application.expiry and expiry
                        and math.abs(expiry - application.expiry) <= HELPFUL_TIME_TOLERANCE)) and expiry or nil
            -- A readable endpoint can correct this precise application even
            -- when no first-sighting timestamp refinement remains possible.
            -- Same ID alone does not bind a different application clock.
            rememberHelpful(guid, canonical, key, instance, now, nil, compatibleExpiry)
            -- A stronger alias must also remain deduplicated if an older
            -- sensor reports it after a later genuine application.
            if rawKey then rememberSeen(rawKey, key, now) end
            pruneSeen(now)
        end
        -- A later exact timestamp can refine a first-sighting estimate, but
        -- only for this same aura identity. Duplicate sensors add provenance.
        if ns.model.CorroborateHelpful
            and ns.model:CorroborateHelpful(guid,canonical,key,now,origin) then
            Evidence.stats.helpfulProvenanceLinked = Evidence.stats.helpfulProvenanceLinked + 1
        end
        if timingRefined or (not approximate and ns.model.RefineHelpfulTime
            and ns.model:RefineHelpfulTime(guid,canonical,key,started,now,origin)) then
            rememberHelpful(guid, canonical, key, instance, now, started, expiry)
            pruneSeen(now)
            Evidence.stats.helpfulTimingRefined = Evidence.stats.helpfulTimingRefined + 1
        end
        return false
    end
    Evidence.stats.helpfulPositive = Evidence.stats.helpfulPositive + 1
    local accepted, corroborated = ns.model:Cast(guid, nil, canonical, started,
        'helpful-aura:'..key, false, ns.db.cooldownOverrides,
        'helpful-aura', approximate, {
            identity=key, origin=origin, observedAt=now,
            newApplication=(newApplication == true or resetTimedApplication) and not castCorroborationOnly,
            resetAt=resetApplication and resetAt or nil,
        })
    local associated = not accepted and corroborated and rememberCastHelpful(guid, canonical,
        corroborated, key, rawWitness, instance, started, approximate, expiry, now, proposedUnknown)
    -- Wait for Model's ownership decision before assigning a fresh alias.
    -- Rejected strong keys stay deduplicated; unaccepted anonymous proposals
    -- remain available for the next genuinely admitted occurrence.
    if not proposedUnknown and not associated then
        rememberSeen(key, key, now)
        if not accepted and instance and not approximate and sampleOwner
            and sampleOwner.evidenceSource == 'cast' and now < sampleOwner.started + sampleOwner.duration then
            rememberSample(Evidence.seenHelpful[guid..':'..canonical..':instance:'..instance], expiry, now)
        end
        pruneSeen(now)
    end
    if accepted then
        if proposedUnknown then
            Evidence.unknownHelpful[guid..':'..canonical] = proposedUnknown
            rememberSeen(key, key, now)
            if renewedUnknown then
                Evidence.stats.unknownRenewed = Evidence.stats.unknownRenewed + 1
            end
        end
        rememberHelpful(guid, canonical, key, instance, now, started, expiry)
        pruneSeen(now)
        Evidence.stats.helpfulAccepted = Evidence.stats.helpfulAccepted + 1
    else
        Evidence.stats.helpfulAlreadyTracked = Evidence.stats.helpfulAlreadyTracked + 1
    end
    return accepted == true
end

-- Observer calls this only AFTER Model accepts the successful cast. Keep the
-- reset barrier inside the existing bounded continuity records; never erase
-- native witness keys or let an ordinary sighting spend a reset permission.
function Evidence.OnAcceptedCast(guid, spellID, now)
    local canonical = ns.Data.castToSpell[spellID] or spellID
    local known = Evidence.unknownHelpful[guid..':'..canonical]
    if known then
        known.lastActivation, known.resetPending = now, nil
    end
    local applicationKey = guid..':'..canonical
    local application = Evidence.helpfulApplications[applicationKey]
    local caster = ns.model.casters[guid]
    local current = caster and caster.cooldowns[canonical]
    if application and (not current or current.evidenceIdentity ~= application.identity) then
        -- A distinct successful cast supersedes that aura application. Its old
        -- endpoint cannot later authorize a reused-ID refresh across a reset.
        Evidence.helpfulApplications[applicationKey] = nil
    end
    local reset = ns.Data.resets[spellID] or ns.Data.resets[canonical]
    for _, resetID in ipairs(reset or {}) do
        if ns.Data.helpfulCooldownAuras[resetID] == resetID then
            local key = guid..':'..resetID
            known = Evidence.unknownHelpful[key]
            if not known then
                local count = 0
                for _ in pairs(Evidence.unknownHelpful) do count = count + 1 end
                if count < MAX_UNKNOWN then
                    known = {generation=0,lastActivation=now}
                    Evidence.unknownHelpful[key] = known
                else
                    -- Preserve the failed guard only for this fixed reset family
                    -- on the already capped caster record. Do not evict another
                    -- activation anchor or suppress unrelated strong identities.
                    local caster = ns.model.casters[guid]
                    if caster then
                        caster.helpfulResetBlocked = caster.helpfulResetBlocked or {}
                        caster.helpfulResetBlocked[resetID] = true
                    end
                end
            end
            if known then
                local application = Evidence.helpfulApplications[key]
                known.resetAt, known.resetPending = now, true
                known.resetSerial = (known.resetSerial or 0) + 1
                known.resetInstance = application and application.instance
                known.resetExpiry = application and application.expiry
                known.resetSampleExpiry = application and (application.sampleReplayExpiry or application.sampleExpiry)
                known.resetSampleObservedAt = application and application.sampleObservedAt
            end
        end
    end
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

-- World entry resets the consumer after another addon's handler may already
-- have published its current snapshot. Re-read the four fixed bindings once
-- after that reset; replaying recent bus history cannot prove world freshness.
-- Derived tokens are eligible only here, not in the general event/poll paths.
function Evidence.OnWorldEntered(now)
    now = currentTime(now)
    if not now then return end
    for _, unit in ipairs({'target','focus','targettarget','focustarget'}) do
        local guid = hostilePlayerGUID(unit, true)
        if guid then exactHelpful(unit, guid, now) end
    end
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
