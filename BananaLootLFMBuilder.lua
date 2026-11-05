-- BananaLootLFMBuilder.lua
-- LFM-Assistent: erzeugt den Text fuer die "Looking for More"-Suche im Weltkanal aus einem
-- vorbereiteten Raid und der Auswahl, was gesucht wird (Rolle, Klasse, Spezialisierung).
--
--   - Raid: einer der vorbereiteten Raids (Standard: der im Hauptfenster ausgewaehlte)
--   - Hard-Reserve-Items des Raids werden automatisch in den Text uebernommen (abschaltbar).
--     Im Text stehen sie als [Name]; beim Posten im Weltkanal wird jedes [Name] zu einem
--     ANKLICKBAREN Item-Link (siehe BananaLoot:LFMSubstituteLinks). Die Laenge wird mit den
--     Links gerechnet (ein Link kostet ca. 44 Zeichen mehr) -- es passen deshalb weniger Items.
--   - Gesucht: Tanks / Heiler / DDs per Knopfdruck, ganze Klassen oder einzelne Specs
--   - Live-Vorschau; "Text uebernehmen" fuellt das LFM-Fenster (dort weiter editierbar),
--     "Uebernehmen & LFM starten" postet ausserdem sofort und dann im eingestellten Intervall
--
-- Der erzeugte Text ist IMMER ENGLISCH (der Weltkanal ist englisch), unabhaengig von der
-- Addon-Sprache; nur die Beschriftung der Buttons im Assistenten folgt der Addon-Sprache.
--
-- Der Text wird nach den gewaehlten Kriterien automatisch zusammengesetzt und auf die
-- 255 Zeichen einer Chatzeile gekuerzt (zuerst weniger HR-Items, dann Zusatztexte).
--
-- Lua 5.0: kein #-Operator, kein %-Operator, kein string.gmatch/match.

local MAX_CHARS = 255

-- Klassen und Specs (Vanilla). role: T = Tank, H = Heiler, D = Damage-Dealer
local CLASSES = {
    { key = "WARRIOR", de = "Krieger", en = "Warrior", color = "c79c6e", specs = {
        { de = "Waffen", en = "Arms", role = "D" }, { de = "Furor", en = "Fury", role = "D" },
        { de = "Schutz", en = "Protection", role = "T" } } },
    { key = "PALADIN", de = "Paladin", en = "Paladin", color = "f58cba", specs = {
        { de = "Heilig", en = "Holy", role = "H" }, { de = "Schutz", en = "Protection", role = "T" },
        { de = "Vergeltung", en = "Retribution", role = "D" } } },
    { key = "HUNTER", de = "Jäger", en = "Hunter", color = "abd473", specs = {
        { de = "Tierherrschaft", en = "Beast Mastery", role = "D" },
        { de = "Treffsicherheit", en = "Marksmanship", role = "D" },
        { de = "Überleben", en = "Survival", role = "D" } } },
    { key = "ROGUE", de = "Schurke", en = "Rogue", color = "fff569", specs = {
        { de = "Meucheln", en = "Assassination", role = "D" }, { de = "Kampf", en = "Combat", role = "D" },
        { de = "Täuschung", en = "Subtlety", role = "D" } } },
    { key = "PRIEST", de = "Priester", en = "Priest", color = "ffffff", specs = {
        { de = "Disziplin", en = "Discipline", role = "H" }, { de = "Heilig", en = "Holy", role = "H" },
        { de = "Schatten", en = "Shadow", role = "D" } } },
    { key = "SHAMAN", de = "Schamane", en = "Shaman", color = "0070de", specs = {
        { de = "Elementar", en = "Elemental", role = "D" }, { de = "Verstärkung", en = "Enhancement", role = "D" },
        { de = "Wiederherstellung", en = "Restoration", role = "H" } } },
    { key = "MAGE", de = "Magier", en = "Mage", color = "69ccf0", specs = {
        { de = "Arkan", en = "Arcane", role = "D" }, { de = "Feuer", en = "Fire", role = "D" },
        { de = "Frost", en = "Frost", role = "D" } } },
    { key = "WARLOCK", de = "Hexenmeister", en = "Warlock", color = "9482c9", specs = {
        { de = "Gebrechen", en = "Affliction", role = "D" }, { de = "Dämonologie", en = "Demonology", role = "D" },
        { de = "Zerstörung", en = "Destruction", role = "D" } } },
    { key = "DRUID", de = "Druide", en = "Druid", color = "ff7d0a", specs = {
        { de = "Gleichgewicht", en = "Balance", role = "D" }, { de = "Bär (Tank)", en = "Feral Tank", role = "T" },
        { de = "Katze (DD)", en = "Feral DPS", role = "D" }, { de = "Wiederherstellung", en = "Restoration", role = "H" } } },
}

