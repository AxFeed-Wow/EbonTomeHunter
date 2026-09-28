-- EbonTomeHunter Dev: records game data into EbonTomeHunterDevDB (SavedVariables) so that it
-- can be read outside the game. The client writes SavedVariables on /reload and on logout
-- only: run a command, then /reload, then read
--   WTF/Account/<account>/SavedVariables/EbonTomeHunterDev.lua
-- Developer tool: never shipped to players (tools/dev, outside the addon folder).
-- ProjectEbonhold is only READ, every access protected by pcall.
--
--   /ethdev dump        snapshot: echoes of ProjectEbonhold, echo and tome tooltips, learned
--                       echoes, checkpoints, services of ProjectEbonhold and their functions
--   /ethdev log on|off  journal: corpses opened, tomes looted, server messages (codes)
--   /ethdev scav on|off Greedy Scavenger investigation (EbonTomeHunterDevDB.scav): what the
--                       game shows around its loots, to find which corpse a tome came from
--   /ethdev stats       asks the users online (EbonTomeHunter 3.0.0+, through EbonAPI) for
--                       their kills per creature; the answers land in EbonTomeHunterDevDB.stats
--                       after 15 s
--   /ethdev clear       empties everything
--   /ethdev             status

local TOME_MIN, TOME_MAX = 300000, 301999
local ECHO_MIN, ECHO_MAX = 200000, 201999
local LOG_MAX = 3000
local SCAV_MAX = 4000

local db
local tip = CreateFrame("GameTooltip", "EbonTomeHunterDevTip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffETH Dev|r " .. tostring(text))
end

