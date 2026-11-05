-- BananaLootTest.lua
-- TESTMODUS: laesst die ECHTE BananaLoot-Engine auf einem simulierten Raid
-- laufen -- jetzt mit der neuen Raid-Struktur: Es gibt 5 vorbereitete Test-Raids
-- (Molten Core, Blackwing Lair, AQ40, Naxxramas, UBRS) mit Hard Reserve, Bankreserve,
-- Raid-Roll und SR von erfundenen Spielern. Beim Teststart wird der gewaehlte Test-
-- Raid ueber den echten Weg gestartet (Raid waehlen > Raid starten): die Listen
-- werden gesetzt, die SR erscheinen im Hauptfenster, danach landen ca. 15 Items auf
-- einen Schlag im normalen Loot-Fenster, 10 erfundene Raider wuerfeln mit
-- sichtbaren Meldungen mit, und du
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
--     vergebene Items, Wiederherstellungsliste, vorbereitete Raids, Raid-
--     Vorlagen, laufender Raid, SR-Sperre, SR-Limit) werden beim Teststart
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

-- "behavior" steuert, wie die erfundenen Raider auf einen Roll reagieren:
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
--   rr      - Raid-Roll-Item, wird beim Oeffnen automatisch unter dem Raid verlost
-- "qty" = Anzahl Kopien (je eigener Loot-Slot), "reservers" = Roster-Indizes.

-- Die 5 Test-Raids. Items, Reservierungen und Listen werden aus der Beute des Raids
-- (BananaLoot_RaidLoot) mit festem Startwert gewuerfelt: jeder Lauf mit demselben Raid ist
-- gleich, die fuenf Raids unterscheiden sich. maxSR = SR-Limit pro Spieler im Test.
local TEST_RAIDS = {
    { key = "MC",   name = "Test: Molten Core",     seed = 101, maxSR = 1 },
    { key = "BWL",  name = "Test: Blackwing Lair",  seed = 202, maxSR = 1 },
    { key = "AQ40", name = "Test: AQ40 (2 SR pro Spieler)", seed = 303, maxSR = 2 },
    { key = "NAXX", name = "Test: Naxxramas",       seed = 404, maxSR = 1 },
    { key = "UBRS", name = "Test: UBRS",            seed = 505, maxSR = 1 },
}

-- Eigener Zufallsgenerator (Park-Miller), damit der globale math.random unberuehrt bleibt.
local function MakeRng(seed)
    local state = seed
    return function(n)
        state = math.mod(state * 16807, 2147483647)
        return math.mod(state, n) + 1
    end
end

-- Baut einen Test-Raid: { name, raidKey, hr, rr, br, sr (Spieler -> IDs), items (Loot-Plan), maxSR }
local function BuildScenario(def)
    local raid = BananaLoot_RaidLoot and BananaLoot_RaidLoot[def.key]
    if not raid then return nil end
    -- Pool: alle Items des Raids mit Qualitaet >= gruen, ohne Doppelte
    local pool, seen = {}, {}
    for b = 1, table.getn(raid) do
        local ids = raid[b][2]
        for k = 1, table.getn(ids) do
            local id = ids[k]
            if not seen[id] then
                seen[id] = true
                local _, q = BananaLoot:SetupItemInfo(id)
                if q >= 2 then table.insert(pool, id) end
            end
        end
    end
    if table.getn(pool) < 20 then return nil end
    local rng = MakeRng(def.seed)
    -- mischen (Fisher-Yates)
    for k = table.getn(pool), 2, -1 do
        local r = rng(k)
        pool[k], pool[r] = pool[r], pool[k]
    end
    local nextItem = 0
    local function take()
        nextItem = nextItem + 1
        return pool[nextItem]
    end

    local sc = { name = def.name, raidKey = def.key, maxSR = def.maxSR or 1,
        hr = {}, rr = {}, br = {}, sr = {}, items = {} }
    local function add(id, behavior, extra)
        local it = { id = id, behavior = behavior }
        if extra then for k, v in pairs(extra) do it[k] = v end end
        table.insert(sc.items, it)
        return it
    end
    -- Hard Reserve (2), Bankreserve (1), Raid-Roll (2)
    for _ = 1, 2 do local id = take(); sc.hr[id] = true; add(id, "hr") end
    do local id = take(); sc.br[id] = true; add(id, "br") end
    for _ = 1, 2 do local id = take(); sc.rr[id] = true; add(id, "rr") end
    -- SR-Items (5) mit 2/2/3/1/2 Reservierern aus dem Fake-Roster (je Spieler genau eine
    -- erste SR; bei SR-Limit 2 haben ein paar Spieler zusaetzlich eine zweite)
    local counts = { 2, 2, 3, 1, 2 }
    local srItems = {}
    local player = 0
    for k = 1, 5 do
        local id = take()
        local reservers = {}
        for _ = 1, counts[k] do
            player = player + 1
            table.insert(reservers, player)
            local pname = TEST_ROSTER[player][1]
            sc.sr[pname] = { id }
        end
        table.insert(srItems, id)
        add(id, (k == 2) and "srbonus" or "sr", { reservers = reservers })
    end
    if sc.maxSR >= 2 then
        -- zweite SR: Spieler 1, 3 und 5 reservieren zusaetzlich das naechste SR-Item
        local second = { [1] = 2, [3] = 4, [5] = 1 }
        for p, k in pairs(second) do
            local pname = TEST_ROSTER[p][1]
            local id = srItems[k]
            if id and sc.sr[pname][1] ~= id then table.insert(sc.sr[pname], id) end
        end
    end
    -- Items ohne Reservierung: normal (x2 und x1), niemand, Off-Spec, Gleichstand
    add(take(), "normal", { qty = 2 })
    add(take(), "normal")
    add(take(), "nobody")
    add(take(), "offspec")
    add(take(), "tie")
    return sc
