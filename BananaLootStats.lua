-- BananaLootStats.lua
-- Reiter "Statistik" im Optionsfenster: Raid-Uebersicht, Raid-Liste, Loot-
-- Rangliste, Anwesenheit, hoechste SR+ und Details pro Raider (MS/OS/TM,
-- Teilnahmen, besuchte Raids).
--
-- Datenquellen:
--   BananaLoot_DB.raidHistory  (aufgezeichnete Raids: Start/Ende/Teilnehmer)
--   BananaLoot_DB.raidSession  (laufender Raid)
--   BananaLoot_DB.log          (Loot-Log, Zeitstempel ts bzw. Datumstext)
--   BananaLoot_DB.players      (aktuelle SR+ Werte)
-- Anwesenheit/Dauer gibt es nur fuer Raids, die mit "Raid starten"
-- aufgezeichnet wurden. Loot zaehlt immer (auch ausserhalb), wird aber nur
-- einem Raid zugeordnet, wenn der Zeitstempel in dessen Zeitraum liegt.

local optFrame = getglobal("BananaLootOptionsFrame")
if not optFrame or not BananaLoot_UI.OptAddToTab then return end

local PLAYER_ROWS = 80
local PLAYER_ROW_H = 18
local selectedPlayer = nil
local playerRows = {}
local cached = nil

-- ============================================================
-- Auswertung
-- ============================================================
local function PoolCategory(pool)
    local p = string.lower(pool or "")
    if string.find(p, "haupt", 1, true) or string.find(p, "main", 1, true) then return "ms" end
    if string.find(p, "off", 1, true) then return "os" end
    if string.find(p, "transmog", 1, true) or string.find(p, "tmog", 1, true) then return "tm" end
    if string.find(p, "raid roll", 1, true) then return "rr" end
    if string.find(p, "manu", 1, true) then return "man" end
    if string.find(p, "bank", 1, true) then return "bank" end
    return "other"
end

