-- BananaLootExtra.lua
-- Minimap-Button, Optionsfenster (u.a. SR+ Bonus pro Stufe einstellbar)
-- sowie Export/Import-Popups, um die aktuelle SR-Liste an eine
-- Vertretung weiterzugeben.


-- ============================================================
-- 1) OPTIONSFENSTER
-- ============================================================
-- Registrierungs-Tabelle für einfache Text-Elemente (Label/Button mit
-- genau einem festen Locale-Key). ApplyLocaleExtra() iteriert am Ende
-- nur über DIESE eine Tabelle statt jedes Element einzeln als eigene
-- Upvalue zu referenzieren - Lua 5.0 (echtes Vanilla-Lua) erlaubt pro
-- Funktion maximal 32 Upvalues, und bei 60+ UI-Elementen in dieser
-- Datei würde eine Funktion, die alle einzeln anspricht, dieses Limit
-- klar überschreiten (führte früher zu einem stillen Ladefehler).
local localeTexts = {}
local function RegisterLocaleText(obj, key)
    table.insert(localeTexts, { obj = obj, key = key })
    obj:SetText(BananaLoot:L(key))
end

local optFrame = CreateFrame("Frame", "BananaLootOptionsFrame", UIParent)
optFrame:SetWidth(400)
optFrame:SetHeight(600)
optFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
optFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
optFrame:SetMovable(true)
optFrame:EnableMouse(true)
optFrame:RegisterForDrag("LeftButton")
optFrame:SetScript("OnDragStart", function() optFrame:StartMoving() end)
optFrame:SetScript("OnDragStop", function() optFrame:StopMovingOrSizing() end)
optFrame:SetFrameStrata("DIALOG")
optFrame:Hide()

-- Logo sitzt zentriert ganz oben im Fenster. Die Quellgrafik ist
-- quadratisch (1:1), die Textur wird deshalb auch quadratisch angelegt
-- (138x138) -- KEIN Breitformat und kein SetTexCoord, sonst wird das
-- Logo gestaucht. Die 138 px entsprechen genau dem Platz, den das
-- frühere Banner belegt hat, darunter beginnt bei -160 die Reiterleiste.
-- WICHTIG: WoW verlangt bei eigenen TGA-UI-Texturen zwingend Zweier-
-- potenz-Dimensionen (16/32/64/128/256/512/...), sonst wird die Datei
-- gar nicht erst geladen/angezeigt. Die Datei ist daher 256x256 gross
-- und wird vom Spiel sauber auf 138x138 herunterskaliert.
local optLogo = optFrame:CreateTexture(nil, "ARTWORK")
optLogo:SetWidth(138)
optLogo:SetHeight(138)
optLogo:SetPoint("TOP", optFrame, "TOP", 0, -8)
optLogo:SetTexture("Interface\\AddOns\\BananaLoot\\Icons\\BananaLoot_Logo_256")

local optCloseBtn = CreateFrame("Button", "BananaLootOptionsCloseButton", optFrame, "UIPanelCloseButton")
optCloseBtn:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT", -4, -4)
optCloseBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

-- Hinweis: der frühere Hilfe-Button ("?", Befehlsübersicht) ist ins
-- SR-Fenster umgezogen (siehe BananaLootUI.lua) -- dort ist er auch
-- waehrend eines laufenden Loot-Vorgangs erreichbar, ohne extra die
-- Optionen oeffnen zu muessen.

-- ============================================================
-- 1a) REITER-LEISTE: gruppiert die Einstellungsliste in fuenf Kategorien
-- (aehnlich den Blizzard-Optionsreitern), damit kein einzelner Reiter
-- ueberladen wird. tabGroups[N] sammelt alle UI-Elemente, die zu Reiter N
-- gehoeren; AddToTab() traegt sie dort ein. ShowOptTab() blendet beim
-- Wechsel alles andere aus und passt zusaetzlich die Fensterhoehe an den
-- jeweiligen Reiter an (siehe OPT_TAB_HEIGHTS), damit ein kurzer Reiter
-- (z.B. "Netzwerk") nicht denselben riesigen leeren Freiraum zeigt wie
-- der laengste. Bewusst OHNE ScrollFrame, da jeder Reiter fuer sich
-- kompakt genug ist.
-- ============================================================
local TAB_GENERAL, TAB_AUTOMATION, TAB_NETWORK, TAB_DISPLAY, TAB_MANAGE = 1, 2, 3, 4, 5
local tabGroups = { {}, {}, {}, {}, {}, {} }
local tabButtons = {}
local optActiveTab = TAB_GENERAL

-- Benoetigte Fensterhoehe je Reiter (Inhalt + Rand), siehe ShowOptTab().
-- Werte wurden anhand der tiefsten Y-Position der jeweils zugeordneten
-- Elemente (siehe AddToTab()-Aufrufe weiter unten) bestimmt.
local OPT_TAB_HEIGHTS = {
    [TAB_GENERAL] = 680,
    [TAB_AUTOMATION] = 700,
    [TAB_NETWORK] = 500,
    [TAB_DISPLAY] = 820,
    [TAB_MANAGE] = 600,
    [6] = 680, -- Statistik (BananaLootStats.lua)
}

-- Nimmt eine explizite Tabelle (Array) statt Varargs entgegen. Vermeidet
-- bewusst "..."/die implizite "arg"-Tabelle: das ist die EINZIGE Stelle im
-- gesamten Addon, die Varargs bräuchte, und ungetestet auf diesem Server-
-- Lua riskanter als die überall sonst bereits bewährte table.getn-Version.
local function AddToTab(tabIndex, list)
    local group = tabGroups[tabIndex]
    for i = 1, table.getn(list) do
        table.insert(group, list[i])
    end
end

local function ShowOptTab(index)
    optActiveTab = index
    for t = 1, 6 do
        local group = tabGroups[t]
        local visible = (t == index)
        for i = 1, table.getn(group) do
            if visible then group[i]:Show() else group[i]:Hide() end
        end
        if tabButtons[t] then
            if visible then tabButtons[t]:Disable() else tabButtons[t]:Enable() end
        end
    end
    -- Fenster passt sich an den jeweils angezeigten Reiter an, damit kurze
    -- Reiter nicht unnoetig viel leeren Platz unten zeigen. Das Fenster ist
    -- ueber CENTER verankert, bleibt beim Groessenwechsel also mittig.
    optFrame:SetHeight(OPT_TAB_HEIGHTS[index] or 600)
    if index == 6 and BananaLoot_UI.RefreshStats then BananaLoot_UI:RefreshStats() end
end

-- Fuer BananaLootStats.lua (Reiter 6): Elemente einem Reiter zuordnen.
BananaLoot_UI.OptAddToTab = AddToTab

local function CreateOptTabButton(index, width)
    local btn = CreateFrame("Button", "BananaLootOptTabBtn" .. index, optFrame, "UIPanelButtonTemplate")
    btn:SetWidth(width)
    btn:SetHeight(22)
    btn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        ShowOptTab(index)
    end)
    tabButtons[index] = btn
    return btn
end

-- Reihe 1 (drei kompakte Reiter): Allgemein / Automatik / Netzwerk
local optTabGeneralBtn = CreateOptTabButton(TAB_GENERAL, 112)
optTabGeneralBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -160)
RegisterLocaleText(optTabGeneralBtn, "OPT_TAB_GENERAL")

local optTabAutomationBtn = CreateOptTabButton(TAB_AUTOMATION, 112)
optTabAutomationBtn:SetPoint("LEFT", optTabGeneralBtn, "RIGHT", 4, 0)
RegisterLocaleText(optTabAutomationBtn, "OPT_TAB_AUTOMATION")

local optTabNetworkBtn = CreateOptTabButton(TAB_NETWORK, 112)
optTabNetworkBtn:SetPoint("LEFT", optTabAutomationBtn, "RIGHT", 4, 0)
RegisterLocaleText(optTabNetworkBtn, "OPT_TAB_NETWORK")

-- Reihe 2 (zwei breitere Reiter, mehr Platz fuer laengere Beschriftung):
-- Anzeige & Sound / Verwaltung
local optTabDisplayBtn = CreateOptTabButton(TAB_DISPLAY, 118)
optTabDisplayBtn:SetPoint("TOPLEFT", optTabGeneralBtn, "BOTTOMLEFT", 0, -4)
RegisterLocaleText(optTabDisplayBtn, "OPT_TAB_DISPLAY")

local optTabManageBtn = CreateOptTabButton(TAB_MANAGE, 118)
optTabManageBtn:SetPoint("LEFT", optTabDisplayBtn, "RIGHT", 4, 0)
RegisterLocaleText(optTabManageBtn, "OPT_TAB_MANAGE")

-- Reiter 6: Statistik (Inhalt in BananaLootStats.lua). Bewusst ohne neue
-- lokale Variablen (Locals-Limit dieser Datei, siehe Hinweis oben).
CreateOptTabButton(6, 118)
tabButtons[6]:SetPoint("LEFT", optTabManageBtn, "RIGHT", 4, 0)
RegisterLocaleText(tabButtons[6], "OPT_TAB_STATS")

local bonusLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bonusLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -228)
RegisterLocaleText(bonusLabel, "OPT_BONUS_LABEL")

local bonusEditBox = CreateFrame("EditBox", "BananaLootBonusEditBox", optFrame, "InputBoxTemplate")
bonusEditBox:SetWidth(60)
bonusEditBox:SetHeight(20)
bonusEditBox:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 26, -252)
bonusEditBox:SetAutoFocus(false)
bonusEditBox:SetNumeric(true)

local bonusSaveBtn = CreateFrame("Button", "BananaLootBonusSaveBtn", optFrame, "UIPanelButtonTemplate")
bonusSaveBtn:SetWidth(80)
bonusSaveBtn:SetHeight(20)
bonusSaveBtn:SetPoint("LEFT", bonusEditBox, "RIGHT", 16, 0)
RegisterLocaleText(bonusSaveBtn, "OPT_SAVE_BTN")
bonusSaveBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local value = tonumber(bonusEditBox:GetText())
    if value and value >= 0 then
        BananaLoot:SetBonusPerStack(value)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("OPT_BONUS_SET"), value))
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_BONUS_INVALID"))
    end
end)

local optHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
optHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -276)
optHint:SetWidth(360)
optHint:SetJustifyH("LEFT")
RegisterLocaleText(optHint, "OPT_BONUS_HINT")

-- Roll-Timeout (Sekunden bis zur automatischen Auswertung)
local timeoutLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
timeoutLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -328)
RegisterLocaleText(timeoutLabel, "OPT_TIMEOUT_LABEL")

local timeoutEditBox = CreateFrame("EditBox", "BananaLootTimeoutEditBox", optFrame, "InputBoxTemplate")
timeoutEditBox:SetWidth(60)
timeoutEditBox:SetHeight(20)
timeoutEditBox:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 26, -352)
timeoutEditBox:SetAutoFocus(false)
timeoutEditBox:SetNumeric(true)

local timeoutSaveBtn = CreateFrame("Button", "BananaLootTimeoutSaveBtn", optFrame, "UIPanelButtonTemplate")
timeoutSaveBtn:SetWidth(80)
timeoutSaveBtn:SetHeight(20)
timeoutSaveBtn:SetPoint("LEFT", timeoutEditBox, "RIGHT", 16, 0)
RegisterLocaleText(timeoutSaveBtn, "OPT_SAVE_BTN")
timeoutSaveBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local value = tonumber(timeoutEditBox:GetText())
    if BananaLoot:SetRollTimeout(value) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("OPT_TIMEOUT_SET"), value))
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_TIMEOUT_INVALID"))
    end
end)

-- Chat-Countdown an/aus
local countdownCheck = CreateFrame("CheckButton", "BananaLootCountdownCheck", optFrame, "UICheckButtonTemplate")
countdownCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -456)
countdownCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = countdownCheck:GetChecked()
    BananaLoot:SetChatCountdownEnabled(checked and true or false)
    if checked then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_COUNTDOWN_ON"))
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_COUNTDOWN_OFF"))
    end
end)

local countdownLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
countdownLabel:SetPoint("LEFT", countdownCheck, "RIGHT", 2, 0)
RegisterLocaleText(countdownLabel, "OPT_COUNTDOWN_LABEL")

local countdownHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
countdownHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -480)
countdownHint:SetWidth(360)
countdownHint:SetJustifyH("LEFT")
RegisterLocaleText(countdownHint, "OPT_COUNTDOWN_HINT")

-- Rückantwort bei unbekanntem Whisper-Befehl an/aus
local unknownReplyCheck = CreateFrame("CheckButton", "BananaLootUnknownReplyCheck", optFrame, "UICheckButtonTemplate")
unknownReplyCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -500)
unknownReplyCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = unknownReplyCheck:GetChecked()
    BananaLoot:SetUnknownCommandReplyEnabled(checked and true or false)
    if checked then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_UNKNOWN_REPLY_ON"))
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_UNKNOWN_REPLY_OFF"))
    end
end)

local unknownReplyLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
unknownReplyLabel:SetPoint("LEFT", unknownReplyCheck, "RIGHT", 2, 0)
RegisterLocaleText(unknownReplyLabel, "OPT_UNKNOWN_REPLY_LABEL")

local unknownReplyHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
unknownReplyHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -524)
unknownReplyHint:SetWidth(360)
unknownReplyHint:SetJustifyH("LEFT")
RegisterLocaleText(unknownReplyHint, "OPT_UNKNOWN_REPLY_HINT")

-- raidres.top-Import: SR+ von raidres.top hat Vorrang vor lokalem SR+
-- (Standard: AUS). Siehe BananaLoot:GetRaidResSRPlusOverride.
-- Hinweis: bewusst KEINE lokalen Variablen (Vanilla-Lua 5.0 erlaubt max. 200
-- Locals pro Funktion; diese Datei ist am Limit). Frames liegen in BananaLoot_UI.
BananaLoot_UI.raidresPlusCheck = CreateFrame("CheckButton", "BananaLootRaidResPlusCheck", optFrame, "UICheckButtonTemplate")
BananaLoot_UI.raidresPlusCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -566)
BananaLoot_UI.raidresPlusCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = BananaLoot_UI.raidresPlusCheck:GetChecked()
    BananaLoot:SetRaidResSRPlusOverride(checked and true or false)
end)

BananaLoot_UI.raidresPlusLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
BananaLoot_UI.raidresPlusLabel:SetPoint("LEFT", BananaLoot_UI.raidresPlusCheck, "RIGHT", 2, 0)
RegisterLocaleText(BananaLoot_UI.raidresPlusLabel, "OPT_RAIDRES_SRPLUS_LABEL")

BananaLoot_UI.raidresPlusHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
BananaLoot_UI.raidresPlusHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -590)
BananaLoot_UI.raidresPlusHint:SetWidth(360)
BananaLoot_UI.raidresPlusHint:SetJustifyH("LEFT")
RegisterLocaleText(BananaLoot_UI.raidresPlusHint, "OPT_RAIDRES_SRPLUS_HINT")

-- Sprache der Chat- und UI-Ausgaben
local languageLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
languageLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -228)
RegisterLocaleText(languageLabel, "OPT_LANGUAGE_LABEL")

-- Die Sprachnamen selbst bleiben immer nativ ("Deutsch"/"English"),
-- damit sie unabhängig von der aktuell eingestellten Sprache erkennbar sind.
local langDeBtn = CreateFrame("Button", "BananaLootLangDeBtn", optFrame, "UIPanelButtonTemplate")
langDeBtn:SetWidth(90)
langDeBtn:SetHeight(20)
langDeBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 26, -252)
langDeBtn:SetText("Deutsch")
langDeBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetLanguage("de")
    DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_LANGUAGE_SET"))
    if BananaLoot_UI and BananaLoot_UI.ApplyLocaleAll then BananaLoot_UI:ApplyLocaleAll() end
end)

local langEnBtn = CreateFrame("Button", "BananaLootLangEnBtn", optFrame, "UIPanelButtonTemplate")
langEnBtn:SetWidth(90)
langEnBtn:SetHeight(20)
langEnBtn:SetPoint("LEFT", langDeBtn, "RIGHT", 10, 0)
langEnBtn:SetText("English")
langEnBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetLanguage("en")
    DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_LANGUAGE_SET"))
    if BananaLoot_UI and BananaLoot_UI.ApplyLocaleAll then BananaLoot_UI:ApplyLocaleAll() end
end)

-- ============================================================
-- 1a-S) SOUND-FEEDBACK: optionale Sounds bei Events + Button-Klicks.
-- Ein Hauptschalter, darunter vier einzelne Schalter für die Event-
-- Sounds (Loot/Roll/Gewinner/Award) sowie ein eigener globaler Schalter
-- für den Klick-Sound auf allen UI-Buttons. Alle Standard: an.
-- ============================================================
local soundSectionLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
soundSectionLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -524)
RegisterLocaleText(soundSectionLabel, "OPT_SOUND_LABEL")

local soundEnabledCheck = CreateFrame("CheckButton", "BananaLootSoundEnabledCheck", optFrame, "UICheckButtonTemplate")
soundEnabledCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -548)
soundEnabledCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetSoundEnabled(soundEnabledCheck:GetChecked() and true or false)
end)

local soundEnabledLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
soundEnabledLabel:SetPoint("LEFT", soundEnabledCheck, "RIGHT", 2, 0)
RegisterLocaleText(soundEnabledLabel, "OPT_SOUND_MASTER_LABEL")

local soundLootCheck = CreateFrame("CheckButton", "BananaLootSoundLootCheck", optFrame, "UICheckButtonTemplate")
soundLootCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 30, -570)
soundLootCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetSoundLootDetectedEnabled(soundLootCheck:GetChecked() and true or false)
end)
local soundLootLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
soundLootLabel:SetPoint("LEFT", soundLootCheck, "RIGHT", 2, 0)
RegisterLocaleText(soundLootLabel, "OPT_SOUND_LOOT_LABEL")

local soundRollCheck = CreateFrame("CheckButton", "BananaLootSoundRollCheck", optFrame, "UICheckButtonTemplate")
soundRollCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 30, -590)
soundRollCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetSoundRollStartedEnabled(soundRollCheck:GetChecked() and true or false)
end)
local soundRollLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
soundRollLabel:SetPoint("LEFT", soundRollCheck, "RIGHT", 2, 0)
RegisterLocaleText(soundRollLabel, "OPT_SOUND_ROLL_LABEL")

local soundWinnerCheck = CreateFrame("CheckButton", "BananaLootSoundWinnerCheck", optFrame, "UICheckButtonTemplate")
soundWinnerCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 30, -610)
soundWinnerCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetSoundWinnerEnabled(soundWinnerCheck:GetChecked() and true or false)
end)
local soundWinnerLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
soundWinnerLabel:SetPoint("LEFT", soundWinnerCheck, "RIGHT", 2, 0)
RegisterLocaleText(soundWinnerLabel, "OPT_SOUND_WINNER_LABEL")

local soundAwardCheck = CreateFrame("CheckButton", "BananaLootSoundAwardCheck", optFrame, "UICheckButtonTemplate")
soundAwardCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 30, -630)
soundAwardCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetSoundAwardEnabled(soundAwardCheck:GetChecked() and true or false)
end)
local soundAwardLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
soundAwardLabel:SetPoint("LEFT", soundAwardCheck, "RIGHT", 2, 0)
RegisterLocaleText(soundAwardLabel, "OPT_SOUND_AWARD_LABEL")

local soundClickCheck = CreateFrame("CheckButton", "BananaLootSoundClickCheck", optFrame, "UICheckButtonTemplate")
soundClickCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -654)
soundClickCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetSoundButtonClicksEnabled(soundClickCheck:GetChecked() and true or false)
end)
local soundClickLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
soundClickLabel:SetPoint("LEFT", soundClickCheck, "RIGHT", 2, 0)
RegisterLocaleText(soundClickLabel, "OPT_SOUND_CLICK_LABEL")

-- Loot-Vorschau im Raid-/Gruppenchat: postet beim Öffnen eines neuen
-- Loot-Fensters (nicht bei wiederholtem Öffnen desselben Fensters,
-- siehe BananaLoot:OnLootOpened) eine Item-für-Item-Übersicht, bevor
-- irgendein Roll gestartet wird. Standard: an.
local lootPreviewCheck = CreateFrame("CheckButton", "BananaLootLootPreviewCheck", optFrame, "UICheckButtonTemplate")
lootPreviewCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -380)
lootPreviewCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = lootPreviewCheck:GetChecked()
    BananaLoot:SetLootPreviewEnabled(checked and true or false)
    if checked then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_LOOTPREVIEW_ON"))
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_LOOTPREVIEW_OFF"))
    end
end)
local lootPreviewLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lootPreviewLabel:SetPoint("LEFT", lootPreviewCheck, "RIGHT", 2, 0)
RegisterLocaleText(lootPreviewLabel, "OPT_LOOTPREVIEW_LABEL")

local lootPreviewHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lootPreviewHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -404)
lootPreviewHint:SetWidth(360)
lootPreviewHint:SetJustifyH("LEFT")
RegisterLocaleText(lootPreviewHint, "OPT_LOOTPREVIEW_HINT")

-- ============================================================
-- 1a) VERWALTUNG: Neuer Raid, SR+ leeren, CSV-Export, Log leeren.
-- Hierher aus dem Hauptfenster verschoben, um es aufzuräumen - diese
-- Aktionen werden selten benötigt (meist nur vor/nach dem Raid).
-- ============================================================
local manageSectionLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
manageSectionLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -228)
RegisterLocaleText(manageSectionLabel, "OPT_MANAGE_LABEL")

local optResetBtn = CreateFrame("Button", "BananaLootOptResetBtn", optFrame, "UIPanelButtonTemplate")
optResetBtn:SetWidth(120)
optResetBtn:SetHeight(20)
optResetBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -252)
RegisterLocaleText(optResetBtn, "UI_BTN_NEW_RAID")
optResetBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if StaticPopup_Show then
        StaticPopup_Show("BANANALOOT_CONFIRM_RESET")
    else
        BananaLoot:ClearAllReservations()
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    end
end)

local optWipeBtn = CreateFrame("Button", "BananaLootOptWipeBtn", optFrame, "UIPanelButtonTemplate")
optWipeBtn:SetWidth(140)
optWipeBtn:SetHeight(20)
optWipeBtn:SetPoint("LEFT", optResetBtn, "RIGHT", 6, 0)
RegisterLocaleText(optWipeBtn, "UI_BTN_WIPE")
optWipeBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if StaticPopup_Show then
        StaticPopup_Show("BANANALOOT_CONFIRM_WIPE")
    else
        BananaLoot.EnsureDB()
        BananaLoot_DB.players = {}
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("CMD_WIPE_DONE"))
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    end
end)

local optCsvBtn = CreateFrame("Button", "BananaLootOptCsvBtn", optFrame, "UIPanelButtonTemplate")
optCsvBtn:SetWidth(120)
optCsvBtn:SetHeight(20)
optCsvBtn:SetPoint("TOPLEFT", optResetBtn, "BOTTOMLEFT", 0, -6)
RegisterLocaleText(optCsvBtn, "UI_BTN_CSV_SR")
optCsvBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ShowCSVReservations()
end)

local optCsvLogBtn = CreateFrame("Button", "BananaLootOptCsvLogBtn", optFrame, "UIPanelButtonTemplate")
optCsvLogBtn:SetWidth(140)
optCsvLogBtn:SetHeight(20)
optCsvLogBtn:SetPoint("LEFT", optCsvBtn, "RIGHT", 6, 0)
RegisterLocaleText(optCsvLogBtn, "UI_BTN_CSV_LOG")
optCsvLogBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ShowCSVLog()
end)

local optClearLogBtn = CreateFrame("Button", "BananaLootOptClearLogBtn", optFrame, "UIPanelButtonTemplate")
optClearLogBtn:SetWidth(120)
optClearLogBtn:SetHeight(20)
optClearLogBtn:SetPoint("TOPLEFT", optCsvBtn, "BOTTOMLEFT", 0, -6)
RegisterLocaleText(optClearLogBtn, "UI_BTN_CLEAR_LOG")
optClearLogBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:ClearLog()
    DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("CMD_LOG_CLEARED"))
end)

local optAliasBtn = CreateFrame("Button", "BananaLootOptAliasBtn", optFrame, "UIPanelButtonTemplate")
optAliasBtn:SetWidth(140)
optAliasBtn:SetHeight(20)
optAliasBtn:SetPoint("LEFT", optClearLogBtn, "RIGHT", 6, 0)
RegisterLocaleText(optAliasBtn, "UI_BTN_ALIAS_MANAGE")
optAliasBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI and BananaLoot_UI.ShowAliasManager then BananaLoot_UI:ShowAliasManager() end
end)

-- ============================================================
-- 1b) ANZEIGE: getrennte Skalierung für SR-Fenster und Loot-Fenster
-- (z.B. für kleine Displays) -- zwei unabhängige Werte, da beide
-- Fenster unterschiedlich oft/groß genutzt werden.
-- ============================================================
local scaleLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
scaleLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -300)
RegisterLocaleText(scaleLabel, "OPT_SCALE_LABEL")

local scaleEditBox = CreateFrame("EditBox", "BananaLootScaleEditBox", optFrame, "InputBoxTemplate")
scaleEditBox:SetWidth(60)
scaleEditBox:SetHeight(20)
scaleEditBox:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 26, -324)
scaleEditBox:SetAutoFocus(false)
scaleEditBox:SetNumeric(true)

local scaleSaveBtn = CreateFrame("Button", "BananaLootScaleSaveBtn", optFrame, "UIPanelButtonTemplate")
scaleSaveBtn:SetWidth(80)
scaleSaveBtn:SetHeight(20)
scaleSaveBtn:SetPoint("LEFT", scaleEditBox, "RIGHT", 16, 0)
RegisterLocaleText(scaleSaveBtn, "OPT_SAVE_BTN")
scaleSaveBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local value = tonumber(scaleEditBox:GetText())
    if BananaLoot:SetUIScalePercent(value) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("OPT_SCALE_SET"), value))
        if BananaLoot_UI and BananaLoot_UI.ApplyScale then BananaLoot_UI:ApplyScale() end
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_SCALE_INVALID"))
    end
end)

local scaleHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
scaleHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -348)
scaleHint:SetWidth(360)
scaleHint:SetJustifyH("LEFT")
RegisterLocaleText(scaleHint, "OPT_SCALE_HINT")

-- Separate Skalierung nur für das Loot-Fenster (unabhängig von der
-- SR-Fenster-Skalierung oben).
local lootScaleLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lootScaleLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -412)
RegisterLocaleText(lootScaleLabel, "OPT_LOOT_SCALE_LABEL")

local lootScaleEditBox = CreateFrame("EditBox", "BananaLootLootScaleEditBox", optFrame, "InputBoxTemplate")
lootScaleEditBox:SetWidth(60)
lootScaleEditBox:SetHeight(20)
lootScaleEditBox:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 26, -436)
lootScaleEditBox:SetAutoFocus(false)
lootScaleEditBox:SetNumeric(true)

local lootScaleSaveBtn = CreateFrame("Button", "BananaLootLootScaleSaveBtn", optFrame, "UIPanelButtonTemplate")
lootScaleSaveBtn:SetWidth(80)
lootScaleSaveBtn:SetHeight(20)
lootScaleSaveBtn:SetPoint("LEFT", lootScaleEditBox, "RIGHT", 16, 0)
RegisterLocaleText(lootScaleSaveBtn, "OPT_SAVE_BTN")
lootScaleSaveBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local value = tonumber(lootScaleEditBox:GetText())
    if BananaLoot:SetLootUIScalePercent(value) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("OPT_LOOT_SCALE_SET"), value))
        if BananaLoot_UI and BananaLoot_UI.ApplyScale then BananaLoot_UI:ApplyScale() end
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_LOOT_SCALE_INVALID"))
    end
end)

local lootScaleHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lootScaleHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -460)
lootScaleHint:SetWidth(360)
lootScaleHint:SetJustifyH("LEFT")
RegisterLocaleText(lootScaleHint, "OPT_LOOT_SCALE_HINT")

-- ============================================================
-- 1c) MEHRFACH-SR: maximale Anzahl gleichzeitiger Reservierungen pro
-- Spieler (Standard: 1, Bereich 1-4). Siehe BananaLoot:GetMaxSRCount.
-- ============================================================
local maxSRLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
maxSRLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -400)
RegisterLocaleText(maxSRLabel, "OPT_MAXSR_LABEL")

local maxSREditBox = CreateFrame("EditBox", "BananaLootMaxSREditBox", optFrame, "InputBoxTemplate")
maxSREditBox:SetWidth(60)
maxSREditBox:SetHeight(20)
maxSREditBox:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 26, -424)
maxSREditBox:SetAutoFocus(false)
maxSREditBox:SetNumeric(true)

local maxSRSaveBtn = CreateFrame("Button", "BananaLootMaxSRSaveBtn", optFrame, "UIPanelButtonTemplate")
maxSRSaveBtn:SetWidth(80)
maxSRSaveBtn:SetHeight(20)
maxSRSaveBtn:SetPoint("LEFT", maxSREditBox, "RIGHT", 16, 0)
RegisterLocaleText(maxSRSaveBtn, "OPT_SAVE_BTN")
maxSRSaveBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local value = tonumber(maxSREditBox:GetText())
    if BananaLoot:SetMaxSRCount(value) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("OPT_MAXSR_SET"), value))
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("OPT_MAXSR_INVALID"))
    end
end)

local maxSRHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
maxSRHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -448)
maxSRHint:SetWidth(360)
maxSRHint:SetJustifyH("LEFT")
RegisterLocaleText(maxSRHint, "OPT_MAXSR_HINT")

-- Automatisches Master Loot beim Anvisieren eines bekannten Raid-Bosses
-- (Standard: an). Siehe BananaLoot:GetAutoMasterLootEnabled/TryAutoMasterLoot.
local autoMLCheck = CreateFrame("CheckButton", "BananaLootAutoMLCheck", optFrame, "UICheckButtonTemplate")
autoMLCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -228)
autoMLCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = autoMLCheck:GetChecked()
    BananaLoot:SetAutoMasterLootEnabled(checked and true or false)
end)

local autoMLLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
autoMLLabel:SetPoint("LEFT", autoMLCheck, "RIGHT", 2, 0)
RegisterLocaleText(autoMLLabel, "OPT_AUTOML_LABEL")

local autoMLHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
autoMLHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -252)
autoMLHint:SetWidth(360)
autoMLHint:SetJustifyH("LEFT")
RegisterLocaleText(autoMLHint, "OPT_AUTOML_HINT")

-- Roll-Sync mit anderen BananaLoot-Nutzern (AddonMessage-Broadcast).
-- Standard: AUS. Siehe BananaLoot:GetRollSyncEnabled / HandleRollSyncMessage.
local rollSyncCheck = CreateFrame("CheckButton", "BananaLootRollSyncCheck", optFrame, "UICheckButtonTemplate")
rollSyncCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -228)
rollSyncCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = rollSyncCheck:GetChecked()
    BananaLoot:SetRollSyncEnabled(checked and true or false)
end)

local rollSyncLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rollSyncLabel:SetPoint("LEFT", rollSyncCheck, "RIGHT", 2, 0)
RegisterLocaleText(rollSyncLabel, "OPT_ROLLSYNC_LABEL")

local rollSyncHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
rollSyncHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -252)
rollSyncHint:SetWidth(360)
rollSyncHint:SetJustifyH("LEFT")
RegisterLocaleText(rollSyncHint, "OPT_ROLLSYNC_HINT")

local rollSyncSenderCheck = CreateFrame("CheckButton", "BananaLootRollSyncSenderCheck", optFrame, "UICheckButtonTemplate")
rollSyncSenderCheck:SetPoint("TOPLEFT", rollSyncHint, "BOTTOMLEFT", 10, -6)
rollSyncSenderCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = rollSyncSenderCheck:GetChecked()
    BananaLoot:SetRollSyncShowForSender(checked and true or false)
end)

local rollSyncSenderLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rollSyncSenderLabel:SetPoint("LEFT", rollSyncSenderCheck, "RIGHT", 2, 0)
RegisterLocaleText(rollSyncSenderLabel, "OPT_ROLLSYNC_SENDER_LABEL")

-- "Top N gewinnen" bei Mehrfachdrops (mehrere Kopien desselben Items im
-- Loot-Fenster). Standard: AUS. Siehe BananaLoot:GetMultiWinnerEnabled.
local multiWinnerCheck = CreateFrame("CheckButton", "BananaLootMultiWinnerCheck", optFrame, "UICheckButtonTemplate")
multiWinnerCheck:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 18, -304)
multiWinnerCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = multiWinnerCheck:GetChecked()
    BananaLoot:SetMultiWinnerEnabled(checked and true or false)
end)

local multiWinnerLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
multiWinnerLabel:SetPoint("LEFT", multiWinnerCheck, "RIGHT", 2, 0)
RegisterLocaleText(multiWinnerLabel, "OPT_MULTIWINNER_LABEL")

local multiWinnerHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
multiWinnerHint:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -328)
multiWinnerHint:SetWidth(360)
multiWinnerHint:SetJustifyH("LEFT")
RegisterLocaleText(multiWinnerHint, "OPT_MULTIWINNER_HINT")

-- Trade-Tracking (automatisch, siehe BananaLoot:GetTradeTrackingEnabled).
local tradeTrackingCheck = CreateFrame("CheckButton", "BananaLootTradeTrackingCheck", optFrame, "UICheckButtonTemplate")
tradeTrackingCheck:SetPoint("TOPLEFT", rollSyncSenderCheck, "BOTTOMLEFT", -12, -10)
tradeTrackingCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = tradeTrackingCheck:GetChecked()
    BananaLoot:SetTradeTrackingEnabled(checked and true or false)
end)

local tradeTrackingLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tradeTrackingLabel:SetPoint("LEFT", tradeTrackingCheck, "RIGHT", 2, 0)
RegisterLocaleText(tradeTrackingLabel, "OPT_TRADETRACKING_LABEL")

local tradeTrackingHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tradeTrackingHint:SetPoint("TOPLEFT", tradeTrackingCheck, "BOTTOMLEFT", 2, 0)
tradeTrackingHint:SetWidth(360)
tradeTrackingHint:SetJustifyH("LEFT")
RegisterLocaleText(tradeTrackingHint, "OPT_TRADETRACKING_HINT")

