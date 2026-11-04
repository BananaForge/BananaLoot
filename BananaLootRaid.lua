-- BananaLootRaid.lua
-- Ausklappbares Menue rechts am SR-Fenster, Raid starten/beenden-Button und
-- Raid-Timer unten im SR-Fenster. Die Logik (Teilnehmer, Dauer, SR+ am Ende)
-- steht in BananaLoot.lua (StartRaid/EndRaid/TickRaid), hier nur Oberflaeche.
--
-- Hinweis: Dieses Menue nimmt einige selten im Raid benoetigte Buttons aus
-- dem Hauptfenster (Export, Import, Optionen, Raid speichern/laden, LFM) auf.
-- Die Buttons selbst bleiben unveraendert (inkl. Klick-Verhalten), sie
-- werden nur umgehaengt und neu angeordnet.

local srFrame = getglobal("BananaLootSRFrame")
if not srFrame then return end

-- Layout des Seitenmenues: einheitliche Buttonhoehe, klare Abstaende, vier
-- Gruppen (Raid / Daten / Sonstiges / Looter) durch Trennlinien getrennt.
local PANEL_W = 180
local BTN_W = PANEL_W - 24
local BTN_H = 26
local PANEL_PAD = 12

-- ============================================================
-- Seitenpanel
-- ============================================================
local panel = CreateFrame("Frame", "BananaLootSRMenuPanel", srFrame)
panel:SetWidth(PANEL_W)
panel:SetHeight(392)
-- Der Fensterrahmen des SR-Fensters liegt optisch einige Pixel innerhalb der
-- Frame-Kante, daher negativer Versatz, damit das Panel buendig anliegt.
panel:SetPoint("TOPLEFT", srFrame, "TOPRIGHT", -5, -60)
panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0, 0, 0, 0.9)
panel:Hide()

-- Umhaengen der bestehenden Buttons ins Panel
local moved = {
    { "BananaLootExportBtn", -62 },
    { "BananaLootImportBtn", -94 },
    { "BananaLootSaveRaidBtn", -126 },
    { "BananaLootLoadRaidBtn", -158 },
    { "BananaLootOptionsBtn", -204 },
    { "BananaLootLFMQuickBtn", -236 },
}
for i = 1, table.getn(moved) do
    local btn = getglobal(moved[i][1])
    if btn then
        btn:SetParent(panel)
        btn:ClearAllPoints()
        btn:SetWidth(BTN_W)
        btn:SetHeight(BTN_H)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, moved[i][2])
    end
end

-- Duenne Trennlinien zwischen den Gruppen
local function AddSeparator(y)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, y)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_PAD, y)
end
AddSeparator(-52)
AddSeparator(-194)
AddSeparator(-274)

-- Hauptfenster neu ordnen: Sperren/ML-GL/Loot-Fenster in eine Zeile, Liste
-- rueckt hoch, unten bleibt Platz fuer den Timer.
local lockBtn = getglobal("BananaLootLockBtn")
if lockBtn then
    lockBtn:ClearAllPoints()
    lockBtn:SetPoint("TOPLEFT", srFrame, "TOPLEFT", 20, -100)
end
local openLootBtn = getglobal("BananaLootOpenLootBtn")
local lootMethodBtn = getglobal("BananaLootLootMethodBtn")
if openLootBtn and lootMethodBtn then
    openLootBtn:ClearAllPoints()
    openLootBtn:SetPoint("LEFT", lootMethodBtn, "RIGHT", 6, 0)
end
local srScroll = getglobal("BananaLootSRScrollFrame")
if srScroll then
    srScroll:SetPoint("TOPLEFT", srFrame, "TOPLEFT", 20, -128)
    srScroll:SetPoint("BOTTOMRIGHT", srFrame, "BOTTOMRIGHT", -34, 44)
end


-- ============================================================
-- Disenchanter / BR-Looter setzen: ein gemeinsames kleines Fenster,
-- Modus "de" bzw. "br" bestimmt Texte und Speicherort.
-- ============================================================
local setMode = nil

local setFrame = CreateFrame("Frame", "BananaLootSetPlayerFrame", UIParent)
setFrame:SetWidth(340)
setFrame:SetHeight(190)
setFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
setFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
setFrame:SetMovable(true)
setFrame:EnableMouse(true)
setFrame:RegisterForDrag("LeftButton")
setFrame:SetScript("OnDragStart", function() setFrame:StartMoving() end)
setFrame:SetScript("OnDragStop", function() setFrame:StopMovingOrSizing() end)
setFrame:SetFrameStrata("DIALOG")
setFrame:Hide()

