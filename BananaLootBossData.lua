-- BananaLootBossData.lua
-- Raid-/Bossdaten fuer die Raidlead-Ansagen UND die Auto-Masterloot-Erkennung
-- (eine gemeinsame Quelle, damit sich die Bossnamen nicht auseinanderentwickeln).
--
-- raid.zones : Instanznamen (GetRealZoneText, englischer Client) zur Raid-Erkennung.
-- boss.units : Namen, die beim Anvisieren als dieser Boss gelten (UnitName).
-- boss.zoneOnly: Einheit zaehlt nur als Boss, wenn die Zone zum Raid passt
--                (z.B. Anubisath Defender, kommt auch als Trash in AQ40 vor).
-- boss.m1/m2 : Standardtexte (deutsch, max. 255 Zeichen), im Raidlead-Fenster
--              editierbar. m1 = beim ersten Anvisieren, m2 = per Button/Verzoegerung.
-- unverified : Zonen-/Bossnamen dieses Raids sind nicht ingame geprueft.
-- raid.optional: Raid ist nur aktiv, wenn die Option dafuer gesetzt ist (z.B. UBRS).
-- raid.welcome/trash: optionale Standardtexte des Raids (Raidlead-Fenster ueberschreibt).

BananaLoot_RaidData = {
    {
        key = "MC", name = "Molten Core", short = "MC",
        zones = { "Molten Core" },
        bosses = {
            { key = "lucifron", label = "Lucifron", units = { "Lucifron" } },
            { key = "magmadar", label = "Magmadar", units = { "Magmadar" } },
            { key = "gehennas", label = "Gehennas", units = { "Gehennas" } },
            { key = "garr", label = "Garr", units = { "Garr" } },
            { key = "shazzrah", label = "Shazzrah", units = { "Shazzrah" } },
            { key = "geddon", label = "Baron Geddon", units = { "Baron Geddon" } },
            { key = "sulfuron", label = "Sulfuron Harbinger", units = { "Sulfuron Harbinger" } },
            { key = "golemagg", label = "Golemagg the Incinerator", units = { "Golemagg the Incinerator" } },
            { key = "majordomo", label = "Majordomo Executus", units = { "Majordomo Executus" } },
            { key = "ragnaros", label = "Ragnaros", units = { "Ragnaros" } },
            { key = "incindis", label = "Incindis (Custom)", units = { "Incindis" }, m1 = "Tank: Incindis kontrollieren. Heiler: Tank-Schaden beobachten. DDs: Feuerflächen verlassen und Aggro kontrollieren.", m2 = "Primär: alle Spieler müssen Feuermechaniken beachten. Heiler: Feuerschaden sofort ausgleichen. Cleanse/Decurse nur bei tatsächlich entfernbaren Debuffs." },
            { key = "golemtwins", label = "Smoldaris & Basalthar (Custom)", units = { "Smoldaris", "Basalthar" }, m1 = "Tank: Beide Ziele nach Raidplan positionieren. DDs: Killreihenfolge strikt einhalten. Heiler: beide Tankziele beobachten.", m2 = "Alle: Auf Flächenangriffe und Debuffs achten. Priester/Paladin/Schamane für Magie, Druide/Schamane für Gift, Druide/Magier für Flüche bereithalten." },
            { key = "thaurissan", label = "Sorcerer-Thane Thaurissan (Custom)", units = { "Sorcerer-Thane Thaurissan" }, m1 = "Tank: Sorcerer-Thane Thaurissan kontrollieren. DDs: Unterbrechungen nach Ansage. Heiler: Zauberschaden und Debuffs auf dem Tank beachten.", m2 = "Primär: Zauberwirker achten auf Casts, Heiler auf Magie-Debuffs. Decurse/Cleanse erst nach Identifikation des konkreten Effekts." },
        },
    },
    {
        key = "ONY", name = "Onyxia's Lair", short = "Onyxia",
        zones = { "Onyxia's Lair" },
        bosses = {
            { key = "onyxia", label = "Onyxia", units = { "Onyxia" } },
            { key = "axelus", label = "Broodcommander Axelus (Custom)", units = { "Broodcommander Axelus" }, m1 = "Tank: Axelus kontrollieren und vom Raid wegdrehen. DDs: Adds nach Ansage fokussieren. Heiler: Tank und Spieler mit Feuerschaden beobachten.", m2 = "Primär: alle achten auf Drachenmechaniken und Positionierung. Heiler: Feuer- und Gruppenschaden. Dispels nur nach tatsächlichem Debufftyp." },
        },
    },
    {
        key = "BWL", name = "Blackwing Lair", short = "BWL",
        zones = { "Blackwing Lair" },
        bosses = {
            { key = "razorgore", label = "Razorgore the Untamed", units = { "Razorgore the Untamed" } },
            { key = "vaelastrasz", label = "Vaelastrasz the Corrupt", units = { "Vaelastrasz the Corrupt" } },
            { key = "broodlord", label = "Broodlord Lashlayer", units = { "Broodlord Lashlayer" } },
            { key = "firemaw", label = "Firemaw", units = { "Firemaw" } },
            { key = "ebonroc", label = "Ebonroc", units = { "Ebonroc" } },
            { key = "flamegor", label = "Flamegor", units = { "Flamegor" } },
            { key = "chromaggus", label = "Chromaggus", units = { "Chromaggus" } },
            { key = "nefarian", label = "Nefarian", units = { "Nefarian" } },
            { key = "ezzel", label = "Ezzel Darkbrewer (Custom)", units = { "Ezzel Darkbrewer" }, m1 = "Tank: Ezzel und Ton'Raka kontrollieren. DDs: Bei Charge-Ziel sofort reagieren und Acid Bomb ausweichen. Heiler: betroffene Spieler schnell stabilisieren.", m2 = "Primär: markierte/angegriffene Spieler achten auf Charge und Säureflächen. Heiler: Debuffs prüfen; Gift reinigen, falls entfernbar, Magie entsprechend dispellen." },
        },
    },
    {
        key = "ZG", name = "Zul'Gurub", short = "ZG",
        zones = { "Zul'Gurub" },
        bosses = {
            { key = "jeklik", label = "High Priestess Jeklik", units = { "High Priestess Jeklik" } },
            { key = "venoxis", label = "High Priest Venoxis", units = { "High Priest Venoxis" } },
            { key = "marli", label = "High Priestess Mar'li", units = { "High Priestess Mar'li" } },
            { key = "mandokir", label = "Bloodlord Mandokir", units = { "Bloodlord Mandokir" } },
            { key = "edge", label = "Edge of Madness", units = { "Gri'lek", "Hazza'rah", "Renataki", "Wushoolay" } },
            { key = "gahzranka", label = "Gahz'ranka", units = { "Gahz'ranka" } },
            { key = "thekal", label = "High Priest Thekal", units = { "High Priest Thekal" } },
            { key = "arlokk", label = "High Priestess Arlokk", units = { "High Priestess Arlokk" } },
            { key = "jindo", label = "Jin'do the Hexxer", units = { "Jin'do the Hexxer" } },
            { key = "hakkar", label = "Hakkar the Soulflayer", units = { "Hakkar the Soulflayer" } },
        },
    },
    {
        key = "AQ20", name = "Ruins of Ahn'Qiraj", short = "AQ20",
        zones = { "Ruins of Ahn'Qiraj" },
        bosses = {
            { key = "kurinnaxx", label = "Kurinnaxx", units = { "Kurinnaxx" }, m1 = "Tank: Boss frontal wegdrehen. Heiler: Sandfallen und Heilungsreduktion beachten; Tank bei Debuff besonders eng heilen.", m2 = "Alle: Sandfallen sofort verlassen. DDs: Aggro kontrollieren und Flanken nutzen; bei Heilungsreduktion auf Tank nicht unnötig Schaden provozieren." },
            { key = "rajaxx", label = "General Rajaxx", units = { "General Rajaxx" }, m1 = "Tank: Jede Welle sauber einsammeln. DDs: Ziele nach Ansage fokussieren und nicht vorzeitig pullen. Heiler: Tank- und Gruppenschaden über alle Wellen einteilen.", m2 = "Raid: Rajaxx erst nach den Wellen bekämpfen. Bei Gruppen-Schadensrufen zusammenbleiben und nicht unkoordiniert durch die Gegner laufen." },
            { key = "moam", label = "Moam", units = { "Moam" }, m1 = "Tank: Boss kontrollieren. DDs: Adds nach Ansage töten; Mana-Klassen beachten Moams Manabrand und behalten Ressourcen im Blick.", m2 = "Heiler: Mana rechtzeitig einteilen. Bei Manaleere-Phase Adds kontrollieren und töten; DDs wechseln zügig auf Elementare und halten sie vom Raid fern." },
            { key = "buru", label = "Buru der Verschlinger", units = { "Buru the Gorger" }, m1 = "Alle: Buru wird über Eiermechanik bekämpft. Markierte Spieler führen ihn kontrolliert zu einem Ei; nicht unkoordiniert in die Gruppe laufen.", m2 = "Tank: Adds/Eierphase koordinieren. Heiler: markierte Spieler und Tank schützen. DDs: Eier nach Ansage zerstören und in der Endphase auf Buru fokussieren." },
            { key = "ayamiss", label = "Ayamiss der Jäger", units = { "Ayamiss the Hunter" }, m1 = "Tank: Ayamiss am Boden kontrollieren, wenn möglich. DDs: Larven schnell töten, besonders wenn Spieler geopfert werden. Heiler: markierte Spieler schützen.", m2 = "Alle: Bei Opfermechanik sofort Larve töten, bevor der Spieler stirbt. Fernkämpfer bleiben verteilt; Nahkämpfer greifen an, sobald Boss erreichbar ist." },
            { key = "ossirian", label = "Ossirian der Narbenlose", units = { "Ossirian the Unscarred" }, m1 = "Tank: Ossirian zu Kristallen führen, damit sein Stärkungsbuff gebrochen wird. DDs: Kristalle aktivieren/Position ansagen und Boss nur mit geschwächtem Buff fokussieren.", m2 = "Alle: Wirbel-/Windflächen meiden und nach Kristallansage schnell umpositionieren. Heiler: Tank-Schaden bei fehlgeschlagenem Debuff besonders beachten." },
            { key = "tuubid", label = "Captain Tuubid (Custom)", units = { "Captain Tuubid" }, m1 = "Markiertes Ziel für Attack Command beachten. Betroffener Spieler reagiert sofort nach Raidansage; Tank hält den Boss stabil, DDs bleiben beim Fokusziel." },
            { key = "drenn", label = "Captain Drenn (Custom)", units = { "Captain Drenn" }, m1 = "Bei Lightning Cloud sofort aus dem Wirkungsbereich laufen. Tank hält Drenn kontrolliert; Heiler achten auf Natur-Schaden, DDs vermeiden unnötige Treffer." },
            { key = "defenders", label = "Anubisath Defenders (Custom)", units = { "Anubisath Defender" }, zoneOnly = true, m1 = "Tank: Defender kontrollieren. Alle: Vor Explosion Abstand nehmen und den markierten Wirkungsbereich verlassen. DDs folgen der jeweiligen Defender-Mechanik." },
        },
    },
    {
        key = "AQ40", name = "Temple of Ahn'Qiraj", short = "AQ40",
        zones = { "Temple of Ahn'Qiraj" },
        bosses = {
            { key = "skeram", label = "Prophet Skeram", units = { "The Prophet Skeram" }, m1 = "Tank: Skeram und Klone sofort zuweisen. DDs: Echtes Ziel nach Markierung fokussieren; Klone kontrollieren und nicht ungeplant verteilen.", m2 = "Alle: Bei Gedankenkontrolle Abstand halten und kontrollierte Spieler nicht angreifen. Heiler: Tanks aller Skeram-Ziele versorgen; Klone schnell erkennen." },
            { key = "sartura", label = "Schlachtwache Sartura", units = { "Battleguard Sartura" }, m1 = "Tank: Sartura und Wächter kontrollieren. DDs: Nicht unkontrolliert in Wirbelangriffe laufen; bei Wirbeln Abstand halten und Aggro beachten.", m2 = "Heiler: Tank-Spitzen und zufällige Ziele im Blick behalten. Tanks sammeln die Wächter wieder ein, sobald sie aus dem Wirbel kommen; DDs folgen Killreihenfolge." },
            { key = "bugtrio", label = "Bug-Trio (Kri, Vem, Yauj)", units = { "Lord Kri", "Vem", "Princess Yauj" }, m1 = "Tank: Alle drei Käfer kontrolliert positionieren. DDs: Killreihenfolge strikt einhalten; beim Tod eines Käfers lösen die anderen zusätzliche Effekte aus.", m2 = "Heiler: Gift, Furcht und Gruppenschaden beachten. Alle: Kri-Gift schnell entfernen, Yauj-Heilung unterbrechen und Adds nach Ansage kontrollieren." },
            { key = "fankriss", label = "Fankriss der Unnachgiebige", units = { "Fankriss the Unyielding" }, m1 = "Tank: Fankriss frontal wegdrehen. DDs: Wurm-Adds sofort nach Ansage töten, besonders wenn sie Heiler bedrohen; Aggro nicht überholen.", m2 = "Heiler: Tank-Schaden und zufällige Ziele beachten. Alle: Bei Wurmbefall schnell reagieren und Adds kontrollieren, bevor sie sich im Raid verteilen." },
            { key = "viscidus", label = "Viscidus", units = { "Viscidus" }, m1 = "Alle: Viscidus braucht Frosttreffer zum Einfrieren und viele schnelle Treffer zum Zersplittern. Frostzauber und schnelle Angriffe nach Raidplan einsetzen.", m2 = "DDs: Nach Zersplittern die Globs schnell töten. Heiler: Gift entfernen und Raid stabilisieren. Tank: Boss kontrollieren; bei Giftwolken Abstand halten." },
            { key = "huhuran", label = "Prinzessin Huhuran", units = { "Princess Huhuran" }, m1 = "Tank: Huhuran frontal wegdrehen. Heiler: Naturwiderstand und hohe Natur-/Gift-Schäden einplanen. DDs: Gift-Debuffs beachten und nicht unnötig Aggro ziehen.", m2 = "Bei Frenzy-Endphase volle DPS nach Ansage. Heiler nutzen defensive CDs; Jäger/Spieler mit Naturresistenz nach Raidplan einsetzen. Gift sofort entfernen, wenn möglich." },
            { key = "twins", label = "Zwillingsimperatoren", units = { "Emperor Vek'lor", "Emperor Vek'nilash", "Vek'lor", "Vek'nilash" }, m1 = "Tank: Vek'lor nur mit Zauber-/Fernkampf-Tank halten, Vek'nilash mit Nahkampf-Tank. Imperatoren auseinander halten; sie tauschen Positionen/teleportieren.", m2 = "DDs: Richtigen Imperator angreifen - Nahkampf auf Vek'nilash, Fernkampf auf Vek'lor. Heiler: beide Tankgruppen heilen; Käfer-Adds rasch kontrollieren." },
            { key = "ouro", label = "Ouro", units = { "Ouro" }, m1 = "Tank: Ouro vom Raid wegdrehen. Alle: Sandsturm und Untertauchen beachten; wenn Ouro verschwindet, Adds sammeln und nach Ansage töten.", m2 = "DDs: Bei Wiederauftauchen Aggro kontrollieren und schnell fokussieren. Heiler: Tank-Spitzen abfangen. Alle: Erdbeben/Flächenangriffe verlassen und Abstand halten." },
            { key = "cthun", label = "C'Thun", units = { "C'Thun" }, m1 = "Alle: Vor dem Auge weit verteilen, Strahlenkette verhindern. Tank: Tentakel sofort einsammeln. DDs: Kleine Tentakel und große Tentakel nach Ansage priorisieren.", m2 = "Bauchphase: Nur nach Ansage hinein; Tentakel töten und rechtzeitig raus. Heiler: Strahlenopfer und Tank-Schaden im Blick behalten. Nie in einer Linie stehen." },
        },
    },
    {
        key = "NAXX", name = "Naxxramas", short = "Naxx",
        zones = { "Naxxramas" },
        bosses = {
            { key = "anub", label = "Anub'Rekhan", units = { "Anub'Rekhan" } },
            { key = "faerlina", label = "Grand Widow Faerlina", units = { "Grand Widow Faerlina" } },
            { key = "maexxna", label = "Maexxna", units = { "Maexxna" } },
            { key = "noth", label = "Noth the Plaguebringer", units = { "Noth the Plaguebringer" } },
            { key = "heigan", label = "Heigan the Unclean", units = { "Heigan the Unclean" } },
            { key = "loatheb", label = "Loatheb", units = { "Loatheb" } },
            { key = "razuvious", label = "Instructor Razuvious", units = { "Instructor Razuvious" } },
            { key = "gothik", label = "Gothik the Harvester", units = { "Gothik the Harvester" } },
            { key = "horsemen", label = "Die vier Reiter", units = { "Thane Korth'azz", "Lady Blaumeux", "Sir Zeliek", "Baron Rivendare" } },
            { key = "patchwerk", label = "Patchwerk", units = { "Patchwerk" } },
            { key = "grobbulus", label = "Grobbulus", units = { "Grobbulus" } },
            { key = "gluth", label = "Gluth", units = { "Gluth" } },
            { key = "thaddius", label = "Thaddius", units = { "Thaddius" } },
            { key = "sapphiron", label = "Sapphiron", units = { "Sapphiron" } },
            { key = "kelthuzad", label = "Kel'Thuzad", units = { "Kel'Thuzad" } },
        },
    },
    {
        key = "TIMB", name = "Timbermaw Hold", short = "Timbermaw",
        zones = { "Timbermaw Hold" },
        unverified = true,
        bosses = {
            { key = "karrsh", label = "Karrsh the Sentinel", units = { "Karrsh the Sentinel" }, m1 = "Tank: Karrsh kontrollieren und vom Raid wegdrehen. Heiler: Tank-Schaden beobachten. DDs: Aggro kontrollieren und Killziel halten.", m2 = "Alle: Debuffs melden. Priester/Magier: Magie entfernen, Druiden/Schamanen: Gift oder Flüche nur bei entsprechendem Debuff reinigen. Bossmechanik vor Ort prüfen." },
            { key = "kodiakrotgrowl", label = "Kodiak & Rotgrowl", units = { "Kodiak", "Rotgrowl" }, m1 = "Tank: Kodiak und Rotgrowl getrennt halten. DDs: Fokusziel nach Ansage; keine unkontrollierten Zielwechsel. Heiler: beide Tankziele im Blick behalten.", m2 = "Alle: Bei Gift/Fluch/Magie-Debuffs sofort melden. Druide/Schamane: Gift reinigen; Magier/Priester: Magie bannen; Flüche nach Klasse entfernen. Fähigkeiten vor Ort verifizieren." },
            { key = "ormanos", label = "Ormanos the Cracked", units = { "Ormanos the Cracked" }, m1 = "Tank: Ormanos kontrollieren. DDs: Hinter/seitlich stehen, sofern kein anderer Positionsruf erfolgt. Heiler: Tank und gefährdete Spieler im Blick behalten.", m2 = "Bei Debuffs Typ prüfen: Gift - Druide/Schamane; Fluch - Druide/Magier; Magie - Priester/Paladin/Schamane. Keine Dispels verschwenden, wenn der Debuff nicht entfernbar ist." },
            { key = "kronn", label = "Archdruid Kronn", units = { "Archdruid Kronn" }, m1 = "Tank: Kronn stabil positionieren. Heiler: Tankheilung priorisieren. DDs: Adds und besondere Ziele nur nach Raidansage wechseln.", m2 = "Druiden/Schamanen: Gift reinigen, falls vorhanden. Druiden/Magier: Flüche entfernen. Priester/Paladine/Schamanen: Magie bannen. Konkrete Debuffs vor dem finalen Einsatz verifizieren." },
            { key = "loktanag", label = "Loktanag the Vile", units = { "Loktanag the Vile" }, m1 = "Tank: Loktanag kontrollieren und Adds nach Plan übernehmen. DDs: Fokusziel halten. Heiler: Tankwechsel und plötzlichen Gruppenschaden beachten.", m2 = "Bei Fluch: Druide/Magier decursen. Bei Gift: Druide/Schamane reinigen. Bei Magie: Priester/Paladin/Schamane dispellen. Nicht entfernbaren Debuff sofort melden." },
            { key = "trioch", label = "Trioch the Devourer", units = { "Trioch the Devourer" }, m1 = "Tank: Trioch kontrollieren. DDs: Bei Adds sofort nach Ansage wechseln. Heiler: Tank und markierte Spieler beobachten; nicht unnötig zusammenstehen.", m2 = "Alle: Debuffs sofort melden. Druide/Schamane reinigen Gift, Druide/Magier entfernen Flüche, Priester/Paladin/Schamane bannen Magie - nur wenn der Effekt dispellbar ist." },
            { key = "selenaxx", label = "Selenaxx Foulheart", units = { "Selenaxx Foulheart" }, m1 = "Tank: Selenaxx kontrollieren und vom Raid wegdrehen. DDs: Unterbrechungen nach Ansage nutzen. Heiler: Tank und Spieler mit Debuffs priorisieren.", m2 = "Foulheart im Namen allein beweist keinen Fluch! Debufftyp prüfen: Druide/Magier decursen Flüche; Gift durch Druide/Schamane, Magie durch passende Dispeller entfernen." },
            { key = "partath", label = "Chieftain Partath", units = { "Chieftain Partath" }, m1 = "Tank: Partath kontrollieren. DDs: Aggro halten und auf Ansage Adds wechseln. Heiler: Tank-Schaden und unerwartete Angriffe auf Fernkämpfer beobachten.", m2 = "Bei Fluch Druide/Magier einsetzen; bei Gift Druide/Schamane; bei Magie Priester/Paladin/Schamane. Raid meldet Debuffs und wartet bei unklarer Mechanik auf Ansage." },
            { key = "ursol", label = "Ursol", units = { "Ursol" }, m1 = "Tank: Ursol stabil ausrichten. Heiler: Tank-Spitzen und Gruppenschaden beachten. DDs: Aggro kontrollieren, Adds nach Ansage priorisieren.", m2 = "Alle: Auf Debuffs und Flächenangriffe achten. Dispeller nach Debufftyp einsetzen: Gift - Druide/Schamane; Fluch - Druide/Magier; Magie - Priester/Paladin/Schamane." },
        },
    },
    {
        key = "LKH", name = "Lower Karazhan Halls", short = "Kara 10",
        zones = { "Lower Karazhan Halls" },
        unverified = true,
        bosses = {
            { key = "araxxna", label = "Brood Queen Araxxna", units = { "Brood Queen Araxxna" }, m1 = "Tank: Araxxna kontrollieren. DDs: Spinnen-Adds priorisieren. Heiler: Gift auf Tanks prüfen; Druide/Schamane zum Reinigen bereithalten.", m2 = "Achtung: Giftstapel auf dem Tank! Druiden reinigen Gift bevorzugt mit Abolish Poison. Adds haben Vorrang vor Boss-DPS." },
            { key = "grizikil", label = "Grizikil", units = { "Grizikil" }, m1 = "Tank: Grizikil kontrollieren. Alle: Flamewave und Rain of Fire verlassen. Heiler: Feueropfer stabilisieren. DDs: Imp-Casts unterbrechen, wo möglich.", m2 = "Heiler: Tank und Feueropfer stabilisieren. DDs: Zauber der Imps unterbrechen, wo möglich. Bei Feuerflächen sofort bewegen." },
            { key = "howlfang", label = "Clawlord Howlfang", units = { "Clawlord Howlfang" }, m1 = "Tank: Tankwechsel bei hohen Debuffstapeln nach Raidplan. Heiler: aktiven Tank priorisieren. DDs: Aggro kontrollieren. Sichtlinienmechanik vorher verifizieren.", m2 = "Heiler: Tankwechsel vorbereiten und Curse schnell entfernen. DDs: Aggro kontrollieren und Howlfang nicht unkontrolliert drehen." },
            { key = "blackwald", label = "Lord Blackwald II", units = { "Lord Blackwald II" }, m1 = "Tank: Boss und Adds kontrollieren. DDs: Adds nach Ansage töten oder CC nutzen. Heiler: Tank und Add-Tanks stabil halten.", m2 = "Achtung: Adds können bei hohem DPS nur wenige Wellen erzeugen. Trotzdem Offtank oder CC bereithalten und Boss sauber positionieren." },
            { key = "moroes", label = "Moroes", units = { "Moroes" }, m1 = "Tanks: Spot/Wechsel nach Plan. DDs: Aggro kontrollieren. Heiler: Stille beachten; Flüche auf Tanks durch Druide/Magier entfernen, falls vorhanden.", m2 = "Heiler: Stille und Tank-Stuns beachten. Tanks bei Magie-Debuffs reinigen, damit sie wieder spotten können. Adds nach Raidplan kontrollieren." },
            { key = "rolfen", label = "Master Blacksmith Rolfen (optional)", units = { "Master Blacksmith Rolfen", "Rolfen" }, m1 = "Optionalboss Rolfen: Tank nimmt ihn auf, DDs fokussieren nach Ansage. Heiler auf Tank-Schaden achten. Nur bekämpfen, wenn die Gruppe den Zusatzloot möchte." },
        },
    },
    {
        key = "UKH", name = "Tower of Karazhan", short = "Tower of Kara",
        zones = { "Tower of Karazhan", "Upper Karazhan Halls" },
        unverified = true,
        bosses = {
            { key = "gnarlmoon", label = "Keeper Gnarlmoon", units = { "Keeper Gnarlmoon", "Gnarlmoon" }, m1 = "Tank: Gnarlmoon kontrollieren. DDs: Mechaniken und Adds nach Ansage beachten. Heiler: Tank und Gruppenschaden beobachten." },
            { key = "incantigos", label = "Ley-Watcher Incantigos", units = { "Ley-Watcher Incantigos", "Incantigos", "Incantagos" }, m1 = "Tank: Boss stabil positionieren. Zauberwirker: Casts nach Ansage unterbrechen. Heiler: Magie-Debuffs prüfen und dispellen, falls möglich." },
            { key = "anomalus", label = "Anomalus", units = { "Anomalus" }, m1 = "Tank: Anomalus kontrollieren. DDs: gefährliche Zaubereffekte und Adds nach Ansage priorisieren. Heiler: arkanen Schaden beachten." },
            { key = "echo", label = "Echo of Medivh", units = { "Echo of Medivh", "Echo" }, m1 = "Tank: Boss kontrollieren. DDs: Zaubermechaniken beachten und Casts nach Ansage unterbrechen. Heiler: Gruppenschaden und Debuffs beobachten." },
            { key = "chess", label = "Chess Event", units = {  }, m1 = "Alle: Schachfiguren nach Raidansage steuern. Positionierung und sichere Züge beachten; nicht unkoordiniert Figuren bewegen." },
            { key = "sanv", label = "Sanv Tas'dal", units = { "Sanv Tas'dal", "Sanv Tasdal" }, m1 = "Tank: Boss kontrollieren. DDs: Fokusziel halten. Heiler: Tank und markierte Spieler beobachten; Debuffs nach Typ dispellen." },
            { key = "rupturan", label = "Rupturan the Broken", units = { "Rupturan the Broken", "Rupturan" }, m1 = "Tank: Rupturan stabil positionieren. DDs: Adds und Flächenmechaniken nach Ansage beachten. Heiler: Tank-Spitzen abfangen." },
            { key = "kruul", label = "Kruul", units = { "Kruul" }, m1 = "Tank: Kruul kontrollieren. DDs: Aggro beachten und Adds nach Ansage priorisieren. Heiler: Tank und Gruppenschaden im Blick behalten." },
            { key = "mephistroth", label = "Mephistroth", units = { "Mephistroth" }, m1 = "Tank: Mephistroth kontrollieren und frontal wegdrehen. DDs: Bossmechaniken beachten. Heiler: gefährdete Spieler und Debuffs beobachten." },
        },
    },
    {
        key = "ES", name = "Emerald Sanctum", short = "Emerald S.",
        zones = { "Emerald Sanctum" },
        unverified = true,
        bosses = {
            { key = "erennius", label = "Erennius", units = { "Erennius" }, m1 = "Tank: Erennius kontrollieren. DDs: Boss fokussieren und Casts nach Ansage unterbrechen. Heiler: Gruppenschaden und Debuffs beobachten.", m2 = "Primär: Heiler und betroffene Spieler achten auf Affliktionen. Magie bannen, Gift reinigen oder Flüche entfernen nur, wenn der konkrete Debuff dies erlaubt." },
            { key = "solnius", label = "Solnius the Awakener", units = { "Solnius the Awakener", "Solnius" }, m1 = "Tank: Solnius kontrollieren und frontal vom Raid wegdrehen. DDs: Adds nach Ansage priorisieren. Heiler: Tank und Gruppe bei Affliktionen stabil halten.", m2 = "Primär: alle achten auf Debuffs und Drachenmechaniken. Bei Dreamstate Magie-Dispels prüfen; Heiler müssen den Raid besonders bei Add-Phasen beobachten." },
        },
    },
    {
        key = "WB", name = "World Bosses", short = "Weltbosse",
        zones = {  },
        unverified = true,
        bosses = {
            { key = "azuregos", label = "Azuregos", units = { "Azuregos" } },
            { key = "kazzak", label = "Lord Kazzak", units = { "Lord Kazzak" } },
            { key = "emeriss", label = "Emeriss", units = { "Emeriss" } },
            { key = "lethon", label = "Lethon", units = { "Lethon" } },
            { key = "taerar", label = "Taerar", units = { "Taerar" } },
            { key = "ysondre", label = "Ysondre", units = { "Ysondre" } },
            { key = "clackora", label = "Cla'ckora (Custom)", units = { "Cla'ckora" }, m1 = "Tank: Cla'ckora kontrollieren. Heiler: Tank-Schaden beobachten. DDs: Aggro kontrollieren und Mechaniken nach Ansage beachten." },
            { key = "concavius", label = "Concavius (Custom)", units = { "Concavius" }, m1 = "Tank: Concavius kontrollieren. Alle: Void- und Flächenmechaniken beachten. Heiler: Gruppenschaden und Debuffs prüfen." },
            { key = "darkreaver", label = "Dark Reaver of Karazhan (Custom)", units = { "Dark Reaver of Karazhan" }, m1 = "Tank: Dark Reaver kontrollieren. DDs: Fokusziel halten. Heiler: Tank-Spitzen und Debuffs beobachten; Dispels nach Typ einsetzen." },
            { key = "ostarius", label = "Ostarius of Uldum (Custom)", units = { "Ostarius of Uldum", "Ostarius" }, m1 = "Tank: Ostarius kontrollieren. DDs: Aggro kontrollieren und Flächenmechaniken beachten. Heiler: Tank und Raid stabil halten." },
            { key = "overseer", label = "Nerubian Overseer (Custom)", units = { "Nerubian Overseer" }, m1 = "Tank: Nerubian Overseer kontrollieren. DDs: Adds nach Ansage priorisieren. Heiler: Tank und Add-Tanks beobachten." },
            { key = "lycan", label = "Father Lycan (Custom)", units = { "Father Lycan" }, m1 = "Tank: Father Lycan kontrollieren. DDs: Bossmechaniken und Adds beachten. Heiler: Tank-Schaden und Debuffs beobachten." },
        },
    },
    {
        -- Optionaler Test-Raid (Dungeon fuer 10 Spieler). Nur aktiv, wenn die Option
        -- "UBRS als Test-Raid aktivieren" gesetzt ist (siehe optional = true).
        key = "UBRS", name = "Upper Blackrock Spire", short = "UBRS", optional = true,
        zones = { "Upper Blackrock Spire" },
        trash = "Trash UBRS: Blackhand Dreadweaver wirken Curse of Thorns und Veil of Shadow (senkt Heilung und Zauberschaden) - beides sofort decursen! Fire Tongue/Flamescale: Feuerzauber unterbrechen, hier ist kein Decurse nötig.",
        bosses = {
            { key = "emberseer", label = "Pyroguard Emberseer", units = { "Pyroguard Emberseer" }, zoneOnly = true, m1 = "Emberseer: Tank zieht ihn von den Rangeds weg! Melees aufpassen wegen Fire Nova. Rangeds Abstand halten. Keine besonderen Flüche, Gifte oder Krankheiten zu cleansen." },
            { key = "solakar", label = "Solakar Flamewreath (optional)", units = { "Solakar Flamewreath" }, zoneOnly = true, m1 = "Solakar: Adds zuerst! Tank sammelt sie ein, DDs killen Hatchers und Whelps. Solakar an der Wand tanken. Rangeds Abstand wegen War Stomp (AoE-Stun). Keine speziellen Debuffs zu cleansen." },
            { key = "goraluk", label = "Goraluk Anvilcrack", units = { "Goraluk Anvilcrack" }, zoneOnly = true, m1 = "Goraluk: Tank mit dem Rücken zur Wand, Raid hinter dem Boss. Achtung Head Crack, der Tank kann gestunnt werden. Heiler auf Tank achten. Keine besonderen Debuffs zu cleansen." },
            { key = "jed", label = "Jed Runewatcher (Rare)", units = { "Jed Runewatcher" }, zoneOnly = true, m1 = "Jed: Tank fängt Charge ab und hält ihn mit dem Rücken zur Wand. Rangeds Abstand halten. Achtung Shield Bash, Tank kann gestunnt werden. Keine speziellen Debuffs zu cleansen." },
            { key = "rend", label = "Rend Blackhand & Gyth", units = { "Warchief Rend Blackhand", "Rend Blackhand", "Gyth" }, zoneOnly = true, m1 = "Rend-Event: Adds kontrollieren und Whelps schnell killen. Gyth zuerst, danach Rend. Tanks sammeln Adds ein. Rend kann Fear wirken – Fear-Schutz nutzen. Keine speziellen Debuffs zu cleansen." },
            { key = "beast", label = "The Beast", units = { "The Beast" }, zoneOnly = true, m1 = "The Beast: Tank mit Rücken zur Wand, Boss vom Raid weg. Rangeds auf Abstand wegen Fear und Flamebreak. Tank muss nach Charge sofort wieder Aggro haben. Immolate ist ein Feuer-Debuff – keine normale Curse/Poison-Cleanse." },
            { key = "drakkisath", label = "General Drakkisath", units = { "General Drakkisath" }, zoneOnly = true, m1 = "Drakkisath: Beide Guards zuerst! Tanks je einen, dann Drakkisath. Boss vom Raid weg wegen Flame Breath. Conflagration: Betroffene verteilen sich, nicht zusammenstehen! Keine Flüche/Gifte; Conflagration nicht blind dispellen." },
        },
    },
}
