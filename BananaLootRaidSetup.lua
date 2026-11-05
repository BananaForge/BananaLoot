-- BananaLootRaidSetup.lua
-- Raids VORBEREITEN und starten.
--   Optionen > "Neuer Raid": Raid (Instanz) waehlen, dann Hard Reserve (HR),
--   Soft Reserve (Hinweis/Import) und Raid-Roll-Items aus der Beutetabelle
--   abhaken (mit Qualitaetsfilter), Raid benennen und speichern. Beliebig
--   viele Raids koennen vorbereitet werden; im Hauptfenster waehlt man einen
--   aus und startet ihn mit "Raid starten" (dabei werden HR/Raid-Roll-Listen
--   gesetzt). Die Auswahl pro Raid-Typ dient zusaetzlich als Vorlage fuer den
--   naechsten neuen Raid desselben Typs.
--   Drops-Tab (im laufenden Raid): gefallene Items per Klick "kuenftig Raid-
--   Roll" setzen, falls sie versehentlich normal gerollt wurden.
--
-- Daten:  BananaLootRaidLoot.lua (Raid -> Bosse -> Item-IDs, aus AtlasLoot)
-- Texte:  LOCALE-Tabellen in BananaLoot.lua (Schluessel SETUP_*)
-- Speicher: BananaLoot_DB.preparedRaids = { { id, name, raidKey, hr, rr, created }, ... }
--           BananaLoot_DB.selectedPreparedRaid = id
--           BananaLoot_DB.raidTemplates[raidKey] = { hr = {id=true}, rr = {id=true}, savedAt }
--           BananaLoot_DB.raidSession.raidKey / .raidName / .preparedId / .drops / .dropOrder
--
-- Lua 5.0: kein #-Operator, kein %-Operator, kein string.gmatch/match, Events
-- ueber this/arg1. UI-Zustand liegt in der Tabelle S (Grenze von 200 lokalen
-- Variablen bzw. 32 Upvalues je Funktion).

local ROW_H = 26
local NUM_ROWS = 12
local BOSS_ROW_H = 20
local NUM_BOSS_ROWS = 18
local MAX_DROPS = 200

local QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80",
}

