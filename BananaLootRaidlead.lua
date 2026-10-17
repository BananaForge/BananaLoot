-- BananaLootRaidlead.lua
-- Raidlead-Fenster: pro Raid (linke Liste) Willkommens-/Trash-/Abschluss-
-- nachricht und pro Boss zwei Nachrichten bearbeiten. Logik und Daten:
-- BananaLoot.lua (Abschnitt Raidlead) und BananaLootBossData.lua.

local data = BananaLoot_RaidData
if not data then return end

local WIN_W = 640
local WIN_H = 620
local BLOCK_H = 190
local BOX_H = 74
local MAX_BLOCKS = 16
local CONTENT_W = 440

local selectedKey = "GENERAL"
local loading = false

-- ============================================================
-- Fenster
-- ============================================================
local frame = CreateFrame("Frame", "BananaLootRaidleadFrame", UIParent)
frame:SetWidth(WIN_W)
frame:SetHeight(WIN_H)
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

local closeBtn = CreateFrame("Button", "BananaLootRaidleadClose", frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    frame:Hide()
end)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -16)

-- ---------- Einstellungen oben ----------
local senderLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
senderLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -46)
local senderBox = CreateFrame("EditBox", "BananaLootRaidleadSender", frame, "InputBoxTemplate")
senderBox:SetWidth(130)
senderBox:SetHeight(20)
senderBox:SetPoint("LEFT", senderLabel, "RIGHT", 10, 0)
senderBox:SetAutoFocus(false)
senderBox:SetMaxLetters(24)

local delayLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
delayLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -72)
local delayBox = CreateFrame("EditBox", "BananaLootRaidleadDelay", frame, "InputBoxTemplate")
delayBox:SetWidth(40)
delayBox:SetHeight(20)
delayBox:SetPoint("LEFT", delayLabel, "RIGHT", 10, 0)
delayBox:SetAutoFocus(false)
delayBox:SetMaxLetters(3)

local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -96)
hint:SetWidth(WIN_W - 56)
hint:SetJustifyH("LEFT")

senderBox:SetScript("OnTextChanged", function()
    if loading then return end
    local rl = BananaLoot:RLEnsure()
    local text = senderBox:GetText() or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    rl.sender = text
end)
senderBox:SetScript("OnEscapePressed", function() senderBox:ClearFocus() end)
senderBox:SetScript("OnEnterPressed", function() senderBox:ClearFocus() end)
delayBox:SetScript("OnTextChanged", function()
    if loading then return end
    local rl = BananaLoot:RLEnsure()
    rl.msg2delay = tonumber(delayBox:GetText()) or 0
end)
delayBox:SetScript("OnEscapePressed", function() delayBox:ClearFocus() end)
delayBox:SetScript("OnEnterPressed", function() delayBox:ClearFocus() end)

-- ---------- Raid-Liste links ----------
local listButtons = {}
local raidList = {}   -- { key=, label= }; Eintrag 1 = Allgemein
local function BuildRaidList()
    raidList = { { key = "GENERAL", label = BananaLoot:L("RL_GENERAL") } }
    for i = 1, table.getn(data) do
        if BananaLoot:IsRaidEnabled(data[i]) then
            table.insert(raidList, { key = data[i].key, label = data[i].short or data[i].name })
        end
    end
end
BuildRaidList()

for i = 1, table.getn(data) + 1 do
    local b = CreateFrame("Button", "BananaLootRaidleadTab" .. i, frame, "UIPanelButtonTemplate")
    b:SetWidth(112)
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -140 - (i - 1) * 24)
    listButtons[i] = b
end

-- ---------- Rechter Bereich (scrollbar) ----------
local scroll = CreateFrame("ScrollFrame", "BananaLootRaidleadScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 146, -140)
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 20)

local child = CreateFrame("Frame", "BananaLootRaidleadChild", scroll)
child:SetWidth(CONTENT_W)
child:SetHeight(1)
scroll:SetScrollChild(child)

