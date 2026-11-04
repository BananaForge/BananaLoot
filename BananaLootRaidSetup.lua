-- BananaLootRaidSetup.lua
-- Raid-Setup beim Raid-Start: Raid auswaehlen, dann Hard Reserve (HR), Soft
-- Reserve (Hinweis/Import) und Raid-Roll-Items aus der Beutetabelle des
-- gewaehlten Raids abhaken. Die Auswahl wird pro Raid als Vorlage gespeichert
-- und beim naechsten Start desselben Raids zum Uebernehmen angeboten.
-- Zusaetzlich: Drops-Tab -- im Raid gefallene Items per Klick "kuenftig
-- Raid-Roll" setzen (falls sie versehentlich normal gerollt wurden).
--
-- Daten:  BananaLootRaidLoot.lua (Raid -> Bosse -> Item-IDs, aus AtlasLoot)
-- Texte:  LOCALE-Tabellen in BananaLoot.lua (Schluessel SETUP_*)
-- Speicher: BananaLoot_DB.raidTemplates[raidKey] = { hr = {id=true}, rr = {id=true}, savedAt }
--           BananaLoot_DB.raidSession.raidKey / .drops / .dropOrder
--
-- Lua 5.0: kein #-Operator, kein %-Operator, kein string.gmatch/match, Events
-- ueber this/arg1. UI-Zustand liegt in der Tabelle S (Grenze von 200 lokalen
-- Variablen bzw. 32 Upvalues je Funktion).

local ROW_H = 26
local NUM_ROWS = 13
local BOSS_ROW_H = 20
local NUM_BOSS_ROWS = 18
local MAX_DROPS = 200

local QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80",
}

local S = {
    tab = "HR",        -- HR | SR | RR | DROPS
    bossIdx = 0,       -- 0 = alle Bosse
    search = "",
    offset = 0,
    selHR = {},        -- [itemID] = true (noch nicht angewendet)
    selRR = {},
    entries = {},
    rows = {},
    bossRows = {},
    setupKey = nil,    -- Raid-Key, falls kein Raid laeuft
    loading = false,
}
BananaLoot_SetupState = S

-- ============================================================
-- 1) DATENSCHICHT (ohne UI, testbar)
-- ============================================================

-- Raids mit Beutedaten in der Reihenfolge von BananaLoot_RaidData.
function BananaLoot:GetSetupRaids()
    local list = {}
    if not BananaLoot_RaidLoot or not BananaLoot_RaidData then return list end
    for i = 1, table.getn(BananaLoot_RaidData) do
        local raid = BananaLoot_RaidData[i]
        if BananaLoot_RaidLoot[raid.key] then
            table.insert(list, { key = raid.key, name = raid.name, zone = raid.zones and raid.zones[1] })
        end
    end
    return list
end

function BananaLoot:GetSetupRaidName(key)
    if not key then return nil end
    if BananaLoot_RaidData then
        for i = 1, table.getn(BananaLoot_RaidData) do
            if BananaLoot_RaidData[i].key == key then return BananaLoot_RaidData[i].name end
        end
    end
    return key
end

-- Name, Qualitaet, Icon (ohne Pfad), statischer DB-Eintrag zu einer Item-ID.
-- Reihenfolge: statische Item-DB, AtlasLoot-Fallback, Client-Cache.
function BananaLoot:SetupItemInfo(id)
    local name, quality, icon
    local st = self:GetStaticItemInfo(id)
    if st then name, quality, icon = st.name, st.quality, st.icon end
    if not name and BananaLoot_RaidLootInfo then
        local ri = BananaLoot_RaidLootInfo[id]
        if ri then name, quality, icon = ri[1], ri[2], ri[3] end
    end
    if not name or not icon then
        local cn, _, cq, _, _, _, _, _, ctex = GetItemInfo("item:" .. id .. ":0:0:0:0:0:0:0")
        if cn then
            name = name or cn
            quality = quality or cq
            if not icon and ctex then icon = string.gsub(ctex, "^Interface\\Icons\\", "") end
        end
    end
    return name or ("Item #" .. id), quality or 1, icon, st
end

-- Farbcodierter Item-Link aus der ID (ohne Server-Abfrage).
function BananaLoot:SetupItemLink(id)
    local name, quality = self:SetupItemInfo(id)
    if self.itemQualityHints then self.itemQualityHints[id] = quality end
    return "|cff" .. (QUALITY_HEX[quality] or "ffffff") .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
end

-- Menge aller Item-IDs eines Raids.
function BananaLoot:GetSetupPool(key)
    local pool = {}
    local raid = BananaLoot_RaidLoot and BananaLoot_RaidLoot[key]
    if raid then
        for b = 1, table.getn(raid) do
            local ids = raid[b][2]
            for i = 1, table.getn(ids) do pool[ids[i]] = true end
        end
    end
    return pool
end

local function CountSet(set)
    local n = 0
    if set then
        for _, v in pairs(set) do if v then n = n + 1 end end
    end
    return n