local S = {
    tab = "HR",        -- HR | SR | RR | BR | DROPS
    bossIdx = 0,       -- 0 = alle Bosse
    search = "",
    offset = 0,
    mode = "live",     -- "prepare" (Raid vorbereiten) | "live" (laufender Raid)
    prepKey = nil,     -- Raid-Key beim Vorbereiten
    editId = nil,      -- ID eines bearbeiteten vorbereiteten Raids
    qual = {},         -- aktive Qualitaetsfilter [1..5] = true (leer = alle)
    selHR = {},        -- [itemID] = true (noch nicht angewendet)
    selRR = {},
    selBR = {},
    entries = {},
    rows = {},
    bossRows = {},
    setupKey = nil,    -- Raid-Key fuer den Live-Modus ohne Raid-Key in der Session
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

function BananaLoot:SaveRaidTemplate(key, hrSet, rrSet, brSet)
    if not key then return end
    BananaLoot.EnsureDB()
    if not BananaLoot_DB.raidTemplates then BananaLoot_DB.raidTemplates = {} end
    BananaLoot_DB.raidTemplates[key] = { hr = CopySet(hrSet), rr = CopySet(rrSet), br = CopySet(brSet), savedAt = time() }
end

-- Vorbereitete Raids ---------------------------------------------------
function BananaLoot:GetPreparedRaids()
    BananaLoot.EnsureDB()
    if not BananaLoot_DB.preparedRaids then BananaLoot_DB.preparedRaids = {} end
    return BananaLoot_DB.preparedRaids
end

function BananaLoot:GetPreparedRaid(id)
    if not id then return nil end
    local list = self:GetPreparedRaids()
    for i = 1, table.getn(list) do
        if list[i].id == id then return list[i], i end
    end
    return nil
end

-- Legt einen vorbereiteten Raid an (id = nil) oder aktualisiert ihn. Speichert
-- zusaetzlich die Auswahl als Vorlage des Raid-Typs. Rueckgabe: Eintrag.
function BananaLoot:SavePreparedRaid(id, name, key, hrSet, rrSet, brSet)
    local list = self:GetPreparedRaids()
    local entry = self:GetPreparedRaid(id)
    if not entry then
        BananaLoot_DB.nextPreparedId = (BananaLoot_DB.nextPreparedId or 0) + 1
        entry = { id = BananaLoot_DB.nextPreparedId, created = time() }
        table.insert(list, entry)
    end
    entry.name = name
    entry.raidKey = key
    entry.hr = CopySet(hrSet)
    entry.rr = CopySet(rrSet)
    entry.br = CopySet(brSet)
    if self.EnsurePreparedCode then self:EnsurePreparedCode(entry) end   -- Raid-Code, SR-Status
    self:SaveRaidTemplate(key, hrSet, rrSet, brSet)
    return entry
end

function BananaLoot:DeletePreparedRaid(id)
    local e, idx = self:GetPreparedRaid(id)
    if not e then return false end
    if self.CodeOnDelete then self:CodeOnDelete(e) end
    table.remove(self:GetPreparedRaids(), idx)
    if BananaLoot_DB.selectedPreparedRaid == id then
        BananaLoot_DB.selectedPreparedRaid = nil
        -- Der ausgewaehlte Raid ist weg: seine SR (auch importierte/geflusterte) verschwinden aus dem
        -- Hauptfenster. Ein gerade laufender Raid behaelt seine SR.
        local session = self:GetRaidSession()
        if not (session and session.running) then self:ClearAllReservations() end
    end
    return true
end

function BananaLoot:SelectPreparedRaid(id)
    BananaLoot.EnsureDB()
    local old = self:GetSelectedPreparedRaid()
    BananaLoot_DB.selectedPreparedRaid = id
    -- SR-Sperre und per Raid-Code eingegangene SR auf den neuen Raid umstellen
    if self.CodeOnSelectionChanged then self:CodeOnSelectionChanged(old, self:GetPreparedRaid(id)) end
end

function BananaLoot:GetSelectedPreparedRaid()
    BananaLoot.EnsureDB()
    return self:GetPreparedRaid(BananaLoot_DB.selectedPreparedRaid)
end

-- Name des laufenden bzw. ausgewaehlten Raids (nil, wenn keiner).
function BananaLoot:GetSelectedRaidLabel()
    local session = self:GetRaidSession()
    if session and session.running then
        return session.raidName or self:GetSetupRaidName(session.raidKey)
    end
    local e = self:GetSelectedPreparedRaid()
    if e then return e.name end
    return nil
end

-- Ueberschrift im Hauptfenster (siehe BananaLoot_UI:RefreshSR).
function BananaLoot:GetRaidHeadline()
    local label = self:GetSelectedRaidLabel()
    if label then return label end
    -- (Der Name eines frueher gespeicherten/geladenen Raid-Snapshots wird hier bewusst nicht
    -- mehr angezeigt: ohne ausgewaehlten vorbereiteten Raid steht die Aufforderung zur Auswahl.)
    return "|cff888888" .. self:L("SETUP_SELECT_NONE") .. "|r"
end

-- Wendet eine Auswahl auf die Bankreserve-, HR- und Raid-Roll-Liste an und
-- speichert sie als Vorlage (noTemplate = true: nicht speichern). Nur Items des
-- Raids (Pool) werden angefasst: abgehakte kommen auf die Liste, nicht (mehr)
-- abgehakte werden von dieser Liste entfernt. Ein Item steht nie in mehreren
-- Listen (Prioritaet Bankreserve > Hard Reserve > Raid-Roll).
-- Rueckgabe: Anzahl HR, Anzahl Raid-Roll, Anzahl Bankreserve.
function BananaLoot:ApplyRaidSetup(key, selHR, selRR, selBR, noTemplate)
    selBR = selBR or {}
    local pool = self:GetSetupPool(key)
    local nHR, nRR, nBR = 0, 0, 0
    for id in pairs(pool) do
        if self:IsBankReserve(id) and not selBR[id] then self:RemoveBankReserve(id) end
        if self:IsHardReserve(id) and not selHR[id] then self:RemoveHardReserve(id) end
        if self:IsRaidRollItem(id) and not selRR[id] then self:RemoveRaidRollItem(id) end
    end
    local hrKeep, rrKeep, brKeep = {}, {}, {}
    for id in pairs(pool) do
        if selBR[id] then
            if not self:IsBankReserve(id) then self:AddBankReserve(self:SetupItemLink(id)) end
            brKeep[id] = true
            nBR = nBR + 1
        elseif selHR[id] then
            if not self:IsHardReserve(id) then self:AddHardReserve(self:SetupItemLink(id)) end
            hrKeep[id] = true
            nHR = nHR + 1
        elseif selRR[id] then
            if not self:IsRaidRollItem(id) then self:AddRaidRollItem(self:SetupItemLink(id)) end
            rrKeep[id] = true
            nRR = nRR + 1
        end
    end
    if not noTemplate then self:SaveRaidTemplate(key, hrKeep, rrKeep, brKeep) end
    return nHR, nRR, nBR
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
        tpl = { hr = {}, rr = {}, br = {}, savedAt = time() }
        BananaLoot_DB.raidTemplates[key] = tpl
    end
    tpl.hr[id] = nil
    if tpl.br then tpl.br[id] = nil end
    tpl.rr[id] = true
    -- Auch der gestartete vorbereitete Raid merkt es sich fuer den naechsten Start.
    if session and session.preparedId then
        local pe = self:GetPreparedRaid(session.preparedId)
        if pe then
            pe.hr[id] = nil
            if pe.br then pe.br[id] = nil end
            pe.rr[id] = true
        end
    end
    S.selHR[id] = nil
    S.selBR[id] = nil
    S.selRR[id] = true
    return true
end

-- Aktueller Raid-Key: laufender Raid, sonst im Setup gewaehlter Raid.
function S.GetKey()
    if S.mode == "prepare" then return S.prepKey end
    local session = BananaLoot:GetRaidSession()
    if session and session.running and session.raidKey then return session.raidKey end
    return S.setupKey
end

-- Auswahl aus den aktuellen HR-/Raid-Roll-Listen vorbelegen.
function S.LoadFromCurrent(key)
    S.selHR, S.selRR, S.selBR = {}, {}, {}
    local pool = BananaLoot:GetSetupPool(key)
    for id in pairs(pool) do
        if BananaLoot:IsBankReserve(id) then S.selBR[id] = true
        elseif BananaLoot:IsHardReserve(id) then S.selHR[id] = true
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
    BananaLoot_Theme.Darken(f)
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
-- 2a) Raid-Auswahl (Optionen > Neuer Raid)
-- ------------------------------------------------------------
local CH_COLS, CH_BTN_W, CH_BTN_H = 2, 170, 28

S.chooser = MakeWindow("BananaLootRaidChooser", 400, 120)
S.chooser.hint = S.chooser:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
S.chooser.hint:SetPoint("TOP", S.chooser, "TOP", 0, -40)
S.chooser.hint:SetWidth(350)
S.chooser.btns = {}
S.chooser.cancelBtn = MakeButton("BananaLootRaidChooserCancel", S.chooser, 120, 22)
S.chooser.cancelBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    S.chooser:Hide()
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
    local y = 64 + rows * (CH_BTN_H + 4) + 8
    S.chooser.cancelBtn:ClearAllPoints()
    S.chooser.cancelBtn:SetPoint("TOP", S.chooser, "TOP", 0, -y)
    S.chooser:SetHeight(y + 40)
    local titleKey = (S.chooserMode == "live") and "SETUP_CHOOSE_TITLE_LIVE" or "SETUP_CHOOSE_TITLE"
    S.chooser.title:SetText(BananaLoot:L(titleKey))
    S.chooser.hint:SetText(BananaLoot:L("SETUP_CHOOSE_HINT"))
    S.chooser.cancelBtn:SetText(BananaLoot:L("SETUP_CANCEL"))
end

-- Raid im Auswahlfenster angeklickt.
function S.OnRaidPicked(key)
    S.chooser:Hide()
    if not key then return end
    S.PrefetchRaid(key)
    if S.chooserMode == "live" then
        S.setupKey = key
        local session = BananaLoot:GetRaidSession()
        if session and session.running then session.raidKey = key end
        S.mode = "live"
        S.LoadFromCurrent(key)
        S.tab = "HR"
        S.bossIdx = 0
        S.Open()
        return
    end
    -- Vorbereiten: Vorlage des letzten Raids dieses Typs anbieten
    local tpl = BananaLoot:GetRaidTemplate(key)
    if tpl and (CountSet(tpl.hr) + CountSet(tpl.rr) + CountSet(tpl.br)) > 0 then
        S.pendingKey = key
        local d = StaticPopupDialogs["BANANALOOT_SETUP_TEMPLATE"]
        d.text = string.format(BananaLoot:L("SETUP_TEMPLATE_ASK"),
            BananaLoot:GetSetupRaidName(key), CountSet(tpl.hr), CountSet(tpl.br), CountSet(tpl.rr))
        d.button1 = BananaLoot:L("SETUP_TEMPLATE_YES")
        d.button2 = BananaLoot:L("SETUP_TEMPLATE_NO")
        StaticPopup_Show("BANANALOOT_SETUP_TEMPLATE")
    else
        S.BeginPrepare(key, nil, nil)
    end
