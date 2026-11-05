-- BananaLootRaidCode.lua
-- Raid-Code: Verbindung zwischen BananaLoot (Loot-Master) und BananaLoot Raider.
--
-- Jeder vorbereitete Raid bekommt einen Code (z.B. MC-7K3Q). Raider geben ihn in
-- BananaLoot Raider ein, waehlen ihre SR-Items aus der Beute des Raids und senden
-- sie per Addon-Nachricht in den Raid-Chat (ohne Raid: Gruppe bzw. Gilde). Jeder
-- BananaLoot-Client, der den Raid kennt (Ersteller oder per Code geladener
-- Stellvertreter), nimmt die SR entgegen -- faellt der Loot-Master aus, bekommt der
-- Stellvertreter dieselben Informationen.
--
-- Vor dem Raid-Start landen SR im vorbereiteten Raid (entry.sr) und werden beim
-- Start in die Reservierungen uebernommen; danach ist die SR-Liste gesperrt. Der
-- Raid-Leiter kann sie mit dem Sperr-Button im Hauptfenster wieder oeffnen
-- (z.B. vor einem bestimmten Boss); dann gehen SR direkt in die Reservierungen.
--
-- Nachrichten (Praefix "BananaLoot", "~"-getrennt, Kanal RAID/PARTY/GUILD):
--   SR~code~spieler~id,id      Raider -> Hosts: komplette SR-Liste (ersetzt die alte)
--   SQ~code                    Raider -> Hosts: Status + Listen anfragen
--   SJ~code                    Stellvertreter -> Hosts: Raid komplett laden
--   SS~code~O|C~max~raid~name  Host: SR offen/geschlossen, max. SR, Raid-Typ, Name
--   SH~code~H|R~id,id,...      Host: Hard-Reserve- bzw. Raid-Roll-Items (in Bloecken)
--   SD~code~spieler~id,id      Host: SR-Liste eines Spielers (nur beim Laden per SJ)
--   SA~code~spieler~OK~n~skip  Host: SR angenommen (n Items, skip uebersprungen)
--   SA~code~spieler~ERR~grund  Host: abgelehnt (closed, limit, unknown)
--   SW                         Raider -> Host: "welcher Raid laeuft in meiner Gruppe?"
--                              (nur ueber RAID/PARTY, nie ueber GUILD)
--   SC~code~name~O|C           Host: Code des aktiven Raids (Antwort auf SW)
--   HQ / HA~version / RV~version  "wer hat BananaLoot?" / BananaLoot antwortet mit seiner Version /
--                              BananaLoot Raider antwortet mit seiner Version (Raid-Lead abgeben, /bl version)
--   HO~code~spieler            neuer Raid-Leiter: laedt den Raid automatisch (wie SJ)
--
-- Lua 5.0: kein #-Operator, kein %-Operator, kein string.gmatch/match, Events ueber
-- this/arg1.

local PREFIX = "BananaLoot"
local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local SEND_INTERVAL = 0.2   -- Sekunden zwischen zwei Addon-Nachrichten (Flood-Schutz)
local CHUNK = 28            -- Item-IDs pro SH-Nachricht

local C = {
    queue = {}, qHead = 1, qTail = 0,
    timers = {},
    seen = {},       -- ["S|code"] / ["A|code|spieler"] = Zeit der zuletzt gesehenen Antwort anderer
    lastMsg = {},    -- [sender] = Zeit der letzten SR-Nachricht (Spam-Schutz)
    joining = {},    -- [code] = Startzeit
    hasAddon = {},   -- [spieler] = BananaLoot-Version (Antwort auf HQ)
    raiderVersion = {},  -- [spieler] = BananaLoot-Raider-Version (Antwort auf HQ)
}
BananaLoot_CodeState = C

local function Split(str, sep)
    local result = {}
    local start = 1
    while true do
        local s, e = string.find(str, sep, start, true)
        if not s then
            table.insert(result, string.sub(str, start))
            break
        end
        table.insert(result, string.sub(str, start, s - 1))
        start = e + 1
    end
    return result
end

local function IdsToList(str)
    local ids = {}
    if not str or str == "" then return ids end
    local parts = Split(str, ",")
    for i = 1, table.getn(parts) do
        local n = tonumber(parts[i])
        if n then table.insert(ids, n) end
    end
    return ids
end

local function SetToSortedList(set)
    local list = {}
    if set then
        for id, v in pairs(set) do if v then table.insert(list, id) end end
    end
    table.sort(list)
    return list
end

-- Code normalisieren: Grossbuchstaben, ohne Leerzeichen.
function BananaLoot:NormalizeRaidCode(code)
    if not code then return "" end
    code = string.upper(code)
    code = string.gsub(code, "%s", "")
    return code
