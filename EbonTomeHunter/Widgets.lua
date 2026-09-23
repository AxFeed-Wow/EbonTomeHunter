local addonName, ns = ...
local L = ns.L

-- Visual kit shared by the main window, the Auction House panel and the options.
-- 3.3.5a: no SetColorTexture (SetTexture(r, g, b, a)), no BackdropTemplate
-- (SetBackdrop is native), no SetShown / SetEnabled.
local W = {}
ns.Widgets = W

W.C = {
    window = { 0.055, 0.055, 0.070, 0.97 },
    panel = { 0.085, 0.085, 0.105, 0.96 },
    input = { 0.030, 0.030, 0.040, 0.95 },
    border = { 0.36, 0.29, 0.16, 1 },       -- bronze
    borderSoft = { 0.20, 0.20, 0.24, 1 },
    titleTop = { 0.20, 0.15, 0.08, 1 },
    titleBottom = { 0.09, 0.075, 0.05, 1 },
    button = { 0.13, 0.12, 0.10, 1 },
    buttonHover = { 0.22, 0.18, 0.11, 1 },
    accent = { 0.96, 0.72, 0.30, 1 },       -- warm amber
    gold = { 1.00, 0.82, 0.00, 1 },
    text = { 0.92, 0.92, 0.92, 1 },
    muted = { 0.58, 0.58, 0.62, 1 },
    good = { 0.35, 0.85, 0.45, 1 },
    bad = { 0.95, 0.38, 0.38, 1 },
    place = { 0.80, 0.74, 0.56, 1 },
    stripe = { 1, 1, 1, 0.03 },
    hover = { 1, 1, 1, 0.08 },
    selected = { 0.96, 0.72, 0.30, 0.20 },
}
local C = W.C

W.TOME_ICON = "Interface\\Icons\\INV_Misc_Book_09"

local counter = 0
function W.NextName(kind)
    counter = counter + 1
    return addonName .. (kind or "Widget") .. counter
end

local FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

function W.Backdrop(frame, bg, border)
    bg = bg or C.panel
    border = border or C.borderSoft
    frame:SetBackdrop(FLAT_BACKDROP)
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- Solid colour rectangle.
function W.Solid(parent, layer, color)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetTexture(color[1], color[2], color[3], color[4] or 1)
    return tex
end

-- Vertical gradient: `top` colour at the top, `bottom` at the bottom.
function W.Gradient(parent, layer, top, bottom)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetTexture(1, 1, 1, 1)
    tex:SetGradientAlpha("VERTICAL", bottom[1], bottom[2], bottom[3], bottom[4] or 1,
        top[1], top[2], top[3], top[4] or 1)
    return tex
end

