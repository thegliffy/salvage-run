# UI chrome

Combat presentation art that is not a card *face*.

| File | Used for |
|---|---|
| `card_back.png` | Shared card back — draw / shuffle ghosts and DRAW / DISCARD pile thumbs |
| `drone_slots/` | Drone bay chips (see that folder's README) |

## Card back

**Canonical path: `assets/ui/card_back.png`.**

`assets/frames/` is reserved for kind-coloured faces. Do not add a second
`card_back.png` there.

Art Director artwork lives here (industrial plate + cyan wrench). Keep
1152×1712 (card ratio). `scripts/make_card_back.py` regenerates a framed
placeholder only — do not run it over this file.

Loaded through `UITheme.card_back_texture()`. Missing file falls back rather
than erroring.