-- SR+-Wiederherstellung: zeigt das zuletzt durch eine neue Reservierung
-- verdrängte Item je Spieler zum manuellen Zurückholen (siehe Extra 2e).
local recoveryBtn = CreateFrame("Button", "BananaLootRecoveryBtn", optFrame, "UIPanelButtonTemplate")
recoveryBtn:SetWidth(160)
recoveryBtn:SetHeight(20)
recoveryBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -338)
RegisterLocaleText(recoveryBtn, "UI_BTN_RECOVERY")
recoveryBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI and BananaLoot_UI.ShowRecoveryList then BananaLoot_UI:ShowRecoveryList() end
end)
recoveryBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(recoveryBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_RECOVERY_TOOLTIP"))
    GameTooltip:Show()
end)
recoveryBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Testlauf (Loot-Simulation, siehe BananaLootTest.lua). Bewusst OHNE
-- eigene lokale Variable: diese Datei liegt nah am Lua-5.1-Limit von 200
-- Locals pro Chunk, die Referenz haengt daher an BananaLoot_UI.
BananaLoot_UI.optTestBtn = CreateFrame("Button", "BananaLootTestRunBtn", optFrame, "UIPanelButtonTemplate")
BananaLoot_UI.optTestBtn:SetWidth(160)
BananaLoot_UI.optTestBtn:SetHeight(20)
BananaLoot_UI.optTestBtn:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -372)
RegisterLocaleText(BananaLoot_UI.optTestBtn, "UI_BTN_TEST_RUN")
BananaLoot_UI.optTestBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.StartTest then BananaLoot_UI:StartTest() end
end)
BananaLoot_UI.optTestBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(BananaLoot_UI.optTestBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_TEST_TOOLTIP"), 1, 1, 1, 1, 1)
    GameTooltip:Show()
end)
BananaLoot_UI.optTestBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Raidlead-Fenster oeffnen (siehe BananaLootRaidlead.lua). Ohne lokale Variable.
BananaLoot_UI.optRaidleadBtn = CreateFrame("Button", "BananaLootRaidleadOpenBtn", optFrame, "UIPanelButtonTemplate")
BananaLoot_UI.optRaidleadBtn:SetWidth(160)
BananaLoot_UI.optRaidleadBtn:SetHeight(20)
BananaLoot_UI.optRaidleadBtn:SetPoint("TOPLEFT", BananaLoot_UI.optTestBtn, "BOTTOMLEFT", 0, -6)
RegisterLocaleText(BananaLoot_UI.optRaidleadBtn, "UI_BTN_RAIDLEAD")
BananaLoot_UI.optRaidleadBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ShowRaidlead then BananaLoot_UI:ShowRaidlead() end
end)
BananaLoot_UI.optRaidleadBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(BananaLoot_UI.optRaidleadBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_RAIDLEAD_TOOLTIP"), 1, 1, 1, 1, 1)
    GameTooltip:Show()
end)
BananaLoot_UI.optRaidleadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Hauptschalter fuer das GESAMTE Raidlead-Feature (Standard: aus). Aus =
-- keine Ansagen, kein Fenster, keine Reaktion auf Ziel/Raidstart/Raidende.
BananaLoot_UI.rlEnableCheck = CreateFrame("CheckButton", "BananaLootRaidleadEnableCheck", optFrame, "UICheckButtonTemplate")
BananaLoot_UI.rlEnableCheck:SetPoint("TOPLEFT", BananaLoot_UI.optRaidleadBtn, "BOTTOMLEFT", -2, -8)
BananaLoot_UI.rlEnableCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = BananaLoot_UI.rlEnableCheck:GetChecked() and true or false
    BananaLoot:SetRaidleadEnabled(checked)
    if checked then BananaLoot_UI.optRaidleadBtn:Enable() else BananaLoot_UI.optRaidleadBtn:Disable() end
end)
BananaLoot_UI.rlEnableLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
BananaLoot_UI.rlEnableLabel:SetPoint("LEFT", BananaLoot_UI.rlEnableCheck, "RIGHT", 2, 0)
RegisterLocaleText(BananaLoot_UI.rlEnableLabel, "OPT_RL_ENABLE_LABEL")
BananaLoot_UI.rlEnableHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
BananaLoot_UI.rlEnableHint:SetPoint("TOPLEFT", BananaLoot_UI.rlEnableCheck, "BOTTOMLEFT", 2, 0)
BananaLoot_UI.rlEnableHint:SetWidth(360)
BananaLoot_UI.rlEnableHint:SetJustifyH("LEFT")
RegisterLocaleText(BananaLoot_UI.rlEnableHint, "OPT_RL_ENABLE_HINT")

-- Optionaler Test-Raid UBRS (Standard: aus). Unabhaengig vom Raidlead-Schalter:
-- gilt auch fuer den Auto-Masterloot.
BananaLoot_UI.ubrsCheck = CreateFrame("CheckButton", "BananaLootUBRSCheck", optFrame, "UICheckButtonTemplate")
BananaLoot_UI.ubrsCheck:SetPoint("TOPLEFT", BananaLoot_UI.rlEnableHint, "BOTTOMLEFT", -2, -34)
BananaLoot_UI.ubrsCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:SetOptionalRaidEnabled("UBRS", BananaLoot_UI.ubrsCheck:GetChecked() and true or false)
end)
BananaLoot_UI.ubrsLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
BananaLoot_UI.ubrsLabel:SetPoint("LEFT", BananaLoot_UI.ubrsCheck, "RIGHT", 2, 0)
RegisterLocaleText(BananaLoot_UI.ubrsLabel, "OPT_UBRS_LABEL")
BananaLoot_UI.ubrsHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
BananaLoot_UI.ubrsHint:SetPoint("TOPLEFT", BananaLoot_UI.ubrsCheck, "BOTTOMLEFT", 2, 0)
BananaLoot_UI.ubrsHint:SetWidth(360)
BananaLoot_UI.ubrsHint:SetJustifyH("LEFT")
RegisterLocaleText(BananaLoot_UI.ubrsHint, "OPT_UBRS_HINT")

-- ============================================================
-- 1d) REITER-ZUORDNUNG: jedes Element genau einem Reiter zuordnen.
-- Muss NACH der Erzeugung aller obigen Elemente stehen.
-- Tab 1 = Allgemein (Raid-Mechanik-Grundwerte), Tab 2 = Automatik
-- (automatisches Verhalten beim Looten), Tab 3 = Netzwerk (Addon-
-- Message-Features zwischen BananaLoot-Nutzern), Tab 4 = Anzeige & Sound,
-- Tab 5 = Verwaltung.
-- ============================================================
AddToTab(TAB_GENERAL, {
    bonusLabel, bonusEditBox, bonusSaveBtn, optHint,
    timeoutLabel, timeoutEditBox, timeoutSaveBtn,
    maxSRLabel, maxSREditBox, maxSRSaveBtn, maxSRHint,
    unknownReplyCheck, unknownReplyLabel, unknownReplyHint,
    BananaLoot_UI.raidresPlusCheck, BananaLoot_UI.raidresPlusLabel, BananaLoot_UI.raidresPlusHint })

-- Round Robin fuer Main-Spec (siehe BananaLoot:IsRoundRobinActive). Ohne neue
-- lokale Variablen (Locals-Limit dieser Datei), Elemente in BananaLoot_UI.
BananaLoot_UI.rrCheck = CreateFrame("CheckButton", "BananaLootRRCheck", optFrame, "UICheckButtonTemplate")
BananaLoot_UI.rrCheck:SetPoint("TOPLEFT", countdownHint, "BOTTOMLEFT", -2, -10)
BananaLoot_UI.rrCheck:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local checked = BananaLoot_UI.rrCheck:GetChecked()
    BananaLoot:SetRoundRobinEnabled(checked and true or false)
end)

BananaLoot_UI.rrLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
BananaLoot_UI.rrLabel:SetPoint("LEFT", BananaLoot_UI.rrCheck, "RIGHT", 2, 0)
RegisterLocaleText(BananaLoot_UI.rrLabel, "OPT_RR_LABEL")

BananaLoot_UI.rrHint = optFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
BananaLoot_UI.rrHint:SetPoint("TOPLEFT", BananaLoot_UI.rrCheck, "BOTTOMLEFT", 2, 0)
BananaLoot_UI.rrHint:SetWidth(360)
BananaLoot_UI.rrHint:SetJustifyH("LEFT")
RegisterLocaleText(BananaLoot_UI.rrHint, "OPT_RR_HINT")

AddToTab(TAB_AUTOMATION, {
    autoMLCheck, autoMLLabel, autoMLHint,
    BananaLoot_UI.rrCheck, BananaLoot_UI.rrLabel, BananaLoot_UI.rrHint,
    multiWinnerCheck, multiWinnerLabel, multiWinnerHint,
    lootPreviewCheck, lootPreviewLabel, lootPreviewHint,
    countdownCheck, countdownLabel, countdownHint })

AddToTab(TAB_NETWORK, {
    rollSyncCheck, rollSyncLabel, rollSyncHint,
    rollSyncSenderCheck, rollSyncSenderLabel,
    tradeTrackingCheck, tradeTrackingLabel, tradeTrackingHint })

AddToTab(TAB_DISPLAY, {
    languageLabel, langDeBtn, langEnBtn,
    scaleLabel, scaleEditBox, scaleSaveBtn, scaleHint,
    lootScaleLabel, lootScaleEditBox, lootScaleSaveBtn, lootScaleHint,
    soundSectionLabel, soundEnabledCheck, soundEnabledLabel,
    soundLootCheck, soundLootLabel, soundRollCheck, soundRollLabel,
    soundWinnerCheck, soundWinnerLabel, soundAwardCheck, soundAwardLabel,
    soundClickCheck, soundClickLabel })

AddToTab(TAB_MANAGE, {
    manageSectionLabel, optResetBtn, optWipeBtn, optCsvBtn, optCsvLogBtn,
    optClearLogBtn, optAliasBtn, recoveryBtn, BananaLoot_UI.optTestBtn, BananaLoot_UI.optRaidleadBtn,
    BananaLoot_UI.rlEnableCheck, BananaLoot_UI.rlEnableLabel, BananaLoot_UI.rlEnableHint,
    BananaLoot_UI.ubrsCheck, BananaLoot_UI.ubrsLabel, BananaLoot_UI.ubrsHint })


function BananaLoot_UI:ToggleOptions()
    if optFrame:IsShown() then
        optFrame:Hide()
    else
        BananaLoot.EnsureDB()
        bonusEditBox:SetText(tostring(BananaLoot:GetBonusPerStack()))
        timeoutEditBox:SetText(tostring(BananaLoot:GetRollTimeout()))
        countdownCheck:SetChecked(BananaLoot:GetChatCountdownEnabled())
        unknownReplyCheck:SetChecked(BananaLoot:GetUnknownCommandReplyEnabled())
        BananaLoot_UI.raidresPlusCheck:SetChecked(BananaLoot:GetRaidResSRPlusOverride())
        BananaLoot_UI.rrCheck:SetChecked(BananaLoot:GetRoundRobinEnabled())
        BananaLoot_UI.rlEnableCheck:SetChecked(BananaLoot:GetRaidleadEnabled())
        BananaLoot_UI.ubrsCheck:SetChecked(BananaLoot:GetOptionalRaidEnabled("UBRS"))
        if BananaLoot:GetRaidleadEnabled() then BananaLoot_UI.optRaidleadBtn:Enable() else BananaLoot_UI.optRaidleadBtn:Disable() end
        scaleEditBox:SetText(tostring(BananaLoot:GetUIScalePercent()))
        lootScaleEditBox:SetText(tostring(BananaLoot:GetLootUIScalePercent()))
        soundEnabledCheck:SetChecked(BananaLoot:GetSoundEnabled())
        soundLootCheck:SetChecked(BananaLoot:GetSoundLootDetectedEnabled())
        soundRollCheck:SetChecked(BananaLoot:GetSoundRollStartedEnabled())
        soundWinnerCheck:SetChecked(BananaLoot:GetSoundWinnerEnabled())
        soundAwardCheck:SetChecked(BananaLoot:GetSoundAwardEnabled())
        soundClickCheck:SetChecked(BananaLoot:GetSoundButtonClicksEnabled())
        lootPreviewCheck:SetChecked(BananaLoot:GetLootPreviewEnabled())
        maxSREditBox:SetText(tostring(BananaLoot:GetMaxSRCount()))
        autoMLCheck:SetChecked(BananaLoot:GetAutoMasterLootEnabled())
        rollSyncCheck:SetChecked(BananaLoot:GetRollSyncEnabled())
        rollSyncSenderCheck:SetChecked(BananaLoot:GetRollSyncShowForSender())
        multiWinnerCheck:SetChecked(BananaLoot:GetMultiWinnerEnabled())
        tradeTrackingCheck:SetChecked(BananaLoot:GetTradeTrackingEnabled())
        ShowOptTab(TAB_GENERAL)
        optFrame:Show()
    end
end

-- ============================================================
-- 2) EXPORT / IMPORT POPUPS (für die Vertretung)
-- ============================================================
local function CreateCopyBoxFrame(name, titleKey, width, height)
    width = width or 420
    height = height or 180
    local f = CreateFrame("Frame", name, UIParent)
    f:SetWidth(width)
    f:SetHeight(height)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 11, bottom = 11 },
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText(BananaLoot:L(titleKey))
    f.titleText = title
    f.titleKey = titleKey

    local closeBtn = CreateFrame("Button", name .. "CloseButton", f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        this:GetParent():Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 46)

    local editBox = CreateFrame("EditBox", name .. "EditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(width - 60)
    editBox:SetAutoFocus(true)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    f.editBox = editBox
    return f
end

local exportFrame = CreateCopyBoxFrame("BananaLootExportFrame", "WIN_EXPORT_TITLE")
local exportHint = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
exportHint:SetPoint("BOTTOM", exportFrame, "BOTTOM", 0, 16)
RegisterLocaleText(exportHint, "WIN_EXPORT_HINT")

function BananaLoot_UI:ShowExport()
    local text = BananaLoot:ExportSRList()
    exportFrame.editBox:SetText(text)
    exportFrame.editBox:HighlightText()
    exportFrame:Show()
    exportFrame.editBox:SetFocus()
end

local importFrame = CreateCopyBoxFrame("BananaLootImportFrame", "WIN_IMPORT_TITLE")
-- Höher als der Standard und der untere Reservebereich (unter dem
-- Textfeld) vergrößert, damit drei Button-Reihen (Import / raidres.top /
-- Debug-Rohdaten) plus Hinweistext bequem Platz finden.
importFrame:SetHeight(230)
if BananaLootImportFrameScroll then
    BananaLootImportFrameScroll:ClearAllPoints()
    BananaLootImportFrameScroll:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 20, -50)
    BananaLootImportFrameScroll:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMRIGHT", -34, 76)
end
local importHint = importFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
importHint:SetPoint("BOTTOM", importFrame, "BOTTOM", 0, 66)
RegisterLocaleText(importHint, "WIN_IMPORT_HINT")

local importBtn = CreateFrame("Button", "BananaLootImportConfirmBtn", importFrame, "UIPanelButtonTemplate")
importBtn:SetWidth(100)
importBtn:SetHeight(20)
importBtn:SetPoint("BOTTOM", importFrame, "BOTTOM", -55, 38)
RegisterLocaleText(importBtn, "WIN_IMPORT_BTN")
importBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local text = importFrame.editBox:GetText()
    local ok, err, count, hrCount, ageMinutes, droppedCount = BananaLoot:ImportSRList(text)
    if ok then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_SUCCESS"), count or 0, hrCount or 0))
        -- Warnung, falls die importierte Liste bereits einige Zeit alt ist
        -- (z.B. Vertretung übernimmt einen Export von vor 20 Minuten -
        -- in der Zwischenzeit könnten schon Items vergeben worden sein).
        if ageMinutes and ageMinutes >= 5 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_OLD_WARNING"), ageMinutes))
        end
        -- Warnung, falls einzelne Reservierungen wegen des aktuellen
        -- SR-Limits (siehe Optionen) beim Import verworfen wurden.
        if droppedCount and droppedCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_DROPPED_WARNING"), droppedCount, BananaLoot:GetMaxSRCount()))
        end
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        importFrame:Hide()
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_FAIL"))
    end
end)

