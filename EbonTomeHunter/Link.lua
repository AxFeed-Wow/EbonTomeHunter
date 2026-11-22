local addonName, ns = ...

-- The network of EbonTomeHunter itself: a hidden chat channel between its users (stock 3.3.5a
-- has no realm-wide addon channel), used while EbonAPI is kept aside (NetApi.lua, Net.lua picks
-- one of the two). It carries the datasets of Net.lua ("T<item id>" the places of a tome,
-- "E<item id>" its evidence): texts of lines separated by ";", every line meaningful alone.
-- Nothing is sent to compare the data but fingerprints, and only the lines the others lack:
--   P  name~line;line          lines just learned (a drop of ours, the result of a merge)
--   A  F~datasets~version      "here is the fingerprint F of all I hold": at login, then every
--                              15 min by one user only (hearing an A resets the others' timer)
--   B  F~buckets               answer to an A with another F: the fingerprints of the 48
--                              buckets (item id % 48); users holding the same data answer once
--   L  bucket!name=hash,../..  the announcer lists its datasets of the buckets that differ
--   D  name~hash~i~n~lines     the whole text of a dataset the lister holds another (or no)
--                              version of; whoever knows more lines answers with a P of them
--   G  name,name,...           "send me these datasets" (the lister holds them, we do not)
--   X  op~id~i~n~text          a free message of Net.lua in parts (kill statistics)
-- Users in step exchange one A every 15 min, whatever their number. Every answer waits a random
-- moment and is dropped when another user gave it meanwhile. One line of at most 240 characters
-- leaves every 0.4 s (AzerothCore mutes 10 chat lines in one second), never "|". Received
-- lines are checked by Net.lua and Evidence.lua like any data from another player.
ns.Link = {}
local Link = ns.Link

local CHANNEL = "ebontomehunternet"
local WIRE = "E4"
local MAX_WIRE = 240
local TICK = 0.4             -- seconds: one line sent per tick at most
local BUCKETS = 48
local PERIOD = 900           -- seconds between two announcements (+ up to 2 min)
local JOIN_MIN, JOIN_MAX = 8, 30   -- the client restores the player's channels first (WOW-335.md)
local BUILD_PER_TICK = 6     -- datasets read per tick at the start (no hitch at login)
local ROUND = 30             -- seconds our announcement takes the answers
local REPLY_MAX, REPLY_WINDOW = 3, 600   -- answers about one dataset: a merge that never settles stops
local SYNC_GAP = 30          -- seconds between two forced announcements
local ASSEMBLY_TTL = 90      -- seconds to get every part of a text
local PEER_TIMEOUT = 1800
local BUSY = 3               -- texts being sent by this many others: ours wait (no burst of lines)
local OFFER_TTL = 600        -- seconds a text is not said again to a lister whose version did not change

local wanted, online = false, false
local enteredAt = 0
local queue = {}
local texts, hashes = {}, {}   -- [dataset name] = its text, its fingerprint (6 hex digits)
local building                 -- dataset names still to read at the start (nil once done)
local digest                   -- fingerprints of all the data (nil: to compute again)
local peers = {}               -- [name] = GetTime() of the last line heard
local newer                    -- a newer version heard
local nextAnnounce
local round                    -- our last announcement: { at, listed = { [bucket] = true }, todo, due }
local pendingB                 -- due time of our answer to an announcement
local pendingD = {}            -- [name] = { due, keys }: a whole text to send (keys: for `offered`)
local pendingReply = {}        -- [name] = { due, lines = { [line] = true } }
local want, wantDue = {}, nil  -- [name] = true: datasets to ask for
local assembling = {}          -- [sender/name] = { hash, n, parts, got, at }
local offered = {}             -- [lister/name/their hash] = { hash, at }: our text was said to that version
local settled = {}             -- [name/their hash] = our hash once their text was merged
local replied = {}             -- [name] = { n, since }
local says, sayParts = {}, {}  -- X messages: [op] = handler, [sender/id] = { n, parts, got, at }
local recentD = { -10, -10, -10 }   -- when the last texts of other users were heard
local lastSync = -math.huge
local stats = { sent = 0, received = 0 }
local nextPoll, lastSignature, stable, joinTries, nextTry = 0, nil, 0, 0, 0
local MAX_CHANNELS = 10      -- chat channels a character can be in
local toldFull = false

------------------------------------------------------------------------
-- Fingerprints
------------------------------------------------------------------------
local function Hash(text)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 16777213 end
    return h
end

local function Bucket(name)
    return (tonumber(name:match("%d+$")) or 0) % BUCKETS
end

local function LineSet(text)
    local set = {}
    for line in tostring(text or ""):gmatch("[^;]+") do set[line] = true end
    return set
end

-- The lines of a text that neither set holds.
local function Missing(text, a, b)
    local out = {}
    for line in tostring(text or ""):gmatch("[^;]+") do
        if not a[line] and not (b and b[line]) then out[#out + 1] = line end
    end
    return out
end

-- Reads a dataset again: its text and fingerprint (none when it is empty).
local function Refresh(name)
    local text = ns.Net.DatasetText(name) or ""
    if text == "" then text = nil end
    if text == texts[name] then return end
    texts[name], hashes[name] = text, text and format("%06x", Hash(text)) or nil
    digest = nil
end

local function Digest()
    if digest then return digest end
    local byBucket = {}
    for name in pairs(hashes) do
        local b = Bucket(name)
        byBucket[b] = byBucket[b] or {}
        tinsert(byBucket[b], name)
    end
    local d, all = { buckets = {}, entries = {}, count = 0 }, {}
    for b = 0, BUCKETS - 1 do
        local names, parts = byBucket[b] or {}, {}
        table.sort(names)
        for i, name in ipairs(names) do parts[i] = name .. "=" .. hashes[name] end
        d.count = d.count + #names
        d.entries[b] = table.concat(parts, ",")
        d.buckets[b] = format("%04x", Hash(d.entries[b]) % 65536)
        all[b + 1] = d.buckets[b]
    end
    d.all = table.concat(all)
    d.F = format("%06x", Hash(d.all))
    digest = d
    return d
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
local function Send(kind, payload)
    local wire = WIRE .. kind .. "~" .. payload
    if #wire > MAX_WIRE or wire:find("[|%z\1-\31\127]") then return false end
    queue[#queue + 1] = wire
    return true
end

-- Items put together, as many as fit in `room` characters each time.
local function Pack(items, separator, room)
    local out, current = {}, nil
    for _, item in ipairs(items) do
        if #item <= room then
            if current and #current + #separator + #item <= room then
                current = current .. separator .. item
            else
                out[#out + 1] = current
                current = item
            end
        end
    end
    out[#out + 1] = current
    return out
end

local function SendLines(name, lines)
    for _, part in ipairs(Pack(lines, ";", MAX_WIRE - #WIRE - 3 - #name)) do Send("P", name .. "~" .. part) end
end

local function SendFull(name)
    local text = texts[name]
    if not text then return end
    local lines = {}
    for line in text:gmatch("[^;]+") do lines[#lines + 1] = line end
    local head = name .. "~" .. hashes[name] .. "~"
    local parts = Pack(lines, ";", MAX_WIRE - #WIRE - 2 - #head - 8)   -- 8: "iii~nnn~"
    for i, part in ipairs(parts) do Send("D", head .. i .. "~" .. #parts .. "~" .. part) end
end

local function Announce()
    local d, now = Digest(), GetTime()
    Send("A", d.F .. "~" .. d.count .. "~" .. ns.version)
    round = { at = now, listed = {}, todo = {} }
    nextAnnounce = now + PERIOD + math.random() * 120
    lastSync = now
end

-- Lines of ours the others lack: sent in a moment, unless somebody says them first.
local function Reply(name, lines)
    if #lines == 0 then return end
    local now = GetTime()
    local count = replied[name]
    if not count or now - count.since > REPLY_WINDOW then
        count = { n = 0, since = now }
        replied[name] = count
    end
    if count.n >= REPLY_MAX then return end
    local reply = pendingReply[name]
    if not reply then
        reply = { due = now + 2 + math.random() * 4, lines = {} }
        pendingReply[name] = reply
    end
    for _, line in ipairs(lines) do reply.lines[line] = true end
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
-- Lines of another user merged into our data. Returns our text as it was before.
local function Import(name, text)
    local before = texts[name]
    ns.Net.Import(name, text, true)
    Refresh(name)
    local reply = pendingReply[name]
    if reply then
        for line in text:gmatch("[^;]+") do reply.lines[line] = nil end   -- (said by somebody else)
    end
    return before
end

local on = {}

function on.P(_, payload)
    local name, text = payload:match("^([TE]%d+)~(.+)$")
    if not (name and ns.Net.DatasetKnown(name)) then return end
    local before = Import(name, text)
    -- what the merge made of them, when it is neither what was said nor what we had
    Reply(name, Missing(texts[name], LineSet(text), LineSet(before)))
end

function on.D(author, payload)
    local name, hash, i, n, text = payload:match("^([TE]%d+)~(%x+)~(%d+)~(%d+)~(.+)$")
    i, n = tonumber(i), tonumber(n)
    if not (name and ns.Net.DatasetKnown(name)) or i < 1 or i > n or n > 300 then return end
    local now = GetTime()
    tremove(recentD, 1)
    recentD[#recentD + 1] = now
    want[name] = nil
    local pending = pendingD[name]
    pendingD[name] = nil   -- (the same text: said; another: we answer with our lines instead)
    if hashes[name] == hash then
        for key in pairs(pending and pending.keys or {}) do offered[key] = { hash = hash, at = now } end
        return
    end
    if settled[name .. "/" .. hash] == (hashes[name] or "") then return end
    local key = author .. "/" .. name
    local a = assembling[key]
    if not a or a.hash ~= hash or a.n ~= n then
        a = { hash = hash, n = n, parts = {}, got = 0, at = now }
        assembling[key] = a
    end
    if a.parts[i] then return end
    a.parts[i], a.got = text, a.got + 1
    Import(name, text)
    if a.got < n then return end
    assembling[key] = nil
    Reply(name, Missing(texts[name], LineSet(table.concat(a.parts, ";"))))
    settled[name .. "/" .. hash] = hashes[name] or ""
end

function on.A(_, payload)
    local F, _, version = payload:match("^(%x+)~(%d+)~([%d%.]+)$")
    if not F then return end
    Link.SeeVersion(version)
    if building then return end
    local now = GetTime()
    if nextAnnounce then nextAnnounce = now + PERIOD + math.random() * 120 end
    if F ~= Digest().F then pendingB = pendingB or (now + 1 + math.random() * 3) end
end

function on.B(_, payload)
    local F, all = payload:match("^(%x+)~(%x+)$")
    if not F or #all ~= BUCKETS * 4 or building then return end
    local d, now = Digest(), GetTime()
    if F == d.F then pendingB = nil end   -- (a user holding what we hold answered)
    if not round or now - round.at > ROUND then return end
    for b = 0, BUCKETS - 1 do
        if all:sub(b * 4 + 1, b * 4 + 4) ~= d.buckets[b] and not round.listed[b] then
            round.listed[b] = true
            round.todo[#round.todo + 1] = b
            round.due = round.due or (now + 1.5)
        end
    end
end

function on.L(author, payload)
    if building then return end
    local now = GetTime()
    for segment in payload:gmatch("[^/]+") do
        local b, list = segment:match("^(%d+)!(.*)$")
        b = tonumber(b)
        if b and b < BUCKETS then
            local theirs = {}
            for name, hash in list:gmatch("([TE]%d+)=(%x+)") do theirs[name] = hash end
            for name, hash in pairs(hashes) do
                if Bucket(name) == b and theirs[name] ~= hash then
                    local version = name .. "/" .. (theirs[name] or "")
                    local key = author .. "/" .. version
                    local said = offered[key]
                    if not (said and said.hash == hash and now - said.at < OFFER_TTL) and settled[version] ~= hash then
                        pendingD[name] = pendingD[name] or { due = now + 1 + math.random() * 4, keys = {} }
                        pendingD[name].keys[key] = true
                    end
                end
            end
            for name in pairs(theirs) do
                if not hashes[name] and Bucket(name) == b and ns.Net.DatasetKnown(name) then
                    want[name] = true
                    wantDue = wantDue or (now + 1 + math.random() * 2)
                end
            end
        end
    end
end

function on.G(_, payload)
    if building then return end
    for name in payload:gmatch("[TE]%d+") do
        if hashes[name] then pendingD[name] = pendingD[name] or { due = GetTime() + 1 + math.random() * 4, keys = {} } end
    end
end

function on.X(author, payload)
    local op, id, i, n, text = payload:match("^(%u+)~(%x+)~(%d+)~(%d+)~(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not (op and says[op]) or i < 1 or i > n or n > 20 then return end
    local key = author .. "/" .. id
    local a = sayParts[key]
    if not a or a.n ~= n then
        a = { n = n, parts = {}, got = 0, at = GetTime() }
        sayParts[key] = a
    end
    if a.parts[i] then return end
    a.parts[i], a.got = text, a.got + 1
    if a.got < n then return end
    sayParts[key] = nil
    says[op](author, table.concat(a.parts))
end

------------------------------------------------------------------------
-- Hidden channel
------------------------------------------------------------------------
local function IsOurChannel(name)
    return type(name) == "string" and strlower(name):find(CHANNEL, 1, true) ~= nil
end

local function FindChannel()
    if type(GetChannelName) ~= "function" then return nil end
    local index = tonumber((GetChannelName(CHANNEL)))
    return index and index > 0 and index or nil
end

local function HideChannel()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chat = _G["ChatFrame" .. i]
        if chat then ChatFrame_RemoveChannel(chat, CHANNEL) end
    end
end

-- Joins once the client has given the player's own channels back: joined before, ours takes
-- one of their numbers, and a channel joined while the client restores it breaks its sending.
local function TryJoin(now)
    if now < nextPoll then return end
    nextPoll = now + 2
    local list, parts = type(GetChannelList) == "function" and { GetChannelList() } or {}, {}
    for i, value in ipairs(list) do parts[i] = tostring(value) end
    local signature = table.concat(parts, ",")
    stable = signature == lastSignature and stable + 1 or 0
    lastSignature = signature
    local waited = now - enteredAt
    if not (waited >= JOIN_MAX or (#list > 0 and stable >= 2 and waited >= JOIN_MIN)) or now < nextTry then return end
    local channels = 0
    for _, value in ipairs(list) do
        if type(value) == "string" then channels = channels + 1 end
    end
    if channels >= MAX_CHANNELS then
        -- the game refuses an 11th channel: said once, joined as soon as the player left one
        if not toldFull then
            toldFull = true
            ns.Print(ns.L.NetChannelsFull)
        end
        return
    end
    joinTries = joinTries + 1
    nextTry = now + (joinTries < 3 and 10 or 300)   -- (refused beyond 10 chat channels: no nagging)
    if type(JoinChannelByName) == "function" then JoinChannelByName(CHANNEL) end
    HideChannel()
end

------------------------------------------------------------------------
-- The clock: what is due, then one line
------------------------------------------------------------------------
local function Due(now)
    if nextAnnounce and now >= nextAnnounce then Announce() end
    if pendingB and now >= pendingB then
        pendingB = nil
        local d = Digest()
        Send("B", d.F .. "~" .. d.all)
    end
    if round and round.due and now >= round.due then
        local d, segments = Digest(), {}
        for i, b in ipairs(round.todo) do
            -- ponytail: a bucket whose list passes one line is cut (the others then send those
            -- datasets every round); raise BUCKETS when a bucket holds more than ~12 datasets
            local list = d.entries[b]
            while #list > 200 do list = list:match("^(.*),[^,]*$") or "" end
            segments[i] = b .. "!" .. list
        end
        for _, part in ipairs(Pack(segments, "/", MAX_WIRE - #WIRE - 2)) do Send("L", part) end
        round.todo, round.due = {}, nil
    end
    if wantDue and now >= wantDue then
        local names = {}
        for name in pairs(want) do
            if not hashes[name] then names[#names + 1] = name end
        end
        table.sort(names)
        for _, part in ipairs(Pack(names, ",", MAX_WIRE - #WIRE - 2)) do Send("G", part) end
        wipe(want)
        wantDue = nil
    end
    for name, reply in pairs(pendingReply) do
        if now >= reply.due then
            pendingReply[name] = nil
            local lines, mine = {}, LineSet(texts[name])
            for line in pairs(reply.lines) do
                if mine[line] then lines[#lines + 1] = line end
            end
            if #lines > 0 then
                table.sort(lines)
                replied[name].n = replied[name].n + 1
                SendLines(name, lines)
            end
        end
    end
    -- one whole text at a time, when nothing waits and few others are sending theirs
    if #queue <= 1 and now - recentD[#recentD - BUSY + 1] > 1 then
        local first, firstDue
        for name, pending in pairs(pendingD) do
            if pending.due <= now and (not firstDue or pending.due < firstDue) then first, firstDue = name, pending.due end
        end
        if first then
            -- said to those who listed another version: not again for 10 min while neither side changes
            for key in pairs(pendingD[first].keys) do offered[key] = { hash = hashes[first], at = now } end
            pendingD[first] = nil
            SendFull(first)
        end
    end
    for _, tbl in ipairs({ assembling, sayParts }) do
        for key, a in pairs(tbl) do
            if now - a.at > ASSEMBLY_TTL then tbl[key] = nil end
        end
    end
end

local function Tick()
    local now = GetTime()
    if building then
        for _ = 1, BUILD_PER_TICK do
            local name = tremove(building)
            if not name then
                building = nil
                break
            end
            Refresh(name)
        end
    end
    local index = FindChannel()
    if not index then
        if online then
            online = false
            ns.Net.Notify()
        end
        TryJoin(now)
        return
    end
    if not online then
        online = true
        HideChannel()
        nextAnnounce = now + 15 + math.random() * 15
        ns.Net.Notify()
    end
    if not building then Due(now) end
    if queue[1] and pcall(SendChatMessage, queue[1], "CHANNEL", nil, index) then
        tremove(queue, 1)
        stats.sent = stats.sent + 1
    end
end

local frame = CreateFrame("Frame")
frame:Hide()
local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < TICK then return end
    elapsed = 0
    Tick()
end)

ns.RegisterEvent("CHAT_MSG_CHANNEL", function(text, author, _, channelString, _, _, _, _, channelName)
    if not wanted or not (IsOurChannel(channelString) or IsOurChannel(channelName)) then return end
    local kind, payload = tostring(text or ""):match("^" .. WIRE .. "(%u)~(.*)$")
    if not (kind and on[kind]) or not author or author == "" or author == UnitName("player") then return end
    if payload:find("[|%z\1-\31\127]") then return end
    stats.received = stats.received + 1
    peers[author] = GetTime()
    on[kind](author, payload)
end)

-- Never show the protocol, nor the "Joined / Left channel" notices, in a chat window.
if ChatFrame_AddMessageEventFilter then
    local function HideOurs(_, _, ...)
        local channelString, channelName = select(4, ...), select(9, ...)
        return IsOurChannel(channelString) or IsOurChannel(channelName)
    end
    for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
        ChatFrame_AddMessageEventFilter(event, HideOurs)
    end
end

ns.On("LOGIN", function() enteredAt = GetTime() end)

------------------------------------------------------------------------
-- For Net.lua (the same functions as NetApi.lua)
------------------------------------------------------------------------
function Link.Connect() return true end
function Link.Ready() return true end

function Link.Start()
    if wanted then return end
    wanted = true
    wipe(texts)
    wipe(hashes)
    digest = nil
    building = ns.Net.DatasetNames()
    frame:Show()
end

function Link.Stop()
    if not wanted then return end
    wanted, online, building, round, pendingB, wantDue, nextAnnounce = false, false, nil, nil, nil, nil, nil
    for _, tbl in ipairs({ queue, pendingD, pendingReply, want, assembling, sayParts }) do wipe(tbl) end
    frame:Hide()
    if type(LeaveChannelByName) == "function" then LeaveChannelByName(CHANNEL) end
end

-- A dataset of ours changed: its new lines leave now (a text still unread at the start is no news).
function Link.Changed(name)
    if not wanted then return end
    local before = texts[name]
    if building and before == nil then return end
    Refresh(name)
    if online and texts[name] then SendLines(name, Missing(texts[name], LineSet(before))) end
end

function Link.Joined()
    return wanted and online and FindChannel() ~= nil
end

-- Announces our data now; false when it was done less than 30 s ago.
function Link.Sync()
    if not Link.Joined() or building or GetTime() - lastSync < SYNC_GAP then return false end
    Announce()
    return true
end

function Link.Say(op, body)
    if not Link.Joined() then return false end
    local parts, id = {}, format("%04x", math.random(0, 0xFFFF))
    body = tostring(body or "")
    for i = 1, math.max(#body, 1), 200 do parts[#parts + 1] = body:sub(i, i + 199) end
    for i, part in ipairs(parts) do
        if not Send("X", op .. "~" .. id .. "~" .. i .. "~" .. #parts .. "~" .. part) then return false end
    end
    return true
end

function Link.Listen(op, fn) says[op] = fn end

-- Datasets of places we hold.
function Link.Count()
    local n = 0
    for name in pairs(hashes) do
        if name:sub(1, 1) == "T" then n = n + 1 end
    end
    return n
end

-- Users heard in the last 30 min.
function Link.PeerCount()
    local n, now = 0, GetTime()
    for _, at in pairs(peers) do
        if now - at < PEER_TIMEOUT then n = n + 1 end
    end
    return n
end

-- { sent, received }: lines of this session (tests, /eth net).
function Link.Stats() return stats end

local function Version(text)
    local a, b, c = tostring(text or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    return a and { tonumber(a), tonumber(b), tonumber(c) } or nil
end

local function IsNewer(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return false
end

-- A version heard from another user: remembered when newer than ours and than the last one heard
-- (one major version ahead at most: a forged "99.0.0" must not nag everybody).
function Link.SeeVersion(text)
    local theirs, mine = Version(text), Version(ns.version)
    if not (theirs and mine) or theirs[1] > mine[1] + 1 or not IsNewer(theirs, mine) then return end
    if newer and not IsNewer(theirs, Version(newer)) then return end
    newer = text
    ns.Net.TellUpdate()
end

function Link.Newer() return newer end
