local addonName, ns = ...
local L = ns.L
local W = ns.Widgets
local C = W.C

-- Main window: every tome (or the wishlist) with its price, drop place and
-- wishlist quantity.
ns.UI = {}
local UI = ns.UI

UI.WIDTH, UI.HEIGHT = 780, 540
UI.ROW_H = 24
UI.VISIBLE_ROWS = 16
UI.mode = "all"      -- "all" | "wish"
UI.filter = ""

local frame, list, header, searchBox, countText
local tabAll, tabWish, scanButton, listedChip, locatedChip, unknownChip
local totalText, statusText, progress, emptyText
local syncButton

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
local function Opt() return ns.Opt() end

local function Matches(row, filter)
    if filter == "" then return true end
    if row.name and strlower(row.name):find(filter, 1, true) then return true end
    for _, loc in ipairs(ns.WorldMap.Locations(row)) do
        if type(loc.placeName) == "string" and strlower(loc.placeName):find(filter, 1, true) then return true end
        if type(loc.mobs) == "table" then
            for _, mob in ipairs(loc.mobs) do
                if strlower(tostring(mob)):find(filter, 1, true) then return true end
            end
        end
    end
    return false
end

local function HasPlace(row)
    for _, loc in ipairs(ns.WorldMap.Locations(row)) do
        if ns.WorldMap.WorldPosition(loc) then return true end
    end
    return false
end

local SORTERS = {
    name = function(a, b) return (a.row.name or "") < (b.row.name or "") end,
    place = function(a, b)
        local pa = a.row.location and a.row.location.placeName or "~"
        local pb = b.row.location and b.row.location.placeName or "~"
        if pa ~= pb then return pa < pb end
        return (a.row.name or "") < (b.row.name or "")
    end,
    price = function(a, b)
        local pa = ns.Prices.GetMin(a.itemId) or math.huge
        local pb = ns.Prices.GetMin(b.itemId) or math.huge
        if pa ~= pb then return pa < pb end
        return (a.row.name or "") < (b.row.name or "")
    end,
    qty = function(a, b)
        local qa = a.entry and a.entry.qty or 0
        local qb = b.entry and b.entry.qty or 0
        if qa ~= qb then return qa > qb end
        return (a.row.name or "") < (b.row.name or "")
    end,
}

