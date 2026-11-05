-- BananaLootPrefetch.lua
-- Laedt beim Betreten einer Instanz (Dungeon/Raid) alle Items vor, die dort
-- droppen koennen und dem Client noch unbekannt sind.
--
-- Hintergrund: Das Blizzard-Wuerfelfenster zeigt fuer Items, die der Client noch
-- nie gesehen hat, nur ein Fragezeichen ohne Tooltip. Eine Tooltip-Abfrage per
-- SetHyperlink("item:ID...") veranlasst den Client, das Item beim Server
-- anzufragen und lokal zu cachen. Das passiert hier gedrosselt im Hintergrund.
--
-- Rein lokal: keine Addon-Nachrichten, das Roll-Sync-Protokoll bleibt unberuehrt.
--
-- Gemerkt wird dauerhaft (SavedVariables, BananaLoot_DB.prefetchSeen), welche Items schon
-- angefragt wurden: so wird nicht bei jedem Zonenwechsel/Login alles erneut abgefragt, auch
-- wenn der Server einzelne Items nie beantwortet. Am Ende meldet der Chat, wie viele Items
-- der Client jetzt kennt. Die Anzeige in BananaLoot haengt nicht davon ab: Name, Qualitaet
-- und Icon kommen aus der mitgelieferten Item-Datenbank (BananaLootItemDB/ItemInfoExtra).
--
-- Befehle: /bl prefetch (aktuelle Zone, erzwingt), /bl prefetch all (alle Instanzen),
--          /bl prefetch on|off (Zonen-Vorladen), /bl prefetch auto on|off (alles im Hintergrund).
-- Daten: BananaLootZoneLoot.lua (Quelle: AtlasLoot Turtle WoW Edition).
-- Sprachtexte: LOCALE-Tabellen in BananaLoot.lua (Schluessel PREFETCH_*).
-- Einstellung: BananaLoot_DB.settings.prefetchEnabled (Standard: an).
--
-- Lua 5.0: kein #-Operator, kein string.gmatch; Queue mit Head-/Tail-Index.

local INTERVAL = 0.25   -- Sekunden zwischen zwei Abfragen (kein Lag/Disconnect-Risiko)
local ZONE_DELAY = 3    -- Sekunden Wartezeit nach Zonenwechsel (Zonentext ist anfangs oft noch leer)

-- Lokalisierte bzw. abweichende Zonennamen -> Schluessel in BananaLoot_ZoneLoot.
-- Ein Schluessel gilt auch fuer alle Eintraege "<Schluessel> (...)", z.B. werden
-- alle Fluegel von Scarlet Monastery / Dire Maul zusammen geladen.
-- ACHTUNG: Die deutschen Namen sind nicht ingame geprueft.
local ZONE_ALIASES = {
    -- deutsche Clients
    ["Flammenschlund"] = "Ragefire Chasm",
    ["Der Flammenschlund"] = "Ragefire Chasm",
    ["Höhlen des Wehklagens"] = "Wailing Caverns",
    ["Die Todesminen"] = "The Deadmines",
    ["Burg Schattenfang"] = "Shadowfang Keep",
    ["Das Verlies"] = "The Stockade",
    ["Tiefschwarze Grotte"] = "Blackfathom Deeps",
    ["Gnomeregan"] = "Gnomeregan",
    ["Kral der Klingenhauer"] = "Razorfen Kraul",
    ["Hügel der Klingenhauer"] = "Razorfen Downs",
    ["Scharlachrotes Kloster"] = "Scarlet Monastery",
    ["Uldaman"] = "Uldaman",
    ["Maraudon"] = "Maraudon",
    ["Zul'Farrak"] = "Zul'Farrak",
    ["Der Tempel von Atal'Hakkar"] = "The Sunken Temple",
    ["Versunkener Tempel"] = "The Sunken Temple",
    ["Die Schwarzfelstiefen"] = "Blackrock Depths",
    ["Schwarzfelstiefen"] = "Blackrock Depths",
    ["Düsterbruch"] = "Dire Maul",
    ["Scholomance"] = "Scholomance",
    ["Stratholme"] = "Stratholme",
    ["Untere Schwarzfelsspitze"] = "Lower Blackrock Spire",
    ["Obere Schwarzfelsspitze"] = "Upper Blackrock Spire",
    ["Zul'Gurub"] = "Zul'Gurub",
    ["Ruinen von Ahn'Qiraj"] = "Ruins of Ahn'Qiraj",
    ["Tempel von Ahn'Qiraj"] = "Temple of Ahn'Qiraj",
    ["Onyxias Hort"] = "Onyxia's Lair",
    ["Geschmolzener Kern"] = "Molten Core",
    ["Pechschwingenhort"] = "Blackwing Lair",
    ["Naxxramas"] = "Naxxramas",
    -- Namensabweichungen auf Turtle WoW
    ["Black Morass"] = "Caverns of Time: Black Morass",
    ["The Black Morass"] = "Caverns of Time: Black Morass",
}

