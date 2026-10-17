local _, ns = ...

-- Pure state: inputs must already be readable, ordinary Lua values. Client API
-- calls and secret-value guards belong to Observer, before any input gets here.
local Model = {}
Model.__index = Model
ns.Model = Model

local MAX_UNITS = 128
local MAX_CASTERS = 128
local MAX_CAST_IDS = 128
local CAST_ID_TTL = 120
local FALLBACK_DEDUP_SECONDS = 0.15
local APPLICATION_EPSILON = 0.001 -- Ignore sub-millisecond API rounding changes.
local MAX_DURATION_BASELINES = 64
local DURATION_QUIET_SECONDS = 20 -- Conservative Classic maximum; not a fixed server rule.
local DURATION_RESET_MINIMUM = 15 -- Only reconcile within/after the documented uncertainty range.

local function trimOldest(records, maximum)
    local count = 0
    for _ in pairs(records) do count = count + 1 end
    while count > maximum do
        local oldestKey, oldestTime
        for key, record in pairs(records) do
            local stamp = type(record) == "table" and record.seen or record
            if not oldestTime or stamp < oldestTime then oldestKey, oldestTime = key, stamp end
        end
        if not oldestKey then break end
        records[oldestKey] = nil
        count = count - 1
    end
end

function Model.New(applicationSeconds, stageResetSeconds, resetOnApplication)
    local order = {}
    for index, category in ipairs(ns.Data.categories) do order[category.key] = index end
    return setmetatable({
        resetSeconds = applicationSeconds or 20,
        resetOnApplication = resetOnApplication == true,
        stageResetSeconds = stageResetSeconds or 18,
        units = {},
        estimates = {}, -- Own casts are predictions, never observed applications.
        casters = {},
        categoryOrder = order,
    }, Model)
end

local function inWindow(state, now, resetSeconds)
    return state and now < state.appliedAt + resetSeconds
end

local function stageInWindow(state, now)
    return state and (state.stageResetPending or (state.stageResetAt and now < state.stageResetAt))
end

local function recordEnd(state, effect, now)
    if not state then return end
    local endedAt = effect.endedAt or math.min(now, effect.expires or now)
    if not state.lastEndedAt or endedAt > state.lastEndedAt then state.lastEndedAt = endedAt end
    return endedAt
end

local function updateStageClocks(unit, effects, now, stageResetSeconds, applicationSeconds)
    for _, state in pairs(unit.categories) do
        state.activeCount = 0
        state.stageResetPending = false
        state.stageEndAt = state.lastEndedAt
        state.stageResetSource = state.lastEndedAt and "observed-end" or nil
    end
    for _, effect in pairs(effects) do
        local state = unit.categories[effect.category]
        if state then
            local endedAt = effect.endedAt or effect.expires
            if not effect.endedAt and (not effect.expires or now < effect.expires) then
                state.activeCount = state.activeCount + 1
            end
            if endedAt then
                if not state.stageEndAt or endedAt > state.stageEndAt then
                    state.stageEndAt = endedAt
                    state.stageResetSource = effect.endedAt and "observed-end" or "predicted-end"
                end
            else
                state.stageResetPending = true
            end
        end
    end
    for _, state in pairs(unit.categories) do
        state.stageResetAt = not state.stageResetPending and state.stageEndAt
            and state.stageEndAt + stageResetSeconds or nil
        if state.stageResetPending then state.stageResetSource = nil end
        if applicationSeconds then
            state.stageResetAt = state.appliedAt + applicationSeconds
            state.stageResetPending = false
            state.stageResetSource = "application"
        end
    end
end

local function predecessor(state)
    if not state then return nil end
    -- One flat predecessor lets a later readable timestamp repair the latest
    -- provisional application. Never copy previousApplication recursively.
    return {
        stage = state.stage, inferredStage = state.inferredStage,
        appliedAt = state.appliedAt, spellID = state.spellID,
        applicationKey = state.applicationKey, timeEstimated = state.timeEstimated,
        uncertain = state.uncertain, activeCount = 0,
        confirmationStage = state.confirmationStage,
        confirmationSentAt = state.confirmationSentAt,
        confirmationAppliedAt = state.confirmationAppliedAt,
        witness = state.witness,
        lastEndedAt = state.lastEndedAt, stageEndAt = state.stageEndAt,
        stageResetAt = state.stageResetAt, stageResetPending = state.stageResetPending,
        stageResetSource = state.stageResetSource,
        observedQuietSince = state.observedQuietSince,
        durationContext = state.durationContext, reportedDurationWitness = state.reportedDurationWitness,
        resetEvidence = state.resetEvidence, resetBaselineDuration = state.resetBaselineDuration,
        resetPreviousStage = state.resetPreviousStage, resetBaselineSource = state.resetBaselineSource,
    }
