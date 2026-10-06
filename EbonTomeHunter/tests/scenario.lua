-- Offline scenario (validate_addon.py). Not listed in the .toc: never loaded in game.
-- Uses the REAL tome data (TomeData.lua, extracted from the client) and replays an
-- Auction House scan with real item links.

local ns = EbonTomeHunter
Check(ns ~= nil, "the addon namespace must be reachable")
if not ns then return end

-- The saved tables are replaced just before ADDON_LOADED (like the client): the
-- defaults must have been applied to the saved ones.
Check(type(EbonTomeHunterDB.tomes) == "table" and type(EbonTomeHunterDB.prices) == "table",
    "saved tables completed on ADDON_LOADED")
Check(type(EbonTomeHunterDB.options) == "table" and EbonTomeHunterDB.options.confirmBuy == true,
    "options have their defaults")
Check(type(EbonTomeHunterCharDB.wishlist) == "table", "per-character wishlist ready")

-- --- Complete static catalogue -----------------------------------------------
ns.Catalog.Build()
Check(ns.Catalog.Count() >= 148, "all 148 tomes listed, got " .. ns.Catalog.Count())

local beast = ns.Catalog.Get(300569)
Check(beast and beast.name == "Beast Bane", "tome 300569 is Beast Bane")
Check(beast and beast.tomeName == "Tome of Echo: Beast Bane", "real auction name")
Check(beast and beast.quality == "rare", "item quality mapped to a colour name")
Check(ns.Catalog.FindBySpell(200569) == beast, "the echo spell id resolves to its tome")
Check(beast and beast.desc and beast.desc:find("Beast Bane", 1, true), "tooltip description available")

-- Item names that differ from spell names still resolve.
Check(ns.Catalog.FindByTomeName("Tome of Echo: Eonar Seed") ~= nil, "item spelling 'Eonar Seed' matches")
Check(ns.Catalog.FindByTomeName("Tome of Eonar's Seed") ~= nil, "spell spelling 'Eonar's Seed' matches too")

-- Complete even when ProjectEbonhold is absent (no retry loop needed).
local savedPE = ProjectEbonhold
ProjectEbonhold = nil
ns.Catalog.Build()
Check(ns.Catalog.Count() >= 148, "complete without ProjectEbonhold loaded")
ProjectEbonhold = savedPE

-- --- Migration of keys saved by older versions (echo spell id -> tome item id) ---
EbonTomeHunterCharDB.wishlist[200569] = { qty = 2 }
EbonTomeHunterDB.prices[200569] = { min = 55555, listings = 1, at = 10, hist = {} }
ns.Catalog.Build()
Check(EbonTomeHunterCharDB.wishlist[200569] == nil and EbonTomeHunterCharDB.wishlist[300569] ~= nil,
    "old wishlist key migrated to the tome item id")
Check(EbonTomeHunterCharDB.wishlist[300569] and EbonTomeHunterCharDB.wishlist[300569].qty == 2, "quantity preserved")
Check(EbonTomeHunterDB.prices[300569] and EbonTomeHunterDB.prices[300569].min == 55555, "old price migrated")
ns.Wishlist.Remove(300569)
EbonTomeHunterDB.prices[300569] = nil

-- --- Auction House replay (real item links) -------------------------------------
AuctionFrame:Show()   -- at an auctioneer (Blizzard windows start hidden, like in the game)
local function Link(id, name, color)
    return "|cff" .. (color or "0070dd") .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0:80|h[" .. name .. "]|h|r"
end
local LISTINGS = {
    { name = "Tome of Echo: Beast Bane", count = 1, buyout = 150000, link = Link(300569, "Tome of Echo: Beast Bane") },
    { name = "Tome of Echo: Beast Bane", count = 1, buyout = 90000, link = Link(300569, "Tome of Echo: Beast Bane") },
    -- item name differs from the spell name: matched by exact item id
    { name = "Tome of Echo: DragonKin Bane", count = 2, buyout = 400000, link = Link(300570, "Tome of Echo: DragonKin Bane") },
    { name = "Frostweave Cloth", count = 20, buyout = 10000, link = Link(33470, "Frostweave Cloth", "ffffff") },
    -- a tome that does not exist in TomeData (future patch): learned
    { name = "Tome of Echo: Mystery Power", count = 1, buyout = 777000, link = Link(399999, "Tome of Echo: Mystery Power") },
}
GetNumAuctionItems = function() return #LISTINGS, #LISTINGS end
GetAuctionItemInfo = function(list, i)
    local l = LISTINGS[i]
    if not l then return nil end
    return l.name, "", l.count, 3, true, 80, l.buyout, 1, l.buyout
end
GetAuctionItemLink = function(list, i) return LISTINGS[i] and LISTINGS[i].link end
CanSendAuctionQuery = function() return true end
local queried
QueryAuctionItems = function(name) queried = name end

ns.Scan.Start()
Check(queried == "Tome of Echo", "AH query searches tomes, got " .. tostring(queried))
Fire("AUCTION_ITEM_LIST_UPDATE")
Advance(1)
Check(not ns.Scan.IsScanning(), "scan finished")
Check(ns.Prices.GetMin(300569) == 90000, "cheapest Beast Bane = 90000, got " .. tostring(ns.Prices.GetMin(300569)))
Check(ns.Prices.GetListings(300569) == 2, "two Beast Bane listings")
Check(ns.Prices.GetMin(300570) == 200000, "DragonKin Bane matched by item id, per-unit price, got " .. tostring(ns.Prices.GetMin(300570)))

local mystery = ns.Catalog.FindByTomeName("Tome of Echo: Mystery Power")
Check(mystery and mystery.learned, "unknown tome learned from the scan")
Check(mystery and mystery.name == "Mystery Power", "learned tome keeps its capitalisation")
Check(mystery and ns.Prices.GetMin(mystery.itemId) == 777000, "learned tome priced")
ns.Catalog.Build()
Check(ns.Catalog.FindByTomeName("Tome of Echo: Mystery Power") ~= nil, "learned tome survives a rebuild")

-- an auction whose item the client has not cached yet comes without a name (3.3.5a), until
-- AUCTION_ITEM_LIST_UPDATE fires again with its data
local loading   -- index of the auction still loading
GetAuctionItemInfo = function(list, i)
    local l = LISTINGS[i]
    if not l or i == loading then return nil end
    return l.name, "", l.count, 3, true, 80, l.buyout, 1, l.buyout
end
loading = 3   -- DragonKin Bane, the only auction of its tome
ns.Scan.Start()
Fire("AUCTION_ITEM_LIST_UPDATE")
Advance(1)
Check(ns.Scan.IsScanning(), "a page with an auction still loading waits for its data")
loading = nil
Fire("AUCTION_ITEM_LIST_UPDATE")
Advance(1)
Check(not ns.Scan.IsScanning() and ns.Prices.GetListings(300570) == 1, "its data arrived: the page is read in full")
loading = 3   -- this time it never comes
ns.Scan.Start()
Fire("AUCTION_ITEM_LIST_UPDATE")
Advance(5)
Check(not ns.Scan.IsScanning() and ChatContains(ns.L.ScanPartial), "never loaded: the scan ends and says so")
Check(ns.Prices.GetListings(300570) == 1, "a tome the scan could not see is not marked 'not for sale'")
loading = nil

AuctionFrame:Hide()   -- the Auction House is closed again

-- --- Wishlist ---------------------------------------------------------------------
ns.Wishlist.Add(300569, 2)
ns.Wishlist.Add(300570, 1)
Check(ns.Wishlist.ComputeTotal() == 2 * 90000 + 200000, "wishlist total = 380000, got " .. tostring(ns.Wishlist.ComputeTotal()))
ns.Wishlist.Remove(300569)
ns.Wishlist.Remove(300570)

-- The locked echoes import is gone (1.5.1): no button, no automatic import at login.
Check(ns.Wishlist.ImportFromPE == nil and ns.Wishlist.AutoImport == nil, "no locked echoes import any more")
Check(EbonTomeHunterCharDB.autoImported == nil, "its old per-character flag is cleared")

-- --- Bags -------------------------------------------------------------------------
GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end
GetContainerItemLink = function(bag, slot)
    if bag == 0 and slot == 2 then return Link(399998, "Tome of Echo: Bag Find") end
    return nil
end
Check(ns.Scan.ScanBags(false) == 1, "a tome in the bags is learned")

-- --- World map (3.3.5a returns names as multiple values) ---------------------------
GetMapContinents = function() return "Kalimdor", "Eastern Kingdoms", "Outland", "Northrend" end
GetMapZones = function(ci)
    if ci == 1 then return "Durotar", "Mulgore", "The Barrens" end
    if ci == 2 then return "Elwynn Forest", "Westfall", "Duskwood" end
    return "Hellfire Peninsula"
