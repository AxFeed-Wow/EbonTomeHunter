local addonName, ns = ...
local L = ns.L

-- Is a tome already learned by the current character?
-- ProjectEbonhold keeps the character's echo discovery list (server message 530,
-- cached per character in its SavedVariables). As in its own tome tooltip, a tome
-- is learned when its echo is in that list: tome item id == echo spell id + 100000.
-- Read only: nothing is ever written into ProjectEbonhold's tables.
ns.Known = {}
local K = ns.Known

local ECHO_OFFSET = 100000
local SERVER_PREFIX = "AAM0x9"
local DISCOVERY_CODE = 530   -- SEND_ECHO_DISCOVERY

local function Discovered()
    local svc = ns.PE.Service("PerkService")
    if not (svc and type(svc.GetDiscoveredEchoes) == "function") then return nil end
    local ok, list = pcall(svc.GetDiscoveredEchoes)
    if ok and type(list) == "table" then return list end
    return nil
end

-- False when ProjectEbonhold is not there to tell.
function K.Available()
    return Discovered() ~= nil
end

-- true / false, or nil when it cannot be known (ProjectEbonhold not loaded).
function K.IsKnown(itemId)
    local list = Discovered()
    if not list then return nil end
    itemId = tonumber(itemId)
    if not itemId then return false end
    if list[itemId - ECHO_OFFSET] then return true end
    local row = ns.Catalog.Get(itemId)
    if row and type(row.echoes) == "table" then
        for _, echoId in ipairs(row.echoes) do
            if list[echoId] then return true end
        end
    end
    return false
end

-- Learned, but switched off in the Echo journal (out of the draw pool).
function K.IsDisabled(itemId)
    itemId = tonumber(itemId)
    if not itemId then return false end
    local svc = ns.PE.Service("PerkService")
    if not (svc and type(svc.IsTomeEchoDisabled) == "function") then return false end
    return ns.SafeCall(svc.IsTomeEchoDisabled, itemId - ECHO_OFFSET) == true
end

-- true, "disabled", false, or nil (unknown): what the badges show.
function K.State(itemId)
    local known = K.IsKnown(itemId)
    if known and K.IsDisabled(itemId) then return "disabled" end
    return known
end

-- Learned tomes of the catalogue: known, total (nil when unavailable).
function K.Count()
    if not K.Available() then return nil end
    local known, total = 0, 0
    for _, row in ipairs(ns.Catalog.rows) do
        total = total + 1
        if K.IsKnown(row.itemId) then known = known + 1 end
    end
    return known, total
end

------------------------------------------------------------------------
-- Live refresh
------------------------------------------------------------------------
local pending = false
local function Changed()
    if pending then return end
    pending = true
    ns.Timer.After(0.5, function()
        pending = false
        ns.Fire("KNOWN_CHANGED")
    end)
end
K.Changed = Changed

-- The discovery list arrives or changes with server message 530: only listened to
-- (ProjectEbonhold handles it; its list is read half a second later).
ns.RegisterEvent("CHAT_MSG_ADDON", function(prefix, message)
    if prefix ~= SERVER_PREFIX or type(message) ~= "string" then return end
    local code = tonumber(message:match("^(%d+)"))
    local ss = type(ProjectEbonhold) == "table" and ProjectEbonhold.SS
    local expected = type(ss) == "table" and tonumber(ss.SEND_ECHO_DISCOVERY) or DISCOVERY_CODE
    if code == expected then Changed() end
end)
ns.On("BAGS_CHANGED", Changed)   -- a tome used from the bags
ns.On("READY", Changed)