end
BananaLoot.CountSet = CountSet

local function CopySet(set)
    local c = {}
    if set then
        for id, v in pairs(set) do if v then c[id] = true end end
    end
    return c
end

function BananaLoot:GetRaidTemplate(key)
    if not key then return nil end
    BananaLoot.EnsureDB()
    if not BananaLoot_DB.raidTemplates then return nil end
    return BananaLoot_DB.raidTemplates[key]
end

function BananaLoot:SaveRaidTemplate(key, hrSet, rrSet)
    if not key then return end
    BananaLoot.EnsureDB()
    if not BananaLoot_DB.raidTemplates then BananaLoot_DB.raidTemplates = {} end
    BananaLoot_DB.raidTemplates[key] = { hr = CopySet(hrSet), rr = CopySet(rrSet), savedAt = time() }
end

-- Wendet eine Auswahl auf die HR- und Raid-Roll-Liste an und speichert sie als
-- Vorlage. Nur Items des Raids (Pool) werden angefasst: abgehakte kommen auf die
-- Liste, nicht (mehr) abgehakte werden von dieser Liste entfernt. Bankreserve-
-- Items bleiben unberuehrt. Rueckgabe: Anzahl HR, Anzahl Raid-Roll.
function BananaLoot:ApplyRaidSetup(key, selHR, selRR)
    local pool = self:GetSetupPool(key)
    local nHR, nRR = 0, 0
    for id in pairs(pool) do
        if not self:IsBankReserve(id) then
            if self:IsHardReserve(id) and not selHR[id] then self:RemoveHardReserve(id) end
            if self:IsRaidRollItem(id) and not selRR[id] then self:RemoveRaidRollItem(id) end
        end
    end
    local hrKeep, rrKeep = {}, {}
    for id in pairs(pool) do
        if not self:IsBankReserve(id) then
            if selHR[id] then
                if not self:IsHardReserve(id) then self:AddHardReserve(self:SetupItemLink(id)) end
                hrKeep[id] = true
                nHR = nHR + 1
            elseif selRR[id] then
                if not self:IsRaidRollItem(id) then self:AddRaidRollItem(self:SetupItemLink(id)) end
                rrKeep[id] = true
                nRR = nRR + 1
            end
        end
    end
    self:SaveRaidTemplate(key, hrKeep, rrKeep)
    return nHR, nRR
end

-- Merkt sich gefallene Items des laufenden Raids (fuer den Drops-Tab).
function BananaLoot:SetupRecordDrops(items)
    local session = self:GetRaidSession()
    if not session or not session.running or not items then return end
    if not session.drops then session.drops = {} end
    if not session.dropOrder then session.dropOrder = {} end
    for i = 1, table.getn(items) do
        local it = items[i]
        if it.itemID and it.link and not session.drops[it.itemID] then
            session.drops[it.itemID] = { link = it.link, icon = it.icon }
            table.insert(session.dropOrder, it.itemID)
            while table.getn(session.dropOrder) > MAX_DROPS do
                local old = table.remove(session.dropOrder, 1)
                session.drops[old] = nil
            end
        end
    end
end

-- Item ab jetzt und beim naechsten Start desselben Raids als Raid-Roll-Item
-- setzen (z.B. weil es versehentlich normal gerollt wurde). Rueckgabe: true,
-- wenn auch die Vorlage des Raids angepasst wurde.
function BananaLoot:MarkRaidRollNextTime(id, link)
    link = link or self:SetupItemLink(id)
    self:AddRaidRollItem(link)
    local session = self:GetRaidSession()
    local key = (session and session.raidKey) or S.setupKey
    if not key then return false end
    local tpl = self:GetRaidTemplate(key)
    if not tpl then
        BananaLoot.EnsureDB()
        if not BananaLoot_DB.raidTemplates then BananaLoot_DB.raidTemplates = {} end
        tpl = { hr = {}, rr = {}, savedAt = time() }
        BananaLoot_DB.raidTemplates[key] = tpl
    end
    tpl.hr[id] = nil
    tpl.rr[id] = true
    S.selHR[id] = nil
    S.selRR[id] = true
    return true
end

-- Aktueller Raid-Key: laufender Raid, sonst im Setup gewaehlter Raid.
function S.GetKey()
    local session = BananaLoot:GetRaidSession()
    if session and session.running and session.raidKey then return session.raidKey end
    return S.setupKey
end

-- Auswahl aus den aktuellen HR-/Raid-Roll-Listen vorbelegen.
function S.LoadFromCurrent(key)
    S.selHR, S.selRR = {}, {}
    local pool = BananaLoot:GetSetupPool(key)
    for id in pairs(pool) do
        if BananaLoot:IsHardReserve(id) then S.selHR[id] = true
        elseif BananaLoot:IsRaidRollItem(id) then S.selRR[id] = true end
    end
end

-- ============================================================
-- 2) FENSTER
-- ============================================================
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
}
local PANEL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function MakeButton(name, parent, w, h, text)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(h)
    if text then b:SetText(text) end
    return b
