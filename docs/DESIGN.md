# Design notes

Rationale for decisions already baked into the scaffold. Where a choice is still
open, it says so.

---

## 1. The ship is the deck

The single rule the whole game hangs off. The player has no deck-editing screen;
they have a shipyard. Parts grant cards, and removing a part removes its cards.

**Why:** in most deckbuilders, deck and character progression are two separate
currencies that have to be balanced against each other. Fusing them means every
decision is legible — "do I want these cards?" and "do I want this hardware?" are
one question. It also makes the run-end sale meaningful, because the thing you
sell is the thing you built.

**Cost:** you lose fine-grained deck control. That is addressed by the strip
mechanic in §8, which removes one card from a specific part rather than offering
a generic purge — the narrow tool is the right one here, because swapping parts
already thins the deck on its own.

## 2. Typed slots, not a spatial hull

The ship is a set of typed slots — **4 weapon, 3 hull, 4 utility**. Pick up a
laser and it attaches. There is no layout to arrange.

This replaced a spatial hull grid, and the sim is why: at a typical endgame ship
the grid sat **61% empty**, so space never bound, and only three of twelve parts
used the adjacency rule that was the grid's one non-accounting job. It was
costing a whole drag-and-drop shipyard screen and buying nothing.

**What limits a ship instead** — three soft costs, none spatial:

| Cost | Effect |
|---|---|
| Power | draw beyond hull output cuts energy every turn |
| Mass | heavier ships dodge worse |
| Deck | every part adds three cards, so a big ship draws badly |

None of them ever *refuse* a part. Slots are the only hard limit, and their job
is to shape **what** you carry, not how much. Deck dilution is the real
governor, and it is the deckbuilder-native one: a big ship isn't blocked, it's
clogged.

**The hull generates the power, not a module.** No part has `power_gen`. Reactor
output is a property of the ship, raised by improvements — so energy is never a
slot tax, and there is no mandatory part every build has to carry. Power
overdraw is surfaced in UI as a **deficit** so the soft cost is readable before
the next fight.

Synergy is keyed to whether the ship **has** a system, not to where a part sits.
Same combo design, discoverable without a layout screen.

`ShipLoadout.compile() → ShipProfile` remains the only bridge to combat.

## 3. Soft subsystem control, hull as the primary target

Enemies announce their next move and the subsystem it comes from. Knock that
subsystem offline and the shot cannot fire this turn; chip it and
`EnemyBrain.scaled_effects()` softens the hit.

**What changed:** an earlier design treated fizzle as the *celebrated* win
condition — destroy weapons or die trying. That made every fight a mandatory
hunt and made hull shooting feel wrong. Soft systems now have low HP and
auto-repair if left alone; they are optional control. **Hull is always a legal
finish target**, and the combat UI highlights it as such.

**Why keep soft control at all:** without it, "shoot weapons" vs "shoot hull" is
just arithmetic. With it, EMP and suppression still have a job raw damage cannot
do — buying a quiet turn — without forcing that path every fight.

**Tuning levers:**

- Soft system HP and enemy `system_repair` (auto-repair when undamaged)
- The `0.5 + 0.5 * efficiency` curve in `scaled_effects()`
- Player system regen (rare improvement only — Damage Control Nanites)

**Drone bays.** The Drone Launcher grants two **empty** slots, not a pre-filled
wing. Combat starts vacant. Launch cards fill a bay as Attack (red) or Shield
(blue); Overcharge makes occupied drones activate twice immediately. Launch is
refused when both bays are full. Offline `drones` silences ticks and overcharge.

**Tick phase** (`CombatController.begin_player_turn`), in order:

1. Energy refills to max
2. **Virus ticks** if this combatant is infected (see below)
3. Subsystems tick (auto-repair, suppress clocks)
4. Overshield expires
5. Shield regen fills toward capacity
6. **Occupied drones activate once each** — Attack deals homing system damage;
   Shield gains shield (excess is overshield)
7. Draw for the turn