end

local function applicationTime(effect, now)
    local start = effect.appliedAt
    if type(start) == "number" and start == start and start >= 0 and start <= now then return start end
end

local function refreshedApplication(previous, effect, start)
    -- An untimed identity already represents one observed application. Its
    -- first readable timestamp calibrates that application, even when the
    -- client reports it after our local first-seen fallback. Only two known
    -- application timestamps can establish a same-identity refresh.
    if not previous or not previous.appliedAt or not start then return false end
    if start <= previous.appliedAt + APPLICATION_EPSILON then return false end
    if effect.applicationSource == "loc" then
        -- Aura expiration-duration and explicit LoC starts are different
        -- clocks. The first LoC start calibrates this identity; only another
        -- explicit start can establish a same-identity LoC refresh.
        return previous.applicationSource == "loc"
    end
    -- A duration correction can move expiration-duration without another CC.
    -- A derived refresh needs both boundaries to change, from the same sensor.
    -- Diminished CC can end earlier even though its application is newer.
    return previous.applicationSource == "aura" and effect.applicationSource == "aura"
        and previous.expires and effect.expires
        and math.abs(effect.expires - previous.expires) > APPLICATION_EPSILON
end

local function durationContext(unit, state, effects, key, category)
    local overlap = false
    for otherKey, other in pairs(effects or {}) do
        if otherKey ~= key and other.category == category then overlap = true; break end
    end
    -- This is the state BEFORE this application. Late timing/duration must not
    -- compare against the new application's own end or quiet history.
    return {
        coverageEpoch = unit.durationEpoch, completeSince = unit.completeSince,
        priorEnd = state and state.stageEndAt,
        priorEndObserved = state and state.stageResetSource == "observed-end" or false,
        quietSince = state and state.observedQuietSince,
        pending = state and state.stageResetPending or false,
        overlap = overlap or (state and state.activeCount > 0) or false,
        noPriorCategory = state == nil,
    }
end

local function rememberAuraDuration(state, effect, preciseStart)
    local context = state and state.durationContext
    if not context or context.initialAuraDuration or effect.applicationSource ~= "aura"
        or not preciseStart or preciseStart >= math.huge
        or state.spellID ~= effect.spellID
        or math.abs(state.appliedAt - preciseStart) > APPLICATION_EPSILON
        or (state.witness and state.witness.applicationSource == "loc") then return end
    local expires = effect.expires
    if type(expires) ~= "number" or expires ~= expires or expires >= math.huge then return end
    local duration = expires - preciseStart
    if duration <= 0 or duration > 120 then return end
    -- This interval can only veto inconsistent baseline learning. It never
    -- teaches a full duration or infers a diminished stage. Freeze the first
    -- coherent interval, including one that becomes readable after identity.
    context.initialAuraDuration = duration
end

local function auraDurationConsistent(context, duration)
    return not context.initialAuraDuration
        or math.abs(duration - context.initialAuraDuration) <= APPLICATION_EPSILON
end

local function matchesDurationCandidate(state, candidate)
    return state and state.stage == candidate.step and state.spellID == candidate.spellID
        and state.applicationKey == candidate.applicationKey
        and math.abs(state.appliedAt - candidate.appliedAt) <= APPLICATION_EPSILON
end

local function categoryHasSibling(effects, key, category)
    for otherKey, other in pairs(effects or {}) do
        if otherKey ~= key and other.category == category then return true end
    end
    return false
end

local function chainReplacementEnd(unit, state, previous, effect, effects, key, start, complete)
    -- A real aura identity can stay present across an explicit LoC refresh.
    -- Its accepted old duration can prove a nonoverlapping successor for the
    -- halving chain only. It cannot prove observed absence or a stage reset.
    local candidate = unit.durationLadders[effect.category]
    if not complete or not state or not candidate or not start
        or type(key) ~= "string" or not key:match("^a:%d+$")
        or unit.effects[key] ~= previous or state.witness ~= previous
        or previous.endedAt or previous.fallbackIdentity or effect.fallbackIdentity
        or previous.applicationSource ~= "loc" or effect.applicationSource ~= "loc"
        or not previous.appliedAt or not previous.expires
        or state.applicationKey ~= key or state.spellID ~= effect.spellID
        or previous.spellID ~= effect.spellID or previous.category ~= effect.category
        or math.abs(state.appliedAt - previous.appliedAt) > APPLICATION_EPSILON
        or state.stageResetPending or state.inferredStage
        or candidate.coverageEpoch ~= unit.durationEpoch
        or not matchesDurationCandidate(state, candidate) then return end
    local duration = state.reportedDurationWitness
    if type(duration) ~= "number" or duration ~= duration or duration <= 0 or duration > 120
        or type(previous.expires) ~= "number" or previous.expires ~= previous.expires
        or previous.expires >= math.huge
        or math.abs(previous.expires - previous.appliedAt - duration) > APPLICATION_EPSILON
        or start < previous.expires or start - previous.expires >= DURATION_RESET_MINIMUM then return end
    if categoryHasSibling(unit.effects, key, effect.category)
        or categoryHasSibling(effects, key, effect.category) then return end
    return previous.expires
