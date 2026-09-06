# Enemy portraits

Redistributable painted industrial ships. `UITheme.art()` loads
`res://assets/portraits/` plus the `portrait` field from `content/enemies.json`.

Drop the PNGs (and the `.import` sidecars Godot generates) in this directory.
Filenames must match exactly:

```
a_09_t.png   # Scout Drone
a_02_t.png   # Raider
k_04_t.png   # Gunship
f_07_t.png   # Dreadnought
```

Optional commercially licensed packs go in `commercial/` (gitignored) and must
not be redistributed. See [docs/ASSETS.md](../../docs/ASSETS.md).