end

-- Beutelisten des Raids im Hintergrund beim Server abfragen (Tooltips/Icons).
function S.PrefetchRaid(key)
    if BananaLoot.testMode then return end   -- im Testlauf keine Server-Abfragen
    if not BananaLoot.PrefetchZoneItems or not BananaLoot:GetPrefetchEnabled() then return end
    local raids = BananaLoot:GetSetupRaids()
    for i = 1, table.getn(raids) do
        if raids[i].key == key and raids[i].zone then
            BananaLoot:PrefetchZoneItems(raids[i].zone, false)
        end
    end
end

-- Standardname eines neuen Raids: "<Raid> <TT.MM.JJ>".
function S.DefaultName(key)
    local d = ""
    if date then d = " " .. date("%d.%m.%y") end
    return (BananaLoot:GetSetupRaidName(key) or "Raid") .. d
end

-- Raid vorbereiten starten (neuer Raid: id/entry = nil; sonst bearbeiten).
function S.BeginPrepare(key, tpl, entry)
    S.mode = "prepare"
    S.prepKey = key
    S.editId = entry and entry.id or nil
    S.selHR, S.selRR, S.selBR = {}, {}, {}
    local src = entry or tpl
    if src then
        S.selHR = CopySet(src.hr)
        S.selRR = CopySet(src.rr)
        S.selBR = CopySet(src.br)
    end
    S.prepName = entry and entry.name or S.DefaultName(key)
    S.tab = "HR"
    S.bossIdx = 0
    S.Open()
end

StaticPopupDialogs["BANANALOOT_SETUP_TEMPLATE"] = {
    text = "",
    button1 = "",
    button2 = "",
    OnAccept = function()
        local key = S.pendingKey
        if key then S.BeginPrepare(key, BananaLoot:GetRaidTemplate(key), nil) end
    end,
    OnCancel = function()
        local key = S.pendingKey
        if key then S.BeginPrepare(key, nil, nil) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

-- ------------------------------------------------------------
-- 2b) Setup-Fenster
-- ------------------------------------------------------------
local FW, FH = 780, 556
S.frame = MakeWindow("BananaLootRaidSetupFrame", FW, FH)
local F = S.frame

F.hint = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
F.hint:SetPoint("TOP", F, "TOP", 0, -38)
F.hint:SetWidth(720)
F.hint:SetJustifyH("CENTER")

-- Tabs
local TAB_KEYS = { "HR", "SR", "RR", "BR", "DROPS" }
S.tabBtns = {}
for i = 1, table.getn(TAB_KEYS) do
    local b = MakeButton("BananaLootRaidSetupTab" .. i, F, 132, 24)
    b:SetPoint("TOPLEFT", F, "TOPLEFT", 20 + (i - 1) * 136, -62)
    b.tabKey = TAB_KEYS[i]
    b:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        S.SetTab(this.tabKey)
    end)
    S.tabBtns[i] = b
end

-- Raid-Name (nur beim Vorbereiten), rechts neben den drei Tabs
F.nameLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.nameLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 574, -66)
F.nameBox = CreateFrame("EditBox", "BananaLootRaidSetupName", F, "InputBoxTemplate")
F.nameBox:SetWidth(130)
F.nameBox:SetHeight(22)
F.nameBox:SetPoint("LEFT", F.nameLabel, "RIGHT", 12, 0)
F.nameBox:SetAutoFocus(false)
F.nameBox:SetMaxLetters(40)
F.nameBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
F.nameBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
F.nameBox:SetScript("OnTextChanged", function()
    if S.loading then return end
    S.prepName = this:GetText() or ""
end)

-- Linke Spalte: Bosse
F.left = CreateFrame("Frame", "BananaLootRaidSetupBosses", F)
F.left:SetWidth(200)
F.left:SetHeight(NUM_BOSS_ROWS * BOSS_ROW_H + 12)
F.left:SetPoint("TOPLEFT", F, "TOPLEFT", 20, -96)
F.left:SetBackdrop(PANEL_BACKDROP)
F.left:SetBackdropColor(0, 0, 0, BananaLoot_Theme.PANEL_ALPHA)

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

-- Rechte Seite: Suche, Qualitaetsfilter, Liste
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

-- Qualitaetsfilter: Weiss / Gruen / Blau / Episch / Orange (Mehrfachauswahl,
-- keine Auswahl = alle Qualitaeten)
F.qualLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.qualLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 240, -132)
S.qualBtns = {}
local QUAL_KEYS = { "SETUP_QUAL_1", "SETUP_QUAL_2", "SETUP_QUAL_3", "SETUP_QUAL_4", "SETUP_QUAL_5" }
for q = 1, 5 do
    local b = MakeButton("BananaLootRaidSetupQual" .. q, F, 66, 20)
    b:SetPoint("TOPLEFT", F, "TOPLEFT", 306 + (q - 1) * 68, -129)
    b.q = q
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetAllPoints(b)
    b.sel:SetTexture(1, 0.82, 0, 0.35)
    b.sel:Hide()
    b:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        if S.qual[this.q] then S.qual[this.q] = nil else S.qual[this.q] = true end
        S.offset = 0
        S.Refresh()
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
        GameTooltip:SetText(BananaLoot:L("SETUP_QUAL_TIP"), 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    S.qualBtns[q] = b
end

F.list = CreateFrame("Frame", "BananaLootRaidSetupList", F)
F.list:SetWidth(500)
F.list:SetHeight(NUM_ROWS * ROW_H)
F.list:SetPoint("TOPLEFT", F, "TOPLEFT", 234, -156)
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
    BananaLoot:ShowItemTooltip(owner, id, "ANCHOR_RIGHT")
end

-- Reihen der Item-Liste
local function CreateRow(i)
    local r = CreateFrame("Button", "BananaLootRaidSetupRow" .. i, F.list)
    r:SetWidth(500)
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
    r.text:SetWidth(330)
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
F.srPane:SetWidth(740)
F.srPane:SetHeight(360)
F.srPane:SetPoint("TOPLEFT", F, "TOPLEFT", 20, -100)
F.srPane:SetBackdrop(PANEL_BACKDROP)
F.srPane:SetBackdropColor(0, 0, 0, BananaLoot_Theme.PANEL_ALPHA)
F.srText = F.srPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
F.srText:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 20, -12)
F.srText:SetWidth(700)
F.srText:SetJustifyH("LEFT")
F.srText:SetJustifyV("TOP")
F.srCount = F.srPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.srCount:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 20, -112)
F.srImportBtn = MakeButton("BananaLootRaidSetupSRImport", F.srPane, 240, 28)
F.srImportBtn:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 20, -76)
F.srImportBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI and BananaLoot_UI.ShowImport then BananaLoot_UI:ShowImport() end
end)
F.srOpenBtn = MakeButton("BananaLootRaidSetupSROpen", F.srPane, 240, 28)
F.srOpenBtn:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 270, -76)
F.srOpenBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local sr = getglobal("BananaLootSRFrame")
    if sr and not sr:IsShown() then sr:Show() end
