local _, ns = ...
local Safe = ns.Safe
local Observer = {}
ns.Observer = Observer
-- The first readable token owns a shared GUID's snapshot. Player must win so
-- self target/focus aliases retain the player-only Loss of Control fallback.
local trackedUnits = {"player", "target", "focus"}
local MAX_WITNESSES = 512
local APPLICATION_EPSILON = 0.001 -- Match the model's timestamp rounding tolerance.
local MAX_API_FAILURE_KINDS = 32
local MAX_API_FAILURE_COUNT = 2147483647
local apiFailureKinds = 0

local function countEffects(effects)
    local count = 0
    for _ in pairs(effects) do count = count + 1 end
    return count
end

local function boundedIDs(unmapped)
    local ids = {}
    for id in pairs(unmapped) do ids[#ids + 1] = id end
    table.sort(ids)
    while #ids > 12 do ids[#ids] = nil end
    return ids
end

local function mergeIDs(first, second)
    local ids = {}
    for _, id in ipairs(first or {}) do ids[id] = true end
    for _, id in ipairs(second or {}) do ids[id] = true end
    return boundedIDs(ids)
end

local function auraResult(effects, complete, unmapped)
    return effects, complete, {mappedAuras = countEffects(effects), unmappedSpellIDs = boundedIDs(unmapped)}
end

-- Readable data alone is eligible for classification. pcall catches API or
-- record-access failures; it is never used to infer the content of a secret.
local function recordApiFailure(operation, unit, value)
    -- Operation names come only from fixed call sites below, never API values.
    local failure = Observer.apiFailures[operation]
    if not failure then
        if apiFailureKinds >= MAX_API_FAILURE_KINDS then return end
        failure = {count = 0}
        Observer.apiFailures[operation] = failure
        apiFailureKinds = apiFailureKinds + 1
    end
    failure.count = math.min(failure.count + 1, MAX_API_FAILURE_COUNT)
    local token = Safe.String(unit)
    failure.lastUnit = (token == "player" or token == "target" or token == "focus") and token or "other"
    -- Errors can themselves be secret or arbitrary Lua objects. Do not format
    -- them. Keep only the first/latest readable string, with no chat markup.
    local message = Safe.String(value)
    if message then
        message = message:sub(1, 240):gsub("[%c|]", "?")
        failure.firstMessage = failure.firstMessage or message
        failure.lastMessage = message
    end
end

local function call(operation, unit, fn, ...)
    if type(fn) ~= "function" then
        Observer.stats.missingApis = Observer.stats.missingApis + 1
        return nil, false
    end
    local ok, value = pcall(fn, ...)
    if not ok then
        Observer.stats.apiErrors = Observer.stats.apiErrors + 1
        recordApiFailure(operation, unit, value)
        return nil, false
    end
    if not Safe.Readable(value) then
        Observer.stats.restricted = Observer.stats.restricted + 1
        return nil, false
    end
    return value, true
end

local function field(record, key, operation, unit)
    return call(operation, unit, function() return record[key] end)
end

local function number(value)
    local v = Safe.Number(value)
    if v and v == v and v > -math.huge and v < math.huge then return v end
end

local function identifier(value)
    local v = number(value)
    if v and v > 0 and v == math.floor(v) then return v end
end

local function unitToken(value)
    local token = Safe.String(value)
    if not token or #token > 40 then return nil end
    if token == "player" or token == "target" or token == "focus"
        or token == "mouseover" or token == "pet" or token == "targettarget"
        or token == "focustarget" then return token end
    if token:match("^nameplate%d+$") or token:match("^arena%d+$")
        or token:match("^arenapet%d+$") or token:match("^party%d+$")
        or token:match("^partypet%d+$") or token:match("^raid%d+$")
        or token:match("^raidpet%d+$") or token:match("^boss%d+$") then return token end
end

local function guidString(value)
    local guid = Safe.String(value)
    if guid and #guid <= 128 and guid:match("^[A-Za-z]+%-[%w%-]+$") then return guid end
end

local function applicationTime(value, now)
    local start = number(value)
    if start and start >= 0 and start <= now then return start end
end

local function auraSnapshot(unit, now)
    local effects, unmapped = {}, {}
    local api = C_UnitAuras
    if type(api) ~= "table" or type(api.GetAuraDataByIndex) ~= "function" then
        Observer.stats.missingApis = Observer.stats.missingApis + 1
        return auraResult(effects, false, unmapped)
    end
    local complete = true
    for index = 1, 255 do
        -- Forever can tell us up front that reading this index will be
        -- forbidden. Skip the known-error call, but NEVER treat the omitted
        -- aura (or the remaining list) as an absence witness.
        local predicate = C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret
        if type(predicate) == "function" then
            local ok, secret = pcall(predicate, unit, index, "HARMFUL")
            if ok and Safe.Boolean(secret) == true then
                Observer.stats.predictedSecretAuraIndexes =
                    Observer.stats.predictedSecretAuraIndexes + 1
                return auraResult(effects, false, unmapped)
            end
        end
        local aura, readable = call("C_UnitAuras.GetAuraDataByIndex", unit, api.GetAuraDataByIndex, unit, index, "HARMFUL")
        if not readable then return auraResult(effects, false, unmapped) end
        if aura == nil then return auraResult(effects, complete, unmapped) end
        if type(aura) ~= "table" then return auraResult(effects, false, unmapped) end
        local rawSpell, spellReadable = field(aura, "spellId", "AuraData.spellId", unit)
        local spellID = identifier(rawSpell)
        if not spellReadable or not spellID then
            complete = false
        else
            local category = ns.Data.auraCategory[spellID]
            if category then
                local rawInstance, instanceReadable = field(aura, "auraInstanceID", "AuraData.auraInstanceID", unit)
                local instanceID = identifier(rawInstance)
                if not instanceReadable or not instanceID then
                    complete = false
                else
                    local rawExpiry = field(aura, "expirationTime", "AuraData.expirationTime", unit)
                    local expires = number(rawExpiry)
                    if expires and expires <= 0 then expires = nil end
                    local rawDuration = field(aura, "duration", "AuraData.duration", unit)
                    local duration = number(rawDuration)
                    local appliedAt
                    if expires and duration and duration > 0 then
                        appliedAt = applicationTime(expires - duration, now)
                    end
                    effects["a:" .. tostring(instanceID)] = {
                        category = category, spellID = spellID, expires = expires,
                        appliedAt = appliedAt, applicationSource = appliedAt and "aura" or nil,
                    }
                end
            else
                unmapped[spellID] = true
            end
        end
    end
    Observer.stats.scanCaps = Observer.stats.scanCaps + 1
    return auraResult(effects, false, unmapped)
end

-- The index scan requires blanket aura access. This documented getter instead
-- requires a non-secret aura: only a readable positive matching this exact
-- spell/instance is evidence. Nil, errors and hidden values never prove absence.
-- The reviewed effect IDs below keep this bounded; no cast identifies a victim.
local function exactAura(unit, wantedSpellID, now)
    local api = C_UnitAuras
    if type(api) ~= "table" or type(api.GetUnitAuraBySpellID) ~= "function" then
        return nil, "unavailable"
    end
    local aura, readable = call("C_UnitAuras.GetUnitAuraBySpellID", unit,
        api.GetUnitAuraBySpellID, unit, wantedSpellID)
    if not readable then return nil, "blocked" end
    if aura == nil then return nil, "none" end
    if type(aura) ~= "table" then return nil, "identity-unavailable" end
    local rawSpell = field(aura, "spellId", "AuraData.spellId", unit)
    local spellID = identifier(rawSpell)
    if not spellID then return nil, "identity-unavailable" end
    if spellID ~= wantedSpellID then return nil, "mismatch" end
    local rawInstance = field(aura, "auraInstanceID", "AuraData.auraInstanceID", unit)
    local instanceID = identifier(rawInstance)
    if not instanceID then return nil, "identity-unavailable" end
    local category = ns.Data.auraCategory[spellID]
    if not category then return nil, "unmapped" end
    local rawExpiry = field(aura, "expirationTime", "AuraData.expirationTime", unit)
    local expires = number(rawExpiry)
    if expires and expires > 0 and expires <= now then return nil, "expired" end
    if expires and expires <= 0 then expires = nil end
    local rawDuration = field(aura, "duration", "AuraData.duration", unit)
    local duration = number(rawDuration)
    local appliedAt
    if expires and duration and duration > 0 then
        appliedAt = applicationTime(expires - duration, now)
    end
    return {["a:" .. tostring(instanceID)] = {
        category = category, spellID = spellID, expires = expires,
        appliedAt = appliedAt, applicationSource = appliedAt and "aura" or nil,
    }}, "confirmed"
end

-- AoE stuns have no provable victim from the cast event. Independently
-- identify only actual harmful effects, never the item/racial activation.
local aoeStunEffects = {[20549] = true, [4068] = true}
local graspEffects = {19975, 19974, 19973, 19972, 19971, 19970}
local graspEffectIDs = {}
for _, id in ipairs(graspEffects) do graspEffectIDs[id] = true end
-- A single fixed status summarizes six positive-only queries. Confirmed takes
-- precedence; otherwise retain the strongest limitation regardless of rank.
local exactStatusPriority = {none=1, unavailable=2, unmapped=3, expired=4,
    mismatch=5, ["identity-unavailable"]=6, blocked=7, confirmed=8}
local function exactGrasp(unit, now)
    local effects, status = {}, "none"
    for _, spellID in ipairs(graspEffects) do
        local additional, result = exactAura(unit, spellID, now)
        if exactStatusPriority[result] > exactStatusPriority[status] then status = result end
        if additional then
            for key, effect in pairs(additional) do effects[key] = effect end
        end
    end
    return next(effects) and effects or nil, status
end

-- UNIT_AURA addedAuras is fully secret on restricted Forever clients. Still
-- consume rare readable positive records before they disappear between scans.
-- Never infer an absence from this delta or attempt to interpret secret data.
-- Restrict this extra path to the two confirmed AoE effect IDs.
local function addedAoEEvent(unit, updateInfo, now)
    if not Safe.Readable(updateInfo) or type(updateInfo) ~= "table" then
        return nil, "restricted"
    end
    local added, readable = field(updateInfo, "addedAuras", "UNIT_AURA.addedAuras", unit)
    if not readable then return nil, "restricted" end
    if added == nil then return nil, "no-added" end
    if not Safe.Readable(added) or type(added) ~= "table" then return nil, "restricted" end
    local length = number(Safe.Call(function() return #added end))
    if not length or length < 0 or length ~= math.floor(length) then return nil, "restricted" end
    local results, accepted = {}, 0
    for i = 1, math.min(length, 64) do
        local aura, ok = field(added, i, "UNIT_AURA.addedAuras.item", unit)
        if ok and type(aura) == "table" then
            local rawID = field(aura, "spellId", "AuraData.spellId", unit)
            local id = identifier(rawID)
            if id and aoeStunEffects[id] and ns.Data.auraCategory[id] == "stun" then
                local rawHarmful = field(aura, "isHarmful", "AuraData.isHarmful", unit)
                local harmful = Safe.Boolean(rawHarmful)
                local rawInstance = field(aura, "auraInstanceID", "AuraData.auraInstanceID", unit)
                local instance = identifier(rawInstance)
                if harmful == true and instance then
                    local rawExpiry = field(aura, "expirationTime", "AuraData.expirationTime", unit)
                    local expires = number(rawExpiry)
                    if not expires or expires <= 0 or expires > now then
                        if expires and expires <= 0 then expires = nil end
                        local rawDuration = field(aura, "duration", "AuraData.duration", unit)
                        local duration = number(rawDuration)
                        local appliedAt = expires and duration and duration > 0
                            and applicationTime(expires - duration, now) or nil
                        local key = "a:" .. tostring(instance)
                        results[key] = {category = "stun", spellID = id,
                            expires = expires, appliedAt = appliedAt,
                            applicationSource = appliedAt and "aura" or nil}
                        accepted = accepted + 1
                    end
                end
            end
        end
    end
    return next(results) and results or nil, length > 64 and "capped" or "readable", accepted
end

local function byUnitAvailable()
    return type(C_LossOfControl) == "table"
        and type(C_LossOfControl.GetActiveLossOfControlDataCountByUnit) == "function"
        and type(C_LossOfControl.GetActiveLossOfControlDataByUnit) == "function"
end

local function lossOfControlSnapshot(now, unit)
    local effects, unmapped = {}, {}
    local api = C_LossOfControl
    if type(api) ~= "table" then
        Observer.stats.missingApis = Observer.stats.missingApis + 1
        return effects, false
    end
    -- The player-only API has no conditional-secret-return annotation. ByUnit
    -- records are conditionally secret; they are only positive witnesses after
    -- the same field guards as the player API, never an access workaround.
    local rawCount, countReadable
    if unit then
        rawCount, countReadable = call("C_LossOfControl.GetActiveLossOfControlDataCountByUnit", unit,
            api.GetActiveLossOfControlDataCountByUnit, unit)
    else
        rawCount, countReadable = call("C_LossOfControl.GetActiveLossOfControlDataCount", "player",
            api.GetActiveLossOfControlDataCount)
    end
    local count = number(rawCount)
    if not countReadable or not count or count < 0 or count > 255 or count ~= math.floor(count) then
        return effects, false
    end
    local complete = true
    for index = 1, count do
        local data, readable
        if unit then
            data, readable = call("C_LossOfControl.GetActiveLossOfControlDataByUnit", unit,
                api.GetActiveLossOfControlDataByUnit, unit, index)
        else
            data, readable = call("C_LossOfControl.GetActiveLossOfControlData", "player",
                api.GetActiveLossOfControlData, index)
        end
        if not readable or type(data) ~= "table" then
            complete = false
        else
            local rawSpell, spellReadable = field(data, "spellID", "LossOfControlData.spellID", unit or "player")
            local spellID = identifier(rawSpell)
            if not spellReadable or not spellID then
                complete = false
            else
                -- locType is deliberately not a category fallback: e.g. STUN
                -- does not distinguish separate Classic stun DR families.
                local category = ns.Data.auraCategory[spellID]
                if category then
                    local rawInstance = field(data, "auraInstanceID", "LossOfControlData.auraInstanceID", unit or "player")
                    local instanceID = identifier(rawInstance)
                    local rawStart = field(data, "startTime", "LossOfControlData.startTime", unit or "player")
                    local start = applicationTime(rawStart, now)
                    local key
                    if instanceID then
                        key = "a:" .. tostring(instanceID)
                    elseif start then
                        key = "l:s:" .. tostring(spellID) .. ":" .. tostring(start)
                    end
                    if not key then
                        complete = false
                    else
                        local rawDuration = field(data, "duration", "LossOfControlData.duration", unit or "player")
                        local duration = number(rawDuration)
                        -- Keep raw LoC duration separate from the expiry fallback.
                        -- A remaining-time estimate cannot establish full duration.
                        local reportedDuration = start and duration and duration > 0
                            and duration <= 120 and duration or nil
                        local expires
                        if start and duration and duration > 0 then
                            expires = start + duration
                        else
                            local rawRemaining = field(data, "timeRemaining", "LossOfControlData.timeRemaining", unit or "player")
                            local remaining = number(rawRemaining)
                            if remaining and remaining > 0 then expires = now + remaining end
                        end
                        effects[key] = {category = category, spellID = spellID, expires = expires,
                            appliedAt = start, applicationSource = start and "loc" or nil,
                            reportedDuration = reportedDuration,
                            fallbackIdentity = not instanceID}
                    end
                else
                    unmapped[spellID] = true
                end
            end
        end
    end
    return effects, complete, boundedIDs(unmapped), count
end

local function mergeEffects(effects, additional)
    for key, effect in pairs(additional) do
        -- An exact aura-instance witness is the same application in either API.
        -- Prefer the explicit LoC start to a duration-derived aura boundary.
        local existing = effects[key]
        if not existing then effects[key] = effect
        elseif effect.applicationSource == "loc" and effect.appliedAt then
            existing.appliedAt, existing.applicationSource = effect.appliedAt, effect.applicationSource
            existing.expires = effect.expires or existing.expires
            existing.reportedDuration = effect.reportedDuration
        end
    end
end

local function reconcileWitnesses(effects, previous)
    local result, ambiguous = {}, false
    local prior = previous and previous.witnesses or {}
    local function sameFallbackTime(first, second)
        return first.fallbackIdentity and second.fallbackIdentity
            and first.appliedAt and second.appliedAt
            and math.abs(first.appliedAt - second.appliedAt) <= APPLICATION_EPSILON
    end
    local function add(key, effect)
        local existing = result[key]
        if not existing or (effect.applicationSource == "loc" and effect.appliedAt
            and (existing.applicationSource ~= "loc" or not existing.appliedAt or effect.appliedAt > existing.appliedAt)) then
            result[key] = effect
        end
    end
    for key, effect in pairs(effects) do
        local canonical, candidates = nil, {}
        if not prior[key] then
            -- A startTime-only LoC identity cannot prove that another source's
            -- same-spell instance is a second application. Keep the earlier
            -- identity (or the current instance) and flag the ambiguity.
            for oldKey, old in pairs(prior) do
                if old.spellID == effect.spellID and old.category == effect.category
                    and ((old.fallbackIdentity == true) ~= (effect.fallbackIdentity == true)
                        or sameFallbackTime(old, effect)) then
                    candidates[oldKey] = old
                end
            end
            if effect.fallbackIdentity then
                for currentKey, current in pairs(effects) do
                    if not current.fallbackIdentity and current.spellID == effect.spellID
                        and current.category == effect.category then candidates[currentKey] = current end
                end
            end
            local count = countEffects(candidates)
            if count > 0 then
                ambiguous = true
                if count == 1 then canonical = next(candidates) end
                if canonical then
                    local witness = {}
                    for field, value in pairs(candidates[canonical]) do witness[field] = value end
                    -- Identity may survive a sensor handoff, but raw duration is
                    -- evidence only from this observation's accepted LoC start.
                    witness.reportedDuration = nil
                    if effect.applicationSource == "loc" and effect.appliedAt then
                        -- Identity ambiguity does not erase a readable start.
                        -- Keep the canonical key/fallback policy so repeated
                        -- polls cannot create another copy of this application.
                        local timed = {}
                        for field, value in pairs(witness) do timed[field] = value end
                        -- Rounding in a no-instance key is not a new CC. Keep
                        -- the original boundary so repeated corrections cannot
                        -- slide the tolerance forward on every poll.
                        timed.appliedAt = sameFallbackTime(witness, effect) and witness.appliedAt or effect.appliedAt
                        timed.applicationSource = "loc"
                        timed.expires = effect.expires or witness.expires
                        timed.reportedDuration = effect.reportedDuration
                        witness = timed
                    end
                    add(canonical, witness)
                end
            else
                add(key, effect)
            end
        else
            add(key, effect)
        end
    end
    return result, ambiguous
end

local function retainWitnesses(effects, previous, complete)
    local witnesses, count, capped = {}, 0, false
    if not complete and previous then
        for key, effect in pairs(previous.witnesses or {}) do witnesses[key] = effect; count = count + 1 end
    end
    for key, effect in pairs(effects) do
        if witnesses[key] or count < MAX_WITNESSES then
            if not witnesses[key] then count = count + 1 end
            witnesses[key] = effect
        else
            -- Do not grow model memory indefinitely while every removal is
            -- unreadable. Losing a witness here is reported as limited coverage.
            effects[key] = nil
            capped = true
        end
    end
    return witnesses, capped
end

local function forget(guid)
    if guid then ns.model:Forget(guid) end
end

local function unavailableState()
    return {status = "unavailable", sensor = "none", coverageLimited = false,
        mappedAuras = 0, unmappedSpellIDs = {}, byUnitAvailable = false, mappedLoC = 0,
        reason = "No readable player identity for this unit."}
end

local function readIdentity(unit)
    local rawGuid = call("UnitGUID", unit, UnitGUID, unit)
    local guid = guidString(rawGuid)
    if not guid or not guid:match("^Player%-") then return nil end
    if unit ~= "player" then
        local isPlayer = call("UnitIsPlayer", unit, UnitIsPlayer, unit)
        -- A readable Player- GUID is already positive identity evidence.
        -- An inaccessible secondary boolean cannot turn that into a nonplayer.
        -- A readable contradiction still vetoes the association.
        if Safe.Boolean(isPlayer) == false then return nil end
    end
    return guid
end

local function exactPlayerHandoff(unit, previous, effects, complete, sensor, ambiguous, capped)
    if unit ~= "player" or not previous or previous.sensor ~= "aura" or sensor ~= "loc"
        or previous.status ~= "readable" or not complete or ambiguous or capped
        or not next(effects) then return false end
    local prior = previous.witnesses or {}
    for key, effect in pairs(effects) do
        local old = prior[key]
        if not key:match("^a:%d+$") or effect.fallbackIdentity or not old or old.fallbackIdentity
            or old.spellID ~= effect.spellID or old.category ~= effect.category
            or old.applicationSource ~= "aura" then return false end
        local start, expires = number(old.appliedAt), number(old.expires)
        if not start or not expires or expires <= start or expires - start > 120 then return false end
    end
    for key in pairs(prior) do if not effects[key] then return false end end
    return true
end

local function scanGuid(unit, guid, previous, now, aliases, eventProof)
    local effects, complete, sensor, limited
    local diagnostics = {mappedAuras = 0, unmappedSpellIDs = {}, mappedLoC = 0,
        byUnitAvailable = unit ~= "player" and byUnitAvailable() or false}
    if unit == "player" and Observer.playerLoCSelected then
        local locUnmapped
        effects, complete, locUnmapped = lossOfControlSnapshot(now)
        sensor, limited = "loc", true
        diagnostics.mappedLoC = countEffects(effects)
        diagnostics.unmappedSpellIDs = locUnmapped or {}
    else
        local auraInfo
        effects, complete, auraInfo = auraSnapshot(unit, now)
        diagnostics.auraComplete = complete
        diagnostics.mappedAuras = auraInfo.mappedAuras
        diagnostics.unmappedSpellIDs = auraInfo.unmappedSpellIDs
        sensor, limited = "aura", false
        if unit == "player" and not complete then
            local locUnmapped
            effects, complete, locUnmapped = lossOfControlSnapshot(now)
            sensor, limited = "loc", true
            diagnostics.mappedLoC = countEffects(effects)
            diagnostics.unmappedSpellIDs = mergeIDs(diagnostics.unmappedSpellIDs, locUnmapped)
            -- Once the fallback can provide a complete LoC snapshot, retain it
            -- for this observer session. Empty auras become readable as CC ends;
            -- switching back then would Forget the just-started DR reset timer.
            if complete then Observer.playerLoCSelected = true end
        elseif unit ~= "player" and not complete then
            limited = true
            local exactEffects
            exactEffects, diagnostics.stompLookup = exactAura(unit, 20549, now)
            if exactEffects then mergeEffects(effects, exactEffects); sensor = "aura+exact" end
            -- Iron Grenade's effect 4068 is a real stun aura, not a reliable
            -- target from the player's thrown-item cast. Require a positive.
            local grenade
            grenade, diagnostics.grenadeLookup = exactAura(unit, 4068, now)
            if grenade then mergeEffects(effects, grenade); sensor = "aura+exact" end
            local roots
            roots, diagnostics.graspLookup = exactGrasp(unit, now)
            if roots then mergeEffects(effects, roots); sensor = "aura+exact" end
            -- A targeted, successful own cast is NOT proof of application.
            -- It can, however, select a small exact-spell QUERY on the actual
            -- resolved victim. Only a readable positive aura instance counts.
            local pending = ns.model.GetPendingExactSpellIDs
                and ns.model:GetPendingExactSpellIDs(guid, now) or {}
            local lookup, queryCount, positiveCount = "none", 0, 0
            for _, spellID in ipairs(pending) do
                if not aoeStunEffects[spellID] and not graspEffectIDs[spellID] then
                    local additional, result = exactAura(unit, spellID, now)
                    queryCount = queryCount + 1
                    if exactStatusPriority[result] > exactStatusPriority[lookup] then lookup = result end
                    if additional then
                        mergeEffects(effects, additional)
                        positiveCount = positiveCount + 1
                        sensor = "aura+exact"
                    end
                end
            end
            if queryCount > 0 then
                diagnostics.castLookup = lookup
                diagnostics.castLookupQueries = queryCount
                diagnostics.castLookupHits = positiveCount
            end
            if diagnostics.byUnitAvailable then
                local locEffects, locComplete, locUnmapped, locCount = lossOfControlSnapshot(now, unit)
                diagnostics.byUnitComplete = locComplete
                diagnostics.byUnitCount = locCount
                diagnostics.mappedLoC = countEffects(locEffects)
                diagnostics.unmappedSpellIDs = mergeIDs(diagnostics.unmappedSpellIDs, locUnmapped)
                mergeEffects(effects, locEffects)
                if diagnostics.mappedLoC > 0 then
                    sensor = (exactEffects or grenade or roots) and "aura+exact+loc" or "aura+loc"
                end
            end
            -- LoC does not enumerate every debuff. Even a complete/empty LoC
            -- list must not turn this restricted aura scan into absence proof.
        end
    end
    -- Only after collecting every positive from the owning token (including
    -- exact aura and LoC fallbacks), probe another readable alias for this GUID.
    -- A complete Focus scan is valuable absence evidence ONLY if it does not
    -- contradict any simultaneously readable positive from Target. Never let
    -- an apparently empty alias erase a distinct LoC or exact witness.
    if unit ~= "player" and not complete then
        for _, alias in ipairs(aliases or {}) do
            if alias ~= unit and readIdentity(alias) == guid then
                local other, otherComplete, otherInfo = auraSnapshot(alias, now)
                diagnostics.aliasUnit = alias
                diagnostics.aliasCoverage = otherComplete and "complete" or "partial"
                diagnostics.aliasMapped = otherInfo.mappedAuras
                diagnostics.unmappedSpellIDs = mergeIDs(diagnostics.unmappedSpellIDs, otherInfo.unmappedSpellIDs)
                if otherComplete then
                    local contradiction = false
                    for key in pairs(effects) do
                        if not other[key] then contradiction = true; break end
                    end
                    mergeEffects(other, effects)
                    effects = other
                    diagnostics.mappedAuras = countEffects(effects)
                    if contradiction then
                        -- An observed hit beats a second token's empty snapshot.
                        -- Treat the relation as incomplete until a new complete
                        -- uncontested observation establishes removal.
                        diagnostics.aliasCoverage = "conflicting-positive"
                        limited = true
                    else
                        complete = true
                        diagnostics.auraComplete = true
                        diagnostics.authoritativeUnit = alias
                        limited, sensor = false, "aura-alias"
                        Observer.stats.aliasRecoveries = Observer.stats.aliasRecoveries + 1
                    end
                    break
                end
                mergeEffects(effects, other)
                diagnostics.mappedAuras = countEffects(effects)
                if next(other) then sensor = "aura+alias" end
            end
        end
    end

    if eventProof and eventProof.guid == guid and eventProof.effects then
        local conflict = false
        if complete then
            for key in pairs(eventProof.effects) do
                if not effects[key] then conflict = true; break end
            end
        end
        if conflict then
            complete, limited = false, true
            diagnostics.eventConflict = true
            Observer.stats.auraEventConflicts = Observer.stats.auraEventConflicts + 1
        end
        mergeEffects(effects, eventProof.effects)
        diagnostics.eventWitnesses = countEffects(eventProof.effects)
        sensor = sensor .. "+event"
    end
    local ambiguous
    effects, ambiguous = reconcileWitnesses(effects, previous)
    if ambiguous then complete, limited = false, true end
    local witnesses, capped = retainWitnesses(effects, previous, complete)
    if capped then complete, limited = false, true end
    if previous and (previous.sensor == "loc") ~= (sensor == "loc") then
        if exactPlayerHandoff(unit, previous, effects, complete, sensor, ambiguous, capped) then
            -- The same complete real aura identities bridge the player's first
            -- LoC selection. Preserve the pre-application quiet context so late
            -- raw duration can be evaluated; never repair an actual scan gap.
            Observer.stats.handoffsPreserved = Observer.stats.handoffsPreserved + 1
        else
            -- Changed or incomplete coverage invalidates confidence without
            -- erasing the applications already observed.
            ns.model:Observe(guid, {}, now, false)
            Observer.stats.handoffsInvalidated = Observer.stats.handoffsInvalidated + 1
        end
    end
    if sensor == "loc" then
        diagnostics.reason = complete and "Player Loss of Control fallback; debuff coverage is limited."
            or "Player Loss of Control data is unavailable or restricted."
    elseif diagnostics.auraComplete then
        diagnostics.reason = diagnostics.mappedAuras > 0 and "Readable mapped crowd-control aura observed."
            or "Complete harmful aura scan has no mapped crowd-control witness."
    elseif diagnostics.stompLookup == "confirmed" then
        diagnostics.reason = "Restricted harmful aura scan; exact readable War Stomp aura added."
    elseif diagnostics.grenadeLookup == "confirmed" then
        diagnostics.reason = "Restricted harmful aura scan; exact readable Iron Grenade stun added."
    elseif diagnostics.graspLookup == "confirmed" then
        diagnostics.reason = "Restricted harmful aura scan; exact readable Nature's Grasp root added."
    elseif diagnostics.mappedLoC > 0 then
        diagnostics.reason = "Restricted harmful aura scan; readable ByUnit Loss of Control witness added."
    elseif not diagnostics.byUnitAvailable then
        diagnostics.reason = "Restricted harmful aura scan; ByUnit Loss of Control API unavailable."
    elseif diagnostics.byUnitComplete then
        diagnostics.reason = "Restricted harmful aura scan; ByUnit Loss of Control has no mapped witness."
    else
        diagnostics.reason = "Harmful aura and ByUnit Loss of Control data are unavailable or restricted."
    end
    if diagnostics.eventConflict then
        diagnostics.reason = "Readable AoE aura event conflicts with indexed absence; retaining positive, incomplete coverage."
    end
    if ambiguous then diagnostics.reason = "Ambiguous aura/LoC application identity; canonical witness retained." end
    if capped then diagnostics.reason = "Observation capacity reached while removal data remains restricted." end
    local state = {
        guid = guid, status = complete and "readable" or "restricted", sensor = sensor,
        coverageLimited = limited,
        coverageNote = limited and "Loss of Control omits some debuffs, including possible Frost Shock effects." or nil,
        witnesses = witnesses,
    }
    for key, value in pairs(diagnostics) do state[key] = value end
    ns.model:Observe(guid, effects, now, complete)
    if ns.RecordDRObservation then ns.RecordDRObservation(guid, effects, now, complete, sensor, diagnostics) end
    return state
end

function Observer.Init()
    Observer.apiFailures = {}
    apiFailureKinds = 0
    Observer.playerLoCSelected = false
    Observer.lastScan = nil
    Observer.units = {}
    for _, unit in ipairs(trackedUnits) do Observer.units[unit] = unavailableState() end
    Observer.stats = {scans = 0, restricted = 0, casts = 0, acceptedCasts = 0, apiErrors = 0, missingApis = 0,
        predictedSecretAuraIndexes = 0,
        scanCaps = 0, scanGaps = 0, handoffsPreserved = 0, handoffsInvalidated = 0,
        aliasRecoveries = 0, castStartsPlayer = 0, castStartsOther = 0, castStartsUnknown = 0,
        castSuccessPlayer = 0, castSuccessOther = 0, castSuccessUnknown = 0,
        castNameUnavailable = 0, castPlayerGuidFallback = 0,
        auraEventCalls = 0, auraEventRestricted = 0, auraEventPositives = 0,
        auraEventConflicts = 0, nativeDREvents = 0, nativeDRRestricted = 0,
        nativeDRReadable = 0,
        ownBashSent = 0, ownBashSucceeded = 0,
        ownGrenadeSent = 0, ownGrenadeSucceeded = 0,
        ownStompSent = 0, ownStompSucceeded = 0,
        ownMortarSent = 0, ownMortarSucceeded = 0}
    Observer.castRejects = {}
    Observer.nativeLast = nil
    Observer.ownCCLast = nil
end

function Observer.GetUnitState(unit)
    local token = Safe.String(unit)
    if token == "player" or token == "target" or token == "focus" then return Observer.units[token] end
end

function Observer.Scan(now, eventProof)
    now = number(now)
    if not now or now < 0 then return end
    Observer.stats.scans = Observer.stats.scans + 1
    local identities, owners, previous, aliases = {}, {}, {}, {}
    -- Resolve every identity before releasing any GUID. A target/focus handoff
    -- or swap must not erase history still observable through another token.
    for _, unit in ipairs(trackedUnits) do
        local guid = readIdentity(unit)
        identities[unit] = guid
        if guid and not owners[guid] then owners[guid] = unit end
        if guid then
            aliases[guid] = aliases[guid] or {}
            aliases[guid][#aliases[guid] + 1] = unit
        end
        local state = Observer.units[unit]
        if state.guid and not previous[state.guid] then previous[state.guid] = state end
    end
    if Observer.lastScan and now - Observer.lastScan > 1 then
        -- A pause can contain an entire CC application/removal. A later clean
        -- snapshot cannot prove those intervening seconds were continuously quiet.
        local seen = {}
        for _, unit in ipairs(trackedUnits) do
            local guid = Observer.units[unit].guid
            if guid and not seen[guid] then
                seen[guid] = true
                ns.model:Observe(guid, {}, now, false)
            end
        end
        Observer.stats.scanGaps = Observer.stats.scanGaps + 1
    end
    Observer.lastScan = now
    for guid in pairs(previous) do
        if not owners[guid] then forget(guid) end
    end
    local units, scanned = {}, {}
    for _, unit in ipairs(trackedUnits) do
        local guid = identities[unit]
        if guid then
            if not scanned[guid] then
                scanned[guid] = scanGuid(owners[guid], guid, previous[guid], now, aliases[guid],
                    eventProof and eventProof.guid == guid and eventProof or nil)
            end
            units[unit] = scanned[guid]
        else
            units[unit] = unavailableState()
        end
    end
    Observer.units = units
end

-- Blizzard's own DR feed is a possible server-authoritative alternative.
-- Observe *only* separately readable fields, never secret tracker data.
-- This is diagnostic. A category event does not prove which spell landed.
function Observer.OnNativeDR(unit, trackerInfo)
    Observer.stats.nativeDREvents = Observer.stats.nativeDREvents + 1
    local token = unitToken(unit)
    if not token or not Safe.Readable(trackerInfo) or type(trackerInfo) ~= "table" then
        Observer.stats.nativeDRRestricted = Observer.stats.nativeDRRestricted + 1
        Observer.nativeLast = {unit=token or "unknown", reason="restricted"}
        return
    end
    local category, readable = field(trackerInfo, "category", "NativeDR.category", token)
    local categoryID = number(category)
    if not readable or not categoryID or categoryID < 0 or categoryID ~= math.floor(categoryID) then
        Observer.stats.nativeDRRestricted = Observer.stats.nativeDRRestricted + 1
        Observer.nativeLast = {unit=token, reason="category-unreadable"}
        return
    end
    Observer.stats.nativeDRReadable = Observer.stats.nativeDRReadable + 1
    local rawStart = field(trackerInfo, "startTime", "NativeDR.startTime", token)
    local rawDuration = field(trackerInfo, "duration", "NativeDR.duration", token)
    local rawCountdown = field(trackerInfo, "showCountdown", "NativeDR.showCountdown", token)
    local rawImmune = field(trackerInfo, "isImmune", "NativeDR.isImmune", token)
    local start, duration = number(rawStart), number(rawDuration)
    Observer.nativeLast = {
        unit=token, reason="category-readable", category=categoryID,
        start=start and start >= 0 and start or nil,
        duration=duration and duration >= 0 and duration or nil,
        countdown=Safe.Boolean(rawCountdown), immune=Safe.Boolean(rawImmune),
    }
end

local observedOwnCCSpell = {
    [5211]="Bash", [6798]="Bash", [8983]="Bash",
    [20549]="Stomp", [4068]="Grenade", [13237]="Mortar",
}
-- Cast events are not successful hits. This lets duel reports identify whether
-- Bash or a particular engineering stun even arrived as a readable player spell event.
function Observer.NoteOwnCCCast(phase, unit, spellID, now)
    if Safe.String(unit) ~= "player" or (phase ~= "Sent" and phase ~= "Succeeded") then return end
    local id = identifier(spellID)
    local family = id and observedOwnCCSpell[id]
    if not family then return end
    Observer.stats["own"..family..phase] = Observer.stats["own"..family..phase] + 1
    Observer.ownCCLast = {spellID=id, family=family, phase=phase, time=number(now)}
end

-- Retain only exact positive AoE observations from readable UNIT_AURA deltas.
-- The event calls Scan once; later secret snapshots cannot erase the witness.
function Observer.OnAuraEvent(unit, updateInfo, now)
    Observer.stats.auraEventCalls = Observer.stats.auraEventCalls + 1
    local token = unitToken(unit)
    now = number(now)
    if not now then return end
    if not token then
        Observer.stats.auraEventRestricted = Observer.stats.auraEventRestricted + 1
        Observer.Scan(now)
        return
    end
    local guid = (token == "player" or token == "target" or token == "focus")
        and readIdentity(token) or nil
    local effects, status, positive = addedAoEEvent(token, updateInfo, now)
    if status == "restricted" then
        Observer.stats.auraEventRestricted = Observer.stats.auraEventRestricted + 1
    end
    if effects and guid then
        Observer.stats.auraEventPositives = Observer.stats.auraEventPositives + (positive or 0)
        Observer.Scan(now, {guid = guid, effects = effects, unit = token})
    else
        Observer.Scan(now)
    end
end

-- START is telemetry only: it must NEVER start an enemy cooldown or DR.
-- Compare delivery by unit against successful cast events in /bcc status.
function Observer.NoteCastStart(unit)
    local token = unitToken(unit)
    local field = token == "player" and "castStartsPlayer"
        or token and "castStartsOther" or "castStartsUnknown"
    Observer.stats[field] = Observer.stats[field] + 1
end

local function rejectCast(reason)
    local rejects = Observer.castRejects
    rejects[reason] = (rejects[reason] or 0) + 1
    return false
end

function Observer.OnCast(unit, castGUID, spellID, now)
    Observer.stats.casts = Observer.stats.casts + 1
    unit = unitToken(unit)
    local delivery = unit == "player" and "castSuccessPlayer"
        or unit and "castSuccessOther" or "castSuccessUnknown"
    Observer.stats[delivery] = Observer.stats[delivery] + 1
    spellID = identifier(spellID)
    now = number(now)
    if not unit or not spellID or not now or now < 0 then return rejectCast("invalidEvent") end
    if not Safe.Readable(castGUID) then
        Observer.stats.restricted = Observer.stats.restricted + 1
        return rejectCast("restrictedCastID")
    end
    if castGUID ~= nil then
        castGUID = Safe.String(castGUID)
        if not castGUID or castGUID == "" or #castGUID > 128 then return rejectCast("invalidCastID") end
    end
    local canonicalID = ns.Data.castToSpell[spellID]
    if not canonicalID and not ns.Data.resets[spellID] then return rejectCast("unknownSpell") end
    if canonicalID and not ns.Data.spells[canonicalID] and not ns.Data.resets[spellID] then
        return rejectCast("untrackedSpell")
    end
    local rawGuid = call("UnitGUID", unit, UnitGUID, unit)
    local guid = guidString(rawGuid)
    if not guid then return rejectCast("unreadableGuid") end
    local hostile = call("UnitCanAttack", unit, UnitCanAttack, "player", unit)
    if Safe.Boolean(hostile) ~= true then return rejectCast("hostilityUnconfirmed") end
    local isPlayer = call("UnitIsPlayer", unit, UnitIsPlayer, unit)
    if Safe.Boolean(isPlayer) == false and guid:match("^Player%-") then
        return rejectCast("conflictingIdentity")
    end
    if Safe.Boolean(isPlayer) ~= true then
        if guid:match("^Player%-") then
            -- Positive GUID type is valid even when UnitIsPlayer is secret.
            Observer.stats.castPlayerGuidFallback = Observer.stats.castPlayerGuidFallback + 1
        elseif not guid:match("^Pet%-") and not guid:match("^Vehicle%-") then
            return rejectCast("unconfirmedUnitType")
        end
    end
    local rawName = call("UnitName", unit, UnitName, unit)
    local name = Safe.String(rawName)
    if not name or name == "" or #name > 128 then
        -- A verified caster GUID suffices for a cooldown; the model labels
        -- it by GUID until a future readable name is available.
        name = nil
        Observer.stats.castNameUnavailable = Observer.stats.castNameUnavailable + 1
    end
    -- Interrupt settings are a view filter. No cast is a DR application.
    local accepted = ns.model:Cast(guid, name, spellID, now, castGUID, false, ns.db.cooldownOverrides)
    if not accepted then return rejectCast("duplicateOrNoCooldown") end
    Observer.stats.acceptedCasts = Observer.stats.acceptedCasts + 1
    return true
end
