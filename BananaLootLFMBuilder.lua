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

-- ============================================================
-- 0) START-ZEIT MIT ZEITZONE (immer englisch im Text)
-- ============================================================
-- Eine Startzeit in EINER frei waehlbaren Zeitzone + immer die Server-Zeit. Sommer-/Winterzeit wird je
-- Datum automatisch berechnet (EU: letzter Sonntag im Maerz bis letzter Sonntag im Oktober, jeweils 01:00 UTC;
-- USA: zweiter Sonntag im Maerz bis erster Sonntag im November, jeweils 02:00 Ortszeit).
-- Ab einer Stunde vor dem Start steht nur noch "starts in N min"; die Minuten werden bei JEDEM Posten
-- neu berechnet, weil im gespeicherten LFM-Text nur der Platzhalter {TIME} steht.
local ZONES = {
    { std = "CET", dst = "CEST", off = 1, rule = "EU" },
    { std = "GMT", dst = "BST", off = 0, rule = "EU" },
    { std = "EET", dst = "EEST", off = 2, rule = "EU" },
    { std = "EST", dst = "EDT", off = -5, rule = "US" },
    { std = "PST", dst = "PDT", off = -8, rule = "US" },
}
local WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }   -- 1 = Montag
B.ZONES = ZONES
B.WEEKDAYS = WEEKDAYS
local TIME_TOKEN = "{TIME}"
B.TIME_TOKEN = TIME_TOKEN

local function DaysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = math.mod(m + 9, 12)
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function CivilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + 3
    if m > 12 then m = m - 12 end
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- 0 = Sonntag ... 6 = Samstag
local function WeekdayOf(days) return math.mod(days + 4, 7) end

local function DaysInMonth(y, m)
    local nd = (m == 12) and DaysFromCivil(y + 1, 1, 1) or DaysFromCivil(y, m + 1, 1)
    return nd - DaysFromCivil(y, m, 1)
end

local function LastSunday(y, m)
    local last = DaysFromCivil(y, m, DaysInMonth(y, m))
    return last - WeekdayOf(last)
end

local function NthSunday(y, m, n)
    local first = DaysFromCivil(y, m, 1)
    local w = WeekdayOf(first)
    local firstSun = first + (w == 0 and 0 or (7 - w))
    return firstSun + (n - 1) * 7
end

local function IsDST(zone, utc)
    local y = CivilFromDays(math.floor(utc / 86400))
    local startUTC, endUTC
    if zone.rule == "EU" then
        startUTC = LastSunday(y, 3) * 86400 + 3600
        endUTC = LastSunday(y, 10) * 86400 + 3600
    else
        startUTC = NthSunday(y, 3, 2) * 86400 + (2 - zone.off) * 3600
        endUTC = NthSunday(y, 11, 1) * 86400 + (2 - (zone.off + 1)) * 3600
    end
    return utc >= startUTC and utc < endUTC
end
B.IsDST = IsDST

local function OffsetHours(zone, utc)
    return zone.off + (IsDST(zone, utc) and 1 or 0)
end

-- aktuelle UTC-Zeit in Sekunden (Epoche). Faellt auf time() zurueck, falls date("!*t") fehlt.
local function UTCNow()
    local t = date("!*t")
    if t and t.year then
        return DaysFromCivil(t.year, t.month, t.day) * 86400 + t.hour * 3600 + t.min * 60 + t.sec
    end
    return time()
end
B.UTCNow = function() return UTCNow() end

-- Ortszeit (Tag, Stunde, Minute) in der Zone -> UTC-Sekunden
local function LocalToUTC(zone, days, h, m)
    local try = days * 86400 + h * 3600 + m * 60 - zone.off * 3600
    if IsDST(zone, try - 3600) then return try - 3600 end
    return try
end

