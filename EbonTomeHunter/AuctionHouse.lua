local addonName, ns = ...
local L = ns.L
local W = ns.Widgets
local C = W.C

-- Two tabs on the Auction House (like Auctionator): "Tomes" (scan, browse every
-- tome) and "Wishlist" (search the wished tomes), sharing one panel: tome list on
-- the left, listings of the selected tome on the right, Buy at the bottom.
-- Blizzard_AuctionUI is load-on-demand: everything is built on its ADDON_LOADED.
ns.AH = {}
local AH = ns.AH

AH.tabs = {}          -- [mode] = tab button
AH.mode = nil         -- "tomes" | "wish" while our panel is shown
AH.selectedId = nil   -- tome whose listings are shown
AH.selectedListing = nil
AH.filter = ""

local ROW_H = 22
local LEFT_ROWS = 13     -- panes are 332 px high (dark area of the AH textures)
local RIGHT_ROWS = 12
local AUTO_SCAN_AGE = 30 * 60

local panel, leftList, rightList, leftHeader, rightHeader, titleText, listingTitle, hintText, emptyText
local searchBox, listedChip, scanButton, wishButton, wishTotal, progress, statusText
local refreshButton, buyButton, selectionText

local function Opt() return ns.Opt() end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
local function LiveInfo(itemId)
    -- cheapest unit buyout and number of tomes for sale, from this session's search
    local result = ns.Scan.Results(itemId)
    if not result then return nil end
    local cheapest, count = nil, 0
    for _, listing in ipairs(result.listings) do
        if listing.buyout > 0 then
            count = count + listing.count
            if not cheapest or listing.unit < cheapest then cheapest = listing.unit end
        end
    end
    return cheapest, count, result.at
end

