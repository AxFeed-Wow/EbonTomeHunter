local addonName, ns = ...
local L = ns.L

-- Buying a listing found by an exact search (Scan.lua). PlaceAuctionBid() acts on
-- the auction at an INDEX of the page currently loaded: the auction is looked up
-- again (name, stack size, buyout, seller) right before buying, since the page may
-- have changed since it was displayed.
ns.Buy = {}
local Buy = ns.Buy

local PENDING_TIMEOUT = 6

Buy.pending = nil   -- { listing, at }

local function AHOpen()
    return AuctionFrame and AuctionFrame:IsShown() and true or false
end

-- ok, reason (for a disabled button or a refusal).
function Buy.Check(listing)
    if not listing then return false, L.BuySelect end
    if (listing.buyout or 0) <= 0 then return false, L.BuyBidOnly end
    if listing.owner and listing.owner == UnitName("player") then return false, L.BuyOwn end
    if (GetMoney() or 0) < listing.buyout then return false, L.BuyNoMoney end
    if Buy.pending then return false, L.BuyPending end
    return true
end

local function Same(listing, i)
    local name, _, count, _, _, _, _, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)
    if name ~= listing.name then return false end
    if (tonumber(count) or 1) ~= listing.count or (tonumber(buyout) or 0) ~= listing.buyout then return false end
    if listing.owner and owner and owner ~= listing.owner then return false end
    return true
end

-- Index of the listing on the page loaded right now, or nil (page changed, sold...).
function Buy.FindOnPage(listing)
    local loaded = ns.Scan.loaded
    if not (loaded and listing) then return nil end
    if loaded.query ~= listing.query or loaded.page ~= listing.page then return nil end
    local batch = tonumber((GetNumAuctionItems("list"))) or 0
    if listing.index and listing.index <= batch and Same(listing, listing.index) then
        return listing.index
    end
    for i = 1, batch do
        if Same(listing, i) then return i end   -- the page shifted (someone bought one)
    end
    return nil
end

function Buy.Confirm(listing)
    local label = format("%s x%d", listing.link or listing.name or "?", listing.count or 1)
    if ns.Known.IsKnown(listing.itemId) then
        label = label .. "\n|cffff8000" .. L.KnownYes .. "|r"
    end
    local dialog = StaticPopup_Show("EBONTOMEHUNTER_BUY", label, nil, listing)
    if dialog then dialog.data = listing end
    return dialog
end

-- Entry point of the Buy buttons (a click: hardware event).
function Buy.Request(listing)
    local ok, reason = Buy.Check(listing)
    if not ok then
        ns.Print(reason)
        return false
    end
    if not AHOpen() then
        ns.Print(L.NeedAH)
        return false
    end
    if not Buy.FindOnPage(listing) then
        -- Not on the page loaded now (another search since, second page of results):
        -- load its page, then ask for a confirmation (the purchase needs a click).
        ns.Print(L.BuyReloading)
        ns.Scan.Search(listing.itemId, { page = listing.page or 0, front = true, silent = true, onDone = function(job)
            for _, fresh in ipairs(job.listings) do
                if fresh.page == job.page and fresh.name == listing.name and fresh.count == listing.count
                    and fresh.buyout == listing.buyout and (not listing.owner or fresh.owner == listing.owner) then
                    Buy.Confirm(fresh)
                    return
                end
            end
            ns.Print(L.BuyGone)
        end })
        return false
    end
    if ns.Opt().confirmBuy then
        Buy.Confirm(listing)
    else
        Buy.Execute(listing)
    end
    return true
end

