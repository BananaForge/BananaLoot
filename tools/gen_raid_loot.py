#!/usr/bin/env python3
"""Erzeugt BananaLootRaidLoot.lua (Raid -> Bosse -> Item-IDs) aus einer AtlasLoot-Kopie.

Aufruf: python3 tools/gen_raid_loot.py <pfad/zu/AtlasLoot> [ausgabe.lua]
Quelle der Daten: AtlasLoot Turtle WoW Edition (Nutzung mit Erlaubnis des Entwicklers).

Gruppiert die Items je Raid nach Boss (Reihenfolge wie im AtlasLoot-Menue). Wird vom
Raid-Setup-Fenster (Hard Reserve / Raid-Roll-Auswahl) benutzt. Die Schluessel sind die
Raid-Keys aus BananaLootBossData.lua (MC, BWL, NAXX ...).
"""
import re, sys, os

src = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "..", "BananaLootRaidLoot.lua")
rd = lambda p: open(os.path.join(src, p), encoding="utf-8-sig", errors="replace").read()

inst, menus = rd("Database/Instances.lua"), rd("Database/Menus.lua")

# AtlasLoot-Menuename -> Raid-Key (BananaLootBossData.lua), in Anzeigereihenfolge
RAIDS = [
    ("MoltenCore", "MC"), ("Onyxia", "ONY"), ("BlackwingLair", "BWL"),
    ("ZulGurub", "ZG"), ("RuinsofAQ", "AQ20"), ("TempleofAQ", "AQ40"),
    ("Naxxramas", "NAXX"), ("EmeraldSanctum", "ES"), ("LowerKara", "LKH"),
    ("UpperKara", "UKH"), ("TimbermawHold", "TIMB"), ("UpperBlackrock", "UBRS"),
    ("WorldBosses", "WB"),
]

# Tabellen-Key -> Item-IDs
table_items = {}
item_info = {}   # id -> (name, quality, icon) aus den AtlasLoot-Zeilen
cur = None
for line in inst.splitlines():
    m = re.match(r"^    ([A-Za-z0-9_]+) = \{\s*$", line)
    if m:
        cur = m.group(1)
        table_items[cur] = []
        continue
    # echte Item-Zeile: { Slot, ID, "Icon", ... } (Varianten-Listen { id, id, } ausschliessen)
    m = re.match(r'^\s*\{\s*\d+,\s*(\d+),\s*"', line)
    if m and cur and int(m.group(1)) > 0:
        table_items[cur].append(int(m.group(1)))
        mi = re.match(r'^\s*\{\s*\d+,\s*(\d+),\s*"([^"]*)",\s*"=q(\d)=([^"]*)"', line)
        if mi and int(mi.group(1)) not in item_info:
            item_info[int(mi.group(1))] = (mi.group(4), int(mi.group(3)), mi.group(2))

# Statische DB (zur Abdeckungspruefung)
db_path = os.path.join(here, "..", "BananaLootItemDB.lua")
known = set()
if os.path.exists(db_path):
    for l in open(db_path, encoding="utf-8", errors="replace"):
        m = re.match(r"^\[(\d+)\]=", l)
        if m:
            known.add(int(m.group(1)))

result = {}
for menu_key, raid_key in RAIDS:
    m = re.search(r'\n    \["%s"\] = \{\n(.*?)\n    \},' % re.escape(menu_key), menus, re.S)
    if not m:
        print("WARN: kein Menue fuer", menu_key)
        continue
    bosses, seen_names = [], {}
    for line in m.group(1).splitlines():
        line = line.strip()
        if line.startswith("--"):
            continue
        e = re.match(r'^\{\s*(.*?),\s*"(\w+)"\s*\},?\s*$', line)
        if not e:
            continue
        expr, tkey = e.groups()
        parts = re.findall(r'L\["([^"]+)"\]', expr)
        if not parts:
            continue
        name = parts[0] if len(parts) == 1 else "%s (%s)" % (parts[0], parts[1])
        ids = []
        for i in table_items.get(tkey, []):
            if i not in ids:
                ids.append(i)
        if not ids:
            continue
        if name in seen_names:
            seen_names[name] += 1
            name = "%s (%d)" % (name, seen_names[name])
        else:
            seen_names[name] = 1
        bosses.append((name, ids))
    result[raid_key] = bosses

with open(out, "w", encoding="utf-8", newline="\n") as o:
    o.write("""-- BananaLootRaidLoot.lua
-- Raid -> Bosse -> Item-IDs (Reihenfolge wie im AtlasLoot-Menue).
-- Wird vom Raid-Setup-Fenster (Hard-Reserve- und Raid-Roll-Auswahl) benutzt.
-- Schluessel = Raid-Key aus BananaLootBossData.lua (MC, BWL, NAXX ...).
-- Quelle: AtlasLoot Turtle WoW Edition (Nutzung mit Erlaubnis des Entwicklers).
-- REINE DATEN. Neu erzeugen mit: python3 tools/gen_raid_loot.py <AtlasLoot-Ordner>

BananaLoot_RaidLoot = {
""")
    for _, raid_key in RAIDS:
        if raid_key not in result or not result[raid_key]:
            continue
        o.write('["%s"]={\n' % raid_key)
        for name, ids in result[raid_key]:
            o.write('{"%s",{%s}},\n' % (name.replace('"', '\\"'), ",".join(map(str, ids))))
        o.write("},\n")
    o.write("}\n\n")
    # Name/Qualitaet/Icon nur fuer Items, die NICHT in BananaLootItemDB.lua stehen
    o.write("-- Fallback-Infos fuer Items ohne Eintrag in BananaLootItemDB.lua: [id]={name,quality,icon}\n")
    o.write("BananaLoot_RaidLootInfo = {\n")
    used = sorted(set(i for b in result.values() for _, l in b for i in l))
    for i in used:
        if known and i in known:
            continue
        if i in item_info:
            n, q, ic = item_info[i]
            o.write('[%d]={"%s",%d,"%s"},\n' % (i, n.replace("\\", "\\\\").replace('"', '\\"'), q, ic))
    o.write("}\n")

tot = missing = 0
maxb = 0
for k, b in result.items():
    ids = set(i for _, l in b for i in l)
    miss = [i for i in ids if known and i not in known]
    tot += len(ids)
    missing += len(miss)
    maxb = max(maxb, len(b))
    print("%-5s %2d Bosse, %3d Items, %d nicht in ItemDB" % (k, len(b), len(ids), len(miss)))
noinfo = [i for i in set(i for b in result.values() for _, l in b for i in l) if known and i not in known and i not in item_info]
print("ohne jede Info (weder ItemDB noch AtlasLoot):", len(noinfo))
print("gesamt", tot, "Items,", missing, "nicht in ItemDB, max. Bosse je Raid:", maxb)