local headerText = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
headerText:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)

local noteText = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
noteText:SetWidth(CONTENT_W - 90)
noteText:SetJustifyH("LEFT")

local resetBtn = CreateFrame("Button", "BananaLootRaidleadReset", child, "UIPanelButtonTemplate")
resetBtn:SetWidth(90)
resetBtn:SetHeight(20)
resetBtn:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, 0)

-- Mausrad ueber Textfeldern/Bloecken scrollt das aeussere Fenster (die
-- Textfelder und ihre inneren ScrollFrames fangen das Mausrad sonst ab).
local function ScrollOuter()
    local current = scroll:GetVerticalScroll()
    local maxScroll = scroll:GetVerticalScrollRange()
    local target = current - arg1 * 45
    if target < 0 then target = 0 end
    if target > maxScroll then target = maxScroll end
    scroll:SetVerticalScroll(target)
end

-- Mehrzeilige Textbox mit Zeichenzaehler (max. 255 = Chat-Limit).
-- Aufbau wie im LFM-Fenster: mehrzeilige EditBox als ScrollChild eines
-- ScrollFrames (nur so waechst/wrappt sie im Vanilla-Client zuverlaessig),
-- umgeben von einem Rahmen fester Hoehe (BOX_H), in den 255 Zeichen
-- vollstaendig sichtbar passen. Ein Klick irgendwo im Rahmen fokussiert.
local function MakeBox(width, height, onChange, tag)
    local holder = CreateFrame("Frame", nil, child)
    holder:SetWidth(width)
    holder:SetHeight(height)
    holder:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    holder:SetBackdropColor(0, 0, 0, 0.6)
    holder:EnableMouse(true)

    local sf = CreateFrame("ScrollFrame", nil, holder)
    sf:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -5)
    sf:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 5)

    local box = CreateFrame("EditBox", nil, sf)
    box:SetMultiLine(true)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetWidth(width - 16)
    box:SetMaxLetters(255)
    box:SetAutoFocus(false)
    sf:SetScrollChild(box)

    holder.box = box
    holder.tag = tag or ""
    holder.counter = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    holder.counter:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -7, 4)

    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", ScrollOuter)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", ScrollOuter)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", ScrollOuter)
    box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnTextChanged", function()
        local text = box:GetText() or ""
        holder.counter:SetText(holder.tag .. string.len(text) .. "/255")
        if loading then return end
        text = string.gsub(text, "[\r\n]+", " ")
        onChange(text)
    end)
    return holder
end

local function SetBoxText(holder, text)
    loading = true
    holder.box:SetText(text or "")
    holder.counter:SetText(holder.tag .. string.len(text or "") .. "/255")
    loading = false
end

-- Raid-Texte (Willkommen / Trash / Abschluss)
local raidFields = { "welcome", "trash", "ending" }
local raidFieldKeys = { welcome = "RL_WELCOME", trash = "RL_TRASH", ending = "RL_ENDING" }
local raidCaptions = {}
local raidBoxes = {}
for i = 1, table.getn(raidFields) do
    local field = raidFields[i]
    raidCaptions[field] = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidBoxes[field] = MakeBox(CONTENT_W - 6, BOX_H, function(text)
        BananaLoot:RLSetRaidText(selectedKey, field, text)
    end)
end

