-- BananaLootTest.lua
-- TESTMODUS: laesst die ECHTE BananaLoot-Engine auf einem simulierten Raid
-- laufen. 10 erfundene Items landen auf einen Schlag im normalen Loot-
-- Fenster, 10 erfundene Raider wuerfeln mit sichtbaren Meldungen mit, und du
-- verrollst/vergibst wie im Raid (Roll, ARF, Verwalten, Raid Roll, /bl auto,
-- /bl award ...). Auch du selbst kannst per /roll mitwuerfeln. Es gelten das
-- echte Roll-Timeout, SR+ Bonus, Countdown, "Top N gewinnen", Loot-Vorschau.
--
-- WIE ES FUNKTIONIERT
--   - Die Simulation speist nur DATEN in die echte Engine ein: Fake-Loot
--     (BananaLoot.testLootItems), Fake-Roster (BananaLoot.testRoster),
--     Fake-Reservierungen/SR+ und Fake-Wuerfe (ueber BananaLoot:OnRoll).
--     Die echte Engine hat dafuer nur schmale Einhaengepunkte (testMode-
--     Weichen in ScanLootWindow/AssignLoot/Roster/MasterLooter sowie die
--     BananaLoot:TestHook()-Aufrufe).
--
-- SICHERHEIT (bitte beim Erweitern beibehalten)
--   - Waehrend des Tests wird SendChatMessage fuer RAID/PARTY/SAY lokal
--     umgeleitet (mit [TEST]-Marke und Raid-Warning-Sound) und
--     SendAddonMessage fuer das BananaLoot-Praefix blockiert. Es verlaesst
--     also NICHTS den eigenen Client. Beides wird beim Testende zurueck-
--     gesetzt.
--   - Die echte Loot-API (GiveMasterLoot) wird nie angefasst.
--   - Alle echten Daten (SR-Liste, SR+ Werte, Hard/Bankreserve, Loot-Log,
--     vergebene Items, Wiederherstellungsliste) werden beim Teststart
--     beiseitegelegt (auch in den SavedVariables, falls mitten im Test ein
--     /reload oder Absturz passiert) und beim Testende bzw. beim naechsten
--     Login wieder eingesetzt.
-- ============================================================

local TEST = {
    phase = "idle",    -- "idle" | "countdown" | "running"
    scheduled = {},    -- { time = GetTime()+X, fn = function() end }
    awarded = 0,
    totalSlots = 0,
    lastStatusUpdate = 0,
    lastWarnSound = 0,
    allDoneScheduled = false,
}

-- ============================================================
-- 1) DATEN: erfundene Raider und die 10 Loot-Slots
-- ============================================================
local TEST_ROSTER = {
    { "Testopher", "WARRIOR" }, { "Rollinator", "ROGUE" }, { "Lootgoblin", "DRUID" },
    { "Sadpanda", "PRIEST" }, { "Grumpybear", "SHAMAN" }, { "Luckyone", "MAGE" },
    { "DPSMcGee", "WARLOCK" }, { "Healbot", "PALADIN" }, { "Tankzilla", "HUNTER" },
    { "Ninjaloot", "ROGUE" },
}

