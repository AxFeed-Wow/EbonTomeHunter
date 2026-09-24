local addonName, ns = ...
local L = ns.L

-- Tomes the player gets: wishlist alert, and the drop place (position + mob) reported to
-- the other EbonTomeHunter users (Net.lua). A tome comes in two ways:
--  * the loot window: "You receive loot" in the chat; the mob is the dead unit under the
--    mouse (corpse clicked) or the dead target (interact key) when the window opens
--    (3.3.5a has no GetLootSourceInfo);
--  * Project Ebonhold's Greedy Scavenger pet, which loots the corpses by itself and puts
--    the items straight into the bags WITHOUT any chat line (found by EbonClearance): a
--    tome appearing in the bags while no loot window, bank, mail, vendor... is open. Its
--    mob is the one the player or the group killed in the last minute when all those kills
--    were the same mob; otherwise only the place is reported.
ns.Loot = {}
local Loot = ns.Loot

local SOURCE_MAX_AGE = 90     -- seconds between opening the loot and the loot message
local CLOSED_GRACE = 5        -- the last loot messages can come just after the window closed
local KILL_WINDOW = 60        -- the Scavenger loots the corpses of the last minute
local HANDLED_TTL = 20        -- a tome announced by its chat line: its bag increase is not counted again
local TRANSACTION_GAP = 10    -- bags filled through a bank, mail, vendor... window: not loot
local SETTLE = 10             -- after a loading screen the bags are read again: nothing announced

-- Windows through which items enter the bags without being loot (Blizzard, ProjectEbonhold).
local TRANSACTION_FRAMES = {
    "MerchantFrame", "BankFrame", "GuildBankFrame", "MailFrame", "OpenMailFrame", "TradeFrame",
    "AuctionFrame", "TradeSkillFrame", "QuestFrame", "GossipFrame",
    "ExtBankFrame", "VoidStorageFrame", "ModernShopFrame", "ItemPurchasePopup", "EbonholdExtractionFrame",
}

local lootSource      -- { at, closedAt, name, npcId, place }: the last loot window
local kills = {}      -- { at, name, npcId }, oldest first: creatures the player or the group killed
local engaged = {}    -- [guid] = GetTime(): creatures the player or the group fought
local engagedCount = 0
local handled = {}    -- [itemId] = { count, at }: tomes announced by their chat line
local bagTomes        -- [itemId] = count in the bags (nil until the first reading)
local transactionAt, settleUntil = -TRANSACTION_GAP, 0

-- "You receive loot: %s." -> "^You receive loot: (.+)%.$" (localized by the client)
local function Pattern(format)
    if type(format) ~= "string" then return nil end
    local pattern = format:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
    pattern = pattern:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

local SELF_PATTERNS = { Pattern(LOOT_ITEM_SELF_MULTIPLE), Pattern(LOOT_ITEM_SELF) }
local OTHER_PATTERNS = { Pattern(LOOT_ITEM_MULTIPLE), Pattern(LOOT_ITEM) }

-- Where the player stands: zone texts, and the zone map + position when possible.
-- Never while the world map is open (it would change the map the player looks at).
function Loot.CapturePlace()
    local place = { zone = GetRealZoneText() or "", sub = GetSubZoneText() or "" }
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then
        SetMapToCurrentZone()
        place.mapFile = GetMapInfo()
        local x, y = GetPlayerMapPosition("player")
        if x and y and (x > 0 or y > 0) then place.x, place.y = x, y end
    end
    return place
end

------------------------------------------------------------------------
-- Loot window
------------------------------------------------------------------------
local function DeadUnit(unit)
    return UnitExists(unit) and UnitIsDead(unit) and not UnitIsPlayer(unit)
end

ns.RegisterEvent("LOOT_OPENED", function()
    lootSource = { at = GetTime() }
    if IsFishingLoot and IsFishingLoot() then return end
    local unit = (DeadUnit("mouseover") and "mouseover") or (DeadUnit("target") and "target") or nil
    if not unit then return end   -- chest, gathering, bag opened from the inventory
    lootSource.name = UnitName(unit)
    lootSource.npcId = ns.Wowhead.NpcIdFromGUID(UnitGUID(unit))
    if lootSource.name and lootSource.npcId then ns.Wowhead.Remember(lootSource.name, lootSource.npcId) end
    lootSource.place = Loot.CapturePlace()
    ns.Fire("CORPSE_OPENED", UnitGUID(unit), lootSource.name, lootSource.npcId)   -- Evidence.lua
end)

