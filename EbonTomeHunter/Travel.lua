local addonName, ns = ...
local L = ns.L

-- Teleport near a tome's drop place: ProjectEbonhold's checkpoints (flight masters
-- and meeting stones the character has unlocked), the nearest one to the mob's spot
-- on the same continent, straight-line distance in yards. A tome dropped by several
-- mobs (or at several places): the source with the nearest checkpoint wins.
-- PE checkpoint: { id, name, kind, mapId = GetCurrentMapAreaID() (WorldMapArea id + 1),
-- serverMapId, x, y (0..1 on that zone map), factionAllowed, unlocked }. "unlocked"
-- stays false until the server has sent the list (code 800, asked at login).
ns.Travel = {}
local T = ns.Travel

local REQUEST_GAP = 3      -- seconds between two teleport requests (double clicks)
local REFRESH_GAP = 30     -- seconds between two requests of the checkpoint list

local lastRequest, lastRefresh = -REQUEST_GAP, -REFRESH_GAP
local byArea               -- [GetCurrentMapAreaID()] = MapData entry

local function AreaInfo(areaId)
    if not byArea then
        byArea = {}
        for _, info in pairs(ns.MapData and ns.MapData.maps or {}) do
            if info.id then byArea[info.id + 1] = info end
        end
    end
    return byArea[tonumber(areaId)]
end

function T.Available()
    local svc = ns.PE.Service("CheckpointService")
    return svc ~= nil and type(svc.GetCheckpoints) == "function" and type(svc.UseCheckpoint) == "function"
end

-- The checkpoints of the character's faction, as world points (read only: the list
-- belongs to ProjectEbonhold).
function T.Checkpoints()
    local out, seen = {}, {}
    local list = T.Available() and ns.PE.Call("CheckpointService", "GetCheckpoints")
    if type(list) ~= "table" then return out end
    for _, c in ipairs(list) do
        local id = type(c) == "table" and tonumber(c.id) or nil
        local info = id and AreaInfo(c.mapId)
        local x, y = id and tonumber(c.x), id and tonumber(c.y)
        -- a meeting stone is listed once per zone map around it: the same point
        if info and x and y and not seen[id] and c.factionAllowed ~= false and info.map == tonumber(c.serverMapId) then
            seen[id] = true
            out[#out + 1] = {
                id = id, name = tostring(c.name or ("#" .. id)), kind = c.kind, unlocked = c.unlocked == true,
                map = info.map,
                worldX = info.top - y * (info.top - info.bottom),
                worldY = info.left - x * (info.left - info.right),
            }
        end
    end
    return out
end

function T.UnlockedCount()
    local n = 0
    for _, c in ipairs(T.Checkpoints()) do
        if c.unlocked then n = n + 1 end
    end
    return n
end

-- Asks ProjectEbonhold for the list again (nothing unlocked: not received yet?).
function T.Refresh()
    if GetTime() - lastRefresh < REFRESH_GAP then return false end
    lastRefresh = GetTime()
    ns.PE.Call("CheckpointService", "RequestCheckpoints")
    return true
end

local function Distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function T.FormatDistance(yards)
    return format(L.TravelYards, floor((yards or 0) + 0.5))
end

-- Nearest checkpoints of a drop place: the nearest unlocked one, and a nearer one
-- that is still locked (worth unlocking). nil when the place has no position.
function T.Nearest(loc, checkpoints)
    local map, worldX, worldY = ns.WorldMap.WorldPosition(loc)
    if not map then return nil end
    local near = { map = map, worldX = worldX, worldY = worldY }
    for _, c in ipairs(checkpoints or T.Checkpoints()) do
        if c.map == map then
            local d = Distance(c.worldX, c.worldY, worldX, worldY)
            if c.unlocked then
                if not near.distance or d < near.distance then near.checkpoint, near.distance = c, d end
            elseif not near.lockedDistance or d < near.lockedDistance then
                near.locked, near.lockedDistance = c, d
            end
        end
    end
    if near.locked and near.distance and near.lockedDistance >= near.distance then
        near.locked, near.lockedDistance = nil, nil
    end
    return near
end