-- raidres.top-Import: Base64-kodierter JSON-Export von der Website
-- (separater Button, da anderes Format als der eigene MSRv2-Export).
local importRaidResBtn = CreateFrame("Button", "BananaLootImportRaidResBtn", importFrame, "UIPanelButtonTemplate")
importRaidResBtn:SetWidth(110)
importRaidResBtn:SetHeight(20)
importRaidResBtn:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
RegisterLocaleText(importRaidResBtn, "WIN_IMPORT_RAIDRES_BTN")
importRaidResBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local text = importFrame.editBox:GetText()
    if not text or text == "" then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_EMPTY"))
        return
    end
    local ok, err, result = BananaLoot:ImportRaidResData(text)
    if ok then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_RAIDRES_SUCCESS"), result.itemCount, result.hrCount))
        if result.droppedCount and result.droppedCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_DROPPED_WARNING"), result.droppedCount, BananaLoot:GetMaxSRCount()))
        end
        if table.getn(result.unmatchedNames) > 0 then
            if BananaLoot:IsSolo() then
                DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_SOLO_HINT"))
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_RAIDRES_UNMATCHED_WARNING"), table.concat(result.unmatchedNames, ", ")))
            end
        end
        if table.getn(result.hrSkipped) > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_RAIDRES_HR_SKIPPED_WARNING"), table.getn(result.hrSkipped), table.concat(result.hrSkipped, ", ")))
        end
        if result.whisperCount and result.whisperCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_RAIDRES_WHISPERS"), result.whisperCount))
        end
        if result.whisperSkipped and table.getn(result.whisperSkipped) > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("IMPORT_RAIDRES_WHISPER_SKIPPED"), table.concat(result.whisperSkipped, ", ")))
        end
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        importFrame:Hide()
        if table.getn(result.unmatchedNames) > 0 and BananaLoot_UI.ShowAliasWindow then
            BananaLoot_UI:ShowAliasWindow()
        end
    else
        if err == "base64_failed" then
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_BASE64_FAILED"))
        elseif err == "json_failed" then
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_JSON_FAILED"))
        elseif err == "no_entries_found" then
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_NO_ENTRIES"))
            -- Debug-Fallback: rohe (dekodierte) JSON-Daten im bereits
            -- vorhandenen Export-Fenster anzeigen, damit sie zur Fehlersuche
            -- kopiert und weitergegeben werden können, falls das Format
            -- doch nicht wie erwartet aussieht.
            if result and result.rawJson then
                exportFrame.titleText:SetText(BananaLoot:L("IMPORT_RAIDRES_SHOW_RAW"))
                exportFrame.editBox:SetText(result.rawJson)
                exportFrame.editBox:HighlightText()
                exportFrame:Show()
                exportFrame.editBox:SetFocus()
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_EMPTY"))
        end
    end
end)

-- Debug-Button: zeigt die rohen dekodierten JSON-Daten unabhängig davon, ob
-- der Import selbst funktioniert -- nützlich, um das exakte raidres.top-
-- Format einmal einzusehen und die Feldnamen-Zuordnung bei Bedarf zu
-- verfeinern, statt bei jedem Sonderfall neu zu raten.
local importRawDebugBtn = CreateFrame("Button", "BananaLootImportRawDebugBtn", importFrame, "UIPanelButtonTemplate")
importRawDebugBtn:SetWidth(160)
importRawDebugBtn:SetHeight(20)
importRawDebugBtn:SetPoint("BOTTOM", importFrame, "BOTTOM", 0, 12)
RegisterLocaleText(importRawDebugBtn, "IMPORT_RAIDRES_SHOW_RAW")
importRawDebugBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local text = importFrame.editBox:GetText()
    local decoded, err = BananaLoot:DecodeRaidResRaw(text)
    if decoded then
        exportFrame.titleText:SetText(BananaLoot:L("IMPORT_RAIDRES_SHOW_RAW"))
        exportFrame.editBox:SetText(decoded)
        exportFrame.editBox:HighlightText()
        exportFrame:Show()
        exportFrame.editBox:SetFocus()
    elseif err == "empty" then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_EMPTY"))
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("IMPORT_RAIDRES_BASE64_FAILED"))
    end
end)

function BananaLoot_UI:ShowImport()
    importFrame.editBox:SetText("")
    importFrame:Show()
    importFrame.editBox:SetFocus()
end

-- ============================================================
-- 2b) CSV-EXPORT POPUPS (Tab-getrennt, für Google Sheets)
-- ============================================================
local csvResFrame = CreateCopyBoxFrame("BananaLootCsvResFrame", "WIN_CSV_SR_TITLE")
local csvResHint = csvResFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
csvResHint:SetPoint("BOTTOM", csvResFrame, "BOTTOM", 0, 16)
RegisterLocaleText(csvResHint, "WIN_CSV_HINT")

function BananaLoot_UI:ShowCSVReservations()
    local text = BananaLoot:ExportReservationsCSV()
    csvResFrame.editBox:SetText(text)
    csvResFrame.editBox:HighlightText()
    csvResFrame:Show()
    csvResFrame.editBox:SetFocus()
end

local csvLogFrame = CreateCopyBoxFrame("BananaLootCsvLogFrame", "WIN_CSV_LOG_TITLE")
local csvLogHint = csvLogFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
csvLogHint:SetPoint("BOTTOM", csvLogFrame, "BOTTOM", 0, 16)
RegisterLocaleText(csvLogHint, "WIN_CSV_HINT")

function BananaLoot_UI:ShowCSVLog()
    local text = BananaLoot:ExportLogCSV()
    csvLogFrame.editBox:SetText(text)
    csvLogFrame.editBox:HighlightText()
    csvLogFrame:Show()
    csvLogFrame.editBox:SetFocus()
end

-- ============================================================
-- 2c-Help) BEFEHLSÜBERSICHT: reine Nachschlage-Referenz für alle
-- Slash-/Whisper-Befehle und Roll-Kategorien, ausklappbar über einen
-- kleinen "?"-Button im Optionsfenster. Wiederverwendet CreateCopyBoxFrame
-- (etwas größer als Export/CSV, damit der komplette Text ohne viel
-- Scrollen sichtbar ist).
-- ============================================================
local helpFrame = CreateCopyBoxFrame("BananaLootHelpFrame", "WIN_HELP_TITLE", 460, 480)
local helpHint = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
helpHint:SetPoint("BOTTOM", helpFrame, "BOTTOM", 0, 16)
RegisterLocaleText(helpHint, "WIN_HELP_HINT")

function BananaLoot_UI:ShowHelp()
    local text = BananaLoot:L("CMD_LEGEND_TEXT")
    helpFrame.editBox:SetText(text)
    helpFrame.editBox:HighlightText()
    helpFrame:Show()
    helpFrame.editBox:SetFocus()
end

-- ============================================================
-- 2c) VERWALTEN: SR-Liste pro Item ansehen und bearbeiten
-- ============================================================
local manageFrame = CreateFrame("Frame", "BananaLootManageFrame", UIParent)
manageFrame:SetWidth(380)
manageFrame:SetHeight(420)
manageFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
manageFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
manageFrame:SetMovable(true)
manageFrame:EnableMouse(true)
manageFrame:RegisterForDrag("LeftButton")
manageFrame:SetScript("OnDragStart", function() manageFrame:StartMoving() end)
manageFrame:SetScript("OnDragStop", function() manageFrame:StopMovingOrSizing() end)
manageFrame:SetFrameStrata("DIALOG")
manageFrame:Hide()
manageFrame.itemID = nil
manageFrame.context = nil -- "sr" oder "loot", steuert welche Aktionen sichtbar sind (siehe ShowManage)

if StaticPopupDialogs then
    StaticPopupDialogs["BANANALOOT_CONFIRM_MANUAL_AWARD"] = {
        text = BananaLoot:L("MG_POPUP_TEXT"),
        button1 = BananaLoot:L("UI_POPUP_YES"),
        button2 = BananaLoot:L("UI_POPUP_CANCEL"),
        OnAccept = function()
            if BananaLoot_ManualAwardPending then
                BananaLoot:AwardItem(BananaLoot_ManualAwardPending.itemID, BananaLoot_ManualAwardPending.name)
                manageFrame:Hide()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
                BananaLoot_ManualAwardPending = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["BANANALOOT_CONFIRM_RAID_ROLL"] = {
        text = BananaLoot:L("MG_RAIDROLL_POPUP_TEXT"),
        button1 = BananaLoot:L("UI_POPUP_YES"),
        button2 = BananaLoot:L("UI_POPUP_CANCEL"),
        OnAccept = function()
            if BananaLoot_RaidRollPending then
                BananaLoot:DoRaidRoll(BananaLoot_RaidRollPending.itemID)
                manageFrame:Hide()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
                BananaLoot_RaidRollPending = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local mgClose = CreateFrame("Button", "BananaLootManageCloseButton", manageFrame, "UIPanelCloseButton")
mgClose:SetPoint("TOPRIGHT", manageFrame, "TOPRIGHT", -4, -4)
mgClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

local mgTitle = manageFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mgTitle:SetPoint("TOP", manageFrame, "TOP", 0, -16)
RegisterLocaleText(mgTitle, "WIN_MANAGE_TITLE")

local mgItemText = manageFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mgItemText:SetPoint("TOP", manageFrame, "TOP", 0, -38)
mgItemText:SetWidth(300)

local mgScroll = CreateFrame("ScrollFrame", "BananaLootManageScroll", manageFrame, "UIPanelScrollFrameTemplate")
mgScroll:SetPoint("TOPLEFT", manageFrame, "TOPLEFT", 16, -60)
mgScroll:SetPoint("BOTTOMRIGHT", manageFrame, "BOTTOMRIGHT", -30, 96)

local mgChild = CreateFrame("Frame", "BananaLootManageScrollChild", mgScroll)
mgChild:SetWidth(320)
mgChild:SetHeight(1)
mgScroll:SetScrollChild(mgChild)

local MG_ROW_H = 24
local MG_MAX = 25
local mgRows = {}

local function CreateMgRow(i)
    local r = CreateFrame("Frame", "BananaLootManageRow" .. i, mgChild)
    r:SetWidth(320)
    r:SetHeight(MG_ROW_H)
    r:SetPoint("TOPLEFT", mgChild, "TOPLEFT", 0, -(i - 1) * MG_ROW_H)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.nameText:SetWidth(110)
    r.nameText:SetJustifyH("LEFT")

    r.minusBtn = CreateFrame("Button", "BananaLootManageRow" .. i .. "MinusBtn", r, "UIPanelButtonTemplate")
    r.minusBtn:SetWidth(16)
    r.minusBtn:SetHeight(18)
    r.minusBtn:SetPoint("LEFT", r.nameText, "RIGHT", 1, 0)
    r.minusBtn:SetText("-")

    r.plusBtn = CreateFrame("Button", "BananaLootManageRow" .. i .. "PlusBtn", r, "UIPanelButtonTemplate")
    r.plusBtn:SetWidth(16)
    r.plusBtn:SetHeight(18)
    r.plusBtn:SetPoint("LEFT", r.minusBtn, "RIGHT", 1, 0)
    r.plusBtn:SetText("+")

    r.removeBtn = CreateFrame("Button", "BananaLootManageRow" .. i .. "RemoveBtn", r, "UIPanelButtonTemplate")
    r.removeBtn:SetWidth(70)
    r.removeBtn:SetHeight(18)
    r.removeBtn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.removeBtn:SetText(BananaLoot:L("MG_REMOVE_BTN"))

    r.winBtn = CreateFrame("Button", "BananaLootManageRow" .. i .. "WinBtn", r, "UIPanelButtonTemplate")
    r.winBtn:SetWidth(80)
    r.winBtn:SetHeight(18)
    r.winBtn:SetPoint("RIGHT", r.removeBtn, "LEFT", -4, 0)
    r.winBtn:SetText(BananaLoot:L("MG_WIN_BTN"))

    return r
end

for i = 1, MG_MAX do
    mgRows[i] = CreateMgRow(i)
    mgRows[i]:Hide()
end

local mgOverflowText = manageFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mgOverflowText:SetPoint("BOTTOM", manageFrame, "BOTTOM", 0, 86)
mgOverflowText:SetText("")

-- Vorwärtsdeklaration: mgRemoveItemBtn und mgRaidRollBtn werden erst weiter
-- unten per CreateFrame erzeugt, aber RefreshManage() (direkt darunter)
-- muss sie schon referenzieren können. Ohne dieses "local" hier würde
-- RefreshManage() beim Erstversuch auf eine globale (nil) Variable
-- zugreifen statt auf die später zugewiesene lokale -- Lua-Locals sind
-- lexikalisch gebunden, ein "local" weiter unten im Chunk kommt zu spät.
local mgRemoveItemBtn, mgRaidRollBtn

local function RefreshManage()
    local id = manageFrame.itemID
    if not id then return end

    -- Kontextabhängige Buttons: im SR-Fenster gibt es noch keinen Loot-
    -- Slot zu vergeben, daher "Reservierung löschen" statt "Drop
    -- überspringen" und kein Raid-Roll-Button.
    if manageFrame.context == "sr" then
        mgRemoveItemBtn:SetText(BananaLoot:L("MG_REMOVE_RESERVATION_BTN"))
        mgRaidRollBtn:Hide()
    else
        mgRemoveItemBtn:SetText(BananaLoot:L("MG_SKIP_DROP_BTN"))
        mgRaidRollBtn:Show()
    end

    local res = BananaLoot.reservations[id]
    local hrTag = BananaLoot:IsHardReserve(id) and BananaLoot:L("MG_HR_TAG") or ""
    local mgLink = (res and res.link) or BananaLoot.knownLootItems[id]
    local mgDisplay = mgLink
    if not mgLink or (not string.find(mgLink, "|Hitem:") and string.find(mgLink, "^item:")) then
        mgDisplay = "|cff" .. BananaLoot:GetQualityColorHex(id) .. "Item #" .. id .. "|r"
    end
    mgItemText:SetText(mgDisplay .. hrTag)

    if res and table.getn(res.order) > MG_MAX then
        mgOverflowText:SetText(string.format(BananaLoot:L("MG_OVERFLOW"), table.getn(res.order) - MG_MAX, MG_MAX))
    else
        mgOverflowText:SetText("")
    end

    local shown = 0
    if res then
        for i = 1, table.getn(res.order) do
            shown = shown + 1
            if shown > MG_MAX then break end
            local name = res.order[i]
            local row = mgRows[shown]
            local stack = BananaLoot:GetStack(name, id)
            local bonusTxt = ""
            if stack > 0 then bonusTxt = " |cffffcc00(+" .. (stack * BananaLoot:GetBonusPerStack()) .. ")|r" end
            local isTemp = BananaLoot:IsTempReservation(id, name)
            if isTemp then
                row.nameText:SetText(BananaLoot:ColoredName(name) .. BananaLoot:L("MG_TEMP_TAG"))
                row.minusBtn:Hide()
                row.plusBtn:Hide()
            else
                row.nameText:SetText(BananaLoot:ColoredName(name) .. bonusTxt)
                row.minusBtn:Show()
                row.plusBtn:Show()
            end
            row.removeBtn:SetText(BananaLoot:L("MG_REMOVE_BTN"))
            row.removeBtn:Show()
            row.winBtn:SetText(BananaLoot:L("MG_WIN_BTN"))
            if manageFrame.context == "sr" then
                row.winBtn:Hide()
            else
                row.winBtn:Show()
            end
            row.minusBtn:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                BananaLoot:DecrementStack(name, id)
                RefreshManage()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end)
            row.plusBtn:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                BananaLoot:IncrementStack(name, id)
                RefreshManage()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end)
            row.removeBtn:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                BananaLoot:RemoveReservation(res.link, name)
                RefreshManage()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end)
            row.winBtn:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                if StaticPopup_Show then
                    BananaLoot_ManualAwardPending = { itemID = id, name = name }
                    StaticPopup_Show("BANANALOOT_CONFIRM_MANUAL_AWARD", name)
                else
                    BananaLoot:AwardItem(id, name)
                    manageFrame:Hide()
                    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
                end
            end)
            row:Show()
        end
    end
    for i = shown + 1, MG_MAX do mgRows[i]:Hide() end
    mgChild:SetHeight(math.max(1, shown * MG_ROW_H))

    if shown == 0 then
        mgRows[1].nameText:SetText(BananaLoot:L("MG_NONE"))
        mgRows[1].minusBtn:Hide()
        mgRows[1].plusBtn:Hide()
        mgRows[1].removeBtn:Hide()
        mgRows[1].winBtn:Hide()
        mgRows[1]:Show()
    end
end

local mgAddLabel = manageFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
mgAddLabel:SetPoint("BOTTOMLEFT", manageFrame, "BOTTOMLEFT", 16, 80)
RegisterLocaleText(mgAddLabel, "MG_ADD_LABEL")

local mgAddBox = CreateFrame("EditBox", "BananaLootManageAddBox", manageFrame, "InputBoxTemplate")
mgAddBox:SetWidth(140)
mgAddBox:SetHeight(20)
mgAddBox:SetPoint("TOPLEFT", mgAddLabel, "BOTTOMLEFT", 6, -8)
mgAddBox:SetAutoFocus(false)