local ROLE_WORDS = {
    T = { de = "Tanks", en = "Tanks" },
    H = { de = "Heiler", en = "Healers" },
    D = { de = "DDs", en = "DPS" },
}
local ROLE_ORDER = { "T", "H", "D" }

local B = {
    raidIdx = 0,       -- Index in der Liste der vorbereiteten Raids (0 = kein Raid)
    withHR = true,     -- Hard-Reserve-Items in den Text
    sel = {},          -- sel[classIndex][specIndex] = true
    classBtns = {},
    specBtns = {},
    roleBtns = {},
}
BananaLoot_LFMBuilder = B

-- Sprache der Button-Beschriftungen (Addon-Sprache)
local function Lang()
    return (BananaLoot:GetLanguage() == "en") and "en" or "de"
end

-- Sprache und Bausteine des erzeugten Textes: immer Englisch
local TEXT_LANG = "en"
local T_LFM = "LFM %s"
local T_NEED = " - looking for: %s"
local T_HR = " - HR: %s"
local T_SUFFIX = " - /w for invite"
local T_ALL = "all classes and roles"
local T_DEFAULT_RAID = "Raid"

local function IsSel(c, s)
    return B.sel[c] and B.sel[c][s] and true or false
end

local function SetSel(c, s, on)
    if not B.sel[c] then B.sel[c] = {} end
    B.sel[c][s] = on and true or nil
end

-- ============================================================
-- 1) TEXT ERZEUGEN (ohne UI, testbar)
-- ============================================================

-- Waehlt, welche Specs gesucht werden: Rollen-Voreinstellung (alle Specs einer Rolle).
function B.SelectRole(role, on)
    for c = 1, table.getn(CLASSES) do
        for s = 1, table.getn(CLASSES[c].specs) do
            if CLASSES[c].specs[s].role == role then SetSel(c, s, on) end
        end
    end
end

function B.SelectClass(c, on)
    for s = 1, table.getn(CLASSES[c].specs) do SetSel(c, s, on) end
end

function B.SelectAll(on)
    for c = 1, table.getn(CLASSES) do B.SelectClass(c, on) end
end

-- Sind ALLE Specs einer Rolle gewaehlt?
local function RoleFullySelected(role)
    local any = false
    for c = 1, table.getn(CLASSES) do
        for s = 1, table.getn(CLASSES[c].specs) do
            if CLASSES[c].specs[s].role == role then
                any = true
                if not IsSel(c, s) then return false end
            end
        end
    end
    return any
end

-- Beschreibung der Suche, z.B. "Tanks, Heiler, Magier (Feuer/Frost), Schurke".
function B.NeedText()
    local l = TEXT_LANG
    local total, selected = 0, 0
    for c = 1, table.getn(CLASSES) do
        for s = 1, table.getn(CLASSES[c].specs) do
            total = total + 1
            if IsSel(c, s) then selected = selected + 1 end
        end
    end
    if selected == 0 then return nil end
    if selected == total then return T_ALL end

    local parts = {}
    local covered = {}   -- covered[c..":"..s] = true, durch eine voll gewaehlte Rolle abgedeckt
    for r = 1, table.getn(ROLE_ORDER) do
        local role = ROLE_ORDER[r]
        if RoleFullySelected(role) then
            table.insert(parts, ROLE_WORDS[role][l])
            for c = 1, table.getn(CLASSES) do
                for s = 1, table.getn(CLASSES[c].specs) do
                    if CLASSES[c].specs[s].role == role then covered[c .. ":" .. s] = true end
                end
            end
        end
    end
    for c = 1, table.getn(CLASSES) do
        local cls = CLASSES[c]
        local names, count, left = {}, 0, 0
        for s = 1, table.getn(cls.specs) do
            if IsSel(c, s) and not covered[c .. ":" .. s] then
                left = left + 1
                table.insert(names, cls.specs[s][l])
            end
            if IsSel(c, s) then count = count + 1 end
        end
        if left > 0 then
            if count == table.getn(cls.specs) then
                table.insert(parts, cls[l])                       -- ganze Klasse
            else
                table.insert(parts, cls[l] .. " (" .. table.concat(names, "/") .. ")")
            end
        end
    end
    return table.concat(parts, ", ")