-- Echte Naxxramas-Item-IDs aus der mitgelieferten Item-Datenbank (nur die
-- Vergabe ist simuliert, nicht die Items). "behavior" steuert, wie die
-- erfundenen Raider auf einen Roll reagieren:
--   normal  - 4-7 Raider wuerfeln (meist Hauptspec, ein paar Off-Spec)
--   sr      - die Reservierer wuerfeln, ein Nicht-Reservierer wuerfelt
--             mit (wird von der Engine ignoriert)
--   srbonus - wie sr, aber der Reservierer mit SR+ Stack hat einen knapp
--             niedrigeren Wurf, den der Bonus ausgleicht
--   nobody  - niemand wuerfelt (-> "Niemand hat gerollt" nach Timeout)
--   offspec - nur Off-Spec-Wuerfe
--   tie     - zwei Raider wuerfeln denselben Hoechstwert (-> Rewuerfeln)
--   hr      - Hard Reserve, nur manuelle Vergabe
--   br      - Bankreserve, geht automatisch an den (Test-)BR-Looter
-- "qty" = Anzahl Kopien (je eigener Loot-Slot), "reservers" = Roster-Indizes.
local TEST_ITEMS = {
    { id = 16939, behavior = "sr",      reservers = { 2, 4 } },  -- Dragonstalker's Helm
    { id = 23054, behavior = "normal" },                         -- Gressil, Dawn of Ruin
    { id = 23075, behavior = "nobody" },                         -- Death's Bargain
    { id = 22804, behavior = "offspec" },                        -- Maexxna's Fang
    { id = 16958, behavior = "srbonus", reservers = { 8, 7 } },  -- Judgement Breastplate
    { id = 23044, behavior = "tie" },                            -- Harbinger of Doom
    { id = 22981, behavior = "normal",  qty = 2 },               -- Gluth's Missing Collar (x2)
    { id = 22520, behavior = "hr" },                             -- The Phylactery of Kel'Thuzad
    { id = 22727, behavior = "sr",      reservers = { 5, 9 } },  -- Frame of Atiesh
    { id = 22732, behavior = "br" },                             -- Mark of C'Thun (Bankreserve)
}

-- Waehrend des Tests gesetzte Empfaenger (Roster-Namen): Disenchanter fuer
-- "Disenchant" bei "Niemand hat gerollt", BR-Looter fuer Bankreserve-Items.
local TEST_DISENCHANTER = "Sadpanda"
local TEST_BR_LOOTER = "Healbot"

local CHATTER = {
    de = {
        need = { "need!", "gl alle", "Daumen drücken...", "ich brauch das", "los, würfeln!" },
        sr = { "SR hier!", "mein SR!", "gl euch", "Daumen drücken..." },
        gz = { "gz!", "gz, verdient", "grats", "ok gz", "neidisch..." },
        win = { "yeah!", "endlich!", "danke euch!", "wuhu" },
    },
    en = {
        need = { "need!", "gl all", "fingers crossed...", "I need this", "roll roll roll!" },
        sr = { "SR here!", "my SR!", "gl you", "fingers crossed..." },
        gz = { "gz!", "gz, well deserved", "grats", "ok gz", "so jealous..." },
        win = { "yeah!", "finally!", "thanks guys!", "woohoo" },
    },
}

-- ============================================================
-- 2) HELFER
-- ============================================================
local function TPrint(msg, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage(msg, r, g, b)
end

local function TSchedule(delay, fn)
    table.insert(TEST.scheduled, { time = GetTime() + delay, fn = fn })
end

local function TIsFake(name)
    for i = 1, table.getn(TEST_ROSTER) do
        if TEST_ROSTER[i][1] == name then return true end
    end
    return false
end

local function TRandomFakeName(usedSet)
    local c = {}
    for i = 1, table.getn(TEST_ROSTER) do
        local n = TEST_ROSTER[i][1]
        if not usedSet[n] then table.insert(c, n) end
    end
    if table.getn(c) == 0 then return nil end
    return c[math.random(1, table.getn(c))]
end

local function TPick(list)
    return list[math.random(1, table.getn(list))]
end

local function TChatter()
    return CHATTER[BananaLoot:GetLanguage()] or CHATTER.de
end

-- Raid-Chat-Zeile eines erfundenen Raiders (lokal, Raid-Orange).
local function TRaidChatFrom(name, text)
    TPrint("|cffff7f00[Raid] [|r" .. BananaLoot:ColoredName(name) .. "|cffff7f00]: " .. text .. "|r")
end

-- System-Wurfzeile im Originalformat des Clients ("X rolls 77 (1-100)").
local function TSystemRoll(name, value, rollType)
    local maxRange = 100
    if rollType == "os" then maxRange = 99 elseif rollType == "tmog" then maxRange = 98 end
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    TPrint(string.format(fmt, name, value, 1, maxRange), 1, 1, 0)
end

-- Laesst einen erfundenen Raider nach "delay" Sekunden wuerfeln -- nur,
-- wenn derselbe Roll dann noch laeuft (spaete Wuerfe verfallen wie im Raid).
local function TSimRoll(ar, name, value, rollType, delay)
    TSchedule(delay, function()
        if BananaLoot.testMode and BananaLoot.activeRoll == ar and ar.running then
            TSystemRoll(name, value, rollType)
            BananaLoot:OnRoll(name, value, rollType)
        end
    end)
end

-- Verteilt Wuerfe ueber die ersten ~60% des eingestellten Timeouts, damit
-- sie auch bei kurzem Timeout noch rechtzeitig eintreffen.
local function TRollDelay(ar)
    local span = ar.maxDuration * 0.6
    if span < 2 then span = 2 end
    return 1 + math.random() * (span - 1)
end

-- ============================================================
-- 3) UMLEITUNG DER CHAT-AUSGABEN (nur waehrend des Tests aktiv)
-- ============================================================
local origSendChatMessage, origSendAddonMessage

