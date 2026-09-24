local addonName, ns = ...
local L = ns.L

ns.version = "2.1.0"
-- Public namespace: lets macros, other addons and the offline tests reach the API.
EbonTomeHunter = ns

------------------------------------------------------------------------
-- Saved data
-- WoW loads the SavedVariables AFTER this file has run, just before
-- ADDON_LOADED: tables created here are replaced by the saved ones. The
-- defaults are therefore applied again on ADDON_LOADED (older versions did it
-- only here, and the learned tomes were never saved).
------------------------------------------------------------------------
local DB_DEFAULTS = {
    meta = { version = "" },
    prices = {},    -- [itemId] = { min, listings, at, seen, prevMin, hist }
    lastScan = 0,
    tomes = {},     -- tomes learned from Auction House scans and from the bags
    sightings = {}, -- [itemId] = drop places found by the players (Net.lua)
    npcIds = {},    -- [mob name] = NPC id, for the Wowhead links (Wowhead.lua)
    lastSync = 0,
    syncedAt = 0,   -- start (our clock) of the last sync that went to the end (Net.lua)
    netOutbox = {}, -- own finds made while no other user was online, sent when one shows up
    tutorialDone = 0,   -- version of the guided tour already seen (Tutorial.lua)
    options = {
        minimap = { hide = false, angle = 200 },
        mapPins = true,             -- wishlist tomes on the world map
        ahTabs = true,              -- "Tomes" / "Wishlist" tabs on the Auction House
        ahOpenTab = false,          -- open the Auction House directly on the Tomes tab
        ahOnlyListed = true,        -- AH "Tomes" tab: only the tomes on sale
        confirmBuy = true,          -- confirmation popup before every purchase
        buyUpdatesWishlist = true,  -- a bought tome is deducted from the wishlist
        autoScan = false,           -- full scan when the AH opens, if the last one is old
        scale = 1,
        window = { point = "CENTER", x = 0, y = 0 },
        sortKey = "name",
        sortDesc = false,
        onlyPriced = false,
        onlyLocated = false,
        onlyUnknown = false,        -- main list: only the tomes this character has not learned
        netEnabled = true,          -- share tome drops with the other users (hidden channel)
        alertSelf = true,           -- alert when I loot a wishlist tome
        alertGroup = true,          -- tell me when my group loots a wishlist tome
        alertNetwork = true,        -- chat line when a user finds a wishlist tome
        alertSound = true,
        receiveWishlists = true,    -- accept wishlists sent by other players
        confirmTeleport = false,    -- teleport buttons: popup before teleporting (player's choice: direct)
    },
}
local CHAR_DEFAULTS = {
    wishlist = {},  -- [itemId] = { qty }
}

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function ns.InitDatabase()
    if type(EbonTomeHunterDB) ~= "table" then EbonTomeHunterDB = {} end
    if type(EbonTomeHunterCharDB) ~= "table" then EbonTomeHunterCharDB = {} end
    ApplyDefaults(EbonTomeHunterDB, DB_DEFAULTS)
    ApplyDefaults(EbonTomeHunterCharDB, CHAR_DEFAULTS)
    EbonTomeHunterCharDB.autoImported = nil   -- flag of the locked-echoes import (removed in 1.5.1)
    EbonTomeHunterDB.meta.version = ns.version
    ns.DB = EbonTomeHunterDB
    ns.CDB = EbonTomeHunterCharDB
end
ns.InitDatabase()   -- usable right away; applied again to the saved tables on ADDON_LOADED

-- Options are always read through here (never cached: the table changes on load).
function ns.Opt()
    return ns.DB.options
end

function ns.SetOption(key, value)
    ns.DB.options[key] = value
    ns.Fire("SETTINGS_CHANGED", key, value)
end

------------------------------------------------------------------------
-- Messages between modules: CATALOG_CHANGED, WISHLIST_CHANGED, PRICES_CHANGED,
-- SCAN_STATE, SEARCH_RESULTS, PURCHASE, SETTINGS_CHANGED, DATABASE_READY...
------------------------------------------------------------------------
local listeners = {}

local function Dispatch(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
end

function ns.On(message, fn)
    local list = listeners[message]
    if not list then
        list = {}
        listeners[message] = list
    end
    list[#list + 1] = fn
end

function ns.Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        Dispatch(list[i], ...)
    end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
-- Identity of a tome: its item id when known, otherwise its normalized name.
-- Numbers stay numbers so wishlists saved by older versions still work.
function ns.Key(value)
    if value == nil then return nil end
    local n = tonumber(value)
    if n then return n end
    return tostring(value)
end

-- ns.Print(text) or ns.Print(formatString, ...): a lone text is never passed to format
-- (a "%" in a zone or mob name received from another player would raise an error).
function ns.Print(text, ...)
    if not DEFAULT_CHAT_FRAME then return end
    if select("#", ...) > 0 then text = format(text, ...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cffd7b26cEbonTomeHunter|r " .. tostring(text))
end

function ns.FormatMoney(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return "0c" end
    local g = floor(copper / 10000)
    local s = floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return format("%dg %ds %dc", g, s, c)
    elseif s > 0 then
        return format("%ds %dc", s, c)
    end
    return format("%dc", c)
end

-- "5 min ago", "2 h ago"... since a time() stamp.
function ns.Ago(stamp)
    stamp = tonumber(stamp) or 0
    if stamp <= 0 then return nil end
    local elapsed = math.max(0, time() - stamp)
    if elapsed < 60 then return L.JustNow end
    if elapsed < 3600 then return format(L.MinutesAgo, floor(elapsed / 60)) end
    if elapsed < 86400 then return format(L.HoursAgo, floor(elapsed / 3600)) end
    return format(L.DaysAgo, floor(elapsed / 86400))
end

function ns.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end

ns.PE = {}

function ns.PE.Service(name)
    local root = ProjectEbonhold
    if not root or type(root) ~= "table" then return nil end
    local svc = root[name]
    if type(svc) ~= "table" then return nil end
    return svc
end

function ns.PE.Call(service, fn, ...)
    local svc = ns.PE.Service(service)
    if not svc or type(svc[fn]) ~= "function" then return nil end
    return ns.SafeCall(svc[fn], ...)
end

------------------------------------------------------------------------
-- Timers (OnUpdate: no C_Timer on a stock 3.3.5a client)
------------------------------------------------------------------------
local timers = {}
local timerFrame
local function TimerUpdate()
    local now = GetTime()
    for i = #timers, 1, -1 do
        local t = timers[i]
        if now >= t.at then
            tremove(timers, i)
            local fn = t.fn
            t.fn = nil
            if fn then Dispatch(fn) end
        end
    end
    if #timers == 0 then
        timerFrame:Hide()
    end
end

ns.Timer = {}

function ns.Timer.After(delay, fn)
    if not timerFrame then
        timerFrame = CreateFrame("Frame", "EbonTomeHunterTimer")
        timerFrame:SetScript("OnUpdate", TimerUpdate)
    end
    timers[#timers + 1] = { at = GetTime() + (tonumber(delay) or 0), fn = fn }
    timerFrame:Show()
end

function ns.Timer.CancelAll()
    wipe(timers)
    if timerFrame then timerFrame:Hide() end
end

------------------------------------------------------------------------
-- Game events: several modules may listen to the same one.
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "EbonTomeHunterEvents")
ns.EventFrame = eventFrame
local handlers = {}

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        Dispatch(list[i], ...)
    end
end)

function ns.RegisterEvent(event, handler)
    local list = handlers[event]
    if not list then
        -- An event this client build does not know RAISES here, which would abort the
        -- rest of the file (slash commands included): never let one kill the addon.
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = handler
    return true
end

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------
local bootAttempts = 0

local function PEUp()
    return type(ProjectEbonhold) == "table" and
        (ProjectEbonhold.PerkDatabase or ProjectEbonhold.PerkService) and true or false
end

local function DataUp()
    if EbonholdHub and EbonholdHub.EchoMapData and EbonholdHub.EchoMapData.Locations then
        return true
    end
    if EbonCompletionist and EbonCompletionist.Data and EbonCompletionist.Data.EchoMap and
        EbonCompletionist.Data.EchoMap.Locations then
        return true
    end
    return false
end

local function Bootstrap()
    if PEUp() or DataUp() or bootAttempts >= 60 then
        if ns.Catalog and ns.Catalog.Build then
            ns.Catalog.Build()   -- re-arms itself if the echo database is not up yet
        end
        if ns.Scan and ns.Scan.ScanBags then
            ns.Scan.ScanBags(false)
        end
        ns.Fire("READY")
        return
    end
    bootAttempts = bootAttempts + 1
    ns.Timer.After(0.5, Bootstrap)
end

ns.RegisterEvent("ADDON_LOADED", function(name)
    if name == addonName then
        ns.InitDatabase()
        ns.Fire("DATABASE_READY")
    elseif name == "Blizzard_AuctionUI" then
        ns.Fire("AUCTION_UI_LOADED")
    end
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.Fire("LOGIN")
    ns.Timer.After(1.0, Bootstrap)
end)

ns.RegisterEvent("BAG_UPDATE", function()
    -- Bursty event: look at the bags once things settle.
    if ns.bagScanPending then return end
    ns.bagScanPending = true
    ns.Timer.After(1.5, function()
        ns.bagScanPending = nil
        if ns.Scan and ns.Scan.ScanBags then ns.Scan.ScanBags(false) end
        ns.Fire("BAGS_CHANGED")
    end)
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_EBONTOMEHUNTER1 = "/eth"
SLASH_EBONTOMEHUNTER2 = "/tomehunter"
SlashCmdList["EBONTOMEHUNTER"] = function(input)
    -- "send Name": the argument keeps its case (player names)
    local command, argument = strtrim(tostring(input or "")):match("^(%S*)%s*(.-)$")
    command = strlower(command or "")
    if command == "send" then
        if argument ~= "" then
            ns.Comm.SendWishlist(argument)
        else
            ns.Share.ShowDialog()
        end
    elseif command == "net" then
        ns.Print(ns.Net.StatusText())
    elseif command == "tp" or command == "travel" then
        ns.Travel.Command(argument)
    elseif command == "tuto" or command == "tutorial" or command == "guide" then
        ns.Tutorial.Start()
    elseif command == "rebuild" then
        ns.Catalog.Build()
        ns.Print(L.Rebuilt, ns.Catalog.Count())
    elseif command == "bags" then
        ns.Scan.ScanBags(true)
    elseif command == "options" or command == "config" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif command == "minimap" then
        local minimap = ns.Opt().minimap
        minimap.hide = not minimap.hide
        ns.Fire("SETTINGS_CHANGED", "minimap")
        ns.Print(minimap.hide and L.MinimapHidden or L.MinimapShown)
    elseif command == "scan" then
        ns.Scan.Start()
    elseif command == "share" or command == "export" or command == "import" then
        ns.Share.ShowDialog(command == "import")
    elseif command == "help" then
        ns.Print(L.Help)
    elseif ns.UI and ns.UI.Toggle then
        ns.UI.Toggle()
    end
end
