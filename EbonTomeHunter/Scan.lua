local addonName, ns = ...
local L = ns.L

-- Auction House queries: the full tome scan, exact searches of one tome (to show
-- and buy its listings) and a queue of searches (wishlist refresh). One query at a
-- time; each page waits for CanSendAuctionQuery() and for AUCTION_ITEM_LIST_UPDATE.
ns.Scan = {}
local Scan = ns.Scan

local FULL_QUERY = "Tome of Echo"   -- item names are "Tome of Echo: <echo>" (substring search)
local PAGE_DELAY = 0.3
local WAIT_STEP = 0.2
local MAX_WAIT = 15                  -- seconds waiting for the AH to accept a query
local QUERY_TIMEOUT = 8              -- seconds without answer: send the page again
local MAX_PAGE_RETRIES = 2
local SCAN_MAX_PAGES = 60
local SEARCH_MAX_PAGES = 5

Scan.job = nil       -- query in progress
Scan.queue = {}      -- searches waiting for their turn
Scan.results = {}    -- [itemId] = { at, listings, total }: last exact search of each tome
Scan.loaded = nil    -- { query, page, itemId }: what the AH "list" results hold right now
Scan.sending = false

local generation = 0

local function ItemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end
Scan.ItemIdFromLink = ItemIdFromLink

local function AHOpen()
    return AuctionFrame and AuctionFrame:IsShown() and true or false
end

local function Notify()
    ns.Fire("SCAN_STATE")
end

-- Search text of a tome: its auction item name.
function Scan.QueryName(row)
    if not row then return nil end
    return row.tomeName or ("Tome of Echo: " .. tostring(row.name or ""))
end

------------------------------------------------------------------------
-- Reading the current page
------------------------------------------------------------------------
-- One auction of the "list" results (3.3.5a GetAuctionItemInfo: name, texture, count,
-- quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner).
function Scan.ReadListing(i, page, query)
    local name, texture, count, quality, _, _, minBid, _, buyout, bidAmount, highBidder, owner =
        GetAuctionItemInfo("list", i)
    if not name then return nil end
    local link = GetAuctionItemLink("list", i)
    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    buyout = tonumber(buyout) or 0
    bidAmount = tonumber(bidAmount) or 0
    return {
        index = i, page = page, query = query,
        name = name, texture = texture, quality = quality, link = link, itemId = ItemIdFromLink(link),
        count = count, buyout = buyout, unit = buyout > 0 and floor(buyout / count) or 0,
        bid = bidAmount > 0 and bidAmount or (tonumber(minBid) or 0),
        owner = owner, highBidder = highBidder,
        timeLeft = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("list", i) or nil,
    }
end

-- Full scan: cheapest unit buyout and number of listings per tome, and every
-- tome seen is learned (the catalogue grows with each scan).
local function ParseScanPage(job, batch)
    for i = 1, batch do
        local listing = Scan.ReadListing(i, job.page, job.query)
        if listing and ns.Catalog.IsTomeName(listing.name) then
            if ns.Catalog.LearnTome(listing.name, listing.itemId) then
                job.learned = job.learned + 1
            end
        end
        -- Exact match on the item id of the auction link; the name is only a fallback
        -- (a few item names differ from the tome spell names).
        local row = listing and ((listing.itemId and ns.Catalog.byItem[listing.itemId])
            or ns.Catalog.FindByTomeName(listing.name))
        if row and row.itemId then
            if listing.itemId then row.auctionItemId = listing.itemId end
            local acc = job.found[row.itemId]
            if not acc then
                acc = { listings = 0, min = 0 }
                job.found[row.itemId] = acc
            end
            acc.listings = acc.listings + 1
            if listing.unit > 0 and (acc.min == 0 or listing.unit < acc.min) then
                acc.min = listing.unit
            end
        end
    end
end

-- The name search is a substring match: keep only the listings of the searched tome
-- (by item id, or by name for a tome learned at the Auction House, keyed by its name).
local function BelongsTo(listing, job)
    local row = (listing.itemId and ns.Catalog.byItem[listing.itemId]) or ns.Catalog.FindByTomeName(listing.name)
    return row ~= nil and row.itemId == job.itemId
end

