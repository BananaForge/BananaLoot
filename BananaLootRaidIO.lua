-- BananaLootRaidIO.lua
-- Discord-Export/-Import eines vorbereiteten Raids (ohne Addon-Netzwerk): der Loot-Master exportiert den Raid als
-- Text, postet ihn in einen geschuetzten Discord-Kanal, ein Vertreter holt ihn dort und importiert ihn.
--
-- Der Export enthaelt: Raid-ID (uid), Zeitstempel, Raid-Name, Raid-Typ, Raid-Code, alle Spieler mit ihren SR und
-- SR+ sowie die HR-, BR- und Raid-Roll-Liste. Der Import ERSETZT den lokalen Stand desselben Raids (gleiche uid) nur,
-- wenn der Export NEUER ist als der lokale Stand; unbekannte Raids werden neu angelegt. Vor dem Import kommt eine
-- Sicherheitsabfrage.
--
-- Format (eine Zeile pro Teil, jeder Teil passt in eine Discord-Nachricht):  BLX/<teil>/<anzahl>/<text>
-- Der zusammengesetzte Text ist "~"-getrennt:  V1 ~ U^uid ~ T^stamp ~ N^name ~ K^raidKey ~ C^code ~
--   S^spieler^id:plus,id:plus ~ H^ids ~ B^ids ~ R^ids ~ Z^pruefsumme
--
-- Lua 5.0: kein #, kein %, kein string.gmatch/match.

local IO = { pending = nil }
BananaLoot_RaidIO = IO

local PART_LIMIT = 1700   -- Zeichen pro Teil (Discord: max. 2000 je Nachricht)

local function Split(str, sep)
    local result = {}
    local start = 1
    while true do
        local s, e = string.find(str, sep, start, true)
        if not s then table.insert(result, string.sub(str, start)) break end
        table.insert(result, string.sub(str, start, s - 1))
        start = e + 1
    end
    return result
end

local function Checksum(s)
    local n = 0
    for i = 1, string.len(s) do n = math.mod(n * 31 + string.byte(s, i), 1000003) end
    return n
end

local function Clean(s, maxLen)
    s = string.gsub(s or "", "[~%^/`,:]", "-")
    s = string.gsub(s, "%s", "_")       -- Leerzeichen als _ (der Text darf in Discord nirgends umbrechen)
    return string.sub(s, 1, maxLen or 40)
end

local function SortedKeys(set)
    local list = {}
    for id in pairs(set or {}) do table.insert(list, id) end
    table.sort(list)
    return list
end

-- ------------------------------------------------------------
-- Raid-ID und Zeitstempel
-- ------------------------------------------------------------
function BananaLoot:EnsureRaidUID(entry)
    if not entry then return end
    if not entry.uid then
        entry.uid = string.format("%x", time()) .. string.format("%03x", math.random(0, 4095)) .. string.format("%x", entry.id or 0)
    end
    if not entry.stamp then entry.stamp = entry.created or 0 end
end

function BananaLoot:FindPreparedByUID(uid)
    if not uid then return nil end
    local list = self:GetPreparedRaids()
    for i = 1, table.getn(list) do
        if list[i].uid == uid then return list[i] end
    end
    return nil
end

-- ------------------------------------------------------------
-- Export
-- ------------------------------------------------------------
-- Spieler -> Liste der Item-IDs: beim aktiven (laufenden/ausgewaehlten) Raid die aktuellen Reservierungen,
-- sonst die im Raid gespeicherten SR.
local function CollectSR(entry)
    local out = {}
    if BananaLoot:IsActivePrepared(entry) then
        for itemID, res in pairs(BananaLoot.reservations or {}) do
            if res and res.order then
                for i = 1, table.getn(res.order) do
                    local name = res.order[i]
                    if not (res.temp and res.temp[name]) then
                        out[name] = out[name] or {}
                        table.insert(out[name], itemID)
                    end
                end
            end
        end
    else
        for player, ids in pairs(entry.sr or {}) do
            out[player] = {}
            for i = 1, table.getn(ids) do table.insert(out[player], ids[i]) end
        end
    end
    return out
end

