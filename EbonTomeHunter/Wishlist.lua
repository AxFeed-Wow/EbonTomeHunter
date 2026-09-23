local addonName, ns = ...
local L = ns.L

ns.Wishlist = {}
local Wish = ns.Wishlist

local function Store()
    if type(ns.CDB.wishlist) ~= "table" then ns.CDB.wishlist = {} end
    return ns.CDB.wishlist
end

function Wish.Has(itemId)
    itemId = ns.Key(itemId)
    if not itemId then return false end
    return Store()[itemId] ~= nil
end

function Wish.Get(itemId)
    itemId = ns.Key(itemId)
    if not itemId then return nil end
    return Store()[itemId]
end

function Wish.Add(itemId, qty)
    itemId = ns.Key(itemId)
    qty = tonumber(qty) or 1
    if not itemId or qty < 0 then return false end
    local store = Store()
    local entry = store[itemId]
    if not entry then
        if qty == 0 then return false end
        store[itemId] = { qty = qty }
        ns.Fire("WISHLIST_CHANGED")
        return true
    end
    entry.qty = entry.qty + qty
    if entry.qty <= 0 then
        store[itemId] = nil
    end
    ns.Fire("WISHLIST_CHANGED")
    return true
end

function Wish.Remove(itemId)
    itemId = ns.Key(itemId)
    if not itemId then return false end
    Store()[itemId] = nil
    ns.Fire("WISHLIST_CHANGED")
    return true
end

function Wish.SetQty(itemId, qty)
    itemId = ns.Key(itemId)
    qty = tonumber(qty) or 0
    if not itemId then return false end
    local store = Store()
    if qty <= 0 then
        store[itemId] = nil
    else
        local entry = store[itemId]
        if entry then
            entry.qty = qty
        else
            store[itemId] = { qty = qty }
        end
    end
    ns.Fire("WISHLIST_CHANGED")
    return true
end

function Wish.List()
    local out = {}
    local store = Store()
    for itemId in pairs(store) do
        local row = ns.Catalog.Get(itemId)
        local entry = store[itemId]
        out[#out + 1] = { itemId = itemId, row = row, entry = entry }
    end
    table.sort(out, function(a, b)
        local an = a.row and a.row.name or ""
        local bn = b.row and b.row.name or ""
        return an < bn
    end)
    return out
end

-- Bulk update from an imported list ({ itemId, qty } entries): "merge" adds the
-- missing tomes and keeps the larger quantity, "replace" drops everything else.
function Wish.ApplyImport(items, mode)
    local store = Store()
    if mode == "replace" then wipe(store) end
    local added, raised = 0, 0
    for _, item in ipairs(items) do
        local entry = store[item.itemId]
        if not entry then
            store[item.itemId] = { qty = item.qty }
            added = added + 1
        elseif item.qty > (entry.qty or 1) then
            entry.qty = item.qty
            raised = raised + 1
        end
    end
    ns.Fire("WISHLIST_CHANGED")
    return added, raised
end

function Wish.Count()
    local n = 0
    for _ in pairs(Store()) do
        n = n + 1
    end
    return n
end

function Wish.ComputeTotal()
    local total = 0
    local missing = 0
    local pricedCount = 0
    for itemId, entry in pairs(Store()) do
        local min = ns.Prices.GetMin(itemId)
        if min and min > 0 then
            total = total + min * (entry.qty or 1)
            pricedCount = pricedCount + 1
        else
            missing = missing + 1
        end
    end
    return total, missing, pricedCount
end
