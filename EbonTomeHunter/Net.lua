local addonName, ns = ...
local L = ns.L

-- Drop places shared between the players, through EbonAPI (by Siphelis,
-- github.com/Siphelis/EbonAPI): a separate addon each player installs, never shipped nor
-- changed here (its licence forbids both). Without it, the places stay on this computer.
-- Every tome is one EbonAPI dataset, "T<item id>": its places, those of every player put
-- together. EbonAPI spreads the datasets from player to player and keeps them in its saved
-- data, also for players who do not run EbonTomeHunter (AutoCallboard, SkillTreeAutoLoad... users):
-- a find reaches the others even when they are never online at the same time, as soon as
-- they meet any EbonAPI user, and one hidden channel serves every addon of EbonAPI.
-- A client takes a newer dataset (higher state), merges it into what it knows and, when it
-- knows more, publishes the union again: every copy converges to the union of the finds.
--   dataset T<itemId>  place;place;...   (12 places at most, the best known first)
--     place = itemId^mapFile^x^y^npcId^mob^zone^found^finder^finders^candidates
--       x, y: 0..1000 on the zone map; found: time() of the last drop there; finder: the
--       first player who found it; finders: how many did; candidates (no mob known):
--       "npcId:Name,..." the mobs one of which dropped it (Greedy Scavenger, Hints.lua)
--   dataset E<itemId>  the evidence of stale sources (Evidence.lua)
--   channel ops KQ / KA: kill statistics asked by the developer helper (/ethdev stats)
-- A dataset state is time() * 1000 plus a checksum of its text: two players who publish
-- different texts in the same second (a group farming together) still get different states,
-- or neither would take the other's. A state more than a day in the future is refused
-- (forged), as is any text with an escape sequence.
ns.Net = {}
local Net = ns.Net

local API_NAME = "EbonTomeHunter"
local API_MAJOR, API_MINOR = 1, 0
local URL = "https://github.com/AxFeed-Wow/EbonTomeHunter"
local MAX_PER_TOME = 12
local MAX_FINDERS = 10
local MAX_CANDIDATES = 4
local CANDIDATES_ROOM = 200   -- a place with its candidates stays under this many bytes
local PUBLISH_DELAY = 3       -- seconds: several changes leave as one publication
local FUTURE = 86400
local STATE_SCALE = 1000
local LIVE = 3600             -- a place found this recently is news (wishlist alert)
local OLD_PLACE = 90 * 86400  -- a place nobody found again for 90 days comes after the others
local STATS_TOP = 60
local STATS_WAIT = 15
local STATS_GAP = 30

local api                     -- the EbonAPI handle; nil without EbonAPI (or when it is too old)
local apiReady, catalogReady, started = false, false, false
local dirty = {}              -- [dataset name] = true: to publish again
local publishPending = false
local statsRequest            -- our statistics request: { qid, results = { [name] = { total, kills } } }
local lastStatsRequest, lastStatsAnswer = -math.huge, -math.huge

local function Opt() return ns.Opt() end

local function Store()
    if type(ns.DB.sightings) ~= "table" then ns.DB.sightings = {} end
    return ns.DB.sightings
end