end

local function observeHalvingChain(unit, state, effect, start, duration, now, context)
    local category = effect.category
    if unit.durationBaselines[effect.spellID] then
        unit.durationLadders[category] = nil
        return
    end
    local candidate = unit.durationLadders[category]
    if state.inferredStage or not auraDurationConsistent(context, duration) then
        unit.durationLadders[category] = nil
        return
    end
    if state.stage == 1 then
        unit.durationLadders[category] = {
            spellID = effect.spellID, firstDuration = duration, step = 1,
            applicationKey = state.applicationKey, appliedAt = start,
            coverageEpoch = unit.durationEpoch, seen = now,
        }
        trimOldest(unit.durationLadders, MAX_DURATION_BASELINES)
        return
    end
    local prior = state.previousApplication
    local connected = context.chainReplacementEnd
        and start >= context.chainReplacementEnd
        and start - context.chainReplacementEnd < DURATION_RESET_MINIMUM
    if not connected then
        connected = context.priorEndObserved and context.priorEnd and context.quietSince
            and start >= context.priorEnd and start >= context.quietSince
            and start - context.priorEnd < DURATION_RESET_MINIMUM
            and start - context.quietSince < DURATION_RESET_MINIMUM
    end
    if not candidate or candidate.spellID ~= effect.spellID
        or candidate.coverageEpoch ~= unit.durationEpoch
        or state.stage ~= candidate.step + 1 or candidate.step >= 3
        or not matchesDurationCandidate(prior, candidate) or prior.inferredStage
        or not connected
        or math.abs(duration - candidate.firstDuration / (2 ^ candidate.step)) > APPLICATION_EPSILON then
        unit.durationLadders[category] = nil
        return
    end
    candidate.step, candidate.applicationKey, candidate.appliedAt, candidate.seen =
        candidate.step + 1, state.applicationKey, start, now
    if candidate.step == 3 then
        -- Three observed nonzero hits corroborate the first interval under the
        -- provisional full/half/quarter/immune rules. Never derive a current
        -- stage from ratios or treat two shortened hits as a full baseline.
        unit.durationBaselines[effect.spellID] = {
            duration = candidate.firstDuration, seen = now, source = "observed-halving-chain",
        }
        trimOldest(unit.durationBaselines, MAX_DURATION_BASELINES)
        unit.durationLadders[category] = nil
        state.uncertain = true
    end
end