local SEEN_SECONDS = 3 * 86400   -- so lange gilt ein Item als "bereits angefragt"
local GRACE = 6                    -- Sekunden nach der letzten Anfrage bis zur Auswertung
local AUTO_DELAY = 30              -- Sekunden nach dem Login bis "alles vorladen" startet

local tip = CreateFrame("GameTooltip", "BananaLootPrefetchTooltip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

local queue, qHead, qTail = {}, 1, 0
local ran = {}            -- Items dieses Laufs (zur Auswertung)
local total, done = 0, 0
local mode = nil          -- "zone" | "all"
local zoneName = nil
local finishAt = nil
local nextProgress = 25

local function IsKnown(id)
    return GetItemInfo("item:" .. id .. ":0:0:0:0:0:0:0") ~= nil
end

local function Say(key, a, b, c)
    local text = BananaLoot:L(key)
    if a ~= nil then text = string.format(text, a, b, c) end
    DEFAULT_CHAT_FRAME:AddMessage(text)
end

local function Enabled()
    if not BananaLoot_DB or not BananaLoot_DB.settings then return true end
    return BananaLoot_DB.settings.prefetchEnabled ~= false
end

local function Seen()
    BananaLoot.EnsureDB()
    if not BananaLoot_DB.prefetchSeen then BananaLoot_DB.prefetchSeen = {} end
    return BananaLoot_DB.prefetchSeen
end

-- Sammelt alle Item-IDs der Instanz zum aktuellen Zonennamen.
local function CollectZoneItems(zone)
    local data = BananaLoot_ZoneLoot
    if not data or not zone or zone == "" then return nil end
    local key = ZONE_ALIASES[zone] or zone
    local ids, any = {}, false
    for name, list in pairs(data) do
        if name == key or string.sub(name, 1, string.len(key) + 2) == key .. " (" then
            any = true
            for i = 1, table.getn(list) do ids[list[i]] = true end
        end
    end
    if not any then return nil end
    return ids
end

-- Alle Items aller Instanzen (Beutetabellen + Raid-Beute).
local function CollectAllItems()
    local ids = {}
    if BananaLoot_ZoneLoot then
        for _, list in pairs(BananaLoot_ZoneLoot) do
            for i = 1, table.getn(list) do ids[list[i]] = true end
        end
    end
    if BananaLoot_RaidLoot then
        for _, raid in pairs(BananaLoot_RaidLoot) do
            for b = 1, table.getn(raid) do
                local l = raid[b][2]
                for i = 1, table.getn(l) do ids[l[i]] = true end
            end
        end
    end
    return ids
end

local worker = CreateFrame("Frame")
worker:Hide()
local elapsed = 0
worker:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < INTERVAL then return end
    elapsed = 0
    local id = (qHead <= qTail) and queue[qHead] or nil
    if not id then
        -- Queue leer: kurz warten, damit die Serverantworten eintreffen, dann auswerten
        if not finishAt then finishAt = GetTime() + GRACE end
        if GetTime() >= finishAt then
            finishAt = nil
            worker:Hide()
            if total > 0 then
                local bad = 0
                for i = 1, table.getn(ran) do
                    if not IsKnown(ran[i]) then bad = bad + 1 end
                end
                if mode == "all" then
                    Say("PREFETCH_SUMMARY_ALL", total - bad, total, bad)
                else
                    Say("PREFETCH_SUMMARY", zoneName or "?", total - bad, total)
                    if bad > 0 then Say("PREFETCH_UNANSWERED", bad) end
                end
            end
            ran = {}
            mode = nil
        end
        return
    end
    queue[qHead] = nil
    qHead = qHead + 1
    pcall(function()
        tip:SetOwner(WorldFrame, "ANCHOR_NONE")
        tip:SetHyperlink("item:" .. id .. ":0:0:0:0:0:0:0")
    end)
    done = done + 1
    if mode == "all" and total > 0 then
        local pct = math.floor(done * 100 / total)
        if pct >= nextProgress and nextProgress < 100 then
            Say("PREFETCH_PROGRESS", nextProgress, done, total)
            nextProgress = nextProgress + 25
        end
    end
end)