local function IdList(set)
    return table.concat(SortedKeys(set), ",")
end

-- Ergebnis: Text (mehrzeilig, ein Teil pro Zeile), Zeitstempel. nil, "noraid" ohne Raid.
function BananaLoot:ExportPreparedRaid(entry)
    if not entry then return nil, "noraid" end
    self:EnsurePreparedCode(entry)
    local stamp = time()
    local rec = {
        "V1",
        "U^" .. entry.uid,
        "T^" .. stamp,
        "N^" .. Clean(entry.name),
        "K^" .. Clean(entry.raidKey or ""),
        "C^" .. Clean(entry.code or ""),
    }
    local sr = CollectSR(entry)
    local names = {}
    for p in pairs(sr) do table.insert(names, p) end
    table.sort(names)
    for i = 1, table.getn(names) do
        local p = names[i]
        local parts = {}
        table.sort(sr[p])
        for k = 1, table.getn(sr[p]) do
            local id = sr[p][k]
            table.insert(parts, id .. ":" .. (self:GetStack(p, id) or 0))
        end
        table.insert(rec, "S^" .. Clean(p, 24) .. "^" .. table.concat(parts, ","))
    end
    table.insert(rec, "H^" .. IdList(entry.hr))
    table.insert(rec, "B^" .. IdList(entry.br))
    table.insert(rec, "R^" .. IdList(entry.rr))
    local body = table.concat(rec, "~")
    local payload = body .. "~Z^" .. Checksum(body)

    local parts = {}
    local len = string.len(payload)
    local i = 1
    while i <= len do
        table.insert(parts, string.sub(payload, i, i + PART_LIMIT - 1))
        i = i + PART_LIMIT
    end
    local lines = {}
    for k = 1, table.getn(parts) do
        table.insert(lines, "BLX/" .. k .. "/" .. table.getn(parts) .. "/" .. parts[k])
    end
    entry.stamp = stamp   -- eigener Export gilt als Stand dieses Raids
    return table.concat(lines, "\n"), stamp
end

-- ------------------------------------------------------------
-- Import: lesen
-- ------------------------------------------------------------
local function ParseIds(str)
    local list = {}
    if str and str ~= "" then
        local f = Split(str, ",")
        for i = 1, table.getn(f) do
            local id = tonumber(f[i])
            if id then table.insert(list, id) end
        end
    end
    return list
end

local function ToSet(list)
    local set = {}
    for i = 1, table.getn(list) do set[list[i]] = true end
    return set
end

-- Rueckgabe: data | nil, grund ("empty", "incomplete", "checksum", "format")
function BananaLoot:ParseRaidExport(text)
    if not text or text == "" then return nil, "empty" end
    local parts, total = {}, nil
    local found = 0
    for k, n, chunk in string.gfind(text, "BLX/(%d+)/(%d+)/([^%s]+)") do
        k, n = tonumber(k), tonumber(n)
        if k and n and n > 0 and k >= 1 and k <= n then
            if total and total ~= n then return nil, "format" end
            total = n
            if not parts[k] then found = found + 1 end
            parts[k] = chunk
        end
    end
    if not total then return nil, "format" end
    if found < total then return nil, "incomplete", found, total end
    local payload = ""
    for k = 1, total do payload = payload .. parts[k] end

    local _, _, body, sum = string.find(payload, "^(.*)~Z%^(%d+)$")
    if not body then return nil, "checksum" end
    if Checksum(body) ~= tonumber(sum) then return nil, "checksum" end

    local recs = Split(body, "~")
    if recs[1] ~= "V1" then return nil, "format" end
    local data = { uid = nil, stamp = 0, name = "", key = "", code = "", sr = {}, hr = {}, br = {}, rr = {}, players = 0, srItems = 0 }
    for i = 2, table.getn(recs) do
        local f = Split(recs[i], "^")
        local t = f[1]
        if t == "U" then data.uid = f[2]
        elseif t == "T" then data.stamp = tonumber(f[2]) or 0
        elseif t == "N" then data.name = string.gsub(f[2] or "", "_", " ")
        elseif t == "K" then data.key = f[2] or ""
        elseif t == "C" then data.code = f[2] or ""
        elseif t == "H" then data.hr = ToSet(ParseIds(f[2]))
        elseif t == "B" then data.br = ToSet(ParseIds(f[2]))
        elseif t == "R" then data.rr = ToSet(ParseIds(f[2]))
        elseif t == "S" and f[2] and f[2] ~= "" then
            local list = {}
            local items = Split(f[3] or "", ",")
            for k = 1, table.getn(items) do
                local _, _, id, plus = string.find(items[k], "^(%d+):(%d+)$")
                if id then table.insert(list, { id = tonumber(id), plus = tonumber(plus) or 0 }) end
            end
            if table.getn(list) > 0 then
                data.sr[f[2]] = list
                data.players = data.players + 1
                data.srItems = data.srItems + table.getn(list)
            end
        end
    end
    if not data.uid or data.uid == "" or data.stamp == 0 then return nil, "format" end
    return data
