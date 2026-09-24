local addonName, ns = ...
local L = ns.L
local W = ns.Widgets
local C = W.C

-- "History" window: the drop places shared on the network (Net.lua), the most recent
-- first: when, which tome, who found it (+ the players who confirmed it), where, which mob.
-- A click on a row opens the Sources window of that tome.
ns.History = {}
local H = ns.History

local WIDTH = 700
local ROW_H = 20
local VISIBLE = 18
local MAX_ROWS = 300

local frame, list, countText, onlyMine

-- Every shared drop place, the most recently found first.
function H.Entries(mineOnly)
    local me = UnitName("player")
    local out = {}
    for itemId, places in pairs(ns.DB.sightings or {}) do
        for _, r in ipairs(places) do
            local mine = r.by == me or (type(r.finders) == "table" and r.finders[me])
            if not mineOnly or mine then
                local others = 0
                for name in pairs(type(r.finders) == "table" and r.finders or {}) do
                    if name ~= r.by then others = others + 1 end
                end
                local zone, sub = tostring(r.zone or ""):match("^([^:]*):?(.*)$")
                out[#out + 1] = {
                    itemId = itemId, at = tonumber(r.at) or 0, by = r.by, others = others, mob = r.mob,
                    place = (sub and sub ~= "") and (zone .. " - " .. sub) or (zone ~= "" and zone or L.LocationUnknown),
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    for i = #out, MAX_ROWS + 1, -1 do out[i] = nil end
    return out
end

local function CreateRow(row)
    row.when = W.Cell(row, "GameFontHighlightSmall", 80, 14)
    row.when:SetPoint("LEFT", 6, 0)
    row.when:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    row.tome = W.Cell(row, "GameFontNormalSmall", 170, 14)
    row.tome:SetPoint("LEFT", 90, 0)
    row.who = W.Cell(row, "GameFontHighlightSmall", 120, 14)
    row.who:SetPoint("LEFT", 264, 0)
    row.where = W.Cell(row, "GameFontHighlightSmall", 170, 14)
    row.where:SetPoint("LEFT", 388, 0)
    row.where:SetTextColor(C.place[1], C.place[2], C.place[3])
    row.mob = W.Cell(row, "GameFontHighlightSmall", 110, 14)
    row.mob:SetPoint("LEFT", 562, 0)
    row:SetScript("OnClick", function(self)
        if self.item then ns.Sources.Show(self.item.itemId) end
    end)
end

local function UpdateRow(row, entry)
    local tome = ns.Catalog.Get(entry.itemId)
    local r, g, b = 1, 1, 1
    if tome then r, g, b = ns.Catalog.QualityColor(tome) end
    row.when:SetText(ns.Ago(entry.at) or "?")
    row.tome:SetText(tome and tome.name or ("#" .. tostring(entry.itemId)))
    row.tome:SetTextColor(r, g, b)
    row.who:SetText((entry.by or "?") .. (entry.others > 0 and (" |cff888888+" .. entry.others .. "|r") or ""))
    row.where:SetText(entry.place)
    row.mob:SetText(entry.mob or ("|cff888888" .. L.SourceNoMob .. "|r"))
end

function H.Refresh()
    if not (frame and frame:IsShown()) then return end
    local entries = H.Entries(onlyMine:GetChecked())
    list:SetItems(entries)
    countText:SetText(format(L.HistoryCount, #entries))
end

local function Build()
    frame = W.Window("EbonTomeHunterHistoryFrame", WIDTH, 120 + ROW_H * VISIBLE, L.HistoryTitle)
    frame:SetFrameStrata("DIALOG")
    frame:SetPoint("CENTER")
    frame:Hide()
    tinsert(UISpecialFrames, "EbonTomeHunterHistoryFrame")

    for _, column in ipairs({ { L.HistoryWhen, 16 }, { L.HistoryTome, 100 }, { L.HistoryWho, 274 },
        { L.HistoryWhere, 398 }, { L.HistoryMob, 572 } }) do
        local title = W.Text(frame, "GameFontNormalSmall", C.muted)
        title:SetPoint("TOPLEFT", column[2], -40)
        title:SetText(column[1])
    end
    list = W.List(frame, "EbonTomeHunterHistoryList", ROW_H, VISIBLE, CreateRow, UpdateRow)
    list:SetPoint("TOPLEFT", 10, -56)
    list:SetPoint("RIGHT", -10, 0)

    countText = W.Text(frame, "GameFontHighlightSmall", C.muted)
    countText:SetPoint("BOTTOMLEFT", 16, 16)
    onlyMine = W.CheckBox(frame, L.HistoryMine, function() return false end, function() H.Refresh() end)
    onlyMine:SetPoint("BOTTOMRIGHT", -200, 10)
    H.onlyMine, H.countText = onlyMine, countText
end

function H.Show()
    if not frame then Build() end
    frame:Show()
    H.Refresh()
end

function H.Toggle()
    if frame and frame:IsShown() then frame:Hide() else H.Show() end
end

ns.On("SIGHTINGS_CHANGED", function() H.Refresh() end)
