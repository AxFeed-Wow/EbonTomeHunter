local addonName, ns = ...
local L = ns.L

-- Sources that no longer drop their tome. A source is a mob listed for a tome (by
-- EbonholdHub, or by a drop place of the network). Two kinds of evidence, shared on the
-- hidden channel (Net.lua):
--  * corpses looted without the tome: every user counts, per tome and mob, the corpses of
--    that mob it looted ITSELF since the tome last dropped from it. A looted corpse is a
--    sure "no": nobody else took its loot, and a group kill is counted once;
--  * reports: the "Gone?" button of the Sources window.
-- A source is marked, never removed, when since the last drop known anywhere the corpses
-- reach STALE_KILLS (another user weighs STALE_KILLS / 2 at most: two users at least, or
-- the player alone), or STALE_VOTES users reported it (the player's own report marks it
-- for them). A new drop clears everything before it.
-- Wire (types unknown to 2.0.0, which ignores them):
--   K  counters: itemId^mob^corpses^since^lastDrop;...    mob = "#npcId", else its name
--   V  reports:  itemId^mob^time;...                       time 0: report withdrawn
ns.Evidence = {}
local E = ns.Evidence

E.STALE_KILLS = 500
E.STALE_VOTES = 3
local SEND_EVERY = 25       -- a counter is announced every 25 corpses
local SEND_MIN = 10         -- counters below this stay home
local BUNDLE_GAP = 600      -- our counters and reports, sent again at most every 10 min
local CLOSE_GRACE = 5       -- loot lines can come just after the window closed
local MAX_PLAYERS = 50      -- per source

local corpse                -- the corpse being looted: { tomes = { [itemId] = key }, name, dropped }
local counted = {}          -- [guid] = true: a corpse opened twice counts once
local countedSize = 0
local lastBundle = -math.huge

local function Data()
    local db = ns.DB
    if type(db.corpses) ~= "table" then db.corpses = {} end     -- [key] = { n, since, drop }: ours
    if type(db.evidence) ~= "table" then db.evidence = {} end   -- [key][player] = { n, since, drop }
    if type(db.reports) ~= "table" then db.reports = {} end     -- [key][player] = time
    return db.corpses, db.evidence, db.reports
end

local function Me() return UnitName("player") end

-- "#1234" when the NPC id is known (the same in every client language), else the name.
function E.MobKey(name, npcId, nameOnly)
    npcId = not nameOnly and (tonumber(npcId) or (name and ns.Wowhead.NpcId(name))) or nil
    if npcId then return "#" .. npcId end
    local key = strlower(strtrim(tostring(name or ""))):gsub("[~%^;|]", "")
    return key ~= "" and key:sub(1, 40) or nil
end

-- Every key a source may have been counted under (id, and the name).
local function Keys(name, npcId)
    local keys, seen = {}, {}
    for _, key in ipairs({ E.MobKey(name, npcId), E.MobKey(name, nil, true) }) do
        if key and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    return keys
end

local function Key(itemId, mob) return itemId .. "@" .. mob end

-- Mobs listed as sources, and their tomes: [mob key] = { [itemId] = true }.
local index
local function Index()
    if index then return index end
    index = {}
    for _, row in ipairs(ns.Catalog.rows or {}) do
        for _, loc in ipairs(ns.WorldMap.Locations(row)) do
            for _, text in ipairs(type(loc.mobs) == "table" and loc.mobs or {}) do
                for _, name in ipairs(ns.Wowhead.SplitMobs(text)) do
                    local npcId = type(loc.npcIds) == "table" and loc.npcIds[name] or nil
                    for _, key in ipairs(Keys(name, npcId)) do
                        index[key] = index[key] or {}
                        index[key][row.itemId] = true
                    end
                end
            end
        end
    end
    return index
end
ns.On("CATALOG_CHANGED", function() index = nil end)

------------------------------------------------------------------------
-- Verdict
------------------------------------------------------------------------
-- The last time the tome is known to have dropped from this mob: ours, other users',
-- the drop places of the network.
local function LastDrop(itemId, keys)
    local corpses, evidence = Data()
    local last = 0
    local wanted = {}
    for _, key in ipairs(keys) do
        wanted[key] = true
        local own = corpses[Key(itemId, key)]
        if own then last = math.max(last, tonumber(own.drop) or 0) end
        for _, e in pairs(evidence[Key(itemId, key)] or {}) do last = math.max(last, tonumber(e.drop) or 0) end
    end
    for _, place in ipairs(ns.Net.Places(itemId) or {}) do
        if (place.npcId and wanted["#" .. place.npcId]) or (place.mob and wanted[E.MobKey(place.mob, nil, true)]) then
            last = math.max(last, tonumber(place.at) or 0)
        end
    end
    return last
