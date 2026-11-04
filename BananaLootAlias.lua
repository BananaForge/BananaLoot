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
local soloConfirmed = {}
local pendingAssign = nil

local function Trim(str)
    return (string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
end

local function DoAssign(importName, target, onDone)
    if BananaLoot:SetAlias(importName, target) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("ALIAS_SET"), importName, target))
    end
    if onDone then onDone() end
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
end

-- Zuordnung mit Sicherheitsabfrage, falls ein fremder Name dem eigenen
-- Charakter zugeordnet werden soll (haeufiger Fehler beim Import ohne Gruppe).
local function TryAssign(importName, target, onDone)
    local me = UnitName("player")
    if target == me and importName ~= me and StaticPopup_Show and StaticPopupDialogs then
        pendingAssign = { importName = importName, target = target, onDone = onDone }
        StaticPopupDialogs["BANANALOOT_CONFIRM_ALIAS_SELF"].text = BananaLoot:L("ALIAS_SELF_POPUP")
        StaticPopupDialogs["BANANALOOT_CONFIRM_ALIAS_SELF"].button1 = BananaLoot:L("ALIAS_SELF_YES")
        StaticPopupDialogs["BANANALOOT_CONFIRM_ALIAS_SELF"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
        StaticPopup_Show("BANANALOOT_CONFIRM_ALIAS_SELF", importName, me)
        return
    end
    DoAssign(importName, target, onDone)
end

if StaticPopupDialogs then
    StaticPopupDialogs["BANANALOOT_CONFIRM_ALIAS_SELF"] = {
        text = "",
        button1 = "",
        button2 = "",
        OnAccept = function()
            if pendingAssign then
                local pa = pendingAssign
                pendingAssign = nil
                DoAssign(pa.importName, pa.target, pa.onDone)
            end
        end,
        OnCancel = function()
            pendingAssign = nil
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

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

local manageBtn = CreateFrame("Button", "BananaLootAliasManageButton", frame, "UIPanelButtonTemplate")
manageBtn:SetWidth(150)
manageBtn:SetHeight(20)
manageBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 8)
manageBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ShowAliasManager()
end)

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

    -- Nur ohne Gruppe: Textfeld mit Namen + OK (statt Vorschlag/Waehlen)
    r.edit = CreateFrame("EditBox", "BananaLootAliasRow" .. i .. "Edit", r, "InputBoxTemplate")
    r.edit:SetWidth(180)
    r.edit:SetHeight(20)
    r.edit:SetPoint("LEFT", r, "LEFT", 132, 0)
    r.edit:SetAutoFocus(false)
    r.edit:SetMaxLetters(24)
    r.edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    r.edit:SetScript("OnEnterPressed", function() this:GetParent().okBtn:Click() end)
    r.edit:Hide()

    r.okBtn = CreateFrame("Button", "BananaLootAliasRow" .. i .. "OkBtn", r, "UIPanelButtonTemplate")
    r.okBtn:SetWidth(80)
    r.okBtn:SetHeight(20)
    r.okBtn:SetPoint("LEFT", r, "LEFT", 322, 0)
    r.okBtn:Hide()
    return r
end

for i = 1, MAX_ROWS do
    aliasRows[i] = CreateRow(i)
    aliasRows[i]:Hide()
end

