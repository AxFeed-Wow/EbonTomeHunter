local addonName, ns = ...
local L = ns.L

ns.WorldMap = {}
local WM = ns.WorldMap

-- Place texts that name a zone the coordinates alone cannot tell apart (overlapping
-- zone maps). Only used as a tie-breaker: the map point itself always wins.
local ZONE_ALIASES = {
    { "hearthglen", "Western Plaguelands" },
    { "booty bay", "Stranglethorn Vale" },
    { "outside bb", "Stranglethorn Vale" },
    { "blackrock stronghold", "Burning Steppes" },
    { "blackrock mountain", "Burning Steppes" },
    { "grinding quarry", "Burning Steppes" },
    { "dreadmaul", "Burning Steppes" },
    { "scarlet encampments", "Western Plaguelands" },
    { "scarlet monastery", "Tirisfal Glades" },
    { "redridge mountain", "Redridge Mountains" },
    { "redrige", "Redridge Mountains" },
    { "render's rock", "Redridge Mountains" },
    { "mosh'ogg", "Stranglethorn Vale" },
    { "tyr's hand", "Eastern Plaguelands" },
    { "pestilent scar", "Eastern Plaguelands" },
    { "stratholme", "Eastern Plaguelands" },
    { "pyrewood village", "Silverpine Forest" },
    { "alterac mountains", "Alterac Mountains" },
    { "southwind village", "Silithus" },
    { "onyxia", "Dustwallow Marsh" },
    { "hellfire citadel", "Hellfire Peninsula" },
    { "throne of kil", "Hellfire Peninsula" },
    { "shattered halls", "Hellfire Peninsula" },
    { "black temple", "Shadowmoon Valley" },
    { "forge camp", "Blade's Edge Mountains" },
    { "bash'ir", "Blade's Edge Mountains" },
    { "tomb of lights", "Terokkar Forest" },
    { "caverns of time", "Tanaris" },
    { "naxxramas", "Dragonblight" },
    { "obsidian sanctum", "Dragonblight" },
    { "ulduar", "The Storm Peaks" },
    { "coldarra", "Borean Tundra" },
    { "eye of eternity", "Borean Tundra" },
    { "malykriss", "Icecrown" },
    { "trial of the crusader", "Icecrown" },
    { "bonechewer ruins", "Terokkar Forest" },
    { "nagrand", "Nagrand" },
    { "shattrath", "Shattrath City" },
    { "drak sotra", "Zul'Drak" },
    { "goldshire", "Elwynn Forest" },
    { "wintergrasp", "Wintergrasp" },
    { "forlorn woods", "Crystalsong Forest" },
    { "render", "Redridge Mountains" },
}

local SLUG_CONTINENT = {
    ["eastern-kingdoms"] = "Eastern Kingdoms",
    ["kalimdor"] = "Kalimdor",
    ["outland"] = "Outland",
    ["northrend"] = "Northrend",
}

-- Place texts of the source data that mean "no precise spot" (their coordinates are
-- placeholders, e.g. every "Unknown location" of Kalimdor sits at the top of the map).
local UNLOCATABLE = {
    "anywhere",
    "everywhere",
    "pretty much",
    "unknown",
    "to be placed",
    "bottom right corner",
}

