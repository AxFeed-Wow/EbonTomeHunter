local addonName, ns = ...
local L = ns.L
local W = ns.Widgets
local C = W.C

-- A wishlist as a string to copy / paste: "ETH1:<author>:<entries>:<checksum>"
--   entries  = the tomes sorted by item id, separated by commas: <item id - 300000>[x<qty>]
--              (#<item id> for an id outside the 300000 range)
--   checksum = 6 hex digits over everything before it: a truncated or edited copy
--              is refused instead of importing a wrong list.
ns.Share = {}
local S = ns.Share

local VERSION = "ETH1"
local LEGACY = { ETP1 = true }   -- strings of EbonTomePrices 1.x (the addon's former name): same format
local BASE_ID = 300000
local MAX_QTY = 99

local function Checksum(text)
    local h = 0
    for i = 1, #text do
        h = (h * 31 + text:byte(i)) % 16777213
    end
    return format("%06x", h)
end

local function CleanAuthor(name)
    name = tostring(name or ""):gsub("[:,%s]", "")
    return name:sub(1, 24)   -- character names: 12 letters at most, 2 bytes when accented
end

local function ClampQty(qty)
    qty = floor(tonumber(qty) or 1)
    if qty < 1 then return 1 end
    if qty > MAX_QTY then return MAX_QTY end
    return qty
end

-- items = { { itemId = n, qty = n }, ... }
function S.Encode(items, author)
    local sorted = {}
    for _, item in ipairs(items) do
        local id = tonumber(item.itemId)
        if id then sorted[#sorted + 1] = { id = id, qty = ClampQty(item.qty) } end
    end
    table.sort(sorted, function(a, b) return a.id < b.id end)
    local parts = {}
    for _, item in ipairs(sorted) do
        local token = (item.id >= BASE_ID and item.id < BASE_ID + 100000) and tostring(item.id - BASE_ID)
            or ("#" .. item.id)
        if item.qty > 1 then token = token .. "x" .. item.qty end
        parts[#parts + 1] = token
    end
    local body = VERSION .. ":" .. CleanAuthor(author) .. ":" .. table.concat(parts, ",")
    return body .. ":" .. Checksum(body)
end

-- String of the current wishlist, number of tomes, number of copies.
function S.ExportWishlist()
    local items, copies = {}, 0
    for _, item in ipairs(ns.Wishlist.List()) do
        if tonumber(item.itemId) then
            local qty = ClampQty(item.entry and item.entry.qty or 1)
            items[#items + 1] = { itemId = item.itemId, qty = qty }
            copies = copies + qty
        end
    end
    return S.Encode(items, UnitName("player")), #items, copies
end

-- Finds and checks a wishlist string (it may be surrounded by other text).
-- Returns { author, items = { { itemId, qty, row } }, copies, unknown }, or nil + error key.
function S.Decode(text)
    text = tostring(text or "")
    local version, author, entries, sum = text:match("(ET[HP]%d+):([^:\r\n]*):([^:\r\n]*):(%x%x%x%x%x%x)")
    if not version then
        if text:find("ET[HP]%d+:") then return nil, "ShareCorrupt" end
        return nil, "ShareNoString"
    end
    if version ~= VERSION and not LEGACY[version] then return nil, "ShareVersion" end
    if Checksum(version .. ":" .. author .. ":" .. entries) ~= strlower(sum) then
        return nil, "ShareCorrupt"
    end
    local qtyById, order = {}, {}
    for token in entries:gmatch("[^,]+") do
        local hash, number, qty = token:match("^(#?)(%d+)x?(%d*)$")
        if not number then return nil, "ShareCorrupt" end
        local id = hash == "#" and tonumber(number) or (BASE_ID + tonumber(number))
        qty = ClampQty(qty ~= "" and qty or 1)
        if not qtyById[id] then
            order[#order + 1] = id
            qtyById[id] = qty
        elseif qty > qtyById[id] then
            qtyById[id] = qty
        end
    end
    local result = { author = author, items = {}, copies = 0, unknown = 0 }
    for _, id in ipairs(order) do
        local row = ns.Catalog.Get(id)
        if row then
            result.items[#result.items + 1] = { itemId = id, qty = qtyById[id], row = row }
            result.copies = result.copies + qtyById[id]
        else
            result.unknown = result.unknown + 1   -- tome missing from this catalogue
        end
    end
    return result
end

-- mode: "merge" (missing tomes added, larger quantity kept) or "replace".
function S.Import(result, mode)
    if not result or #result.items == 0 then return 0, 0 end
    local added, raised = ns.Wishlist.ApplyImport(result.items, mode)
    ns.Print(L.ShareImported, added, raised)
    return added, raised
end

------------------------------------------------------------------------
-- Dialog: export (top) and import (bottom)
------------------------------------------------------------------------
local dialog, exportArea, importArea, summaryText, previewText, mergeButton, replaceButton
local exportText = ""
local parsed

local function RefreshExport()
    if not dialog then return end
    local text, count, copies = S.ExportWishlist()
    exportText = text
    exportArea.box:SetText(text)
    summaryText:SetText(count > 0 and format(L.ShareSummary, count, copies) or L.ShareEmpty)
end

local function RefreshPreview()
    if not dialog then return end
    local text = importArea.box:GetText() or ""
    parsed = nil
    local color = C.text
    if strtrim(text) == "" then
        previewText:SetText(L.SharePasteHint)
        color = C.muted
    else
        local result, err = S.Decode(text)
        if not result then
            previewText:SetText(L[err])
            color = C.bad
        elseif #result.items == 0 then
            previewText:SetText(L.ShareNothing)
            color = C.bad
        else
            parsed = result
            local names = {}
            for i = 1, math.min(5, #result.items) do
                local item = result.items[i]
                names[#names + 1] = (item.row.name or "?") .. (item.qty > 1 and (" x" .. item.qty) or "")
            end
            if #result.items > 5 then names[#names + 1] = "..." end
            local line = format(L.SharePreview, result.author ~= "" and result.author or "?", #result.items, result.copies)
            if result.unknown > 0 then
                line = line .. "  |cffff8000" .. format(L.ShareUnknown, result.unknown) .. "|r"
            end
            previewText:SetText(line .. "\n|cffaaaaaa" .. table.concat(names, ", ") .. "|r")
        end
    end
    previewText:SetTextColor(color[1], color[2], color[3])
    W.SetEnabled(mergeButton, parsed ~= nil)
    W.SetEnabled(replaceButton, parsed ~= nil)
end

local function AfterImport()
    if not dialog then return end
    importArea.box:SetText("")
    RefreshExport()
end

local function Build()
    dialog = W.Window("EbonTomeHunterShareFrame", 540, 390, L.ShareTitle)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetPoint("CENTER")
    dialog:Hide()
    tinsert(UISpecialFrames, "EbonTomeHunterShareFrame")

    local exportTitle = W.Section(dialog, L.ShareExportSection)
    exportTitle:SetPoint("TOPLEFT", 14, -42)
    summaryText = W.Text(dialog, "GameFontHighlightSmall", C.muted)
    summaryText:SetPoint("TOPLEFT", exportTitle, "BOTTOMLEFT", 0, -6)
    exportArea = W.TextArea(dialog, "EbonTomeHunterShareExport", 512, 70)
    exportArea:SetPoint("TOPLEFT", summaryText, "BOTTOMLEFT", 0, -6)
    -- read only: whatever is typed, the string comes back (selected, ready for Ctrl+C)
    exportArea.box:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= exportText then
            self:SetText(exportText)
            self:HighlightText()
        end
    end)
    exportArea.box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    if type(CopyToClipboard) == "function" then   -- AwesomeWotLK extension of the Ebonhold client
        local copy = W.Button(dialog, L.ShareCopy, 90, 22, function()
            if pcall(CopyToClipboard, exportText) then ns.Print(L.ShareCopied) end
        end)
        copy:SetPoint("TOPRIGHT", exportArea, "BOTTOMRIGHT", 0, -6)
    end

    -- straight to a player (addon message: they need EbonTomeHunter too)
    local sendLabel = W.Text(dialog, "GameFontNormalSmall")
    sendLabel:SetPoint("TOPLEFT", exportArea, "BOTTOMLEFT", 0, -11)
    sendLabel:SetText(L.SendTo)
    local nameBox = CreateFrame("EditBox", "EbonTomeHunterShareName", dialog)
    nameBox:SetSize(130, 20)
    nameBox:SetPoint("LEFT", sendLabel, "RIGHT", 6, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetFontObject(GameFontHighlightSmall)
    nameBox:SetTextInsets(6, 6, 0, 0)
    nameBox:SetMaxLetters(24)
    W.Backdrop(nameBox, C.input, C.borderSoft)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ns.Comm.SendWishlist(self:GetText())
    end)
    local sendButton = W.Button(dialog, L.SendButton, 80, 22, function()
        ns.Comm.SendWishlist(nameBox:GetText())
    end)
    sendButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    sendButton:SetTip(L.SendButton, L.SendTip)
    local targetButton = W.Button(dialog, L.SendTarget, 60, 22, function()
        if UnitExists("target") and UnitIsPlayer("target") then nameBox:SetText(UnitName("target") or "") end
    end)
    targetButton:SetPoint("LEFT", sendButton, "RIGHT", 4, 0)
    targetButton:SetTip(L.SendTarget, L.SendTargetTip)
    S.nameBox, S.sendButton = nameBox, sendButton

    local importTitle = W.Section(dialog, L.ShareImportSection)
    importTitle:SetPoint("TOPLEFT", exportArea, "BOTTOMLEFT", 0, -36)
    importArea = W.TextArea(dialog, "EbonTomeHunterShareImport", 512, 70)
    importArea:SetPoint("TOPLEFT", importTitle, "BOTTOMLEFT", 0, -8)
    importArea.box:SetScript("OnTextChanged", RefreshPreview)
    previewText = W.Text(dialog, "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", importArea, "BOTTOMLEFT", 2, -6)
    previewText:SetWidth(510)

    replaceButton = W.Button(dialog, L.ShareReplace, 110, 24, function()
        if not parsed then return end
        if ns.Wishlist.Count() > 0 then
            StaticPopup_Show("EBONTOMEHUNTER_REPLACE_WISHLIST", ns.Wishlist.Count(), #parsed.items, parsed)
        else
            S.Import(parsed, "replace")
            AfterImport()
        end
    end)
    replaceButton:SetPoint("BOTTOMRIGHT", -14, 12)
    replaceButton:SetTip(L.ShareReplace, L.ShareReplaceTip)
    mergeButton = W.Button(dialog, L.ShareMerge, 110, 24, function()
        if not parsed then return end
        S.Import(parsed, "merge")
        AfterImport()
    end)
    mergeButton:SetPoint("RIGHT", replaceButton, "LEFT", -6, 0)
    mergeButton:SetTip(L.ShareMerge, L.ShareMergeTip)

    dialog:SetScript("OnShow", function()
        RefreshExport()
        RefreshPreview()
    end)
    S.exportBox, S.importBox, S.previewText = exportArea.box, importArea.box, previewText
    S.mergeButton, S.replaceButton = mergeButton, replaceButton
end

-- importText: a string received from another player, put in the import box.
function S.ShowDialog(focusImport, importText)
    if not dialog then Build() end
    dialog:Show()
    if importText then importArea.box:SetText(importText) end
    if focusImport then
        importArea.box:SetFocus()
    else
        exportArea.box:SetFocus()
        exportArea.box:HighlightText()
    end
end

StaticPopupDialogs["EBONTOMEHUNTER_REPLACE_WISHLIST"] = {
    text = L.ShareReplaceConfirm,
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        S.Import(data or self.data, "replace")
        AfterImport()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
}

ns.On("WISHLIST_CHANGED", function()
    if dialog and dialog:IsShown() then RefreshExport() end
end)