end

local function MakeWindow(name, w, h)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetWidth(w)
    f:SetHeight(h)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop(BACKDROP)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    local close = CreateFrame("Button", name .. "Close", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        this:GetParent():Hide()
    end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -16)
    return f
end

-- ------------------------------------------------------------
-- 2a) Raid-Auswahl (beim Klick auf "Raid starten")
-- ------------------------------------------------------------
local CH_COLS, CH_BTN_W, CH_BTN_H = 2, 170, 28

S.chooser = MakeWindow("BananaLootRaidChooser", 400, 120)
S.chooser.hint = S.chooser:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
S.chooser.hint:SetPoint("TOP", S.chooser, "TOP", 0, -40)
S.chooser.hint:SetWidth(350)
S.chooser.btns = {}
S.chooser.noneBtn = MakeButton("BananaLootRaidChooserNone", S.chooser, 350, 24)
S.chooser.cancelBtn = MakeButton("BananaLootRaidChooserCancel", S.chooser, 120, 22)
S.chooser.cancelBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    S.chooser:Hide()
end)
S.chooser.noneBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    S.OnRaidPicked(nil)
end)

function S.BuildChooser()
    local raids = BananaLoot:GetSetupRaids()
    local detected = BananaLoot:RLDetectRaidKey()
    local n = table.getn(raids)
    for i = 1, n do
        local b = S.chooser.btns[i]
        if not b then
            b = MakeButton("BananaLootRaidChooserBtn" .. i, S.chooser, CH_BTN_W, CH_BTN_H)
            S.chooser.btns[i] = b
        end
        local col = math.mod(i - 1, CH_COLS)
        local row = math.floor((i - 1) / CH_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", S.chooser, "TOPLEFT", 20 + col * (CH_BTN_W + 10), -64 - row * (CH_BTN_H + 4))
        local label = raids[i].name
        if raids[i].key == detected then label = "|cff33ff99" .. label .. "|r" end
        b:SetText(label)
        b.raidKey = raids[i].key
        b:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            S.OnRaidPicked(this.raidKey)
        end)
        b:Show()
    end
    for i = n + 1, table.getn(S.chooser.btns) do S.chooser.btns[i]:Hide() end
    local rows = math.ceil(n / CH_COLS)
    local y = 64 + rows * (CH_BTN_H + 4) + 6
    S.chooser.noneBtn:ClearAllPoints()
    S.chooser.noneBtn:SetPoint("TOPLEFT", S.chooser, "TOPLEFT", 25, -y)
    S.chooser.cancelBtn:ClearAllPoints()
    S.chooser.cancelBtn:SetPoint("TOP", S.chooser, "TOP", 0, -(y + 32))
    S.chooser:SetHeight(y + 66)
    S.chooser.title:SetText(BananaLoot:L(S.chooserMode == "setup" and "SETUP_CHOOSE_TITLE_SETUP" or "SETUP_CHOOSE_TITLE"))
    S.chooser.hint:SetText(BananaLoot:L("SETUP_CHOOSE_HINT"))
    S.chooser.noneBtn:SetText(BananaLoot:L(S.chooserMode == "setup" and "SETUP_CHOOSE_NONE_SETUP" or "SETUP_CHOOSE_NONE"))
    S.chooser.cancelBtn:SetText(BananaLoot:L("SETUP_CANCEL"))
end

-- Raid im Auswahlfenster angeklickt (key = nil: ohne Vorlage).
function S.OnRaidPicked(key)
    S.chooser:Hide()
    if S.chooserMode == "setup" then
        if not key then return end
        S.setupKey = key
        local session = BananaLoot:GetRaidSession()
        if session and session.running then session.raidKey = key end
        S.LoadFromCurrent(key)
        S.tab = "HR"
        S.bossIdx = 0
        S.PrefetchRaid(key)
        S.Open()
        return
    end
    if BananaLoot_UI and BananaLoot_UI.DoStartRaid then
        if not BananaLoot_UI:DoStartRaid(key) then return end
    end
    if not key then return end
    S.setupKey = key
    S.bossIdx = 0
    S.tab = "HR"
    S.PrefetchRaid(key)
    local tpl = BananaLoot:GetRaidTemplate(key)
    if tpl and (CountSet(tpl.hr) + CountSet(tpl.rr)) > 0 then
        S.pendingKey = key
        local d = StaticPopupDialogs["BANANALOOT_SETUP_TEMPLATE"]
        d.text = string.format(BananaLoot:L("SETUP_TEMPLATE_ASK"),
            BananaLoot:GetSetupRaidName(key), CountSet(tpl.hr), CountSet(tpl.rr))
        d.button1 = BananaLoot:L("SETUP_TEMPLATE_YES")
        d.button2 = BananaLoot:L("SETUP_TEMPLATE_NO")
        StaticPopup_Show("BANANALOOT_SETUP_TEMPLATE")
    else
        S.LoadFromCurrent(key)
        S.Open()
    end
end

