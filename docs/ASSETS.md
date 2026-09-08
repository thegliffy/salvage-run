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
| `assets/modules/*.png` | Part / module icons (`UITheme.art()` via `content/parts.json` `icon`, default `<part_id>.png`) | Project art — unified painted 3D isometric hardware; ships with the repo |
| `assets/ui/drone_slots/*.png` | Combat drone bay chips (empty ring, attack red, shield blue) | Project art — ships with the repo |

Attribution: **Exo** designed by Natanael Gama. Card icons derived from
[Game-icons.net](https://game-icons.net) (CC-BY 3.0), tinted per card kind.

`ShipView` bolts installed modules onto hardpoints on that hull (weapons dorsal,
hull plating belly, utilities aft). If the PNG is missing, it falls back to a
procedural chassis — same pattern as `UITheme.art()` elsewhere.

## What does not ship here

The **card frames**, **redistributable card icons**, **painted enemy
portraits**, and **module / part icons** ARE included.

Commercially purchased icon or portrait packs remain **optional** and **must
not be redistributed**. A public git repository redistributes. If you keep a
purchased set locally, put it under `assets/icons/commercial/`,
`assets/portraits/commercial/`, or `assets/modules/commercial/` — those paths
stay in `.gitignore`. Do not commit or publish those files.

Older commercial art that once lived at the top of `assets/icons/` and
`assets/portraits/` was stripped from git history, not merely deleted in a later
commit.

**The game still runs if a file is missing.** `UITheme.art()` returns null for
absent files rather than erroring, and cards fall back to a flat block in their
kind colour. You lose that piece of art, not the game.

## Shipped filenames

`UITheme.art()` joins these names onto `res://assets/icons/`,
`res://assets/portraits/`, or `res://assets/modules/`. They must match
`content/cards.json` `icon`, `content/enemies.json` `portrait`, and
`content/parts.json` `icon` (or the `<part_id>.png` default) exactly.

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

### Module icons — 19 PNGs in `assets/modules/`

Unified painted 3D isometric hardware, one square PNG per part. Filenames are
the part ids in `content/parts.json`. `PartDef` defaults `icon` to
`<part_id>.png`; set `"icon"` in JSON only to override.

| File | Part |
|---|---|
| `burst_laser.png` | Burst Laser |
| `plasma_cycler.png` | Plasma Cycler |
| `missile_rack.png` | Missile Rack |
| `aegis_rail.png` | Aegis Rail |
| `emp_projector.png` | EMP Projector |
| `capacitor_cannon.png` | Capacitor Cannon |
| `carrion_lance.png` | Carrion Lance |
| `ablative_plating.png` | Ablative Plating |
| `deflector_mk1.png` | Deflector Mk I |
| `armor_plating.png` | Armor Plating |
| `blast_doors.png` | Blast Doors |
| `shield_capacitor.png` | Shield Capacitor |
| `ion_thrusters.png` | Ion Thrusters |
| `power_relay.png` | Power Relay |
| `sensor_array.png` | Sensor Array |
| `salvage_arm.png` | Salvage Arm |
| `repair_bay.png` | Repair Bay |
| `overcharge_rig.png` | Overcharge Rig |
| `drone_launcher.png` | Drone Launcher (`UITheme.module_icon()` hides the TextureRect if this PNG is missing) |
| `static_coil.png` | Static Coil (same `UITheme.module_icon()` fallback if the PNG is missing) |

`UITheme.module_icon()` draws these keep-aspect on reward / shop / unlock
offer rows (~64–96px at 720p). Missing files return null and hide the
TextureRect — same `UITheme.art()` fallback as cards and portraits.

### Drone bay chips — 3 PNGs in `assets/ui/drone_slots/`

128×128 RGBA chips for the two combat-header bays. `UITheme.drone_slot_texture()`
loads them; combat falls back to StyleBox circles if a file is absent.

| File | Bay |
|---|---|
| `drone_slot_empty.png` | Vacant ring |
| `drone_slot_attack.png` | Occupied attack (red) |
| `drone_slot_shield.png` | Occupied shield charger (blue) |

Do not commit `contact_sheet.png` (gitignored); it is source reference, not a
game asset.

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

### Module icons — `assets/modules/`

Square PNGs with transparency; 256×256 or larger works well. Referenced by the
`icon` field in `content/parts.json`, defaulting to `<part_id>.png`. They
render keep-aspect (never stretch-distorted) at ~64–96px on offer rows, and
scale with `canvas_items` stretch.

Style lock: **unified painted 3D** isometric hardware. Hull and utility pieces
may be redrawn to match the weapons; keep the same filenames.

Eighteen are needed for the current part roster. A source contact sheet is
not a game asset — leave it out of this directory (gitignored).

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