local function reconcileDuration(unit, state, effect, preciseStart, now, complete)
    if not state or state.reportedDurationWitness or not complete
        or effect.applicationSource ~= "loc" or not preciseStart
        or math.abs(state.appliedAt - preciseStart) > APPLICATION_EPSILON then return end
    local duration, expires = effect.reportedDuration, effect.expires
    if type(duration) ~= "number" or duration ~= duration or duration <= 0 or duration > 120
        or type(expires) ~= "number" or expires ~= expires
        or math.abs(expires - preciseStart - duration) > APPLICATION_EPSILON then return end
    -- Only the first coherent, explicitly reported duration belongs to this
    -- decision. A later duration-only edit must never masquerade as a reset.
    state.reportedDurationWitness = duration
    local context = state.durationContext
    if not context or context.coverageEpoch ~= unit.durationEpoch
        or not context.completeSince or preciseStart < context.completeSince
        or context.pending or context.chainReplacementInvalid then
        unit.durationLadders[effect.category] = nil
        return
    end
    if context.chainReplacementEnd then
        -- This separate entry can connect only an existing observed chain.
        -- It never reaches quiet baseline learning or stage reset correction.
        observeHalvingChain(unit, state, effect, preciseStart, duration, now, context)
        return
    end
    if context.overlap then
        unit.durationLadders[effect.category] = nil
        return
    end
    local observedQuiet = context.noPriorCategory
        or (context.priorEndObserved and context.priorEnd
            and preciseStart - context.priorEnd >= DURATION_QUIET_SECONDS
            and context.quietSince and preciseStart - context.quietSince >= DURATION_QUIET_SECONDS)
    if state.stage == 1 and not state.inferredStage
        and auraDurationConsistent(context, duration)
        and preciseStart - context.completeSince >= DURATION_QUIET_SECONDS and observedQuiet then
        unit.durationBaselines[effect.spellID] = {duration = duration, seen = now, source = "quiet-observation"}
        trimOldest(unit.durationBaselines, MAX_DURATION_BASELINES)
        unit.durationLadders[effect.category] = nil
        return
    end
    observeHalvingChain(unit, state, effect, preciseStart, duration, now, context)
    local baseline = unit.durationBaselines[effect.spellID]
    if state.stage > 1 and baseline and context.priorEndObserved and context.priorEnd
        and preciseStart - context.priorEnd >= DURATION_RESET_MINIMUM
        and context.quietSince and preciseStart - context.quietSince >= DURATION_RESET_MINIMUM
        and math.abs(duration - baseline.duration) <= APPLICATION_EPSILON then
        state.resetPreviousStage = state.stage
        state.stage, state.inferredStage = 1, nil
        state.confirmationStage, state.confirmationSentAt, state.confirmationAppliedAt = nil, nil, nil
        state.resetEvidence, state.resetBaselineDuration = "matching-full-duration", baseline.duration
        state.resetBaselineSource = baseline.source
        state.uncertain = true
    end
end

