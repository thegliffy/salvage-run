#!/usr/bin/env python3
"""Generate the interim card-back placeholder at assets/ui/card_back.png.

TODO(art): Art Director replaces this file in place. Keep 1152×1712 (same
ratio as assets/frames/*.png / CardView.CARD_SIZE) so TextureRects stay
aspect-correct. See docs/ASSETS.md.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "ui" / "card_back.png"
FRAME = ROOT / "assets" / "frames" / "tech.png"

W, H = 1152, 1712
# CardView body fill — sit just inside the neon outline.
INSET = 58
RADIUS = 52


def _lerp(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def _body() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # Raised navy — dark enough for the neon frame, light enough that a 70px
    # ghost still reads as a card and not a hollow outline on the combat UI.
    top = (22, 34, 48, 255)
    bot = (32, 48, 64, 255)
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gp = grad.load()
    for y in range(H):
        t = y / float(H - 1)
        c = _lerp(top, bot, t)
        for x in range(W):
            gp[x, y] = c

    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [INSET, INSET, W - INSET, H - INSET], radius=RADIUS, fill=255
    )
    img.paste(grad, (0, 0), mask)

    draw = ImageDraw.Draw(img, "RGBA")
    # Inner rail — tinted frame so the fallback still looks like a card back
    # if the neon overlay is missing.
    draw.rounded_rectangle(
        [INSET + 10, INSET + 10, W - INSET - 10, H - INSET - 10],
        radius=RADIUS - 8,
        outline=(28, 111, 150, 210),
        width=4,
    )
    draw.rounded_rectangle(
        [INSET + 22, INSET + 22, W - INSET - 22, H - INSET - 22],
        radius=RADIUS - 16,
        outline=(41, 182, 246, 70),
        width=2,
    )

    # Quiet hatch. Dense enough to read at pile size, not busy in motion.
    hatch = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hatch, "RGBA")
    step = 26
    colour = (48, 110, 148, 70)
    for i in range(-H, W + H, step):
        hd.line([(i, 0), (i + H, H)], fill=colour, width=2)
        hd.line([(i, H), (i + H, 0)], fill=colour, width=1)
    img.paste(hatch, (0, 0), Image.composite(hatch, Image.new("RGBA", (W, H)), mask))

    _emblem(draw)
    return img


def _emblem(draw: ImageDraw.ImageDraw) -> None:
    cx, cy = W // 2, int(H * 0.48)
    ring_r = 168
    draw.ellipse(
        [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
        outline=(41, 182, 246, 200),
        width=7,
    )
    draw.ellipse(
        [cx - ring_r + 18, cy - ring_r + 18, cx + ring_r - 18, cy + ring_r - 18],
        outline=(28, 111, 150, 140),
        width=3,
    )
    # Nested chevrons — reads as a hull / salvage mark at 70×104.
    for i, (spread, alpha) in enumerate(((0, 230), (34, 160), (68, 90))):
        y0 = cy - 70 + spread * 0.15
        pts = [
            (cx, y0 - 36),
            (cx + 92 + spread * 0.35, y0 + 48),
            (cx + 58 + spread * 0.2, y0 + 48),
            (cx, y0 - 4),
            (cx - 58 - spread * 0.2, y0 + 48),
            (cx - 92 - spread * 0.35, y0 + 48),
        ]
        draw.polygon(pts, outline=(41, 182, 246, alpha))
        # Fat stroke via a second offset polygon fill ring.
        draw.line(pts + [pts[0]], fill=(41, 182, 246, alpha), width=8 if i == 0 else 5)

    # Small lower pip so the back isn't a single blob when scaled down.
    pip_y = cy + 210
    draw.ellipse([cx - 14, pip_y - 14, cx + 14, pip_y + 14], fill=(41, 182, 246, 200))
    draw.ellipse(
        [cx - 36, pip_y + 40, cx + 36, pip_y + 48],
        fill=(28, 111, 150, 120),
    )


def main() -> None:
    body = _body()
    if FRAME.is_file():
        frame = Image.open(FRAME).convert("RGBA")
        if frame.size != (W, H):
            frame = frame.resize((W, H), Image.Resampling.LANCZOS)
        # Soften the electrical fringe a hair so a flying ghost stays readable.
        glow = frame.filter(ImageFilter.GaussianBlur(radius=1.2))
        body = Image.alpha_composite(body, glow)
        body = Image.alpha_composite(body, frame)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    body.save(OUT, "PNG")
    print(f"wrote {OUT} {body.size} {OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