end

-- Is this mob a stale source of the tome? Returns stale, corpses without the tome since
-- the last drop, users who reported it, whether the player reported it.
function E.Verdict(itemId, name, npcId)
    itemId = tonumber(itemId)
    if not itemId or not name then return false, 0, 0, false end
    local keys = Keys(name, npcId)
    local lastDrop = LastDrop(itemId, keys)
    local corpses, evidence, reports = Data()
    local kills, voters, mine, me = 0, 0, false, Me()
    for _, key in ipairs(keys) do
        local k = Key(itemId, key)
        local own = corpses[k]
        if own and (tonumber(own.since) or 0) >= lastDrop then kills = kills + (tonumber(own.n) or 0) end
        for _, e in pairs(evidence[k] or {}) do
            if (tonumber(e.since) or 0) >= lastDrop then
                kills = kills + math.min(tonumber(e.n) or 0, E.STALE_KILLS / 2)
            end
        end
        for player, at in pairs(reports[k] or {}) do
            if at > lastDrop then
                voters = voters + 1
                if player == me then mine = true end
            end
        end
    end
    return kills >= E.STALE_KILLS or voters >= E.STALE_VOTES or mine, kills, voters, mine
end

-- The reason shown next to a stale source.
function E.Reason(kills, voters, mine)
    if kills >= E.STALE_KILLS then return format(L.StaleKills, kills) end
    if voters >= E.STALE_VOTES then return format(L.StaleVotes, voters) end
    if mine then return L.StaleMine end
    return nil
end

-- A drop place whose every mob is stale (a place without mob never is).
function E.LocationStale(itemId, loc)
    local any = false
    for _, text in ipairs(type(loc.mobs) == "table" and loc.mobs or {}) do
        for _, name in ipairs(ns.Wowhead.SplitMobs(text)) do
            local npcId = type(loc.npcIds) == "table" and loc.npcIds[name] or nil
            if not E.Verdict(itemId, name, npcId) then return false end
            any = true
        end
    end
    return any
end

------------------------------------------------------------------------
-- Sharing
------------------------------------------------------------------------
local changePending = false
local function Changed()
    if changePending then return end
    changePending = true
    ns.Timer.After(1, function()
        changePending = false
        ns.Fire("SIGHTINGS_CHANGED")
    end)
end

-- Entries packed into as few messages as possible.
local function SendEntries(msgType, entries)
    local line = ""
    for _, entry in ipairs(entries) do
        if line ~= "" and 8 + #line + 1 + #entry > 240 then
            ns.Net.Send(msgType, line)
            line = ""
        end
        line = line == "" and entry or (line .. ";" .. entry)
    end
    if line ~= "" then ns.Net.Send(msgType, line) end
end

local function CounterEntry(key, c)
    local itemId, mob = key:match("^(%d+)@(.+)$")
    if not itemId then return nil end
    return table.concat({ itemId, mob, floor(tonumber(c.n) or 0), floor(tonumber(c.since) or 0),
        floor(tonumber(c.drop) or 0) }, "^")
end