-- Text lines of a tooltip link ("item:301402", "spell:201402"), nil when not cached.
local function TooltipLines(link)
    tip:ClearLines()
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    if not pcall(tip.SetHyperlink, tip, link) then return nil end
    local lines = {}
    for i = 1, tip:NumLines() do
        local left = _G["EbonTomeHunterDevTipTextLeft" .. i]
        local right = _G["EbonTomeHunterDevTipTextRight" .. i]
        local l, r = left and left:GetText(), right and right:GetText()
        if l or r then lines[#lines + 1] = (l or "") .. ((r and r ~= "") and ("  |  " .. r) or "") end
    end
    tip:Hide()
    return #lines > 0 and lines or nil
end

-- Plain copy of a value: numbers, strings, booleans; tables to `depth` levels.
local function Copy(value, depth)
    local kind = type(value)
    if kind == "number" or kind == "string" or kind == "boolean" then return value end
    if kind ~= "table" or depth <= 0 then return kind end
    local out, n = {}, 0
    for k, v in pairs(value) do
        n = n + 1
        if n > 400 then out["..."] = "truncated" break end
        if type(k) == "number" or type(k) == "string" then out[k] = Copy(v, depth - 1) end
    end
    return out
end

local function PE()
    return type(ProjectEbonhold) == "table" and ProjectEbonhold or nil
end

local function Call(service, fn, ...)
    local pe = PE()
    local svc = pe and pe[service]
    if type(svc) ~= "table" or type(svc[fn]) ~= "function" then return nil end
    local ok, a = pcall(svc[fn], ...)
    return ok and a or nil
end

local function Log(kind, data)
    if not (db and db.logging) then return end
    data.kind, data.at, data.t = kind, time(), GetTime()
    local log = db.log
    log[#log + 1] = data
    while #log > LOG_MAX do table.remove(log, 1) end
end

------------------------------------------------------------------------
-- Snapshot
------------------------------------------------------------------------
local function Dump()
    local snap = { at = time(), date = date("%Y-%m-%d %H:%M:%S"), locale = GetLocale(),
        player = { class = select(2, UnitClass("player")), level = UnitLevel("player"), zone = GetRealZoneText() } }

    -- services of ProjectEbonhold: their functions and plain fields (structure, not the source)
    local pe = PE()
    snap.services = {}
    if pe then
        for name, value in pairs(pe) do
            if type(value) == "table" then
                local fns, fields = {}, {}
                for k, v in pairs(value) do
                    if type(v) == "function" then fns[#fns + 1] = tostring(k) else fields[#fields + 1] = tostring(k) .. ":" .. type(v) end
                end
                table.sort(fns)
                table.sort(fields)
                snap.services[name] = { functions = fns, fields = fields }
            else
                snap.services[name] = type(value)
            end
        end
    end

    -- echoes: ProjectEbonhold's database + the client's spell name and tooltip
    snap.echoes = {}
    local perks = pe and pe.PerkDatabase
    for id = ECHO_MIN, ECHO_MAX do
        local name = GetSpellInfo(id)
        local perk = type(perks) == "table" and perks[id] or nil
        if name or perk then
            snap.echoes[id] = { name = name, perk = Copy(perk, 2), tooltip = TooltipLines("spell:" .. id) }
        end
    end

    -- tomes: item tooltip (only the items the client has in its cache)
    snap.tomes = {}
    for id = TOME_MIN, TOME_MAX do
        local name, link, quality = GetItemInfo(id)
        local spell = GetSpellInfo(id)
        if name or spell then
            snap.tomes[id] = { name = name, spell = spell, quality = quality, tooltip = name and TooltipLines("item:" .. id) or nil }
        end
    end

    snap.discovered = Copy(Call("PerkService", "GetDiscoveredEchoes"), 1)
    -- our own kills per creature, counted by EbonTomeHunter
    snap.killStats = type(EbonTomeHunterDB) == "table" and Copy(EbonTomeHunterDB.killStats, 2) or nil
    snap.checkpoints = Copy(Call("CheckpointService", "GetCheckpoints"), 3)
    db.dump = snap
    local echoes, tomes = 0, 0
    for _ in pairs(snap.echoes) do echoes = echoes + 1 end
    for _ in pairs(snap.tomes) do tomes = tomes + 1 end
    Print(format("dump: %d echoes, %d tomes. Type /reload to write the file.", echoes, tomes))
end

------------------------------------------------------------------------
-- Journal
------------------------------------------------------------------------
local function NpcId(guid)
    if type(guid) ~= "string" or #guid < 12 then return nil end
    local high = strupper(guid:sub(3, 6))
    if high ~= "F130" and high ~= "F150" then return nil end
    return tonumber(guid:sub(7, 12), 16)
end

local function Where()
    local x, y = GetPlayerMapPosition("player")
    return { zone = GetRealZoneText(), sub = GetSubZoneText(), map = GetMapInfo(), x = x, y = y }
end

------------------------------------------------------------------------
-- Greedy Scavenger investigation
------------------------------------------------------------------------
-- The pet loots the corpses by itself: no loot window, and no chat line for its tomes.
-- Everything that might tell which corpse it took is recorded, with the time (GetTime):
-- the combat log lines that name it (or its GUID, met through its gossip menu) and the
-- deaths of creatures, monster emotes and says, system lines, loot and money lines, the
-- items gained or lost in the bags, money changes, loot windows, addon messages, and the
-- verdict of EbonTomeHunter (TOME_OBTAINED: the mob or the candidates, and the kills of the
-- last minute).
local scavGUID
local scavFrame = CreateFrame("Frame")
local bagCounts, bagsDirty, money = nil, false, nil

local function Scav(kind, data)
    if not (db and db.scavenging) then return end
    data.kind, data.at, data.t = kind, time(), GetTime()
    local log = db.scav
    log[#log + 1] = data
    while #log > SCAV_MAX do table.remove(log, 1) end
end

local function IsScavenger(name, guid)
    if guid and scavGUID and guid == scavGUID then return true end
    return type(name) == "string" and strlower(name):find("scaveng", 1, true) ~= nil
end

local function BagCounts()
    local counts = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local link = GetContainerItemLink(bag, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                local _, count = GetContainerItemInfo(bag, slot)
                counts[id] = (counts[id] or 0) + (count or 1)
            end
        end
    end
    return counts
end

-- The pet talks and emotes while it works ("Greedy Scavenger gnaws on the corpse": the lines
-- EbonClearance hides): creature lines are all kept; say, yell and emote lines only when they
-- name it (EbonClearance watches those too; a pet can be renamed: "Serv's Scavenger").
local SCAV_EVENTS = {
    "COMBAT_LOG_EVENT_UNFILTERED", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_WHISPER",
    "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY", "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "BAG_UPDATE",
    "ITEM_PUSH", "PLAYER_MONEY", "LOOT_OPENED", "LOOT_CLOSED", "GOSSIP_SHOW", "CHAT_MSG_ADDON",
}
local PLAYER_CHAT = { CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true }

local function Args(...)
    local args = {}
    for i = 1, math.min(select("#", ...), 16) do args[i] = tostring((select(i, ...))) end
    return args
end

scavFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- timestamp, subEvent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName...
        local _, subEvent, srcGUID, srcName, _, dstGUID, dstName, _, _, spellName = ...
        if IsScavenger(srcName, srcGUID) or IsScavenger(dstName, dstGUID) or IsScavenger(spellName) then
            Scav("combat", { args = Args(...) })
        elseif subEvent == "UNIT_DIED" and NpcId(dstGUID) then
            Scav("death", { name = dstName, npcId = NpcId(dstGUID), guid = dstGUID })
        end
    elseif event == "BAG_UPDATE" then
        bagsDirty = true   -- compared once the bags settle (next frame)
    elseif event == "PLAYER_MONEY" then
        local now = GetMoney()
        Scav("money", { delta = now - (money or now), total = now })
        money = now
    elseif event == "GOSSIP_SHOW" then
        local name, guid = UnitName("npc"), UnitGUID("npc")
        if IsScavenger(name) then
            scavGUID = guid
            Scav("scavenger", { name = name, guid = guid, npcId = NpcId(guid) })
        end
    elseif event == "LOOT_OPENED" or event == "LOOT_CLOSED" then
        Scav(event == "LOOT_OPENED" and "window" or "closed", { target = UnitName("target"),
            mouseover = UnitName("mouseover"), items = event == "LOOT_OPENED" and GetNumLootItems() or nil })
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        Scav("addon", { prefix = prefix, size = #tostring(message), head = tostring(message):sub(1, 200),
            channel = channel, from = sender })
    elseif PLAYER_CHAT[event] then
        local text, author = ...
        if IsScavenger(author) or IsScavenger(text) then Scav(strlower(event), { args = Args(...) }) end
    else
        -- chat lines, ITEM_PUSH (bag, icon): every argument as the game gives it
        Scav(strlower(event), { args = Args(...), where = event == "CHAT_MSG_LOOT" and Where() or nil })
    end
end)

scavFrame:SetScript("OnUpdate", function()
    if not bagsDirty then return end
    bagsDirty = false
    local now = BagCounts()
    local gained, lost = {}, {}
    for id, n in pairs(now) do
        local before = bagCounts and bagCounts[id] or 0
        if n > before then gained[id] = n - before end
    end
    for id, n in pairs(bagCounts or {}) do
        if (now[id] or 0) < n then lost[id] = n - (now[id] or 0) end
    end
    if bagCounts and (next(gained) or next(lost)) then Scav("bags", { gained = gained, lost = lost, where = Where() }) end
    bagCounts = now
end)

local function SetScavenging(on)
    db.scavenging = on or nil
    scavFrame:UnregisterAllEvents()
    if not on then return end
    for _, event in ipairs(SCAV_EVENTS) do pcall(scavFrame.RegisterEvent, scavFrame, event) end
    bagCounts, money = BagCounts(), GetMoney()
    Scav("start", { pet = UnitName("pet"), zone = GetRealZoneText() })
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= "EbonTomeHunterDev" then return end
        if type(EbonTomeHunterDevDB) ~= "table" then EbonTomeHunterDevDB = {} end
        db = EbonTomeHunterDevDB
        db.log = type(db.log) == "table" and db.log or {}
        db.scav = type(db.scav) == "table" and db.scav or {}
        db.stats = type(db.stats) == "table" and db.stats or {}
        if db.scavenging then SetScavenging(true) end
        -- answers to /ethdev stats, collected by EbonTomeHunter's network
        if type(EbonTomeHunter) == "table" and type(EbonTomeHunter.On) == "function" then
            EbonTomeHunter.On("NET_STATS", function(results)
                local n = 0
                for name, result in pairs(results) do
                    db.stats[name] = { at = time(), total = result.total, kills = result.kills }
                    n = n + 1
                end
                Print(format("stats: %d user(s) answered. Type /reload to write the file.", n))
            end)
            -- a tome that came without loot window: EbonTomeHunter's verdict, with the kills it weighed
            EbonTomeHunter.On("TOME_OBTAINED", function(itemId, mob, npcId, candidates, why, recent)
                local kills, cands = {}, {}
                for i, kill in ipairs(type(recent) == "table" and recent or {}) do
                    local spells = {}
                    for spell, seen in pairs(type(kill.spells) == "table" and kill.spells or {}) do
                        if seen == true then spells[#spells + 1] = spell end
                    end
                    kills[i] = { name = kill.name, npcId = kill.npcId, ago = GetTime() - (kill.at or 0), spells = spells }
                end
                for i, c in ipairs(type(candidates) == "table" and candidates or {}) do cands[i] = c.name end
                Scav("verdict", { itemId = itemId, mob = mob, npcId = npcId, why = why, candidates = cands, kills = kills })
            end)
        end
    elseif event == "LOOT_OPENED" then
        local unit = (UnitExists("mouseover") and UnitIsDead("mouseover") and "mouseover")
            or (UnitExists("target") and UnitIsDead("target") and "target") or nil
        local items = {}
        for i = 1, GetNumLootItems() do
            local link = GetLootSlotLink(i)
            if link then items[#items + 1] = link:match("|H(item:%d+)") or link end
        end
        Log("corpse", { name = unit and UnitName(unit), npcId = unit and NpcId(UnitGUID(unit)),
            where = Where(), items = items })
    elseif event == "CHAT_MSG_LOOT" then
        local id = tonumber(tostring(a1):match("|Hitem:(%d+)"))
        if id and id >= TOME_MIN and id <= TOME_MAX then Log("tome", { text = a1, itemId = id, where = Where() }) end
    elseif event == "CHAT_MSG_ADDON" and a1 == "AAM0x9" then
        local code = tostring(a2):match("^(%d+)")
        Log("server", { code = code, size = #tostring(a2), head = tostring(a2):sub(1, 200) })
    end
end)

SLASH_EBONTOMEHUNTERDEV1 = "/ethdev"
SlashCmdList["EBONTOMEHUNTERDEV"] = function(input)
    local command, argument = strtrim(tostring(input or "")):match("^(%S*)%s*(.-)$")
    command = strlower(command or "")
    if not db then return Print("not loaded yet") end
    if command == "dump" then
        Dump()
    elseif command == "log" then
        db.logging = strlower(argument) ~= "off"
        Print("journal " .. (db.logging and "on" or "off") .. " (" .. #db.log .. " entries)")
    elseif command == "scav" then
        SetScavenging(strlower(argument) ~= "off")
        Print("Scavenger investigation " .. (db.scavenging and "on" or "off") .. " (" .. #db.scav
            .. " entries). Kill, let the pet loot, then /reload to write the file.")
    elseif command == "stats" then
        local net = type(EbonTomeHunter) == "table" and EbonTomeHunter.Net
        if not (net and net.RequestStats) then return Print("EbonTomeHunter 3.0.0 or later needed") end
        if net.RequestStats() then
            Print("stats asked to the users online; answers in 15 s")
        else
            Print("not sent: network off, EbonAPI missing or not in its channel, or asked less than 30 s ago")
        end
    elseif command == "clear" then
        SetScavenging(false)
        wipe(db)
        db.log, db.scav, db.stats = {}, {}, {}
        Print("cleared")
    else
        Print(format("journal %s, %d entries; Scavenger investigation %s, %d entries; dump %s. "
            .. "Commands: dump, log on|off, scav on|off, stats, clear.", db.logging and "on" or "off", #db.log,
            db.scavenging and "on" or "off", #db.scav, db.dump and db.dump.date or "none"))
    end
end
