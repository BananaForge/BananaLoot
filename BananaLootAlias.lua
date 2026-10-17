-- BananaLootAlias.lua
-- Fenster zum Zuordnen von Import-Namen (raidres.top/Discord) zu den echten
-- Ingame-Namen. Logik (Alias-Speicher, Vorschlag, Umbenennen) steht in
-- BananaLoot.lua, hier nur die Oberflaeche.

local ROW_H = 24
local MAX_ROWS = 20
local PICK_ROW_H = 20
local PICK_MAX = 40

local texts = {}
local aliasRows = {}
local pickRows = {}
local pickTarget = nil

-- ============================================================
-- Auswahlfenster: Raider aus der aktuellen Raid-/Gruppenliste waehlen
-- ============================================================
local pickFrame = CreateFrame("Frame", "BananaLootAliasPickFrame", UIParent)
pickFrame:SetWidth(240)
pickFrame:SetHeight(380)
pickFrame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
pickFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
pickFrame:SetMovable(true)
pickFrame:EnableMouse(true)
pickFrame:RegisterForDrag("LeftButton")
pickFrame:SetScript("OnDragStart", function() pickFrame:StartMoving() end)
pickFrame:SetScript("OnDragStop", function() pickFrame:StopMovingOrSizing() end)
pickFrame:SetFrameStrata("FULLSCREEN_DIALOG")
pickFrame:Hide()

local pickClose = CreateFrame("Button", "BananaLootAliasPickClose", pickFrame, "UIPanelCloseButton")
pickClose:SetPoint("TOPRIGHT", pickFrame, "TOPRIGHT", -4, -4)
pickClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    pickFrame:Hide()
end)

local pickTitle = pickFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pickTitle:SetPoint("TOP", pickFrame, "TOP", 0, -18)
pickTitle:SetWidth(190)

local pickScroll = CreateFrame("ScrollFrame", "BananaLootAliasPickScroll", pickFrame, "UIPanelScrollFrameTemplate")
pickScroll:SetPoint("TOPLEFT", pickFrame, "TOPLEFT", 16, -44)
pickScroll:SetPoint("BOTTOMRIGHT", pickFrame, "BOTTOMRIGHT", -30, 18)

local pickChild = CreateFrame("Frame", "BananaLootAliasPickChild", pickScroll)
pickChild:SetWidth(180)
pickChild:SetHeight(1)
pickScroll:SetScrollChild(pickChild)

for i = 1, PICK_MAX do
    local b = CreateFrame("Button", "BananaLootAliasPickRow" .. i, pickChild, "UIPanelButtonTemplate")
    b:SetWidth(176)
    b:SetHeight(PICK_ROW_H - 2)
    b:SetPoint("TOPLEFT", pickChild, "TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
    b:Hide()
    pickRows[i] = b
end

-- ============================================================
-- Hauptfenster: nicht gefundene Namen mit Vorschlag
-- ============================================================
local frame = CreateFrame("Frame", "BananaLootAliasFrame", UIParent)
frame:SetWidth(470)
frame:SetHeight(420)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() frame:StartMoving() end)
frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
frame:SetFrameStrata("DIALOG")
frame:Hide()

local closeBtn = CreateFrame("Button", "BananaLootAliasCloseButton", frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    pickFrame:Hide()
    frame:Hide()
end)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -16)

local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOP", frame, "TOP", 0, -40)
hint:SetWidth(420)
hint:SetJustifyH("CENTER")

local scroll = CreateFrame("ScrollFrame", "BananaLootAliasScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -76)
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 30)

local child = CreateFrame("Frame", "BananaLootAliasScrollChild", scroll)
child:SetWidth(420)
child:SetHeight(1)
scroll:SetScrollChild(child)

local overflowText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
overflowText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
overflowText:SetText("")

