#!/usr/bin/env python3
"""Erzeugt BananaLootItemInfoExtra.lua: Name, Qualitaet und Icon fuer alle Items, die in
AtlasLoot vorkommen, aber in BananaLootItemDB.lua fehlen.

Aufruf: python3 tools/gen_item_info.py <pfad/zu/AtlasLoot> [ausgabe.lua]
Quelle der Daten: AtlasLoot Turtle WoW Edition (Nutzung mit Erlaubnis des Entwicklers).

Hintergrund: Der Client kennt Items, die er noch nie gesehen hat, nicht (GetItemInfo liefert
nichts). Damit BananaLoot trotzdem fuer JEDES Item Name, Farbe und Icon anzeigen kann, liegen
diese Angaben lokal vor: BananaLootItemDB.lua (Hauptdatenbank) plus diese Ergaenzung.
"""
import re, sys, os, glob

src = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "BananaLootItemInfoExtra.lua")

known = set()
for l in open(os.path.join(here, "..", "BananaLootItemDB.lua"), encoding="utf-8", errors="replace"):
    m = re.match(r"^\[(\d+)\]=", l)
    if m:
        known.add(int(m.group(1)))

# Item-Zeile: { Slot, ID, "Icon", "=qQ=Name", ...
pat = re.compile(r'^\s*\{\s*(?:\d+|"[^"]*"),\s*(\d+),\s*"([^"]*)",\s*"=q(\d)=([^"]*)"', re.M)
info = {}
for f in sorted(glob.glob(os.path.join(src, "Database", "*.lua"))):
    t = open(f, encoding="utf-8-sig", errors="replace").read()
    for m in pat.finditer(t):
        i = int(m.group(1))
        if i > 0 and i not in known and i not in info:
            info[i] = (m.group(4), int(m.group(3)), m.group(2))

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')

with open(out, "w", encoding="utf-8", newline="\n") as o:
    o.write("""-- BananaLootItemInfoExtra.lua
-- Ergaenzung zu BananaLootItemDB.lua: Name, Qualitaet und Icon fuer Items, die dort fehlen
-- (Instanz-, Set-, PvP-, Weltboss- und Weltevent-Beute). [id] = { name, quality (0-6), icon }
-- Wird von BananaLoot:GetStaticItemInfo() als zweite Quelle genutzt, damit auch Items, die der
-- Client noch nie gesehen hat, mit Namen, Farbe und Icon angezeigt werden (kein "Item #123").
-- Quelle: AtlasLoot Turtle WoW Edition (Nutzung mit Erlaubnis des Entwicklers).
-- REINE DATEN. Neu erzeugen mit: python3 tools/gen_item_info.py <AtlasLoot-Ordner>
-- Anzahl Items: %d

BananaLoot_ItemInfoExtra = {
""" % len(info))
    for i in sorted(info):
        n, q, ic = info[i]
        o.write('[%d]={"%s",%d,"%s"},\n' % (i, esc(n), q, esc(ic)))
    o.write("}\n")
print(len(info), "Items ergaenzt")
