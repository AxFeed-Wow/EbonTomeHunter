local addonName, ns = ...
local L = ns.L

-- Drop places shared between the players. This file holds the data: the places of every tome,
-- how two copies of them merge, and their texts. A transport carries the texts between the
-- players: Link.lua, a hidden chat channel of our own, or NetApi.lua, the EbonAPI addon of
-- Siphelis (kept aside while it does not work with the server's v2 update: USE_EBONAPI below).
-- Every tome is one dataset, "T<item id>": its places, those of every player put together.
-- A client merges the lines it receives into what it knows; every copy converges to the union
-- of the finds, also between players who are never online at the same time (through any
-- player who met both).
--   dataset T<itemId>  place;place;...   (12 places at most, the best known first)
--     place = itemId^mapFile^x^y^npcId^mob^zone^found^finder^finders^candidates
--       x, y: 0..1000 on the zone map; found: time() of the last drop there; finder: the
--       first player who found it; finders: how many did; candidates (no mob known):
--       "npcId:Name,..." the mobs one of which dropped it (Scavenger's Eye, Hints.lua)
--   dataset E<itemId>  the evidence of stale sources (Evidence.lua)
--   messages KQ / KA: kill statistics asked by the developer helper (/ethdev stats)
-- A place must say which mob dropped the tome, or which ones it may be (candidates): a place
-- without either (older versions) is neither kept nor shared. The candidates are narrowed by
-- every drop: at the same spot, only the mobs killed each time remain; anywhere, a candidate
-- that is a known source of the tome (a confirmed place, EbonholdHub, the server's hint) is
-- the mob when it is the only one; several known sources among them stay candidates.
-- Any text with an escape sequence is refused, as is a place dated in the future.
ns.Net = {}
local Net = ns.Net

local USE_EBONAPI = false     -- true: the network goes through EbonAPI (NetApi.lua) again
local URL = "https://github.com/AxFeed-Wow/EbonTomeHunter"
local MAX_PER_TOME = 12
local MAX_FINDERS = 10
local MAX_CANDIDATES = 4
local CANDIDATES_ROOM = 200   -- a place with its candidates stays under this many bytes
local PUBLISH_DELAY = 3       -- seconds: several changes leave together
local FUTURE = 86400
local LIVE = 3600             -- a place found this recently is news (wishlist alert)
local OLD_PLACE = 90 * 86400  -- a place nobody found again for 90 days comes after the others
local STATS_TOP = 60
local STATS_WAIT = 15
local STATS_GAP = 30

local transport               -- ns.Link or ns.NetApi; nil when EbonAPI is chosen but missing
local catalogReady, started = false, false
local dirty = {}              -- [dataset name] = true: changed, to tell the others
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
    -- (explicit bytes, not %c / %s: those follow the locale of the computer, and a byte of an
    -- accented letter such as the second one of "\195\144" must stay)
    text = tostring(text or ""):gsub("[~%^;|%z\1-\31\127]", ""):gsub(" +", " "):gsub("^ ", ""):gsub(" $", "")
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

-- ponytail: no instance difficulty (normal / heroic) in a place yet: a 12th field would make 3.x
-- clients (which write 11) and newer ones republish each other's text forever. Add it once the
-- 3.x clients are gone, with the difficulty from GetInstanceInfo() in Loot.CapturePlace.
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
    if text:find("[|%z\1-\31\127]") then return nil end
    local f = { strsplit("^", text) }
    if #f < 9 then return nil end
    local itemId = tonumber(f[1])
    if not (itemId and ns.Catalog.Get(itemId)) then return nil end
    local x, y = tonumber(f[3]), tonumber(f[4])
    if (x and (x < 0 or x > 1000)) or (y and (y < 0 or y > 1000)) or ((x == nil) ~= (y == nil)) then return nil end
    local at, now = tonumber(f[8]) or 0, time()
    if not Plausible(at, now) then return nil end
    local mob = f[6] ~= "" and f[6] or nil
    local cands = not mob and DecodeCandidates(f[11]) or nil
    if not (mob or cands) then return nil end   -- a place of an older version: which mob is unknown
    local finders = tonumber(f[10])
    return {
        itemId = itemId, mapFile = f[2] ~= "" and f[2] or nil, x = x and x / 1000, y = y and y / 1000,
        npcId = tonumber(f[5]), mob = mob, zone = f[7], at = at,   -- (as said, even a little ahead of our clock: one text for all)
        by = f[9] ~= "" and f[9] or nil, n = finders and math.max(0, math.min(99, floor(finders))) or nil,
        cands = cands,
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
    if not (a.mapFile and b.mapFile) then
        -- a place without its map (an instance the client had no map for): one with the same mob
        if a.mapFile ~= b.mapFile and not ((a.npcId and a.npcId == b.npcId) or (a.mob and a.mob == b.mob)) then
            return false
        end
    elseif a.mapFile ~= b.mapFile then
        return false
    end
    if a.mapFile ~= b.mapFile then
        -- (same mob, one place without a map)
    elseif a.x and b.x then
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

-- The best places first: confirmed by the most players, then the most recent, then by their
-- text (a total order: every client writes the same text). Sorts { record, wire } pairs.
local function Better(a, b)
    local ca, cb = CountFinders(a.record), CountFinders(b.record)
    if ca ~= cb then return ca > cb end
    local ta, tb = a.record.at or 0, b.record.at or 0
    if ta ~= tb then return ta > tb end
    return a.wire < b.wire
end

-- The places of a list, the best first: { { record, wire } }.
local function Ranked(list)
    local out = {}
    for i, r in ipairs(list) do out[i] = { record = r, wire = Net.Encode(r) } end
    table.sort(out, Better)
    return out
end

local function Milli(v) return v and floor(v * 1000 + 0.5) or nil end

-- Two copies of one place must end with the same fields on every client, whatever the order
-- in which they met: the smallest finder name, the smallest point, the most precise zone text.
local function Converge(old, record)
    local changed = false
    if record.mapFile and not old.mapFile then   -- the place now knows its map
        old.mapFile, old.x, old.y, old.zone, changed = record.mapFile, record.x, record.y, record.zone, true
    end
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
    if not (record.mob or (record.cands and #record.cands > 0)) then return false, false end
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
        local ranked = Ranked(list)
        for i = #list, 1, -1 do list[i] = nil end
        for i = 1, MAX_PER_TOME do list[i] = ranked[i].record end
    end
    return true, true
end

-- The places of a tome changed: its catalogue row is built again (Catalog.lua).
local function Changed(itemId) ns.FireSoon("SIGHTINGS_CHANGED", 1, itemId) end

-- A Scavenger place whose candidates hold exactly one known source of the tome gets that mob
-- (merged with a place of that mob at the same spot). Returns true when something changed.
local function Refine(itemId)
    local list = Store()[itemId]
    if not list then return false end
    local known = ns.Hints and ns.Hints.KnownSources(itemId) or {}
    for _, r in ipairs(list) do
        if r.mob then
            known[strlower(r.mob)] = true
            if r.npcId then known["#" .. r.npcId] = true end
        end
    end
    local changed = false
    for i = #list, 1, -1 do
        local r = list[i]
        if not r.mob and r.cands then
            local match
            for _, c in ipairs(r.cands) do
                if (c.npcId and known["#" .. c.npcId]) or known[strlower(c.name)] then
                    if match then match = false break end   -- several known sources: still a doubt
                    match = c
                end
            end
            if match then
                tremove(list, i)
                r.mob, r.npcId, r.cands, r.inferred = match.name, match.npcId, nil, true
                r.n = CountFinders(r)
                Net.Add(r)   -- (merged with a place of that mob at the same spot)
                changed = true
            end
        end
    end
    return changed
end
Net.Refine = Refine

-- The place a record names, as shown: "Zone - Subzone". The zone text is in the finder's client
-- language: a zone map known to MapData shows its English name instead (as the other sources of
-- the addon), an instance named in another alphabet the name of its map ("TheRubySanctum" ->
-- "The Ruby Sanctum"). The wire keeps the finder's text (3.x clients choose among them).
function Net.PlaceName(r)
    local zone, sub = tostring(r.zone or ""):match("^([^:]*):?(.*)$")
    local info = r.mapFile and ns.WorldMap.MapInfo(r.mapFile)
    if info and info.name and not info.continent and zone ~= info.name then
        zone, sub = info.name, ""
    elseif zone:find("[\128-\255]") and r.mapFile and not info then
        zone, sub = r.mapFile:gsub("%d+$", ""):gsub("(%l)(%u)", "%1 %2"), ""
    end
    if sub ~= "" then return zone .. " - " .. sub end
    return zone ~= "" and zone or L.LocationUnknown
end

-- Drop places of a tome, as catalogue locations (zone map coordinates), the most
-- recently found first. A mob found at several spots (it roams a whole zone) or by players of
-- several languages ("Revenant lié à la terre" is Earthbound Revenant: one NPC id) shows one
-- name, the one most of its finders saw, and `mobSeen`: the drops seen from it at every spot.
function Net.Locations(itemId)
    local stored = Store()[tonumber(itemId)]
    if not stored or #stored == 0 then return nil end
    local list = {}
    for i, r in ipairs(stored) do list[i] = r end
    table.sort(list, function(a, b) return (tonumber(a.at) or 0) > (tonumber(b.at) or 0) end)
    local votes, total = {}, {}   -- [mob key] = { [name] = finders }, [mob key] = finders
    local function MobKey(r) return r.npcId and ("#" .. r.npcId) or (r.mob and strlower(r.mob)) end
    for _, r in ipairs(list) do
        local key = r.mob and MobKey(r)
        if key then
            local n = math.max(1, CountFinders(r))
            votes[key] = votes[key] or {}
            votes[key][r.mob] = (votes[key][r.mob] or 0) + n
            total[key] = (total[key] or 0) + n
        end
    end
    local function Name(r)
        local best, most = r.mob, -1
        for name, n in pairs(votes[MobKey(r)] or {}) do
            if n > most or (n == most and name < best) then best, most = name, n end
        end
        return best
    end
    local out, now = {}, time()
    for index, r in ipairs(list) do
        local place = Net.PlaceName(r)
        -- found inside an instance whose map the client did not know: its point is one of the
        -- continent, not of the place (no map point; the teleport finds its meeting stone by name)
        local info = r.mapFile and ns.WorldMap.MapInfo(r.mapFile)
        local onMap = not (info and info.continent)
        local candidates
        if not r.mob and type(r.cands) == "table" then
            candidates = {}
            for i, c in ipairs(r.cands) do candidates[i] = c.name end
        end
        out[#out + 1] = {
            source = "net", mapFile = onMap and r.mapFile or nil, x = onMap and r.x or nil, y = onMap and r.y or nil,
            placeName = place,
            mobs = r.mob and { Name(r) } or nil, npcIds = (r.mob and r.npcId) and { [Name(r)] = r.npcId } or nil,
            mobSeen = r.mob and total[MobKey(r)] or nil,   -- drops seen from that mob, every spot
            candidates = candidates, inferred = r.inferred,
            notes = format(L.NetNotes, r.by or "?", ns.Ago(r.at) or "?", math.max(1, CountFinders(r))),
            seen = math.max(1, CountFinders(r)),   -- drops seen there: one per player who found it
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
-- Datasets (what the transport carries: Link.lua, or NetApi.lua)
------------------------------------------------------------------------
-- Does our text hold a line the other lacks?
function Net.HasNews(mine, held)
    local known = {}
    for line in tostring(held or ""):gmatch("[^;]+") do known[line] = true end
    for line in tostring(mine or ""):gmatch("[^;]+") do
        if not known[line] then return true end
    end
    return false
end

-- The text of a tome's dataset: its places, the best first (the same order on every client).
local function PlacesText(itemId)
    local ranked, parts = Ranked(Store()[itemId] or {}), {}
    for i = 1, math.min(#ranked, MAX_PER_TOME) do parts[i] = ranked[i].wire end
    return table.concat(parts, ";")
end
Net.PlacesText = PlacesText

local function DatasetItem(name)
    local kind, id = tostring(name or ""):match("^([TE])(%d+)$")
    return kind, tonumber(id)
end

-- A dataset name of a tome of the catalogue.
function Net.DatasetKnown(name)
    local kind, itemId = DatasetItem(name)
    return kind ~= nil and ns.Catalog.Get(itemId) ~= nil
end

-- The names of the datasets we may hold a text for.
function Net.DatasetNames()
    local names = {}
    for itemId, list in pairs(Store()) do
        if tonumber(itemId) and #list > 0 then names[#names + 1] = "T" .. itemId end
    end
    if ns.Evidence and ns.Evidence.SharedTomes then
        for itemId in pairs(ns.Evidence.SharedTomes()) do names[#names + 1] = "E" .. itemId end
    end
    return names
end

-- The text of a dataset as we hold it ("" when we hold nothing).
function Net.DatasetText(name)
    local kind, itemId = DatasetItem(name)
    if kind == "T" then return PlacesText(itemId) end
    if kind == "E" and ns.Evidence and ns.Evidence.SharedText then return ns.Evidence.SharedText(itemId) end
    return ""
end

local function Flush()
    publishPending = false
    if not (transport and started and Opt().netEnabled) then return end
    for name in pairs(dirty) do
        dirty[name] = nil
        transport.Changed(name)
    end
end

-- A dataset of ours changed: told to the others soon (several changes leave together).
local function Publish(name)
    dirty[name] = true
    if publishPending then return end
    publishPending = true
    ns.Timer.After(PUBLISH_DELAY, Flush)
end
Net.Publish = Publish

function Net.PublishEvidence(itemId)
    if tonumber(itemId) then Publish("E" .. floor(tonumber(itemId))) end
end

-- A place learned from the network: stored, and told for a wishlist tome found lately.
local function Receive(record, alert)
    local isNew, changed = Net.Add(record)
    if changed then Changed(record.itemId) end
    if isNew and alert and ns.Opt().alertNetwork and ns.Wishlist.Has(record.itemId)
        and time() - (record.at or 0) < LIVE then
        local row = ns.Catalog.Get(record.itemId)
        ns.Print(L.AlertNetwork, record.by or "?", row and row.name or "?", Net.PlaceName(record),
            record.mob and (" (" .. record.mob .. ")") or "")
    end
    return isNew
end

-- The places of received lines, merged. Returns the new places, and whether we know more
-- than they said.
local function ImportPlaces(itemId, text, alert)
    local fresh = 0
    for part in tostring(text or ""):gmatch("[^;]+") do
        local record = Net.Decode(part)
        if record and record.itemId == itemId and Receive(record, alert) then fresh = fresh + 1 end
    end
    if Refine(itemId) then Changed(itemId) end
    return fresh, Net.HasNews(PlacesText(itemId), text)
end
Net.ImportPlaces = ImportPlaces

-- Lines of a dataset received from another player (the transport calls it), merged into what
-- we hold. Returns the new places, and whether we know more than they said.
function Net.Import(name, text, alert)
    local kind, itemId = DatasetItem(name)
    if not (itemId and text) then return 0, false end
    if kind == "T" then return ImportPlaces(itemId, text, alert) end
    if kind == "E" and ns.Evidence and ns.Evidence.ImportShared then
        return 0, ns.Evidence.ImportShared(itemId, text) and true or false
    end
    return 0, false
end

local TellUpdate   -- (below: a newer version)

-- Once the transport and the catalogue are both ready.
local function Start()
    if started or not (transport and catalogReady and transport.Ready()) then return end
    started = true
    if Opt().netEnabled then transport.Start() end
    TellUpdate()   -- (already known from an earlier exchange)
    ns.Fire("NET_SYNC_STATE")
end
Net.TransportReady = Start

-- Started, and the network option on (the transport asks before it takes anything).
function Net.Running()
    return started and Opt().netEnabled and true or false
end

-- The transport joined or lost its channel, or took something from `sender`.
function Net.Notify(sender)
    ns.Fire("NET_SYNC_STATE", sender)
end

------------------------------------------------------------------------
-- Own drops
------------------------------------------------------------------------
-- A tome the player just looted: stored, and told to the others when the place is new or
-- this player confirms a known one.
function Net.Report(record)
    local _, changed = Net.Add(record)
    if not changed then return false end
    Refine(record.itemId)
    Changed(record.itemId)
    if transport and Opt().netEnabled then Publish("T" .. record.itemId) end
    return true
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
function Net.Available()
    return transport ~= nil
end

-- "off" (network option off), "noapi" (no transport: EbonAPI chosen but missing or too old),
-- "joining" (not in the channel yet) or "online".
function Net.SyncState()
    if not Opt().netEnabled then return "off" end
    if not transport then return "noapi" end
    if not transport.Joined() then return "joining" end
    return "online"
end

-- Tomes whose places are on the network.
function Net.DatasetCount()
    return transport and transport.Count() or 0
end

-- Other users heard lately (nil when the transport cannot tell).
function Net.PeerCount()
    return transport and transport.PeerCount and transport.PeerCount() or nil
end

function Net.StatusText()
    local places, tomes = Net.Count()
    local state = Net.SyncState()
    local text = state == "off" and L.NetOff or (state == "noapi" and L.NetNoApi)
        or (state == "joining" and L.NetJoining) or L.NetOn
    return format(L.NetStatus, text, places, tomes)
end

-- /eth net: what went through the channel in this session (nil when the transport cannot tell).
function Net.TrafficText()
    local stats = transport and transport.Stats and transport.Stats()
    if not stats or Net.SyncState() == "off" then return nil end
    return format(L.NetTraffic, stats.sent, stats.received, Net.PeerCount() or 0)
end

-- /eth net sync: our data is compared with the others' now (at most every 30 s).
function Net.ForceSync()
    if Net.SyncState() ~= "online" then
        ns.Print(Net.StatusText())
        return false
    end
    local ok = transport.Sync()
    ns.Print(ok and L.NetSyncAsked or L.NetSyncWait)
    return ok
end

-- A newer EbonTomeHunter seen on the network.
function Net.NewerVersion()
    return transport and transport.Newer() or nil
end

-- A newer version: told once in the chat, the network button turns into "Update!".
TellUpdate = function()
    local latest = Net.NewerVersion()
    if latest and ns.DB.updateTold ~= latest then
        ns.DB.updateTold = latest
        ns.Print(L.UpdateChat, latest, ns.version, URL)
    end
    ns.Fire("NET_SYNC_STATE")
end
Net.TellUpdate = TellUpdate

------------------------------------------------------------------------
-- Kill statistics (asked by the developer helper, /ethdev stats)
------------------------------------------------------------------------
-- Asks the users online for their kills per creature; after 15 s, NET_STATS is fired with
-- { [name] = { total, kills = { [npcId] = count } } }.
function Net.RequestStats()
    if Net.SyncState() ~= "online" or GetTime() - lastStatsRequest < STATS_GAP then return false end
    local current = { qid = format("%05x", math.random(0, 0xFFFFF)), results = {} }
    if not transport.Say("KQ", current.qid) then return false end
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
        if transport then transport.Say("KA", qid .. "^" .. total .. "^" .. table.concat(entries, ";")) end
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
-- Takes the transport: our own channel (Link.lua), or EbonAPI when USE_EBONAPI is set (false
-- without it, or when it is too old for us).
function Net.Connect()
    if transport then return true end
    local candidate = USE_EBONAPI and ns.NetApi or ns.Link
    if not (candidate and candidate.Connect()) then return false end
    transport = candidate
    transport.Listen("KQ", OnStatsAsked)
    transport.Listen("KA", OnStatsAnswer)
    return true
end

-- The saved places of older versions without a mob go, the candidates are narrowed again.
local function Tidy()
    for itemId, list in pairs(Store()) do
        -- the stored places merged again among themselves (older versions, or two places a later
        -- Converge brought together), in one order for every client
        local before = #list
        local ranked = Ranked(list)
        Store()[itemId] = {}
        for _, entry in ipairs(ranked) do
            local r = entry.record
            local finders = r.finders
            r.n = CountFinders(r)
            if Net.Add(r) then r.finders = finders end   -- (Add keeps only its finder)
        end
        list = Store()[itemId]
        local changed = #list ~= before
        for i = #list, 1, -1 do
            if not (list[i].mob or (list[i].cands and #list[i].cands > 0)) then
                tremove(list, i)
                changed = true
            end
        end
        if Refine(itemId) or changed then Changed(itemId) end
        if #list == 0 then Store()[itemId] = nil end
    end
end

Net.Tidy = Tidy

ns.On("READY", function()
    catalogReady = true
    Tidy()
    Start()
end)

-- EbonAPI chosen but missing: the places stay here. Said once per version of EbonTomeHunter.
ns.On("LOGIN", function()
    ns.Timer.After(20, function()
        if transport or not Opt().netEnabled or ns.DB.apiHint == ns.version then return end
        ns.DB.apiHint = ns.version
        ns.Print(L.NetNeedApi)
    end)
end)

-- Network switched on or off.
ns.On("SETTINGS_CHANGED", function(key)
    if key ~= "netEnabled" then return end
    if started then
        if Opt().netEnabled then transport.Start() else transport.Stop() end
    end
    ns.Fire("NET_SYNC_STATE")
end)

Net.Connect()