Drones launched this turn sit until the **next** start-of-turn tick, unless you
Overcharge them the same turn.

**Virus** is a hull-side poison analog. Counters live on the **combatant**
(`Combatant.statuses["virus"]`), not on a subsystem. Each tick deals **1 hull
per counter**, then **reduces counters by 1** (damage then decay). That hull
hit skips evasion and shields.

Tick timing: **the infected combatant's turn start** — player virus in
`begin_player_turn` after energy refill; enemy virus in `_run_enemy_turn`
before they act, so a lethal tick can win the fight without a shot. The
opponent is not also ticked on the other side's turn (no double-tick).
Signal Injector (`signal_injector`, uncommon / tier 2) is the first part that
applies it. Contagion Array (`contagion_array`, rare / tier 3) is the heavy
follow-up and reuses Firewall Bypass. Persistent Strain (`persistent_strain`,
uncommon improvement, flag `virus_no_decay`) keeps the damage tick but skips
decay on virus the player applied to the enemy — Super Capacitor's flag pattern.

**Pure Payload** (`pure_payload`, rare improvement, flag `damage_as_virus`):
player outgoing damage that would hit hull or systems is converted **1:1 into
virus after the evasion roll** (a miss still misses). Shields, subsystems, and
hull are not touched by that shot. Self-damage (`damage_self_hull` / overheat)
is not converted. Drones and pierce shots convert the same way.

Subsystem targeting while the flag is on: the player cannot aim **damage** at
enemy subsystems. Cards with `suppress_system` may still pick a system
(Computer Spike, EMP Pulse, Weak Point) so suppress lands; any damage on those
cards still becomes virus on the hull, not system integrity. Damage-only
system cards (Laser Burst, Infected Burst) are hull-only. That mixed rule is
the cleaner split — suppress still has a job, conversion stays on the shared
`_deal_damage` path.

Related commons: Probe Tip (`probe_tip`) adds +1 to the first virus application
each combat; Signal Noise (`signal_noise`) gives infected enemies −5 evasion.

## 4. Damage pipeline

One path, in `EffectResolver._deal_damage()`:

```
evasion roll → [Pure Payload: become virus] → shields → subsystem integrity → hull spill
```

- `pierce` skips shields
- `homing` skips the evasion roll
- `unavoidable` skips evasion and is used for self-damage
- overflow past a subsystem continues into the hull at full value
- a destroyed subsystem absorbs nothing, so shots pass straight through
- explicit `&"hull"` targets skip the subsystem step

That last-but-one point is a rule, not an accident. It was added after the
balance sim found that a fully disabled enemy became unkillable and fights
stalled forever. There is a regression test for it.

## 5. Content in JSON, systems in code

`content/*.json` holds every number a designer would want to change. Structural
things — hull layouts, the valuation formula, the damage pipeline — live in code.

**Why:** Slay the Spire's team balanced on play metrics at a scale a solo dev
cannot match. The substitute is being able to change a hundred numbers in one
pass and re-run 10,000 fights in a few seconds. JSON diffs cleanly in git, can be
generated by scripts, and never requires opening the editor.

**Cost:** no editor autocomplete on content, and typos become runtime problems.
Mitigated by `Database._validate_references()`, which fails loudly at load for
dangling card ids and intents that name systems the enemy does not have.

## 6. Seeded, streamed RNG

Every random decision goes through `Rng`, which partitions randomness into named
streams (`map`, `combat`, `reward`, `shop`, `enemy_ai`).

**Why streams:** with one shared stream, drawing one extra card shifts the map
layout and every subsequent roll. Runs stop being reproducible the moment
anything changes, which destroys both bug reports and the simulator's ability to
A/B a balance change against a fixed set of seeds.

`Array.shuffle()` is banned — it uses the global RNG. Use `Rng.shuffle()`.

## 7. Combat is not a Node

`CombatController` is a `RefCounted`. It can be constructed and run to completion
with no scene tree. UI observes through `EventBus` and never drives logic.