local setClose = CreateFrame("Button", "BananaLootSetPlayerCloseButton", setFrame, "UIPanelCloseButton")
setClose:SetPoint("TOPRIGHT", setFrame, "TOPRIGHT", -4, -4)
setClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    setFrame:Hide()
end)

local setTitle = setFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
setTitle:SetPoint("TOP", setFrame, "TOP", 0, -16)

local setHint = setFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
setHint:SetPoint("TOP", setFrame, "TOP", 0, -40)
setHint:SetWidth(300)
setHint:SetJustifyH("CENTER")

local setCurrent = setFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
setCurrent:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 26, -84)
setCurrent:SetJustifyH("LEFT")

local setBox = CreateFrame("EditBox", "BananaLootSetPlayerBox", setFrame, "InputBoxTemplate")
setBox:SetWidth(220)
setBox:SetHeight(20)
setBox:SetPoint("TOPLEFT", setFrame, "TOPLEFT", 30, -110)
setBox:SetAutoFocus(false)
setBox:SetMaxLetters(24)
setBox:SetScript("OnEscapePressed", function() setFrame:Hide() end)

local setSaveBtn = CreateFrame("Button", "BananaLootSetPlayerSaveBtn", setFrame, "UIPanelButtonTemplate")
setSaveBtn:SetWidth(100)
setSaveBtn:SetHeight(20)
setSaveBtn:SetPoint("TOPLEFT", setBox, "BOTTOMLEFT", -4, -14)

local setClearBtn = CreateFrame("Button", "BananaLootSetPlayerClearBtn", setFrame, "UIPanelButtonTemplate")
setClearBtn:SetWidth(120)
setClearBtn:SetHeight(20)
setClearBtn:SetPoint("LEFT", setSaveBtn, "RIGHT", 8, 0)

local function GetSetValue()
    if setMode == "de" then return BananaLoot:GetDisenchanter() end
    return BananaLoot:GetBRLooter()
end

local function RefreshSetFrame()
    if not setMode then return end
    local isDE = (setMode == "de")
    setTitle:SetText(BananaLoot:L(isDE and "SETPLAYER_DE_TITLE" or "SETPLAYER_BR_TITLE"))
    setHint:SetText(BananaLoot:L(isDE and "SETPLAYER_DE_HINT" or "SETPLAYER_BR_HINT"))
    local cur = GetSetValue()
    if cur then
        setCurrent:SetText(string.format(BananaLoot:L("SETPLAYER_CURRENT"), BananaLoot:ColoredName(cur)))
    else
        setCurrent:SetText(BananaLoot:L(isDE and "SETPLAYER_DE_NONE" or "SETPLAYER_BR_NONE"))
    end
    setSaveBtn:SetText(BananaLoot:L("SETPLAYER_SAVE"))
    setClearBtn:SetText(BananaLoot:L(isDE and "SETPLAYER_CLEAR_DE" or "SETPLAYER_CLEAR_BR"))
end

local function AfterSetChange()
    RefreshSetFrame()
    if BananaLoot_UI and BananaLoot_UI.RefreshLoot then BananaLoot_UI:RefreshLoot() end
end

local function SaveSetPlayer()
    local _, _, name = string.find(setBox:GetText() or "", "^%s*(.-)%s*$")
    if not name or name == "" then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("SETPLAYER_NEED_NAME"))
        return
    end
    local stored
    if setMode == "de" then
        stored = BananaLoot:SetDisenchanter(name)
    else
        stored = BananaLoot:SetBRLooter(name)
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        BananaLoot:L(setMode == "de" and "SETPLAYER_DE_DONE" or "SETPLAYER_BR_DONE"), stored or name))
    if stored and not BananaLoot:IsNameInGroup(stored) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SETPLAYER_NOT_IN_GROUP"), stored))
    end
    setBox:SetText("")
    setBox:ClearFocus()
    setFrame:Hide()
    AfterSetChange()
end

local function ClearSetPlayer()
    if setMode == "de" then
        BananaLoot:SetDisenchanter(nil)
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("SETPLAYER_DE_CLEARED"))
    else
        BananaLoot:SetBRLooter(nil)
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("SETPLAYER_BR_CLEARED"))
    end
    setBox:SetText("")
    setBox:ClearFocus()
    setFrame:Hide()
    AfterSetChange()
