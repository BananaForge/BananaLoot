-- BananaLootUI.lua
-- Zwei getrennte, sichtbare Fenster fuer den Masterlooter:
--   1) SR-Fenster:   dauerhafte Uebersicht aller aktuellen Reservierungen
--                     (aus Whisper sr/unsr und raidres.top/MSRv2-Import).
--                     Erreichbar per /bl bzw. Minimap-Linksklick.
--   2) Loot-Fenster: nur die aktuell im echten Loot-Fenster sichtbaren
--                     Items, mit Roll/ARF/Vergabe. Oeffnet sich automatisch
--                     bei LOOT_OPENED, zusaetzlich per /bl loot erreichbar.
-- Beide Fenster teilen sich Icon-Ladelogik und den periodischen Ticker
-- (Roll-Live-Update, Icon-/Link-Nachlade-Retry), um Code nicht doppelt
-- pflegen zu muessen. Baut das komplette UI in Lua auf (kein XML noetig,
-- dadurch unabhaengig von FrameXML-Eigenheiten des Servers).

BananaLoot_UI = {}

local LOOT_ROW_HEIGHT = 72
local SR_ROW_HEIGHT = 40
local MAX_ROWS = 20
local MAX_PLAYERS_SHOWN = 3 -- vollständige Liste bleibt im "Verwalten"-Fenster einsehbar

local lootRows = {}
local srRows = {}
local pendingIcons = {} -- [itemID] = Anzahl bisheriger Versuche (fensterübergreifend, ID-basiert)
local pendingLinks = {} -- [itemID] = Anzahl bisheriger Versuche, solange nur ein roher "item:ID:..."-Platzhalter bekannt ist

-- Extrahiert aus einem vollen Chat-Hyperlink (|cffxxxxxx|Hitem:ID:...|h[Name]|h|r)
-- nur den reinen "item:ID:..."-Teil ohne Farbcode/Klammern. SetHyperlink()
-- wirft auf diesem Server-Core einen "Unknown link type"-Fehler, wenn ihm
-- der komplette farbcodierte Link übergeben wird -- der rohe item:-String
-- funktioniert dagegen zuverlässig.
local function GetRawItemString(link)
    if not link then return nil end
    local _, _, raw = string.find(link, "item:([%d:%-]+)")
    if raw then return "item:" .. raw end
    return nil
end

-- Sucht das Item in den eigenen Taschen (Bag 0-4) und liefert dessen
-- Icon-Textur direkt über die Bag-API. Zuverlässiger als GetItemInfo/
-- GetItemIcon mit reiner numerischer ID (auf diesem Server unzuverlässig,
-- siehe Kommentar weiter unten) - wenn das Item im Inventar liegt (z.B.
-- Ziel von /bl arf [Item]), ist die Bag-API die "Wahrheit" und braucht
-- keine Serverabfrage.
local function GetBagIconForItem(itemID)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, id = string.find(link, "item:(%d+)")
                    if id and tonumber(id) == itemID then
                        local texture = GetContainerItemInfo(bag, slot)
                        if type(texture) == "string" and texture ~= "" then
                            return texture
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Ermittelt best-effort ein Icon fuer eine Item-ID (siehe Prioritaeten-
-- Kommentar innerhalb der Funktion) und traegt die ID ggf. in pendingIcons
-- ein, damit der Ticker es spaeter erneut versucht. Gemeinsame Logik fuer
-- beide Fenster, damit sich das Verhalten nicht auseinanderentwickelt.
local function ResolveRowIcon(id)
    -- WICHTIG: GetItemInfo() mit der reinen numerischen ID ist auf diesem
    -- Server unzuverlässig (liefert oft nutzlose/leere Werte zurück) --
    -- der reine "item:ID:..."-String funktioniert dagegen zuverlässig.
    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo("item:" .. id .. ":0:0:0:0:0:0:0")
    local cachedLootIcon = BananaLoot.knownLootIcons[id]
    local bagIcon = GetBagIconForItem(id)
    local staticInfo = BananaLoot:GetStaticItemInfo(id)
    local staticIcon = staticInfo and staticInfo.icon or nil
    local iconFromDedicatedApi = nil
    if GetItemIcon then
        local ok, result = pcall(GetItemIcon, "item:" .. id .. ":0:0:0:0:0:0:0")
        if ok then iconFromDedicatedApi = result end
    end

    local texture = nil
    if type(cachedLootIcon) == "string" and cachedLootIcon ~= "" then
        texture = cachedLootIcon
    elseif type(bagIcon) == "string" and bagIcon ~= "" then
        texture = bagIcon
    elseif type(staticIcon) == "string" and staticIcon ~= "" then
        texture = "Interface\\Icons\\" .. staticIcon
    elseif type(iconFromDedicatedApi) == "string" and iconFromDedicatedApi ~= "" then
        texture = iconFromDedicatedApi
    elseif type(itemTexture) == "string" and itemTexture ~= "" then
        texture = itemTexture
    end

    if texture then
        pendingIcons[id] = nil
        return texture
    end

    if pendingIcons[id] == nil then
        pendingIcons[id] = 0
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Baut den Anzeige-Text (farbig, mit Platzhalter-Fallback) fuer ein Item
-- und merkt rohe Platzhalter-Links fuer den Link-Retry im Ticker vor.
-- Gemeinsame Logik fuer beide Fenster.
local function ResolveDisplayText(id, link)
    if link and not string.find(link, "|Hitem:") and string.find(link, "^item:") then
        if pendingLinks[id] == nil then
            pendingLinks[id] = 0
        end
        return "|cff" .. BananaLoot:GetQualityColorHex(id) .. "Item #" .. id .. "|r"
    end
    return link
end

-- Hinterlegt den Tooltip-Handler auf dem unsichtbaren iconFrame einer Zeile.
-- Texturen können in der WoW-API keine Maus-Events empfangen, daher ein
-- unsichtbares Frame exakt über dem Icon, das Hover abfängt und den
-- Item-Tooltip zeigt (identisch zum Verhalten im echten Loot-Fenster).
local function AttachIconTooltip(row)
    row.iconFrame:SetScript("OnEnter", function()
        -- Nur echte Item-Links an SetHyperlink übergeben (Fallback-Anzeigen
        -- ohne bekannten Link, z.B. "Item 12345", sind kein gültiger Link).
        if row.currentLink and string.find(row.currentLink, "|Hitem:") then
            GameTooltip:SetOwner(row.iconFrame, "ANCHOR_RIGHT")
            -- SetHyperlink erwartet auf diesem Server-Core den reinen
            -- "item:ID:..."-String OHNE Farbcode/Klammern -- der komplette
            -- Chat-Link (|cffxxxxxx|Hitem:...|h[Name]|h|r) führt hier zu
            -- "Unknown link type". Zusätzlich per pcall abgesichert, falls
            -- andere Addons trotzdem noch einen Hook auf GameTooltip legen.
            local rawItemString = GetRawItemString(row.currentLink)
            if rawItemString then
                pcall(function() GameTooltip:SetHyperlink(rawItemString) end)
            end
            GameTooltip:Show()
        end
    end)
    row.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ============================================================
-- 1) SR-FENSTER: dauerhafte Uebersicht aller aktuellen Reservierungen
-- ============================================================
local srFrame = CreateFrame("Frame", "BananaLootSRFrame", UIParent)
srFrame:SetWidth(460)
srFrame:SetHeight(530)
srFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
srFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
srFrame:SetMovable(true)
srFrame:EnableMouse(true)
srFrame:RegisterForDrag("LeftButton")
srFrame:SetScript("OnDragStart", function() srFrame:StartMoving() end)
srFrame:SetScript("OnDragStop", function() srFrame:StopMovingOrSizing() end)
srFrame:SetFrameStrata("HIGH")
srFrame:Hide()

local srTitleIcon = srFrame:CreateTexture(nil, "ARTWORK")
-- Quadratisch (1:1), passend zur quadratischen Quellgrafik. Die Datei
-- enthaelt nur den Kisten-Ausschnitt des Logos (ohne Schriftzug), daher
-- kein SetTexCoord noetig -- und vor allem keine 4:3-Masse mehr, die
-- das Bild stauchen wuerden.
srTitleIcon:SetWidth(32)
srTitleIcon:SetHeight(32)
srTitleIcon:SetPoint("TOPLEFT", srFrame, "TOPLEFT", 24, -18)
srTitleIcon:SetTexture("Interface\\AddOns\\BananaLoot\\Icons\\BananaLoot_Icon_64")

-- Titel wird rechts NEBEN dem (jetzt größeren) Icon verankert statt
-- mittig im Fenster -- so bleibt garantiert Platz zu den Buttons oben
-- rechts (Schließen/?/BR/HR), unabhängig von der genauen Pixelbreite
-- des Titeltexts (vorher überdeckte z.B. das "+" am Ende von "SR+"
-- teilweise den HR-Button).
local srTitle = srFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
srTitle:SetText(BananaLoot:L("UI_TITLE"))
srTitle:SetPoint("LEFT", srTitleIcon, "RIGHT", 8, 0)