end

-- ============================================================
-- 1) CODES
-- ============================================================
function BananaLoot:GenerateRaidCode(key)
    BananaLoot.EnsureDB()
    math.randomseed(time() + math.floor(GetTime() * 1000))
    local code
    for _ = 1, 50 do
        local s = ""
        for _ = 1, 4 do
            local n = math.random(1, string.len(ALPHABET))
            s = s .. string.sub(ALPHABET, n, n)
        end
        code = (key or "RAID") .. "-" .. s
        if not self:FindPreparedByCode(code) then break end
    end
    return code
end

function BananaLoot:FindPreparedByCode(code)
    code = self:NormalizeRaidCode(code)
    if code == "" then return nil end
    local list = self:GetPreparedRaids()
    for i = 1, table.getn(list) do
        if list[i].code == code then return list[i] end
    end
    return nil
end

-- Sorgt dafuer, dass ein vorbereiteter Raid Code, SR-Status und SR-Liste hat.
function BananaLoot:EnsurePreparedCode(entry)
    if not entry then return end
    if not entry.code then entry.code = self:GenerateRaidCode(entry.raidKey) end
    if entry.srOpen == nil then entry.srOpen = true end
    if not entry.sr then entry.sr = {} end
end

function BananaLoot:CountPreparedSR(entry)
    local n = 0
    if entry and entry.sr then
        for _ in pairs(entry.sr) do n = n + 1 end
    end
    return n
end

-- Ist der Raid gerade der laufende Raid dieser Sitzung?
function BananaLoot:IsRunningPrepared(entry)
    local session = self:GetRaidSession()
    return session and session.running and entry and session.preparedId == entry.id
end

-- Ist der Raid der im Hauptfenster ausgewaehlte (oder laufende) Raid?
function BananaLoot:IsActivePrepared(entry)
    if not entry then return false end
    if self:IsRunningPrepared(entry) then return true end
    local sel = self:GetSelectedPreparedRaid()
    return sel ~= nil and sel.id == entry.id
end

-- Nimmt dieser Raid aktuell SR an? Fuer den ausgewaehlten bzw. laufenden Raid ist
-- das die SR-Sperre des Hauptfensters (Button "Offen"/"Gesperrt"), sonst der
-- gespeicherte Status des Raids -- beide Schalter sind also dieselbe Einstellung.
function BananaLoot:IsSROpenFor(entry)
    if self:IsActivePrepared(entry) then return not self:GetSRLocked() end
    return entry.srOpen ~= false
end

-- ============================================================
-- 2) VERSAND (gedrosselte Warteschlange + verzoegerte Antworten)
-- ============================================================
function BananaLoot:RaidCodeChannel()
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    if GetGuildInfo and GetGuildInfo("player") then return "GUILD" end
    return nil
end

C.frame = CreateFrame("Frame", "BananaLootRaidCodeFrame")
C.frame:Hide()
C.elapsed = 0
C.frame:SetScript("OnUpdate", function()
    local now = GetTime()
    -- verzoegerte Aktionen
    for i = table.getn(C.timers), 1, -1 do
        local t = C.timers[i]
        if now >= t.at then
            table.remove(C.timers, i)
            pcall(t.fn)
        end
    end
    -- Sendewarteschlange
    C.elapsed = C.elapsed + arg1
    if C.elapsed >= SEND_INTERVAL then
        C.elapsed = 0
        if C.qHead <= C.qTail then
            local m = C.queue[C.qHead]
            C.queue[C.qHead] = nil
            C.qHead = C.qHead + 1
            pcall(function() SendAddonMessage(PREFIX, m[1], m[2]) end)
        end
    end
    if C.qHead > C.qTail and table.getn(C.timers) == 0 then C.frame:Hide() end
end)

local function QueueSend(text, channel)
    if not channel then return end
    if string.len(text) > 240 then return end
    C.qTail = C.qTail + 1
    C.queue[C.qTail] = { text, channel }
    C.frame:Show()
end
BananaLoot.CodeQueueSend = QueueSend

local function After(delay, fn)
    table.insert(C.timers, { at = GetTime() + delay, fn = fn })
    C.frame:Show()
end

local function Clean(s)
    s = string.gsub(s or "", "~", "-")
    return string.sub(s, 1, 30)
end

local function SendStatus(entry, channel)
    local state = BananaLoot:IsSROpenFor(entry) and "O" or "C"
    QueueSend("SS~" .. entry.code .. "~" .. state .. "~" .. BananaLoot:GetMaxSRCount() .. "~"
        .. (entry.raidKey or "") .. "~" .. Clean(entry.name), channel)
end