end)

-- Uebersicht aller Listen (HR / SR mit Spielern / Raid-Roll / Bankreserve), scrollbar
F.ovScroll = CreateFrame("ScrollFrame", "BananaLootRaidSetupOverviewScroll", F.srPane, "UIPanelScrollFrameTemplate")
F.ovScroll:SetPoint("TOPLEFT", F.srPane, "TOPLEFT", 16, -136)
F.ovScroll:SetPoint("BOTTOMRIGHT", F.srPane, "BOTTOMRIGHT", -34, 12)
F.ovChild = CreateFrame("Frame", "BananaLootRaidSetupOverviewChild", F.ovScroll)
F.ovChild:SetWidth(676)
F.ovChild:SetHeight(1)
F.ovScroll:SetScrollChild(F.ovChild)
F.ovLines = {}
BananaLoot_UI.setupF = F
BananaLoot_UI.setupS = S
local OV_LINE_H = 15

local function OvLine(i)
    if not F.ovLines[i] then
        local fs = F.ovChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", F.ovChild, "TOPLEFT", 4, -(i - 1) * OV_LINE_H)
        fs:SetWidth(668)
        fs:SetHeight(OV_LINE_H - 1)
        fs:SetJustifyH("LEFT")
        F.ovLines[i] = fs
    end
    return F.ovLines[i]
end

local function OvName(link, id)
    local _, _, nm = string.find(link or "", "%[(.-)%]")
    return string.lower(nm or ("zz" .. tostring(id)))
end

-- Sortierte Liste { id, link } einer Item-Tabelle (id -> { link = ... })
local function OvSorted(tbl)
    local out = {}
    for id, e in pairs(tbl or {}) do
        local link = (type(e) == "table" and e.link) or BananaLoot:SetupItemLink(id)
        table.insert(out, { id = id, link = link, key = OvName(link, id) })
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function S.BuildOverview()
    BananaLoot.EnsureDB()
    local db = BananaLoot_DB
    local lines = {}
    local function add(t) table.insert(lines, t) end
    local function section(key, n, extraA)
        add("|cffffd100" .. string.format(BananaLoot:L(key), n, extraA) .. "|r")
    end
    local function none() add("   |cff888888" .. BananaLoot:L("SETUP_OV_NONE") .. "|r") end

    -- Hard Reserve
    local hr = OvSorted(db.hardReserves)
    section("SETUP_OV_HR", table.getn(hr))
    if table.getn(hr) == 0 then none() end
    for i = 1, table.getn(hr) do add("   " .. hr[i].link) end

    -- Soft Reserve: je Item die Spieler (SR+ in Klammern)
    local items = {}
    for id, res in pairs(BananaLoot.reservations or {}) do
        if res and res.order and table.getn(res.order) > 0 then
            table.insert(items, { id = id, link = res.link or BananaLoot:SetupItemLink(id), order = res.order, key = OvName(res.link, id) })
        end
    end
    table.sort(items, function(a, b) return a.key < b.key end)
    local players = 0
    for _ in pairs(BananaLoot.playerReservedItems or {}) do players = players + 1 end
    add(" ")
    section("SETUP_OV_SR", table.getn(items), players)
    if table.getn(items) == 0 then none() end
    for i = 1, table.getn(items) do
        local it = items[i]
        local names = ""
        for p = 1, table.getn(it.order) do
            local n = it.order[p]
            local stack = BananaLoot:GetStack(n, it.id)
            names = names .. (p > 1 and ", " or "") .. n
            if stack > 0 then names = names .. "|cffffcc00(+" .. (stack * BananaLoot:GetBonusPerStack()) .. ")|r" end
        end
        add("   " .. it.link .. "  |cff888888-|r  " .. names)
    end

    -- Raid-Roll
    local rr = OvSorted(db.raidRolls)
    add(" ")
    section("SETUP_OV_RR", table.getn(rr))
    if table.getn(rr) == 0 then none() end
    for i = 1, table.getn(rr) do add("   " .. rr[i].link) end

    -- Bankreserve
    local br = OvSorted(db.bankReserves)
    add(" ")
    section("SETUP_OV_BR", table.getn(br))
    if table.getn(br) == 0 then none() end
    for i = 1, table.getn(br) do add("   " .. br[i].link) end

    local n = table.getn(lines)
    for i = 1, n do
        local fs = OvLine(i)
        fs:SetText(lines[i])
        fs:Show()
    end
    for i = n + 1, table.getn(F.ovLines) do F.ovLines[i]:Hide() end
    F.ovChild:SetHeight(math.max(1, n * OV_LINE_H))
    F.ovScroll:UpdateScrollChildRect()
end

function BananaLoot_UI:RefreshSetupOverview()
    if F.srPane:IsShown() then S.BuildOverview() end
end