-- Name des aktuell gespeicherten/geladenen Raids (siehe /bl-Buttons
-- "Raid speichern"/"Raid laden"), rein informative Überschrift. Bleibt
-- leer, solange noch nie gespeichert/geladen wurde. Text wird in
-- BananaLoot_UI:RefreshSR() aktuell gehalten.
local srRaidNameText = srFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
srRaidNameText:SetPoint("TOP", srFrame, "TOP", 0, -62)
srRaidNameText:SetText("")

local srCloseBtn = CreateFrame("Button", "BananaLootSRFrameCloseButton", srFrame, "UIPanelCloseButton")
srCloseBtn:SetPoint("TOPRIGHT", srFrame, "TOPRIGHT", -6, -6)
srCloseBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

-- Kleiner Hilfe-Button ("?"): öffnet die Befehlsübersicht (BananaLoot_UI:
-- ShowHelp, definiert in BananaLootExtra.lua). Bewusst hier im SR-Fenster
-- statt in den Optionen, damit man auch mitten im Loot-Prozess schnell
-- reinschauen kann, ohne extra die Optionen öffnen zu müssen.
local srHelpBtn = CreateFrame("Button", "BananaLootSRHelpBtn", srFrame, "UIPanelButtonTemplate")
srHelpBtn:SetWidth(20)
srHelpBtn:SetHeight(20)
srHelpBtn:SetPoint("TOPRIGHT", srFrame, "TOPRIGHT", -30, -6)
srHelpBtn:SetText("?")
srHelpBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ShowHelp()
end)
srHelpBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(srHelpBtn, "ANCHOR_LEFT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_HELP_TOOLTIP"))
    GameTooltip:Show()
end)
srHelpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local srBRBtn = CreateFrame("Button", "BananaLootSRBRBtn", srFrame, "UIPanelButtonTemplate")
srBRBtn:SetWidth(26)
srBRBtn:SetHeight(20)
srBRBtn:SetPoint("RIGHT", srHelpBtn, "LEFT", -4, 0)
srBRBtn:SetText("BR")
srBRBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ShowBRList then BananaLoot_UI:ShowBRList() end
end)
srBRBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(srBRBtn, "ANCHOR_LEFT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_BR_TOOLTIP"))
    GameTooltip:Show()
end)
srBRBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local srHRBtn = CreateFrame("Button", "BananaLootSRHRBtn", srFrame, "UIPanelButtonTemplate")
srHRBtn:SetWidth(26)
srHRBtn:SetHeight(20)
srHRBtn:SetPoint("RIGHT", srBRBtn, "LEFT", -4, 0)
srHRBtn:SetText("HR")
srHRBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ShowHRList then BananaLoot_UI:ShowHRList() end
end)
srHRBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(srHRBtn, "ANCHOR_LEFT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_HR_TOOLTIP"))
    GameTooltip:Show()
end)
srHRBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ------------------------------------------------------------
-- Kopfzeile: Hinweistext + Steuerbuttons (Export/Import/Optionen/Lock/
-- Loot-Fenster oeffnen) -- alles, was die SR-Liste als Ganzes betrifft.
-- ------------------------------------------------------------
local srHint = srFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
srHint:SetPoint("TOPLEFT", srFrame, "TOPLEFT", 20, -80)
srHint:SetText(BananaLoot:L("UI_HINT"))

local exportBtn = CreateFrame("Button", "BananaLootExportBtn", srFrame, "UIPanelButtonTemplate")
exportBtn:SetWidth(90)
exportBtn:SetHeight(20)
exportBtn:SetPoint("TOPLEFT", srFrame, "TOPLEFT", 20, -100)
exportBtn:SetText(BananaLoot:L("UI_BTN_EXPORT"))
exportBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ShowExport()
end)

local importBtn = CreateFrame("Button", "BananaLootImportBtn", srFrame, "UIPanelButtonTemplate")
importBtn:SetWidth(90)
importBtn:SetHeight(20)
importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
importBtn:SetText(BananaLoot:L("UI_BTN_IMPORT"))
importBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ShowImport()
end)

local optionsBtn = CreateFrame("Button", "BananaLootOptionsBtn", srFrame, "UIPanelButtonTemplate")
optionsBtn:SetWidth(90)
optionsBtn:SetHeight(20)
optionsBtn:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)
optionsBtn:SetText(BananaLoot:L("UI_BTN_OPTIONS"))
optionsBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot_UI:ToggleOptions()
end)

-- SR-Lock-Button: sperrt/entsperrt Whisper-Reservierungen (sr/unsr) für die
-- Dauer des Raids, ohne die manuelle Bearbeitung im "Verwalten"-Fenster
-- einzuschränken. Textbasiert über UIPanelButtonTemplate (wie alle anderen
-- Buttons) statt eigener Icon-Texturen -- Blizzards LockButton-Texturen
-- waren auf diesem Server-Client nicht zuverlässig sichtbar.
local lockBtn = CreateFrame("Button", "BananaLootLockBtn", srFrame, "UIPanelButtonTemplate")
lockBtn:SetWidth(76)
lockBtn:SetHeight(20)
lockBtn:SetPoint("LEFT", optionsBtn, "RIGHT", 6, 0)

local function UpdateLockButtonText()
    if BananaLoot:GetSRLocked() then
        lockBtn:SetText(BananaLoot:L("UI_BTN_LOCK_LOCKED"))
    else
        lockBtn:SetText(BananaLoot:L("UI_BTN_LOCK_UNLOCKED"))
    end
end
UpdateLockButtonText()

lockBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local newState = not BananaLoot:GetSRLocked()
    BananaLoot:SetSRLocked(newState)
    UpdateLockButtonText()
    if newState then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("SR_LOCK_ON"))
    else
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("SR_LOCK_OFF"))
    end
end)

lockBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(lockBtn, "ANCHOR_RIGHT")
    if BananaLoot:GetSRLocked() then
        GameTooltip:SetText(BananaLoot:L("UI_BTN_LOCK_TOOLTIP_LOCKED"))
    else
        GameTooltip:SetText(BananaLoot:L("UI_BTN_LOCK_TOOLTIP_UNLOCKED"))
    end
    GameTooltip:Show()
end)
lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ML/GL-Mini-Button: wechselt die eigentliche WoW-Loot-Methode zwischen
-- Masterloot (du selbst) und Gruppenloot mit einem Klick, ohne den Umweg
-- über das Blizzard-Raidoptionen-Menü. Funktioniert nur als Gruppen-/
-- Raidleiter (native Einschränkung von SetLootMethod), ansonsten bleibt
-- die Loot-Methode unverändert, egal wie oft geklickt wird.
local lootMethodBtn = CreateFrame("Button", "BananaLootLootMethodBtn", srFrame, "UIPanelButtonTemplate")
lootMethodBtn:SetWidth(34)
lootMethodBtn:SetHeight(20)
lootMethodBtn:SetPoint("LEFT", lockBtn, "RIGHT", 6, 0)

local function UpdateLootMethodButtonText()
    local ok, method = pcall(GetLootMethod)
    if ok and method == "master" then
        lootMethodBtn:SetText("ML")
    else
        lootMethodBtn:SetText("GL")
    end
end
UpdateLootMethodButtonText()

lootMethodBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local ok, method = pcall(GetLootMethod)
    if ok and method == "master" then
        SetLootMethod("group")
    else
        SetLootMethod("master", UnitName("player"))
    end
    -- GetLootMethod() spiegelt eine Serveränderung nicht zwingend im
    -- selben Frame wider -- optimistisches Update hier, zusätzlich per
    -- PARTY_LOOT_METHOD_CHANGED-Event unten nochmal abgesichert.
    UpdateLootMethodButtonText()
end)

lootMethodBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(lootMethodBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_LOOTMETHOD_TOOLTIP"))
    GameTooltip:Show()
end)
lootMethodBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local lootMethodEventFrame = CreateFrame("Frame")
lootMethodEventFrame:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
lootMethodEventFrame:SetScript("OnEvent", function()
    UpdateLootMethodButtonText()
end)