local mgAddBtn = CreateFrame("Button", "BananaLootManageAddBtn", manageFrame, "UIPanelButtonTemplate")
mgAddBtn:SetWidth(80)
mgAddBtn:SetHeight(20)
mgAddBtn:SetPoint("LEFT", mgAddBox, "RIGHT", 10, 0)
RegisterLocaleText(mgAddBtn, "MG_ADD_BTN")
-- Auswahlfenster nach "Hinzufuegen": nur fuer diesen Drop oder in die SR-Liste.
-- Als BananaLoot_UI.mgChoice statt als Top-Level-Local (Locals-Limit der Datei).
do
    local f = CreateFrame("Frame", "BananaLootManageChoiceFrame", UIParent)
    f:SetWidth(380)
    f:SetHeight(170)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 11, bottom = 11 },
    })
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:Hide()
    tinsert(UISpecialFrames, "BananaLootManageChoiceFrame")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -18)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOP", f, "TOP", 0, -48)
    f.text:SetWidth(330)

    f.tempBtn = CreateFrame("Button", "BananaLootManageChoiceTempBtn", f, "UIPanelButtonTemplate")
    f.tempBtn:SetWidth(165)
    f.tempBtn:SetHeight(28)
    f.tempBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 58)

    f.srBtn = CreateFrame("Button", "BananaLootManageChoiceSRBtn", f, "UIPanelButtonTemplate")
    f.srBtn:SetWidth(165)
    f.srBtn:SetHeight(28)
    f.srBtn:SetPoint("LEFT", f.tempBtn, "RIGHT", 10, 0)

    f.cancelBtn = CreateFrame("Button", "BananaLootManageChoiceCancelBtn", f, "UIPanelButtonTemplate")
    f.cancelBtn:SetWidth(120)
    f.cancelBtn:SetHeight(24)
    f.cancelBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 22)

    local function Finish()
        f:Hide()
        mgAddBox:SetText("")
        RefreshManage()
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    end

    local function WarnIfNotInRoster(name)
        if not BananaLoot:IsPlayerInRoster(name) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("MANAGE_ADD_WARNING"), name))
        end
    end

    f.tempBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        if f.pendingLink and f.pendingName then
            BananaLoot:AddTempReservation(f.pendingLink, f.pendingName)
            WarnIfNotInRoster(f.pendingName)
        end
        Finish()
    end)
    f.srBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        if f.pendingLink and f.pendingName then
            -- forceIgnoreHR = true: der Loot-Master darf im Verwalten-Fenster
            -- auch fuer Hard-Reserve-Items direkt einen Spieler hinterlegen
            -- (z.B. um danach ueber "Gewinner" manuell zu vergeben).
            BananaLoot:AddReservation(f.pendingLink, f.pendingName, true)
            WarnIfNotInRoster(f.pendingName)
        end
        Finish()
    end)
    f.cancelBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        f:Hide()
    end)

    BananaLoot_UI.mgChoice = f
end

function BananaLoot_UI:ShowAddChoice(link, name)
    local f = BananaLoot_UI.mgChoice
    f.pendingLink = link
    f.pendingName = name
    f.title:SetText(BananaLoot:L("MG_CHOICE_TITLE"))
    f.text:SetText(string.format(BananaLoot:L("MG_CHOICE_TEXT"), BananaLoot:ColoredName(name)))
    f.tempBtn:SetText(BananaLoot:L("MG_CHOICE_TEMP"))
    f.srBtn:SetText(BananaLoot:L("MG_CHOICE_SR"))
    f.cancelBtn:SetText(BananaLoot:L("MG_CHOICE_CANCEL"))
    f:Show()
end

mgAddBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local name = mgAddBox:GetText()
    local id = manageFrame.itemID
    if name and name ~= "" and id then
        local res = BananaLoot.reservations[id]
        local link = (res and res.link) or BananaLoot.knownLootItems[id]
        if link then
            BananaLoot_UI:ShowAddChoice(link, name)
        end
    end
end)

mgRemoveItemBtn = CreateFrame("Button", "BananaLootManageRemoveItemBtn", manageFrame, "UIPanelButtonTemplate")
mgRemoveItemBtn:SetWidth(180)
mgRemoveItemBtn:SetHeight(20)
mgRemoveItemBtn:SetPoint("BOTTOMLEFT", manageFrame, "BOTTOMLEFT", 16, 20)
-- Text wird kontextabhängig in RefreshManage() gesetzt (siehe dort),
-- daher KEINE RegisterLocaleText-Registrierung hier (würde bei
-- Sprachwechsel sonst immer auf einen festen Text zurückfallen).
mgRemoveItemBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local id = manageFrame.itemID
    if not id then return end

    if manageFrame.context == "sr" then
        -- Nur die Reservierung löschen, der Loot-Eintrag (falls das Item
        -- gerade real im Loot-Fenster liegt) bleibt unangetastet -- das
        -- Loot-Fenster kümmert sich unabhängig davon um den Drop selbst.
        local res = BananaLoot.reservations[id]
        if res then
            for i = 1, table.getn(res.order) do
                BananaLoot:RemoveItemFromPlayerList(res.order[i], id)
            end
        end
        BananaLoot.reservations[id] = nil
        BananaLoot:SaveSession()
    else
        -- Nur den Loot-Eintrag entfernen ("Drop überspringen"), die SR-
        -- Reservierung bleibt für einen möglichen erneuten Drop erhalten
        -- und ist weiterhin im SR-Fenster sichtbar/bearbeitbar.
        BananaLoot.knownLootItems[id] = nil
        BananaLoot.lootCounts[id] = nil
        BananaLoot:ClearTempReservations(id)
        if BananaLoot.activeRoll and BananaLoot.activeRoll.itemID == id then
            BananaLoot.activeRoll = nil
        end
    end

    manageFrame:Hide()
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
end)

-- Raid Roll: vergibt das Item per Zufallsauswahl unter dem kompletten
-- aktuellen Raid/der Gruppe (unabhängig von SR-Reservierungen), ohne dass
-- Spieler selbst würfeln müssen -- siehe BananaLoot:DoRaidRoll (Core).
mgRaidRollBtn = CreateFrame("Button", "BananaLootManageRaidRollBtn", manageFrame, "UIPanelButtonTemplate")
mgRaidRollBtn:SetWidth(130)
mgRaidRollBtn:SetHeight(20)
mgRaidRollBtn:SetPoint("LEFT", mgRemoveItemBtn, "RIGHT", 6, 0)
RegisterLocaleText(mgRaidRollBtn, "MG_RAIDROLL_BTN")
mgRaidRollBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local id = manageFrame.itemID
    if not id then return end
    local res = BananaLoot.reservations[id]
    local link = (res and res.link) or BananaLoot.knownLootItems[id] or ("Item " .. id)
    if StaticPopup_Show then
        BananaLoot_RaidRollPending = { itemID = id }
        StaticPopup_Show("BANANALOOT_CONFIRM_RAID_ROLL", link)
    else
        BananaLoot:DoRaidRoll(id)
        manageFrame:Hide()
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    end
end)

-- context: "sr" (aus dem SR-Fenster aufgerufen, keine Vergabe-Aktionen)
-- oder "loot" (aus dem Loot-Fenster, mit Gewinner/Raid-Roll). Default
-- "loot" falls nicht angegeben, aus Kompatibilitätsgründen.
function BananaLoot_UI:ShowManage(itemID, context)
    manageFrame.itemID = itemID
    manageFrame.context = context or "loot"
    RefreshManage()
    manageFrame:Show()
end

-- ============================================================
-- 2d) HARD RESERVE VERWALTUNG (Liste + Entfernen-Button je Item)
-- ============================================================
local hrFrame = CreateFrame("Frame", "BananaLootHRFrame", UIParent)
hrFrame:SetWidth(340)
hrFrame:SetHeight(360)
hrFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
hrFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
hrFrame:SetMovable(true)
hrFrame:EnableMouse(true)
hrFrame:RegisterForDrag("LeftButton")
hrFrame:SetScript("OnDragStart", function() hrFrame:StartMoving() end)
hrFrame:SetScript("OnDragStop", function() hrFrame:StopMovingOrSizing() end)
hrFrame:SetFrameStrata("DIALOG")
hrFrame:Hide()

local hrClose = CreateFrame("Button", "BananaLootHRCloseButton", hrFrame, "UIPanelCloseButton")
hrClose:SetPoint("TOPRIGHT", hrFrame, "TOPRIGHT", -4, -4)
hrClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

local hrTitle = hrFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
hrTitle:SetPoint("TOP", hrFrame, "TOP", 0, -16)
RegisterLocaleText(hrTitle, "WIN_HR_TITLE")

local hrHint = hrFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hrHint:SetPoint("TOP", hrFrame, "TOP", 0, -36)
hrHint:SetWidth(300)
hrHint:SetJustifyH("CENTER")
RegisterLocaleText(hrHint, "WIN_HR_HINT")

local hrScroll = CreateFrame("ScrollFrame", "BananaLootHRScroll", hrFrame, "UIPanelScrollFrameTemplate")
hrScroll:SetPoint("TOPLEFT", hrFrame, "TOPLEFT", 16, -60)
hrScroll:SetPoint("BOTTOMRIGHT", hrFrame, "BOTTOMRIGHT", -30, 20)

local hrChild = CreateFrame("Frame", "BananaLootHRScrollChild", hrScroll)
hrChild:SetWidth(280)
hrChild:SetHeight(1)
hrScroll:SetScrollChild(hrChild)

local HR_ROW_H = 22
local HR_MAX = 30
local hrRows = {}

local function CreateHRRow(i)
    local r = CreateFrame("Frame", "BananaLootHRRow" .. i, hrChild)
    r:SetWidth(280)
    r:SetHeight(HR_ROW_H)
    r:SetPoint("TOPLEFT", hrChild, "TOPLEFT", 0, -(i - 1) * HR_ROW_H)

    r.linkText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.linkText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.linkText:SetWidth(190)
    r.linkText:SetJustifyH("LEFT")

    r.removeBtn = CreateFrame("Button", "BananaLootHRRow" .. i .. "RemoveBtn", r, "UIPanelButtonTemplate")
    r.removeBtn:SetWidth(80)
    r.removeBtn:SetHeight(18)
    r.removeBtn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.removeBtn:SetText(BananaLoot:L("HR_REMOVE_BTN"))

    return r
end

for i = 1, HR_MAX do
    hrRows[i] = CreateHRRow(i)
    hrRows[i]:Hide()
end

local hrOverflowText = hrFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hrOverflowText:SetPoint("BOTTOM", hrFrame, "BOTTOM", 0, 4)
hrOverflowText:SetText("")

local function RefreshHRList()
    local list = BananaLoot:GetHardReserveList()
    local ids = {}
    for id, _ in pairs(list) do table.insert(ids, id) end
    table.sort(ids)

    if table.getn(ids) > HR_MAX then
        hrOverflowText:SetText(string.format(BananaLoot:L("HR_OVERFLOW"), table.getn(ids) - HR_MAX))
    else
        hrOverflowText:SetText("")
    end

    local shown = 0
    for i = 1, table.getn(ids) do
        local id = ids[i]
        shown = shown + 1
        if shown > HR_MAX then break end
        local row = hrRows[shown]
        row.linkText:SetText(list[id].link)
        row.removeBtn:SetText(BananaLoot:L("HR_REMOVE_BTN"))
        row.removeBtn:Show()
        row.removeBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            local removedLink = list[id] and list[id].link
            BananaLoot:RemoveHardReserve(id)
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("HR_REMOVED_LIST"), removedLink or ("Item " .. id)))
            RefreshHRList()
            if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        end)
        row:Show()
    end
    for i = shown + 1, HR_MAX do hrRows[i]:Hide() end
    hrChild:SetHeight(math.max(1, shown * HR_ROW_H))

    if shown == 0 then
        hrRows[1].linkText:SetText(BananaLoot:L("HR_EMPTY"))
        hrRows[1].removeBtn:Hide()
        hrRows[1]:Show()
    end
end

function BananaLoot_UI:ShowHRList()
    RefreshHRList()
    hrFrame:Show()
end

-- ============================================================
-- 2f) BANK RESERVE VERWALTUNG (Liste + Entfernen-Button je Item)
-- ============================================================
local brFrame = CreateFrame("Frame", "BananaLootBRFrame", UIParent)
brFrame:SetWidth(340)
brFrame:SetHeight(360)
brFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
brFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
brFrame:SetMovable(true)
brFrame:EnableMouse(true)
brFrame:RegisterForDrag("LeftButton")
brFrame:SetScript("OnDragStart", function() brFrame:StartMoving() end)
brFrame:SetScript("OnDragStop", function() brFrame:StopMovingOrSizing() end)
brFrame:SetFrameStrata("DIALOG")
brFrame:Hide()

local brClose = CreateFrame("Button", "BananaLootBRCloseButton", brFrame, "UIPanelCloseButton")
brClose:SetPoint("TOPRIGHT", brFrame, "TOPRIGHT", -4, -4)
brClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

local brTitle = brFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
brTitle:SetPoint("TOP", brFrame, "TOP", 0, -16)
RegisterLocaleText(brTitle, "WIN_BR_TITLE")

local brHint = brFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
brHint:SetPoint("TOP", brFrame, "TOP", 0, -36)
brHint:SetWidth(300)
brHint:SetJustifyH("CENTER")
RegisterLocaleText(brHint, "WIN_BR_HINT")

local brScroll = CreateFrame("ScrollFrame", "BananaLootBRScroll", brFrame, "UIPanelScrollFrameTemplate")
brScroll:SetPoint("TOPLEFT", brFrame, "TOPLEFT", 16, -70)
brScroll:SetPoint("BOTTOMRIGHT", brFrame, "BOTTOMRIGHT", -30, 20)

local brChild = CreateFrame("Frame", "BananaLootBRScrollChild", brScroll)
brChild:SetWidth(280)
brChild:SetHeight(1)
brScroll:SetScrollChild(brChild)

local BR_ROW_H = 22
local BR_MAX = 30
local brRows = {}

local function CreateBRRow(i)
    local r = CreateFrame("Frame", "BananaLootBRRow" .. i, brChild)
    r:SetWidth(280)
    r:SetHeight(BR_ROW_H)
    r:SetPoint("TOPLEFT", brChild, "TOPLEFT", 0, -(i - 1) * BR_ROW_H)

    r.linkText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.linkText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.linkText:SetWidth(190)
    r.linkText:SetJustifyH("LEFT")

    r.removeBtn = CreateFrame("Button", "BananaLootBRRow" .. i .. "RemoveBtn", r, "UIPanelButtonTemplate")
    r.removeBtn:SetWidth(80)
    r.removeBtn:SetHeight(18)
    r.removeBtn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.removeBtn:SetText(BananaLoot:L("BR_REMOVE_BTN"))

    return r
end

for i = 1, BR_MAX do
    brRows[i] = CreateBRRow(i)
    brRows[i]:Hide()
end

local brOverflowText = brFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
brOverflowText:SetPoint("BOTTOM", brFrame, "BOTTOM", 0, 4)
brOverflowText:SetText("")

local function RefreshBRList()
    local list = BananaLoot:GetBankReserveList()
    local ids = {}
    for id, _ in pairs(list) do table.insert(ids, id) end
    table.sort(ids)

    if table.getn(ids) > BR_MAX then
        brOverflowText:SetText(string.format(BananaLoot:L("BR_OVERFLOW"), table.getn(ids) - BR_MAX))
    else
        brOverflowText:SetText("")
    end

    local shown = 0
    for i = 1, table.getn(ids) do
        local id = ids[i]
        shown = shown + 1
        if shown > BR_MAX then break end
        local row = brRows[shown]
        row.linkText:SetText(list[id].link)
        row.removeBtn:SetText(BananaLoot:L("BR_REMOVE_BTN"))
        row.removeBtn:Show()
        row.removeBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            BananaLoot:RemoveBankReserve(id)
            RefreshBRList()
            if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        end)
        row:Show()
    end
    for i = shown + 1, BR_MAX do brRows[i]:Hide() end
    brChild:SetHeight(math.max(1, shown * BR_ROW_H))

    if shown == 0 then
        brRows[1].linkText:SetText(BananaLoot:L("BR_EMPTY"))
        brRows[1].removeBtn:Hide()
        brRows[1]:Show()
    end
end

function BananaLoot_UI:ShowBRList()
    RefreshBRList()
    brFrame:Show()
end

