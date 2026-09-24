local addonName, ns = ...
local L = ns.L

ns.Catalog = {}
local Cat = ns.Catalog

local QUALITY_SUFFIX = "%s*%(%a+%)%s*$"

function Cat.StripQualitySuffix(name)
    if type(name) ~= "string" then return name end
    local stripped = name:gsub(QUALITY_SUFFIX, "")
    if stripped ~= "" then return stripped end
    return name
end

function Cat.GetEchoLocations()
    local hub = EbonholdHub
    if hub and hub.EchoMapData and type(hub.EchoMapData.Locations) == "table" then
        return hub.EchoMapData.Locations, "hub"
    end
    local ec = EbonCompletionist
    if ec and ec.Data and ec.Data.EchoMap and type(ec.Data.EchoMap.Locations) == "table" then
        return ec.Data.EchoMap.Locations, "completionist"
    end
    return nil, nil
end

Cat.rows = {}
Cat.byItem = {}
Cat.bySpell = {}
Cat.byName = {}
Cat.byTomeName = {}
Cat.byEchoKey = {}
Cat.mapReady = false

-- FALLBACK identity, only used when TomeData.lua is missing: the echo's spellId.
-- With TomeData the key is the tome's real item id (== its spell id), and
-- auction listings match on that exact id (names are only a fallback).
local function ItemIdFromPerk(perk, spellId)
    if spellId then return spellId end
    if type(perk) == "table" and tonumber(perk.requiredSpell) then
        local id = tonumber(perk.requiredSpell)
        if id ~= 0 then return id end
    end
    return nil
end

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- ProjectEbonhold's PerkDatabase rows have NO `name` field: the display name
-- lives in `comment` ("Spiritual Fortitude - Common", "Death Knight - Foo"),
-- with GetSpellInfo(spellId) as the fallback.
function Cat.PerkName(perk, spellId)
    local name
    if type(perk) == "table" and type(perk.comment) == "string" and perk.comment ~= "" then
        name = perk.comment
        for _, rarity in ipairs(RARITIES) do
            name = name:gsub(" %- " .. rarity .. "$", "")
        end
        name = name:gsub("^%a+ %- ", ""):gsub("^Death Knight %- ", "")
    end
    if (not name or name == "") and spellId then
        name = ns.SafeCall(GetSpellInfo, spellId)
    end
    return name
end

-- Auction items are named "Tome of Echo: <echo name>" (verified against real
-- scan data). perk.requiredSpell, when set, is the tome SPELL and gives a second
-- accepted spelling; both are registered as aliases.
local TOME_PREFIX = "Tome of Echo: "

function Cat.TomeName(perk, echoName)
    if echoName then return TOME_PREFIX .. echoName end
    if type(perk) == "table" then
        local gate = tonumber(perk.requiredSpell)
        if gate and gate ~= 0 then
            local gateName = ns.SafeCall(GetSpellInfo, gate)
            if type(gateName) == "string" and gateName ~= "" then return gateName end
        end
    end
    return nil
end

function Cat.TomeAlias(perk)
    if type(perk) ~= "table" then return nil end
    local gate = tonumber(perk.requiredSpell)
    if not gate or gate == 0 then return nil end
    local gateName = ns.SafeCall(GetSpellInfo, gate)
    if type(gateName) == "string" and gateName ~= "" then return gateName end
    return nil
end

-- Lowercase, straighten the typographic apostrophes the game uses
-- ("Broodmother's Fury"), and collapse spaces.
function Cat.NormalizeName(name)
    if type(name) ~= "string" then return nil end
    -- The game uses a typographic apostrophe (UTF-8 E2 80 99) in names like
    -- "Broodmother's Fury": fold it to a plain quote before comparing.
    name = name:gsub(string.char(226, 128, 153), "'")
    name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return strlower(name)
end

-- "Tome of Echo: Pandemic" -> "pandemic" (also tolerates "Tome of Pandemic").
function Cat.EchoKeyFromTome(name)
    local key = Cat.NormalizeName(name)
    if not key then return nil end
    key = key:gsub("^tome of echo:%s*", ""):gsub("^tome of echo%s+", ""):gsub("^tome of%s+", "")
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return nil end
    return key
end

