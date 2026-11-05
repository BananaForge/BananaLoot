-- BananaLootTheme.lua
-- Einheitlicher, gut lesbarer Fensterhintergrund fuer alle BananaLoot-Fenster.
--
-- Der Standard-Dialoghintergrund (UI-DialogBox-Background) ist halbtransparent:
-- Texte darunterliegender Fenster scheinen durch. Darken() legt hinter den Inhalt
-- eine fast deckende dunkle Flaeche (innerhalb des Rahmens) und macht das Fenster
-- "toplevel", damit ein angeklicktes/geoeffnetes Fenster samt Inhalt komplett ueber
-- anderen Fenstern derselben Ebene liegt.
--
-- Ebenen (FrameStrata):
--   HIGH    Hauptfenster: SR-Fenster, Loot-Fenster, Roll-Sync-Popup, Testmodus
--   DIALOG  alle weiteren Fenster (Optionen, Listen, Verwalten, Raid-Setup, ...)
--   (Blizzards StaticPopups und Tooltips liegen darueber)
--
-- Wird als ERSTE Lua-Datei geladen.

BananaLoot_Theme = {}
local T = BananaLoot_Theme

T.BG = { 0.03, 0.03, 0.05, 0.95 }   -- Fensterflaeche (fast deckend)
T.PANEL_ALPHA = 0.95                -- Unterpanels (Listen, Bossspalte, ...)

function T.Darken(f)
    if not f or f.bananaBG then return end
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(T.BG[1], T.BG[2], T.BG[3], T.BG[4])
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -11)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -11, 11)
    f.bananaBG = t
    if f.SetToplevel then f:SetToplevel(true) end
end

-- Setzt den Text eines Buttons und kuerzt ihn mit "...", falls er breiter als maxWidth waere.
-- (Langer Text passt so immer in den Button; der volle Text gehoert in den Tooltip.)
function T.FitText(btn, text, maxWidth)
    btn:SetText(text)
    local fs = btn.GetFontString and btn:GetFontString()
    if not fs or not fs.GetStringWidth then return text end
    local shown = text
    local guard = 0
    while fs:GetStringWidth() > maxWidth and string.len(shown) > 4 and guard < 80 do
        shown = string.sub(shown, 1, string.len(shown) - 1)
        btn:SetText(shown .. "...")
        guard = guard + 1
    end
    return shown
end

-- Rueckfrage-Dialoge (StaticPopup) von BananaLoot (Raid beenden, SR+ anheben, Raid loeschen ...):
-- Blizzards Dialoghintergrund ist durchscheinend; fuer Dialoge mit dem Namen "BANANALOOT_*"
-- wird dieselbe dunkle Flaeche wie in den Fenstern dahinter gelegt. Fremde Dialoge bleiben
-- unveraendert (die vier Popup-Frames werden wiederverwendet, die Flaeche daher bei Bedarf
-- wieder ausgeblendet).
function T.StylePopup(frame, which)
    if not frame then return end
    local ours = which and string.find(which, "^BANANALOOT_") ~= nil
    if ours then
        if not frame.bananaPopupBG then
            local t = frame:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(T.BG[1], T.BG[2], T.BG[3], T.BG[4])
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -11)
            t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 11)
            frame.bananaPopupBG = t
        end
        frame.bananaPopupBG:Show()
    elseif frame.bananaPopupBG then
        frame.bananaPopupBG:Hide()
    end
end

if StaticPopup_Show then
    local origStaticPopupShow = StaticPopup_Show
    StaticPopup_Show = function(which, text1, text2, data)
        local frame = origStaticPopupShow(which, text1, text2, data)
        if not frame then
            for i = 1, 4 do
                local f = getglobal("StaticPopup" .. i)
                if f and f:IsShown() and f.which == which then frame = f end
            end
        end
        T.StylePopup(frame, which)
        return frame
    end
end