local function CreateRow(i)
    local r = CreateFrame("Frame", "BananaLootAliasRow" .. i, child)
    r:SetWidth(420)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_H)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.nameText:SetWidth(120)
    r.nameText:SetJustifyH("LEFT")

    r.sugText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sugText:SetPoint("LEFT", r, "LEFT", 124, 0)
    r.sugText:SetWidth(110)
    r.sugText:SetJustifyH("LEFT")

    r.sugBtn = CreateFrame("Button", "BananaLootAliasRow" .. i .. "SugBtn", r, "UIPanelButtonTemplate")
    r.sugBtn:SetWidth(80)
    r.sugBtn:SetHeight(20)
    r.sugBtn:SetPoint("LEFT", r, "LEFT", 238, 0)

    r.pickBtn = CreateFrame("Button", "BananaLootAliasRow" .. i .. "PickBtn", r, "UIPanelButtonTemplate")
    r.pickBtn:SetWidth(80)
    r.pickBtn:SetHeight(20)
    r.pickBtn:SetPoint("LEFT", r, "LEFT", 322, 0)
    return r
end

for i = 1, MAX_ROWS do
    aliasRows[i] = CreateRow(i)
    aliasRows[i]:Hide()
end

local function RefreshAlias()
    title:SetText(BananaLoot:L("WIN_ALIAS_TITLE"))
    hint:SetText(BananaLoot:L("WIN_ALIAS_HINT"))

    local names = BananaLoot:GetUnmatchedPlayers()
    local total = table.getn(names)
    if total > MAX_ROWS then
        overflowText:SetText(string.format(BananaLoot:L("ALIAS_OVERFLOW"), total - MAX_ROWS))
    else
        overflowText:SetText("")
    end

    local shown = 0
    for i = 1, total do
        if i <= MAX_ROWS then
            shown = shown + 1
            local importName = names[i]
            local row = aliasRows[shown]
            row.nameText:SetText(BananaLoot:ColoredName(importName))
            local suggestion = BananaLoot:SuggestRosterName(importName)
            row.sugBtn:SetText(BananaLoot:L("ALIAS_BTN_SUGGEST"))
            row.pickBtn:SetText(BananaLoot:L("ALIAS_BTN_PICK"))
            if suggestion then
                row.sugText:SetText("|cff33ff99" .. suggestion .. "|r")
                row.sugBtn:Enable()
                row.sugBtn:SetScript("OnClick", function()
                    BananaLoot:PlayClickSound()
                    if BananaLoot:SetAlias(importName, suggestion) then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("ALIAS_SET"), importName, suggestion))
                    end
                    RefreshAlias()
                    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
                end)
            else
                row.sugText:SetText("|cff888888-|r")
                row.sugBtn:Disable()
                row.sugBtn:SetScript("OnClick", nil)
            end
            row.pickBtn:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                BananaLoot_UI:ShowAliasPick(importName)
            end)
            row.sugBtn:Show()
            row.pickBtn:Show()
            row:Show()
        end
    end
    for i = shown + 1, MAX_ROWS do aliasRows[i]:Hide() end
    child:SetHeight(math.max(1, shown * ROW_H))

    if shown == 0 then
        aliasRows[1].nameText:SetText(BananaLoot:L("ALIAS_EMPTY"))
        aliasRows[1].sugText:SetText("")
        aliasRows[1].sugBtn:Hide()
        aliasRows[1].pickBtn:Hide()
        aliasRows[1]:Show()
    end
end

function BananaLoot_UI:ShowAliasPick(importName)
    pickTarget = importName
    pickTitle:SetText(string.format(BananaLoot:L("ALIAS_PICK_TITLE"), importName))
    local roster = BananaLoot:GetRosterNames()
    table.sort(roster)
    local shown = 0
    for i = 1, table.getn(roster) do
        if i <= PICK_MAX then
            shown = shown + 1
            local rosterName = roster[i]
            local b = pickRows[shown]
            b:SetText(rosterName)
            b:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                if BananaLoot:SetAlias(pickTarget, rosterName) then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("ALIAS_SET"), pickTarget, rosterName))
                end
                pickFrame:Hide()
                RefreshAlias()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end)
            b:Show()
        end
    end
    for i = shown + 1, PICK_MAX do pickRows[i]:Hide() end
    pickChild:SetHeight(math.max(1, shown * PICK_ROW_H))
    pickFrame:Show()
end

function BananaLoot_UI:ShowAliasWindow()
    RefreshAlias()
    frame:Show()
end

function BananaLoot_UI:ApplyLocaleAlias()
    if frame:IsShown() then RefreshAlias() end
    if pickFrame:IsShown() and pickTarget then BananaLoot_UI:ShowAliasPick(pickTarget) end
end