-- Button, um das separate Loot-Fenster manuell zu oeffnen/schliessen
-- (es oeffnet sich zusaetzlich automatisch bei LOOT_OPENED, siehe
-- BananaLoot:OnLootOpened -> BananaLoot_UI:ShowLoot()).
local openLootBtn = CreateFrame("Button", "BananaLootOpenLootBtn", srFrame, "UIPanelButtonTemplate")
openLootBtn:SetWidth(120)
openLootBtn:SetHeight(20)
-- Eigene zweite Zeile statt an lockBtn angehängt: die erste Zeile
-- (Export/Import/Optionen/Lock/ML-GL) war mit weiteren Buttons in
-- gleicher Breite bereits zu breit fürs 460px-Fenster und ragte über
-- den Rand hinaus. Zweite Zeile vermeidet das unabhängig von der
-- Textlänge in beiden Sprachen.
openLootBtn:SetPoint("TOPLEFT", srFrame, "TOPLEFT", 20, -124)
openLootBtn:SetText(BananaLoot:L("UI_BTN_OPEN_LOOT"))
openLootBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ToggleLoot then BananaLoot_UI:ToggleLoot() end
end)
openLootBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(openLootBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_OPEN_LOOT_TOOLTIP"))
    GameTooltip:Show()
end)
openLootBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Raid speichern/laden (siehe BananaLootExtra.lua für die zugehörigen
-- Fenster BananaLoot_UI:ShowSaveRaid()/ShowLoadRaidList()) -- in
-- derselben zweiten Zeile wie "Loot-Fenster", passt bequem hinein.
local saveRaidBtn = CreateFrame("Button", "BananaLootSaveRaidBtn", srFrame, "UIPanelButtonTemplate")
saveRaidBtn:SetWidth(110)
saveRaidBtn:SetHeight(20)
saveRaidBtn:SetPoint("LEFT", openLootBtn, "RIGHT", 6, 0)
saveRaidBtn:SetText(BananaLoot:L("UI_BTN_SAVE_RAID"))
saveRaidBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ShowSaveRaid then BananaLoot_UI:ShowSaveRaid() end
end)

local loadRaidBtn = CreateFrame("Button", "BananaLootLoadRaidBtn", srFrame, "UIPanelButtonTemplate")
loadRaidBtn:SetWidth(110)
loadRaidBtn:SetHeight(20)
loadRaidBtn:SetPoint("LEFT", saveRaidBtn, "RIGHT", 6, 0)
loadRaidBtn:SetText(BananaLoot:L("UI_BTN_LOAD_RAID"))
loadRaidBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ShowLoadRaidList then BananaLoot_UI:ShowLoadRaidList() end
end)

-- Quick-Access fuer das LFM-Fenster (siehe BananaLootExtra.lua), damit
-- man nicht zwingend "/bl lfm" tippen muss. Gleiche Zeile wie Loot-
-- Fenster/Raid speichern/Raid laden, noch knapp Platz vorhanden.
local lfmQuickBtn = CreateFrame("Button", "BananaLootLFMQuickBtn", srFrame, "UIPanelButtonTemplate")
lfmQuickBtn:SetWidth(50)
lfmQuickBtn:SetHeight(20)
lfmQuickBtn:SetPoint("LEFT", loadRaidBtn, "RIGHT", 6, 0)
lfmQuickBtn:SetText("LFM")
lfmQuickBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI.ShowLFM then BananaLoot_UI:ShowLFM() end
end)
lfmQuickBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(lfmQuickBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_LFM_TOOLTIP"))
    GameTooltip:Show()
end)
lfmQuickBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Hinweis: "Neuer Raid", "SR+ komplett leeren", CSV-Export und "Log leeren"
-- wurden ins Optionsfenster verschoben (Aufräumen des Hauptfensters) -
-- diese Aktionen werden selten benötigt (meist nur vor/nach dem Raid).
-- Die zugehörigen StaticPopup-Bestätigungsdialoge bleiben hier definiert,
-- da sie unabhängig davon sind, wo die auslösenden Buttons liegen.

-- Bestätigungsdialog für "Neuer Raid" (nur falls StaticPopup verfügbar)
if StaticPopupDialogs then
    StaticPopupDialogs["BANANALOOT_CONFIRM_RESET"] = {
        text = BananaLoot:L("UI_POPUP_RESET_TEXT"),
        button1 = BananaLoot:L("UI_POPUP_YES"),
        button2 = BananaLoot:L("UI_POPUP_CANCEL"),
        OnAccept = function()
            BananaLoot:ClearAllReservations()
            BananaLoot_UI:Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["BANANALOOT_CONFIRM_WIPE"] = {
        text = BananaLoot:L("UI_POPUP_WIPE_TEXT"),
        button1 = BananaLoot:L("UI_POPUP_WIPE_YES"),
        button2 = BananaLoot:L("UI_POPUP_CANCEL"),
        OnAccept = function()
            BananaLoot.EnsureDB()
            BananaLoot_DB.players = {}
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("CMD_WIPE_DONE"))
            BananaLoot_UI:Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- ------------------------------------------------------------
-- Scroll-Bereich mit den SR-Zeilen
-- ------------------------------------------------------------
local srOverflowText = srFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
srOverflowText:SetPoint("BOTTOM", srFrame, "BOTTOM", 0, 4)
srOverflowText:SetText("")

local srScrollFrame = CreateFrame("ScrollFrame", "BananaLootSRScrollFrame", srFrame, "UIPanelScrollFrameTemplate")
srScrollFrame:SetPoint("TOPLEFT", srFrame, "TOPLEFT", 20, -150)
srScrollFrame:SetPoint("BOTTOMRIGHT", srFrame, "BOTTOMRIGHT", -34, 20)

local srScrollChild = CreateFrame("Frame", "BananaLootSRScrollChild", srScrollFrame)
srScrollChild:SetWidth(400)
srScrollChild:SetHeight(1) -- wird dynamisch angepasst
srScrollFrame:SetScrollChild(srScrollChild)

-- Zeilen-Erzeugung (Pool, wiederverwendet). Schlanker als die Loot-Zeile:
-- kein Status/Roll/ARF/Award noetig, da hier nur die reine Reservierung
-- angezeigt wird, keine aktive Loot-Vergabe.
local function CreateSRRow(index)
    local row = CreateFrame("Frame", "BananaLootSRRow" .. index, srScrollChild)
    row:SetWidth(400)
    row:SetHeight(SR_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", srScrollChild, "TOPLEFT", 0, -(index - 1) * SR_ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(0, 0, 0, 0.15)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(22)
    row.icon:SetHeight(22)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)

    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetWidth(22)
    row.iconFrame:SetHeight(22)
    row.iconFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    row.iconFrame:EnableMouse(true)
    AttachIconTooltip(row)

    row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.itemText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
    row.itemText:SetJustifyH("LEFT")
    row.itemText:SetWidth(250)

    row.manageBtn = CreateFrame("Button", "BananaLootSRRow" .. index .. "ManageBtn", row, "UIPanelButtonTemplate")
    row.manageBtn:SetWidth(74)
    row.manageBtn:SetHeight(16)
    row.manageBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -3)
    row.manageBtn:SetText(BananaLoot:L("UI_BTN_MANAGE"))

    row.playersText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.playersText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -18)
    row.playersText:SetJustifyH("LEFT")
    row.playersText:SetWidth(266)
    row.playersText:SetHeight(12)

    return row
end

for i = 1, MAX_ROWS do
    srRows[i] = CreateSRRow(i)
    srRows[i]:Hide()
end

-- ------------------------------------------------------------
-- RefreshSR: baut die Liste ausschliesslich aus BananaLoot.reservations
-- neu auf (Items mit mindestens einem Reservierer). Der aktuelle Loot-
-- Status (knownLootItems) spielt hier bewusst KEINE Rolle mehr, siehe
-- RefreshLoot fuer das separate Loot-Fenster.
-- ------------------------------------------------------------
function BananaLoot_UI:RefreshSR()
    srRaidNameText:SetText(BananaLoot:GetCurrentRaidName() or "")
    UpdateLootMethodButtonText()

    local ids = {}
    for id, res in pairs(BananaLoot.reservations) do
        if table.getn(res.order) > 0 then
            table.insert(ids, id)
        end
    end
    table.sort(ids)

    if table.getn(ids) > MAX_ROWS then
        srOverflowText:SetText(string.format(BananaLoot:L("UI_OVERFLOW"), table.getn(ids) - MAX_ROWS, MAX_ROWS))
    else
        srOverflowText:SetText("")
    end

    local shown = 0
    for i = 1, table.getn(ids) do
        local id = ids[i]
        local res = BananaLoot.reservations[id]
        shown = shown + 1
        if shown > MAX_ROWS then break end

        local row = srRows[shown]
        row.itemID = id
        row:Show()

        row.icon:SetTexture(ResolveRowIcon(id))

        local displayLink = res.link
        row.currentLink = displayLink
        local prettyDisplay = ResolveDisplayText(id, displayLink)
        local tag = BananaLoot:IsHardReserve(id) and BananaLoot:L("UI_TAG_HR") or ""
        row.itemText:SetText(prettyDisplay .. tag)

        row.manageBtn:SetText(BananaLoot:L("UI_BTN_MANAGE"))
        row.manageBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            BananaLoot_UI:ShowManage(id, "sr")
        end)

        local list = ""
        local total = table.getn(res.order)
        local shownPlayers = total
        if shownPlayers > MAX_PLAYERS_SHOWN then shownPlayers = MAX_PLAYERS_SHOWN end
        for p = 1, shownPlayers do
            local name = res.order[p]
            local stack = BananaLoot:GetStack(name, id)
            if stack > 0 then
                list = list .. BananaLoot:ColoredName(name) .. "|cffffcc00(+" .. (stack * BananaLoot:GetBonusPerStack()) .. ")|r"
            else
                list = list .. BananaLoot:ColoredName(name)
            end
            if p < shownPlayers then list = list .. ", " end
        end
        if total > MAX_PLAYERS_SHOWN then
            list = list .. string.format(BananaLoot:L("UI_PLAYERS_MORE"), total - MAX_PLAYERS_SHOWN)
        end
        row.playersText:SetText(list)
    end

    for i = shown + 1, MAX_ROWS do
        srRows[i]:Hide()
    end

    srScrollChild:SetHeight(math.max(1, shown * SR_ROW_HEIGHT))