local function LogTimestamp(entry)
    if entry.ts then return entry.ts end
    if not entry.time then return nil end
    local _, _, d, m, y, h, mi = string.find(entry.time, "^(%d+)%.(%d+)%.(%d+) (%d+):(%d+)$")
    if not d then return nil end
    local ok, t = pcall(time, { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
    if ok and type(t) == "number" then return t end
    return nil
end

local function NewPlayer()
    return { ms = 0, os = 0, tm = 0, rr = 0, man = 0, other = 0, total = 0, raids = {} }
end

local function Compute()
    BananaLoot.EnsureDB()
    local data = { raids = {}, players = {}, lootCat = { ms = 0, os = 0, tm = 0, rr = 0, man = 0 }, lootTotal = 0 }

    -- Raids (chronologisch), laufender Raid zuletzt
    local hist = BananaLoot_DB.raidHistory or {}
    for i = 1, table.getn(hist) do
        local r = hist[i]
        table.insert(data.raids, {
            startTime = r.startTime, endTime = r.endTime, duration = r.duration or 0,
            attendees = r.attendees or {}, raised = r.srPlusRaised, raisedCount = r.raisedCount or 0,
            loot = 0, running = false,
        })
    end
    local session = BananaLoot_DB.raidSession
    if session and session.running then
        local names = {}
        for name, _ in pairs(session.attendees) do table.insert(names, name) end
        table.insert(data.raids, {
            startTime = session.startTime, endTime = time(), duration = BananaLoot:GetRaidElapsed(),
            attendees = names, raised = false, raisedCount = 0, loot = 0, running = true,
        })
    end

    -- Teilnahmen
    for i = 1, table.getn(data.raids) do
        local att = data.raids[i].attendees
        for k = 1, table.getn(att) do
            local name = att[k]
            if not data.players[name] then data.players[name] = NewPlayer() end
            table.insert(data.players[name].raids, i)
        end
    end

    -- Loot-Log
    local log = BananaLoot_DB.log or {}
    for i = 1, table.getn(log) do
        local e = log[i]
        local cat = PoolCategory(e.pool)
        if e.winner and cat ~= "bank" then
            if not data.players[e.winner] then data.players[e.winner] = NewPlayer() end
            local pl = data.players[e.winner]
            pl[cat] = pl[cat] + 1
            pl.total = pl.total + 1
            data.lootTotal = data.lootTotal + 1
            if data.lootCat[cat] ~= nil then data.lootCat[cat] = data.lootCat[cat] + 1 end
        end
        local ts = LogTimestamp(e)
        if ts then
            for r = 1, table.getn(data.raids) do
                local raid = data.raids[r]
                if raid.startTime and ts >= raid.startTime - 60 and ts <= (raid.endTime or ts) + 60 then
                    raid.loot = raid.loot + 1
                    break
                end
            end
        end
    end

    -- sortierte Spielerliste (Teilnahmen absteigend, dann Name)
    data.sorted = {}
    for name, _ in pairs(data.players) do table.insert(data.sorted, name) end
    table.sort(data.sorted, function(a, b)
        local na = table.getn(data.players[a].raids)
        local nb = table.getn(data.players[b].raids)
        if na ~= nb then return na > nb end
        return a < b
    end)
    return data
end

local function RaidLabel(raid, index)
    local d = raid.startTime and date("%d.%m.%y", raid.startTime) or "?"
    return "#" .. index .. " " .. d
end

local function Bar(fraction)
    local filled = math.floor(fraction * 10 + 0.5)
    if filled < 0 then filled = 0 end
    if filled > 10 then filled = 10 end
    return "|cff33ff99" .. string.rep("=", filled) .. "|r|cff555555" .. string.rep("=", 10 - filled) .. "|r"
end

-- ============================================================
-- Oberflaeche
-- ============================================================
local overviewText = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
overviewText:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 22, -222)
overviewText:SetWidth(356)
overviewText:SetJustifyH("LEFT")

local dashScroll = CreateFrame("ScrollFrame", "BananaLootStatsScroll", optFrame, "UIPanelScrollFrameTemplate")
dashScroll:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -268)
dashScroll:SetWidth(340)
dashScroll:SetHeight(190)

local dashChild = CreateFrame("Frame", "BananaLootStatsScrollChild", dashScroll)
dashChild:SetWidth(320)
dashChild:SetHeight(1)
dashScroll:SetScrollChild(dashChild)

local dashText = dashChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dashText:SetPoint("TOPLEFT", dashChild, "TOPLEFT", 0, 0)
dashText:SetWidth(318)
dashText:SetJustifyH("LEFT")

local playersLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
playersLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 22, -470)

local playerScroll = CreateFrame("ScrollFrame", "BananaLootStatsPlayerScroll", optFrame, "UIPanelScrollFrameTemplate")
playerScroll:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 20, -492)
playerScroll:SetWidth(145)
playerScroll:SetHeight(160)

local playerChild = CreateFrame("Frame", "BananaLootStatsPlayerChild", playerScroll)
playerChild:SetWidth(140)
playerChild:SetHeight(1)
playerScroll:SetScrollChild(playerChild)

local detailText = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detailText:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 196, -494)
detailText:SetWidth(178)
detailText:SetJustifyH("LEFT")
detailText:SetJustifyV("TOP")

