# Development log

Working notes: how the scaffold was built, what broke, and what each failure
taught. DESIGN.md records *what* was decided and why; this records *how* it was
arrived at, including the parts that were wrong first.

Newest entries at the bottom.

---

## 2026-09-05 — Research and engine selection

**Question asked:** FTL-like roguelike deckbuilder where you change your deck by
upgrading your ship, fighting to a final boss, then selling the ship for
meta-currency that unlocks parts. Steam and Android as primary platforms.

### What was checked

- Engine comparison for a 2D roguelike deckbuilder targeting Steam + Android
  with a solo developer
- Steam integration options for Godot 4 and their current maintenance status
- Comparable games, for what the genre has already solved
- Slay the Spire's balancing approach, for how a solo dev can substitute for
  play metrics they will not have

### Findings that changed decisions

**GodotSteam migrated off GitHub.** The `github.com/GodotSteam/*` repositories
were archived July–September 2026. This is a move to `codeberg.org/godotsteam/
godotsteam`, not an abandonment — releases were landing there the day before this
session. A search lands you on the dead repo first, so this is written down in
SHIPPING.md to stop it being rediscovered painfully later.

**Prior art is strong and specific.** *Luck Be a Landlord* is a Godot roguelike
deckbuilder shipped to Steam, Android, iOS, Switch, PlayStation and Xbox — direct
evidence the engine handles this exact genre and platform spread. *Cobalt Core*
and *Breachway* are the closest design comparables.

**Slay the Spire was balanced on play metrics at a scale a solo dev cannot
match.** This is the origin of the whole simulator approach: if you cannot get
ten thousand players, get ten thousand simulated fights.

### Decisions taken

Three forks were put to the user rather than assumed, because each would have
produced materially different code:

| Decision | Chosen | Over |
|---|---|---|
| Engine | Godot 4 + GDScript | Godot + C#, Unity 6 |
| Combat | FTL-style enemy subsystem targeting | Cobalt-Core positional lanes, abstract StS |
| Ship model | Hybrid: spatial grid out of combat, flat stat block inside | Pure slot list, pure spatial |

Godot 4.7.2 was pinned as the current stable. No engine was installed on this
machine, so a binary was downloaded purely to verify the work.

---

## 2026-09-05 — Scaffold

### Build order

Data and rules first, UI last. Everything was written to be runnable with no
scene tree, so it could be verified before any UI existed:

1. Autoloads — event bus, seeded RNG, content database, save system
2. Typed definitions parsed from JSON content
3. Hull grid and the `compile()` bridge to a combat profile
4. Combat — turn loop, effect resolver, enemy AI, deck
5. Run state and map generation
6. Meta — valuation and unlocks
7. Headless test suite and balance simulator

### The one architectural rule

`CombatController` is a `RefCounted`, not a `Node`, and nothing in the
resolution path awaits. That single constraint is what makes a full run simulate
in milliseconds. Everything else — the event bus, the derived deck, the
`compile()` seam — follows from wanting the game to be testable without being
played.

### Verification

Nothing here was "looks right". Each layer was run:

```bash
godot --headless --path . --import                              # parses, registers classes
godot --headless --path . res://tests/headless.tscn -- --test   # assertions
godot --headless --path . res://tests/headless.tscn -- --sim N  # balance
godot --headless --path . --quit-after 3                        # boot scene
```

First green run: **65 tests**.

---

## 2026-09-05 — Findings log

Each of these was found by running something, not by reading code.

### 1. RefCounted cycle leaked every combat

`CombatController` held `EffectResolver`, which held a strong reference back.
Godot reported 90 leaked ObjectDB instances at exit. Fixed with a `WeakRef` and
a property getter. Worth noting because GDScript has no cycle collector — any
two RefCounted objects pointing at each other leak silently, and only the exit
warning tells you.

### 2. A fully disabled enemy was unkillable *(the important one)*

