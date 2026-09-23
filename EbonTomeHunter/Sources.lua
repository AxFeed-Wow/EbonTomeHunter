local addonName, ns = ...
local L = ns.L
local W = ns.Widgets
local C = W.C

-- "Sources" window of a tome: every mob and place that drops it, nearest first by
-- teleport, each with its nearest unlocked checkpoint (TP) and the Wowhead page of
-- the mob (WotLK section; never an item page: Ebonhold's tomes are not on Wowhead).
ns.Sources = {}
local S = ns.Sources

local WIDTH = 580
local ROW_H = 44
local VISIBLE = 6

local frame, list, urlBox, hint

-- The link goes in the box, selected for Ctrl+C (no browser, no clipboard).
local function SelectURL(url)
    urlBox.url = url
    urlBox:SetText(url or "")
    urlBox:SetFocus()
    urlBox:HighlightText()
end

local function OpenWowhead(source)
    if not source.url then return end
    if ns.Wowhead.Open(source.url) then return end
    if type(CopyToClipboard) == "function" and pcall(CopyToClipboard, source.url) then
        ns.Print(L.WowheadCopied)
    end
    SelectURL(source.url)
end

local function Muted(text)
    return "  |cff888888" .. text .. "|r"
end

local function CreateRow(row)
    row.title = W.Cell(row, "GameFontNormal", 330, 14)
    row.title:SetPoint("TOPLEFT", 6, -5)
    row.place = W.Cell(row, "GameFontHighlightSmall", 180, 12, "RIGHT")
    row.place:SetPoint("TOPRIGHT", -6, -6)
    row.place:SetTextColor(C.place[1], C.place[2], C.place[3])
    row.travel = W.Cell(row, "GameFontHighlightSmall", 380, 12)
    row.travel:SetPoint("BOTTOMLEFT", 6, 7)
    row.wowhead = W.Button(row, L.WowheadButton, 74, 18, function(self)
        local source = self:GetParent().item
        if source then OpenWowhead(source) end
    end)
    row.wowhead:SetPoint("BOTTOMRIGHT", -6, 5)
    row.tp = W.Button(row, L.SourceTP, 44, 18, function(self)
        local source = self:GetParent().item
        if source then ns.Travel.GoTo(source) end
    end)
    row.tp:SetPoint("BOTTOMRIGHT", -84, 5)
end

local function UpdateRow(row, source)
    local title = source.mob or L.SourceNoMob
    if source.mob then
        if source.custom then
            title = title .. Muted(L.SourceCustomMob)
        elseif source.npcId then
            title = title .. Muted("#" .. source.npcId)
        else
            title = title .. Muted("(" .. L.WowheadSearch .. ")")
        end
    end
    row.title:SetText(title)
    row.place:SetText(source.place)

    local near, fmt = source.near, ns.Travel.FormatDistance
    if near and near.checkpoint then
        local text = format(L.SourceCheckpoint, near.checkpoint.name, fmt(near.distance))
        if source.you then text = text .. Muted(format(L.SourceYou, fmt(source.you))) end
        row.travel:SetText(text)
        row.travel:SetTextColor(0.55, 0.9, 0.55)
    elseif near and near.locked then
        row.travel:SetText(format(L.SourceLocked, near.locked.name, fmt(near.lockedDistance)))
        row.travel:SetTextColor(1, 0.6, 0.25)
    else
        row.travel:SetText(near and L.SourceNoCheckpoint or L.SourceNoPosition)
        row.travel:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end
    W.SetEnabled(row.tp, near ~= nil and near.checkpoint ~= nil)
    if source.url then row.wowhead:Show() else row.wowhead:Hide() end
end

local function Build()
    frame = W.Window("EbonTomeHunterSourcesFrame", WIDTH, 128 + ROW_H * VISIBLE, L.SourcesTitle)
    frame:SetFrameStrata("DIALOG")
    frame:SetPoint("CENTER")
    frame:Hide()
    tinsert(UISpecialFrames, "EbonTomeHunterSourcesFrame")

    list = W.List(frame, "EbonTomeHunterSourcesList", ROW_H, VISIBLE, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 10, -38)
    list:SetPoint("RIGHT", -10, 0)

    -- read only: the link comes back, selected for Ctrl+C
    urlBox = CreateFrame("EditBox", "EbonTomeHunterSourcesURL", frame)
    urlBox:SetSize(WIDTH - 24, 20)
    urlBox:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -10)
    urlBox:SetAutoFocus(false)
    urlBox:SetFontObject(GameFontHighlightSmall)
    urlBox:SetTextInsets(6, 6, 0, 0)
    W.Backdrop(urlBox, C.input, C.borderSoft)
    urlBox:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= (self.url or "") then
            self:SetText(self.url or "")
            self:HighlightText()
        end
    end)
    urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    hint = W.Text(frame, "GameFontHighlightSmall", C.muted)
    hint:SetPoint("TOPLEFT", urlBox, "BOTTOMLEFT", 0, -8)
    hint:SetWidth(WIDTH - 24)
    hint:SetJustifyH("LEFT")
end

local function Collect(itemId)
    local sources = ns.Travel.Sources(itemId)
    local map, worldX, worldY = ns.Travel.PlayerPosition()
    for _, source in ipairs(sources) do
        if source.mob then source.url, source.npcId, source.custom = ns.Wowhead.LinkFor(source.mob, source.loc) end
        source.you = map and ns.Travel.PlayerDistance(source, map, worldX, worldY) or nil
    end
    return sources
end

-- Opens the sources of a tome. Returns their number.
function S.Show(itemId)
    local row = ns.Catalog.Get(itemId)
    local sources = Collect(itemId)
    if #sources == 0 then
        ns.Print(L.SourcesNone, row and row.name or "?")
        return 0
    end
    if not frame then Build() end
    S.itemId, S.sources = itemId, sources
    frame.titleText:SetText(L.SourcesTitle .. " - " .. (row and row.name or "?"))
    local hintText = type(EbonholdOpenURL) == "function" and L.SourcesHintOpen or L.SourcesHintCopy
    if not ns.Travel.Available() then hintText = hintText .. "\n" .. L.TravelNoPE end
    hint:SetText(hintText)
    urlBox.url = nil
    urlBox:SetText("")
    list:ResetScroll()
    list:SetItems(sources)
    frame:Show()
    return #sources
end

function S.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- New drop places (network) or learned NPC ids: refresh an open window in place.
ns.On("CATALOG_CHANGED", function()
    if not (S.IsShown() and S.itemId) then return end
    S.sources = Collect(S.itemId)
    list:SetItems(S.sources)
end)