-- cfg = { h, m, zone (Index), day (0 = heute, 1..7 = Mo..So) }. Rueckgabe: Minuten bis zum Start, Tag-Wort,
-- Ortszeit-Text, Zonenkuerzel, Server-Zeit (Stunde, Minute). nowOverride/serverOverride nur fuer Tests.
function B.TimeInfo(cfg, nowOverride, serverH, serverM)
    local zone = ZONES[cfg.zone or 1] or ZONES[1]
    local nowUTC = nowOverride or UTCNow()
    local localNow = nowUTC + OffsetHours(zone, nowUTC) * 3600
    local today = math.floor(localNow / 86400)
    local days = today
    if cfg.day and cfg.day >= 1 then
        -- naechster Tag mit diesem Wochentag (1 = Montag -> WeekdayOf == 1)
        local want = math.mod(cfg.day, 7)   -- 7 (So) -> 0
        local n = 0
        while WeekdayOf(today + n) ~= want and n < 7 do n = n + 1 end
        days = today + n
    end
    local target = LocalToUTC(zone, days, cfg.h or 0, cfg.m or 0)
    -- schon lange vorbei: naechster Termin (naechster Tag bzw. naechste Woche)
    if target - nowUTC < -1800 then
        days = days + ((cfg.day and cfg.day >= 1) and 7 or 1)
        target = LocalToUTC(zone, days, cfg.h or 0, cfg.m or 0)
    end
    local delta = target - nowUTC
    local label = IsDST(zone, target) and zone.dst or zone.std
    local dayWord
    if days == today then dayWord = "today" else dayWord = WEEKDAYS[WeekdayOf(days) == 0 and 7 or WeekdayOf(days)] end
    if not serverH then
        if GetGameTime then serverH, serverM = GetGameTime() else serverH, serverM = 0, 0 end
    end
    local mins = math.floor(delta / 60)
    local sm = math.mod((serverH or 0) * 60 + (serverM or 0) + mins, 1440)
    if sm < 0 then sm = sm + 1440 end
    return {
        minutes = mins, dayWord = dayWord, label = label,
        hh = cfg.h or 0, mm = cfg.m or 0,
        sh = math.floor(sm / 60), sm = math.mod(sm, 60),
    }
end

-- Text-Stueck fuer die Startzeit: "Sat 20:00 (CET), 20:00 (ServerTime)" bzw. "starts in 45 min"
function B.TimeSegment(cfg, nowOverride, serverH, serverM)
    if not cfg or cfg.h == nil then return nil end
    local ti = B.TimeInfo(cfg, nowOverride, serverH, serverM)
    if ti.minutes <= 0 then return "starting now" end
    if ti.minutes <= 60 then return "starts in " .. ti.minutes .. " min" end
    return string.format("%s %02d:%02d (%s), %02d:%02d (ServerTime)", ti.dayWord, ti.hh, ti.mm, ti.label, ti.sh, ti.sm)
end

-- "20:00" / "20.00" / "2000" -> Stunde, Minute (oder nil)
function B.ParseClock(str)
    if not str then return nil end
    local _, _, h, m = string.find(str, "^%s*(%d%d?)[:%.](%d%d)%s*$")
    if not h then
        local _, _, hh, mm = string.find(str, "^%s*(%d%d)(%d%d)%s*$")
        h, m = hh, mm
    end
    h, m = tonumber(h), tonumber(m)
    if not h or h > 23 or m > 59 then return nil end
    return h, m
end

-- beim Posten: {TIME} durch die aktuelle Zeitangabe ersetzen (Minuten werden dabei neu berechnet)
function BananaLoot:LFMExpandTime(text)
    if not text or not string.find(text, TIME_TOKEN, 1, true) then return text end
    BananaLoot.EnsureDB()
    local seg = B.TimeSegment(BananaLoot_DB.settings.lfmTimeCfg)
    local a, b = string.find(text, TIME_TOKEN, 1, true)
    if not seg then
        -- keine Zeit hinterlegt: Platzhalter samt Trenner entfernen
        local out = string.gsub(text, " %- " .. "{TIME}", "")
        out = string.gsub(out, "{TIME}", "")
        return out
    end
    return string.sub(text, 1, a - 1) .. seg .. string.sub(text, b + 1)
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
function BananaLoot:BuildLFMText(entry, needText, withHR, timeSeg, freeText)
    local raidName = entry and entry.name or T_DEFAULT_RAID
    local head = string.format(T_LFM, raidName)
    local need = needText and string.format(T_NEED, needText) or ""
    local suffix = T_SUFFIX
    local items = (withHR and entry) and HRItems(entry) or {}
    local timeStr = (timeSeg and timeSeg ~= "") and (" - " .. timeSeg) or ""
    freeText = freeText or ""

    -- Text + Laenge NACH dem Ersetzen durch Links
    local function compose(nHR, useSuffix, needStr, free)
        free = free or freeText
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
        local freeStr = (free ~= "") and (" - " .. free) or ""
        local text = head .. needStr .. hr .. timeStr .. freeStr .. (useSuffix and suffix or "")
        return text, string.len(text) + nHR * LINK_OVERHEAD, links
    end

    -- zuerst alle HR-Items, dann weniger, dann ohne Zusatztext, zuletzt gekuerzt
    for n = table.getn(items), 0, -1 do
        local t, len, links = compose(n, true, need)
        if len <= MAX_CHARS then return t, links end
    end
    local t, len, links = compose(0, false, need)
    if len <= MAX_CHARS then return t, links end
    -- zuletzt den Freitext kuerzen (Rollen, Zeit und HR-Hinweis bleiben immer erhalten)
    if freeText ~= "" then
        local over = len - MAX_CHARS
        local keep = string.len(freeText) - over - 3
        local short = (keep > 0) and (string.sub(freeText, 1, keep) .. "...") or ""
        local t2, len2, links2 = compose(0, false, need, short)
        if len2 <= MAX_CHARS then return t2, links2 end
    end
    return string.sub(t, 1, MAX_CHARS - 3) .. "...", {}