**Why:** it is what makes `--sim` possible at ~5ms per full run. A deckbuilder
that cannot be simulated in bulk gets balanced by vibes.

**Constraint this imposes:** no `await` anywhere in the resolution path. Effects
resolve synchronously and emit an ordered event stream; animation replays that
stream afterward. If you ever need combat logic to wait on an animation, the
answer is to make the animation wait on the event, not the reverse.

## 8. Card removal: strip a mount

Every part grants **three** cards, and each part can have **exactly one** of them
stripped, permanently, for the rest of the run. The service lives at the store.
It costs **run credits** that scale with how many mounts you've already stripped
this run, and it still cuts that part's **sale value** by 25%.

**Credit formula.** `40 + 25 × strips_already_done`, where `strips_already_done`
is the count of currently installed parts with `is_stripped()` before this
strip. First strip 40, second 65, third 90. The store refuses (and disables the
buttons) if `run.credits` cannot cover it. Charge lives in `SalvageYard.strip()`
so every caller — shop UI, leftover salvage screen, sim — hits the same path.

**Why one per part:** thinning is capped by construction. A ship can never fall
below two thirds of its cards, so there is no degenerate five-card deck. The
limit is a rule the player can see. The escalating credit cost is the *soft*
pressure against stripping every mount, not a substitute for that floor.

**Why it must live on `PartInstance`:** the deck is *derived*. `compile()`
rebuilds `ShipProfile.deck` from part grants on every ship change, so a removal
recorded anywhere else is silently undone the next time the player installs
anything. `PartInstance.stripped_index` is the only sanctioned place, and
`compile()` reads `granted_cards()` rather than `def.grants` to honour it. There
is a test for exactly this.

**Why credits *and* sale value:** credits make thinning compete with buying
parts — the same purse, two uses, a real mid-run choice. The 25% sale-value
penalty still hits meta-progression and still surfaces on the end-of-run
receipt, so you are also cutting up the ship you intend to sell. Paying only
in sale value made strips free during the run; paying only in credits would
let a rich run thin the deck with no yard consequence. Both costs are load-
bearing.

**Content shape.** The three cards are a designed package, not three copies:

- *Teaching parts* (tier 1) run two core cards plus a clear dud, so the first
  strip is satisfying rather than agonising. The duds use `kind: "status"`,
  which gives drawback cards a home without needing a curse system.
- *Choice parts* (tier 2–3) run three cards pulling in different directions, so
  stripping declares what the ship is for.

**Consequence:** removal is load-bearing, not optional. Seven parts is a 21-card
deck, which cycles sluggishly at 5–6 draws a turn. Stripping is what keeps deck
size honest as a ship grows.

## 9. The simulator's pilot

`tests/headless.gd` scores cards from their **effect ops**, not from a list of
card names, so new content is evaluated the moment it is added and cards the
pilot never reaches for show up in the play histogram as dead content.

The weights encode a *reasonable median player*, not an optimal one. The point
is a stable yardstick: a change in the win rate should mean the numbers moved,
not that the bot got cleverer. It understands soft control —
`FIZZLE_BONUS` still values silencing a telegraphed subsystem — but also scores
direct hull damage, matching the live targeting model.

Three scoring rules were not obvious, and each was found by watching the sim
deadlock rather than by reasoning about it:

- **Shield gain must be capped by remaining shield room.** The resolver caps
  gains at `max_shield`, so scoring a card's printed number made every defensive
  card look far better than it was. The pilot turtled forever.
- **Damage absorbed by shields still counts.** Scoring it at zero made attacks
  on a shielded ship worth nothing, so the pilot refused to attack at all, so
  the shields never came down. A self-fulfilling deadlock.
- **Cantrip riders must not dominate.** With draw weighted at 3.5, a 1-cost
  "gain 4 shield, draw 1" outscored every attack in the game.

The simulator also buys parts between fights out of run credits. Handing them
out free was tried first and pushed the win rate to 98%: the ship outgrew the
enemy ladder and the number stopped measuring anything.