end

-- Was wuerde der Import tun? Rueckgabe: status ("new" | "newer" | "older"), lokaler Raid (oder nil)
function BananaLoot:PlanRaidImport(data)
    local entry = self:FindPreparedByUID(data.uid)
    if not entry then return "new", nil end
    self:EnsureRaidUID(entry)
    if data.stamp > (entry.stamp or 0) then return "newer", entry end
    return "older", entry
end

-- ------------------------------------------------------------
-- Import: anwenden
-- ------------------------------------------------------------
function BananaLoot:ApplyRaidImport(data)
    local status, entry = self:PlanRaidImport(data)
    if status == "older" then return false, "older", entry end
    BananaLoot.EnsureDB()
    local list = self:GetPreparedRaids()
    local created = false
    if not entry then
        BananaLoot_DB.nextPreparedId = (BananaLoot_DB.nextPreparedId or 0) + 1
        entry = { id = BananaLoot_DB.nextPreparedId, created = time() }
        table.insert(list, entry)
        created = true
    end
    local session = self:GetRaidSession()
    local running = self:IsRunningPrepared(entry)
    local selected = (not running) and self:IsActivePrepared(entry)
    if selected then self:CodeClearLive(entry) end

    entry.uid = data.uid
    entry.stamp = data.stamp
    entry.name = data.name
    entry.raidKey = (data.key ~= "") and data.key or entry.raidKey
    entry.hr, entry.br, entry.rr = data.hr, data.br, data.rr
    if data.code and data.code ~= "" then entry.code = data.code end
    entry.live = nil
    entry.sr = {}
    for player, items in pairs(data.sr) do
        local ids = {}
        for i = 1, table.getn(items) do
            table.insert(ids, items[i].id)
            BananaLoot_DB.players[player] = BananaLoot_DB.players[player] or {}
            BananaLoot_DB.players[player][items[i].id] = items[i].plus
        end
        entry.sr[player] = ids
    end
    self:EnsurePreparedCode(entry)

    if selected or running then self:CodeApplyLive(entry) end
    self:SaveSession()
    if BananaLoot_UI then
        if BananaLoot_UI.Refresh then BananaLoot_UI:Refresh() end
        if BananaLoot_UI.RefreshRaidPicker then BananaLoot_UI:RefreshRaidPicker() end
    end
    return true, created and "new" or "newer", entry
end

-- ------------------------------------------------------------
-- Fenster
-- ------------------------------------------------------------
local F
local function StampText(ts)
    if not ts or ts == 0 then return "-" end
    return date("%d.%m.%Y %H:%M", ts)
end

local function ShowStatus(text)
    if F then F.status:SetText(text or "") end
end

local function ExportCurrent()
    local list = BananaLoot:GetPreparedRaids()
    local entry = list[IO.index or 1]
    if not entry then
        F.raidLabel:SetText(BananaLoot:L("IO_NORAID"))
        F.editBox:SetText("")
        return
    end
    BananaLoot:EnsureRaidUID(entry)
    F.raidLabel:SetText((entry.name or "?") .. "  (" .. (IO.index or 1) .. "/" .. table.getn(list) .. ")")
    local text, stamp = BananaLoot:ExportPreparedRaid(entry)
    F.editBox:SetText(text or "")
    F.editBox:HighlightText()
    ShowStatus(string.format(BananaLoot:L("IO_EXPORTED"), StampText(stamp)))