-- ============================================================
-- 2f-2) RAIDROLL-LISTE (Liste + Entfernen-Button je Item). In einem
-- do-Block, damit keine Top-Level-Locals dazukommen (Locals-Limit).
-- ============================================================
do
    local rlFrame = CreateFrame("Frame", "BananaLootRaidListFrame", UIParent)
    rlFrame:SetWidth(340)
    rlFrame:SetHeight(380)
    rlFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    rlFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 11, bottom = 11 },
    })
    rlFrame:SetMovable(true)
    rlFrame:EnableMouse(true)
    rlFrame:RegisterForDrag("LeftButton")
    rlFrame:SetScript("OnDragStart", function() rlFrame:StartMoving() end)
    rlFrame:SetScript("OnDragStop", function() rlFrame:StopMovingOrSizing() end)
    rlFrame:SetFrameStrata("DIALOG")
    rlFrame:Hide()

    local rlClose = CreateFrame("Button", "BananaLootRaidListCloseButton", rlFrame, "UIPanelCloseButton")
    rlClose:SetPoint("TOPRIGHT", rlFrame, "TOPRIGHT", -4, -4)
    rlClose:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        rlFrame:Hide()
    end)

    local rlTitle = rlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rlTitle:SetPoint("TOP", rlFrame, "TOP", 0, -16)
    RegisterLocaleText(rlTitle, "WIN_RAIDLIST_TITLE")

    local rlHint = rlFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rlHint:SetPoint("TOP", rlFrame, "TOP", 0, -36)
    rlHint:SetWidth(300)
    rlHint:SetJustifyH("CENTER")
    RegisterLocaleText(rlHint, "WIN_RAIDLIST_HINT")

    local rlScroll = CreateFrame("ScrollFrame", "BananaLootRaidListScroll", rlFrame, "UIPanelScrollFrameTemplate")
    rlScroll:SetPoint("TOPLEFT", rlFrame, "TOPLEFT", 16, -96)
    rlScroll:SetPoint("BOTTOMRIGHT", rlFrame, "BOTTOMRIGHT", -30, 24)

    local rlChild = CreateFrame("Frame", "BananaLootRaidListScrollChild", rlScroll)
    rlChild:SetWidth(280)
    rlChild:SetHeight(1)
    rlScroll:SetScrollChild(rlChild)

    local RL_ROW_H = 24
    local RL_MAX = 30
    local rlRows = {}

    for i = 1, RL_MAX do
        local r = CreateFrame("Frame", "BananaLootRaidListRow" .. i, rlChild)
        r:SetWidth(280)
        r:SetHeight(RL_ROW_H)
        r:SetPoint("TOPLEFT", rlChild, "TOPLEFT", 0, -(i - 1) * RL_ROW_H)
        r.linkText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.linkText:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.linkText:SetWidth(180)
        r.linkText:SetJustifyH("LEFT")
        r.removeBtn = CreateFrame("Button", "BananaLootRaidListRow" .. i .. "RemoveBtn", r, "UIPanelButtonTemplate")
        r.removeBtn:SetWidth(80)
        r.removeBtn:SetHeight(20)
        r.removeBtn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r:Hide()
        rlRows[i] = r
    end

    local rlOverflow = rlFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rlOverflow:SetPoint("BOTTOM", rlFrame, "BOTTOM", 0, 6)
    rlOverflow:SetText("")

    local function RefreshRaidList()
        local list = BananaLoot:GetRaidRollList()
        local ids = {}
        for id, _ in pairs(list) do table.insert(ids, id) end
        table.sort(ids)

        if table.getn(ids) > RL_MAX then
            rlOverflow:SetText(string.format(BananaLoot:L("RAIDLIST_OVERFLOW"), table.getn(ids) - RL_MAX))
        else
            rlOverflow:SetText("")
        end

        local shown = 0
        for i = 1, table.getn(ids) do
            local id = ids[i]
            shown = shown + 1
            if shown > RL_MAX then break end
            local row = rlRows[shown]
            row.linkText:SetText(list[id].link)
            row.removeBtn:SetText(BananaLoot:L("RAIDLIST_REMOVE_BTN"))
            row.removeBtn:Show()
            row.removeBtn:SetScript("OnClick", function()
                BananaLoot:PlayClickSound()
                BananaLoot:RemoveRaidRollItem(id)
                RefreshRaidList()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end)
            row:Show()
        end
        for i = shown + 1, RL_MAX do rlRows[i]:Hide() end
        rlChild:SetHeight(math.max(1, shown * RL_ROW_H))

        if shown == 0 then
            rlRows[1].linkText:SetText(BananaLoot:L("RAIDLIST_EMPTY"))
            rlRows[1].removeBtn:Hide()
            rlRows[1]:Show()
        end
    end

    function BananaLoot_UI:ShowRaidRollList()
        RefreshRaidList()
        rlFrame:Show()
    end
end

-- ============================================================
-- 2e) SR+ WIEDERHERSTELLUNG: zeigt je Spieler die zuletzt durch eine neue
-- Reservierung verdrängte Reservierung (inkl. SR+ Stack) und erlaubt es,
-- sie mit einem Klick wiederherzustellen -- z.B. wenn sich ein Spieler
-- beim SR-Wechsel vertan hat. Aufbau analog zum Hard-Reserve-Fenster.
-- ============================================================
local recoveryFrame = CreateFrame("Frame", "BananaLootRecoveryFrame", UIParent)
recoveryFrame:SetWidth(380)
recoveryFrame:SetHeight(360)
recoveryFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
recoveryFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
recoveryFrame:SetMovable(true)
recoveryFrame:EnableMouse(true)
recoveryFrame:RegisterForDrag("LeftButton")
recoveryFrame:SetScript("OnDragStart", function() recoveryFrame:StartMoving() end)
recoveryFrame:SetScript("OnDragStop", function() recoveryFrame:StopMovingOrSizing() end)
recoveryFrame:SetFrameStrata("DIALOG")
recoveryFrame:Hide()

local recoveryClose = CreateFrame("Button", "BananaLootRecoveryCloseButton", recoveryFrame, "UIPanelCloseButton")
recoveryClose:SetPoint("TOPRIGHT", recoveryFrame, "TOPRIGHT", -4, -4)
recoveryClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

local recoveryTitle = recoveryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
recoveryTitle:SetPoint("TOP", recoveryFrame, "TOP", 0, -16)
RegisterLocaleText(recoveryTitle, "WIN_RECOVERY_TITLE")

local recoveryHint = recoveryFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
recoveryHint:SetPoint("TOP", recoveryFrame, "TOP", 0, -36)
recoveryHint:SetWidth(330)
recoveryHint:SetJustifyH("CENTER")
RegisterLocaleText(recoveryHint, "WIN_RECOVERY_HINT")

local recoveryScroll = CreateFrame("ScrollFrame", "BananaLootRecoveryScroll", recoveryFrame, "UIPanelScrollFrameTemplate")
recoveryScroll:SetPoint("TOPLEFT", recoveryFrame, "TOPLEFT", 16, -72)
recoveryScroll:SetPoint("BOTTOMRIGHT", recoveryFrame, "BOTTOMRIGHT", -30, 20)

local recoveryChild = CreateFrame("Frame", "BananaLootRecoveryScrollChild", recoveryScroll)
recoveryChild:SetWidth(320)
recoveryChild:SetHeight(1)
recoveryScroll:SetScrollChild(recoveryChild)

local RECOVERY_ROW_H = 24
local RECOVERY_MAX = 25
local recoveryRows = {}

local function CreateRecoveryRow(i)
    local r = CreateFrame("Frame", "BananaLootRecoveryRow" .. i, recoveryChild)
    r:SetWidth(320)
    r:SetHeight(RECOVERY_ROW_H)
    r:SetPoint("TOPLEFT", recoveryChild, "TOPLEFT", 0, -(i - 1) * RECOVERY_ROW_H)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.nameText:SetWidth(90)
    r.nameText:SetJustifyH("LEFT")

    r.itemText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.itemText:SetPoint("LEFT", r.nameText, "RIGHT", 4, 0)
    r.itemText:SetWidth(130)
    r.itemText:SetJustifyH("LEFT")

    r.restoreBtn = CreateFrame("Button", "BananaLootRecoveryRow" .. i .. "RestoreBtn", r, "UIPanelButtonTemplate")
    r.restoreBtn:SetWidth(90)
    r.restoreBtn:SetHeight(18)
    r.restoreBtn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.restoreBtn:SetText(BananaLoot:L("RECOVERY_RESTORE_BTN"))

    return r
end

for i = 1, RECOVERY_MAX do
    recoveryRows[i] = CreateRecoveryRow(i)
    recoveryRows[i]:Hide()
end

local function RefreshRecoveryList()
    local list = BananaLoot:GetOverwrittenList()
    local names = {}
    for name, _ in pairs(list) do table.insert(names, name) end
    table.sort(names)

    local shown = 0
    for i = 1, table.getn(names) do
        local name = names[i]
        shown = shown + 1
        if shown > RECOVERY_MAX then break end
        local entry = list[name]
        local row = recoveryRows[shown]
        row.nameText:SetText(BananaLoot:ColoredName(name))
        local bonusTxt = ""
        if entry.stack and entry.stack > 0 then
            bonusTxt = " |cffffcc00(+" .. (entry.stack * BananaLoot:GetBonusPerStack()) .. ")|r"
        end
        local recDisplay = entry.link
        if not recDisplay or (not string.find(recDisplay, "|Hitem:") and string.find(recDisplay, "^item:")) then
            recDisplay = "|cff" .. BananaLoot:GetQualityColorHex(entry.itemID) .. "Item #" .. entry.itemID .. "|r"
        end
        row.itemText:SetText(recDisplay .. bonusTxt)
        row.restoreBtn:SetText(BananaLoot:L("RECOVERY_RESTORE_BTN"))
        row.restoreBtn:Show()
        row.restoreBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            local itemDisplay = entry.link or ("Item " .. entry.itemID)
            local stackValue = entry.stack or 0
            if BananaLoot:RestoreOverwrittenReservation(name) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("RECOVERY_RESTORED_MSG"), name, itemDisplay, stackValue))
            else
                DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("RECOVERY_RESTORE_FAILED"))
            end
            RefreshRecoveryList()
            if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        end)
        row:Show()
    end
    for i = shown + 1, RECOVERY_MAX do recoveryRows[i]:Hide() end
    recoveryChild:SetHeight(math.max(1, shown * RECOVERY_ROW_H))

    if shown == 0 then
        recoveryRows[1].nameText:SetText(BananaLoot:L("RECOVERY_EMPTY"))
        recoveryRows[1].itemText:SetText("")
        recoveryRows[1].restoreBtn:Hide()
        recoveryRows[1]:Show()
    end
end

function BananaLoot_UI:ShowRecoveryList()
    RefreshRecoveryList()
    recoveryFrame:Show()
end

-- ============================================================
-- 2e-2) GETEILTE LOOT-HISTORIE (/bl history) -- zeigt Zeit/Item/
-- Gewinner/Kategorie aller Vergaben dieser Session, gespeist sowohl
-- aus den eigenen Vergaben (direkt, siehe AwardItem in BananaLoot.lua)
-- als auch aus AW-Roll-Sync-Nachrichten anderer Loot-Master (siehe
-- BananaLoot:HandleRollSyncMessage). Rein session-lokal, NICHT in
-- SavedVariables persistiert -- der Loot-Master hat mit /bl csvlog
-- ohnehin schon sein eigenes dauerhaftes Log. Bankreserve-Vergaben
-- werden hier bewusst nie eingetragen (bleiben lautlos).
-- ============================================================
local historyFrame = CreateFrame("Frame", "BananaLootHistoryFrame", UIParent)
historyFrame:SetWidth(440)
historyFrame:SetHeight(380)
historyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
historyFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
historyFrame:SetMovable(true)
historyFrame:EnableMouse(true)
historyFrame:RegisterForDrag("LeftButton")
historyFrame:SetScript("OnDragStart", function() historyFrame:StartMoving() end)
historyFrame:SetScript("OnDragStop", function() historyFrame:StopMovingOrSizing() end)
historyFrame:SetFrameStrata("DIALOG")
historyFrame:Hide()

local historyClose = CreateFrame("Button", "BananaLootHistoryCloseButton", historyFrame, "UIPanelCloseButton")
historyClose:SetPoint("TOPRIGHT", historyFrame, "TOPRIGHT", -4, -4)
historyClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

local historyTitle = historyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
historyTitle:SetPoint("TOP", historyFrame, "TOP", 0, -16)
RegisterLocaleText(historyTitle, "WIN_HISTORY_TITLE")

local historyHint = historyFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
historyHint:SetPoint("TOP", historyFrame, "TOP", 0, -36)
historyHint:SetWidth(400)
historyHint:SetJustifyH("CENTER")
RegisterLocaleText(historyHint, "WIN_HISTORY_HINT")

local historyScroll = CreateFrame("ScrollFrame", "BananaLootHistoryScroll", historyFrame, "UIPanelScrollFrameTemplate")
historyScroll:SetPoint("TOPLEFT", historyFrame, "TOPLEFT", 16, -76)
historyScroll:SetPoint("BOTTOMRIGHT", historyFrame, "BOTTOMRIGHT", -30, 20)

local historyChild = CreateFrame("Frame", "BananaLootHistoryScrollChild", historyScroll)
historyChild:SetWidth(380)
historyChild:SetHeight(1)
historyScroll:SetScrollChild(historyChild)

local HISTORY_ROW_H = 20
local HISTORY_MAX = 30
local historyRows = {}

local function CreateHistoryRow(i)
    local r = CreateFrame("Frame", "BananaLootHistoryRow" .. i, historyChild)
    r:SetWidth(380)
    r:SetHeight(HISTORY_ROW_H)
    r:SetPoint("TOPLEFT", historyChild, "TOPLEFT", 0, -(i - 1) * HISTORY_ROW_H)

    r.timeText = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.timeText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.timeText:SetWidth(40)
    r.timeText:SetJustifyH("LEFT")

    r.itemText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.itemText:SetPoint("LEFT", r.timeText, "RIGHT", 4, 0)
    r.itemText:SetWidth(160)
    r.itemText:SetJustifyH("LEFT")

    r.winnerText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.winnerText:SetPoint("LEFT", r.itemText, "RIGHT", 4, 0)
    r.winnerText:SetWidth(100)
    r.winnerText:SetJustifyH("LEFT")

    r.poolText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.poolText:SetPoint("LEFT", r.winnerText, "RIGHT", 4, 0)
    r.poolText:SetWidth(70)
    r.poolText:SetJustifyH("LEFT")

    return r
end

for i = 1, HISTORY_MAX do
    historyRows[i] = CreateHistoryRow(i)
    historyRows[i]:Hide()
end

local historyOverflowText = historyFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
historyOverflowText:SetPoint("BOTTOM", historyFrame, "BOTTOM", 0, 4)
historyOverflowText:SetText("")

-- itemID -> Item-ID, winner -> Spielername, poolCode -> "ms"/"os"/"tmog"/
-- "manual"/"raidroll" (kein "bank", siehe Kommentar oben). Neueste
-- Einträge werden vorne eingefügt (index 1), daher keine Umkehrung beim
-- Anzeigen nötig.
local historyEntries = {}

local HISTORY_POOL_LABEL_KEY = {
    ms = "POOL_MS", os = "POOL_OS", tmog = "POOL_TMOG",
    manual = "POOL_MANUAL", bank = "POOL_BANK", raidroll = "POOL_RAIDROLL",
    disenchant = "POOL_DISENCHANT",
}

-- Baut einen farbcodierten Anzeigetext direkt aus einer itemID auf --
-- kein Link wird per Roll-Sync mitgesendet (siehe Protokollkommentar in
-- BananaLoot.lua). Bewusste, kleine Duplikation derselben Fallback-Kette
-- wie in BananaLootUI.lua (lokale Funktionen sind nicht dateiübergreifend
-- sichtbar, vgl. TrimRaidName weiter unten in dieser Datei fürs gleiche
-- Prinzip).
local function ResolveHistoryItemDisplay(itemID)
    local staticInfo = BananaLoot:GetStaticItemInfo(itemID)
    if staticInfo and staticInfo.name then
        return BananaLoot:BuildItemLink(itemID, staticInfo.name)
    end
    local itemName = GetItemInfo("item:" .. itemID .. ":0:0:0:0:0:0:0")
    if itemName then
        return BananaLoot:BuildItemLink(itemID, itemName)
    end
    return "|cff" .. BananaLoot:GetQualityColorHex(itemID) .. "Item #" .. itemID .. "|r"
end

local function RefreshHistoryList()
    local total = table.getn(historyEntries)
    if total > HISTORY_MAX then
        historyOverflowText:SetText(string.format(BananaLoot:L("HISTORY_OVERFLOW"), total - HISTORY_MAX))
    else
        historyOverflowText:SetText("")
    end

    local shown = 0
    for i = 1, total do
        shown = shown + 1
        if shown > HISTORY_MAX then break end
        local entry = historyEntries[i]
        local row = historyRows[shown]
        row.timeText:SetText(entry.time)
        row.itemText:SetText(ResolveHistoryItemDisplay(entry.itemID))
        row.winnerText:SetText(BananaLoot:ColoredName(entry.winner))
        local labelKey = HISTORY_POOL_LABEL_KEY[entry.poolCode]
        row.poolText:SetText(labelKey and BananaLoot:L(labelKey) or (entry.poolCode or ""))
        row:Show()
    end
    for i = shown + 1, HISTORY_MAX do historyRows[i]:Hide() end
    historyChild:SetHeight(math.max(1, shown * HISTORY_ROW_H))

    if shown == 0 then
        historyRows[1].timeText:SetText("")
        historyRows[1].itemText:SetText(BananaLoot:L("HISTORY_EMPTY"))
        historyRows[1].winnerText:SetText("")
        historyRows[1].poolText:SetText("")
        historyRows[1]:Show()
    end
end

-- Aufgerufen sowohl für die eigene Vergabe (direkt aus AwardItem, ohne
-- Netzwerk-Umweg) als auch für per Roll-Sync empfangene AW-Nachrichten
-- anderer Loot-Master (siehe BananaLoot:HandleRollSyncMessage).
function BananaLoot_UI:AddHistoryEntry(itemID, winner, poolCode)
    table.insert(historyEntries, 1, {
        time = date("%H:%M"),
        itemID = itemID,
        winner = winner,
        poolCode = poolCode,
    })
    if historyFrame:IsShown() then RefreshHistoryList() end
end

function BananaLoot_UI:ShowHistory()
    RefreshHistoryList()
    historyFrame:Show()
end