end

setSaveBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    SaveSetPlayer()
end)
setClearBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    ClearSetPlayer()
end)
setBox:SetScript("OnEnterPressed", function() SaveSetPlayer() end)

local function OpenSetFrame(mode)
    setMode = mode
    RefreshSetFrame()
    setBox:SetText(GetSetValue() or "")
    setFrame:Show()
    setBox:SetFocus()
    setBox:HighlightText()
end

-- Buttons im Seitenmenue (unter LFM)
local deBtn = CreateFrame("Button", "BananaLootSetDEBtn", panel, "UIPanelButtonTemplate")
deBtn:SetWidth(BTN_W)
deBtn:SetHeight(BTN_H)
deBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -284)
deBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    OpenSetFrame("de")
end)

local brBtn = CreateFrame("Button", "BananaLootSetBRBtn", panel, "UIPanelButtonTemplate")
brBtn:SetWidth(BTN_W)
brBtn:SetHeight(BTN_H)
brBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -316)
brBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    OpenSetFrame("br")
end)

-- Auto-Masterloot bei Boss-Target (alle Raidbosse) an/aus, Standard: an
local autoMLBtn = CreateFrame("Button", "BananaLootAutoMLMenuBtn", panel, "UIPanelButtonTemplate")
autoMLBtn:SetWidth(BTN_W)
autoMLBtn:SetHeight(BTN_H)
autoMLBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -348)

local function UpdateAutoMLBtn()
    if BananaLoot:GetAutoMasterLootEnabled() then
        autoMLBtn:SetText(BananaLoot:L("RAID_BTN_AUTOML_ON"))
    else
        autoMLBtn:SetText(BananaLoot:L("RAID_BTN_AUTOML_OFF"))
    end
end

autoMLBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetAutoMasterLootEnabled(not BananaLoot:GetAutoMasterLootEnabled())
    UpdateAutoMLBtn()
    if BananaLootAutoMLCheck then BananaLootAutoMLCheck:SetChecked(BananaLoot:GetAutoMasterLootEnabled()) end
end)

local function RefreshSetButtonTexts()
    UpdateAutoMLBtn()
    deBtn:SetText(BananaLoot:L("RAID_BTN_SET_DE"))
    brBtn:SetText(BananaLoot:L("RAID_BTN_SET_BR"))
    RefreshSetFrame()
end

-- ============================================================
-- Raid starten / beenden
-- ============================================================
local raidBtn = CreateFrame("Button", "BananaLootRaidToggleBtn", panel, "UIPanelButtonTemplate")
raidBtn:SetWidth(BTN_W)
raidBtn:SetHeight(32)
raidBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -12)

local timerText = srFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
timerText:SetPoint("BOTTOM", srFrame, "BOTTOM", 0, 18)
timerText:SetText("")

local function RefreshRaidUI()
    RefreshSetButtonTexts()
    if BananaLoot:IsRaidRunning() then
        raidBtn:SetText("|cffff5555" .. BananaLoot:L("RAID_BTN_STOP") .. "|r")
        timerText:SetText("|cff33ff99" .. string.format(BananaLoot:L("RAID_TIMER_TEXT"),
            BananaLoot:FormatDuration(BananaLoot:GetRaidElapsed()),
            BananaLoot:CountRaidAttendees()) .. "|r")
    else
        raidBtn:SetText("|cff33ff99" .. BananaLoot:L("RAID_BTN_START") .. "|r")
        timerText:SetText("")
    end
end

raidBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(raidBtn, "ANCHOR_RIGHT")
    if BananaLoot:IsRaidRunning() then
        GameTooltip:SetText(BananaLoot:L("RAID_BTN_STOP_TOOLTIP"))
    else
        GameTooltip:SetText(BananaLoot:L("RAID_BTN_START_TOOLTIP"))
    end
    GameTooltip:Show()
