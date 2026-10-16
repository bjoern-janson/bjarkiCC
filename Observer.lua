local _, ns = ...
local Safe = ns.Safe
local Observer = {}
ns.Observer = Observer
-- The first readable token owns a shared GUID's snapshot. Player must win so
-- self target/focus aliases retain the player-only Loss of Control fallback.
local trackedUnits = {"player", "target", "focus"}
local MAX_WITNESSES = 512
local APPLICATION_EPSILON = 0.001 -- Match the model's timestamp rounding tolerance.

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
local function call(fn, ...)
    if type(fn) ~= "function" then
        Observer.stats.missingApis = Observer.stats.missingApis + 1
        return nil, false
    end
    local ok, value = pcall(fn, ...)
    if not ok then
        Observer.stats.apiErrors = Observer.stats.apiErrors + 1
        return nil, false
    end
    if not Safe.Readable(value) then
        Observer.stats.restricted = Observer.stats.restricted + 1
        return nil, false
    end
    return value, true
end

local function field(record, key)
    return call(function() return record[key] end)
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
        local aura, readable = call(api.GetAuraDataByIndex, unit, index, "HARMFUL")
        if not readable then return auraResult(effects, false, unmapped) end
        if aura == nil then return auraResult(effects, complete, unmapped) end
        if type(aura) ~= "table" then return auraResult(effects, false, unmapped) end
        local rawSpell, spellReadable = field(aura, "spellId")
        local spellID = identifier(rawSpell)
        if not spellReadable or not spellID then
            complete = false
        else
            local category = ns.Data.auraCategory[spellID]
            if category then
                local rawInstance, instanceReadable = field(aura, "auraInstanceID")
                local instanceID = identifier(rawInstance)
                if not instanceReadable or not instanceID then
                    complete = false
                else
                    local rawExpiry = field(aura, "expirationTime")
                    local expires = number(rawExpiry)
                    if expires and expires <= 0 then expires = nil end
                    local rawDuration = field(aura, "duration")
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
        rawCount, countReadable = call(api.GetActiveLossOfControlDataCountByUnit, unit)
    else
        rawCount, countReadable = call(api.GetActiveLossOfControlDataCount)
    end
    local count = number(rawCount)
    if not countReadable or not count or count < 0 or count > 255 or count ~= math.floor(count) then
        return effects, false
    end
    local complete = true
    for index = 1, count do
        local data, readable
        if unit then data, readable = call(api.GetActiveLossOfControlDataByUnit, unit, index)
        else data, readable = call(api.GetActiveLossOfControlData, index) end
        if not readable or type(data) ~= "table" then
            complete = false
        else
            local rawSpell, spellReadable = field(data, "spellID")
            local spellID = identifier(rawSpell)
            if not spellReadable or not spellID then
                complete = false
            else
                -- locType is deliberately not a category fallback: e.g. STUN
                -- does not distinguish separate Classic stun DR families.
                local category = ns.Data.auraCategory[spellID]
                if category then
                    local rawInstance = field(data, "auraInstanceID")
                    local instanceID = identifier(rawInstance)
                    local rawStart = field(data, "startTime")
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
                        local rawDuration = field(data, "duration")
                        local duration = number(rawDuration)
                        local expires
                        if start and duration and duration > 0 then
                            expires = start + duration
                        else
                            local rawRemaining = field(data, "timeRemaining")
                            local remaining = number(rawRemaining)
                            if remaining and remaining > 0 then expires = now + remaining end
                        end
                        effects[key] = {category = category, spellID = spellID, expires = expires,
                            appliedAt = start, applicationSource = start and "loc" or nil,
                            fallbackIdentity = not instanceID}
                    end
                else
                    unmapped[spellID] = true
                end
            end
        end
    end
    return effects, complete, boundedIDs(unmapped)
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
                    local witness = candidates[canonical]
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
    local rawGuid = call(UnitGUID, unit)
    local guid = guidString(rawGuid)
    if not guid or not guid:match("^Player%-") then return nil end
    if unit ~= "player" then
        local isPlayer = call(UnitIsPlayer, unit)
        if Safe.Boolean(isPlayer) ~= true then return nil end
    end
    return guid
end