-- Beutelisten des Raids im Hintergrund beim Server abfragen (Tooltips/Icons).
function S.PrefetchRaid(key)
    if not BananaLoot.PrefetchZoneItems or not BananaLoot:GetPrefetchEnabled() then return end
    local raids = BananaLoot:GetSetupRaids()
    for i = 1, table.getn(raids) do
        if raids[i].key == key and raids[i].zone then
            BananaLoot:PrefetchZoneItems(raids[i].zone, false)
        end
    end
end

StaticPopupDialogs["BANANALOOT_SETUP_TEMPLATE"] = {
    text = "",
    button1 = "",
    button2 = "",
    OnAccept = function()
        local key = S.pendingKey
        local tpl = BananaLoot:GetRaidTemplate(key)
        if not key or not tpl then return end
        local nHR, nRR = BananaLoot:ApplyRaidSetup(key, tpl.hr, tpl.rr)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SETUP_TEMPLATE_APPLIED"),
            BananaLoot:GetSetupRaidName(key), nHR, nRR))
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    end,
    OnCancel = function()
        if S.pendingKey then
            S.LoadFromCurrent(S.pendingKey)
            S.Open()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

-- ------------------------------------------------------------
-- 2b) Setup-Fenster
-- ------------------------------------------------------------
local FW, FH = 720, 520
S.frame = MakeWindow("BananaLootRaidSetupFrame", FW, FH)
local F = S.frame

F.hint = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
F.hint:SetPoint("TOP", F, "TOP", 0, -38)
F.hint:SetWidth(660)
F.hint:SetJustifyH("CENTER")

-- Tabs
local TAB_KEYS = { "HR", "SR", "RR", "DROPS" }
S.tabBtns = {}
for i = 1, table.getn(TAB_KEYS) do
    local b = MakeButton("BananaLootRaidSetupTab" .. i, F, 150, 24)
    b:SetPoint("TOPLEFT", F, "TOPLEFT", 20 + (i - 1) * 154, -62)
    b.tabKey = TAB_KEYS[i]
    b:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        S.SetTab(this.tabKey)
    end)
    S.tabBtns[i] = b
end

-- Linke Spalte: Bosse
F.left = CreateFrame("Frame", "BananaLootRaidSetupBosses", F)
F.left:SetWidth(200)
F.left:SetHeight(NUM_BOSS_ROWS * BOSS_ROW_H + 12)
F.left:SetPoint("TOPLEFT", F, "TOPLEFT", 20, -96)
F.left:SetBackdrop(PANEL_BACKDROP)
F.left:SetBackdropColor(0, 0, 0, 0.8)

F.leftHint = F.left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
F.leftHint:SetPoint("TOPLEFT", F.left, "TOPLEFT", 10, -10)
F.leftHint:SetWidth(180)
F.leftHint:SetJustifyH("LEFT")
F.leftHint:SetJustifyV("TOP")

for i = 1, NUM_BOSS_ROWS do
    local r = CreateFrame("Button", "BananaLootRaidSetupBoss" .. i, F.left)
    r:SetWidth(186)
    r:SetHeight(BOSS_ROW_H)
    r:SetPoint("TOPLEFT", F.left, "TOPLEFT", 7, -6 - (i - 1) * BOSS_ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.text:SetWidth(178)
    r.text:SetJustifyH("LEFT")
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints(r)
    r.sel:SetTexture(1, 0.82, 0, 0.25)
    r.sel:Hide()
    r.idx = i - 1
    r:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        S.bossIdx = this.idx
        S.offset = 0
        S.Refresh()
    end)
    S.bossRows[i] = r
end

-- Rechte Seite: Suche + Liste
F.searchLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.searchLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 240, -102)

F.searchBox = CreateFrame("EditBox", "BananaLootRaidSetupSearch", F, "InputBoxTemplate")
F.searchBox:SetWidth(190)
F.searchBox:SetHeight(20)
F.searchBox:SetPoint("LEFT", F.searchLabel, "RIGHT", 12, 0)
F.searchBox:SetAutoFocus(false)
F.searchBox:SetMaxLetters(40)
F.searchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
F.searchBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
F.searchBox:SetScript("OnTextChanged", function()
    if S.loading then return end
    S.search = string.lower(this:GetText() or "")
    S.offset = 0
    S.Refresh()
end)

F.countText = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
F.countText:SetPoint("TOPRIGHT", F, "TOPRIGHT", -34, -106)
F.countText:SetJustifyH("RIGHT")

F.list = CreateFrame("Frame", "BananaLootRaidSetupList", F)
F.list:SetWidth(440)
F.list:SetHeight(NUM_ROWS * ROW_H)
F.list:SetPoint("TOPLEFT", F, "TOPLEFT", 234, -128)
F.list:EnableMouseWheel(true)