-- HR-Looter (nur im Schritt "Hard Reserve"): Auswahl aus dem Raid; Hard-Reserve-Items koennen im
-- Loot-Fenster nach einem Klick und einer Abfrage an diese Person vergeben werden.
F.hrlLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.hrlLabel:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 24, 56)
F.hrlName = F:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
F.hrlName:SetPoint("LEFT", F.hrlLabel, "RIGHT", 8, 0)
F.hrlName:SetWidth(150)
F.hrlName:SetJustifyH("LEFT")
F.hrlPick = MakeButton("BananaLootRaidSetupHRLPick", F, 120, 22)
F.hrlPick:SetPoint("LEFT", F.hrlName, "RIGHT", 4, 0)
F.hrlPick:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ShowMemberPicker then
        BananaLoot_UI:ShowMemberPicker({
            title = BananaLoot:L("HRL_PICK_TITLE"),
            hint = BananaLoot:L("HRL_PICK_HINT"),
            includeSelf = true,
            onPick = function(name)
                BananaLoot:SetHRLooter(name)
                S.Refresh()
                if BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end,
        })
    end
end)
F.hrlClear = MakeButton("BananaLootRaidSetupHRLClear", F, 26, 22)
F.hrlClear:SetPoint("LEFT", F.hrlPick, "RIGHT", 4, 0)
F.hrlClear:SetText("X")
F.hrlClear:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetHRLooter(nil)
    S.Refresh()
    if BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
end)
F.hrlClear:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(BananaLoot:L("HRL_CLEAR_TIP"), 1, 1, 1, 1, 1)
    GameTooltip:Show()
end)
F.hrlClear:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Import (raidres.top): importierte HR-Items in die Auswahl uebernehmen
function BananaLoot:OnImportedHardReserves(ids)
    for i = 1, table.getn(ids) do
        local id = ids[i]
        -- offener Setup-Dialog (Raid vorbereiten / laufender Raid)
        S.selHR[id] = true
        S.selRR[id] = nil
        S.selBR[id] = nil
        -- ausgewaehlter vorbereiteter Raid
        local e = self:GetSelectedPreparedRaid()
        if e then
            e.hr = e.hr or {}
            e.hr[id] = true
            if e.rr then e.rr[id] = nil end
            if e.br then e.br[id] = nil end
        end
    end
    if F:IsShown() then S.Refresh() end
end

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
-- Auswahl-Tabelle des aktuellen Reiters (HR/RR/BR) und die beiden anderen.
function S.CurrentSel()
    if S.tab == "RR" then return S.selRR, S.selHR, S.selBR end
    if S.tab == "BR" then return S.selBR, S.selHR, S.selRR end
    return S.selHR, S.selRR, S.selBR
end

-- Ist das Item in diesem Tab gesperrt (steht in der anderen Liste bzw. Bankreserve)?
-- Rueckgabe: Grund-Schluessel oder nil.
function S.Blocked(id)
    -- Ein Item steht in genau einer Liste: wer in einer anderen Auswahl steckt, ist gesperrt.
    if S.tab ~= "BR" and S.selBR[id] then return "SETUP_TAG_BR" end
    if S.tab ~= "HR" and S.selHR[id] then return "SETUP_TAG_HR" end
    if S.tab ~= "RR" and S.selRR[id] then return "SETUP_TAG_RR" end
    return nil
end

-- Qualitaetsfilter: true, wenn das Item angezeigt werden soll.
function S.QualityOK(id)
    local any = false
    for q = 1, 5 do
        if S.qual[q] then any = true end
    end
    if not any then return true end
    local _, quality = BananaLoot:SetupItemInfo(id)
    return S.qual[quality] == true
end

function S.ItemVisible(id)
    if not S.QualityOK(id) then return false end
    if S.search ~= "" then
        local nm = string.lower((BananaLoot:SetupItemInfo(id)))
        if not string.find(nm, S.search, 1, true) then return false end
    end
    return true
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
                if d and S.ItemVisible(id) then
                    table.insert(entries, { kind = "drop", id = id, link = d.link, icon = d.icon })
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
                if S.ItemVisible(id) then
                    table.insert(items, { kind = "item", id = id, boss = b })
                end
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

local function SetRowTexture(r, iconName)
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
                SetRowTexture(r, icon)
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

-- Tabs, die im aktuellen Modus verfuegbar sind (Drops nur im laufenden Raid).
function S.TabCount()
    if S.mode == "prepare" then return 4 end
    return 5
end

