# Asset provenance

What `assets/` needs, what ships with this repository, and what does not.

---

## What ships here

| Asset | Used for | Licence |
|---|---|---|
| `assets/fonts/Exo-*.ttf` | All UI type | SIL Open Font License 1.1 — see [`OFL.txt`](../assets/fonts/OFL.txt) |
| `assets/frames/*.png` | Card frames, one per card kind | Original work by **thegliffy** |
| `assets/ships/salvager-hull.png` | Side-view hull behind bolted-on parts (`ShipView`) | Project art — ships with the repo |
| `assets/icons/*.png` | Card icons (`UITheme.art()` via `content/cards.json` `icon`) | Redistributable [Game-icons.net](https://game-icons.net) glyphs, tinted to kind colour (CC-BY 3.0) |
| `assets/portraits/*.png` | Enemy portraits (`UITheme.art()` via `content/enemies.json` `portrait`) | Redistributable painted industrial ships — ships with the repo |

Attribution: **Exo** designed by Natanael Gama. Card icons derived from
[Game-icons.net](https://game-icons.net) (CC-BY 3.0), tinted per card kind.

`ShipView` bolts installed modules onto hardpoints on that hull (weapons dorsal,
hull plating belly, utilities aft). If the PNG is missing, it falls back to a
procedural chassis — same pattern as `UITheme.art()` elsewhere.

## What does not ship here

The **card frames**, **redistributable card icons**, and **painted enemy
portraits** ARE included.

Commercially purchased icon or portrait packs remain **optional** and **must
not be redistributed**. A public git repository redistributes. If you keep a
purchased set locally, put it under `assets/icons/commercial/` or
`assets/portraits/commercial/` — those paths stay in `.gitignore`. Do not commit
or publish those files.

Older commercial art that once lived at the top of `assets/icons/` and
`assets/portraits/` was stripped from git history, not merely deleted in a later
commit.

**The game still runs if a file is missing.** `UITheme.art()` returns null for
absent files rather than erroring, and cards fall back to a flat block in their
kind colour. You lose that piece of art, not the game.

## Shipped filenames

`UITheme.art()` joins these names onto `res://assets/icons/` or
`res://assets/portraits/`. They must match `content/cards.json` `icon` and
`content/enemies.json` `portrait` exactly.

### Card icons — 31 PNGs in `assets/icons/`

Flat Game-icons glyphs, tinted by kind colour (red attack, blue tech, green
manoeuvre, violet status):

- Attack: `red_gr_01.png`, `red_gr_03.png`, `red_gr_04.png`, `red_gr_06.png`,
  `red_gr_07.png`, `red_gr_08.png`, `red_gr_09.png`, `red_r_01.png`
- Tech: `blue_b_01.png` through `blue_b_17.png`
- Manoeuvre: `green_g_01.png`, `green_g_02.png`
- Status: `violet_p_01.png` through `violet_p_04.png`

### Enemy portraits — 4 PNGs in `assets/portraits/`

Painted industrial ships, square with transparency:

| File | Enemy |
|---|---|
| `a_09_t.png` | Scout Drone |
| `a_02_t.png` | Raider |
| `k_04_t.png` | Gunship |
| `f_07_t.png` | Dreadnought |

Godot 4 writes a sibling `.import` sidecar the first time the editor (or
`godot --headless --import`) sees a new PNG. Commit those sidecars with the
PNGs, matching the existing `assets/frames/` / `assets/ships/` convention.

## Supplying your own art

### Card icons — `assets/icons/`

Square PNGs, 256×256 works well. Filenames are referenced by the `icon` field in
`content/cards.json`, so any naming scheme works as long as the JSON matches.

Colour is load-bearing: icon colour is keyed to card kind so a hand reads as
shapes before it reads as words.

| Colour | Card kind |
|---|---|
| Red | attack |
| Cyan / blue | tech |
| Green | manoeuvre |
| Violet | status (drawback cards) |

The shipped set uses four colour families named `red_*`, `blue_*`, `green_*`
and `violet_*`. To regenerate assignments after dropping in a new set, the
mapping is a plain loop over `content/cards.json` — assign by `kind`, then write
the filename into each card's `icon` field.

### Enemy portraits — `assets/portraits/`

Square PNGs with transparency, 256×256. Referenced by the `portrait` field in
`content/enemies.json`. They render scaled to fit whatever vertical space the
enemy's subsystem list leaves, so they should read at roughly 150–300px tall.

Four are needed for the current enemy roster.

### Ship hull — `assets/ships/`

Side-view PNG, landscape. Referenced by `ShipView.HULL_ART`
(`salvager-hull.png`). Parts are drawn on top in code, so the hull should leave
clear dorsal / belly / aft regions rather than painting every hardpoint into the
base art.

## Assets deliberately not used

A purchased **cyberpunk HUD panel** set was evaluated and rejected. Those panels
are fixed-shape with an asymmetric notch cut into one edge, so stretching them to
arbitrary sizes mangles the artwork, and 9-slicing cannot preserve the notch. UI
panels are Godot `StyleBoxFlat` matched to the same cyan palette instead.

Using that angular look properly would need purpose-cut 9-slice frames rather
than the shipped PNGs.
