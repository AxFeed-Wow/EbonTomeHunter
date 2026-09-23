-- wow_mock.lua -- a small, permissive WoW 3.3.5a client stand-in for load/boot smoke tests.
-- Driven by validate_addon.py. It is NOT an emulator: widgets remember a few values,
-- unknown widget methods are no-ops, and unknown API that exists on 3.3.5a (per
-- api_globals_335.txt) returns nil. Names that do NOT exist on 3.3.5a resolve to nil,
-- exactly like the real client, so calling them raises "attempt to call global".

WOWMOCK = { notes = {}, errors = {}, known = {}, meta = {}, saved = {}, own = {}, events = {}, withEbonhold = true }
local M = WOWMOCK
local realG = _G

local function note(msg) M.notes[#M.notes + 1] = msg end
local seenErr = {}
local function addError(msg)
    msg = tostring(msg)
    if not seenErr[msg] then
        seenErr[msg] = true
        M.errors[#M.errors + 1] = msg
    end
end

local function traceback(err)
    local tb = realG.debug.traceback(tostring(err), 2) or tostring(err)
    -- keep only addon frames, drop the mock's own lines
    local out = {}
    for line in string.gmatch(tb, "[^\n]+") do
        if not line:find("wow_mock", 1, true) and not line:find("%[C%]") then
            out[#out + 1] = line
        end
        if #out >= 6 then break end
    end
    return table.concat(out, "\n    ")
end

------------------------------------------------------------------------------
-- clock / timers
------------------------------------------------------------------------------
local now = 1000
local timers = {}

------------------------------------------------------------------------------
-- widgets
------------------------------------------------------------------------------
local allFrames = {}
local namedPrefixes = {}
local env -- forward

local Widget = {}
local widgetMeta = {}

local function NewWidget(kind, name, parent)
    local w = setmetatable({
        __kind = kind, __name = name, __parent = parent, __scripts = {}, __events = {},
        __shown = true, __w = 100, __h = 20, __alpha = 1, __scale = 1, __level = 1,
    }, widgetMeta)
    if kind == "Frame" or kind == "Button" or kind == "CheckButton" or kind == "Slider"
        or kind == "EditBox" or kind == "ScrollFrame" or kind == "StatusBar" or kind == "GameTooltip"
        or kind == "Cooldown" or kind == "Model" or kind == "PlayerModel" or kind == "MessageFrame"
        or kind == "ScrollingMessageFrame" or kind == "ColorSelect" or kind == "SimpleHTML" then
        allFrames[#allFrames + 1] = w
    end
    if type(name) == "string" and name ~= "" then
        if parent and name:find("$parent", 1, true) then
            name = name:gsub("%$parent", parent.__name or "")
            w.__name = name
        end
        env[name] = w
        namedPrefixes[name] = true
    end
    return w
end
M.NewWidget = NewWidget

local function noop() end

function Widget:SetScript(event, fn) self.__scripts[event] = fn end
function Widget:GetScript(event) return self.__scripts[event] end
function Widget:HookScript(event, fn)
    local prev = self.__scripts[event]
    if prev then
        self.__scripts[event] = function(...) prev(...); return fn(...) end
    else
        self.__scripts[event] = fn
    end
end
function Widget:RegisterEvent(event)
    if type(event) ~= "string" then error("RegisterEvent: event name must be a string", 2) end
    -- The real client raises on an event name it does not know, which aborts the
    -- rest of the file being loaded. Reproduce that exactly.
    if next(M.events) and not M.events[event] then
        error("Attempt to register unknown event \"" .. event .. "\" (it does not exist on 3.3.5a)", 2)
    end
    self.__events[event] = true
end
function Widget:UnregisterEvent(event) self.__events[event] = nil end
function Widget:RegisterAllEvents() self.__allEvents = true end
function Widget:UnregisterAllEvents() self.__events = {}; self.__allEvents = nil end
function Widget:IsEventRegistered(event) return self.__events[event] and 1 or nil end
function Widget:Show() self.__shown = true; local s = self.__scripts.OnShow; if s then M.Call(s, self) end end
function Widget:Hide() local was = self.__shown; self.__shown = false; local s = self.__scripts.OnHide; if s and was then M.Call(s, self) end end
function Widget:IsShown() return self.__shown and 1 or nil end
function Widget:IsVisible() return self.__shown and 1 or nil end
function Widget:SetWidth(v) self.__w = tonumber(v) or self.__w end
function Widget:SetHeight(v) self.__h = tonumber(v) or self.__h end
function Widget:SetSize(wd, ht) self.__w = tonumber(wd) or self.__w; self.__h = tonumber(ht) or self.__h end
function Widget:GetWidth() return self.__w end
function Widget:GetHeight() return self.__h end
function Widget:GetSize() return self.__w, self.__h end
function Widget:GetLeft() return 0 end
function Widget:GetRight() return self.__w end
function Widget:GetTop() return self.__h end
function Widget:GetBottom() return 0 end
function Widget:GetCenter() return self.__w / 2, self.__h / 2 end
function Widget:GetRect() return 0, 0, self.__w, self.__h end
-- Anchors are recorded so scenarios can check where things were placed.
local ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
    if type(point) ~= "string" or not ANCHOR_POINTS[point:upper()] then
        error("SetPoint: invalid anchor point " .. tostring(point), 2)
    end
    if type(relativeTo) == "number" then          -- SetPoint("TOPLEFT", x, y)
        relativeTo, relativePoint, x, y = self.__parent, point, relativeTo, relativePoint
    elseif relativePoint == nil or type(relativePoint) == "number" then  -- SetPoint(point, frame[, x, y])
        relativePoint, x, y = point, relativePoint, x
    end
    if type(relativePoint) ~= "string" or not ANCHOR_POINTS[relativePoint:upper()] then
        error("SetPoint: invalid relative point " .. tostring(relativePoint), 2)
    end
    self.__points = self.__points or {}
    for i, p in ipairs(self.__points) do
        if p[1] == point then table.remove(self.__points, i) break end
    end
    self.__points[#self.__points + 1] = { point, relativeTo or self.__parent, relativePoint, x or 0, y or 0 }
end
function Widget:ClearAllPoints() self.__points = nil end
function Widget:SetAllPoints(rel) self.__points = { { "TOPLEFT", rel or self.__parent, "TOPLEFT", 0, 0 },
    { "BOTTOMRIGHT", rel or self.__parent, "BOTTOMRIGHT", 0, 0 } } end
function Widget:GetNumPoints() return self.__points and #self.__points or 0 end
function Widget:GetPoint(i)
    local p = self.__points and self.__points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function Widget:SetAlpha(a) self.__alpha = tonumber(a) or 1 end
function Widget:GetAlpha() return self.__alpha end
function Widget:SetScale(s) self.__scale = tonumber(s) or 1 end
function Widget:GetScale() return self.__scale end
function Widget:GetEffectiveScale() return self.__scale end
function Widget:SetFrameLevel(l) self.__level = tonumber(l) or 1 end
function Widget:GetFrameLevel() return self.__level end
function Widget:GetFrameStrata() return self.__strata or "MEDIUM" end
function Widget:SetFrameStrata(s) self.__strata = s end
function Widget:GetParent() return self.__parent end
function Widget:SetParent(p) self.__parent = p end
function Widget:GetName() return self.__name end
function Widget:GetObjectType() return self.__kind end
function Widget:IsObjectType(t) return self.__kind == t end
function Widget:GetChildren() return end
function Widget:GetRegions() return end
function Widget:GetNumChildren() return 0 end
function Widget:SetText(t)
    self.__text = t
    -- Like the client, EditBox:SetText fires OnTextChanged (userInput = false).
    if self.__kind == "EditBox" then
        local s = self.__scripts.OnTextChanged
        if s then M.Call(s, self, false) end
    end
end
function Widget:GetText() if self.__text == nil and self.__kind == "EditBox" then return "" end return self.__text end
function Widget:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
function Widget:GetStringWidth() return #(tostring(self.__text or "")) * 7 end
function Widget:GetStringHeight() return 12 end
function Widget:GetNumber() return tonumber(self.__text) or 0 end
function Widget:SetNumber(n) self.__text = tostring(n) end
function Widget:SetTexture(t, g, b, a)
    if type(t) == "number" and g == nil then error("SetTexture(number) is not valid here -- use a path, or SetTexture(r, g, b, a)", 2) end
    self.__texture = t
end
function Widget:GetTexture() return self.__texture end
function Widget:SetChecked(v) self.__checked = v and true or false end
function Widget:GetChecked() return self.__checked and 1 or nil end
-- Like the client: the value is clamped to the range, OnValueChanged only fires on a change.
function Widget:SetValue(v)
    v = tonumber(v) or 0
    if self.__min and v < self.__min then v = self.__min end
    if self.__max and v > self.__max then v = self.__max end
    if v == (self.__value or 0) and self.__value ~= nil then return end
    self.__value = v
    local s = self.__scripts.OnValueChanged
    if s then M.Call(s, self, v) end
end
function Widget:GetValue() return self.__value or 0 end
function Widget:SetMinMaxValues(a, b)
    self.__min, self.__max = tonumber(a), tonumber(b)
    if self.__value and self.__max and self.__value > self.__max then self:SetValue(self.__max) end
end
function Widget:GetMinMaxValues() return self.__min or 0, self.__max or 1 end
function Widget:SetID(id) self.__id = id end
function Widget:GetID() return self.__id or 0 end
function Widget:IsMouseOver() return nil end
function Widget:IsEnabled()   -- ("x and nil or 1" would always give 1)
    if self.__disabled then return nil end
    return 1
end
function Widget:Enable() self.__disabled = nil end
function Widget:Disable() self.__disabled = true end
function Widget:SetVerticalScroll(v)
    self.__vscroll = tonumber(v) or 0
    local s = self.__scripts.OnVerticalScroll
    if s then M.Call(s, self, self.__vscroll) end
end
function Widget:GetVerticalScroll() return self.__vscroll or 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:EnableMouseWheel(v) self.__wheel = v and true or nil end
function Widget:IsMouseWheelEnabled() return self.__wheel and 1 or nil end
function Widget:GetHorizontalScroll() return 0 end
function Widget:SetScrollChild(c) self.__child = c end
function Widget:GetScrollChild() return self.__child end
function Widget:NumLines() return 0 end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Widget:SetFont(path, size) if type(path) ~= "string" then error("SetFont: font path must be a string", 2) end return 1 end
function Widget:GetTextColor() return 1, 1, 1, 1 end
function Widget:GetVertexColor() return 1, 1, 1, 1 end
function Widget:GetBackdrop() return self.__backdrop end
function Widget:SetBackdrop(b) self.__backdrop = b end
function Widget:GetBackdropColor() return 0, 0, 0, 1 end
function Widget:GetBackdropBorderColor() return 1, 1, 1, 1 end
function Widget:GetMovable() return self.__movable end
function Widget:SetMovable(v) self.__movable = v end
function Widget:IsMovable() return self.__movable end
function Widget:GetCursorPosition() return 0 end
function Widget:HasFocus() return nil end
function Widget:IsOwned() return nil end
function Widget:GetOwner() return self.__owner end
function Widget:SetOwner(o) self.__owner = o end
function Widget:GetUnit() return nil end
function Widget:GetItem() return nil end
function Widget:GetSpell() return nil end
function Widget:GetStatusBarTexture() return NewWidget("Texture", nil, self) end
function Widget:GetNormalTexture() return NewWidget("Texture", nil, self) end
function Widget:GetHighlightTexture() return NewWidget("Texture", nil, self) end
function Widget:GetPushedTexture() return NewWidget("Texture", nil, self) end
function Widget:GetCheckedTexture() return NewWidget("Texture", nil, self) end
function Widget:GetDisabledTexture() return NewWidget("Texture", nil, self) end
function Widget:GetFontString() return self.__fs or NewWidget("FontString", nil, self) end
function Widget:SetFontString(fs) self.__fs = fs end
function Widget:GetThumbTexture() return NewWidget("Texture", nil, self) end
function Widget:CreateTexture(name) return NewWidget("Texture", name, self) end
function Widget:CreateFontString(name) return NewWidget("FontString", name, self) end
function Widget:CreateAnimationGroup(name) return NewWidget("AnimationGroup", name, self) end
function Widget:CreateAnimation(kind, name) return NewWidget(kind or "Animation", name, self) end
function Widget:IsPlaying() return nil end
function Widget:GetDuration() return 0 end
function Widget:GetProgress() return 0 end
function Widget:GetHitRectInsets() return 0, 0, 0, 0 end
function Widget:GetMaxLetters() return 0 end
function Widget:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function Widget:GetStatusBarColor() return 1, 1, 1, 1 end
function Widget:GetMinResize() return 0, 0 end
function Widget:GetMaxResize() return 0, 0 end
function Widget:IsUserPlaced() return nil end
function Widget:GetDepth() return 0 end
function Widget:IsProtected() return nil end
function Widget:CanChangeProtectedState() return 1 end

-- Methods that do NOT exist on 3.3.5a: must fail like in game.
local RETAIL_METHODS = {
    SetColorTexture = true, SetShown = true, SetEnabled = true, SetAtlas = true, SetResizeBounds = true,
    SetClipsChildren = true, SetIgnoreParentScale = true, SetIgnoreParentAlpha = true, SetObeyStepOnDrag = true,
    RegisterUnitEvent = true, SetMouseClickEnabled = true, SetMouseMotionEnabled = true, SetFromAlpha = true,
    SetToAlpha = true, SetScaleFrom = true, SetScaleTo = true, GetScaledRect = true, SetFixedFrameStrata = true,
}

widgetMeta.__index = function(self, key)
    local m = Widget[key]
    if m then return m end
    if RETAIL_METHODS[key] then return nil end
    if type(key) == "string" and key:match("^[A-Z]") then return noop end -- unknown widget method
    return nil
end

------------------------------------------------------------------------------
-- environment
------------------------------------------------------------------------------
local API = {}
local chat = {}

-- Sub-regions that stock templates create as "$parent<Suffix>".
M.childSuffixes = {
    "^Text$", "^Label$", "^Low$", "^High$", "^Title$", "^TitleText$", "^Icon$", "^IconTexture$", "^Count$",
    "^Cooldown$", "^Border$", "^Left$", "^Right$", "^Middle$", "^NormalTexture$", "^HighlightTexture$",
    "^PushedTexture$", "^CloseButton$", "^ScrollBar$", "^ScrollBarScrollUpButton$", "^ScrollBarScrollDownButton$",
    "^ScrollBarThumbTexture$", "^ScrollChildFrame$", "^TextLeft%d+$", "^TextRight%d+$", "^Texture%d*$",
    "^Button%d+$", "^Tab%d+$", "^Name$", "^Background$", "^Bar$", "^Spark$", "^Header$", "^EditBox$",
}

-- FrameXML/known names ending like a widget become mock frames; everything else is a no-op function.
local WIDGET_SUFFIX = {
    "Frame%d*$", "Button%d*$", "Container$", "Scroll$", "ScrollBar$", "Bar%d*$", "Tooltip%d*$", "Panel%d*$",
    "Tab%d+$", "Text%d*$", "Icon%d*$", "Slider$", "Box$", "Background$", "Border$", "Portrait$", "Texture%d*$",
    "Label$", "Menu%d*$", "List%d*$", "Dialog$", "Popup%d+$", "Parent$", "Minimap$", "Anchor$", "Title$",
    "Model$", "Cooldown$", "Highlight$", "Glow$", "Flash$", "Overlay$", "Holder$", "Header$", "Footer$",
    -- Blizzard sub-frames of a named parent frame (AuctionFrameBrowse, MerchantItem3, ...)
    "Browse$", "Bid$", "Auctions$", "Detail$", "Details$", "Entry%d*$", "Item%d*$", "Row%d*$", "Page%d*$",
    "Status$", "Slot%d*$", "Edit$", "Search$", "Content$", "Child$", "Inset$", "Portrait$", "Backdrop$",
}
-- Server/extension globals are never auto-stubbed: InstallEbonhold() provides them explicitly,
-- RemoveEbonhold() makes them nil, so both code paths are exercised for real.
local NEVER_STUB = {}
for _, n in ipairs({
    "LibStub", "ProjectEbonhold", "ProjectEbonholdDB", "ProjectEbonholdOptionsService", "ProjectEbonholdEchoJournal",
    "ProjectEbonholdEchoJournalScroll", "ProjectEbonholdEchoJournalMyRunScroll", "ProjectEbonholdPlayerRunFrame",
    "EbonholdPlayerRunData", "ExtractionService", "TalentDatabase", "PerkDatabase", "utils", "HardmodeFrame",
    "SpecCustomNames", "EbonholdOpenURL", "EbonholdLog", "EbonholdWorldToScreen", "EbonholdGetPlayerPosition",
    "EbonholdRequestQuestPOI", "ExtBankOpen", "ExtBankMove", "ExtBankUnlock", "ExtBankSetActive", "ExtBank_OnPacket",
    "CheckPatches", "GetPatchCheckResult", "FetchLoginMessage", "GetLoginMessageResult",
    "C_Timer", "C_Json", "C_MountJournal", "C_NamePlate", "C_VoiceChat",
}) do NEVER_STUB[n] = true end

-- FrameXML windows that start HIDDEN in the real client (opened by an NPC, a key or a click):
-- a stub of one of these must not look open ("is the mailbox open?" checks).
local HIDDEN_AT_START = {}
for _, n in ipairs({
    "MerchantFrame", "BankFrame", "GuildBankFrame", "MailFrame", "OpenMailFrame", "TradeFrame", "AuctionFrame",
    "TradeSkillFrame", "QuestFrame", "QuestLogFrame", "GossipFrame", "LootFrame", "TaxiFrame", "ClassTrainerFrame",
    "CharacterFrame", "SpellBookFrame", "FriendsFrame", "InspectFrame", "GameMenuFrame", "InterfaceOptionsFrame",
    "ItemTextFrame", "PetStableFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "BarberShopFrame",
    "AchievementFrame", "CalendarFrame", "PlayerTalentFrame", "MacroFrame", "KeyBindingFrame", "HelpFrame",
    "LFDParentFrame", "PVPParentFrame", "WorldStateScoreFrame", "StaticPopup1", "StaticPopup2", "StaticPopup3",
    "StaticPopup4", "DropDownList1", "DropDownList2",
}) do HIDDEN_AT_START[n] = true end

local VERBS = {
    "Get", "Set", "Is", "Has", "Can", "Create", "Send", "Use", "Cast", "Toggle", "Show", "Hide", "Open",
    "Close", "Enable", "Disable", "Register", "Unregister", "Update", "Add", "Remove", "Clear", "Reset",
    "Request", "Query", "Select", "Pickup", "Accept", "Decline", "Load", "Reload", "Play", "Stop", "Start",
    "Cancel", "Delete", "Take", "Place", "Confirm", "Save", "Run", "Summon", "Learn", "Buy", "Sell", "Repair",
    "Equip", "Invite", "Join", "Leave", "Do", "Sort", "Expand", "Collapse", "Refresh", "Initiate", "Report",
    "Unit", "Find", "Check", "Apply", "Display", "Swap", "Split", "Drop", "Move", "Turn", "Jump", "Promote",
}

local function looksLikeWidget(name)
    if name:find("_", 1, true) or name:match("^[a-z]") then return false end
    for _, v in ipairs(VERBS) do
        local nextChar = name:sub(#v + 1, #v + 1)
        if name:sub(1, #v) == v and nextChar:match("[A-Z]") then return false end
    end
    for _, suffix in ipairs(WIDGET_SUFFIX) do
        if name:match(suffix) then return true end
    end
    return false
end

local function stubFor(name)
    if M.own[name] or M.saved[name] then return nil end -- the addon defines it itself
    if M.known[name] then
        if name:match("^[A-Z0-9_]+$") then
            return name -- GlobalStrings constant
        end
        if NEVER_STUB[name] then return nil end
        if looksLikeWidget(name) or HIDDEN_AT_START[name] then
            local frame = NewWidget("Frame", name, nil) -- FrameXML frame (BankFrame, InterfaceOptionsFramePanelContainer...)
            if HIDDEN_AT_START[name] then frame.__shown = false end
            return frame
        end
        return noop
    end
    -- children of named frames created from templates: MyFrameText, MyFrameScrollBar, ...
    for prefix in pairs(namedPrefixes) do
        if #name > #prefix and name:sub(1, #prefix) == prefix then
            local suffix = name:sub(#prefix + 1)
            for _, pat in ipairs(M.childSuffixes) do
                if suffix:match(pat) then
                    return NewWidget("Frame", name, env[prefix])
                end
            end
        end
    end
    return nil
end

local LUA_STD = {
    "assert", "collectgarbage", "error", "getfenv", "getmetatable", "ipairs", "loadstring", "next",
    "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "select", "setfenv", "setmetatable",
    "tonumber", "tostring", "type", "unpack", "xpcall", "coroutine", "math", "string", "table", "os",
    "debug", "_VERSION", "newproxy", "gcinfo",
}

env = setmetatable({}, {
    __index = function(t, k)
        local v = API[k]
        if v ~= nil then return v end
        v = stubFor(k)
        if v ~= nil then rawset(t, k, v) end
        return v
    end,
})
for _, k in ipairs(LUA_STD) do rawset(env, k, realG[k]) end
rawset(env, "_G", env)
M.env = env

-- WoW Lua helpers ---------------------------------------------------------------
API.strsplit = function(sep, s, limit)
    if type(s) ~= "string" then error("bad argument #2 to 'strsplit' (string expected)", 2) end
    local out, pos, n = {}, 1, 0
    local plain = true
    while true do
        if limit and n >= limit - 1 then break end
        local a, b = string.find(s, "[" .. sep:gsub("%p", "%%%0") .. "]", pos)
        if not a then break end
        out[#out + 1] = s:sub(pos, a - 1)
        pos = b + 1
        n = n + 1
    end
    out[#out + 1] = s:sub(pos)
    return unpack(out)
end
API.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
API.strtrim = function(s, chars)
    chars = chars and ("[" .. chars:gsub("%p", "%%%0") .. "]") or "%s"
    return (tostring(s):gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
end
API.strconcat = function(...) return table.concat({ ... }) end
API.strlower, API.strupper, API.strlen, API.strsub = string.lower, string.upper, string.len, string.sub
API.strfind, API.strmatch, API.strrep, API.strbyte, API.strchar = string.find, string.match, string.rep, string.byte, string.char
API.strrev, API.format, API.gsub, API.gmatch = string.reverse, string.format, string.gsub, string.gmatch
API.tinsert, API.tremove, API.sort, API.getn = table.insert, table.remove, table.sort, table.getn
API.floor, API.ceil, API.abs, API.max, API.min, API.random, API.sqrt = math.floor, math.ceil, math.abs, math.max, math.min, math.random, math.sqrt
API.mod, API.fmod, API.log, API.exp, API.sin, API.cos, API.rad, API.deg, API.atan2 = math.fmod, math.fmod, math.log, math.exp, math.sin, math.cos, math.rad, math.deg, math.atan2
API.date, API.time = os.date, os.time
API.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
API.tContains = function(t, v) for _, x in pairs(t) do if x == v then return 1 end end return nil end
API.tostringall = function(...) local r = {} for i = 1, select("#", ...) do r[i] = tostring((select(i, ...))) end return unpack(r) end
API.getglobal = function(n) return env[n] end
API.setglobal = function(n, v) env[n] = v end
API.debugstack = function() return "" end
API.debugprofilestop = function() return now * 1000 end
API.geterrorhandler = function() return addError end
API.seterrorhandler = noop
API.securecall = function(fn, ...) if type(fn) == "string" then fn = env[fn] end return fn(...) end
API.issecurevariable = function() return nil end
API.hooksecurefunc = function(tbl, name, fn)
    if type(tbl) == "string" then tbl, name, fn = env, tbl, name end
    local orig = tbl[name]
    if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2) end
    tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
do -- bit library (LuaBitOp subset shipped with the client)
    local function tobit(x) x = math.floor(tonumber(x) or 0) % 4294967296; if x >= 2147483648 then x = x - 4294967296 end return x end
    local function op(a, b, f)
        a, b = tonumber(a) % 4294967296, tonumber(b) % 4294967296
        local r, bitv = 0, 1
        for _ = 1, 32 do
            local x, y = a % 2, b % 2
            if f(x, y) then r = r + bitv end
            a, b, bitv = (a - x) / 2, (b - y) / 2, bitv * 2
        end
        return tobit(r)
    end
    API.bit = {
        tobit = tobit,
        band = function(a, b, ...) local r = op(a, b, function(x, y) return x == 1 and y == 1 end) if ... then return API.bit.band(r, ...) end return r end,
        bor = function(a, b, ...) local r = op(a, b, function(x, y) return x == 1 or y == 1 end) if ... then return API.bit.bor(r, ...) end return r end,
        bxor = function(a, b) return op(a, b, function(x, y) return x ~= y end) end,
        bnot = function(a) return tobit(-1 - tobit(a)) end,
        lshift = function(a, n) return tobit(tobit(a) * 2 ^ n) end,
        rshift = function(a, n) return tobit(math.floor((tonumber(a) % 4294967296) / 2 ^ n)) end,
    }
end

-- Core API ----------------------------------------------------------------------
API.GetTime = function() return now end
-- Stock scroll templates: the named children and script wiring of UIPanelTemplates.xml, so that
-- FauxScrollFrame_* and the mouse wheel behave like in game. The children are "$parent"-named:
-- a scroll frame created WITHOUT a name breaks FauxScrollFrame_Update in game, and here too.
local SCROLL_TEMPLATES = {
    FauxScrollFrameTemplate = true, FauxScrollFrameTemplateLight = true,
    UIPanelScrollFrameTemplate = true, UIPanelScrollFrameTemplate2 = true,
}
local function ApplyScrollTemplate(w, template)
    local name = w.__name
    if not name then return end
    local bar = NewWidget("Slider", name .. "ScrollBar", w)
    bar.__w, bar.__h = 16, 100
    NewWidget("Button", name .. "ScrollBarScrollUpButton", bar)
    NewWidget("Button", name .. "ScrollBarScrollDownButton", bar)
    if template:find("^Faux") then
        w.__child = NewWidget("Frame", name .. "ScrollChildFrame", w)
    end
    bar:SetMinMaxValues(0, 0)   -- ScrollFrame_OnLoad
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(self, value) self:GetParent():SetVerticalScroll(value) end)
    w.offset = 0
    w:SetScript("OnVerticalScroll", function(self, offset) bar:SetValue(offset) end)
    w:SetScript("OnMouseWheel", function(self, delta) env.ScrollFrameTemplate_OnMouseWheel(self, delta) end)
    w.__wheel = true
end

API.CreateFrame = function(kind, name, parent, template)
    if type(kind) ~= "string" then error("CreateFrame: frameType must be a string", 2) end
    if template == "BackdropTemplate" then error("Unknown template 'BackdropTemplate' (retail only)", 2) end
    local w = NewWidget(kind, name, parent)
    if kind == "GameTooltip" then w.__kind = "GameTooltip" end
    if type(template) == "string" then
        for t in template:gmatch("[^,%s]+") do
            if SCROLL_TEMPLATES[t] then ApplyScrollTemplate(w, t) end
        end
    end
    return w
end
API.UIParent = NewWidget("Frame", "UIParent"); API.UIParent.__w, API.UIParent.__h = 1920, 1080
API.WorldFrame = NewWidget("Frame", "WorldFrame")
API.Minimap = NewWidget("Minimap", "Minimap"); API.Minimap.__w, API.Minimap.__h = 140, 140
API.GameTooltip = NewWidget("GameTooltip", "GameTooltip")
API.ItemRefTooltip = NewWidget("GameTooltip", "ItemRefTooltip")
API.DEFAULT_CHAT_FRAME = NewWidget("ScrollingMessageFrame", "ChatFrame1")
API.DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) chat[#chat + 1] = tostring(msg) end
API.ChatFrame1 = API.DEFAULT_CHAT_FRAME
API.SlashCmdList = {}
API.StaticPopupDialogs = {}
API.StaticPopup_Show = function(which) if not API.StaticPopupDialogs[which] then error("StaticPopup_Show: unknown dialog " .. tostring(which), 2) end return NewWidget("Frame") end
API.StaticPopup_Hide = noop
API.UISpecialFrames = {}
M.optionPanels = {}
API.InterfaceOptions_AddCategory = function(panel)
    if type(panel) ~= "table" or not panel.name then error("InterfaceOptions_AddCategory: panel.name must be set before registering", 2) end
    M.optionPanels[#M.optionPanels + 1] = panel
end
API.InterfaceOptionsFrame_OpenToCategory = noop
API.UIDropDownMenu_CreateInfo = function() return {} end
API.UIDropDownMenu_Initialize = function(frame, init) if type(init) == "function" then M.Call(init, frame, 1) end end
API.UIDropDownMenu_GetSelectedValue = function() return nil end
-- FauxScrollFrame helpers: same logic as UIPanelTemplates.lua (3.3.5a).
API.FauxScrollFrame_Update = function(frame, numItems, numToDisplay, valueStep, button, smallWidth, bigWidth,
                                      highlightFrame, smallHighlightWidth, bigHighlightWidth, alwaysShowScrollBar)
    local frameName = frame:GetName()
    local scrollBar = env[frameName .. "ScrollBar"]
    local showScrollBar
    if numItems > numToDisplay or alwaysShowScrollBar then
        frame:Show()
        showScrollBar = 1
    else
        scrollBar:SetValue(0)
        frame:Hide()
    end
    if frame:IsShown() then
        local scrollFrameHeight, scrollChildHeight = 0, 0
        if numItems > 0 then
            scrollFrameHeight = math.max(0, (numItems - numToDisplay) * valueStep)
            scrollChildHeight = numItems * valueStep
        end
        scrollBar:SetMinMaxValues(0, scrollFrameHeight)
        local child = env[frameName .. "ScrollChildFrame"]
        if child then child:SetHeight(scrollChildHeight) end
    end
    return showScrollBar
end
API.FauxScrollFrame_GetOffset = function(frame) return frame.offset end
API.FauxScrollFrame_SetOffset = function(frame, offset) frame.offset = offset end
API.FauxScrollFrame_OnVerticalScroll = function(self, value, itemHeight, updateFunction)
    local scrollbar = env[self:GetName() .. "ScrollBar"]
    scrollbar:SetValue(value)
    self.offset = math.floor((value / itemHeight) + 0.5)
    if updateFunction then updateFunction(self) end
end
API.ScrollFrameTemplate_OnMouseWheel = function(self, value, scrollBar)
    scrollBar = scrollBar or env[self:GetName() .. "ScrollBar"]
    if value > 0 then
        scrollBar:SetValue(scrollBar:GetValue() - (scrollBar:GetHeight() / 2))
    else
        scrollBar:SetValue(scrollBar:GetValue() + (scrollBar:GetHeight() / 2))
    end
end
API.RAID_CLASS_COLORS = {}
for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    API.RAID_CLASS_COLORS[c] = { r = 1, g = 1, b = 1 }
end
API.ITEM_QUALITY_COLORS = {}
for q = 0, 7 do API.ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
API.GetItemQualityColor = function() return 1, 1, 1, "|cffffffff" end
API.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
API.UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
API.DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
API.NUM_BAG_SLOTS = 4
API.BANK_CONTAINER = -1
API.NUM_BANKBAGSLOTS = 7
API.MAX_PARTY_MEMBERS = 4
API.MAX_RAID_MEMBERS = 40
API.BOOKTYPE_SPELL = "spell"

API.UnitName = function(u) if u == "player" then return "Tester", nil end return nil end
API.UnitClass = function(u) return "Paladin", "PALADIN", 2 end
API.UnitRace = function() return "Human", "Human" end
API.UnitLevel = function() return 80 end
API.UnitGUID = function(u) if u == "player" then return "0x0000000000000001" end end
API.UnitExists = function(u) return u == "player" and 1 or nil end
API.UnitFactionGroup = function() return "Alliance", "Alliance" end
-- Scenario-controllable player state
M.player = { health = 1000, maxHealth = 1000, combat = false, dead = false }
API.UnitHealth = function(u) if u == "player" then return M.player.health end return 1000 end
API.UnitHealthMax = function(u) if u == "player" then return M.player.maxHealth end return 1000 end
API.UnitPower = function() return 100 end
API.UnitPowerMax = function() return 100 end
API.UnitPowerType = function() return 0, "MANA" end
API.UnitIsDead = function() return nil end
API.UnitIsDeadOrGhost = function(u) if u == "player" and M.player.dead then return 1 end return nil end
API.UnitAffectingCombat = function(u) if u == "player" and M.player.combat then return 1 end return nil end
API.UnitAura = function() return nil end
API.UnitBuff = function() return nil end
API.UnitDebuff = function() return nil end
API.UnitXP = function() return 0 end
API.UnitXPMax = function() return 1 end
API.InCombatLockdown = function() if M.player.combat then return 1 end return nil end
API.IsMounted = function() return nil end
API.IsFlying = function() return nil end
API.IsIndoors = function() return nil end
API.IsInInstance = function() return nil, "none" end
API.IsInGuild = function() return nil end
API.GetRealmName = function() return "Rogue-Lite (Live)" end
API.GetLocale = function() return M.locale or "enUS" end
API.GetBuildInfo = function() return "3.3.5", "12340", "Jun 24 2010", 30300 end
API.GetFramerate = function() return 60 end
API.GetNetStats = function() return 0, 0, 50 end
API.GetAddOnMetadata = function(addon, field) return M.meta[field] end
API.IsAddOnLoaded = function(name) return name == M.addonName and 1 or nil end
API.GetNumAddOns = function() return 1 end
API.GetNumPartyMembers = function() return 0 end
API.GetNumRaidMembers = function() return 0 end
API.GetMoney = function() return 1234567 end
API.GetZoneText = function() return "Elwynn Forest" end
API.GetRealZoneText = API.GetZoneText
API.GetSubZoneText = function() return "" end
API.GetMinimapZoneText = API.GetZoneText
API.GetContainerNumSlots = function(bag) if bag and bag >= 0 and bag <= 4 then return 16 end return 0 end
API.GetContainerNumFreeSlots = function() return 16, 0 end
API.GetContainerItemInfo = function() return nil end
API.GetContainerItemLink = function() return nil end
API.GetContainerItemID = function() return nil end
API.GetInventoryItemLink = function() return nil end
API.GetInventoryItemID = function() return nil end
API.GetItemInfo = function() return nil end
API.GetItemIcon = function() return "Interface\\Icons\\INV_Misc_QuestionMark" end
API.GetItemCount = function() return 0 end
API.GetSpellInfo = function(id)
    if id == nil then return nil end
    return "Spell " .. tostring(id), "", "Interface\\Icons\\INV_Misc_QuestionMark", 0, 0, 0, 0, 0, 0
end
API.GetSpellTexture = function() return "Interface\\Icons\\INV_Misc_QuestionMark" end
API.GetSpellCooldown = function() return 0, 0, 1 end
API.IsSpellKnown = function() return nil end
API.GetNumSpellTabs = function() return 0 end
API.GetNumCompanions = function() return 0 end
API.GetNumTalentTabs = function() return 3 end
API.GetTalentTabInfo = function(i) return "Tab" .. tostring(i), "Interface\\Icons\\INV_Misc_QuestionMark", 0, "bg" end
API.GetNumTalents = function() return 0 end
API.GetActiveTalentGroup = function() return 1 end
API.GetNumTalentGroups = function() return 1 end
API.GetUnspentTalentPoints = function() return 0 end
API.GetNumQuestLogEntries = function() return 0, 0 end
API.GetNumGossipOptions = function() return 0 end
API.GetGossipOptions = function() return end
API.GetGossipText = function() return "" end
-- Map API. GetMapContinents/GetMapZones return the names as MULTIPLE values on
-- 3.3.5a (a classic crash source when treated as a table).
API.GetMapContinents = function() return "Kalimdor", "Eastern Kingdoms", "Outland", "Northrend" end
API.GetMapZones = function(continent)
    if continent == 1 then return "Durotar", "Mulgore", "The Barrens" end
    if continent == 2 then return "Elwynn Forest", "Westfall", "Duskwood" end
    if continent == 3 then return "Hellfire Peninsula", "Zangarmarsh" end
    return "Borean Tundra", "Dragonblight"
end
API.GetCurrentMapContinent = function() return 2 end
API.GetCurrentMapZone = function() return 1 end
API.GetCurrentMapAreaID = function() return 31 end   -- Elwynn Forest (WorldMapArea id 30, + 1 on 3.3.5a)
API.GetMapInfo = function() return "Elwynn", 668 end  -- map file name, as in WorldMapArea.dbc
API.GetCurrentMapDungeonLevel = function() return 0 end
API.SetMapToCurrentZone = noop
API.SetMapZoom = noop
API.SetMapByID = noop
API.GetPlayerMapPosition = function(unit) if unit == "player" then return 0.45, 0.62 end return 0, 0 end
API.GetPlayerFacing = function() return 0 end
API.GetUnitSpeed = function() return 0 end

API.GetCursorPosition = function() return 960, 540 end
API.GetScreenWidth = function() return 1920 end
API.GetScreenHeight = function() return 1080 end
API.GetMouseFocus = function() return nil end
API.IsShiftKeyDown = function() return nil end
API.IsControlKeyDown = function() return nil end
API.IsAltKeyDown = function() return nil end
API.GetCVar = function() return "0" end
API.GetCVarBool = function() return nil end
API.GetBindingKey = function() return nil end
API.PlaySound = function(s) if type(s) == "number" then error("PlaySound expects a sound NAME string on 3.3.5a, got a number", 2) end end
API.PlaySoundFile = noop
API.RegisterAddonMessagePrefix = nil -- does not exist on 3.3.5a: code must guard it
API.SendAddonMessage = function(prefix, msg, chan, target)
    if type(prefix) ~= "string" or type(msg) ~= "string" then error("SendAddonMessage: prefix and message must be strings", 2) end
    if prefix:find("\t", 1, true) then error("SendAddonMessage: prefix may not contain a tab", 2) end
    if #prefix + #msg > 254 then error("SendAddonMessage: prefix+message longer than 254 bytes (" .. (#prefix + #msg) .. ")", 2) end
    if chan == "WHISPER" and not target then error("SendAddonMessage: WHISPER needs a target", 2) end
end
API.SendChatMessage = function(msg) if #tostring(msg) > 255 then error("SendChatMessage: message longer than 255 chars", 2) end end
API.ChatFrame_AddMessageEventFilter = noop
API.ChatFrame_RemoveMessageEventFilter = noop

------------------------------------------------------------------------------
-- Project Ebonhold (enabled in pass 1, removed in pass 2 to test fail-closed code)
------------------------------------------------------------------------------
function M.InstallEbonhold()
    local empty = function() return {} end
    API.ProjectEbonhold = {
        addonVersion = 100, modVersion = "mock",
        PerkDatabase = { [1000001] = { maxStack = 1, classMask = 1535, minLevel = 1, quality = 2, groupId = 0, requiredSpell = 0, comment = "Mock Echo - Rare" } },
        Perks = { grantedPerks = {}, lockedPerks = {}, discoveredEchoes = {} },
        PerkService = {
            GetCurrentChoice = function()
                if not M.boardVisible then return nil end
                return { { spellId = 1000001, quality = 3, isGuaranteed = true }, { spellId = 1000002, quality = 1 }, { spellId = 1000003, quality = 4, isFrozen = true } }
            end, GetGrantedPerks = empty, GetLockedPerks = empty,
            GetDiscoveredEchoes = empty, RequestGrantedPerks = noop, GetActiveEchoLoadout = empty,
            GetPendingRollsCount = function() return 0 end, GetMaximumPermanentEchoes = function() return 6 end,
            IsTomeEchoDisabled = function() return false end, GetServerBuildSlots = function() return nil end,
        },
        PlayerRunService = { GetCurrentData = function() return { soulPoints = 1000, soulPointsMax = 5000, soulPointsMultiplier = 1.5, remainingBanishes = 2, hasReachedMaxLevel = false } end },
        CheckpointService = { GetCheckpoints = empty, UseCheckpoint = noop },
        EchoJournal = { Show = noop, Toggle = noop },
        PerkUI = { Show = noop, UpdateSinglePerk = noop },
        GetPerkData = function() return nil end,
        GetTotalPerkCount = function() return 1 end,
        RequestLoadoutFromServer = noop,
    }
    API.ProjectEbonholdDB = { settings = {} }
    API.ExtractionService = { learnedAffixes = {}, RequestLearnedAffixes = noop }
    API.EbonholdOpenURL = noop
    API.EbonholdLog = noop
    API.EbonholdGetPlayerPosition = function() return 0, 0, 0, 0 end
    API.EbonholdWorldToScreen = function() return 0, 0, 10, 10 end
    API.EbonholdPlayerRunData = API.ProjectEbonhold.PlayerRunService.GetCurrentData()
    API.ProjectEbonholdOptionsService = { GetSetting = function() return nil end, SetSetting = noop }
    API.TalentDatabase = { [0] = { nodes = {}, links = {} } }
    API.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + (tonumber(delay) or 0), fn = fn } end }
    M.withEbonhold = true
end
function M.RemoveEbonhold()
    for k in pairs(NEVER_STUB) do
        API[k] = nil
        rawset(env, k, nil)
    end
    M.withEbonhold = false
end

------------------------------------------------------------------------------
-- driver
------------------------------------------------------------------------------
local BUDGET = 20000000 -- VM instructions allowed per handler before we call it an infinite loop
local function guarded(fn)
    return function(...)
        local prevHook, prevMask, prevCount = debug.gethook()
        debug.sethook(function() debug.sethook(); error("watchdog: handler exceeded " .. BUDGET .. " instructions (infinite loop?)", 2) end, "", BUDGET)
        local r = { pcall(fn, ...) }
        if prevHook then debug.sethook(prevHook, prevMask, prevCount) else debug.sethook() end
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2, table.maxn(r))
    end
end

function M.Call(fn, ...)
    local args = { n = select("#", ...), ... }
    local ok, err = xpcall(guarded(function() return fn(unpack(args, 1, args.n)) end), traceback)
    if not ok then addError(err) end
    return ok
end

function M.NewNamespace() return {} end

function M.SetKnown(list) for i = 1, #list do M.known[list[i]] = true end end

function M.SetEvents(list) for i = 1, #list do M.events[list[i]] = true end end

function M.SetConstants(src)
    local fn = loadstring(src, "@api_constants_335.lua")
    local ok, tbl = pcall(fn)
    if ok and type(tbl) == "table" then
        for k, v in pairs(tbl) do
            if API[k] == nil then API[k] = v end
        end
    end
end

function M.LoadFile(src, name, addonName, ns)
    M.addonName = addonName
    local fn, err = loadstring(src, "@" .. name)
    if not fn then return err end
    setfenv(fn, env)
    local ok, e = xpcall(guarded(function() return fn(addonName, ns) end), traceback)
    if not ok then return e end
    return nil
end

local function fire(event, ...)
    local snapshot = {}
    for i = 1, #allFrames do snapshot[i] = allFrames[i] end
    for _, f in ipairs(snapshot) do
        if (f.__events[event] or f.__allEvents) and f.__scripts.OnEvent then
            M.Call(f.__scripts.OnEvent, f, event, ...)
        end
    end
end

local function advance(seconds)
    local step = 0.1
    local t = 0
    while t < seconds do
        now = now + step
        t = t + step
        local snapshot = {}
        for i = 1, #allFrames do snapshot[i] = allFrames[i] end
        for _, f in ipairs(snapshot) do
            local s = f.__scripts.OnUpdate
            if s and f.__shown then M.Call(s, f, step) end
        end
        local due = {}
        for i = #timers, 1, -1 do
            if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
        end
        for _, tm in ipairs(due) do M.Call(tm.fn) end
    end
end

-- Scenario API (tests/scenario.lua inside the addon). Runs in the addon's
-- environment plus these helpers; any error or failed Check is reported.
function M.RunScenario(src)
    local fn, err = loadstring(src, "@tests/scenario.lua")
    if not fn then addError("scenario: " .. tostring(err)) return M.errors end
    local senv = setmetatable({
        Fire = fire,
        Advance = advance,
        Player = M.player,
        Chat = chat,
        Slash = function(text)
            local cmd, rest = text:match("^/(%S+)%s*(.-)$")
            for key, handler in pairs(env.SlashCmdList) do
                for i = 1, 3 do
                    local alias = rawget(env, "SLASH_" .. key .. i)
                    if alias and alias:lower() == "/" .. cmd:lower() then return handler(rest) end
                end
            end
            error("unknown slash command /" .. tostring(cmd), 2)
        end,
        ChatContains = function(needle)
            for _, line in ipairs(chat) do if line:find(needle, 1, true) then return true end end
            return false
        end,
        Check = function(cond, message)
            if not cond then addError("scenario check failed: " .. tostring(message)) end
        end,
        Note = note,
        CLEU = function(subEvent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
            fire("COMBAT_LOG_EVENT_UNFILTERED", now, subEvent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
        end,
    }, { __index = env, __newindex = env })
    setfenv(fn, senv)
    M.Call(fn)
    return M.errors
end

function M.Boot(addonName)
    M.addonName = addonName
    -- The client loads SavedVariables AFTER the addon's files have run, just before
    -- ADDON_LOADED: whatever the files stored in those globals is REPLACED. The run with
    -- ProjectEbonhold simulates a saved file from an older version (empty tables), the run
    -- without it a first launch (no file). Initialise the DB on ADDON_LOADED, not at load.
    if M.withEbonhold then
        for name in pairs(M.saved) do rawset(env, name, {}) end
    end
    fire("ADDON_LOADED", addonName)
    fire("VARIABLES_LOADED")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD")
    advance(3)
    -- exercise every slash command (usually opens the UI)
    local cmds = {}
    for key in pairs(env.SlashCmdList) do cmds[#cmds + 1] = key end
    table.sort(cmds)
    for _, key in ipairs(cmds) do
        if rawget(env, "SLASH_" .. key .. "1") == nil then
            addError("SlashCmdList." .. key .. " has no SLASH_" .. key .. "1 alias (command unreachable)")
        end
        local handler = env.SlashCmdList[key]
        if type(handler) == "function" then
            M.Call(handler, "", API.DEFAULT_CHAT_FRAME)
            M.Call(handler, "help", API.DEFAULT_CHAT_FRAME)
            advance(0.5)
            M.Call(handler, "", API.DEFAULT_CHAT_FRAME) -- toggle back
        end
        note("slash " .. tostring(rawget(env, "SLASH_" .. key .. "1") or key) .. " exercised")
    end
    -- open every Interface Options panel (builds lazily-created widgets), then close it
    for _, panel in ipairs(M.optionPanels) do
        panel:Show()
        for _, key in ipairs({ "refresh", "okay", "cancel" }) do
            if type(rawget(panel, key)) == "function" then M.Call(panel[key], panel) end
        end
        panel:Hide()
        note("options panel '" .. tostring(panel.name) .. "' opened")
    end
    -- simulate an Echo board appearing (with ProjectEbonhold only)
    M.boardVisible = true
    if API.ProjectEbonhold then
        for _, fnName in ipairs({ "Show", "UpdateSinglePerk" }) do
            local fn = API.ProjectEbonhold.PerkUI[fnName]
            if type(fn) == "function" then M.Call(fn) end
        end
    end
    advance(2)
    M.boardVisible = false
    advance(1.5)
    fire("BAG_UPDATE", 0)
    fire("PLAYER_REGEN_DISABLED")
    fire("PLAYER_REGEN_ENABLED")
    advance(2)
    fire("PLAYER_LOGOUT")
    note((M.withEbonhold and "with" or "WITHOUT") .. " ProjectEbonhold: " .. #allFrames .. " frame(s) created, " .. #chat .. " chat line(s) printed")
    return M.errors
end
