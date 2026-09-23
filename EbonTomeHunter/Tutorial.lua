local addonName, ns = ...
local L = ns.L
local W = ns.Widgets
local C = W.C

-- Guided tour of the addon: a glowing frame around each part of the main window and a
-- bubble that explains it, step by step. Starts by itself the first time the window
-- opens (once per account), then from the "?" button, the options or /eth tuto.
ns.Tutorial = {}
local T = ns.Tutorial

local VERSION = 1          -- raise it when steps are added: the tour then shows once more
local BUBBLE_W = 350
local PAD = 4

T.index, T.running = 0, false
local highlight, bubble

local function Parts()
    return ns.UI.parts or {}
end

local function Row(i)
    local rows = ns.UI.list and ns.UI.list.rows
    local row = rows and rows[i]
    return row and row:IsShown() and row or nil
end

local function RowPart(key)
    local row = Row(1)
    return row and row[key] or nil
end

local function MinimapButton()
    return ns.MinimapButton and ns.MinimapButton() or nil
end

-- The Auction House tabs, when the Auction House is open.
local function AuctionTabs()
    local tabs = ns.AH and ns.AH.tabs
    if AuctionFrame and AuctionFrame:IsShown() and tabs and tabs.tomes and tabs.tomes:IsShown() then
        return tabs.tomes, tabs.wish
    end
end

-- target() returns what to light up: one frame, or two (from the top-left of the first
-- to the bottom-right of the second); nothing: the bubble sits on the window.
local STEPS = {
    { title = L.TutoWelcomeTitle, text = L.TutoWelcomeText, target = function() return Parts().title end },
    { title = L.TutoTabsTitle, text = L.TutoTabsText, target = function() return Parts().tabAll, Parts().tabWish end },
    { title = L.TutoSearchTitle, text = L.TutoSearchText, target = function() return Parts().search, Parts().chipLast end },
    { title = L.TutoListTitle, text = L.TutoListText, target = function() return Parts().header, Row(3) end },
    { title = L.TutoKnownTitle, text = L.TutoKnownText, target = function() return RowPart("icon") end },
    { title = L.TutoWishlistTitle, text = L.TutoWishlistText, target = function() return RowPart("minus"), RowPart("plus") end },
    { title = L.TutoButtonsTitle, text = L.TutoButtonsText, target = function() return RowPart("locate"), RowPart("remove") end },
    { title = L.TutoScanTitle, text = L.TutoScanText, target = function() return Parts().scan end },
    { title = L.TutoAuctionTitle, text = L.TutoAuctionText, target = AuctionTabs, side = "above" },
    { title = L.TutoShareTitle, text = L.TutoShareText, target = function() return Parts().share end },
    { title = L.TutoMapTitle, text = L.TutoMapText },
    { title = L.TutoNetworkTitle, text = L.TutoNetworkText },
    { title = L.TutoMinimapTitle, text = L.TutoMinimapText, target = MinimapButton, side = "left" },
    { title = L.TutoEndTitle, text = L.TutoEndText, target = function() return Parts().help end },
}
T.STEPS = STEPS