local function ShowDetail(name)
    selectedPlayer = name
    if not cached then return end
    local pl = name and cached.players[name]
    if not pl then
        detailText:SetText("|cff888888" .. BananaLoot:L("STATS_DETAIL_HINT") .. "|r")
        return
    end
    local total = table.getn(cached.raids)
    local att = table.getn(pl.raids)
    local pct = 0
    if total > 0 then pct = math.floor(att * 100 / total + 0.5) end
    local lines = {}
    table.insert(lines, BananaLoot:ColoredName(name))
    table.insert(lines, string.format(BananaLoot:L("STATS_DETAIL_ATT"), att, total, pct))
    table.insert(lines, string.format(BananaLoot:L("STATS_DETAIL_ITEMS"), pl.total))
    table.insert(lines, string.format(BananaLoot:L("STATS_DETAIL_SPLIT"), pl.ms, pl.os, pl.tm))
    table.insert(lines, string.format(BananaLoot:L("STATS_DETAIL_OTHER"), pl.rr, pl.man))
    if att > 0 then
        local labels = {}
        for i = 1, att do
            local idx = pl.raids[i]
            table.insert(labels, RaidLabel(cached.raids[idx], idx))
        end
        table.insert(lines, BananaLoot:L("STATS_DETAIL_RAIDS") .. " " .. table.concat(labels, ", "))
    else
        table.insert(lines, BananaLoot:L("STATS_DETAIL_RAIDS") .. " " .. BananaLoot:L("STATS_DETAIL_NONE"))
    end
    detailText:SetText(table.concat(lines, "\n"))
end

for i = 1, PLAYER_ROWS do
    local b = CreateFrame("Button", "BananaLootStatsPlayerRow" .. i, playerChild)
    b:SetWidth(138)
    b:SetHeight(PLAYER_ROW_H)
    b:SetPoint("TOPLEFT", playerChild, "TOPLEFT", 0, -(i - 1) * PLAYER_ROW_H)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "LEFT", 2, 0)
    b.label:SetJustifyH("LEFT")
    b:SetScript("OnClick", function()
        BananaLoot:PlayClickSound()
        if b.playerName then ShowDetail(b.playerName) end
    end)
    b:Hide()
    playerRows[i] = b
end

BananaLoot_UI.OptAddToTab(6, { overviewText, dashScroll, playersLabel, playerScroll, detailText })

local function Section(lines, title)
    table.insert(lines, "")
    table.insert(lines, "|cffffd100" .. title .. "|r")
end

