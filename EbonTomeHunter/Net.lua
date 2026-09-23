local addonName, ns = ...
local L = ns.L

-- Community drop places. When an EbonTomeHunter user loots a tome, where it dropped
-- (zone map position, mob) is sent to every other user online; each client keeps
-- the places and shows them like the EbonholdHub ones, so a tome listed as
-- "Unknown location" gets a real place for everybody.
-- Stock 3.3.5a has no realm-wide addon channel: like EbonAffixAlert, a hidden chat
-- channel is joined and removed from the chat windows. Wire: "ETHN1~<type>~<payload>",
-- at most 240 characters, never "|" (chat escape character).
--   D  one drop:            itemId^mapFile^x^y^npcId^mob^zone^time^finder
--   Q  sync request:        qid^since
--   S  sync answer:         qid~more~record;record;...   oldest first, 30 at most; more=1
--                           when there are others (the asker then asks again from the
--                           last one). The best-stocked client answers first, the others
--                           see the answer and stay silent.
ns.Net = {}
local Net = ns.Net

local CHANNEL = "ebontomehunter"
local WIRE = "ETHN1"
local SEND_DELAY = 0.3
local MAX_QUEUE = 40
local MAX_PER_TOME = 12
local MAX_FINDERS = 10
local SYNC_MAX_RECORDS = 30
local SYNC_COOLDOWN = 600
local SYNC_MARGIN = 600      -- the clocks of two players are never exactly in time
local SYNC_BATCHES = 5       -- requests per session when the backlog is large
local SYNC_SETTLE = 4        -- seconds without a new part: the answer is complete
local JOIN_DELAY = 10

local channelIndex
local joined = false
local queue = {}
local nextSend = 0
local peers = {}           -- [name] = GetTime() of their last message
local awaitingReply = {}   -- [qid] = true while we wait before answering a sync request
local mySync               -- our pending sync request: { qid, newest, more, batches, parts }

local function Opt() return ns.Opt() end

local function Store()
    if type(ns.DB.sightings) ~= "table" then ns.DB.sightings = {} end
    return ns.DB.sightings
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
    if LeaveChannelByName then LeaveChannelByName(CHANNEL) end
end

function Net.IsJoined()
    return joined
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
    return table.concat({
        r.itemId, Clean(r.mapFile, 30),
        r.x and floor(r.x * 1000 + 0.5) or "", r.y and floor(r.y * 1000 + 0.5) or "",
        r.npcId or "", Clean(r.mob, 40), Clean(r.zone, 60), floor(tonumber(r.at) or time()), Clean(r.by, 24),
    }, "^")
end

-- nil for anything malformed, unknown or implausible.
function Net.Decode(text)
    local f = { strsplit("^", tostring(text or "")) }
    if #f < 9 then return nil end
    local itemId = tonumber(f[1])
    if not (itemId and ns.Catalog.Get(itemId)) then return nil end
    local x, y = tonumber(f[3]), tonumber(f[4])
    if (x and (x < 0 or x > 1000)) or (y and (y < 0 or y > 1000)) or ((x == nil) ~= (y == nil)) then return nil end
    local at, now = tonumber(f[8]) or 0, time()
    if at > now + 86400 or at < now - 2 * 365 * 86400 then return nil end
    at = math.min(at, now)   -- a clock a little ahead must not push the sync forward
    return {
        itemId = itemId, mapFile = f[2] ~= "" and f[2] or nil, x = x and x / 1000, y = y and y / 1000,
        npcId = tonumber(f[5]), mob = f[6] ~= "" and f[6] or nil, zone = f[7], at = at,
        by = f[9] ~= "" and f[9] or nil,
    }
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
            return false, confirmed
        end
    end
    record.finders = record.by and { [record.by] = true } or {}
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

-- Drop places of a tome, as catalogue locations (zone map coordinates).
function Net.Locations(itemId)
    local list = Store()[tonumber(itemId)]
    if not list or #list == 0 then return nil end
    local out = {}
    for index, r in ipairs(list) do
        local zone, sub = tostring(r.zone or ""):match("^([^:]*):?(.*)$")
        local place = (sub and sub ~= "") and (zone .. " - " .. sub) or (zone ~= "" and zone or L.LocationUnknown)
        local finders = math.max(1, CountFinders(r))
        out[#out + 1] = {
            source = "net", mapFile = r.mapFile, x = r.x, y = r.y, placeName = place,
            mobs = r.mob and { r.mob } or nil, npcIds = (r.mob and r.npcId) and { [r.mob] = r.npcId } or nil,
            notes = format(L.NetNotes, r.by or "?", ns.Ago(r.at) or "?", finders),
            order = 50000 + index,
        }
    end
    return out
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
        if now - seen < 1800 then n = n + 1 end
    end
    return n
end

function Net.StatusText()
    local places, tomes = Net.Count()
    local state = (Opt().netEnabled and joined) and L.NetOn or L.NetOff
    return format(L.NetStatus, state, Net.PeerCount(), places, tomes)
end

------------------------------------------------------------------------
-- Own drops and incoming ones
------------------------------------------------------------------------
-- A tome the player just looted: sent when it is a new place, or a known place
-- this player confirms (the others then count one more finder).
function Net.Report(record)
    local _, changed = Net.Add(record)
    if not changed then return false end
    Changed()
    Queue("D", Net.Encode(record))
    return true