F.slider = CreateFrame("Slider", "BananaLootRaidSetupSlider", F, "UIPanelScrollBarTemplate")
F.slider:SetPoint("TOPLEFT", F.list, "TOPRIGHT", 6, -16)
F.slider:SetPoint("BOTTOMLEFT", F.list, "BOTTOMRIGHT", 6, 16)
F.slider:SetMinMaxValues(0, 0)
F.slider:SetValueStep(1)
F.slider:SetValue(0)
F.slider:SetScript("OnValueChanged", function()
    if S.loading then return end
    S.offset = math.floor((arg1 or 0) + 0.5)
    S.UpdateRows()
end)
local upBtn = getglobal("BananaLootRaidSetupSliderScrollUpButton")
local downBtn = getglobal("BananaLootRaidSetupSliderScrollDownButton")
if upBtn then
    upBtn:SetScript("OnClick", function() F.slider:SetValue(F.slider:GetValue() - 1) end)
end
if downBtn then
    downBtn:SetScript("OnClick", function() F.slider:SetValue(F.slider:GetValue() + 1) end)
end
F.list:SetScript("OnMouseWheel", function()
    F.slider:SetValue(F.slider:GetValue() - arg1 * 3)
end)

-- Item-Tooltip: echter Item-Tooltip aus dem Client-Cache, sonst Ersatztext.
function S.ShowItemTooltip(owner, id)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(function() GameTooltip:SetHyperlink("item:" .. id .. ":0:0:0:0:0:0:0") end)
    local lines = 0
    if ok and GameTooltip:NumLines() then lines = GameTooltip:NumLines() end
    if lines == 0 then
        local name, quality, _, st = BananaLoot:SetupItemInfo(id)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cff" .. (QUALITY_HEX[quality] or "ffffff") .. name .. "|r")
        if st and st.ilvl then
            GameTooltip:AddLine(string.format(BananaLoot:L("SETUP_TIP_ILVL"), st.ilvl), 1, 1, 1)
        end
        GameTooltip:AddLine(BananaLoot:L("SETUP_TIP_UNCACHED"), 0.7, 0.7, 0.7, 1)
    end
    GameTooltip:Show()
end

-- Reihen der Item-Liste
local function CreateRow(i)
    local r = CreateFrame("Button", "BananaLootRaidSetupRow" .. i, F.list)
    r:SetWidth(440)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", F.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    r.check = CreateFrame("CheckButton", "BananaLootRaidSetupRow" .. i .. "Check", r, "UICheckButtonTemplate")
    r.check:SetWidth(24)
    r.check:SetHeight(24)
    r.check:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.check:EnableMouse(false)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetWidth(20)
    r.icon:SetHeight(20)
    r.icon:SetPoint("LEFT", r.check, "RIGHT", 2, 0)

    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWidth(270)
    r.text:SetJustifyH("LEFT")

    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.tag:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.tag:SetWidth(100)
    r.tag:SetJustifyH("RIGHT")

    r.act = MakeButton("BananaLootRaidSetupRow" .. i .. "Act", r, 120, 20)
    r.act:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.act:SetScript("OnClick", function()
        local row = this:GetParent()
        if row.entry and row.entry.kind == "drop" then
            BananaLoot:PlayClickSound()
            S.OnDropAction(row.entry.id)
        end
    end)

    r:SetScript("OnClick", function() S.OnRowClick(this) end)
    r:SetScript("OnEnter", function()
        if this.entry and this.entry.id then S.ShowItemTooltip(this, this.entry.id) end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end
for i = 1, NUM_ROWS do S.rows[i] = CreateRow(i) end

-- SR-Seite
F.srPane = CreateFrame("Frame", "BananaLootRaidSetupSR", F)
F.srPane:SetWidth(680)
F.srPane:SetHeight(360)
F.srPane:SetPoint("TOPLEFT", F, "TOPLEFT", 20, -100)
F.srPane:SetBackdrop(PANEL_BACKDROP)
F.srPane:SetBackdropColor(0, 0, 0, 0.8)
F.srText = F.srPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
F.srText:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 20, -20)
F.srText:SetWidth(640)
F.srText:SetJustifyH("LEFT")
F.srText:SetJustifyV("TOP")
F.srCount = F.srPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.srCount:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 20, -190)
F.srImportBtn = MakeButton("BananaLootRaidSetupSRImport", F.srPane, 240, 28)
F.srImportBtn:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 20, -224)
F.srImportBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI and BananaLoot_UI.ShowImport then BananaLoot_UI:ShowImport() end
end)
F.srOpenBtn = MakeButton("BananaLootRaidSetupSROpen", F.srPane, 240, 28)
F.srOpenBtn:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 270, -224)
F.srOpenBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local sr = getglobal("BananaLootSRFrame")
    if sr and not sr:IsShown() then sr:Show() end
end)

