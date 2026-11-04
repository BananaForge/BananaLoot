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

-- Nimmt dieser Raid aktuell SR an?
function BananaLoot:IsSROpenFor(entry)
    if self:IsRunningPrepared(entry) then return not self:GetSRLocked() end
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
    local kinds = { { "H", entry.hr }, { "R", entry.rr } }
    for k = 1, 2 do
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

-- Hook aus SetSRLocked: laufenden vorbereiteten Raid melden.
function BananaLoot:RaidCodeOnLockChanged()
    local session = self:GetRaidSession()
    if session and session.running and session.preparedId then
        local entry = self:GetPreparedRaid(session.preparedId)
        if entry and entry.code then self:RaidCodeBroadcastStatus(entry) end
    end
end

-- SR vor dem Raid-Start auf-/zusperren (Raid-Liste).
function BananaLoot:SetPreparedSROpen(entry, open)
    if not entry then return end
    self:EnsurePreparedCode(entry)
    entry.srOpen = open and true or false
    self:RaidCodeBroadcastStatus(entry)
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
                or self:IsBankReserve(id)
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
    self:SetSRLocked(true)   -- meldet den Status (siehe RaidCodeOnLockChanged)
    return players
end

-- ============================================================
-- 4) NACHRICHTEN EMPFANGEN. Rueckgabe true = Nachricht gehoert zum Raid-Code.
-- ============================================================
function BananaLoot:HandleCodeMessage(text, sender, channel)
    if not text or string.sub(text, 3, 3) ~= "~" then return false end
    local t = string.sub(text, 1, 2)
    if t ~= "SR" and t ~= "SQ" and t ~= "SJ" and t ~= "SS" and t ~= "SH" and t ~= "SD" and t ~= "SA" then
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
        if entry and not isSelf then
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
                name = fields[6] or code, raidKey = fields[5], hr = {}, rr = {}, sr = {},
                srOpen = (fields[3] == "O"),
            })
        elseif entry and entry.joined then
            entry.srOpen = (fields[3] == "O")
        end
    elseif t == "SH" then
        if entry and entry.joined and C.joining[code] then
            local target = (fields[3] == "H") and entry.hr or entry.rr
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
-- 5) RAID-LEAD ABGEBEN
-- ============================================================
local H = { rows = {}, offset = 0 }
local HROWS = 12

local function IsLeader()
    if GetNumRaidMembers() > 0 then return IsRaidLeader and IsRaidLeader() == 1 end
    if GetNumPartyMembers() > 0 then return IsPartyLeader and IsPartyLeader() == 1 end
    return false
end

-- Namen aller anderen Raid-/Gruppenmitglieder, alphabetisch.
function BananaLoot:GetHandoverCandidates()
    local names = {}
    local me = UnitName("player")
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local name = GetRaidRosterInfo(i)
            if name and name ~= me then table.insert(names, name) end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then table.insert(names, name) end
        end
    end
    table.sort(names)
    return names
end

-- Uebergibt die Raid-Leitung (und, falls Masterloot aktiv und man selbst Loot-
-- Master ist, den Loot-Master) an einen anderen Spieler.
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
    DEFAULT_CHAT_FRAME:AddMessage(string.format(self:L(movedML and "LEAD_DONE_ML" or "LEAD_DONE"), name))
    return true
end

local function MakeBtn(name, parent, w, h)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(h)
    return b
end

H.frame = CreateFrame("Frame", "BananaLootHandoverFrame", UIParent)
H.frame:SetWidth(280)
H.frame:SetHeight(HROWS * 24 + 90)
H.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
H.frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
})
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
H.hint:SetPoint("TOP", H.frame, "TOP", 0, -38)
H.hint:SetWidth(240)
H.close = CreateFrame("Button", "BananaLootHandoverClose", H.frame, "UIPanelCloseButton")
H.close:SetPoint("TOPRIGHT", H.frame, "TOPRIGHT", -4, -4)
H.close:SetScript("OnClick", function() BananaLoot:PlayClickSound(); this:GetParent():Hide() end)
H.list = CreateFrame("Frame", "BananaLootHandoverList", H.frame)
H.list:SetWidth(240)
H.list:SetHeight(HROWS * 24)
H.list:SetPoint("TOPLEFT", H.frame, "TOPLEFT", 20, -64)
H.list:EnableMouseWheel(true)
H.list:SetScript("OnMouseWheel", function()
    H.offset = H.offset - arg1
    H.Refresh()
end)
H.empty = H.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
H.empty:SetPoint("TOP", H.frame, "TOP", 0, -100)
H.empty:SetWidth(220)

for i = 1, HROWS do
    local b = MakeBtn("BananaLootHandoverRow" .. i, H.list, 236, 22)
    b:SetPoint("TOPLEFT", H.list, "TOPLEFT", 2, -(i - 1) * 24)
    b:SetScript("OnClick", function()
        if not this.who then return end
        BananaLoot:PlayClickSound()
        H.pending = this.who
        local d = StaticPopupDialogs["BANANALOOT_HANDOVER"]
        d.text = string.format(BananaLoot:L("LEAD_CONFIRM"), this.who)
        d.button1 = BananaLoot:L("UI_POPUP_YES")
        d.button2 = BananaLoot:L("UI_POPUP_CANCEL")
        StaticPopup_Show("BANANALOOT_HANDOVER")
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
        H.frame:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function H.Refresh()
    if not H.frame:IsShown() then return end
    local names = BananaLoot:GetHandoverCandidates()
    local n = table.getn(names)
    local maxOff = math.max(0, n - HROWS)
    if H.offset > maxOff then H.offset = maxOff end
    if H.offset < 0 then H.offset = 0 end
    H.title:SetText(BananaLoot:L("LEAD_TITLE"))
    H.hint:SetText(BananaLoot:L("LEAD_HINT"))
    for i = 1, HROWS do
        local nm = names[H.offset + i]
        if nm then
            H.rows[i].who = nm
            H.rows[i]:SetText(BananaLoot:ColoredName(nm))
            H.rows[i]:Show()
        else
            H.rows[i].who = nil
            H.rows[i]:Hide()
        end
    end
    if n == 0 then H.empty:SetText(BananaLoot:L("LEAD_EMPTY")) else H.empty:SetText("") end
end
H.frame:SetScript("OnShow", function() H.Refresh() end)

function BananaLoot_UI:ShowHandover()
    if not IsLeader() then
        DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L("LEAD_NOT_LEADER"))
        return
    end
    H.offset = 0
    H.frame:Show()
    H.Refresh()
end

-- Button unten rechts im Hauptfenster
local srMain = getglobal("BananaLootSRFrame")
if srMain then
    local leadBtn = CreateFrame("Button", "BananaLootHandoverBtn", srMain, "UIPanelButtonTemplate")
    leadBtn:SetWidth(120)
    leadBtn:SetHeight(20)
    leadBtn:SetPoint("BOTTOMRIGHT", srMain, "BOTTOMRIGHT", -22, 16)
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