local function SendLists(entry, channel)
    local kinds = { { "H", entry.hr }, { "R", entry.rr }, { "B", entry.br } }
    for k = 1, 3 do
        local list = SetToSortedList(kinds[k][2])
        local i = 1
        while i <= table.getn(list) do
            local part = {}
            for j = i, math.min(i + CHUNK - 1, table.getn(list)) do table.insert(part, list[j]) end
            QueueSend("SH~" .. entry.code .. "~" .. kinds[k][1] .. "~" .. table.concat(part, ","), channel)
            i = i + CHUNK
        end
    end
end

local function SendSRData(entry, channel)
    for player, ids in pairs(entry.sr or {}) do
        QueueSend("SD~" .. entry.code .. "~" .. player .. "~" .. table.concat(ids, ","), channel)
    end
end

-- Antwort verzoegert senden; entfaellt, wenn inzwischen ein anderer Client geantwortet hat.
-- Ersteller antworten zuerst, per Code geladene Stellvertreter spaeter (Ausfall-Reserve).
local function ScheduleReply(entry, seenKey, fn)
    local queried = GetTime()
    local delay
    if entry.joined then delay = 1.4 + math.random() * 0.6 else delay = 0.1 + math.random() * 0.3 end
    After(delay, function()
        local s = C.seen[seenKey]
        if s and s >= queried then return end
        C.seen[seenKey] = GetTime()
        fn()
    end)
end

-- Status des Raids an alle schicken (z.B. nach Auf-/Zusperren der SR).
function BananaLoot:RaidCodeBroadcastStatus(entry)
    if not entry or not entry.code then return end
    SendStatus(entry, self:RaidCodeChannel())
end

-- Der aktive Raid: laufender, sonst im Hauptfenster ausgewaehlter vorbereiteter Raid.
function BananaLoot:GetActivePrepared()
    local session = self:GetRaidSession()
    if session and session.running then return self:GetPreparedRaid(session.preparedId) end
    return self:GetSelectedPreparedRaid()
end

-- Hook aus SetSRLocked: Status des aktiven Raids merken und melden, beide
-- Buttons (Hauptfenster, Raid-Liste) angleichen.
function BananaLoot:RaidCodeOnLockChanged()
    local entry = self:GetActivePrepared()
    if entry and entry.code then
        entry.srOpen = not self:GetSRLocked()
        self:RaidCodeBroadcastStatus(entry)
    end
    if BananaLoot_UI then
        if BananaLoot_UI.UpdateLockButton then BananaLoot_UI:UpdateLockButton() end
        if BananaLoot_UI.RefreshRaidPicker then BananaLoot_UI:RefreshRaidPicker() end
    end
end

-- SR auf-/zusperren (Raid-Liste). Beim aktiven Raid schaltet das dieselbe Sperre
-- wie der Button im Hauptfenster.
function BananaLoot:SetPreparedSROpen(entry, open)
    if not entry then return end
    self:EnsurePreparedCode(entry)
    if self:IsActivePrepared(entry) then
        self:SetSRLocked(not open)   -- ruft RaidCodeOnLockChanged
    else
        entry.srOpen = open and true or false
        self:RaidCodeBroadcastStatus(entry)
    end
end

-- Per Raid-Code eingegangene SR des ausgewaehlten Raids stehen schon vor dem Start
-- im Hauptfenster: in die Reservierungen uebernehmen bzw. wieder entfernen.
function BananaLoot:CodeApplyLive(entry)
    if not entry then return end
    entry.live = entry.live or {}
    for player, ids in pairs(entry.sr or {}) do
        self:ApplyPlayerSRList(player, ids)
        entry.live[player] = ids
    end
end

function BananaLoot:CodeClearLive(entry)
    if not entry or not entry.live then return end
    for player, ids in pairs(entry.live) do
        for i = 1, table.getn(ids) do
            self:RemoveReservation(self:SetupItemLink(ids[i]), player)
        end
    end
    entry.live = nil
end

-- Auswahl im Hauptfenster gewechselt (nicht bei laufendem Raid).
function BananaLoot:CodeOnSelectionChanged(old, new)
    local session = self:GetRaidSession()
    if session and session.running then return end
    if old and (not new or old.id ~= new.id) then self:CodeClearLive(old) end
    if new then
        self:EnsurePreparedCode(new)
        self:SetSRLocked(new.srOpen == false)   -- Sperre auf den Status des Raids stellen
        self:CodeApplyLive(new)
    end
    if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
end

function BananaLoot:CodeOnDelete(entry)
    local session = self:GetRaidSession()
    if session and session.running then return end
    self:CodeClearLive(entry)
end

-- ============================================================
-- 3) SR ANNEHMEN
-- ============================================================