end
Check(#ns.WorldMap.Continents() == 4, "continents packed from varargs")
Check(ns.WorldMap.FindZoneForPlace("Sentinel Hill, Westfall") == "Westfall", "zone resolved from a place name")
Check(ns.WorldMap.FindZoneForPlace("Somewhere That Does Not Exist") == nil, "unknown place returns nil")

-- --- Tome list: every tome reachable, sorting and filters --------------------------------
local UI = ns.UI
UI.Show()

-- --- Guided tour: by itself the first time the window opens, then from "?" / /eth tuto ---
local Tuto = ns.Tutorial
-- the validator already opened the window (/eth) while booting: start from a new account
UI.frame:Hide()
Tuto.Stop()
ns.DB.tutorialDone = 0
ns.Fire("READY")
Check(ChatContains(ns.L.TutoLoginHint), "login: the tutorial is announced in the chat")
UI.Show()
Advance(0.5)
local bubble = EbonTomeHunterTutorial
Check(Tuto.running and bubble and bubble:IsShown() and Tuto.index == 1, "first opening: the tour starts by itself")
Check(bubble and bubble.title:GetText() == ns.L.TutoWelcomeTitle, "step 1: welcome")
local lit = 0
for i = 1, #Tuto.STEPS do
    Check(Tuto.index == i and bubble.text:GetText() == Tuto.STEPS[i].text and bubble.title:GetText() ~= "",
        "step " .. i .. " shown")
    if EbonTomeHunterTutorialHighlight:IsShown() then lit = lit + 1 end
    if i < #Tuto.STEPS then bubble.nextButton:GetScript("OnClick")(bubble.nextButton) end
end
Check(lit >= 9, "most steps light up a part of the window, got " .. lit)
Check(bubble.nextButton:GetText() == ns.L.TutoDone, "last step: Finish")
bubble.prevButton:GetScript("OnClick")(bubble.prevButton)
Check(Tuto.index == #Tuto.STEPS - 1, "Back: previous step")
bubble.skip:GetScript("OnClick")(bubble.skip)
Check(not Tuto.running and not bubble:IsShown() and not EbonTomeHunterTutorialHighlight:IsShown()
    and ns.DB.tutorialDone == 1, "Skip: tour over and remembered")
UI.Toggle()
UI.Toggle()
Advance(0.5)
Check(not Tuto.running and UI.frame:IsShown(), "it does not start by itself any more")
UI.parts.help:GetScript("OnClick")(UI.parts.help)
Check(Tuto.running and Tuto.index == 1 and bubble:IsShown(), "the ? button replays it")
UI.frame:Hide()
Check(not Tuto.running and not bubble:IsShown(), "closing the window ends the tour")
Slash("/eth tuto")
Check(Tuto.running and UI.frame:IsShown(), "/eth tuto opens the window on the tour")
Tuto.Next()
Tuto.Stop(true)
Check(not Tuto.running and not bubble:IsShown() and UI.frame:IsShown(), "tour stopped, window kept")

local scrollFrame = EbonTomeHunterListScroll
local bar = EbonTomeHunterListScrollScrollBar
local count = ns.Catalog.Count()
local rows, rowH = UI.VISIBLE_ROWS, UI.ROW_H
Check(#UI.list.items == count, "all " .. count .. " tomes listed, got " .. #UI.list.items)
Check(scrollFrame:IsShown(), "scroll frame shown: more tomes than rows")
local _, maxValue = bar:GetMinMaxValues()
Check(maxValue == (count - rows) * rowH, "scroll range covers every tome, got " .. tostring(maxValue))
local anchor, anchorTo, anchorToPoint = scrollFrame:GetPoint(1)
Check(anchor == "TOPLEFT" and anchorTo ~= nil and anchorToPoint == "TOPLEFT",
    "the scroll frame covers the rows (mouse wheel works over the list)")
Check(scrollFrame:IsMouseWheelEnabled(), "mouse wheel enabled on the list")
local firstBefore = EbonTomeHunterListRow1.item and EbonTomeHunterListRow1.item.itemId
scrollFrame:GetScript("OnMouseWheel")(scrollFrame, -1)
Check(FauxScrollFrame_GetOffset(scrollFrame) == 3, "one wheel notch scrolls 3 rows, got " .. tostring(FauxScrollFrame_GetOffset(scrollFrame)))
Check(EbonTomeHunterListRow1.item and EbonTomeHunterListRow1.item.itemId ~= firstBefore, "rows redrawn after scrolling")
bar:SetValue(maxValue)
local lastRow = _G["EbonTomeHunterListRow" .. rows]
Check(lastRow.item and lastRow.item.itemId == UI.list.items[count].itemId, "the last tome is reachable")
UI.searchBox:SetText("bane")
Check(FauxScrollFrame_GetOffset(scrollFrame) == 0, "a new search scrolls back to the top")
Check(#UI.list.items > 0 and #UI.list.items < count, "the search filters the list")
UI.searchBox:SetText("")

ns.Opt().sortKey, ns.Opt().sortDesc = "price", false
UI.Refresh()
Check(UI.list.items[1].itemId == 300569, "sorted by price: the cheapest tome first (Beast Bane 9g)")
ns.Opt().sortKey = "name"
ns.Opt().onlyPriced = true
UI.Refresh()
local allListed = #UI.list.items > 0
for _, data in ipairs(UI.list.items) do
    if not ns.Prices.IsListed(data.itemId) then allListed = false end
end
Check(allListed, "the 'On sale' filter keeps only the listed tomes")
ns.Opt().onlyPriced = false
UI.Refresh()

-- --- Minimap button ------------------------------------------------------------------------
local minimapButton = EbonTomeHunterMinimapButton
Check(minimapButton ~= nil and minimapButton:IsShown(), "minimap button created at login")
Slash("/eth minimap")
Check(not minimapButton:IsShown() and ns.Opt().minimap.hide, "/eth minimap hides it")
Slash("/eth minimap")
Check(minimapButton:IsShown(), "and shows it again")
EbonTomeHunterFrame:Hide()
minimapButton:GetScript("OnClick")(minimapButton, "LeftButton")
Check(EbonTomeHunterFrame:IsShown(), "left-click opens the window")
minimapButton:GetScript("OnClick")(minimapButton, "LeftButton")
Check(not EbonTomeHunterFrame:IsShown(), "and closes it")

-- --- Tomes learned by this character (ProjectEbonhold discovery list) ---------------------------
if ProjectEbonhold then
    -- discovery list = echo spell ids; tome item id == echo id + 100000
    ProjectEbonhold.PerkService = ProjectEbonhold.PerkService or {}
    ProjectEbonhold.PerkService.GetDiscoveredEchoes = function() return { [200569] = 2, [200570] = 1 } end
    ProjectEbonhold.PerkService.IsTomeEchoDisabled = function(echoId) return echoId == 200570 end
    Check(ns.Known.IsKnown(300569) == true, "Beast Bane learned (echo 200569 discovered)")
    Check(ns.Known.IsKnown(300022) == false, "a tome whose echo is not discovered is not learned")
    Check(ns.Known.State(300570) == "disabled", "DragonKin Bane learned but switched off")
    local known, total = ns.Known.Count()
    Check(known == 2 and total == ns.Catalog.Count(), "2 tomes learned, got " .. tostring(known))

    UI.Show()
    ns.Opt().onlyUnknown = true
    UI.Refresh()
    local onlyUnknown = #UI.list.items > 0
    for _, data in ipairs(UI.list.items) do
        if ns.Known.IsKnown(data.itemId) then onlyUnknown = false end
    end
    Check(onlyUnknown and #UI.list.items == ns.Catalog.Count() - 2, "'To learn' filter hides the 2 learned tomes")
    ns.Opt().onlyUnknown = false
    UI.searchBox:SetText("beast bane")
    local badge = false
    for i = 1, rows do
        local row = _G["EbonTomeHunterListRow" .. i]
        if row:IsShown() and row.item and row.item.itemId == 300569 then badge = row.icon.badge:IsShown() end
    end
    Check(badge, "learned badge shown on the tome icon")
    UI.searchBox:SetText("")

    local refreshed = false
    ns.On("KNOWN_CHANGED", function() refreshed = true end)
    Fire("CHAT_MSG_ADDON", "AAM0x9", "530\t200569:2,200570:1", "WHISPER", "Tester")
    Advance(1)
    Check(refreshed, "the server discovery message (530) refreshes the learned state")
    refreshed = false
    Fire("CHAT_MSG_ADDON", "AAM0x9", "800\t1;2", "WHISPER", "Tester")
    Advance(1)
    Check(not refreshed, "other server messages are ignored")
else
    Check(ns.Known.IsKnown(300569) == nil and ns.Known.Count() == nil, "without ProjectEbonhold the learned state is unknown")
end

-- --- Share a wishlist as a string ------------------------------------------------------------
for _, item in ipairs(ns.Wishlist.List()) do ns.Wishlist.Remove(item.itemId) end
ns.Wishlist.SetQty(300569, 2)
ns.Wishlist.SetQty(300570, 1)
local shared, sharedCount, sharedCopies = ns.Share.ExportWishlist()
Check(shared:find("^ETH1:Tester:") and sharedCount == 2 and sharedCopies == 3, "export string: " .. tostring(shared))
Check(shared:find("569x2,570:", 1, true) ~= nil, "tomes encoded compactly, sorted by id")
ns.Wishlist.Remove(300569)
ns.Wishlist.Remove(300570)
local parsed = ns.Share.Decode("Voici ma liste : " .. shared .. " merci !")
Check(parsed and #parsed.items == 2 and parsed.author == "Tester" and parsed.copies == 3,
    "the string is found inside other text")
ns.Share.Import(parsed, "merge")
Check(ns.Wishlist.Get(300569) and ns.Wishlist.Get(300569).qty == 2 and ns.Wishlist.Get(300570).qty == 1,
    "round trip: same wishlist")
ns.Wishlist.SetQty(300569, 5)
ns.Share.Import(parsed, "merge")
Check(ns.Wishlist.Get(300569).qty == 5, "merge keeps the larger quantity")
ns.Wishlist.SetQty(300022, 1)
ns.Share.Import(parsed, "replace")
Check(not ns.Wishlist.Has(300022) and ns.Wishlist.Get(300569).qty == 2, "replace drops the other tomes")

local damaged = shared:gsub("569x2", "569x3")
local nothing, why = ns.Share.Decode(damaged)
Check(nothing == nil and why == "ShareCorrupt", "an edited string is refused")
Check(select(2, ns.Share.Decode("hello")) == "ShareNoString", "no string at all")
Check(select(2, ns.Share.Decode("ETH9:Bob:1:abcdef")) == "ShareVersion", "string of a future version")
local readme = ns.Share.Decode("ETH1:Bob:22x3,569x2,570:3f38d1")   -- example of the README
Check(readme and #readme.items == 3 and readme.copies == 6 and readme.author == "Bob", "README example decodes")
local legacy = ns.Share.Decode("ETP1:Bob:22x3,569x2,570:c062c3")   -- EbonTomePrices 1.x string
Check(legacy and #legacy.items == 3 and legacy.copies == 6, "strings of the former EbonTomePrices still import")
local withUnknown = ns.Share.Encode({ { itemId = 300569, qty = 1 }, { itemId = 399999, qty = 2 } }, "Bob")
local p2 = ns.Share.Decode(withUnknown)
Check(p2 and #p2.items == 1 and p2.unknown == 1 and p2.author == "Bob", "unknown tomes are counted and skipped")

-- the dialog
Slash("/eth share")
Check(EbonTomeHunterShareFrame:IsShown(), "/eth share opens the dialog")
Check(ns.Share.exportBox:GetText() == ns.Share.ExportWishlist(), "the export box holds the string")
ns.Share.exportBox:SetText("typed over")
Check(ns.Share.exportBox:GetText() == ns.Share.ExportWishlist(), "the export box is read only")
ns.Share.importBox:SetText(withUnknown)
Check((ns.Share.previewText:GetText() or ""):find("Bob", 1, true) ~= nil, "preview names the author")
local realPopup = StaticPopup_Show
local asked
StaticPopup_Show = function(which, a1, a2, data)
    asked = { which = which, data = data }
    return CreateFrame("Frame")
end
ns.Share.replaceButton:GetScript("OnClick")(ns.Share.replaceButton)
Check(asked and asked.which == "EBONTOMEHUNTER_REPLACE_WISHLIST", "replacing a non-empty wishlist asks first")
StaticPopupDialogs.EBONTOMEHUNTER_REPLACE_WISHLIST.OnAccept(nil, asked.data)
Check(ns.Wishlist.Count() == 1 and ns.Wishlist.Get(300569).qty == 1, "the wishlist is now the imported one")
Check(ns.Share.importBox:GetText() == "", "the import box is cleared")
StaticPopup_Show = realPopup
ns.Share.importBox:SetText("ETH1:x:12,oops:000000")
Check(not ns.Share.mergeButton:IsEnabled(), "merge disabled for an invalid string")
EbonTomeHunterShareFrame:Hide()

-- --- Echo Builder builds in the same import box (real examples of project-ebonhold.com) -------
local EB_BUILD = "200044-200479-200491-200500-200521-200539-200540-200663-200688-200722-200954-201340-201378"
local EB_LINK = "https://project-ebonhold.com/tools/echo-builder?b=" .. EB_BUILD .. "&c=paladin"   -- "Copy link"
local EB_TEXT = table.concat({                                                                        -- "Copy build"
    "Echo build \226\128\148 13/85 picks \226\128\148 Paladin", "Cyclone of Cold Bones x1", "Dark Nucleus x1",
    "Forged in Combat x1", "Keen Aim x1", "Mystic Potency x1", "Nature\226\128\153s Surge x1", "Open Wounds x1",
    "Precision Strike x1", "Reactive Retaliation x1", "Rolling Momentum x1", "Spiteful Shard x1",
    "Steady Channeling x1", "Tunnel Vision x1", EB_LINK,
}, "\n")
local surge, cyclone, nucleus = ns.Catalog.FindBySpell(200954), ns.Catalog.FindBySpell(201340), ns.Catalog.FindBySpell(201378)
Check(surge and cyclone and nucleus and not ns.Catalog.FindBySpell(200044),
    "3 echoes of the build have a tome (Nature's Surge, Cyclone of Cold Bones, Dark Nucleus), the others none")
local realKnown = ns.Known.IsKnown
ns.Known.IsKnown = function(id) return nucleus ~= nil and id == nucleus.itemId end   -- Dark Nucleus learned
for label, pasted in pairs({ link = EB_LINK, ["Copy build"] = EB_TEXT, ["bare build"] = EB_BUILD }) do
    local b = ns.Share.Decode(pasted)
    Check(b and b.echoBuild and b.echoes == 13 and #b.items == 2 and #b.learned == 1 and #b.basic == 10,
        "Echo Builder " .. label .. ": 13 echoes = 2 tomes to add, 1 already learned, 10 basic")
end
local eb = ns.Share.Decode(EB_LINK)
local ebNames = {}
for _, item in ipairs(eb.items) do ebNames[item.row.name] = item.qty end
Check(eb.class == "Paladin" and ebNames[surge.name] == 1 and ebNames[cyclone.name] == 1 and eb.learned[1] == nucleus,
    "the tomes of the build, 1 copy each; the learned one set apart")
local stacked = ns.Share.Decode("https://project-ebonhold.com/tools/echo-builder?b=200954.3-201340-200044.2%21201340&c=death-knight")
Check(stacked and #stacked.items == 2 and #stacked.basic == 1 and stacked.class == "Death Knight",
    "picks (.3), locked echoes (!, %21 when encoded) and the class name are read")
local onlyBasic = ns.Share.Decode("https://project-ebonhold.com/tools/echo-builder?b=200044-200479&c=mage")
Check(onlyBasic and #onlyBasic.items == 0 and #onlyBasic.basic == 2, "a build of basic echoes only: nothing to add")
Check(select(2, ns.Share.Decode("ETH1:Yangr:20,35,48,52,63,227,228,234,231,240:7768f7")) == "ShareCorrupt",
    "a hand-made string with a wrong checksum is still refused")

for _, item in ipairs(ns.Wishlist.List()) do ns.Wishlist.Remove(item.itemId) end
Slash("/eth share")
ns.Share.importBox:SetText("https://project-ebonhold.com/tools/echo-builder?b=200044-200479&c=mage")
Check(not ns.Share.mergeButton:IsEnabled() and (ns.Share.previewText:GetText() or ""):find(ns.L.ShareEchoNoTome, 1, true),
    "only basic echoes: the preview says so, nothing to import")
ns.Share.importBox:SetText(EB_TEXT)
local ebPreview = ns.Share.previewText:GetText() or ""
Check(ns.Share.mergeButton:IsEnabled() and ebPreview:find(format(ns.L.ShareEchoTomes, 2), 1, true)
    and ebPreview:find(format(ns.L.ShareEchoLearned, 1), 1, true) and ebPreview:find(format(ns.L.ShareEchoBasic, 10), 1, true),
    "preview of the pasted build: learnable tomes, learned, basic echoes")
ns.Share.mergeButton:GetScript("OnClick")(ns.Share.mergeButton)
Check(ns.Wishlist.Has(surge.itemId) and ns.Wishlist.Has(cyclone.itemId) and not ns.Wishlist.Has(nucleus.itemId)
    and ns.Wishlist.Count() == 2, "merged: the 2 learnable tomes are in the wishlist, not the learned one")
Check(ChatContains(format(ns.L.ShareEchoBasicChat, 10, ""):sub(1, 20)), "the ignored basic echoes are listed in the chat")
local mine = ns.Share.ExportWishlist()
ns.Share.importBox:SetText(mine)
Check(ns.Share.mergeButton:IsEnabled() and (ns.Share.previewText:GetText() or ""):find("2", 1, true) ~= nil,
    "an addon string still imports in the same box")
Check(not ns.Share.learnedCheck:IsShown(), "no 'add the learned tomes' box for an addon string")

-- tomes already learned: added only when the player ticks the box
ns.Share.importBox:SetText(EB_LINK)
Check(ns.Share.learnedCheck:IsShown() and not ns.Share.learnedCheck:GetChecked(),
    "a build with a learned tome: the box is offered, unticked")
ns.Share.learnedCheck:SetChecked(true)
ns.Share.learnedCheck:GetScript("OnClick")(ns.Share.learnedCheck)
Check((ns.Share.previewText:GetText() or ""):find(format(ns.L.ShareEchoLearnedAdded, 1), 1, true) ~= nil,
    "ticked: the preview says the learned tome is added anyway")
ns.Share.mergeButton:GetScript("OnClick")(ns.Share.mergeButton)
Check(ns.Wishlist.Has(nucleus.itemId) and ns.Wishlist.Count() == 3, "merged: the learned tome is in the wishlist too")
Check(not ns.Share.learnedCheck:IsShown(), "after the import the box is gone")
ns.Share.importBox:SetText(EB_LINK)
Check(ns.Share.learnedCheck:IsShown() and not ns.Share.learnedCheck:GetChecked(), "and unticked again for the next build")
ns.Share.importBox:SetText("https://project-ebonhold.com/tools/echo-builder?b=200044-200479&c=mage")
Check(not ns.Share.learnedCheck:IsShown(), "no learned tome in the build: no box")
EbonTomeHunterShareFrame:Hide()
ns.Known.IsKnown = realKnown
for _, item in ipairs(ns.Wishlist.List()) do ns.Wishlist.Remove(item.itemId) end

-- --- World map: a marker where the tome drops ------------------------------------------------
-- Farm places as EbonholdHub gives them: percentages of ITS map images (real coordinates).
EbonholdHub = { EchoMapData = { Locations = {
    ["eastern-kingdoms"] = {
        { name = "Beast Bane", x = 46.5, y = 9.3, placeName = "Hearthglen", mobs = { "Scarlet Paladins" } },
        -- just past the east edge of the Burning Steppes map in the source data
        { name = "Entropic Fusion", x = 64.9, y = 63.8, placeName = "Burning Steppes - Dreadmaul Rock", mobs = { "Flamekin Spitter" } },
    },
    ["kalimdor"] = {
        { name = "Beast Bane", x = 53.5, y = 7.0, placeName = "Unknown location", mobs = {} },
        { name = "Dragonkin Bane", x = 62.3, y = 70.9, placeName = "Dustwallow Marsh - Outside Ony raid", mobs = { "Dragonkins" } },
        { name = "Arcane Hazard", x = 65.6, y = 7.5, placeName = "Unknown location", mobs = {} },
    },
    ["northrend"] = {
        { name = "Beast Bane", x = 51.3, y = 42.9, placeName = "Crystalsong Forest - Forlorn Woods", mobs = { "Sinewy Wolf" } },
    },
} } }
for _, item in ipairs(ns.Wishlist.List()) do ns.Wishlist.Remove(item.itemId) end
ns.Catalog.Build()
local bane = ns.Catalog.Get(300569)
Check(bane and bane.locations and #bane.locations == 3, "every drop place kept (3 for Beast Bane)")
Check(bane and bane.location and bane.location.placeName == "Hearthglen", "main place = first one with a map point")
Check(bane and bane.locations and bane.locations[3].placeName == "Unknown location", "places without a map point come last")

local zoneFile, _, zx, zy = ns.WorldMap.BestZone(bane.locations[1])
Check(zoneFile == "WesternPlaguelands", "Hearthglen drawn on Western Plaguelands, got " .. tostring(zoneFile))
Check(zx and math.abs(zx - 0.45) < 0.03 and math.abs(zy - 0.13) < 0.03, format("Hearthglen at 45,13 (got %.2f, %.2f)", zx or -1, zy or -1))
local csFile, _, csx, csy = ns.WorldMap.BestZone(bane.locations[2])
Check(csFile == "CrystalsongForest" and math.abs(csx - 0.49) < 0.03 and math.abs(csy - 0.54) < 0.03,
    "Forlorn Woods at Crystalsong Forest 49,54")

-- A small world map: GetMapInfo() names the shown map, SetMapByID(WorldMapArea id) changes it.
local shownMap = "Elwynn"
local fileById = {}
for file, info in pairs(ns.MapData.maps) do fileById[info.id] = file end
GetMapInfo = function() return shownMap, 668 end
SetMapByID = function(id) shownMap = fileById[id] or shownMap; Fire("WORLD_MAP_UPDATE") end
ShowUIPanel = function(f) f:Show() end
HideUIPanel = function(f) f:Hide() end
WorldMapButton:SetSize(1002, 668)
WorldMapFrame:Hide()
local function ShownPins()
    local out = {}
    for i = 1, 50 do
        local pin = _G["EbonTomeHunterPin" .. i]
        if not pin then break end
        if pin:IsShown() then out[#out + 1] = pin end
    end
    return out
end
local function ShowMap(file) shownMap = file; Fire("WORLD_MAP_UPDATE") end

ns.WorldMap.Locate(300569)
Check(WorldMapFrame:IsShown(), "Locate opens the world map")
Check(shownMap == "WesternPlaguelands", "Locate shows the zone of the first place, got " .. tostring(shownMap))
local pins = ShownPins()
Check(#pins == 1 and pins[1]._etp.current, "one highlighted marker on Western Plaguelands, got " .. #pins)
if pins[1] then
    local _, rel, relPoint, ox, oy = pins[1]:GetPoint(1)
    Check(rel == WorldMapButton and relPoint == "TOPLEFT", "marker anchored to the map's top-left corner")
    Check(math.abs(ox - 0.45 * 1002) < 30 and math.abs(oy + 0.13 * 668) < 30, format("marker drawn on Hearthglen (%.0f, %.0f)", ox, oy))
end
Check(ChatContains("Western Plaguelands") and ChatContains("Scarlet Paladins"), "chat gives the zone, coordinates and mobs")

ns.WorldMap.Locate(300569)
Check(shownMap == "CrystalsongForest", "Locate again: next place (Crystalsong Forest), got " .. tostring(shownMap))
pins = ShownPins()
Check(#pins == 1 and math.abs(pins[1]._etp.x - 0.49) < 0.03, "marker on the Forlorn Woods")
ns.WorldMap.Locate(300569)
Check(shownMap == "WesternPlaguelands", "places without a map point are skipped when cycling")

ShowMap("Azeroth")
Check(#ShownPins() == 1, "Eastern Kingdoms continent map shows the Hearthglen marker")
ShowMap("Kalimdor")
Check(#ShownPins() == 0, "an 'Unknown location' placeholder is never drawn")
ShowMap("Elwynn")
Check(#ShownPins() == 0, "no marker on a zone without drop place")

ns.Wishlist.Add(300570, 1)
ShowMap("Dustwallow")
pins = ShownPins()
Check(#pins == 1 and pins[1]._etp.itemId == 300570 and not pins[1]._etp.focus, "wishlist tomes are marked too (Dustwallow Marsh)")
ns.SetOption("mapPins", false)
Check(#ShownPins() == 0, "option off: no wishlist marker")
ns.SetOption("mapPins", true)
Check(#ShownPins() == 1, "option on again")
ns.Wishlist.Remove(300570)

WorldMapFrame:Hide()
Check(#ShownPins() == 0, "markers hidden with the map")
local hazard = ns.Catalog.byName["arcane hazard"]
Check(hazard ~= nil, "Arcane Hazard is a known tome")
if hazard then
    ns.WorldMap.Locate(hazard.itemId)
    Check(not WorldMapFrame:IsShown(), "a tome without precise place: told in chat, no map opened")
end

local fusion = ns.Catalog.byName["entropic fusion"]
Check(fusion ~= nil, "Entropic Fusion is a known tome")
if fusion then
    ns.WorldMap.Locate(fusion.itemId)
    Check(shownMap == "BurningSteppes", "Dreadmaul Rock shown on Burning Steppes, got " .. tostring(shownMap))
    pins = ShownPins()
    Check(#pins == 1 and pins[1]._etp.x == 1, "a place just past the map edge keeps its marker, against the edge")
end

ns.WorldMap.Locate(300569)
pins = ShownPins()
if pins[1] then
    pins[1]:GetScript("OnClick")(pins[1])
    Check(not WorldMapFrame:IsShown(), "clicking a marker closes the map")
    local visible = false
    for i = 1, rows do
        local row = _G["EbonTomeHunterListRow" .. i]
        if row:IsShown() and row.item and row.item.itemId == 300569 then visible = true end
    end
    Check(visible, "the clicked tome is scrolled into view in the list")
end
-- --- Wowhead links (WotLK Classic section) ---------------------------------------------------
local WH = ns.Wowhead
Check(WH.NpcURL(21405, "Ethereal Arcanist") == "https://www.wowhead.com/wotlk/npc=21405/ethereal-arcanist",
    "NPC link in the WotLK format of wowhead.com")
Check(WH.SearchURL("Scarlet Paladin") == "https://www.wowhead.com/wotlk/search?q=Scarlet+Paladin", "WotLK search link")
Check(WH.Slug("Mosh'Ogg Brute") == "moshogg-brute", "slug without apostrophe")
Check(WH.NpcIdFromGUID("0xF130005F4E0005B1") == 24398, "NPC id read from a 3.3.5a creature GUID")
Check(WH.NpcIdFromGUID("0x0000000000ABCDEF") == nil, "a player GUID is not an NPC")
local split = WH.SplitMobs("Bloodsail Mage/Raider")
Check(split[1] == "Bloodsail Mage" and split[2] == "Bloodsail Raider", "grouped mob names are split")
Check(WH.SplitMobs("Blackrock Stronghold mobs")[1] == "Blackrock Stronghold", "'mobs' suffix dropped")

-- the Wowhead links of a tome's sources (those of the Sources window)
local function Links(itemId)
    local out = {}
    for _, loc in ipairs(ns.WorldMap.Locations(ns.Catalog.Get(itemId))) do
        for _, text in ipairs(type(loc.mobs) == "table" and loc.mobs or {}) do
            for _, name in ipairs(WH.SplitMobs(text)) do
                local url = WH.LinkFor(name, loc)
                if url then out[#out + 1] = { url = url } end
            end
        end
    end
    return out
end
local links = Links(300569)
Check(#links >= 2 and links[1].url:find("^https://www%.wowhead%.com/wotlk/search%?q=") ~= nil,
    "unknown NPC id: WotLK search link")
-- the mob is moused over: its id is learned (only for mobs of the drop places)
local unitState = {}
UnitExists = function(unit) return unitState[unit] ~= nil end
UnitIsPlayer = function() return false end
UnitIsDead = function(unit) return unitState[unit] and unitState[unit].dead or false end
UnitName = function(unit)
    if unit == "player" then return "Tester" end
    return unitState[unit] and unitState[unit].name or nil
end
UnitGUID = function(unit) return unitState[unit] and unitState[unit].guid or nil end
unitState.mouseover = { name = "Scarlet Paladin", guid = "0xF13000125A000001" }
Fire("UPDATE_MOUSEOVER_UNIT")
Check(WH.NpcId("Scarlet Paladins") == 4698, "NPC id learned from a mouseover (plural name matched)")
unitState.mouseover = { name = "Random Critter", guid = "0xF1300000AA000001" }
Fire("UPDATE_MOUSEOVER_UNIT")
Check(WH.NpcId("Random Critter") == nil, "mobs unrelated to tomes are not stored")
unitState.mouseover = nil
links = Links(300569)
local exact = false
for _, link in ipairs(links) do
    if link.url == "https://www.wowhead.com/wotlk/npc=4698/scarlet-paladins" then exact = true end
end
Check(exact, "the learned id gives an exact NPC link")
local opened
EbonholdOpenURL = function(url) opened = url end
Check(ns.Sources.Show(300569) >= 2 and EbonTomeHunterSourcesFrame:IsShown(), "Sources window opened (Wowhead links, teleports)")
local sourceRow = EbonTomeHunterSourcesListRow1
Check(sourceRow and sourceRow:IsShown() and sourceRow.wowhead:IsShown(), "a source row with its Wowhead button")
sourceRow.wowhead:GetScript("OnClick")(sourceRow.wowhead)
Check(opened and opened:find("^https://www%.wowhead%.com/wotlk/") ~= nil, "Wowhead opens a WotLK page: " .. tostring(opened))
EbonTomeHunterSourcesFrame:Hide()
local customUrl, customId, isCustom = WH.LinkFor("Echo Wraith", { npcIds = { ["Echo Wraith"] = 190001 } })
Check(customUrl == nil and customId == 190001 and isCustom, "a creature made for Ebonhold (id 190001) gets no Wowhead link")
for _, link in ipairs(Links(300569)) do
    Check(not link.url:find("item=", 1, true), "never an item page (Ebonhold tomes are not on Wowhead)")
end

-- --- Loot: wishlist alert, drop place recorded ------------------------------------------------
GetRealZoneText = function() return "Crystalsong Forest" end
GetSubZoneText = function() return "Forlorn Woods" end
GetPlayerMapPosition = function(unit) return 0.49, 0.54 end
WorldMapFrame:Hide()
shownMap = "CrystalsongForest"
for _, item in ipairs(ns.Wishlist.List()) do ns.Wishlist.Remove(item.itemId) end
ns.Wishlist.SetQty(300569, 1)

unitState.target = { name = "Sinewy Wolf", guid = "0xF130006F12000042", dead = true }
Fire("LOOT_OPENED")
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300569, "Tome of Echo: Beast Bane")))
Check(ChatContains(format(ns.L.AlertSelf, "Beast Bane")), "alert: wishlist tome looted")
do
    local mine = ns.DB.sightings[300569] and ns.DB.sightings[300569][1]
    Check(mine and mine.mapFile == "CrystalsongForest" and mine.npcId == 28434 and mine.mob == "Sinewy Wolf"
        and math.abs(mine.x - 0.49) < 0.001, "drop place recorded (zone map, position, mob)")
end
Check(WH.NpcId("Sinewy Wolf") == 28434, "the looted mob's id is learned too")
unitState.target = nil
Fire("LOOT_CLOSED")
Advance(4)

-- names are cut to a byte length, never in the middle of a French character
do
    local function ZoneField(zone)
        return ({ strsplit("^", ns.Net.Encode({ itemId = 300569, zone = zone, at = time() })) })[7]
    end
    local eAcute = string.char(195, 169)   -- "é" in UTF-8
    Check(ZoneField(string.rep("a", 59) .. eAcute) == string.rep("a", 59), "a 2-byte character is not cut in two")
    Check(ZoneField(string.rep("a", 58) .. eAcute) == string.rep("a", 58) .. eAcute, "a character that fits is kept")
end

-- places of the network: validated, merged, the same text on every client
do
    local hazardId = ns.Catalog.byName["arcane hazard"].itemId
    local found = time()
    local function Place(extra)   -- (false removes a field)
        local r = { itemId = hazardId, mapFile = "Tanaris", x = 0.512, y = 0.498, npcId = 5420, mob = "Wastewander Bandit",
            zone = "Tanaris:Wavestrider Beach", at = found, by = "Bob", finders = { Bob = true } }
        for k, v in pairs(extra or {}) do
            if v == false then r[k] = nil else r[k] = v end
        end
        return ns.Net.Encode(r)
    end
    ns.SetOption("netEnabled", false)   -- these test places must not reach EbonAPI
    local kept = ns.DB.sightings
    ns.DB.sightings = {}
    local hazardRow = ns.Catalog.Get(hazardId)
    Check(hazardRow and not ns.WorldMap.WorldPosition(hazardRow.location), "Arcane Hazard has no map point yet")
    Check(ns.Net.ImportPlaces(hazardId, Place(), false) == 1, "a place of a dataset is taken")
    Advance(2)
    local hzFile, _, hzx = ns.WorldMap.BestZone(hazardRow.location)
    Check(hazardRow.location.source == "net" and hzFile == "Tanaris" and math.abs(hzx - 0.512) < 0.001,
        "the catalogue now places Arcane Hazard where the other player looted it")
    Check(ns.Net.PlacesText(hazardId) == Place(), "a dataset that says all we know is written back the same")
    ns.Net.ImportPlaces(hazardId, Place({ by = "Carl", finders = { Carl = true }, x = 0.515 }), false)
    local text = ns.Net.PlacesText(hazardId)
    Check(#ns.DB.sightings[hazardId] == 1 and text:find("%^512%^498%^", 1) and text:find("%^Bob%^2$"),
        "the same spot from a second player: one place, 2 players, the smallest name and point on every client")
    Check(ns.Net.ImportPlaces(hazardId, "399999^Tanaris^500^500^^Bandit^Tanaris^" .. time() .. "^Eve^1", false) == 0
        and ns.Net.ImportPlaces(hazardId, Place({ x = 5, mob = "Other" }), false) == 0, "unknown tome or bad position ignored")
    Check(ns.Net.ImportPlaces(hazardId, Place({ mob = "Bandit", npcId = 7 }):gsub("%^Bandit%^", "^|cffff0000Bandit|r^"),
        false) == 0, "a place with an escape sequence is refused")
    local function State(at) return format("%.0f", at * 1000) end   -- a dataset state (Net.lua)
    Check(ns.Net.Accept("T" .. hazardId, State(time() + 60), State(time())) and not ns.Net.Accept("T" .. hazardId,
        State(time() + 3 * 86400), nil) and not ns.Net.Accept("X1", "5", nil) and not ns.Net.Accept("T" .. hazardId, "5", "9"),
        "datasets taken: ours, newer, not dated in the future")
    -- Greedy Scavenger drops at one spot, from several players: only the mobs killed every time remain
    local function Scav(by, list)
        return Place({ mob = false, npcId = false, by = by, finders = { [by] = true }, cands = list })
    end
    ns.DB.sightings = {}
    ns.Net.ImportPlaces(hazardId, Scav("Fay", { { npcId = 3113, name = "Razormane Dustrunner" },
        { npcId = 3114, name = "Razormane Battleguard" }, { npcId = 3111, name = "Razormane Quilboar" } }), false)
    local place = ns.DB.sightings[hazardId][1]
    Check(place and not place.mob and #place.cands == 3, "a Scavenger drop: the place with its 3 candidate mobs")
    ns.Net.ImportPlaces(hazardId, Scav("Gil", { { npcId = 3114, name = "Razormane Battleguard" },
        { npcId = 3111, name = "Razormane Quilboar" }, { npcId = 3112, name = "Razormane Hunter" } }), false)
    Check(#ns.DB.sightings[hazardId] == 1 and #place.cands == 2, "another drop there: the mobs killed both times remain")
    ns.Net.ImportPlaces(hazardId, Scav("Hal", { { npcId = 3111, name = "Razormane Quilboar" },
        { npcId = 3108, name = "Vile Familiar" } }), false)
    Check(place.mob == "Razormane Quilboar" and place.npcId == 3111 and place.inferred,
        "a third: one mob left, the place has its mob")
    Check(ns.WorldMap.MobsText(ns.Net.Locations(hazardId)[1]) == "Razormane Quilboar", "shown with its mob")
    ns.DB.sightings = kept
    ns.SetOption("netEnabled", true)
    ns.Fire("SIGHTINGS_CHANGED")
    Advance(2)
end

-- --- Network through EbonAPI (Siphelis: a separate addon, read where it is) --------------------
if not EbonAPI then
    Check(ns.Net.SyncState() == "noapi" and not ns.Net.Available(), "without EbonAPI: no network, the places stay here")
    Check(ChatContains(ns.L.NetNeedApi), "the player is told once to install EbonAPI")
    Check(not ns.Net.RequestStats(), "no statistics request without EbonAPI")
else
    local api = EbonAPI:NewAddon("EbonTomeHunter", 1, 0)
    local ownTomes = {}   -- (the tests below start again from these)
    for itemId in pairs(ns.DB.sightings) do ownTomes[itemId] = true end
    -- EbonAPI holds an announcement while it is still fetching (60 s), then compares again every
    -- 2 minutes: an exchange can take a few minutes. Waits up to `seconds` for cond().
    local function Until(seconds, cond)
        for _ = 1, seconds / 5 do
            if cond() then return true end
            Advance(5)
        end
        return cond() and true or false
    end
    local function Places(name, itemId)   -- places another player holds for a tome
        return tonumber(Peers.Run(name, "local s = EbonTomeHunterDB.sightings[" .. itemId .. "] return s and #s or 0"))
    end
    local function Share(name, dataset, text)   -- another player's EbonAPI publishes a dataset of ours
        return Peers.Run(name, "return EbonAPI:NewAddon('EbonTomeHunter', 1, 0):Share('" .. dataset .. "', "
            .. "(time() + 5) * 1000, " .. string.format("%q", text) .. ")")
    end
    Check(ns.Net.Available() and ns.Net.SyncState() == "online", "connected to EbonAPI, in its channel")
    Check(api:GetShared("T300569") and api:GetShared("T300569"):find("^300569%^CrystalsongForest%^490%^540%^28434%^Sinewy Wolf%^"),
        "our find is the dataset of its tome (T300569)")

    -- another EbonTomeHunter user comes online: our places reach him, his reach us
    Check(Peers.Start("Bob"), "Bob logs in")
    Advance(40)
    Check(Places("Bob", 300569) == 1, "Bob got our drop place through EbonAPI")
    local hazardId = ns.Catalog.byName["arcane hazard"].itemId
    ns.Wishlist.SetQty(hazardId, 1)
    Peers.Run("Bob", "EbonTomeHunter.Net.Report({ itemId = " .. hazardId .. ", mapFile = 'Tanaris', x = 0.512, y = 0.498, "
        .. "npcId = 5420, mob = 'Wastewander Bandit', zone = 'Tanaris:Wavestrider Beach', at = time(), by = 'Bob' })")
    Advance(40)
    local hazard = ns.Catalog.Get(hazardId)
    Check(ns.DB.sightings[hazardId] and #ns.DB.sightings[hazardId] == 1 and hazard.location and hazard.location.source == "net"
        and hazard.location.mapFile == "Tanaris", "Bob's find reached us: the catalogue places Arcane Hazard where he looted it")
    Check(ChatContains("Bob") and ChatContains("Wastewander Bandit"), "a wishlist tome found by another player: told in chat")
    ns.WorldMap.Locate(hazardId)
    Check(WorldMapFrame:IsShown() and shownMap == "Tanaris", "Locate now opens Tanaris")
    WorldMapFrame:Hide()

    -- permanent: Alice and Bob are never online together; Bob's find reaches her through Carol,
    -- who does not run EbonTomeHunter but another addon of EbonAPI (AutoCallboard, SkillTreeAutoLoad...):
    -- EbonAPI keeps and passes on the datasets of every addon
    Peers.Online("Tester", false)   -- we stay out of it
    Check(Peers.Start("Alice") and Peers.Start("Carol", "api"), "Alice logs in, Carol too (EbonAPI, no EbonTomeHunter)")
    Peers.Run("Carol", "EbonAPI:NewAddon('OtherAddon', 1, 0)")   -- (EbonAPI joins its channel for its addons)
    Advance(40)
    Check(Places("Alice", 300569) == 1, "Alice got our place from Bob")
    Check(Peers.Stop("Alice"), "Alice logs off")
    Peers.Run("Bob", "EbonTomeHunter.Net.Report({ itemId = 300446, mapFile = 'Durotar', x = 0.4, y = 0.5, npcId = 3099, "
        .. "mob = 'Dire Mottled Boar', zone = 'Durotar', at = time(), by = 'Bob' })")
    Advance(60)
    Check(Peers.Run("Carol", "return (EbonAPI:NewAddon('OtherAddon', 1, 0):GetShared('T300446', 'EbonTomeHunter'))")
        == Peers.Run("Bob", "return EbonTomeHunter.Net.PlacesText(300446)"), "Carol's EbonAPI holds Bob's find")
    Check(Peers.Stop("Bob"), "Bob logs off")
    Check(Peers.Start("Alice"), "Alice logs in again, Bob is gone")
    Check(Places("Alice", 300569) == 1 and Places("Alice", 300446) == 0, "Alice kept her places (saved data), no boar yet")
    Advance(60)
    Check(Places("Alice", 300446) == 1 and Peers.Run("Alice", "return EbonTomeHunterDB.sightings[300446][1].by") == "Bob",
        "Bob's find reached Alice through Carol: they were never online together")
    Peers.Online("Tester", true)
    Check(api:SyncShares(), "we log in again: EbonAPI announces what it holds")
    Advance(40)
    local boar = ns.DB.sightings[300446] and ns.DB.sightings[300446][1]
    Check(boar and boar.mob == "Dire Mottled Boar" and boar.by == "Bob", "back on the network, we have it too")
    Check(Peers.Start("Bob"), "Bob logs in again")
    Check(Places("Bob", 300446) == 1 and Places("Bob", 300569) == 1, "Bob kept his places between two sessions (saved data)")
    Advance(20)

    -- Scavenger drops of two players at one spot: merged on every client
    Peers.Run("Bob", "EbonTomeHunter.Net.Report({ itemId = 300447, mapFile = 'Barrens', x = 0.3, y = 0.3, zone = 'The Barrens', "
        .. "at = time(), by = 'Bob', cands = { { npcId = 3113, name = 'Razormane Dustrunner' }, "
        .. "{ npcId = 3111, name = 'Razormane Quilboar' } } })")
    Advance(40)
    ns.Net.Report({ itemId = 300447, mapFile = "Barrens", x = 0.31, y = 0.3, zone = "The Barrens", at = time(), by = "Tester",
        cands = { { npcId = 3111, name = "Razormane Quilboar" }, { npcId = 3108, name = "Vile Familiar" } } })
    Advance(40)
    local quilboar = ns.DB.sightings[300447] and ns.DB.sightings[300447][1]
    Check(quilboar and quilboar.mob == "Razormane Quilboar", "our Scavenger drop and Bob's: the only mob killed both times")
    Check(Until(180, function()
        return Peers.Run("Bob", "local s = EbonTomeHunterDB.sightings[300447] return s and s[1] and s[1].mob") == "Razormane Quilboar"
    end), "Bob deduced the same mob")

    -- two players publish different places of one tome in the same second (a group farming
    -- together): their states still differ, the one who takes the other's publishes the union
    Peers.Run("Bob", "EbonTomeHunter.Net.Report({ itemId = 300449, mapFile = 'Mulgore', x = 0.2, y = 0.2, npcId = 2956, "
        .. "mob = 'Adult Plainstrider', zone = 'Mulgore', at = time(), by = 'Bob' })")
    ns.Net.Report({ itemId = 300449, mapFile = "Mulgore", x = 0.7, y = 0.7, npcId = 2957, mob = "Elder Plainstrider",
        zone = "Mulgore", at = time(), by = "Tester" })
    Advance(90)
    Check(ns.DB.sightings[300449] and #ns.DB.sightings[300449] == 2 and Places("Bob", 300449) == 2,
        "published in the same second: both places on both clients")
    Check(api:GetShared("T300449") == Peers.Run("Bob", "return (EbonAPI:NewAddon('EbonTomeHunter', 1, 0):GetShared('T300449'))"),
        "and the same dataset text")

    -- evidence of stale sources travels the same way (dataset E<itemId>)
    Share("Bob", "E300569", "#4698^Lea^0^0^0^0^0^" .. time() .. "^" .. time() .. ";#4698^Max^0^0^0^0^0^" .. time()
        .. "^" .. time() .. ";#4698^Ned^0^0^0^0^0^" .. time() .. "^" .. time())
    Check(Until(180, function() return select(3, ns.Evidence.Verdict(300569, "Scarlet Paladins", 4698)) == 3 end),
        "3 players' reports reached us: the source is stale for everybody")

    -- a forged dataset (dated in the future) is not taken
    Peers.Run("Bob", "EbonTomeHunter.Net.Report({ itemId = 300448, mapFile = 'Mulgore', x = 0.5, y = 0.5, "
        .. "mob = 'Plainstrider', zone = 'Mulgore', at = time(), by = 'Bob' })")
    Peers.Run("Bob", "EbonAPI:NewAddon('EbonTomeHunter', 1, 0):Share('T300448', (time() + 3 * 86400) * 1000, "
        .. "EbonTomeHunter.Net.PlacesText(300448))")
    Advance(40)
    Check(not ns.DB.sightings[300448], "a dataset dated 3 days ahead is refused")

    -- kill statistics (asked by the developer helper): answered by the EbonTomeHunter users only
    ns.DB.killStats = { [29120] = { n = 7, name = "Test Mob" } }
    for i = 1, 30 do ns.DB.killStats[600600 + i] = { n = 12345 + i, name = "Custom " .. i } end
    local stats
    ns.On("NET_STATS", function(results) stats = results end)
    Check(ns.Net.RequestStats(), "statistics asked to the players online")
    Advance(20)
    Check(stats and stats.Bob and not stats.Carol, "Bob answered, Carol (no EbonTomeHunter) did not")
    Peers.Run("Bob", "EbonTomeHunter.On('NET_STATS', function(r) BobStats = r end) EbonTomeHunter.Net.RequestStats()")
    Advance(20)
    Check(Peers.Run("Bob", "local s = BobStats and BobStats.Tester local n = 0 for _ in pairs(s and s.kills or {}) do "
        .. "n = n + 1 end return n") == 31 and Peers.Run("Bob", "return BobStats.Tester.kills[29120]") == 7,
        "our 31 creatures reached Bob (a long answer: several lines, put together again by EbonAPI)")
    ns.DB.killStats = {}

    -- the network button of the main window
    if not EbonTomeHunterFrame:IsShown() then UI.Toggle() end
    local button = UI.syncButton
    UI.RefreshSync()
    Check(button:GetText() == ns.L.SyncOnline, "EbonAPI in its channel: 'Network'")
    local _, tip = UI.SyncTip()
    Check(tip:find(format(ns.L.SyncTipDatasets, ns.Net.DatasetCount()), 1, true) and ns.Net.DatasetCount() >= 4,
        "the tooltip counts the tomes shared")
    button:GetScript("OnClick")(button)
    Check(ChatContains(ns.L.NetSyncAsked), "the button announces our datasets now")
    Slash("/eth net sync")
    Check(ChatContains(ns.L.NetSyncWait), "again right away: EbonAPI waits 30 s")
    ns.SetOption("netEnabled", false)
    Check(button:GetText() == ns.L.SyncOff, "network off: 'Network off'")
    ns.SetOption("netEnabled", true)
    EbonTomeHunterFrame:Hide()
    Peers.Stop("Alice")
    Peers.Stop("Bob")
    Peers.Stop("Carol")
    -- the tests below start again from our own finds: the other players' places leave, and the
    -- datasets of these tests (EbonAPI keeps every dataset it received)
    for itemId in pairs(ns.DB.sightings) do
        if not ownTomes[itemId] then ns.DB.sightings[itemId] = nil end
    end
    for _, name in ipairs(api:SharedNames()) do
        if name ~= "T300569" then api:Unshare(name) end
    end
    ns.Fire("SIGHTINGS_CHANGED")
    Advance(2)
end

-- --- Stale sources (Evidence.lua) --------------------------------------------------------
local EV = ns.Evidence
local keptForEvidence = ns.DB.sightings
ns.DB.sightings = {}
shownMap = "CrystalsongForest"   -- (Locate may have left Tanaris)
ns.Fire("SIGHTINGS_CHANGED")
Advance(2)
ns.DB.corpses, ns.DB.evidence, ns.DB.reports = {}, {}, {}
local wolfKey = "300569@#28434"
local function LootCorpse(guidTail, withTome)
    unitState.target = { name = "Sinewy Wolf", guid = "0xF130006F1200" .. guidTail, dead = true }
    Fire("LOOT_OPENED")
    if withTome then Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300569, "Tome of Echo: Beast Bane"))) end
    Fire("LOOT_CLOSED")
    unitState.target = nil
    Advance(6)
end
LootCorpse("1001")
LootCorpse("1001")
Check(ns.DB.corpses[wolfKey] and ns.DB.corpses[wolfKey].n == 1,
    "a looted corpse of a listed source without the tome counts, once")
ns.DB.corpses[wolfKey].n = 98
LootCorpse("1002")
Check(EV.SharedText(300569) == "", "99 corpses without the tome: nothing worth sharing yet")
LootCorpse("1005")
do
    local text = EV.SharedText(300569)
    Check(text:find("#28434^Tester^100^", 1, true), "the counter is shared from 100 corpses: " .. text)
    if EbonAPI then
        Advance(3)
        Check(EbonAPI:NewAddon("EbonTomeHunter", 1, 0):GetShared("E300569") == text, "published as the dataset E300569")
    end
end
Check(not EV.Verdict(300569, "Sinewy Wolf", 28434), "100 corpses: still a good source")
do
    -- bad luck: the threshold follows the drop rate of the source (1 % left to bad luck)
    local _, _, _, _, oneIn, needed = EV.Verdict(300569, "Sinewy Wolf", 28434)
    Check(oneIn == 200 and needed == 919, "no drop seen yet: 1 in 200 assumed, stale past 919 corpses, got "
        .. tostring(oneIn) .. " / " .. tostring(needed))
    ns.DB.corpses[wolfKey].n = 600
    Check(not EV.Verdict(300569, "Sinewy Wolf", 28434), "600 corpses without the tome, rate unknown: bad luck possible")
    ns.DB.corpses[wolfKey].n = 919
    Check(EV.Verdict(300569, "Sinewy Wolf", 28434), "919 corpses without the tome: probably no longer drops it")
    -- a rare tome (1 drop in 3000 corpses before): 2000 corpses without it are still bad luck
    ns.DB.corpses[wolfKey] = { n = 2000, since = time(), drop = time() - 10, total = 5000, drops = 1 }
    local rareStale, _, _, _, rareOneIn, rareNeeded = EV.Verdict(300569, "Sinewy Wolf", 28434)
    Check(not rareStale and rareOneIn == 1600 and rareNeeded == EV.STALE_MAX, "rare tome: 2000 corpses are not enough")
    -- a frequent one (20 drops in 1000 corpses before): 500 corpses without it are not bad luck
    ns.DB.corpses[wolfKey] = { n = 500, since = time(), drop = time() - 10, total = 1500, drops = 20 }
    local staleNow, kills = EV.Verdict(300569, "Sinewy Wolf", 28434)
    Check(staleNow and kills == 500, "frequent tome: 500 corpses without it, probably no longer drops it")
end
local staleSeen, orderOk = false, true
for _, source in ipairs(ns.Travel.Sources(300569)) do
    if source.stale then staleSeen = true elseif staleSeen then orderOk = false end
end
Check(staleSeen and orderOk, "stale sources come last (teleport, Sources window)")
LootCorpse("1003", true)
Check(ns.DB.corpses[wolfKey].n == 0 and not EV.Verdict(300569, "Sinewy Wolf", 28434),
    "the tome drops from it again: counter back to 0, good source")
Check(ns.DB.corpses[wolfKey].drops == 21 and ns.DB.corpses[wolfKey].total == 1501,
    "the drop is kept in the history of the source (its rate)")

-- the tome lies in the corpse but is not taken (bags full, roll won by another player): it
-- dropped, the corpse is not one "without the tome", and the place is recorded all the same
ns.DB.corpses[wolfKey].n = 40
ns.DB.sightings[300569] = nil   -- a place the network does not know yet
GetNumLootItems = function() return 1 end
GetLootSlotLink = function(slot) return slot == 1 and Link(300569, "Tome of Echo: Beast Bane") or nil end
LootCorpse("1004")
GetNumLootItems, GetLootSlotLink = function() return 0 end, function() return nil end
Check(ns.DB.corpses[wolfKey].n == 0, "a tome left in the loot window counts as a drop, not a corpse without it")
Check(ns.DB.sightings[300569] and #ns.DB.sightings[300569] == 1, "and its drop place is recorded (for the network too)")

-- other players' counters (dataset E<itemId>): one weighs half the threshold at most; a later
-- drop clears them
ns.DB.corpses = {}
local nowEv = time()
local function Line(mob, player, n, since, drop, total, drops, report, stamp)
    return table.concat({ mob, player, n, since, drop, total, drops, report, stamp }, "^")
end
EV.ImportShared(300569, Line("#28434", "Hal", 900, nowEv, 0, 900, 0, 0, nowEv))
do
    local _, halKills, _, _, _, halNeeded = EV.Verdict(300569, "Sinewy Wolf", 28434)
    Check(halKills == halNeeded / 2 and not EV.Verdict(300569, "Sinewy Wolf", 28434),
        "a single other player cannot mark a source alone")
end
EV.ImportShared(300569, Line("#28434", "Ivy", 700, nowEv, 0, 700, 0, 0, nowEv))
Check(ns.DB.evidence[wolfKey].Ivy.total == 700, "the totals of another player's counter are kept")
Check(EV.Verdict(300569, "Sinewy Wolf", 28434), "two players with enough corpses: stale")
EV.ImportShared(300569, Line("#28434", "Kim", 3, nowEv + 30, nowEv + 30, 3, 1, 0, nowEv + 30))
Check(not EV.Verdict(300569, "Sinewy Wolf", 28434), "a drop reported after their counts: good source again")
EV.ImportShared(300569, Line("#28434", "Joe", 5, nowEv, 0, 5, 9, 0, nowEv))
Check(not ns.DB.evidence[wolfKey].Joe, "a counter with more drops than corpses is refused")
Check(ns.DB.evidence[wolfKey].Kim and not EV.SharedText(300569):find("^Kim^", 1, true),
    "a counter of few corpses is kept, but not passed on (its drop travels with the drop places)")
Check(EV.ImportShared(300569, "") and not EV.ImportShared(300569, EV.SharedText(300569)),
    "a dataset that knows less than we do is published again, one that says all we know is not")
do   -- EbonAPI takes 32 KB per dataset: past 30 000 bytes, the newest lines are kept
    local many = {}
    for source = 1, 40 do
        for player = 1, 20 do
            many[#many + 1] = Line("#" .. (70000 + source), "Player" .. player, 150, nowEv, 0, 150, 0, 0,
                nowEv - source * 100 - player)
        end
    end
    local sent = table.concat(many, ";")
    EV.ImportShared(300570, sent)
    local text = EV.SharedText(300570)
    Check(#sent > 30000 and #text <= 30000 and text:find("#70001^Player1^", 1, true)
        and not text:find("#70040^Player20^", 1, true), "a big dataset: under 30 000 bytes, the newest lines kept ("
        .. #sent .. " -> " .. #text .. " bytes)")
    Check(not EV.ImportShared(300570, text), "that text is the same on every client: not published again")
    Check(not EV.ImportShared(300570, text .. ";" .. Line("#70001", "Old", 3, nowEv, 0, 3, 0, 0, nowEv)),
        "a 3.x dataset with more lines than ours is not answered with a shorter one")
end

-- reports: 3 players, or the player alone for themselves; withdrawn from the Sources window
ns.DB.evidence, ns.DB.reports = {}, {}
local later = nowEv + 60
EV.ImportShared(300569, Line("#4698", "Lea", 0, 0, 0, 0, 0, later, later) .. ";" .. Line("#4698", "Max", 0, 0, 0, 0, 0, later, later))
Check(not EV.Verdict(300569, "Scarlet Paladins", 4698), "2 reports: not enough")
EV.ImportShared(300569, Line("#4698", "Ned", 0, 0, 0, 0, 0, later, later))
local byVotes, _, voters = EV.Verdict(300569, "Scarlet Paladins", 4698)
Check(byVotes and voters == 3, "3 players reported it: stale")
EV.ImportShared(300569, Line("#4698", "Ned", 0, 0, 0, 0, 0, 0, later + 1))
Check(not EV.Verdict(300569, "Scarlet Paladins", 4698), "a report withdrawn (a newer entry of that player)")
EV.ImportShared(300569, Line("#4698", "Ned", 0, 0, 0, 0, 0, later, later))
Check(not EV.Verdict(300569, "Scarlet Paladins", 4698), "an older entry of that player does not bring it back")
Check(EV.Report(300569, "Scarlet Paladins", 4698, true), "the player reports a source")
local mineStale, _, _, mine = EV.Verdict(300569, "Scarlet Paladins", 4698)
Check(mineStale and mine and EV.SharedText(300569):find("#4698%^Tester%^0%^%d+%^0%^0%^0%^[1-9]%d*%^%d+") ~= nil,
    "own report: stale for the player, in the dataset shared with the others")
Check(ns.Sources.Show(300569) > 0, "Sources window opened")
local reportRow
for i = 1, 6 do
    local r = _G["EbonTomeHunterSourcesListRow" .. i]
    if r and r:IsShown() and r.title:GetText() and r.title:GetText():find(format(ns.L.SourceStale, format(ns.L.StaleVotes, 3)), 1, true) then
        reportRow = r
    end
end
Check(reportRow ~= nil, "the Sources window greys the source, with the reason (Lea, Max and the player: 3 reports)")
if reportRow then reportRow.report:GetScript("OnClick")(reportRow.report) end
Advance(2)
Check(not EV.Verdict(300569, "Scarlet Paladins", 4698), "clicked again: report withdrawn")
EbonTomeHunterSourcesFrame:Hide()

-- network places: the most recent first, those not found for 90 days flagged
ns.Net.Add({ itemId = 300569, mapFile = "Tanaris", x = 0.1, y = 0.1, mob = "Old Mob", zone = "Tanaris",
    at = time() - 100 * 86400, by = "Pat" })
local netLocs = ns.Net.Locations(300569)
Check(netLocs and #netLocs >= 2 and not netLocs[1].old and netLocs[#netLocs].old and netLocs[1].at >= netLocs[#netLocs].at,
    "network places: most recent first, the old ones flagged")
Advance(4)
ns.DB.sightings = keptForEvidence
ns.DB.corpses, ns.DB.evidence, ns.DB.reports = {}, {}, {}
if EbonAPI then   -- EbonAPI keeps what these tests published: it leaves with them
    EbonAPI:NewAddon("EbonTomeHunter", 1, 0):Unshare("T300569")
    EbonAPI:NewAddon("EbonTomeHunter", 1, 0):Unshare("E300569")
    EbonAPI:NewAddon("EbonTomeHunter", 1, 0):Unshare("E300570")
end
ns.Fire("SIGHTINGS_CHANGED")
Advance(2)

-- --- Kill statistics (counted by Loot.lua, asked on the network by /ethdev stats) -------------
do
    ns.DB.killStats = {}
    local function Kill(guid, name)
        CLEU("SWING_DAMAGE", "0x0000000000000042", "Tester", 0x511, guid, name, 0xa48, 250)
        CLEU("UNIT_DIED", nil, nil, 0, guid, name, 0xa48)
    end
    Kill("0xF1300071C0000101", "Frost Wyrm")
    Kill("0xF1300071C0000102", "Frost Wyrm")
    CLEU("UNIT_DIED", nil, nil, 0, "0xF1300071C0000103", "Frost Wyrm", 0xa48)   -- not fought by us
    local wyrm = ns.Wowhead.NpcIdFromGUID("0xF1300071C0000101")
    local counted = ns.DB.killStats[wyrm]
    Check(counted and counted.n == 2 and counted.name == "Frost Wyrm",
        "kills per creature: the ones fought by the player or the group, counted")
    -- (asking the other players and their answers: see the EbonAPI tests above)
    Advance(61)   -- these kills must not count as the recent kills of the Scavenger tests
end

-- --- Drop history window (/eth history) ------------------------------------------------------
do
    local hazardId = ns.Catalog.byName["arcane hazard"].itemId
    for _, by in ipairs({ "Bob", "Carl" }) do   -- a place of another player, confirmed by a third one
        ns.Net.Add({ itemId = hazardId, mapFile = "Tanaris", x = 0.512, y = 0.498, npcId = 5420, mob = "Wastewander Bandit",
            zone = "Tanaris:Wavestrider Beach", at = time() - 60, by = by })
    end
    local entries = ns.History.Entries(false)
    local sorted, bob = true, nil
    for i, e in ipairs(entries) do
        if i > 1 and e.at > entries[i - 1].at then sorted = false end
        if e.by == "Bob" and e.itemId == hazardId then bob = e end
    end
    Check(#entries == ns.Net.Count() and sorted, "history: every shared drop, the most recent first")
    Check(bob and bob.mob == "Wastewander Bandit" and bob.others == 1 and bob.place:find("Tanaris", 1, true),
        "who (Bob, confirmed by 1 more player), where and which mob")
    local mine = ns.History.Entries(true)
    local onlyMine = #mine > 0
    for _, e in ipairs(mine) do
        if e.by ~= "Tester" then
            local r = ns.DB.sightings[e.itemId]
            onlyMine = onlyMine and r ~= nil
        end
    end
    Check(onlyMine and #mine < #entries, "'my finds only' keeps the player's finds")
    Slash("/eth history")
    Check(EbonTomeHunterHistoryFrame:IsShown() and EbonTomeHunterHistoryListRow1:IsShown()
        and (ns.History.countText:GetText() or ""):find(tostring(#entries), 1, true),
        "/eth history opens the window with its rows and count")
    local first = EbonTomeHunterHistoryListRow1
    Check(first.item and first.who:GetText() and first.where:GetText() and first.mob:GetText(), "a row shows who, where, mob")
    first:GetScript("OnClick")(first)
    Check(EbonTomeHunterSourcesFrame:IsShown(), "a click on a row opens the Sources of that tome")
    EbonTomeHunterSourcesFrame:Hide()
    ns.History.onlyMine:SetChecked(true)
    ns.History.onlyMine:GetScript("OnClick")(ns.History.onlyMine)
    Check((ns.History.countText:GetText() or ""):find(tostring(#mine), 1, true), "the box filters the list")
    ns.History.onlyMine:SetChecked(false)
    Slash("/eth history")
    Check(not EbonTomeHunterHistoryFrame:IsShown(), "the command closes it again")
    if not EbonTomeHunterFrame:IsShown() then UI.Toggle() end
    UI.historyButton:GetScript("OnClick")(UI.historyButton)
    Check(EbonTomeHunterHistoryFrame:IsShown(), "the History button of the main window opens it")
    EbonTomeHunterHistoryFrame:Hide()
    EbonTomeHunterFrame:Hide()
end

-- --- Raid tomes: Icecrown Citadel and Ruby Sanctum bosses (no EbonholdHub place) ------------
local defile = ns.Catalog.Get(301402)
local raidLoc = defile and defile.location
Check(raidLoc and raidLoc.source == "raid" and raidLoc.placeName == ns.L.RaidICC and raidLoc.mobs[1] == "The Lich King"
    and raidLoc.notes == ns.L.RaidGuess, "Defile: supposed source, the Lich King in Icecrown Citadel")
Check(ns.WorldMap.WorldPosition(raidLoc) ~= nil and ns.WorldMap.BestZone(raidLoc) == "IcecrownGlacier",
    "placed at the raid entrance on the Icecrown map")
local lichUrl, lichId = WH.LinkFor("The Lich King", raidLoc)
Check(lichId == 36597 and lichUrl and lichUrl:find("npc=36597", 1, true), "exact Wowhead link of the boss")
local gunship = ns.Travel.Sources(301348)
Check(#gunship == 2, "Gunship Barrage: the two gunship leaders")
local halion = ns.Catalog.Get(301428)
Check(halion and halion.location and halion.location.placeName == ns.L.RaidRS and halion.location.mobs[1] == "Halion",
    "Twilight Combustion: Halion in the Ruby Sanctum")
local raidCount = 0
for id in pairs(ns.Catalog.RAID_BOSSES) do
    if ns.Catalog.Get(id) then raidCount = raidCount + 1 end
end
Check(raidCount == 20, "the 20 raid tomes are all in the catalogue, got " .. raidCount)
Check(ns.Catalog.Get(300569).location.source ~= "raid", "a tome with EbonholdHub places keeps them")
Check(#ns.Travel.Sources(301370) == 3, "Shock Vortex: the three princes of the Blood Prince Council")

-- the server's hints (ProjectEbonhold.PerkDropSources, read in game)
if type(ProjectEbonhold) == "table" then
    local keptHints = ProjectEbonhold.PerkDropSources
    local lonely
    for _, row in ipairs(ns.Catalog.rows) do
        if not row.location and tonumber(row.itemId) then lonely = row break end
    end
    ProjectEbonhold.PerkDropSources = { [200569] = "Can be found on Beast-type enemies" }
    if lonely then ProjectEbonhold.PerkDropSources[lonely.itemId - 100000] = "Can be found on Test-type enemies" end
    Check(ns.Catalog.DropHint(ns.Catalog.Get(300569)) == "Can be found on Beast-type enemies",
        "the Echo journal hint of a tome is read (echo = tome id - 100000)")
    Check(ns.Sources.Show(300569) > 0 and (ns.Sources.hintText:GetText() or ""):find("Beast-type", 1, true) ~= nil,
        "the Sources window shows the hint")
    EbonTomeHunterSourcesFrame:Hide()
    if lonely then
        if not EbonTomeHunterFrame:IsShown() then UI.Toggle() end
        UI.searchBox:SetText(lonely.name)
        local placeText
        for i = 1, UI.VISIBLE_ROWS do
            local r = _G["EbonTomeHunterListRow" .. i]
            if r and r:IsShown() and r.item and r.item.itemId == lonely.itemId then placeText = r.place:GetText() end
        end
        Check(placeText and placeText:find("Test-type", 1, true), "a tome without place shows its hint instead of 'unknown'")
        UI.searchBox:SetText("")
        EbonTomeHunterFrame:Hide()
    end
    ProjectEbonhold.PerkDropSources = keptHints
else
    Check(ns.Catalog.DropHint(ns.Catalog.Get(300569)) == nil, "without ProjectEbonhold: no hint, no error")
end

-- a tome that no source lists at all says "unknown" in the list (it showed nothing)
local noPlace
for _, row in ipairs(ns.Catalog.rows) do
    if not row.location and row.itemId then noPlace = row break end
end
if not EbonTomeHunterFrame:IsShown() then UI.Toggle() end
if noPlace then
    UI.searchBox:SetText(noPlace.name)
    local shown
    for i = 1, UI.VISIBLE_ROWS do
        local r = _G["EbonTomeHunterListRow" .. i]
        if r and r:IsShown() and r.item and r.item.itemId == noPlace.itemId then shown = r.place:GetText() end
    end
    Check(shown and shown:find(ns.L.LocationUnknown, 1, true), "no place at all: 'unknown' shown for " .. noPlace.name)
    UI.searchBox:SetText("")
end
EbonTomeHunterFrame:Hide()

-- group loot of a wishlist tome
ns.Wishlist.SetQty(300570, 1)
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM, "Groupie", Link(300570, "Tome of Echo: DragonKin Bane")))
Check(ChatContains("Groupie"), "a group member looted a wishlist tome: told in chat")

-- network off: nothing leaves any more
shownMap = "CrystalsongForest"   -- the zone map of the zone texts (Locate had left Tanaris)
ns.SetOption("netEnabled", false)
local heldBefore = EbonAPI and EbonAPI:NewAddon("EbonTomeHunter", 1, 0):GetShared("T300569")
unitState.target = { name = "Sinewy Wolf", guid = "0xF130006F12000042", dead = true }
GetPlayerMapPosition = function(unit) return 0.20, 0.30 end
Fire("LOOT_OPENED")
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300569, "Tome of Echo: Beast Bane")))
Advance(4)
Check(#ns.DB.sightings[300569] == 2 and (not EbonAPI or EbonAPI:NewAddon("EbonTomeHunter", 1, 0):GetShared("T300569") == heldBefore),
    "network off: kept locally, not published")
ns.SetOption("netEnabled", true)
if EbonAPI then
    Advance(4)
    local _, count = EbonAPI:NewAddon("EbonTomeHunter", 1, 0):GetShared("T300569"):gsub("300569%^", "")
    Check(count == 2, "network on again: the find made meanwhile is published")
end
unitState.target = nil

-- the corpse under the mouse wins over the target
unitState.target = { name = "Sinewy Wolf", guid = "0xF130006F12000042", dead = true }
unitState.mouseover = { name = "Crystalline Ice Giant", guid = "0xF13000714B000007", dead = true }
GetPlayerMapPosition = function(unit) return 0.70, 0.70 end
Fire("LOOT_OPENED")
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300570, "Tome of Echo: DragonKin Bane")))
local drops570 = ns.DB.sightings[300570] or {}
Check(#drops570 == 1 and drops570[1].mob == "Crystalline Ice Giant" and drops570[1].npcId == 0x714B,
    "the corpse under the mouse is the source, not the target")
Fire("LOOT_CLOSED")
unitState.target, unitState.mouseover = nil, nil
-- an item won in a roll long after the window closed may come from another corpse
GetPlayerMapPosition = function(unit) return 0.10, 0.90 end
Advance(10)
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300570, "Tome of Echo: DragonKin Bane")))
Check(#ns.DB.sightings[300570] == 1, "tome received after the loot window closed: place not reported")
-- chest, or bag opened from the inventory (possibly in town): no dead mob
Fire("LOOT_OPENED")
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300570, "Tome of Echo: DragonKin Bane")))
Check(#ns.DB.sightings[300570] == 1, "loot without a dead mob (chest, bag): place not reported")
Fire("LOOT_CLOSED")
Advance(2)

-- Greedy Scavenger: the pet loots the corpses by itself and puts the items in the bags WITHOUT
-- any chat line: a tome appearing in the bags is detected; its mob = the kills of the last minute
local savedNumSlots, savedItemLink, savedItemInfo = GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo
local bagSlots = {}
GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end
GetContainerItemLink = function(bag, slot) return bag == 0 and bagSlots[slot] and bagSlots[slot].link or nil end
GetContainerItemInfo = function(bag, slot)
    local item = bag == 0 and bagSlots[slot]
    if item then return "Interface\\Icons\\INV_Misc_Book_09", item.count end
end
local alerts = {}
local realAlert = ns.Loot.Alert
ns.Loot.Alert = function(text)
    alerts[#alerts + 1] = text
    realAlert(text)
end
local function BagsChanged()
    Fire("BAG_UPDATE", 0)
    Advance(2)
end
local function Kill(guid, name)
    CLEU("SWING_DAMAGE", "0x0000000000000042", "Tester", 0x511, guid, name, 0xa48, 250)
    CLEU("UNIT_DIED", nil, nil, 0, guid, name, 0xa48)
end
Advance(6)                         -- the last loot window is long closed
shownMap = "CrystalsongForest"
GetPlayerMapPosition = function(unit) return 0.33, 0.44 end
BagsChanged()
Check(#alerts == 0, "first reading of the bags: nothing announced")

local wolfGUID = "0xF1300071BE000099"
CLEU("UNIT_DIED", nil, nil, 0, "0xF1300071C0000077", "Other Player's Kill", 0xa48)
Kill(wolfGUID, "Snowblind Wolf")
Advance(3)
ns.Wishlist.SetQty(300022, 1)
bagSlots[3] = { link = Link(300022, "Tome of Echo: Earthen Snap"), count = 1 }
BagsChanged()
Check(#alerts == 1 and alerts[1] == format(ns.L.AlertSelf, "Earthen Snap"),
    "Scavenger: wishlist tome appearing in the bags, alert without any chat line")
local scav = ns.DB.sightings[300022] and ns.DB.sightings[300022][1]
Check(scav and scav.mob == "Snowblind Wolf" and scav.npcId == tonumber("0071BE", 16) and scav.mapFile == "CrystalsongForest"
    and math.abs(scav.x - 0.33) < 0.001, "its drop place: the wolf just killed (not a mob we never fought), where we stand")

Kill("0xF1300071C0000012", "Frostbite Bear")
GetPlayerMapPosition = function(unit) return 0.60, 0.20 end
bagSlots[4] = { link = Link(300025, "Tome of Echo: Frost Bite"), count = 1 }
BagsChanged()
local mixed = ns.DB.sightings[300025] and ns.DB.sightings[300025][1]
Check(mixed and mixed.mob == nil and mixed.mapFile == "CrystalsongForest" and math.abs(mixed.x - 0.60) < 0.001,
    "two kinds of mobs killed in the last minute: the place, no mob")
Check(mixed and mixed.cands and #mixed.cands == 2 and mixed.cands[1].name == "Frostbite Bear"
    and mixed.cands[2].name == "Snowblind Wolf", "with the two candidates, the most recent kill first")
ns.Net.ImportPlaces(300025, ns.Net.Encode({ itemId = 300025, mapFile = "CrystalsongForest", x = 0.61, y = 0.21,
    npcId = tonumber("0071C0", 16), mob = "Frostbite Bear", zone = "Crystalsong Forest", at = time(), by = "Zed",
    finders = { Zed = true } }), false)
Check(#ns.DB.sightings[300025] == 1 and ns.DB.sightings[300025][1].mob == "Frostbite Bear",
    "a player who knows the mob confirms that spot: merged, the mob is now known")

-- several kinds of mobs killed, but only one is a known source of the tome: that one
Advance(61)
Kill("0xF130006F120000AB", "Sinewy Wolf")        -- a known source of Beast Bane
Kill("0xF1300071C00000AC", "Frostbite Bear")
GetPlayerMapPosition = function(unit) return 0.80, 0.80 end
bagSlots[12] = { link = Link(300569, "Tome of Echo: Beast Bane"), count = 1 }
BagsChanged()
local sourced
for _, r in ipairs(ns.DB.sightings[300569] or {}) do
    if r.x and math.abs(r.x - 0.80) < 0.001 then sourced = r end
end
Check(sourced and sourced.mob == "Sinewy Wolf" and sourced.npcId == 28434,
    "Scavenger after mixed kills: the only known source of the tome among them is its mob")
bagSlots[12] = nil
BagsChanged()
for i, r in ipairs(ns.DB.sightings[300569] or {}) do   -- leave the teleport tests as they were
    if r == sourced then table.remove(ns.DB.sightings[300569], i) break end
end
ns.Fire("SIGHTINGS_CHANGED")
Advance(2)

Advance(61)
bagSlots[5] = { link = Link(300436, "Tome of Echo: Shielded Steps"), count = 1 }
BagsChanged()
Check(ns.DB.sightings[300436] == nil, "nothing killed in the last minute: no drop place")

local mailbox = CreateFrame("Frame", "MailFrame")
mailbox:Show()
ns.Wishlist.SetQty(300437, 1)
local alertsBefore = #alerts
bagSlots[6] = { link = Link(300437, "Tome of Echo: Steady Casting"), count = 1 }
BagsChanged()
mailbox:Hide()
BagsChanged()
Check(#alerts == alertsBefore and ns.DB.sightings[300437] == nil, "a tome taken from the mailbox is not loot")

Advance(11)
unitState.mouseover = { name = "Snowblind Wolf", guid = wolfGUID, dead = true }
Fire("LOOT_OPENED")
ns.Wishlist.SetQty(300438, 1)
alertsBefore = #alerts
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300438, "Tome of Echo: Subtle Presence")))
bagSlots[7] = { link = Link(300438, "Tome of Echo: Subtle Presence"), count = 1 }
BagsChanged()
Fire("LOOT_CLOSED")
unitState.mouseover = nil
Check(#alerts == alertsBefore + 1, "looted by hand: the chat line and the bag increase make one alert, got "
    .. (#alerts - alertsBefore))

-- several kinds of mobs killed: the server's hint of the tome tells which one (Hints.lua)
do
    local HT = ns.Hints
    local frost = HT.Parse("Can be found on enemies that cast Frostbolt / Slow")
    Check(frost and frost.spells.frostbolt and frost.spells.slow, "hint 'enemies that cast ...': the spells to watch")
    Check((HT.Parse("Can be found on Beast-type enemies (Paladin, Warrior)") or {}).ctype == "beast",
        "hint 'Beast-type enemies': the creature type")
    local boss = HT.Parse("Can be found on Lord Marrowgar")
    Check(boss and boss.names and boss.names["lord marrowgar"], "hint naming a creature: its name")
    local fire = HT.Parse("Can be found on Fire Elemental-type enemies")
    Check(fire and fire.ctype == "elemental" and #fire.words > 0, "hint 'Fire Elemental-type enemies': elementals, fire words")
    Check(HT.Parse("Can be found on enemies with high armor") == nil, "a hint with nothing to observe: no test")

    -- stand-in hints (in game they come from ProjectEbonhold's Echo journal)
    local savedHint = ns.Catalog.DropHint
    local hints = { [300450] = "Can be found on enemies that cast Frostbolt / Slow",
        [300508] = "Can be found on Beast-type enemies (Paladin, Warrior)",
        [300509] = "Can be found on Fire Elemental-type enemies" }
    ns.Catalog.DropHint = function(row)
        return row and hints[row.itemId] or savedHint(row)
    end
    GetPlayerMapPosition = function(unit) return 0.45, 0.55 end

    -- a mob seen casting a spell of the hint (combat log)
    Advance(61)
    Kill("0xF1300071BE0000C1", "Snowblind Wolf")
    CLEU("SPELL_CAST_SUCCESS", "0xF1300077AB0000C2", "Crystalsong Frostcaller", 0xa48, "0x0000000000000042", "Tester",
        0x511, 116, "Frostbolt")
    Kill("0xF1300077AB0000C2", "Crystalsong Frostcaller")
    bagSlots[9] = { link = Link(300450, "Tome of Echo: Insulated Soul"), count = 1 }
    BagsChanged()
    local byCast = ns.DB.sightings[300450] and ns.DB.sightings[300450][1]
    Check(byCast and byCast.mob == "Crystalsong Frostcaller" and byCast.npcId == 0x77AB,
        "Scavenger: the mob seen casting a spell of the tome's hint dropped it")

    -- the creature types shown by the nameplates (the Ebonhold client gives them units)
    Advance(61)
    local savedType = UnitCreatureType
    UnitCreatureType = function(unit) return unitState[unit] and unitState[unit].ctype or nil end
    unitState.nameplate1 = { name = "Crystal Spider", guid = "0xF1300077AC0000D1", ctype = "Beast" }
    unitState.nameplate2 = { name = "Ice Revenant", guid = "0xF1300077AD0000D2", ctype = "Elemental" }
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    unitState.nameplate1, unitState.nameplate2 = nil, nil
    Kill("0xF1300077AD0000D3", "Ice Revenant")
    Kill("0xF1300077AC0000D4", "Crystal Spider")
    bagSlots[10] = { link = Link(300508, "Tome of Echo: Ember Ward"), count = 1 }
    BagsChanged()
    local byType = ns.DB.sightings[300508] and ns.DB.sightings[300508][1]
    Check(byType and byType.mob == "Crystal Spider", "Scavenger: the only beast killed dropped the 'Beast-type' tome")
    UnitCreatureType = savedType

    -- a weak clue only (a word of the name): not enough, the candidates go with the place
    Advance(61)
    Kill("0xF1300077AE0000E1", "Blazing Ember")
    Kill("0xF1300077AF0000E2", "Crystalsong Wisp")
    bagSlots[11] = { link = Link(300509, "Tome of Echo: Frost Ward"), count = 1 }
    BagsChanged()
    local unsure = ns.DB.sightings[300509] and ns.DB.sightings[300509][1]
    Check(unsure and not unsure.mob and unsure.cands and #unsure.cands == 2 and unsure.cands[1].name == "Blazing Ember",
        "a weak clue only: no mob, both candidates kept, the likeliest first")
    Check(ns.WorldMap.MobsText(ns.Net.Locations(300509)[1]) == format(ns.L.SourceCandidates, "Blazing Ember / Crystalsong Wisp"),
        "shown as 'one of' the candidates")
    ns.Catalog.DropHint = savedHint
    bagSlots[9], bagSlots[10], bagSlots[11] = nil, nil, nil
    BagsChanged()
    ns.DB.sightings[300450], ns.DB.sightings[300508], ns.DB.sightings[300509] = nil, nil, nil
    ns.Fire("SIGHTINGS_CHANGED")
    Advance(2)
end

Fire("PLAYER_ENTERING_WORLD")
Kill(wolfGUID, "Snowblind Wolf")
ns.Wishlist.SetQty(300439, 1)
alertsBefore = #alerts
bagSlots[8] = { link = Link(300439, "Tome of Echo: Provoking Presence"), count = 1 }
BagsChanged()
Check(#alerts == alertsBefore, "just after a loading screen the bags are read again: nothing announced")
ns.Loot.Alert = realAlert
GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo = savedNumSlots, savedItemLink, savedItemInfo

-- --- Teleport: nearest checkpoint to the mobs (ProjectEbonhold checkpoints) ------------------
local T = ns.Travel
local usedCheckpoints, listRequests, dismounts = {}, 0, 0
Dismount = function() dismounts = dismounts + 1 end
IsMounted = function() return false end
IsFlying = function() return false end
WorldMapFrame:Hide()
shownMap = "Elwynn"                      -- the player is far away, in Elwynn Forest
GetPlayerMapPosition = function(unit) return 0.5, 0.5 end
-- real definitions of ProjectEbonhold (checkpoint_service.lua), plus states and factions
local CHECKPOINTS = {
    { id = 66, name = "Chillwind Camp, Western Plaguelands", mapId = 23, serverMapId = 0, x = 0.42948, y = 0.84954, factionAllowed = true, unlocked = true },
    { id = 383, name = "Thondoril River, Western Plaguelands", mapId = 23, serverMapId = 0, x = 0.69206, y = 0.49679, factionAllowed = true, unlocked = false },
    { id = 67, name = "Light's Hope Chapel, Eastern Plaguelands", mapId = 24, serverMapId = 0, x = 0.7574078, y = 0.5332380, factionAllowed = true, unlocked = true },
    { id = 68, name = "Light's Hope Chapel, Eastern Plaguelands", mapId = 24, serverMapId = 0, x = 0.7440347, y = 0.5122817, factionAllowed = false, unlocked = true },
    { id = 336, name = "Windrunner's Overlook, Crystalsong Forest", mapId = 511, serverMapId = 571, x = 0.7211788, y = 0.8081377, factionAllowed = true, unlocked = true },
    { id = 310, name = "Dalaran", mapId = 511, serverMapId = 571, x = 0.3652774, y = 0.3792568, factionAllowed = true, unlocked = true },
    { id = 39, name = "Gadgetzan, Tanaris", mapId = 162, serverMapId = 1, x = 0.5095420, y = 0.2932543, factionAllowed = true, unlocked = true },
    { id = 10019, name = "Zul'Farrak", mapId = 162, serverMapId = 1, x = 0.3857, y = 0.2066, factionAllowed = true, unlocked = true, kind = "MEETINGSTONE" },
    { id = 10019, name = "Zul'Farrak", mapId = 202, serverMapId = 1, x = 0.9225, y = 0.3481, factionAllowed = true, unlocked = true, kind = "MEETINGSTONE" },
    { id = 83, name = "Tranquillien, Ghostlands", mapId = 464, serverMapId = 530, x = 0.4548355, y = 0.3055438, factionAllowed = true, unlocked = true },
}
local function RowOf(itemId)
    ns.UI.Show(itemId)
    for _, row in ipairs(ns.UI.list.rows) do
        if row:IsShown() and row.item and row.item.itemId == itemId then return row end
    end
end
if ProjectEbonhold then
    ProjectEbonhold.CheckpointService = {
        GetCheckpoints = function() return CHECKPOINTS end,
        UseCheckpoint = function(id) usedCheckpoints[#usedCheckpoints + 1] = id end,
        RequestCheckpoints = function() listRequests = listRequests + 1 end,
    }
    local count = {}
    for _, c in ipairs(T.Checkpoints()) do count[c.id] = (count[c.id] or 0) + 1 end
    Check(count[68] == nil, "checkpoints of the other faction left out")
    Check(count[10019] == 1, "a meeting stone listed on two zone maps counts once")
    Check(count[310] == 1 and count[39] == 1 and count[83] == 1, "checkpoints placed on their continent (Ghostlands too)")

    -- one place: the nearest unlocked checkpoint, and a nearer one still locked
    local hearthglen
    for _, loc in ipairs(ns.Catalog.Get(300569).locations) do
        if loc.placeName == "Hearthglen" then hearthglen = loc end
    end
    local near = T.Nearest(hearthglen)
    Check(near and near.checkpoint and near.checkpoint.id == 66, "Hearthglen: Chillwind Camp, nearest unlocked checkpoint")
    Check(near and near.locked and near.locked.id == 383 and near.lockedDistance < near.distance,
        "a nearer checkpoint not unlocked yet is reported (Thondoril River)")

    -- several sources (Hearthglen, Crystalsong...): the one seen dropping it (our loot in
    -- Crystalsong Forest) comes first, via its nearest checkpoint
    local best, sources = T.Best(300569)
    Check(#sources >= 3 and best and best.near.checkpoint.id == 310 and (best.drops or 0) >= 1,
        "Beast Bane: the source seen dropping it, via Dalaran, got " .. tostring(best and best.near.checkpoint.id))
    Check(sources[#sources].near == nil, "sources without a position come last")

    -- a drop found in Ghostlands (zone drawn on the Eastern Kingdoms map, on map 530)
    ns.Net.Add({ itemId = 300570, mapFile = "Ghostlands", x = 0.47, y = 0.33, mob = "Mummified Headhunter",
        zone = "Ghostlands", at = time(), by = "Elfy" })
    ns.Fire("SIGHTINGS_CHANGED")
    Advance(1)
    local ghost = T.Best(300570)
    Check(ghost and ghost.near.checkpoint.id == 83 and ghost.near.distance < 150,
        "Ghostlands drop: Tranquillien, a few steps away")

    -- the list button teleports at once (no confirmation by default: the player's choice)
    local baneRow = RowOf(300569)
    Check(baneRow and baneRow.travel:IsEnabled(), "teleport button enabled on the tome's row")
    baneRow.travel:GetScript("OnEnter")(baneRow.travel)
    GameTooltip:Hide()
    baneRow.travel:GetScript("OnClick")(baneRow.travel)
    Check(usedCheckpoints[1] == 310 and ChatContains("Dalaran"), "one click: teleport to Dalaran")
    T.GoBest(300569)
    Check(#usedCheckpoints == 1 and ChatContains(ns.L.TravelWait), "a second request right after is ignored")
    Advance(4)

    IsMounted = function() return true end
    T.GoBest(300569)
    Check(dismounts == 1 and usedCheckpoints[2] == 310, "mounted on the ground: dismounted first")
    IsMounted = function() return false end
    Advance(4)

    Player.combat = true
    Check(not T.GoBest(300569) and #usedCheckpoints == 2 and ChatContains(ns.L.TravelCombat), "no teleport in combat")
    Player.combat = false

    -- standing next to the mobs: the list button does not teleport, the Sources window does
    shownMap = "CrystalsongForest"
    GetPlayerMapPosition = function(unit) return 0.49, 0.54 end
    Check(not T.GoBest(300569) and #usedCheckpoints == 2, "already closer than any checkpoint: no teleport")
    Check(ns.Sources.Show(300569) >= 3 and EbonTomeHunterSourcesFrame:IsShown(), "Sources window")
    local first = EbonTomeHunterSourcesListRow1
    Check(first.item and first.item.near.checkpoint.id == 310 and first.tp:IsEnabled() and first.item.you
        and first.item.you < 150, "first source: Dalaran, with the player's own distance")
    first.tp:GetScript("OnClick")(first.tp)
    Check(usedCheckpoints[3] == 310, "Sources window: teleports even when already close")
    Advance(4)
    local lockedShown = false
    for _, row in ipairs(EbonTomeHunterSourcesList.rows) do
        if row:IsShown() and row.item and not row.item.near then
            Check(not row.tp:IsEnabled(), "a source without a position has no teleport")
        end
        if row:IsShown() and row.item and row.item.near and row.item.near.checkpoint then lockedShown = true end
    end
    Check(lockedShown, "sources listed with their checkpoints")
    EbonTomeHunterSourcesFrame:Hide()
    shownMap = "Elwynn"
    GetPlayerMapPosition = function(unit) return 0.5, 0.5 end

    -- confirmation (option)
    ns.SetOption("confirmTeleport", true)
    local asked
    local popupSaved = StaticPopup_Show
    StaticPopup_Show = function(which, a1, a2, data)
        asked = { which = which, a1 = a1, a2 = a2, data = data }
        return CreateFrame("Frame")
    end
    T.GoBest(300569)
    Check(asked and asked.which == "EBONTOMEHUNTER_TRAVEL" and asked.a1 == "Dalaran" and #usedCheckpoints == 3,
        "option on: asks before teleporting")
    StaticPopupDialogs.EBONTOMEHUNTER_TRAVEL.OnAccept(nil, asked.data)
    Check(usedCheckpoints[4] == 310, "accepted: teleport")
    StaticPopup_Show = popupSaved
    ns.SetOption("confirmTeleport", false)
    Advance(4)

    -- map marker: Ctrl-click teleports near that very place
    ShowUIPanel(WorldMapFrame)
    ns.WorldMap.Invalidate()
    ShowMap("WesternPlaguelands")
    local hearthPin
    for _, pin in ipairs(ShownPins()) do
        if pin._etp.itemId == 300569 and pin._etp.loc == hearthglen then hearthPin = pin end
    end
    Check(hearthPin ~= nil, "Hearthglen marker shown for the wishlist tome")
    if hearthPin then
        IsControlKeyDown = function() return true end
        hearthPin:GetScript("OnClick")(hearthPin)
        IsControlKeyDown = function() return nil end
        Check(usedCheckpoints[5] == 66 and not WorldMapFrame:IsShown(), "Ctrl-click on the marker: Chillwind Camp")
    end
    Advance(4)

    -- /eth tp <tome>
    Slash("/eth tp beast bane")
    Check(usedCheckpoints[6] == 310, "/eth tp <tome name>")
    Advance(4)
    Slash("/eth tp bane")
    Check(ChatContains("Beast Bane") and #usedCheckpoints == 6, "several tomes match: listed, no teleport")
    Slash("/eth tp zzzz")
    Check(ChatContains(format(ns.L.TravelUnknownTome, "zzzz")), "unknown tome")

    -- nothing unlocked in Northrend: the next best source; nothing unlocked at all: list asked again
    for _, c in ipairs(CHECKPOINTS) do
        if c.serverMapId == 571 then c.unlocked = false end
    end
    best = T.Best(300569)
    Check(best and best.near.checkpoint.id == 66, "Northrend locked: Hearthglen via Chillwind Camp")
    for _, c in ipairs(CHECKPOINTS) do c.unlocked = false end
    Check(not T.GoBest(300569) and listRequests == 1 and ChatContains(ns.L.TravelNoData),
        "nothing unlocked (list not received?): asked again")
    for _, c in ipairs(CHECKPOINTS) do c.unlocked = true end

    -- the most farmed source first: a place inside Black Temple found by 2 players (the map of
    -- the instance: no world map point) beats the listed places nobody saw drop the tome;
    -- the teleport aims at the raid's meeting stone
    do
        CHECKPOINTS[#CHECKPOINTS + 1] = { id = 10028, name = "Black Temple", mapId = 474, serverMapId = 530,
            x = 0.6445, y = 0.4670, factionAllowed = true, unlocked = true, kind = "MEETINGSTONE_RAID" }
        local places = ns.DB.sightings[300569]
        local count = #places
        for _, by in ipairs({ "Zyn", "Kor" }) do
            ns.Net.Add({ itemId = 300569, mapFile = "BlackTemple", x = 0.534, y = 0.756, zone = "Black Temple:Temple Summit",
                npcId = 22917, mob = "Illidan Stormrage", at = time(), by = by })
        end
        ns.Net.Add({ itemId = 300569, mapFile = "Tanaris", x = 0.3, y = 0.3, mob = "Old Mob", zone = "Tanaris",
            at = time() - 100 * 86400, by = "Pat", n = 9 })
        ns.Fire("SIGHTINGS_CHANGED")
        Advance(1)
        local main = ns.Catalog.Get(300569).location
        Check(main and main.mobs and main.mobs[1] == "Illidan Stormrage" and main.drops == 2 and not main.onMap,
            "the place seen dropping it the most (2 players) comes first, even without a map point")
        local farmed = T.Best(300569)
        Check(farmed and farmed.mob == "Illidan Stormrage" and farmed.near.entrance and farmed.near.checkpoint.id == 10028,
            "teleport: to it, at the meeting stone of Black Temple (its entrance)")
        Check(T.Sources(300569)[1].mob == "Illidan Stormrage", "first in the Sources window too")
        Check(ns.Sources.Show(300569) > 0 and (EbonTomeHunterSourcesListRow1.title:GetText() or ""):find(
            format(ns.L.SourceDrops, 2), 1, true), "with the drops seen there")
        EbonTomeHunterSourcesFrame:Hide()
        local oldFirst = false
        for i, loc in ipairs(ns.Catalog.Get(300569).locations) do
            if loc.mobs and loc.mobs[1] == "Old Mob" and i == 1 then oldFirst = true end
        end
        Check(not oldFirst, "a place not found for 90 days does not lead, even confirmed by 9 players")
        -- the corpses counted by Evidence.lua also count: 3 drops seen on the Scarlet Paladins
        ns.DB.corpses["300569@#4698"] = { n = 0, since = time(), drop = time(), total = 30, drops = 3, stamp = time() }
        ns.Fire("SIGHTINGS_CHANGED")
        Advance(1)
        Check(ns.Catalog.Get(300569).location.placeName == "Hearthglen" and T.Best(300569).mob == "Scarlet Paladins",
            "3 drops counted on a listed source: it leads again")
        ns.DB.corpses = {}
        for i = #places, count + 1, -1 do table.remove(places, i) end
        table.remove(CHECKPOINTS)
        ns.Fire("SIGHTINGS_CHANGED")
        Advance(1)
    end
else
    Check(not T.Available() and not T.GoBest(300569) and ChatContains(ns.L.TravelNoPE), "without ProjectEbonhold: no teleport")
    local baneRow = RowOf(300569)
    Check(baneRow and not baneRow.travel:IsEnabled(), "without ProjectEbonhold: teleport button disabled")
    Check(ns.Sources.Show(300569) >= 3 and not EbonTomeHunterSourcesListRow1.tp:IsEnabled(), "Sources: no TP either")
    EbonTomeHunterSourcesFrame:Hide()
end

-- --- EbonBuilds' Tome Atlas (its saved data, read where it is, never written) ------------------
do
    local SEP = string.char(31)   -- EbonBuilds' separator between the mob and the zone
    EbonBuildsDB = {
        tomeAtlas = {
            [300450] = { name = "Tome of Echo: Insulated Soul", sources = {
                ["Venture Co. Shredder" .. SEP .. "Stonetalon Mountains"] = 12,
                ["Unknown" .. SEP .. "Stonetalon Mountains"] = 2,
                ["Ignis the Furnace Master" .. SEP .. "Ulduar"] = 5,
                ["Sandfury Hideskinner" .. SEP .. "Tanaris"] = 3,
                ["Bad|cffff0000Mob" .. SEP .. "Durotar"] = 1,
            } },
            [300569] = { name = "Tome of Echo: Beast Bane", sources = { ["Sinewy Wolf" .. SEP .. "Crystalsong Forest"] = 4 } },
        },
        tomeAtlasPinCoords = { ["Stonetalon Mountains"] = { ["Tome of Echo: Insulated Soul"] = { x = 0.6, y = 0.4, n = 3 } } },
    }
    Advance(61)   -- (EbonBuilds records drops while we play: its atlas is read again when it changes)
    local function AtlasPlaces(itemId)
        local out = {}
        for _, loc in ipairs(ns.WorldMap.Locations(ns.Catalog.Get(itemId))) do
            if loc.source == "atlas" then out[loc.mobs and loc.mobs[1] or "?"] = loc end
        end
        return out
    end
    local atlas = AtlasPlaces(300450)
    local shredder, ignis = atlas["Venture Co. Shredder"], atlas["Ignis the Furnace Master"]
    Check(shredder and shredder.mapFile == "StonetalonMountains" and shredder.onMap and shredder.count == 12
        and math.abs(shredder.x - 0.6) < 0.001, "EbonBuilds atlas: the zone map, and the point EbonBuilds noted")
    Check(ignis and not ignis.onMap and ignis.placeName == "Ulduar", "a raid source: its place, no map point")
    Check(not atlas["?"], "a source without mob, in a zone another source gives: left out")
    Check(atlas["Badcffff0000Mob"] and not atlas["Bad|cffff0000Mob"], "no escape sequence taken from its data")
    Check(next(AtlasPlaces(300569)) == nil, "a mob another source of the tome lists already: not repeated")
    Check(ns.Hints.KnownSources(300450)["venture co. shredder"], "its mobs are known sources (Greedy Scavenger)")
    Check(ns.Sources.Show(300450) > 0, "Sources window of the tome")
    local told = false
    for i = 1, 8 do
        local r = _G["EbonTomeHunterSourcesListRow" .. i]
        if r and r:IsShown() and (r.title:GetText() or ""):find(format(ns.L.SourceAtlas, 12), 1, true) then told = true end
    end
    Check(told, "the Sources window tells the atlas and how many drops it saw")
    EbonTomeHunterSourcesFrame:Hide()
    if T.Available() then
        local near = atlas["Sandfury Hideskinner"] and T.Nearest(atlas["Sandfury Hideskinner"])
        Check(near and near.approx and near.checkpoint and near.checkpoint.id == 39,
            "only its zone known: the teleport aims at the middle of Tanaris (Gadgetzan)")
        Check(T.FormatDistance(120, true) == "~" .. format(ns.L.TravelYards, 120), "an approximate distance shows '~'")
    end
    EbonBuildsDB = nil
    Advance(61)
    Check(next(AtlasPlaces(300450)) == nil, "EbonBuilds gone: its sources too")
end

-- --- Sending a wishlist to a player (addon whisper) ------------------------------------------
local addonSent = {}
SendAddonMessage = function(prefix, msg, chatType, target)
    addonSent[#addonSent + 1] = { prefix = prefix, msg = msg, chatType = chatType, target = target }
end
Check(not ns.Comm.SendWishlist(""), "no name: nothing sent")
Check(not ns.Comm.SendWishlist("tester"), "not to oneself")
Check(ns.Comm.SendWishlist("bob"), "wishlist sent to Bob")
Advance(1)
local wl = addonSent[1]
Check(wl and wl.prefix == "ETH" and wl.chatType == "WHISPER" and wl.target == "Bob"
    and wl.msg:find("^WL:%x+:1:1:ETH1:Tester:") ~= nil, "whisper addon message to Bob: " .. tostring(wl and wl.msg))
local sendId = wl and wl.msg:match("^WL:(%x+):")
Fire("CHAT_MSG_ADDON", "ETH", "WLA:" .. tostring(sendId) .. ":3", "WHISPER", "Bob")
Check(ChatContains(format(ns.L.SendDelivered, "Bob", 3)), "Bob's addon confirmed")
ns.Comm.SendWishlist("Carl")
Advance(13)
Check(ChatContains(format(ns.L.SendNoAnswer, "Carl")), "no answer: told after a while")

-- receiving one (in two slices)
local offer
local popupBefore = StaticPopup_Show
StaticPopup_Show = function(which, a1, a2, data)
    offer = { which = which, from = a1, count = a2, data = data }
    return CreateFrame("Frame")
end
local incoming = ns.Share.Encode({ { itemId = 300022, qty = 2 }, { itemId = 300569, qty = 1 } }, "Dave")
addonSent = {}
Fire("CHAT_MSG_ADDON", "ETH", "WL:beef:1:2:" .. incoming:sub(1, 10), "WHISPER", "Dave")
Check(offer == nil, "waits for every slice")
Fire("CHAT_MSG_ADDON", "ETH", "WL:beef:2:2:" .. incoming:sub(11), "WHISPER", "Dave")
Check(offer and offer.which == "EBONTOMEHUNTER_WISHLIST_OFFER" and offer.from == "Dave" and offer.count == 2,
    "offer shown when the wishlist is complete")
Advance(1)
Check(addonSent[1] and addonSent[1].msg == "WLA:beef:2" and addonSent[1].target == "Dave", "reception confirmed to Dave")
StaticPopupDialogs.EBONTOMEHUNTER_WISHLIST_OFFER.OnAccept(nil, offer.data)
Check(EbonTomeHunterShareFrame:IsShown() and ns.Share.importBox:GetText() == incoming,
    "View: the share dialog opens with Dave's wishlist ready to import")
Check((ns.Share.previewText:GetText() or ""):find("Dave", 1, true) ~= nil, "its preview")
EbonTomeHunterShareFrame:Hide()
ns.SetOption("receiveWishlists", false)
offer, addonSent = nil, {}
Fire("CHAT_MSG_ADDON", "ETH", "WL:f00d:1:1:" .. incoming, "WHISPER", "Eve")
Advance(1)
Check(offer == nil and addonSent[1] and addonSent[1].msg == "WLN:f00d", "option off: refused politely")
ns.SetOption("receiveWishlists", true)
local floodOffers = 0
StaticPopup_Show = function() floodOffers = floodOffers + 1 return CreateFrame("Frame") end
for i = 1, 5 do
    Fire("CHAT_MSG_ADDON", "ETH", format("WL:%04x:1:1:%s", i, incoming), "WHISPER", "Spammer")
end
Check(floodOffers == 3, "at most 3 offers a minute from the same player, got " .. floodOffers)
StaticPopup_Show = popupBefore
Slash("/eth send Bob")
Slash("/eth net")
Check(ChatContains(ns.Net.StatusText():sub(1, 12)), "/eth net prints the network status")
Check(EbonTomeHunterNetPanel ~= nil, "network options sub-panel registered")
for _, item in ipairs(ns.Wishlist.List()) do ns.Wishlist.Remove(item.itemId) end

EbonholdHub = nil
ns.Catalog.Build()

-- --- Auction House tabs: search and buy ------------------------------------------------------
AuctionFrame:Show()
-- Blizzard_AuctionUI is load-on-demand: the tabs appear with its ADDON_LOADED.
AuctionFrameTab_OnClick = function(self) AuctionFrame.selectedTab = self:GetID() end
Fire("ADDON_LOADED", "Blizzard_AuctionUI")
local AH = ns.AH
local tomesTab, wishTab = AH.tabs.tomes, AH.tabs.wish
Check(tomesTab and tomesTab:GetID() == 4 and AuctionFrameTab4 == tomesTab, "Tomes tab added after Blizzard's three tabs")
Check(wishTab and wishTab:GetID() == 5 and AuctionFrameTab5 == wishTab, "Wishlist tab is the fifth")
AuctionFrameTab_OnClick(tomesTab)
Check(EbonTomeHunterAHPanel:IsShown() and AH.mode == "tomes", "clicking the Tomes tab shows the panel")
Check(AuctionFrame.selectedTab == 4, "Blizzard's tab handler still runs (tab selected)")
AuctionFrameTab_OnClick(AuctionFrameTab1)
Check(not EbonTomeHunterAHPanel:IsShown() and AH.mode == nil, "another tab hides the panel")
AuctionFrameTab_OnClick(tomesTab)

local function Auction(count, buyout, owner, bid)
    return { name = "Tome of Echo: Beast Bane", count = count, buyout = buyout, owner = owner, bid = bid or 0,
             link = Link(300569, "Tome of Echo: Beast Bane") }
end
local AH_PAGE = {
    Auction(1, 120000, "Seller1"),
    Auction(2, 160000, "Seller2"),          -- 80000 per tome: cheapest that we can buy
    Auction(1, 0, "Seller3", 50000),        -- bid only
    Auction(1, 70000, "Tester"),            -- ours (UnitName("player") == "Tester")
}
GetNumAuctionItems = function() return #AH_PAGE, #AH_PAGE end
GetAuctionItemInfo = function(list, i)
    local a = AH_PAGE[i]
    if not a then return nil end
    return a.name, "", a.count, 3, true, 80, a.bid, 100, a.buyout, 0, nil, a.owner
end
GetAuctionItemLink = function(list, i) return AH_PAGE[i] and AH_PAGE[i].link end
GetAuctionItemTimeLeft = function() return 4 end
local bids = {}
PlaceAuctionBid = function(list, index, amount) bids[#bids + 1] = { list = list, index = index, amount = amount } end
GetMoney = function() return 10000000 end
local queries = {}
QueryAuctionItems = function(name, _, _, _, _, _, page) queries[#queries + 1] = { name = name, page = page } end

-- click Beast Bane in the tome list
local baneRow
for i = 1, 20 do
    local row = _G["EbonTomeHunterAHTomesRow" .. i]
    if row and row.item and row.item.itemId == 300569 then baneRow = row end
end
Check(baneRow ~= nil, "Beast Bane is in the Tomes tab list (listed at the last scan)")
if baneRow then baneRow:GetScript("OnClick")(baneRow, "LeftButton") end
Check(#queries == 1 and queries[1].name == "Tome of Echo: Beast Bane" and queries[1].page == 0,
    "clicking a tome searches its exact name")
Fire("AUCTION_ITEM_LIST_UPDATE")
local result = ns.Scan.Results(300569)
Check(result and #result.listings == 4, "4 Beast Bane listings found")
Check(result and result.listings[1].unit == 70000 and result.listings[4].buyout == 0,
    "listings sorted by unit price, bid-only last")
Check(ns.Prices.GetMin(300569) == 70000, "the search updates the saved price")
local chosen = AH.selectedListing
Check(chosen and chosen.owner == "Seller2" and chosen.count == 2, "the cheapest listing that is not ours is preselected")
Check(EbonTomeHunterAHListingsRow1:IsShown() and EbonTomeHunterAHListingsRow4:IsShown(), "listings shown on the right")

-- safety checks
Check(not ns.Buy.Check(result.listings[1]), "cannot buy our own auction")
Check(not ns.Buy.Check(result.listings[4]), "cannot buy a bid-only auction")
GetMoney = function() return 100 end
Check(not ns.Buy.Check(chosen), "not enough gold: refused")
GetMoney = function() return 10000000 end

-- buy the preselected listing: confirmation first
ns.Wishlist.SetQty(300569, 3)
local popup
StaticPopup_Show = function(which, a1, a2, data)
    popup = { which = which, text = a1, data = data }
    return CreateFrame("Frame")
end
EbonTomeHunterAHBuy:GetScript("OnClick")(EbonTomeHunterAHBuy)
Check(popup and popup.which == "EBONTOMEHUNTER_BUY" and popup.data == chosen, "Buy asks for a confirmation first")
Check(#bids == 0, "nothing bought before the confirmation")
StaticPopupDialogs.EBONTOMEHUNTER_BUY.OnAccept(nil, popup.data)
Check(#bids == 1 and bids[1].list == "list" and bids[1].index == 2 and bids[1].amount == 160000,
    "buyout placed on the right auction at the right price")
Fire("CHAT_MSG_SYSTEM", ERR_AUCTION_BID_PLACED)
Check(ns.Wishlist.Get(300569) and ns.Wishlist.Get(300569).qty == 1, "the 2 bought tomes are deducted from the wishlist (3 -> 1)")
Check(ChatContains("x2"), "purchase reported in chat")
Check(ns.Buy.pending == nil, "purchase settled")
local stillThere = false
for _, listing in ipairs(ns.Scan.Results(300569).listings) do
    if listing == chosen then stillThere = true end
end
Check(not stillThere, "the bought listing leaves the list")

-- the page changed under our feet: never buy another auction than the one shown
local seller1
for _, listing in ipairs(ns.Scan.Results(300569).listings) do
    if listing.owner == "Seller1" then seller1 = listing end
end
AH_PAGE[1].buyout = 999999
ns.Buy.Execute(seller1)
Check(#bids == 1, "a changed auction is not bought")
Check(ns.Scan.IsBusy(), "the tome is searched again instead")
AH_PAGE[1].buyout = 120000
Fire("AUCTION_ITEM_LIST_UPDATE")
Check(not ns.Scan.IsBusy(), "list refreshed")

-- another query replaced the list (Browse tab): the page is loaded again before buying
ns.Scan.loaded = nil
queries = {}
popup = nil
ns.Buy.Request(seller1)
Check(#queries == 1 and queries[1].page == 0, "its page is loaded again first")
Fire("AUCTION_ITEM_LIST_UPDATE")
Check(popup and popup.data and popup.data.owner == "Seller1", "then the purchase is confirmed")
StaticPopupDialogs.EBONTOMEHUNTER_BUY.OnAccept(nil, popup.data)
Check(#bids == 2 and bids[2].index == 1 and bids[2].amount == 120000, "and it is bought")
Fire("UI_ERROR_MESSAGE", ERR_NOT_ENOUGH_MONEY)
Check(ns.Buy.pending == nil and ns.Wishlist.Get(300569).qty == 1, "a server error cancels it (wishlist untouched)")
Check(ns.Scan.IsBusy(), "and the tome is searched again")
Fire("AUCTION_ITEM_LIST_UPDATE")

-- no confirmation when the option is off
ns.SetOption("confirmBuy", false)
popup = nil
local seller1b
for _, listing in ipairs(ns.Scan.Results(300569).listings) do
    if listing.owner == "Seller1" then seller1b = listing end
end
ns.Buy.Request(seller1b)
Check(popup == nil and #bids == 3, "option off: bought at once")
Fire("CHAT_MSG_SYSTEM", ERR_AUCTION_BID_PLACED)
Check(not ns.Wishlist.Has(300569), "wishlist quantity reached: the tome leaves the wishlist")
ns.SetOption("confirmBuy", true)

-- Wishlist tab: search every wished tome in turn
ns.Wishlist.Add(300569, 1)
ns.Wishlist.Add(300570, 1)
AuctionFrameTab_OnClick(wishTab)
Check(AH.mode == "wish" and EbonTomeHunterAHPanel:IsShown(), "Wishlist tab shows the panel in wishlist mode")
queries = {}
Check(AH.SearchWishlist() == 2, "two wishlist tomes queued")
Fire("AUCTION_ITEM_LIST_UPDATE")
Fire("AUCTION_ITEM_LIST_UPDATE")
Check(#queries == 2 and queries[1].name ~= queries[2].name, "each wishlist tome searched in turn")
Check(not ns.Scan.IsBusy(), "all searches done")
Check(ns.Scan.Results(300570) and #ns.Scan.Results(300570).listings == 0, "a tome with nothing for sale gets an empty result")

-- closing the AH stops everything
ns.Scan.SearchMany({ 300569, 300570 })
Fire("AUCTION_HOUSE_CLOSED")
Check(not ns.Scan.IsBusy(), "closing the Auction House cancels the searches")

-- options: tabs can be removed
ns.SetOption("ahTabs", false)
Check(not tomesTab:IsShown() and not wishTab:IsShown(), "option off: tabs hidden")
ns.SetOption("ahTabs", true)
Check(tomesTab:IsShown(), "option on: tabs back")

Slash("/eth")
Slash("/eth rebuild")
Note("EbonTomeHunter scenario: " .. ns.Catalog.Count() .. " tomes, " .. ns.Prices.PricedCount() .. " priced")
