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
--   /ethdev clear       empties everything
--   /ethdev             status

local TOME_MIN, TOME_MAX = 300000, 301999
local ECHO_MIN, ECHO_MAX = 200000, 201999
local LOG_MAX = 3000

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
    elseif command == "clear" then
        wipe(db)
        db.log = {}
        Print("cleared")
    else
        Print(format("journal %s, %d entries; dump %s. Commands: dump, log on|off, clear.",
            db.logging and "on" or "off", #db.log, db.dump and db.dump.date or "none"))
    end
end
