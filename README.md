![BananaLoot](assets/BananaLoot.png)

# 🍌 BananaLoot

**Masterloot addon with chat-based soft-reserves and a local SR+ bonus system** for World of Warcraft Classic 1.12 (OctoWoW, Turtle WoW, and similar Vanilla servers)

Behavior is inspired by the well-known RollFor workflow – the code itself is
fully original (no code copied from elsewhere).

Part of [BananaForge](https://github.com/BananaForge).

**⬇️ [Download the latest version](https://github.com/BananaForge/BananaLoot/releases/latest)**

---

## What is BananaLoot?

BananaLoot takes the paperwork off the master looter's plate: players reserve
items the normal way via whisper, the addon remembers everything locally,
evaluates rolls automatically, and rewards raid attendance with SR+ bonuses
for players who have soft-reserved an item without winning it.

No external service, no login, no dependency on working HTTP in the game
client – everything runs entirely locally via SavedVariables. Importing a
list from raidres.top is supported, but purely as a one-time text paste –
BananaLoot never talks to the internet on its own.

---

## Features

### Whisper-based soft reserve

- Players simply whisper `sr [Item]` or `unsr [Item]` to the master looter
- `srlist` shows a player's own reservations including bonus
- `hr` / `hrlist` lists all current Hard Reserve items
- By default exactly 1 SR per player is active – reserving a new item
  automatically drops the old one (with a heads-up sent via whisper).
  Optionally configurable up to 4 simultaneous reservations per player
  (Options → General)
- `/bl sr [Item]` / `/bl unsr [Item]` let the master looter reserve for
  themselves (you can't whisper yourself)
- The SR list can be locked/unlocked for the whole raid with one click –
  while locked, new `sr`/`unsr` whispers are politely declined, but you can
  still edit everything manually in the Manage window
- Spam protection (max. 1 command every 2 seconds per player)
- Unknown commands get a reply instead of being silently ignored
  (can be turned off)

### SR+ bonus system

- SR+ is a reward for raid attendance: when you end a raid (see
  [Raid start / end](#raid-start--end)), every SR of an attendee that was not
  won gets +1 SR+ – whether or not the item dropped
- Each SR+ stack adds a bonus to the next roll on that item; the bonus per
  stack is freely configurable (default: +10)
- SR+ values persist across raids and relogs
- **SR+ recovery**: if a player accidentally overwrites their reservation
  (or an import replaces it), the most recently displaced reservation per
  player is kept in a recovery list and can be restored with one click
  (`/bl recover`)

### Hard Reserve (HR)

- Permanently reserve items for a specific player, independent of the
  whisper system
- Never rolled automatically – awarded exclusively by hand in the Manage
  window
- Dedicated management view with an overview and a remove button per item,
  reachable via `/bl hr` or the **HR** quick-access button in the SR
  window's title bar

### Bank Reserve (BR)

- A second, independent reserve list for items that should never be rolled
  **or announced** at all – e.g. tradeskill materials for the guild bank,
  BoE items earmarked for sale/crafting
- BR items are detected silently the moment loot opens and are
  automatically awarded via the master loot API – no roll, no raid/party
  chat announcement, no entry in the loot window. Only a local chat line
  confirms the award to you
- By default the master looter receives them. With **Set BR Looter** (SR
  window side menu) you can name another player who gets all Bank Reserve
  items instead
- Managed via `/bl br`, `/bl br [Item]`, `/bl br remove [Item]`, or the
  **BR** quick-access button in the SR window's title bar

### Automatic roll evaluation

- Detects Main Spec (`/roll`), Off-Spec (`/roll 99`), and Transmog
  (`/roll 98`) rolls automatically via system chat
- Priority: Main Spec > Off-Spec > Transmog
- If an item is soft-reserved, only the reservers may roll Main Spec –
  Off-Spec/Transmog stays open to everyone
- Resolves immediately once all eligible players have rolled (no need to
  wait for the timeout)
- On a tie, only the affected players are automatically asked to re-roll
- Configurable timeout as a fallback (default: 60 seconds)
- Optional chat countdown in the final seconds (10/5/3/2/1), can be toggled off
- **Raid Roll**: award an item to a random raid/party member without
  anyone needing to actually type `/roll` – useful for junk/consolation
  items nobody wants to bother with

### Disenchanter

- Set a player with **Set Disenchanter** (SR window side menu)
- If nobody rolled on an item, the loot window shows a **Disenchant** button
  instead of **Award**. One click gives the item straight to the disenchanter –
  no new roll – and announces it in raid/party chat
- The award is logged like any other (category "Disenchant") and appears in
  the shared loot history. If no disenchanter is set, you get a chat hint

### Round Robin for Main Spec (optional)

- Optional (Options → Automation, default **off**, active only while a raid
  is running): every item won through an MS roll (without SR) raises the
  winner's RR level for this raid. In MS rolls the lower RR always wins; the
  roll only decides between equal RR levels
- Off-spec and transmog still rank below every MS roll; SR items, manual
  awards and Raid Rolls are unaffected
- The raid is the round: ending the raid resets everything. Rolls that don't
  count are listed transparently in chat and in the loot window
- Commands: `/bl rr`, `/bl rr reset`

### Multi-drop rolls ("top rolls win")

- Optional (Options, default **off**): if multiple copies of the same item
  are sitting in the loot window, BananaLoot starts a single shared roll
  instead of one roll per copy, and the top N rollers (N = number of
  copies) each win a copy
- A tie right at the cutoff only makes the tied players re-roll for the
  remaining copies – players already above the cutoff are locked in
- The loot window lists every winner with their roll/score (greyed out
  once awarded), with one Award click needed per copy
- With the option off (default), or if only a single copy drops, behavior
  is identical to a normal single-winner roll

### Roll-Sync & shared loot history

- Optional (Options, default **off**): broadcasts roll progress (start,
  incoming rolls, ties, winner, cancellation) via addon message to other
  raid/party members who also run BananaLoot with the option enabled
- Recipients get their own small popup window with the item, mode
  (SR/Open/ARF), a live countdown, and a standings list of incoming rolls –
  with MS/OS/TM buttons to roll directly from the popup (same effect as
  typing `/roll` by hand). With Round Robin active, the popup shows each
  player's RR level
- The master looter can optionally see their own popup too (separate
  sub-option, off by default, since they already have the loot window)
- Every award (roll winner, manual award, raid roll, disenchant) is
  additionally logged to a **shared loot history** (`/bl history`), visible
  to the master looter and everyone with Roll-Sync enabled – session-only,
  not saved to disk. Bank Reserve awards never appear here, by design

### Trade tracking

- Optional (Options, default **off**): automatically detects when an item
  previously awarded via BananaLoot is traded onward to another player,
  and adds the new owner to the corresponding loot log entry ("Traded to"
  column, see `/bl csvlog`)
- Detection happens through your own trade window; hand-offs are shared
  with other trade-tracking-enabled BananaLoot users in the raid/group so
  multi-hop trades stay traceable even if you aren't part of every trade
- Hard limitation of the WoW trade API: a trade between two *other* players
  is only visible if at least one of them also has this option enabled

### Loot preview in raid/party chat

- Optional (Options, default **on**): the moment a *new* loot window opens
  – before anyone rolls – BananaLoot posts a one-line-per-item preview so
  everyone knows in advance how each item will be handled:
  `[Item] [SR]: Bareg(+10), Nareg`, `[Item] [Open]`, `[Item] [HR]`
- Bank Reserve items are never part of this preview, since they're meant
  to be awarded completely silently
- Reopening the loot window for the same corpse without looting anything
  new does **not** spam the preview (or the "loot detected" sound) a
  second time

### Loot window automation

- Automatically detects when a loot window is opened as master looter,
  and pops it up on its own
- `/bl auto` works through the entire chest one item at a time: non-SR
  items first (open to everyone), SR items afterward (reservers only) –
  Bank Reserve items are skipped entirely (see above)
- Multiple drops of the same item are counted correctly and handled one by one
- `/bl arf [Item]` suspends SR for a single roll (open to everyone)
- Attempts to award automatically via the master loot API – if that fails,
  the winner is displayed clearly so you can award manually instead
- Every row of the loot window shows the winner on its own line ("Winner:
  Name" in class color) so you can double-check before you click Award

### Auto Master Loot on boss target

- Targeting a known raid boss switches the loot method to Master Loot
  automatically (needs party/raid leader). Boss names live in a single data
  file shared with the raid lead announcements
- On by default; toggle it with the **Auto ML on boss** button in the SR
  window side menu or under Options → Automation
- Stratholme is deliberately excluded (bosses there share names with
  Naxxramas bosses)
- Optional test raid **Upper Blackrock Spire**: enable it under Options →
  Management to use boss announcements and Auto Master Loot in UBRS (a
  10-player dungeon, handy for testing the addon). Off by default

### Raid start / end

- A **Start Raid / End Raid** button records everyone in the raid as an
  attendee (players invited later are added automatically) and runs a raid
  timer with attendee count at the bottom of the SR window. The raid keeps
  running across `/reload` and relog
- Ending a raid asks twice: "Do you really want to end the raid?" and then
  "Raise SR+ for all raiders?". Duration, attendees and the result of the
  last 50 raids are saved

### Statistics

- A Statistics tab in the options window: overview (raids, total and average
  duration, average attendees, items by MS/OS/TM/Raid Roll/Manual), raid
  list, loot ranking (top 10), attendance with bars, highest SR+ (top 10)
  and a per-raider detail view
- Duration and attendance are only available for raids recorded with
  Start Raid

### Raid lead announcements

- Optional (Options → Management, default **off**; when off, nothing is
  announced and the window is locked). Open the window with the **Raid lead
  window** button or `/bl rl`
- One tab per raid (General fallback, MC, Onyxia, BWL, ZG, AQ20, AQ40, Naxx,
  Timbermaw Hold, Lower Karazhan Halls, Tower of Karazhan, Emerald Sanctum,
  World Bosses; UBRS when enabled). Per raid you can edit a welcome message,
  trash notes and a closing message, and per boss two announcement texts
  (255 characters each) plus an on/off checkbox, with **Send 1 / Send 2**
  buttons for manual posting
- On Start Raid the welcome message and trash notes are posted to raid/party
  chat, on End Raid the closing message. The first time a boss is targeted,
  its message 1 is posted; message 2 follows via button or after a
  configurable delay
- Double-post protection: only the raid leader sends – or, if a name is
  entered in the sender field, only that player. Each boss is announced once
  per raid, and other BananaLoot clients are informed so they stay silent
- Default texts ship for every boss (including the optional UBRS raid);
  everything is editable and your own texts always take priority

### Two dedicated windows

- **SR window** (`/bl`, minimap left-click): persistent overview of all
  current reservations, independent of whether loot is currently open.
  Player names are shown in their class color throughout. A collapsible
  **side menu** on the right (state is remembered) holds Start/End Raid,
  Export, Import, Save Raid, Load Raid, Options, LFM, Set Disenchanter, Set BR
  Looter and the Auto ML toggle. Lock, ML/GL, HR/BR quick access and the loot
  window button stay in the main window
- **Loot window** (`/bl loot`): only the items currently visible in the
  real Blizzard loot window, with Roll/ARF/Award (or Disenchant) actions.
  Opens automatically whenever loot becomes available

### Manage window

- For every item: view all reservers including their SR+ bonus
- Manually adjust SR+ stack (+/-)
- Manually add or remove players
- Directly set a winner and award instantly (with a confirmation prompt),
  or hand it off with a Raid Roll
- Warns if a manually entered name isn't currently in the raid
  (typo protection)
- Context-aware: opened from the SR window it only offers list editing;
  opened from the loot window it additionally offers Winner/Raid Roll,
  and its removal button becomes "Skip drop" (keeps the SR reservation
  intact for a possible re-drop)

### Save Raid / Load Raid

- Save the entire current SR state (reservations, everyone's SR+ values,
  and the SR+ recovery list) locally under a name of your choosing, and
  reload it later – handy for keeping separate raid nights cleanly apart
  or undoing a mistake
- An existing name prompts for confirmation before it gets overwritten
- The Load Raid list shows when each save was last updated, with Load and
  Delete actions per entry
- The name of the currently active saved/loaded raid is shown as a
  subtitle right under the SR window's title
- Hard Reserve and Bank Reserve are intentionally **not** part of a
  snapshot – they're meant to persist across raids, not be tied to one
- Fully independent of Export/Import below – both remain available side
  by side

### Export / import for a stand-in loot master

- Export the complete SR list (including SR+ values and Hard Reserves) as
  text, timestamped so an old export can be flagged as stale
- The stand-in simply pastes the text into their own BananaLoot and is
  immediately up to date

### raidres.top import

- Paste a raidres.top export directly and BananaLoot decodes and applies it
  (soft reserves, plus-ones, and hard reserves) – no manual re-typing needed
- The import reconciles per player instead of wiping: an item the raider
  already has on SR stays untouched and keeps its SR+; an old item missing
  from the import is removed and its SR+ reset; a new item is reserved.
  Players who are not part of the import are never touched
- Affected raiders get a whisper when their SR was overwritten or removed
  (throttled; players who aren't in the group are listed in your chat)
- Option "Raidres.top SR+ takes priority" (Options → General, default off):
  off keeps your local SR+, on lets an SR+ value above 0 from raidres.top
  overwrite it
- **Name mapping**: if a raider's Discord/raidres.top name differs from their
  in-game name, a "Match names" window opens after the import (or via
  `/bl alias`). Suggestions are never applied automatically; a mapping moves
  existing reservations and SR+ right away and applies to every future import

### Static item database

- Ships with a built-in item database of about 14,000 items (name, quality,
  icon and further attributes – see [Credits](#-credits)), used as a fallback
  whenever the server's `GetItemInfo()` doesn't know an item yet (very
  common for items nobody has looted, inspected, or linked this session)
- Lets raidres.top imports and Hard/Bank Reserve entries show the real,
  correctly colored item name and icon immediately, instead of just
  "Item #12345" until the item actually drops

### Test mode

- "Start test run" (Options → Management) simulates a complete loot drop on
  the **real** engine: 10 made-up Naxxramas loot slots and 10 made-up
  raiders who roll, chat and emote. Includes a Bank Reserve item and a
  disenchanter, so every award path can be tried
- Everything is announced locally only (marked `[TEST]`), and your real
  data and settings are backed up and restored automatically

### LFM poster for the world channel

- `/bl lfm` (or the **LFM** button in the SR window side menu) opens a small
  window that posts a text of your choice to the world channel at a fixed
  interval – e.g. for PUG raid ads or to replace a player who left
- Up to 255 characters with a live counter, interval in minutes
  (minimum 1, to stay clear of the server's chat spam protection)
- One Start/Stop button; text and interval are saved, but posting
  **never** restarts on its own after a relog or `/reload`
- The world channel's number is looked up by name before every post
  instead of being hard-wired to `/4`

### CSV export for Google Sheets

- Export the SR list and the full loot log as tab-separated text
- Just paste into an empty cell in Google Sheets – done

### Options

- Split into six tabs; the window adjusts its height to the active tab
- General: SR+ bonus per stack, roll timeout, max. simultaneous SR per
  player, unknown-command replies, raidres.top SR+ priority
- Automation: auto Master Loot on boss target, multi-drop ("top rolls
  win"), Round Robin, loot preview, chat countdown
- Network: Roll-Sync (plus the master looter's own popup), trade tracking
- Display & Sound: language (German/English, one click), UI scale and a
  separate loot window scale (50–150%, handy on small screens), and
  individual sound toggles for loot detected / roll started / winner
  determined / item awarded / button clicks (plus one master switch)
- Management: new raid, full SR+ wipe, CSV exports, log clearing, SR+
  recovery, test run, raid lead switch and window, optional UBRS test raid
- Statistics

### Other

- Loot log records every award (date, item, player, category, plus who it
  was traded to, if trade tracking is enabled)
- Draggable minimap button with a custom icon and a tooltip summary of
  current SR reservations
- Dedicated options window with banner
- Small ML/GL button (next to the SR lock toggle) switches WoW's actual
  loot method between Master Loot and Group Loot with one click (only
  works while you're the party/raid leader)

---

## Installation

1. Download `BananaLoot-<version>.zip` from the
   [latest release](https://github.com/BananaForge/BananaLoot/releases/latest)
2. Extract it into `World of Warcraft/Interface/AddOns/` – you should end up
   with `Interface/AddOns/BananaLoot/BananaLoot.toc`
3. Restart the client or `/reload`
4. Keep it enabled under "AddOns" on the character selection screen
5. The addon can be switched from German to English with a single click
   under Options → Display & Sound

> **Don't use GitHub's green "Code → Download ZIP" button.** It produces a
> folder called `BananaLoot-main`, and the client then finds neither the
> addon nor its icons. If you did, rename the folder to `BananaLoot`.

The release ZIP also contains `ANLEITUNG.txt`, the full German manual.

---

## Key commands

| Command                                             | Effect                                                                      |
| --------------------------------------------------- | --------------------------------------------------------------------------- |
| `/bl`                                               | Open/close the SR window                                                    |
| `/bl loot`                                          | Open/close the Loot window (also opens automatically when loot is detected) |
| `/bl auto`                                          | Automatically work through the current loot chest                           |
| `/bl award`                                         | Award the most recently evaluated item to the winner                        |
| `/bl arf [Item]`                                    | Open roll for everyone, SR suspended for this roll                          |
| `/bl sr [Item]` / `/bl unsr [Item]`                 | Reserve / unreserve an item for yourself as master looter                   |
| `/bl stop`                                          | Cancel auto mode / the active roll                                          |
| `/bl reset`                                         | Clear all current reservations (SR+ values are kept)                        |
| `/bl wipeplus`                                      | Completely reset all SR+ values                                             |
| `/bl export` / `/bl import`                         | Share the SR list with a stand-in (also accepts raidres.top exports)        |
| `/bl alias` / `/bl alias list` / `/bl alias del <n>`| Match raidres.top names to in-game names                                    |
| `/bl csv` / `/bl csvlog`                            | Export the SR list / loot log as CSV for Google Sheets                      |
| `/bl hr [Item]` / `/bl hr remove [Item]` / `/bl hr` | Manage the Hard Reserve list                                                |
| `/bl br [Item]` / `/bl br remove [Item]` / `/bl br` | Manage the Bank Reserve list                                                |
| `/bl rr` / `/bl rr reset`                           | Show / reset the Round Robin levels of the current raid                     |
| `/bl rl` / `/bl rl reset`                           | Open the raid lead window / clear the "already announced" markers           |
| `/bl recover`                                       | Show the SR+ recovery list                                                  |
| `/bl history`                                       | Show the shared loot history for this session (Roll-Sync)                   |
| `/bl clearlog`                                      | Clear the loot log (e.g. at the start of a season)                          |
| `/bl lfm`                                           | Open the LFM window (timed posts in the world channel)                      |
| `/bl options`                                       | Open settings                                                               |

Full command overview is also available in-game via the **?** button in
the SR window's title bar. Save Raid / Load Raid, Start/End Raid, Set
Disenchanter, Set BR Looter and the Auto ML toggle are button-only (SR
window) and don't have a slash command.

---

## Honestly: limitations of this addon

No loot tool is perfect – here are the deliberate trade-offs:

- **Automatic awarding is best-effort.** Assignment via the master loot API
  can fail depending on the server implementation. In that case the addon
  clearly displays the winner so the final award can be done manually in
  the Blizzard loot window.
- **No softres.it import.** raidres.top is supported (see Features); other
  formats would need their own decoder.
- **No automatic class or spec prioritization.** Everything runs on rolls,
  not on a rules engine.
- **Loot source detection is content-based, not ID-based.** Vanilla gives
  no unique loot-source identifier, so "was this the same corpse reopened"
  is inferred from the exact item set still present – extremely unlikely,
  but two unrelated kills with a coincidentally identical item set could
  in theory be treated as the same loot window.
- **Roll-Sync and trade tracking only work between BananaLoot users.**
  They're purely client-side addon-message features with no server
  component; players without the option enabled are invisible to them.
- The static item database can't know about items added after it was last
  generated – those simply show as "Item #ID" until actually looted once,
  exactly like before the database existed.
- Boss and zone names (especially the optional UBRS test raid) are matched
  by their English client names and are not verified on every server.
- Tested primarily on OctoWoW/Turtle WoW – other 1.12 servers may differ in
  details (e.g. master loot API behavior).

---

## Technical details

- Pure Lua, no XML – the entire UI is built at runtime
- Compatible with Lua 5.0 (no `#` operator, no `string.gmatch`)
- Data is stored locally in
  `World of Warcraft/WTF/Account/<ACCOUNT>/SavedVariables/BananaLoot.lua`
  and survives relogs and patches

### Repository layout

```
BananaLoot.toc            Addon manifest (version lives here and in BananaLoot.lua)
BananaLootItemDB.lua      Static item database (generated, don't edit by hand)
BananaLootBossData.lua    Raid and boss data shared by raid lead announcements and
                          Auto Master Loot (incl. the optional UBRS test raid)
BananaLoot.lua            Core: SavedVariables, locales, whispers, rolls, awarding,
                          raidres.top import, Roll-Sync, trade tracking, raid lead
                          logic, slash commands
BananaLootUI.lua          SR window, loot window, Roll-Sync popup
BananaLootExtra.lua       Options, Manage window, HR/BR lists, export/import, CSV,
                          SR+ recovery, LFM, Save/Load Raid, minimap button
BananaLootAlias.lua       Name mapping window for raidres.top imports
BananaLootRaid.lua        SR window side menu, Start/End Raid, raid timer,
                          Disenchanter / BR looter / Auto ML buttons
BananaLootStats.lua       Statistics tab
BananaLootRaidlead.lua    Raid lead window
BananaLootTest.lua        Test mode (simulated loot drop)
Icons/                    TGA textures loaded in-game
docs/ANLEITUNG.txt        Full German user manual (shipped in the release ZIP)
docs/ENTWICKLUNG.md       Developer notes (German)
tools/                    Checks run by CI: syntax, Lua 5.0 compatibility, TOC, version
assets/                   Images for this README only (not shipped)
```

### Development

- `bash tools/run_tests.sh` runs all checks locally (needs `lua5.1`).
  They also run on every push via GitHub Actions.
- **Releasing:** bump `## Version:` in `BananaLoot.toc` *and*
  `BananaLoot.VERSION` in `BananaLoot.lua`, add a `CHANGELOG.md` entry,
  push to `main`. The release workflow tags the version and attaches a
  correctly named `BananaLoot-<version>.zip`.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## Author

**Bareg**

🍌 Made for my guild, the Bananenrepublik – part of [BananaForge](https://github.com/BananaForge) 🍌

---

## 🙏 Credits

BananaLoot's code is fully original, but it stands on the shoulders of a
few great community projects and resources:

- **[RollFor](https://github.com/WowRollFor/RollFor)** – the soft-reserve
  workflow (whisper `sr`/`unsr`, automatic roll evaluation, SR+-style
  bonus stacking) that BananaLoot's behavior is modeled after.
- **Bananaforge Luminar** – source of the bundled static item database
  (see `THIRD_PARTY_NOTICES.md`).
- **[raidres.top](https://raidres.top/)** – the external soft-reserve
  website whose export format BananaLoot can import directly.

If your project or work should be credited here and isn't, please open an
issue – it wasn't intentional.

---

## ☕ Support the Project

If you enjoy BananaLoot and want to support its development:

[☕ Buy me a Coffee](https://www.buymeacoffee.com/bareg)

or you can send me an in-game mail with a donation to [N'Zoth] Bareg. Thank you for your support!

---

## License

Use at your own risk. Not a substitute for common sense while master looting. 🍌

BananaLoot's original source code and original artwork are licensed under the MIT License.
The bundled item database contains third-party data. See THIRD_PARTY_NOTICES.md for attribution and source information.

![BananaLoot](assets/BananaLootIcon.jpg)