-- ============================================================
-- 2f-2) RAID SPEICHERN/LADEN
-- Zwei Fenster: ein kompaktes Speichern-Fenster (Namenseingabe) und
-- ein Listen-Fenster für gespeicherte Raids (analog zu HR/BR, aber mit
-- zwei Aktions-Buttons je Zeile: Laden und Löschen). Die eigentliche
-- Speicher-/Lade-/Löschlogik liegt in BananaLoot.lua (SaveRaid/
-- LoadRaid/DeleteSavedRaid) -- hier nur UI und Bestätigungsdialoge.
-- ============================================================

-- Eigene, einfache Trim-Funktion: BananaLoot.lua's Trim() ist eine
-- lokale (nicht exportierte) Funktion, hier daher dupliziert -- gleiche
-- zwei Zeilen wie dort, um Leerzeichen um den eingegebenen Raid-Namen
-- zu entfernen.
local function TrimRaidName(str)
    if not str then return str end
    local _, _, captured = string.find(str, "^%s*(.-)%s*$")
    return captured or str
end

-- ---- Speichern-Fenster ----
local saveRaidFrame = CreateFrame("Frame", "BananaLootSaveRaidFrame", UIParent)
saveRaidFrame:SetWidth(340)
saveRaidFrame:SetHeight(170)
saveRaidFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
saveRaidFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
saveRaidFrame:SetMovable(true)
saveRaidFrame:EnableMouse(true)
saveRaidFrame:RegisterForDrag("LeftButton")
saveRaidFrame:SetScript("OnDragStart", function() saveRaidFrame:StartMoving() end)
saveRaidFrame:SetScript("OnDragStop", function() saveRaidFrame:StopMovingOrSizing() end)
saveRaidFrame:SetFrameStrata("DIALOG")
saveRaidFrame:Hide()

local saveRaidClose = CreateFrame("Button", "BananaLootSaveRaidCloseButton", saveRaidFrame, "UIPanelCloseButton")
saveRaidClose:SetPoint("TOPRIGHT", saveRaidFrame, "TOPRIGHT", -4, -4)
saveRaidClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

local saveRaidTitle = saveRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
saveRaidTitle:SetPoint("TOP", saveRaidFrame, "TOP", 0, -16)
RegisterLocaleText(saveRaidTitle, "WIN_SAVE_RAID_TITLE")

local saveRaidHint = saveRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
saveRaidHint:SetPoint("TOP", saveRaidFrame, "TOP", 0, -38)
saveRaidHint:SetWidth(300)
saveRaidHint:SetJustifyH("CENTER")
RegisterLocaleText(saveRaidHint, "WIN_SAVE_RAID_HINT")

local saveRaidNameLabel = saveRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
saveRaidNameLabel:SetPoint("TOPLEFT", saveRaidFrame, "TOPLEFT", 20, -88)
RegisterLocaleText(saveRaidNameLabel, "SAVE_RAID_NAME_LABEL")

local saveRaidNameBox = CreateFrame("EditBox", "BananaLootSaveRaidNameBox", saveRaidFrame, "InputBoxTemplate")
saveRaidNameBox:SetWidth(220)
saveRaidNameBox:SetHeight(20)
saveRaidNameBox:SetPoint("TOPLEFT", saveRaidFrame, "TOPLEFT", 26, -110)
saveRaidNameBox:SetAutoFocus(true)
saveRaidNameBox:SetMaxLetters(64)
saveRaidNameBox:SetScript("OnEscapePressed", function() saveRaidFrame:Hide() end)

local saveRaidConfirmBtn = CreateFrame("Button", "BananaLootSaveRaidConfirmBtn", saveRaidFrame, "UIPanelButtonTemplate")
saveRaidConfirmBtn:SetWidth(100)
saveRaidConfirmBtn:SetHeight(20)
saveRaidConfirmBtn:SetPoint("TOPLEFT", saveRaidNameBox, "BOTTOMLEFT", 0, -14)
RegisterLocaleText(saveRaidConfirmBtn, "SAVE_RAID_BTN")

-- Prüft den eingegebenen Namen, fragt bei einem bereits vorhandenen
-- Eintrag per StaticPopup nach (Überschreiben), speichert sonst direkt.
local function TrySaveRaid()
    local name = TrimRaidName(saveRaidNameBox:GetText())
    if name == "" then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("SAVE_RAID_NEED_NAME"))
        return
    end
    local alreadyExists = BananaLoot:GetSavedRaidList()[name] ~= nil
    if alreadyExists and StaticPopup_Show then
        BananaLoot_SaveRaidPendingName = name
        StaticPopup_Show("BANANALOOT_CONFIRM_OVERWRITE_RAID", name)
    else
        BananaLoot:SaveRaid(name)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SAVE_RAID_DONE"), name))
        saveRaidFrame:Hide()
        if BananaLoot_UI and BananaLoot_UI.RefreshSR then BananaLoot_UI:RefreshSR() end
    end
end

saveRaidConfirmBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    TrySaveRaid()
end)
saveRaidNameBox:SetScript("OnEnterPressed", function()
    TrySaveRaid()
end)

function BananaLoot_UI:ShowSaveRaid()
    -- Vorbefüllen mit dem Namen des aktuell aktiven Raids (falls
    -- vorhanden), damit ein einfaches Zwischenspeichern ("Speichern"
    -- klicken) ohne erneute Namenseingabe möglich ist.
    saveRaidNameBox:SetText(BananaLoot:GetCurrentRaidName() or "")
    saveRaidNameBox:HighlightText()
    saveRaidFrame:Show()
    saveRaidNameBox:SetFocus()
end

if StaticPopupDialogs then
    StaticPopupDialogs["BANANALOOT_CONFIRM_OVERWRITE_RAID"] = {
        text = BananaLoot:L("UI_POPUP_OVERWRITE_RAID_TEXT"),
        button1 = BananaLoot:L("UI_POPUP_YES"),
        button2 = BananaLoot:L("UI_POPUP_CANCEL"),
        OnAccept = function()
            if BananaLoot_SaveRaidPendingName then
                local name = BananaLoot_SaveRaidPendingName
                BananaLoot:SaveRaid(name)
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("SAVE_RAID_DONE"), name))
                saveRaidFrame:Hide()
                if BananaLoot_UI and BananaLoot_UI.RefreshSR then BananaLoot_UI:RefreshSR() end
                BananaLoot_SaveRaidPendingName = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- ---- Laden-Fenster (Liste aller gespeicherten Raids) ----
local loadRaidFrame = CreateFrame("Frame", "BananaLootLoadRaidFrame", UIParent)
loadRaidFrame:SetWidth(380)
loadRaidFrame:SetHeight(360)
loadRaidFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
loadRaidFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
loadRaidFrame:SetMovable(true)
loadRaidFrame:EnableMouse(true)
loadRaidFrame:RegisterForDrag("LeftButton")
loadRaidFrame:SetScript("OnDragStart", function() loadRaidFrame:StartMoving() end)
loadRaidFrame:SetScript("OnDragStop", function() loadRaidFrame:StopMovingOrSizing() end)
loadRaidFrame:SetFrameStrata("DIALOG")
loadRaidFrame:Hide()

local loadRaidClose = CreateFrame("Button", "BananaLootLoadRaidCloseButton", loadRaidFrame, "UIPanelCloseButton")
loadRaidClose:SetPoint("TOPRIGHT", loadRaidFrame, "TOPRIGHT", -4, -4)
loadRaidClose:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

local loadRaidTitle = loadRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
loadRaidTitle:SetPoint("TOP", loadRaidFrame, "TOP", 0, -16)
RegisterLocaleText(loadRaidTitle, "WIN_LOAD_RAID_TITLE")

local loadRaidHint = loadRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
loadRaidHint:SetPoint("TOP", loadRaidFrame, "TOP", 0, -36)
loadRaidHint:SetWidth(330)
loadRaidHint:SetJustifyH("CENTER")
RegisterLocaleText(loadRaidHint, "WIN_LOAD_RAID_HINT")

local loadRaidScroll = CreateFrame("ScrollFrame", "BananaLootLoadRaidScroll", loadRaidFrame, "UIPanelScrollFrameTemplate")
loadRaidScroll:SetPoint("TOPLEFT", loadRaidFrame, "TOPLEFT", 16, -70)
loadRaidScroll:SetPoint("BOTTOMRIGHT", loadRaidFrame, "BOTTOMRIGHT", -30, 20)

local loadRaidChild = CreateFrame("Frame", "BananaLootLoadRaidScrollChild", loadRaidScroll)
loadRaidChild:SetWidth(320)
loadRaidChild:SetHeight(1)
loadRaidScroll:SetScrollChild(loadRaidChild)

local LOADRAID_ROW_H = 24
local LOADRAID_MAX = 25
local loadRaidRows = {}

local function CreateLoadRaidRow(i)
    local r = CreateFrame("Frame", "BananaLootLoadRaidRow" .. i, loadRaidChild)
    r:SetWidth(320)
    r:SetHeight(LOADRAID_ROW_H)
    r:SetPoint("TOPLEFT", loadRaidChild, "TOPLEFT", 0, -(i - 1) * LOADRAID_ROW_H)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.nameText:SetWidth(170)
    r.nameText:SetJustifyH("LEFT")

    r.deleteBtn = CreateFrame("Button", "BananaLootLoadRaidRow" .. i .. "DeleteBtn", r, "UIPanelButtonTemplate")
    r.deleteBtn:SetWidth(64)
    r.deleteBtn:SetHeight(18)
    r.deleteBtn:SetPoint("RIGHT", r, "RIGHT", 0, 0)

    r.loadBtn = CreateFrame("Button", "BananaLootLoadRaidRow" .. i .. "LoadBtn", r, "UIPanelButtonTemplate")
    r.loadBtn:SetWidth(64)
    r.loadBtn:SetHeight(18)
    r.loadBtn:SetPoint("RIGHT", r.deleteBtn, "LEFT", -4, 0)

    return r
end

for i = 1, LOADRAID_MAX do
    loadRaidRows[i] = CreateLoadRaidRow(i)
    loadRaidRows[i]:Hide()
end

local loadRaidOverflowText = loadRaidFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
loadRaidOverflowText:SetPoint("BOTTOM", loadRaidFrame, "BOTTOM", 0, 4)
loadRaidOverflowText:SetText("")

local function RefreshLoadRaidList()
    local list = BananaLoot:GetSavedRaidList()
    local names = {}
    for name, _ in pairs(list) do table.insert(names, name) end
    table.sort(names)

    if table.getn(names) > LOADRAID_MAX then
        loadRaidOverflowText:SetText(string.format(BananaLoot:L("LOAD_RAID_OVERFLOW"), table.getn(names) - LOADRAID_MAX))
    else
        loadRaidOverflowText:SetText("")
    end

    local shown = 0
    for i = 1, table.getn(names) do
        local name = names[i]
        shown = shown + 1
        if shown > LOADRAID_MAX then break end
        local entry = list[name]
        local row = loadRaidRows[shown]
        local timeTxt = entry.timestamp and date("%d.%m.%Y %H:%M", entry.timestamp) or "?"
        row.nameText:SetText(name .. " |cff888888(" .. timeTxt .. ")|r")
        row.loadBtn:SetText(BananaLoot:L("LOAD_RAID_BTN"))
        row.deleteBtn:SetText(BananaLoot:L("LOAD_RAID_DELETE_BTN"))
        row.loadBtn:Show()
        row.deleteBtn:Show()

        row.loadBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            if StaticPopup_Show then
                BananaLoot_LoadRaidPendingName = name
                StaticPopup_Show("BANANALOOT_CONFIRM_LOAD_RAID", name)
            else
                BananaLoot:LoadRaid(name)
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("LOAD_RAID_DONE"), name))
                loadRaidFrame:Hide()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            end
        end)
        row.deleteBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            if StaticPopup_Show then
                BananaLoot_DeleteRaidPendingName = name
                StaticPopup_Show("BANANALOOT_CONFIRM_DELETE_RAID", name)
            else
                BananaLoot:DeleteSavedRaid(name)
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("DELETE_RAID_DONE"), name))
                RefreshLoadRaidList()
            end
        end)
        row:Show()
    end
    for i = shown + 1, LOADRAID_MAX do loadRaidRows[i]:Hide() end
    loadRaidChild:SetHeight(math.max(1, shown * LOADRAID_ROW_H))

    if shown == 0 then
        loadRaidRows[1].nameText:SetText(BananaLoot:L("LOAD_RAID_EMPTY"))
        loadRaidRows[1].loadBtn:Hide()
        loadRaidRows[1].deleteBtn:Hide()
        loadRaidRows[1]:Show()
    end
end

function BananaLoot_UI:ShowLoadRaidList()
    RefreshLoadRaidList()
    loadRaidFrame:Show()
end

if StaticPopupDialogs then
    StaticPopupDialogs["BANANALOOT_CONFIRM_LOAD_RAID"] = {
        text = BananaLoot:L("UI_POPUP_LOAD_RAID_TEXT"),
        button1 = BananaLoot:L("UI_POPUP_YES"),
        button2 = BananaLoot:L("UI_POPUP_CANCEL"),
        OnAccept = function()
            if BananaLoot_LoadRaidPendingName then
                local name = BananaLoot_LoadRaidPendingName
                BananaLoot:LoadRaid(name)
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("LOAD_RAID_DONE"), name))
                loadRaidFrame:Hide()
                if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
                BananaLoot_LoadRaidPendingName = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["BANANALOOT_CONFIRM_DELETE_RAID"] = {
        text = BananaLoot:L("UI_POPUP_DELETE_RAID_TEXT"),
        button1 = BananaLoot:L("UI_POPUP_YES"),
        button2 = BananaLoot:L("UI_POPUP_CANCEL"),
        OnAccept = function()
            if BananaLoot_DeleteRaidPendingName then
                local name = BananaLoot_DeleteRaidPendingName
                BananaLoot:DeleteSavedRaid(name)
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("DELETE_RAID_DONE"), name))
                RefreshLoadRaidList()
                BananaLoot_DeleteRaidPendingName = nil
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- ============================================================
-- 2g) LFM ("Looking For More") -- postet einen frei waehlbaren Text in
-- regelmaessigen Abstaenden im Weltkanal (z.B. PUG-Raid-Werbung oder
-- Nachbesetzung fuer einen abgesprungenen Spieler). Die eigentliche
-- Sende-/Timer-Logik (Kanal-Suche, Intervall-Pruefung) liegt komplett
-- in BananaLoot.lua (StartLFM/StopLFM/TickLFM, Abschnitt 9e) -- hier
-- nur das Fenster: Texteingabe (hart auf eine Chat-Nachricht begrenzt),
-- Intervall-Eingabe und ein Start/Stop-Button, der Beschriftung UND
-- Funktion je nach aktuellem Zustand wechselt.
--
-- Alle Widgets haengen bewusst an EINER einzigen Tabelle (LFM) statt an
-- je einer eigenen lokalen Variable: Lua 5.1 erlaubt max. 200
-- gleichzeitig aktive Locals pro Chunk, und diese Datei war mit den
-- schon vorhandenen Fenstern (keines davon in "do...end" gekapselt)
-- bereits nah an diesem Limit -- ein Dutzend weiterer Einzel-Locals
-- (wie an anderer Stelle im Addon ueblich) wuerde es reissen.
-- ============================================================

-- Maximale Laenge einer einzelnen Chat-Nachricht in diesem Client.
-- SendChatMessage() schneidet laengere Texte sonst serverabhaengig
-- entweder ab oder lehnt sie komplett ab -- die EditBox verhindert das
-- von vornherein ueber SetMaxLetters.
local LFM_MAX_CHARS = 255
local LFM = { windowLastUpdate = 0 }

LFM.frame = CreateFrame("Frame", "BananaLootLFMFrame", UIParent)
LFM.frame:SetWidth(440)
LFM.frame:SetHeight(300)
LFM.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
LFM.frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
LFM.frame:SetMovable(true)
LFM.frame:EnableMouse(true)
LFM.frame:RegisterForDrag("LeftButton")
LFM.frame:SetScript("OnDragStart", function() LFM.frame:StartMoving() end)
LFM.frame:SetScript("OnDragStop", function() LFM.frame:StopMovingOrSizing() end)
LFM.frame:SetFrameStrata("DIALOG")
LFM.frame:Hide()

LFM.closeBtn = CreateFrame("Button", "BananaLootLFMCloseButton", LFM.frame, "UIPanelCloseButton")
LFM.closeBtn:SetPoint("TOPRIGHT", LFM.frame, "TOPRIGHT", -4, -4)
LFM.closeBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

LFM.title = LFM.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
LFM.title:SetPoint("TOP", LFM.frame, "TOP", 0, -16)
RegisterLocaleText(LFM.title, "WIN_LFM_TITLE")

LFM.textLabel = LFM.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LFM.textLabel:SetPoint("TOPLEFT", LFM.frame, "TOPLEFT", 20, -46)
RegisterLocaleText(LFM.textLabel, "LFM_TEXT_LABEL")

