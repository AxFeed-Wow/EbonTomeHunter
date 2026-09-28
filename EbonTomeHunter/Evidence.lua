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
-- make bad luck very unlikely, or STALE_VOTES users reported it (the player's own report
-- marks it for them). A new drop clears everything before it.
-- Bad luck: a tome that drops 1 time in 200 can miss 500 corpses in a row (8 % of the
-- time), a rarer one far more. The drop rate of the source is estimated from every counter
-- (drops / corpses, plus a prior of 1 in 200 worth 200 corpses) and the source is stale only
-- past the number of corpses without the tome that bad luck gives less than 1 % of the time
-- (500 at least, 5000 at most). Another user weighs half of it at most: two users at least,
-- or the player alone.
-- Shared through EbonAPI (Net.lua), one dataset per tome, "E<itemId>": every counter and
-- report known for the tome, each player's own the newest one (stamp):
--   mob^player^corpses^since^lastDrop^totalCorpses^drops^report^stamp;...
--   mob = "#npcId", else its name; report = time of the player's "Gone?" (0: none)
ns.Evidence = {}
local E = ns.Evidence

E.STALE_KILLS = 500     -- corpses without the tome, at least
E.STALE_MAX = 5000      -- ... and at most, whatever the rate
E.STALE_VOTES = 3
local PRIOR_DROPS, PRIOR_CORPSES = 1, 200   -- what is assumed before any drop is seen: 1 in 200
local BAD_LUCK = 0.01   -- chance left to bad luck when a source is called stale
local SEND_EVERY = 25       -- a counter is published every 25 corpses
local CLOSE_GRACE = 5       -- loot lines can come just after the window closed
local MAX_PLAYERS = 50      -- per source

local corpse                -- the corpse being looted: { tomes = { [itemId] = key }, name, dropped }
local counted = {}          -- [guid] = true: a corpse opened twice counts once
local countedSize = 0

local function Data()
    local db = ns.DB
    if type(db.corpses) ~= "table" then db.corpses = {} end     -- [key] = { n, since, drop, total, drops, stamp }: ours
    if type(db.evidence) ~= "table" then db.evidence = {} end   -- [key][player] = { n, since, drop, total, drops, stamp }
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

-- The corpses and drops of a counter BEFORE its current run without the tome: the run itself
-- is what is being judged (counting it in the rate would push the threshold away forever).
local function History(c)
    local total, run = tonumber(c.total) or 0, tonumber(c.n) or 0
    return math.max(0, total - run), tonumber(c.drops) or 0
end