-- Every source of a tome: one per mob of each drop place (a place without mob: one),
-- with its nearest checkpoint. Order: reachable by teleport (nearest first), then
-- with a position but nothing unlocked on that continent, then without position.
function T.Sources(itemId)
    local row = ns.Catalog.Get(itemId)
    local checkpoints = T.Checkpoints()
    local out = {}
    for index, loc in ipairs(ns.WorldMap.Locations(row)) do
        local near = T.Nearest(loc, checkpoints)
        local names = {}
        if type(loc.mobs) == "table" then
            for _, text in ipairs(loc.mobs) do
                for _, name in ipairs(ns.Wowhead.SplitMobs(text)) do names[#names + 1] = name end
            end
        end
        if #names == 0 then names[1] = false end
        for _, name in ipairs(names) do
            out[#out + 1] = {
                itemId = itemId, loc = loc, index = index, mob = name or nil, near = near,
                place = tostring(loc.placeName or L.LocationUnknown), order = #out,
            }
        end
    end
    local function Rank(s)
        if s.near and s.near.checkpoint then return 1 end
        return s.near and 2 or 3
    end
    table.sort(out, function(a, b)
        local ra, rb = Rank(a), Rank(b)
        if ra ~= rb then return ra < rb end
        if ra == 1 and a.near.distance ~= b.near.distance then return a.near.distance < b.near.distance end
        return a.order < b.order
    end)
    return out
end

-- The source reached fastest by teleport (nil when none), and all the sources.
function T.Best(itemId)
    local sources = T.Sources(itemId)
    local best = sources[1]
    if best and best.near and best.near.checkpoint then return best, sources end
    return nil, sources
end

-- The player's world position. Not while the world map is open: SetMapToCurrentZone
-- would change the map being looked at.
function T.PlayerPosition()
    if WorldMapFrame and WorldMapFrame:IsShown() then return nil end
    local place = ns.Loot.CapturePlace()
    if not (place.mapFile and place.x) then return nil end
    return ns.WorldMap.WorldPosition({ mapFile = place.mapFile, x = place.x, y = place.y })
end

-- Distance from the player to a source (nil: other continent, unknown position).
function T.PlayerDistance(source, map, worldX, worldY)
    local near = source and source.near
    if not (near and map and map == near.map) then return nil end
    return Distance(worldX, worldY, near.worldX, near.worldY)
end

-- "Plaguehound Runt (Eastern Plaguelands)"
function T.SourceName(source)
    if source.mob then return source.mob .. " (" .. source.place .. ")" end
    return source.place
end

------------------------------------------------------------------------
-- Teleporting
------------------------------------------------------------------------
function T.Execute(source)
    local checkpoint = source and source.near and source.near.checkpoint
    if not checkpoint then return false end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        ns.Print(L.TravelCombat)
        return false
    end
    if GetTime() - lastRequest < REQUEST_GAP then
        ns.Print(L.TravelWait)
        return false
    end
    lastRequest = GetTime()
    -- like PE's own map pins; dismounting in flight would be a fall
    if IsMounted() and not IsFlying() then Dismount() end
    ns.PE.Call("CheckpointService", "UseCheckpoint", checkpoint.id)
    ns.Print(L.TravelGoing, checkpoint.name, T.FormatDistance(source.near.distance), T.SourceName(source))
    return true
end

-- Teleports near a source (confirmation if the option is on). Says why when it cannot.
function T.GoTo(source)
    local row = source and ns.Catalog.Get(source.itemId)
    local tome = row and row.name or "?"
    if not T.Available() then
        ns.Print(L.TravelNoPE)
        return false
    end
    if not (source and source.near) then
        ns.Print(L.TravelNoPlace, tome)
        return false
    end
    local near = source.near
    if not near.checkpoint then
        if T.UnlockedCount() == 0 then
            T.Refresh()
            ns.Print(L.TravelNoData)
        elseif near.locked then
            ns.Print(L.TravelLockedOnly, tome, near.locked.name, T.FormatDistance(near.lockedDistance))
        else
            ns.Print(L.TravelNoCheckpoint, tome)
        end
        return false
    end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        ns.Print(L.TravelCombat)
        return false
    end
    if ns.Opt().confirmTeleport then
        StaticPopup_Show("EBONTOMEHUNTER_TRAVEL", near.checkpoint.name,
            format(L.TravelNear, T.FormatDistance(near.distance), T.SourceName(source)), source)
        return true
    end
    return T.Execute(source)
end

-- Row button and /eth tp: the source with the nearest checkpoint. When the player
-- already stands closer to one of the sources than any checkpoint, no teleport
-- (it would take them further): the Sources window still forces one.
function T.GoBest(itemId)
    local best, sources = T.Best(itemId)
    local row = ns.Catalog.Get(itemId)
    if not best then
        if #sources == 0 then
            ns.Print(L.TravelNoPlace, row and row.name or "?")
            return false
        end
        return T.GoTo(sources[1])
    end
    local map, worldX, worldY = T.PlayerPosition()
    if map then
        for _, source in ipairs(sources) do
            local mine = T.PlayerDistance(source, map, worldX, worldY)
            if mine and mine < best.near.distance then
                ns.Print(L.TravelAlreadyClose, T.FormatDistance(mine), T.SourceName(source),
                    T.FormatDistance(best.near.distance))
                return false
            end
        end
    end
    return T.GoTo(best)
end

-- Ctrl-click on a map marker: that place precisely.
function T.GoLocation(itemId, loc)
    local mobs = type(loc) == "table" and type(loc.mobs) == "table" and loc.mobs[1]
    local mob = mobs and ns.Wowhead.SplitMobs(mobs)[1] or nil
    return T.GoTo({
        itemId = itemId, loc = loc, mob = mob, near = T.Nearest(loc),
        place = tostring(type(loc) == "table" and loc.placeName or L.LocationUnknown),
    })
end

-- /eth tp <tome>: exact name first, then the only name containing the text.
function T.FindTome(text)
    local wanted = strlower(strtrim(tostring(text or "")))
    if wanted == "" then return nil end
    local matches = {}
    for _, row in ipairs(ns.Catalog.rows) do
        local name = strlower(tostring(row.name or ""))
        if name == wanted or strlower(tostring(row.tomeName or "")) == wanted then return row end
        if name:find(wanted, 1, true) then matches[#matches + 1] = row end
    end
    if #matches == 1 then return matches[1] end
    return nil, matches
end

function T.Command(text)
    if strtrim(tostring(text or "")) == "" then
        ns.Print(L.TravelUsage)
        return false
    end
    local row, matches = T.FindTome(text)
    if row then return T.GoBest(row.itemId) end
    if matches and #matches > 1 then
        local names = {}
        for i = 1, math.min(#matches, 6) do names[i] = matches[i].name end
        ns.Print(L.TravelAmbiguous, text, table.concat(names, ", ") .. (#matches > 6 and ", ..." or ""))
    else
        ns.Print(L.TravelUnknownTome, text)
    end
    return false
end

StaticPopupDialogs["EBONTOMEHUNTER_TRAVEL"] = {
    text = L.TravelConfirm,
    button1 = L.TravelGo,
    button2 = CANCEL,
    OnAccept = function(self, data)
        T.Execute(data or self.data)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
