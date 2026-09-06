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

## Where it stands

```
87 tests passing
300-run sim: ~96% win rate, 27 distinct cards played, 6 stalls
```

The systems work and are tested. Balance is not tuned, and the simulator now
names the reasons rather than just reporting a number:

- **Enemies do not scale with depth.** The same Gunship appears at fight 4 and
  fight 6 while the player's ship reaches ~10 parts. Highest-leverage fix.
- **Reward-to-cost ratio is too generous** — the ladder funds roughly four parts
  before the boss.
- **Dead content:** Ammo Drum, Salvo, Dead Weight, and notably Breach Missile —
  a 150-salvage unlock that loses to a 1-cost Laser Burst at nearly every board
  state.

At 96% the simulator is not yet a sensitive instrument. It will sharpen once the
win rate lands mid-range, where a tuning change actually moves the number.

No gameplay UI exists. See ROADMAP.md for the order it should be built in.
