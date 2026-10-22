local _, ns = ...
-- A cooldown claim describes the estimate already held in Model. It is NOT a
-- second source of truth, nor a probability of readiness. Only Model may issue,
-- revise or retire claims. Records are ephemeral and never saved to SavedVariables.
local Claims = {}
ns.Claims = Claims
local MAX_ACTIVITY, MAX_WITNESSES, MAX_REVISIONS = 64, 4, 4

local function activity(model, status, claim, at, reason)
    if not model or not claim then return end
    local entries = model.claimActivity
    if not entries then return end
    entries[#entries + 1] = {
        at = at, claimID = claim.id, spellID = claim.spellID,
        status = status, reason = reason,
    }
    if #entries > MAX_ACTIVITY then table.remove(entries, 1) end
end

-- All parameters are sanitized, ordinary values at the Model boundary.
function Claims.Issue(model, spellID, source, at, anonymous, approximate, context)
    model.nextClaimID = (model.nextClaimID or 0) + 1
    local basis = source == 'helpful-aura' and (approximate and 'first-sighting' or 'aura-start')
        or source == 'player-loc' and (approximate and 'loc-first-sighting' or 'loc-effect-start')
        or source == 'manual' and 'manual-mark' or 'cast-success-event'
    local claim = {
        id = model.nextClaimID, spellID = spellID, source = source,
        basis = basis, anonymous = anonymous == true,
        evidenceIdentity = context and context.identity or nil,
        witnesses = {}, revisions = {},
    }
    Claims.Witness(claim, source, context and context.origin or source,
        context and context.observedAt or at)
    activity(model, 'issued', claim, at, source)
    return claim
end

-- Multiple unit tokens observing one aura are provenance, not independent
-- confirmations. The cap is deliberate: a claim is an explanation, not a log.
function Claims.Witness(claim, kind, origin, at)
    if not claim or type(kind) ~= 'string' or type(origin) ~= 'string' then return false end
    for _, witness in ipairs(claim.witnesses) do
        if witness.kind == kind and witness.origin == origin then return false end
    end
    if #claim.witnesses >= MAX_WITNESSES then
        -- Preserve strong corrective evidence inside the SAME fixed cap.
        -- Redundant sensor sightings must not crowd out a cast or a newly
        -- readable timestamp that could revise the active interpretation.
        if kind ~= 'cast' and kind ~= 'readable-aura-start' then return false end
        local replace
        for i = #claim.witnesses, 1, -1 do
            if claim.witnesses[i].kind == 'same-aura-sighting' then replace=i; break end
        end
        if not replace then return false end
        table.remove(claim.witnesses, replace)
    end
    claim.witnesses[#claim.witnesses + 1] = {kind = kind, origin = origin, at = at}
    return true
end

function Claims.Revise(model, claim, at, reason, before, after, basis)
    -- A better *basis* is a real revision even when its timestamp agrees.
    if not claim or (before == after and (not basis or basis == claim.basis)) then return false end
    local r = claim.revisions
    r[#r+1] = {at=at, reason=reason, before=before, after=after}
    if #r > MAX_REVISIONS then table.remove(r,1) end
    if basis then claim.basis = basis end
    activity(model,'revised',claim,at,reason)
    return true
end

function Claims.Retire(model, claim, at, reason)
    activity(model,'retired',claim,at,reason)
end

-- Never publish writable model internals or raw aura identities/GUIDs.
function Claims.Snapshot(claim)
    if not claim then return nil end
    local out = {
        id=claim.id, spellID=claim.spellID, source=claim.source,
        basis=claim.basis, anonymous=claim.anonymous,
        witnesses={}, revisions={},
    }
    for _, w in ipairs(claim.witnesses) do
        out.witnesses[#out.witnesses+1]={kind=w.kind,origin=w.origin,at=w.at}
    end
    for _, r in ipairs(claim.revisions) do
        out.revisions[#out.revisions+1]={at=r.at,reason=r.reason,before=r.before,after=r.after}
    end
    return out
end

function Claims.Recent(model, limit)
    local events = model and model.claimActivity or {}
    local out = {}
    limit = math.max(0, math.min(12, math.floor(tonumber(limit) or 8)))
    for i=#events,math.max(1,#events-limit+1),-1 do
        local v=events[i]
        out[#out+1]={at=v.at,claimID=v.claimID,spellID=v.spellID,
            status=v.status,reason=v.reason}
    end
    return out
end

function Claims.LastDecision(model, spellID)
    local history=model and model.claimActivity or {}
    for i=#history,1,-1 do
        local v=history[i]
        if v.spellID==spellID then
            return {at=v.at,claimID=v.claimID,spellID=v.spellID,
                status=v.status,reason=v.reason}
        end
    end
end

-- Plain-language explanation consumes only a public cooldown row. The row
-- itself is the active state: expired/superseded claims cannot appear here.
function Claims.Explain(row)
    local c = row and row.claim
    if not c then return {'No evidence lineage recorded for this estimate.'} end
    local lines = {
        'Claim #'..c.id..': ESTIMATED cooldown, not proven ability readiness.',
        'Evidence basis: '..c.basis..'.',
    }
    if row.anonymous then
        lines[#lines+1]='A CC effect was observed on you; caster UNKNOWN (never assigned to target).'
    elseif c.source=='helpful-aura' then
        lines[#lines+1]='Readable self-only beneficial effect on an identified hostile player.'
        lines[#lines+1]='A new effect supports activation, not a verified successful cast.'
    elseif c.source=='manual' then
        lines[#lines+1]='You manually marked this ability; the cast was not independently observed.'
    else
        lines[#lines+1]='A readable successful enemy cast event supports activation.'
    end
    local basis = {
        ['first-sighting']='Start is FIRST SIGHTING; actual activation may be earlier.',
        ['aura-start']='Start reconstructed from readable aura duration and expiry.',
        ['cast-success-event']='Start from readable cast-success event.',
        ['loc-first-sighting']='Start from first observed loss-of-control effect (estimated).',
        ['loc-effect-start']='Start from readable landed-effect timestamp, not guaranteed cast time.',
        ['manual-mark']='Start was entered manually.',
    }
    lines[#lines+1]=basis[c.basis] or 'Start time is an estimate.'
    if #c.witnesses > 1 then
        lines[#lines+1]='Other evidence: '..(#c.witnesses-1)..' linked observation(s); not independent votes.'
    end
    if #c.revisions > 0 then
        local last=c.revisions[#c.revisions]
        lines[#lines+1]='Revision: '..last.reason..' (start '..string.format('%.1f',last.before)
            ..' -> '..string.format('%.1f',last.after)..').'
    end
    if row.earlyRemaining and row.remaining and row.earlyRemaining < row.remaining then
        lines[#lines+1]='Cooldown interval includes unverified talent/rank variation.'
    end
    return lines
end
return Claims
