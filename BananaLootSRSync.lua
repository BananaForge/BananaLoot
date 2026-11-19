-- BananaLootSRSync.lua
-- SR+-Uebersicht: BananaLoot (Loot-Master) schickt die Reservierungen samt SR+ der lokal angelegten Raids per
-- Addon-Nachricht an BananaLoot Raider (Raid-/Gruppen- und Gildenchat); Raider zeigt sie als Liste und als Tooltip.
--
-- Nachrichten (Praefix "BananaLoot", "~"-getrennt):
--   OB~id~A|N~raidKey~name       Beginn eines Raids (A = aktiver/laufender bzw. ausgewaehlter Raid)
--   OI~id~itemID~teil~N:p,N:p    Reservierer eines Items mit SR+ (teil 1 ersetzt, danach angehaengt)
--   OE~id~anzahl                 Ende; erst jetzt uebernimmt Raider die Daten
--   OQ~cur|all                   Raider -> Loot-Master: Uebersicht (erneut) senden
--
-- Wann gesendet wird: beim Raid-Start (Raid + Gilde), bei Aenderungen der Reservierungen/des SR+ des aktiven Raids
-- (Raid/Gruppe, nicht Gilde, hoechstens alle 40 s), auf Anfrage (OQ) und per Knopf "Raider-Sync" (alle Raids).
--
-- Lua 5.0: kein #-Operator, kein %-Operator, kein string.gmatch.

local PART_LIMIT = 190      -- Zeichen der Spielerliste je OI-Nachricht
local AUTO_CHECK = 15       -- Sekunden zwischen zwei Aenderungs-Pruefungen
local AUTO_MIN_GAP = 40     -- Mindestabstand zwischen zwei automatischen Sendungen
local REPLY_GAP = 30        -- Anfragen (OQ) hoechstens alle 30 s beantworten

local S = { lastSig = nil, lastSend = 0, lastReply = 0 }
BananaLoot_SRSyncState = S

-- ------------------------------------------------------------
-- Einstellungen
-- ------------------------------------------------------------
function BananaLoot:GetSRSyncAuto()
    BananaLoot.EnsureDB()
    if BananaLoot_DB.settings.srSyncAuto == nil then return true end
    return BananaLoot_DB.settings.srSyncAuto
end
function BananaLoot:SetSRSyncAuto(v)
    BananaLoot.EnsureDB()
    BananaLoot_DB.settings.srSyncAuto = v and true or false
end

-- ------------------------------------------------------------
-- Daten aufbauen
-- ------------------------------------------------------------
local function Clean(s)
    s = string.gsub(s or "", "~", "-")
    return string.sub(s, 1, 30)
end

-- Welcher Raid ist "aktiv"? laufender Raid, sonst ausgewaehlter vorbereiteter Raid. Rueckgabe: entry (kann nil sein), running
function BananaLoot:SRSyncActiveRaid()
    local session = self:GetRaidSession()
    local running = session and session.running
    if running then
        local e = session.preparedId and self:GetPreparedRaid(session.preparedId) or nil
        return e, true, session
    end
    return self:GetSelectedPreparedRaid(), false, session
end

-- Ergebnis: { id, name, key, active, items = { [itemID] = { { n = Name, p = SR+ }, ... } } }
function BananaLoot:BuildSROverview(entry, active, session)
    local ov = { id = 0, name = "", key = "", active = active and true or false, items = {} }
    if entry then
        ov.id, ov.name, ov.key = entry.id or 0, entry.name or "", entry.raidKey or ""
    elseif session then
        ov.name, ov.key = session.raidName or "", session.raidKey or ""
    end
    local bonus = self:GetBonusPerStack() or 0
    local function add(itemID, player)
        if not ov.items[itemID] then ov.items[itemID] = {} end
        table.insert(ov.items[itemID], { n = player, p = (self:GetStack(player, itemID) or 0) * bonus })
    end
    if active then
        -- laufender/ausgewaehlter Raid: die aktuellen Reservierungen (auch per Fluestern eingegangene)
        for itemID, res in pairs(self.reservations or {}) do
            if res and res.order then
                for i = 1, table.getn(res.order) do
                    local name = res.order[i]
                    if not (res.temp and res.temp[name]) then add(itemID, name) end
                end
            end
        end
    elseif entry then
        for player, ids in pairs(entry.sr or {}) do
            for i = 1, table.getn(ids) do add(ids[i], player) end
        end
    end
    for itemID, list in pairs(ov.items) do
        table.sort(list, function(a, b)
            if a.p ~= b.p then return a.p > b.p end
            return a.n < b.n
        end)
    end
    return ov
end

local function SortedItemIds(ov)
    local ids = {}
    for id in pairs(ov.items) do table.insert(ids, id) end
    table.sort(ids)
    return ids
end

local function Signature(ov)
    local sig = 0
    local ids = SortedItemIds(ov)
    for i = 1, table.getn(ids) do
        local list = ov.items[ids[i]]
        for k = 1, table.getn(list) do
            sig = math.mod(sig * 31 + ids[i] + list[k].p * 7 + string.len(list[k].n) * 3 + (string.byte(list[k].n, 1) or 0), 1000003)
        end
    end
    return ov.id .. ":" .. table.getn(ids) .. ":" .. sig
end

-- ------------------------------------------------------------
-- Senden
-- ------------------------------------------------------------
local function Out(msg, channel)
    if BananaLoot.testMode then
        if BananaLoot.TestRouteSync then BananaLoot:TestRouteSync(msg) end
        return
    end
    if BananaLoot.CodeQueueSend then BananaLoot.CodeQueueSend(msg, channel) end
