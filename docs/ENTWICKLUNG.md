# BananaLoot — Entwicklung

Technische Notizen für alle, die am Addon arbeiten. Die Bedienung steht in
[`ANLEITUNG.txt`](ANLEITUNG.txt), die Änderungen in [`../CHANGELOG.md`](../CHANGELOG.md).

## Aufbau

Das Repo **ist** der Addon-Ordner: alles, was der Client braucht, liegt im
Stamm. Was nur fürs Repo da ist (`docs/`, `tools/`, `assets/`,
`screenshots/`, `.github/`), landet nicht im Release-ZIP.

Ladereihenfolge laut `BananaLoot.toc`:

| Datei | Inhalt |
|---|---|
| `BananaLootItemDB.lua` | Statische Item-Datenbank `[itemID] = { name, quality }`, ~3600 Einträge aus AtlasLoot (OctoWoW-Fork) und AtlasLootClassic. Fallback, weil `GetItemInfo()` auf dem Server für ungesehene Items nichts liefert. **Fremddaten** — siehe `THIRD_PARTY_NOTICES.md`. |
| `BananaLoot.lua` | Kernlogik: SavedVariables und Migration, Übersetzungen (DE/EN), Sounds, Reservierungen, Hard/Bank Reserve, Whisper-Befehle, Roll-Sync, Trade-Tracking, Roll-Auswertung, Vergabe, Loot-Erkennung, Export/Import, raidres.top-Import, Loot-Log, Auto-Masterloot, LFM, Events, Slash-Befehle. |
| `BananaLootUI.lua` | SR-Fenster, Loot-Fenster, Roll-Sync-Popup. |
| `BananaLootExtra.lua` | Optionsfenster (fünf Reiter), Export/Import- und CSV-Popups, Verwalten-Fenster, HR-/BR-Listen, SR+-Wiederherstellung, LFM-Fenster, Raid speichern/laden, Minimap-Button. |

Jede Lua-Datei hat oben einen Kopfkommentar und ist in nummerierte
Abschnitte (`-- 1) …`, `-- 2b) …`) gegliedert.

## Feste Namen

Diese Namen sind nach außen sichtbar oder liegen in den SavedVariables.
Wer sie ändert, bricht bestehende Installationen oder die Verbindung
zwischen Spielern mit verschiedenen Versionen.

| Was | Name |
|---|---|
| Addon-Ordner | `BananaLoot` (Texturpfade hängen daran) |
| SavedVariables | `BananaLoot_DB` |
| Globale Tabellen | `BananaLoot`, `BananaLoot_UI` |
| Addon-Message-Prefix (Roll-Sync, Trade-Tracking) | `"BananaLoot"` |
| Slash-Befehle | `/bl`, `/bananaloot` |

**Datenbankänderungen:** `BananaLoot.DB_VERSION` hochzählen und die
Umstellung in `MigrateDB()` (`BananaLoot.lua`) ergänzen.

## Lua 5.0

WoW 1.12 läuft auf Lua 5.0. Lua 5.1 meldet folgende Dinge **nicht** als
Fehler, im Spiel brechen sie aber ab:

| Nicht verwenden | Stattdessen |
|---|---|
| `#t`, `#s` | `table.getn(t)`, `string.len(s)` |
| `a % b` | `math.mod(a, b)` |
| `string.gmatch` | `string.gfind` |
| `string.match`, `s:match()` | `string.find` mit Captures |
| `select()`, `...` als Ausdruck | `arg`-Tabelle |

Events laufen im klassischen Vanilla-Stil über die globalen `event`,
`arg1` … `argN`.

`tools/check_lua50.lua` sucht nach den ersten vier Punkten (Kommentare
und Zeichenketten ausgenommen). Den letzten Punkt prüft es nicht.

## Grafiken

Liegen in `Icons/`, geladen als `Interface\AddOns\BananaLoot\Icons\<Name>`
(ohne Endung):

- `BananaLoot_Logo_256.tga` — ganzes Logo, oben im Optionsfenster
  (`optLogo` in `BananaLootExtra.lua`).
- `BananaLoot_Icon_64.tga` — nur die Kiste ohne Schriftzug, für
  Minimap-Button und die Titelzeilen von SR- und Loot-Fenster.

Regeln für Ersatzgrafiken: Kantenlängen als Zweierpotenz (16, 32, 64 … 512),
sonst lädt der Client die Datei gar nicht. Unkomprimiertes 32-Bit-TGA mit
Alphakanal. Quadratisch lassen, der Code zeigt sie ohne `SetTexCoord` mit
gleicher Breite und Höhe an.

Die PNG/JPG-Bilder in `assets/` sind nur für die README auf GitHub.

## Prüfen

```bash
bash tools/run_tests.sh
```

Braucht `lua5.1` und `luac5.1` (unter Git Bash auf Windows nicht dabei —
dann einfach pushen, GitHub Actions führt dieselben Prüfungen aus).
Geprüft wird:

1. Syntax aller `.lua`-Dateien
2. keine leeren oder abgeschnittenen Dateien
3. Lua-5.0-Kompatibilität (`tools/check_lua50.lua`)
4. jede Datei aus der TOC existiert, jede `.lua` steht in der TOC
5. `## Version:` in der TOC = `BananaLoot.VERSION` in `BananaLoot.lua`;
   der CHANGELOG hat eine Ueberschrift `## v<Version>`
6. jede Textur, die der Code lädt, liegt im Repo

Was sich nur im Spiel prüfen lässt — Masterloot-Vergabe, Whisper,
Roll-Sync zwischen zwei Clients, Trade-Tracking — gehört als Testhinweis
in den CHANGELOG-Eintrag.

## Release

**Bei JEDER Aenderung die Version erhoehen** (sie steht im Titel des Hauptfensters
und in der Ladezeile; `/bl version` zeigt, wer in der Gruppe welche Version hat).

1. `## Version:` in `BananaLoot.toc` **und** `BananaLoot.VERSION` in
   `BananaLoot.lua` hochzählen (der Test bricht ab, wenn sie
   auseinanderlaufen).
2. Eintrag oben in `CHANGELOG.md`.
3. Auf `main` pushen.

Der Workflow `.github/workflows/release.yml` sieht eine Version ohne Tag,
legt `v<Version>` an und hängt `BananaLoot-<Version>.zip` an das Release.
Im ZIP liegt der Ordner `BananaLoot` mit allen Spieldateien, `Icons/`,
README, CHANGELOG, LICENSE, THIRD_PARTY_NOTICES und `ANLEITUNG.txt`.

Ein Push ohne neue Version erzeugt kein Release.