-- Untere Buttonleiste
F.allBtn = MakeButton("BananaLootRaidSetupAll", F, 90, 24)
F.allBtn:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 20, 18)
F.allBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); S.SetVisible(true) end)
F.noneBtn = MakeButton("BananaLootRaidSetupNone", F, 90, 24)
F.noneBtn:SetPoint("LEFT", F.allBtn, "RIGHT", 6, 0)
F.noneBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); S.SetVisible(false) end)
F.applyBtn = MakeButton("BananaLootRaidSetupApply", F, 190, 26)
F.applyBtn:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -20, 16)
F.applyBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); S.Apply(true) end)
F.nextBtn = MakeButton("BananaLootRaidSetupNext", F, 100, 24)
F.nextBtn:SetPoint("RIGHT", F.applyBtn, "LEFT", -10, 0)
F.nextBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); S.Step(1) end)
F.backBtn = MakeButton("BananaLootRaidSetupBack", F, 100, 24)
F.backBtn:SetPoint("RIGHT", F.nextBtn, "LEFT", -6, 0)
F.backBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); S.Step(-1) end)

-- ------------------------------------------------------------
-- 2c) Logik des Fensters
-- ------------------------------------------------------------
function S.CurrentSel()
    if S.tab == "RR" then return S.selRR, S.selHR end
    return S.selHR, S.selRR
end

-- Ist das Item in diesem Tab gesperrt (steht in der anderen Liste bzw. Bankreserve)?
-- Rueckgabe: Grund-Schluessel oder nil.
function S.Blocked(id)
    if BananaLoot:IsBankReserve(id) then return "SETUP_TAG_BR" end
    if S.tab == "RR" and S.selHR[id] then return "SETUP_TAG_HR" end
    return nil
end

function S.BuildEntries()
    local entries = {}
    if S.tab == "DROPS" then
        local session = BananaLoot:GetRaidSession()
        local order = session and session.dropOrder
        if order then
            for i = table.getn(order), 1, -1 do
                local id = order[i]
                local d = session.drops and session.drops[id]
                if d then
                    local ok = true
                    if S.search ~= "" then
                        local nm = string.lower(BananaLoot:SetupItemInfo(id))
                        ok = string.find(nm, S.search, 1, true) ~= nil
                    end
                    if ok then table.insert(entries, { kind = "drop", id = id, link = d.link, icon = d.icon }) end
                end
            end
        end
        S.entries = entries
        return
    end
    local raid = BananaLoot_RaidLoot and BananaLoot_RaidLoot[S.GetKey()]
    if raid then
        local first, last = 1, table.getn(raid)
        if S.bossIdx > 0 and S.bossIdx <= last then first, last = S.bossIdx, S.bossIdx end
        for b = first, last do
            local ids = raid[b][2]
            local items = {}
            for i = 1, table.getn(ids) do
                local id = ids[i]
                local ok = true
                if S.search ~= "" then
                    local nm = string.lower(BananaLoot:SetupItemInfo(id))
                    ok = string.find(nm, S.search, 1, true) ~= nil
                end
                if ok then table.insert(items, { kind = "item", id = id, boss = b }) end
            end
            if table.getn(items) > 0 then
                if first ~= last then
                    table.insert(entries, { kind = "boss", boss = b, name = raid[b][1], items = items })
                end
                for i = 1, table.getn(items) do table.insert(entries, items[i]) end
            end
        end
    end
    S.entries = entries
end

local function SetRowTexture(r, id, iconName)
    if iconName then
        r.icon:SetTexture("Interface\\Icons\\" .. iconName)
    else
        r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

function S.UpdateRows()
    local sel = S.CurrentSel()
    for i = 1, NUM_ROWS do
        local r = S.rows[i]
        local e = S.entries[S.offset + i]
        r.entry = e
        if not e then
            r:Hide()
        else
            r.act:Hide()
            r.tag:SetText("")
            if e.kind == "boss" then
                local n = 0
                for k = 1, table.getn(e.items) do
                    if sel[e.items[k].id] then n = n + 1 end
                end
                r.check:Hide()
                r.icon:Hide()
                r.text:ClearAllPoints()
                r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
                r.text:SetText("|cffffd100" .. e.name .. "|r")
                r.tag:SetText("|cffffd100" .. n .. "/" .. table.getn(e.items) .. "|r")
            else
                local name, quality, icon = BananaLoot:SetupItemInfo(e.id)
                if not icon and e.icon then icon = string.gsub(e.icon, "^Interface\\Icons\\", "") end
                r.icon:Show()
                SetRowTexture(r, e.id, icon)
                r.text:ClearAllPoints()
                r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                local color = "|cff" .. (QUALITY_HEX[quality] or "ffffff")
                if e.kind == "drop" then
                    r.check:Hide()
                    r.text:SetText(color .. name .. "|r")
                    r.act:Show()
                    if BananaLoot:IsRaidRollItem(e.id) then
                        r.act:SetText(BananaLoot:L("SETUP_DROPS_DONE"))
                        r.act:Disable()
                    else
                        r.act:SetText(BananaLoot:L("SETUP_DROPS_BTN"))
                        r.act:Enable()
                    end
                    if BananaLoot:IsHardReserve(e.id) then
                        r.tag:SetText("|cffff8080" .. BananaLoot:L("SETUP_TAG_HR") .. "|r")
                    end
                else
                    r.check:Show()
                    local why = S.Blocked(e.id)
                    if why then
                        r.check:SetChecked(false)
                        r.text:SetText("|cff808080" .. name .. "|r")
                        r.tag:SetText("|cff808080" .. BananaLoot:L(why) .. "|r")
                    else
                        r.check:SetChecked(sel[e.id] and true or false)
                        r.text:SetText(color .. name .. "|r")
                    end
                end
            end
            r:Show()
        end
    end