local function RefreshAlias()
    title:SetText(BananaLoot:L("WIN_ALIAS_TITLE"))
    local solo = BananaLoot:IsSolo()
    if solo then
        hint:SetText(BananaLoot:L("WIN_ALIAS_SOLO_HINT"))
    else
        hint:SetText(BananaLoot:L("WIN_ALIAS_HINT"))
    end
    manageBtn:SetText(BananaLoot:L("ALIASMGR_BTN_OPEN"))

    local names
    if solo then
        names = BananaLoot:GetReservedPlayerNames()
    else
        names = BananaLoot:GetUnmatchedPlayers()
    end
    local total = table.getn(names)
    if total > MAX_ROWS then
        overflowText:SetText(string.format(BananaLoot:L("ALIAS_OVERFLOW"), total - MAX_ROWS))
    else
        overflowText:SetText("")
    end

    local shown = 0
    local me = UnitName("player")
    for i = 1, total do
        if i <= MAX_ROWS then
            shown = shown + 1
            local importName = names[i]
            local row = aliasRows[shown]
            row.nameText:SetText(BananaLoot:ColoredName(importName))
            if solo then
                row.sugText:Hide()
                row.sugBtn:Hide()
                row.pickBtn:Hide()
                row.edit:SetText(importName)
                row.edit:Show()
                if soloConfirmed[importName] or importName == me then
                    row.okBtn:SetText(BananaLoot:L("ALIAS_SOLO_DONE"))
                else
                    row.okBtn:SetText(BananaLoot:L("ALIAS_SOLO_OK"))
                end
                row.okBtn:SetScript("OnClick", function()
                    BananaLoot:PlayClickSound()
                    local newName = Trim(row.edit:GetText())
                    row.edit:ClearFocus()
                    if newName == "" then return end
                    if newName == importName then
                        soloConfirmed[importName] = true
                        RefreshAlias()
                    else
                        TryAssign(importName, newName, function()
                            soloConfirmed[newName] = true
                            RefreshAlias()
                        end)
                    end
                end)
                row.okBtn:Show()
            else
                row.edit:Hide()
                row.okBtn:Hide()
                row.sugText:Show()
                local suggestion = BananaLoot:SuggestRosterName(importName)
                row.sugBtn:SetText(BananaLoot:L("ALIAS_BTN_SUGGEST"))
                row.pickBtn:SetText(BananaLoot:L("ALIAS_BTN_PICK"))
                if suggestion then
                    row.sugText:SetText("|cff33ff99" .. suggestion .. "|r")
                    row.sugBtn:Enable()
                    row.sugBtn:SetScript("OnClick", function()
                        BananaLoot:PlayClickSound()
                        TryAssign(importName, suggestion, function() RefreshAlias() end)
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
            end
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
        aliasRows[1].edit:Hide()
        aliasRows[1].okBtn:Hide()
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
                local importName = pickTarget
                pickFrame:Hide()
                TryAssign(importName, rosterName, function() RefreshAlias() end)
            end)
            b:Show()
        end
    end
    for i = shown + 1, PICK_MAX do pickRows[i]:Hide() end
    pickChild:SetHeight(math.max(1, shown * PICK_ROW_H))
    pickFrame:Show()
end

-- ============================================================
-- Verwaltung gespeicherter Zuordnungen (anzeigen / entfernen)
-- ============================================================
local MGR_ROW_H = 24
local MGR_MAX = 30

local mgrFrame = CreateFrame("Frame", "BananaLootAliasMgrFrame", UIParent)
mgrFrame:SetWidth(400)
mgrFrame:SetHeight(400)
mgrFrame:SetPoint("CENTER", UIParent, "CENTER", 30, 0)
mgrFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
mgrFrame:SetMovable(true)
mgrFrame:EnableMouse(true)
mgrFrame:RegisterForDrag("LeftButton")
mgrFrame:SetScript("OnDragStart", function() mgrFrame:StartMoving() end)
mgrFrame:SetScript("OnDragStop", function() mgrFrame:StopMovingOrSizing() end)
mgrFrame:SetFrameStrata("FULLSCREEN_DIALOG")
mgrFrame:Hide()

local mgrClose = CreateFrame("Button", "BananaLootAliasMgrClose", mgrFrame, "UIPanelCloseButton")
mgrClose:SetPoint("TOPRIGHT", mgrFrame, "TOPRIGHT", -4, -4)
mgrClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    mgrFrame:Hide()
end)

local mgrTitle = mgrFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mgrTitle:SetPoint("TOP", mgrFrame, "TOP", 0, -16)

local mgrHint = mgrFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mgrHint:SetPoint("TOP", mgrFrame, "TOP", 0, -40)
mgrHint:SetWidth(350)
mgrHint:SetJustifyH("CENTER")

