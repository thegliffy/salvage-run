# Asset provenance

What `assets/` needs, what ships with this repository, and what does not.

---

## What ships here

| Asset | Used for | Licence |
|---|---|---|
| `assets/fonts/Exo-*.ttf` | All UI type | SIL Open Font License 1.1 — see [`OFL.txt`](../assets/fonts/OFL.txt) |

Attribution: **Exo** designed by Natanael Gama.

## What does not ship here

`assets/icons/` and `assets/portraits/` are **not in this repository**. They are
commercially purchased artwork, licensed for use inside a released game but not
for redistribution — and a public git repository redistributes.

They are listed in `.gitignore` and were removed from git history, not merely
deleted in a later commit.

**The game runs without them.** `UITheme.art()` returns null for absent files
rather than erroring, and cards fall back to a flat block in their kind colour.
A full run has been rendered end to end with both directories removed; every
screen draws and the hand stays readable. You lose the art, not the game.

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

The reference set used four colour families named `red_*`, `blue_*`, `green_*`
and `violet_*`. To regenerate assignments after dropping in a new set, the
mapping is a plain loop over `content/cards.json` — assign by `kind`, then write
the filename into each card's `icon` field.

### Enemy portraits — `assets/portraits/`

Square PNGs with transparency, 256×256. Referenced by the `portrait` field in
`content/enemies.json`. They render scaled to fit whatever vertical space the
enemy's subsystem list leaves, so they should read at roughly 150–300px tall.

Four are needed for the current enemy roster.

### Free alternatives

If you want a permissively licensed starting point: [Game-icons.net](https://game-icons.net)
(CC-BY 3.0) covers the card-icon slot well and can be tinted per card kind at
build time, which would also make the colour convention automatic rather than
manual.

## Assets deliberately not used

A purchased **cyberpunk HUD panel** set was evaluated and rejected. Those panels
are fixed-shape with an asymmetric notch cut into one edge, so stretching them to
arbitrary sizes mangles the artwork, and 9-slicing cannot preserve the notch. UI
panels are Godot `StyleBoxFlat` matched to the same cyan palette instead.

Using that angular look properly would need purpose-cut 9-slice frames rather
than the shipped PNGs.