The very first simulator run returned **0% win rate, all 300 runs stalling at the
first enemy**. Reading the fight log: the pilot destroyed every enemy subsystem,
at which point `targetable_systems()` returned nothing, no attack card had a legal
target, and the fight ran forever.

In FTL you can always just shoot the hull. The rule is now that destroyed
subsystems stay targetable — the damage pipeline finds no integrity to absorb
and spills the full amount into the hull.

This is the clearest argument for the simulator existing at all. The hole was
invisible in the code and would have survived to the first playtest.

Win rate after the fix: 82%.

### 3. Shield scoring made the pilot turtle forever

After the pilot was rewritten to evaluate cards properly (see below), 70 of 300
runs stalled. The pilot scored a shield card at its printed number, but the
resolver caps gains at `max_shield` — so an 8-shield card that could only give 2
still looked like the best play in the game.

### 4. Absorbed damage scoring zero created a deadlock

The subtlest one. Attacks against a shielded ship scored ~0.1, because the
pilot counted only damage that got *through* the shield pool. So it refused to
attack. So the shields never came down. So attacks kept scoring zero.

Stripping the shield pool **is** progress, and now scores at 0.5 per point.

### 5. Cantrip riders outscored the entire game

With card draw weighted at 3.5, a 1-cost "gain 4 shield, draw 1" beat every
attack card. Draw is now 2.0.

### 6. Free parts made the win rate meaningless *(self-inflicted)*

To exercise more content, the simulator was made to install a part between
fights. This pushed the win rate to 98% — the ship grew to eleven parts and a
26-card deck against a fixed enemy ladder. The number had stopped measuring
anything.

Parts are now bought out of run credits, so growth is gated by the economy the
game actually has.

---

## 2026-09-05 — Card removal

Added after a design discussion, not up front. Worth recording because the
architecture forced the shape of the mechanic.

**The constraint:** the deck is *derived*. `compile()` rebuilds it from part
grants on every ship change, so a removal recorded anywhere but on the part is
silently undone the next time the player installs anything. There is a
regression test that installs an unrelated part after a strip specifically to
catch this.

**The shape:** every part grants three cards; each part can have exactly one
stripped, permanently. Because the cap is a single `int` on `PartInstance`
rather than a list, thinning is limited by construction — a ship can never fall
below two thirds of its cards, so no escalating purge price is needed.

**The cost:** paid in the ship's eventual sale value rather than credits. It
trades meta-progression for run strength, and the consequence lands on the
end-of-run receipt where the player is already reading outcomes.

Content was reworked to match: 15 new cards, all twelve parts moved to designed
three-card packages rather than three copies of one card.

---

## Operational notes

Things that cost time and would cost it again.

**A parse error in a scene script looks like a hang, not an error.** `_ready()`
never runs, so nothing calls `quit()`, and Godot idles forever with no output.
If a headless run times out with an empty log, suspect a parse error first.

**`--check-only --script` does not load autoloads.** It will report
`Identifier not found: Database` for perfectly valid code. Useful for syntax
only; the scene run is authoritative.

**`Array.shuffle()` is banned in this project.** It uses the global RNG and
silently breaks run reproducibility. Use `Rng.shuffle()`, which takes a named
stream.

**Editing code with anchored text replacements is fragile.** One replacement in
this session deleted the anchor a later replacement depended on, and the
function it should have inserted simply never appeared — surfacing as the parse
hang above. Verify insertions landed rather than trusting that the script ran.

---

## 2026-09-05 — Playable PC demo

Built the UI against the existing EventBus / CombatController seam, so no
gameplay code changed. Screens are constructed programmatically rather than in
`.tscn` files: hand-authoring complex scene files is error-prone, and code-built
containers are far easier to iterate on.

**Assets.** Of 79 purchased packs, four were right for a space deckbuilder:
sci-fi skill icons for card art (colour keyed to card kind, so a hand reads as
shapes before words), character icons as enemy portraits, and the Exo typeface.
Provenance and the licensing problem are recorded in ASSETS.md.

