local addonName, ns = ...
local L = ns.L

-- Sending a wishlist straight to another player (addon message, whisper).
--   WL:<id>:<part>:<parts>:<slice of the ETH1 string>   the wishlist, in slices
--   WLA:<id>:<tomes>                                     received (the addon answered)
--   WLN:<id>                                             refused (option off)
-- #prefix + #message must stay under 255 bytes on 3.3.5a.
ns.Comm = {}
local Comm = ns.Comm

local PREFIX = "ETH"
local SLICE = 200
local SEND_DELAY = 0.15
local ANSWER_TIMEOUT = 12
local OFFERS_PER_MINUTE = 3

local outbox = {}      -- { message, target }
local nextSend = 0
local waiting = {}     -- [id] = { target, count } until the other addon answers
local inbox = {}       -- [sender .. id] = { parts, got, total, at }
local offers = {}      -- [sender] = { times }

local function Opt() return ns.Opt() end

local sender = CreateFrame("Frame")
sender:Hide()
sender:SetScript("OnUpdate", function(self)
    if #outbox == 0 then
        self:Hide()
        return
    end
    if GetTime() < nextSend then return end
    local item = tremove(outbox, 1)
    pcall(SendAddonMessage, PREFIX, item.message, "WHISPER", item.target)
    nextSend = GetTime() + SEND_DELAY
end)

local function Send(message, target)
    outbox[#outbox + 1] = { message = message, target = target }
    sender:Show()
end

local function CleanName(name)
    name = strtrim(tostring(name or ""))
    if name == "" then return nil end
    return (name:gsub("^%l", strupper))   -- player names start with a capital
end

-- Sends the current wishlist to a player. Returns true when it left.
function Comm.SendWishlist(target)
    target = CleanName(target)
    if not target then
        ns.Print(L.SendNoName)
        return false
    end
    if strlower(target) == strlower(UnitName("player") or "") then
        ns.Print(L.SendSelf)
        return false
    end
    local text, count = ns.Share.ExportWishlist()
    if count == 0 then
        ns.Print(L.ShareEmpty)
        return false
    end
    local id = format("%04x", math.random(0, 65535))
    local parts = math.ceil(#text / SLICE)
    for i = 1, parts do
        Send(format("WL:%s:%d:%d:%s", id, i, parts, text:sub((i - 1) * SLICE + 1, i * SLICE)), target)
    end
    waiting[id] = { target = target, count = count }
    ns.Print(L.SendStarted, count, target)
    ns.Timer.After(ANSWER_TIMEOUT, function()
        if waiting[id] then
            waiting[id] = nil
            ns.Print(L.SendNoAnswer, target)
        end
    end)
    return true
end

-- Not more than a few offers a minute from the same player.
local function Flooding(from)
    local now = GetTime()
    local list = offers[from] or {}
    for i = #list, 1, -1 do
        if now - list[i] > 60 then tremove(list, i) end
    end
    list[#list + 1] = now
    offers[from] = list
    return #list > OFFERS_PER_MINUTE
end

local function OnWishlist(from, id, text)
    if Flooding(from) then return end
    if not Opt().receiveWishlists then
        Send("WLN:" .. id, from)
        return
    end
    local result = ns.Share.Decode(text)
    if not result or #result.items == 0 then return end
    Send(format("WLA:%s:%d", id, #result.items), from)
    ns.Print(L.ReceivedWishlist, from, #result.items)
    StaticPopup_Show("EBONTOMEHUNTER_WISHLIST_OFFER", from, #result.items, { from = from, text = text })
end

ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, message, channel, from)
    if prefix ~= PREFIX or channel ~= "WHISPER" or type(message) ~= "string" or not from then return end
    local kind, rest = message:match("^(%u+):(.*)$")
    if kind == "WL" then
        local id, part, total, slice = rest:match("^(%x+):(%d+):(%d+):(.*)$")
        part, total = tonumber(part), tonumber(total)
        if not (id and part and total) or total < 1 or total > 20 or part > total then return end
        local key = from .. id
        local entry = inbox[key]
        if not entry or GetTime() - entry.at > 60 then
            entry = { parts = {}, got = 0, total = total, at = GetTime() }
            inbox[key] = entry
        end
        if not entry.parts[part] then
            entry.parts[part] = slice
            entry.got = entry.got + 1
        end
        if entry.got == entry.total then
            inbox[key] = nil
            OnWishlist(from, id, table.concat(entry.parts, "", 1, entry.total))
        end
    elseif kind == "WLA" then
        local id, count = rest:match("^(%x+):(%d+)$")
        local job = id and waiting[id]
        if job then
            waiting[id] = nil
            ns.Print(L.SendDelivered, job.target, tonumber(count) or job.count)
        end
    elseif kind == "WLN" then
        local job = waiting[rest]
        if job then
            waiting[rest] = nil
            ns.Print(L.SendRefused, job.target)
        end
    end
end)

StaticPopupDialogs["EBONTOMEHUNTER_WISHLIST_OFFER"] = {
    text = L.OfferText,
    button1 = L.OfferView,
    button2 = L.OfferIgnore,
    OnAccept = function(self, data)
        data = data or self.data
        if data then ns.Share.ShowDialog(true, data.text) end
    end,
    timeout = 60,
    whileDead = 1,
    hideOnEscape = 1,
}