-- Setzt die komplette SR-Liste eines Spielers in den Live-Reservierungen
-- (Items, die bleiben, behalten ihren SR+ Stack).
function BananaLoot:ApplyPlayerSRList(player, ids)
    local keep = {}
    for i = 1, table.getn(ids) do keep[ids[i]] = true end
    local old = self.playerReservedItems[player]
    if old then
        local copy = {}
        for i = 1, table.getn(old) do table.insert(copy, old[i]) end
        for i = 1, table.getn(copy) do
            if not keep[copy[i]] then self:RemoveReservation(self:SetupItemLink(copy[i]), player) end
        end
    end
    local n = 0
    for i = 1, table.getn(ids) do
        local ok = self:AddReservation(self:SetupItemLink(ids[i]), player)
        if ok then n = n + 1 end
    end
    return n
end

-- Prueft und speichert eine eingegangene SR. Rueckgabe: ok, n|grund, uebersprungen.
function BananaLoot:CodeSubmitSR(entry, player, ids)
    if not self:IsSROpenFor(entry) then return false, "closed" end
    local pool = self:GetSetupPool(entry.raidKey)
    local running = self:IsRunningPrepared(entry)
    local list, seen, skipped = {}, {}, 0
    for i = 1, table.getn(ids) do
        local id = ids[i]
        if not seen[id] then
            seen[id] = true
            local blocked = (not pool[id]) or (entry.hr and entry.hr[id]) or (entry.rr and entry.rr[id])
                or (entry.br and entry.br[id]) or self:IsBankReserve(id)
            if running and (self:IsHardReserve(id) or self:IsRaidRollItem(id)) then blocked = true end
            if blocked then skipped = skipped + 1 else table.insert(list, id) end
        end
    end
    if table.getn(list) > self:GetMaxSRCount() then return false, "limit" end
    if running then
        local n = self:ApplyPlayerSRList(player, list)
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        return true, n, skipped
    end
    if not entry.sr then entry.sr = {} end
    if table.getn(list) == 0 then entry.sr[player] = nil else entry.sr[player] = list end
    -- Ausgewaehlter Raid: SR sofort im Hauptfenster anzeigen
    if self:IsActivePrepared(entry) then
        self:ApplyPlayerSRList(player, list)
        entry.live = entry.live or {}
        if table.getn(list) == 0 then entry.live[player] = nil else entry.live[player] = list end
        if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
    end
    return true, table.getn(list), skipped
end

-- Beim Raid-Start: im vorbereiteten Raid gesammelte SR in die Reservierungen
-- uebernehmen und die SR-Liste sperren.
function BananaLoot:CodeOnRaidStart(entry)
    if not entry then return 0 end
    self:EnsurePreparedCode(entry)
    local players = 0
    for player, ids in pairs(entry.sr or {}) do
        self:ApplyPlayerSRList(player, ids)
        players = players + 1
    end
    entry.srOpen = false
    entry.live = nil          -- die SR gehoeren ab jetzt zum laufenden Raid
    self:SetSRLocked(true)   -- meldet den Status (siehe RaidCodeOnLockChanged)
    return players
end