function S.Refresh()
    if not F:IsShown() then return end
    local prepare = (S.mode == "prepare")
    if prepare and S.tab == "DROPS" then S.tab = "HR" end
    local key = S.GetKey()
    local raidName = BananaLoot:GetSetupRaidName(key)
    if raidName then
        F.title:SetText(string.format(BananaLoot:L(prepare and "SETUP_TITLE_PREP" or "SETUP_TITLE"), raidName))
    else
        F.title:SetText(BananaLoot:L("SETUP_TITLE_NONE"))
    end
    local tabNames = { "SETUP_TAB_HR", "SETUP_TAB_SR", "SETUP_TAB_RR", "SETUP_TAB_BR", "SETUP_TAB_DROPS" }
    for i = 1, table.getn(TAB_KEYS) do
        local label = BananaLoot:L(tabNames[i])
        if S.tab == TAB_KEYS[i] then label = "|cffffd100" .. label .. "|r" end
        S.tabBtns[i]:SetText(label)
        if i <= S.TabCount() then S.tabBtns[i]:Show() else S.tabBtns[i]:Hide() end
    end
    if prepare then
        F.nameLabel:SetText(BananaLoot:L("SETUP_NAME_LABEL"))
        F.nameLabel:Show()
        F.nameBox:Show()
        if F.nameBox:GetText() ~= S.prepName then
            S.loading = true
            F.nameBox:SetText(S.prepName or "")
            S.loading = false
        end
    else
        F.nameLabel:Hide()
        F.nameBox:Hide()
    end
    F.hint:SetText(BananaLoot:L("SETUP_HINT_" .. S.tab))
    F.searchLabel:SetText(BananaLoot:L("SETUP_SEARCH"))
    F.qualLabel:SetText(BananaLoot:L("SETUP_QUAL_LABEL"))
    for q = 1, 5 do
        local c = QUALITY_HEX[q]
        S.qualBtns[q]:SetText("|cff" .. c .. BananaLoot:L(QUAL_KEYS[q]) .. "|r")
        if S.qual[q] then S.qualBtns[q].sel:Show() else S.qualBtns[q].sel:Hide() end
    end
    F.allBtn:SetText(BananaLoot:L("SETUP_BTN_ALL"))
    F.noneBtn:SetText(BananaLoot:L("SETUP_BTN_NONE"))
    F.backBtn:SetText(BananaLoot:L("SETUP_BTN_BACK"))
    F.nextBtn:SetText(BananaLoot:L("SETUP_BTN_NEXT"))
    F.applyBtn:SetText(BananaLoot:L(prepare and "SETUP_BTN_SAVE" or "SETUP_BTN_APPLY"))
    F.srImportBtn:SetText(BananaLoot:L("SETUP_SR_IMPORT"))
    F.srOpenBtn:SetText(BananaLoot:L("SETUP_SR_OPEN"))

    local isHRTab = (S.tab == "HR")
    if isHRTab then
        F.hrlLabel:SetText(BananaLoot:L("HRL_LABEL"))
        local hl = BananaLoot:GetHRLooter()
        F.hrlName:SetText(hl and BananaLoot:ColoredName(hl) or ("|cff888888" .. BananaLoot:L("HRL_NONE") .. "|r"))
        F.hrlPick:SetText(BananaLoot:L("HRL_PICK"))
        F.hrlLabel:Show(); F.hrlName:Show(); F.hrlPick:Show(); F.hrlClear:Show()
    else
        F.hrlLabel:Hide(); F.hrlName:Hide(); F.hrlPick:Hide(); F.hrlClear:Hide()
    end
    local isSR = (S.tab == "SR")
    local isDrops = (S.tab == "DROPS")
    local isPick = (S.tab == "HR" or S.tab == "RR" or S.tab == "BR")
    if isSR then F.srPane:Show() else F.srPane:Hide() end
    if isSR then
        F.list:Hide(); F.slider:Hide(); F.searchBox:Hide(); F.searchLabel:Hide(); F.countText:Hide(); F.left:Hide()
        F.qualLabel:Hide()
        for q = 1, 5 do S.qualBtns[q]:Hide() end
        F.srText:SetText(BananaLoot:L("SETUP_SR_TEXT"))
        F.srCount:SetText(BananaLoot:L("SETUP_OV_NOTE"))
        S.BuildOverview()
    else
        F.list:Show(); F.slider:Show(); F.searchBox:Show(); F.searchLabel:Show(); F.countText:Show(); F.left:Show()
        F.qualLabel:Show()
        for q = 1, 5 do S.qualBtns[q]:Show() end
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
            F.countText:SetText(string.format(BananaLoot:L("SETUP_COUNT_" .. S.tab), CountSet(sel)))
        else
            F.countText:SetText(string.format(BananaLoot:L("SETUP_COUNT_DROPS"), n))
        end
        if n == 0 and isDrops then
            F.leftHint:SetText(F.leftHint:GetText() .. "\n\n" .. BananaLoot:L("SETUP_DROPS_EMPTY"))
        end
    end
    if isPick then F.allBtn:Show(); F.noneBtn:Show() else F.allBtn:Hide(); F.noneBtn:Hide() end
    if S.tab == "HR" then F.backBtn:Hide() else F.backBtn:Show() end
    if S.tab == TAB_KEYS[S.TabCount()] then F.nextBtn:Hide() else F.nextBtn:Show() end
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
    if idx > S.TabCount() then idx = S.TabCount() end
    S.SetTab(TAB_KEYS[idx])
end

-- Item (de)selektieren; ein Item steht nie in HR UND Raid-Roll.
function S.SetItem(id, on)
    if S.Blocked(id) then return end
    local sel, other1, other2 = S.CurrentSel()
    if on then
        sel[id] = true
        other1[id] = nil
        other2[id] = nil
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
    F.countText:SetText(string.format(BananaLoot:L("SETUP_COUNT_" .. S.tab), CountSet(sel)))
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

local function Trim(str)
    local t = string.gsub(str or "", "^%s*(.-)%s*$", "%1")
    return t
end

-- Prepare: Raid speichern. Live: Auswahl auf die Listen anwenden.
function S.Apply(close)
    local key = S.GetKey()
    if not key then
        if close then F:Hide() end
        return
    end
    if S.mode == "prepare" then
        local name = Trim(S.prepName)
        if name == "" then name = S.DefaultName(key) end
        local entry = BananaLoot:SavePreparedRaid(S.editId, name, key, S.selHR, S.selRR, S.selBR)
        S.editId = entry.id
        BananaLoot:SelectPreparedRaid(entry.id)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SETUP_SAVED"),
            name, BananaLoot:GetSetupRaidName(key), CountSet(entry.hr), CountSet(entry.br), CountSet(entry.rr)))
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        if BananaLoot_UI and BananaLoot_UI.RefreshRaidPicker then BananaLoot_UI:RefreshRaidPicker() end
        F:Hide()
        return
    end
    local nHR, nRR, nBR = BananaLoot:ApplyRaidSetup(key, S.selHR, S.selRR, S.selBR)
    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SETUP_APPLIED"),
        BananaLoot:GetSetupRaidName(key), nHR, nBR, nRR))
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    if close then F:Hide() else S.Refresh() end
end

function S.Open()
    S.loading = true
    F.searchBox:SetText("")
    S.search = ""
    S.loading = false
    S.offset = 0
    S.qual = {}
    F:Show()
    S.Refresh()
end

F:SetScript("OnShow", function() S.Refresh() end)

-- ------------------------------------------------------------
-- 2d) Raid-Verwaltung: vorbereitete Raids auswaehlen / bearbeiten / loeschen
-- ------------------------------------------------------------
local P = { offset = 0, rows = {} }
local PROWS, PROW_H = 8, 36
P.frame = MakeWindow("BananaLootRaidPicker", 780, 440)
local PF = P.frame
PF.hint = PF:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
PF.hint:SetPoint("TOP", PF, "TOP", 0, -38)
PF.hint:SetWidth(720)
PF.empty = PF:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
PF.empty:SetPoint("TOP", PF, "TOP", 0, -120)
PF.empty:SetWidth(460)
PF.more = PF:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
PF.more:SetPoint("BOTTOM", PF, "BOTTOM", 0, 62)

PF.list = CreateFrame("Frame", "BananaLootRaidPickerList", PF)
PF.list:SetWidth(740)
PF.list:SetHeight(PROWS * PROW_H)
PF.list:SetPoint("TOPLEFT", PF, "TOPLEFT", 20, -62)
PF.list:EnableMouseWheel(true)
PF.list:SetScript("OnMouseWheel", function()
    P.offset = P.offset - arg1
    P.Refresh()
end)