The purchased cyberpunk HUD panels were **rejected**: they are fixed-shape with
an asymmetric notch, so stretching them to arbitrary sizes mangles the art and
9-slicing cannot preserve the notch. Panels are Godot styleboxes matched to the
same palette instead.

**Verification.** Headless cannot render, so `ShotRunner` drives a whole run
under `xvfb` and captures each screen. It doubles as an integration test for the
flow: if any screen deadlocks it never reaches the sale. It also proved the
*exported* build works, not just the editor run.

### Findings

**7. `pkill -f "godot --path"` killed the shell running it.** The pattern matched
the calling bash process's own command line, which contained that text later in
the script. Presented as mysterious exit-code-144 failures. Use `pkill -x godot`.

**8. A screenshot raced the process that was writing it.** `ls` on the output
directory ran while the capture was still in flight and reported the directory
missing. The files were fine.

**9. The receipt captured mid-animation.** The sale screen tallies on wall-clock
timers, so waiting a fixed number of *frames* under llvmpipe was not equivalent.
Wait on time, not frames, when the thing you are waiting for uses a timer.

---

## 2026-09-05 — Slots replace the grid

The spatial hull grid is gone. Parts go into typed slots — 4 weapon, 3 hull,
4 utility — and picking up a laser attaches a laser.

**Why.** The sim made the case: at a typical endgame ship the grid sat **61%
empty**, so space never bound, and only 3 of 12 parts used the adjacency rule
that was the grid's one non-accounting job. It was costing a whole drag-and-drop
shipyard screen and buying nothing. Cutting it *deleted* work — that screen came
off the roadmap entirely.

This reversed the hybrid grid/abstract model chosen at the start. That was a
reasonable call on the information available then; the simulator is what showed
the spatial half was not earning its place.

**The hull generates the power now, not a module.** No part has `power_gen`, and
there is a test asserting it stays that way. The reactor parts' energy cards
moved onto a Power Relay, so the burst-energy playstyle survives without every
build being taxed a slot for a mandatory reactor. Synergy re-keyed from "adjacent
to system X" to "ship has system X" — same combo design, discoverable without a
layout screen.

**Rewards were rebuilt** around enemy tier: regular enemies drop credits and a
part offer, mini-bosses add a common/uncommon improvement, sector bosses drop a
rare part and a rare improvement. Improvements are a new class that fills no slot
and grants no cards — they change the ship itself. Declining a part offer lets
you jettison an installed one, which is the ship-level counterpart to stripping a
card.

### Findings

**10. Splicing functions by text anchor ate the next function's doc comment.**
A range replacement ran from one marker to the next and swallowed the comment
directly above the following function — which a *later* replacement used as its
anchor, so that edit silently did nothing and the function was never inserted.
Surfaced as the parse-hang from finding 7's era. Verify insertions landed.

**11. Trailing `func ` from a splice is a parse error, not a merge.** Ending a
replacement block with `func ` to join the following line does not work when the
text is split on newlines: it becomes its own line and Godot reports "Expected
function name after func".

### Result

Balance moved from a meaningless 96% to **50%**, with deaths spread across the
mini-boss and boss rather than piling on one enemy. The simulator is finally a
sensitive instrument.

Remaining defect: ~15% of runs stall against shield-regenerating enemies. Either
enemy `shield_regen` is too high relative to card damage, or the player lacks
enough shield-stripping tools. Content, not code.

---

## Where it stands *(superseded — see entries below)*

```
112 tests passing
200-run sim: ~50% win rate, 27 distinct cards played
Playable PC demo: title -> combat -> reward -> salvage yard -> sale
```

The systems work, are tested, and are playable end to end.

**Open defects, all content rather than code:**

- **Stalls.** ~15% of runs hit the turn guard against shield-regenerating
  enemies. Highest-priority fix.
- **Dead content.** The play histogram flags Ammo Drum, Salvo and Dead Weight as
  near-unplayed, and notably Breach Missile — a 150-salvage unlock that loses to
  a 1-cost Laser Burst at almost every board state. A costed unlock nobody plays
  is worse than no unlock.
