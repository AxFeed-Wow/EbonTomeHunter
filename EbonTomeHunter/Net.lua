local addonName, ns = ...
local L = ns.L

-- Community drop places. When an EbonTomeHunter user loots a tome, where it dropped
-- (zone map position, mob) is sent to every other user online; each client keeps
-- the places and shows them like the EbonholdHub ones, so a tome listed as
-- "Unknown location" gets a real place for everybody.
-- Stock 3.3.5a has no realm-wide addon channel: like EbonAffixAlert, a hidden chat
-- channel is joined and removed from the chat windows. Wire: "ETHN1~<type>~<payload>",
-- at most 240 characters, never "|" (chat escape character).
--   D  one drop:            itemId^mapFile^x^y^npcId^mob^zone^time^finder^learned
--   Q  sync request:        qid^since
--   S  sync answer:         qid~more~record;record;...   oldest first, 30 at most; more=1
--                           when there are others (the asker then asks again from the
--                           last one). qid "0": places sent without a request.
-- "learned" (10th field, ignored by 2.0.0) is when the sender stored the place, on its
-- own clock. The length of the qid tells the two kinds of request apart:
--   4 hex digits (2.0.0 askers): the places FOUND after <since>. The best-stocked client
--     answers first, the others see the answer and stay silent.
--   5 hex digits (2.1.0 askers): the places LEARNED after <since>, so that an old find
--     that arrived late travels too. Every client online sends what the answers heard so
--     far lacked, then the asker sends what it learned since <since> and nobody said.
-- A find made while no other user is online waits in an outbox and is sent again
-- (qid "0") when one shows up.
ns.Net = {}
local Net = ns.Net

local CHANNEL = "ebontomehunter"
local WIRE = "ETHN1"
local PUSH = "0"             -- qid of the places sent without a request
local SEND_DELAY = 0.3
local MAX_QUEUE = 80
local MAX_PER_TOME = 12
local MAX_FINDERS = 10
local SYNC_MAX_RECORDS = 30
local SYNC_COOLDOWN = 600
local SYNC_MARGIN = 600      -- the clocks of two players are never exactly in time
local SYNC_BATCHES = 5       -- requests per session when the backlog is large
local SYNC_SETTLE = 4        -- seconds without a new part: the answer is complete
local SYNC_WAIT = 12         -- seconds after our request left without any answer: nobody
local JOIN_DELAY = 10
local PEER_TIMEOUT = 1800    -- a user not heard from for 30 min counts as gone
local OUTBOX_MAX = 50
local OUTBOX_DAYS = 30
local PUSH_MAX = 60          -- places the asker adds at the end of its sync
local REASK_DELAY = 5
local REASK_GAP = 60
local REASK_MAX = 10         -- per session of play
local OLD_PLACE = 90 * 86400  -- a place nobody found again for 90 days comes after the others

local channelIndex
local joined = false         -- joining was asked (the game may still have refused it)
local queue = {}
local nextSend = 0
local peers = {}             -- [name] = GetTime() of their last message
local answering = {}         -- [qid] = a request of another user we are about to answer
local heard = {}             -- [qid] = { [itemId] = places heard in the answers to it }
local mySync                 -- our request waiting for its answer (one round of a session)
local lastSession            -- our last sync (several rounds when the backlog is large)
local pushed = setmetatable({}, { __mode = "k" })   -- [place] = its learned time when we last added it to a sync
local reasks, lastReask = 0, -math.huge

local function Opt() return ns.Opt() end

local function Store()
    if type(ns.DB.sightings) ~= "table" then ns.DB.sightings = {} end
    return ns.DB.sightings
end

local function Outbox()
    if type(ns.DB.netOutbox) ~= "table" then ns.DB.netOutbox = {} end
    return ns.DB.netOutbox
end

-- When this client stored a place (2.0.0 did not note it: the time it was found).
local function Learned(r)
    return tonumber(r.rx) or tonumber(r.at) or 0