for i = 1, PROWS do
    local r = CreateFrame("Button", "BananaLootRaidPickerRow" .. i, PF.list)
    r:SetWidth(740)
    r:SetHeight(PROW_H - 2)
    r:SetPoint("TOPLEFT", PF.list, "TOPLEFT", 0, -(i - 1) * PROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints(r)
    r.sel:SetTexture(1, 0.82, 0, 0.25)
    r.sel:Hide()
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -4)
    r.name:SetWidth(380)
    r.name:SetJustifyH("LEFT")
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -19)
    r.info:SetWidth(380)
    r.info:SetJustifyH("LEFT")
    r.delBtn = MakeButton("BananaLootRaidPickerDel" .. i, r, 70, 20)
    r.delBtn:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.editBtn = MakeButton("BananaLootRaidPickerEdit" .. i, r, 96, 20)
    r.editBtn:SetPoint("RIGHT", r, "RIGHT", -76, 0)
    r.srBtn = MakeButton("BananaLootRaidPickerSR" .. i, r, 88, 20)
    r.srBtn:SetPoint("RIGHT", r, "RIGHT", -176, 0)
    r.codeBtn = MakeButton("BananaLootRaidPickerCode" .. i, r, 106, 20)
    r.codeBtn:SetPoint("RIGHT", r, "RIGHT", -268, 0)
    r.srBtn:SetScript("OnClick", function()
        local row = this:GetParent()
        local e = BananaLoot:GetPreparedRaid(row.raidId)
        if not e then return end
        BananaLoot:PlayClickSound()
        BananaLoot:SetPreparedSROpen(e, e.srOpen == false)
        P.Refresh()
    end)
    r.srBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(BananaLoot:L("SETUP_PICK_SR_TIP"), 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    r.srBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.codeBtn:SetScript("OnClick", function()
        local row = this:GetParent()
        local e = BananaLoot:GetPreparedRaid(row.raidId)
        if not e then return end
        BananaLoot:PlayClickSound()
        BananaLoot:PostRaidCode(e)
    end)
    r.codeBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(BananaLoot:L("SETUP_PICK_CODE_TIP"), 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    r.codeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function()
        if this.raidId then
            BananaLoot:PlayClickSound()
            BananaLoot:SelectPreparedRaid(this.raidId)
            P.Refresh()
            if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        end
    end)
    r.editBtn:SetScript("OnClick", function()
        local row = this:GetParent()
        local e = BananaLoot:GetPreparedRaid(row.raidId)
        if not e then return end
        BananaLoot:PlayClickSound()
        BananaLoot:SelectPreparedRaid(e.id)
        S.PrefetchRaid(e.raidKey)
        S.BeginPrepare(e.raidKey, nil, e)
    end)
    r.delBtn:SetScript("OnClick", function()
        local row = this:GetParent()
        local e = BananaLoot:GetPreparedRaid(row.raidId)
        if not e then return end
        BananaLoot:PlayClickSound()
        P.pendingDelete = e.id
        local d = StaticPopupDialogs["BANANALOOT_DELETE_PREPARED"]
        d.text = string.format(BananaLoot:L("SETUP_DELETE_ASK"), e.name or "?")
        d.button1 = BananaLoot:L("UI_POPUP_YES")
        d.button2 = BananaLoot:L("UI_POPUP_CANCEL")
        StaticPopup_Show("BANANALOOT_DELETE_PREPARED")
    end)
    P.rows[i] = r
end

StaticPopupDialogs["BANANALOOT_DELETE_PREPARED"] = {
    text = "",
    button1 = "",
    button2 = "",
    OnAccept = function()
        if P.pendingDelete then BananaLoot:DeletePreparedRaid(P.pendingDelete) end
        P.pendingDelete = nil
        P.Refresh()
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

PF.newBtn = MakeButton("BananaLootRaidPickerNew", PF, 150, 26)
PF.newBtn:SetPoint("BOTTOMLEFT", PF, "BOTTOMLEFT", 20, 22)
PF.newBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ShowRaidChooser()
end)
PF.startBtn = MakeButton("BananaLootRaidPickerStart", PF, 150, 26)
PF.startBtn:SetPoint("LEFT", PF.newBtn, "RIGHT", 8, 0)
PF.startBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local e = BananaLoot:GetSelectedPreparedRaid()
    if e and BananaLoot_UI:StartPreparedRaid(e.id) then PF:Hide() end
end)
PF.quickBtn = MakeButton("BananaLootRaidPickerQuick", PF, 214, 26)
PF.quickBtn:SetPoint("LEFT", PF.startBtn, "RIGHT", 8, 0)
PF.quickBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI:DoStartRaid(nil) then PF:Hide() end
end)
PF.joinBtn = MakeButton("BananaLootRaidPickerJoin", PF, 110, 26)
PF.joinBtn:SetPoint("LEFT", PF.quickBtn, "RIGHT", 8, 0)
PF.joinBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local d = StaticPopupDialogs["BANANALOOT_JOIN_CODE"]
    d.text = BananaLoot:L("SETUP_JOIN_ASK")
    d.button1 = BananaLoot:L("UI_POPUP_YES")
    d.button2 = BananaLoot:L("UI_POPUP_CANCEL")
    StaticPopup_Show("BANANALOOT_JOIN_CODE")
end)

