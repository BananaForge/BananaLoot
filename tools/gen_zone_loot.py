#!/usr/bin/env python3
"""Erzeugt BananaLootZoneLoot.lua aus einer AtlasLoot-(Turtle-WoW)-Kopie.

Aufruf: python3 tools/gen_zone_loot.py <pfad/zu/AtlasLoot> [ausgabe.lua]
Quelle der Daten: AtlasLoot Turtle WoW Edition (Nutzung mit Erlaubnis des Entwicklers).
"""
import re, sys, os, collections

src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "BananaLootZoneLoot.lua")
rd = lambda p: open(os.path.join(src, p), encoding="utf-8-sig", errors="replace").read()

inst, menus = rd("Database/Instances.lua"), rd("Database/Menus.lua")

# 1) Boss-Key -> Item-IDs (AtlasLootItems)
items_part = inst[inst.index('AtlasLoot_Data["AtlasLootItems"]'):]
boss_items = {}
cur = None
for line in items_part.splitlines():
    m = re.match(r"^    ([A-Za-z0-9_]+) = \{\s*$", line)
    if m:
        cur = m.group(1); boss_items[cur] = []; continue
    m = re.match(r"^\s*\{\s*\d+,\s*(\d+),", line)
    if m and cur and int(m.group(1)) > 0:
        boss_items[cur].append(int(m.group(1)))

# 2) Instanz-Bosstabellen
inst_bosses = {}
for m in re.finditer(r"AtlasLootBossButtons\.(\w+) = \{(.*?)\n\}", inst, re.S):
    inst_bosses[m.group(1)] = re.findall(r'"([A-Za-z0-9_]+)"', m.group(2))

# 3) Menueeintraege: erster Boss-Key + Instanzname (Englisch)
zones = collections.OrderedDict()  # english name -> set(ids)
for blk in re.finditer(r"DUNGEONSMENU\d = \{(.*?)\n    \},", menus, re.S):
    for m in re.finditer(r'\{\s*\d+,\s*"(\w+)",\s*"[^"]*",\s*[^"\n]*"[^"\n]*\|r "\.\.L\["([^"]+)"\]', blk.group(1)):
        boss, name = m.groups()
        tbl = [b for b in inst_bosses.values() if boss in b]
        keys = set(tbl[0]) if tbl else {boss}
        ids = set()
        for k in keys:
            ids.update(boss_items.get(k, []))
        zones[name] = ids

with open(out, "w", encoding="utf-8", newline="\n") as o:
    o.write("""-- BananaLootZoneLoot.lua
-- Instanz (Dungeon/Raid) -> Item-IDs, die dort droppen koennen.
-- Wird fuer das Vorladen unbekannter Items genutzt (siehe BananaLoot:PrefetchZoneItems).
-- Quelle: AtlasLoot Turtle WoW Edition (Nutzung mit Erlaubnis des Entwicklers).
-- REINE DATEN. Neu erzeugen mit: python3 tools/gen_zone_loot.py <AtlasLoot-Ordner>

BananaLoot_ZoneLoot = {
""")
    for name, ids in zones.items():
        if not ids:
            continue
        o.write('["%s"]={%s},\n' % (name.replace('"', '\\"'), ",".join(map(str, sorted(ids)))))
    o.write("}\n")
print(len(zones), "Instanzen,", sum(len(v) for v in zones.values()), "IDs")
for n, v in zones.items():
    print(f"{n}: {len(v)}")
