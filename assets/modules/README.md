# Module / part icons

Painted isometric hardware for each part. `UITheme.art()` loads
`res://assets/modules/` plus the `icon` field from `content/parts.json`
(default `<part_id>.png`).

Drop the PNGs (and the `.import` sidecars Godot generates) in this directory.
Filenames must match part ids:

```
burst_laser.png
plasma_cycler.png
missile_rack.png
aegis_rail.png
emp_projector.png
capacitor_cannon.png
carrion_lance.png
ablative_plating.png
deflector_mk1.png
armor_plating.png
blast_doors.png
shield_capacitor.png
ion_thrusters.png
power_relay.png
sensor_array.png
salvage_arm.png
repair_bay.png
overcharge_rig.png
drone_launcher.png
```

Style lock: unified painted 3D (isometric hardware). Hull/utility pieces may
be redrawn to match weapons; filenames stay the same.

Do not commit `contact_sheet.png` (gitignored) or commercially licensed packs.
Optional commercial drops go in `commercial/` (gitignored). See
[docs/ASSETS.md](../../docs/ASSETS.md).
