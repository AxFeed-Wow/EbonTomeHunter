local addonName, ns = ...
local L = ns.L

-- Wowhead links (WotLK Classic section) for the mobs that drop a tome.
-- Checked on wowhead.com: /wotlk/npc=21405/ethereal-arcanist and /wotlk/npc=21405 open
-- "Ethereal Arcanist - NPC - WotLK Classic"; /wotlk/search?q=... is the WotLK search.
-- The NPC id is known for mobs the player targeted, moused over or looted (learned
-- from their GUID); otherwise the link searches the name. Mobs only: the tomes are
-- Ebonhold items (ids 300000+), they have no Wowhead page.
ns.Wowhead = {}
local WH = ns.Wowhead

local BASE = "https://www.wowhead.com/wotlk/"

-- 3.3.5a creature GUID: "0xF130" + entry (6 hex) + spawn (6 hex); vehicles use F150.
function WH.NpcIdFromGUID(guid)
    if type(guid) ~= "string" or #guid < 12 then return nil end
    local high = strupper(guid:sub(3, 6))
    if high ~= "F130" and high ~= "F150" then return nil end
    return tonumber(guid:sub(7, 12), 16)
end

function WH.Slug(name)
    local slug = strlower(tostring(name or "")):gsub("'", ""):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return slug
end

function WH.Encode(text)
    return (tostring(text or ""):gsub("[^%w%-_%.~ ]", function(c)
        return format("%%%02X", c:byte())
    end):gsub(" ", "+"))
end

function WH.NpcURL(npcId, name)
    local slug = name and WH.Slug(name) or ""
    return BASE .. "npc=" .. npcId .. (slug ~= "" and ("/" .. slug) or "")
end

function WH.SearchURL(name)
    return BASE .. "search?q=" .. WH.Encode(name)
end

-- Mob texts of the source data are sometimes plural or grouped:
-- "Scarlet Paladins", "Bloodsail Mage/Raider", "Blackrock Stronghold mobs".
function WH.SplitMobs(text)
    local out = {}
    text = tostring(text or ""):gsub("%s+[Mm]obs?$", "")
    local first
    for part in text:gmatch("[^/,]+") do
        part = strtrim(part)
        if part ~= "" then
            if not first then
                first = part
            elseif not part:find(" ") and first:find(" ") then
                part = first:match("^(.*) ") .. " " .. part   -- "Bloodsail Mage/Raider" -> "Bloodsail Raider"
            end
            out[#out + 1] = part
        end
    end
    return out
end

local function Keys(name)
    local key = strlower(strtrim(tostring(name or "")))
    if key == "" then return {} end
    local keys = { key }
    if key:sub(-1) == "s" then keys[2] = key:sub(1, -2) end   -- "scarlet paladins" -> "scarlet paladin"
    return keys
end

local function NpcIds()
    if type(ns.DB.npcIds) ~= "table" then ns.DB.npcIds = {} end
    return ns.DB.npcIds
end

function WH.NpcId(name)
    local ids = NpcIds()
    for _, key in ipairs(Keys(name)) do
        if ids[key] then return ids[key] end
    end
    return nil
end

function WH.Remember(name, npcId)
    npcId = tonumber(npcId)
    if not npcId or not name then return end
    NpcIds()[strlower(strtrim(name))] = npcId
end

------------------------------------------------------------------------
-- Learning the ids of the mobs named in the drop places (only those: the
-- saved table stays small).
------------------------------------------------------------------------
local wanted = {}

local function RebuildWanted()
    wipe(wanted)
    for _, row in ipairs(ns.Catalog.rows) do
        for _, loc in ipairs(ns.WorldMap.Locations(row)) do
            if type(loc.mobs) == "table" then
                for _, mob in ipairs(loc.mobs) do
                    for _, name in ipairs(WH.SplitMobs(mob)) do
                        for _, key in ipairs(Keys(name)) do wanted[key] = true end
                    end
                end
            end
        end
    end
end

local function Learn(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    local key = name and strlower(name)
    if not (key and wanted[key]) then return end
    local npcId = WH.NpcIdFromGUID(UnitGUID(unit))
    if npcId then NpcIds()[key] = npcId end
end

ns.On("CATALOG_CHANGED", RebuildWanted)
ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Learn("mouseover") end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Learn("target") end)

------------------------------------------------------------------------
-- Links of a tome: one per mob of each drop place
------------------------------------------------------------------------
-- WotLK creatures stop around id 40 000: a higher id is a creature made for
-- Ebonhold, absent from Wowhead (like its tomes): no link rather than a dead page.
local CUSTOM_NPC_MIN = 50000

-- Link of a mob: its NPC page when its id is known, otherwise a WotLK search of
-- its name. Returns url (nil for an Ebonhold creature), npcId, custom.
function WH.LinkFor(name, loc)
    local npcId = (type(loc) == "table" and type(loc.npcIds) == "table" and loc.npcIds[name]) or WH.NpcId(name)
    npcId = tonumber(npcId)
    if npcId and npcId >= CUSTOM_NPC_MIN then return nil, npcId, true end
    return npcId and WH.NpcURL(npcId, name) or WH.SearchURL(name), npcId, false
end

function WH.Links(itemId)
    local row = ns.Catalog.Get(itemId)
    local out, seen = {}, {}
    for _, loc in ipairs(ns.WorldMap.Locations(row)) do
        if type(loc.mobs) == "table" then
            for _, mob in ipairs(loc.mobs) do
                for _, name in ipairs(WH.SplitMobs(mob)) do
                    local url, npcId = WH.LinkFor(name, loc)
                    if url and not seen[url] then
                        seen[url] = true
                        out[#out + 1] = { name = name, npcId = npcId, url = url,
                            place = tostring(loc.placeName or L.LocationUnknown) }
                    end
                end
            end
        end
    end
    return out
end

function WH.Open(url)
    if type(EbonholdOpenURL) == "function" and pcall(EbonholdOpenURL, url) then
        return true
    end
    return false
end

-- The links are shown in the Sources window (Sources.lua), with the teleports.
function WH.Show(itemId)
    return ns.Sources.Show(itemId)
end
