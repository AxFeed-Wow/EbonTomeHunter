local addonName, ns = ...
local L = ns.L

-- The network through EbonAPI (by Siphelis, github.com/Siphelis/EbonAPI): a separate addon each
-- player installs, never shipped nor changed here (its licence forbids both). KEPT ASIDE since
-- 3.4.0, while it does not work with the server's v2 update: Net.lua uses Link.lua unless its
-- USE_EBONAPI is set, and then calls the functions below (the same as Link.lua's).
-- Every dataset of Net.lua is one EbonAPI dataset: EbonAPI spreads them from player to player
-- and keeps them in its saved data, also for players who do not run EbonTomeHunter. A client
-- takes a newer dataset (higher state), merges it and, when it knows more, publishes the union.
-- A dataset state is time() * 1000 plus a checksum of its text: two players who publish
-- different texts in the same second still get different states, or neither would take the
-- other's. A state more than a day in the future is refused (forged).
ns.NetApi = {}
local A = ns.NetApi

local API_NAME = "EbonTomeHunter"
local API_MAJOR, API_MINOR = 1, 0
local URL = "https://github.com/AxFeed-Wow/EbonTomeHunter"
local FUTURE = 86400
local STATE_SCALE = 1000

local api                     -- the EbonAPI handle; nil without EbonAPI (or when it is too old)
local apiReady = false

-- A state higher than the copy EbonAPI holds.
local function NextState(held, text)
    local sum = 0
    for i = 1, #text do sum = (sum * 31 + text:byte(i)) % STATE_SCALE end
    return math.max(time() * STATE_SCALE, (tonumber(held) or 0) + 1) + sum
end

-- Which datasets of ours to take (EbonAPI asks, on the receiving side): the kinds we know,
-- with a state higher than ours and not in the future.
local function Accept(name, theirState, myState)
    if not tostring(name or ""):match("^[TE]%d+$") then return false end
    local theirs = tonumber(theirState) or 0
    if theirs > (time() + FUTURE) * STATE_SCALE then return false end
    return myState == nil or theirs > (tonumber(myState) or 0)
end
A.Accept = Accept

local function OnShareReceived(_, addon, name, _, sender)
    if addon ~= API_NAME or not ns.Net.Running() then return end
    local _, news = ns.Net.Import(name, api:GetShared(name), true)
    if news then ns.Net.Publish(name) end   -- (we know more than it said: the union again)
    ns.Net.Notify(sender)
end

-- Binds EbonTomeHunter to EbonAPI (loaded before us: OptionalDeps). False without it, or
-- when it is too old for us (EbonAPI then tells the player).
function A.Connect()
    if api then return true end
    if type(EbonAPI) ~= "table" or type(EbonAPI.NewAddon) ~= "function" then return false end
    local ok, handle = pcall(EbonAPI.NewAddon, EbonAPI, API_NAME, API_MAJOR, API_MINOR)
    if not (ok and type(handle) == "table") then return false end
    api = handle
    pcall(api.Version, api, ns.version, URL)
    api:ShareRule(Accept)
    api:On("SHARE_RECEIVED", OnShareReceived)
    api:On("CHANNEL_JOINED", function() ns.Net.Notify() end)
    api:On("CHANNEL_LOST", function() ns.Net.Notify() end)
    api:On("UPDATE_AVAILABLE", function(_, name)
        if name == API_NAME then ns.Net.TellUpdate() end
    end)
    api:On("READY", function()   -- sticky: runs right away when EbonAPI is already ready
        apiReady = true
        ns.Net.TransportReady()
    end)
    return true
end

function A.Ready() return apiReady end

-- Every dataset EbonAPI holds merged in, then ours published where they know less than we do.
function A.Start()
    local fresh = 0
    for _, name in ipairs(api:SharedNames() or {}) do
        local got, news = ns.Net.Import(name, api:GetShared(name), false)
        fresh = fresh + got
        if news then ns.Net.Publish(name) end
    end
    for _, name in ipairs(ns.Net.DatasetNames()) do ns.Net.Publish(name) end
    if fresh > 0 then ns.Print(L.NetReceived, fresh) end
end

function A.Stop() end   -- (EbonAPI goes on for its other addons; Net.lua takes nothing meanwhile)

-- A dataset of ours changed: published when our text holds a line EbonAPI's copy lacks.
function A.Changed(name)
    local text = ns.Net.DatasetText(name)
    local held, state = api:GetShared(name)
    if text ~= "" and ns.Net.HasNews(text, held) then
        pcall(api.Share, api, name, NextState(state, text), text)
    end
end

function A.Joined() return api:IsChannelJoined() and true or false end
function A.Sync() return api:SyncShares() end
function A.Say(op, body) return api:Say(op, body) end
function A.Listen(op, fn) api:OnChannel(op, fn) end
function A.Newer() return (api:AvailableUpdate()) end

function A.Count()
    local n = 0
    for _, name in ipairs(api:SharedNames() or {}) do
        if name:sub(1, 1) == "T" then n = n + 1 end
    end
    return n
end
