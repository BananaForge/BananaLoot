-- BananaLootMini.lua
-- Kleiner, frei verschiebbarer Button "GL"/"ML" (Gruppenloot / Masterloot), unabhaengig vom
-- Hauptfenster immer sichtbar. Ein Klick wechselt die Loot-Methode genau wie der ML/GL-Button
-- im SR-Fenster, ziehen verschiebt ihn (Position wird gespeichert). "/bl mini" blendet ihn
-- ein/aus.
--
-- Lua 5.0: kein #-Operator, Events ueber this/arg1.

local btn = CreateFrame("Button", "BananaLootMiniGLBtn", UIParent, "UIPanelButtonTemplate")
btn:SetWidth(38)
btn:SetHeight(22)
btn:SetFrameStrata("MEDIUM")
btn:SetToplevel(true)
btn:SetMovable(true)
btn:EnableMouse(true)
btn:RegisterForDrag("LeftButton")
btn:SetPoint("TOP", UIParent, "TOP", 0, -26)   -- Standard: oben in der Bildschirmmitte
btn:Hide()

local function CurrentIsMaster()
    local ok, method = pcall(GetLootMethod)
    return ok and method == "master"
end

function BananaLoot_UI:UpdateMiniGL()
    if CurrentIsMaster() then
        btn:SetText("|cff33ff99ML|r")
    else
        btn:SetText("|cffffd100GL|r")
    end
end

btn:SetScript("OnDragStart", function() this:StartMoving() end)
btn:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local left, top = this:GetLeft(), this:GetTop()
    if left and top then
        BananaLoot.EnsureDB()
        BananaLoot_DB.settings.miniGL = { x = left, y = top }
    end
end)

btn:SetScript("OnClick", function()
    BananaLoot:PlayClickSound()
    -- gleiche Logik wie der ML/GL-Button im SR-Fenster
    local lm = getglobal("BananaLootLootMethodBtn")
    local fn = lm and lm:GetScript("OnClick")
    if fn then
        local keep = this
        this = lm
        fn()
        this = keep
    elseif CurrentIsMaster() then
        SetLootMethod("group")
    else
        SetLootMethod("master", UnitName("player"))
    end
    BananaLoot_UI:UpdateMiniGL()
end)

btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
    GameTooltip:SetText(BananaLoot:L("MINI_TOOLTIP"), 1, 1, 1, 1, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

function BananaLoot:GetMiniGLEnabled()
    BananaLoot.EnsureDB()
    return BananaLoot_DB.settings.miniGLEnabled ~= false
end

function BananaLoot:SetMiniGLEnabled(on)
    BananaLoot.EnsureDB()
    BananaLoot_DB.settings.miniGLEnabled = on and true or false
    if on then btn:Show() else btn:Hide() end
end

function BananaLoot_UI:ToggleMiniGL()
    local on = not BananaLoot:GetMiniGLEnabled()
    BananaLoot:SetMiniGLEnabled(on)
    DEFAULT_CHAT_FRAME:AddMessage(BananaLoot:L(on and "MINI_ON" or "MINI_OFF"))
end

-- Position und Sichtbarkeit erst nach dem Laden der SavedVariables anwenden.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        BananaLoot.EnsureDB()
        local pos = BananaLoot_DB.settings.miniGL
        if pos and pos.x and pos.y then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        end
        if BananaLoot:GetMiniGLEnabled() then btn:Show() end
    end
    BananaLoot_UI:UpdateMiniGL()
end)
BananaLoot_UI:UpdateMiniGL()