local mgrScroll = CreateFrame("ScrollFrame", "BananaLootAliasMgrScroll", mgrFrame, "UIPanelScrollFrameTemplate")
mgrScroll:SetPoint("TOPLEFT", mgrFrame, "TOPLEFT", 16, -76)
mgrScroll:SetPoint("BOTTOMRIGHT", mgrFrame, "BOTTOMRIGHT", -30, 30)

local mgrChild = CreateFrame("Frame", "BananaLootAliasMgrChild", mgrScroll)
mgrChild:SetWidth(350)
mgrChild:SetHeight(1)
mgrScroll:SetScrollChild(mgrChild)

local mgrOverflow = mgrFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mgrOverflow:SetPoint("BOTTOM", mgrFrame, "BOTTOM", 0, 12)
mgrOverflow:SetText("")

local mgrRows = {}
for i = 1, MGR_MAX do
    local r = CreateFrame("Frame", "BananaLootAliasMgrRow" .. i, mgrChild)
    r:SetWidth(350)
    r:SetHeight(MGR_ROW_H)
    r:SetPoint("TOPLEFT", mgrChild, "TOPLEFT", 0, -(i - 1) * MGR_ROW_H)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text:SetWidth(250)
    r.text:SetJustifyH("LEFT")
    r.btn = CreateFrame("Button", "BananaLootAliasMgrRow" .. i .. "Btn", r, "UIPanelButtonTemplate")
    r.btn:SetWidth(80)
    r.btn:SetHeight(20)
    r.btn:SetPoint("LEFT", r, "LEFT", 262, 0)
    r:Hide()
    mgrRows[i] = r
end

local function RefreshMgr()
    mgrTitle:SetText(BananaLoot:L("WIN_ALIASMGR_TITLE"))
    mgrHint:SetText(BananaLoot:L("WIN_ALIASMGR_HINT"))
    local list = BananaLoot:GetAliasList()
    local total = table.getn(list)
    local me = UnitName("player")
    if total > MGR_MAX then
        mgrOverflow:SetText(string.format(BananaLoot:L("ALIAS_OVERFLOW"), total - MGR_MAX))
    else
        mgrOverflow:SetText("")
    end
    local shown = 0
    for i = 1, total do
        if i <= MGR_MAX then
            shown = shown + 1
            local entry = list[i]
            local row = mgrRows[shown]
            local line = entry.name .. " |cff888888->|r " .. entry.target
            if entry.target == me and entry.name ~= me then
                line = line .. BananaLoot:L("ALIASMGR_SELF_WARN")
            end
            row.text:SetText(line)
            row.btn:SetText(BananaLoot:L("ALIASMGR_BTN_REMOVE"))
            row.btn:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                local ok, count, hadTracking = BananaLoot:RemoveAlias(entry.name, true)
                if ok then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("ALIAS_REMOVED"), entry.name))
                    if not hadTracking then
                        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("ALIAS_REMOVED_NOTRACK"))
                    elseif count > 0 then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("ALIAS_REVERTED"), count, entry.name))
                    end
                end
                RefreshMgr()
                if frame:IsShown() then RefreshAlias() end
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end)
            row.btn:Show()
            row:Show()
        end
    end
    for i = shown + 1, MGR_MAX do mgrRows[i]:Hide() end
    mgrChild:SetHeight(math.max(1, shown * MGR_ROW_H))
    if shown == 0 then
        mgrRows[1].text:SetText(BananaLoot:L("ALIAS_LIST_EMPTY"))
        mgrRows[1].btn:Hide()
        mgrRows[1]:Show()
    end
end

function BananaLoot_UI:ShowAliasManager()
    RefreshMgr()
    mgrFrame:Show()
end

function BananaLoot_UI:ShowAliasWindow()
    RefreshAlias()
    frame:Show()
end

function BananaLoot_UI:ApplyLocaleAlias()
    if frame:IsShown() then RefreshAlias() end
    if mgrFrame:IsShown() then RefreshMgr() end
    if pickFrame:IsShown() and pickTarget then BananaLoot_UI:ShowAliasPick(pickTarget) end
end
