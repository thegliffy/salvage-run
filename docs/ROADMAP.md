# Roadmap

What exists, and the order the rest should be built in.

## Done

- [x] Seeded RNG with independent streams
- [x] JSON content pipeline with load-time reference validation
- [x] Hull grid: placement, overlap/bounds rules, adjacency synergy
- [x] `compile()` bridge from spatial layout to combat profile
- [x] Combat: turn loop, energy, draw/discard/exhaust, reshuffle
- [x] Subsystem targeting with telegraphed intents and the fizzle rule
- [x] Damage pipeline: evasion → shields → subsystem → hull
- [x] Persistent part wear written back from combat
- [x] Sector map generation (layered DAG, reachability-guaranteed)
- [x] Ship valuation with itemised receipt
- [x] Card removal: three-card part packages, one strip per part, paid in sale value
- [x] Meta state: salvage currency, part unlocks, save/load with migrations
- [x] Headless test suite (87 tests) and balance simulator with a content-aware
      pilot and card-play histogram

## Next: make it playable

The systems work but nobody can see them. In order:

1. **Combat screen.** Hand, energy, enemy panel with per-subsystem integrity
   bars, and the intent telegraph. The telegraph is the most important widget in
   the game — it must show *which subsystem* the shot comes from, or the core
   mechanic is invisible.
2. **Targeting interaction.** Tap a card, tap a subsystem. Needs to work with a
   thumb; subsystem hitboxes should be at least 48dp.
3. **Map screen.** The layered DAG, showing node types and the path taken.
4. **Shipyard screen.** Drag parts onto the hull grid. Show the compiled profile
   live so the player sees stats change as they place. Surface
   `ShipProfile.warnings` (power deficit) prominently.
5. **Salvage node screen.** List each part's three mounts and let the player cut
   one, showing the sale value it costs. `SalvageYard.options()` already returns
   everything this needs, including per-option cost.
6. **Sale screen.** Animate the receipt line by line. This is the run's payoff
   moment and deserves more polish than its complexity suggests.
7. **Meta shop.** Spend salvage on part unlocks.

## Then

- **Run save/resume.** Critical for Android — the OS kills the process whenever
  it likes. `SaveSystem` currently persists meta only. Run saves need
  write-on-every-transition with the same atomic temp-then-rename approach.
- **Content pass.** Target roughly 60–80 cards and 40+ parts before the game has
  enough variety to sustain runs. Use `--sim` between batches.
- **Balance pass.** See DESIGN.md §Open questions — the sim wins ~96%, and names
  two causes: enemies that do not scale with depth, and an over-generous
  reward-to-cost ratio. Start by keying enemy stats off sector.
- **Audio, art, juice.**
- **Steam integration.** Achievements and cloud saves via GodotSteam. See
  SHIPPING.md.
- **Android input and layout pass.** Safe areas, notches, back-button handling.

## Deliberately not doing yet

- Multiplayer of any kind
- Crew management (FTL's other half — adding it doubles the design surface)
- Procedural part generation