end

local function Receive(record, fromSync)
    local isNew, changed = Net.Add(record)
    if changed then Changed() end
    if not isNew then return end
    if not fromSync and ns.Opt().alertNetwork and ns.Wishlist.Has(record.itemId) then
        local row = ns.Catalog.Get(record.itemId)
        local zone = tostring(record.zone or ""):gsub(":", " - ")
        ns.Print(L.AlertNetwork, record.by or "?", row and row.name or "?", zone,
            record.mob and (" (" .. record.mob .. ")") or "")
    end
end

local function NewestTime()
    local newest = 0
    for _, list in pairs(Store()) do
        for _, r in ipairs(list) do
            if (r.at or 0) > newest then newest = r.at end
        end
    end
    return newest
end

local function SendSyncRequest(since, batches)
    local qid = format("%04x", math.random(0, 65535))
    mySync = { qid = qid, newest = since, more = false, batches = batches, parts = 0 }
    return Queue("Q", qid .. "^" .. since)
end

-- Asks the users online for the drops we do not have (at most every 10 min).
-- Answers come oldest first, 30 at most: while there are more, we ask again from
-- the last one received (a few times, then at the next login: ns.DB.syncFrom).
function Net.RequestSync()
    if not Opt().netEnabled then return false end
    if time() - (ns.DB.lastSync or 0) < SYNC_COOLDOWN then return false end
    ns.DB.lastSync = time()
    local since = tonumber(ns.DB.syncFrom) or math.max(0, NewestTime() - SYNC_MARGIN)
    return SendSyncRequest(since, 1)
end

-- A part of the answer to our own request.
local function OnOwnAnswer(more, newest)
    local sync = mySync
    if newest > sync.newest then sync.newest = newest end
    if more then sync.more = true end
    sync.parts = sync.parts + 1
    local parts = sync.parts
    ns.Timer.After(SYNC_SETTLE, function()
        if mySync ~= sync or sync.parts ~= parts then return end   -- another part came since
        mySync = nil
        if sync.more then
            ns.DB.syncFrom = sync.newest
            if sync.batches < SYNC_BATCHES then SendSyncRequest(sync.newest, sync.batches + 1) end
        else
            ns.DB.syncFrom = nil   -- up to date: next time, from the newest record we have
        end
    end)
end

local function Answer(qid, since)
    local records = {}
    for _, list in pairs(Store()) do
        for _, r in ipairs(list) do
            if (r.at or 0) > since then records[#records + 1] = r end
        end
    end
    if #records == 0 then return end
    table.sort(records, function(a, b) return (a.at or 0) < (b.at or 0) end)
    -- the asker goes on after the last record it gets: never split records of the
    -- same second between two answers
    local count = math.min(#records, SYNC_MAX_RECORDS)
    while count < #records and records[count + 1].at == records[count].at do count = count + 1 end
    local more = count < #records and "1" or "0"
    awaitingReply[qid] = true
    -- the user with the most to send answers first; when someone answers, the others
    -- stay silent (no flood)
    local delay = 1 + 4 * (1 - math.min(#records, SYNC_MAX_RECORDS) / SYNC_MAX_RECORDS) + math.random() * 1.5
    ns.Timer.After(delay, function()
        if not awaitingReply[qid] then return end
        awaitingReply[qid] = nil
        local head = #WIRE + 3 + #qid + 3
        local line = ""
        for i = 1, count do
            local encoded = Net.Encode(records[i])
            if line ~= "" and head + #line + 1 + #encoded > 240 then
                Queue("S", qid .. "~" .. more .. "~" .. line)
                line = ""
            end
            line = line == "" and encoded or (line .. ";" .. encoded)
        end
        if line ~= "" then Queue("S", qid .. "~" .. more .. "~" .. line) end
    end)
end

ns.RegisterEvent("CHAT_MSG_CHANNEL", function(text, author, _, channelString, _, _, _, channelNumber, channelName)
    if not (IsOurChannel(channelString) or IsOurChannel(channelName)) then return end
    if type(channelNumber) == "number" and channelNumber > 0 then channelIndex = channelNumber end
    if not Opt().netEnabled then return end
    local wire, msgType, payload = tostring(text or ""):match("^(%w+)~(%a)~(.*)$")
    if wire ~= WIRE then return end
    local me = UnitName("player")
    if author and author ~= "" and author ~= me then peers[author] = GetTime() end
    if msgType == "D" then
        if author == me then return end
        local record = Net.Decode(payload)
        if record then
            record.by = record.by or author
            Receive(record, false)
        end
    elseif msgType == "Q" then
        local qid, since = payload:match("^(%x+)%^(%d+)$")
        if qid and author ~= me then Answer(qid, tonumber(since) or 0) end
    elseif msgType == "S" then
        local qid, more, body = payload:match("^(%x+)~([01])~(.*)$")
        if not qid then return end
        awaitingReply[qid] = nil   -- somebody answered: no need to answer too
        if author == me then return end
        local newest = 0
        for encoded in body:gmatch("[^;]+") do
            local record = Net.Decode(encoded)
            if record then
                newest = math.max(newest, record.at)
                Receive(record, true)
            end
        end
        if mySync and mySync.qid == qid then OnOwnAnswer(more == "1", newest) end
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
