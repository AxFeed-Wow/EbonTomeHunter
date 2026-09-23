local addonName, ns = ...
local L = ns.L

ns.Prices = {}
local Prices = ns.Prices

local MAX_HISTORY = 20

-- [itemId] = { min = cheapest unit buyout last seen, listings = count at the last
--              look (0 = not listed), at = last look, seen = when `min` was seen,
--              prevMin, hist = { { at, min, listings } } }
function Prices.All()
    return ns.DB.prices
end

function Prices.Get(itemId)
    itemId = ns.Key(itemId)
    if not itemId then return nil end
    return ns.DB.prices[itemId]
end

-- Last known cheapest unit price (kept when the tome is not listed any more).
function Prices.GetMin(itemId)
    local rec = Prices.Get(itemId)
    if rec and rec.min and rec.min > 0 then
        return rec.min
    end
    return nil
end

function Prices.GetListings(itemId)
    local rec = Prices.Get(itemId)
    if rec then
        return rec.listings or 0
    end
    return 0
end

function Prices.IsListed(itemId)
    return Prices.GetListings(itemId) > 0
end

-- minBuyout = cheapest unit buyout now (0: none with a buyout), listings = count now.
function Prices.Set(itemId, minBuyout, listings)
    itemId = ns.Key(itemId)
    if not itemId then return end
    minBuyout = tonumber(minBuyout) or 0
    listings = tonumber(listings) or 0

    local prices = ns.DB.prices
    local rec = prices[itemId]
    if not rec then
        if minBuyout <= 0 and listings <= 0 then return end   -- never seen, not listed
        rec = { min = 0, listings = 0, at = 0, hist = {} }
        prices[itemId] = rec
    end

    local now = time()
    rec.listings = listings
    rec.at = now
    if minBuyout > 0 then
        if rec.min and rec.min > 0 and rec.min ~= minBuyout then
            rec.prevMin = rec.min
        end
        rec.min = minBuyout
        rec.seen = now
        local hist = rec.hist
        if type(hist) ~= "table" then
            hist = {}
            rec.hist = hist
        end
        hist[#hist + 1] = { at = now, min = minBuyout, listings = listings }
        while #hist > MAX_HISTORY do
            tremove(hist, 1)
        end
    end
end

function Prices.Clear(itemId)
    itemId = ns.Key(itemId)
    if not itemId then return end
    ns.DB.prices[itemId] = nil
end

function Prices.ClearAll()
    wipe(ns.DB.prices)
    ns.DB.lastScan = 0
    ns.Fire("PRICES_CHANGED")
end

function Prices.LastScan()
    return ns.DB.lastScan or 0
end

function Prices.SetLastScan(t)
    ns.DB.lastScan = tonumber(t) or time()
end

function Prices.PricedCount()
    local n = 0
    for _, rec in pairs(ns.DB.prices) do
        if rec and rec.min and rec.min > 0 then
            n = n + 1
        end
    end
    return n
end