function Model:Observe(guid, effects, now, complete)
    if not guid then return end
    local unit = self.units[guid]
    if not unit then
        unit = {seen = now, effects = {}, categories = {}, durationBaselines = {}, durationLadders = {}, durationEpoch = 0}
        self.units[guid] = unit
    end
    unit.seen = now
    -- Keep the application clock separate from stage reset after the last CC
    -- ends. A delayed readable witness chains by application time, not arrival.
    -- Each category also has at most one flat predecessor for timing correction.
    -- Category count is fixed by Data; retained GUIDs have the MAX_UNITS cap.

    if complete then
        if not unit.completeSince then unit.completeSince = now end
    else
        -- An unreadable/partial snapshot cannot establish a removal or preserve
        -- the earlier history proof. It also cannot change an observed timer.
        unit.completeSince = nil
        unit.durationBaselines = {}
        unit.durationLadders = {}
        unit.durationEpoch = unit.durationEpoch + 1
        for _, state in pairs(unit.categories) do
            state.uncertain = true
            state.observedQuietSince = nil
        end
    end

    -- Preserve evidence from the previous complete snapshot. Current removal
    -- discovery may backdate a predicted end, but cannot create prior observed
    -- quiet time for this new application.
    local priorDurationHistory = {}
    for category, state in pairs(unit.categories) do
        local context = state.durationContext
        if context and context.chainReplacementEnd and not state.reportedDurationWitness
            and (categoryHasSibling(unit.effects, state.applicationKey, category)
                or categoryHasSibling(effects, state.applicationKey, category)) then
            -- Later raw timing cannot consume a previously isolated successor
            -- after another category witness appeared, even if it disappeared
            -- again before the timing became readable.
            context.chainReplacementEnd = nil
            context.chainReplacementInvalid = true
            unit.durationLadders[category] = nil
        end
        priorDurationHistory[category] = {
            stageEndAt = state.stageEndAt, stageResetSource = state.stageResetSource,
            stageResetPending = state.stageResetPending, activeCount = state.activeCount,
            observedQuietSince = state.observedQuietSince,
        }
    end

    -- Only complete absence establishes a removal. A readable expiration can
    -- bound a missing observer later, but partial absence never supplies an end.
    -- Retain a closed witness so stale returns cannot slide a recorded end.
    local stageEffects = {}
    for key, previous in pairs(unit.effects) do
        local incoming = effects and effects[key]
        local removed = (complete and not incoming) or (incoming
            and (incoming.category ~= previous.category or incoming.spellID ~= previous.spellID))
        if removed then
            local state = unit.categories[previous.category]
            local endedAt = recordEnd(state, previous, now)
            if state and state.witness == previous then
                local closed = {}
                for field, value in pairs(previous) do closed[field] = value end
                closed.endedAt = endedAt
                state.witness = closed
            end
        else
            stageEffects[key] = previous
        end
    end
    updateStageClocks(unit, stageEffects, now, self.stageResetSeconds, self.resetOnApplication and self.resetSeconds or nil)

    local nextEffects = {}
    if not complete then
        -- Missing effects in a partial snapshot are unknown, not absent.
        for key, value in pairs(unit.effects) do nextEffects[key] = value end
    end
    local keys = {}
    for key in pairs(effects or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local aTime, bTime = applicationTime(effects[a], now) or now, applicationTime(effects[b], now) or now
        if aTime ~= bTime then return aTime < bTime end
        return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
        local effect = effects[key]
        local category = effect.category
        local state = unit.categories[category]
        local preciseStart = applicationTime(effect, now)
        -- A complete empty snapshot ends activity, not the identity of the
        -- application. Retain one immutable witness with the category so the
        -- same record returning cannot be counted as another CC. An untimed
        -- identity seen again after its window has no such continuity proof.
        local retained = state and state.witness
        local sameFallback = retained and retained.fallbackIdentity and effect.fallbackIdentity
            and retained.spellID == effect.spellID and preciseStart and retained.appliedAt
            and math.abs(preciseStart - retained.appliedAt) <= APPLICATION_EPSILON
        if retained and state.applicationKey ~= key and not sameFallback then retained = nil end
        if retained and not retained.appliedAt and not preciseStart and not stageInWindow(state, now) then
            retained = nil
        end
        local previous = unit.effects[key] or retained
        local same = previous and previous.category == category and previous.spellID == effect.spellID
        local refreshed = same and refreshedApplication(previous, effect, preciseStart)
        if not same or refreshed then
            local prediction = self.estimates[guid]
            local candidate = prediction and prediction.categories[category]
            local matchedPrediction = candidate and candidate.spellID == effect.spellID
                and (not preciseStart or (preciseStart >= (candidate.sentAt or candidate.appliedAt)
                    and inWindow(candidate, preciseStart, self.resetSeconds)))
            local estimatedTime = not preciseStart and matchedPrediction and candidate.appliedAt or nil
            local appliedAt = preciseStart or estimatedTime or now
            if state and appliedAt < state.appliedAt then
                -- A late older witness cannot rewind the current deadline
                -- or confidently reconstruct intervening application order.
                state.uncertain = true
            else
                local replacementEnd = refreshed
                    and chainReplacementEnd(unit, state, previous, effect, effects, key, preciseStart, complete)
                if refreshed then
                    -- A positive refresh replaces the preceding application on
                    -- this identity. Its old predicted end must not outlive it.
                    recordEnd(state, previous, appliedAt)
                    stageEffects[key] = nil
                    updateStageClocks(unit, stageEffects, now, self.stageResetSeconds, self.resetOnApplication and self.resetSeconds or nil)
                end
                local prior = predecessor(state)
                local context = durationContext(unit, priorDurationHistory[category], effects, key, category)
                context.chainReplacementEnd = replacementEnd or nil
                if not stageInWindow(state, appliedAt) then
                    state = {
                        stage = 0,
                        activeCount = 0,
                        uncertain = not unit.completeSince or appliedAt < unit.completeSince + self.stageResetSeconds,
                    }
                    unit.categories[category] = state
                end
                local inferredStage = state.inferredStage and math.min(3, state.inferredStage + 1)
                state.stage = math.min(3, state.stage + 1)
                if matchedPrediction then inferredStage = math.max(inferredStage or 0, candidate.stage) end
                -- The current application is observed; earlier unconfirmed casts
                -- remain only an optional display overlay, never observed history.
                state.inferredStage = inferredStage and inferredStage > state.stage and inferredStage or nil
                state.spellID = effect.spellID
                state.appliedAt = appliedAt
                state.applicationKey = key
                state.timeEstimated = estimatedTime ~= nil
                state.previousApplication = prior
                state.durationContext, state.reportedDurationWitness = context, nil
                state.resetEvidence, state.resetBaselineDuration, state.resetPreviousStage, state.resetBaselineSource = nil, nil, nil, nil
                state.confirmationStage = matchedPrediction and candidate.stage or nil
                state.confirmationSentAt = matchedPrediction and (candidate.sentAt or candidate.appliedAt) or nil
                state.confirmationAppliedAt = matchedPrediction and candidate.appliedAt or nil
                if estimatedTime or (refreshed and effect.applicationSource == "aura") then state.uncertain = true end
            end
            if prediction and candidate and (matchedPrediction or candidate.appliedAt <= appliedAt) then
                prediction.categories[category] = nil
            end
        elseif same and preciseStart
            and (not previous.appliedAt or (previous.applicationSource ~= "loc"
                and effect.applicationSource == "loc"))
            and state and state.applicationKey == key then
            -- The identity was observed before timing became readable. Correct
            -- that application in place; its arrival is not another CC.
            local prior = state.previousApplication
            if prior and preciseStart < prior.appliedAt then
                -- This provisional witness turns out to predate the retained
                -- application. Restore that newer state instead of rewinding it.
                prior.uncertain = true
                unit.categories[category] = prior
            else
                local continuing = stageInWindow(prior, preciseStart)
                if prior then
                    state.stage = math.min(3, (continuing and prior.stage or 0) + 1)
                    local inferredStage = continuing and prior.inferredStage and math.min(3, prior.inferredStage + 1)
                    if state.confirmationStage and preciseStart >= state.confirmationSentAt
                        and preciseStart < state.confirmationAppliedAt + self.resetSeconds then
                        inferredStage = math.max(inferredStage or 0, state.confirmationStage)
                    end
                    state.inferredStage = inferredStage and inferredStage > state.stage and inferredStage or nil
                end
                -- A restored flat predecessor has no older history attached;
                -- correcting its clock cannot discard its already known count.
                state.appliedAt, state.timeEstimated = preciseStart, false
                if (continuing and prior.uncertain) or not unit.completeSince
                    or preciseStart < unit.completeSince + self.stageResetSeconds
                    or (previous.appliedAt and math.abs(preciseStart - previous.appliedAt) > APPLICATION_EPSILON) then
                    state.uncertain = true
                end
            end
        elseif state and previous.expires and effect.expires and effect.expires > previous.expires then
            -- A stable key with an extended expiry may be a refreshed CC. It
            -- provides no reliable new application, so never restart its timer
            -- or invent a stage. An expired timer stays expired.
            state.uncertain = true
        end
        -- Explicit timing stays authoritative for this application. A weaker
        -- aura clock, missing timing, or stale LoC sample must not replace the
        -- baseline used to recognize its next refresh. A new identity or a
        -- newer explicit start creates a new witness normally. Same-ID aura
        -- changes after LoC are ambiguous until stronger evidence arrives.
        local retainTiming = same and not refreshed and previous.applicationSource == "loc"
        if retainTiming and state and effect.applicationSource == "aura"
            and ((preciseStart and math.abs(preciseStart - previous.appliedAt) > APPLICATION_EPSILON)
                or (effect.expires and previous.expires
                    and math.abs(effect.expires - previous.expires) > APPLICATION_EPSILON)) then
            state.uncertain = true
        end
        local expires = retainTiming and previous.expires or effect.expires or (same and previous.expires or nil)
        local endedAt = same and not refreshed and previous.endedAt or nil
        if endedAt and expires and expires > now then
            -- A still-live identical witness can repair a transient empty
            -- snapshot. It restores coverage, never another application.
            endedAt = nil
            if state then state.uncertain = true end
        end
        nextEffects[key] = {category = category, spellID = effect.spellID,
            expires = expires, endedAt = endedAt,
            appliedAt = retainTiming and previous.appliedAt or preciseStart or (same and previous.appliedAt or nil),
            applicationSource = retainTiming and previous.applicationSource
                or (preciseStart and effect.applicationSource) or (same and previous.applicationSource or nil),
            fallbackIdentity = effect.fallbackIdentity == true,
            firstSeenAt = same and not refreshed and previous.firstSeenAt or now}
        local current = unit.categories[category]
        if current and current.applicationKey == key then
            current.witness = nextEffects[key]
            rememberAuraDuration(current, effect, preciseStart)
            if not self.resetOnApplication then reconcileDuration(unit, current, effect, preciseStart, now, complete) end
        end
        stageEffects[key] = nextEffects[key]
        updateStageClocks(unit, stageEffects, now, self.stageResetSeconds, self.resetOnApplication and self.resetSeconds or nil)
    end

    updateStageClocks(unit, nextEffects, now, self.stageResetSeconds, self.resetOnApplication and self.resetSeconds or nil)
    local presentCategories = {}
    for _, effect in pairs(nextEffects) do presentCategories[effect.category] = true end
    for category, state in pairs(unit.categories) do
        if complete and not presentCategories[category] then
            state.observedQuietSince = state.observedQuietSince or now
        else
            state.observedQuietSince = nil
        end
    end
    unit.effects = nextEffects
    trimOldest(self.units, MAX_UNITS)
end

function Model:Forget(guid)
    -- Losing a target's aura visibility does not undo a recorded cast event.
    self.units[guid] = nil
    self.estimates[guid] = nil
end

function Model:PruneEstimates(now)
    for guid, prediction in pairs(self.estimates) do
        for category, state in pairs(prediction.categories) do
            if now >= state.appliedAt + self.resetSeconds then prediction.categories[category] = nil end
        end
        for castID, time in pairs(prediction.castIDs) do
            if now - time >= CAST_ID_TTL then prediction.castIDs[castID] = nil end
        end
        if not next(prediction.categories) and not next(prediction.castIDs) then self.estimates[guid] = nil end
    end
end

function Model:EstimateDR(guid, spellID, category, now, castID, sentAt)
    if not guid or not castID or not self.categoryOrder[category] then return false end
    self:PruneEstimates(now)
    local prediction = self.estimates[guid]
    if not prediction then
        prediction = {seen = now, categories = {}, castIDs = {}}
        self.estimates[guid] = prediction
    end
    if prediction.castIDs[castID] then return false end
    prediction.seen, prediction.castIDs[castID] = now, now
    trimOldest(prediction.castIDs, MAX_CAST_IDS)
    trimOldest(self.estimates, MAX_UNITS)
    local unit = self.units[guid]
    local actual = unit and unit.categories[category]
    if not stageInWindow(actual, now) then actual = nil end
    -- Prefer an application already observed during this cast. This does not
    -- claim to identify its caster; it merely avoids stacking a guess on it.
    if actual and actual.appliedAt >= (sentAt or now) then return false end
    local previous = prediction.categories[category]
    local base = actual
    if previous and (not base or previous.appliedAt > base.appliedAt) then base = previous end
    -- Cast success does not prove a CC landed. Once this category predicts
    -- immunity, further unconfirmed attempts must not postpone its reset.
    -- Keep the cast ID above so a duplicate cannot replay after expiry. A new
    -- positive aura/LoC application still updates observed history in Observe.
    if base and (base.inferredStage or base.stage) >= 3 then return false end
    prediction.categories[category] = {
        spellID = spellID, appliedAt = now, stage = math.min(3, (base and (base.inferredStage or base.stage) or 0) + 1),
        sentAt = sentAt or now,
    }
    return true
end

function Model:GetDR(guid, now, includeEstimates)
    local rows = {}
    local unit = guid and self.units[guid]
    self:PruneEstimates(now)
    local states = {}
    for category, state in pairs(unit and unit.categories or {}) do
        if stageInWindow(state, now) then states[category] = state end
    end
    local prediction = includeEstimates ~= false and guid and self.estimates[guid]
    for category, state in pairs(prediction and prediction.categories or {}) do
        if not states[category] or state.appliedAt > states[category].appliedAt then
            states[category] = state
        end
    end
    for category, state in pairs(states) do
        local estimated = prediction and prediction.categories[category] == state or false
        local active = false
        for _, effect in pairs(not estimated and unit and unit.effects or {}) do
            if effect.category == category and not effect.endedAt and (not effect.expires or now < effect.expires) then
                active = true
            end
        end
        local inferredStage = includeEstimates ~= false and not estimated and state.inferredStage
        local stageEstimated = inferredStage ~= nil and inferredStage ~= false and inferredStage > state.stage
        local observed = unit and unit.categories[category]
        local baseline = not estimated and unit and unit.durationBaselines[state.spellID]
        local durationCandidate = not estimated and unit and unit.durationLadders[category]
        if durationCandidate and (durationCandidate.spellID ~= state.spellID
            or (not matchesDurationCandidate(state, durationCandidate)
                and not matchesDurationCandidate(state.previousApplication, durationCandidate))) then
            durationCandidate = nil
        end
        rows[#rows + 1] = {
            category = category,
            spellID = state.spellID,
            stage = stageEstimated and inferredStage or state.stage,
            observedStage = estimated and (stageInWindow(observed, now) and observed.stage or 0) or state.stage,
            stageEstimated = stageEstimated,
            remaining = math.max(0, self.resetSeconds - (now - state.appliedAt)),
            duration = self.resetSeconds,
            started = state.appliedAt,
            applicationExpired = now >= state.appliedAt + self.resetSeconds,
            stageResetAt = not estimated and state.stageResetAt or nil,
            stageRemaining = not estimated and state.stageResetAt and math.max(0, state.stageResetAt - now) or nil,
            stageResetPending = not estimated and state.stageResetPending or false,
            stageResetSource = not estimated and state.stageResetSource or nil,
            resetEvidence = not estimated and state.resetEvidence or nil,
            resetBaselineDuration = not estimated and state.resetBaselineDuration or nil,
            resetPreviousStage = not estimated and state.resetPreviousStage or nil,
            resetBaselineSource = not estimated and state.resetBaselineSource or nil,
            fullDurationBaseline = baseline and baseline.duration or nil,
            fullDurationBaselineSource = baseline and baseline.source or nil,
            durationCandidateStep = durationCandidate and durationCandidate.step or nil,
            active = active,
            uncertain = estimated or stageEstimated or state.uncertain
                or (not active and state.stageResetSource == "predicted-end"),
            estimated = estimated,
            timeEstimated = state.timeEstimated == true,
        }
    end
    table.sort(rows, function(a, b)
        local aOrder, bOrder = self.categoryOrder[a.category] or 999, self.categoryOrder[b.category] or 999
        if aOrder ~= bOrder then return aOrder < bOrder end
        return a.category < b.category
    end)
    return rows
end

function Model:PruneCooldowns(now)
    for guid, caster in pairs(self.casters) do
        for spellID, cooldown in pairs(caster.cooldowns) do
            if now >= cooldown.started + cooldown.duration then caster.cooldowns[spellID] = nil end
        end
        for castID, time in pairs(caster.castIDs) do
            if now - time >= CAST_ID_TTL then caster.castIDs[castID] = nil end
        end
        for spellID, event in pairs(caster.recent) do
            if now - event.time > FALLBACK_DEDUP_SECONDS then caster.recent[spellID] = nil end
        end
        if not next(caster.cooldowns) and not next(caster.castIDs) and not next(caster.recent) then
            self.casters[guid] = nil
        end
    end
end

function Model:Cast(guid, name, spellID, now, castID, manual, overrides)
    if not guid then return false end
    local data = ns.Data
    local canonicalID = data.castToSpell[spellID] or spellID
    local ability = data.spells[canonicalID]
    local reset = data.resets[spellID] or data.resets[canonicalID]
    if not ability and not reset then return false end
    self:PruneCooldowns(now)
    local caster = self.casters[guid]
    if not caster then
        caster = {seen = now, name = name or guid, cooldowns = {}, castIDs = {}, recent = {}}
        self.casters[guid] = caster
    end
    caster.seen = now
    if name then caster.name = name end
    local previous = caster.recent[canonicalID]
    if castID then
        if caster.castIDs[castID] then return false end
        caster.castIDs[castID] = now
        trimOldest(caster.castIDs, MAX_CAST_IDS)
        if previous and not previous.castID and now - previous.time <= FALLBACK_DEDUP_SECONDS then
            -- Attach the later identity to the ID-less event already recorded.
            previous.castID = castID
            return false
        end
    else
        if previous and now - previous.time <= FALLBACK_DEDUP_SECONDS then return false end
    end
    caster.recent[canonicalID] = {time = now, castID = castID}

    if reset then
        for _, resetSpellID in ipairs(reset) do caster.cooldowns[resetSpellID] = nil end
    end
    local duration = ability and ability.cdMax or 0
    local minimum = ability and ability.cdMin or duration
    local override = overrides and overrides[canonicalID]
    if duration > 0 and type(override) == "number" and override > 0 then
        duration, minimum = override, override
    end
    if duration > 0 then
        caster.cooldowns[canonicalID] = {
            spellID = canonicalID,
            category = ability.category,
            started = now,
            duration = duration,
            minimum = minimum,
            manual = manual == true,
            interrupt = ability.interrupt == true,
        }
    end
    trimOldest(self.casters, MAX_CASTERS)
    return reset ~= nil or duration > 0
end

function Model:GetCooldowns(now, filterGuid)
    self:PruneCooldowns(now)
    local rows = {}
    for guid, caster in pairs(self.casters) do
        if not filterGuid or filterGuid == guid then
            for _, cooldown in pairs(caster.cooldowns) do
                rows[#rows + 1] = {
                    guid = guid,
                    name = caster.name,
                    spellID = cooldown.spellID,
                    category = cooldown.category,
                    started = cooldown.started,
                    duration = cooldown.duration,
                    remaining = math.max(0, cooldown.duration - (now - cooldown.started)),
                    earlyRemaining = math.max(0, cooldown.minimum - (now - cooldown.started)),
                    manual = cooldown.manual,
                    interrupt = cooldown.interrupt,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.guid ~= b.guid then return a.guid < b.guid end
        local aOrder, bOrder = self.categoryOrder[a.category] or 999, self.categoryOrder[b.category] or 999
        if aOrder ~= bOrder then return aOrder < bOrder end
        return a.spellID < b.spellID
    end)
    return rows
end
