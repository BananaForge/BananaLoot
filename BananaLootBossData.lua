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
            { key = "lucifron", label = "Lucifron", units = { "Lucifron" }, m1 = "Lucifron: Tank ihn mit den 2 Flamewaker Protectors, Adds nacheinander töten. Lucifron's Curse und Impending Doom sofort decursen (Druide/Magier)! Heilung auf die Tanks fokussieren." },
            { key = "magmadar", label = "Magmadar", units = { "Magmadar" }, m1 = "Magmadar: Tank weg vom Raid, Rücken zur Wand. Panic (Fear): Fear Ward/Tremor Totem bereithalten. Hunter: Tranquilizing Shot gegen Frenzy. Alle raus aus Lava Bomb. Keine Flüche zu cleansen." },
            { key = "gehennas", label = "Gehennas", units = { "Gehennas" }, m1 = "Gehennas: Tank ihn mit den 2 Flamewakers, Adds zuerst. Gehennas' Curse (-75% Heilung) sofort decursen! Rain of Fire sofort verlassen. Heiler: auf Shadow Bolt auf Zufallsziele achten." },
            { key = "garr", label = "Garr", units = { "Garr" }, m1 = "Garr: Tanks sammeln die 8 Firesworn ein, Garr an einer Stelle halten. Adds nicht vor Garr töten, sie explodieren beim Tod. Garr zuerst nach unten. Magma Shackles dispellen. Keine Flüche." },
            { key = "shazzrah", label = "Shazzrah", units = { "Shazzrah" }, m1 = "Shazzrah: Blink wirft Aggro, Tank holt ihn sofort zurück. Alle raus aus Arcane Explosion. Deaden Magic und Magic Grounding purgen/dispellen. Shazzrah's Curse (Magieschaden) decursen! Counterspell beachten." },
            { key = "geddon", label = "Baron Geddon", units = { "Baron Geddon" }, m1 = "Geddon: Wer Living Bomb hat, sofort weit weg vom Raid! Bei Inferno (AoE) Melees raus. Ignite Mana dispellen. Tank bei Armageddon nicht bewegen. Keine Flüche zu cleansen." },
            { key = "sulfuron", label = "Sulfuron Harbinger", units = { "Sulfuron Harbinger" }, m1 = "Sulfuron: 4 Flamewaker Priests zuerst, feste Killreihenfolge. Dark Mending unterbrechen/stunnen! Inspire (Magie-Buff) purgen. Tank bei Hand of Ragnaros (Knockback) Rücken zur Wand. Keine Flüche." },
            { key = "golemagg", label = "Golemagg the Incinerator", units = { "Golemagg the Incinerator" }, m1 = "Golemagg: Tank weg vom Raid, bei Magma Splash Tanks bei hohen Stacks tauschen. Core Rager separat tanken, nicht zuerst töten. Ab 10% Earthquake: Melees aus dem Nahkampf, Ranged nuken. Keine Flüche." },
            { key = "majordomo", label = "Majordomo Executus", units = { "Majordomo Executus" }, m1 = "Majordomo: Elites und Healer einzeln pullen/CC, nacheinander töten. Magic Reflection/Damage Shield: Angriff pausieren bis das Shield weg ist. Keine speziellen Flüche, Magie-Debuffs nach Bedarf dispellen." },
            { key = "ragnaros", label = "Ragnaros", units = { "Ragnaros" }, m1 = "Ragnaros: Tank weg von den Melees, Rest außerhalb der Wrath-Reichweite. Bei Submerge: Sons of Flame töten, Tanks sammeln sie ein. Feuerresistenz nutzen. Heiler: Tank und Raidschaden. Keine Flüche." },
            { key = "incindis", label = "Incindis (Custom)", units = { "Incindis" }, m1 = "Tank: Incindis kontrollieren. Heiler: Tank-Schaden beobachten. DDs: Feuerflächen verlassen und Aggro kontrollieren.", m2 = "Primär: alle Spieler müssen Feuermechaniken beachten. Heiler: Feuerschaden sofort ausgleichen. Cleanse/Decurse nur bei tatsächlich entfernbaren Debuffs." },
            { key = "golemtwins", label = "Smoldaris & Basalthar (Custom)", units = { "Smoldaris", "Basalthar" }, m1 = "Tank: Beide Ziele nach Raidplan positionieren. DDs: Killreihenfolge strikt einhalten. Heiler: beide Tankziele beobachten.", m2 = "Alle: Auf Flächenangriffe und Debuffs achten. Priester/Paladin/Schamane für Magie, Druide/Schamane für Gift, Druide/Magier für Flüche bereithalten." },
            { key = "thaurissan", label = "Sorcerer-Thane Thaurissan (Custom)", units = { "Sorcerer-Thane Thaurissan" }, m1 = "Tank: Sorcerer-Thane Thaurissan kontrollieren. DDs: Unterbrechungen nach Ansage. Heiler: Zauberschaden und Debuffs auf dem Tank beachten.", m2 = "Primär: Zauberwirker achten auf Casts, Heiler auf Magie-Debuffs. Decurse/Cleanse erst nach Identifikation des konkreten Effekts." },
        },
    },
    {
        key = "ONY", name = "Onyxia's Lair", short = "Onyxia",
        zones = { "Onyxia's Lair" },
        bosses = {
            { key = "onyxia", label = "Onyxia", units = { "Onyxia" }, m1 = "Onyxia: Phase 1 Tank mit Rücken zur Wand, Raid hinter ihr, Flame Breath meiden. Phase 2: Whelps töten, Fireball ausweichen. Phase 3: Bellowing Roar (Fear Ward/Tremor Totem), Deep Breath meiden. Feuerresistenz hilft." },
            { key = "axelus", label = "Broodcommander Axelus (Custom)", units = { "Broodcommander Axelus" }, m1 = "Tank: Axelus kontrollieren und vom Raid wegdrehen. DDs: Adds nach Ansage fokussieren. Heiler: Tank und Spieler mit Feuerschaden beobachten.", m2 = "Primär: alle achten auf Drachenmechaniken und Positionierung. Heiler: Feuer- und Gruppenschaden. Dispels nur nach tatsächlichem Debufftyp." },
        },
    },
    {
        key = "BWL", name = "Blackwing Lair", short = "BWL",
        zones = { "Blackwing Lair" },
        bosses = {
            { key = "razorgore", label = "Razorgore the Untamed", units = { "Razorgore the Untamed" }, m1 = "Razorgore: Ein Spieler kontrolliert ihn per Orb und zerstört die Eier, Tanks halten die Adds. Nach allen Eiern Razorgore normal töten. Fireball Volley und Conflagration beachten. Keine Flüche zu cleansen." },
            { key = "vaelastrasz", label = "Vaelastrasz the Corrupt", units = { "Vaelastrasz the Corrupt" }, m1 = "Vaelastrasz: Tank Rücken zur Wand, Heiler fokussieren den Tank. Wer Burning Adrenaline hat, läuft sofort weit weg vom Raid, sonst explodiert die Bombe! Cleave und Flame Breath meiden. Keine Flüche." },
            { key = "broodlord", label = "Broodlord Lashlayer", units = { "Broodlord Lashlayer" }, m1 = "Broodlord: Tank Rücken zur Wand, Melees hinter dem Boss. Mortal Strike: Tanks wechseln, Heiler vorbereiten. Blast Wave und Knock Away beachten. Keine speziellen Flüche zu cleansen." },
            { key = "firemaw", label = "Firemaw", units = { "Firemaw" }, m1 = "Firemaw: Tank vom Raid wegdrehen, Wing Buffet wirft Aggro – Tanks wechseln. Flame Buffet stackt: Feuerresistenz nutzen, Stacks beachten. Shadow Flame (Kegel) meiden. Keine Flüche zu cleansen." },
            { key = "ebonroc", label = "Ebonroc", units = { "Ebonroc" }, m1 = "Ebonroc: Tank vom Raid wegdrehen, Wing Buffet und Shadow Flame beachten. Shadow of Ebonroc auf dem Tank: nicht heilen, Tankwechsel! Aggro nach Wing Buffet zurückholen. Keine Flüche zu cleansen." },
            { key = "flamegor", label = "Flamegor", units = { "Flamegor" }, m1 = "Flamegor: Tank vom Raid wegdrehen, Wing Buffet und Shadow Flame beachten. Frenzy: Hunter Tranquilizing Shot. Tanks wechseln bei Aggro-Verlust. Heiler auf Tanks fokussieren. Keine Flüche zu cleansen." },
            { key = "chromaggus", label = "Chromaggus", units = { "Chromaggus" }, m1 = "Chromaggus: Tank wegdrehen, Breath per Line of Sight meiden. Brood Affliction ständig cleansen (Magie/Gift/Krankheit/Fluch je nach Farbe), Bronze: Hourglass Sand. Frenzy: Hunter Tranquilizing Shot." },
            { key = "nefarian", label = "Nefarian", units = { "Nefarian" }, m1 = "Nefarian: Phase 1 Drakoniden mit Tanks kontrollieren. Phase 2: Tank Rücken zur Wand, Bellowing Roar: Fear Ward/Tremor Totem, Class Calls beachten. Shadow Flame meiden, Veil of Shadow entfernen." },
            { key = "ezzel", label = "Ezzel Darkbrewer (Custom)", units = { "Ezzel Darkbrewer" }, m1 = "Tank: Ezzel und Ton'Raka kontrollieren. DDs: Bei Charge-Ziel sofort reagieren und Acid Bomb ausweichen. Heiler: betroffene Spieler schnell stabilisieren.", m2 = "Primär: markierte/angegriffene Spieler achten auf Charge und Säureflächen. Heiler: Debuffs prüfen; Gift reinigen, falls entfernbar, Magie entsprechend dispellen." },
        },
    },
    {
        key = "ZG", name = "Zul'Gurub", short = "ZG",
        zones = { "Zul'Gurub" },
        bosses = {
            { key = "jeklik", label = "High Priestess Jeklik", units = { "High Priestess Jeklik" }, m1 = "Jeklik: Fledermaus-Phase: Fledermäuse und Feuerbomben meiden. Phase 2: Great Heal unterbrechen, Shadow Word: Pain und Mind Flay beachten. Tank Rücken zur Wand. Sonic Burst: Casters Abstand halten." },
            { key = "venoxis", label = "High Priest Venoxis", units = { "High Priest Venoxis" }, m1 = "Venoxis: Poison Cloud meiden, Holy Fire dispellen, Renew purgen. In Schlangenphase Gift cleansen, Schlangen von Tanks einsammeln lassen. Tank Rücken zur Wand, Raid verteilt stehen." },
            { key = "marli", label = "High Priestess Mar'li", units = { "High Priestess Mar'li" }, m1 = "Mar'li: Spinnen-Adds einsammeln, Poison Bolt Volley cleansen, Drain Life unterbrechen. Phase 2 (Spinne): Tanks wechseln, Charge beachten. Tank Rücken zur Wand. Keine Flüche zu cleansen." },
            { key = "mandokir", label = "Bloodlord Mandokir", units = { "Bloodlord Mandokir" }, m1 = "Mandokir: Wer von Threatening Gaze betroffen ist, bleibt stehen (nicht bewegen)! Ohgan zuerst töten, er belebt den Boss. Tank wegdrehen wegen Whirlwind. Heiler: Raid und Tanks. Keine Flüche." },
            { key = "edge", label = "Edge of Madness", units = { "Gri'lek", "Hazza'rah", "Renataki", "Wushoolay" }, m1 = "Edge of Madness: Zufälliger Boss (Gri'lek, Hazza'rah, Renataki, Wushoolay), nach Ansage. Tank weg vom Raid. Hazza'rah: Illusionen töten, Renataki: Aggro nach Vanish zurückholen, Wushoolay: Chain Lightning unterbrechen." },
            { key = "gahzranka", label = "Gahz'ranka", units = { "Gahz'ranka" }, m1 = "Gahz'ranka: Tank wegdrehen, Raid hinter dem Boss. Frost Breath (Kegel) meiden, Massive Geyser (Knockback) beachten. Frostresistenz hilft. Heiler: Tank und Raidschaden. Keine Flüche." },
            { key = "thekal", label = "High Priest Thekal", units = { "High Priest Thekal" }, m1 = "Thekal: Thekal, Zath und Lor'Khan etwa gleichzeitig töten, sonst werden sie wiederbelebt. Tiger-Phase: Tanks wechseln, Mortal Cleave (Heilung -50%) beachten. Silence und Disarm beachten. Keine Flüche." },
            { key = "arlokk", label = "High Priestess Arlokk", units = { "High Priestess Arlokk" }, m1 = "Arlokk: Wer Mark of Arlokk hat, wird von Panthern gejagt – Panther schnell töten. Tank holt Aggro nach Vanish zurück. Raid verteilt stehen wegen Gouge und Trap. Keine speziellen Flüche." },
            { key = "jindo", label = "Jin'do the Hexxer", units = { "Jin'do the Hexxer" }, m1 = "Jin'do: Totems sofort töten (Brain Wash Totem, Healing Ward). Hex und Delusions of Jin'do decursen. Schatten der Jin'do (Adds) nach Ansage töten. Tank Rücken zur Wand, Raid verteilt stehen." },
            { key = "hakkar", label = "Hakkar the Soulflayer", units = { "Hakkar the Soulflayer" }, m1 = "Hakkar: Priester (Hohepriester) zuvor töten. Poison Cloud meiden, Poisonous Blood/Gift cleansen. Mind Control: Kontrollierte nicht angreifen. Corrupted Blood nicht ins Raid tragen. Tank Rücken zur Wand." },
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
            { key = "anub", label = "Anub'Rekhan", units = { "Anub'Rekhan" }, m1 = "Anub'Rekhan: Tank wegdrehen, Crypt Guards von Offtanks halten. Locust Swarm: Abstand zum Boss/Raid halten. Impale (Linie) meiden. Add-Welle nach Ansage töten. Keine Flüche zu cleansen." },
            { key = "faerlina", label = "Grand Widow Faerlina", units = { "Grand Widow Faerlina" }, m1 = "Faerlina: Enrage per Mind Control eines Worshippers (Priester) entfernen, Adds nach Ansage töten. Rain of Fire sofort verlassen. Tanks wechseln bei Enrage. Keine Flüche zu cleansen." },
            { key = "maexxna", label = "Maexxna", units = { "Maexxna" }, m1 = "Maexxna: Tank Rücken zur Wand. Web Spray: Heiler Raidschaden. Necrotic Poison cleansen! Web-Wrap-Adds nach Ansage freikämpfen. Frenzy ab 30%: Hunter Tranquilizing Shot. Keine Flüche." },
            { key = "noth", label = "Noth the Plaguebringer", units = { "Noth the Plaguebringer" }, m1 = "Noth: Curse of the Plaguebringer sofort decursen! Blink wirft Aggro, Tank holt ihn zurück. Skelett-Adds nach Ansage töten. Balkon-Phase: Skelette killen. Tank Rücken zur Wand." },
            { key = "heigan", label = "Heigan the Unclean", units = { "Heigan the Unclean" }, m1 = "Heigan: Pest-Spalten meiden (Tanzmuster nach Ansage). Disease Cloud: Krankheit cleansen, Spell Disruption beachten. Tank wegdrehen. Raid verteilt stehen. Keine Flüche zu cleansen." },
            { key = "loatheb", label = "Loatheb", units = { "Loatheb" }, m1 = "Loatheb: Inevitable Doom decursen! Corrupted Mind: Heiler heilen in Rotation nach Ansage. Spores einsammeln für den Crit-Buff. Heilung gezielt auf Tanks und Raid, nicht überheilen." },
            { key = "razuvious", label = "Instructor Razuvious", units = { "Instructor Razuvious" }, m1 = "Razuvious: Priester kontrollieren die Understudies und tanken damit Razuvious. Disrupting Shout kostet Mana. Selbst nicht tanken! Understudy-Taunts nutzen. Keine Flüche zu cleansen." },
            { key = "gothik", label = "Gothik the Harvester", units = { "Gothik the Harvester" }, m1 = "Gothik: Raid in Live- und Dead-Seite teilen, Adds nach Ansage töten. Danach ist Gothik offen: Tank wegdrehen, Shadow Bolt Volley heilen. Keine speziellen Flüche zu cleansen." },
            { key = "horsemen", label = "Die vier Reiter", units = { "Thane Korth'azz", "Lady Blaumeux", "Sir Zeliek", "Baron Rivendare" }, m1 = "Vier Reiter: Tanks rotieren, Marks (Korth'azz, Zeliek, Blaumeux, Mograine) bei 4 Stacks abtauschen. Void Zone und Meteor meiden. Heiler decken die Tankteams ab. Keine Flüche zu cleansen." },
            { key = "patchwerk", label = "Patchwerk", units = { "Patchwerk" }, m1 = "Patchwerk: 2 Tanks mit viel Leben (Hateful Strike trifft den Melee mit den meisten HP), Heiler auf Tanks fokussieren. Berserk ab 5%. DDs Schaden ohne Aggro. Keine Flüche zu cleansen." },
            { key = "grobbulus", label = "Grobbulus", units = { "Grobbulus" }, m1 = "Grobbulus: Tank wegdrehen, Raid verteilt stehen. Mutating Injection: Betroffener läuft weit weg vom Raid! Poison Cloud meiden, Gift cleansen. Keine Flüche zu cleansen." },
            { key = "gluth", label = "Gluth", units = { "Gluth" }, m1 = "Gluth: Zombie Chow vorher kontrollieren. Decimate: Heiler Raid sofort heilen! Frenzy: Hunter Tranquilizing Shot. Mortal Wound: Tanks wechseln. Keine Flüche zu cleansen." },
            { key = "thaddius", label = "Thaddius", units = { "Thaddius" }, m1 = "Thaddius: Stalagg und Feugen etwa gleichzeitig töten (Zeitfenster ~5 Sek). Polarity Shift: Gruppen nach Ansage tauschen, sonst Schaden. Chain Lightning beachten. Keine Flüche zu cleansen." },
            { key = "sapphiron", label = "Sapphiron", units = { "Sapphiron" }, m1 = "Sapphiron: Life Drain decursen. Frost Aura und Blizzard meiden, Frostresistenz Pflicht. Bei Frost Breath hinter Ice Block verstecken! Luftphase: Ice Bolt beachten. Tanks wechseln." },
            { key = "kelthuzad", label = "Kel'Thuzad", units = { "Kel'Thuzad" }, m1 = "Kel'Thuzad: Phase 1 Adds töten. Phase 2: Frostbolt unterbrechen, Frost Blast heilen, Detonate Mana: Manauser fernhalten. Chains: Kontrollierte nicht angreifen. Phase 3 Guardians. Keine Flüche." },
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
            { key = "azuregos", label = "Azuregos", units = { "Azuregos" }, m1 = "Azuregos: Tank Rücken zur Wand, Raid hinter dem Boss. Magic Shield: Zauber stoppen, bis das Shield weg ist. Mark of Frost/Teleport beachten (Aggro zurückholen). Mana Storm meiden. Frostresistenz hilft." },
            { key = "kazzak", label = "Lord Kazzak", units = { "Lord Kazzak" }, m1 = "Lord Kazzak: Tank wegdrehen. Mark of Kazzak: Manauser beobachten und Mark entfernen, bevor das Mana leer ist (Explosion). Shadow Bolt Volley heilen. Fear Ward/Tremor Totem. Keine Flüche." },
            { key = "emeriss", label = "Emeriss", units = { "Emeriss" }, m1 = "Emeriss: Tank Rücken zur Wand. Noxious Breath: Tankwechsel. Volatile Infection: Krankheit cleansen. Bei 75/50/25% Pilze meiden. Aggro nach Breath zurückholen. Keine Flüche zu cleansen." },
            { key = "lethon", label = "Lethon", units = { "Lethon" }, m1 = "Lethon: Tank Rücken zur Wand. Shadow Bolt Whirl meiden. Spirit Shades (75/50/25%) töten, nicht ignorieren. Noxious Breath: Tankwechsel. Keine Flüche zu cleansen." },
            { key = "taerar", label = "Taerar", units = { "Taerar" }, m1 = "Taerar: Fear Ward/Tremor Totem gegen Bellowing Roar. Shades of Taerar (75/50/25%) töten. Noxious Breath: Tankwechsel. Arcane Blast: Abstand halten. Keine Flüche zu cleansen." },
            { key = "ysondre", label = "Ysondre", units = { "Ysondre" }, m1 = "Ysondre: Druids of the Talon (75/50/25%) nacheinander töten. Lightning Wave: Raid aufteilen. Noxious Breath: Tankwechsel. Sleep/Schlaf-Effekte dispellen. Keine Flüche zu cleansen." },
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