end

-- ============================================================
-- 2) LOOT-FENSTER: nur die aktuell im echten Loot-Fenster sichtbaren
-- Items, mit Roll/ARF/Vergabe. Oeffnet sich automatisch bei LOOT_OPENED.
-- ============================================================
local lootFrame = CreateFrame("Frame", "BananaLootFrame", UIParent)
lootFrame:SetWidth(460)
lootFrame:SetHeight(526)
lootFrame:SetPoint("CENTER", UIParent, "CENTER", 30, -30)
lootFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
lootFrame:SetMovable(true)
lootFrame:EnableMouse(true)
lootFrame:RegisterForDrag("LeftButton")
lootFrame:SetScript("OnDragStart", function() lootFrame:StartMoving() end)
lootFrame:SetScript("OnDragStop", function() lootFrame:StopMovingOrSizing() end)
lootFrame:SetFrameStrata("HIGH")
lootFrame:Hide()

local lootTitleIcon = lootFrame:CreateTexture(nil, "ARTWORK")
-- Quadratisch (1:1) wie die Quellgrafik, kein SetTexCoord.
lootTitleIcon:SetWidth(18)
lootTitleIcon:SetHeight(18)
lootTitleIcon:SetTexture("Interface\\AddOns\\BananaLoot\\Icons\\BananaLoot_Icon_64")

local lootTitle = lootFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
lootTitle:SetText(BananaLoot:L("UI_TITLE_LOOT"))
lootTitle:SetPoint("TOP", lootFrame, "TOP", 0, -18)

lootTitleIcon:SetPoint("RIGHT", lootTitle, "LEFT", -6, 0)

local lootCloseBtn = CreateFrame("Button", "BananaLootFrameCloseButton", lootFrame, "UIPanelCloseButton")
lootCloseBtn:SetPoint("TOPRIGHT", lootFrame, "TOPRIGHT", -6, -6)
lootCloseBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    this:GetParent():Hide()
end)

-- Auto-Toggle: startet/pausiert den automatischen Loot-Durchlauf (wie
-- /bl auto), ohne dass man den Chat-Befehl tippen muss. Zeigt den
-- aktuellen Zustand als Beschriftung (analog zum Gesperrt/Offen-Button
-- im SR-Fenster) -- Ausschalten bricht einen GERADE laufenden Roll
-- bewusst NICHT ab (siehe Tooltip), dafür bleibt /bl stop zuständig.
local autoToggleBtn = CreateFrame("Button", "BananaLootAutoToggleBtn", lootFrame, "UIPanelButtonTemplate")
autoToggleBtn:SetWidth(100)
autoToggleBtn:SetHeight(20)
autoToggleBtn:SetPoint("TOPLEFT", lootFrame, "TOPLEFT", 20, -50)

local function UpdateAutoToggleButtonText()
    if BananaLoot.autoRunning then
        autoToggleBtn:SetText(BananaLoot:L("UI_BTN_AUTO_ON"))
    else
        autoToggleBtn:SetText(BananaLoot:L("UI_BTN_AUTO_OFF"))
    end
end
UpdateAutoToggleButtonText()

autoToggleBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot.autoRunning then
        BananaLoot.autoRunning = false
    else
        BananaLoot:StartAutoMode()
    end
    UpdateAutoToggleButtonText()
    if BananaLoot_UI and BananaLoot_UI.RefreshLoot then BananaLoot_UI:RefreshLoot() end
end)

autoToggleBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(autoToggleBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_AUTO_TOOLTIP"))
    GameTooltip:Show()
end)
autoToggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Stop-Button: bricht Auto-Modus UND einen gerade laufenden Roll sofort
-- ab (wie /bl stop) -- im Gegensatz zum Auto-Toggle-Button oben, der
-- beim Ausschalten einen laufenden Roll bewusst weiterlaufen lässt.
local stopBtn = CreateFrame("Button", "BananaLootStopBtn", lootFrame, "UIPanelButtonTemplate")
stopBtn:SetWidth(70)
stopBtn:SetHeight(20)
stopBtn:SetPoint("LEFT", autoToggleBtn, "RIGHT", 6, 0)
stopBtn:SetText(BananaLoot:L("UI_BTN_STOP"))
stopBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    BananaLoot:StopAutoMode()
    DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("CMD_STOPPED"))
    UpdateAutoToggleButtonText()
    if BananaLoot_UI and BananaLoot_UI.RefreshLoot then BananaLoot_UI:RefreshLoot() end
end)
stopBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(stopBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText(BananaLoot:L("UI_BTN_STOP_TOOLTIP"))
    GameTooltip:Show()
end)
stopBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ------------------------------------------------------------
-- Scroll-Bereich mit den Loot-Item-Zeilen
-- ------------------------------------------------------------
local lootOverflowText = lootFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lootOverflowText:SetPoint("BOTTOM", lootFrame, "BOTTOM", 0, 4)
lootOverflowText:SetText("")

local lootScrollFrame = CreateFrame("ScrollFrame", "BananaLootScrollFrame", lootFrame, "UIPanelScrollFrameTemplate")
lootScrollFrame:SetPoint("TOPLEFT", lootFrame, "TOPLEFT", 20, -76)
lootScrollFrame:SetPoint("BOTTOMRIGHT", lootFrame, "BOTTOMRIGHT", -34, 20)

local lootScrollChild = CreateFrame("Frame", "BananaLootScrollChild", lootScrollFrame)
lootScrollChild:SetWidth(400)
lootScrollChild:SetHeight(1) -- wird dynamisch angepasst
lootScrollFrame:SetScrollChild(lootScrollChild)

-- ------------------------------------------------------------
-- Zeilen-Erzeugung (Pool, wiederverwendet)
-- ------------------------------------------------------------
local function CreateLootRow(index)
    local row = CreateFrame("Frame", "BananaLootRow" .. index, lootScrollChild)
    row:SetWidth(400)
    row:SetHeight(LOOT_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", lootScrollChild, "TOPLEFT", 0, -(index - 1) * LOOT_ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(0, 0, 0, 0.15)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(22)
    row.icon:SetHeight(22)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)

    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetWidth(22)
    row.iconFrame:SetHeight(22)
    row.iconFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    row.iconFrame:EnableMouse(true)
    AttachIconTooltip(row)

    row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.itemText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
    row.itemText:SetJustifyH("LEFT")
    row.itemText:SetWidth(250)

    row.manageBtn = CreateFrame("Button", "BananaLootRow" .. index .. "ManageBtn", row, "UIPanelButtonTemplate")
    row.manageBtn:SetWidth(74)
    row.manageBtn:SetHeight(16)
    row.manageBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -3)
    row.manageBtn:SetText(BananaLoot:L("UI_BTN_MANAGE"))

    -- Reservierer-Liste: nur eine Zeile, bei vielen Namen trunkiert
    -- ("+N weitere" - die vollständige Liste bleibt über "Verwalten"
    -- weiterhin einsehbar, es geht also keine Information verloren).
    row.playersText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.playersText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -18)
    row.playersText:SetJustifyH("LEFT")
    row.playersText:SetWidth(266)
    row.playersText:SetHeight(12)

    -- Status-Text und Aktions-Buttons teilen sich dieselbe Zeile
    -- (statt jeweils eigener Zeile), das spart die meiste Höhe ein.
    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statusText:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -32)
    row.statusText:SetJustifyH("LEFT")
    row.statusText:SetWidth(190)
    row.statusText:SetHeight(14)

    row.rollBtn = CreateFrame("Button", "BananaLootRow" .. index .. "RollBtn", row, "UIPanelButtonTemplate")
    row.rollBtn:SetWidth(66)
    row.rollBtn:SetHeight(18)
    row.rollBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    row.rollBtn:SetText(BananaLoot:L("UI_BTN_ROLL"))

    row.arfBtn = CreateFrame("Button", "BananaLootRow" .. index .. "ArfBtn", row, "UIPanelButtonTemplate")
    row.arfBtn:SetWidth(40)
    row.arfBtn:SetHeight(18)
    row.arfBtn:SetPoint("RIGHT", row.rollBtn, "LEFT", -4, 0)
    row.arfBtn:SetText(BananaLoot:L("UI_BTN_ARF"))

    row.awardBtn = CreateFrame("Button", "BananaLootRow" .. index .. "AwardBtn", row, "UIPanelButtonTemplate")
    row.awardBtn:SetWidth(70)
    row.awardBtn:SetHeight(18)
    row.awardBtn:SetPoint("RIGHT", row.arfBtn, "LEFT", -4, 0)
    row.awardBtn:SetText(BananaLoot:L("UI_BTN_AWARD"))
    row.awardBtn:Hide()

    -- Gewinner-/Disenchanter-Name: eigene, gut lesbare Zeile links neben
    -- den Buttons (unterste Zeile der Row), damit vor dem Klick auf
    -- "Vergeben"/"Disenchant" klar sichtbar ist, wer das Item bekommt.
    row.winnerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.winnerText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
    row.winnerText:SetJustifyH("LEFT")
    row.winnerText:SetWidth(190)
    row.winnerText:SetHeight(16)

    return row
