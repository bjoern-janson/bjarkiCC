local _, ns = ...

-- Pure state: inputs must already be readable, ordinary Lua values. Client API
-- calls and secret-value guards belong to Observer, before any input gets here.
local Model = {}
Model.__index = Model
ns.Model = Model

local MAX_UNITS = 128
local MAX_EFFECTS = 512
local MAX_CASTERS = 128
local MAX_ANONYMOUS_COOLDOWNS = 40
local MAX_ANONYMOUS_WITNESSES = 160
local ANONYMOUS_WITNESS_TTL = 360
local AURA_CAST_DEDUP_SECONDS = 1.5
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

function Model.New(applicationSeconds, stageResetSeconds)
    local order = {}
    for index, category in ipairs(ns.Data.categories) do order[category.key] = index end
    return setmetatable({
        resetSeconds = applicationSeconds or 20,
        stageResetSeconds = stageResetSeconds or 18,
        units = {},
        estimates = {}, -- Own casts are predictions, never observed applications.
        casters = {},
        anonymousCooldowns = {}, -- Distinct landed effects; do not invent a caster GUID.
        anonymousWitnesses = {}, -- Bounded replay deduplication independent of cooldown expiry.
        nextClaimID = 0, claimActivity = {}, -- Ephemeral bounded explanation lifecycle.
        categoryOrder = order,
    }, Model)
end

local function inWindow(state, now, resetSeconds)
    return state and now < state.appliedAt + resetSeconds
end

local function stageInWindow(state, now)
    return state and (state.stageResetPending or (state.stageResetAt and now < state.stageResetAt))
end

local function recordEnd(state, effect, now, source)
    if not state then return end
    local endedAt = effect.endedAt or math.min(now, effect.expires or now)
    if not state.lastEndedAt or endedAt > state.lastEndedAt then
        state.lastEndedAt = endedAt
        state.lastEndSource = source or effect.endSource or "observed-end"
    end
    return endedAt
end

local function updateStageClocks(unit, effects, now, stageResetSeconds)
    for _, state in pairs(unit.categories) do
        state.activeCount = 0
        state.stageResetPending = state.retentionPending or false
        state.stageEndAt = state.lastEndedAt
        state.stageResetSource = state.lastEndedAt and (state.lastEndSource or "observed-end") or nil
        if state.retentionEndAt and (not state.stageEndAt or state.retentionEndAt > state.stageEndAt) then
            state.stageEndAt, state.stageResetSource = state.retentionEndAt, "predicted-end"
        end
    end
    for _, effect in pairs(effects) do
        local state = unit.categories[effect.category]
        if state then
            local endedAt = effect.endedAt or effect.expires
            if not effect.gapUnresolved and not effect.endedAt and (not effect.expires or now < effect.expires) then
                state.activeCount = state.activeCount + 1
            end
            if endedAt then
                if not state.stageEndAt or endedAt > state.stageEndAt then
                    state.stageEndAt = endedAt
                    state.stageResetSource = effect.endedAt and (effect.endSource or "observed-end") or "predicted-end"
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
    end
end

