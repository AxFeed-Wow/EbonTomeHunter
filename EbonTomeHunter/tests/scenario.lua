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
Check(ns.Catalog.fromTomeData == true, "catalogue built from TomeData.lua")
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

local links = WH.Links(300569)
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
links = WH.Links(300569)
local exact = false
for _, link in ipairs(links) do
    if link.url == "https://www.wowhead.com/wotlk/npc=4698/scarlet-paladins" then exact = true end
end
Check(exact, "the learned id gives an exact NPC link")
local opened
EbonholdOpenURL = function(url) opened = url end
Check(WH.Show(300569) >= 2 and EbonTomeHunterSourcesFrame:IsShown(), "Sources window opened (Wowhead links, teleports)")
local sourceRow = EbonTomeHunterSourcesListRow1
Check(sourceRow and sourceRow:IsShown() and sourceRow.wowhead:IsShown(), "a source row with its Wowhead button")
sourceRow.wowhead:GetScript("OnClick")(sourceRow.wowhead)
Check(opened and opened:find("^https://www%.wowhead%.com/wotlk/") ~= nil, "Wowhead opens a WotLK page: " .. tostring(opened))
EbonTomeHunterSourcesFrame:Hide()
local customUrl, customId, isCustom = WH.LinkFor("Echo Wraith", { npcIds = { ["Echo Wraith"] = 190001 } })
Check(customUrl == nil and customId == 190001 and isCustom, "a creature made for Ebonhold (id 190001) gets no Wowhead link")
for _, link in ipairs(WH.Links(300569)) do
    Check(not link.url:find("item=", 1, true), "never an item page (Ebonhold tomes are not on Wowhead)")
end

-- --- Loot: wishlist alert, drop place shared with the network --------------------------------
local sentChat = {}
SendChatMessage = function(msg, chatType, language, channel)
    sentChat[#sentChat + 1] = { msg = msg, chatType = chatType, channel = channel }
end
GetChannelName = function(id)
    if id == "ebontomehunter" or id == 5 then return 5, "ebontomehunter" end
    return 0, nil
end
GetRealZoneText = function() return "Crystalsong Forest" end
GetSubZoneText = function() return "Forlorn Woods" end
GetPlayerMapPosition = function(unit) return 0.49, 0.54 end
WorldMapFrame:Hide()
shownMap = "CrystalsongForest"
ns.Net.Join()
for _, item in ipairs(ns.Wishlist.List()) do ns.Wishlist.Remove(item.itemId) end
ns.Wishlist.SetQty(300569, 1)

unitState.target = { name = "Sinewy Wolf", guid = "0xF130006F12000042", dead = true }
Fire("LOOT_OPENED")
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300569, "Tome of Echo: Beast Bane")))
Check(ChatContains(format(ns.L.AlertSelf, "Beast Bane")), "alert: wishlist tome looted")
local mine = ns.DB.sightings[300569] and ns.DB.sightings[300569][1]
Check(mine and mine.mapFile == "CrystalsongForest" and mine.npcId == 28434 and mine.mob == "Sinewy Wolf"
    and math.abs(mine.x - 0.49) < 0.001, "drop place recorded (zone map, position, mob)")