-- ============================================================
-- 4) NACHRICHTEN EMPFANGEN. Rueckgabe true = Nachricht gehoert zum Raid-Code.
-- ============================================================
function BananaLoot:HandleCodeMessage(text, sender, channel)
    -- Kurznachrichten (SW, HQ) bestehen nur aus dem Typ, alle anderen haben "~" an Stelle 3
    if not text or (string.len(text) > 2 and string.sub(text, 3, 3) ~= "~") then return false end
    local t = string.sub(text, 1, 2)
    if t ~= "SR" and t ~= "SQ" and t ~= "SJ" and t ~= "SS" and t ~= "SH" and t ~= "SD" and t ~= "SA"
        and t ~= "SW" and t ~= "SC" and t ~= "HQ" and t ~= "HA" and t ~= "HO" and t ~= "RV" then
        return false
    end
    local fields = Split(text, "~")
    local code = self:NormalizeRaidCode(fields[2])
    local me = UnitName("player")
    local isSelf = (sender == me)
    local entry = self:FindPreparedByCode(code)

    if t == "SR" then
        if not entry then return true end
        local player = fields[3]
        if player ~= sender then return true end   -- nur die eigene SR (Absender ist gesichert)
        local now = GetTime()
        if C.lastMsg[sender] and (now - C.lastMsg[sender]) < 1.5 then return true end
        C.lastMsg[sender] = now
        self:EnsurePreparedCode(entry)
        local ok, a, b = self:CodeSubmitSR(entry, player, IdsToList(fields[4]))
        local ack
        if ok then
            ack = "SA~" .. code .. "~" .. player .. "~OK~" .. a .. "~" .. (b or 0)
            if BananaLoot_UI and BananaLoot_UI.RefreshRaidPicker then BananaLoot_UI:RefreshRaidPicker() end
        else
            ack = "SA~" .. code .. "~" .. player .. "~ERR~" .. a
        end
        ScheduleReply(entry, "A|" .. code .. "|" .. player, function() QueueSend(ack, channel) end)
        return true
    end

    if t == "SQ" then
        -- Auch die eigene Anfrage beantworten: Loot-Master mit installiertem
        -- BananaLoot Raider (gleicher Charakter) fragt sich selbst an.
        if entry then
            self:EnsurePreparedCode(entry)
            ScheduleReply(entry, "S|" .. code, function()
                SendStatus(entry, channel)
                SendLists(entry, channel)
            end)
        end
        return true
    end

    if t == "SJ" then
        if entry and not isSelf then
            self:EnsurePreparedCode(entry)
            ScheduleReply(entry, "J|" .. code, function()
                SendStatus(entry, channel)
                SendLists(entry, channel)
                SendSRData(entry, channel)
            end)
        end
        return true
    end

    -- SW: Raider fragt in der Gruppe nach dem aktiven Raid. Beantwortet wird nur, was ueber
    -- Raid/Gruppe kommt (der Kanal beweist, dass der Anfragende in der Gruppe ist).
    if t == "SW" then
        if channel == "RAID" or channel == "PARTY" then
            local active = self:GetActivePrepared()
            if active then
                self:EnsurePreparedCode(active)
                ScheduleReply(active, "W|" .. active.code, function()
                    local state = BananaLoot:IsSROpenFor(active) and "O" or "C"
                    QueueSend("SC~" .. active.code .. "~" .. Clean(active.name) .. "~" .. state, channel)
                end)
            end
        end
        return true
    end
    if t == "SC" then return true end   -- nur fuer Raider

    -- HQ/HA: wer hat BananaLoot? (Raid-Lead abgeben)
    if t == "HQ" then
        if not isSelf then
            After(math.random() * 1.2, function() QueueSend("HA~" .. (BananaLoot.VERSION or "?"), channel) end)
        end
        return true
    end
    if t == "RV" then
        C.raiderVersion[sender] = fields[2] or "?"
        return true
    end
    if t == "HA" then
        C.hasAddon[sender] = fields[2] or "?"
        if BananaLoot_UI and BananaLoot_UI.RefreshMemberPicker then BananaLoot_UI:RefreshMemberPicker() end
        return true
    end
    if t == "HO" then
        -- Neuer Raid-Leiter: den Raid des bisherigen Leiters sofort per Code laden.
        if fields[3] == me and not isSelf then
            local code2 = self:NormalizeRaidCode(fields[2])
            if code2 ~= "" and not self:FindPreparedByCode(code2) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L("LEAD_RECEIVED"), sender))
                self:JoinRaidCode(code2)
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L("LEAD_RECEIVED_NOCODE"), sender))
            end
        end
        return true
    end

    -- Antworten anderer Hosts (SS/SH/SD/SA)
    if not isSelf then
        if t == "SS" then C.seen["S|" .. code] = GetTime()
        elseif t == "SA" then C.seen["A|" .. code .. "|" .. tostring(fields[3])] = GetTime() end
    end
    if isSelf then return true end

    if t == "SS" then
        if C.joining[code] and not entry then
            BananaLoot.EnsureDB()
            BananaLoot_DB.nextPreparedId = (BananaLoot_DB.nextPreparedId or 0) + 1
            local list = self:GetPreparedRaids()
            table.insert(list, {
                id = BananaLoot_DB.nextPreparedId, created = time(), joined = true, code = code,
                name = fields[6] or code, raidKey = fields[5], hr = {}, rr = {}, br = {}, sr = {},
                srOpen = (fields[3] == "O"),
            })
        elseif entry and entry.joined then
            entry.srOpen = (fields[3] == "O")
        end
    elseif t == "SH" then
        if entry and entry.joined and C.joining[code] then
            local target = entry.rr
            if fields[3] == "H" then target = entry.hr elseif fields[3] == "B" then
                if not entry.br then entry.br = {} end
                target = entry.br
            end
            local ids = IdsToList(fields[4])
            for i = 1, table.getn(ids) do target[ids[i]] = true end
        end
    elseif t == "SD" then
        if entry and entry.joined and C.joining[code] and fields[3] then
            local ids = IdsToList(fields[4])
            if table.getn(ids) > 0 then entry.sr[fields[3]] = ids end
        end
    end
    return true
end