------------------------------------------------------------------------
-- Records
------------------------------------------------------------------------
-- Byte limit that never cuts a UTF-8 character in two (French zone and mob names).
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
    text = tostring(text or ""):gsub("[~%^;|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return Utf8Cut(text, maxLength)
end

-- How many players found a place: its finders we know by name, or the count a dataset gave.
local function CountFinders(record)
    local n = 0
    for _ in pairs(type(record.finders) == "table" and record.finders or {}) do n = n + 1 end
    return math.max(n, tonumber(record.n) or 0)
end
Net.FinderCount = CountFinders

local function EncodeCandidates(list, room)
    -- one order for every client (the same text everywhere: no endless republishing)
    local sorted = {}
    for i, c in ipairs(type(list) == "table" and list or {}) do sorted[i] = c end
    table.sort(sorted, function(a, b)
        if (a.npcId or 0) ~= (b.npcId or 0) then return (a.npcId or 0) < (b.npcId or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    local parts, size = {}, 0
    for _, c in ipairs(sorted) do
        local name = Clean(tostring(c.name or ""):gsub("[,:]", ""), 24)
        if name ~= "" then
            local item = (tonumber(c.npcId) and floor(tonumber(c.npcId)) or "") .. ":" .. name
            if #parts >= MAX_CANDIDATES or size + #item + 1 > room then break end
            parts[#parts + 1] = item
            size = size + #item + 1
        end
    end
    return table.concat(parts, ",")
end

local function DecodeCandidates(text)
    local list = {}
    for item in tostring(text or ""):gmatch("[^,]+") do
        local id, name = item:match("^(%d*):(.+)$")
        if name and #list < MAX_CANDIDATES then list[#list + 1] = { npcId = tonumber(id), name = name } end
    end
    return #list > 0 and list or nil
end

function Net.Encode(r)
    local wire = table.concat({
        r.itemId, Clean(r.mapFile, 30),
        r.x and floor(r.x * 1000 + 0.5) or "", r.y and floor(r.y * 1000 + 0.5) or "",
        r.npcId or "", Clean(r.mob, 40), Clean(r.zone, 60), floor(tonumber(r.at) or time()), Clean(r.by, 24),
        math.min(99, CountFinders(r)),
    }, "^")
    if not r.mob and r.cands then
        local candidates = EncodeCandidates(r.cands, CANDIDATES_ROOM - #wire - 1)
        if candidates ~= "" then wire = wire .. "^" .. candidates end
    end
    return wire
end

local function Plausible(stamp, now)
    return stamp <= now + FUTURE and stamp >= now - 2 * 365 * 86400
end

-- nil for anything malformed, unknown or implausible.
function Net.Decode(text)
    text = tostring(text or "")
    -- names end up in chat lines and windows: an escape sequence ("|c" colour, "|H" link,
    -- "|T" texture) or a control character was not written by EbonTomeHunter
    if text:find("[|%c]") then return nil end
    local f = { strsplit("^", text) }
    if #f < 9 then return nil end
    local itemId = tonumber(f[1])
    if not (itemId and ns.Catalog.Get(itemId)) then return nil end
    local x, y = tonumber(f[3]), tonumber(f[4])
    if (x and (x < 0 or x > 1000)) or (y and (y < 0 or y > 1000)) or ((x == nil) ~= (y == nil)) then return nil end
    local at, now = tonumber(f[8]) or 0, time()
    if not Plausible(at, now) then return nil end
    local mob = f[6] ~= "" and f[6] or nil
    local finders = tonumber(f[10])
    return {
        itemId = itemId, mapFile = f[2] ~= "" and f[2] or nil, x = x and x / 1000, y = y and y / 1000,
        npcId = tonumber(f[5]), mob = mob, zone = f[7], at = math.min(at, now),
        by = f[9] ~= "" and f[9] or nil, n = finders and math.max(0, math.min(99, floor(finders))) or nil,
        cands = not mob and DecodeCandidates(f[11]) or nil,
    }
end

-- Is this mob (npcId or name) in a candidate list?
local function IsCandidate(list, npcId, name)
    for _, c in ipairs(list or {}) do
        if (npcId and c.npcId == npcId) or (name and c.name == name) then return true end
    end
    return false
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
    -- one does not know its mob (Scavenger loot after several kills): the same place when
    -- its candidates allow it (none listed: anything)
    if a.mob then return not b.cands or IsCandidate(b.cands, a.npcId, a.mob) end
    if b.mob then return not a.cands or IsCandidate(a.cands, b.npcId, b.mob) end
    if not (a.cands and b.cands) then return true end
    for _, c in ipairs(a.cands) do
        if IsCandidate(b.cands, c.npcId, c.name) then return true end
    end
    return false
end
Net.SameSpot = SameSpot

-- The candidates of a place narrowed by another drop there: nil when nothing changes.
local function Narrow(old, new)
    if not old then return new end
    local kept = {}
    for _, c in ipairs(old) do
        if IsCandidate(new, c.npcId, c.name) then kept[#kept + 1] = c end
    end
    if #kept == 0 or #kept == #old then return nil end
    return kept
end

-- The best places first: confirmed by the most players, then the most recent.
local function Better(a, b)
    local ca, cb = CountFinders(a), CountFinders(b)
    if ca ~= cb then return ca > cb end
    if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
    return Net.Encode(a) < Net.Encode(b)   -- a total order: every client writes the same text
end

local function Milli(v) return v and floor(v * 1000 + 0.5) or nil end

-- Two copies of one place must end with the same fields on every client, whatever the order
-- in which they met: the smallest finder name, the smallest point, the most precise zone text.
local function Converge(old, record)
    local changed = false
    if record.by and (not old.by or record.by < old.by) then old.by, changed = record.by, true end
    if record.x and old.x then
        local ox, oy, rx, ry = Milli(old.x), Milli(old.y), Milli(record.x), Milli(record.y)
        if rx < ox or (rx == ox and ry < oy) then old.x, old.y, changed = record.x, record.y, true end
    elseif record.x and not old.x then
        old.x, old.y, changed = record.x, record.y, true
    end
    local oz, rz = tostring(old.zone or ""), tostring(record.zone or "")
    if #rz > #oz or (#rz == #oz and rz > oz) then old.zone, changed = record.zone, true end
    return changed
end

-- Stores a drop place. Returns true when it is a new place, and whether anything changed.
function Net.Add(record)
    local store = Store()
    local list = store[record.itemId]
    if not list then
        list = {}
        store[record.itemId] = list
    end
    for _, old in ipairs(list) do
        if SameSpot(old, record) then
            old.finders = type(old.finders) == "table" and old.finders or {}
            local changed = Converge(old, record)
            if record.by and not old.finders[record.by] and CountFinders(old) < MAX_FINDERS then
                old.finders[record.by] = true
                changed = true
            end
            local count = tonumber(record.n) or 0
            if count > CountFinders(old) then old.n, changed = count, true end
            if (record.at or 0) > (old.at or 0) then old.at, changed = record.at, true end
            if not old.mob and record.mob then
                old.mob, old.npcId, old.cands, changed = record.mob, record.npcId, nil, true   -- now we know the mob
            elseif not old.mob and record.cands then
                -- another Scavenger drop here: only the mobs killed both times remain
                local narrowed = Narrow(old.cands, record.cands)
                if narrowed then
                    old.cands, changed = narrowed, true
                    if #narrowed == 1 then
                        old.mob, old.npcId, old.cands, old.inferred = narrowed[1].name, narrowed[1].npcId, nil, true
                    end
                end
            end
            if not old.npcId and record.npcId and old.mob == record.mob then old.npcId, changed = record.npcId, true end
            return false, changed
        end
    end
    if not record.mob and record.cands and #record.cands == 1 then
        record.mob, record.npcId, record.cands, record.inferred = record.cands[1].name, record.cands[1].npcId, nil, true
    end
    record.finders = record.by and { [record.by] = true } or {}
    list[#list + 1] = record
    if #list > MAX_PER_TOME then
        table.sort(list, Better)
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
        local candidates
        if not r.mob and type(r.cands) == "table" then
            candidates = {}
            for i, c in ipairs(r.cands) do candidates[i] = c.name end
        end
        out[#out + 1] = {
            source = "net", mapFile = r.mapFile, x = r.x, y = r.y, placeName = place,
            mobs = r.mob and { r.mob } or nil, npcIds = (r.mob and r.npcId) and { [r.mob] = r.npcId } or nil,
            candidates = candidates, inferred = r.inferred,
            notes = format(L.NetNotes, r.by or "?", ns.Ago(r.at) or "?", math.max(1, CountFinders(r))),
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

------------------------------------------------------------------------
-- Datasets (EbonAPI)
------------------------------------------------------------------------
-- The text of a tome's dataset: its places, the best first (the same order on every client).
local function PlacesText(itemId)
    local list = {}
    for i, r in ipairs(Store()[itemId] or {}) do list[i] = r end
    table.sort(list, Better)
    local parts = {}
    for i = 1, math.min(#list, MAX_PER_TOME) do parts[i] = Net.Encode(list[i]) end
    return table.concat(parts, ";")
end
Net.PlacesText = PlacesText

local function DatasetItem(name)
    local kind, id = tostring(name or ""):match("^([TE])(%d+)$")
    return kind, tonumber(id)
end

-- A state higher than the copy we hold (see the top of this file).
local function NextState(held, text)
    local sum = 0
    for i = 1, #text do sum = (sum * 31 + text:byte(i)) % STATE_SCALE end
    return math.max(time() * STATE_SCALE, (tonumber(held) or 0) + 1) + sum
end

local function Flush()
    publishPending = false
    if not (api and started and Opt().netEnabled) then return end
    for name in pairs(dirty) do
        dirty[name] = nil
        local kind, itemId = DatasetItem(name)
        local text
        if kind == "T" then
            text = PlacesText(itemId)
        elseif kind == "E" and ns.Evidence and ns.Evidence.SharedText then
            text = ns.Evidence.SharedText(itemId)
        end
        local held, state = api:GetShared(name)
        if text and text ~= "" and text ~= held then
            pcall(api.Share, api, name, NextState(state, text), text)
        end
    end
end

-- A dataset to publish again soon (several changes leave together).
local function Publish(name)
    dirty[name] = true
    if publishPending then return end
    publishPending = true
    ns.Timer.After(PUBLISH_DELAY, Flush)
end

function Net.PublishEvidence(itemId)
    if tonumber(itemId) then Publish("E" .. floor(tonumber(itemId))) end
end

-- A place learned from the network: stored, and told for a wishlist tome found lately.
local function Receive(record, alert)
    local isNew, changed = Net.Add(record)
    if changed then Changed() end
    if isNew and alert and ns.Opt().alertNetwork and ns.Wishlist.Has(record.itemId)
        and time() - (record.at or 0) < LIVE then
        local row = ns.Catalog.Get(record.itemId)
        local zone = tostring(record.zone or ""):gsub(":", " - ")
        ns.Print(L.AlertNetwork, record.by or "?", row and row.name or "?", zone,
            record.mob and (" (" .. record.mob .. ")") or "")
    end
    return isNew
end

-- The places of a received dataset, merged. Returns the new places; the tome's dataset is
-- published again when we know more than it said.
local function ImportPlaces(itemId, text, alert)
    local fresh = 0
    for part in tostring(text or ""):gmatch("[^;]+") do
        local record = Net.Decode(part)
        if record and record.itemId == itemId and Receive(record, alert) then fresh = fresh + 1 end
    end
    if PlacesText(itemId) ~= text then Publish("T" .. itemId) end
    return fresh
end
Net.ImportPlaces = ImportPlaces

local function ImportDataset(name, text, alert)
    local kind, itemId = DatasetItem(name)
    if not (itemId and text) then return 0 end
    if kind == "T" then return ImportPlaces(itemId, text, alert) end
    if kind == "E" and ns.Evidence and ns.Evidence.ImportShared then
        if ns.Evidence.ImportShared(itemId, text) then Publish(name) end
    end
    return 0
end

-- Which datasets of ours to take (EbonAPI asks, on the receiving side): the kinds we know,
-- with a state higher than ours and not in the future.
local function Accept(name, theirState, myState)
    if not DatasetItem(name) then return false end
    local theirs = tonumber(theirState) or 0
    if theirs > (time() + FUTURE) * STATE_SCALE then return false end
    return myState == nil or theirs > (tonumber(myState) or 0)
end
Net.Accept = Accept

-- Every dataset EbonAPI holds merged in, then ours published where they know less than we
-- do (the places of older versions, or found with the network off, join the network).
local function SyncAll()
    local fresh = 0
    for _, name in ipairs(api:SharedNames() or {}) do
        local text = api:GetShared(name)
        fresh = fresh + ImportDataset(name, text, false)
    end
    for itemId in pairs(Store()) do
        if tonumber(itemId) then Publish("T" .. itemId) end
    end
    if ns.Evidence and ns.Evidence.SharedTomes then
        for itemId in pairs(ns.Evidence.SharedTomes()) do Publish("E" .. itemId) end
    end
    if fresh > 0 then ns.Print(L.NetReceived, fresh) end
end

-- Once EbonAPI and the catalogue are both ready.
local function Start()
    if started or not (api and apiReady and catalogReady) then return end
    started = true
    if Opt().netEnabled then SyncAll() end
    ns.Fire("NET_SYNC_STATE")
end

local function OnShareReceived(_, addon, name, _, sender)
    if addon ~= API_NAME or not started or not Opt().netEnabled then return end
    local text = api:GetShared(name)
    ImportDataset(name, text, true)
    ns.Fire("NET_SYNC_STATE", sender)
end

------------------------------------------------------------------------
-- Own drops
------------------------------------------------------------------------
-- A tome the player just looted: stored, and its dataset published when the place is new or
-- this player confirms a known one.
function Net.Report(record)
    local _, changed = Net.Add(record)
    if not changed then return false end
    Changed()
    if api and Opt().netEnabled then Publish("T" .. record.itemId) end
    return true
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
function Net.Available()
    return api ~= nil
end

function Net.IsJoined()
    return api ~= nil and Opt().netEnabled and api:IsChannelJoined() and true or false
end

-- "off" (network option off), "noapi" (EbonAPI missing or too old), "joining" (EbonAPI not
-- in its channel yet) or "online".
function Net.SyncState()
    if not Opt().netEnabled then return "off" end
    if not api then return "noapi" end
    if not api:IsChannelJoined() then return "joining" end
    return "online"
end

function Net.DatasetCount()
    local n = 0
    for _, name in ipairs(api and api:SharedNames() or {}) do
        if DatasetItem(name) == "T" then n = n + 1 end
    end
    return n
end

function Net.StatusText()
    local places, tomes = Net.Count()
    local state = Net.SyncState()
    local text = state == "off" and L.NetOff or (state == "noapi" and L.NetNoApi)
        or (state == "joining" and L.NetJoining) or L.NetOn
    return format(L.NetStatus, text, places, tomes)
end

-- /eth net sync: EbonAPI announces our datasets now (at most every 30 s).
function Net.ForceSync()
    if Net.SyncState() ~= "online" then
        ns.Print(Net.StatusText())
        return false
    end
    local ok = api:SyncShares()
    ns.Print(ok and L.NetSyncAsked or L.NetSyncWait)
    return ok
end

-- A newer EbonTomeHunter seen on the network by EbonAPI (which tells the player itself).
function Net.NewerVersion()
    if not api then return nil end
    local latest = api:AvailableUpdate()
    return latest
end

------------------------------------------------------------------------
-- Kill statistics (asked by the developer helper, /ethdev stats)
------------------------------------------------------------------------
-- Asks the users online for their kills per creature; after 15 s, NET_STATS is fired with
-- { [name] = { total, kills = { [npcId] = count } } }.
function Net.RequestStats()
    if Net.SyncState() ~= "online" or GetTime() - lastStatsRequest < STATS_GAP then return false end
    local current = { qid = format("%05x", math.random(0, 0xFFFFF)), results = {} }
    if not api:Say("KQ", current.qid) then return false end
    lastStatsRequest = GetTime()
    statsRequest = current
    ns.Timer.After(STATS_WAIT, function()
        if statsRequest ~= current then return end
        statsRequest = nil
        ns.Fire("NET_STATS", current.results)
    end)
    return true
end

-- A user asked: our 60 most killed creatures, at most every 30 s.
local function OnStatsAsked(_, body)
    local qid = tostring(body or ""):match("^(%x+)$")
    if not qid or not Opt().netEnabled or GetTime() - lastStatsAnswer < STATS_GAP then return end
    lastStatsAnswer = GetTime()
    local list, total = {}, 0
    for npcId, s in pairs(type(ns.DB.killStats) == "table" and ns.DB.killStats or {}) do
        local n = tonumber(s.n) or 0
        total = total + n
        list[#list + 1] = { npcId = npcId, n = n }
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    local entries = {}
    for i = 1, math.min(#list, STATS_TOP) do entries[i] = list[i].npcId .. ":" .. list[i].n end
    ns.Timer.After(1 + math.random() * 4, function()
        if api then api:Say("KA", qid .. "^" .. total .. "^" .. table.concat(entries, ";")) end
    end)
end

local function OnStatsAnswer(sender, body)
    local current = statsRequest
    local qid, total, list = tostring(body or ""):match("^(%x+)%^(%d+)%^(.*)$")
    if not (current and qid == current.qid and sender) then return end
    local kills = {}
    for npcId, n in list:gmatch("(%d+):(%d+)") do kills[tonumber(npcId)] = tonumber(n) end
    current.results[sender] = { total = tonumber(total), kills = kills }
end

------------------------------------------------------------------------
-- Life cycle
------------------------------------------------------------------------
-- Binds EbonTomeHunter to EbonAPI (loaded before us: OptionalDeps). False without it, or
-- when it is too old for us (EbonAPI then tells the player).
function Net.Connect()
    if api then return true end
    if type(EbonAPI) ~= "table" or type(EbonAPI.NewAddon) ~= "function" then return false end
    local ok, handle = pcall(EbonAPI.NewAddon, EbonAPI, API_NAME, API_MAJOR, API_MINOR)
    if not (ok and type(handle) == "table") then return false end
    api = handle
    pcall(api.Version, api, ns.version, URL)
    api:ShareRule(Accept)
    api:On("SHARE_RECEIVED", OnShareReceived)
    api:On("CHANNEL_JOINED", function() ns.Fire("NET_SYNC_STATE") end)
    api:On("CHANNEL_LOST", function() ns.Fire("NET_SYNC_STATE") end)
    api:OnChannel("KQ", OnStatsAsked)
    api:OnChannel("KA", OnStatsAnswer)
    api:On("READY", function()   -- sticky: runs right away when EbonAPI is already ready
        apiReady = true
        Start()
    end)
    return true
end

ns.On("READY", function()
    catalogReady = true
    Start()
end)

-- No EbonAPI: the places stay here. Said once per version of EbonTomeHunter.
ns.On("LOGIN", function()
    ns.Timer.After(20, function()
        if api or not Opt().netEnabled or ns.DB.apiHint == ns.version then return end
        ns.DB.apiHint = ns.version
        ns.Print(L.NetNeedApi)
    end)
end)

-- Network on again: what EbonAPI received meanwhile is merged, our finds are published.
ns.On("SETTINGS_CHANGED", function(key)
    if key ~= "netEnabled" then return end
    if Opt().netEnabled and started then SyncAll() end
    ns.Fire("NET_SYNC_STATE")
end)

Net.Connect()