function BananaLoot_UI:RefreshStats()
    local data = Compute()
    cached = data
    local raidCount = table.getn(data.raids)

    playersLabel:SetText(BananaLoot:L("STATS_PLAYERS_LABEL"))

    -- Uebersicht
    local totalDur, totalAtt = 0, 0
    for i = 1, raidCount do
        totalDur = totalDur + data.raids[i].duration
        totalAtt = totalAtt + table.getn(data.raids[i].attendees)
    end
    local avgDur, avgAtt = 0, "-"
    if raidCount > 0 then
        avgDur = totalDur / raidCount
        avgAtt = string.format("%.1f", totalAtt / raidCount)
    end
    local ov = {}
    table.insert(ov, string.format(BananaLoot:L("STATS_OVERVIEW_RAIDS"), raidCount,
        BananaLoot:FormatDuration(totalDur), BananaLoot:FormatDuration(avgDur), avgAtt))
    local c = data.lootCat
    table.insert(ov, string.format(BananaLoot:L("STATS_OVERVIEW_LOOT"), data.lootTotal, c.ms, c.os, c.tm, c.rr, c.man))
    if raidCount == 0 then
        table.insert(ov, "|cff888888" .. BananaLoot:L("STATS_NO_DATA") .. "|r")
    end
    overviewText:SetText(table.concat(ov, "\n"))

    -- Dashboard-Text
    local lines = {}
    if raidCount > 0 then
        table.insert(lines, "|cffffd100" .. BananaLoot:L("STATS_SEC_RAIDS") .. "|r")
        local shown = 0
        for i = raidCount, 1, -1 do
            if shown >= 15 then break end
            shown = shown + 1
            local r = data.raids[i]
            local status
            if r.running then
                status = "|cff33ff99" .. BananaLoot:L("STATS_RAID_RUNNING") .. "|r"
            elseif r.raised then
                status = string.format(BananaLoot:L("STATS_RAID_RAISED"), r.raisedCount)
            else
                status = BananaLoot:L("STATS_RAID_NORAISE")
            end
            table.insert(lines, string.format(BananaLoot:L("STATS_RAID_LINE"), i,
                r.startTime and date("%d.%m.%y", r.startTime) or "?",
                BananaLoot:FormatDuration(r.duration), table.getn(r.attendees), r.loot, status))
        end
    end

    -- Loot-Rangliste
    local byLoot = {}
    for name, pl in pairs(data.players) do
        if pl.total > 0 then table.insert(byLoot, name) end
    end
    table.sort(byLoot, function(a, b)
        local ta, tb = data.players[a].total, data.players[b].total
        if ta ~= tb then return ta > tb end
        return a < b
    end)
    if table.getn(byLoot) > 0 then
        Section(lines, BananaLoot:L("STATS_SEC_LOOT"))
        for i = 1, math.min(10, table.getn(byLoot)) do
            local pl = data.players[byLoot[i]]
            table.insert(lines, string.format(BananaLoot:L("STATS_LOOT_LINE"), i,
                BananaLoot:ColoredName(byLoot[i]), pl.total, pl.ms, pl.os, pl.tm))
        end
    end

    -- Anwesenheit
    if raidCount > 0 and table.getn(data.sorted) > 0 then
        Section(lines, BananaLoot:L("STATS_SEC_ATT"))
        for i = 1, table.getn(data.sorted) do
            local name = data.sorted[i]
            local att = table.getn(data.players[name].raids)
            if att > 0 then
                local frac = att / raidCount
                table.insert(lines, string.format(BananaLoot:L("STATS_ATT_LINE"),
                    BananaLoot:ColoredName(name), att, raidCount, Bar(frac), math.floor(frac * 100 + 0.5)))
            end
        end
    end

    -- Hoechste SR+
    local top = {}
    for name, stacks in pairs(BananaLoot_DB.players or {}) do
        for id, value in pairs(stacks) do
            if type(value) == "number" and value > 0 then
                table.insert(top, { name = name, id = id, value = value })
            end
        end
    end
    table.sort(top, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    if table.getn(top) > 0 then
        Section(lines, BananaLoot:L("STATS_SEC_SRPLUS"))
        for i = 1, math.min(10, table.getn(top)) do
            local t = top[i]
            local res = BananaLoot.reservations[t.id]
            local itemName = nil
            if res and res.link then
                local _, _, linkName = string.find(res.link, "%[(.-)%]")
                itemName = linkName
            end
            if not itemName then
                local si = BananaLoot:GetStaticItemInfo(t.id)
                itemName = si and si.name or ("Item #" .. t.id)
            end
            table.insert(lines, string.format(BananaLoot:L("STATS_SRPLUS_LINE"), i,
                BananaLoot:ColoredName(t.name), "[" .. itemName .. "]", t.value))
        end
    end

    dashText:SetText(table.concat(lines, "\n"))
    dashChild:SetHeight(math.max(1, dashText:GetHeight() + 8))

    -- Spielerliste
    local shownPlayers = 0
    for i = 1, table.getn(data.sorted) do
        if i <= PLAYER_ROWS then
            shownPlayers = shownPlayers + 1
            local name = data.sorted[i]
            local row = playerRows[shownPlayers]
            row.playerName = name
            row.label:SetText(BananaLoot:ColoredName(name) .. " |cff888888" ..
                table.getn(data.players[name].raids) .. "/" .. raidCount .. "|r")
            row:Show()
        end
    end
    for i = shownPlayers + 1, PLAYER_ROWS do
        playerRows[i].playerName = nil
        playerRows[i]:Hide()
    end
    playerChild:SetHeight(math.max(1, shownPlayers * PLAYER_ROW_H))

    if selectedPlayer and not data.players[selectedPlayer] then selectedPlayer = nil end
    ShowDetail(selectedPlayer)
end

function BananaLoot_UI:ApplyLocaleStats()
    if optFrame:IsShown() and dashScroll:IsShown() then BananaLoot_UI:RefreshStats() end
end