local function TitleCase(s)
    return (s:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

local function NormalizePlace(place)
    if type(place) ~= "string" then return "" end
    local p = strlower(place)
    p = p:gsub("''", "'")
    return p
end

local function IsUnlocatable(place)
    local p = NormalizePlace(place)
    if p == "" then return true end
    for _, token in ipairs(UNLOCATABLE) do
        if p:find(token, 1, true) then
            return true
        end
    end
    return false
end
WM.IsUnlocatable = IsUnlocatable

local zoneMemo = {}

-- 3.3.5a: GetMapContinents() and GetMapZones(ci) return the names as MULTIPLE
-- return values, not a table. Pack them before using # or [i].
local function PackCall(fn, ...)
    if type(fn) ~= "function" then return {} end
    local packed = { pcall(fn, ...) }
    if not packed[1] then return {} end
    tremove(packed, 1)   -- drop the pcall status
    return packed
end

function WM.Continents()
    return PackCall(GetMapContinents)
end

function WM.Zones(continentIndex)
    return PackCall(GetMapZones, continentIndex)
end

function WM.AllZoneNames()
    local out = {}
    local continents = WM.Continents()
    for ci = 1, #continents do
        local zones = WM.Zones(ci)
        for zi = 1, #zones do
            out[#out + 1] = { cont = ci, zone = zi, name = zones[zi], contName = continents[ci] }
        end
    end
    return out, continents
end

-- Zone named by a place text ("Tyr's Hand - Eastern Plaguelands" -> "Eastern Plaguelands").
function WM.FindZoneForPlace(place, preferContName)
    local memoKey = (preferContName or "") .. "|" .. NormalizePlace(place)
    if zoneMemo[memoKey] ~= nil then
        local v = zoneMemo[memoKey]
        if v == false then return nil end
        return v
    end
    if IsUnlocatable(place) then
        zoneMemo[memoKey] = false
        return nil
    end

    local p = NormalizePlace(place)
    local bestAlias = nil
    for _, entry in ipairs(ZONE_ALIASES) do
        if p:find(entry[1], 1, true) then
            if not bestAlias or #entry[1] > #bestAlias[1] then
                bestAlias = entry
            end
        end
    end
    if bestAlias then
        zoneMemo[memoKey] = bestAlias[2]
        return bestAlias[2]
    end

    local allZones = WM.AllZoneNames()
    local bestName = nil
    local bestScore = 0
    for _, z in ipairs(allZones) do
        local zn = strlower(z.name or "")
        local score = 0
        if zn == "" then
            score = 0
        elseif zn == p then
            score = 3 + #zn
        elseif p:find(zn, 1, true) then
            score = 2 + #zn
        elseif zn:find(p, 1, true) then
            score = 1 + #p
        end
        if score > 0 then
            if preferContName and z.contName == preferContName then
                score = score + 100
            end
            if score > bestScore then
                bestScore = score
                bestName = z.name
            end
        end
    end

    zoneMemo[memoKey] = bestName or false
    return bestName
end

function WM.SlugToContinentName(slug)
    if type(slug) ~= "string" then return nil end
    if SLUG_CONTINENT[slug] then
        return SLUG_CONTINENT[slug]
    end
    return TitleCase(slug:gsub("%-", " "))
end

------------------------------------------------------------------------
-- Geometry
-- Farm locations are percentages of EbonholdHub's OWN map images, not of the
-- game's maps. MapData.lua gives the world bounds (yards) of those images and of
-- every in-game zone/continent map, so a location can be drawn on any of them.
------------------------------------------------------------------------
local EDGE_MARGIN = 0.06   -- a point slightly outside a zone map still picks that zone

local function MapData()
    return ns.MapData or {}
end

function WM.MapInfo(file)
    local maps = MapData().maps
    return file and maps and maps[file] or nil
end

-- Instance map id + world coordinates of a farm location, or nil when it has no
-- usable spot ("Anywhere", "Unknown location", no coordinates, unknown map image).
function WM.WorldPosition(loc)
    if type(loc) ~= "table" then return nil end
    local x, y = tonumber(loc.x), tonumber(loc.y)
    if loc.mapFile then
        -- place found by a player (Net.lua): 0..1 position on a zone map
        local info = WM.MapInfo(loc.mapFile)
        if not (info and x and y) then return nil end
        return info.map, info.top - y * (info.top - info.bottom), info.left - x * (info.left - info.right)
    end
    if IsUnlocatable(loc.placeName) then return nil end
    local image = MapData().hub and MapData().hub[loc.zone]
    if not (x and y and image) then return nil end
    local worldY = image.left - x / 100 * (image.left - image.right)
    local worldX = image.top - y / 100 * (image.top - image.bottom)
    return image.map, worldX, worldY
end

-- Position (0..1 from the top-left corner) of a world point on a MapData map.
function WM.MapPosition(info, map, worldX, worldY)
    if not info or not map or info.map ~= map then return nil end
    return (info.left - worldY) / (info.left - info.right), (info.top - worldX) / (info.top - info.bottom)
end

local function Inside(x, y, margin)
    margin = margin or 0
    return x ~= nil and y ~= nil and x >= -margin and x <= 1 + margin and y >= -margin and y <= 1 + margin
end

local function Clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- The zone map that best shows a location: the zone its text names when the point
-- lies on that map, otherwise the zone map most centred on the point (no cities).
-- Returns the map file name, its MapData entry and the position on that map.
function WM.BestZone(loc)
    local map, worldX, worldY = WM.WorldPosition(loc)
    if not map then return nil end
    local own = loc.mapFile and WM.MapInfo(loc.mapFile)
    if own and not own.continent then
        return loc.mapFile, own, Clamp01(tonumber(loc.x)), Clamp01(tonumber(loc.y))   -- its own zone map
    end
    local hint = WM.FindZoneForPlace(loc.placeName)
    hint = hint and strlower(hint)
    local bestFile, bestScore, bestX, bestY
    for file, info in pairs(MapData().maps or {}) do
        if info.map == map and not info.continent and not info.city then
            local x, y = WM.MapPosition(info, map, worldX, worldY)
            if Inside(x, y, EDGE_MARGIN) then
                local score = math.min(x, 1 - x, y, 1 - y)
                if hint and info.name and strlower(info.name) == hint then
                    score = score + 10
                end
                if not bestScore or score > bestScore or (score == bestScore and file < bestFile) then
                    bestFile, bestScore, bestX, bestY = file, score, x, y
                end
            end
        end
    end
    if not bestFile then return nil end
    return bestFile, MapData().maps[bestFile], Clamp01(bestX), Clamp01(bestY)
end

-- The continent map (MapData file name) a location belongs to.
function WM.ContinentFile(loc)
    local image = type(loc) == "table" and MapData().hub and MapData().hub[loc.zone]
    return image and image.continent or nil
end

-- "Crystalsong Forest 49, 54" (or nil when the location has no map point).
function WM.Describe(loc)
    local file, info, x, y = WM.BestZone(loc)
    if not file then return nil end
    return format("%s %d, %d", info.name or file, floor(x * 100 + 0.5), floor(y * 100 + 0.5))
end

function WM.MobsText(loc)
    if type(loc) ~= "table" or type(loc.mobs) ~= "table" or #loc.mobs == 0 then return nil end
    local parts = {}
    for _, mob in ipairs(loc.mobs) do parts[#parts + 1] = tostring(mob) end
    return table.concat(parts, ", ")
end

function WM.Locations(row)
    if type(row) ~= "table" then return {} end
    if type(row.locations) == "table" then return row.locations end
    if row.location then return { row.location } end
    return {}
end

------------------------------------------------------------------------
-- Pins on the world map
------------------------------------------------------------------------
local PIN_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local ICON_STAR = { 0, 0.25, 0, 0.25 }        -- the tome being located
local ICON_CIRCLE = { 0.25, 0.5, 0, 0.25 }    -- wishlist tomes

WM.focus = nil   -- { itemId, index } : the tome (and which of its places) being located

local pinPool = {}
local activeCount = 0
local pinsBuiltFor = nil

local function HidePins()
    for _, pin in ipairs(pinPool) do
        pin:Hide()
    end
    activeCount = 0
end

local function PinTooltip(self)
    local d = self._etp
    if not d then return end
    local tt = WorldMapTooltip or GameTooltip
    tt:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = ns.Catalog.QualityColor(d.row)
    tt:AddLine(ns.Catalog.Title(d.row), r, g, b)
    tt:AddLine(tostring(d.loc.placeName or L.LocationUnknown), 1, 0.82, 0, true)
    local mobs = WM.MobsText(d.loc)
    if mobs then
        tt:AddLine(L.MobsLabel .. ": " .. mobs, 0.9, 0.9, 0.9, true)
    end
    if type(d.loc.notes) == "string" and d.loc.notes ~= "" then
        tt:AddLine(d.loc.notes, 0.6, 0.6, 0.6, true)
    end
    local where = WM.Describe(d.loc)
    if where then
        tt:AddLine(where, 0.6, 0.6, 0.6)
    end
    local min = ns.Prices.GetMin(d.itemId)
    if min then
        tt:AddLine(L.Buyout .. ": |cffffffff" .. ns.FormatMoney(min), 0.4, 1.0, 0.4)
    end
    tt:AddLine(L.ClickHint, 0.5, 0.5, 0.5)
    tt:AddLine(L.ShiftClickSources, 0.5, 0.5, 0.5)
    if ns.Travel.Available() then tt:AddLine(L.CtrlClickTravel, 0.5, 0.5, 0.5) end
    tt:Show()
end

local function PinPulse(self, elapsed)
    self.pulse = (self.pulse or 0) + elapsed
    local a = 0.35 + 0.35 * math.sin(self.pulse * 5)
    self.glow:SetAlpha(a > 0 and a or 0)
end

local function AcquirePin(index)
    local pin = pinPool[index]
    if pin then
        return pin
    end
    pin = CreateFrame("Button", "EbonTomeHunterPin" .. index, WorldMapButton)
    pin:SetSize(16, 16)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow:Hide()
    pin.tex = pin:CreateTexture(nil, "OVERLAY")
    pin.tex:SetAllPoints()
    pin.tex:SetTexture(PIN_TEXTURE)
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pin.label:SetPoint("TOP", pin, "BOTTOM", 0, -1)
    pin.label:Hide()
    pin:SetScript("OnEnter", PinTooltip)
    pin:SetScript("OnLeave", function()
        local tt = WorldMapTooltip or GameTooltip
        tt:Hide()
    end)
    pin:SetScript("OnClick", function(self)
        local d = self._etp
        if not (d and ns.UI and ns.UI.Show) then return end
        -- The world map covers the whole screen: close it to show the tome in the list
        -- (its sources with Shift; Ctrl: teleport to the checkpoint nearest this place).
        if WorldMapFrame and WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) end
        if IsControlKeyDown() then
            ns.Travel.GoLocation(d.itemId, d.loc)
        elseif IsShiftKeyDown() then
            ns.Sources.Show(d.itemId)
        else
            ns.UI.Show(d.itemId)
        end
    end)
    pinPool[index] = pin
    return pin
end

local function SetupPin(pin, entry, loc, x, y, current)
    local size = current and 26 or (entry.focus and 20 or 16)
    pin:SetSize(size, size)
    pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + (entry.focus and 8 or 5))
    pin.tex:SetTexCoord(unpack(entry.focus and ICON_STAR or ICON_CIRCLE))
    if current then
        pin.glow:SetSize(size * 2.4, size * 2.4)
        pin.glow:Show()
        pin.label:SetText(entry.row.name or "")
        pin.label:Show()
        pin:SetScript("OnUpdate", PinPulse)
    else
        pin.glow:Hide()
        pin.label:Hide()
        pin:SetScript("OnUpdate", nil)
    end
    pin._etp = { itemId = entry.itemId, row = entry.row, loc = loc, x = x, y = y, focus = entry.focus, current = current }
end

-- The located tome first, then the wishlist (option): one entry per tome.
local function PinEntries()
    local out, seen = {}, {}
    if WM.focus then
        local row = ns.Catalog.Get(WM.focus.itemId)
        if row then
            out[#out + 1] = { itemId = WM.focus.itemId, row = row, focus = true }
            seen[WM.focus.itemId] = true
        end
    end
    if not ns.Opt().mapPins then return out end
    for _, item in ipairs(ns.Wishlist.List()) do
        if item.row and not seen[item.itemId] then
            seen[item.itemId] = true
            out[#out + 1] = { itemId = item.itemId, row = item.row }
        end
    end
    return out
end

function WM.BuildPins()
    if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapButton) then
        HidePins()
        return
    end
    local file = GetMapInfo and GetMapInfo() or nil
    local level = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
    local mapKey = tostring(file) .. ":" .. tostring(level)
    if pinsBuiltFor == mapKey then
        return
    end
    HidePins()
    pinsBuiltFor = mapKey

    local info = WM.MapInfo(file)
    if not info or (level or 0) > 0 then
        return
    end
    local width, height = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
    local placed = 0
    for _, entry in ipairs(PinEntries()) do
        for index, loc in ipairs(WM.Locations(entry.row)) do
            local current = entry.focus and WM.focus.index == index or false
            local map, worldX, worldY = WM.WorldPosition(loc)
            local x, y = WM.MapPosition(info, map, worldX, worldY)
            -- The place being located may sit just past the edge of its zone map (source
            -- data): keep it, against the edge, like Locate's choice of zone does.
            if Inside(x, y, (current and not info.continent) and EDGE_MARGIN or 0) then
                x, y = Clamp01(x), Clamp01(y)
                placed = placed + 1
                local pin = AcquirePin(placed)
                SetupPin(pin, entry, loc, x, y, current)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT", x * width, -y * height)
                pin:Show()
            end
        end
    end
    activeCount = placed
end

function WM.ActivePinCount()
    return activeCount
end

function WM.OnWorldMapUpdate()
    pinsBuiltFor = nil
    WM.BuildPins()
end

-- 3.3.5a has no WORLD_MAP_CLOSED event: the frame itself tells us when it closes.
if WorldMapFrame then
    WorldMapFrame:HookScript("OnHide", function()
        if WM.OnWorldMapClosed then WM.OnWorldMapClosed() end
    end)
end

function WM.OnWorldMapClosed()
    HidePins()
    pinsBuiltFor = nil
end

function WM.Invalidate()
    pinsBuiltFor = nil
    if WorldMapFrame and WorldMapFrame:IsShown() then
        WM.BuildPins()
    end
end

ns.RegisterEvent("WORLD_MAP_UPDATE", WM.OnWorldMapUpdate)
ns.On("WISHLIST_CHANGED", WM.Invalidate)
ns.On("CATALOG_CHANGED", WM.Invalidate)
ns.On("SETTINGS_CHANGED", function(key)
    if key == "mapPins" then WM.Invalidate() end
end)

------------------------------------------------------------------------
-- Locate a tome: open the world map on the zone of its drop place
------------------------------------------------------------------------
local function CurrentMapFile()
    return GetMapInfo and GetMapInfo() or nil
end

-- Shows a map of MapData by its file name. SetMapByID(WorldMapArea id) exists on
-- 3.3.5a; if it is missing or lands elsewhere, walk the continents and zones with
-- SetMapZoom until GetMapInfo() names the wanted map.
function WM.ShowMap(file)
    local info = WM.MapInfo(file)
    if not info then return false end
    if SetMapByID then
        pcall(SetMapByID, info.id)
        if CurrentMapFile() == file then return true end
    end
    if not SetMapZoom then return false end
    -- Eversong, Azuremyst...: on map 530, drawn on the Eastern Kingdoms / Kalimdor map
    local continentMap = info.shownOn or info.map
    local continentFile
    for f, other in pairs(MapData().maps or {}) do
        if other.continent and other.map == continentMap then continentFile = f end
    end
    for ci = 1, #WM.Continents() do
        pcall(SetMapZoom, ci)
        if CurrentMapFile() == continentFile then
            if file == continentFile then return true end
            for zi = 1, #WM.Zones(ci) do
                pcall(SetMapZoom, ci, zi)
                if CurrentMapFile() == file then return true end
            end
            pcall(SetMapZoom, ci)   -- zone not reachable: stay on its continent
            return false
        end
    end
    return false
end

-- Opens the world map on the drop place of a tome and marks it. Clicking "Locate"
-- again on the same tome moves to its next place.
function WM.Locate(itemId)
    local row = ns.Catalog.Get(itemId)
    if not row then return end
    if not ns.MapData then
        ns.Print(L.NeedRestart)   -- new file in the .toc: only a client restart loads it
        return
    end
    local title = row.name or ns.Catalog.Title(row)
    local locations = WM.Locations(row)
    if #locations == 0 then
        if ns.Catalog.GetEchoLocations() == nil then
            ns.Print(L.NeedHub)
        else
            ns.Print(L.NoLocation, title)
        end
        return
    end

    local points = {}
    for index, loc in ipairs(locations) do
        if WM.WorldPosition(loc) then points[#points + 1] = index end
    end
    if #points == 0 then
        local places = {}
        for _, loc in ipairs(locations) do places[#places + 1] = tostring(loc.placeName or L.LocationUnknown) end
        ns.Print(L.LocateNoPoint, title, table.concat(places, " / "))
        return
    end

    local step = 1
    if WM.focus and WM.focus.itemId == itemId and WM.focus.step then
        step = WM.focus.step % #points + 1
    end
    local index = points[step]
    local loc = locations[index]
    WM.focus = { itemId = itemId, index = index, step = step }

    local file, info, x, y = WM.BestZone(loc)
    if file then
        ns.Print(L.LocateInfo, title, info.name or file, floor(x * 100 + 0.5), floor(y * 100 + 0.5),
            tostring(loc.placeName or ""))
    end
    local mobs = WM.MobsText(loc)
    if mobs then
        ns.Print("%s: %s", L.MobsLabel, mobs)
    end
    if #points > 1 then
        ns.Print(L.MorePlaces, step, #points)
    end

    if not (WorldMapFrame and WorldMapButton) then
        ns.Print(L.NoMapApi)
        return
    end
    if not WorldMapFrame:IsShown() then
        ShowUIPanel(WorldMapFrame)
    end
    if not (file and WM.ShowMap(file)) then
        WM.ShowMap(WM.ContinentFile(loc))
    end
    pinsBuiltFor = nil
    WM.BuildPins()
end