end

-- Hard-Reserve-Items eines vorbereiteten Raids (beste Qualitaet zuerst): { {name, id}, ... }
local function HRItems(entry)
    local list = {}
    if entry and entry.hr then
        for id, v in pairs(entry.hr) do
            if v then
                local name, quality = BananaLoot:SetupItemInfo(id)
                table.insert(list, { name = name, id = id, q = quality or 1 })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.q ~= b.q then return a.q > b.q end
        return a.name < b.name
    end)
    return list
end

-- Zeichen, die ein Item-Link mehr braucht als der Klammertext "[Name]":
-- "|cffRRGGBB|Hitem:12345:0:0:0:0:0:0:0|h" + "|h|r" (mit Reserve fuer 6-stellige IDs)
local LINK_OVERHEAD = 44

-- Setzt den LFM-Text zusammen. entry = vorbereiteter Raid (oder nil), withHR = HR-Items nennen.
-- Rueckgabe: Text (mit [Name] fuer Items), links = { [Name] = itemID } der im Text genannten Items.
function BananaLoot:BuildLFMText(entry, needText, withHR)
    local raidName = entry and entry.name or T_DEFAULT_RAID
    local head = string.format(T_LFM, raidName)
    local need = needText and string.format(T_NEED, needText) or ""
    local suffix = T_SUFFIX
    local items = (withHR and entry) and HRItems(entry) or {}

    -- Text + Laenge NACH dem Ersetzen durch Links
    local function compose(nHR, useSuffix, needStr)
        local hr = ""
        local links = {}
        if nHR > 0 then
            local shown = {}
            for i = 1, nHR do
                table.insert(shown, "[" .. items[i].name .. "]")
                links[items[i].name] = items[i].id
            end
            local more = table.getn(items) - nHR
            local s = table.concat(shown, ", ")
            if more > 0 then s = s .. " +" .. more end
            hr = string.format(T_HR, s)
        end
        local text = head .. needStr .. hr .. (useSuffix and suffix or "")
        return text, string.len(text) + nHR * LINK_OVERHEAD, links
    end

    -- zuerst alle HR-Items, dann weniger, dann ohne Zusatztext, zuletzt gekuerzt
    for n = table.getn(items), 0, -1 do
        local t, len, links = compose(n, true, need)
        if len <= MAX_CHARS then return t, links end
    end
    local t, len, links = compose(0, false, need)
    if len <= MAX_CHARS then return t, links end
    return string.sub(t, 1, MAX_CHARS - 3) .. "...", {}
end

function B.CurrentEntry()
    local list = BananaLoot:GetPreparedRaids()
    return list[B.raidIdx]
end

function B.CurrentText()
    local need = B.NeedText()
    local text, links = BananaLoot:BuildLFMText(B.CurrentEntry(), need, B.withHR)
    return text, need, links
end

-- Beim Posten: [Name] -> anklickbarer Item-Link (nur fuer die Items, die der Assistent genannt hat).
function BananaLoot:LFMSubstituteLinks(text)
    BananaLoot.EnsureDB()
    local links = BananaLoot_DB.settings.lfmLinks
    if not links or not text then return text end
    local result = text
    for name, id in pairs(links) do
        local plain = "[" .. name .. "]"
        local a, b = string.find(result, plain, 1, true)
        if a then
            result = string.sub(result, 1, a - 1) .. self:SetupItemLink(id) .. string.sub(result, b + 1)
        end
    end
    if string.len(result) > MAX_CHARS then return text end   -- zu lang: lieber ohne Links als abgeschnitten
    return result