end

------------------------------------------------------------------------
-- Hidden channel
------------------------------------------------------------------------
local function IsOurChannel(name)
    return type(name) == "string" and strlower(name):find(CHANNEL, 1, true) ~= nil
end

local function FindChannel()
    if GetChannelName then
        local index = tonumber((GetChannelName(CHANNEL)))
        if index and index > 0 then return index end
    end
    if GetChannelList then
        local list = { GetChannelList() }
        for i = 1, #list - 1 do
            local index = tonumber(list[i])
            if index and index > 0 and IsOurChannel(list[i + 1]) then return index end
        end
    end
    return nil
end

local function HideChannel()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chat = _G["ChatFrame" .. i]
        if chat then ChatFrame_RemoveChannel(chat, CHANNEL) end
    end
end

function Net.Join()
    if joined or not Opt().netEnabled then return end
    joined = true
    channelIndex = FindChannel()
    if not channelIndex and JoinChannelByName then
        JoinChannelByName(CHANNEL)
        channelIndex = FindChannel()   -- may still be nil: resolved again before sending
    end
    HideChannel()
end

function Net.Leave()
    joined, channelIndex = false, nil
    wipe(queue)
    wipe(Outbox())   -- the player stopped sharing: nothing found meanwhile leaves later
    mySync, lastSession = nil, nil
    if LeaveChannelByName then LeaveChannelByName(CHANNEL) end
end

-- In the hidden channel right now (the game refuses it beyond 10 chat channels).
function Net.IsJoined()
    return (Opt().netEnabled and FindChannel() ~= nil) and true or false
end

local sender = CreateFrame("Frame")
sender:Hide()
sender:SetScript("OnUpdate", function(self)
    if #queue == 0 then
        self:Hide()
        return
    end
    if GetTime() < nextSend then return end
    -- channel numbers change when other channels are left: check before every send,
    -- a stale number would post protocol text into General
    if channelIndex and GetChannelName then
        local _, name = GetChannelName(channelIndex)
        if not IsOurChannel(name) then channelIndex = nil end
    end
    if not channelIndex then
        channelIndex = FindChannel()
        if not channelIndex then
            nextSend = GetTime() + 1
            return
        end
        HideChannel()
    end
    local ok = pcall(SendChatMessage, queue[1], "CHANNEL", nil, channelIndex)
    if ok then tremove(queue, 1) else channelIndex = nil end
    nextSend = GetTime() + (ok and SEND_DELAY or 1)
end)