-- Mehrzeilige EditBox mit automatischem Zeilenumbruch (SetMultiLine),
-- statt einer einzeiligen Box, die laengeren Text nur ausschnittweise
-- scrollt und so nie komplett lesbar macht. Kleinere Schrift (ChatFont-
-- Small statt der Standard-InputBox-Schrift), damit mehr Text gleich-
-- zeitig sichtbar ist. Weiterhin hart auf LFM_MAX_CHARS begrenzt (siehe
-- oben) -- SetMaxLetters zaehlt Zeichen, unabhaengig vom Zeilenumbruch.
-- Text/Intervall werden bewusst erst beim Klick auf den Start/Stop-
-- Button uebernommen (nicht live bei jedem Tastendruck gespeichert),
-- damit ein laufender Post-Zyklus nicht mitten im Tippen durcheinander-
-- kommt -- siehe LFM.toggleBtn weiter unten.
LFM.editBox = CreateFrame("EditBox", "BananaLootLFMEditBox", LFM.frame, "InputBoxTemplate")
LFM.editBox:SetWidth(390)
LFM.editBox:SetHeight(90)
LFM.editBox:SetPoint("TOPLEFT", LFM.frame, "TOPLEFT", 26, -70)
LFM.editBox:SetAutoFocus(false)
LFM.editBox:SetMaxLetters(LFM_MAX_CHARS)
LFM.editBox:SetMultiLine(true)
LFM.editBox:SetFontObject(ChatFontSmall)
LFM.editBox:SetScript("OnEscapePressed", function() LFM.editBox:ClearFocus() end)

-- Live-Zaehler, wie viele der maximal LFM_MAX_CHARS Zeichen bereits
-- verwendet sind -- WoW's EditBox zeigt das nicht von selbst an.
LFM.charCountText = LFM.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
LFM.charCountText:SetPoint("TOPLEFT", LFM.editBox, "BOTTOMLEFT", 0, -2)

LFM.editBox:SetScript("OnTextChanged", function()
    LFM.charCountText:SetText(string.len(LFM.editBox:GetText()) .. " / " .. LFM_MAX_CHARS)
end)

LFM.intervalLabel = LFM.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LFM.intervalLabel:SetPoint("TOPLEFT", LFM.frame, "TOPLEFT", 20, -196)
RegisterLocaleText(LFM.intervalLabel, "LFM_INTERVAL_LABEL")

LFM.intervalEditBox = CreateFrame("EditBox", "BananaLootLFMIntervalEditBox", LFM.frame, "InputBoxTemplate")
LFM.intervalEditBox:SetWidth(50)
LFM.intervalEditBox:SetHeight(20)
LFM.intervalEditBox:SetPoint("TOPLEFT", LFM.frame, "TOPLEFT", 26, -220)
LFM.intervalEditBox:SetAutoFocus(false)
LFM.intervalEditBox:SetNumeric(true)

-- Zeigt entweder "Aktiv -- naechster Post in Xs" oder "Gestoppt",
-- aktualisiert per kleinem Sekunden-Ticker weiter unten, solange das
-- Fenster offen ist.
LFM.statusText = LFM.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
LFM.statusText:SetPoint("LEFT", LFM.intervalEditBox, "RIGHT", 16, 0)
LFM.statusText:SetWidth(230)
LFM.statusText:SetJustifyH("LEFT")

LFM.toggleBtn = CreateFrame("Button", "BananaLootLFMToggleBtn", LFM.frame, "UIPanelButtonTemplate")
LFM.toggleBtn:SetWidth(120)
LFM.toggleBtn:SetHeight(22)
LFM.toggleBtn:SetPoint("BOTTOM", LFM.frame, "BOTTOM", 0, 16)

LFM.updateToggleButtonText = function()
    if BananaLoot.lfmRunning then
        LFM.toggleBtn:SetText(BananaLoot:L("LFM_BTN_STOP"))
    else
        LFM.toggleBtn:SetText(BananaLoot:L("LFM_BTN_START"))
    end
end

LFM.updateStatusText = function()
    if BananaLoot.lfmRunning then
        local intervalSeconds = BananaLoot:GetLFMIntervalMinutes() * 60
        local last = BananaLoot.lfmLastPostTime or GetTime()
        local remaining = intervalSeconds - (GetTime() - last)
        if remaining < 0 then remaining = 0 end
        LFM.statusText:SetText(string.format(BananaLoot:L("LFM_STATUS_RUNNING"), math.ceil(remaining)))
    else
        LFM.statusText:SetText(BananaLoot:L("LFM_STATUS_STOPPED"))
    end
end

-- Start/Stop auf demselben Button: Beschriftung UND Aktion haengen
-- ausschliesslich von BananaLoot.lfmRunning ab, kein separater Zustand
-- hier im UI noetig.
LFM.toggleBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot.lfmRunning then
        BananaLoot:StopLFM()
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("LFM_STOPPED"))
    else
        local intervalValue = tonumber(LFM.intervalEditBox:GetText())
        if not BananaLoot:SetLFMIntervalMinutes(intervalValue) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("LFM_INTERVAL_INVALID"), 1))
            return
        end
        BananaLoot:SetLFMText(LFM.editBox:GetText())
        local ok = BananaLoot:StartLFM()
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("LFM_NEED_TEXT"))
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("LFM_STARTED"), BananaLoot:GetLFMIntervalMinutes()))
    end
    LFM.updateToggleButtonText()
    LFM.updateStatusText()
end)

function BananaLoot_UI:ShowLFM()
    -- Gespeicherten Text/Intervall aus den SavedVariables vorbefuellen --
    -- bleibt bestehen, bis der Spieler ihn hier aktiv ersetzt (siehe
    -- SetLFMText/SetLFMIntervalMinutes).
    LFM.editBox:SetText(BananaLoot:GetLFMText())
    LFM.intervalEditBox:SetText(tostring(BananaLoot:GetLFMIntervalMinutes()))
    LFM.charCountText:SetText(string.len(LFM.editBox:GetText()) .. " / " .. LFM_MAX_CHARS)
    LFM.updateToggleButtonText()
    LFM.updateStatusText()
    LFM.frame:Show()
end

-- Haelt den Status-/Countdown-Text aktuell, solange das Fenster offen
-- ist. Eigener, einfacher Sekunden-Ticker (wie an mehreren Stellen im
-- Addon ueblich) statt eines Hooks auf den zentralen LFM-Timer in
-- BananaLoot.lua, der bewusst unabhaengig vom UI laeuft.
LFM.ticker = CreateFrame("Frame")
LFM.ticker:SetScript("OnUpdate", function()
    if not LFM.frame:IsShown() then return end
    LFM.windowLastUpdate = LFM.windowLastUpdate + arg1
    if LFM.windowLastUpdate > 1 then
        LFM.windowLastUpdate = 0
        LFM.updateStatusText()
    end
end)

-- Aufgerufen von BananaLoot.lua, falls der Text zwischenzeitlich geleert
-- wurde und PostLFMMessage() den Lauf deshalb selbst beendet hat --
-- haelt Button/Status im UI synchron, auch wenn das Fenster gerade
-- nicht sichtbar ist (dann passiert hier einfach nichts Sichtbares).
function BananaLoot_UI:RefreshLFM()
    if not LFM.frame:IsShown() then return end
    LFM.updateToggleButtonText()
    LFM.updateStatusText()
end

-- ============================================================
-- 3) MINIMAP-BUTTON
-- ============================================================
local mmButton = CreateFrame("Button", "BananaLootMinimapButton", Minimap)
mmButton:SetWidth(31)
mmButton:SetHeight(31)
mmButton:SetFrameStrata("MEDIUM")
mmButton:SetFrameLevel(8)
mmButton:SetToplevel(true)
mmButton:SetMovable(true)
mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mmButton:RegisterForDrag("LeftButton")

local mmIcon = mmButton:CreateTexture(nil, "BACKGROUND")
-- Quadratisch (1:1), passend zur quadratischen Quellgrafik. Kein
-- SetTexCoord -- die Datei enthaelt bereits nur den Kisten-Ausschnitt
-- des Logos, der auch bei 20 px noch lesbar bleibt.
mmIcon:SetWidth(20)
mmIcon:SetHeight(20)
mmIcon:SetPoint("CENTER", mmButton, "CENTER", 0, 0)
mmIcon:SetTexture("Interface\\AddOns\\BananaLoot\\Icons\\BananaLoot_Icon_64")

local mmBorder = mmButton:CreateTexture(nil, "OVERLAY")
mmBorder:SetWidth(54)
mmBorder:SetHeight(54)
mmBorder:SetPoint("TOPLEFT", mmButton, "TOPLEFT", 0, 0)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Position entlang des Minimap-Randes speichern/laden (Winkel in Grad)
local function GetSavedAngle()
    BananaLoot.EnsureDB()
    return BananaLoot_DB.settings.minimapAngle or 200
end

local function SetSavedAngle(angle)
    BananaLoot.EnsureDB()
    BananaLoot_DB.settings.minimapAngle = angle
end

local function UpdateMinimapButtonPosition(angle)
    local radius = 80
    local rad = angle * (math.pi / 180)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

mmButton:SetScript("OnDragStart", function()
    this.dragging = true
end)

mmButton:SetScript("OnDragStop", function()
    this.dragging = false
end)

mmButton:SetScript("OnUpdate", function()
    if this.dragging then
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        UpdateMinimapButtonPosition(angle)
        SetSavedAngle(angle)
    end
end)

mmButton:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if arg1 == "RightButton" then
        BananaLoot_UI:ToggleOptions()
    else
        if BananaLoot_UI and BananaLoot_UI.Toggle then BananaLoot_UI:Toggle() end
    end
end)

mmButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("BananaLoot")
    GameTooltip:AddLine(BananaLoot:L("MM_TOOLTIP_LEFT"), 1, 1, 1)
    GameTooltip:AddLine(BananaLoot:L("MM_TOOLTIP_RIGHT"), 1, 1, 1)
    GameTooltip:AddLine(BananaLoot:L("MM_TOOLTIP_DRAG"), 0.7, 0.7, 0.7)

    -- Übersicht der aktuellen SR-Reservierungen (wer hat was mit wie viel
    -- SR+ gesetzt) -- nützlich um z.B. übersehene Hard-Reserve-Kollisionen
    -- nach einem raidres.top-Import schnell zu erkennen. Nur anzeigen,
    -- wenn es überhaupt Reservierungen gibt.
    local ids = {}
    for id, res in pairs(BananaLoot.reservations) do
        if BananaLoot:CountRealReservers(res) > 0 then table.insert(ids, id) end
    end
    if table.getn(ids) > 0 then
        table.sort(ids)
        local lines = {}
        for i = 1, table.getn(ids) do
            local id = ids[i]
            local res = BananaLoot.reservations[id]
            for p = 1, table.getn(res.order) do
                local name = res.order[p]
                if not (res.temp and res.temp[name]) then
                    local stack = BananaLoot:GetStack(name, id)
                    local bonusTxt = ""
                    if stack > 0 then bonusTxt = " (+" .. (stack * BananaLoot:GetBonusPerStack()) .. ")" end
                    table.insert(lines, BananaLoot:ColoredName(name) .. ": " .. res.link .. bonusTxt)
                end
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(BananaLoot:L("MM_TOOLTIP_SR_HEADER"), 1, 0.82, 0)
        local maxLines = 15
        local shownLines = table.getn(lines)
        if shownLines > maxLines then shownLines = maxLines end
        for i = 1, shownLines do
            GameTooltip:AddLine(lines[i], 1, 1, 1)
        end
        if table.getn(lines) > maxLines then
            GameTooltip:AddLine(string.format(BananaLoot:L("MM_TOOLTIP_SR_MORE"), table.getn(lines) - maxLines), 0.7, 0.7, 0.7)
        end
    end

    GameTooltip:Show()
end)
mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Initiale Position setzen, sobald die Datenbank geladen ist
local mmInitFrame = CreateFrame("Frame")
mmInitFrame:RegisterEvent("PLAYER_LOGIN")
mmInitFrame:SetScript("OnEvent", function()
    UpdateMinimapButtonPosition(GetSavedAngle())
end)

-- ============================================================
-- 4) SPRACHUMSCHALTUNG: Options-/Verwalten-/HR-/Export-/Import-Fenster
-- ============================================================
function BananaLoot_UI:ApplyLocaleExtra()
    -- Alle einfachen Label/Button-Texte laufen über die Registrierungs-
    -- Tabelle (siehe RegisterLocaleText oben) - das hält die Anzahl der
    -- Upvalues dieser Funktion niedrig (Lua 5.0 Limit: 32 pro Funktion).
    for i = 1, table.getn(localeTexts) do
        local entry = localeTexts[i]
        entry.obj:SetText(BananaLoot:L(entry.key))
    end

    -- Dynamische Titel (abhängig vom jeweiligen Fenster) bleiben Einzelfälle.
    exportFrame.titleText:SetText(BananaLoot:L(exportFrame.titleKey))
    importFrame.titleText:SetText(BananaLoot:L(importFrame.titleKey))
    csvResFrame.titleText:SetText(BananaLoot:L(csvResFrame.titleKey))
    csvLogFrame.titleText:SetText(BananaLoot:L(csvLogFrame.titleKey))
    helpFrame.titleText:SetText(BananaLoot:L(helpFrame.titleKey))

    if manageFrame:IsShown() then RefreshManage() end
    if hrFrame:IsShown() then RefreshHRList() end
    if brFrame:IsShown() then RefreshBRList() end
    if helpFrame:IsShown() then BananaLoot_UI:ShowHelp() end
    if recoveryFrame:IsShown() then RefreshRecoveryList() end
    if historyFrame:IsShown() then RefreshHistoryList() end
    if loadRaidFrame:IsShown() then RefreshLoadRaidList() end
    if BananaLoot_UI.RefreshLFM then BananaLoot_UI:RefreshLFM() end

    if StaticPopupDialogs and StaticPopupDialogs["BANANALOOT_CONFIRM_MANUAL_AWARD"] then
        StaticPopupDialogs["BANANALOOT_CONFIRM_MANUAL_AWARD"].text = BananaLoot:L("MG_POPUP_TEXT")
        StaticPopupDialogs["BANANALOOT_CONFIRM_MANUAL_AWARD"].button1 = BananaLoot:L("UI_POPUP_YES")
        StaticPopupDialogs["BANANALOOT_CONFIRM_MANUAL_AWARD"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
    end
    if StaticPopupDialogs and StaticPopupDialogs["BANANALOOT_CONFIRM_RAID_ROLL"] then
        StaticPopupDialogs["BANANALOOT_CONFIRM_RAID_ROLL"].text = BananaLoot:L("MG_RAIDROLL_POPUP_TEXT")
        StaticPopupDialogs["BANANALOOT_CONFIRM_RAID_ROLL"].button1 = BananaLoot:L("UI_POPUP_YES")
        StaticPopupDialogs["BANANALOOT_CONFIRM_RAID_ROLL"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
    end
    if StaticPopupDialogs and StaticPopupDialogs["BANANALOOT_CONFIRM_OVERWRITE_RAID"] then
        StaticPopupDialogs["BANANALOOT_CONFIRM_OVERWRITE_RAID"].text = BananaLoot:L("UI_POPUP_OVERWRITE_RAID_TEXT")
        StaticPopupDialogs["BANANALOOT_CONFIRM_OVERWRITE_RAID"].button1 = BananaLoot:L("UI_POPUP_YES")
        StaticPopupDialogs["BANANALOOT_CONFIRM_OVERWRITE_RAID"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
    end
    if StaticPopupDialogs and StaticPopupDialogs["BANANALOOT_CONFIRM_LOAD_RAID"] then
        StaticPopupDialogs["BANANALOOT_CONFIRM_LOAD_RAID"].text = BananaLoot:L("UI_POPUP_LOAD_RAID_TEXT")
        StaticPopupDialogs["BANANALOOT_CONFIRM_LOAD_RAID"].button1 = BananaLoot:L("UI_POPUP_YES")
        StaticPopupDialogs["BANANALOOT_CONFIRM_LOAD_RAID"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
    end
    if StaticPopupDialogs and StaticPopupDialogs["BANANALOOT_CONFIRM_DELETE_RAID"] then
        StaticPopupDialogs["BANANALOOT_CONFIRM_DELETE_RAID"].text = BananaLoot:L("UI_POPUP_DELETE_RAID_TEXT")
        StaticPopupDialogs["BANANALOOT_CONFIRM_DELETE_RAID"].button1 = BananaLoot:L("UI_POPUP_YES")
        StaticPopupDialogs["BANANALOOT_CONFIRM_DELETE_RAID"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
    end
end

-- Zentraler Einstiegspunkt: aktualisiert ALLE sichtbaren Texte des Addons
-- (Hauptfenster + Options/Verwalten/HR/Export/Import), aufgerufen beim
-- Laden und bei jedem Sprachwechsel im Optionsfenster.
function BananaLoot_UI:ApplyLocaleAll()
    if self.ApplyLocale then self:ApplyLocale() end
    if self.ApplyLocaleExtra then self:ApplyLocaleExtra() end
    if self.ApplyLocaleAlias then self:ApplyLocaleAlias() end
    if self.ApplyLocaleRaid then self:ApplyLocaleRaid() end
    if self.ApplyLocaleRaidlead then self:ApplyLocaleRaidlead() end
    if self.ApplyLocaleStats then self:ApplyLocaleStats() end
    if self.ApplyLocaleTest then self:ApplyLocaleTest() end
end