-- Raid per Code von einem anderen Loot-Master laden (Stellvertreter).
function BananaLoot:JoinRaidCode(code)
    code = self:NormalizeRaidCode(code)
    if code == "" then return false end
    if self:FindPreparedByCode(code) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L("CODE_JOIN_EXISTS"), code))
        return false
    end
    local channel = self:RaidCodeChannel()
    if not channel then
        DEFAULT_CHAT_FRAME:AddMessage(self:L("CODE_NO_CHANNEL"))
        return false
    end
    C.joining[code] = GetTime()
    QueueSend("SJ~" .. code, channel)
    DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L("CODE_JOIN_SENT"), code))
    After(5, function()
        local entry = BananaLoot:FindPreparedByCode(code)
        C.joining[code] = nil
        if entry then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("CODE_JOIN_DONE"), entry.name,
                BananaLoot:CountPreparedSR(entry)))
            BananaLoot:SelectPreparedRaid(entry.id)
            if BananaLoot_UI and BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
            if BananaLoot_UI and BananaLoot_UI.RefreshRaidPicker then BananaLoot_UI:RefreshRaidPicker() end
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("CODE_JOIN_FAILED"), code))
        end
    end)
    return true
end

-- Raid-Code im Chat veroeffentlichen (Raid, sonst Gruppe/Gilde; ohne Kanal lokal anzeigen).
function BananaLoot:PostRaidCode(entry)
    if not entry then return end
    self:EnsurePreparedCode(entry)
    local msg = string.format(self:L("CODE_POST_TEXT"), entry.name or "", entry.code)
    local channel = self:RaidCodeChannel()
    if channel then
        pcall(function() SendChatMessage(msg, channel) end)
    else
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

-- ============================================================
-- 4b) VERSIONEN IN DER GRUPPE: /bl version fragt per HQ, wer BananaLoot bzw. BananaLoot Raider hat
-- und in welcher Version; die Antworten (HA/RV) werden nach 3 Sekunden aufgelistet.
-- ============================================================
local function VersionNewer(a, b)
    -- true, wenn Version a neuer ist als b ("3.43" > "3.42")
    local function part(v, i)
        local n = 0
        local k = 0
        for num in string.gfind(v or "0", "%d+") do
            k = k + 1
            if k == i then n = tonumber(num) or 0 end
        end
        return n
    end
    for i = 1, 3 do
        if part(a, i) ~= part(b, i) then return part(a, i) > part(b, i) end
    end
    return false
end

function BananaLoot:ShowGroupVersions()
    DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L("VERSION_OWN"), self.VERSION))
    local channel = self:RaidCodeChannel()
    if not channel or channel == "GUILD" then
        -- ohne Gruppe/Raid gibt es niemanden zum Abfragen
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage(self:L("VERSION_ASKING"))
    C.hasAddon = {}
    C.raiderVersion = {}
    QueueSend("HQ", channel)
    After(3, function()
        local lines = 0
        local names = {}
        for name in pairs(C.hasAddon) do table.insert(names, name) end
        for name in pairs(C.raiderVersion) do
            if not C.hasAddon[name] then table.insert(names, name) end
        end
        table.sort(names)
        for i = 1, table.getn(names) do
            local name = names[i]
            if C.hasAddon[name] and name ~= UnitName("player") then
                lines = lines + 1
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("VERSION_LINE"), name, C.hasAddon[name]))
                if VersionNewer(BananaLoot.VERSION, C.hasAddon[name]) then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("VERSION_OLDER"), name))
                end
            end
            if C.raiderVersion[name] then
                lines = lines + 1
                DEFAULT_CHAT_FRAME:AddMessage(string.format(BananaLoot:L("VERSION_LINE_RAIDER"), name, C.raiderVersion[name]))
            end
        end
        if lines == 0 then DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("VERSION_NONE")) end
    end)
end

-- ============================================================
-- 5) SPIELERAUSWAHL + RAID-LEAD ABGEBEN
-- ============================================================
local H = { rows = {}, offset = 0, showAll = false, opts = nil }
local HROWS = 12

local function InGroup()
    return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

local function IsLeader()
    if GetNumRaidMembers() > 0 then return IsRaidLeader and IsRaidLeader() == 1 end
    if GetNumPartyMembers() > 0 then return IsPartyLeader and IsPartyLeader() == 1 end
    return false
end

-- Namen der Raid-/Gruppenmitglieder (includeSelf: auch man selbst), alphabetisch.
function BananaLoot:GetGroupMembers(includeSelf)
    local names = {}
    local me = UnitName("player")
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local name = GetRaidRosterInfo(i)
            if name and (includeSelf or name ~= me) then table.insert(names, name) end
        end
    else
        if includeSelf and me then table.insert(names, me) end
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then table.insert(names, name) end
        end
    end
    table.sort(names)
    return names