local function scanGuid(unit, guid, previous, now)
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
            if diagnostics.byUnitAvailable then
                local locEffects, locComplete, locUnmapped = lossOfControlSnapshot(now, unit)
                diagnostics.byUnitComplete = locComplete
                diagnostics.mappedLoC = countEffects(locEffects)
                diagnostics.unmappedSpellIDs = mergeIDs(diagnostics.unmappedSpellIDs, locUnmapped)
                mergeEffects(effects, locEffects)
                if diagnostics.mappedLoC > 0 then sensor = "aura+loc" end
            end
            -- LoC does not enumerate every debuff. Even a complete/empty LoC
            -- list must not turn this restricted aura scan into absence proof.
        end
    end
    if previous and (previous.sensor == "loc") ~= (sensor == "loc") then
        -- Coverage changed, but positively observed applications still happened.
        -- Invalidate confidence without erasing stages, clocks or identities;
        -- reconciliation below withholds ambiguous cross-sensor duplicates.
        ns.model:Observe(guid, {}, now, false)
    end
    local ambiguous
    effects, ambiguous = reconcileWitnesses(effects, previous)
    if ambiguous then complete, limited = false, true end
    local witnesses, capped = retainWitnesses(effects, previous, complete)
    if capped then complete, limited = false, true end
    if sensor == "loc" then
        diagnostics.reason = complete and "Player Loss of Control fallback; debuff coverage is limited."
            or "Player Loss of Control data is unavailable or restricted."
    elseif diagnostics.auraComplete then
        diagnostics.reason = diagnostics.mappedAuras > 0 and "Readable mapped crowd-control aura observed."
            or "Complete harmful aura scan has no mapped crowd-control witness."
    elseif diagnostics.mappedLoC > 0 then
        diagnostics.reason = "Restricted harmful aura scan; readable ByUnit Loss of Control witness added."
    elseif not diagnostics.byUnitAvailable then
        diagnostics.reason = "Restricted harmful aura scan; ByUnit Loss of Control API unavailable."
    elseif diagnostics.byUnitComplete then
        diagnostics.reason = "Restricted harmful aura scan; ByUnit Loss of Control has no mapped witness."
    else
        diagnostics.reason = "Harmful aura and ByUnit Loss of Control data are unavailable or restricted."
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
    if ns.RecordDRObservation then ns.RecordDRObservation(guid, effects, now, complete, sensor) end
    return state
end

function Observer.Init()
    Observer.playerLoCSelected = false
    Observer.lastScan = nil
    Observer.units = {}
    for _, unit in ipairs(trackedUnits) do Observer.units[unit] = unavailableState() end
    Observer.stats = {scans = 0, restricted = 0, casts = 0, acceptedCasts = 0, apiErrors = 0, missingApis = 0, scanCaps = 0, scanGaps = 0}
end

function Observer.GetUnitState(unit)
    local token = Safe.String(unit)
    if token == "player" or token == "target" or token == "focus" then return Observer.units[token] end
end

function Observer.Scan(now)
    now = number(now)
    if not now or now < 0 then return end
    Observer.stats.scans = Observer.stats.scans + 1
    local identities, owners, previous = {}, {}, {}
    -- Resolve every identity before releasing any GUID. A target/focus handoff
    -- or swap must not erase history still observable through another token.
    for _, unit in ipairs(trackedUnits) do
        local guid = readIdentity(unit)
        identities[unit] = guid
        if guid and not owners[guid] then owners[guid] = unit end
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
                scanned[guid] = scanGuid(owners[guid], guid, previous[guid], now)
            end
            units[unit] = scanned[guid]
        else
            units[unit] = unavailableState()
        end
    end
    Observer.units = units
end

function Observer.OnCast(unit, castGUID, spellID, now)
    Observer.stats.casts = Observer.stats.casts + 1
    unit = unitToken(unit)
    spellID = identifier(spellID)
    now = number(now)
    if not unit or not spellID or not now or now < 0 then return end
    if not Safe.Readable(castGUID) then Observer.stats.restricted = Observer.stats.restricted + 1; return end
    if castGUID ~= nil then
        castGUID = Safe.String(castGUID)
        if not castGUID or castGUID == "" or #castGUID > 128 then return end
    end
    local canonicalID = ns.Data.castToSpell[spellID]
    if not canonicalID and not ns.Data.resets[spellID] then return end
    if canonicalID and not ns.Data.spells[canonicalID] and not ns.Data.resets[spellID] then return end
    local rawGuid = call(UnitGUID, unit)
    local guid = guidString(rawGuid)
    if not guid then return end
    local hostile = call(UnitCanAttack, "player", unit)
    if Safe.Boolean(hostile) ~= true then return end
    local isPlayer = call(UnitIsPlayer, unit)
    if Safe.Boolean(isPlayer) ~= true and not guid:match("^Pet%-") and not guid:match("^Vehicle%-") then return end
    local rawName = call(UnitName, unit)
    local name = Safe.String(rawName)
    if not name or name == "" or #name > 128 then return end
    -- Interrupt settings are a view filter, so enabling them later can reveal
    -- already observed cooldowns. Pet identities are never invented as owners.
    ns.model:Cast(guid, name, spellID, now, castGUID, false, ns.db.cooldownOverrides)
    Observer.stats.acceptedCasts = Observer.stats.acceptedCasts + 1
end