- **Enemies do not scale with depth,** which will matter once the sector map
  replaces the fixed three-fight ladder.

Not built: the sector map, the ship screen, the meta unlock shop, audio, and run
save/resume — which is a launch blocker for Android. See ROADMAP.md.

---

## 2026-09-05 — Sector map, soft combat, ship fantasy

Replaced the fixed three-fight ladder with a Slay-the-Spire sector map:
start → ~15 stop layers → boss, weighted ~70% combat / 10% shop / 10% elite /
10% chest. `MapGenerator` guarantees forward-only edges and full reachability.

**Combat redesign.** Hull is the primary target (`&"hull"`). Enemy soft systems
have low HP and auto-repair (+2) if left undamaged — temporary control, not a
mandatory fizzle hunt. The celebrated "cancel their shot or die" loop made every
fight feel the same; soft control keeps EMP useful without forcing it.

**Rewards.** Skipping a part offer field-repairs 15% of max hull (was
jettison-only as the interesting skip). Jettison remains available separately.

**Ship fantasy.** Painted hull art (`assets/ships/salvager-hull.png`) with
`ShipView` bolting modules onto hardpoints. Ship status overlay on the map
(slots, deck, power, ship view). Subsystem blurbs in combat. Power deficit when
part draw exceeds hull output, cut into energy/turn for the whole run.

Narrative framing on title and sale screens: steal a ship, sell what survives.

Balance after the longer map + soft combat landed around **~31%** win rate
initially (accepted as intentionally tougher than the old 50% ladder figure).

---

## 2026-09-05 — Unlock shop, power UI, hull art

Title → **Salvage Yard** meta unlock shop. Unlocks put parts into the reward
pool; they do not grant the part. Starter weapon is Burst Laser; Missile Rack /
EMP Projector / Carrion Lance (and other gated parts) cost salvage.

Power budget panel on the reward screen with per-offer energy preview so overdraw
is visible before you bolt something on.

---

## 2026-09-06 — Ship stats in combat + disconnect mitigations

Ship status extracted to `ShipStatusOverlay` and wired into **combat** as well as
the map (SHIP button + compact evasion / shield / power / deck strip on the
player panel).

Release builds were spamming
`Attempt to disconnect a nonexistent connection … tree_exited, callable: ''`.
Mitigations: combat log no longer awaits frames to scroll; hand cards are
`remove_child`'d and set to ignore mouse before `queue_free`; card hover lift
removed (it fought HBox layout); scene-exit awaits check `is_inside_tree`.
Residual empty-callable disconnects may still be a Godot 4 Window/focus quirk in
release exports — track, do not thrash.

### Result

```
215 tests passing
200-run sim: ~37% win rate
Playable PC demo: title → unlock shop → map → combat/shop/chest → rewards → sale
```

**Open defects (mostly content):**

- **Stalls.** Still a large share of sim losses against shield-regenerating
  gunship / dreadnought. Highest-priority balance fix.
- **Dead content.** Histogram still names rarely-played cards; dud status cards
  remaining unplayed is intended.
- **Run save/resume** still missing — Android launch blocker.
- **Audio / Steam / enemy depth scaling** not started.

See ROADMAP.md.

---

## 2026-09-08 — Card rebalance + 3×10 sectors

Kyle's cards-by-module sheet is the new base/upgrade table. Shared cards
(laser_burst, armor_brace, dead_weight, raise_deflector, …) changed once.
Upgrades can now drop Exhaust (`upgrade.keywords: []`) so Ammo Drum+ and Divert
Power+ match the sheet. Plasma Bolt is 2-cost with a +1 energy rider; Ion Haze
is 0-cost system damage + self-harm (kept `kind: status` as the Plasma Cycler
dud). Execute Protocol only gains homing on the upgrade.

