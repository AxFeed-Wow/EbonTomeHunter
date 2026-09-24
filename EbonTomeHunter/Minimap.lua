local addonName, ns = ...
local L = ns.L
local W = ns.Widgets

-- Minimap button without LibDBIcon: drag it around the edge of the minimap.
local RADIUS = 80

local button

local function UpdatePosition()
    local angle = math.rad(ns.Opt().minimap.angle or 200)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.Opt().minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.Title, 1, 0.82, 0)
    local count = ns.Wishlist.Count()
    local total, missing = ns.Wishlist.ComputeTotal()
    GameTooltip:AddLine(format(L.MinimapWish, count), 1, 1, 1)
    if count > 0 then
        GameTooltip:AddLine(format(L.MinimapTotal, W.Money(total, true)), 1, 1, 1)
        if missing > 0 then GameTooltip:AddLine(format(L.MinimapMissing, missing), 0.8, 0.5, 0.5) end
    end
    local known, total = ns.Known.Count()
    if known then
        GameTooltip:AddLine(format(L.MinimapKnown, known, total), 0.3, 1, 0.3)
    end
    local last = ns.Prices.LastScan()
    GameTooltip:AddLine(last > 0 and format(L.LastScanAgo, ns.Ago(last) or "") or L.NeverScanned, 0.6, 0.6, 0.6)
    local _, syncTip = ns.UI.SyncTip()
    GameTooltip:AddLine(syncTip, 0.55, 0.8, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.MinimapLeft, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MinimapRight, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MinimapDrag, 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function Build()
    button = CreateFrame("Button", "EbonTomeHunterMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(W.TOME_ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if ns.OpenOptions then ns.OpenOptions() end
        else
            ns.UI.Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Refresh()
    if not button then Build() end
    UpdatePosition()
    if ns.Opt().minimap.hide then button:Hide() else button:Show() end
end
ns.MinimapButtonRefresh = Refresh

-- The button when it is on the minimap (guided tour).
function ns.MinimapButton()
    return button and button:IsShown() and button or nil
end

ns.On("LOGIN", Refresh)
ns.On("SETTINGS_CHANGED", function(key)
    if key == "minimap" and button then Refresh() end
end)