function UI.BuildList()
    local out = {}
    local filter = strlower(UI.filter or "")
    local opt = Opt()
    local source = {}
    if UI.mode == "wish" then
        for _, item in ipairs(ns.Wishlist.List()) do
            if item.row then source[#source + 1] = item.row end
        end
    else
        source = ns.Catalog.rows
    end
    local onlyUnknown = opt.onlyUnknown and ns.Known.Available()
    for _, row in ipairs(source) do
        if Matches(row, filter)
            and (not opt.onlyPriced or ns.Prices.IsListed(row.itemId))
            and (not opt.onlyLocated or HasPlace(row))
            and (not onlyUnknown or ns.Known.IsKnown(row.itemId) == false) then
            out[#out + 1] = { itemId = row.itemId, row = row, entry = ns.Wishlist.Get(row.itemId) }
        end
    end
    local sorter = SORTERS[opt.sortKey] or SORTERS.name
    if opt.sortDesc then
        table.sort(out, function(a, b) return sorter(b, a) end)
    else
        table.sort(out, sorter)
    end
    return out
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function PriceText(itemId)
    local min = ns.Prices.GetMin(itemId)
    local listings = ns.Prices.GetListings(itemId)
    if min and listings > 0 then
        return W.Money(min, true) .. " |cff888888(" .. listings .. ")|r", C.text
    elseif min then
        return W.Money(min, true), C.muted
    elseif listings > 0 then
        return L.BidOnly .. " |cff888888(" .. listings .. ")|r", C.muted
    end
    return "|cff666666-|r", C.muted
end

-- "Already learned by this character" (or not) in a tooltip; nothing without ProjectEbonhold.
function UI.AddKnownLine(tooltip, itemId)
    local state = ns.Known.State(itemId)
    if state == true then
        tooltip:AddLine(L.KnownYes, 0.3, 1, 0.3)
    elseif state == "disabled" then
        tooltip:AddLine(L.KnownDisabled, 1, 0.82, 0)
    elseif state == false then
        tooltip:AddLine(L.KnownNo, 0.65, 0.65, 0.65)
    end
end

local function RowTooltip(row)
    local data = row.item
    if not data then return end
    local tome = data.row
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local r, g, b = ns.Catalog.QualityColor(tome)
    GameTooltip:AddLine(ns.Catalog.Title(tome), r, g, b)
    UI.AddKnownLine(GameTooltip, data.itemId)
    if tome.desc and tome.desc ~= "" then
        GameTooltip:AddLine(tome.desc, 1, 0.82, 0, true)
    end
    local hint = ns.Catalog.DropHint(tome)
    if hint then GameTooltip:AddLine(L.HintLabel .. " : " .. hint, 0.55, 0.8, 1, true) end
    local locations = ns.WorldMap.Locations(tome)
    for i, loc in ipairs(locations) do
        if i > 4 then
            GameTooltip:AddLine(format(L.OtherPlaces, #locations - 4), 0.6, 0.6, 0.6)
            break
        end
        local where = ns.WorldMap.Describe(loc)
        GameTooltip:AddLine(L.PlaceLabel .. " : " .. tostring(loc.placeName or L.LocationUnknown)
            .. (where and (" |cff999999(" .. where .. ")|r") or ""), C.place[1], C.place[2], C.place[3], true)
        local mobs = ns.WorldMap.MobsText(loc)
        if mobs then
            GameTooltip:AddLine("   " .. L.MobsLabel .. " : " .. mobs, 0.7, 0.7, 0.7, true)
        end
        if (loc.source == "net" or loc.source == "raid") and loc.notes then
            GameTooltip:AddLine("   " .. loc.notes, 0.45, 0.75, 1, true)   -- found by a player
        end
    end
    local rec = ns.Prices.Get(data.itemId)
    if rec and rec.min and rec.min > 0 then
        if (rec.listings or 0) > 0 then
            GameTooltip:AddDoubleLine(L.Buyout, W.Money(rec.min) .. "  " .. format(L.ListingsCount, rec.listings),
                0.4, 1, 0.4, 1, 1, 1)
        else
            GameTooltip:AddLine(format(L.NotListedTip, ns.Ago(rec.seen or rec.at) or "?"), 0.8, 0.5, 0.5, true)
        end
        if rec.prevMin and rec.prevMin > 0 and rec.prevMin ~= rec.min then
            local text = rec.min > rec.prevMin and L.PriceUp or L.PriceDown
            GameTooltip:AddLine(format(text, W.Money(rec.prevMin)), 0.6, 0.6, 0.6)
        end
        if rec.at and rec.at > 0 then
            GameTooltip:AddLine(L.LastScan .. " " .. (ns.Ago(rec.at) or ""), 0.5, 0.5, 0.5)
        end
    else
        GameTooltip:AddLine(L.NoPrice, 1, 0.4, 0.4)
    end
    GameTooltip:AddLine(L.RowHint, 0.45, 0.45, 0.45)
    GameTooltip:Show()
end

-- Teleport button: where it goes, or why it cannot.
local function TravelTooltip(button)
    local data = button:GetParent().item
    if not data then return end
    local T, fmt = ns.Travel, ns.Travel.FormatDistance
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    local best, sources = T.Best(data.itemId)
    if best then
        GameTooltip:AddLine(format(L.TravelTo, best.near.checkpoint.name), 1, 1, 1)
        GameTooltip:AddLine(format(L.TravelNear, fmt(best.near.distance), T.SourceName(best)), 0.55, 0.9, 0.55, true)
        if best.near.locked then
            GameTooltip:AddLine(format(L.TravelLockedCloser, best.near.locked.name, fmt(best.near.lockedDistance)),
                1, 0.6, 0.25, true)
        end
        local map, worldX, worldY = T.PlayerPosition()
        for _, source in ipairs(map and sources or {}) do
            local mine = T.PlayerDistance(source, map, worldX, worldY)
            if mine and mine < best.near.distance then
                GameTooltip:AddLine(format(L.TravelAlreadyCloseTip, fmt(mine), T.SourceName(source)), 1, 0.82, 0, true)
                break
            end
        end
        if #sources > 1 then GameTooltip:AddLine(format(L.TravelOthers, #sources - 1), 0.6, 0.6, 0.6, true) end
    else
        GameTooltip:AddLine(L.TravelButton, 1, 1, 1)
        local first = sources[1]
        if not T.Available() then
            GameTooltip:AddLine(L.TravelNoPE, 1, 0.4, 0.4, true)
        elseif not (first and first.near) then
            GameTooltip:AddLine(L.SourceNoPosition, 0.6, 0.6, 0.6, true)
        elseif first.near.locked then
            GameTooltip:AddLine(format(L.SourceLocked, first.near.locked.name, fmt(first.near.lockedDistance)),
                1, 0.6, 0.25, true)
        else
            GameTooltip:AddLine(L.SourceNoCheckpoint, 0.6, 0.6, 0.6, true)
        end
    end
    GameTooltip:Show()
end

local function CreateRow(row)
    row.icon = W.ItemIcon(row, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = W.Cell(row, "GameFontHighlight", 206, 14)
    row.name:SetPoint("LEFT", 30, 0)
    row.place = W.Cell(row, "GameFontNormalSmall", 166, 12)
    row.place:SetPoint("LEFT", 246, 0)
    row.place:SetTextColor(C.place[1], C.place[2], C.place[3])
    row.price = W.Cell(row, "GameFontHighlightSmall", 130, 12, "RIGHT")
    row.price:SetPoint("LEFT", 420, 0)

    row.minus = W.IconButton(row, "Interface\\Buttons\\UI-MinusButton-Up", 16, function(self)
        local data = self:GetParent().item
        if not data then return end
        local entry = ns.Wishlist.Get(data.itemId)
        if entry then ns.Wishlist.SetQty(data.itemId, (entry.qty or 1) - 1) end
    end, L.QtyMinusTip)
    row.minus:SetPoint("LEFT", 564, 0)
    row.qty = W.Cell(row, "GameFontHighlight", 24, 14, "CENTER")
    row.qty:SetPoint("LEFT", 582, 0)
    row.plus = W.IconButton(row, "Interface\\Buttons\\UI-PlusButton-Up", 16, function(self)
        local data = self:GetParent().item
        if data then ns.Wishlist.Add(data.itemId, 1) end
    end, L.QtyPlusTip)
    row.plus:SetPoint("LEFT", 608, 0)

    row.locate = W.IconButton(row, "Interface\\Icons\\INV_Misc_Map_01", 18, function(self)
        local data = self:GetParent().item
        if data then ns.WorldMap.Locate(data.itemId) end
    end, L.Locate, L.LocateHint, true)
    row.locate:SetPoint("LEFT", 640, 0)
    row.travel = W.IconButton(row, "Interface\\Icons\\Spell_Arcane_PortalDalaran", 18, function(self)
        local data = self:GetParent().item
        if data then ns.Travel.GoBest(data.itemId) end
    end, nil, nil, true)
    row.travel:SetPoint("LEFT", 662, 0)
    row.travel:SetScript("OnEnter", TravelTooltip)
    row.travel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.sources = W.IconButton(row, "Interface\\Icons\\Ability_Tracking", 16, function(self)
        local data = self:GetParent().item
        if data then ns.Sources.Show(data.itemId) end
    end, L.SourcesButton, L.SourcesButtonTip, true)
    row.sources:SetPoint("LEFT", 685, 0)
    row.remove = W.IconButton(row, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", 16, function(self)
        local data = self:GetParent().item
        if data then ns.Wishlist.Remove(data.itemId) end
    end, L.RemoveFromWishlist)
    row.remove:SetPoint("LEFT", 707, 0)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local data = self.item
        if data and IsShiftKeyDown() then
            local _, link = GetItemInfo(data.itemId)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end
    end)
end

local function UpdateRow(row, data)
    local tome = data.row
    local r, g, b = ns.Catalog.QualityColor(tome)
    row.icon:SetItem(W.TomeIcon(data.itemId), r, g, b)
    row.icon:SetKnown(ns.Known.State(data.itemId))
    row.name:SetText(tome.name or ns.Catalog.Title(tome))
    row.name:SetTextColor(r, g, b)
    -- a tome no source lists at all still says so (it used to show nothing)
    local place = tome.location and (tome.location.placeName or L.LocationUnknown)
        or ("|cff888888" .. (ns.Catalog.DropHint(tome) or L.LocationUnknown) .. "|r")
    local extra = tome.locations and (#tome.locations - 1) or 0
    if extra > 0 then place = place .. " |cff888888(+" .. extra .. ")|r" end
    row.place:SetText(place)
    local text, color = PriceText(data.itemId)
    row.price:SetText(text)
    row.price:SetTextColor(color[1], color[2], color[3])

    local entry = ns.Wishlist.Get(data.itemId)
    if entry then
        row.qty:SetText(tostring(entry.qty or 1))
        row.qty:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        row.remove:Show()
    else
        row.qty:SetText("0")
        row.qty:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        row.remove:Hide()
    end
    W.SetEnabled(row.minus, entry ~= nil)
    W.SetEnabled(row.locate, tome.location ~= nil)
    local locations = ns.WorldMap.Locations(tome)
    local hasSpot = false
    for _, loc in ipairs(locations) do
        if ns.WorldMap.WorldPosition(loc) then
            hasSpot = true
            break
        end
    end
    W.SetEnabled(row.travel, hasSpot and ns.Travel.Available())
    W.SetEnabled(row.sources, #locations > 0)
    if UI.flashId == data.itemId then row.selectedTex:Show() else row.selectedTex:Hide() end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function UpdateFooter()
    local total, missing = ns.Wishlist.ComputeTotal()
    local count = ns.Wishlist.Count()
    totalText:SetText(format(L.WishTotal, W.Money(total, true)) .. "   |cff888888" ..
        format(L.WishPriced, count - missing, count) .. "|r")

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
                (queued > 0 and ("  " .. format(L.Queued, queued)) or ""))
        end
    else
        progress:Hide()
        statusText:Show()
        local last = ns.Prices.LastScan()
        statusText:SetText(last > 0 and format(L.LastScanAgo, ns.Ago(last) or "") or L.NeverScanned)
    end
    scanButton:SetText(ns.Scan.IsScanning() and L.StopScan or L.Scan)
end

function UI.RenderRows()
    if not frame then return end
    local data = UI.BuildList()
    list:SetItems(data)
    local total = UI.mode == "wish" and ns.Wishlist.Count() or ns.Catalog.Count()
    if #data ~= total then
        countText:SetText(format(L.CountFiltered, #data, total))
    else
        countText:SetText(format(L.CountLabel, #data))
    end
    if not ns.Catalog.mapReady then
        emptyText:SetText(L.Waiting)
        emptyText:Show()
    elseif #data == 0 then
        emptyText:SetText(UI.mode == "wish" and UI.filter == "" and ns.Wishlist.Count() == 0 and L.NoWishlist or L.NoMatch)
        emptyText:Show()
    else
        emptyText:Hide()
    end
end

function UI.Refresh()
    if not (frame and frame:IsShown()) then return end
    local subtitle = format(L.Subtitle, ns.Catalog.Count(), ns.Prices.PricedCount())
    local known = ns.Known.Count()
    if known then subtitle = subtitle .. "  -  " .. format(L.SubtitleKnown, known) end
    frame.subtitle:SetText(subtitle)
    tabAll:SetActive(UI.mode == "all")
    tabWish:SetActive(UI.mode == "wish")
    tabWish:SetText(L.WishlistTab .. " (" .. ns.Wishlist.Count() .. ")")
    listedChip:SetActive(Opt().onlyPriced)
    locatedChip:SetActive(Opt().onlyLocated)
    W.SetEnabled(unknownChip, ns.Known.Available())
    unknownChip:SetActive(Opt().onlyUnknown and ns.Known.Available())
    header:SetSort(Opt().sortKey, Opt().sortDesc)
    UI.RenderRows()
    UpdateFooter()
end

local function SetMode(mode)
    UI.mode = mode
    list:ResetScroll()
    UI.Refresh()
end

local function SortBy(key)
    local opt = Opt()
    if opt.sortKey == key then
        opt.sortDesc = not opt.sortDesc
    else
        opt.sortKey, opt.sortDesc = key, false
    end
    list:ResetScroll()
    UI.Refresh()
end

local function ApplyLayout()
    if not frame then return end
    local opt = Opt()
    frame:SetScale(opt.scale or 1)
    local pos = opt.window
    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
end

------------------------------------------------------------------------
-- Construction (lazy: first time the window is opened)
------------------------------------------------------------------------
function UI.Init()
    if frame then return frame end
    frame = W.Window("EbonTomeHunterFrame", UI.WIDTH, UI.HEIGHT, L.Title)
    frame:Hide()
    UI.frame = frame
    function frame:OnMoved()
        local point, _, _, x, y = self:GetPoint(1)
        local pos = Opt().window
        pos.point, pos.x, pos.y = point or "CENTER", x or 0, y or 0
    end
    frame:SetScript("OnShow", function()
        UI.Refresh()
        ns.Tutorial.MaybeStart()   -- the very first time: guided tour
    end)
    frame:HookScript("OnShow", function() UI.RefreshSync() end)
    frame:SetScript("OnHide", function()
        if ns.Tutorial.running then ns.Tutorial.Stop(true) end
    end)
    tinsert(UISpecialFrames, "EbonTomeHunterFrame")
    local helpButton = W.Button(frame.titleBar, "?", 22, 20, function() ns.Tutorial.Start() end)
    helpButton:SetPoint("RIGHT", frame.titleBar, "RIGHT", -34, 0)
    helpButton:SetTip(L.TutoHelpTitle, L.TutoHelpTip)

    -- toolbar: tabs + actions
    tabAll = W.Tab(frame, L.AllTomesTab, 130, function() SetMode("all") end)
    tabAll:SetPoint("TOPLEFT", 10, -40)
    tabWish = W.Tab(frame, L.WishlistTab, 130, function() SetMode("wish") end)
    tabWish:SetPoint("LEFT", tabAll, "RIGHT", 4, 0)
    local shareButton = W.Button(frame, L.Share, 100, 24, function() ns.Share.ShowDialog() end)
    shareButton:SetPoint("LEFT", tabWish, "RIGHT", 8, 0)
    shareButton:SetTip(L.Share, L.ShareTip)
    local historyButton = W.Button(frame, L.HistoryButton, 80, 24, function() ns.History.Toggle() end)
    historyButton:SetPoint("LEFT", shareButton, "RIGHT", 4, 0)
    historyButton:SetTip(L.HistoryTitle, L.HistoryTip)
    UI.historyButton = historyButton

    local optionsButton = W.Button(frame, L.Options, 80, 24, function()
        if ns.OpenOptions then ns.OpenOptions() end
    end)
    optionsButton:SetPoint("TOPRIGHT", -10, -40)
    scanButton = W.Button(frame, L.Scan, 110, 24, function() ns.Scan.Start() end)
    scanButton:SetPoint("RIGHT", optionsButton, "LEFT", -4, 0)
    scanButton:SetTip(L.ScanAll, L.ScanAllTip)
    -- network: "Up to date" or not; a click asks the users online for everything again
    syncButton = W.Button(frame, L.SyncUpToDate, 100, 24, function()
        ns.Net.ForceSync()
        UI.RefreshSync()
    end)
    syncButton:SetPoint("RIGHT", scanButton, "LEFT", -4, 0)
    UI.syncButton = syncButton

    -- search + filters
    searchBox = W.SearchBox(frame, 280, L.SearchPlaceholder, function(text)
        UI.filter = text or ""
        list:ResetScroll()
        UI.RenderRows()
    end)
    searchBox:SetPoint("TOPLEFT", 10, -72)
    UI.searchBox = searchBox
    listedChip = W.Button(frame, L.FilterListed, 90, 22, function()
        Opt().onlyPriced = not Opt().onlyPriced
        list:ResetScroll()
        UI.Refresh()
    end)
    listedChip:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    listedChip:SetTip(L.FilterListed, L.FilterListedTip)
    locatedChip = W.Button(frame, L.FilterLocated, 90, 22, function()
        Opt().onlyLocated = not Opt().onlyLocated
        list:ResetScroll()
        UI.Refresh()
    end)
    locatedChip:SetPoint("LEFT", listedChip, "RIGHT", 4, 0)
    locatedChip:SetTip(L.FilterLocated, L.FilterLocatedTip)
    unknownChip = W.Button(frame, L.FilterUnknown, 90, 22, function()
        Opt().onlyUnknown = not Opt().onlyUnknown
        list:ResetScroll()
        UI.Refresh()
    end)
    unknownChip:SetPoint("LEFT", locatedChip, "RIGHT", 4, 0)
    unknownChip:SetTip(L.FilterUnknown, L.FilterUnknownTip)
    countText = W.Text(frame, "GameFontHighlightSmall", C.muted, "RIGHT")
    countText:SetPoint("TOPRIGHT", -14, -77)

    -- list
    header = W.Header(frame, {
        { key = "name", text = L.TomeLabel, width = 236, sortable = true, offset = 4 },
        { key = "place", text = L.PlaceLabel, width = 174, sortable = true, offset = 6 },
        { key = "price", text = L.PriceLabel, width = 134, justify = "RIGHT", sortable = true },
        { key = "qty", text = L.QtyLabel, width = 76, justify = "CENTER", sortable = true, offset = 6 },
    }, SortBy)
    header:SetPoint("TOPLEFT", 10, -102)
    header:SetPoint("TOPRIGHT", -34, -102)

    list = W.List(frame, "EbonTomeHunterList", UI.ROW_H, UI.VISIBLE_ROWS, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 10, -124)
    list:SetPoint("RIGHT", -10, 0)
    UI.list = list

    emptyText = W.Text(frame, "GameFontNormal", C.muted, "CENTER")
    emptyText:SetPoint("CENTER", list, "CENTER", -12, 0)
    emptyText:SetWidth(UI.WIDTH - 120)
    emptyText:Hide()

    -- footer
    local line = W.Solid(frame, "ARTWORK", C.borderSoft)
    line:SetPoint("BOTTOMLEFT", 10, 34)
    line:SetPoint("BOTTOMRIGHT", -10, 34)
    line:SetHeight(1)
    totalText = W.Text(frame, "GameFontNormal")
    totalText:SetPoint("BOTTOMLEFT", 14, 12)
    statusText = W.Text(frame, "GameFontHighlightSmall", C.muted, "RIGHT")
    statusText:SetPoint("BOTTOMRIGHT", -14, 13)
    progress = W.ProgressBar(frame, 300, 16)
    progress:SetPoint("BOTTOMRIGHT", -12, 10)
    progress:Hide()

    -- what the guided tour (Tutorial.lua) lights up
    UI.parts = {
        title = frame.titleBar, help = helpButton, tabAll = tabAll, tabWish = tabWish, share = shareButton,
        scan = scanButton, options = optionsButton, search = searchBox, chipLast = unknownChip, header = header,
    }

    ApplyLayout()
    return frame
end

-- The network button: its label says whether the data and the addon are up to date, its
-- tooltip gives the details (last complete sync, newer version seen on the network).
local SYNC_LABELS = {
    synced = { L.SyncUpToDate, 0.35, 1, 0.35 }, stale = { L.SyncOutdated, 1, 0.6, 0.2 },
    alone = { L.SyncAlone, 0.7, 0.7, 0.7 }, nochannel = { L.SyncNoChannel, 1, 0.35, 0.35 },
    off = { L.SyncOff, 0.6, 0.6, 0.6 },
}

function UI.SyncTip()
    local state, synced = ns.Net.SyncState()
    local lines = {}
    if state == "synced" then
        lines[1] = format(L.SyncTipData, ns.Ago(synced) or "?")
    elseif state == "alone" then
        lines[1] = L.SyncTipAlone
    elseif state == "stale" then
        lines[1] = synced > 0 and format(L.SyncTipStale, ns.Ago(synced) or "?") or L.SyncTipNever
    else
        lines[1] = ns.Net.StatusText()
    end
    local newer = ns.Net.NewerVersion()
    lines[2] = newer and format(L.SyncTipNewer, newer, ns.version) or format(L.SyncTipAddon, ns.version)
    if state ~= "off" and state ~= "nochannel" then lines[3] = L.SyncTipClick end
    return state, table.concat(lines, "\n")
end

function UI.RefreshSync()
    if not syncButton then return end
    local state, tip = UI.SyncTip()
    local label = SYNC_LABELS[state] or SYNC_LABELS.stale
    syncButton:SetText(label[1])
    local text = syncButton:GetFontString()
    if text then text:SetTextColor(label[2], label[3], label[4]) end
    syncButton:SetTip(L.SyncTitle, tip)
end

ns.On("NET_SYNC_STATE", function() UI.RefreshSync() end)

-- Guided tour: every tome in the list, no search (the chips stay as they are).
function UI.ResetForTour()
    UI.Init()
    UI.mode = "all"
    if searchBox:GetText() ~= "" then searchBox:SetText("") end
    list:ResetScroll()
    UI.Refresh()
end

function UI.Toggle()
    UI.Init()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Opens the window on a tome (map pin, Auction House), scrolled to it and lit for 2 s.
function UI.Show(itemId)
    UI.Init()
    if itemId then
        UI.mode = ns.Wishlist.Has(itemId) and "wish" or "all"
        UI.flashId = itemId
        ns.Timer.After(2, function()
            if UI.flashId == itemId then
                UI.flashId = nil
                if frame:IsShown() then UI.RenderRows() end
            end
        end)
    end
    frame:Show()
    UI.Refresh()
    if itemId then
        local function IndexOf()
            for i, data in ipairs(list.items) do
                if data.itemId == itemId then return i end
            end
        end
        local index = IndexOf()
        if not index and (UI.filter ~= "" or Opt().onlyPriced or Opt().onlyLocated or Opt().onlyUnknown) then
            Opt().onlyPriced, Opt().onlyLocated, Opt().onlyUnknown = false, false, false
            searchBox:SetText("")   -- the filters hid it (OnTextChanged redraws)
            UI.Refresh()
            index = IndexOf()
        end
        if index then list:ShowIndex(index) end
    end
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------
ns.On("CATALOG_CHANGED", UI.Refresh)
ns.On("WISHLIST_CHANGED", UI.Refresh)
ns.On("KNOWN_CHANGED", UI.Refresh)
ns.On("PRICES_CHANGED", UI.Refresh)
ns.On("READY", UI.Refresh)
ns.On("SCAN_STATE", function()
    if frame and frame:IsShown() then UpdateFooter() end
end)
ns.On("SETTINGS_CHANGED", function(key)
    if key == "scale" or key == "window" then ApplyLayout() end
end)