end

local function Cycle(delta)
    local n = table.getn(BananaLoot:GetPreparedRaids())
    if n == 0 then return end
    local i = (IO.index or 1) + delta
    if i < 1 then i = n elseif i > n then i = 1 end
    IO.index = i
    ExportCurrent()
end

local function ImportClicked()
    local text = F.editBox:GetText()
    local data, why, a, b = BananaLoot:ParseRaidExport(text)
    if not data then
        local key = (why == "empty" and "IO_ERR_EMPTY") or (why == "incomplete" and "IO_ERR_INCOMPLETE")
            or (why == "checksum" and "IO_ERR_CHECKSUM") or "IO_ERR_FORMAT"
        local msg = BananaLoot:L(key)
        if why == "incomplete" then msg = string.format(msg, a or 0, b or 0) end
        ShowStatus(msg)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555BananaLoot|r: " .. msg)
        return
    end
    local status, entry = BananaLoot:PlanRaidImport(data)
    if status == "older" then
        local msg = string.format(BananaLoot:L("IO_OLDER"), StampText(data.stamp), StampText(entry.stamp))
        ShowStatus(msg)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00BananaLoot|r: " .. msg)
        return
    end
    IO.pending = data
    local ask
    if status == "new" then
        ask = string.format(BananaLoot:L("IO_CONFIRM_NEW"), data.name, data.players, data.srItems, StampText(data.stamp))
    else
        ask = string.format(BananaLoot:L("IO_CONFIRM_REPLACE"), data.name, data.players, data.srItems,
            StampText(data.stamp), StampText(entry.stamp))
    end
    StaticPopupDialogs["BANANALOOT_RAIDIO_IMPORT"].text = "%s"
    StaticPopupDialogs["BANANALOOT_RAIDIO_IMPORT"].button1 = BananaLoot:L("UI_POPUP_YES")
    StaticPopupDialogs["BANANALOOT_RAIDIO_IMPORT"].button2 = BananaLoot:L("UI_POPUP_CANCEL")
    StaticPopup_Show("BANANALOOT_RAIDIO_IMPORT", ask)
end

function IO.DoImport()
    local data = IO.pending
    IO.pending = nil
    if not data then return end
    local ok, status, entry = BananaLoot:ApplyRaidImport(data)
    if ok then
        local msg = string.format(BananaLoot:L(status == "new" and "IO_DONE_NEW" or "IO_DONE_REPLACED"), data.name, data.players)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BananaLoot|r: " .. msg)
        if F then
            ShowStatus(msg)
            -- Anzeige auf den importierten Raid stellen und seinen (jetzt aktuellen) Export zeigen
            local list = BananaLoot:GetPreparedRaids()
            for i = 1, table.getn(list) do if list[i] == entry then IO.index = i end end
            ExportCurrent()
            ShowStatus(msg)
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555BananaLoot|r: " .. BananaLoot:L("IO_ERR_FORMAT"))
    end
end