end

-- Zeigt statt "Vergeben" den "Disenchant"-Button (Item, für das niemand
-- gerollt hat) samt Name des gesetzten Disenchanters.
local function ShowDisenchantButton(row, id)
    local de = BananaLoot:GetDisenchanter()
    if de then
        row.winnerText:SetText(string.format(BananaLoot:L("UI_DE_LABEL"), BananaLoot:ColoredName(de)))
    else
        row.winnerText:SetText(BananaLoot:L("UI_DE_NOT_SET_LABEL"))
    end
    row.awardBtn:SetText(BananaLoot:L("UI_BTN_DISENCHANT"))
    row.awardBtn:SetWidth(84)
    row.awardBtn:Show()
    row.awardBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        BananaLoot:AwardDisenchant(id)
    end)
end

for i = 1, MAX_ROWS do
    lootRows[i] = CreateLootRow(i)
    lootRows[i]:Hide()
end

-- ------------------------------------------------------------
-- RefreshLoot: baut die Liste ausschliesslich aus den aktuell im
-- Loot-Fenster sichtbaren Items (BananaLoot.knownLootItems) neu auf.
-- Reine SR-Reservierungen ohne zugehoerigen Loot erscheinen hier NICHT
-- mehr (siehe RefreshSR fuer das separate SR-Fenster).
-- ------------------------------------------------------------
function BananaLoot_UI:RefreshLoot()
    UpdateAutoToggleButtonText()

    -- Falls gerade ein Loot-Fenster offen ist, Ansicht auf aktuellsten Stand bringen
    if LootFrame and LootFrame:IsShown() then
        BananaLoot:RefreshKnownLootItems()
    end

    local ids = {}
    for id, _ in pairs(BananaLoot.knownLootItems) do
        table.insert(ids, id)
    end
    table.sort(ids)

    if table.getn(ids) > MAX_ROWS then
        lootOverflowText:SetText(string.format(BananaLoot:L("UI_OVERFLOW"), table.getn(ids) - MAX_ROWS, MAX_ROWS))
    else
        lootOverflowText:SetText("")
    end

    local shown = 0
    for i = 1, table.getn(ids) do
        local id = ids[i]
        local res = BananaLoot.reservations[id]
        shown = shown + 1
        if shown > MAX_ROWS then break end

        local row = lootRows[shown]
        row.itemID = id
        row:Show()

        row.icon:SetTexture(ResolveRowIcon(id))

        local displayLink = (res and res.link) or BananaLoot.knownLootItems[id] or ("Item " .. id)
        row.currentLink = displayLink
        local prettyDisplay = ResolveDisplayText(id, displayLink)

        local isHR = BananaLoot:IsHardReserve(id)
        local tag
        if isHR then
            tag = BananaLoot:L("UI_TAG_HR")
        elseif res and table.getn(res.order) > 0 then
            tag = BananaLoot:L("UI_TAG_SR")
        else
            tag = BananaLoot:L("UI_TAG_OPEN")
        end
        local qty = BananaLoot.lootCounts[id]
        local qtyTxt = (qty and qty > 1) and string.format(BananaLoot:L("UI_QTY"), qty) or ""
        row.itemText:SetText(prettyDisplay .. tag .. qtyTxt)

        row.manageBtn:SetText(BananaLoot:L("UI_BTN_MANAGE"))
        row.manageBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            BananaLoot_UI:ShowManage(id, "loot")
        end)

        local list = ""
        if res then
            local total = table.getn(res.order)
            local shownPlayers = total
            if shownPlayers > MAX_PLAYERS_SHOWN then shownPlayers = MAX_PLAYERS_SHOWN end
            for p = 1, shownPlayers do
                local name = res.order[p]
                local stack = BananaLoot:GetStack(name, id)
                if stack > 0 then
                    list = list .. BananaLoot:ColoredName(name) .. "|cffffcc00(+" .. (stack * BananaLoot:GetBonusPerStack()) .. ")|r"
                else
                    list = list .. BananaLoot:ColoredName(name)
                end
                if p < shownPlayers then list = list .. ", " end
            end
            if total > MAX_PLAYERS_SHOWN then
                list = list .. string.format(BananaLoot:L("UI_PLAYERS_MORE"), total - MAX_PLAYERS_SHOWN)
            end
        end
        if list == "" then list = BananaLoot:L("UI_NO_RESERVATIONS") end
        row.playersText:SetText(list)

        -- Status / Roll-Auswertung
        row.statusText:SetText("")
        row.winnerText:SetText("")
        row.awardBtn:SetText(BananaLoot:L("UI_BTN_AWARD"))
        row.awardBtn:SetWidth(70)
        row.awardBtn:Hide()

        if isHR then
            row.statusText:SetText(BananaLoot:L("UI_STATUS_HR"))
            row.rollBtn:Disable()
            row.arfBtn:Disable()
        elseif BananaLoot.activeRoll and BananaLoot.activeRoll.itemID == id then
            if BananaLoot.activeRoll.running then
                local waitSet = BananaLoot.activeRoll.restrictTo or BananaLoot.activeRoll.waitFor
                if waitSet then
                    local pending = ""
                    local pendingCount = 0
                    local pendingShown = 0
                    for n, _ in pairs(waitSet) do
                        if not BananaLoot.activeRoll.rolls[n] then
                            pendingCount = pendingCount + 1
                            if pendingShown < MAX_PLAYERS_SHOWN then
                                pending = pending .. BananaLoot:ColoredName(n) .. " "
                                pendingShown = pendingShown + 1
                            end
                        end
                    end
                    if pendingCount > MAX_PLAYERS_SHOWN then
                        pending = pending .. string.format(BananaLoot:L("UI_PLAYERS_MORE"), pendingCount - MAX_PLAYERS_SHOWN)
                    end
                    if pendingCount > 0 then
                        row.statusText:SetText(string.format(BananaLoot:L("UI_STATUS_WAITING"), pending))
                    else
                        row.statusText:SetText(BananaLoot:L("UI_STATUS_EVALUATING"))
                    end
                else
                    row.statusText:SetText(BananaLoot:L("UI_STATUS_OPEN_TIMEOUT"))
                end
                row.rollBtn:Disable()
                row.arfBtn:Disable()
            else
                local winners = BananaLoot.activeRoll.confirmedWinners or {}
                if table.getn(winners) <= 1 then
                    -- Einzelgewinner (Standardfall, auch bei deaktiviertem
                    -- "Top N gewinnen"): unveraendert wie bisher.
                    local winner, score, roll, pool = BananaLoot.activeRoll.winner, BananaLoot.activeRoll.winnerScore, BananaLoot.activeRoll.winnerRoll, BananaLoot.activeRoll.winnerPool
                    if winner then
                        row.statusText:SetText(string.format(BananaLoot:L("UI_STATUS_WINNER"), pool or "?", BananaLoot:ColoredName(winner), roll, score))
                        if BananaLoot.activeRoll.rrActive then
                            row.statusText:SetText(row.statusText:GetText() .. string.format(BananaLoot:L("UI_STATUS_RR"),
                                BananaLoot.activeRoll.rrWinnerRR or 0, table.getn(BananaLoot.activeRoll.rrExcluded or {})))
                        end
                        row.winnerText:SetText(string.format(BananaLoot:L("UI_WINNER_LABEL"), BananaLoot:ColoredName(winner)))
                        row.awardBtn:Show()
                        row.awardBtn:SetScript("OnClick", function()
                            BananaLoot:PlayClickSound()
                            BananaLoot:AwardItem(id, winner)
                        end)
                    else
                        row.statusText:SetText(BananaLoot:L("UI_STATUS_NOBODY_ROLLED"))
                        ShowDisenchantButton(row, id)
                    end
                else
                    -- Mehrfachdrop ("Top N gewinnen"): jeder Gewinner wird
                    -- einzeln aufgelistet (bereits vergebene grau, der
                    -- naechste noch offene in Klassenfarbe). Der Award-
                    -- Button vergibt pro Klick jeweils den naechsten noch
                    -- offenen Gewinner.
                    local text = ""
                    local nextUnawarded = nil
                    for i = 1, table.getn(winners) do
                        local w = winners[i]
                        if i > 1 then text = text .. ", " end
                        if w.awarded then
                            text = text .. "|cff888888" .. w.name .. " (" .. w.roll .. "/" .. w.score .. ")|r"
                        else
                            text = text .. BananaLoot:ColoredName(w.name) .. " (" .. w.roll .. "/" .. w.score .. ")"
                            if not nextUnawarded then nextUnawarded = w end
                        end
                    end
                    row.statusText:SetText(text)
                    if nextUnawarded then
                        row.winnerText:SetText(string.format(BananaLoot:L("UI_WINNER_LABEL"), BananaLoot:ColoredName(nextUnawarded.name)))
                        row.awardBtn:Show()
                        row.awardBtn:SetText(BananaLoot:L("UI_BTN_AWARD"))
                        local winnerNameForClick = nextUnawarded.name
                        row.awardBtn:SetScript("OnClick", function()
                            BananaLoot:PlayClickSound()
                            BananaLoot:AwardMultiRollWinner(id, winnerNameForClick)
                        end)
                    end
                end
                row.rollBtn:Enable()
                row.rollBtn:SetText(BananaLoot:L("UI_BTN_ROLL"))
                row.arfBtn:Enable()
            end
        else
            -- Auto-Modus: "Niemand hat gerollt" räumt activeRoll weg, der
            -- Merker in noRollItems zeigt trotzdem den Disenchant-Button.
            if BananaLoot.noRollItems[id] then
                row.statusText:SetText(BananaLoot:L("UI_STATUS_NOBODY_ROLLED"))
                ShowDisenchantButton(row, id)
            end
            row.rollBtn:Enable()
            row.rollBtn:SetText(BananaLoot:L("UI_BTN_ROLL"))
            row.arfBtn:Enable()
        end

        row.arfBtn:SetText(BananaLoot:L("UI_BTN_ARF"))
        row.arfBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            BananaLoot:StartRoll(id, nil, true)
            BananaLoot_UI:RefreshLoot()
        end)

        row.rollBtn:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            BananaLoot:StartRoll(id)
            BananaLoot_UI:RefreshLoot()
        end)
    end

    for i = shown + 1, MAX_ROWS do
        lootRows[i]:Hide()
    end

    lootScrollChild:SetHeight(math.max(1, shown * LOOT_ROW_HEIGHT))