end

function S.UpdateBossRows()
    local raid = BananaLoot_RaidLoot and BananaLoot_RaidLoot[S.GetKey()]
    local sel = S.CurrentSel()
    local nBoss = raid and table.getn(raid) or 0
    for i = 1, NUM_BOSS_ROWS do
        local r = S.bossRows[i]
        local text
        if i == 1 then
            text = BananaLoot:L("SETUP_ALL_BOSSES")
        elseif raid and raid[i - 1] then
            local ids = raid[i - 1][2]
            local n = 0
            for k = 1, table.getn(ids) do
                if sel[ids[k]] then n = n + 1 end
            end
            text = raid[i - 1][1] .. " |cffaaaaaa(" .. n .. "/" .. table.getn(ids) .. ")|r"
        end
        if text and i - 1 <= nBoss then
            r.text:SetText(text)
            if S.bossIdx == i - 1 then r.sel:Show() else r.sel:Hide() end
            r:Show()
        else
            r:Hide()
        end
    end
end

function S.Refresh()
    if not F:IsShown() then return end
    local key = S.GetKey()
    local raidName = BananaLoot:GetSetupRaidName(key)
    if raidName then
        F.title:SetText(string.format(BananaLoot:L("SETUP_TITLE"), raidName))
    else
        F.title:SetText(BananaLoot:L("SETUP_TITLE_NONE"))
    end
    local tabNames = { "SETUP_TAB_HR", "SETUP_TAB_SR", "SETUP_TAB_RR", "SETUP_TAB_DROPS" }
    for i = 1, table.getn(TAB_KEYS) do
        local label = BananaLoot:L(tabNames[i])
        if S.tab == TAB_KEYS[i] then label = "|cffffd100" .. label .. "|r" end
        S.tabBtns[i]:SetText(label)
    end
    F.hint:SetText(BananaLoot:L("SETUP_HINT_" .. S.tab))
    F.searchLabel:SetText(BananaLoot:L("SETUP_SEARCH"))
    F.allBtn:SetText(BananaLoot:L("SETUP_BTN_ALL"))
    F.noneBtn:SetText(BananaLoot:L("SETUP_BTN_NONE"))
    F.backBtn:SetText(BananaLoot:L("SETUP_BTN_BACK"))
    F.nextBtn:SetText(BananaLoot:L("SETUP_BTN_NEXT"))
    F.applyBtn:SetText(BananaLoot:L("SETUP_BTN_APPLY"))
    F.srImportBtn:SetText(BananaLoot:L("SETUP_SR_IMPORT"))
    F.srOpenBtn:SetText(BananaLoot:L("SETUP_SR_OPEN"))

    local isSR = (S.tab == "SR")
    local isDrops = (S.tab == "DROPS")
    local isPick = (S.tab == "HR" or S.tab == "RR")
    if isSR then F.srPane:Show() else F.srPane:Hide() end
    if isSR then
        F.list:Hide(); F.slider:Hide(); F.searchBox:Hide(); F.searchLabel:Hide(); F.countText:Hide(); F.left:Hide()
        F.srText:SetText(BananaLoot:L("SETUP_SR_TEXT"))
        local n = 0
        for _ in pairs(BananaLoot.reservations or {}) do n = n + 1 end
        F.srCount:SetText(string.format(BananaLoot:L("SETUP_SR_COUNT"), n))
    else
        F.list:Show(); F.slider:Show(); F.searchBox:Show(); F.searchLabel:Show(); F.countText:Show(); F.left:Show()
        if isPick then
            F.leftHint:SetText("")
            S.UpdateBossRows()
        else
            for i = 1, NUM_BOSS_ROWS do S.bossRows[i]:Hide() end
            F.leftHint:SetText(BananaLoot:L("SETUP_DROPS_SIDE"))
        end
        S.BuildEntries()
        local n = table.getn(S.entries)
        local maxOff = math.max(0, n - NUM_ROWS)
        if S.offset > maxOff then S.offset = maxOff end
        S.loading = true
        F.slider:SetMinMaxValues(0, maxOff)
        F.slider:SetValue(S.offset)
        S.loading = false
        S.UpdateRows()
        if isPick then
            local sel = S.CurrentSel()
            F.countText:SetText(string.format(BananaLoot:L(S.tab == "HR" and "SETUP_COUNT_HR" or "SETUP_COUNT_RR"),
                CountSet(sel)))
        else
            F.countText:SetText(string.format(BananaLoot:L("SETUP_COUNT_DROPS"), n))
        end
        if n == 0 then
            F.leftHint:SetText(F.leftHint:GetText() .. (isDrops and "\n\n" .. BananaLoot:L("SETUP_DROPS_EMPTY") or ""))
        end
    end
    if isPick then F.allBtn:Show(); F.noneBtn:Show() else F.allBtn:Hide(); F.noneBtn:Hide() end
    if S.tab == "HR" then F.backBtn:Hide() else F.backBtn:Show() end
    if S.tab == "DROPS" then F.nextBtn:Hide() else F.nextBtn:Show() end