ns.RegisterEvent("LOOT_CLOSED", function()
    if lootSource and not lootSource.closedAt then
        lootSource.closedAt = GetTime()
        if lootSource.name then ns.Fire("CORPSE_CLOSED") end
    end
end)

-- The loot window the tome came from: open, or closed a few seconds ago.
local function RecentLootWindow(now)
    local source = lootSource
    if not source or now - source.at > SOURCE_MAX_AGE then return nil end
    if source.closedAt and now - source.closedAt > CLOSED_GRACE then return nil end
    return source
end

------------------------------------------------------------------------
-- Kills (combat log): the corpses the Scavenger can loot
------------------------------------------------------------------------
local band = bit.band
local OURS = 0x7        -- COMBATLOG_OBJECT_AFFILIATION_MINE / _PARTY / _RAID
local FRIENDLY = 0x10   -- COMBATLOG_OBJECT_REACTION_FRIENDLY

local function IsCreature(guid)
    if type(guid) ~= "string" then return false end
    local high = strupper(guid:sub(3, 6))
    return high == "F130" or high == "F150"
end

local function ForgetOldFights(now)
    for guid, at in pairs(engaged) do
        if now - at > 600 then
            engaged[guid] = nil
            engagedCount = engagedCount - 1
        end
    end
end

ns.RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function(_, subEvent, _, _, srcFlags, dstGUID, dstName, dstFlags)
    if subEvent == "UNIT_DIED" then
        if not (dstGUID and engaged[dstGUID]) then return end
        engaged[dstGUID] = nil
        engagedCount = engagedCount - 1
        local now = GetTime()
        kills[#kills + 1] = { at = now, name = dstName, npcId = ns.Wowhead.NpcIdFromGUID(dstGUID) }
        while kills[1] and now - kills[1].at > KILL_WINDOW do tremove(kills, 1) end
    elseif srcFlags and band(srcFlags, OURS) ~= 0 and not (dstFlags and band(dstFlags, FRIENDLY) ~= 0)
        and IsCreature(dstGUID) then
        if not engaged[dstGUID] then
            engagedCount = engagedCount + 1
            if engagedCount > 300 then ForgetOldFights(GetTime()) end
        end
        engaged[dstGUID] = GetTime()
    end
end)

------------------------------------------------------------------------
-- A tome obtained: alert and drop place
------------------------------------------------------------------------
-- Raid-warning style alert (option) with a sound.
function Loot.Alert(text)
    if type(RaidNotice_AddMessage) == "function" and RaidWarningFrame then
        local color = type(ChatTypeInfo) == "table" and ChatTypeInfo.RAID_WARNING or nil
        RaidNotice_AddMessage(RaidWarningFrame, text, color or { r = 1, g = 0.82, b = 0 })
    end
    if ns.Opt().alertSound then PlaySound("RaidWarning") end
    ns.Print(text)
end

local function Report(itemId, place, mob, npcId)
    ns.Net.Report({
        itemId = itemId, mapFile = place.mapFile, x = place.x, y = place.y, npcId = npcId, mob = mob,
        zone = (place.zone or "") .. ((place.sub or "") ~= "" and (":" .. place.sub) or ""),
        at = time(), by = UnitName("player"),
    })
end

-- The mob of the kills of the last minute: all the same one, or nil (several mobs).
-- Second value: false when nothing was killed (no corpse to come from).
local function RecentMob(now)
    local mob, npcId, any = nil, nil, false
    for i = #kills, 1, -1 do
        local kill = kills[i]
        if now - kill.at > KILL_WINDOW then break end
        if not any then
            mob, npcId, any = kill.name, kill.npcId, true
        elseif kill.name ~= mob then
            mob, npcId = nil, nil
        end
    end
    return mob, any, npcId
end