end

-- ============================================================
-- 2b) ROLL-SYNC POPUP: kleines, verschiebbares Fenster für Empfänger
-- des Roll-Sync-Broadcasts (siehe BananaLoot:HandleRollSyncMessage in
-- BananaLoot.lua, das hier über BananaLoot_UI:HandleRollSync andockt).
-- Zeigt Item/Modus/Countdown/laufende Rolls live an und erlaubt per
-- MS/OS/TM-Button, direkt daraus zu würfeln (RandomRoll -- derselbe
-- Effekt wie /roll bzw. /roll 1 99/98 von Hand einzutippen; kennt wie
-- ein manueller /roll keine SR-Berechtigung, das prüft weiterhin
-- ausschließlich der Loot-Master lokal).
-- ============================================================
local rollSyncFrame = CreateFrame("Frame", "BananaLootRollSyncFrame", UIParent)
rollSyncFrame:SetWidth(260)
rollSyncFrame:SetHeight(320)
rollSyncFrame:SetPoint("CENTER", UIParent, "CENTER", -260, 0)
rollSyncFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
rollSyncFrame:SetMovable(true)
rollSyncFrame:EnableMouse(true)
rollSyncFrame:RegisterForDrag("LeftButton")
rollSyncFrame:SetScript("OnDragStart", function() rollSyncFrame:StartMoving() end)
rollSyncFrame:SetScript("OnDragStop", function() rollSyncFrame:StopMovingOrSizing() end)
rollSyncFrame:SetFrameStrata("HIGH")
rollSyncFrame:Hide()

local rsCloseBtn = CreateFrame("Button", "BananaLootRollSyncCloseButton", rollSyncFrame, "UIPanelCloseButton")
rsCloseBtn:SetPoint("TOPRIGHT", rollSyncFrame, "TOPRIGHT", -4, -4)
rsCloseBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    rollSyncFrame:Hide()
end)

local rsTitle = rollSyncFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
rsTitle:SetPoint("TOP", rollSyncFrame, "TOP", 0, -12)
rsTitle:SetText(BananaLoot:L("RSWIN_TITLE"))

local rsIcon = rollSyncFrame:CreateTexture(nil, "ARTWORK")
rsIcon:SetWidth(28)
rsIcon:SetHeight(28)
rsIcon:SetPoint("TOPLEFT", rollSyncFrame, "TOPLEFT", 16, -36)

local rsIconFrame = CreateFrame("Frame", nil, rollSyncFrame)
rsIconFrame:SetWidth(28)
rsIconFrame:SetHeight(28)
rsIconFrame:SetPoint("TOPLEFT", rollSyncFrame, "TOPLEFT", 16, -36)
rsIconFrame:EnableMouse(true)
local rsIconRow = { iconFrame = rsIconFrame, currentLink = nil }
AttachIconTooltip(rsIconRow)

local rsItemText = rollSyncFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rsItemText:SetPoint("LEFT", rsIcon, "RIGHT", 8, 0)
rsItemText:SetJustifyH("LEFT")
rsItemText:SetWidth(160)

local rsModeText = rollSyncFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rsModeText:SetPoint("TOPLEFT", rsIcon, "BOTTOMLEFT", 0, -8)

local rsTimeText = rollSyncFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rsTimeText:SetPoint("LEFT", rsModeText, "RIGHT", 12, 0)

local rsStatusText = rollSyncFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rsStatusText:SetPoint("TOPLEFT", rsModeText, "BOTTOMLEFT", 0, -8)
rsStatusText:SetWidth(220)
rsStatusText:SetJustifyH("LEFT")

local rsScroll = CreateFrame("ScrollFrame", "BananaLootRollSyncScroll", rollSyncFrame, "UIPanelScrollFrameTemplate")
rsScroll:SetPoint("TOPLEFT", rollSyncFrame, "TOPLEFT", 16, -112)
rsScroll:SetPoint("BOTTOMRIGHT", rollSyncFrame, "BOTTOMRIGHT", -30, 60)

local rsChild = CreateFrame("Frame", "BananaLootRollSyncScrollChild", rsScroll)
rsChild:SetWidth(200)
rsChild:SetHeight(1)
rsScroll:SetScrollChild(rsChild)

local RS_ROW_H = 18
local RS_MAX = 15
local rsRows = {}

local function CreateRSListRow(i)
    local r = CreateFrame("Frame", "BananaLootRollSyncRow" .. i, rsChild)
    r:SetWidth(200)
    r:SetHeight(RS_ROW_H)
    r:SetPoint("TOPLEFT", rsChild, "TOPLEFT", 0, -(i - 1) * RS_ROW_H)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.nameText:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.nameText:SetWidth(130)
    r.nameText:SetJustifyH("LEFT")

    r.valueText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.valueText:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.valueText:SetJustifyH("RIGHT")

    return r
end

for i = 1, RS_MAX do
    rsRows[i] = CreateRSListRow(i)
    rsRows[i]:Hide()
end

local rsOverflowText = rollSyncFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
rsOverflowText:SetPoint("BOTTOM", rollSyncFrame, "BOTTOM", 0, 66)
rsOverflowText:SetText("")

local rsMsBtn = CreateFrame("Button", "BananaLootRollSyncMsBtn", rollSyncFrame, "UIPanelButtonTemplate")
rsMsBtn:SetWidth(60)
rsMsBtn:SetHeight(20)
rsMsBtn:SetPoint("BOTTOMLEFT", rollSyncFrame, "BOTTOMLEFT", 16, 16)
rsMsBtn:SetText(BananaLoot:L("RSWIN_MS_BTN"))
rsMsBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    RandomRoll(1, 100)
end)

local rsOsBtn = CreateFrame("Button", "BananaLootRollSyncOsBtn", rollSyncFrame, "UIPanelButtonTemplate")
rsOsBtn:SetWidth(60)
rsOsBtn:SetHeight(20)
rsOsBtn:SetPoint("LEFT", rsMsBtn, "RIGHT", 6, 0)
rsOsBtn:SetText(BananaLoot:L("RSWIN_OS_BTN"))
rsOsBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    RandomRoll(1, 99)
end)