function W.Text(parent, template, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Fixed width AND height: long texts end with "..." instead of wrapping over the next row.
function W.Cell(parent, template, width, height, justify)
    local fs = W.Text(parent, template, nil, justify)
    fs:SetSize(width, height or 14)
    return fs
end

------------------------------------------------------------------------
-- Money with coin icons: 12[g] 34[s] 56[c]
------------------------------------------------------------------------
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- compact: drop copper when there is gold (prices of tomes are in gold anyway).
function W.Money(copper, compact)
    copper = floor((tonumber(copper) or 0) + 0.5)
    if copper <= 0 then return "0" .. COPPER end
    local g = floor(copper / 10000)
    local s = floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. GOLD end
    if s > 0 or (g > 0 and c > 0 and not compact) then parts[#parts + 1] = s .. SILVER end
    if c > 0 and not (compact and g > 0) then parts[#parts + 1] = c .. COPPER end
    if #parts == 0 then parts[1] = g .. GOLD end
    return table.concat(parts, " ")
end

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------
function W.Tooltip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(type(title) == "function" and title() or title, 1, 1, 1)
        local text = type(body) == "function" and body() or body
        if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Window with a title bar (drag to move, close button)
------------------------------------------------------------------------
function W.Window(name, width, height, title, icon)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    W.Backdrop(frame, C.window, C.border)

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(30)
    local grad = W.Gradient(bar, "BACKGROUND", C.titleTop, C.titleBottom)
    grad:SetAllPoints()
    local line = W.Solid(bar, "BORDER", C.border)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)

    local iconTex = bar:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(20, 20)
    iconTex:SetPoint("LEFT", 8, 0)
    iconTex:SetTexture(icon or W.TOME_ICON)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local titleText = W.Text(bar, "GameFontNormalLarge")
    titleText:SetPoint("LEFT", iconTex, "RIGHT", 8, 0)
    titleText:SetText(title or "")

    local subtitle = W.Text(bar, "GameFontHighlightSmall", C.muted)
    subtitle:SetPoint("LEFT", titleText, "RIGHT", 12, -1)

    local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    close:SetPoint("RIGHT", 3, 0)
    close:SetScript("OnClick", function() frame:Hide() end)   -- default would hide the bar

    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if frame.OnMoved then frame:OnMoved() end
    end)

    frame.titleBar, frame.titleText, frame.subtitle, frame.icon = bar, titleText, subtitle, iconTex
    return frame
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
local function PaintButton(button)
    local bg = button.active and C.buttonHover or (button.hover and C.buttonHover or C.button)
    local border = (button.active or button.hover) and C.border or C.borderSoft
    button:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    button:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    if button.accentLine then
        if button.active then button.accentLine:Show() else button.accentLine:Hide() end
    end
end

-- Flat button; button:SetActive(true) keeps it lit (toggles, tabs).
function W.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 100, height or 22)
    W.Backdrop(button, C.button, C.borderSoft)
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    button:SetFontString(fs)
    button:SetNormalFontObject(GameFontNormalSmall)
    button:SetHighlightFontObject(GameFontHighlightSmall)
    button:SetDisabledFontObject(GameFontDisableSmall)
    button:SetPushedTextOffset(1, -1)
    button:SetText(text or "")
    button:SetScript("OnEnter", function(self)
        self.hover = true
        PaintButton(self)
        if self.tipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tipTitle, 1, 1, 1)
            if self.tipText then GameTooltip:AddLine(self.tipText, nil, nil, nil, true) end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self.hover = false
        PaintButton(self)
        GameTooltip:Hide()
    end)
    if onClick then
        button:SetScript("OnClick", function(self, mouseButton) onClick(self, mouseButton) end)
    end
    function button:SetActive(active)
        self.active = active and true or false
        PaintButton(self)
    end
    function button:SetTip(title, body)
        self.tipTitle, self.tipText = title, body
    end
    return button
end

-- Tab: flat button with an amber line under the active one.
function W.Tab(parent, text, width, onClick)
    local tab = W.Button(parent, text, width or 110, 24, onClick)
    tab.accentLine = W.Solid(tab, "OVERLAY", C.accent)
    tab.accentLine:SetPoint("BOTTOMLEFT", 1, 1)
    tab.accentLine:SetPoint("BOTTOMRIGHT", -1, 1)
    tab.accentLine:SetHeight(2)
    tab.accentLine:Hide()
    return tab
end

-- Square button showing a texture (icons, +/-, close...).
function W.IconButton(parent, texture, size, onClick, tipTitle, tipText, crop)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size or 16, size or 16)
    button:SetNormalTexture(texture)
    button:SetPushedTexture(texture)
    button:SetHighlightTexture(texture)
    button:SetDisabledTexture(texture)
    local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
    local highlight, disabled = button:GetHighlightTexture(), button:GetDisabledTexture()
    if crop then
        for _, tex in ipairs({ normal, pushed, highlight, disabled }) do
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
    pushed:SetVertexColor(0.8, 0.8, 0.8)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.45)
    disabled:SetDesaturated(true)
    disabled:SetAlpha(0.35)
    if onClick then
        button:SetScript("OnClick", function(self, mouseButton) onClick(self, mouseButton) end)
    end
    if tipTitle then W.Tooltip(button, tipTitle, tipText) end
    return button
end

function W.SetEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