The run is three sectors of ~10 stops + boss. Sector 1 boss is the gunship
(still a boss payout); sector 2/3 bosses are the dreadnought; sector 3 is the
finale. Valuation uses the sector you actually reached. The sim walks those
maps instead of a canned 7-fight ladder.

**Shepherd** hull (unlock 650): 1 weapon / 3 hull / 6 utility, Deflector Mk I,
and a Drone Launcher. Two **empty** bays; launch Attack (red) or Shield Charger
(blue) with cards. Occupied drones tick once at the start of your turn after
shield regen and before the draw. Overcharge activates occupied drones twice
this turn. Offline `drones` subsystem silences them.

---

## 2026-09-08 — Static Coil (uncommon utility)

Kyle's Static Coil is a tier-2 utility in the Repair Bay band: `support`,
integrity 8, mass 2, power_draw 1, base_value 100, unlock 175. Grants two
existing Afterburners plus a new uncommon attack, Static Buildup.

**Play count.** Combat had no play counter. `CombatController.cards_played_this_turn`
increments after a successful play and resets at the start of each player turn.
`EffectResolver.scaled_amount` uses `count + 1` so the resolving card is included
— same number the sim sees when it scores the card before playing it. First card
of the turn deals 2; after two Afterburners it deals 6.

**Cost / upgrade.** 1 energy, like the other setup-dependent uncommon attacks
(Feedback Spike, Vulture Strike). The Afterburners are 0-cost, so a 1-cost
finisher still fires after a long cheap chain; 2-cost would compete with Salvo
for leftover energy on the turn the card asks you to fill. Upgrade is 3× cards
played (50% bump), not a flat bonus — the identity is the multiplier.

---

## 2026-09-08 — Self-destruct

Kyle asked for a button that ends the run. **SELF-DESTRUCT** lives on the SHIP
STATUS footer (map and combat share that overlay) as a hostile outline, so it
cannot be mistaken for CLOSE and cannot fire from a single tap.

Confirm is a second panel: CANCEL / dim click dismisses it; **SCUTTLE** calls
`Game.self_destruct()` → `RunState.scuttle()` (`alive = false`) → `_end_run()`.
That is the hull-loss pipeline — `Valuation.appraise` applies the 40% wreck
recovery and the sale screen reads as a towed wreck, then back to title.
Mid-combat scuttle skips `finish_combat` so it cannot land on a reward screen.

---

## 2026-09-09 — Card FX polish

Play / draw / shuffle are still ghosts — combat does not wait. The old
`_card_back()` was a 30×42 StyleBox chip, so reshuffle read as blank pips
vanishing mid-flight. Play also aimed the discard at `discard_pos - CARD_BACK
* 0.5` while the ghost's pivot was the full card centre, so the visual landed
about a card-height off the pile.

Canonical back path is `assets/ui/card_back.png` (not `assets/frames/` — that
folder is kind faces). AD industrial plate + cyan wrench ships there.
`CardFx` uses a keep-aspect TextureRect, pile thumbs share it, and missing art
still falls back to a framed panel.

Timings: play 0.26/0.22 CUBIC+BACK 1.12× → 0.40/0.36 QUINT/SINE 1.06× with a
slight arc; draw 0.28 → 0.40; shuffle 0.34 random chaos → 0.52 leftward ribbon,
fade only after landing. Hand fan `TWEEN_TIME` 0.12 BACK → 0.20 CUBIC.

---

## 2026-09-09 — Calibrate (fourth card)

Every part now grants four cards. The new one is a cost-3 Exhaust tech that
stamps a fight-long buff — usually scoped to cards from that mount, with
Evasion Calibrate ship-wide and Drone Overclock on occupied ticks. Shared defs
(`hardpoint_optimization`, `armor_brace`-style) keep the JSON small.

`CardInstance.source_part_uid` is the scope key. Compile writes a parallel
`deck_sources` array so two Burst Lasers do not buff each other. Strip floor
is three quarters, not two thirds. Icons are filename-only until art lands.