-- Raid-Code eingeben (Stellvertreter laedt den Raid vom Loot-Master)
StaticPopupDialogs["BANANALOOT_JOIN_CODE"] = {
    text = "",
    button1 = "",
    button2 = "",
    hasEditBox = 1,
    maxLetters = 16,
    OnAccept = function()
        local box = getglobal(this:GetParent():GetName() .. "EditBox")
        if box and BananaLoot.JoinRaidCode then BananaLoot:JoinRaidCode(box:GetText()) end
    end,
    EditBoxOnEnterPressed = function()
        local box = getglobal(this:GetParent():GetName() .. "EditBox")
        if box and BananaLoot.JoinRaidCode then BananaLoot:JoinRaidCode(box:GetText()) end
        this:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function P.Refresh()
    if not PF:IsShown() then return end
    local list = BananaLoot:GetPreparedRaids()
    local n = table.getn(list)
    local maxOff = math.max(0, n - PROWS)
    if P.offset > maxOff then P.offset = maxOff end
    if P.offset < 0 then P.offset = 0 end
    local selId = BananaLoot_DB and BananaLoot_DB.selectedPreparedRaid
    PF.title:SetText(BananaLoot:L("SETUP_PICK_TITLE"))
    PF.hint:SetText(BananaLoot:L("SETUP_PICK_HINT"))
    for i = 1, PROWS do
        local r = P.rows[i]
        local e = list[n - P.offset - i + 1]   -- neueste zuerst
        if e then
            r.raidId = e.id
            r.name:SetText((e.name or "?") .. "  |cff909090[" .. (e.code or "-") .. "]|r")
            if BananaLoot.EnsurePreparedCode then BananaLoot:EnsurePreparedCode(e) end
            local srOpen = BananaLoot.IsSROpenFor and BananaLoot:IsSROpenFor(e)
            r.info:SetText(string.format(BananaLoot:L("SETUP_PICK_ROW"),
                BananaLoot:GetSetupRaidName(e.raidKey) or "?", CountSet(e.hr), CountSet(e.br), CountSet(e.rr),
                BananaLoot.CountPreparedSR and BananaLoot:CountPreparedSR(e) or 0,
                BananaLoot:L(srOpen and "SETUP_STATE_OPEN" or "SETUP_STATE_CLOSED")))
            r.srBtn:SetText(BananaLoot:L(srOpen and "SETUP_PICK_SR_OPEN" or "SETUP_PICK_SR_CLOSED"))
            r.codeBtn:SetText(BananaLoot:L("SETUP_PICK_CODE"))
            r.editBtn:SetText(BananaLoot:L("SETUP_PICK_EDIT"))
            r.delBtn:SetText(BananaLoot:L("SETUP_PICK_DELETE"))
            if e.id == selId then r.sel:Show() else r.sel:Hide() end
            r:Show()
        else
            r.raidId = nil
            r:Hide()
        end
    end
    if n == 0 then PF.empty:SetText(BananaLoot:L("SETUP_PICK_EMPTY")) else PF.empty:SetText("") end
    if n > PROWS then PF.more:SetText(string.format(BananaLoot:L("SETUP_PICK_MORE"), n)) else PF.more:SetText("") end
    PF.newBtn:SetText(BananaLoot:L("SETUP_PICK_NEW"))
    PF.startBtn:SetText(BananaLoot:L("SETUP_PICK_START"))
    PF.quickBtn:SetText(BananaLoot:L("SETUP_PICK_QUICK"))
    PF.joinBtn:SetText(BananaLoot:L("SETUP_PICK_JOIN"))
    local running = BananaLoot:IsRaidRunning()
    if BananaLoot:GetSelectedPreparedRaid() and not running then PF.startBtn:Enable() else PF.startBtn:Disable() end
    if running then PF.quickBtn:Disable() else PF.quickBtn:Enable() end
end
PF:SetScript("OnShow", function() P.Refresh() end)

-- ============================================================
-- 3) OEFFENTLICHE EINSTIEGSPUNKTE
-- ============================================================

-- Raid vorbereiten (Optionen > Neuer Raid): zuerst die Raid-Auswahl.
function BananaLoot_UI:ShowRaidChooser()
    if not BananaLoot_RaidLoot then return end
    S.chooserMode = "prepare"
    S.BuildChooser()
    S.chooser:Show()
end

-- Setup-Fenster (Seitenmenue-Button, /bl setup): im laufenden Raid die Listen
-- des Raids bearbeiten, sonst einen neuen Raid vorbereiten.
function BananaLoot_UI:ShowRaidSetup(tab)
    if not BananaLoot_RaidLoot then return end
    local session = BananaLoot:GetRaidSession()
    if not (session and session.running) then
        BananaLoot_UI:ShowRaidChooser()
        return
    end
    local key = session.raidKey or S.setupKey
    if not key then
        S.chooserMode = "live"
        S.BuildChooser()
        S.chooser:Show()
        return
    end
    S.mode = "live"
    S.LoadFromCurrent(key)
    S.tab = tab or "HR"
    S.bossIdx = 0
    S.Open()
end

-- Liste der vorbereiteten Raids (Hauptfenster-Ueberschrift, Seitenmenue).
function BananaLoot_UI:ShowRaidPicker()
    P.offset = 0
    PF:Show()
    P.Refresh()
end

function BananaLoot_UI:RefreshRaidPicker()
    P.Refresh()
end

-- Startet den im Hauptfenster gewaehlten Raid; ohne Auswahl die Raid-Liste.
function BananaLoot_UI:StartSelectedRaid()
    local e = BananaLoot:GetSelectedPreparedRaid()
    if e then
        BananaLoot_UI:StartPreparedRaid(e.id)
    else
        BananaLoot_UI:ShowRaidPicker()
    end
end

-- Vorbereiteten Raid starten: HR-/Raid-Roll-Listen setzen, Raid starten.
function BananaLoot_UI:StartPreparedRaid(id)
    local e = BananaLoot:GetPreparedRaid(id)
    if not e or BananaLoot:IsRaidRunning() then return false end
    local nHR, nRR, nBR = BananaLoot:ApplyRaidSetup(e.raidKey, e.hr, e.rr, e.br, true)
    if not BananaLoot_UI:DoStartRaid(e.raidKey, e.name, e.id) then return false end
    BananaLoot:SetCurrentRaidName(e.name)
    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SETUP_STARTED"), e.name, nHR, nBR, nRR))
    -- Per Raid-Code eingegangene SR uebernehmen, SR-Liste sperren
    if BananaLoot.CodeOnRaidStart then
        local players = BananaLoot:CodeOnRaidStart(e)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("CODE_START_SR"), players))
    end
    S.PrefetchRaid(e.raidKey)
    if BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    return true
end

function BananaLoot_UI:ApplyLocaleSetup()
    if F:IsShown() then S.Refresh() end
    if S.chooser:IsShown() then S.BuildChooser() end
    if PF:IsShown() then P.Refresh() end
end

-- Die Ueberschrift im Hauptfenster (Raid-Name) ist anklickbar und oeffnet die
-- Liste der vorbereiteten Raids.
local srMain = getglobal("BananaLootSRFrame")
if srMain then
    local headBtn = CreateFrame("Button", "BananaLootSRHeadlineBtn", srMain)
    headBtn:SetWidth(300)
    headBtn:SetHeight(26)
    headBtn:SetPoint("TOP", srMain, "TOP", 0, -58)
    headBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        BananaLoot_UI:ShowRaidPicker()
    end)
    headBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(headBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText(BananaLoot:L("SETUP_SELECT_TIP"), 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    headBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