local function TestSendChatMessage(msg, chatType, language, target)
    if chatType == "RAID" or chatType == "PARTY" or chatType == "SAY" or chatType == "RAID_WARNING" then
        local text = string.gsub(msg or "", "|r", "|r|cffff7f00")
        TPrint("|cff33ccff[TEST]|r |cffff7f00[Raid] [" .. UnitName("player") .. "]: " .. text .. "|r")
        -- Raid-Warning-Sound zu jeder Ansage (leicht gedrosselt, damit
        -- mehrere Zeilen in Folge nicht als Dauerton klingen).
        if GetTime() - TEST.lastWarnSound > 0.25 then
            TEST.lastWarnSound = GetTime()
            pcall(function() PlaySound("RaidWarning") end)
        end
        return
    end
    if chatType == "WHISPER" and TIsFake(target) then return end
    return origSendChatMessage(msg, chatType, language, target)
end

local function TestSendAddonMessage(prefix, text, channel, target)
    if prefix == "BananaLoot" then return end
    return origSendAddonMessage(prefix, text, channel, target)
end

local function InstallOverrides()
    origSendChatMessage = SendChatMessage
    origSendAddonMessage = SendAddonMessage
    SendChatMessage = TestSendChatMessage
    SendAddonMessage = TestSendAddonMessage
end

local function RemoveOverrides()
    if SendChatMessage == TestSendChatMessage then SendChatMessage = origSendChatMessage end
    if SendAddonMessage == TestSendAddonMessage then SendAddonMessage = origSendAddonMessage end
end

-- ============================================================
-- 4) ECHTE DATEN SICHERN / WIEDERHERSTELLEN
-- ============================================================
-- Die echten Tabellen werden per Referenz beiseitegelegt (kein Kopieren)
-- und durch leere Test-Tabellen ersetzt. Die Sicherung liegt zusaetzlich in
-- BananaLoot_DB.testBackup und wird damit bei einem /reload mitten im Test
-- mitgespeichert -- beim naechsten Login holt RestoreFromBackup() alles
-- zurueck.
local function RestoreFromBackup(backup)
    local db = BananaLoot_DB
    db.players = backup.players
    db.lastOverwritten = backup.lastOverwritten
    db.hardReserves = backup.hardReserves
    db.bankReserves = backup.bankReserves
    db.awardedItems = backup.awardedItems
    db.log = backup.log
    db.settings.disenchanter = backup.disenchanter
    db.settings.brLooter = backup.brLooter
    BananaLoot.reservations = backup.reservations
    BananaLoot.playerReservedItems = backup.playerReservedItems
    db.testBackup = nil
    BananaLoot:SaveSession()
end