-- All our counters and reports (a user just showed up): at most every 10 min.
local function SendBundle()
    if GetTime() - lastBundle < BUNDLE_GAP then return end
    lastBundle = GetTime()
    local corpses, _, reports = Data()
    local counters, votes, me = {}, {}, Me()
    for key, c in pairs(corpses) do
        if (tonumber(c.n) or 0) >= SEND_MIN then counters[#counters + 1] = CounterEntry(key, c) end
    end
    for key, players in pairs(reports) do
        if players[me] then votes[#votes + 1] = key:gsub("@", "^", 1) .. "^" .. floor(players[me]) end
    end
    SendEntries("K", counters)
    SendEntries("V", votes)
end
ns.On("NET_PEER_ARRIVED", SendBundle)

local function Plausible(stamp)
    local now = time()
    return stamp == 0 or (stamp <= now + 86400 and stamp >= now - 2 * 365 * 86400)
end

local function Keep(tbl, key, player, value)
    local players = tbl[key]
    if not players then
        players = {}
        tbl[key] = players
    end
    if value == nil or players[player] then
        players[player] = value
        return
    end
    local n = 0
    for _ in pairs(players) do n = n + 1 end
    if n < MAX_PLAYERS then players[player] = value end
end

ns.On("NET_MESSAGE", function(msgType, payload, author)
    if not author or author == "" or author == Me() then return end
    local _, evidence, reports = Data()
    local changed = false
    for entry in tostring(payload):gmatch("[^;]+") do
        if msgType == "K" then
            local itemId, mob, n, since, drop = entry:match("^(%d+)%^([^%^]+)%^(%d+)%^(%d+)%^(%d+)$")
            itemId, n, since, drop = tonumber(itemId), tonumber(n), tonumber(since), tonumber(drop)
            if itemId and ns.Catalog.Get(itemId) and #mob <= 41 and n <= 100000 and Plausible(since) and Plausible(drop) then
                Keep(evidence, Key(itemId, mob), author, { n = n, since = since, drop = drop })
                changed = true
            end
        elseif msgType == "V" then
            local itemId, mob, at = entry:match("^(%d+)%^([^%^]+)%^(%d+)$")
            itemId, at = tonumber(itemId), tonumber(at)
            if itemId and ns.Catalog.Get(itemId) and #mob <= 41 and Plausible(at) then
                Keep(reports, Key(itemId, mob), author, at > 0 and math.min(at, time()) or nil)
                changed = true
            end
        end
    end
    if changed then Changed() end
end)

-- The player's report ("Gone?" button): on, or withdrawn. Shared right away.
function E.Report(itemId, name, npcId, on)
    local mob = E.MobKey(name, npcId)
    if not (tonumber(itemId) and mob) then return false end
    local _, _, reports = Data()
    local at = on and time() or nil
    Keep(reports, Key(itemId, mob), Me(), at)
    ns.Net.Send("V", table.concat({ itemId, mob, at or 0 }, "^"))
    Changed()
    return true
end

function E.IsReported(itemId, name, npcId)
    local mob = E.MobKey(name, npcId)
    local _, _, reports = Data()
    local players = mob and reports[Key(itemId, mob)]
    return players ~= nil and players[Me()] ~= nil
end

------------------------------------------------------------------------
-- Our corpses (Loot.lua)
------------------------------------------------------------------------
local function Dropped(itemId, key)
    local corpses = Data()
    corpses[Key(itemId, key)] = { n = 0, since = time(), drop = time() }
end

local function Finish()
    local current = corpse
    corpse = nil
    if not current then return end
    local corpses = Data()
    for itemId, key in pairs(current.tomes) do
        if not current.dropped[itemId] then
            local k = Key(itemId, key)
            local c = corpses[k]
            if not c then
                c = { n = 0, since = time(), drop = 0 }
                corpses[k] = c
            end
            c.n = c.n + 1
            if c.n % SEND_EVERY == 0 then ns.Net.Send("K", CounterEntry(k, c)) end
            if c.n == E.STALE_KILLS then Changed() end
        end
    end
end

ns.On("CORPSE_OPENED", function(guid, name, npcId)
    Finish()
    if not guid or counted[guid] then return end
    if countedSize > 1000 then
        wipe(counted)
        countedSize = 0
    end
    counted[guid], countedSize = true, countedSize + 1
    local key = E.MobKey(name, npcId)
    if not key then return end
    local tomes = {}
    for _, k in ipairs(Keys(name, npcId)) do
        for itemId in pairs(Index()[k] or {}) do tomes[itemId] = key end
    end
    if next(tomes) then corpse = { tomes = tomes, name = name, dropped = {} } end
end)

ns.On("CORPSE_CLOSED", function()
    local current = corpse
    ns.Timer.After(CLOSE_GRACE, function()
        if corpse == current then Finish() end
    end)
end)

-- A tome looted from a corpse: that mob drops it (even when it was not a listed source).
ns.On("TOME_DROPPED", function(itemId, name, npcId)
    local key = E.MobKey(name, npcId)
    if not key then return end
    if corpse and corpse.name == name then corpse.dropped[itemId] = true end
    Dropped(itemId, key)
    Changed()
end)