end

function BananaLoot:SRSyncChannels(includeGuild)
    if self.testMode then return { "TEST" } end
    local list = {}
    if GetNumRaidMembers() > 0 then table.insert(list, "RAID")
    elseif GetNumPartyMembers() > 0 then table.insert(list, "PARTY") end
    if includeGuild and GetGuildInfo and GetGuildInfo("player") then table.insert(list, "GUILD") end
    return list
end

local function SendOverview(ov, channels)
    local ids = SortedItemIds(ov)
    for c = 1, table.getn(channels) do
        local ch = channels[c]
        Out("OB~" .. ov.id .. "~" .. (ov.active and "A" or "N") .. "~" .. Clean(ov.key) .. "~" .. Clean(ov.name), ch)
        for i = 1, table.getn(ids) do
            local list = ov.items[ids[i]]
            local part, text, n = 1, "", 0
            for k = 1, table.getn(list) do
                local piece = list[k].n .. ":" .. list[k].p
                if n > 0 and string.len(text) + string.len(piece) + 1 > PART_LIMIT then
                    Out("OI~" .. ov.id .. "~" .. ids[i] .. "~" .. part .. "~" .. text, ch)
                    part, text, n = part + 1, "", 0
                end
                text = text .. (n > 0 and "," or "") .. piece
                n = n + 1
            end
            if n > 0 then Out("OI~" .. ov.id .. "~" .. ids[i] .. "~" .. part .. "~" .. text, ch) end
        end
        Out("OE~" .. ov.id .. "~" .. table.getn(ids), ch)
    end
end

-- scope "cur" = nur der aktive Raid, "all" = alle vorbereiteten Raids. Rueckgabe: Raids, Items, Kanaele (oder nil, "grund")
function BananaLoot:SyncOverview(scope, includeGuild, channels)
    channels = channels or self:SRSyncChannels(includeGuild)
    if table.getn(channels) == 0 then return nil, "nochannel" end
    local activeEntry, running, session = self:SRSyncActiveRaid()
    local raids, items = 0, 0
    local function send(ov)
        SendOverview(ov, channels)
        raids = raids + 1
        for _ in pairs(ov.items) do items = items + 1 end
    end
    if scope == "all" then
        local list = self:GetPreparedRaids()
        for i = 1, table.getn(list) do
            local e = list[i]
            local isActive = activeEntry and activeEntry.id == e.id
            send(self:BuildSROverview(e, isActive, isActive and session or nil))
        end
        if running and not activeEntry then send(self:BuildSROverview(nil, true, session)) end
    else
        if activeEntry or running then send(self:BuildSROverview(activeEntry, true, session)) end
    end
    if raids == 0 then return nil, "noraid" end
    S.lastSend = GetTime()
    return raids, items, table.getn(channels)
end

-- Knopf "Raider-Sync" / /bl sync: alle Raids, Gruppe + Gilde
function BananaLoot:SyncOverviewManual()
    local raids, items, n = self:SyncOverview("all", true)
    if raids then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L("SRS_SENT"), raids, items, n))
    elseif items == "nochannel" then
        DEFAULT_CHAT_FRAME:AddMessage(self:L("SRS_NOGROUP"))
    else
        DEFAULT_CHAT_FRAME:AddMessage(self:L("SRS_NORAID"))
    end
end

-- Raid-Start: sofort (aktiver Raid, Gruppe + Gilde)
function BananaLoot:SRSyncOnRaidStart()
    if not self:GetSRSyncAuto() then return end
    S.lastSig = nil
    self:SyncOverview("cur", true)
    local entry, running, session = self:SRSyncActiveRaid()
    if entry or running then S.lastSig = Signature(self:BuildSROverview(entry, true, session)) end
end

-- Anfrage eines Raiders (OQ). Antwort nur ueber den Kanal der Anfrage; hoechstens alle 30 s.
function BananaLoot:SRSyncOnRequest(arg, channel)
    local now = GetTime()
    if not self.testMode and now - S.lastReply < REPLY_GAP then return end
    S.lastReply = now
    local channels = { channel }
    if self.testMode then channels = { "TEST" } end
    self:SyncOverview(arg == "all" and "all" or "cur", false, channels)
end

-- ------------------------------------------------------------
-- Automatische Sendung bei Aenderungen (nur Gruppe/Raid-Kanal)
-- ------------------------------------------------------------
local ticker = CreateFrame("Frame")
ticker.elapsed = 0
ticker:SetScript("OnUpdate", function()
    ticker.elapsed = ticker.elapsed + (arg1 or 0)
    if ticker.elapsed < AUTO_CHECK then return end
    ticker.elapsed = 0
    if not BananaLoot.GetSRSyncAuto or not BananaLoot:GetSRSyncAuto() then return end
    if not (BananaLoot.testMode or GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0) then return end
    local entry, running, session = BananaLoot:SRSyncActiveRaid()
    if not (entry or running) then return end
    local sig = Signature(BananaLoot:BuildSROverview(entry, true, session))
    if sig == S.lastSig then return end
    if GetTime() - S.lastSend < AUTO_MIN_GAP then return end
    S.lastSig = sig
    BananaLoot:SyncOverview("cur", false)
end)

-- Test: nach dem Teststart die Uebersicht aller Test-Raids an Raider schicken
function BananaLoot:SRSyncTestStart()
    S.lastSig = nil
    self:SyncOverview("all", false)
end