local function SeedTestData()
    local db = BananaLoot_DB
    local names = {}
    for i = 1, table.getn(TEST_ROSTER) do
        names[i] = TEST_ROSTER[i][1]
        BananaLoot.playerClasses[TEST_ROSTER[i][1]] = TEST_ROSTER[i][2]
    end
    BananaLoot.testRoster = names

    BananaLoot.testLootItems = {}
    BananaLoot.knownLootItems = {}
    BananaLoot.lootCounts = {}
    BananaLoot.lootQueue = {}
    BananaLoot.lastLootSignature = nil

    for i = 1, table.getn(TEST_ITEMS) do
        local plan = TEST_ITEMS[i]
        local info = BananaLoot:GetStaticItemInfo(plan.id)
        local name = (info and info.name) or ("Item " .. plan.id)
        if info and info.quality then BananaLoot.itemQualityHints[plan.id] = info.quality end
        local link = BananaLoot:BuildItemLink(plan.id, name)

        for c = 1, (plan.qty or 1) do
            table.insert(BananaLoot.testLootItems, { itemID = plan.id, link = link })
        end

        if plan.behavior == "hr" then
            db.hardReserves[plan.id] = { link = link }
        end
        if plan.behavior == "br" then
            db.bankReserves[plan.id] = { link = link }
        end

        if plan.reservers then
            local res = { link = link, name = name, players = {}, order = {} }
            for r = 1, table.getn(plan.reservers) do
                local pname = TEST_ROSTER[plan.reservers[r]][1]
                res.players[pname] = true
                table.insert(res.order, pname)
                BananaLoot.playerReservedItems[pname] = { plan.id }
            end
            BananaLoot.reservations[plan.id] = res
            -- SR+ Demonstration: der erste Reservierer hat dieses Item schon
            -- zweimal verloren (SR+ gilt pro Item, siehe GetStack).
            if plan.behavior == "srbonus" then
                BananaLoot:SetStack(TEST_ROSTER[plan.reservers[1]][1], plan.id, 2)
            end
        end
    end
    TEST.totalSlots = table.getn(BananaLoot.testLootItems)
    TEST.awarded = 0
    TEST.allDoneScheduled = false
end

local function EndTest(silent)
    if TEST.phase == "idle" then return end
    local wasRunning = (TEST.phase == "running")
    TEST.phase = "idle"
    TEST.scheduled = {}

    if wasRunning then
        BananaLoot.testMode = false
        BananaLoot.testRoster = nil
        BananaLoot.testLootItems = {}
        BananaLoot.testHooks = nil
        BananaLoot.activeRoll = nil
        BananaLoot.autoRunning = false
        BananaLoot.noRollItems = {}
        BananaLoot.knownLootItems = TEST.memKnown or {}
        BananaLoot.lootCounts = TEST.memCounts or {}
        BananaLoot.lootQueue = TEST.memQueue or {}
        BananaLoot.lastLootSignature = TEST.memSignature
        for i = 1, table.getn(TEST_ROSTER) do
            BananaLoot.playerClasses[TEST_ROSTER[i][1]] = nil
        end
        RemoveOverrides()
        if BananaLoot_DB.testBackup then RestoreFromBackup(BananaLoot_DB.testBackup) end
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        if not silent then
            TPrint(string.format(BananaLoot:L("TEST_ENDED"), TEST.awarded))
        end
    end
    if BananaLoot_UI and BananaLoot_UI.RefreshTest then BananaLoot_UI:RefreshTest() end
end

-- ============================================================
-- 5) VERHALTEN DER ERFUNDENEN RAIDER (Einhaengepunkte der echten Engine)
-- ============================================================
local hooks = {}