end

-- ============================================================
-- 2) FENSTER
-- ============================================================
local F = CreateFrame("Frame", "BananaLootLFMBuilderFrame", UIParent)
B.frame = F
F:SetWidth(640)
F:SetHeight(560)
F:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
F:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
BananaLoot_Theme.Darken(F)
F:SetMovable(true)
F:EnableMouse(true)
F:RegisterForDrag("LeftButton")
F:SetScript("OnDragStart", function() this:StartMoving() end)
F:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
F:SetFrameStrata("DIALOG")
F:Hide()

local function MakeButton(name, w, h)
    local b = CreateFrame("Button", name, F, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(h)
    return b
end

F.close = CreateFrame("Button", "BananaLootLFMBuilderClose", F, "UIPanelCloseButton")
F.close:SetPoint("TOPRIGHT", F, "TOPRIGHT", -4, -4)
F.close:SetScript("OnClick", function() BananaLoot:PlayClickSound(); F:Hide() end)

F.title = F:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
F.title:SetPoint("TOP", F, "TOP", 0, -16)

-- Raid-Auswahl: < Name >
F.raidLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.raidLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -52)
F.prevBtn = MakeButton("BananaLootLFMBuilderPrev", 26, 22)
F.prevBtn:SetPoint("LEFT", F.raidLabel, "RIGHT", 10, 0)
F.prevBtn:SetText("<")
F.raidName = F:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
F.raidName:SetPoint("LEFT", F.prevBtn, "RIGHT", 8, 0)
F.raidName:SetWidth(250)
F.raidName:SetJustifyH("CENTER")
F.nextBtn = MakeButton("BananaLootLFMBuilderNext", 26, 22)
F.nextBtn:SetPoint("LEFT", F.raidName, "RIGHT", 8, 0)
F.nextBtn:SetText(">")

F.hrCheck = CreateFrame("CheckButton", "BananaLootLFMBuilderHRCheck", F, "UICheckButtonTemplate")
F.hrCheck:SetPoint("TOPLEFT", F, "TOPLEFT", 20, -80)
F.hrCheck:SetScript("OnClick", function()
    B.withHR = F.hrCheck:GetChecked() and true or false
    B.Refresh()
end)
F.hrLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.hrLabel:SetPoint("LEFT", F.hrCheck, "RIGHT", 2, 0)

-- Rollen-Voreinstellungen
F.roleLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.roleLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -116)
for r = 1, table.getn(ROLE_ORDER) do
    local b = MakeButton("BananaLootLFMBuilderRole" .. r, 118, 22)
    b:SetPoint("TOPLEFT", F, "TOPLEFT", 100 + (r - 1) * 124, -112)
    b.role = ROLE_ORDER[r]
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetAllPoints(b)
    b.sel:SetTexture(1, 0.82, 0, 0.35)
    b.sel:Hide()
    b:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        B.SelectRole(this.role, not RoleFullySelected(this.role))
        B.Refresh()
    end)
    B.roleBtns[r] = b
end
F.allBtn = MakeButton("BananaLootLFMBuilderAll", 70, 22)
F.allBtn:SetPoint("TOPLEFT", F, "TOPLEFT", 478, -112)
F.allBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); B.SelectAll(true); B.Refresh() end)
F.noneBtn = MakeButton("BananaLootLFMBuilderNone", 70, 22)
F.noneBtn:SetPoint("LEFT", F.allBtn, "RIGHT", 6, 0)
F.noneBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); B.SelectAll(false); B.Refresh() end)