local function Queue(msgType, payload)
    if not Opt().netEnabled then return false end
    if not joined then Net.Join() end
    local wire = WIRE .. "~" .. msgType .. "~" .. payload
    if #wire > 240 or wire:find("|", 1, true) then return false end
    if #queue >= MAX_QUEUE then tremove(queue, 1) end
    queue[#queue + 1] = wire
    sender:Show()
    return true
end

-- For the other modules (Evidence.lua): one message of their own type.
function Net.Send(msgType, payload)
    return Queue(msgType, payload)
end

local function Queued(wire)
    for i = 1, #queue do
        if queue[i] == wire then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Records
------------------------------------------------------------------------
-- Byte limit that never cuts a UTF-8 character in two (French zone and mob names):
-- a broken character could get the whole chat message refused.
local function Utf8Cut(text, maxBytes)
    if #text <= maxBytes then return text end
    text = text:sub(1, maxBytes)
    local lead = #text
    while lead > 0 and text:byte(lead) >= 0x80 and text:byte(lead) < 0xC0 do lead = lead - 1 end
    local byte = lead > 0 and text:byte(lead) or 0
    if byte >= 0xC0 then
        local size = byte >= 0xF0 and 4 or (byte >= 0xE0 and 3 or 2)
        if #text - lead + 1 < size then text = text:sub(1, lead - 1) end
    end
    return text
end

local function Clean(text, maxLength)
    text = tostring(text or ""):gsub("[~%^;|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return Utf8Cut(text, maxLength)
end

function Net.Encode(r)
    local at = floor(tonumber(r.at) or time())
    return table.concat({
        r.itemId, Clean(r.mapFile, 30),
        r.x and floor(r.x * 1000 + 0.5) or "", r.y and floor(r.y * 1000 + 0.5) or "",
        r.npcId or "", Clean(r.mob, 40), Clean(r.zone, 60), at, Clean(r.by, 24),
        floor(tonumber(r.rx) or at),
    }, "^")
end

local function Plausible(stamp, now)
    return stamp <= now + 86400 and stamp >= now - 2 * 365 * 86400
end

-- nil for anything malformed, unknown or implausible. Second value: when the sender
-- learned the place, on its own clock (nil from a 2.0.0 client).
function Net.Decode(text)
    local f = { strsplit("^", tostring(text or "")) }
    if #f < 9 then return nil end
    local itemId = tonumber(f[1])
    if not (itemId and ns.Catalog.Get(itemId)) then return nil end
    local x, y = tonumber(f[3]), tonumber(f[4])
    if (x and (x < 0 or x > 1000)) or (y and (y < 0 or y > 1000)) or ((x == nil) ~= (y == nil)) then return nil end
    local at, now = tonumber(f[8]) or 0, time()
    if not Plausible(at, now) then return nil end
    at = math.min(at, now)   -- a clock a little ahead must not push the sync forward
    local learned = tonumber(f[10])
    if learned and not Plausible(learned, now) then learned = nil end
    return {
        itemId = itemId, mapFile = f[2] ~= "" and f[2] or nil, x = x and x / 1000, y = y and y / 1000,
        npcId = tonumber(f[5]), mob = f[6] ~= "" and f[6] or nil, zone = f[7], at = at,
        by = f[9] ~= "" and f[9] or nil,
    }, learned
end

local function SameSpot(a, b)
    if a.mapFile ~= b.mapFile then return false end
    if a.x and b.x then
        if math.abs(a.x - b.x) > 0.04 or math.abs(a.y - b.y) > 0.04 then return false end
    elseif a.zone ~= b.zone then
        return false
    end
    if a.npcId and b.npcId then return a.npcId == b.npcId end
    if a.mob and b.mob then return a.mob == b.mob end
    return true   -- one of them does not know its mob (Scavenger loot after several kills)
end

local function CountFinders(record)
    local n = 0
    for _ in pairs(record.finders or {}) do n = n + 1 end
    return n
end

-- Stores a drop place. Returns true when it is a new place, and whether anything
-- changed (a known place confirmed by another player).
function Net.Add(record)
    local store = Store()
    local list = store[record.itemId]
    if not list then
        list = {}
        store[record.itemId] = list
    end
    for _, old in ipairs(list) do
        if SameSpot(old, record) then
            old.finders = old.finders or {}
            local confirmed = false
            if record.by and not old.finders[record.by] and CountFinders(old) < MAX_FINDERS then
                old.finders[record.by] = true
                confirmed = true
            end
            if record.at > (old.at or 0) then old.at = record.at end
            if not old.mob and record.mob then
                old.mob, old.npcId, confirmed = record.mob, record.npcId, true   -- now we know the mob
            end
            old.npcId = old.npcId or record.npcId
            if confirmed then old.rx = time() end   -- news: goes to the next askers too
            return false, confirmed
        end
    end
    record.finders = record.by and { [record.by] = true } or {}
    record.rx = tonumber(record.rx) or time()
    list[#list + 1] = record
    if #list > MAX_PER_TOME then
        -- keep the places confirmed by the most players, then the most recent
        table.sort(list, function(a, b)
            local ca, cb = CountFinders(a), CountFinders(b)
            if ca ~= cb then return ca > cb end
            return (a.at or 0) > (b.at or 0)
        end)
        for i = #list, MAX_PER_TOME + 1, -1 do tremove(list, i) end
    end
    return true, true
end

local changePending = false
local function Changed()
    if changePending then return end
    changePending = true
    ns.Timer.After(1, function()
        changePending = false
        ns.Fire("SIGHTINGS_CHANGED")
    end)
end

-- Drop places of a tome, as catalogue locations (zone map coordinates), the most
-- recently found first.
function Net.Locations(itemId)
    local stored = Store()[tonumber(itemId)]
    if not stored or #stored == 0 then return nil end
    local list = {}
    for i, r in ipairs(stored) do list[i] = r end
    table.sort(list, function(a, b) return (tonumber(a.at) or 0) > (tonumber(b.at) or 0) end)
    local out, now = {}, time()
    for index, r in ipairs(list) do
        local zone, sub = tostring(r.zone or ""):match("^([^:]*):?(.*)$")
        local place = (sub and sub ~= "") and (zone .. " - " .. sub) or (zone ~= "" and zone or L.LocationUnknown)
        local finders = math.max(1, CountFinders(r))
        out[#out + 1] = {
            source = "net", mapFile = r.mapFile, x = r.x, y = r.y, placeName = place,
            mobs = r.mob and { r.mob } or nil, npcIds = (r.mob and r.npcId) and { [r.mob] = r.npcId } or nil,
            notes = format(L.NetNotes, r.by or "?", ns.Ago(r.at) or "?", finders),
            order = 50000 + index, at = r.at, old = now - (tonumber(r.at) or 0) > OLD_PLACE,
        }
    end
    return out
end

-- The drop places stored for a tome (nil when none).
function Net.Places(itemId)
    return Store()[tonumber(itemId)]
end

function Net.Count()
    local places, tomes = 0, 0
    for _, list in pairs(Store()) do
        if #list > 0 then tomes = tomes + 1 end
        places = places + #list
    end
    return places, tomes
end

function Net.PeerCount()
    local n, now = 0, GetTime()
    for _, seen in pairs(peers) do
        if now - seen < PEER_TIMEOUT then n = n + 1 end
    end
    return n
end

function Net.StatusText()
    local places, tomes = Net.Count()
    local state = L.NetOff
    if Opt().netEnabled then
        if FindChannel() then
            state = L.NetOn
        else
            state = joined and L.NetNoChannel or L.NetJoining
        end
    end
    return format(L.NetStatus, state, Net.PeerCount(), places, tomes)
end

------------------------------------------------------------------------
-- Own drops and incoming ones
------------------------------------------------------------------------
-- A tome the player just looted: sent when it is a new place, or a known place
-- this player confirms (the others then count one more finder). With nobody online
-- to receive it, it also waits in the outbox until another user shows up.
function Net.Report(record)
    local _, changed = Net.Add(record)
    if not changed then return false end
    Changed()
    if not Opt().netEnabled then return true end
    local wire = Net.Encode(record)
    if Net.PeerCount() == 0 then
        local box = Outbox()
        box[#box + 1] = { wire = wire, at = time() }
        while #box > OUTBOX_MAX do tremove(box, 1) end
    end
    Queue("D", wire)
    return true
end

-- Returns true for a new place.
local function Receive(record, fromSync)
    local isNew, changed = Net.Add(record)
    if changed then Changed() end
    if not isNew then return false end
    if not fromSync and ns.Opt().alertNetwork and ns.Wishlist.Has(record.itemId) then
        local row = ns.Catalog.Get(record.itemId)
        local zone = tostring(record.zone or ""):gsub(":", " - ")
        ns.Print(L.AlertNetwork, record.by or "?", row and row.name or "?", zone,
            record.mob and (" (" .. record.mob .. ")") or "")
    end
    return true
end

local function NewestLearned()
    local newest = 0
    for _, list in pairs(Store()) do
        for _, r in ipairs(list) do
            newest = math.max(newest, Learned(r))
        end
    end
    return newest
end

------------------------------------------------------------------------
-- Sync
------------------------------------------------------------------------
local function IsLegacy(qid)
    return #qid ~= 5
end

-- Our places after <since>, oldest first: by time found for a 2.0.0 asker, by time
-- learned otherwise.
local function Candidates(since, legacy)
    local function Stamp(r) return legacy and (tonumber(r.at) or 0) or Learned(r) end
    local list = {}
    for _, places in pairs(Store()) do
        for _, r in ipairs(places) do
            if Stamp(r) > since then list[#list + 1] = r end
        end
    end
    table.sort(list, function(a, b) return Stamp(a) < Stamp(b) end)
    -- the asker goes on after the last record it gets: never split records of the
    -- same second between two answers
    local count = math.min(#list, SYNC_MAX_RECORDS)
    while count < #list and Stamp(list[count + 1]) == Stamp(list[count]) do count = count + 1 end
    return list, count
end

local function SendEncoded(qid, more, wires)
    local head = #WIRE + 3 + #qid + 3
    local line = ""
    for _, encoded in ipairs(wires) do
        if line ~= "" and head + #line + 1 + #encoded > 240 then
            Queue("S", qid .. "~" .. more .. "~" .. line)
            line = ""
        end
        line = line == "" and encoded or (line .. ";" .. encoded)
    end
    if line ~= "" then Queue("S", qid .. "~" .. more .. "~" .. line) end
end

local function SendRecords(qid, more, records, first, last)
    local wires = {}
    for i = first, last do wires[#wires + 1] = Net.Encode(records[i]) end
    SendEncoded(qid, more, wires)
end

local function Heard(qid, record)
    local byTome = heard[qid]
    if not byTome then
        byTome = {}
        heard[qid] = byTome
        ns.Timer.After(300, function() heard[qid] = nil end)
    end
    local list = byTome[record.itemId]
    if not list then
        list = {}
        byTome[record.itemId] = list
    end
    list[#list + 1] = record
end

local function WasHeard(qid, r)
    local list = heard[qid] and heard[qid][r.itemId]
    if not list then return false end
    for _, h in ipairs(list) do
        if SameSpot(h, r) then return true end
    end
    return false
end

-- Another user's request. The user with the most to send answers first; then a 2.0.0
-- asker gets no other answer, a 2.1.0 asker gets from each other user what the answers
-- heard so far lacked.
local function Answer(qid, since)
    if answering[qid] ~= nil then return end
    local legacy = IsLegacy(qid)
    local list, count = Candidates(since, legacy)
    if #list == 0 then return end
    local request = { legacy = legacy }
    answering[qid] = request
    local delay = 1 + 4 * (1 - math.min(count, SYNC_MAX_RECORDS) / SYNC_MAX_RECORDS) + math.random() * 1.5
    ns.Timer.After(delay, function()
        if answering[qid] ~= request then return end   -- a 2.0.0 asker got its answer
        answering[qid] = false                         -- answered: a repeated request is ignored
        if not legacy then
            -- afresh: places may have come meanwhile, those already said are left out
            local all = Candidates(since, false)
            list = {}
            for _, r in ipairs(all) do
                if not WasHeard(qid, r) then list[#list + 1] = r end
            end
            if #list == 0 then return end
            count = math.min(#list, SYNC_MAX_RECORDS)
            while count < #list and Learned(list[count + 1]) == Learned(list[count]) do count = count + 1 end
        end
        SendRecords(qid, count < #list and "1" or "0", list, 1, count)
    end)
end

-- Where our sync starts: the resume point of an unfinished one, else our last complete
-- sync (minus a margin: the clocks differ). Never asked: everything. Asked with 2.0.0,
-- which did not note it: from the newest place we have.
local function WindowStart()
    local from = tonumber(ns.DB.syncFrom)
    if from then return from end
    local synced = tonumber(ns.DB.syncedAt) or 0
    if synced > 0 then return math.max(0, synced - SYNC_MARGIN) end
    if (tonumber(ns.DB.lastSync) or 0) == 0 then return 0 end
    return math.max(0, NewestLearned() - SYNC_MARGIN)
end

local function HeardIn(qids, r)
    for _, qid in ipairs(qids) do
        if WasHeard(qid, r) then return true end
    end
    return false
end

-- End of our sync: tell what it brought, then send what we learned since its start and
-- nobody said (we may have learned it while the others were offline).
local function EndSession(session)
    if session.done then return end
    session.done = true
    if session.fresh > 0 then ns.Print(L.NetSynced, session.fresh) end
    if not (session.answered or Net.PeerCount() > 0) then return end   -- nobody online
    local list = {}
    for _, r in ipairs((Candidates(session.since, false))) do
        if Learned(r) <= session.startedAt and pushed[r] ~= Learned(r) and not HeardIn(session.qids, r) then
            list[#list + 1] = r
        end
    end
    if #list == 0 then return end
    local first = math.max(1, #list - PUSH_MAX + 1)   -- the most recent ones
    for i = first, #list do pushed[list[i]] = Learned(list[i]) end
    SendRecords(PUSH, "0", list, first, #list)
end

local SendSyncRequest

-- A part of the answer to our own request.
local function OnOwnAnswer(author, more, newest, fresh)
    local sync = mySync
    local session = sync.session
    session.answered = true
    session.fresh = session.fresh + fresh
    local from = sync.authors[author]
    if not from then
        from = { newest = sync.since }
        sync.authors[author] = from
    end
    if newest > from.newest then from.newest = newest end
    if more then from.more = true end
    sync.parts = sync.parts + 1
    local parts = sync.parts
    ns.Timer.After(SYNC_SETTLE, function()
        if mySync ~= sync or sync.parts ~= parts then return end   -- another part came since
        mySync = nil
        -- users with more to send: go on from the lowest point one of them reached
        local resume
        for _, a in pairs(sync.authors) do
            if a.more and (not resume or a.newest < resume) then resume = a.newest end
        end
        if resume then
            ns.DB.syncFrom = resume   -- kept for the next login if the batches run out
            if sync.batches < SYNC_BATCHES and SendSyncRequest(resume, sync.batches + 1, session) then return end
        else
            ns.DB.syncFrom = nil      -- up to date with the users online
            ns.DB.syncedAt = session.startedAt
        end
        EndSession(session)
    end)
end

SendSyncRequest = function(since, batches, session)
    local qid = format("%05x", math.random(0, 0xFFFFF))
    local sync = { qid = qid, since = since, batches = batches, parts = 0, authors = {}, session = session }
    local payload = qid .. "^" .. floor(since)
    if not Queue("Q", payload) then return false end
    session.qids[#session.qids + 1] = qid
    mySync = sync
    local wire = WIRE .. "~Q~" .. payload
    local function Wait()
        if mySync ~= sync then return end
        if Queued(wire) then   -- still waiting for the channel
            ns.Timer.After(SYNC_WAIT, Wait)
            return
        end
        if sync.parts == 0 then
            mySync = nil
            EndSession(session)
        end
    end
    ns.Timer.After(SYNC_WAIT, Wait)
    return true
end

-- Asks the users online for the places we do not have (at most every 10 min, unless
-- `force`: a user showed up after our last sync went unanswered). Answers come oldest
-- first, 30 at most: while there are more, we ask again from the last one received (a
-- few times, then at the next login: ns.DB.syncFrom).
function Net.RequestSync(force)
    if not Opt().netEnabled then return false end
    if not force and time() - (ns.DB.lastSync or 0) < SYNC_COOLDOWN then return false end
    local since = WindowStart()
    ns.DB.lastSync = time()
    local session = { since = since, startedAt = time(), qids = {}, fresh = 0 }
    if not SendSyncRequest(since, 1, session) then return false end
    lastSession = session
    return true
end

-- Another user shows up (first message after 30 min of silence): our finds made alone
-- leave now, and if our last sync did not go to the end, we ask again.
local function OnPeerArrived()
    local box = Outbox()
    if #box > 0 then
        local limit, wires = time() - OUTBOX_DAYS * 86400, {}
        for _, entry in ipairs(box) do
            if type(entry.wire) == "string" and (tonumber(entry.at) or 0) > limit then wires[#wires + 1] = entry.wire end
        end
        wipe(box)
        SendEncoded(PUSH, "0", wires)
    end
    ns.Fire("NET_PEER_ARRIVED")
    if mySync or (lastSession and not lastSession.done) then return end   -- a sync is going on
    if (tonumber(ns.DB.syncedAt) or 0) >= (tonumber(ns.DB.lastSync) or 0) then return end
    if reasks >= REASK_MAX or GetTime() - lastReask < REASK_GAP then return end
    reasks, lastReask = reasks + 1, GetTime()
    ns.Timer.After(REASK_DELAY, function()
        if not mySync then Net.RequestSync(true) end
    end)
end

ns.RegisterEvent("CHAT_MSG_CHANNEL", function(text, author, _, channelString, _, _, _, channelNumber, channelName)
    if not (IsOurChannel(channelString) or IsOurChannel(channelName)) then return end
    if type(channelNumber) == "number" and channelNumber > 0 then channelIndex = channelNumber end
    if not Opt().netEnabled then return end
    local wire, msgType, payload = tostring(text or ""):match("^(%w+)~(%a)~(.*)$")
    if wire ~= WIRE then return end
    local me = UnitName("player")
    if author and author ~= "" and author ~= me then
        local last = peers[author]
        peers[author] = GetTime()
        if not last or GetTime() - last >= PEER_TIMEOUT then OnPeerArrived() end
    end
    if msgType == "D" then
        if author == me then return end
        local record = Net.Decode(payload)
        if record then
            record.by = record.by or author
            Receive(record, false)
        end
    elseif msgType == "Q" then
        local qid, since = payload:match("^(%x+)%^(%d+)$")
        if qid and qid ~= PUSH and author ~= me then Answer(qid, tonumber(since) or 0) end
    elseif msgType == "S" then
        local qid, more, body = payload:match("^(%x+)~([01])~(.*)$")
        if not qid then return end
        local request = answering[qid]
        if request and request.legacy then answering[qid] = nil end   -- somebody answered it
        if author == me then return end
        local newest, fresh = 0, 0
        for encoded in body:gmatch("[^;]+") do
            local record, learned = Net.Decode(encoded)
            if record then
                if qid ~= PUSH then Heard(qid, record) end
                newest = math.max(newest, learned or record.at)
                if Receive(record, true) then fresh = fresh + 1 end
            end
        end
        if mySync and mySync.qid == qid then OnOwnAnswer(author, more == "1", newest, fresh) end
    elseif author ~= me then
        ns.Fire("NET_MESSAGE", msgType, payload, author)   -- Evidence.lua: K, V
    end
end)

-- Never show the protocol, nor "Joined / Left channel" notices, in a chat window
-- that would still list the channel.
if ChatFrame_AddMessageEventFilter then
    local function HideOurs(self, event, ...)
        local channelString, channelName = select(4, ...), select(9, ...)
        return IsOurChannel(channelString) or IsOurChannel(channelName)
    end
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", HideOurs)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", HideOurs)
end

------------------------------------------------------------------------
-- Life cycle
------------------------------------------------------------------------
ns.On("LOGIN", function()
    -- after the default channels (General, Trade...) so their numbers do not move
    ns.Timer.After(JOIN_DELAY, function()
        if not Opt().netEnabled then return end
        Net.Join()
        ns.Timer.After(5, Net.RequestSync)
    end)
end)

ns.On("SETTINGS_CHANGED", function(key)
    if key ~= "netEnabled" then return end
    if Opt().netEnabled then
        Net.Join()
        Net.RequestSync()
    else
        Net.Leave()
    end
end)
