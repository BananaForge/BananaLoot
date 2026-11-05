# Third-Party Notices

BananaLoot is an original addon project by Bareg. The BananaLoot source code and
original artwork are developed independently and are licensed under the MIT License.

This repository also contains item data from a third-party source. The data is
identified below.

## Item Database

BananaLoot's bundled item database (`BananaLootItemDB.lua`) contains item data
(names, qualities, icons and further item attributes) sourced from
Bananaforge Luminar.

## Instance Loot Data

`BananaLootZoneLoot.lua` (instance -> item IDs) is generated from the loot
tables of AtlasLoot Turtle WoW Edition and used with permission of its
developer. It is only used to preload item information from the game server.
`tools/gen_zone_loot.py` regenerates the file from an AtlasLoot copy.

`BananaLootRaidLoot.lua` (raid -> boss -> item IDs, plus name/quality/icon for
items missing from the bundled item database) is generated from the same
AtlasLoot data and used with the same permission. It is only used to show the
item selection of the Raid Setup window. `tools/gen_raid_loot.py` regenerates
the file from an AtlasLoot copy.

`BananaLootItemInfoExtra.lua` (name, quality and icon for items missing from the
bundled item database) is generated from the same AtlasLoot data and used with the
same permission. It is only used to display items. `tools/gen_item_info.py`
regenerates the file from an AtlasLoot copy.

## Separation of Licenses

The MIT License included in this repository applies to the original BananaLoot
source code and original BananaLoot artwork created by Bareg. It does not
replace or modify any license or rights that may apply to third-party data.

Third-party data remains subject to the applicable terms and licenses of its
respective source.

## Disclaimer

This file is provided to document the sources of third-party data used by
BananaLoot. If a rights holder requires additional attribution or a change to
the use of its data, please open an issue or contact the BananaLoot maintainer.