end

TEST.scenarios = nil
local function GetScenarios()
    if not TEST.scenarios then
        TEST.scenarios = {}
        for k = 1, table.getn(TEST_RAIDS) do
            TEST.scenarios[k] = BuildScenario(TEST_RAIDS[k])
        end
    end
    return TEST.scenarios
end
BananaLoot_TestScenarios = GetScenarios

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
    db.raidRolls = backup.raidRolls or {}
    db.awardedItems = backup.awardedItems
    db.log = backup.log
    db.settings.disenchanter = backup.disenchanter
    db.settings.brLooter = backup.brLooter
    -- neue Raid-Struktur (vorbereitete Raids, Vorlagen, laufender Raid, SR-Sperre/-Limit)
    db.preparedRaids = backup.preparedRaids
    db.selectedPreparedRaid = backup.selectedPreparedRaid
    db.nextPreparedId = backup.nextPreparedId
    db.raidTemplates = backup.raidTemplates
    db.raidSession = backup.raidSession
    db.currentRaidName = backup.currentRaidName
    db.settings.srLocked = backup.srLocked
    db.settings.maxSRCount = backup.maxSRCount
    BananaLoot.reservations = backup.reservations
    BananaLoot.playerReservedItems = backup.playerReservedItems
    db.testBackup = nil
    BananaLoot:SaveSession()
end

