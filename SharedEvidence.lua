-- bjarkiEvidence: a tiny, bounded bridge for independent addons.
-- Contract v1 accepts ONLY readable, positive, helpful aura observations.
-- The schema is deliberately closed: new observation kinds need their own
-- reviewed validators. Never publish raw/secret game values or inferences.
-- Install this file byte-for-byte in bjarkiPortraits and bjarkiCC.
local _, ns = ...
local GLOBAL_KEY = "BjarkiEvidenceV1"
local PROTOCOL = "bjarki-positive-aura-v1"
local MAX_RECENT, REPLAY_SECONDS = 64, 8
local MAX_LISTENERS, MAX_PENDING = 16, 64

local existing = rawget(_G, GLOBAL_KEY)
if existing ~= nil then
    -- Fail closed on mixed protocol builds. Neither addon needs the bus to
    -- function; replacing a live incompatible bus would split observations.
    local ok, compatible = pcall(function()
        return type(existing) == "table" and existing.schema == 1
            and existing.protocol == PROTOCOL
            and type(existing.Publish) == "function"
            and type(existing.Subscribe) == "function"
            and type(existing.Unsubscribe) == "function"
    end)
    if ok and compatible then
        ns.EvidenceBus = existing
        ns.EvidenceStatus = "connected"
    else
        ns.EvidenceStatus = "incompatible-bridge"
    end
    return
end

local Bus = {
    schema = 1, protocol = PROTOCOL, listeners = {}, listenerOrder = {},
    recent = {}, sequence = 0,
    stats = {published=0, rejected=0, errors=0, replayed=0,
        deliveries=0, overflows=0, subscriptions=0},
}
local pending = {}
local draining = false

local function readable(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret == true then return false end
    end
    if type(issecrettable) == "function" then
        local ok, secret = pcall(issecrettable, value)
        if not ok or secret == true then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, permitted = pcall(canaccessvalue, value)
        if not ok or permitted ~= true then return false end
    end
    return true
end

local function finite(value, integer)
    if not readable(value) or type(value) ~= "number" or value ~= value
        or value <= -math.huge or value >= math.huge then return nil end
    if integer and (value < 1 or value > 9999999 or value ~= math.floor(value)) then return nil end
    if not integer and (value < 0 or value > 100000000) then return nil end
    return value
end

local function text(value)
    if not readable(value) or type(value) ~= "string" or #value > 128 then return nil end
    return value
end

local function field(input, key)
    local ok, value = pcall(function() return input[key] end)
    if ok and readable(value) then return value end
end

local function snapshot(input)
    if not readable(input) or type(input) ~= "table" then return nil end
    if text(field(input,"source")) ~= "bjarkiPortraits"
        or text(field(input,"kind")) ~= "aura-positive"
        or field(input,"isHelpful") ~= true then return nil end
    local guid = text(field(input,"recipientGUID"))
    if not guid or not guid:match("^Player%-[%w%-]+$") then return nil end
    local unit = text(field(input,"unit"))
    if unit ~= "target" and unit ~= "focus" and unit ~= "targettarget"
        and unit ~= "focustarget" then return nil end
    local spellID = finite(field(input,"spellId"),true)
    local observedAt = finite(field(input,"observedAt"),false)
    if not spellID or not observedAt then return nil end
    local instance = finite(field(input,"auraInstanceID"),true)
    local expiration = finite(field(input,"expirationTime"),false)
    local duration = finite(field(input,"duration"),false)
    if duration and duration > 300 then duration, expiration = nil, nil end
    -- Plain-value copy: no auraData, functions, tokens, secret values, or
    -- display data cross the boundary. First sighting != new application.
    return {source="bjarkiPortraits",kind="aura-positive",isHelpful=true,
        recipientGUID=guid,unit=unit,spellId=spellID,
        auraInstanceID=instance,expirationTime=expiration,duration=duration,
        observedAt=observedAt,newApplication=field(input,"newApplication") == true}
end

local function copy(record)
    local clone = {}
    for key, value in pairs(record) do clone[key] = value end
    return clone
end

local function store(record)
    local recent = Bus.recent
    recent[#recent+1] = record
    for i = #recent, 1, -1 do
        if record.observedAt - recent[i].observedAt > REPLAY_SECONDS then
            table.remove(recent,i)
        end
    end
    -- Retain the newest publications when the replay window is full.
    while #recent > MAX_RECENT do table.remove(recent,1) end
end

local function send(record)
    Bus.sequence = Bus.sequence + 1
    record.sequence = Bus.sequence
    store(record)
    -- Stable subscription order improves debugging; an unsubscribe during a
    -- callback is respected at the next recipient without mutating this pass.
    local destinations = {}
    for _, key in ipairs(Bus.listenerOrder) do destinations[#destinations+1] = key end
    for _, key in ipairs(destinations) do
        local callback = Bus.listeners[key]
        if callback then
            local ok = pcall(callback,copy(record))
            if ok then Bus.stats.deliveries = Bus.stats.deliveries+1
            else Bus.stats.errors = Bus.stats.errors+1 end
        end
    end
end

function Bus:Publish(raw)
    local record = snapshot(raw)
    if not record then self.stats.rejected = self.stats.rejected+1; return false end
    if #pending >= MAX_PENDING then
        self.stats.overflows = self.stats.overflows+1
        return false
    end
    pending[#pending+1] = record
    self.stats.published = self.stats.published+1
    if draining then return true end
    -- Reentrant publications are queued, not recursively delivered. A buggy
    -- listener cannot create an infinite notification loop in a single tick.
    draining = true
    local head = 1
    while head <= #pending do
        send(pending[head])
        head = head+1
    end
    pending = {}
    draining = false
    return true
end

function Bus:Subscribe(key, callback, now)
    if not readable(key) or type(key) ~= "string" or #key < 1 or #key > 80
        or not readable(callback) or type(callback) ~= "function" then return false end
    if self.listeners[key] == callback then return true end -- idempotent: no duplicate replay
    if not self.listeners[key] then
        if #self.listenerOrder >= MAX_LISTENERS then return false end
        self.listenerOrder[#self.listenerOrder+1] = key
    end
    self.listeners[key] = callback
    self.stats.subscriptions = self.stats.subscriptions+1
    local stamp = finite(now,false)
    if stamp then
        -- Snapshot the replay set before invoking callbacks. Publishing a new
        -- event from a replay callback must not make this replay unbounded.
        local eligible = {}
        for _, record in ipairs(self.recent) do
            if record.observedAt <= stamp and stamp-record.observedAt <= REPLAY_SECONDS then
                eligible[#eligible+1] = record
            end
        end
        for _, record in ipairs(eligible) do
            if self.listeners[key] ~= callback then break end
            local ok = pcall(callback,copy(record))
            if ok then self.stats.replayed = self.stats.replayed+1
            else self.stats.errors = self.stats.errors+1 end
        end
    end
    return true
end

function Bus:Unsubscribe(key)
    if not readable(key) or type(key) ~= "string" or not self.listeners[key] then return false end
    self.listeners[key] = nil
    for i = #self.listenerOrder, 1, -1 do
        if self.listenerOrder[i] == key then table.remove(self.listenerOrder,i); break end
    end
    return true
end

function Bus:Status()
    local status = copy(self.stats)
    status.schema = self.schema
    status.protocol = self.protocol
    status.listeners = #self.listenerOrder
    status.recent = #self.recent
    status.pending = #pending
    return status
end

_G[GLOBAL_KEY] = Bus
ns.EvidenceBus = Bus
ns.EvidenceStatus = "connected"