end

-- Hat der Spieler BananaLoot? (Antwort auf HQ; man selbst natuerlich ja)
function BananaLoot:HasBananaLoot(name)
    return name == UnitName("player") or C.hasAddon[name] ~= nil
end

-- Uebergibt die Raid-Leitung sofort an einen Spieler (und den Loot-Master, falls Masterloot
-- aktiv und man selbst Loot-Master ist). Der neue Leiter bekommt den aktiven Raid
-- automatisch per Code (HO), er muss nichts eintragen.
function BananaLoot:HandOverRaidLead(name)
    if not IsLeader() then
        DEFAULT_CHAT_FRAME:AddMessage(self:L("LEAD_NOT_LEADER"))
        return false
    end
    local ok = pcall(function() PromoteToLeader(name) end)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage(self:L("LEAD_FAILED"))
        return false
    end
    local movedML = false
    local okm, method, mlParty, mlRaid = pcall(GetLootMethod)
    if okm and method == "master" then
        local mlName
        if mlRaid then mlName = UnitName("raid" .. mlRaid) elseif mlParty == 0 then mlName = UnitName("player") end
        if mlName == UnitName("player") then
            movedML = pcall(function() SetLootMethod("master", name) end)
        end
    end
    local active = self:GetActivePrepared()
    local channel = self:RaidCodeChannel()
    if active and active.code and channel and self:HasBananaLoot(name) then
        QueueSend("HO~" .. active.code .. "~" .. name, channel)
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L(movedML and "LEAD_DONE_ML" or "LEAD_DONE"), name))
    return true
end

local function MakeBtn(name, parent, w, h)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(h)
    return b
end

H.frame = CreateFrame("Frame", "BananaLootMemberPicker", UIParent)
H.frame:SetWidth(300)
H.frame:SetHeight(HROWS * 24 + 130)
H.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
H.frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
BananaLoot_Theme.Darken(H.frame)
H.frame:SetMovable(true)
H.frame:EnableMouse(true)
H.frame:RegisterForDrag("LeftButton")
H.frame:SetScript("OnDragStart", function() this:StartMoving() end)
H.frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
H.frame:SetFrameStrata("DIALOG")
H.frame:Hide()
H.title = H.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
H.title:SetPoint("TOP", H.frame, "TOP", 0, -16)
H.hint = H.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
H.hint:SetPoint("TOP", H.frame, "TOP", 0, -40)
H.hint:SetWidth(260)
H.close = CreateFrame("Button", "BananaLootMemberPickerClose", H.frame, "UIPanelCloseButton")
H.close:SetPoint("TOPRIGHT", H.frame, "TOPRIGHT", -4, -4)
H.close:SetScript("OnClick", function() BananaLoot:PlayClickSound(); this:GetParent():Hide() end)
H.list = CreateFrame("Frame", "BananaLootMemberPickerList", H.frame)
H.list:SetWidth(260)
H.list:SetHeight(HROWS * 24)
H.list:SetPoint("TOPLEFT", H.frame, "TOPLEFT", 20, -74)
H.list:EnableMouseWheel(true)
H.list:SetScript("OnMouseWheel", function()
    H.offset = H.offset - arg1
    H.Refresh()
end)
H.empty = H.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
H.empty:SetPoint("TOP", H.frame, "TOP", 0, -110)
H.empty:SetWidth(240)
H.allBtn = MakeBtn("BananaLootMemberPickerAll", H.frame, 180, 22)
H.allBtn:SetPoint("BOTTOM", H.frame, "BOTTOM", 0, 20)
H.allBtn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    H.showAll = not H.showAll
    H.offset = 0
    H.Refresh()
end)

for i = 1, HROWS do
    local b = MakeBtn("BananaLootMemberPickerRow" .. i, H.list, 256, 22)
    b:SetPoint("TOPLEFT", H.list, "TOPLEFT", 2, -(i - 1) * 24)
    b:SetScript("OnClick", function()
        if not this.who or not H.opts then return end
        BananaLoot:PlayClickSound()
        local who, cb = this.who, H.opts.onPick
        H.frame:Hide()
        if cb then cb(who) end
    end)
    H.rows[i] = b
end

