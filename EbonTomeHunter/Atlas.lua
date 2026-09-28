local addonName, ns = ...
local L = ns.L

-- Drop places of the Tome Atlas of EbonBuilds (the addon of Ebonhold Addon Manager's catalogue):
-- the mobs and zones where its users saw each tome drop, put together between them. Read where
-- EbonBuilds keeps them (its saved data EbonBuildsDB.tomeAtlas), never written nor copied.
-- A tome gets its most seen sources (8 at most) that no other source lists already. Their
-- place is a zone name: on the map only where EbonBuilds noted the player's own loots
-- (tomeAtlasPinCoords); otherwise the teleport aims at the middle of the zone
-- (WorldMap.TravelPosition), and a raid or dungeon has no map point at all.
ns.Atlas = {}
local A = ns.Atlas

local MAX_SOURCES = 8
local SEP = "\031"            -- between the mob and the zone in EbonBuilds' keys
local CHECK_EVERY = 60        -- seconds: EbonBuilds records drops and its users' ones meanwhile

local function Data()
    local db = type(EbonBuildsDB) == "table" and EbonBuildsDB or nil
    local atlas = db and type(db.tomeAtlas) == "table" and db.tomeAtlas or nil
    local pins = db and type(db.tomeAtlasPinCoords) == "table" and db.tomeAtlasPinCoords or nil
    return atlas, pins
end

function A.Available()
    return (Data()) ~= nil
end

-- Names end up in chat lines and windows: no escape sequence ("|c", "|H"), nothing too long.
local function Clean(text)
    text = tostring(text or ""):gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, 60)
end

-- English zone names of the zone maps (EbonBuilds notes the zone the game names, English on
-- an English client: the other languages keep the zone name, without map point).
local zoneFiles
local function ZoneFile(zone)
    if not zoneFiles then
        zoneFiles = {}
        for file, info in pairs(ns.MapData and ns.MapData.maps or {}) do
            if info.name and not info.continent then zoneFiles[strlower(info.name)] = file end
        end
    end
    return zoneFiles[strlower(zone)]
end

-- The sources of a tome in the atlas, the most seen first: { mob (nil: not known), zone,
-- count }, and the tome's name there.
function A.Sources(itemId)
    local atlas = Data()
    local entry = atlas and tonumber(itemId) and atlas[tonumber(itemId)]
    if type(entry) ~= "table" or type(entry.sources) ~= "table" then return {} end
    local out = {}
    for key, count in pairs(entry.sources) do
        if type(key) == "string" then
            local mob, zone = key:match("^(.-)" .. SEP .. "(.*)$")
            mob, zone = Clean(mob or key), Clean(zone)
            if mob == "" or mob == "?" or mob == "Unknown" then mob = nil end
            if zone == "?" then zone = "" end
            out[#out + 1] = { mob = mob, zone = zone, count = math.max(1, floor(tonumber(count) or 1)) }
        end
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if (a.mob or "") ~= (b.mob or "") then return (a.mob or "") < (b.mob or "") end
        return a.zone < b.zone
    end)
    return out, type(entry.name) == "string" and entry.name or nil
end

-- Catalogue locations of the atlas sources of a tome. known: [lowercase mob name] = true
-- for the mobs its other sources list already (they are not repeated).
function A.Locations(itemId, known)
    local sources, tomeName = A.Sources(itemId)
    local _, pins = Data()
    local out, zones = {}, {}
    for _, s in ipairs(sources) do
        if s.mob then zones[strlower(s.zone)] = true end
    end
    for _, s in ipairs(sources) do
        if #out >= MAX_SOURCES then break end
        local key = s.mob and strlower(s.mob)
        -- a source without mob only tells a zone that no other source of the atlas gives
        local wanted = (key and not (known and known[key])) or (not key and s.zone ~= "" and not zones[strlower(s.zone)])
        if wanted then
            local file = s.zone ~= "" and ZoneFile(s.zone) or nil
            local byZone = pins and pins[s.zone]
            local pin = file and tomeName and type(byZone) == "table" and byZone[tomeName]
            local x, y = type(pin) == "table" and tonumber(pin.x), type(pin) == "table" and tonumber(pin.y)
            if not (x and y and x > 0 and x < 1 and y > 0 and y < 1) then x, y = nil, nil end
            out[#out + 1] = {
                source = "atlas", mapFile = file, x = x, y = y,
                placeName = s.zone ~= "" and s.zone or L.LocationUnknown,
                mobs = s.mob and { s.mob } or nil, count = s.count, seen = s.count,
                notes = format(L.SourceAtlas, s.count), order = 60000 + #out,
            }
            if key and known then known[key] = true end
            if not key then zones[strlower(s.zone)] = true end
        end
    end
    return out
end

-- EbonBuilds adds drops while we play: the catalogue takes them again when they change.
local signature
local function Signature()
    local atlas = Data()
    if not atlas then return "" end
    local n, total = 0, 0
    for _, entry in pairs(atlas) do
        if type(entry) == "table" and type(entry.sources) == "table" then
            for _, count in pairs(entry.sources) do
                n, total = n + 1, total + (tonumber(count) or 0)
            end
        end
    end
    return n .. ":" .. total
end

local function Check()
    local now = Signature()
    if signature and now ~= signature then ns.Fire("SIGHTINGS_CHANGED") end
    signature = now
    ns.Timer.After(CHECK_EVERY, Check)
end

ns.On("READY", function()
    if signature == nil then Check() end
end)
