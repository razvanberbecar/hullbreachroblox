# Hull Breach

A first-person atmospheric submarine horror game for Roblox, written in Luau.

You wake up as the only survivor of a crashed submarine that is slowly flooding on the ocean floor. A blind creature that hunts by sound moves through the corridors. Explore 9 sections, restore power, manage a 4-slot inventory, piece together the captain's log and reach one of 9 endings. Solo by default, with optional 2-player co-op.

**Status:** published and live on Roblox. Current work is polish, art, balancing and bug fixes (see [ROADMAP.md](ROADMAP.md)).

**Who it's for:** Roblox players 13+ who like slow-burn horror, exploration and puzzles.

## Features

- **Flooding:** each section floods at its own rate, and water equalizes through open bulkhead doors. Sealing a door is permanent.
- **Sound-based creature AI:** the creature hears footsteps, running and noise, and moves between roaming, alerted and hunting states.
- **Power system:** emergency lighting, a main generator that wakes the creature, and a ballast valve puzzle.
- **9 endings**, including 2 secret ones tied to the captain's journal pages.
- **Run randomization:** item and journal positions, creature start, flood rates and the ballast order change every run.
- **Co-op:** the public server is a router menu; runs happen in reserved servers with shared fate and pooled key items.
- **Meta:** save slots, endings log, leaderboards (OrderedDataStores) and cosmetic-only monetization (no pay-to-win).

## Built with

- Roblox Studio and Luau
- Roblox services: DataStoreService, OrderedDataStores, TeleportService, MemoryStoreService, CollectionService
- Python ([discord.py](https://discordpy.readthedocs.io/)) for the community Discord server tooling in `DiscordServer/`

## Repository layout

```
src/                   Snapshot of all game scripts, laid out by Roblox service
  ServerScriptService/   Bootstrap + server managers (Map, Flood, Oxygen, Power, Creature, Endings, ...)
  StarterPlayer/         Client scripts (camera, flashlight, HUD, water rendering, audio, menus)
  ReplicatedStorage/     Shared data modules (sections, items, creature, endings, config, networking)
  ReplicatedFirst/       Intro screen
DevLog/                Dated work log and before/after screenshots of visual changes
DiscordServer/         Scripts that build and post to the game's Discord server
```

File suffixes follow Roblox conventions: `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript.

## How to run

The live game is built in Roblox Studio; `src/` is a snapshot of every script exported from the place.

1. Open Roblox Studio and create a new Baseplate place.
2. Recreate the script tree from `src/` under the matching services (or sync it in with a tool such as [Rojo](https://rojo.space/)).
3. Press **Play**. `ServerScriptService/Server/Bootstrap` starts every manager in order, and `MapBuilder` builds the whole submarine from code.

Some features only work on a published server: DataStores (saves, leaderboards), TeleportService and MemoryStore (co-op).

### Discord tools

```bash
cd DiscordServer
pip install -r requirements.txt
```

The bot token is read from a git-ignored `bot_token.txt`. See [DiscordServer/README.md](DiscordServer/README.md).

## Credits

Designed and developed by Razvan Berbecar and David Berbecar.

## License

Code is released under the [MIT License](LICENSE). Audio comes from free Roblox Creator Store sound effects and is not covered by this license.