function Buy.Execute(listing)
    local ok, reason = Buy.Check(listing)
    if not ok then
        ns.Print(reason)
        return false
    end
    local index = AHOpen() and Buy.FindOnPage(listing) or nil
    if not index then
        ns.Print(L.BuyGone)
        if AHOpen() then ns.Scan.Search(listing.itemId, { front = true, silent = true }) end
        return false
    end
    Buy.pending = { listing = listing, at = GetTime() }
    PlaceAuctionBid("list", index, listing.buyout)
    ns.Fire("SCAN_STATE")
    ns.Timer.After(PENDING_TIMEOUT, function()
        if Buy.pending and Buy.pending.listing == listing then
            -- Neither "Bid accepted" nor an error: check the auction house again.
            Buy.pending = nil
            ns.Print(L.BuyUnconfirmed)
            if AHOpen() then ns.Scan.Search(listing.itemId, { front = true, silent = true }) end
            ns.Fire("SCAN_STATE")
        end
    end)
    return true
end

function Buy.OnSuccess()
    local pending = Buy.pending
    if not pending then return end
    Buy.pending = nil
    local listing = pending.listing
    ns.Scan.RemoveListing(listing)
    ns.Print(L.Bought, listing.link or listing.name, listing.count, ns.Widgets.Money(listing.buyout))
    if ns.Opt().buyUpdatesWishlist and ns.Wishlist.Has(listing.itemId) then
        local entry = ns.Wishlist.Get(listing.itemId)
        local left = (entry and entry.qty or 1) - listing.count
        ns.Wishlist.SetQty(listing.itemId, left)   -- fires WISHLIST_CHANGED
        if left <= 0 then ns.Print(L.WishlistDone, listing.name) end
    end
    ns.Fire("PURCHASE", listing)
    ns.Fire("SEARCH_RESULTS", listing.itemId)
    ns.Fire("SCAN_STATE")
end

function Buy.OnFailure(message)
    if not Buy.pending then return end
    local listing = Buy.pending.listing
    Buy.pending = nil
    ns.Print(L.BuyFailed, tostring(message))
    if AHOpen() then ns.Scan.Search(listing.itemId, { front = true, silent = true }) end
    ns.Fire("SCAN_STATE")
end

local WON_PATTERN = ERR_AUCTION_WON_S and ("^" .. ERR_AUCTION_WON_S:gsub("%%s", ".+") .. "$") or nil

ns.RegisterEvent("CHAT_MSG_SYSTEM", function(message)
    if not Buy.pending or type(message) ~= "string" then return end
    if message == ERR_AUCTION_BID_PLACED or (WON_PATTERN and message:find(WON_PATTERN)) then
        Buy.OnSuccess()
    end
end)

-- Errors the server answers a failed buyout with (unrelated errors are ignored).
local BUY_ERRORS = {}
for _, key in ipairs({ "ERR_NOT_ENOUGH_MONEY", "ERR_ITEM_NOT_FOUND", "ERR_AUCTION_BID_OWN",
    "ERR_AUCTION_HIGHER_BID", "ERR_AUCTION_DATABASE_ERROR", "ERR_AUCTION_RESTRICTED_ACCOUNT",
    "ERR_AUCTION_BID_INCREMENT", "ERR_AUCTION_MIN_BID" }) do
    local text = _G[key]
    if type(text) == "string" then BUY_ERRORS[text] = true end
end

ns.RegisterEvent("UI_ERROR_MESSAGE", function(message)
    if Buy.pending and BUY_ERRORS[message] then
        Buy.OnFailure(message)
    end
end)

ns.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    Buy.pending = nil
    StaticPopup_Hide("EBONTOMEHUNTER_BUY")
end)

StaticPopupDialogs["EBONTOMEHUNTER_BUY"] = {
    text = L.BuyConfirm,
    button1 = BUYOUT,
    button2 = CANCEL,
    hasMoneyFrame = 1,
    showAlert = 1,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnShow = function(self, data)
        data = data or self.data
        if data and self.moneyFrame then MoneyFrame_Update(self.moneyFrame, data.buyout) end
    end,
    OnAccept = function(self, data)
        Buy.Execute(data or self.data)
    end,
}