------------------------------------------------------------------------
-- Search box with a placeholder text and a clear button
------------------------------------------------------------------------
function W.SearchBox(parent, width, placeholder, onChange)
    local box = CreateFrame("EditBox", W.NextName("Search"), parent)
    box:SetSize(width or 180, 22)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextInsets(8, 20, 0, 0)
    W.Backdrop(box, C.input, C.borderSoft)

    local hint = W.Text(box, "GameFontDisableSmall")
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(placeholder or "")

    local clear = W.Button(box, "x", 16, 16, function()
        box:SetText("")
        box:ClearFocus()
    end)
    clear:SetPoint("RIGHT", -3, 0)
    clear:Hide()

    local function Update(self)
        local text = self:GetText() or ""
        if text == "" and not self.focused then hint:Show() else hint:Hide() end
        if text ~= "" then clear:Show() else clear:Hide() end
    end
    box:SetScript("OnTextChanged", function(self)
        Update(self)
        if onChange then onChange(self:GetText() or "") end
    end)
    box:SetScript("OnEditFocusGained", function(self) self.focused = true; Update(self) end)
    box:SetScript("OnEditFocusLost", function(self) self.focused = false; Update(self) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

------------------------------------------------------------------------
-- Progress bar
------------------------------------------------------------------------
function W.ProgressBar(parent, width, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width or 200, height or 14)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    W.Backdrop(bar, C.input, C.borderSoft)
    bar.text = W.Text(bar, "GameFontHighlightSmall", nil, "CENTER")
    bar.text:SetPoint("CENTER", 0, 0)
    return bar
end

------------------------------------------------------------------------
-- Tome icon with a quality-coloured frame
------------------------------------------------------------------------
function W.ItemIcon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size or 20, size or 20)
    holder.frame = W.Solid(holder, "BACKGROUND", C.borderSoft)
    holder.frame:SetAllPoints()
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetPoint("TOPLEFT", 1, -1)
    holder.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    holder.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    function holder:SetItem(texture, r, g, b)
        self.icon:SetTexture(texture or W.TOME_ICON)
        self.frame:SetTexture(r or 0.3, g or 0.3, b or 0.3, 1)
    end
    -- "Learned" badge in the corner: true = check, "disabled" = learned but switched off.
    holder.badge = holder:CreateTexture(nil, "OVERLAY")
    holder.badge:SetSize(12, 12)
    holder.badge:SetPoint("BOTTOMRIGHT", 4, -3)
    holder.badge:Hide()
    function holder:SetKnown(state)
        if state == true then
            self.badge:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            self.badge:Show()
        elseif state == "disabled" then
            self.badge:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
            self.badge:Show()
        else
            self.badge:Hide()
        end
    end
    return holder
end