function Cat.Build()
    wipe(Cat.rows)
    wipe(Cat.byItem)
    wipe(Cat.bySpell)
    wipe(Cat.byName)
    wipe(Cat.byTomeName)
    wipe(Cat.byEchoKey)

    local seen = {}
    local AddRow   -- forward declaration (used by the static-data path below)
    AddRow = function(row)
        if not row or not row.name then return end
        local key = strlower(row.name)
        local prev = seen[key]
        if prev then
            prev.itemId = prev.itemId or row.itemId
            prev.spellId = prev.spellId or row.spellId
            prev.location = prev.location or row.location
            prev.quality = prev.quality or row.quality
            return
        end
        seen[key] = row
        Cat.rows[#Cat.rows + 1] = row
        if row.itemId then Cat.byItem[row.itemId] = row end
        if row.spellId then Cat.bySpell[row.spellId] = row end
        Cat.byName[key] = row
        -- Auction listings are matched on the tome's name, under every spelling.
        local tomeKey = Cat.NormalizeName(row.tomeName)
        if tomeKey then Cat.byTomeName[tomeKey] = row end
        local aliasKey = Cat.NormalizeName(row.tomeAlias)
        if aliasKey then Cat.byTomeName[aliasKey] = row end
        local echoKey = Cat.EchoKeyFromTome(row.name)
        if echoKey then Cat.byEchoKey[echoKey] = row end
    end

    -- Preferred path: the complete, static tome list extracted from the client
    -- (TomeData.lua: one row per real tome item, item id == tome spell id).
    -- Nothing to wait for at login, and auction listings match by exact item id.
    if type(ns.TomeData) == "table" and next(ns.TomeData) then
        Cat.BuildFromTomeData(AddRow)
        Cat.builtFromPerks = true
        Cat.fromTomeData = true
        Cat.MergeLearned()
        table.sort(Cat.rows, function(a, b) return (a.name or "") < (b.name or "") end)
        Cat.AttachAllSightings()
        Cat.mapReady = #Cat.rows > 0
        Cat.MigrateKeys()
        ns.Fire("CATALOG_CHANGED")
        return Cat
    end
    Cat.fromTomeData = false

    -- Fallback without TomeData.lua: ProjectEbonhold's echo database (read only).
    local perks = nil
    if ProjectEbonhold and type(ProjectEbonhold.PerkDatabase) == "table" then
        perks = ProjectEbonhold.PerkDatabase
    end
    -- The echo database may not be loaded yet at login: remember whether this
    -- build saw it, so the boot code can rebuild once it arrives (otherwise the
    -- catalogue stays limited to the handful of echoes with a known farm spot).
    Cat.builtFromPerks = perks ~= nil

    local perkByName = {}
    if perks then
        for spellId, perk in pairs(perks) do
            local sid = tonumber(spellId)
            local perkName = type(perk) == "table" and Cat.PerkName(perk, sid) or nil
            if sid and perkName then
                perkByName[strlower(Cat.StripQualitySuffix(perkName))] = { perk = perk, spellId = sid, name = perkName }
            end
        end
    end

    local locs = Cat.GetEchoLocations()
    if locs then
        for zoneSlug, entries in pairs(locs) do
            if type(entries) == "table" then
                for _, loc in ipairs(entries) do
                    if type(loc) == "table" and loc.name then
                        local stripped = Cat.StripQualitySuffix(loc.name)
                        local matched = perkByName[strlower(stripped)]
                        local perk = matched and matched.perk or nil
                        local spellId = tonumber(loc.spellId) or (matched and matched.spellId) or nil
                        local itemId = ItemIdFromPerk(perk, spellId)
                        AddRow({
                            itemId = itemId,
                            spellId = spellId,
                            name = stripped,
                            tomeName = Cat.TomeName(perk, stripped),
                            tomeAlias = Cat.TomeAlias(perk),
                            quality = loc.quality or (perk and perk.quality) or nil,
                            location = {
                                zone = zoneSlug,
                                placeName = loc.placeName,
                                mobs = loc.mobs,
                                notes = loc.notes,
                                description = loc.description,
                                x = loc.x,
                                y = loc.y,
                            },
                        })
                    end
                end
            end
        end
    end

    if perks then
        for spellId, perk in pairs(perks) do
            local sid = tonumber(spellId)
            local perkName = type(perk) == "table" and Cat.PerkName(perk, sid) or nil
            if sid and perkName then
                local name = Cat.StripQualitySuffix(perkName)
                if not seen[strlower(name)] then
                    AddRow({
                        itemId = ItemIdFromPerk(perk, sid),
                        spellId = sid,
                        name = name,
                        tomeName = Cat.TomeName(perk, name),
                        tomeAlias = Cat.TomeAlias(perk),
                        quality = perk.quality or nil,
                        location = nil,
                    })
                end
            end
        end
    end

    Cat.MergeLearned()

    table.sort(Cat.rows, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    Cat.mapReady = #Cat.rows > 0
    -- Built without the echo database (it loads after us at login): try again
    -- shortly, otherwise the catalogue would stay limited to a few echoes.
    if not Cat.builtFromPerks then Cat.ScheduleRebuild() end
    ns.Fire("CATALOG_CHANGED")
    return Cat
end

------------------------------------------------------------------------
-- Static tome data (TomeData.lua)
------------------------------------------------------------------------
local ITEM_QUALITY_NAMES = { [1] = "common", [2] = "uncommon", [3] = "rare", [4] = "epic", [5] = "legendary" }

-- Farm locations (EbonholdHub / EbonCompletionist) indexed by echo name. A tome often
-- drops in several places (even on several continents): all of them are kept, those
-- with a usable map point first, in a stable order.
local SLUG_ORDER = { ["eastern-kingdoms"] = 1, ["kalimdor"] = 2, ["outland"] = 3, ["northrend"] = 4 }

local function LocationsByEchoName()
    local out = {}
    local locs = Cat.GetEchoLocations()
    if not locs then return out end
    for zoneSlug, entries in pairs(locs) do
        if type(entries) == "table" then
            for index, loc in ipairs(entries) do
                if type(loc) == "table" and loc.name then
                    local key = Cat.NormalizeName(Cat.StripQualitySuffix(loc.name))
                    if key then
                        out[key] = out[key] or {}
                        local list = out[key]
                        local place = loc.placeName
                        if type(place) == "string" then place = place:gsub("''", "'") end   -- "Tyr''s Hand"
                        list[#list + 1] = {
                            zone = zoneSlug, placeName = place, mobs = loc.mobs, notes = loc.notes,
                            description = loc.description, x = loc.x, y = loc.y,
                            order = (SLUG_ORDER[zoneSlug] or 9) * 10000 + index,
                        }
                    end
                end
            end
        end
    end
    local WorldPosition = ns.WorldMap and ns.WorldMap.WorldPosition
    for _, list in pairs(out) do
        for _, loc in ipairs(list) do
            loc.onMap = WorldPosition and WorldPosition(loc) ~= nil or false
        end
        table.sort(list, function(a, b)
            if a.onMap ~= b.onMap then return a.onMap end
            return a.order < b.order
        end)
    end
    return out
end

-- Drop places found by the players (Net.lua) join the static ones. Places with a
-- map point come first: a tome listed as "Unknown location" gets the real place.
function Cat.AttachSightings(row)
    local list = {}
    for _, loc in ipairs(row.staticLocations or {}) do list[#list + 1] = loc end
    local found = ns.Net and ns.Net.Locations(row.itemId)
    if found then
        for _, loc in ipairs(found) do
            loc.onMap = ns.WorldMap.WorldPosition(loc) ~= nil
            list[#list + 1] = loc
        end
    end
    for _, loc in ipairs(list) do
        loc.stale = ns.Evidence and ns.Evidence.LocationStale(row.itemId, loc) or false
    end
    -- on the map first, then the places that still drop the tome
    table.sort(list, function(a, b)
        if (a.onMap and true or false) ~= (b.onMap and true or false) then return a.onMap and true or false end
        if a.stale ~= b.stale then return not a.stale end
        return (a.order or 99999) < (b.order or 99999)
    end)
    row.locations = #list > 0 and list or nil
    row.location = list[1]
end

function Cat.AttachAllSightings()
    for _, row in ipairs(Cat.rows) do Cat.AttachSightings(row) end
end

ns.On("SIGHTINGS_CHANGED", function()
    Cat.AttachAllSightings()
    ns.Fire("CATALOG_CHANGED")
end)

function Cat.BuildFromTomeData(AddRow)
    local locations = LocationsByEchoName()
    for itemId, tome in pairs(ns.TomeData) do
        local echoes = tome.echoes or {}
        local places = locations[Cat.NormalizeName(tome.echo) or ""]
        local row = {
            itemId = itemId,                       -- the REAL item id of the tome
            spellId = echoes[1],
            echoes = echoes,
            name = tome.echo,
            tomeName = tome.name,                  -- "Tome of Echo: <echo>"
            tomeAlias = "Tome of " .. (tome.echo or ""),
            quality = ITEM_QUALITY_NAMES[tome.quality],
            desc = tome.desc,
            staticLocations = places,              -- drop places of EbonholdHub / EbonCompletionist
            locations = places,                    -- + the community ones (AttachSightings)
            location = places and places[1] or nil, -- the main one (first with a map point)
        }
        AddRow(row)
        -- Every echo (all quality variants) resolves to its tome.
        for _, echoId in ipairs(echoes) do Cat.bySpell[echoId] = row end
    end
end

-- Maps a key saved by an older version (echo spell id, or a learned tome name)
-- to the current tome item id. Returns nil when nothing matches.
function Cat.ResolveKey(key)
    if key == nil then return nil end
    if Cat.byItem[key] then return key end
    local row
    if type(key) == "number" then row = Cat.bySpell[key] end
    if not row and type(key) == "string" then row = Cat.FindByTomeName(key) end
    return row and row.itemId or nil
end

-- Re-keys wishlist entries and prices saved under old identities.
-- (Moves are collected first: adding keys to a table while pairs() walks it is
-- undefined behaviour in Lua.)
local function PendingMoves(store)
    local moves = {}
    for key in pairs(store) do
        local target = Cat.ResolveKey(key)
        if target and target ~= key then moves[#moves + 1] = { from = key, to = target } end
    end
    return moves
end

function Cat.MigrateKeys()
    local wish = ns.CDB and ns.CDB.wishlist
    if type(wish) == "table" then
        for _, move in ipairs(PendingMoves(wish)) do
            local entry, existing = wish[move.from], wish[move.to]
            if existing then
                existing.qty = (existing.qty or 0) + (entry.qty or 0)
            else
                wish[move.to] = entry
            end
            wish[move.from] = nil
        end
    end
    local prices = ns.DB and ns.DB.prices
    if type(prices) == "table" then
        for _, move in ipairs(PendingMoves(prices)) do
            local rec, existing = prices[move.from], prices[move.to]
            if not existing or (rec.at or 0) > (existing.at or 0) then prices[move.to] = rec end
            prices[move.from] = nil
        end
    end
end

local rebuildTries, rebuildPending = 0, false
local MAX_REBUILDS = 12   -- ~1 minute of retries

function Cat.ScheduleRebuild()
    if rebuildPending or Cat.builtFromPerks or rebuildTries >= MAX_REBUILDS then return false end
    rebuildPending = true
    rebuildTries = rebuildTries + 1
    ns.Timer.After(5, function()
        rebuildPending = false
        if Cat.builtFromPerks then return end
        Cat.Build()   -- fires CATALOG_CHANGED
    end)
    return true
end

function Cat.Get(itemId)
    return Cat.byItem[itemId]
end

function Cat.FindBySpell(spellId)
    spellId = tonumber(spellId)
    if not spellId then return nil end
    return Cat.bySpell[spellId]
end

function Cat.Title(row)
    if not row then return "" end
    if row.tomeName then return row.tomeName end
    if row.auctionItemId then
        local name = ns.SafeCall(GetItemInfo, row.auctionItemId)
        if name then return name end
    end
    return "Tome of " .. (row.name or "")
end

-- "Tome of Echo: Pandemic" -> "Pandemic", keeping the original capitalisation
-- (for display; EchoKeyFromTome gives the lowercase lookup key).
function Cat.EchoNameFromTome(name)
    if type(name) ~= "string" then return nil end
    local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
    local lower = strlower(trimmed)
    for _, prefix in ipairs({ "tome of echo: ", "tome of echo:", "tome of echo ", "tome of " }) do
        if lower:sub(1, #prefix) == prefix then
            local rest = trimmed:sub(#prefix + 1):gsub("^%s+", "")
            if rest ~= "" then return rest end
        end
    end
    return trimmed
end

-- Is this item name an Echo tome? ("Tome of Echo: X", or the older "Tome of X")
function Cat.IsTomeName(name)
    local key = Cat.NormalizeName(name)
    if not key then return false end
    return key:find("^tome of ") ~= nil
end

-- Remembers a tome seen at the Auction House or in the bags. Returns true the
-- first time that tome is ever seen.
function Cat.LearnTome(name, itemId)
    if not Cat.IsTomeName(name) then return false end
    local key = Cat.NormalizeName(name)
    local store = ns.DB.tomes
    local record = store[key]
    local isNew = false
    if not record then
        record = { name = name, echo = Cat.EchoKeyFromTome(name), firstSeen = time(), seen = 0 }
        store[key] = record
        isNew = true
    end
    record.name = name
    record.seen = (record.seen or 0) + 1
    record.lastSeen = time()
    if itemId then record.itemId = tonumber(itemId) end
    -- Attach it to the matching catalogue row (exact item id first: some item
    -- names differ from the spell names, e.g. "Eonar Seed" / "Eonar's Seed"),
    -- or create one for an unknown tome.
    local row = (record.itemId and Cat.byItem[record.itemId]) or Cat.FindByTomeName(name)
    if row then
        row.tomeName = row.tomeName or name
        if record.itemId then row.auctionItemId = record.itemId end
        record.key = row.itemId
    elseif isNew or not Cat.byTomeName[key] then
        Cat.AddLearnedRow(record)
    end
    return isNew
end

-- Catalogue row for a tome that ProjectEbonhold's database does not know.
-- Its identity is the normalized tome name (a string key, see ns.Key).
function Cat.AddLearnedRow(record)
    local key = Cat.NormalizeName(record.name)
    if not key or Cat.byTomeName[key] then return nil end
    local echoName = Cat.EchoNameFromTome(record.name) or record.name
    local row = {
        itemId = key,                    -- string identity
        name = echoName,
        tomeName = record.name,
        auctionItemId = record.itemId,
        learned = true,                  -- discovered by scanning, not from the perk DB
    }
    record.key = key
    Cat.rows[#Cat.rows + 1] = row
    Cat.byItem[key] = row
    Cat.byName[strlower(echoName)] = Cat.byName[strlower(echoName)] or row
    Cat.byTomeName[key] = row
    local echoKey = Cat.EchoKeyFromTome(echoName)
    if echoKey then Cat.byEchoKey[echoKey] = Cat.byEchoKey[echoKey] or row end
    return row
end

-- Merges everything learned so far into a freshly built catalogue.
function Cat.MergeLearned()
    local learned, added = 0, 0
    for _, record in pairs(ns.DB.tomes or {}) do
        learned = learned + 1
        local row = (record.itemId and Cat.byItem[record.itemId]) or Cat.FindByTomeName(record.name)
        if row then
            row.tomeName = row.tomeName or record.name
            if record.itemId then row.auctionItemId = record.itemId end
            record.key = row.itemId
        elseif Cat.AddLearnedRow(record) then
            added = added + 1
        end
    end
    return learned, added
end

-- Row whose tome matches an auction listing name. Exact spelling first, then
-- the echo name with any "Tome of ..." prefix removed.
function Cat.FindByTomeName(name)
    local key = Cat.NormalizeName(name)
    if not key then return nil end
    local row = Cat.byTomeName[key]
    if row then return row end
    local echoKey = Cat.EchoKeyFromTome(name)
    if echoKey and echoKey ~= key then
        return Cat.byEchoKey[echoKey]
    end
    return nil
end

local QUALITY_COLORS = {
    common = { r = 0.9, g = 0.9, b = 0.9 },
    uncommon = { r = 0.2, g = 0.9, b = 0.2 },
    rare = { r = 0.2, g = 0.6, b = 1.0 },
    epic = { r = 0.6, g = 0.3, b = 1.0 },
    legendary = { r = 1.0, g = 0.6, b = 0.0 },
}

function Cat.QualityColor(row)
    local q = type(row and row.quality) == "string" and strlower(row.quality) or ""
    local c = QUALITY_COLORS[q]
    if not c then
        return 0.7, 0.7, 0.7
    end
    return c.r, c.g, c.b
end

function Cat.Count()
    return #Cat.rows
end