Advance(1)
local sentDrop = sentChat[#sentChat]
Check(sentDrop and sentDrop.chatType == "CHANNEL" and sentDrop.channel == 5
    and sentDrop.msg:find("^ETHN1~D~300569%^CrystalsongForest%^490%^540%^28434%^Sinewy Wolf%^") ~= nil,
    "drop sent on the hidden channel: " .. tostring(sentDrop and sentDrop.msg))
Check(WH.NpcId("Sinewy Wolf") == 28434, "the looted mob's id is learned too")
Check(#ns.DB.netOutbox == 1, "no other user online: the find also waits in the outbox")
unitState.target = nil

-- a tome listed as "Unknown location": another user drops it -> real place for everybody
local hazardRow = ns.Catalog.byName["arcane hazard"]
Check(hazardRow and not ns.WorldMap.WorldPosition(hazardRow.location), "Arcane Hazard has no map point yet")
local function ChannelMessage(text, author)
    Fire("CHAT_MSG_CHANNEL", text, author, "", "5. ebontomehunter", "", "", 0, 5, "ebontomehunter")
end
local found = ns.Net.Encode({ itemId = hazardRow.itemId, mapFile = "Tanaris", x = 0.512, y = 0.498, npcId = 5420,
    mob = "Wastewander Bandit", zone = "Tanaris:Wavestrider Beach", at = time(), by = "Bob" })
ns.Wishlist.SetQty(hazardRow.itemId, 1)
before = #sentChat
ChannelMessage("ETHN1~D~" .. found, "Bob")
Check(ChatContains("Bob") and ChatContains("Wastewander Bandit"), "wishlist tome found by another user: told in chat")
Advance(2)
local resent = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~S~0~0~300569%^CrystalsongForest%^") then resent = true end
end
Check(resent and #ns.DB.netOutbox == 0, "a user shows up: the find made alone is sent again, outbox emptied")
Check(hazardRow.location and hazardRow.location.mapFile == "Tanaris" and hazardRow.location.source == "net",
    "the catalogue now places Arcane Hazard where Bob looted it")
local hzFile, _, hzx, hzy = ns.WorldMap.BestZone(hazardRow.location)
Check(hzFile == "Tanaris" and math.abs(hzx - 0.512) < 0.001, "its zone and coordinates")
ns.WorldMap.Locate(hazardRow.itemId)
Check(WorldMapFrame:IsShown() and shownMap == "Tanaris", "Locate now opens Tanaris")
WorldMapFrame:Hide()
ChannelMessage("ETHN1~D~" .. found:gsub("%^Bob%^", "^Carl^"), "Carl")
Advance(2)
Check(#ns.DB.sightings[hazardRow.itemId] == 1 and hazardRow.location.notes:find("2", 1, true) ~= nil,
    "same spot from a second player: confirmed, not duplicated")
ChannelMessage("ETHN1~D~399999^Tanaris^500^500^^Bandit^Tanaris^" .. time() .. "^Eve", "Eve")
ChannelMessage("ETHN1~D~" .. hazardRow.itemId .. "^Tanaris^5000^500^^Bandit^Tanaris^" .. time() .. "^Eve", "Eve")
Advance(2)
Check(ns.DB.sightings[399999] == nil and #ns.DB.sightings[hazardRow.itemId] == 1, "unknown tome or bad position ignored")
Fire("CHAT_MSG_CHANNEL", "ETHN1~D~" .. found, "Mallory", "", "1. General", "", "", 0, 1, "General")
Check(#ns.DB.sightings[hazardRow.itemId] == 1, "other channels are ignored")

-- sync: a user who comes online asks what they missed; the first to answer wins
local before = #sentChat
ChannelMessage("ETHN1~Q~ab12^0", "Newbie")
Advance(8)
local answered = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~S~ab12~") then answered = true end
end
Check(answered, "sync request answered with the known drops")
before = #sentChat
ChannelMessage("ETHN1~Q~cd34^0", "Newbie2")
ChannelMessage("ETHN1~S~cd34~0~" .. found, "Dan")
Advance(8)
local duplicate = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~S~cd34~") then duplicate = true end
end
Check(not duplicate, "no answer when another user already answered")
ns.DB.lastSync = 0
Check(ns.Net.RequestSync() and not ns.Net.RequestSync(), "sync request, then a 10 min cooldown")
Advance(6)

-- names are cut to a byte length, never in the middle of a French character
local function ZoneField(zone)
    return ({ strsplit("^", ns.Net.Encode({ itemId = 300569, zone = zone, at = time() })) })[7]
end
local eAcute = string.char(195, 169)   -- "é" in UTF-8
Check(ZoneField(string.rep("a", 59) .. eAcute) == string.rep("a", 59), "a 2-byte character is not cut in two")
Check(ZoneField(string.rep("a", 58) .. eAcute) == string.rep("a", 58) .. eAcute, "a character that fits is kept")

-- large backlog: answered oldest first, 30 at a time, with the "more" flag
-- (catalogue rows of tomes whose item id is still unknown are keyed by name: skipped)
local tomeIds = {}
for _, row in ipairs(ns.Catalog.rows) do
    if type(row.itemId) == "number" then tomeIds[#tomeIds + 1] = row.itemId end
end
local keptSightings = ns.DB.sightings
ns.DB.sightings = {}
local base = time() - 5000
for i = 1, 35 do
    ns.Net.Add({ itemId = tomeIds[i], mapFile = "Durotar", x = 0.5, y = 0.5, mob = "Mob" .. i,
        zone = "Durotar", at = base + i, by = "P" .. i })
end
before = #sentChat
ChannelMessage("ETHN1~Q~ef56^" .. (base + 2), "Newbie3")
Advance(10)
local times, flags, inOrder = {}, {}, true
for i = before + 1, #sentChat do
    local more, body = sentChat[i].msg:match("^ETHN1~S~ef56~(%d)~(.*)$")
    if body then
        flags[more] = true
        for encoded in body:gmatch("[^;]+") do
            local record = ns.Net.Decode(encoded)
            times[#times + 1] = record and (record.at - base) or -1
            if times[#times] ~= #times + 2 then inOrder = false end
        end
    end
end
Check(#times == 30 and inOrder and flags["1"] and not flags["0"],
    "backlog: the 30 oldest after the asked time, in order, flagged 'more' (" .. #times .. " sent)")

-- our own request: asks again from the last record received while there are more
ns.DB.syncFrom, ns.DB.lastSync, ns.DB.syncedAt = nil, 0, 0
before = #sentChat
Check(ns.Net.RequestSync(), "sync requested")
Advance(1)
-- the last sync request sent after message n° `from` (other messages, like the version
-- announcement, may follow it); waits for it: messages waiting in the queue go first
local function LastQ(from)
    for _ = 1, 40 do
        for i = #sentChat, (from or 0) + 1, -1 do
            local q, s = sentChat[i].msg:match("^ETHN1~Q~(%x+)%^(%d+)$")
            if q then return q, s end
        end
        Advance(1)
    end
end
local qid, since = LastQ(before)
Check(qid and #qid == 5 and tonumber(since) == 0, "never synced: asks for everything (2.1.0 request)")
local function Rec(i, at)
    return ns.Net.Encode({ itemId = tomeIds[i], mapFile = "Barrens", x = 0.3, y = 0.3,
        mob = "Quilboar", zone = "The Barrens", at = at, by = "Vet" })
end
ChannelMessage("ETHN1~S~" .. qid .. "~1~" .. Rec(40, base + 100), "Vet")
ChannelMessage("ETHN1~S~" .. qid .. "~1~" .. Rec(41, base + 101), "Vet")
local afterAnswers = #sentChat
Advance(6)
local qid2, since2 = LastQ(afterAnswers)
Check(qid2 and tonumber(since2) == base + 101 and ns.DB.syncFrom == base + 101,
    "more to come: asks again from the last record received, kept for the next login")
ChannelMessage("ETHN1~S~" .. qid2 .. "~0~" .. Rec(42, base + 102), "Vet")
Advance(6)
Check(ns.DB.syncFrom == nil and #ns.DB.sightings[tomeIds[42]] == 1 and ns.DB.syncedAt > 0,
    "answer complete: up to date")
Check(ChatContains(format(ns.L.NetSynced, 3)), "the sync tells how many places it brought")
ns.DB.sightings = keptSightings
ns.Fire("SIGHTINGS_CHANGED")

-- 2.1.0: sync by time learned, answers completed by every user, what the asker adds
keptSightings = ns.DB.sightings
ns.DB.sightings = {}
local now = time()
local oldFind = { itemId = tomeIds[1], mapFile = "Durotar", x = 0.2, y = 0.2, mob = "Boar", zone = "Durotar",
    at = now - 5 * 86400, by = "Old", rx = now - 60 }
ns.Net.Add(oldFind)
local function SentFor(qidPattern, from)
    local out = {}
    for i = from + 1, #sentChat do
        local body = sentChat[i].msg:match("^ETHN1~S~" .. qidPattern .. "~[01]~(.*)$")
        if body then
            for encoded in body:gmatch("[^;]+") do out[#out + 1] = (ns.Net.Decode(encoded)) end
        end
    end
    return out
end
before = #sentChat
ChannelMessage("ETHN1~Q~a0000^" .. (now - 3600), "Ann")
ChannelMessage("ETHN1~Q~a001^" .. (now - 3600), "Ann")
Advance(8)
Check(#SentFor("a0000", before) == 1, "2.1.0 request: a find of 5 days ago learned a minute ago is sent")
Check(#SentFor("a001", before) == 0, "2.0.0 request: by time found, as before")

local second = { itemId = tomeIds[2], mapFile = "Durotar", x = 0.4, y = 0.4, mob = "Scorpid", zone = "Durotar",
    at = now - 100, by = "Mia", rx = now - 50 }
ns.Net.Add(second)
before = #sentChat
ChannelMessage("ETHN1~Q~b0000^0", "Ben")
ChannelMessage("ETHN1~S~b0000~0~" .. ns.Net.Encode(oldFind), "Cid")
Advance(8)
local complement = SentFor("b0000", before)
Check(#complement == 1 and complement[1].itemId == tomeIds[2],
    "another user answered first: only what the answer lacked is sent")
before = #sentChat
ChannelMessage("ETHN1~Q~c0000^0", "Ben")
ChannelMessage("ETHN1~S~c0000~0~" .. ns.Net.Encode(oldFind) .. ";" .. ns.Net.Encode(second), "Cid")
Advance(8)
Check(#SentFor("c0000", before) == 0, "the answer already said everything: silent")

ns.DB.syncFrom, ns.DB.lastSync, ns.DB.syncedAt = nil, 0, now - 3600
before = #sentChat
Check(ns.Net.RequestSync(), "sync requested (last complete sync an hour ago)")
Advance(1)
local q3, s3 = LastQ(before)
Check(q3 and tonumber(s3) == now - 3600 - 600, "asks what was learned since the last complete sync, minus a margin")
local fromDee = ns.Net.Encode({ itemId = tomeIds[3], mapFile = "Mulgore", x = 0.5, y = 0.5, mob = "Plainstrider",
    zone = "Mulgore", at = now - 30, by = "Dee" })
ChannelMessage("ETHN1~S~" .. q3 .. "~0~" .. ns.Net.Encode(oldFind) .. ";" .. fromDee, "Dee")
Advance(8)
local added = SentFor("0", before)
Check(#added == 1 and added[1].itemId == tomeIds[2], "then the asker sends what it knew and nobody said")
Check(ns.DB.syncedAt >= now and ns.DB.syncFrom == nil, "sync complete: noted for the next one")

-- our sync went unanswered: asked again as soon as a user shows up
ns.DB.syncFrom, ns.DB.lastSync, ns.DB.syncedAt = nil, 0, 0
Check(ns.Net.RequestSync(), "sync requested with nobody answering")
Advance(75)
before = #sentChat
ChannelMessage("ETHN1~D~" .. fromDee, "Gus")
Advance(7)
local reasked = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~Q~%x%x%x%x%x%^") then reasked = true end
end
Check(reasked, "a user showed up after an unanswered sync: asked again")

-- places sent without a request: stored, no wishlist alert (they are not new finds)
ns.Wishlist.SetQty(tomeIds[4], 1)
ChannelMessage("ETHN1~S~0~0~" .. ns.Net.Encode({ itemId = tomeIds[4], mapFile = "Tanaris", x = 0.6, y = 0.6,
    mob = "Hyena", zone = "Tanaris", at = now - 7200, by = "Fay" }), "Fay")
Advance(2)
Check(ns.DB.sightings[tomeIds[4]] and #ns.DB.sightings[tomeIds[4]] == 1 and not ChatContains("Fay"),
    "pushed place stored without an alert")
ns.Wishlist.Remove(tomeIds[4])

-- the status tells whether the hidden channel is really joined
local realChannelName = GetChannelName
GetChannelName = function() return 0, nil end
Check(ns.Net.StatusText():find(ns.L.NetNoChannel, 1, true) ~= nil and not ns.Net.IsJoined(),
    "channel refused by the game: the status says so")
GetChannelName = realChannelName
Check(ns.Net.StatusText():find(ns.L.NetOn, 1, true) ~= nil and ns.Net.IsJoined(), "in the channel: connected")

do
-- /eth net check: who has the same data
local myDigest = ns.Net.Digest()
local myPlaces = ns.Net.Count()
before = #sentChat
ChannelMessage("ETHN1~H~r^e0000", "Omar")
ChannelMessage("ETHN1~H~r^e0000", "Omar")
Advance(4)
local checkAnswers = {}
for i = before + 1, #sentChat do
    local version, digest = sentChat[i].msg:match("^ETHN1~H~a%^e0000%^([^%^]+)%^%d+%^%d+%^(%x+)%^%d+%^%d+$")
    if version then checkAnswers[#checkAnswers + 1] = { version = version, digest = digest } end
end
Check(#checkAnswers == 1 and checkAnswers[1].version == ns.version and checkAnswers[1].digest == myDigest,
    "a check request is answered once, with our version and fingerprint")
before = #sentChat
Slash("/eth net check")
Advance(1)
local checkQid
for i = before + 1, #sentChat do checkQid = checkQid or sentChat[i].msg:match("^ETHN1~H~r%^(%x+)$") end
Check(checkQid ~= nil and ChatContains(ns.L.NetCheckStart), "/eth net check asks the users online")
ChannelMessage("ETHN1~H~a^" .. checkQid .. "^2.2.0^" .. myPlaces .. "^3^" .. myDigest, "Pia")
ChannelMessage("ETHN1~H~a^" .. checkQid .. "^2.2.0^9^7^abcdef", "Quin")
Advance(7)
Check(ChatContains(format(ns.L.NetCheckSame, "Pia", "2.2.0", myPlaces, "-", 0)), "same fingerprint: in sync")
Check(ChatContains(format(ns.L.NetCheckDiff, "Quin", "2.2.0", 9, "-", 0, myPlaces, "Quin")) and ChatContains(ns.L.NetCheckHint),
    "different fingerprint: told, with the command to fix it")
Check(ChatContains(ns.L.NetCheckSilent:match("^(.-)%%s")) and ChatContains("Gus"),
    "users heard recently who did not answer are listed (older version)")
Slash("/eth net check")
Check(ChatContains(ns.L.NetCheckWait), "a second check right away: wait")

-- /eth net sync: everything again, right away, just for the player
ns.DB.lastSync = time()
before = #sentChat
Slash("/eth net sync")
Advance(1)
local fullAsked = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~Q~%x%x%x%x%x%^0$") then fullAsked = true end
end
Check(fullAsked and ChatContains(ns.L.NetSyncFull), "/eth net sync asks for everything, even within the 10 min")
end
Advance(15)

do
-- /eth net compare: another user asks for our places (the test character is "Tester")
before = #sentChat
ChannelMessage("ETHN1~H~d^f0000^Tester", "Rex")
ChannelMessage("ETHN1~H~d^f0001^Somebody", "Rex")
Advance(3)
local ourKeys, notForUs = {}, false
for i = before + 1, #sentChat do
    local keys = sentChat[i].msg:match("^ETHN1~H~k%^f0000%^%d+%^%d+%^%d+%^%d+%^(.*)$")
    if keys then for key in keys:gmatch("[^,]+") do ourKeys[#ourKeys + 1] = key end end
    if sentChat[i].msg:find("^ETHN1~H~k%^f0001") then notForUs = true end
end
Check(#ourKeys == ns.Net.Count() and not notForUs, "asked for our places: all their short keys sent, only when we are named")
-- we compare with Sam: one place in common, one we lack
local lacking
for i = #tomeIds, 1, -1 do
    if not ns.DB.sightings[tomeIds[i]] then lacking = tomeIds[i] break end
end
Slash("/eth net compare Sam")
Advance(1)
local cq
for i = before + 1, #sentChat do cq = cq or sentChat[i].msg:match("^ETHN1~H~d%^(%x+)%^Sam$") end
Check(cq ~= nil and ChatContains(format(ns.L.NetCompareStart, "Sam")), "/eth net compare asks that user")
ChannelMessage("ETHN1~H~k^" .. cq .. "^1^1^4^" .. time() .. "^" .. ourKeys[1] .. "," .. (lacking - 300000) .. ".1", "Sam")
Advance(1)
Check(ChatContains(format(ns.L.NetCompareHead, "Sam", 2, 4, ns.L.JustNow, #ourKeys)), "the comparison: their places, finds, latest")
Check(ChatContains(format(ns.L.NetCompareTheyHave, 1, ns.Catalog.Get(lacking).name)), "what they have that we don't")
Check(ChatContains(ns.L.NetCompareYouHave:match("^(.-)%%d")), "what we have that they don't")
Advance(31)
Slash("/eth net compare Nobody")
Advance(13)
Check(ChatContains(format(ns.L.NetCompareNoAnswer, "Nobody")), "nobody answers: said so")

-- addon versions: a newer one is announced, a forged one ignored, an older user told
local major, minor = ns.version:match("^(%d+)%.(%d+)")
local newer = major .. "." .. (tonumber(minor) + 1) .. ".0"
ChannelMessage("ETHN1~I~99.0.0", "Troll")
Check(ns.Net.NewerVersion() == nil and not ChatContains("99.0.0"), "a forged far-away version is ignored")
ChannelMessage("ETHN1~I~" .. newer, "Uma")
Check(ChatContains(format(ns.L.NewVersion, newer, ns.version)) and ns.Net.NewerVersion() == newer,
    "a user with a newer addon: the player is told to update")
before = #sentChat
ChannelMessage("ETHN1~I~2.0.0", "Vic")
Advance(6)
local toldVic = false
for i = before + 1, #sentChat do
    if sentChat[i].msg == "ETHN1~I~" .. ns.version then toldVic = true end
end
Check(toldVic, "a user with an older addon: we tell it our version")
before = #sentChat
ChannelMessage("ETHN1~I~2.0.0", "Wes")
ChannelMessage("ETHN1~I~" .. ns.version, "Xan")
Advance(6)
local toldWes = false
for i = before + 1, #sentChat do
    if sentChat[i].msg == "ETHN1~I~" .. ns.version then toldWes = true end
end
Check(not toldWes, "another user already told it: we stay silent")
end

-- "Up to date" button of the main window, and the automatic sync every 15 min
do
    if not EbonTomeHunterFrame:IsShown() then UI.Toggle() end
    local button = UI.syncButton
    ns.DB.syncedAt = time()
    UI.RefreshSync()
    local _, tip = UI.SyncTip()
    Check(button:GetText() == ns.L.SyncUpToDate and tip:find(format(ns.L.SyncTipData, ns.L.JustNow), 1, true),
        "a sync went to the end just now: 'Up to date'")
    local newer = ns.Net.NewerVersion()
    Check(newer and tip:find(format(ns.L.SyncTipNewer, newer, ns.version), 1, true),
        "the tooltip also says a newer addon version exists")
    ns.DB.syncedAt = time() - 7200
    UI.RefreshSync()
    local label = button:GetText()
    Check(label == ns.L.SyncOutdated or label == ns.L.SyncAlone,
        "last complete sync 2 h ago: no longer 'Up to date' (or 'Alone online' after unanswered syncs)")
    before = #sentChat
    button:GetScript("OnClick")(button)
    Advance(1)
    local full = false
    for i = before + 1, #sentChat do
        if sentChat[i].msg:find("^ETHN1~Q~%x%x%x%x%x%^0$") then full = true end
    end
    Check(full, "the button asks the users online for everything")
    Advance(14)
    UI.RefreshSync()
    Check(button:GetText() == ns.L.SyncAlone, "nobody answered: 'Alone online'")
    local realName = GetChannelName
    GetChannelName = function() return 0, nil end
    UI.RefreshSync()
    Check(button:GetText() == ns.L.SyncNoChannel, "hidden channel refused: 'No network'")
    GetChannelName = realName

    -- a sync that goes to the end (automatic or not) turns the button to "Up to date" by itself
    ns.DB.syncedAt = 0
    UI.RefreshSync()
    before = #sentChat
    Check(ns.Net.RequestSync(true), "a sync starts")
    local sq = LastQ(before)
    ChannelMessage("ETHN1~S~" .. sq .. "~0~" .. ns.Net.Encode({ itemId = tomeIds[5], mapFile = "Durotar", x = 0.7, y = 0.7,
        mob = "Raptor", zone = "Durotar", at = time(), by = "Bea" }), "Bea")
    Advance(5)
    Check(button:GetText() == ns.L.SyncUpToDate, "the sync ended: the button says 'Up to date' without being asked")
    -- and it follows time alone (checked every 30 s while the window is shown)
    ns.DB.syncedAt = time() - 7200
    Advance(31)
    Check(button:GetText() ~= ns.L.SyncUpToDate, "2 h later: no longer 'Up to date', by itself")
    EbonTomeHunterFrame:Hide()
    Check(not ns.Net.StartAutoSync(), "the automatic sync runs from the login on (started once)")
    before = #sentChat
    Advance(961)
    local auto = false
    for i = before + 1, #sentChat do
        if sentChat[i].msg:find("^ETHN1~Q~%x%x%x%x%x%^") then auto = true end
    end
    Check(auto, "15 min later: a sync by itself")
end
ns.DB.sightings = keptSightings
ns.Fire("SIGHTINGS_CHANGED")

-- --- Stale sources (Evidence.lua) --------------------------------------------------------
local EV = ns.Evidence
local keptForEvidence = ns.DB.sightings
ns.DB.sightings = {}
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
ns.DB.corpses[wolfKey].n = 24
before = #sentChat
LootCorpse("1002")
local announced = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~K~300569%^#28434%^25%^") then announced = true end
end
Check(announced, "the counter is shared every 25 corpses")
Check(not EV.Verdict(300569, "Sinewy Wolf", 28434), "25 corpses: still a good source")
ns.DB.corpses[wolfKey].n = 500
local staleNow, kills = EV.Verdict(300569, "Sinewy Wolf", 28434)
Check(staleNow and kills == 500, "500 looted corpses without the tome: probably no longer drops it")
local staleSeen, orderOk = false, true
for _, source in ipairs(ns.Travel.Sources(300569)) do
    if source.stale then staleSeen = true elseif staleSeen then orderOk = false end
end
Check(staleSeen and orderOk, "stale sources come last (teleport, Sources window)")
LootCorpse("1003", true)
Check(ns.DB.corpses[wolfKey].n == 0 and not EV.Verdict(300569, "Sinewy Wolf", 28434),
    "the tome drops from it again: counter back to 0, good source")

-- other users' counters: one weighs half the threshold at most; a later drop clears them
ns.DB.corpses = {}
local nowEv = time()
ChannelMessage("ETHN1~K~300569^#28434^900^" .. nowEv .. "^0", "Hal")
local _, halKills = EV.Verdict(300569, "Sinewy Wolf", 28434)
Check(halKills == EV.STALE_KILLS / 2 and not EV.Verdict(300569, "Sinewy Wolf", 28434),
    "a single other user cannot mark a source alone")
ChannelMessage("ETHN1~K~300569^#28434^260^" .. nowEv .. "^0", "Ivy")
Check(EV.Verdict(300569, "Sinewy Wolf", 28434), "two users with enough corpses: stale")
ChannelMessage("ETHN1~K~300569^#28434^3^" .. (nowEv + 30) .. "^" .. (nowEv + 30), "Kim")
Check(not EV.Verdict(300569, "Sinewy Wolf", 28434), "a drop reported after their counts: good source again")

-- reports: 3 users, or the player alone for themselves; withdrawn from the Sources window
ns.DB.evidence, ns.DB.reports = {}, {}
local later = nowEv + 60
ChannelMessage("ETHN1~V~300569^#4698^" .. later, "Lea")
ChannelMessage("ETHN1~V~300569^#4698^" .. later, "Max")
Check(not EV.Verdict(300569, "Scarlet Paladins", 4698), "2 reports: not enough")
ChannelMessage("ETHN1~V~300569^#4698^" .. later, "Ned")
local byVotes, _, voters = EV.Verdict(300569, "Scarlet Paladins", 4698)
Check(byVotes and voters == 3, "3 users reported it: stale")
ChannelMessage("ETHN1~V~300569^#4698^0", "Ned")
Check(not EV.Verdict(300569, "Scarlet Paladins", 4698), "a report withdrawn")
before = #sentChat
Check(EV.Report(300569, "Scarlet Paladins", 4698, true), "the player reports a source")
local mineStale, _, _, mine = EV.Verdict(300569, "Scarlet Paladins", 4698)
Advance(2)
local shared = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~V~300569%^#4698%^%d+$") then shared = true end
end
Check(mineStale and mine and shared, "own report: stale for the player, shared with the others")
Check(WH.Show(300569) > 0, "Sources window opened")
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

-- our counters and reports go to a user who shows up (at most every 10 min)
ns.DB.corpses[wolfKey] = { n = 30, since = time(), drop = 0 }
Advance(601)
before = #sentChat
ChannelMessage("ETHN1~Q~d0000^" .. time(), "Zed")
Advance(3)
local bundled = false
for i = before + 1, #sentChat do
    if sentChat[i].msg:find("^ETHN1~K~.*300569%^#28434%^30%^") then bundled = true end
end
Check(bundled, "a user shows up: our counters are sent")

-- network places: the most recent first, those not found for 90 days flagged
ns.Net.Add({ itemId = 300569, mapFile = "Tanaris", x = 0.1, y = 0.1, mob = "Old Mob", zone = "Tanaris",
    at = time() - 100 * 86400, by = "Pat" })
local netLocs = ns.Net.Locations(300569)
Check(netLocs and #netLocs >= 2 and not netLocs[1].old and netLocs[#netLocs].old and netLocs[1].at >= netLocs[#netLocs].at,
    "network places: most recent first, the old ones flagged")
ns.DB.sightings = keptForEvidence
ns.DB.corpses, ns.DB.evidence, ns.DB.reports = {}, {}, {}
ns.Fire("SIGHTINGS_CHANGED")
Advance(2)

-- --- Kill statistics (counted by Loot.lua, shared on request for /ethdev stats) ---------------
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
    before = #sentChat
    ChannelMessage("ETHN1~H~t^a1b2c", "Yan")
    Advance(6)
    local shared = false
    for i = before + 1, #sentChat do
        if sentChat[i].msg:find("^ETHN1~H~u%^a1b2c%^1%^1%^2%^" .. wyrm .. ":2$") then shared = true end
    end
    Check(shared, "a statistics request is answered with our kills")
    local got
    ns.On("NET_STATS", function(results) got = results end)
    Check(ns.Net.RequestStats(), "statistics asked to the users online")
    Advance(1)
    local sq
    for i = before + 1, #sentChat do sq = sq or sentChat[i].msg:match("^ETHN1~H~t%^(%x+)$") end
    ChannelMessage("ETHN1~H~u^" .. sq .. "^1^1^500^29120:300;1234:200", "Zoe")
    Advance(15)
    Check(got and got.Zoe and got.Zoe.total == 500 and got.Zoe.kills[29120] == 300 and got.Zoe.kills[1234] == 200,
        "the answers are collected and handed over (NET_STATS)")
    Advance(61)   -- these kills must not count as the recent kills of the Scavenger tests
end

-- --- Drop history window (/eth history) ------------------------------------------------------
do
    local entries = ns.History.Entries(false)
    local sorted, bob = true, nil
    for i, e in ipairs(entries) do
        if i > 1 and e.at > entries[i - 1].at then sorted = false end
        if e.by == "Bob" then bob = e end
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
    Check(WH.Show(300569) > 0 and (ns.Sources.hintText:GetText() or ""):find("Beast-type", 1, true) ~= nil,
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
ns.DB.netOutbox[1] = { wire = "pending", at = time() }
ns.SetOption("netEnabled", false)
Check(#ns.DB.netOutbox == 0, "network turned off: the finds waiting to be sent are dropped")
before = #sentChat
unitState.target = { name = "Sinewy Wolf", guid = "0xF130006F12000042", dead = true }
GetPlayerMapPosition = function(unit) return 0.20, 0.30 end
Fire("LOOT_OPENED")
Fire("CHAT_MSG_LOOT", format(LOOT_ITEM_SELF, Link(300569, "Tome of Echo: Beast Bane")))
Advance(2)
Check(#sentChat == before and #ns.DB.sightings[300569] == 2, "network off: kept locally, not sent")
ns.SetOption("netEnabled", true)
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
    "two kinds of mobs killed in the last minute: the place only")
ChannelMessage("ETHN1~D~" .. ns.Net.Encode({ itemId = 300025, mapFile = "CrystalsongForest", x = 0.61, y = 0.21,
    npcId = tonumber("0071C0", 16), mob = "Frostbite Bear", zone = "Crystalsong Forest", at = time(), by = "Zed" }), "Zed")
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
    local hearthglen = ns.Catalog.Get(300569).locations[1]
    local near = T.Nearest(hearthglen)
    Check(near and near.checkpoint and near.checkpoint.id == 66, "Hearthglen: Chillwind Camp, nearest unlocked checkpoint")
    Check(near and near.locked and near.locked.id == 383 and near.lockedDistance < near.distance,
        "a nearer checkpoint not unlocked yet is reported (Thondoril River)")

    -- several sources (Hearthglen, Crystalsong...): the one with the nearest checkpoint wins
    local best, sources = T.Best(300569)
    Check(#sources >= 3 and best and best.near.checkpoint.id == 310,
        "Beast Bane: Dalaran, nearest checkpoint among all its sources, got " .. tostring(best and best.near.checkpoint.id))
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
else
    Check(not T.Available() and not T.GoBest(300569) and ChatContains(ns.L.TravelNoPE), "without ProjectEbonhold: no teleport")
    local baneRow = RowOf(300569)
    Check(baneRow and not baneRow.travel:IsEnabled(), "without ProjectEbonhold: teleport button disabled")
    Check(ns.Sources.Show(300569) >= 3 and not EbonTomeHunterSourcesListRow1.tp:IsEnabled(), "Sources: no TP either")
    EbonTomeHunterSourcesFrame:Hide()
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
