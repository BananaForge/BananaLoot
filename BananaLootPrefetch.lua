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

local tip = CreateFrame("GameTooltip", "BananaLootPrefetchTooltip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

local queue, qHead, qTail = {}, 1, 0
local requested = {}   -- [itemID] = true, in dieser Sitzung bereits abgefragt
local total, done = 0, 0
local announce = false
local zoneName = nil

local function IsKnown(id)
    return GetItemInfo("item:" .. id .. ":0:0:0:0:0:0:0") ~= nil
end

local function Say(key, a, b)
    local text = BananaLoot:L(key)
    if a ~= nil then text = string.format(text, a, b) end
    DEFAULT_CHAT_FRAME:AddMessage(text)
end

local function Enabled()
    if not BananaLoot_DB or not BananaLoot_DB.settings then return true end
    return BananaLoot_DB.settings.prefetchEnabled ~= false
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

local worker = CreateFrame("Frame")
worker:Hide()
local elapsed = 0
worker:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < INTERVAL then return end
    elapsed = 0
    local id = (qHead <= qTail) and queue[qHead] or nil
    if not id then
        worker:Hide()
        if announce and total > 0 then
            Say("PREFETCH_DONE", zoneName or "?", total)
        end
        announce = false
        return
    end
    queue[qHead] = nil
    qHead = qHead + 1
    if not IsKnown(id) then
        pcall(function()
            tip:SetOwner(WorldFrame, "ANCHOR_NONE")
            tip:SetHyperlink("item:" .. id .. ":0:0:0:0:0:0:0")
        end)
    end
    done = done + 1
end)

function BananaLoot:PrefetchZoneItems(zone, verbose)
    zone = zone or GetRealZoneText()
    local ids = CollectZoneItems(zone)
    if not ids then
        if verbose then Say("PREFETCH_NO_DATA", tostring(zone)) end
        return 0
    end
    -- Rest der alten Queue behalten, neue unbekannte Items anhaengen
    local fresh, k = {}, 0
    for i = qHead, qTail do
        if queue[i] then k = k + 1; fresh[k] = queue[i] end
    end
    for id in pairs(ids) do
        if not requested[id] then
            requested[id] = true
            if not IsKnown(id) then k = k + 1; fresh[k] = id end
        end
    end
    queue, qHead, qTail = fresh, 1, k
    total, done, zoneName, announce = k, 0, zone, true
    if total > 0 then
        Say("PREFETCH_START", total, zone)
        elapsed = 0
        worker:Show()
    elseif verbose then
        Say("PREFETCH_ALL_KNOWN", zone)
    end
    return total
end

function BananaLoot:SetPrefetchEnabled(on)
    if not BananaLoot_DB then BananaLoot_DB = {} end
    if not BananaLoot_DB.settings then BananaLoot_DB.settings = {} end
    BananaLoot_DB.settings.prefetchEnabled = on and true or false
end

function BananaLoot:GetPrefetchEnabled()
    return Enabled()
end

-- Zonenwechsel -> nach kurzer Verzoegerung Instanz-Items vorladen
local pending = nil
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function()
    pending = ZONE_DELAY
    ev:Show()
end)
ev:SetScript("OnUpdate", function()
    if not pending then return end
    pending = pending - arg1
    if pending <= 0 then
        pending = nil
        if Enabled() then BananaLoot:PrefetchZoneItems(GetRealZoneText(), false) end
    end
end)
