# Salvage Run

A roguelike deckbuilder where **your ship is your deck**. Fight your way across a
sector to a final boss, then sell the ship you built for meta-currency that
unlocks new parts.

FTL's subsystem targeting, Slay the Spire's card economy, and a run-end sale
that turns "how good was this ship" into a number you spend.

Built with **Godot 4.7.2** / GDScript. Targets **Steam** (Windows/Linux) and
**Android**.

---

## Status: scaffold

The simulation, rules, and data layers are complete and tested. There is no
gameplay UI yet — `scenes/main.tscn` is a boot screen that proves content loads.
See [docs/ROADMAP.md](docs/ROADMAP.md).

```
87 tests passing · 300-run balance sim at ~6ms/run
```

## Quick start

Install Godot 4.7.2, then:

```bash
godot --headless --path . --import
```

Run the test suite:

```bash
godot --headless --path . res://tests/headless.tscn -- --test
```

Run the balance simulator:

```bash
godot --headless --path . res://tests/headless.tscn -- --sim 300
```

Open the project in the editor to run the boot scene.

## The core idea

You never edit your deck directly. You edit your **ship**.

Parts are shapes you place on a hull grid. Each part powers a subsystem and
grants cards. Bolt on a Missile Rack and `Breach Missile` enters your deck; lose
that part to enemy fire and the cards leave with it. Deckbuilding and ship
building are the same action.

### Why subsystem targeting matters

Enemies telegraph an intent one turn ahead, and every intent names the subsystem
it fires from:

```
Raider — Autocannon: 9 damage   [requires: weapons]
```

Destroy or suppress that subsystem before their turn and **the intent fizzles**.
Damage it partially and the shot lands weaker. This is the whole combat design in
one rule — it turns "which system do I shoot" from flavor into the central
decision, and it gives EMP and suppression effects a job that raw damage cannot do.

Destroyed subsystems stay targetable: shots at the wreckage spill straight into
the hull, so a fully disabled ship can still be finished off.

### Removing cards

Every part grants **three** cards, and each part can have **one** of them stripped
permanently at a salvage node. That caps thinning by construction — a ship can
never fall below two thirds of its cards — so there is no escalating purge price.

Strips are paid for in the ship's eventual **sale value**, not credits: you are
cutting up the thing you intend to sell, and the cost lands on the receipt below.

### The sale

At the end of a run the ship is appraised part by part, and the itemized receipt
is the point:

```
--- SHIP SALE ---
  Burst Laser (worn)                     44
  Reactor Mk I (pristine)                50
  Deflector Mk I (pristine)              55
  Hull integrity (72%)                   43
  Elite kills x2                         90
  subtotal                              282
  Sector 3 + boss                      x2.31
  TOTAL                                 651 salvage
```

Wear cuts value, depth multiplies it, dying keeps 40%. The player should be able
to read the receipt and immediately know what to do differently.

## Layout

| Path | What lives there |
|---|---|
| `content/*.json` | All balance data — cards, parts, enemies |
| `src/core/` | Autoloads: event bus, seeded RNG, content DB, saves |
| `src/data/` | Typed definitions parsed from JSON |
| `src/ship/` | Hull grid, parts, and `compile()` → combat profile |
| `src/combat/` | Turn loop, effect resolver, enemy AI, deck |
| `src/run/` | Run state and sector map generation |
| `src/meta/` | Persistent unlocks and the ship valuation |
| `tests/` | Headless test suite and balance simulator |

Design rationale is in [docs/DESIGN.md](docs/DESIGN.md).
Shipping to Steam and Android is in [docs/SHIPPING.md](docs/SHIPPING.md).