end

function S.SetTab(tab)
    S.tab = tab
    S.offset = 0
    S.Refresh()
end

function S.Step(dir)
    local idx = 1
    for i = 1, table.getn(TAB_KEYS) do
        if TAB_KEYS[i] == S.tab then idx = i end
    end
    idx = idx + dir
    if idx < 1 then idx = 1 end
    if idx > table.getn(TAB_KEYS) then idx = table.getn(TAB_KEYS) end
    S.SetTab(TAB_KEYS[idx])
end

-- Item (de)selektieren; ein Item steht nie in HR UND Raid-Roll.
function S.SetItem(id, on)
    if S.Blocked(id) then return end
    local sel, other = S.CurrentSel()
    if on then
        sel[id] = true
        other[id] = nil
    else
        sel[id] = nil
    end
end

function S.OnRowClick(row)
    local e = row.entry
    if not e then return end
    if e.kind == "item" then
        local sel = S.CurrentSel()
        S.SetItem(e.id, not sel[e.id])
    elseif e.kind == "boss" then
        local sel = S.CurrentSel()
        local all = true
        for k = 1, table.getn(e.items) do
            local id = e.items[k].id
            if not S.Blocked(id) and not sel[id] then all = false end
        end
        for k = 1, table.getn(e.items) do S.SetItem(e.items[k].id, not all) end
    else
        return
    end
    BananaLoot:PlayClickSound()
    S.UpdateBossRows()
    S.UpdateRows()
    local sel = S.CurrentSel()
    F.countText:SetText(string.format(BananaLoot:L(S.tab == "HR" and "SETUP_COUNT_HR" or "SETUP_COUNT_RR"), CountSet(sel)))
end

-- "Alle"/"Keine": alle aktuell sichtbaren (gefilterten) Items.
function S.SetVisible(on)
    for i = 1, table.getn(S.entries) do
        local e = S.entries[i]
        if e.kind == "item" then S.SetItem(e.id, on) end
    end
    S.Refresh()
end

function S.OnDropAction(id)
    local d
    local session = BananaLoot:GetRaidSession()
    if session and session.drops then d = session.drops[id] end
    local savedTemplate = BananaLoot:MarkRaidRollNextTime(id, nil)
    local link = (d and d.link) or BananaLoot:SetupItemLink(id)
    local suffix
    if savedTemplate then
        suffix = string.format(BananaLoot:L("SETUP_DROPS_MSG_TPL"), BananaLoot:GetSetupRaidName(S.GetKey()) or "")
    else
        suffix = BananaLoot:L("SETUP_DROPS_MSG_NOTPL")
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SETUP_DROPS_MSG"), link, suffix))
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    S.Refresh()
end

-- Auswahl anwenden und als Vorlage des Raids speichern.
function S.Apply(close)
    local key = S.GetKey()
    if not key then
        if close then F:Hide() end
        return
    end
    local nHR, nRR = BananaLoot:ApplyRaidSetup(key, S.selHR, S.selRR)
    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SETUP_APPLIED"),
        BananaLoot:GetSetupRaidName(key), nHR, nRR))
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    if close then F:Hide() else S.Refresh() end
end

function S.Open()
    S.loading = true
    F.searchBox:SetText("")
    S.search = ""
    S.loading = false
    S.offset = 0
    F:Show()
    S.Refresh()
end

F:SetScript("OnShow", function() S.Refresh() end)

-- ============================================================
-- 3) OEFFENTLICHE EINSTIEGSPUNKTE
-- ============================================================

-- Raid-Auswahl vor dem Raid-Start (Button "Raid starten").
function BananaLoot_UI:ShowRaidChooser()
    S.chooserMode = "start"
    S.BuildChooser()
    S.chooser:Show()
end

-- Setup-Fenster oeffnen (Button im Seitenmenue, /bl setup). Ohne bekannten Raid
-- zuerst die Raid-Auswahl.
function BananaLoot_UI:ShowRaidSetup(tab)
    if not BananaLoot_RaidLoot then return end
    local key = S.GetKey()
    if not key then
        S.chooserMode = "setup"
        S.BuildChooser()
        S.chooser:Show()
        return
    end
    S.LoadFromCurrent(key)
    S.tab = tab or "HR"
    S.bossIdx = 0
    S.Open()
end

function BananaLoot_UI:ApplyLocaleSetup()
    if F:IsShown() then S.Refresh() end
    if S.chooser:IsShown() then S.BuildChooser() end
end