-- Fake-Roster und Loot-Slots des gewaehlten Test-Raids einspeisen. Hard Reserve, Bankreserve,
-- Raid-Roll und SR setzt der echte Raid-Start (BananaLoot_UI:StartPreparedRaid).
local function SeedTestData(sc)
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
    TEST.plan = sc.items

    for i = 1, table.getn(sc.items) do
        local plan = sc.items[i]
        local link = BananaLoot:SetupItemLink(plan.id)
        for c = 1, (plan.qty or 1) do
            table.insert(BananaLoot.testLootItems, { itemID = plan.id, link = link })
        end
        -- SR+ Demonstration: der erste Reservierer hat dieses Item schon zweimal
        -- verloren (SR+ gilt pro Item, siehe GetStack).
        if plan.behavior == "srbonus" and plan.reservers then
            BananaLoot:SetStack(TEST_ROSTER[plan.reservers[1]][1], plan.id, 2)
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
        TEST.plan = nil
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
    local list = TEST.plan or {}
    for i = 1, table.getn(list) do
        if list[i].id == ar.itemID then plan = list[i] end
    end
    local beh = plan and plan.behavior or "normal"
    local me = UnitName("player")
    if beh == "nobody" or beh == "hr" or beh == "rr" or beh == "br" then return end

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
    local scenarios = GetScenarios()
    local chosen = TEST.chosen or 1
    if not scenarios[chosen] then
        TPrint(BananaLoot:L("TEST_NO_SCENARIO"))
        TEST.phase = "idle"
        BananaLoot_UI:RefreshTest()
        return
    end

    db.testBackup = {
        players = db.players, lastOverwritten = db.lastOverwritten,
        hardReserves = db.hardReserves, bankReserves = db.bankReserves,
        raidRolls = db.raidRolls,
        awardedItems = db.awardedItems, log = db.log,
        disenchanter = db.settings.disenchanter, brLooter = db.settings.brLooter,
        preparedRaids = db.preparedRaids, selectedPreparedRaid = db.selectedPreparedRaid,
        nextPreparedId = db.nextPreparedId, raidTemplates = db.raidTemplates,
        raidSession = db.raidSession, currentRaidName = db.currentRaidName,
        srLocked = db.settings.srLocked, maxSRCount = db.settings.maxSRCount,
        reservations = BananaLoot.reservations,
        playerReservedItems = BananaLoot.playerReservedItems,
    }
    db.players = {}
    db.lastOverwritten = {}
    db.hardReserves = {}
    db.bankReserves = {}
    db.raidRolls = {}
    db.awardedItems = {}
    db.log = {}
    db.preparedRaids = {}
    db.selectedPreparedRaid = nil
    db.raidTemplates = {}
    db.raidSession = nil
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

    -- Alle 5 Test-Raids als vorbereitete Raids anlegen (sichtbar in der Raid-Liste, mit
    -- Code, Hard Reserve, Bankreserve, Raid-Roll und SR der erfundenen Spieler).
    local entries = {}
    for k = 1, table.getn(scenarios) do
        local sc = scenarios[k]
        if sc then
            local e = BananaLoot:SavePreparedRaid(nil, sc.name, sc.raidKey, sc.hr, sc.rr, sc.br)
            e.sr = {}
            for pname, ids in pairs(sc.sr) do e.sr[pname] = ids end
            entries[k] = e
        end
    end
    local sc = scenarios[chosen]
    db.settings.maxSRCount = sc.maxSR

    -- Gewaehlten Raid ueber den ECHTEN Weg starten: auswaehlen, dann "Raid starten"
    -- (Listen setzen, SR ins Hauptfenster, SR-Liste sperren).
    BananaLoot:SelectPreparedRaid(entries[chosen].id)
    SeedTestData(sc)
    BananaLoot_UI:StartPreparedRaid(entries[chosen].id)
    local srFrame = getglobal("BananaLootSRFrame")
    if srFrame then srFrame:Show() end
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end

    TPrint(string.format(BananaLoot:L("TEST_RAID_READY"), sc.name))
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
BananaLoot_Theme.Darken(TEST.frame)
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
-- Auswahlfenster: welcher der 5 Test-Raids soll laufen?
TEST.pick = CreateFrame("Frame", "BananaLootTestPickFrame", UIParent)
TEST.pick:SetWidth(520)
TEST.pick:SetHeight(300)
TEST.pick:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
TEST.pick:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
BananaLoot_Theme.Darken(TEST.pick)
TEST.pick:SetMovable(true)
TEST.pick:EnableMouse(true)
TEST.pick:RegisterForDrag("LeftButton")
TEST.pick:SetScript("OnDragStart", function() TEST.pick:StartMoving() end)
TEST.pick:SetScript("OnDragStop", function() TEST.pick:StopMovingOrSizing() end)
TEST.pick:SetFrameStrata("DIALOG")
TEST.pick:Hide()
TEST.pickClose = CreateFrame("Button", "BananaLootTestPickClose", TEST.pick, "UIPanelCloseButton")
TEST.pickClose:SetPoint("TOPRIGHT", TEST.pick, "TOPRIGHT", -4, -4)
TEST.pickClose:SetScript("OnClick", function() BananaLoot:PlayClickSound(); TEST.pick:Hide() end)
TEST.pickTitle = TEST.pick:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
TEST.pickTitle:SetPoint("TOP", TEST.pick, "TOP", 0, -16)
TEST.pickHint = TEST.pick:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
TEST.pickHint:SetPoint("TOP", TEST.pick, "TOP", 0, -40)
TEST.pickHint:SetWidth(470)
TEST.pickBtns = {}
for k = 1, table.getn(TEST_RAIDS) do
    local b = CreateFrame("Button", "BananaLootTestPickBtn" .. k, TEST.pick, "UIPanelButtonTemplate")
    b:SetWidth(470)
    b:SetHeight(34)
    b:SetPoint("TOPLEFT", TEST.pick, "TOPLEFT", 25, -68 - (k - 1) * 40)
    b.idx = k
    b:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        TEST.pick:Hide()
        BananaLoot_UI:StartTest(this.idx)
    end)
    TEST.pickBtns[k] = b
end

local function CountSet(t)
    local n = 0
    if t then for _ in pairs(t) do n = n + 1 end end
    return n
end

function BananaLoot_UI:ShowTestPick()
    local scenarios = GetScenarios()
    TEST.pickTitle:SetText(BananaLoot:L("TEST_PICK_TITLE"))
    TEST.pickHint:SetText(BananaLoot:L("TEST_PICK_HINT"))
    for k = 1, table.getn(TEST.pickBtns) do
        local sc = scenarios[k]
        if sc then
            local srItems, players = {}, 0
            for _, ids in pairs(sc.sr) do
                players = players + 1
                for i = 1, table.getn(ids) do srItems[ids[i]] = true end
            end
            TEST.pickBtns[k]:SetText(string.format(BananaLoot:L("TEST_PICK_ROW"), sc.name,
                CountSet(sc.hr), CountSet(sc.br), CountSet(sc.rr), players))
            TEST.pickBtns[k]:Enable()
        else
            TEST.pickBtns[k]:SetText(TEST_RAIDS[k].name .. " (" .. BananaLoot:L("TEST_PICK_NODATA") .. ")")
            TEST.pickBtns[k]:Disable()
        end
    end
    TEST.pick:Show()
end

function BananaLoot_UI:StartTest(idx)
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
    if not idx then
        -- erst den Test-Raid waehlen
        BananaLoot_UI:ShowTestPick()
        return
    end
    TEST.chosen = idx

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
    if TEST.pick:IsShown() then BananaLoot_UI:ShowTestPick() end
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