-- Boss-Bloecke (Pool)
local blocks = {}
local currentBosses = {}
for i = 1, MAX_BLOCKS do
    local blk = {}
    blk.check = CreateFrame("CheckButton", "BananaLootRaidleadBossCheck" .. i, child, "UICheckButtonTemplate")
    blk.label = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    blk.label:SetPoint("LEFT", blk.check, "RIGHT", 2, 0)
    local index = i
    blk.check:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        local boss = currentBosses[index]
        if boss then
            BananaLoot:RLSetBossEnabled(selectedKey, boss.key, blk.check:GetChecked() and true or false)
        end
    end)
    blk.box1 = MakeBox(CONTENT_W - 6, BOX_H, function(text)
        local boss = currentBosses[index]
        if boss then BananaLoot:RLSetBossText(selectedKey, boss.key, "m1", text) end
    end, "1:  ")
    blk.box2 = MakeBox(CONTENT_W - 6, BOX_H, function(text)
        local boss = currentBosses[index]
        if boss then BananaLoot:RLSetBossText(selectedKey, boss.key, "m2", text) end
    end, "2:  ")
    blk.send1Btn = CreateFrame("Button", "BananaLootRaidleadSend1_" .. i, child, "UIPanelButtonTemplate")
    blk.send1Btn:SetWidth(76)
    blk.send1Btn:SetHeight(22)
    blk.send1Btn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        local boss = currentBosses[index]
        if boss then BananaLoot:RLSendBossMessage(selectedKey, boss, "m1") end
    end)
    blk.sendBtn = CreateFrame("Button", "BananaLootRaidleadSend" .. i, child, "UIPanelButtonTemplate")
    blk.sendBtn:SetWidth(76)
    blk.sendBtn:SetHeight(22)
    blk.sendBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        local boss = currentBosses[index]
        if boss then BananaLoot:RLSendBossMessage(selectedKey, boss, "m2") end
    end)
    blk.check:Hide(); blk.label:Hide(); blk.box1:Hide(); blk.box2:Hide(); blk.sendBtn:Hide(); blk.send1Btn:Hide()
    blocks[i] = blk
end

-- ---------- Bearbeitbare Daten laden ----------
function BananaLoot:RLSetBossEnabled(raidKey, bossKey, value)
    local rl = self:RLEnsure()
    if not rl.texts[raidKey] then rl.texts[raidKey] = {} end
    if not rl.texts[raidKey].bosses then rl.texts[raidKey].bosses = {} end
    if not rl.texts[raidKey].bosses[bossKey] then rl.texts[raidKey].bosses[bossKey] = {} end
    rl.texts[raidKey].bosses[bossKey].enabled = value
end

local function LoadRaid(key)
    selectedKey = key
    local rl = BananaLoot:RLEnsure()
    local raid = BananaLoot:RLGetRaid(key)

    for i = 1, table.getn(listButtons) do
        if raidList[i] and raidList[i].key == key then listButtons[i]:LockHighlight() else listButtons[i]:UnlockHighlight() end
    end

    local y = 0
    headerText:SetText(raid and raid.name or BananaLoot:L("RL_GENERAL"))
    y = 26
    local note = ""
    if not raid then
        note = BananaLoot:L("RL_GENERAL_NOTE")
    elseif raid.unverified then
        note = BananaLoot:L("RL_UNVERIFIED")
    end
    noteText:ClearAllPoints()
    noteText:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    noteText:SetText(note)
    if note ~= "" then y = y + 18 end
    y = y + 6

    for i = 1, table.getn(raidFields) do
        local field = raidFields[i]
        raidCaptions[field]:ClearAllPoints()
        raidCaptions[field]:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        raidCaptions[field]:SetText(BananaLoot:L(raidFieldKeys[field]))
        y = y + 16
        raidBoxes[field]:ClearAllPoints()
        raidBoxes[field]:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        SetBoxText(raidBoxes[field], BananaLoot:RLGetRaidText(key, field))
        y = y + BOX_H + 10
    end

    currentBosses = {}
    local bosses = raid and raid.bosses or {}
    y = y + 6
    for i = 1, MAX_BLOCKS do
        local blk = blocks[i]
        local boss = bosses[i]
        if boss then
            currentBosses[i] = boss
            blk.check:ClearAllPoints()
            blk.check:SetPoint("TOPLEFT", child, "TOPLEFT", -4, -y)
            blk.label:SetText(boss.label)
            blk.check:SetChecked(BananaLoot:RLIsBossEnabled(key, boss.key))
            blk.box1:ClearAllPoints()
            blk.box1:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 28))
            SetBoxText(blk.box1, BananaLoot:RLGetBossText(key, boss, "m1"))
            blk.box2:ClearAllPoints()
            blk.box2:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 28 + BOX_H + 6))
            SetBoxText(blk.box2, BananaLoot:RLGetBossText(key, boss, "m2"))
            blk.send1Btn:ClearAllPoints()
            blk.send1Btn:SetPoint("TOPLEFT", child, "TOPLEFT", CONTENT_W - 164, -(y + 2))
            blk.send1Btn:SetText(BananaLoot:L("RL_BTN_SEND1"))
            blk.sendBtn:ClearAllPoints()
            blk.sendBtn:SetPoint("TOPLEFT", child, "TOPLEFT", CONTENT_W - 82, -(y + 2))
            blk.sendBtn:SetText(BananaLoot:L("RL_BTN_SEND2"))
            blk.check:Show(); blk.label:Show(); blk.box1:Show(); blk.box2:Show(); blk.sendBtn:Show(); blk.send1Btn:Show()
            y = y + BLOCK_H
        else
            blk.check:Hide(); blk.label:Hide(); blk.box1:Hide(); blk.box2:Hide(); blk.sendBtn:Hide(); blk.send1Btn:Hide()
        end
    end
    child:SetHeight(y + 10)
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(0)
    resetBtn:SetText(BananaLoot:L("RL_BTN_RESET"))
    if raid then resetBtn:Show() else resetBtn:Show() end