end

function B.CurrentEntry()
    local list = BananaLoot:GetPreparedRaids()
    return list[B.raidIdx]
end

-- Zeitangabe aus den Eingabefeldern (nil, wenn keine gueltige Startzeit eingetragen ist)
function B.CurrentTimeCfg()
    local h, m = B.ParseClock(B.timeStr)
    if not h then return nil end
    return { h = h, m = m, zone = B.zoneIdx or 1, day = B.dayIdx or 0 }
end

function B.CurrentTimeSegment()
    return B.TimeSegment(B.CurrentTimeCfg())
end

function B.CurrentText()
    local need = B.NeedText()
    local text, links = BananaLoot:BuildLFMText(B.CurrentEntry(), need, B.withHR, B.CurrentTimeSegment(), B.freeText)
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
F:SetHeight(626)
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

-- Startzeit (eine Zeitzone + Server-Zeit) und Freitext
local DAY_UI = {
    de = { [0] = "Heute", "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" },
    en = { [0] = "Today", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" },
}
local function SaveUI()
    BananaLoot.EnsureDB()
    BananaLoot_DB.settings.lfmBuilderUI = { time = B.timeStr or "", zone = B.zoneIdx or 1, day = B.dayIdx or 0, free = B.freeText or "" }
end

local function MakeLine(name, w, maxLetters)
    local e = CreateFrame("EditBox", name, F, "InputBoxTemplate")
    e:SetWidth(w)
    e:SetHeight(20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters)
    e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    return e
end

F.timeLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.timeLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -398)
F.timeEdit = MakeLine("BananaLootLFMBuilderTime", 56, 5)
F.timeEdit:SetPoint("LEFT", F.timeLabel, "RIGHT", 14, 0)
F.timeEdit:SetScript("OnTextChanged", function()
    if B.settingText then return end
    B.timeStr = F.timeEdit:GetText()
    SaveUI()
    B.Refresh()
end)
F.zoneBtn = MakeButton("BananaLootLFMBuilderZone", 118, 22)
F.zoneBtn:SetPoint("LEFT", F.timeEdit, "RIGHT", 10, 0)
F.zoneBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    B.zoneIdx = math.mod(B.zoneIdx or 1, table.getn(B.ZONES)) + 1
    SaveUI()
    B.Refresh()
end)
F.dayBtn = MakeButton("BananaLootLFMBuilderDay", 80, 22)
F.dayBtn:SetPoint("LEFT", F.zoneBtn, "RIGHT", 6, 0)
F.dayBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    B.dayIdx = math.mod((B.dayIdx or 0) + 1, 8)
    SaveUI()
    B.Refresh()
end)
F.timeHint = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
F.timeHint:SetPoint("LEFT", F.dayBtn, "RIGHT", 10, 0)
F.timeHint:SetWidth(240)
F.timeHint:SetJustifyH("LEFT")

F.freeLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.freeLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -430)
F.freeEdit = MakeLine("BananaLootLFMBuilderFree", 470, 80)
F.freeEdit:SetPoint("LEFT", F.freeLabel, "RIGHT", 14, 0)
F.freeEdit:SetScript("OnTextChanged", function()
    if B.settingText then return end
    B.freeText = F.freeEdit:GetText()
    SaveUI()
    B.Refresh()
end)

-- Vorschau
F.previewLabel = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
F.previewLabel:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -458)
F.preview = F:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
F.preview:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -480)
F.preview:SetWidth(590)
F.preview:SetJustifyH("LEFT")
F.preview:SetJustifyV("TOP")
-- Bearbeitbarer Text: was der Assistent erzeugt, kann von Hand ergaenzt/umgestellt werden (z.B. etwas,
-- das sich nicht auswaehlen laesst). Eine neue Auswahl erzeugt den Text neu.
-- Wie das LFM-Textfeld im LFM-Fenster: InputBoxTemplate (mehrzeilig); dessen Rahmenstuecke werden
-- ausgeblendet und durch einen eigenen Rahmen ersetzt (sonst bleibt eine freie Box ohne Template
-- auf Zeilenhoehe zusammengedrueckt).
F.edit = CreateFrame("EditBox", "BananaLootLFMBuilderEdit", F, "InputBoxTemplate")
F.edit:SetWidth(590)
F.edit:SetHeight(64)
F.edit:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -480)
F.edit:SetAutoFocus(false)
F.edit:SetMaxLetters(400)
F.edit:SetMultiLine(true)
F.edit:SetFontObject(ChatFontSmall)
do
    local parts = { "Left", "Middle", "Right" }
    for i = 1, table.getn(parts) do
        local tex = getglobal("BananaLootLFMBuilderEdit" .. parts[i])
        if tex then tex:Hide() end
    end