StaticPopupDialogs["BANANALOOT_RAIDIO_IMPORT"] = {
    text = "%s",
    button1 = "Ja",
    button2 = "Abbrechen",
    OnAccept = function() BananaLoot_RaidIO.DoImport() end,
    OnCancel = function() BananaLoot_RaidIO.pending = nil end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local function Build()
    F = CreateFrame("Frame", "BananaLootRaidIOFrame", UIParent)
    F:SetWidth(520)
    F:SetHeight(360)
    F:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    F:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 11, bottom = 11 },
    })
    if BananaLoot_Theme and BananaLoot_Theme.Darken then BananaLoot_Theme.Darken(F) end
    F:SetMovable(true)
    F:EnableMouse(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", function() F:StartMoving() end)
    F:SetScript("OnDragStop", function() F:StopMovingOrSizing() end)
    F:SetFrameStrata("DIALOG")
    F:Hide()

    F.title = F:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    F.title:SetPoint("TOP", F, "TOP", 0, -16)

    local close = CreateFrame("Button", "BananaLootRaidIOClose", F, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", F, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() BananaLoot:PlayClickSound() F:Hide() end)

    F.prev = CreateFrame("Button", "BananaLootRaidIOPrev", F, "UIPanelButtonTemplate")
    F.prev:SetWidth(26) F.prev:SetHeight(22)
    F.prev:SetPoint("TOPLEFT", F, "TOPLEFT", 20, -46)
    F.prev:SetText("<")
    F.prev:SetScript("OnClick", function() BananaLoot:PlayClickSound() Cycle(-1) end)
    F.next = CreateFrame("Button", "BananaLootRaidIONext", F, "UIPanelButtonTemplate")
    F.next:SetWidth(26) F.next:SetHeight(22)
    F.next:SetPoint("LEFT", F.prev, "RIGHT", 2, 0)
    F.next:SetText(">")
    F.next:SetScript("OnClick", function() BananaLoot:PlayClickSound() Cycle(1) end)
    F.raidLabel = F:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    F.raidLabel:SetPoint("LEFT", F.next, "RIGHT", 10, 0)
    F.raidLabel:SetJustifyH("LEFT")

    F.refresh = CreateFrame("Button", "BananaLootRaidIORefresh", F, "UIPanelButtonTemplate")
    F.refresh:SetWidth(120) F.refresh:SetHeight(22)
    F.refresh:SetPoint("TOPRIGHT", F, "TOPRIGHT", -40, -46)
    F.refresh:SetScript("OnClick", function() BananaLoot:PlayClickSound() ExportCurrent() end)

    local scroll = CreateFrame("ScrollFrame", "BananaLootRaidIOScroll", F, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", F, "TOPLEFT", 20, -78)
    scroll:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -34, 96)
    F.editBox = CreateFrame("EditBox", "BananaLootRaidIOEditBox", scroll)
    F.editBox:SetMultiLine(true)
    F.editBox:SetFontObject(ChatFontNormal)
    F.editBox:SetWidth(460)
    F.editBox:SetAutoFocus(false)
    F.editBox:SetScript("OnEscapePressed", function() F:Hide() end)
    scroll:SetScrollChild(F.editBox)

    F.status = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    F.status:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 20, 76)
    F.status:SetWidth(480)
    F.status:SetJustifyH("LEFT")
    F.hint = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    F.hint:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 20, 40)
    F.hint:SetWidth(480)
    F.hint:SetJustifyH("LEFT")

    F.importBtn = CreateFrame("Button", "BananaLootRaidIOImport", F, "UIPanelButtonTemplate")
    F.importBtn:SetWidth(140) F.importBtn:SetHeight(24)
    F.importBtn:SetPoint("BOTTOM", F, "BOTTOM", -75, 14)
    F.importBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound() ImportClicked() end)
    F.closeBtn = CreateFrame("Button", "BananaLootRaidIOCloseBtn", F, "UIPanelButtonTemplate")
    F.closeBtn:SetWidth(140) F.closeBtn:SetHeight(24)
    F.closeBtn:SetPoint("LEFT", F.importBtn, "RIGHT", 10, 0)
    F.closeBtn:SetScript("OnClick", function() BananaLoot:PlayClickSound() F:Hide() end)
end

local function Texts()
    F.title:SetText(BananaLoot:L("IO_TITLE"))
    F.refresh:SetText(BananaLoot:L("IO_REFRESH"))
    F.hint:SetText(BananaLoot:L("IO_HINT"))
    F.importBtn:SetText(BananaLoot:L("IO_IMPORT"))
    F.closeBtn:SetText(BananaLoot:L("IO_CLOSE"))
end

function BananaLoot_UI:ShowRaidIO()
    if not F then Build() end
    Texts()
    -- Start: der aktive (laufende/ausgewaehlte) Raid
    local list = BananaLoot:GetPreparedRaids()
    local active = BananaLoot:GetActivePrepared()
    IO.index = 1
    for i = 1, table.getn(list) do if list[i] == active then IO.index = i end end
    F:Show()
    ExportCurrent()
end
