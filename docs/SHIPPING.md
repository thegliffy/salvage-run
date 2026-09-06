# Shipping to Steam and Android

Platform notes gathered while scaffolding, current as of **September 2026**.

---

## Engine version

Pinned to **Godot 4.7.2** (stable, released 2026-08-18). `project.godot` declares
`config/features = ("4.7", "GL Compatibility")`.

The renderer is set to **GL Compatibility** on both desktop and mobile. For a 2D
card game this is the right call: it runs on far more Android hardware than the
Vulkan-based Mobile renderer, and nothing in this game needs the extra features.

## Installed toolchain (this machine)

Godot is installed per-user, no sudo, fully reversible:

| Thing | Location |
|---|---|
| Editor | `~/.local/share/godot-engine/4.7.2.stable/godot` |
| Commands | `~/.local/bin/godot`, `~/.local/bin/godot4` (symlinks) |
| Export templates | `~/.local/share/godot/export_templates/4.7.2.stable/` (2.0 GB) |
| Launcher entry | `~/.local/share/applications/org.godotengine.Godot.desktop` |
| Icon | `~/.local/share/icons/hicolor/128x128/apps/godot.png` |
| MIME types | `~/.local/share/mime/packages/org.godotengine.Godot.xml` |

Both downloads were verified against the release's official SHA512 sums.

Upgrading is a matter of unpacking the new version beside the old one and
repointing the symlink; export templates are versioned by tag, so several
versions coexist without conflict.

To remove entirely: delete the paths in the table above.

### Verified working

A Linux release export has been run end to end on this machine and the resulting
binary boots. `export_presets.cfg` exists locally with a Linux preset (it stays
gitignored, per the note below) and excludes `tests/*` from release builds.

```bash
godot --headless --path . --export-release "Linux" build/salvage-run.x86_64
```

### Still needed before Android will export

Export templates are only half of it. The Android pipeline additionally needs:

- A JDK (17+), the Android SDK with build-tools and platform-tools, and the NDK
- Those paths configured in Godot's Editor Settings under `export/android`
- A debug keystore for development and a separate upload keystore for release

None of these are installed on this machine yet — `java`, `gradle`, and `adb`
are all absent. Android export will fail until they are present.

## Steam

### GodotSteam moved to Codeberg — this matters

The GitHub repositories under `github.com/GodotSteam/` were **archived in July–
September 2026**. This is a migration, not an abandonment: development continues
at **`codeberg.org/godotsteam/godotsteam`**, which was releasing as recently as
2026-09-04.

If you search for GodotSteam you will land on the archived GitHub repo first.
Use Codeberg.

Current release at time of writing: **GodotSteam 4.22.1**, targeting Steamworks
SDK 1.65.

### Which build to use

Take the **GDExtension** build (`v4.22.1-gde`, for Godot 4.4+), not the module
build. GDExtension drops into an existing project as an addon; the module build
requires compiling a custom Godot binary and export templates, which is a large
recurring cost every time you update the engine.

Note that as of Godot 4.7.2 the GodotSteam project merged its module and
GDExtension codebases, so the separate GDExtension branch is being retired —
check the Codeberg releases page for the current recommended artifact rather
than assuming the split still exists.

### Setup outline

1. Download the GDExtension release; drop it into `addons/godotsteam/`.
2. Put `steam_appid.txt` (containing your App ID) beside the binary during
   development. It is already gitignored — never commit it.
3. Initialise Steam at boot, and **fail gracefully**: the Android build has no
   Steam, and the desktop build must still run when launched outside the client.
   Wrap every Steam call behind a thin `platform/steam.gd` façade that no-ops
   when unavailable. Do this from day one; retrofitting it is miserable.
4. Define achievements in the Steamworks backend and **publish them live** before
   testing. Unpublished achievements are invisible to the API and every call
   errors — this is the single most common integration complaint.

Since Steamworks SDK 1.61, stats and achievements are synced automatically by the
Steam client at boot, so you no longer need a manual request-stats step.

### Steam Deck

Worth explicitly targeting — deckbuilders do very well there. Requires: full
controller navigation, readable text at 1280×800, and a default resolution that
does not assume a mouse.

## Android

### Export requirements

- Android SDK with build-tools, platform-tools, and NDK
- A debug keystore for development, and a separate **upload keystore** for
  release — back that one up somewhere durable; losing it means you cannot ship
  updates to an existing listing
- Google Play requires **AAB** (Android App Bundle), not APK, and a **64-bit**
  build. Export `arm64-v8a`; include `armeabi-v7a` only if you care about very
  old devices

ETC2/ASTC texture compression is already enabled in `project.godot`.

### The process-death problem

Android kills backgrounded processes without warning. A roguelike run that takes
30+ minutes **will** be lost by players unless run state is saved continuously.

`SaveSystem` currently persists meta-progression only. Before any Android beta,
run state needs the same treatment: save on every state transition (node entered,
combat turn ended, part installed), using the atomic temp-then-rename pattern
already in `SaveSystem.save_meta()`.

This is the number one cause of bad reviews for mobile roguelikes. Treat it as a
launch blocker, not polish.

### Input and layout

`pointing/emulate_mouse_from_touch` is enabled, so mouse-based UI code works
under touch. That covers input but not ergonomics:

- Touch targets ≥ 48dp. Subsystem targeting is the tightest interaction in the
  game and needs the most room.
- Handle the Android back button (`ui_cancel` / `NOTIFICATION_WM_GO_BACK_REQUEST`)
  or the OS will close the app mid-run.
- Respect safe areas — notches and gesture bars eat the edges where card hands
  naturally want to sit.

Orientation is locked to landscape (`window/handheld/orientation = 1`), matching
the desktop layout so one UI serves both platforms.

### Store expectations

Premium (paid, no ads, no IAP) is the norm for this genre on mobile and matches
the Steam build. It also means the meta-progression can be tuned for fun rather
than for retention pressure. If you ever add IAP, note that the run-end salvage
economy is exactly the system that would come under monetisation pressure —
which is a good reason to decide now and not later.

## Build commands

Export presets are not committed (they contain absolute paths and keystore
locations). Create them in the editor, then:

```bash
godot --headless --path . --export-release "Windows Desktop" build/salvage-run.exe
```

```bash
godot --headless --path . --export-release "Android" build/salvage-run.aab
```

## Prior art worth knowing

**Luck Be a Landlord** — a roguelike deckbuilder built in Godot, shipped to
Steam, Android, iOS, Switch, PlayStation, and Xbox. Direct proof the engine
handles this exact genre and platform spread.

**Cobalt Core** and **Breachway** — the two closest design comparables. Both are
ship-based roguelike deckbuilders; worth studying for what they chose *not* to
simulate.