end
F.edit:SetTextInsets(8, 8, 6, 6)
F.edit:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
F.edit:SetBackdropColor(0, 0, 0, 0.9)
F.edit:SetScript("OnEscapePressed", function() F.edit:ClearFocus() end)
F.edit:SetScript("OnTextChanged", function()
    if B.settingText then return end
    B.UpdateCounter()
end)
F.counter = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
F.counter:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -550)
F.editHint = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
F.editHint:SetPoint("TOPLEFT", F, "TOPLEFT", 24, -564)
F.editHint:SetWidth(590)
F.editHint:SetJustifyH("LEFT")

-- Zeichenzahl NACH dem Ersetzen der [Items] durch Links (so zaehlt der Chat)
function B.CountText(text)
    text = text or ""
    local n = string.len(text)
    local links = B.curLinks or {}
    for name in pairs(links) do
        if string.find(text, "[" .. name .. "]", 1, true) then n = n + LINK_OVERHEAD end
    end
    return n
end

function B.UpdateCounter()
    local n = B.CountText(F.edit:GetText())
    local color = (n > MAX_CHARS) and "|cffff5555" or "|cffffffff"
    F.counter:SetText(color .. n .. " / " .. MAX_CHARS .. "|r   " .. BananaLoot:L("LFMB_LINK_NOTE"))
end

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
    F.timeLabel:SetText(BananaLoot:L("LFMB_TIME_LABEL"))
    F.freeLabel:SetText(BananaLoot:L("LFMB_FREE_LABEL"))
    F.timeHint:SetText(BananaLoot:L("LFMB_TIME_HINT"))
    local zn = B.ZONES[B.zoneIdx or 1]
    F.zoneBtn:SetText(zn.std .. "/" .. zn.dst)
    F.dayBtn:SetText(DAY_UI[l][B.dayIdx or 0])

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
    B.curLinks = links or {}
    B.settingText = true
    if need then
        F.preview:SetText("")
        F.edit:SetText(text)
    else
        F.edit:SetText("")
        F.preview:SetText("|cff888888" .. BananaLoot:L("LFMB_NEED_SELECTION") .. "|r")
    end
    B.settingText = false
    F.editHint:SetText(BananaLoot:L("LFMB_EDIT_HINT"))
    B.UpdateCounter()
end

-- Text ins LFM-Fenster uebernehmen (dort weiter editierbar); start = sofort posten und im
-- eingestellten Intervall wiederholen.
function B.Apply(start)
    local _, _, links = B.CurrentText()
    local text = F.edit:GetText() or ""
    if string.gsub(text, "%s", "") == "" then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("LFMB_NEED_SELECTION"))
        return
    end
    if B.CountText(text) > MAX_CHARS then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("LFMB_TOO_LONG"), B.CountText(text), MAX_CHARS))
        return
    end
    -- nur Items behalten, die noch im (ggf. bearbeiteten) Text stehen
    local kept = {}
    for name, id in pairs(links or {}) do
        if string.find(text, "[" .. name .. "]", 1, true) then kept[name] = id end
    end
    links = kept
    -- Startzeit: im gespeicherten Text steht nur {TIME}; beim Posten werden Zeit/Minuten neu berechnet
    BananaLoot.EnsureDB()
    local seg = B.CurrentTimeSegment()
    BananaLoot_DB.settings.lfmTimeCfg = B.CurrentTimeCfg()
    if seg then
        local a, b = string.find(text, seg, 1, true)
        if a then text = string.sub(text, 1, a - 1) .. B.TIME_TOKEN .. string.sub(text, b + 1) end
    end
    BananaLoot:SetLFMText(text)
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
    BananaLoot.EnsureDB()
    local u = BananaLoot_DB.settings.lfmBuilderUI or {}
    B.timeStr = u.time or ""
    B.zoneIdx = u.zone or 1
    B.dayIdx = u.day or 0
    B.freeText = u.free or ""
    B.settingText = true
    F.timeEdit:SetText(B.timeStr)
    F.freeEdit:SetText(B.freeText)
    B.settingText = false
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