local function predecessor(state)
    if not state then return nil end
    -- One flat predecessor lets a later readable timestamp repair the latest
    -- provisional application. Never copy previousApplication recursively.
    return {
        stage = state.stage, inferredStage = state.inferredStage,
        inferredDirectStage = state.inferredDirectStage,
        appliedAt = state.appliedAt, spellID = state.spellID,
        applicationKey = state.applicationKey, timeEstimated = state.timeEstimated,
        uncertain = state.uncertain, activeCount = 0,
        confirmationStage = state.confirmationStage,
        confirmationFullDirectStage = state.confirmationFullDirectStage,
        confirmationSentAt = state.confirmationSentAt,
        confirmationAppliedAt = state.confirmationAppliedAt,
        confirmationDirectStage = state.confirmationDirectStage,
        confirmationDirectFullStage = state.confirmationDirectFullStage,
        confirmationDirectSentAt = state.confirmationDirectSentAt,
        confirmationDirectAppliedAt = state.confirmationDirectAppliedAt,
        confirmationOrigin = state.confirmationOrigin, inferenceOrigins = state.inferenceOrigins,
        witness = state.witness,
        lastEndedAt = state.lastEndedAt, lastEndSource = state.lastEndSource, stageEndAt = state.stageEndAt,
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

local function matchesPrediction(candidate, effect, preciseStart, resetSeconds, now)
    return candidate and candidate.spellID == effect.spellID
        and ((not preciseStart and inWindow(candidate, now, resetSeconds))
            or (preciseStart and preciseStart >= (candidate.sentAt or candidate.appliedAt)
                and inWindow(candidate, preciseStart, resetSeconds)))
end

local function originStages(origin, resetSeconds)
    local start = origin.preciseStart
    local full = origin.fullStage and (not start or (start >= origin.fullSentAt
        and start < origin.fullAppliedAt + resetSeconds))
    local direct = origin.directStage and (not start or (start >= origin.directSentAt
        and start < origin.directAppliedAt + resetSeconds))
    -- Each projection keeps its own valid current candidate. Cross-projection
    -- ancestry is only a fallback, as it is when the witness first arrives.
    return full and origin.fullStage or direct and origin.directFullStage or nil,
        direct and origin.directStage or full and origin.fullDirectStage or nil
end

local function refreshInference(state, resetSeconds)
    if not state then return end
    local full, direct
    for _, entry in ipairs(state.inferenceOrigins or {}) do
        local originFull, originDirect = originStages(entry.origin, resetSeconds)
        if originFull then full = math.max(full or 0, math.min(3, originFull + entry.successors)) end
        if originDirect then direct = math.max(direct or 0, math.min(3, originDirect + entry.successors)) end
    end
    state.inferredStage = full and full > state.stage and full or nil
    state.inferredDirectStage = direct and direct > state.stage and direct or nil
end

local function inheritInference(state, prior, resetSeconds)
    local origins = {}
    -- Only observed stages 1 and 2 can display additional inferred ancestry.
    -- Each step adds one flat origin; thus there are at most two, never a
    -- recursive application history. Reset cycles and stage 3 discard them.
    if state.stage < 3 then
        for _, entry in ipairs(prior and prior.inferenceOrigins or {}) do
            origins[#origins + 1] = {origin = entry.origin, successors = entry.successors + 1}
        end
        if state.confirmationOrigin then
            origins[#origins + 1] = {origin = state.confirmationOrigin, successors = 0}
        end
    end
    state.inferenceOrigins = #origins > 0 and origins or nil
    refreshInference(state, resetSeconds)
end

local function refreshedApplication(previous, effect, start)
    -- An untimed identity already represents one observed application. Its
    -- first readable timestamp calibrates that application, even when the
    -- client reports it after our local first-seen fallback. Only two known
    -- application timestamps can establish a same-identity refresh.
    if not previous or not start then return false end
    local acceptedStart = previous.refreshAppliedAt or previous.appliedAt
    local acceptedSource = previous.applicationSource
    local acceptedExpires = previous.expires
    if not acceptedStart or start <= acceptedStart + APPLICATION_EPSILON then return false end
    if effect.applicationSource == "loc" then
        -- Aura expiration-duration and explicit LoC starts are different
        -- clocks. The first LoC start calibrates this identity; only another
        -- explicit start can establish a same-identity LoC refresh.
        return acceptedSource == "loc"
    end
    -- A duration correction can move expiration-duration without another CC.
    -- A derived refresh needs both boundaries to change, from the same sensor.
    -- Diminished CC can end earlier even though its application is newer.
    return acceptedSource == "aura" and effect.applicationSource == "aura"
        and acceptedExpires and effect.expires
        and math.abs(effect.expires - acceptedExpires) > APPLICATION_EPSILON
end

-- Observer ownership uses exactly the same accepted refresh boundary.
Model.IsRefresh = refreshedApplication

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
        state.stage, state.inferredStage, state.inferredDirectStage = 1, nil, nil
        state.confirmationStage, state.confirmationSentAt, state.confirmationAppliedAt = nil, nil, nil
        state.confirmationDirectStage, state.confirmationDirectSentAt, state.confirmationDirectAppliedAt = nil, nil, nil
        state.confirmationFullDirectStage, state.confirmationDirectFullStage = nil, nil
        state.confirmationOrigin, state.inferenceOrigins = nil, nil
        state.resetEvidence, state.resetBaselineDuration = "matching-full-duration", baseline.duration
        state.resetBaselineSource = baseline.source
        state.uncertain = true
    end
end

-- Bound partial-snapshot history without converting eviction into removal.
-- Each fixed category keeps only an aggregate upper end/pending flag for lost
-- records. Current category witnesses and current positives win retention;
-- older replay metadata is deliberately bounded rather than moved elsewhere.
local function boundEffects(unit, effects, incoming, resetSeconds)
    local keys = {}
    for key in pairs(effects) do keys[#keys + 1] = key end
    if #keys <= MAX_EFFECTS then return end
    local function priority(key)
        local state = unit.categories[effects[key].category]
        if state and state.applicationKey == key then return 3 end
        return incoming and incoming[key] and 2 or 1
    end
    table.sort(keys, function(a, b)
        local ap, bp = priority(a), priority(b)
        if ap ~= bp then return ap > bp end
        local at, bt = effects[a].firstSeenAt or 0, effects[b].firstSeenAt or 0
        if at ~= bt then return at > bt end
        return tostring(a) < tostring(b)
    end)
    for index = MAX_EFFECTS + 1, #keys do
        local key = keys[index]
        local effect = effects[key]
        local state = unit.categories[effect.category]
        if state then
            -- Any occurrence represented by this discarded record was seen
            -- by this time. Keep one upper bound, independent of category
            -- clock calibration and of how long partial snapshots carry it.
            local observedAt = effect.lastSeenAt or effect.firstSeenAt
            state.retentionObservedAt = math.max(state.retentionObservedAt or 0, observedAt)
            local ending = effect.endedAt or effect.expires
            if effect.gapUnresolved then
                local bound = effect.gapEndBound or ending
                    or (effect.appliedAt or effect.firstSeenAt) + resetSeconds
                state.retentionGapBound = math.max(state.retentionGapBound or 0, bound)
            elseif not ending then
                -- Save this discarded record's own clock until its coverage
                -- lapses. A later application cannot lend it a newer bound.
                local bound = (effect.appliedAt or effect.firstSeenAt) + resetSeconds
                state.retentionUngappedBound = math.max(state.retentionUngappedBound or 0, bound)
            end
            if ending then state.retentionEndAt = math.max(state.retentionEndAt or ending, ending)
            else state.retentionPending = true end
            state.uncertain, state.observedQuietSince = true, nil
        end
        effects[key] = nil
    end
end

function Model:Observe(guid, effects, now, complete, removedKeys)
    if not guid then return end
    local unit = self.units[guid]
    if not unit then
        unit = {seen = now, effects = {}, categories = {}, durationBaselines = {}, durationLadders = {}, durationEpoch = 0}
        self.units[guid] = unit
    end
    -- A tracking gap must not be mistaken for observed quiet or a known CC end.
    unit.paused, unit.pauseAt = false, nil
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

    -- Retained exact identities, or accepted occurrences newer than every
    -- discarded positive observation, can exclude discarded-history replay.
    -- Repetition alone supplies neither proof, regardless of scan coverage.
    local ambiguousRetention, unresolvedCategories = {}, {}
    for key, effect in pairs(effects or {}) do
        local state = unit.categories[effect.category]
        if state and (state.retentionPending or state.retentionEndAt) then
            local previous = unit.effects[key]
            local start = applicationTime(effect, now)
            if not previous and state.applicationKey == key then
                previous = state.witness
                if previous and not previous.appliedAt and not start and not stageInWindow(state, now) then
                    previous = nil
                end
            end
            local same = previous and previous.category == effect.category and previous.spellID == effect.spellID
            local acceptedStart = start
            if same and previous.appliedAt and not refreshedApplication(previous, effect, start)
                and not (previous.applicationSource ~= "loc" and effect.applicationSource == "loc") then
                -- A weaker sensor, stale start or duration-only edit cannot
                -- advance the occurrence boundary used for this proof.
                acceptedStart = previous.refreshAppliedAt or previous.appliedAt
            end
            local retainedIdentity = same and not previous.fallbackIdentity and not previous.retentionAmbiguous
            local laterOccurrence = acceptedStart and state.retentionObservedAt
                and acceptedStart > state.retentionObservedAt + APPLICATION_EPSILON
            if effect.fallbackIdentity or not (retainedIdentity or laterOccurrence) then
                ambiguousRetention[key], unresolvedCategories[effect.category] = true, true
            end
        end
    end
    if complete then
        for category, state in pairs(unit.categories) do
            if not unresolvedCategories[category] and (state.retentionPending or state.retentionEndAt) then
                -- A still-ungapped unknown end closes at this observation.
                -- Otherwise every lost end has its own readable/frozen bound.
                local bound = not state.retentionUngappedBound
                    and math.max(state.retentionGapBound or 0, state.retentionEndAt or 0) or nil
                recordEnd(state, {expires = bound}, now,
                    bound and state.retentionGapBound and "unseen-end-estimate" or nil)
                state.retentionPending, state.retentionEndAt, state.retentionGapBound = nil, nil, nil
                state.retentionUngappedBound, state.retentionObservedAt = nil, nil
            end
        end
    end

    -- Only complete absence establishes a removal. A readable expiration can
    -- bound a missing observer later, but partial absence never supplies an end.
    -- Retain a closed witness so stale returns cannot slide a recorded end.
    local stageEffects = {}
    for key, previous in pairs(unit.effects) do
        local incoming = effects and effects[key]
        local removed = ((complete or (removedKeys and removedKeys[key])) and not incoming) or (incoming
            and (incoming.category ~= previous.category or incoming.spellID ~= previous.spellID))
        if removed then
            local state = unit.categories[previous.category]
            local endedAt
            local unseenEnd = previous.gapUnresolved and not previous.endedAt
            if unseenEnd then
                -- The aura disappeared while its owner was unobserved. We do
                -- not know when it ended. An existing readable expiration is
                -- an upper bound; otherwise cap the guess to the unchanged
                -- application clock, rather than inventing a fresh 18s reset
                -- starting on reacquisition.
                local bound = previous.gapEndBound or previous.expires
                if not bound or bound <= 0 then
                    bound = state and state.appliedAt and (state.appliedAt + self.resetSeconds) or now
                end
                endedAt = recordEnd(state, {expires = math.min(now, bound)}, now, "unseen-end-estimate")
                if state then state.uncertain = true end
            else
                endedAt = recordEnd(state, previous, now)
            end
            if state and state.witness == previous then
                local closed = {}
                for field, value in pairs(previous) do closed[field] = value end
                closed.endedAt = endedAt
                closed.endSource = unseenEnd and "unseen-end-estimate" or previous.endSource or "observed-end"
                state.witness = closed
            end
        else
            stageEffects[key] = previous
        end
    end
    updateStageClocks(unit, stageEffects, now, self.stageResetSeconds)

    local nextEffects = {}
    if not complete then
        -- Missing effects in a partial snapshot are unknown, not absent.
        for key, value in pairs(unit.effects) do
            if not (removedKeys and removedKeys[key] and not (effects and effects[key])) then
                nextEffects[key] = value
            end
        end
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
        local timingRefined = same and not refreshed and preciseStart
            and (not previous.appliedAt or (previous.applicationSource ~= "loc"
                and effect.applicationSource == "loc"))
        local origin = same and not refreshed and previous.confirmationOrigin or nil
        if timingRefined and origin then
            -- An older still-present overlap can invalidate ancestry copied
            -- into the latest application or its flat predecessor. All copies
            -- refer to this scalar origin, not to an older state/history.
            origin.preciseStart = preciseStart
            refreshInference(state and state.previousApplication, self.resetSeconds)
            refreshInference(state, self.resetSeconds)
        end
        if not same or refreshed then
            local prediction = self.estimates[guid]
            local candidate = prediction and prediction.categories[category]
            local directCandidate = prediction and prediction.directCategories[category]
            local matchedPrediction = matchesPrediction(candidate, effect, preciseStart, self.resetSeconds, now)
            local matchedDirect = matchesPrediction(directCandidate, effect, preciseStart, self.resetSeconds, now)
            local matched = matchedPrediction and candidate or matchedDirect and directCandidate
            if matchedDirect and (not matched or directCandidate.appliedAt > matched.appliedAt) then
                matched = directCandidate
            end
            -- The full projection can be capped on an older cast while the
            -- direct projection advances. Keep each confirmation's own lineage
            -- and clock; an untimed witness uses the newest matching cast.
            local fullConfirmation = matchedPrediction and candidate or matchedDirect and directCandidate
            local directConfirmation = matchedDirect and directCandidate or matchedPrediction and candidate
            local confirmedStage = matchedPrediction and candidate.stage or matchedDirect and directCandidate.fullStage
            local confirmedDirectStage = matchedDirect and directCandidate.stage or matchedPrediction and candidate.directStage
            local estimatedTime = not preciseStart and matched and matched.appliedAt or nil
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
                    updateStageClocks(unit, stageEffects, now, self.stageResetSeconds)
                end
                local prior = predecessor(state)
                local context = durationContext(unit, priorDurationHistory[category], effects, key, category)
                context.chainReplacementEnd = replacementEnd or nil
                local continuing = stageInWindow(state, appliedAt)
                if not continuing then
                    state = {
                        stage = 0,
                        activeCount = 0,
                        uncertain = not unit.completeSince or appliedAt < unit.completeSince + self.stageResetSeconds,
                    }
                    unit.categories[category] = state
                end
                state.stage = math.min(3, state.stage + 1)
                -- The current application is observed; earlier unconfirmed casts
                -- remain only an optional display overlay, never observed history.
                state.spellID = effect.spellID
                state.appliedAt = appliedAt
                state.applicationKey = key
                state.timeEstimated = estimatedTime ~= nil
                state.previousApplication = prior
                state.durationContext, state.reportedDurationWitness = context, nil
                state.resetEvidence, state.resetBaselineDuration, state.resetPreviousStage, state.resetBaselineSource = nil, nil, nil, nil
                state.confirmationStage = confirmedStage or nil
                state.confirmationFullDirectStage = matchedPrediction and candidate.directStage or confirmedDirectStage or nil
                state.confirmationSentAt = fullConfirmation and (fullConfirmation.sentAt or fullConfirmation.appliedAt) or nil
                state.confirmationAppliedAt = fullConfirmation and fullConfirmation.appliedAt or nil
                state.confirmationDirectStage = confirmedDirectStage or nil
                state.confirmationDirectFullStage = matchedDirect and directCandidate.fullStage or confirmedStage or nil
                state.confirmationDirectSentAt = directConfirmation and (directConfirmation.sentAt or directConfirmation.appliedAt) or nil
                state.confirmationDirectAppliedAt = directConfirmation and directConfirmation.appliedAt or nil
                origin = confirmedStage or confirmedDirectStage
                origin = origin and {
                    preciseStart = preciseStart,
                    fullStage = state.confirmationStage, fullDirectStage = state.confirmationFullDirectStage,
                    fullSentAt = state.confirmationSentAt, fullAppliedAt = state.confirmationAppliedAt,
                    directStage = state.confirmationDirectStage, directFullStage = state.confirmationDirectFullStage,
                    directSentAt = state.confirmationDirectSentAt, directAppliedAt = state.confirmationDirectAppliedAt,
                } or nil
                state.confirmationOrigin = origin
                inheritInference(state, continuing and prior or nil, self.resetSeconds)
                if estimatedTime or (refreshed and effect.applicationSource == "aura") then state.uncertain = true end
            end
            if prediction and candidate and (matchedPrediction or candidate.appliedAt <= appliedAt) then
                prediction.categories[category] = nil
            end
            if prediction and directCandidate and (matchedDirect or directCandidate.appliedAt <= appliedAt) then
                prediction.directCategories[category] = nil
            end
        elseif timingRefined and state and state.applicationKey == key then
            -- The identity was observed before timing became readable. Correct
            -- that application in place; its arrival is not another CC.
            local prior = state.previousApplication
            if prior and preciseStart < prior.appliedAt then
                -- This provisional witness turns out to predate the retained
                -- application. Restore that newer state instead of rewinding it.
                prior.uncertain = true
                -- Capacity evidence belongs to the category now, not to the
                -- predecessor's historical application snapshot.
                prior.retentionPending, prior.retentionEndAt, prior.retentionGapBound =
                    state.retentionPending, state.retentionEndAt, state.retentionGapBound
                prior.retentionUngappedBound = state.retentionUngappedBound
                prior.retentionObservedAt = state.retentionObservedAt
                unit.categories[category] = prior
            else
                local continuing = stageInWindow(prior, preciseStart)
                if prior then
                    state.stage = math.min(3, (continuing and prior.stage or 0) + 1)
                end
                -- Retain independent valid origins while retracting only the
                -- confirmation disproved by this application's readable time.
                if prior then inheritInference(state, continuing and prior or nil, self.resetSeconds)
                else refreshInference(state, self.resetSeconds) end
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
        -- aura clock, missing timing, or stale sample must not replace the
        -- baseline used to recognize its next refresh. A new identity or a
        -- newer explicit start creates a new witness normally. Same-ID aura
        -- changes after LoC are ambiguous until stronger evidence arrives.
        local acceptedStart = same and (previous.refreshAppliedAt or previous.appliedAt)
        local acceptedExpires = same and previous.expires
        local staleAura = same and previous.applicationSource == "aura"
            and effect.applicationSource == "aura" and acceptedStart and preciseStart
            and preciseStart < acceptedStart - APPLICATION_EPSILON
            and acceptedExpires and effect.expires
            and math.abs(effect.expires - acceptedExpires) > APPLICATION_EPSILON
        local retainTiming = same and not refreshed
            and (previous.applicationSource == "loc" or staleAura)
        if retainTiming and state and effect.applicationSource == "aura"
            and ((preciseStart and math.abs(preciseStart - previous.appliedAt) > APPLICATION_EPSILON)
                or (effect.expires and previous.expires
                    and math.abs(effect.expires - previous.expires) > APPLICATION_EPSILON)) then
            state.uncertain = true
        end
        -- A same-start explicit LoC correction supports a new end without a
        -- new occurrence. Keep start authority separate: weaker aura timing,
        -- stale explicit starts and missing ends retain the accepted bound.
        local correctedLoCExpiry = same and not refreshed and previous.applicationSource == "loc"
            and effect.applicationSource == "loc" and acceptedStart and preciseStart
            and math.abs(preciseStart - acceptedStart) <= APPLICATION_EPSILON
            and type(effect.expires) == "number" and effect.expires < math.huge and effect.expires > preciseStart
        local expires = correctedLoCExpiry and effect.expires
            or retainTiming and previous.expires or effect.expires or (same and previous.expires or nil)
        local endedAt = same and not refreshed and previous.endedAt or nil
        if endedAt and expires and expires > now then
            -- A still-live identical witness can repair a transient empty
            -- snapshot. It restores coverage, never another application.
            endedAt = nil
            if state then state.uncertain = true end
        end
        nextEffects[key] = {category = category, spellID = effect.spellID,
            expires = expires, endedAt = endedAt,
            endSource = endedAt and previous.endSource or nil,
            appliedAt = retainTiming and previous.appliedAt or preciseStart or (same and previous.appliedAt or nil),
            applicationSource = retainTiming and previous.applicationSource
                or (preciseStart and effect.applicationSource) or (same and previous.applicationSource or nil),
            fallbackIdentity = effect.fallbackIdentity == true,
            retentionAmbiguous = ambiguousRetention[key] or nil,
            -- Keep occurrence detection independent of raw duration corrections.
            refreshAppliedAt = same and not refreshed and not timingRefined
                and acceptedStart or preciseStart,
            confirmationOrigin = origin,
            firstSeenAt = same and not refreshed and previous.firstSeenAt or now,
            lastSeenAt = now}
        local current = unit.categories[category]
        if current and current.applicationKey == key then
            current.witness = nextEffects[key]
            rememberAuraDuration(current, effect, preciseStart)
            reconcileDuration(unit, current, effect, preciseStart, now, complete)
        end
        stageEffects[key] = nextEffects[key]
        updateStageClocks(unit, stageEffects, now, self.stageResetSeconds)
    end

    boundEffects(unit, nextEffects, effects, self.resetSeconds)
    updateStageClocks(unit, nextEffects, now, self.stageResetSeconds)
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

-- A unit leaving Target/Focus is not evidence that its DR reset. Keep the
-- bounded GUID-keyed history and application identities, but invalidate aura
-- continuity and duration learning. This never manufactures an aura removal.
function Model:Pause(guid, now)
    local unit = guid and self.units[guid]
    if not unit or unit.paused or type(now) ~= "number" or now ~= now or now < 0 then return false end
    self:Observe(guid, {}, now, false)
    unit = self.units[guid]
    if not unit then return false end
    -- Reacquisition may initially be partial. Keep each missing witness's gap
    -- unresolved until that effect is positively seen or completely absent.
    -- Freeze its own bound here so a newer same-category application cannot
    -- lend the old missing effect a fresh application clock.
    for _, effect in pairs(unit.effects) do
        effect.gapUnresolved = true
        if not effect.gapEndBound then
            local state = unit.categories[effect.category]
            local appliedAt = effect.appliedAt
                or (state and state.witness == effect and state.appliedAt)
                or effect.firstSeenAt or now
            effect.gapEndBound = effect.expires and effect.expires > 0 and effect.expires
                or appliedAt + self.resetSeconds
        end
    end
    for _, state in pairs(unit.categories) do
        if state.retentionPending or state.retentionEndAt then
            state.retentionGapBound = math.max(state.retentionGapBound or 0,
                state.retentionUngappedBound or 0, state.retentionEndAt or 0)
            state.retentionUngappedBound = nil
        end
    end
    unit.paused, unit.pauseAt = true, now
    return true
end

-- Old actors must not live indefinitely, especially if their last CC lacked
-- a readable expiration. 128 GUIDs remain the hard memory cap.
function Model:PruneDormant(now)
    if type(now) ~= "number" or now ~= now then return end
    local maxGap = self.resetSeconds + self.stageResetSeconds + 20
    for guid, unit in pairs(self.units) do
        if unit.paused and unit.pauseAt and now - unit.pauseAt >= maxGap then
            self.units[guid] = nil
        end
    end
end

function Model:Forget(guid)
    -- Explicit resets and player death still discard history completely.
    self.units[guid] = nil
    self.estimates[guid] = nil
end

function Model:PruneEstimates(now)
    for guid, prediction in pairs(self.estimates) do
        for category, state in pairs(prediction.categories) do
            if now >= state.appliedAt + self.resetSeconds then prediction.categories[category] = nil end
        end
        for category, state in pairs(prediction.directCategories) do
            if now >= state.appliedAt + self.resetSeconds then prediction.directCategories[category] = nil end
        end
        for castID, time in pairs(prediction.castIDs) do
            if now - time >= CAST_ID_TTL then prediction.castIDs[castID] = nil end
        end
        if not next(prediction.categories) and not next(prediction.directCategories)
            and not next(prediction.castIDs) then self.estimates[guid] = nil end
    end
end

function Model:EstimateDR(guid, spellID, category, now, castID, sentAt, estimateKind)
    if not guid or not castID or not self.categoryOrder[category] then return false end
    if estimateKind ~= nil and estimateKind ~= "aoe" then return false end
    self:PruneEstimates(now)
    local prediction = self.estimates[guid]
    if not prediction then
        prediction = {seen = now, categories = {}, directCategories = {}, castIDs = {}}
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
    local directPrevious = prediction.directCategories[category]
    local directBase = actual
    if directPrevious and (not directBase or directPrevious.appliedAt > directBase.appliedAt) then directBase = directPrevious end
    local baseStage = base and (base.inferredStage or base.stage) or 0
    local directBaseStage = directBase and (directBase.inferredDirectStage or directBase.stage) or 0
    local fullStage, directStage = math.min(3, baseStage + 1), math.min(3, directBaseStage + 1)
    -- Cast success does not prove a CC landed. Once this category predicts
    -- immunity, further unconfirmed attempts must not postpone its reset.
    -- Keep the cast ID above so a duplicate cannot replay after expiry. A new
    -- positive aura/LoC application still updates observed history in Observe.
    local accepted = false
    if baseStage < 3 then
        prediction.categories[category] = {
            spellID = spellID, appliedAt = now, stage = fullStage,
            sentAt = sentAt or now, estimateKind = estimateKind,
            -- If this cast is later observed, it counts in both projections,
            -- even when its unconfirmed AoE guess was hidden.
            directStage = directStage,
        }
        accepted = true
    end
    -- AoE visibility is a projection, not destruction of evidence. Preserve
    -- an independent direct-only clock and count through interleaved guesses.
    -- A full projection at immunity must not cap this lower direct projection
    -- or have its own reset postponed by the new direct estimate.
    if estimateKind ~= "aoe" and directBaseStage < 3 then
        prediction.directCategories[category] = {
            spellID = spellID, appliedAt = now, stage = directStage,
            sentAt = sentAt or now, fullStage = fullStage,
        }
        accepted = true
    end
    return accepted
end

-- Only currently pending, reviewed own-cast estimates can authorize targeted
-- positive exact-aura probes. This is query selection, NEVER application proof.
-- Keep the observer out of the model's private estimate tables.
function Model:GetPendingExactSpellIDs(guid, now)
    local result, seen = {}, {}
    if not guid or type(now) ~= "number" then return result end
    local prediction = self.estimates[guid]
    if not prediction then return result end
    for _, categories in ipairs({prediction.categories, prediction.directCategories}) do
        for _, state in pairs(categories) do
            local id = state.spellID
            if id and not seen[id] and now >= state.appliedAt
                and inWindow(state, now, self.resetSeconds) then
                seen[id] = true
                result[#result + 1] = id
            end
        end
    end
    table.sort(result)
    return result
end

function Model:GetDR(guid, now, includeEstimates, includeAoE)
    local rows = {}
    local unit = guid and self.units[guid]
    self:PruneEstimates(now)
    local states = {}
    for category, state in pairs(unit and unit.categories or {}) do
        if stageInWindow(state, now) then states[category] = state end
    end
    local prediction = includeEstimates ~= false and guid and self.estimates[guid]
    local predictionStates = prediction and (includeAoE == false and prediction.directCategories or prediction.categories)
    for category, state in pairs(predictionStates or {}) do
        if not states[category] or state.appliedAt > states[category].appliedAt then
            states[category] = state
        end
    end
    for category, state in pairs(states) do
        local estimated = predictionStates and predictionStates[category] == state or false
        local active = false
        for _, effect in pairs(not estimated and unit and not unit.paused and unit.effects or {}) do
            if effect.category == category and not effect.gapUnresolved and not effect.endedAt
                and (not effect.expires or now < effect.expires) then
                active = true
            end
        end
        local inferredStage = includeEstimates ~= false and not estimated
            and state[includeAoE == false and "inferredDirectStage" or "inferredStage"]
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
            estimateKind = estimated and state.estimateKind or nil,
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
    for i = #self.anonymousCooldowns, 1, -1 do
        local cooldown = self.anonymousCooldowns[i]
        if now >= cooldown.started + cooldown.duration then
            if ns.Claims then ns.Claims.Retire(self, cooldown.claim, now, 'elapsed') end
            table.remove(self.anonymousCooldowns, i)
        end
    end
    for key, seen in pairs(self.anonymousWitnesses) do
        if now - seen >= ANONYMOUS_WITNESS_TTL then self.anonymousWitnesses[key] = nil end
    end
    for guid, caster in pairs(self.casters) do
        for spellID, cooldown in pairs(caster.cooldowns) do
            if now >= cooldown.started + cooldown.duration then
                if ns.Claims then ns.Claims.Retire(self, cooldown.claim, now, 'elapsed') end
                caster.cooldowns[spellID] = nil
            end
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

-- Retain the former name argument slot for internal caller compatibility.
-- Cooldowns store and sort caster identity only by GUID.
function Model:Cast(guid, ignoredName, spellID, now, castID, manual, overrides, evidenceSource, timingEstimated, context)
    if not guid then return false end
    local data = ns.Data
    local canonicalID = data.castToSpell[spellID] or spellID
    local ability = data.spells[canonicalID]
    local reset = data.resets[spellID] or data.resets[canonicalID]
    if not ability and not reset then return false end
    self:PruneCooldowns(now)
    local caster = self.casters[guid]
    if not caster then
        caster = {seen = now, cooldowns = {}, castIDs = {}, recent = {}}
        self.casters[guid] = caster
    end
    caster.seen = now
    local previous = caster.recent[canonicalID]
    local existing = caster.cooldowns[canonicalID]
    -- A newly encountered aura identity can refer to an OLDER application.
    -- Do not rewind a newer cooldown from its late arrival. A timestamp repair
    -- for the SAME identity instead uses RefineHelpfulTime below.
    if evidenceSource == 'helpful-aura' and existing
        and now < existing.started - APPLICATION_EPSILON then return false end
    if evidenceSource == 'helpful-aura' and existing and existing.evidenceSource == 'cast'
        and (math.abs(now - existing.started) <= AURA_CAST_DEDUP_SECONDS
            or now < existing.started
            or (timingEstimated and not (context and context.newApplication))) then
        -- A late old application or an untimed ordinary sighting cannot
        -- supersede a confirmed later cast, even if UNIT_AURA reports it as
        -- newly added to this observer. Only truly later application evidence
        -- may open a distinct activation; near-concurrent reports can link.
        if ns.Claims and math.abs(now - existing.started) <= AURA_CAST_DEDUP_SECONDS then
            ns.Claims.Witness(existing.claim, 'helpful-aura',
                context and context.origin or 'CC aura',
                context and context.observedAt or now)
            existing.evidenceIdentity = context and context.identity or existing.evidenceIdentity
        end
        return false
    end
    if evidenceSource == 'helpful-aura' and previous
        and math.abs(now - previous.time) <= AURA_CAST_DEDUP_SECONDS then
        return false
    end
    if not manual and evidenceSource ~= 'helpful-aura' and existing
        and existing.evidenceSource == 'helpful-aura'
        and math.abs(now - existing.started) <= AURA_CAST_DEDUP_SECONDS then
        -- Later positive cast evidence corrects the existing near-concurrent
        -- aura estimate. It does NOT create a second activation or timer.
        if castID and caster.castIDs[castID] then return false end
        if castID then
            caster.castIDs[castID] = now
            trimOldest(caster.castIDs, MAX_CAST_IDS)
        end
        caster.recent[canonicalID] = {time = now, castID = castID}
        local before = existing.started
        existing.started, existing.evidenceSource, existing.timingEstimated = now, 'cast', false
        if ns.Claims and existing.claim then
            ns.Claims.Witness(existing.claim,'cast','CC cast-success',now)
            ns.Claims.Revise(self,existing.claim,now,'matched-successful-cast',
                before,now,'cast-success-event')
            existing.claim.source='cast'
            existing.claim.basis='cast-success-event'
        end
        return true
    end
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
        for _, resetSpellID in ipairs(reset) do
            local old = caster.cooldowns[resetSpellID]
            if old and ns.Claims then ns.Claims.Retire(self,old.claim,now,'reset-spell-witness') end
            caster.cooldowns[resetSpellID] = nil
        end
    end
    local duration = ability and ability.cdMax or 0
    local minimum = ability and ability.cdMin or duration
    local override = overrides and overrides[canonicalID]
    if duration > 0 and type(override) == "number" and override > 0 then
        duration, minimum = override, override
    end
    if duration > 0 then
        if existing and ns.Claims then ns.Claims.Retire(self,existing.claim,now,'superseded-by-new-use') end
        caster.cooldowns[canonicalID] = {
            spellID = canonicalID,
            category = ability.category,
            started = now,
            duration = duration,
            minimum = minimum,
            manual = manual == true,
            interrupt = ability.interrupt == true,
            evidenceSource = evidenceSource or (manual and 'manual' or 'cast'),
            timingEstimated = timingEstimated == true,
            evidenceIdentity = context and context.identity or nil,
            claim = ns.Claims and ns.Claims.Issue(self,canonicalID,
                evidenceSource or (manual and 'manual' or 'cast'), now,
                false, timingEstimated, context) or nil,
        }
    end
    trimOldest(self.casters, MAX_CASTERS)
    return reset ~= nil or duration > 0
end

-- Link additional sightings of the SAME aura without increasing the
-- evidentiary weight. Presence of two addons is not two independent casts.
function Model:CorroborateHelpful(guid, spellID, identity, observedAt, origin)
    if not guid or type(identity) ~= 'string' or type(origin) ~= 'string' then return false end
    local canonical = ns.Data.castToSpell[spellID] or spellID
    local caster = self.casters[guid]
    local row = caster and caster.cooldowns[canonical]
    if not row or row.evidenceIdentity ~= identity or not ns.Claims then return false end
    return ns.Claims.Witness(row.claim,'same-aura-sighting',origin,observedAt)
end

-- Correct first-sighting bias only if a later readable application timestamp
-- belongs to the SAME aura identity and existing inferred claim. Never use an
-- empty/missing aura scan as proof of removal, and never retime a cast witness.
function Model:RefineHelpfulTime(guid, spellID, identity, started, observedAt, origin)
    if not guid or type(identity) ~= 'string'
        or type(started) ~= 'number' or started ~= started or started < 0
        or type(observedAt) ~= 'number' or observedAt ~= observedAt
        or started > observedAt + .05 then return false end
    local canonical = ns.Data.castToSpell[spellID] or spellID
    local caster = self.casters[guid]
    local row = caster and caster.cooldowns[canonical]
    if not row or row.evidenceSource ~= 'helpful-aura' or not row.timingEstimated
        or row.evidenceIdentity ~= identity or started > row.started
        or observedAt - started > 300 or observedAt < row.started then return false end
    local before = row.started
    row.started, row.timingEstimated = started, false
    if ns.Claims and row.claim then
        ns.Claims.Witness(row.claim,'readable-aura-start',origin or 'CC aura',observedAt)
        ns.Claims.Revise(self,row.claim,observedAt,'same-aura-timestamp',
            before,started,'aura-start')
    end
    self:PruneCooldowns(observedAt)
    return true
end

-- A landed loss-of-control effect proves an effect, NOT its caster. Keep
-- independent events separate so two different enemies cannot overwrite one
-- another's cooldown. This never adds or changes a DR application.
function Model:RefineUnattributedTime(spellID, witnessKey, started, observedAt)
    if type(started) ~= 'number' or started ~= started or started < 0
        or type(observedAt) ~= 'number' or observedAt ~= observedAt
        or started > observedAt + .05 or observedAt - started > 120 then return false end
    local canonical = ns.Data.castToSpell[spellID] or spellID
    for _, row in ipairs(self.anonymousCooldowns) do
        if row.spellID == canonical and row.evidenceIdentity == witnessKey
            and row.timingEstimated and started <= row.started + APPLICATION_EPSILON
            and observedAt >= row.observedAt then
            local before = row.started
            row.started, row.timingEstimated = started, false
            if ns.Claims and row.claim then
                ns.Claims.Witness(row.claim,'readable-loc-start','CC player LoC',observedAt)
                ns.Claims.Revise(self,row.claim,observedAt,'same-loc-timestamp',
                    before,started,'loc-effect-start')
            end
            self:PruneCooldowns(observedAt)
            return true
        end
    end
    return false
end

function Model:WitnessUnattributedCooldown(spellID, eventTime, observedAt, witnessKey, overrides, timingEstimated)
    if type(observedAt) ~= 'number' or observedAt ~= observedAt or observedAt < 0
        or type(eventTime) ~= 'number' or eventTime ~= eventTime or eventTime < 0
        or eventTime > observedAt + 0.05 or observedAt - eventTime > 120
        or type(witnessKey) ~= 'string' or #witnessKey == 0 or #witnessKey > 160 then return false end
    local canonicalID = ns.Data.castToSpell[spellID] or spellID
    local ability = ns.Data.spells[canonicalID]
    if not ability or not ability.cdMax or ability.cdMax <= 0 then return false end
    self:PruneCooldowns(observedAt)
    if self.anonymousWitnesses[witnessKey] then return false end
    self.anonymousWitnesses[witnessKey] = observedAt
    trimOldest(self.anonymousWitnesses, MAX_ANONYMOUS_WITNESSES)
    local duration, minimum = ability.cdMax, ability.cdMin or ability.cdMax
    local override = overrides and overrides[canonicalID]
    if type(override) == 'number' and override > 0 then duration, minimum = override, override end
    if observedAt >= eventTime + duration then return false end
    self.anonymousCooldowns[#self.anonymousCooldowns+1] = {
        spellID = canonicalID, category = ability.category,
        started = eventTime, duration = duration, minimum = minimum,
        observedAt = observedAt, evidenceSource = 'player-loc',
        evidenceIdentity = witnessKey,
        anonymous = true, timingEstimated = timingEstimated == true,
        interrupt = ability.interrupt == true,
        claim = ns.Claims and ns.Claims.Issue(self,canonicalID,'player-loc',
            eventTime,true,timingEstimated,{origin='CC player LoC',observedAt=observedAt}) or nil,
    }
    while #self.anonymousCooldowns > MAX_ANONYMOUS_COOLDOWNS do
        table.remove(self.anonymousCooldowns, 1)
    end
    return true
end

function Model:GetCooldowns(now, filterGuid, includeClaims)
    self:PruneCooldowns(now)
    local rows = {}
    for guid, caster in pairs(self.casters) do
        if not filterGuid or filterGuid == guid then
            for _, cooldown in pairs(caster.cooldowns) do
                rows[#rows + 1] = {
                    guid = guid,
                    spellID = cooldown.spellID,
                    category = cooldown.category,
                    started = cooldown.started,
                    duration = cooldown.duration,
                    remaining = math.max(0, cooldown.duration - (now - cooldown.started)),
                    earlyRemaining = math.max(0, cooldown.minimum - (now - cooldown.started)),
                    manual = cooldown.manual,
                    interrupt = cooldown.interrupt,
                    evidenceSource = cooldown.evidenceSource,
                    timingEstimated = cooldown.timingEstimated,
                    claimID = cooldown.claim and cooldown.claim.id or nil,
                    claimBasis = cooldown.claim and cooldown.claim.basis or nil,
                    claimRevisionCount = cooldown.claim and #cooldown.claim.revisions or 0,
                    claim = includeClaims and ns.Claims and ns.Claims.Snapshot(cooldown.claim) or nil,
                }
            end
        end
    end
    if not filterGuid then
        for _, cooldown in ipairs(self.anonymousCooldowns) do
            rows[#rows + 1] = {
                anonymous = true, spellID = cooldown.spellID, category = cooldown.category,
                started = cooldown.started, duration = cooldown.duration,
                remaining = math.max(0, cooldown.duration - (now - cooldown.started)),
                earlyRemaining = math.max(0, cooldown.minimum - (now - cooldown.started)),
                evidenceSource = cooldown.evidenceSource, timingEstimated = cooldown.timingEstimated,
                interrupt = cooldown.interrupt,
                claimID = cooldown.claim and cooldown.claim.id or nil,
                claimBasis = cooldown.claim and cooldown.claim.basis or nil,
                claimRevisionCount = cooldown.claim and #cooldown.claim.revisions or 0,
                claim = includeClaims and ns.Claims and ns.Claims.Snapshot(cooldown.claim) or nil,
            }
        end
    end
    -- Select one ordering for the whole collection: switching between time
    -- and GUID per pair creates cycles in a mixed known/anonymous feed.
    local mixed = not filterGuid and #self.anonymousCooldowns > 0
    local rowOrder = {}
    for index, row in ipairs(rows) do rowOrder[row] = index end
    table.sort(rows, function(a, b)
        if mixed then
            if a.started ~= b.started then return a.started > b.started end
            if a.anonymous ~= b.anonymous then return a.anonymous == true end
        end
        if (a.guid or '') ~= (b.guid or '') then return (a.guid or '') < (b.guid or '') end
        local aOrder, bOrder = self.categoryOrder[a.category] or 999, self.categoryOrder[b.category] or 999
        if aOrder ~= bOrder then return aOrder < bOrder end
        if a.spellID ~= b.spellID then return a.spellID < b.spellID end
        -- Distinct anonymous witnesses can have identical spell/time fields.
        -- Their insertion order supplies a stable final tie break.
        return rowOrder[a] < rowOrder[b]
    end)
    return rows
end