end)
raidBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Zweistufige Rueckfrage beim Beenden: 1) wirklich beenden? 2) SR+ anheben?
-- Ja/Nein beim zweiten Dialog beenden den Raid in beiden Faellen, nur die
-- SR+-Erhoehung unterscheidet sich. ESC schliesst den zweiten Dialog nicht,
-- damit nicht versehentlich ohne Entscheidung beendet wird.
local function FinishRaid(raise)
    local session = BananaLoot:GetRaidSession()
    local raidKey = session and session.raidKey or nil
    local ok, raised, duration, count = BananaLoot:EndRaid(raise)
    if ok then
        BananaLoot:RaidleadOnRaidEnd(raidKey)
        if raise then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("RAID_ENDED"),
                BananaLoot:FormatDuration(duration), count, raised))
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("RAID_ENDED_NO_RAISE"),
                BananaLoot:FormatDuration(duration), count))
        end
    end
    RefreshRaidUI()
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
end

if StaticPopupDialogs then
    StaticPopupDialogs["BANANALOOT_CONFIRM_END_RAID"] = {
        text = "",
        button1 = "",
        button2 = "",
        OnAccept = function()
            local d = StaticPopupDialogs["BANANALOOT_CONFIRM_RAISE_SRPLUS"]
            d.text = BananaLoot:L("RAID_POPUP_RAISE_TEXT")
            d.button1 = BananaLoot:L("RAID_POPUP_RAISE_YES")
            d.button2 = BananaLoot:L("RAID_POPUP_RAISE_NO")
            StaticPopup_Show("BANANALOOT_CONFIRM_RAISE_SRPLUS", BananaLoot:CountRaidAttendees())
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["BANANALOOT_CONFIRM_RAISE_SRPLUS"] = {
        text = "",
        button1 = "",
        button2 = "",
        OnAccept = function() FinishRaid(true) end,
        OnCancel = function() FinishRaid(false) end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
    }
end

raidBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot:IsRaidRunning() then
        local d = StaticPopupDialogs["BANANALOOT_CONFIRM_END_RAID"]
        d.text = BananaLoot:L("RAID_POPUP_END_TEXT")
        d.button1 = BananaLoot:L("UI_POPUP_YES")
        d.button2 = BananaLoot:L("UI_POPUP_CANCEL")
        StaticPopup_Show("BANANALOOT_CONFIRM_END_RAID")
    else
        local ok, count = BananaLoot:StartRaid()
        if ok then
            BananaLoot:RaidleadOnRaidStart()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("RAID_STARTED"), count))
            if BananaLoot:IsRoundRobinActive() then
                DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("RR_RAID_START_ACTIVE"))
            end
        end
        RefreshRaidUI()
    end
end)

-- ============================================================
-- Aus-/Einklapp-Button am rechten Fensterrand
-- ============================================================
local toggleBtn = CreateFrame("Button", "BananaLootSRMenuToggle", srFrame, "UIPanelButtonTemplate")
toggleBtn:SetWidth(24)
toggleBtn:SetHeight(24)
toggleBtn:SetPoint("TOPRIGHT", srFrame, "TOPRIGHT", -14, -64)

local function SetPanelOpen(open)
    BananaLoot.EnsureDB()
    BananaLoot_DB.settings.srMenuOpen = open and true or false
    if open then
        panel:Show()
        toggleBtn:SetText("<")
    else
        panel:Hide()
        toggleBtn:SetText(">")
    end
end

toggleBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    SetPanelOpen(not panel:IsShown())
end)
toggleBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(toggleBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("RAID_MENU_TOOLTIP"))
    GameTooltip:Show()
end)
toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Zustand (offen/zu) beim Oeffnen des SR-Fensters wiederherstellen
srFrame:SetScript("OnShow", function()
    BananaLoot.EnsureDB()
    SetPanelOpen(BananaLoot_DB.settings.srMenuOpen == true)
    RefreshRaidUI()
end)

-- Timer: Anzeige 1x pro Sekunde aktualisieren (nur wenn sichtbar)
local ticker = CreateFrame("Frame", "BananaLootRaidTicker", UIParent)
ticker.elapsed = 0
ticker:SetScript("OnUpdate", function()
    ticker.elapsed = ticker.elapsed + arg1
    if ticker.elapsed < 1 then return end
    ticker.elapsed = 0
    if srFrame:IsShown() then RefreshRaidUI() end
end)

function BananaLoot_UI:ApplyLocaleRaid()
    RefreshRaidUI()
end

-- Nicht auf BananaLoot_DB zugreifen: beim Laden der Datei sind die
-- SavedVariables noch nicht eingelesen. Zustand setzt der OnShow-Handler.
panel:Hide()
toggleBtn:SetText(">")
