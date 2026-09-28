local addonName, ns = ...
local L = ns.L

-- Which mob dropped a tome that the Greedy Scavenger looted (no loot window, no corpse,
-- no chat line: Loot.lua only knows the mobs killed in the last minute). Each candidate is
-- weighed against the server's drop hint of the tome (ProjectEbonhold's Echo journal, read
-- in game, never copied: "Can be found on enemies that cast Frostbolt / Slow", "... on
-- Beast-type enemies (...)", "... on Lord Marrowgar") and against the known sources:
--  * strong: its name is the one of the hint, it was seen casting a spell of the hint
--    (combat log), its creature type is the one of the hint;
--  * medium: its class fits the hint ("Mage-type"), it is a known source of the tome;
--  * weak: its name has a word of the hint ("Fire Elemental" -> "Flame", "Ember"...).
-- One mob standing out gives the drop its mob; otherwise the best candidates are kept
-- (Net.lua sends them, and each new drop at the same place narrows the list).
-- The spell names are the English ones of the hints: other client languages only use the
-- names, classes, creature types and known sources.
ns.Hints = {}
local H = ns.Hints

local MAX_CANDIDATES = 4
local STRONG, MEDIUM, WEAK = 3, 2, 1

------------------------------------------------------------------------
-- What the game shows of the mobs around: class and creature type, per NPC id
------------------------------------------------------------------------
local unitInfo = {}   -- [npcId] = { class = "MAGE", ctype = "beast" }; this session only
local unitCount = 0

-- Creature types of the hints, in the languages of the client (UnitCreatureType is localized).
local CREATURE_TYPES = {
    beast = { "beast", "bête", "wildtier", "bestia" },
    demon = { "demon", "démon", "dämon", "demonio" },
    dragon = { "dragonkin", "draconien", "drachkin", "dragón" },
    elemental = { "elemental", "élémentaire", "elementar" },
    giant = { "giant", "géant", "riese", "gigante" },
    mechanical = { "mechanical", "machine", "mechanisch", "mecánico" },
    undead = { "undead", "mort-vivant", "untoter", "no-muerto" },
}
local TYPE_OF = {}
for key, names in pairs(CREATURE_TYPES) do
    for _, name in ipairs(names) do TYPE_OF[name] = key end
end

local function LearnUnit(unit)
    if not (unit and UnitExists(unit)) or UnitIsPlayer(unit) then return end
    local npcId = ns.Wowhead.NpcIdFromGUID(UnitGUID(unit))
    if not npcId or unitInfo[npcId] then return end
    if unitCount >= 2000 then
        wipe(unitInfo)
        unitCount = 0
    end
    local _, class = UnitClass(unit)
    local ctype = UnitCreatureType(unit)
    unitInfo[npcId] = { class = class, ctype = ctype and TYPE_OF[strlower(ctype)] or nil }
    unitCount = unitCount + 1
end
H.LearnUnit = LearnUnit

function H.UnitInfo(npcId)
    return unitInfo[tonumber(npcId) or -1]
end

ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() LearnUnit("mouseover") end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() LearnUnit("target") end)
-- The Ebonhold client gives every nameplate a real unit ("nameplate1"...: ProjectEbonhold's
-- nameplates module), and announces them when its extension has the event.
ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) LearnUnit(unit) end)
local plateScan = CreateFrame("Frame")
local plateElapsed = 0
plateScan:SetScript("OnUpdate", function(self, elapsed)
    plateElapsed = plateElapsed + (elapsed or 0)
    if plateElapsed < 2 then return end
    plateElapsed = 0
    if not UnitAffectingCombat("player") then return end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if not UnitExists(unit) then break end
        LearnUnit(unit)
    end
end)

