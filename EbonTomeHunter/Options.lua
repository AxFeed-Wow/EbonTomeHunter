local addonName, ns = ...
local L = ns.L
local W = ns.Widgets

-- Panel in Interface > AddOns. Widgets read the saved options when shown, so a
-- value changed elsewhere (slash command, minimap drag) is always up to date.
local panel = CreateFrame("Frame", "EbonTomeHunterOptionsPanel", UIParent)
panel.name = "EbonTomeHunter"
panel:Hide()

local function Opt() return ns.Opt() end

local function Toggle(key)
    return function() return Opt()[key] end,
        function(value) ns.SetOption(key, value) end
end

local built = false
local function Build()
    if built then return end
    built = true

    local title = W.Text(panel, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.Title)
    local version = W.Text(panel, "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    version:SetText("v" .. tostring(ns.version))
    local intro = W.Text(panel, "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    intro:SetText(L.OptionsIntro)

    -- General
    local general = W.Section(panel, L.SecGeneral)
    general:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -18)
    local minimap = W.CheckBox(panel, L.OptMinimap,
        function() return not Opt().minimap.hide end,
        function(value)
            Opt().minimap.hide = not value
            ns.Fire("SETTINGS_CHANGED", "minimap")
        end)
    minimap:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -6)
    local scale = W.Slider(panel, L.OptScale, 0.6, 1.4, 0.05,
        function() return Opt().scale or 1 end,
        function(value) ns.SetOption("scale", value) end,
        function(value) return format("%d%%", floor(value * 100 + 0.5)) end)
    scale:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 8, -24)
    local reset = W.Button(panel, L.OptResetPos, 210, 22, function()
        local pos = Opt().window
        pos.point, pos.x, pos.y = "CENTER", 0, 0
        ns.Fire("SETTINGS_CHANGED", "window")
    end)
    reset:SetPoint("LEFT", scale, "RIGHT", 40, 0)

    -- World map
    local map = W.Section(panel, L.SecMap)
    map:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", -6, -30)
    local get, set = Toggle("mapPins")
    local pins = W.CheckBox(panel, L.OptMapPins, get, set, L.OptMapPinsTip)
    pins:SetPoint("TOPLEFT", map, "BOTTOMLEFT", -2, -6)
    get, set = Toggle("confirmTeleport")
    local confirmTeleport = W.CheckBox(panel, L.OptConfirmTeleport, get, set, L.OptConfirmTeleportTip)
    confirmTeleport:SetPoint("TOPLEFT", pins, "BOTTOMLEFT", 0, 0)

    -- Auction House
    local ah = W.Section(panel, L.SecAH)
    ah:SetPoint("TOPLEFT", confirmTeleport, "BOTTOMLEFT", 2, -16)
    local previous = ah
    for i, entry in ipairs({
        { "ahTabs", L.OptAHTabs },
        { "ahOpenTab", L.OptAHOpenTab },
        { "confirmBuy", L.OptConfirmBuy },
        { "buyUpdatesWishlist", L.OptBuyWishlist },
        { "autoScan", L.OptAutoScan },
    }) do
        local getter, setter = Toggle(entry[1])
        local check = W.CheckBox(panel, entry[2], getter, setter)
        check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or 0)
        previous = check
    end

    -- Data
    local data = W.Section(panel, L.SecData)
    data:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -16)
    local clear = W.Button(panel, L.OptClearPrices, 200, 22, function()
        StaticPopup_Show("EBONTOMEHUNTER_CLEAR_PRICES")
    end)
    clear:SetPoint("TOPLEFT", data, "BOTTOMLEFT", 0, -8)
    local rebuild = W.Button(panel, L.OptRebuild, 200, 22, function()
        ns.Catalog.Build()
        ns.Print(L.Rebuilt, ns.Catalog.Count())
    end)
    rebuild:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    local tour = W.Button(panel, L.TutoReplay, 200, 22, function()
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        ns.Tutorial.Start()
    end)
    tour:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -8)
end

panel:SetScript("OnShow", Build)

-- Blizzard calls these for the Okay / Cancel / Defaults buttons: changes apply at once.
panel.okay = function() end
panel.cancel = function() end
panel.default = function() end

InterfaceOptions_AddCategory(panel)

-- Sub-panel: network and alerts
local netPanel = CreateFrame("Frame", "EbonTomeHunterNetPanel", UIParent)
netPanel.name = L.SecNet
netPanel.parent = panel.name
netPanel:Hide()

local netBuilt = false
netPanel:SetScript("OnShow", function()
    if not netBuilt then
        netBuilt = true
        local title = W.Text(netPanel, "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(L.SecNet)
        local previous = title
        for i, entry in ipairs({
            { "netEnabled", L.OptNet, L.OptNetTip },
            { "alertSelf", L.OptAlertSelf },
            { "alertGroup", L.OptAlertGroup },
            { "alertNetwork", L.OptAlertNetwork },
            { "alertSound", L.OptAlertSound },
            { "receiveWishlists", L.OptReceive },
        }) do
            local getter, setter = Toggle(entry[1])
            local check = W.CheckBox(netPanel, entry[2], getter, setter, entry[3])
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -12 or 0)
            previous = check
        end
        netPanel.status = W.Text(netPanel, "GameFontHighlightSmall", W.C.muted)
        netPanel.status:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 4, -16)
        netPanel.status:SetWidth(560)
    end
    netPanel.status:SetText(ns.Net.StatusText())
end)
netPanel.okay = function() end
netPanel.cancel = function() end
netPanel.default = function() end
InterfaceOptions_AddCategory(netPanel)

StaticPopupDialogs["EBONTOMEHUNTER_CLEAR_PRICES"] = {
    text = L.ClearPricesConfirm,
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ns.Prices.ClearAll()
        ns.Print(L.PricesCleared)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
}

function ns.OpenOptions()
    -- Called twice on purpose: on 3.3.5a the first call often only opens the frame.
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end