------------------------------------------------------------------------
-- Multi-line text box that scrolls (strings to copy / paste)
------------------------------------------------------------------------
function W.TextArea(parent, name, width, height)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height)
    W.Backdrop(holder, C.input, C.borderSoft)
    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local box = CreateFrame("EditBox", name, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetWidth(width - 34)
    box:SetHeight(height - 12)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- FrameXML helpers keeping the cursor visible while typing / pasting
    box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    box:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    scroll:SetScrollChild(box)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    holder.box, holder.scroll = box, scroll
    return holder
end

-- Icon of a tome item (item info is local data: works before the item is cached).
function W.TomeIcon(itemId)
    local texture = itemId and GetItemIcon and ns.SafeCall(GetItemIcon, itemId) or nil
    return texture or W.TOME_ICON
end

------------------------------------------------------------------------
-- Column headers (click to sort)
-- columns = { { key, text, width, justify, sortable }, ... }
------------------------------------------------------------------------
function W.Header(parent, columns, onSort)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(20)
    local line = W.Solid(header, "BORDER", C.borderSoft)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    header.buttons = {}
    local x = 0
    for _, column in ipairs(columns) do
        local button = CreateFrame("Button", nil, header)
        button:SetSize(column.width, 20)
        button:SetPoint("LEFT", header, "LEFT", x + (column.offset or 0), 0)
        x = x + column.width + (column.offset or 0)
        local fs = W.Text(button, "GameFontNormalSmall", nil, column.justify or "LEFT")
        fs:SetPoint("LEFT", 2, 0)
        fs:SetPoint("RIGHT", column.sortable and -12 or -2, 0)
        fs:SetText(column.text or "")
        button.label = fs
        if column.sortable and onSort then
            local arrow = button:CreateTexture(nil, "OVERLAY")
            arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
            arrow:SetSize(9, 8)
            arrow:SetPoint("RIGHT", -2, 0)
            arrow:Hide()
            button.arrow = arrow
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetTexture(1, 1, 1, 0.05)
            button:SetScript("OnClick", function() onSort(column.key) end)
        end
        header.buttons[column.key] = button
    end
    function header:SetSort(key, desc)
        for k, button in pairs(self.buttons) do
            if button.arrow then
                if k == key then
                    button.arrow:Show()
                    -- UI-SortArrow points down; flip it for ascending
                    if desc then button.arrow:SetTexCoord(0, 0.5625, 0, 1)
                    else button.arrow:SetTexCoord(0, 0.5625, 1, 0) end
                else
                    button.arrow:Hide()
                end
            end
        end
    end
    return header
end

------------------------------------------------------------------------
-- Virtual list: only `visibleRows` row frames exist, whatever the data size.
-- The (named) FauxScrollFrame covers the rows, so the mouse wheel works over them.
------------------------------------------------------------------------
function W.List(parent, name, rowHeight, visibleRows, createRow, updateRow)
    local holder = CreateFrame("Frame", name, parent)
    holder:SetHeight(rowHeight * visibleRows)
    holder.items = {}
    holder.rows = {}
    holder.rowHeight = rowHeight
    holder.visibleRows = visibleRows

    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", holder, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    holder.scroll = scroll
    holder.bar = _G[name .. "ScrollScrollBar"]

    for i = 1, visibleRows do
        local row = CreateFrame("Button", name .. "Row" .. i, holder)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("RIGHT", holder, "RIGHT", -24, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if i % 2 == 0 then
            local stripe = W.Solid(row, "BACKGROUND", C.stripe)
            stripe:SetAllPoints()
        end
        row.selectedTex = W.Solid(row, "BORDER", C.selected)
        row.selectedTex:SetAllPoints()
        row.selectedTex:Hide()
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetTexture(C.hover[1], C.hover[2], C.hover[3], C.hover[4])
        row.index = i
        createRow(row, i)
        holder.rows[i] = row
    end

    function holder:Refresh()
        local items = self.items
        FauxScrollFrame_Update(scroll, #items, visibleRows, rowHeight)
        local offset = FauxScrollFrame_GetOffset(scroll) or 0
        for i = 1, visibleRows do
            local row = self.rows[i]
            local item = items[offset + i]
            if item then
                row.item, row.itemIndex = item, offset + i
                updateRow(row, item, offset + i)
                row:Show()
            else
                row.item, row.itemIndex = nil, nil
                row:Hide()
            end
        end
    end

    function holder:SetItems(items)
        self.items = items or {}
        self:Refresh()
    end

    function holder:ResetScroll()
        if self.bar then self.bar:SetValue(0) end
        FauxScrollFrame_SetOffset(scroll, 0)
    end

    -- Scrolls so that item `index` is visible (centred when it had to move).
    function holder:ShowIndex(index)
        local offset = FauxScrollFrame_GetOffset(scroll) or 0
        if index > offset and index <= offset + visibleRows then return end
        local top = math.max(0, math.min(index - 1 - floor(visibleRows / 2), #self.items - visibleRows))
        if self.bar then self.bar:SetValue(top * rowHeight) end
    end

    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function() holder:Refresh() end)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if holder.bar then holder.bar:SetValue(holder.bar:GetValue() - delta * 3 * rowHeight) end
    end)
    return holder
end

------------------------------------------------------------------------
-- Options widgets (stock templates need a global name for $parent children)
------------------------------------------------------------------------
-- getter() -> bool, setter(bool)
function W.CheckBox(parent, text, getter, setter, tooltip)
    local name = W.NextName("Check")
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    local label = _G[name .. "Text"]
    if label then
        label:SetText(text)
        label:SetFontObject(GameFontHighlight)
    end
    check:SetScript("OnShow", function(self) self:SetChecked(getter() and true or false) end)
    check:SetScript("OnClick", function(self)
        local value = self:GetChecked() and true or false
        PlaySound(value and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        setter(value)
    end)
    if tooltip then W.Tooltip(check, text, tooltip) end
    check:SetChecked(getter() and true or false)
    return check
end

-- getter() -> number, setter(number); the step is enforced by hand (no SetObeyStepOnDrag).
function W.Slider(parent, text, minValue, maxValue, step, getter, setter, formatValue)
    local name = W.NextName("Slider")
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetSize(200, 17)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    formatValue = formatValue or function(v) return tostring(v) end
    local low, high, title = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
    if low then low:SetText(formatValue(minValue)) end
    if high then high:SetText(formatValue(maxValue)) end
    local updating = false
    local function Label(value)
        if title then title:SetText(text .. " : " .. formatValue(value)) end
    end
    slider:SetScript("OnValueChanged", function(self, value)
        value = floor(value / step + 0.5) * step
        Label(value)
        if not updating then setter(value) end
    end)
    slider:SetScript("OnShow", function(self)
        updating = true
        self:SetValue(getter())
        updating = false
        Label(getter())
    end)
    updating = true
    slider:SetValue(getter())
    updating = false
    Label(getter())
    return slider
end

-- Section title with a thin line.
function W.Section(parent, text)
    local fs = W.Text(parent, "GameFontNormal")
    fs:SetText(text)
    local line = W.Solid(parent, "ARTWORK", C.borderSoft)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return fs
end