-- Klassen-Raster: Klassenname (waehlt alle Specs) + Spec-Buttons
local ROW_Y, ROW_H = -148, 26
for c = 1, table.getn(CLASSES) do
    local cb = MakeButton("BananaLootLFMBuilderClass" .. c, 112, 22)
    cb:SetPoint("TOPLEFT", F, "TOPLEFT", 24, ROW_Y - (c - 1) * ROW_H)
    cb.cls = c
    cb:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        local all = true
        for s = 1, table.getn(CLASSES[this.cls].specs) do
            if not IsSel(this.cls, s) then all = false end
        end
        B.SelectClass(this.cls, not all)
        B.Refresh()
    end)
    B.classBtns[c] = cb
    B.specBtns[c] = {}
    for s = 1, table.getn(CLASSES[c].specs) do
        local sb = MakeButton("BananaLootLFMBuilderSpec" .. c .. "_" .. s, 112, 22)
        sb:SetPoint("LEFT", cb, "RIGHT", 6 + (s - 1) * 116, 0)
        sb.cls, sb.spec = c, s
        sb.sel = sb:CreateTexture(nil, "OVERLAY")
        sb.sel:SetAllPoints(sb)
        sb.sel:SetTexture(1, 0.82, 0, 0.35)
        sb.sel:Hide()
        sb:SetScript("OnClick", function()
            BananaLoot:PlayClickSound()
            SetSel(this.cls, this.spec, not IsSel(this.cls, this.spec))
            B.Refresh()
        end)
        B.specBtns[c][s] = sb
    end
end

-- Vorschau
F.previewLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.previewLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -392)
F.preview = F:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
F.preview:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -414)
F.preview:SetWidth(590)
F.preview:SetJustifyH("LEFT")
F.preview:SetJustifyV("TOP")
F.counter = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
F.counter:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -486)

F.applyBtn = MakeButton("BananaLootLFMBuilderApply", 170, 26)
F.applyBtn:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 24, 18)
F.applyBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); B.Apply(false) end)
F.startBtn = MakeButton("BananaLootLFMBuilderStart", 230, 26)
F.startBtn:SetPoint("LEFT", F.applyBtn, "RIGHT", 10, 0)
F.startBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound(); B.Apply(true) end)

-- Raid wechseln
F.prevBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local n = table.getn(BananaLoot:GetPreparedRaids())
    B.raidIdx = B.raidIdx - 1
    if B.raidIdx < 0 then B.raidIdx = n end
    B.Refresh()
end)
F.nextBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    local n = table.getn(BananaLoot:GetPreparedRaids())
    B.raidIdx = B.raidIdx + 1
    if B.raidIdx > n then B.raidIdx = 0 end
    B.Refresh()
end)

function B.Refresh()
    if not F:IsShown() then return end
    local l = Lang()
    F.title:SetText(BananaLoot:L("LFMB_TITLE"))
    F.raidLabel:SetText(BananaLoot:L("LFMB_RAID_LABEL"))
    F.hrLabel:SetText(BananaLoot:L("LFMB_HR_CHECK"))
    F.hrCheck:SetChecked(B.withHR)
    F.roleLabel:SetText(BananaLoot:L("LFMB_ROLE_LABEL"))
    F.previewLabel:SetText(BananaLoot:L("LFMB_PREVIEW"))
    F.allBtn:SetText(BananaLoot:L("LFMB_ALL"))
    F.noneBtn:SetText(BananaLoot:L("LFMB_NONE"))
    F.applyBtn:SetText(BananaLoot:L("LFMB_APPLY"))
    F.startBtn:SetText(BananaLoot:L("LFMB_APPLY_START"))

    local entry = B.CurrentEntry()
    if entry then
        F.raidName:SetText(entry.name or "?")
    else
        F.raidName:SetText("|cff888888" .. BananaLoot:L("LFMB_NO_RAID") .. "|r")
    end
    for r = 1, table.getn(ROLE_ORDER) do
        local role = ROLE_ORDER[r]
        B.roleBtns[r]:SetText(ROLE_WORDS[role][l])
        if RoleFullySelected(role) then B.roleBtns[r].sel:Show() else B.roleBtns[r].sel:Hide() end
    end
    for c = 1, table.getn(CLASSES) do
        local cls = CLASSES[c]
        B.classBtns[c]:SetText("|cff" .. cls.color .. cls[l] .. "|r")
        for s = 1, table.getn(cls.specs) do
            local sb = B.specBtns[c][s]
            local spec = cls.specs[s]
            BananaLoot_Theme.FitText(sb, spec[l], 98)
            if IsSel(c, s) then sb.sel:Show() else sb.sel:Hide() end
        end
    end
    local text, need, links = B.CurrentText()
    local nlinks = 0
    for _ in pairs(links or {}) do nlinks = nlinks + 1 end
    if need then
        F.preview:SetText(text)
    else
        F.preview:SetText("|cff888888" .. BananaLoot:L("LFMB_NEED_SELECTION") .. "|r")
    end
    -- Zeichenzahl NACH dem Ersetzen der [Items] durch Links (so zaehlt der Chat)
    F.counter:SetText((string.len(text) + nlinks * LINK_OVERHEAD) .. " / " .. MAX_CHARS .. "   " .. BananaLoot:L("LFMB_LINK_NOTE"))