------------------------------------------------------------------------
-- The hint of a tome as a test on a mob
------------------------------------------------------------------------
-- Spells of the classic classes (their English names), for "Mage-type enemies", "enemies
-- that use Rogue-type spells"...
local CLASS_SPELLS = {
    mage = { "frostbolt", "fireball", "arcane missiles", "fire blast", "frost nova", "blizzard", "polymorph",
        "arcane explosion", "flamestrike", "cone of cold", "scorch", "pyroblast", "ice lance", "frost armor",
        "ice armor", "mana shield", "arcane bolt", "slow", "counterspell", "blink", "ice barrier",
        "dragon's breath", "blast wave", "arcane blast", "frostfire bolt", "living bomb" },
    rogue = { "sinister strike", "backstab", "eviscerate", "kick", "gouge", "kidney shot", "cheap shot", "sap",
        "blind", "garrote", "rupture", "ambush", "deadly poison", "crippling poison", "wound poison",
        "instant poison", "mind-numbing poison", "evasion", "sprint", "vanish", "fan of knives", "mutilate",
        "hemorrhage", "shiv", "expose armor", "slice and dice", "envenom" },
    warrior = { "heroic strike", "cleave", "mortal strike", "thunder clap", "demoralizing shout", "battle shout",
        "charge", "intercept", "hamstring", "rend", "sunder armor", "shield bash", "shield block", "shield slam",
        "revenge", "taunt", "execute", "whirlwind", "bladestorm", "shockwave", "disarm", "pummel", "overpower",
        "intimidating shout", "piercing howl", "retaliation", "shield wall", "bloodthirst", "slam", "enrage" },
    paladin = { "holy light", "flash of light", "hammer of justice", "consecration", "exorcism",
        "divine shield", "judgement", "holy shock", "avenger's shield", "hammer of wrath", "lay on hands",
        "divine storm", "crusader strike", "holy wrath", "seal of command", "seal of righteousness" },
    priest = { "smite", "holy fire", "mind blast", "shadow word: pain", "power word: shield", "renew", "heal",
        "flash heal", "greater heal", "binding heal", "prayer of healing", "psychic scream", "mind flay",
        "shadow word: death", "dispel magic", "inner fire", "holy nova", "mana burn", "mind control",
        "devouring plague", "vampiric touch" },
    warlock = { "shadow bolt", "corruption", "curse of agony", "curse of weakness", "curse of tongues",
        "immolate", "fear", "drain life", "drain soul", "drain mana", "death coil", "howl of terror",
        "rain of fire", "hellfire", "shadowflame", "shadowfury", "searing pain", "incinerate", "soul fire",
        "unstable affliction", "haunt", "seed of corruption", "banish", "demon armor", "demon skin",
        "shadow ward", "chaos bolt" },
    druid = { "moonfire", "wrath", "starfire", "entangling roots", "rejuvenation", "healing touch", "regrowth",
        "thorns", "hurricane", "starfall", "swipe", "maul", "mangle", "rake", "rip", "shred", "insect swarm",
        "faerie fire", "cyclone", "lifebloom", "nourish", "wild growth", "bash", "tranquility" },
    shaman = { "lightning bolt", "chain lightning", "lava burst", "earth shock", "flame shock", "frost shock",
        "healing wave", "lesser healing wave", "chain heal", "lightning shield", "water shield",
        "earthbind totem", "searing totem", "stormstrike", "lava lash", "thunderstorm", "hex", "purge",
        "bloodlust", "heroism", "riptide", "earth shield", "healing stream totem", "fire nova" },
    deathknight = { "death coil", "icy touch", "plague strike", "death grip", "blood strike", "obliterate",
        "heart strike", "scourge strike", "howling blast", "frost strike", "death and decay", "blood boil",
        "pestilence", "chains of ice", "mind freeze", "strangulate", "anti-magic shell", "rune strike",
        "army of the dead", "corpse explosion", "blood plague", "frost fever" },
}
local HEALS = {
    priest = { "heal", "flash heal", "greater heal", "binding heal", "prayer of healing", "renew" },
    paladin = { "holy light", "flash of light", "holy shock" },
    druid = { "healing touch", "rejuvenation", "regrowth", "lifebloom", "nourish", "wild growth" },
    shaman = { "healing wave", "lesser healing wave", "chain heal", "riptide" },
}
local PHRASES = {   -- generic parts of the hints
    ["stun"] = { "stun", "hammer of justice", "kidney shot", "cheap shot", "bash", "war stomp",
        "concussion blow", "shockwave", "intercept", "charge stun" },
    ["disarm"] = { "disarm", "dismantle" },
    ["caster dots"] = { "corruption", "shadow word: pain", "immolate", "curse of agony", "moonfire",
        "insect swarm", "flame shock", "devouring plague", "vampiric touch", "unstable affliction" },
    ["hots"] = { "renew", "rejuvenation", "regrowth", "lifebloom", "riptide" },
    ["haste abilities"] = { "bloodlust", "heroism", "flurry", "frenzy", "enrage" },
}
local ELEMENT_WORDS = {
    fire = { "fire", "flame", "magma", "ember", "blaze", "inferno", "lava", "pyre", "burning", "cinder" },
    frost = { "frost", "ice", "snow", "glacier", "hail", "frozen", "chill", "rime", "cold" },
    ice = { "ice", "frost", "snow", "glacier", "hail", "frozen", "chill", "rime", "cold" },
    storm = { "storm", "lightning", "thunder", "air", "wind", "tempest", "cyclone", "gust", "static", "spark" },
    earth = { "earth", "rock", "stone", "crag", "boulder", "dust", "mud", "quake" },
    water = { "water", "tide", "sea", "wave", "aqua", "deep", "ocean", "flood", "brine" },
    arcane = { "arcane", "mana", "nether", "ley", "crystal", "wraith" },
    shadow = { "shadow", "void", "dark", "umbral", "gloom" },
}
-- "<X>-type enemies" of the hints: classes, spells and name words that fit
local ROLES = {
    mage = { classes = { MAGE = true }, spells = "mage" },
    archmage = { classes = { MAGE = true }, spells = "mage" },
    arcane = { classes = { MAGE = true }, spells = "mage", words = ELEMENT_WORDS.arcane },
    spellweaver = { classes = { MAGE = true }, spells = "mage" },
    rogue = { classes = { ROGUE = true }, spells = "rogue" },
    ["dual wielder"] = { classes = { ROGUE = true, WARRIOR = true } },
    warrior = { classes = { WARRIOR = true }, spells = "warrior" },
    ["soldier / defender"] = { classes = { WARRIOR = true, PALADIN = true }, spells = "warrior" },
    tank = { classes = { WARRIOR = true, PALADIN = true },
        extra = { "shield block", "shield bash", "sunder armor", "taunt", "shield slam", "revenge", "shield wall" } },
    gladiator = { classes = { WARRIOR = true }, spells = "warrior" },
    ["weapon master"] = { classes = { WARRIOR = true }, spells = "warrior" },
    ["armor / smith specialist"] = { classes = { WARRIOR = true, PALADIN = true } },
    warlock = { spells = "warlock" },
    shadow = { spells = "warlock", words = ELEMENT_WORDS.shadow, extra = { "shadow word: pain", "mind blast", "mind flay" } },
    druid = { spells = "druid" },
    ["death knight"] = { spells = "deathknight" },
    ["seer / spiritcaller"] = { spells = "shaman" },
    ["disease spreader"] = { words = { "plague", "disease", "blight", "pestil", "rot", "fester", "contagi" },
        extra = { "disease cloud", "plague cloud", "diseased spit", "infected bite", "plague strike", "devouring plague" } },
    ["ethereal / nexus / reality-manipulator"] = { words = { "ethereal", "nexus", "warp", "phase", "void", "arcane" } },
    ["ogre / giant"] = { ctype = "giant", words = { "ogre", "giant", "gronn", "magnataur" } },
    ["poison / bleed predator"] = { extra = { "poison", "venom spit", "deadly poison", "rend", "garrote", "rake", "rip",
        "infected wound", "poison bolt", "crippling poison" } },
}

