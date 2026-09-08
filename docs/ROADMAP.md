# Roadmap

What exists, and the order the rest should be built in.

## Done

- [x] Seeded RNG with independent streams
- [x] JSON content pipeline with load-time reference validation
- [x] Typed slot loadout (4 weapon / 3 hull / 4 utility) with swap support
- [x] `compile()` bridge from loadout to combat profile
- [x] Ship improvements: slot and stat upgrades, separate from parts
- [x] Tiered battle rewards with field-repair skip and jettison
- [x] Combat: turn loop, energy, draw/discard/exhaust, reshuffle
- [x] Soft subsystem targeting + hull as primary target; telegraphed intents
- [x] Damage pipeline: evasion → shields → subsystem → hull
- [x] Persistent part wear written back from combat
- [x] Sector map (StS-style layered DAG, ~15 stops, ~70/10/10/10 mix)
- [x] Map / combat / shop / chest / reward / sale screens
- [x] Ship status overlay (slots, power budget, deck, painted ship view)
- [x] Power-budget / deficit UI on rewards and ship status
- [x] Ship valuation with itemised receipt
- [x] Card removal: three-card part packages, one strip per part, credits + sale penalty
- [x] Meta state: salvage currency, part unlocks, save/load with migrations
- [x] Title-screen Salvage Yard (meta unlock shop)
- [x] Headless test suite (215 tests) and balance simulator with a content-aware
      pilot and card-play histogram

## Next

1. **Balance / stalls.** ~37% win rate on 200 sim runs; a large share of losses
   are turn-guard stalls on shield-regenerating enemies. Fix shield stripping /
   regen first, then dead content the histogram names.
2. **Run save/resume.** Critical for Android — the OS kills the process whenever
   it likes. `SaveSystem` currently persists meta only. Run saves need
   write-on-every-transition with the same atomic temp-then-rename approach.
3. **Content pass.** Target roughly 60–80 cards and 40+ parts before the game has
   enough variety to sustain runs. Use `--sim` between batches. Current scaffold
   sits around 31 cards / 15 parts / 4 enemies / 14 improvements.
4. **Starter-hull unlocks.** Give early meta a visible power curve without
   abandoning additive pool unlocks.
5. **Audio, art, juice.** Redistributable card icons / portraits / module
   icons now ship (see ASSETS.md); remaining polish is audio and juice.
6. **Steam integration.** Achievements and cloud saves via GodotSteam. See
   SHIPPING.md.
7. **Android input and layout pass.** Safe areas, notches, back-button handling.

## Polish backlog (not blockers)

- Quieter scene-exit disconnect logging if engine quirks remain after mitigations
- Enemy scaling with map depth (matters more as content grows)
- Touch hitboxes ≥ 48dp on subsystem / hull targets

## Deliberately not doing yet

- Multiplayer of any kind
- Crew management (FTL's other half — adding it doubles the design surface)
- Procedural part generation
- Bringing back the spatial hull grid