-- ids einreihen: nur Items, die der Client nicht kennt und die nicht kuerzlich angefragt wurden
-- (force: auch kuerzlich angefragte). Rueckgabe: Anzahl neu eingereihter Items.
local function Enqueue(ids, force)
    local seen = Seen()
    local now = time()
    local fresh, k = {}, 0
    for i = qHead, qTail do
        if queue[i] then k = k + 1; fresh[k] = queue[i] end
    end
    local queued = {}
    for i = 1, k do queued[fresh[i]] = true end
    local added = 0
    for id in pairs(ids) do
        if not queued[id] and not IsKnown(id) then
            local t = seen[id]
            if force or not t or (now - t) > SEEN_SECONDS then
                seen[id] = now
                k = k + 1; fresh[k] = id
                ran[table.getn(ran) + 1] = id
                added = added + 1
            end
        end
    end
    queue, qHead, qTail = fresh, 1, k
    return added
end

function BananaLoot:PrefetchZoneItems(zone, verbose, force)
    zone = zone or GetRealZoneText()
    local ids = CollectZoneItems(zone)
    if not ids then
        if verbose then Say("PREFETCH_NO_DATA", tostring(zone)) end
        return 0
    end
    if mode == "all" then
        -- Der Gesamtlauf deckt diese Zone ohnehin ab; nur nach vorne ziehen, wenn erzwungen.
        if not force then return 0 end
    end
    local added = Enqueue(ids, force)
    if added > 0 then
        if mode ~= "all" then
            total, done, zoneName, mode = added, 0, zone, "zone"
            Say("PREFETCH_START", added, zone)
        else
            total = total + added
        end
        elapsed = 0
        finishAt = nil
        worker:Show()
    elseif verbose then
        Say("PREFETCH_ALL_KNOWN", zone)
    end
    return added
end

-- Alle Instanz-Items im Hintergrund vorladen (4 pro Sekunde).
function BananaLoot:PrefetchAllItems(verbose, force)
    if mode == "all" then
        if verbose then Say("PREFETCH_ALL_RUNNING") end
        return 0
    end
    local added = Enqueue(CollectAllItems(), force)
    if added > 0 then
        total, done, mode, zoneName = added, 0, "all", nil
        nextProgress = 25
        Say("PREFETCH_START_ALL", added, math.ceil(added * INTERVAL / 60))
        elapsed = 0
        finishAt = nil
        worker:Show()
    elseif verbose then
        Say("PREFETCH_ALL_KNOWN_ALL")
    end
    return added
end

function BananaLoot:SetPrefetchEnabled(on)
    if not BananaLoot_DB then BananaLoot_DB = {} end
    if not BananaLoot_DB.settings then BananaLoot_DB.settings = {} end
    BananaLoot_DB.settings.prefetchEnabled = on and true or false
end

function BananaLoot:GetPrefetchEnabled()
    return Enabled()
end

-- Alles im Hintergrund vorladen (Standard: an; nach dem Login, einmalig je Merkzeitraum)
function BananaLoot:GetPrefetchAutoAll()
    BananaLoot.EnsureDB()
    return BananaLoot_DB.settings.prefetchAutoAll ~= false
end

function BananaLoot:SetPrefetchAutoAll(on)
    BananaLoot.EnsureDB()
    BananaLoot_DB.settings.prefetchAutoAll = on and true or false
end

-- Zonenwechsel -> nach kurzer Verzoegerung Instanz-Items vorladen; Login -> alles vorladen
local pending = nil
local autoAt = nil
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        autoAt = AUTO_DELAY
    else
        pending = ZONE_DELAY
    end
    ev:Show()
end)
ev:SetScript("OnUpdate", function()
    if pending then
        pending = pending - arg1
        if pending <= 0 then
            pending = nil
            if Enabled() then BananaLoot:PrefetchZoneItems(GetRealZoneText(), false) end
        end
    end
    if autoAt then
        autoAt = autoAt - arg1
        if autoAt <= 0 then
            autoAt = nil
            if Enabled() and BananaLoot:GetPrefetchAutoAll() then BananaLoot:PrefetchAllItems(false) end
        end
    end
end)