-- Drop rate of a source: the history of every counter (ours, the other users' last ones),
-- with the prior. Returns the rate and the corpses without the tome that make it stale.
function E.Threshold(itemId, keys)
    local corpses, evidence = Data()
    local drops, total = PRIOR_DROPS, PRIOR_CORPSES
    for _, key in ipairs(keys) do
        local k = Key(itemId, key)
        local counters = {}
        if corpses[k] then counters[1] = corpses[k] end
        for _, e in pairs(evidence[k] or {}) do counters[#counters + 1] = e end
        for _, c in ipairs(counters) do
            local seen, dropped = History(c)
            total, drops = total + seen, drops + dropped
        end
    end
    local rate = math.min(0.5, drops / total)
    local needed = math.ceil(math.log(BAD_LUCK) / math.log(1 - rate))
    return rate, math.max(E.STALE_KILLS, math.min(E.STALE_MAX, needed))
end

-- Is this mob a stale source of the tome? Returns stale, corpses without the tome since
-- the last drop, users who reported it, whether the player reported it, and how many
-- corpses give one drop on average.
function E.Verdict(itemId, name, npcId)
    itemId = tonumber(itemId)
    if not itemId or not name then return false, 0, 0, false end
    local keys = Keys(name, npcId)
    local lastDrop = LastDrop(itemId, keys)
    local rate, needed = E.Threshold(itemId, keys)
    local corpses, evidence, reports = Data()
    local kills, voters, mine, me = 0, 0, false, Me()
    for _, key in ipairs(keys) do
        local k = Key(itemId, key)
        local own = corpses[k]
        if own and (tonumber(own.since) or 0) >= lastDrop then kills = kills + (tonumber(own.n) or 0) end
        for _, e in pairs(evidence[k] or {}) do
            if (tonumber(e.since) or 0) >= lastDrop then
                kills = kills + math.min(tonumber(e.n) or 0, needed / 2)
            end
        end
        for player, at in pairs(reports[k] or {}) do
            if at > lastDrop then
                voters = voters + 1
                if player == me then mine = true end
            end
        end
    end
    local stale = kills >= needed or voters >= E.STALE_VOTES or mine
    return stale, kills, voters, mine, floor(1 / rate + 0.5), needed
end

-- How many times the tome was seen dropping from this mob: our counter and those of the
-- other players (each counts its own drops). Travel.lua and the catalogue put the most
-- farmed sources first.
function E.Drops(itemId, name, npcId)
    itemId = tonumber(itemId)
    if not itemId or not name then return 0 end
    local corpses, evidence = Data()
    local drops = 0
    for _, key in ipairs(Keys(name, npcId)) do
        local k = Key(itemId, key)
        drops = drops + (tonumber(corpses[k] and corpses[k].drops) or 0)
        for _, c in pairs(evidence[k] or {}) do drops = drops + (tonumber(c.drops) or 0) end
    end
    return drops
end

-- The reason shown next to a stale source.
function E.Reason(kills, voters, mine, oneIn, needed)
    if kills >= (needed or E.STALE_KILLS) then return format(L.StaleKills, kills, oneIn or 200) end
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

-- Our counter of a source (created for a report without any corpse counted yet).
local function Own(k)
    local corpses = Data()
    local c = corpses[k]
    if not c then
        c = { n = 0, since = time(), drop = 0 }
        corpses[k] = c
    end
    return c
end

-- Every entry held for a tome: { mob, player, counter, report }, ours included.
local function Entries(itemId)
    local corpses, evidence, reports = Data()
    local prefix, me, out = itemId .. "@", Me(), {}
    local function Entry(mob, player)
        for _, e in ipairs(out) do
            if e.mob == mob and e.player == player then return e end
        end
        local e = { mob = mob, player = player }
        out[#out + 1] = e
        return e
    end
    for k, c in pairs(corpses) do
        if k:sub(1, #prefix) == prefix and c.stamp then Entry(k:sub(#prefix + 1), me).counter = c end
    end
    for k, players in pairs(evidence) do
        if k:sub(1, #prefix) == prefix then
            for player, c in pairs(players) do
                if player ~= me then Entry(k:sub(#prefix + 1), player).counter = c end
            end
        end
    end
    for k, players in pairs(reports) do
        if k:sub(1, #prefix) == prefix then
            for player, at in pairs(players) do
                local e = Entry(k:sub(#prefix + 1), player)
                e.report = at
                if player == me then e.counter = e.counter or corpses[k] end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.mob ~= b.mob then return a.mob < b.mob end
        return a.player < b.player
    end)
    return out
end

-- The text of the tome's dataset E<itemId> (Net.lua): one line per source and player. EbonAPI
-- takes 32 KB per dataset: past TEXT_MAX, the newest lines are kept (the same choice on every
-- client, so that they all write the same text).
local TEXT_MAX = 30000
function E.SharedText(itemId)
    itemId = tonumber(itemId)
    if not itemId then return "" end
    local lines, size = {}, 0
    for i, e in ipairs(Entries(itemId)) do
        local c = e.counter or {}
        local text = table.concat({ e.mob, e.player, floor(tonumber(c.n) or 0), floor(tonumber(c.since) or 0),
            floor(tonumber(c.drop) or 0), floor(math.max(tonumber(c.total) or 0, tonumber(c.n) or 0)),
            floor(tonumber(c.drops) or 0), floor(tonumber(e.report) or 0), floor(tonumber(c.stamp) or 0) }, "^")
        lines[i] = { text = text, stamp = floor(tonumber(c.stamp) or 0), index = i }
        size = size + #text + 1
    end
    if size > TEXT_MAX then
        local newest = {}
        for i, line in ipairs(lines) do newest[i] = line end
        table.sort(newest, function(a, b)
            if a.stamp ~= b.stamp then return a.stamp > b.stamp end
            return a.text < b.text
        end)
        local keep, total = {}, 0
        for _, line in ipairs(newest) do
            if total + #line.text + 1 > TEXT_MAX then break end
            keep[line.index], total = true, total + #line.text + 1
        end
        for i = #lines, 1, -1 do
            if not keep[i] then tremove(lines, i) end
        end
    end
    local out = {}
    for i, line in ipairs(lines) do out[i] = line.text end
    return table.concat(out, ";")
end

-- The tomes that have evidence to share (Net.lua publishes them at start).
function E.SharedTomes()
    local out = {}
    local corpses, evidence, reports = Data()
    for _, tbl in ipairs({ corpses, evidence, reports }) do
        for k in pairs(tbl) do
            local itemId = tonumber(k:match("^(%d+)@"))
            if itemId then out[itemId] = true end
        end
    end
    return out
end

-- A dataset E<itemId> received: each player's entry is kept when newer than ours (its
-- stamp), our own too (a new computer gets its counters back). Returns true when we know
-- more than the dataset said (Net.lua publishes it again).
function E.ImportShared(itemId, text)
    itemId = tonumber(itemId)
    if not (itemId and ns.Catalog.Get(itemId)) then return false end
    local corpses, evidence, reports = Data()
    local me, changed = Me(), false
    for line in tostring(text or ""):gmatch("[^;]+") do
        local mob, player, n, since, drop, total, drops, report, stamp =
            line:match("^([^%^]+)%^([^%^]+)%^(%d+)%^(%d+)%^(%d+)%^(%d+)%^(%d+)%^(%d+)%^(%d+)$")
        n, since, drop, total, drops = tonumber(n), tonumber(since), tonumber(drop), tonumber(total), tonumber(drops)
        report, stamp = tonumber(report), tonumber(stamp)
        if mob and #mob <= 41 and #player <= 24 and not line:find("[|%c]") and n <= 100000 and drops <= total
            and total <= 1000000 and Plausible(since) and Plausible(drop) and Plausible(report) and Plausible(stamp) then
            local k = Key(itemId, mob)
            local held
            if player == me then held = corpses[k] else held = evidence[k] and evidence[k][player] end
            if not held or (tonumber(held.stamp) or 0) < stamp then
                local counter = { n = n, since = since, drop = drop, total = total, drops = drops, stamp = stamp }
                if player == me then corpses[k] = counter else Keep(evidence, k, player, counter) end
                Keep(reports, k, player, report > 0 and math.min(report, time()) or nil)
                changed = true
            end
        end
    end
    if changed then Changed() end
    return E.SharedText(itemId) ~= text
end

-- The player's report ("Gone?" button): on, or withdrawn. Shared right away.
function E.Report(itemId, name, npcId, on)
    local mob = E.MobKey(name, npcId)
    if not (tonumber(itemId) and mob) then return false end
    local _, _, reports = Data()
    local k = Key(itemId, mob)
    Keep(reports, k, Me(), on and time() or nil)
    Own(k).stamp = time()
    ns.Net.PublishEvidence(itemId)
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
-- A drop: the corpses without the tome start again from 0; the totals (every corpse, every
-- drop) keep the rate of the source.
local function Dropped(itemId, key)
    local corpses = Data()
    local k = Key(itemId, key)
    local old = corpses[k] or {}
    corpses[k] = { n = 0, since = time(), drop = time(), stamp = time(),
        total = math.max(tonumber(old.total) or 0, tonumber(old.n) or 0) + 1, drops = (tonumber(old.drops) or 0) + 1 }
    ns.Net.PublishEvidence(itemId)
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
            c.total = math.max(tonumber(c.total) or 0, c.n) + 1
            c.n = c.n + 1
            if c.n % SEND_EVERY == 0 then
                c.stamp = time()
                ns.Net.PublishEvidence(itemId)
                Changed()   -- the verdict may have turned (its threshold follows the drop rate)
            end
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