local rsTmBtn = CreateFrame("Button", "BananaLootRollSyncTmBtn", rollSyncFrame, "UIPanelButtonTemplate")
rsTmBtn:SetWidth(60)
rsTmBtn:SetHeight(20)
rsTmBtn:SetPoint("LEFT", rsOsBtn, "RIGHT", 6, 0)
rsTmBtn:SetText(BananaLoot:L("RSWIN_TM_BTN"))
rsTmBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    RandomRoll(1, 98)
end)

-- rollSyncState.itemID/duration/mode/startTime kommen 1:1 aus der RS-
-- Nachricht (siehe Protokoll-Kommentar in BananaLoot.lua). rolls ist
-- rein lokal aufgebaut aus den eingehenden RU-Nachrichten.
local rollSyncState = {
    active = false,
    itemID = nil,
    mode = 0,
    duration = 0,
    startTime = 0,
    resolved = false,
    tie = false,
    winner = nil, winnerScore = nil, winnerRoll = nil, winnerPoolCode = nil,
    rolls = {},
    hideAt = nil,
}

-- Baut Icon + farbcodierten Anzeigetext direkt aus der itemID auf --
-- es wird bewusst kein Item-Link mitgesendet (siehe Roll-Sync-
-- Protokollkommentar), daher dieselbe Fallback-Kette wie überall sonst
-- im Addon: statische Item-DB zuerst (kein Serverwarten nötig), dann
-- GetItemInfo als letzter Versuch, sonst Platzhalter "Item #ID".
local function ResolveRollSyncItemDisplay(itemID)
    local icon = ResolveRowIcon(itemID)
    local link = nil
    local staticInfo = BananaLoot:GetStaticItemInfo(itemID)
    if staticInfo and staticInfo.name then
        link = BananaLoot:BuildItemLink(itemID, staticInfo.name)
    else
        local itemName = GetItemInfo("item:" .. itemID .. ":0:0:0:0:0:0:0")
        if itemName then
            link = BananaLoot:BuildItemLink(itemID, itemName)
        end
    end
    local display = link or ("|cff" .. BananaLoot:GetQualityColorHex(itemID) .. "Item #" .. itemID .. "|r")
    return icon, link, display
end

local function RefreshRollSyncPopup()
    if not rollSyncState.active then return end

    local icon, link, display = ResolveRollSyncItemDisplay(rollSyncState.itemID)
    rsIcon:SetTexture(icon)
    rsIconRow.currentLink = link
    rsItemText:SetText(display)

    local modeText
    if rollSyncState.mode == 1 then modeText = BananaLoot:L("RSWIN_MODE_SR")
    elseif rollSyncState.mode == 2 then modeText = BananaLoot:L("RSWIN_MODE_ARF")
    else modeText = BananaLoot:L("RSWIN_MODE_OPEN") end
    rsModeText:SetText(modeText)

    if rollSyncState.resolved then
        rsTimeText:SetText("")
    else
        local remaining = rollSyncState.duration - (GetTime() - rollSyncState.startTime)
        if remaining < 0 then remaining = 0 end
        rsTimeText:SetText(string.format(BananaLoot:L("RSWIN_TIME_LEFT"), math.ceil(remaining)))
    end

    if rollSyncState.resolved then
        rsStatusText:SetText(string.format(BananaLoot:L("RSWIN_WINNER"), BananaLoot:ColoredName(rollSyncState.winner), rollSyncState.winnerRoll, rollSyncState.winnerScore))
        rsMsBtn:Disable()
        rsOsBtn:Disable()
        rsTmBtn:Disable()
    elseif rollSyncState.tie then
        rsStatusText:SetText(BananaLoot:L("RSWIN_TIE"))
        rsMsBtn:Enable()
        rsOsBtn:Enable()
        rsTmBtn:Enable()
    else
        rsStatusText:SetText("")
        rsMsBtn:Enable()
        rsOsBtn:Enable()
        rsTmBtn:Enable()
    end

    -- Sortierung: Pool-Priorität zuerst (Hauptspec schlägt Off-Spec
    -- schlägt Transmog, exakt wie in EvaluatePool/ResolveActiveRoll),
    -- erst innerhalb derselben Kategorie nach Wurf-Wert absteigend.
    -- Rein numerisch zu sortieren wäre irreführend: ein hoher Off-Spec-
    -- Wurf sähe sonst wie der Gewinner aus, obwohl ein niedrigerer
    -- Hauptspec-Wurf ihn immer schlägt.
    local POOL_SYNC_PRIORITY = { ms = 1, os = 2, tmog = 3 }
    local names = {}
    -- Round Robin (nur wenn der Loot-Master RR-Stufen mitsendet): niedrigste
    -- RR unter den MS-Wuerfen gewinnt, Wuerfe mit hoeherer RR sind "nicht gewertet".
    local minRR = nil
    for name, entry in pairs(rollSyncState.rolls) do
        table.insert(names, name)
        if entry.type == "ms" and entry.rr and (not minRR or entry.rr < minRR) then minRR = entry.rr end
    end
    table.sort(names, function(a, b)
        local ea, eb = rollSyncState.rolls[a], rollSyncState.rolls[b]
        local pa = POOL_SYNC_PRIORITY[ea.type] or 9
        local pb = POOL_SYNC_PRIORITY[eb.type] or 9
        if pa ~= pb then return pa < pb end
        if ea.type == "ms" and ea.rr and eb.rr and ea.rr ~= eb.rr then return ea.rr < eb.rr end
        return ea.value > eb.value
    end)

    local anyExcluded = false
    for name, entry in pairs(rollSyncState.rolls) do
        if entry.type == "ms" and entry.rr and minRR and entry.rr > minRR then anyExcluded = true end
    end
    if table.getn(names) > RS_MAX then
        rsOverflowText:SetText(string.format(BananaLoot:L("RSWIN_OVERFLOW"), table.getn(names) - RS_MAX))
    elseif anyExcluded then
        rsOverflowText:SetText(BananaLoot:L("RSWIN_RR_LEGEND"))
    else
        rsOverflowText:SetText("")
    end

    local shown = 0
    for i = 1, table.getn(names) do
        shown = shown + 1
        if shown > RS_MAX then break end
        local name = names[i]
        local entry = rollSyncState.rolls[name]
        local row = rsRows[shown]
        local poolSuffix = ""
        if entry.type == "os" then poolSuffix = " (" .. BananaLoot:L("POOL_OS") .. ")"
        elseif entry.type == "tmog" then poolSuffix = " (" .. BananaLoot:L("POOL_TMOG") .. ")" end
        if entry.type == "ms" and entry.rr and minRR and entry.rr > minRR then
            -- Round Robin: Wurf zaehlt nicht (hoehere RR als der beste MS-Roller)
            row.nameText:SetText("|cff888888" .. name .. "|r")
            row.valueText:SetText("|cff888888" .. tostring(entry.value) .. " RR" .. entry.rr .. "|r |cffff5555X|r")
        else
            row.nameText:SetText(BananaLoot:ColoredName(name))
            local rrTag = ""
            if entry.type == "ms" and entry.rr then rrTag = " |cffffcc00RR" .. entry.rr .. "|r" end
            row.valueText:SetText(tostring(entry.value) .. rrTag .. poolSuffix)
        end
        row:Show()
    end
    for i = shown + 1, RS_MAX do rsRows[i]:Hide() end
    rsChild:SetHeight(math.max(1, shown * RS_ROW_H))

    if shown == 0 then
        rsRows[1].nameText:SetText(BananaLoot:L("RSWIN_NO_ROLLS"))
        rsRows[1].valueText:SetText("")
        rsRows[1]:Show()
    end
end

-- Zentraler Einstiegspunkt, aufgerufen von BananaLoot:HandleRollSyncMessage
-- (BananaLoot.lua) für jede eingehende Roll-Sync-Nachricht.
function BananaLoot_UI:HandleRollSync(msgType, fields, sender)
    if msgType == "RS" then
        rollSyncState.active = true
        rollSyncState.itemID = tonumber(fields[2]) or 0
        rollSyncState.duration = tonumber(fields[3]) or 60
        rollSyncState.mode = tonumber(fields[4]) or 0
        rollSyncState.startTime = GetTime()
        rollSyncState.resolved = false
        rollSyncState.tie = false
        rollSyncState.winner = nil
        rollSyncState.rolls = {}
        rollSyncState.hideAt = nil
        rollSyncFrame:Show()
        RefreshRollSyncPopup()

    elseif msgType == "RU" then
        local itemID = tonumber(fields[2])
        if not rollSyncState.active or itemID ~= rollSyncState.itemID then return end
        rollSyncState.rolls[fields[3]] = { value = tonumber(fields[4]) or 0, type = fields[5], rr = tonumber(fields[6]) }
        RefreshRollSyncPopup()

    elseif msgType == "RT" then
        local itemID = tonumber(fields[2])
        if not rollSyncState.active or itemID ~= rollSyncState.itemID then return end
        rollSyncState.rolls = {}
        rollSyncState.tie = true
        rollSyncState.startTime = GetTime()
        RefreshRollSyncPopup()

    elseif msgType == "RW" then
        local itemID = tonumber(fields[2])
        if not rollSyncState.active or itemID ~= rollSyncState.itemID then return end
        rollSyncState.resolved = true
        rollSyncState.winner = fields[3]
        rollSyncState.winnerScore = tonumber(fields[4]) or 0
        rollSyncState.winnerRoll = tonumber(fields[5]) or 0
        rollSyncState.winnerPoolCode = fields[6]
        rollSyncState.hideAt = GetTime() + 6
        RefreshRollSyncPopup()

    elseif msgType == "RC" then
        local itemID = tonumber(fields[2])
        if not rollSyncState.active or itemID ~= rollSyncState.itemID then return end
        rollSyncState.active = false
        rollSyncFrame:Hide()
    end
