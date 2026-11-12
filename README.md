# BlockCraft

A Minecraft-style survival and PvP server for Roblox, built with [Rojo](https://rojo.space). Everyone in a Roblox server shares one blocky world: mine and place blocks, pick a kit, fight in the wilderness or the PvP warp, and loot whoever you kill. Combat follows Minecraft Java 1.21.1.

## Getting it into Roblox Studio

1. Install the tools. With [Rokit](https://github.com/rojo-rbx/rokit): `rokit install` (versions are pinned in `rokit.toml`).
2. Either build a place file with `rojo build -o BlockCraft.rbxl` and open it in Studio, or live-sync: run `rojo serve`, then connect with the Rojo plugin in Studio.
3. Publish the place, then in **Game Settings → Security** turn on:
   - **Allow Mesh / Image APIs** — required for the pixel-art block textures in a published game. Roblox only offers this switch to accounts that are 13+ and ID-verified. Without it the game still runs, but blocks are flat colours (see [Textures](#textures-sounds-and-animations)). In Studio the textures work without it.
   - **Enable Studio Access to API Services** — needed for kit cooldowns, inventories and stats to save.
4. In **Game Settings → Avatar**, keep **Avatar Type: R6** for blocky characters. The project already sets this, but Game Settings take priority if they were changed.
5. Press Play (or Start Server with 2+ players to test PvP).

## What's in it

| Feature | How it works |
| --- | --- |
| Pixel-art world | Every block face has a 16×16 pixel texture, generated in code. Only visible faces are built. Flat lighting, distance fog, blocky drifting clouds and a day/night cycle. |
| No loading screen | Roblox's default loading screen is removed and the spawn area is built before anyone spawns. The rest of the world grows outward in the background, and streaming keeps joins fast. |
| Shared world | 256×256 blocks of hills, plains, forests (oak and birch), deserts, snowy highlands, beaches, gravel patches and ores. Changes made by any player are seen by everyone in that server. |
| Mining and building | Hold left-click to mine (speed depends on the block), right-click to place. A black outline and darkening overlay show progress. The server checks reach, timing and protected zones. |
| Protected spawn | A walled stone-brick hub with a pavilion. Blocks can't be broken or placed and PvP is off. |
| PvP warp | `/warp pvp` or `/pvp` puts you on a safe spawn platform floating above a walled FFA arena. Nobody can hurt you up there. Jump down (no fall damage) to fight. In the arena blocks are protected, PvP is always on, and killed players drop everything. Dying there respawns you back on the platform. |
| PvP bot | A bot patrols the arena in the Diamond kit. It attacks the player wearing the best armor, ignores players with no armor, and turns on anyone who hits it. See [The bot](#the-bot). |
| Combat (1.21.1) | Attack cooldown, critical hits when falling, sprint-hit knockback, half-second hit invulnerability, armor, toughness and Protection, Sharpness, and Fire Aspect (sets the target on fire for 4 seconds per level). Fall damage, void death, natural regeneration and Minecraft-style death messages. |
| Combat tag | Hitting or being hit (by a player or the bot) tags you for 15 seconds. While tagged you can't use `/spawn`, `/rtp` or `/warp`, and a pending teleport is cancelled. The Roblox reset button is disabled. |
| Combat logging | Roblox can't stop anyone closing the game, so leaving while tagged drops all your items where you stood and announces it to the server. |
| Kits menu | `/kits` opens a chest-style menu. Hover a kit to see its contents and cooldown, click to claim. Cooldowns are saved. |
| Chat | Minecraft-style chat in the bottom-left: translucent lines that fade after ten seconds, `<Name> message` format, yellow join/leave messages. T opens it, `/` opens it with a slash typed, Up/Down recall earlier messages. Messages go through Roblox's text filter. |
| Inventory | 9-slot hotbar, 27-slot inventory and 4 armor slots. Press E, click one slot then another to move or swap, Shift-click to quick-move or equip, number keys over a slot to swap it into the hotbar. Saved between sessions. |
| HUD | Pixel hotbar, hearts and armor icons, held-item name, action-bar messages, combat timer, a sidebar scoreboard (kills, deaths, streak, players online, current zone), name tags with health, and a first-person held item. |

### Kits

| Kit | Contents | Cooldown |
| --- | --- | --- |
| Starter | Iron armor, Iron Sword, 32 Oak Planks | 5 minutes |
| Diamond | Diamond armor with Protection III, Diamond Sword with Sharpness IV and Fire Aspect I | 5 hours |
| Builder | 64 Oak Planks, 64 Cobblestone, 32 Stone Bricks, 16 Glowstone | 10 minutes |

Armor from a kit is put on automatically if the slot is empty. Edit, add or remove kits in `Config.Kits` and `Config.KIT_ORDER`.

### The bot

The bot plays by the same rules as a player: same reach, same weapon cooldown, same damage formulas. What makes it hard is how it uses them:

- It never swings before its sword has recharged, so every hit does full damage.
- It opens with a sprint hit for the extra knockback, then jumps so its next hits land while falling, which makes them critical.
- It lets go of sprint after each hit so the next one is a sprint hit again.
- While its sword recharges it circles you, staying on top of you after landing a hit and backing just out of your reach otherwise.
- It hops one-block walls, goes around pillars, and won't swing through cover.
- Once per life it backs off to heal 4 hearts when it gets low.

It respawns 15 seconds after dying and drops 2 diamonds. All of this is tunable in `Config.BOT` (kit, reaction time, how often it goes for critical hits, healing, loot, whether it leaves unarmored players alone), or set `enabled = false` to remove it.

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
| T | Chat |
| / | Chat with a command started |
| Q / Ctrl+Q | Drop one / drop stack |
| F5 | Toggle first / third person |

### Commands

Player commands: `/help`, `/spawn`, `/kits`, `/kit <name>`, `/rtp` (aliases `/wild`, `/randomtp`), `/warp pvp`, `/pvp`, `/stats`, `/list`.

Admin-style commands are recognised but intentionally do nothing. They reply with the usual "you do not have permission" message: `/gm0`–`/gm3`, `/gmc`, `/gms`, `/gamemode`, `/give`, `/i`, `/tp`, `/tphere`, `/time`, `/weather`, `/kill`, `/op`, `/ban`, `/kick`, `/fly`, `/heal`, `/feed`, `/god`, `/vanish`, `/clear`, `/effect`, `/enchant`, `/summon`, `/setblock`, `/fill`, `/gamerule`, `/xp`, `/speed` and more (see `src/server/Commands.luau`). Any other `/…` message gets "Unknown command" and is never shown to other players.

## Textures, sounds and animations

Minecraft's textures, sounds and models belong to Mojang/Microsoft. Uploading them to Roblox infringes their copyright and gets assets or the whole game taken down, so none are included. Instead:

- **Textures** are original 16×16 pixel art in the same style, generated in code by `src/shared/PixelArt.luau`: 29 block faces plus item, heart and armor sprites. Nothing needs uploading.
  - Block textures are drawn with Roblox's `EditableImage`, which a published game may only use with **Allow Mesh / Image APIs** switched on. If it's off, or the device runs out of image memory, blocks fall back to flat colours and block icons to coloured squares. Item sprites, hearts and armor icons are drawn from UI frames and always work.
  - To use your own uploaded images instead, map a texture key to an asset id in `Config.Textures`.
  - To edit the generated art, change `PixelArt.luau` and preview it with `luau tools/pixelart/render.luau -a all 6 > sheet.ppm` followed by `python3 tools/pixelart/ppm2png.py sheet.ppm sheet.png` (needs the standalone [Luau CLI](https://github.com/luau-lang/luau/releases)).
- **Items** in the hand and on the ground are the same sprites extruded into 3D, as in Minecraft.
- **Sounds** use sounds that ship with the Roblox client. Replace the ids in `Config.Sounds` with your own uploads.
- **Animations** are done in code: arm swings for mining and attacking (visible to everyone), the bot's walk cycle, and a first-person held item with walk bobbing.

Don't use "Minecraft" in the game's title or thumbnail. The trademark belongs to Microsoft and Roblox moderates it.

## Configuration

Everything tunable is in `src/shared/Config.luau`: world size and seed, gravity and jump height, spawn and arena size, whether PvP is on in the wilderness, combat-tag length, teleport warmup, `/rtp` cooldown, movement speeds, knockback, day length, kits, the bot, textures and sounds.

## Project layout

```
src/
  first/       ReplicatedFirst: removes the loading screen
  shared/      Config, block/item definitions, PixelArt (textures), item models, zones, remotes, sounds
  server/      World (voxel storage + generation), Structures (spawn, PvP warp), Inventory, Drops,
               Combat, Bot, Building, Teleport, Kits, Commands, Visuals, Data (DataStore), Main
  client/      Pixel (textures and icons), Ui, Hud, Chat, InventoryUi, KitsUi, Interaction
               (mine/place/attack), Controls, Effects (swings, held item, bot animation, clouds), State
  character/   Empty "Health" script that disables Roblox's default regeneration
tools/pixelart Preview renderer for the generated textures
```

The server is authoritative for everything that matters: block edits, inventories, damage, kits and teleports. Remotes are validated and rate-limited.

## Known limitations

- The world isn't saved. Each server generates a fresh world when it starts; set `Config.SEED` to make every server generate the same terrain.
- Built for keyboard and mouse. Touch and gamepad controls aren't implemented.
- There's no hunger, crafting, mobs, water, tools, shields, bows or durability yet. Stone can be mined by hand and still drops cobblestone.
- Sweep attacks aren't implemented, and fire can't be put out early.
- Ores drop coal, raw iron and diamonds, but nothing uses them yet.
- A failed DataStore load disables saving for that player's session so their real data can't be overwritten. Kit cooldowns are still enforced in memory for the rest of that server's life.