## 10. Rewards scale with the fight

Victory pays out hardware, never cards directly — the deck is downstream of the
ship, so a part *is* the card reward.

| Enemy | Payout |
|---|---|
| Regular | credits + a part offer |
| Mini-boss | credits + a part offer + a common/uncommon **improvement** |
| Sector boss | credits + a **rare** part offer + a rare improvement |

**Improvements** are a separate class from parts: they fill no slot, grant no
cards, and change the ship itself — more power, more hull, another slot. Keeping
them distinct means the two reward types never compete for the same decision.
Parts are how the deck grows; improvements are how the ship's capacity to carry
parts grows. Restricting them to tough fights / chests is what makes an elite
worth seeking out rather than routing around.

**Skipping a part is a real choice.** Skip the offer and you **field-repair 15%
of max hull** (or leave with a full hull unchanged). You may also **jettison** an
installed part: the slot frees up and all three of its cards leave the deck.
That is the ship-level counterpart to stripping a single card.

## 11. The sector map

Three sectors (acts): each is start → **10 stop layers** → boss, as a
left-to-right layered DAG (`MapGenerator`). Beating a sector-1 or sector-2 boss
pays boss rewards, then generates the next sector. The **sector-3 boss is the
final**, run-ending fight. Node weights on each sector are ~70% combat / 10%
shop / 10% elite / 10% chest. Edges only go forward one layer; every node is
reachable.

Enemy ladder reuses the existing roster rather than a new bestiary:

| Sector | Regulars | Elites | Boss |
|---|---|---|---|
| 1 | scouts, then raiders | gunship | gunship |
| 2–3 | raiders | gunship | dreadnought (final in 3) |

Boss *payouts* still key off node type, so the act-1 gunship boss pays rare loot
the same way the dreadnought does. Valuation uses the sector you actually
reached — no more faking "sector 3" at the sale.

**Why StS-shaped:** the fixed three-fight ladder could not express route
choices (shop vs elite vs safe fights). Three shorter sectors give a mid-run
boss beat and a true finale without stretching one map to session-breaking
length.

## 12. Meta unlocks are additive

`MetaState` unlocks parts into the *pool* rather than granting them directly.
The title-screen Salvage Yard is the spend surface. Starter parts begin unlocked;
gated weapons (Missile Rack, EMP Projector, Signal Injector, Contagion Array, Carrion Lance, …) cost salvage.

**Why additive:** more variety next run, not a flat power curve. Early unlocks
can still feel weak — starter-hull unlocks remain an open question (§Open).

---

## Open questions

Genuinely undecided, listed so they do not get decided by accident.

**How punishing should part wear be?** Currently destroying a subsystem wears its
parts to zero, which removes their cards for the rest of the run unless repaired.
That may be too swingy — a mid-run weapons loss can be unrecoverable. Options:
partial wear instead of total, or cheap field repairs between every node.

**Starter-ship unlocks.** Brawler is free, Tank (450) and Shepherd (650) are
the first hull unlocks. More hulls can still be added without breaking additive
pool unlocks.

**Balance.** The simulator now walks the live 3×10 map, so the old ~37% figure
(a canned 7-fight ladder) is not comparable. Stalls against shield-regenerating
gunship / dreadnought remain the defect to watch. Either enemy `shield_regen`
is too high relative to card damage, or the player lacks enough shield-stripping
tools.

**Dead content.** The play histogram still flags cards the pilot rarely reaches
for (Ammo Drum, and several burst-energy / status cards). Coolant Leak and
Magnetic Drag never being played is the *intended* result: they are duds, and
the pilot strips them. Costed unlocks that never get played after unlock are
worse than no unlock.

**Engine disconnect spam.** Release builds sometimes log
`Attempt to disconnect a nonexistent connection … Signal: 'tree_exited',
callable: ''` on scene exit. Mitigations are in place (no await-on-frame in the
combat log, hand detach before free, guarded scene exits); remaining noise may
be a Godot 4 Window/focus quirk. Track, do not chase blindly.