end

-- ============================================================
-- 3) GEMEINSAME FUNKTIONEN: Refresh (beide Fenster), Sprachumschaltung,
-- Skalierung, Ticker (Roll-Live-Update + Icon-/Link-Retry).
-- ============================================================

-- Aktualisiert BEIDE Fenster. Bleibt aus Kompatibilitätsgründen unter
-- diesem Namen bestehen, da an vielen Stellen im restlichen Code
-- (BananaLoot.lua, BananaLootExtra.lua) BananaLoot_UI:Refresh() nach
-- jeder Zustandsänderung aufgerufen wird -- so muss dort nichts
-- angepasst werden, welches Fenster im Einzelfall betroffen ist.
function BananaLoot_UI:Refresh()
    self:RefreshLoot()
    self:RefreshSR()
end

-- ------------------------------------------------------------
-- Live-Update während ein Roll-Timer läuft + Icon-/Link-Nachlade-Retry
-- ------------------------------------------------------------
local ticker = CreateFrame("Frame")
local lastUpdate = 0
ticker:SetScript("OnUpdate", function()
    lastUpdate = lastUpdate + arg1
    if lastUpdate > 1 then
        lastUpdate = 0

        if lootFrame:IsShown() then
            if BananaLoot.activeRoll and BananaLoot.activeRoll.running then
                BananaLoot_UI:RefreshLoot()
            end
        end

        if rollSyncFrame:IsShown() then
            if rollSyncState.hideAt and GetTime() >= rollSyncState.hideAt then
                rollSyncFrame:Hide()
                rollSyncState.active = false
            else
                RefreshRollSyncPopup()
            end
        end

        -- Icon-Retry: GetItemInfo() liefert bei erstmalig unbekannten Items
        -- in Vanilla oft nil (asynchrone Serverabfrage) - hier alle paar
        -- Sekunden erneut versuchen, bis der Client die Daten gecacht hat.
        -- String-Form statt nackter Zahl (siehe ResolveRowIcon()).
        local needRefresh = false
        for id, tries in pairs(pendingIcons) do
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo("item:" .. id .. ":0:0:0:0:0:0:0")
            if type(itemTexture) == "string" and itemTexture ~= "" then
                pendingIcons[id] = nil
                needRefresh = true
            elseif tries >= 15 then
                pendingIcons[id] = nil -- aufgeben, bleibt beim Fragezeichen
            else
                pendingIcons[id] = tries + 1
            end
        end

        -- Link-Retry: rohe Platzhalter-Links (raidres.top-Import ohne
        -- Namen, oder unbekannt in der statischen Item-DB) durch den
        -- echten, farbcodierten Item-Link ersetzen, sobald der Client die
        -- Daten kennt. Nach 15 Versuchen aufgeben.
        for id, tries in pairs(pendingLinks) do
            if BananaLoot:TryUpgradeSyntheticLink(id) then
                pendingLinks[id] = nil
                needRefresh = true
            elseif tries >= 15 then
                pendingLinks[id] = nil
            else
                pendingLinks[id] = tries + 1
            end
        end

        if needRefresh then
            if lootFrame:IsShown() then BananaLoot_UI:RefreshLoot() end
            if srFrame:IsShown() then BananaLoot_UI:RefreshSR() end
        end
    end
end)

-- ------------------------------------------------------------
-- Sprachumschaltung: aktualisiert alle statischen Texte beider Fenster
-- ------------------------------------------------------------
function BananaLoot_UI:ApplyLocale()
    srTitle:SetText(BananaLoot:L("UI_TITLE"))
    srHint:SetText(BananaLoot:L("UI_HINT"))
    exportBtn:SetText(BananaLoot:L("UI_BTN_EXPORT"))
    importBtn:SetText(BananaLoot:L("UI_BTN_IMPORT"))
    optionsBtn:SetText(BananaLoot:L("UI_BTN_OPTIONS"))
    openLootBtn:SetText(BananaLoot:L("UI_BTN_OPEN_LOOT"))
    saveRaidBtn:SetText(BananaLoot:L("UI_BTN_SAVE_RAID"))
    loadRaidBtn:SetText(BananaLoot:L("UI_BTN_LOAD_RAID"))
    UpdateLockButtonText()

    lootTitle:SetText(BananaLoot:L("UI_TITLE_LOOT"))
    UpdateAutoToggleButtonText()
    stopBtn:SetText(BananaLoot:L("UI_BTN_STOP"))

    rsTitle:SetText(BananaLoot:L("RSWIN_TITLE"))
    rsMsBtn:SetText(BananaLoot:L("RSWIN_MS_BTN"))
    rsOsBtn:SetText(BananaLoot:L("RSWIN_OS_BTN"))
    rsTmBtn:SetText(BananaLoot:L("RSWIN_TM_BTN"))
    if rollSyncState.active then RefreshRollSyncPopup() end

    if StaticPopupDialogs then
        if StaticPopupDialogs["BANANALOOT_CONFIRM_RESET"] then
            StaticPopupDialogs["BANANALOOT_CONFIRM_RESET"].text = BananaLoot:L("UI_POPUP_RESET_TEXT")
            StaticPopupDialogs["BANANALOOT_CONFIRM_RESET"].button1 = BananaLoot:L("UI_POPUP_YES")
            StaticPopupDialogs["BANANALOOT_CONFIRM_RESET"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
        end
        if StaticPopupDialogs["BANANALOOT_CONFIRM_WIPE"] then
            StaticPopupDialogs["BANANALOOT_CONFIRM_WIPE"].text = BananaLoot:L("UI_POPUP_WIPE_TEXT")
            StaticPopupDialogs["BANANALOOT_CONFIRM_WIPE"].button1 = BananaLoot:L("UI_POPUP_WIPE_YES")
            StaticPopupDialogs["BANANALOOT_CONFIRM_WIPE"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
        end
    end

    if srFrame:IsShown() then BananaLoot_UI:RefreshSR() end
    if lootFrame:IsShown() then BananaLoot_UI:RefreshLoot() end
end

-- ------------------------------------------------------------
-- Skalierung: wendet die in den Optionen eingestellte Fenster-Skalierung
-- auf beide Fenster an (z.B. für kleine Displays). Ein gemeinsamer Wert
-- fuer beide Fenster, um die Optionen nicht unnoetig zu verkomplizieren.
-- ------------------------------------------------------------
function BananaLoot_UI:ApplyScale()
    srFrame:SetScale(BananaLoot:GetUIScale())
    lootFrame:SetScale(BananaLoot:GetLootUIScale())
end

-- ------------------------------------------------------------
-- Öffnen / Schließen: SR-Fenster (dauerhafte Uebersicht, /bl bzw.
-- Minimap-Linksklick) und Loot-Fenster (aktiver Loot, /bl loot).
-- ------------------------------------------------------------
function BananaLoot_UI:Toggle()
    if srFrame:IsShown() then
        srFrame:Hide()
    else
        BananaLoot_UI:ApplyScale()
        BananaLoot_UI:RefreshSR()
        srFrame:Show()
    end
end

function BananaLoot_UI:ToggleLoot()
    if lootFrame:IsShown() then
        lootFrame:Hide()
    else
        BananaLoot_UI:ApplyScale()
        BananaLoot_UI:RefreshLoot()
        lootFrame:Show()
    end
end

-- Zeigt das Loot-Fenster IMMER an (nie togglend/schliessend) -- genutzt
-- fuer das automatische Oeffnen bei LOOT_OPENED (BananaLoot.lua), damit
-- ein bereits offenes Loot-Fenster nicht versehentlich geschlossen wird.
function BananaLoot_UI:ShowLoot()
    BananaLoot_UI:ApplyScale()
    BananaLoot_UI:RefreshLoot()
    lootFrame:Show()
end