end

-- Text ins LFM-Fenster uebernehmen (dort weiter editierbar); start = sofort posten und im
-- eingestellten Intervall wiederholen.
function B.Apply(start)
    local text, need, links = B.CurrentText()
    if not need then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("LFMB_NEED_SELECTION"))
        return
    end
    BananaLoot:SetLFMText(text)
    BananaLoot.EnsureDB()
    BananaLoot_DB.settings.lfmLinks = links   -- [Name] -> Item-ID, wird beim Posten zu Links
    if BananaLoot_UI and BananaLoot_UI.ShowLFM then BananaLoot_UI:ShowLFM() end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("LFMB_APPLIED"), string.len(text)))
    if start then
        if BananaLoot.lfmRunning then BananaLoot:StopLFM() end
        local ok = BananaLoot:StartLFM()
        if ok then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("LFM_STARTED"), BananaLoot:GetLFMIntervalMinutes()))
        else
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("LFM_NEED_TEXT"))
        end
        if BananaLoot_UI and BananaLoot_UI.RefreshLFM then BananaLoot_UI:RefreshLFM() end
    end
    F:Hide()
end

F:SetScript("OnShow", function() B.Refresh() end)

function BananaLoot_UI:ShowLFMBuilder()
    -- Standard: der im Hauptfenster ausgewaehlte vorbereitete Raid
    local sel = BananaLoot:GetSelectedPreparedRaid()
    B.raidIdx = 0
    if sel then
        local list = BananaLoot:GetPreparedRaids()
        for i = 1, table.getn(list) do
            if list[i].id == sel.id then B.raidIdx = i end
        end
    end
    F:Show()
    B.Refresh()
end

function BananaLoot_UI:ApplyLocaleLFMBuilder()
    if B.openBtn then B.openBtn:SetText(BananaLoot:L("LFMB_OPEN_BTN")) end
    if F:IsShown() then B.Refresh() end
end

-- Das mehrzeilige LFM-Textfeld nutzt die einzeilige InputBoxTemplate: deren Rahmenstuecke (links/
-- mitte/rechts) sitzen mittig im hohen Feld und zeigen eine stoerende Linie quer durch den Text.
-- Entfernen und durch einen eigenen Rahmen ersetzen.
local lfmEdit = getglobal("BananaLootLFMEditBox")
if lfmEdit then
    local parts = { "Left", "Middle", "Right" }
    for i = 1, table.getn(parts) do
        local tex = getglobal("BananaLootLFMEditBox" .. parts[i])
        if tex then tex:Hide() end
    end
    lfmEdit:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    lfmEdit:SetBackdropColor(0, 0, 0, 0.9)
    if lfmEdit.SetTextInsets then lfmEdit:SetTextInsets(8, 8, 6, 6) end
end

-- Button im LFM-Fenster (oben rechts neben "LFM-Text:")
local lfmFrame = getglobal("BananaLootLFMFrame")
if lfmFrame then
    local b = CreateFrame("Button", "BananaLootLFMBuilderOpenBtn", lfmFrame, "UIPanelButtonTemplate")
    b:SetWidth(190)
    b:SetHeight(22)
    b:SetPoint("TOPRIGHT", lfmFrame, "TOPRIGHT", -38, -42)
    b:SetText(BananaLoot:L("LFMB_OPEN_BTN"))
    b:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        BananaLoot_UI:ShowLFMBuilder()
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(BananaLoot:L("LFMB_OPEN_TIP"), 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    B.openBtn = b
end
