-- BananaLootItemTip.lua
-- Item-Tooltips fuer ALLE Items: Zuerst der echte Tooltip des Clients (SetHyperlink). Kennt der
-- Client das Item nicht (noch nie gesehen, Server hat nicht geantwortet), wird der Tooltip
-- lokal aus der mitgelieferten Item-Datenbank aufgebaut: Name in Qualitaetsfarbe, Platz,
-- Item-Level, Ruestung/Waffenschaden und Werte. So steht bei jedem Item eine Information.
--
-- Lua 5.0: kein #-Operator, kein %-Operator, kein string.gmatch/match.

local QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
    [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80",
}

-- Slot-ID der Item-DB -> Name der Blizzard-Globalstrings (lokalisiert durch den Client)
local SLOT_GLOBALS = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY",
    [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET",
    [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET",
    [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK",
    [17] = "INVTYPE_2HWEAPON", [19] = "INVTYPE_TABARD", [20] = "INVTYPE_ROBE",
    [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE",
    [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC",
}

-- Anzeigereihenfolge und Texte (de, en). %s = Wert.
local STAT_ORDER = {
    "ARMOR", "BLOCKVALUE", "STR", "AGI", "STA", "INT", "SPI", "AP", "RAP", "SPELLPOWER", "HEALPOWER",
    "SPELLPOWER_ARCANE", "SPELLPOWER_FIRE", "SPELLPOWER_FROST", "SPELLPOWER_HOLY",
    "SPELLPOWER_NATURE", "SPELLPOWER_SHADOW", "CRIT", "SPELLCRIT", "HIT", "SPELLHIT", "DEFENSE",
    "DODGE", "PARRY", "BLOCK", "RES_ARCANE", "RES_FIRE", "RES_FROST", "RES_NATURE", "RES_SHADOW",
}
local STAT_TEXT = {
    ARMOR = { "%s Rüstung", "%s Armor" },
    BLOCKVALUE = { "%s Blockwert", "%s Block" },
    STR = { "+%s Stärke", "+%s Strength" },
    AGI = { "+%s Beweglichkeit", "+%s Agility" },
    STA = { "+%s Ausdauer", "+%s Stamina" },
    INT = { "+%s Intelligenz", "+%s Intellect" },
    SPI = { "+%s Willenskraft", "+%s Spirit" },
    AP = { "+%s Angriffskraft", "+%s Attack Power" },
    RAP = { "+%s Distanzangriffskraft", "+%s Ranged Attack Power" },
    SPELLPOWER = { "+%s Zaubermacht", "+%s Spell Power" },
    HEALPOWER = { "+%s Heilung", "+%s Healing" },
    SPELLPOWER_ARCANE = { "+%s Arkanzaubermacht", "+%s Arcane Spell Damage" },
    SPELLPOWER_FIRE = { "+%s Feuerzaubermacht", "+%s Fire Spell Damage" },
    SPELLPOWER_FROST = { "+%s Frostzaubermacht", "+%s Frost Spell Damage" },
    SPELLPOWER_HOLY = { "+%s Heiligzaubermacht", "+%s Holy Spell Damage" },
    SPELLPOWER_NATURE = { "+%s Naturzaubermacht", "+%s Nature Spell Damage" },
    SPELLPOWER_SHADOW = { "+%s Schattenzaubermacht", "+%s Shadow Spell Damage" },
    CRIT = { "+%s%% kritische Trefferchance", "+%s%% critical strike chance" },
    SPELLCRIT = { "+%s%% kritische Zaubertrefferchance", "+%s%% spell critical strike chance" },
    HIT = { "+%s%% Trefferchance", "+%s%% hit chance" },
    SPELLHIT = { "+%s%% Zaubertrefferchance", "+%s%% spell hit chance" },
    DEFENSE = { "+%s Verteidigung", "+%s Defense" },
    DODGE = { "+%s%% Ausweichen", "+%s%% dodge" },
    PARRY = { "+%s%% Parieren", "+%s%% parry" },
    BLOCK = { "+%s%% Blocken", "+%s%% block" },
    RES_ARCANE = { "+%s Arkanwiderstand", "+%s Arcane Resistance" },
    RES_FIRE = { "+%s Feuerwiderstand", "+%s Fire Resistance" },
    RES_FROST = { "+%s Frostwiderstand", "+%s Frost Resistance" },
    RES_NATURE = { "+%s Naturwiderstand", "+%s Nature Resistance" },
    RES_SHADOW = { "+%s Schattenwiderstand", "+%s Shadow Resistance" },
}

local function Lang()
    return (BananaLoot:GetLanguage() == "en") and 2 or 1
end

-- Baut den Tooltip lokal aus der Item-Datenbank (Name immer, Details wenn vorhanden).
function BananaLoot:ShowStaticTooltip(owner, itemID, anchor)
    local info = self:GetStaticItemInfo(itemID)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if not info then
        GameTooltip:SetText("Item #" .. itemID)
        GameTooltip:AddLine(self:L("TIP_OFFLINE"), 0.7, 0.7, 0.7, 1)
        GameTooltip:Show()
        return
    end
    local l = Lang()
    GameTooltip:SetText("|cff" .. (QUALITY_HEX[info.quality] or "ffffff") .. info.name .. "|r")
    if info.ilvl then
        GameTooltip:AddLine(string.format(self:L("TIP_ILVL"), info.ilvl), 1, 0.82, 0)
    end
    local slotName = info.slot and SLOT_GLOBALS[info.slot] and getglobal(SLOT_GLOBALS[info.slot])
    if slotName then GameTooltip:AddLine(slotName, 1, 1, 1) end
    local st = info.stats
    if st then
        if st.WEAPON_MIN and st.WEAPON_MAX then
            GameTooltip:AddLine(string.format(self:L("TIP_WEAPON_DMG"), tostring(st.WEAPON_MIN), tostring(st.WEAPON_MAX)), 1, 1, 1)
            if st.WEAPON_SPEED then
                GameTooltip:AddLine(string.format(self:L("TIP_WEAPON_SPEED"), tostring(st.WEAPON_SPEED)), 1, 1, 1)
            end
            if st.WEAPON_DPS then
                GameTooltip:AddLine(string.format(self:L("TIP_WEAPON_DPS"), tostring(st.WEAPON_DPS)), 0.8, 0.8, 0.8)
            end
        end
        for i = 1, table.getn(STAT_ORDER) do
            local k = STAT_ORDER[i]
            local v = st[k]
            if v and STAT_TEXT[k] then
                local isBonus = (k ~= "ARMOR" and k ~= "BLOCKVALUE")
                if isBonus then
                    GameTooltip:AddLine(string.format(STAT_TEXT[k][l], tostring(v)), 0, 1, 0)
                else
                    GameTooltip:AddLine(string.format(STAT_TEXT[k][l], tostring(v)), 1, 1, 1)
                end
            end
        end
    end
    if info.reqlevel and info.reqlevel > 1 then
        GameTooltip:AddLine(string.format(self:L("TIP_REQLEVEL"), info.reqlevel), 1, 1, 1)
    end
    GameTooltip:AddLine(self:L("TIP_OFFLINE"), 0.6, 0.6, 0.6, 1)
    GameTooltip:Show()
end

-- Echter Tooltip, sonst der lokale. owner = Frame, an dem der Tooltip haengt.
function BananaLoot:ShowItemTooltip(owner, itemID, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local ok = pcall(function() GameTooltip:SetHyperlink("item:" .. itemID .. ":0:0:0:0:0:0:0") end)
    local lines = 0
    if ok and GameTooltip:NumLines() then lines = GameTooltip:NumLines() end
    if lines == 0 then
        self:ShowStaticTooltip(owner, itemID, anchor)
    else
        GameTooltip:Show()
    end
end