hooks.OnRollStart = function(ar)
    local plan
    for i = 1, table.getn(TEST_ITEMS) do
        if TEST_ITEMS[i].id == ar.itemID then plan = TEST_ITEMS[i] end
    end
    local beh = plan and plan.behavior or "normal"
    local me = UnitName("player")
    if beh == "nobody" or beh == "hr" then return end

    local used = {}
    used[me] = true

    if ar.srEligible then
        -- SR-Roll: die (erfundenen) Reservierer wuerfeln Hauptspec.
        local holder, other
        for name, _ in pairs(ar.srEligible) do
            if name ~= me then
                used[name] = true
                if beh == "srbonus" and BananaLoot:GetStack(name, ar.itemID) > 0 then holder = name else other = other or name end
            end
        end
        if beh == "srbonus" and holder and other then
            -- Knapper roher Rueckstand, den der SR+ Bonus wieder ausgleicht.
            local low = math.random(40, 70)
            TSimRoll(ar, holder, low, "ms", 1.5)
            TSimRoll(ar, other, low + 1, "ms", 2.2)
        else
            for name, _ in pairs(ar.srEligible) do
                if name ~= me then TSimRoll(ar, name, math.random(1, 100), "ms", TRollDelay(ar)) end
            end
        end
        -- Ein Nicht-Reservierer wuerfelt trotzdem Hauptspec -- die Engine
        -- muss diesen Wurf ignorieren.
        local outsider = TRandomFakeName(used)
        if outsider then TSimRoll(ar, outsider, math.random(1, 100), "ms", TRollDelay(ar)) end
    elseif beh == "tie" then
        local a = TRandomFakeName(used); used[a] = true
        local b = TRandomFakeName(used); used[b] = true
        local top = math.random(60, 95)
        TSimRoll(ar, a, top, "ms", 1.5)
        TSimRoll(ar, b, top, "ms", 2.0)
        for i = 1, 3 do
            local n = TRandomFakeName(used)
            if n then used[n] = true; TSimRoll(ar, n, math.random(1, top - 1), "ms", TRollDelay(ar)) end
        end
    elseif beh == "offspec" then
        for i = 1, math.random(3, 5) do
            local n = TRandomFakeName(used)
            if n then used[n] = true; TSimRoll(ar, n, math.random(1, 100), "os", TRollDelay(ar)) end
        end
    else
        for i = 1, math.random(4, 7) do
            local n = TRandomFakeName(used)
            if n then
                used[n] = true
                local rtype = (math.random(1, 100) <= 75) and "ms" or "os"
                TSimRoll(ar, n, math.random(1, 100), rtype, TRollDelay(ar))
            end
        end
    end

    -- Etwas Raid-Chat-Gemurmel zu Beginn.
    for i = 1, 2 do
        local n = TRandomFakeName({ [me] = true })
        if n then
            TSchedule(0.5 + math.random() * 2, function()
                if BananaLoot.testMode and BananaLoot.activeRoll == ar and ar.running then
                    TRaidChatFrom(n, TPick(ar.srEligible and TChatter().sr or TChatter().need))
                end
            end)
        end
    end
end

-- Gleichstand: die betroffenen erfundenen Raider wuerfeln neu (mit
-- garantiert unterschiedlichen Werten). Bist du selbst betroffen, musst du
-- selbst neu wuerfeln -- genau wie im Raid.
hooks.OnTie = function(ar)
    if not ar.restrictTo then return end
    local me = UnitName("player")
    local used = {}
    for name, _ in pairs(ar.restrictTo) do
        if name ~= me then
            local v = math.random(1, 100)
            while used[v] do v = math.random(1, 100) end
            used[v] = true
            TSimRoll(ar, name, v, "ms", 1.5 + math.random() * 1.5)
        end
    end
end

hooks.OnWinner = function(ar)
    local winners = ar.confirmedWinners
    if not winners or table.getn(winners) == 0 then return end
    local isWinner = {}
    for i = 1, table.getn(winners) do isWinner[winners[i].name] = true end

    -- Jubel des ersten (erfundenen) Gewinners und Fluch eines erfundenen
    -- Verlierers als Emotes, dazu etwas Raid-Chat.
    TSchedule(1.0, function()
        local w = winners[1].name
        if TIsFake(w) then
            TPrint("|cffff8040" .. string.format(BananaLoot:L("TEST_CHEER_" .. math.random(1, 5)), w, ar.link) .. "|r")
            TSchedule(0.8, function() TRaidChatFrom(w, TPick(TChatter().win)) end)
        end
        local losers = {}
        for name, _ in pairs(ar.rolls) do
            if not isWinner[name] and TIsFake(name) then table.insert(losers, name) end
        end
        if table.getn(losers) > 0 then
            local l = losers[math.random(1, table.getn(losers))]
            TSchedule(0.6, function()
                TPrint("|cffff8040" .. string.format(BananaLoot:L("TEST_CURSE_" .. math.random(1, 5)), l) .. "|r")
            end)
            if table.getn(losers) > 1 or not TIsFake(winners[1].name) then
                TSchedule(1.6, function() TRaidChatFrom(losers[1], TPick(TChatter().gz)) end)
            end
        end
    end)
end

