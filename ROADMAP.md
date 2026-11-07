# Roadmap

Planned work for Hull Breach. The game is live, so this is mostly polish, balancing and new content.

## Visuals and performance
- [ ] Fix the dark spawn view on `QualityLevel = Automatic` (screenshots were taken at Level 15; low-end GPUs see much less of the set dressing)
- [ ] Test lighting and water transparency on low-end PCs and mobile
- [ ] Reduce part count from the visual overhaul in `MapBuilder` where it costs frame rate
- [ ] Confirm the third-party rust texture renders for non-developer players on a live server

## Gameplay and balancing
- [ ] Re-tune flood rates and oxygen after the run-randomization changes
- [ ] Balance creature hearing ranges per movement speed
- [ ] Tune Extended Nightmare Mode difficulty
- [ ] Add more journal clue variety for the ballast puzzle

## Co-op
- [ ] Better error handling and messaging when a reserved-server teleport fails
- [ ] Reconnect flow if a partner disconnects mid-run

## Code quality
- [ ] Rename leftover "Deep Descent" identifiers where it is safe (never DataStore keys)
- [ ] Split `MapBuilder` (2,600+ lines) into smaller modules
- [ ] Set up Rojo so `src/` syncs both ways instead of being a one-way snapshot
- [ ] Add unit tests for pure logic (endings, flood equalization) with a Luau test runner

## Community
- [ ] Fill in the Discord invite in `MonetizationData`
- [ ] Post update announcements through the Discord bot