local function Build()
    highlight = CreateFrame("Frame", "EbonTomeHunterTutorialHighlight", UIParent)
    highlight:SetFrameStrata("FULLSCREEN_DIALOG")
    highlight:EnableMouse(false)   -- the lit part stays usable
    highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    highlight:SetScript("OnUpdate", function(self, elapsed)
        self.clock = (self.clock or 0) + elapsed
        self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 0.55 + 0.45 * math.sin(self.clock * 4))
    end)
    highlight:Hide()

    bubble = CreateFrame("Frame", "EbonTomeHunterTutorial", UIParent)
    bubble:SetFrameStrata("FULLSCREEN_DIALOG")
    bubble:SetFrameLevel(highlight:GetFrameLevel() + 5)
    bubble:SetWidth(BUBBLE_W)
    bubble:SetClampedToScreen(true)
    bubble:EnableMouse(true)
    W.Backdrop(bubble, C.window, C.gold)
    bubble:Hide()
    bubble.step = W.Text(bubble, "GameFontDisableSmall")
    bubble.step:SetPoint("TOPRIGHT", -12, -12)
    bubble.title = W.Text(bubble, "GameFontNormalLarge", C.gold)
    bubble.title:SetPoint("TOPLEFT", 12, -10)
    bubble.title:SetWidth(BUBBLE_W - 100)
    bubble.title:SetJustifyH("LEFT")
    bubble.text = W.Text(bubble, "GameFontHighlight")
    bubble.text:SetPoint("TOPLEFT", bubble.title, "BOTTOMLEFT", 0, -8)
    bubble.text:SetWidth(BUBBLE_W - 24)
    bubble.text:SetJustifyH("LEFT")
    bubble.skip = W.Button(bubble, L.TutoSkip, 70, 20, function() T.Stop(true) end)
    bubble.skip:SetPoint("BOTTOMLEFT", 10, 10)
    bubble.nextButton = W.Button(bubble, L.TutoNext, 90, 20, function() T.Next() end)
    bubble.nextButton:SetPoint("BOTTOMRIGHT", -10, 10)
    bubble.prevButton = W.Button(bubble, L.TutoPrev, 90, 20, function() T.Prev() end)
    bubble.prevButton:SetPoint("RIGHT", bubble.nextButton, "LEFT", -6, 0)
    -- Escape (or anything else hiding it) ends the tour
    bubble:SetScript("OnHide", function()
        if T.running then T.Stop(true) end
    end)
    tinsert(UISpecialFrames, "EbonTomeHunterTutorial")
end

local function Place(step)
    local from, to
    if step.target then from, to = step.target() end
    highlight:ClearAllPoints()
    bubble:ClearAllPoints()
    if not from then
        highlight:Hide()
        bubble:SetPoint("CENTER", ns.UI.frame or UIParent, "CENTER", 0, 0)
        return
    end
    to = to or from
    highlight:SetPoint("TOPLEFT", from, "TOPLEFT", -PAD, PAD)
    highlight:SetPoint("BOTTOMRIGHT", to, "BOTTOMRIGHT", PAD, -PAD)
    highlight:Show()
    if step.side == "above" then
        bubble:SetPoint("BOTTOM", highlight, "TOP", 0, 10)
    elseif step.side == "left" then
        bubble:SetPoint("TOPRIGHT", highlight, "TOPLEFT", -10, 0)
    else
        bubble:SetPoint("TOP", highlight, "BOTTOM", 0, -10)
    end
end

function T.Show(index)
    local step = STEPS[index]
    if not step then return T.Stop(true) end
    T.index = index
    bubble.step:SetText(format(L.TutoStep, index, #STEPS))
    bubble.title:SetText(step.title)
    bubble.text:SetText(step.text)
    bubble:SetHeight(10 + (bubble.title:GetStringHeight() or 16) + 8 + (bubble.text:GetStringHeight() or 40) + 42)
    W.SetEnabled(bubble.prevButton, index > 1)
    bubble.nextButton:SetText(index == #STEPS and L.TutoDone or L.TutoNext)
    Place(step)
    bubble:Show()
end

function T.Next()
    if T.index >= #STEPS then return T.Stop(true) end
    T.Show(T.index + 1)
end

function T.Prev()
    if T.index > 1 then T.Show(T.index - 1) end
end

-- Opens the window (list reset: all tomes, no search) and starts from the first step.
function T.Start()
    if not bubble then Build() end
    T.running = true
    ns.UI.Show()
    if ns.UI.ResetForTour then ns.UI.ResetForTour() end
    T.Show(1)
end

-- done: the tour will not start by itself any more (the "?" button replays it).
function T.Stop(done)
    T.running = false
    if done then ns.DB.tutorialDone = VERSION end
    if highlight then highlight:Hide() end
    if bubble and bubble:IsShown() then bubble:Hide() end
end

function T.IsNew()
    return (tonumber(ns.DB.tutorialDone) or 0) < VERSION
end

-- First opening of the window: the tour starts by itself (just after, once laid out).
function T.MaybeStart()
    if T.running or not T.IsNew() then return end
    ns.Timer.After(0.3, function()
        if not T.running and T.IsNew() and ns.UI.frame and ns.UI.frame:IsShown() then
            T.Start()
        end
    end)
end

ns.On("READY", function()
    if T.IsNew() then ns.Print(L.TutoLoginHint) end
end)