hooks.OnAward = function(itemID, name)
    TEST.awarded = TEST.awarded + 1
    if BananaLoot_UI and BananaLoot_UI.RefreshTest then BananaLoot_UI:RefreshTest() end
    if table.getn(BananaLoot.testLootItems) == 0 and not TEST.allDoneScheduled then
        TEST.allDoneScheduled = true
        TPrint(string.format(BananaLoot:L("TEST_ALL_DONE"), 8))
        TSchedule(8, function() EndTest() end)
    end
end

-- ============================================================
-- 6) TESTSTART (nach dem Countdown): Daten sichern, Fake-Raid aufbauen,
-- Items "droppen" lassen -- ueber die echte OnLootOpened()-Logik, also mit
-- Loot-Erkannt-Sound, Chat-Zusammenfassung, Loot-Vorschau und automatisch
-- geoeffnetem Loot-Fenster wie bei einer echten Kiste.
-- ============================================================
local function BeginRun()
    BananaLoot.EnsureDB()
    local db = BananaLoot_DB

    db.testBackup = {
        players = db.players, lastOverwritten = db.lastOverwritten,
        hardReserves = db.hardReserves, bankReserves = db.bankReserves,
        awardedItems = db.awardedItems, log = db.log,
        disenchanter = db.settings.disenchanter, brLooter = db.settings.brLooter,
        reservations = BananaLoot.reservations,
        playerReservedItems = BananaLoot.playerReservedItems,
    }
    db.players = {}
    db.lastOverwritten = {}
    db.hardReserves = {}
    db.bankReserves = {}
    db.awardedItems = {}
    db.log = {}
    db.settings.disenchanter = TEST_DISENCHANTER
    db.settings.brLooter = TEST_BR_LOOTER
    BananaLoot.reservations = {}
    BananaLoot.playerReservedItems = {}

    TEST.memKnown = BananaLoot.knownLootItems
    TEST.memCounts = BananaLoot.lootCounts
    TEST.memQueue = BananaLoot.lootQueue
    TEST.memSignature = BananaLoot.lastLootSignature

    InstallOverrides()
    BananaLoot.testMode = true
    BananaLoot.testHooks = hooks
    TEST.phase = "running"
    SeedTestData()

    TPrint(BananaLoot:L("TEST_DROPPED"))
    TPrint(BananaLoot:L("TEST_HINT_HR"))
    BananaLoot:OnLootOpened()
    if BananaLoot_UI and BananaLoot_UI.RefreshTest then BananaLoot_UI:RefreshTest() end
end

-- ============================================================
-- 7) KLEINES STEUERFENSTER + TICKER
-- ============================================================
TEST.frame = CreateFrame("Frame", "BananaLootTestFrame", UIParent)
TEST.frame:SetWidth(380)
TEST.frame:SetHeight(180)
TEST.frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
TEST.frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
TEST.frame:SetMovable(true)
TEST.frame:EnableMouse(true)
TEST.frame:RegisterForDrag("LeftButton")
TEST.frame:SetScript("OnDragStart", function() TEST.frame:StartMoving() end)
TEST.frame:SetScript("OnDragStop", function() TEST.frame:StopMovingOrSizing() end)
TEST.frame:SetFrameStrata("HIGH")
TEST.frame:Hide()

TEST.title = TEST.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
TEST.title:SetPoint("TOP", TEST.frame, "TOP", 0, -16)
TEST.title:SetText(BananaLoot:L("WIN_TEST_TITLE"))

TEST.banner = TEST.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TEST.banner:SetPoint("TOP", TEST.frame, "TOP", 0, -40)
TEST.banner:SetTextColor(1, 0.35, 0.35)
TEST.banner:SetText(BananaLoot:L("TEST_BANNER"))

TEST.statusText = TEST.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
TEST.statusText:SetPoint("TOP", TEST.frame, "TOP", 0, -70)

TEST.lootBtn = CreateFrame("Button", "BananaLootTestLootBtn", TEST.frame, "UIPanelButtonTemplate")
TEST.lootBtn:SetWidth(160)
TEST.lootBtn:SetHeight(22)
TEST.lootBtn:SetPoint("BOTTOMLEFT", TEST.frame, "BOTTOMLEFT", 24, 22)
TEST.lootBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    if BananaLoot_UI and BananaLoot_UI.ShowLoot then BananaLoot_UI:ShowLoot() end
end)