-- Exact search: keep the listings of that tome (the name search is a substring match).
local function ParseSearchPage(job, batch)
    for i = #job.listings, 1, -1 do
        if job.listings[i].page == job.page then tremove(job.listings, i) end
    end
    for i = 1, batch do
        local listing = Scan.ReadListing(i, job.page, job.query)
        if listing and BelongsTo(listing, job) then
            listing.itemId = job.itemId
            job.listings[#job.listings + 1] = listing
        end
    end
end

local function SortListings(listings)
    table.sort(listings, function(a, b)
        local au, bu = a.unit > 0 and a.unit or math.huge, b.unit > 0 and b.unit or math.huge
        if au ~= bu then return au < bu end
        if a.count ~= b.count then return a.count > b.count end
        return a.index < b.index
    end)
end

-- Price record of one tome from its listings (after an exact search).
local function StorePrice(itemId, listings)
    local min, count = 0, 0
    for _, listing in ipairs(listings) do
        count = count + 1
        if listing.unit > 0 and (min == 0 or listing.unit < min) then min = listing.unit end
    end
    ns.Prices.Set(itemId, min, count)
end

------------------------------------------------------------------------
-- Job life cycle
------------------------------------------------------------------------
local SendPage   -- forward declaration (Next and SendPage call each other)

local function Next()
    if Scan.job then return end
    local job = tremove(Scan.queue, 1)
    if not job then
        Notify()
        return
    end
    Scan.job = job
    job.waitSince = GetTime()
    SendPage(job)
end

local function Abort(job, message)
    if Scan.job == job then Scan.job = nil end
    job.aborted = true
    if message and not job.silent then ns.Print(message) end
    Notify()
    Next()
end

local function FinishScan(job)
    local priced, total = 0, 0
    for itemId, acc in pairs(job.found) do
        ns.Prices.Set(itemId, acc.min, acc.listings)
        total = total + 1
        if acc.min > 0 then priced = priced + 1 end
    end
    -- Tomes absent from a complete scan are not listed right now (their last
    -- price is kept as a reference).
    if job.complete then
        for itemId in pairs(ns.Prices.All()) do
            if not job.found[itemId] then ns.Prices.Set(itemId, 0, 0) end
        end
    end
    ns.Prices.SetLastScan(time())
    ns.Print(L.ScanDone, total, priced)
    if job.learned > 0 then
        ns.Print(L.ScanLearned, job.learned)
        ns.Fire("CATALOG_CHANGED")
    end
    ns.Fire("PRICES_CHANGED")
end

local function FinishSearch(job)
    SortListings(job.listings)
    Scan.results[job.itemId] = { at = time(), listings = job.listings, total = #job.listings }
    if not job.singlePage then
        StorePrice(job.itemId, job.listings)
        ns.Fire("PRICES_CHANGED")
    end
    ns.Fire("SEARCH_RESULTS", job.itemId)
    if job.onDone then job.onDone(job) end
end

local function Finish(job)
    if Scan.job == job then Scan.job = nil end
    job.done = true
    if job.kind == "scan" then FinishScan(job) else FinishSearch(job) end
    Notify()
    Next()
end

SendPage = function(job)
    if Scan.job ~= job or job.aborted then return end
    if not AHOpen() then
        Abort(job)
        return
    end
    if not (CanSendAuctionQuery and CanSendAuctionQuery()) then
        if GetTime() - job.waitSince > MAX_WAIT then
            Abort(job, L.AHNoAnswer)
        else
            ns.Timer.After(WAIT_STEP, function() SendPage(job) end)
        end
        return
    end
    generation = generation + 1
    job.gen = generation
    job.awaiting = true
    Scan.sending = true
    local ok = pcall(QueryAuctionItems, job.query, nil, nil, 0, 0, 0, job.page, false, nil)
    Scan.sending = false
    if not ok then
        Abort(job, L.ScanCancel)
        return
    end
    Scan.loaded = { query = job.query, page = job.page, itemId = job.itemId }
    local gen = job.gen
    ns.Timer.After(QUERY_TIMEOUT, function()
        if Scan.job == job and job.awaiting and job.gen == gen then
            job.retries = job.retries + 1
            if job.retries > MAX_PAGE_RETRIES then
                Abort(job, L.ScanCancel)
            else
                job.waitSince = GetTime()
                SendPage(job)
            end
        end
    end)
    Notify()
end

local function NewJob(kind, query, itemId)
    return {
        kind = kind, query = query, itemId = itemId,
        page = 0, total = 0, processed = 0, retries = 0, learned = 0,
        found = {}, listings = {},
    }
end

local function Enqueue(job, front)
    if front then tinsert(Scan.queue, 1, job) else Scan.queue[#Scan.queue + 1] = job end
    Next()
    Notify()
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
-- Full scan of every tome listing (clicking again cancels it).
function Scan.Start()
    if Scan.IsScanning() then
        Scan.Cancel()
        return
    end
    if not AHOpen() then
        ns.Print(L.NeedAH)
        return
    end
    -- A full scan makes the pending searches pointless.
    wipe(Scan.queue)
    if Scan.job then Abort(Scan.job) end
    local job = NewJob("scan", FULL_QUERY)
    job.complete = true
    Enqueue(job, true)
end

function Scan.Cancel()
    local job = Scan.job
    if not job then return end
    Scan.loaded = nil
    Abort(job, job.kind == "scan" and L.ScanCancel or nil)
end

-- Exact search of one tome. opts: front (run next), silent, onDone(job), page (that page only).
function Scan.Search(itemId, opts)
    opts = opts or {}
    local row = ns.Catalog.Get(itemId)
    if not row then return false end
    if not AHOpen() then
        if not opts.silent then ns.Print(L.NeedAH) end
        return false
    end
    local job = Scan.job
    if job and job.kind == "search" and job.itemId == itemId and not opts.page then return true end
    for i = #Scan.queue, 1, -1 do
        if Scan.queue[i].itemId == itemId then tremove(Scan.queue, i) end
    end
    local newJob = NewJob("search", Scan.QueryName(row), itemId)
    newJob.silent, newJob.onDone = opts.silent, opts.onDone
    if opts.page then
        newJob.page, newJob.singlePage = opts.page, true
        -- keep the other pages already known for this tome
        local known = Scan.results[itemId]
        if known then
            for _, listing in ipairs(known.listings) do
                if listing.page ~= opts.page then newJob.listings[#newJob.listings + 1] = listing end
            end
        end
    end
    Enqueue(newJob, opts.front ~= false)
    return true
end

-- Several searches in a row (wishlist refresh).
function Scan.SearchMany(itemIds)
    if not AHOpen() then
        ns.Print(L.NeedAH)
        return 0
    end
    local added = 0
    for _, itemId in ipairs(itemIds) do
        local row = ns.Catalog.Get(itemId)
        if row then
            local newJob = NewJob("search", Scan.QueryName(row), itemId)
            newJob.silent = true
            Scan.queue[#Scan.queue + 1] = newJob
            added = added + 1
        end
    end
    Next()
    Notify()
    return added
end

function Scan.IsScanning()
    return Scan.job ~= nil and Scan.job.kind == "scan"
end

function Scan.IsBusy()
    return Scan.job ~= nil or #Scan.queue > 0
end

function Scan.IsSearching(itemId)
    if Scan.job and Scan.job.kind == "search" and Scan.job.itemId == itemId then return true end
    for _, job in ipairs(Scan.queue) do
        if job.itemId == itemId then return true end
    end
    return false
end

-- For progress bars: kind, current page (1-based), known page count, jobs waiting, item.
function Scan.Progress()
    local job = Scan.job
    if not job then return nil, 0, 0, #Scan.queue end
    local pages = job.total > 0 and math.max(1, math.ceil(job.total / 50)) or 0
    return job.kind, job.page + 1, pages, #Scan.queue, job.itemId
end

function Scan.Results(itemId)
    return Scan.results[itemId]
end

-- Drops a listing that was just bought from the cached results.
function Scan.RemoveListing(listing)
    local result = listing and Scan.results[listing.itemId]
    if not result then return end
    for i = #result.listings, 1, -1 do
        if result.listings[i] == listing then tremove(result.listings, i) end
    end
    result.total = #result.listings
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
function Scan.OnAuctionUpdate()
    local job = Scan.job
    if not (job and job.awaiting) then
        -- The page we last loaded changed (owner names arriving, an auction bought):
        -- keep the cached listings of that tome in sync with it.
        local loaded = Scan.loaded
        local result = loaded and loaded.itemId and Scan.results[loaded.itemId]
        if result and not job then
            local fake = { page = loaded.page, query = loaded.query, itemId = loaded.itemId, listings = result.listings }
            ParseSearchPage(fake, tonumber((GetNumAuctionItems("list"))) or 0)
            SortListings(result.listings)
            result.total = #result.listings
            ns.Fire("SEARCH_RESULTS", loaded.itemId)
        end
        return
    end
    job.awaiting = false
    job.retries = 0
    local batch, total = GetNumAuctionItems("list")
    batch = tonumber(batch) or 0
    job.total = tonumber(total) or batch
    if job.kind == "scan" then
        ParseScanPage(job, batch)
    else
        ParseSearchPage(job, batch)
    end
    job.processed = job.processed + batch
    local maxPages = job.kind == "scan" and SCAN_MAX_PAGES or SEARCH_MAX_PAGES
    local more = not job.singlePage and batch > 0 and job.processed < job.total and job.page + 1 < maxPages
    if more then
        job.page = job.page + 1
        ns.Timer.After(PAGE_DELAY, function()
            job.waitSince = GetTime()
            SendPage(job)
        end)
        Notify()
    else
        if job.kind == "scan" and job.processed < job.total then
            job.complete = false   -- stopped at the page limit: absent tomes may still be listed
        end
        Finish(job)
    end
end

function Scan.OnAHClosed()
    wipe(Scan.queue)
    Scan.loaded = nil
    if Scan.job then Abort(Scan.job) end
end

ns.RegisterEvent("AUCTION_ITEM_LIST_UPDATE", Scan.OnAuctionUpdate)
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", Scan.OnAHClosed)

-- A query sent by someone else (Browse tab, another addon) replaces the "list"
-- results: what we loaded is gone.
if type(QueryAuctionItems) == "function" then
    hooksecurefunc("QueryAuctionItems", function()
        if not Scan.sending then Scan.loaded = nil end
    end)
end

------------------------------------------------------------------------
-- Tomes sitting in the player's bags also teach the catalogue (no AH needed).
------------------------------------------------------------------------
function Scan.ScanBags(announce)
    local learned = 0
    for bag = 0, NUM_BAG_SLOTS do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            local name = link and link:match("|h%[(.-)%]|h") or nil
            if name and ns.Catalog.IsTomeName(name) then
                if ns.Catalog.LearnTome(name, ItemIdFromLink(link)) then
                    learned = learned + 1
                end
            end
        end
    end
    if learned > 0 then
        if announce then ns.Print(L.BagsLearned, learned) end
        ns.Fire("CATALOG_CHANGED")
    end
    return learned
end