local function TomesData()
    local out = {}
    local filter = strlower(AH.filter or "")
    local onlyListed = Opt().ahOnlyListed ~= false
    for _, row in ipairs(ns.Catalog.rows) do
        if (filter == "" or strlower(row.name or ""):find(filter, 1, true))
            and (not onlyListed or ns.Prices.IsListed(row.itemId) or ns.Scan.Results(row.itemId)) then
            out[#out + 1] = row
        end
    end
    return out
end

local function WishData()
    local out = {}
    for _, item in ipairs(ns.Wishlist.List()) do
        if item.row then out[#out + 1] = item.row end
    end
    return out
end

local function Listings()
    local result = AH.selectedId and ns.Scan.Results(AH.selectedId)
    return result and result.listings or {}
end

-- Cheapest listing with a buyout that is not ours (listings are sorted by unit price).
local function BestListing(listings)
    for _, listing in ipairs(listings) do
        if listing.buyout > 0 and listing.owner ~= UnitName("player") then
            return listing
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Left list (tomes)
------------------------------------------------------------------------
local function SelectTome(itemId, search)
    if AH.selectedId ~= itemId then
        AH.selectedId = itemId
        AH.selectedListing = nil
    end
    if search then
        local result = ns.Scan.Results(itemId)
        if not result or time() - result.at > 5 then
            ns.Scan.Search(itemId, { front = true })
        end
    end
    AH.Refresh()
end

local function CreateTomeRow(row)
    row.icon = W.ItemIcon(row, 18)
    row.icon:SetPoint("LEFT", 3, 0)
    -- row width: 278 (pane 308 - margins - scroll bar)
    row.name = W.Cell(row, "GameFontHighlightSmall", 110, 12)
    row.name:SetPoint("LEFT", 26, 0)
    row.mid = W.Cell(row, "GameFontHighlightSmall", 32, 12, "CENTER")
    row.mid:SetPoint("LEFT", 138, 0)
    row.price = W.Cell(row, "GameFontHighlightSmall", 86, 12, "RIGHT")
    row.price:SetPoint("LEFT", 172, 0)
    row.add = W.IconButton(row, "Interface\\Buttons\\UI-PlusButton-Up", 14, function(self)
        local tome = self:GetParent().item
        if not tome then return end
        ns.Wishlist.Add(tome.itemId, 1)
        ns.Print(L.AddedToWishlist, tome.name or "?")
    end, L.AddToWishlist)
    row.add:SetPoint("LEFT", 262, 0)
    row:SetScript("OnClick", function(self)
        if self.item then SelectTome(self.item.itemId, true) end
    end)
    row:SetScript("OnEnter", function(self)
        local tome = self.item
        if not tome then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = ns.Catalog.QualityColor(tome)
        GameTooltip:AddLine(ns.Catalog.Title(tome), r, g, b)
        ns.UI.AddKnownLine(GameTooltip, tome.itemId)
        if tome.desc and tome.desc ~= "" then GameTooltip:AddLine(tome.desc, 1, 0.82, 0, true) end
        local rec = ns.Prices.Get(tome.itemId)
        if rec and rec.min and rec.min > 0 then
            GameTooltip:AddLine(format(L.PriceSeen, ns.Ago(rec.seen or rec.at) or "") .. " : " .. W.Money(rec.min), 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function UpdateTomeRow(row, tome)
    local r, g, b = ns.Catalog.QualityColor(tome)
    row.icon:SetItem(W.TomeIcon(tome.itemId), r, g, b)
    row.icon:SetKnown(ns.Known.State(tome.itemId))
    row.name:SetText(tome.name or "?")
    row.name:SetTextColor(r, g, b)
    local cheapest, count = LiveInfo(tome.itemId)
    local rec = ns.Prices.Get(tome.itemId)
    if AH.mode == "wish" then
        local entry = ns.Wishlist.Get(tome.itemId)
        row.mid:SetText("x" .. tostring(entry and entry.qty or 0))
        row.mid:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        row.add:Hide()
    else
        row.mid:SetText(cheapest and tostring(count) or ((rec and (rec.listings or 0) > 0) and tostring(rec.listings) or ""))
        row.mid:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        row.add:Show()
    end
    if ns.Scan.IsSearching(tome.itemId) then
        row.price:SetText("|cff888888...|r")
    elseif cheapest then
        row.price:SetText(W.Money(cheapest, true))
        row.price:SetTextColor(C.good[1], C.good[2], C.good[3])
    elseif ns.Scan.Results(tome.itemId) then
        row.price:SetText(L.NoPrice)
        row.price:SetTextColor(C.bad[1], C.bad[2], C.bad[3])
    elseif rec and rec.min and rec.min > 0 then
        row.price:SetText(W.Money(rec.min, true))
        local color = (rec.listings or 0) > 0 and C.text or C.muted
        row.price:SetTextColor(color[1], color[2], color[3])
    else
        row.price:SetText("|cff666666-|r")
    end
    if AH.selectedId == tome.itemId then row.selectedTex:Show() else row.selectedTex:Hide() end
end

------------------------------------------------------------------------
-- Right list (listings of the selected tome)
------------------------------------------------------------------------
local function TimeLeftText(timeLeft)
    local text = timeLeft and _G["AUCTION_TIME_LEFT" .. timeLeft]
    return type(text) == "string" and text or ""
end

local function CreateListingRow(row)
    -- row width: 452 (pane 482 - margins - scroll bar)
    row.count = W.Cell(row, "GameFontHighlightSmall", 34, 12, "CENTER")
    row.count:SetPoint("LEFT", 2, 0)
    row.unit = W.Cell(row, "GameFontHighlightSmall", 112, 12, "RIGHT")
    row.unit:SetPoint("LEFT", 40, 0)
    row.total = W.Cell(row, "GameFontHighlightSmall", 112, 12, "RIGHT")
    row.total:SetPoint("LEFT", 158, 0)
    row.seller = W.Cell(row, "GameFontHighlightSmall", 100, 12)
    row.seller:SetPoint("LEFT", 284, 0)
    row.timeLeft = W.Cell(row, "GameFontDisableSmall", 62, 12)
    row.timeLeft:SetPoint("LEFT", 388, 0)
    row:SetScript("OnClick", function(self)
        if not self.item then return end
        AH.selectedListing = self.item
        AH.Refresh()
    end)
    row:SetScript("OnDoubleClick", function(self)
        if not self.item then return end
        AH.selectedListing = self.item
        AH.Refresh()
        ns.Buy.Request(self.item)
    end)
    row:SetScript("OnEnter", function(self)
        if self.item and self.item.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.item.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function UpdateListingRow(row, listing, index)
    local mine = listing.owner and listing.owner == UnitName("player")
    row.count:SetText(tostring(listing.count))
    if listing.buyout > 0 then
        row.unit:SetText(W.Money(listing.unit))
        row.total:SetText(W.Money(listing.buyout))
    else
        row.unit:SetText(L.BidOnly)
        row.total:SetText(W.Money(listing.bid))
    end
    local color = (mine or listing.buyout <= 0) and C.muted or (index == 1 and C.good or C.text)
    row.unit:SetTextColor(color[1], color[2], color[3])
    row.total:SetTextColor(color[1], color[2], color[3])
    row.seller:SetText(mine and ("|cff888888" .. L.You .. "|r") or (listing.owner or "?"))
    row.timeLeft:SetText(TimeLeftText(listing.timeLeft))
    if AH.selectedListing == listing then row.selectedTex:Show() else row.selectedTex:Hide() end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function UpdateToolbar()
    local kind, page, pages, queued, itemId = ns.Scan.Progress()
    if kind then
        progress:Show()
        statusText:Hide()
        if kind == "scan" then
            progress:SetMinMaxValues(0, math.max(pages, 1))
            progress:SetValue(math.min(page, math.max(pages, 1)))
            progress.text:SetText(pages > 0 and format(L.ScanPage, page, pages) or format(L.ScanPageFirst, page))
        else
            local row = ns.Catalog.Get(itemId)
            progress:SetMinMaxValues(0, 1)
            progress:SetValue(1)
            progress.text:SetText(format(L.Searching, row and row.name or "?") ..
                (queued > 0 and ("  (" .. format(L.Queued, queued) .. ")") or ""))
        end
    else
        progress:Hide()
        statusText:Show()
        local last = ns.Prices.LastScan()
        statusText:SetText(last > 0 and format(L.LastScanAgo, ns.Ago(last) or "") or L.NeverScanned)
    end
    scanButton:SetText(ns.Scan.IsScanning() and L.StopScan or L.ScanAll)
end

local function UpdateSelection()
    local listing = AH.selectedListing
    local ok, reason = ns.Buy.Check(listing)
    W.SetEnabled(buyButton, ok)
    W.SetEnabled(refreshButton, AH.selectedId ~= nil)
    if listing and ok then
        local text = format(L.Selection, listing.count, listing.name or "?", W.Money(listing.buyout))
        if ns.Known.IsKnown(listing.itemId) then
            text = text .. "  |cffff8000(" .. L.AlreadyKnown .. ")|r"   -- buying it is probably a mistake
        end
        selectionText:SetText(text)
        selectionText:SetTextColor(C.text[1], C.text[2], C.text[3])
    elseif listing then
        selectionText:SetText(reason or "")
        selectionText:SetTextColor(C.bad[1], C.bad[2], C.bad[3])
    else
        selectionText:SetText("")
    end
end

function AH.Refresh()
    if not (panel and panel:IsShown()) then return end
    local wish = AH.mode == "wish"
    titleText:SetText(L.Title .. "  -  " .. (wish and L.AHTitleWish or L.AHTitleTomes))
    if wish then
        searchBox:Hide(); listedChip:Hide(); scanButton:Hide()
        wishButton:Show(); wishTotal:Show()
        local total, missing = ns.Wishlist.ComputeTotal()
        local count = ns.Wishlist.Count()
        wishTotal:SetText(format(L.WishTotal, W.Money(total, true)) .. "  |cff888888" ..
            format(L.WishPriced, count - missing, count) .. "|r")
        leftHeader.buttons.mid.label:SetText(L.ColNeed)
    else
        searchBox:Show(); listedChip:Show(); scanButton:Show()
        wishButton:Hide(); wishTotal:Hide()
        listedChip:SetActive(Opt().ahOnlyListed ~= false)
        leftHeader.buttons.mid.label:SetText(L.ColFound)
    end

    local data = wish and WishData() or TomesData()
    leftList:SetItems(data)
    if #data == 0 then
        emptyText:SetText(wish and L.WishEmptyAH or (ns.Prices.LastScan() > 0 and L.NoMatch or L.NoScanYet))
        emptyText:Show()
    else
        emptyText:Hide()
    end

    local row = AH.selectedId and ns.Catalog.Get(AH.selectedId)
    local listings = Listings()
    rightList:SetItems(listings)
    if not row then
        listingTitle:SetText("")
        hintText:SetText(L.ClickTomeHint)
        hintText:Show()
    else
        local result = ns.Scan.Results(AH.selectedId)
        local r, g, b = ns.Catalog.QualityColor(row)
        listingTitle:SetText(format(L.ListingsFor, row.name or "?") ..
            (result and ("  |cff888888" .. format(L.SearchResultsAgo, ns.Ago(result.at) or "") .. "|r") or ""))
        listingTitle:SetTextColor(r, g, b)
        if ns.Scan.IsSearching(AH.selectedId) and #listings == 0 then
            hintText:SetText(format(L.Searching, row.name or "?"))
            hintText:Show()
        elseif result and #listings == 0 then
            hintText:SetText(L.NoListings)
            hintText:Show()
        else
            hintText:Hide()
        end
    end
    UpdateToolbar()
    UpdateSelection()
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------
local function Pane(parent, x1, x2)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, -74)
    pane:SetPoint("BOTTOMRIGHT", parent, "TOPLEFT", x2, -406)
    W.Backdrop(pane, C.panel, C.borderSoft)
    return pane
end

local function BuildPanel()
    panel = CreateFrame("Frame", "EbonTomeHunterAHPanel", AuctionFrame)
    panel:SetAllPoints(AuctionFrame)
    panel:Hide()

    titleText = W.Text(panel, "GameFontNormal", nil, "CENTER")
    titleText:SetPoint("TOP", 0, -18)

    -- toolbar (Tomes)
    searchBox = W.SearchBox(panel, 170, L.SearchPlaceholder, function(text)
        AH.filter = text or ""
        if leftList then leftList:ResetScroll() end
        AH.Refresh()
    end)
    searchBox:SetPoint("TOPLEFT", 80, -42)
    listedChip = W.Button(panel, L.OnlyListed, 130, 22, function()
        Opt().ahOnlyListed = not (Opt().ahOnlyListed ~= false)
        leftList:ResetScroll()
        AH.Refresh()
    end)
    listedChip:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    scanButton = W.Button(panel, L.ScanAll, 110, 22, function() ns.Scan.Start() end)
    scanButton:SetPoint("TOPRIGHT", -12, -42)
    scanButton:SetTip(L.ScanAll, L.ScanAllTip)

    -- toolbar (Wishlist)
    wishButton = W.Button(panel, L.ScanWish, 150, 22, function() AH.SearchWishlist() end)
    wishButton:SetPoint("TOPLEFT", 80, -42)
    wishButton:SetTip(L.ScanWish, L.ScanWishTip)
    wishTotal = W.Text(panel, "GameFontNormalSmall")
    wishTotal:SetPoint("LEFT", wishButton, "RIGHT", 10, 0)

    progress = W.ProgressBar(panel, 250, 16)
    progress:SetPoint("TOPRIGHT", -130, -45)
    statusText = W.Text(panel, "GameFontHighlightSmall", C.muted, "RIGHT")
    statusText:SetPoint("TOPRIGHT", -132, -48)

    -- left pane: tomes
    local left = Pane(panel, 22, 330)
    leftHeader = W.Header(left, {
        { key = "name", text = L.TomeLabel, width = 112, offset = 24 },
        { key = "mid", text = L.ColFound, width = 32, justify = "CENTER", offset = 2 },
        { key = "price", text = L.PriceLabel, width = 86, justify = "RIGHT", offset = 2 },
    })
    leftHeader:SetPoint("TOPLEFT", 3, -3)
    leftHeader:SetPoint("TOPRIGHT", -25, -3)
    leftList = W.List(left, "EbonTomeHunterAHTomes", ROW_H, LEFT_ROWS, CreateTomeRow, UpdateTomeRow)
    leftList:SetPoint("TOPLEFT", 3, -25)
    leftList:SetPoint("RIGHT", -3, 0)
    emptyText = W.Text(left, "GameFontNormalSmall", C.muted, "CENTER")
    emptyText:SetPoint("CENTER", 0, 0)
    emptyText:SetWidth(270)

    -- right pane: listings
    local right = Pane(panel, 336, 818)
    listingTitle = W.Cell(right, "GameFontNormal", 440, 14)
    listingTitle:SetPoint("TOPLEFT", 8, -5)
    rightHeader = W.Header(right, {
        { key = "count", text = L.ColStack, width = 38, justify = "CENTER" },
        { key = "unit", text = L.ColUnit, width = 114, justify = "RIGHT", offset = 2 },
        { key = "total", text = L.ColTotal, width = 116, justify = "RIGHT", offset = 4 },
        { key = "seller", text = L.ColSeller, width = 104, offset = 8 },
        { key = "time", text = L.ColTime, width = 66 },
    })
    rightHeader:SetPoint("TOPLEFT", 3, -24)
    rightHeader:SetPoint("TOPRIGHT", -25, -24)
    rightList = W.List(right, "EbonTomeHunterAHListings", ROW_H, RIGHT_ROWS, CreateListingRow, UpdateListingRow)
    rightList:SetPoint("TOPLEFT", 3, -46)
    rightList:SetPoint("RIGHT", -3, 0)
    hintText = W.Text(right, "GameFontNormalSmall", C.muted, "CENTER")
    hintText:SetPoint("CENTER", 0, -10)
    hintText:SetWidth(420)

    -- bottom bar, on Blizzard's button slots
    local closeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 22)
    closeButton:SetPoint("BOTTOMRIGHT", -8, 14)
    closeButton:SetText(CLOSE)
    closeButton:SetScript("OnClick", function() HideUIPanel(AuctionFrame) end)
    buyButton = CreateFrame("Button", "EbonTomeHunterAHBuy", panel, "UIPanelButtonTemplate")
    buyButton:SetSize(80, 22)
    buyButton:SetPoint("RIGHT", closeButton, "LEFT", 0, 0)
    buyButton:SetText(L.BuyButton)
    buyButton:SetScript("OnClick", function() ns.Buy.Request(AH.selectedListing) end)
    refreshButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshButton:SetSize(80, 22)
    refreshButton:SetPoint("RIGHT", buyButton, "LEFT", 0, 0)
    refreshButton:SetText(L.Refresh)
    refreshButton:SetScript("OnClick", function()
        if AH.selectedId then ns.Scan.Search(AH.selectedId, { front = true }) end
    end)
    W.Tooltip(refreshButton, L.Refresh, L.RefreshTip)
    selectionText = W.Cell(panel, "GameFontHighlightSmall", 390, 12, "CENTER")
    selectionText:SetPoint("BOTTOMLEFT", 188, 20)

    panel:SetScript("OnShow", AH.Refresh)
end

local AUCTION_TEXTURES = {
    TopLeft = "Bid-TopLeft", Top = "Auction-Top", TopRight = "Auction-TopRight",
    BotLeft = "Bid-BotLeft", Bot = "Auction-Bot", BotRight = "Bid-BotRight",
}

function AH.ShowPanel(mode)
    if not panel then BuildPanel() end
    AH.mode = mode
    -- Blizzard's click handler already hid its own frames; an addon replacing it may not.
    for _, name in ipairs({ "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions", "Atr_Main_Panel" }) do
        local other = _G[name]
        if type(other) == "table" and other.Hide then other:Hide() end
    end
    for part, file in pairs(AUCTION_TEXTURES) do
        local tex = _G["AuctionFrame" .. part]
        if type(tex) == "table" and tex.SetTexture then
            tex:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-" .. file)
        end
    end
    if type(AuctionFrameMoneyFrame) == "table" then AuctionFrameMoneyFrame:Show() end
    if SetAuctionsTabShowing then SetAuctionsTabShowing(false) end
    if mode == "wish" and not AH.selectedId then
        local first = ns.Wishlist.List()[1]
        AH.selectedId = first and first.itemId or nil
    end
    panel:Show()
    AH.Refresh()
end

-- Searches every tome of the wishlist, one after the other.
function AH.SearchWishlist()
    local ids = {}
    for _, item in ipairs(ns.Wishlist.List()) do ids[#ids + 1] = item.itemId end
    if #ids == 0 then
        ns.Print(L.WishEmptyAH)
        return 0
    end
    if not AH.selectedId then AH.selectedId = ids[1] end
    return ns.Scan.SearchMany(ids)
end

function AH.HidePanel()
    AH.mode = nil
    if panel then panel:Hide() end
end

function AH.SelectTab(mode)
    local tab = AH.tabs[mode]
    if tab and tab:IsShown() then AuctionFrameTab_OnClick(tab) end
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
local function AddTab(mode, text)
    local n = (tonumber(AuctionFrame.numTabs) or 3) + 1
    local tab = CreateFrame("Button", "AuctionFrameTab" .. n, AuctionFrame, "AuctionTabTemplate")
    tab:SetID(n)
    tab:SetText(text)
    -- The template sizes a tab to its text in OnShow, which does not run when the
    -- Auction House is already open when the tab is created.
    PanelTemplates_TabResize(tab, 0)
    tab:SetPoint("LEFT", _G["AuctionFrameTab" .. (n - 1)], "RIGHT", -8, 0)
    PanelTemplates_SetNumTabs(AuctionFrame, n)
    PanelTemplates_EnableTab(AuctionFrame, n)
    AuctionFrame.numTabs = n   -- (PanelTemplates_SetNumTabs does it; kept explicit)
    tab.ebonTomeHunterMode = mode
    AH.tabs[mode] = tab
    return tab
end

local function ApplyTabOption()
    local show = Opt().ahTabs
    for _, tab in pairs(AH.tabs) do
        if show then tab:Show() else tab:Hide() end
    end
    if not show and AH.mode then AuctionFrameTab_OnClick(_G["AuctionFrameTab1"]) end
end

local function Setup()
    if AH.ready or not AuctionFrame then return end
    AH.ready = true
    AddTab("tomes", L.AHTabTomes)
    AddTab("wish", L.AHTabWish)
    hooksecurefunc("AuctionFrameTab_OnClick", function(self)
        local mode = type(self) == "table" and self.ebonTomeHunterMode or nil
        if mode then AH.ShowPanel(mode) else AH.HidePanel() end
    end)
    ApplyTabOption()
end

------------------------------------------------------------------------
-- Messages and events
------------------------------------------------------------------------
ns.On("AUCTION_UI_LOADED", Setup)
ns.On("DATABASE_READY", function()
    -- Another addon may have loaded the Auction House UI before us.
    if IsAddOnLoaded("Blizzard_AuctionUI") then Setup() end
end)

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
    ns.Timer.After(0, function()
        if not (AuctionFrame and AuctionFrame:IsShown()) then return end
        Setup()
        if Opt().ahTabs and Opt().ahOpenTab then AH.SelectTab("tomes") end
        if Opt().autoScan and time() - ns.Prices.LastScan() > AUTO_SCAN_AGE and not ns.Scan.IsBusy() then
            ns.Scan.Start()
        end
    end)
end)

ns.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    AH.selectedListing = nil
    AH.mode = nil
end)

ns.On("SEARCH_RESULTS", function(itemId)
    if itemId == AH.selectedId then
        -- keep the selection if that auction is still there, else take the cheapest
        local listings = Listings()
        local keep = false
        for _, listing in ipairs(listings) do
            if listing == AH.selectedListing then keep = true end
        end
        if not keep then AH.selectedListing = BestListing(listings) end
    end
    AH.Refresh()
end)
ns.On("SCAN_STATE", function()
    if panel and panel:IsShown() then AH.Refresh() end
end)
ns.On("WISHLIST_CHANGED", AH.Refresh)
ns.On("PRICES_CHANGED", AH.Refresh)
ns.On("CATALOG_CHANGED", AH.Refresh)
ns.On("KNOWN_CHANGED", AH.Refresh)
ns.On("PURCHASE", function(listing)
    if AH.selectedListing == listing then AH.selectedListing = nil end
end)
ns.On("SETTINGS_CHANGED", function(key)
    if key == "ahTabs" then ApplyTabOption() end
end)