StaticPopupDialogs["BANANALOOT_HANDOVER"] = {
    text = "",
    button1 = "",
    button2 = "",
    OnAccept = function()
        if H.pending then BananaLoot:HandOverRaidLead(H.pending) end
        H.pending = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function H.Refresh()
    if not H.frame:IsShown() or not H.opts then return end
    local opts = H.opts
    local names = BananaLoot:GetGroupMembers(opts.includeSelf)
    local list = {}
    for i = 1, table.getn(names) do
        local has = BananaLoot:HasBananaLoot(names[i])
        if not opts.onlyAddon or H.showAll or has then table.insert(list, { name = names[i], has = has }) end
    end
    if opts.onlyAddon then   -- BananaLoot-Nutzer zuerst
        table.sort(list, function(a, b)
            if a.has ~= b.has then return a.has end
            return a.name < b.name
        end)
    end
    local n = table.getn(list)
    local maxOff = math.max(0, n - HROWS)
    if H.offset > maxOff then H.offset = maxOff end
    if H.offset < 0 then H.offset = 0 end
    H.title:SetText(opts.title or "")
    H.hint:SetText(opts.hint or "")
    for i = 1, HROWS do
        local e = list[H.offset + i]
        if e then
            H.rows[i].who = e.name
            local label = BananaLoot:ColoredName(e.name)
            if opts.onlyAddon then
                if e.has then
                    local ver = C.hasAddon[e.name]
                    if e.name == UnitName("player") then ver = BananaLoot.VERSION end
                    label = label .. "  |cff33ff99" .. BananaLoot:L("LEAD_TAG_ADDON") .. (ver and ver ~= "" and (" v" .. ver) or "") .. "|r"
                else
                    label = label .. "  |cff808080" .. BananaLoot:L("LEAD_TAG_NOADDON") .. "|r"
                end
            end
            H.rows[i]:SetText(label)
            H.rows[i]:Show()
        else
            H.rows[i].who = nil
            H.rows[i]:Hide()
        end
    end
    if n == 0 then
        H.empty:SetText(BananaLoot:L(opts.onlyAddon and "LEAD_EMPTY_ADDON" or "LEAD_EMPTY"))
    else
        H.empty:SetText("")
    end
    if opts.onlyAddon then
        H.allBtn:SetText(BananaLoot:L(H.showAll and "LEAD_SHOW_ADDON" or "LEAD_SHOW_ALL"))
        H.allBtn:Show()
    else
        H.allBtn:Hide()
    end
end
H.frame:SetScript("OnShow", function() H.Refresh() end)

-- Allgemeine Spielerauswahl. opts = { title, hint, onPick = function(name), onlyAddon, includeSelf }
function BananaLoot_UI:ShowMemberPicker(opts)
    if not InGroup() then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("PICK_NOT_IN_GROUP"))
        return
    end
    H.opts = opts
    H.offset = 0
    H.showAll = false
    H.frame:Show()
    if opts.onlyAddon then
        local channel = BananaLoot:RaidCodeChannel()
        if channel then QueueSend("HQ", channel) end   -- wer hat BananaLoot?
    end
    H.Refresh()
end

function BananaLoot_UI:RefreshMemberPicker()
    H.Refresh()
end

-- Raid-Lead abgeben: Mitglieder mit BananaLoot waehlen, sofort uebergeben.
function BananaLoot_UI:ShowHandover()
    if not IsLeader() then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("LEAD_NOT_LEADER"))
        return
    end
    BananaLoot_UI:ShowMemberPicker({
        title = BananaLoot:L("LEAD_TITLE"),
        hint = BananaLoot:L("LEAD_HINT"),
        onlyAddon = true,
        onPick = function(name)
            H.pending = name
            local d = StaticPopupDialogs["BANANALOOT_HANDOVER"]
            d.text = string.format(BananaLoot:L("LEAD_CONFIRM"), name)
            d.button1 = BananaLoot:L("UI_POPUP_YES")
            d.button2 = BananaLoot:L("UI_POPUP_CANCEL")
            StaticPopup_Show("BANANALOOT_HANDOVER")
        end,
    })
end

-- Button unten rechts im Hauptfenster
local srMain = getglobal("BananaLootSRFrame")
if srMain then
    local leadBtn = CreateFrame("Button", "BananaLootHandoverBtn", srMain, "UIPanelButtonTemplate")
    leadBtn:SetWidth(150)
    leadBtn:SetHeight(22)
    leadBtn:SetPoint("BOTTOMRIGHT", srMain, "BOTTOMRIGHT", -22, 14)
    leadBtn:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        BananaLoot_UI:ShowHandover()
    end)
    leadBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(leadBtn, "ANCHOR_TOP")
        GameTooltip:SetText(BananaLoot:L("LEAD_TOOLTIP"), 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    leadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    H.leadBtn = leadBtn
    leadBtn:SetText(BananaLoot:L("LEAD_BTN"))
end

function BananaLoot_UI:ApplyLocaleRaidCode()
    if H.leadBtn then H.leadBtn:SetText(BananaLoot:L("LEAD_BTN")) end
    if H.frame:IsShown() then H.Refresh() end
end
