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