local function AddAll(set, list)
    for _, spell in ipairs(list or {}) do set[spell] = true end
end

local function Split(text)
    local out = {}
    for part in text:gmatch("[^/,()]+") do
        part = strtrim(part)
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

-- The test of a hint text (English), nil when it tells nothing usable:
-- { names = { [lowercase name] }, spells = { [lowercase spell] }, ctype, classes, words }.
function H.Parse(text)
    if type(text) ~= "string" then return nil end
    local body = strlower(strtrim((text:gsub("^Can be found on ", ""):gsub("^Can be found in ", ""))))
    local m = { spells = {}, words = {} }
    -- "Beast-type enemies (Paladin, ...)": creature type; the classes are the player's
    local creature = body:match("^(%a+)%-type enemies %(")
    if creature and CREATURE_TYPES[creature] then
        m.ctype = creature
        return m
    end
    -- "Fire Elemental-type enemies"
    local element = body:match("^(%a+) elemental%-type enemies")
    if element then
        m.ctype = "elemental"
        for _, word in ipairs(ELEMENT_WORDS[element] or {}) do m.words[#m.words + 1] = word end
        return m
    end
    if body:match("^plague%-themed enemies") then
        local role = ROLES["disease spreader"]
        for _, word in ipairs(role.words) do m.words[#m.words + 1] = word end
        AddAll(m.spells, role.extra)
        return m
    end
    -- "Entangling Roots caster-type enemies"
    local caster = body:match("^(.-) caster%-type enemies")
    if caster then
        m.spells[caster] = true
        return m
    end
    -- "<role>-type enemies"
    local roleName = body:match("^(.-)%-type enemies")
    if roleName then
        local role = ROLES[roleName]
        if not role then return nil end
        m.classes = role.classes
        m.ctype = role.ctype
        if role.spells then AddAll(m.spells, CLASS_SPELLS[role.spells]) end
        AddAll(m.spells, role.extra)
        for _, word in ipairs(role.words or {}) do m.words[#m.words + 1] = word end
        return m
    end
    -- "enemies that cast / use / can ..."
    local list = body:match("^enemies that %a+ (.+)$")
    if list then
        -- "Priest / Paladin healing spells", "Shaman healing spells (Healing Wave / ...)"
        for class, heals in pairs(HEALS) do
            if list:find(class .. "[^;]-healing spells") then AddAll(m.spells, heals) end
        end
        for class in pairs(CLASS_SPELLS) do
            local label = class == "deathknight" and "death knight" or class
            if list:find(label .. "-type spells", 1, true) then AddAll(m.spells, CLASS_SPELLS[class]) end
        end
        for _, part in ipairs(Split(list)) do
            if PHRASES[part] then
                AddAll(m.spells, PHRASES[part])
            elseif part:find("dots and hots", 1, true) then
                AddAll(m.spells, PHRASES["caster dots"])
                AddAll(m.spells, PHRASES["hots"])
            elseif not part:find("spells", 1, true) and not part:find("abilities", 1, true) then
                m.spells[part] = true
            end
        end
        return next(m.spells) and m or nil
    end
    if body:find("enem", 1, true) then return nil end   -- "enemies with ...": nothing observable
    -- a creature: "Lord Marrowgar", "the Lich King"
    m.names = {}
    for _, name in ipairs(Split(body)) do m.names[(name:gsub("^the ", ""))] = true end
    return m
end

local parsed = {}   -- [hint text] = test or false

function H.Matcher(itemId)
    local row = ns.Catalog.Get(itemId)
    local text = row and ns.Catalog.DropHint(row)
    if not text then return nil end
    if parsed[text] == nil then parsed[text] = H.Parse(text) or false end
    return parsed[text] or nil
end

------------------------------------------------------------------------
-- Attribution
------------------------------------------------------------------------
-- Names and NPC ids of the known sources of a tome (every drop place of it, and the
-- creature named by its hint), as lowercase names and "#npcId".
function H.KnownSources(itemId)
    local keys = {}
    local row = ns.Catalog.Get(itemId)
    for _, loc in ipairs(ns.WorldMap.Locations(row)) do
        for _, text in ipairs(type(loc.mobs) == "table" and loc.mobs or {}) do
            for _, name in ipairs(ns.Wowhead.SplitMobs(text)) do
                keys[strlower(name)] = true
                local npcId = (type(loc.npcIds) == "table" and loc.npcIds[name]) or ns.Wowhead.NpcId(name)
                if npcId then keys["#" .. npcId] = true end
            end
        end
    end
    local test = H.Matcher(itemId)
    for name in pairs(test and test.names or {}) do keys[name] = true end
    return keys
end

-- Score of a killed mob for a tome (see the top of this file) and why.
function H.Score(mob, test, known)
    local score, why = 0, nil
    local name = strlower(mob.name or "")
    local short = name:gsub("^the ", "")
    local info = mob.npcId and unitInfo[mob.npcId]
    if test then
        if test.names and (test.names[name] or test.names[short]) then score, why = score + STRONG, "name" end
        for spell in pairs(mob.spells or {}) do
            if test.spells[spell] then
                score, why = score + STRONG, "spell"
                break
            end
        end
        if test.ctype and info and info.ctype then
            if info.ctype == test.ctype then score, why = score + STRONG, why or "type" else score = score - STRONG end
        end
        if test.classes and info and info.class then
            if test.classes[info.class] then score, why = score + MEDIUM, why or "class" else score = score - WEAK end
        end
        for _, word in ipairs(test.words or {}) do
            if name:find(word, 1, true) then
                score, why = score + WEAK, why or "word"
                break
            end
        end
    end
    if known[name] or known[short] or (mob.npcId and known["#" .. mob.npcId]) then
        score, why = score + MEDIUM, why or "source"
    end
    return score, why
end

-- The mob that dropped a tome among the kills of the last minute (most recent first):
-- mob, npcId, candidates, reason. The candidates (at most 4, each { npcId, name }) come when
-- no mob stands out; false when nothing was killed.
function H.Attribute(itemId, kills)
    if not kills or #kills == 0 then return nil, nil, false end
    local mobs, order = {}, {}
    for _, kill in ipairs(kills) do
        local key = kill.npcId or kill.name or "?"
        local mob = mobs[key]
        if not mob then
            mob = { name = kill.name, npcId = kill.npcId, spells = {} }
            mobs[key] = mob
            order[#order + 1] = mob
        end
        for spell, seen in pairs(kill.spells or {}) do
            if seen == true then mob.spells[spell] = true end   -- (the table also holds its count)
        end
    end
    if #order == 1 then return order[1].name, order[1].npcId, nil, "alone" end
    local test, known = H.Matcher(itemId), H.KnownSources(itemId)
    local best, second = -math.huge, -math.huge
    for _, mob in ipairs(order) do
        mob.score, mob.why = H.Score(mob, test, known)
        if mob.score > best then
            best, second = mob.score, best
        elseif mob.score > second then
            second = mob.score
        end
    end
    if best >= MEDIUM and best > second then
        for _, mob in ipairs(order) do
            if mob.score == best then return mob.name, mob.npcId, nil, mob.why end
        end
    end
    -- the best ones (a weak clue rules nobody out), the most recent first among equals
    local limit = best >= MEDIUM and best or -math.huge
    local ranked = {}
    for index, mob in ipairs(order) do
        mob.index = index
        if mob.score >= limit then ranked[#ranked + 1] = mob end
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.index < b.index
    end)
    local candidates = {}
    for i = 1, math.min(#ranked, MAX_CANDIDATES) do
        candidates[i] = { npcId = ranked[i].npcId, name = ranked[i].name }
    end
    return nil, nil, candidates, nil
end
