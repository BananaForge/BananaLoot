# Alle Texte, die BananaLoot in den Chat postet

Stand: v3.49. Nur Texte, die **andere Spieler sehen** (Raid-/Gruppen-/Say-Chat, Whisper, Weltkanal).
Reine Anzeigen im eigenen Chatfenster (Hinweise, Fehler, `[BananaLoot] ...`-Meldungen an dich) sind nicht aufgeführt.
Kanal "Ansage" = RAID, sonst PARTY, sonst SAY (`BananaLoot:GetAnnounceChannel`).
Texte stehen in `BananaLoot.lua` (Tabelle LOCALE, Sprache de/en) – Schlüssel in Klammern.

## 1) Beim Öffnen der Beute (Loot-Vorschau) – abschaltbar
Option: *Loot-Vorschau im Raid-/Gruppenchat* (`OPT_LOOTPREVIEW_*`). Einmal pro neuem Loot-Fenster, eine Zeile pro Item, Kanal Ansage.

| Fall | Text |
|---|---|
| Hard Reserve | `[Item][ (xN)] [HR]` (`UI_TAG_HR`, `UI_QTY`) |
| Mit SR | `[Item][ (xN)] [SR]: Name(+Bonus), Name, ... (+N weitere)` (`UI_TAG_SR`, `UI_PLAYERS_MORE`) |
| Ohne SR | `[Item][ (xN)] [Offen]` (`UI_TAG_OPEN`) |

## 2) Roll-Start – immer
Beim Start eines Rolls, Kanal Ansage. `%s` = Item (bei Mehrfachdrop + " (N Kopien -- Top-Rolls gewinnen)"), Namen der SR-Spieler, Wurf-Hinweis.

| Fall | DE | EN |
|---|---|---|
| Roll mit SR (`ROLL_ANNOUNCE_SR`) | `[BananaLoot] SR-Roll für [Item] -- Name1 Name2 -- <Hinweis>` | `[BananaLoot] SR roll for ...` |
| Frei-Roll (`ROLL_ANNOUNCE_ARF`) | `[BananaLoot] Frei-Roll für [Item] -- SR ausgesetzt, offen für alle -- <Hinweis>` | `[BananaLoot] Open Roll for ...` |
| Offener Roll (`ROLL_ANNOUNCE_OPEN`) | `[BananaLoot] Roll für [Item] -- offen für alle -- <Hinweis>` | `[BananaLoot] Roll for ...` |

Wurf-Hinweis (`ROLL_HOWTO` + `ROLL_TIME_SUFFIX`): `/roll = Hauptspec, /roll 99 = Off-Spec, /roll 98 = Transmog -- Zeit: 30 Sek.`

## 3) Während des Rolls – abschaltbar
Option: *Chat-Countdown* (`OPT_COUNTDOWN_*`). Kanal Ansage, bei 10, 5, 3, 2, 1 Sekunden Restzeit:
- 10 s (`COUNTDOWN_10`): `[BananaLoot] Roll endet in 10 Sekunden -- bitte bald abschließen!`
- sonst (`COUNTDOWN_N`): `[BananaLoot] Noch 5 Sekunden!` / `Noch 1 Sekunde!`

## 4) Roll-Ergebnis – immer
| Event | Text |
|---|---|
| Gleichstand (`ROLL_TIE`) | `[BananaLoot] Gleichstand (<Kategorie>) bei <Wert>! Name1 Name2 -- bitte erneut rollen (gleiche Kategorie)!` |
| Round Robin, nur wenn Würfe wegen höherer RR nicht zählen (`RR_ROLL_INFO`) | `Round Robin: <Gewinner> (RR n) gewertet. Nicht gewertet wegen höherer RR: Name RRn, ...` |
| Ein Gewinner (`ROLL_WINNER_ANNOUNCE`) | `[BananaLoot] <Name> gewinnt [Item] (<Hauptspec/Off-Spec/Transmog>)!` |
| Mehrere Gewinner (`ROLL_WINNERS_ANNOUNCE`) | `[BananaLoot] [Item] -- <Kategorie>: Name (Wurf/Score), Name (..) teilen sich den Sieg!` |

## 5) Vergaben ohne Roll
| Event | Text |
|---|---|
| Raid-Roll (Liste/Button, `RAID_ROLL_ANNOUNCE`) | `[BananaLoot] [Item] -- Vergabe per random raid Roll an: <Name>` |
| Disenchant, wenn niemand rollt (`DE_ANNOUNCE`) | `[Item] geht an <Disenchanter> (Disenchant).` |
| Bankreserve (BR), manuelles Zuweisen, Gewinner-Button | **kein** Chat-Text (nur eigenes Chatfenster + Log) |

## 6) Raidlead-Ansagen – abschaltbar
Option: *Automatische Raidlead-Ansagen* (nur Raidleiter bzw. eingetragener Absender; Kanal RAID/PARTY). Die Texte sind frei editierbar (Raidlead-Fenster), Standardtexte stehen in `BananaLootBossData.lua`.
- **Raid starten**: Willkommensnachricht + Trash-Hinweis (je Raid, sonst "Allgemein")
- **Boss anvisieren** (einmal pro Raid): Nachricht 1 des Bosses (≈113 Standardtexte, z. B. "Lucifron: Tank ihn mit den 2 Flamewaker Protectors ..."), danach optional Nachricht 2 nach Verzögerung/Button
- **Raid beenden**: Abschlussnachricht

## 7) Raid-Code
Button "Code posten" (`CODE_POST_TEXT`), Kanal Raid, sonst Gruppe/Gilde:
`BananaLoot Raid-Code fuer <Raid>: <Code>  (SR einreichen: BananaLoot Raider, /blr sr)`

## 8) Whisper-Antworten an Spieler (auf `sr`/`unsr`/`srlist`/`hr`)
`WHISPER_*`: SR bestätigt ("%s wurde für dich reserviert" + SR+-Bonus/Ersetzt-Hinweis), Item nicht erkannt, Link fehlt, Limit erreicht, Hard Reserve / Bankreserve nicht reservierbar, SR-Liste gesperrt, Befehl unbekannt, eigene SR-Liste / "Ebenfalls auf SR", HR-Liste, Raidres-Import-Hinweise (`WHISPER_RAIDRES_*`).

## 9) Weltkanal – LFM
LFM-Assistent/-Fenster: der von dir erzeugte bzw. bearbeitete Text (englisch), im eingestellten Intervall, `[Item]` wird zum Link.

## Was BananaLoot Raider postet
Nur Whispers an den Lootmaster: `sr [Item]` / `unsr [Item]` (Fenster "SR einreichen" / "Whisper-SR"). Keine Raid-Chat-Texte.

## Auffälligkeiten (zum Entscheiden)
- Bankreserve/Manuell zuweisen/Gewinner-Button sagen bewusst nichts im Raid an (kein Chat-Spam).
