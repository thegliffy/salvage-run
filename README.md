# Salvage Run

A roguelike deckbuilder where **your ship is your deck**. Fight across a sector
to a final boss, then sell the ship you built for meta-currency that unlocks new
parts.

FTL's subsystem targeting, Slay the Spire's card economy, and a run-end sale that
turns "how good was this ship" into a number you spend.

Built with **Godot 4.7.2** / GDScript. Targets **Steam** (Windows/Linux) and
**Android**.

```
112 tests passing · 200-run balance sim at ~50% win rate
```

---

## Play it

```bash
./build/salvage-run.x86_64
```

or from source:

```bash
godot --path .
```

**How to play.** Click a card, then click the enemy subsystem you want to hit.
The amber banner is the enemy's next attack and it *names the subsystem that
fires it* — destroy or suppress that subsystem before ending your turn and the
attack is cancelled outright. Cards that need no target play on a single click.

The demo runs three fights — scout drone, gunship, dreadnought — deliberately one
of each reward tier, then appraises your ship.

## Status: playable PC demo

Title → combat → reward → salvage yard → … → ship sale, end to end.

**Working:** combat with subsystem targeting, typed-slot ship loadout, tiered
battle rewards, ship improvements, jettison, card stripping, run-end appraisal,
meta-progression saves.

**Not built yet:** the sector map (the demo uses a fixed three-fight ladder), the
ship screen, the meta unlock shop, and audio. See [docs/ROADMAP.md](docs/ROADMAP.md).

---

## The core idea

You never edit your deck directly. You edit your **ship**.

The hull has typed slots — **4 weapon, 3 hull, 4 utility**. Each installed part
grants three cards. Bolt on a Missile Rack and `Breach Missile` enters your deck;
jettison that part and its cards leave with it. Deckbuilding and ship building
are the same action.

Nothing limits how much you carry except the slots. What limits *what* you carry
is three soft costs:

| Cost | Effect |
|---|---|
| Power | draw beyond the hull's output cuts your energy every turn |
| Mass | heavier ships dodge worse |
| Deck | every part adds three cards, so a big ship draws badly |

The hull generates the power — no module does — so energy is a property of the
ship rather than a mandatory part every build has to carry.

### Why subsystem targeting matters

Enemies telegraph an intent one turn ahead, and every intent names the subsystem
it fires from:

```
Raider — Autocannon: 9 damage   [requires: weapons]
```

Destroy or suppress that subsystem before their turn and **the intent fizzles**.
Damage it partially and the shot lands weaker. That single rule is the combat
design: it makes "which system do I shoot" the central decision, and it gives EMP
and suppression effects a job that raw damage cannot do.

Destroyed subsystems stay targetable — shots at the wreckage spill into the hull
— so a fully disabled ship can still be finished off.

### Rewards scale with the fight

| Enemy | Payout |
|---|---|
| Regular | credits + a part offer |
| Mini-boss | + a common/uncommon **ship improvement** |
| Sector boss | a **rare** part + a rare improvement |

**Improvements** fill no slot and grant no cards — they change the ship itself
(more power, more hull, another slot). Keeping them separate from parts means the
two reward types never compete for the same decision.

Declining a part offer lets you **jettison** an installed one instead: the slot
frees up and all three of its cards leave the deck.

### Trimming the deck

Each part can have exactly **one** of its three cards stripped, permanently, at a
salvage yard. Because the cap is one per part, a ship can never fall below two
thirds of its cards — so there is no escalating purge price. Strips are paid for
in the ship's **sale value**: you are cutting up the thing you intend to sell.

### The sale

At the end of a run the ship is appraised part by part, and the itemised receipt
is the point:

```
--- SHIP SALE ---
  Burst Laser (worn)                     44
  Deflector Mk I (pristine)              55
  Hull integrity (72%)                   43
  Elite kills x2                         90
  subtotal                              282
  Sector 3 + boss                      x2.31
  TOTAL                                 651 salvage
```

Wear cuts value, depth multiplies it, dying keeps 40%. The player should read the
receipt and immediately know what to do differently.

---

## Development

Run the test suite:

```bash
godot --headless --path . res://tests/headless.tscn -- --test
```

Run the balance simulator — 200 full runs in a few seconds, with a card-play
histogram that names content nobody reaches for:

```bash
godot --headless --path . res://tests/headless.tscn -- --sim 200
```

Add `--seed 42` to pin it; the same seed replays identically and narrates one
fight turn by turn.

Capture screenshots of every screen without stealing your desktop:

```bash
xvfb-run -a godot --path . -- --shots /tmp/shots
```

## Layout

| Path | What lives there |
|---|---|
| `content/*.json` | All balance data — cards, parts, enemies, improvements |
| `src/core/` | Autoloads: event bus, seeded RNG, content DB, saves, run router |
| `src/data/` | Typed definitions parsed from JSON |
| `src/ship/` | Slot loadout, parts, and `compile()` → combat profile |
| `src/combat/` | Turn loop, effect resolver, enemy AI, deck |
| `src/run/` | Run state, map generation, rewards, salvage yard |
| `src/meta/` | Persistent unlocks and the ship valuation |
| `src/ui/` | Screens, built programmatically against the event bus |
| `tests/` | Headless test suite and balance simulator |

## Docs

- [docs/DESIGN.md](docs/DESIGN.md) — why the systems are shaped this way, and what is still undecided
- [docs/ROADMAP.md](docs/ROADMAP.md) — what exists and what to build next
- [docs/SHIPPING.md](docs/SHIPPING.md) — Steam and Android specifics, toolchain setup
- [docs/DEVLOG.md](docs/DEVLOG.md) — how it was built and what broke on the way
- [docs/ASSETS.md](docs/ASSETS.md) — third-party asset provenance and licensing
