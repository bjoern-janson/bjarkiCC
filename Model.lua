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

function Model.New(resetSeconds)
    local order = {}
    for index, category in ipairs(ns.Data.categories) do order[category.key] = index end
    return setmetatable({
        resetSeconds = resetSeconds or 20,
        units = {},
        estimates = {}, -- Own casts are predictions, never observed applications.
        casters = {},
        categoryOrder = order,
    }, Model)
end

local function inWindow(state, now, resetSeconds)
    return state and now < state.appliedAt + resetSeconds
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
    }
end

local function applicationTime(effect, now)
    local start = effect.appliedAt
    if type(start) == "number" and start == start and start >= 0 and start <= now then return start end
end

local function refreshedApplication(previous, effect, start)
    if not previous or not start then return false end
    local priorStart = previous.appliedAt or previous.firstSeenAt
    if not priorStart or start <= priorStart + APPLICATION_EPSILON then return false end
    if effect.applicationSource == "loc" then
        if previous.applicationSource == "loc" or not previous.appliedAt then return true end
        -- A start after the previous application was already observed cannot
        -- merely correct that application's duration-derived timestamp.
        return previous.firstSeenAt and start > previous.firstSeenAt + APPLICATION_EPSILON
    end
    -- A duration correction can move expiration-duration without another CC.
    -- A derived refresh needs both boundaries to change, from the same sensor.
    -- Diminished CC can end earlier even though its application is newer.
    return (previous.applicationSource == "aura" or not previous.appliedAt) and effect.applicationSource == "aura"
        and previous.expires and effect.expires
        and math.abs(effect.expires - previous.expires) > APPLICATION_EPSILON
end

function Model:Observe(guid, effects, now, complete)
    if not guid then return end
    local unit = self.units[guid]
    if not unit then
        unit = {seen = now, effects = {}, categories = {}}
        self.units[guid] = unit
    end
    unit.seen = now
    -- Keep the last application per category even after its visible timer ends.
    -- A delayed readable witness chains by application time, not arrival time.
    -- Each category also has at most one flat predecessor for timing correction.
    -- Category count is fixed by Data; retained GUIDs have the MAX_UNITS cap.

    if complete then
        if not unit.completeSince then unit.completeSince = now end
    else
        -- An unreadable/partial snapshot cannot establish a removal or preserve
        -- the earlier history proof. It also cannot change an observed timer.
        unit.completeSince = nil
        for _, state in pairs(unit.categories) do
            state.uncertain = true
        end
    end

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
        local previous = unit.effects[key]
        local same = previous and previous.category == category and previous.spellID == effect.spellID
        local state = unit.categories[category]
        local preciseStart = applicationTime(effect, now)
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
                local prior = predecessor(state)
                if not inWindow(state, appliedAt, self.resetSeconds) then
                    state = {
                        stage = 0,
                        activeCount = 0,
                        uncertain = not unit.completeSince or appliedAt < unit.completeSince + self.resetSeconds,
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
                state.confirmationStage = matchedPrediction and candidate.stage or nil
                state.confirmationSentAt = matchedPrediction and (candidate.sentAt or candidate.appliedAt) or nil
                state.confirmationAppliedAt = matchedPrediction and candidate.appliedAt or nil
                if estimatedTime or (refreshed and effect.applicationSource == "aura") then state.uncertain = true end
            end
            if prediction and candidate and (matchedPrediction or candidate.appliedAt <= appliedAt) then
                prediction.categories[category] = nil
            end
        elseif same and preciseStart and preciseStart <= previous.firstSeenAt
            and (not previous.appliedAt or (previous.applicationSource == "aura" and effect.applicationSource == "loc"))
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
                local continuing = inWindow(prior, preciseStart, self.resetSeconds)
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
                    or preciseStart < unit.completeSince + self.resetSeconds then state.uncertain = true end
            end
        elseif state and previous.expires and effect.expires and effect.expires > previous.expires then
            -- A stable key with an extended expiry may be a refreshed CC. It
            -- provides no reliable new application, so never restart its timer
            -- or invent a stage. An expired timer stays expired.
            state.uncertain = true
        end
        nextEffects[key] = {category = category, spellID = effect.spellID,
            expires = effect.expires or (same and previous.expires or nil),
            appliedAt = preciseStart or (same and previous.appliedAt or nil),
            applicationSource = preciseStart and effect.applicationSource or (same and previous.applicationSource or nil),
            firstSeenAt = same and not refreshed and previous.firstSeenAt or now}
    end

    for _, state in pairs(unit.categories) do state.activeCount = 0 end
    for _, effect in pairs(nextEffects) do
        local state = unit.categories[effect.category]
        if state then state.activeCount = state.activeCount + 1 end
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
    if not inWindow(actual, now, self.resetSeconds) then actual = nil end
    -- Prefer an application already observed during this cast. This does not
    -- claim to identify its caster; it merely avoids stacking a guess on it.
    if actual and actual.appliedAt >= (sentAt or now) then return false end
    local previous = prediction.categories[category]
    local base = actual
    if previous and (not base or previous.appliedAt > base.appliedAt) then base = previous end
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
        if inWindow(state, now, self.resetSeconds) then states[category] = state end
    end
    local prediction = includeEstimates ~= false and guid and self.estimates[guid]
    for category, state in pairs(prediction and prediction.categories or {}) do
        if not states[category] or state.appliedAt > states[category].appliedAt then
            states[category] = state
        end
    end
    for category, state in pairs(states) do
        local estimated = prediction and prediction.categories[category] == state or false
        local active = not estimated and state.activeCount > 0
        local inferredStage = includeEstimates ~= false and not estimated and state.inferredStage
        local stageEstimated = inferredStage ~= nil and inferredStage ~= false and inferredStage > state.stage
        local observed = unit and unit.categories[category]
        rows[#rows + 1] = {
            category = category,
            spellID = state.spellID,
            stage = stageEstimated and inferredStage or state.stage,
            observedStage = estimated and (inWindow(observed, now, self.resetSeconds) and observed.stage or 0) or state.stage,
            stageEstimated = stageEstimated,
            remaining = math.max(0, self.resetSeconds - (now - state.appliedAt)),
            duration = self.resetSeconds,
            started = state.appliedAt,
            active = active,
            uncertain = estimated or stageEstimated or state.uncertain,
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