TEST.endBtn = CreateFrame("Button", "BananaLootTestEndBtn", TEST.frame, "UIPanelButtonTemplate")
TEST.endBtn:SetWidth(150)
TEST.endBtn:SetHeight(22)
TEST.endBtn:SetPoint("BOTTOMRIGHT", TEST.frame, "BOTTOMRIGHT", -24, 22)
TEST.endBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    EndTest()
    TEST.frame:Hide()
end)

function BananaLoot_UI:RefreshTest()
    if TEST.phase == "idle" then
        TEST.frame:Hide()
        return
    end
    if TEST.phase == "countdown" then
        TEST.lootBtn:Hide()
        TEST.endBtn:SetText(BananaLoot:L("UI_BTN_TEST_CANCEL"))
        return
    end
    TEST.lootBtn:Show()
    TEST.lootBtn:SetText(BananaLoot:L("UI_BTN_TEST_OPEN_LOOT"))
    TEST.endBtn:SetText(BananaLoot:L("UI_BTN_TEST_END"))
    TEST.statusText:SetText(string.format(BananaLoot:L("TEST_STATUS"), table.getn(BananaLoot.testLootItems), TEST.totalSlots))
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function()
    if TEST.phase == "idle" then return end
    local i = 1
    while i <= table.getn(TEST.scheduled) do
        local ev = TEST.scheduled[i]
        if GetTime() >= ev.time then
            table.remove(TEST.scheduled, i)
            ev.fn()
        else
            i = i + 1
        end
    end
end)

-- ============================================================
-- 8) EINSTIEGSPUNKT (Button im Optionsfenster, Reiter Verwaltung)
-- ============================================================
function BananaLoot_UI:StartTest()
    if TEST.phase ~= "idle" then
        TPrint(BananaLoot:L("TEST_ALREADY_RUNNING"))
        TEST.frame:Show()
        BananaLoot_UI:RefreshTest()
        return
    end
    if BananaLoot.activeRoll or BananaLoot.lootWindowOpen then
        TPrint(BananaLoot:L("TEST_BLOCKED_REAL"))
        return
    end

    TEST.phase = "countdown"
    TEST.scheduled = {}
    TEST.frame:Show()
    TPrint(string.format(BananaLoot:L("TEST_COUNTDOWN_STARTING"), 10))
    TEST.statusText:SetText(string.format(BananaLoot:L("TEST_COUNTDOWN_TEXT"), 10))
    BananaLoot_UI:RefreshTest()

    for sec = 9, 0, -1 do
        TSchedule(10 - sec, function()
            if TEST.phase ~= "countdown" then return end
            if sec == 0 then
                BeginRun()
            else
                TEST.statusText:SetText(string.format(BananaLoot:L("TEST_COUNTDOWN_TEXT"), sec))
            end
        end)
    end
end

function BananaLoot_UI:ApplyLocaleTest()
    TEST.title:SetText(BananaLoot:L("WIN_TEST_TITLE"))
    TEST.banner:SetText(BananaLoot:L("TEST_BANNER"))
    BananaLoot_UI:RefreshTest()
end

-- ============================================================
-- 9) ABSTURZ-/RELOAD-SCHUTZ: wurde mitten im Test neu geladen, liegt die
-- Sicherung noch in den SavedVariables -- beim Login wird sie automatisch
-- zurueckgespielt. (Dieser Handler ist nach dem Kern-Handler registriert
-- und laeuft daher erst, nachdem EnsureDB/RestoreSession schon gelaufen sind.)
-- ============================================================
local recoverFrame = CreateFrame("Frame")
recoverFrame:RegisterEvent("ADDON_LOADED")
recoverFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "BananaLoot" then
        if BananaLoot_DB and BananaLoot_DB.testBackup then
            RestoreFromBackup(BananaLoot_DB.testBackup)
            DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("TEST_RECOVERED"))
        end
    end
end)