end

for i = 1, table.getn(listButtons) do
    local index = i
    listButtons[i]:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        LoadRaid(raidList[index].key)
    end)
end

-- Zuruecksetzen mit Rueckfrage
if StaticPopupDialogs then
    StaticPopupDialogs["BANANALOOT_RL_RESET"] = {
        text = "",
        button1 = "",
        button2 = "",
        OnAccept = function()
            BananaLoot:RLResetRaid(selectedKey)
            LoadRaid(selectedKey)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end
resetBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local d = StaticPopupDialogs["BANANALOOT_RL_RESET"]
    d.text = BananaLoot:L("RL_RESET_CONFIRM")
    d.button1 = BananaLoot:L("UI_POPUP_YES")
    d.button2 = BananaLoot:L("UI_POPUP_CANCEL")
    StaticPopup_Show("BANANALOOT_RL_RESET")
end)

local function RefreshTexts()
    title:SetText(BananaLoot:L("RL_TITLE"))
    senderLabel:SetText(BananaLoot:L("RL_SENDER_LABEL"))
    delayLabel:SetText(BananaLoot:L("RL_DELAY_LABEL"))
    hint:SetText(BananaLoot:L("RL_HINT"))
    BuildRaidList()
    for i = 1, table.getn(listButtons) do
        if raidList[i] then
            listButtons[i]:SetText(raidList[i].label)
            listButtons[i]:Show()
        else
            listButtons[i]:Hide()
        end
    end
    -- Ausgewaehlter Raid nicht mehr aktiv (z.B. UBRS abgeschaltet): zurueck auf Allgemein
    local found = false
    for i = 1, table.getn(raidList) do
        if raidList[i].key == selectedKey then found = true end
    end
    if not found then selectedKey = "GENERAL" end
end

function BananaLoot_UI:ShowRaidlead()
    local rl = BananaLoot:RLEnsure()
    if not rl.enabled then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("RL_DISABLED"))
        return
    end
    RefreshTexts()
    loading = true
    senderBox:SetText(rl.sender or "")
    delayBox:SetText(tostring(rl.msg2delay or 0))
    loading = false
    LoadRaid(selectedKey)
    frame:Show()
end

function BananaLoot_UI:ApplyLocaleRaidlead()
    if frame:IsShown() then
        RefreshTexts()
        LoadRaid(selectedKey)
    end
end
