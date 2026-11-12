# BlockCraft

A Minecraft-style survival server for Roblox, built with [Rojo](https://rojo.space). Everyone in a Roblox server shares one blocky world: mine and place blocks, claim a kit, fight in the wilderness or the PvP arena, and loot whoever you kill.

## Getting it into Roblox Studio

1. Install the tools. With [Rokit](https://github.com/rojo-rbx/rokit): `rokit install` (versions are pinned in `rokit.toml`).
2. Either build a place file: `rojo build -o BlockCraft.rbxl` and open it in Studio,
   or live-sync: run `rojo serve`, then connect with the Rojo plugin in Studio.
3. Publish the place, then in **Game Settings**:
   - **Security → Enable Studio Access to API Services** (needed for kit cooldowns and inventories to save).
   - **Avatar → Avatar Type: R6** for blocky characters. The project already sets this, but Game Settings take priority if they were changed.
4. Press Play (or Start Server with 2+ players to test PvP).

## What's in it

| Feature | How it works |
| --- | --- |
| No loading screen | Roblox's default loading screen is removed and the spawn area is built before anyone spawns. The rest of the world appears in the background, and streaming keeps joins fast. |
| Shared world | 128×128 blocks of generated hills, trees, sand, stone and ores (size is configurable). Changes made by any player are seen by everyone in that server. |
| Mining and building | Hold left-click to mine (breaking speed depends on the block), right-click to place. A black outline and darkening overlay show progress. The server checks reach, timing and protected zones. |
| Protected spawn | Stone-brick hub where blocks can't be broken or placed and PvP is off. Players spawn and respawn here. |
| PvP arena | A walled floating arena reached with `/warp pvp` or `/pvp`. Blocks are protected, PvP is always on, and killed players drop everything. |
| Combat | Hearts (20 HP), the 1.9+ attack cooldown, critical hits when falling, knockback, half-second hit invulnerability, red hurt flash, and Minecraft's armor, toughness and Protection formulas. Includes fall damage, void death, natural regeneration and Minecraft-style death messages. |
| Death and loot | Inventory and armor scatter on the ground as item entities that anyone can pick up. You then get a "You died!" screen with a Respawn button. |
| Combat tag | Hitting or being hit tags you for 15 seconds, shown at the top of the screen. While tagged you can't use `/spawn`, `/rtp` or `/warp`, and a pending teleport is cancelled. The Roblox reset button is disabled. |
| Combat logging | Roblox can't stop anyone closing the game, so leaving while tagged drops all your items where you stood and announces it to the server, the same as on Minecraft servers that use combat-log plugins. |
| Kit | `/kit` gives full Diamond armor (Protection III on every piece) and a Diamond Sword (Sharpness V, Unbreaking III). Armor is equipped automatically. It can be claimed once every 5 hours, and the cooldown is saved. |
| Inventory | 9-slot hotbar, 27-slot inventory and 4 armor slots. Press E, click one slot then another to move or swap, Shift-click to quick-move or equip, and number keys over a slot to swap it into the hotbar. Inventories are saved between sessions. |
| HUD | Hotbar with 3D item icons, hearts, armor bar, held-item name, action-bar messages, combat timer, zone indicator, crosshair, first-person arm and held item, and enchantment tooltips. |

### Controls

| Key | Action |
| --- | --- |
| WASD / Space | Move / jump |
| Left Ctrl or double-tap W | Sprint |
| Left Shift | Sneak |
| Left click (hold) | Attack / mine |
| Right click | Place block |
| 1–9, mouse wheel | Select hotbar slot |
| E | Inventory |
| Q / Ctrl+Q | Drop one / drop stack |
| F5 | Toggle first / third person |
| / | Chat command |

### Commands

Player commands: `/help`, `/spawn`, `/kit [name]`, `/kits`, `/rtp` (aliases `/wild`, `/randomtp`), `/warp pvp`, `/pvp`, `/list`.

Admin-style commands are recognised but intentionally do nothing. They reply with the usual "you do not have permission" message: `/gm0`–`/gm3`, `/gmc`, `/gms`, `/gamemode`, `/give`, `/i`, `/tp`, `/tphere`, `/time`, `/weather`, `/kill`, `/op`, `/ban`, `/kick`, `/fly`, `/heal`, `/feed`, `/god`, `/vanish`, `/clear`, `/effect`, `/enchant`, `/summon`, `/setblock`, `/fill`, `/gamerule`, `/xp`, `/speed` and more (see `src/server/Commands.luau`). Any other `/…` message gets "Unknown command" and is never shown in public chat.

## Textures, sounds and animations

Minecraft's textures, sounds and models belong to Mojang/Microsoft. Uploading them to Roblox infringes their copyright and gets assets or the whole game taken down, so none are included. Out of the box:

- **Blocks** use Roblox materials with Minecraft-like colours. To get a pixel-art look, upload your own (or properly licensed) 16×16 textures and add their ids to `Config.Textures` in `src/shared/Config.luau`. Each block can have a separate top, side and bottom image.
- **Sounds** use sounds that ship with the Roblox client. Replace the ids in `Config.Sounds` with your own uploads.
- **Animations** are procedural: arm swings for mining and attacking (visible to everyone), a first-person arm and held item with walk bobbing, and R6 avatars for the blocky look.

Don't use "Minecraft" in the game's title or thumbnail. The trademark belongs to Microsoft and Roblox moderates it.

## Configuration

Everything tunable is in `src/shared/Config.luau`: world size and seed, spawn and arena size, whether PvP is on in the wilderness, combat-tag length, teleport warmup, `/rtp` cooldown, movement speeds, knockback, day length, kits, textures and sounds. To add a kit, add an entry to `Config.Kits` and its name to `Config.KIT_ORDER`.

## Project layout

```
src/
  first/       ReplicatedFirst: removes the loading screen
  shared/      Config, block/item definitions, item models, zones, remotes, sounds
  server/      World (voxel storage + generation), Structures (spawn, arena), Inventory, Drops,
               Combat, Building, Teleport, Kits, Commands, Visuals, Data (DataStore), Main
  client/      State, Hud, Interaction (mine/place/attack), Controls, Effects
  character/   Empty "Health" script that disables Roblox's default regeneration
```

The server is authoritative for everything that matters: block edits, inventories, damage, kits and teleports. Remotes are validated and rate-limited.

## Known limitations

- The world isn't saved. Each server generates a fresh world when it starts; set `Config.SEED` to make every server generate the same terrain.
- Built for keyboard and mouse. Touch and gamepad controls aren't implemented.
- There's no hunger, crafting, mobs, water, tools or durability yet. Stone can be mined by hand and still drops cobblestone.
- Ores drop coal, raw iron and diamonds, but nothing uses them yet.
- A failed DataStore load disables saving for that player's session so their real data can't be overwritten. Kit cooldowns are still enforced in memory for the rest of that server's life.