-- A tome just came in (loot window or Scavenger): wishlist alert, then its drop place.
function Loot.Obtained(itemId)
    local row = ns.Catalog.Get(itemId)
    if not row then return end
    if ns.Wishlist.Has(itemId) and ns.Opt().alertSelf then
        Loot.Alert(format(L.AlertSelf, row.name or "?"))
    end
    local now = GetTime()
    local window = RecentLootWindow(now)
    if window then
        -- its corpse; nothing for a chest, a bag opened from the inventory or fishing
        if window.name and window.place then Report(itemId, window.place, window.name, window.npcId) end
        if window.name then ns.Fire("TOME_DROPPED", itemId, window.name, window.npcId) end
        return
    end
    -- no loot window: the Greedy Scavenger (or a roll won later): the corpses of the last minute
    local mob, any, npcId = RecentMob(now)
    if any then Report(itemId, Loot.CapturePlace(), mob, npcId) end
end

------------------------------------------------------------------------
-- Chat lines ("You receive loot", "X receives loot")
------------------------------------------------------------------------
local function Match(message, patterns)
    for _, pattern in ipairs(patterns) do
        if pattern then
            local a, b, c = message:match(pattern)
            if a then return a, b, c end
        end
    end
    return nil
end

local function TomeFromLink(link)
    local itemId = ns.Scan.ItemIdFromLink(link)
    local name = type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
    if not (itemId and name and ns.Catalog.IsTomeName(name)) then return nil end
    ns.Catalog.LearnTome(name, itemId)
    return ns.Catalog.Get(itemId) and itemId or nil, name
end

local function OnOtherLoot(who, link)
    local itemId, name = TomeFromLink(link)
    if not itemId or not ns.Wishlist.Has(itemId) or not ns.Opt().alertGroup then return end
    local row = ns.Catalog.Get(itemId)
    ns.Print(L.AlertGroup, who, row and row.name or name)
    if ns.Opt().alertSound then PlaySound("igQuestListOpen") end
end

ns.RegisterEvent("CHAT_MSG_LOOT", function(message)
    if type(message) ~= "string" then return end
    local link, count = Match(message, SELF_PATTERNS)
    if link then
        local itemId = TomeFromLink(link)
        if not itemId then return end
        -- the bag increase that follows is this same tome: counted once
        local now, seen = GetTime(), handled[itemId]
        if not seen or now - seen.at > HANDLED_TTL then
            seen = { count = 0 }
            handled[itemId] = seen
        end
        seen.count, seen.at = seen.count + (tonumber(count) or 1), now
        Loot.Obtained(itemId)
        return
    end
    local who, otherLink = Match(message, OTHER_PATTERNS)
    if who and otherLink then OnOtherLoot(who, otherLink) end
end)

------------------------------------------------------------------------
-- Tomes appearing in the bags (Greedy Scavenger: no chat line at all)
------------------------------------------------------------------------
local function TransactionOpen()
    for _, name in ipairs(TRANSACTION_FRAMES) do
        local frame = _G[name]
        if type(frame) == "table" and frame.IsShown and frame:IsShown() then return true end
    end
    return false
end

local function CountTomes()
    local counts = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local itemId = ns.Scan.ItemIdFromLink(GetContainerItemLink(bag, slot))
            if itemId and ns.Catalog.Get(itemId) then
                local _, count = GetContainerItemInfo(bag, slot)
                counts[itemId] = (counts[itemId] or 0) + (count or 1)
            end
        end
    end
    return counts
end

-- Items coming through a bank, mail, vendor... window are no loot (the bag reading comes
-- 1.5 s later: remember that one was open when the bags changed).
ns.RegisterEvent("BAG_UPDATE", function()
    if TransactionOpen() then transactionAt = GetTime() end
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    settleUntil = GetTime() + SETTLE
end)

ns.On("READY", function()
    bagTomes = CountTomes()   -- what the bags hold at login is not "just looted"
end)

ns.On("BAGS_CHANGED", function()
    local counts, previous, now = CountTomes(), bagTomes, GetTime()
    bagTomes = counts
    if not previous or now < settleUntil or now - transactionAt < TRANSACTION_GAP or TransactionOpen() then
        return
    end
    for itemId, count in pairs(counts) do
        local gained = count - (previous[itemId] or 0)
        local seen = handled[itemId]
        if gained > 0 and seen and now - seen.at <= HANDLED_TTL then
            local used = math.min(seen.count, gained)
            seen.count, gained = seen.count - used, gained - used
            if seen.count <= 0 then handled[itemId] = nil end
        end
        if gained > 0 then Loot.Obtained(itemId) end
    end
end)
