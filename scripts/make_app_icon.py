#!/usr/bin/env python3
"""Generate the Sigillo app icon — a film-noir camera aperture.

Renders a 1024x1024 opaque PNG into the asset catalog:
  Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

Noir aesthetic: a cold, high-contrast charcoal scene cut by venetian-blind
light, with a camera iris lit dramatically from the upper-left (chiaroscuro)
and a single bright catchlight gleaming through the aperture.

Usage:  /tmp/iconenv/bin/python scripts/make_app_icon.py
        (any Python with Pillow installed)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024          # final icon size
SS = 4               # supersample factor (render at SIZE*SS, downsample)
S = SIZE * SS
CX = CY = S / 2

LIGHT = (-0.70, -0.70)   # light direction (upper-left), image coords (y down)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def clamp01(x):
    return max(0.0, min(1.0, x))


# ---------------------------------------------------------------------------
# Background: diagonal charcoal gradient + cool upper-left spotlight.
# ---------------------------------------------------------------------------
def make_background():
    g = 256
    top = (12, 13, 17)        # near-black
    bot = (38, 41, 49)        # cool charcoal
    light_col = (120, 132, 150)
    base = Image.new("RGB", (g, g))
    px = base.load()
    lx, ly = 0.30, 0.26       # spotlight centre (fractional)
    for y in range(g):
        for x in range(g):
            t = clamp01((x * 0.45 + y) / (g * 1.45))
            r, gr, b = lerp(top, bot, t)
            dx, dy = (x / g - lx), (y / g - ly)
            d = math.hypot(dx, dy)
            glow = clamp01(1.0 - d / 0.85) ** 2.2
            r = min(255, int(r + light_col[0] * glow * 0.65))
            gr = min(255, int(gr + light_col[1] * glow * 0.65))
            b = min(255, int(b + light_col[2] * glow * 0.65))
            px[x, y] = (r, gr, b)
    return base.resize((S, S), Image.BICUBIC)


# ---------------------------------------------------------------------------
# Venetian-blind light: angled translucent bars, feathered, low opacity.
# ---------------------------------------------------------------------------
def add_blinds(img):
    big = int(S * 1.6)
    layer = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(layer)
    period = int(S * 0.135)
    bar = int(period * 0.42)
    for y in range(0, big, period):
        d.rectangle([0, y, big, y + bar], fill=70)
    layer = layer.rotate(-24, resample=Image.BICUBIC, expand=False)
    off = (big - S) // 2
    layer = layer.crop((off, off, off + S, off + S))
    layer = layer.filter(ImageFilter.GaussianBlur(S * 0.006))
    # Fade the blinds out toward the lower-right (away from the light).
    grad = Image.new("L", (256, 256), 0)
    gp = grad.load()
    for y in range(256):
        for x in range(256):
            gp[x, y] = int(255 * clamp01(1.0 - (x * 0.5 + y) / (256 * 1.4)))
    grad = grad.resize((S, S), Image.BICUBIC)
    mask = Image.composite(layer, Image.new("L", (S, S), 0), grad)
    glow = Image.new("RGB", (S, S), (150, 162, 180))
    img.paste(glow, (0, 0), mask)
    return img


# ---------------------------------------------------------------------------
# Vignette: darken the edges.
# ---------------------------------------------------------------------------
def add_vignette(img):
    g = 256
    m = Image.new("L", (g, g), 0)
    mp = m.load()
    for y in range(g):
        for x in range(g):
            dx, dy = (x / g - 0.5), (y / g - 0.5)
            d = math.hypot(dx, dy) / 0.72
            mp[x, y] = int(255 * clamp01(d ** 2.1))
    m = m.resize((S, S), Image.BICUBIC)
    dark = Image.new("RGB", (S, S), (4, 4, 6))
    img.paste(dark, (0, 0), m.point(lambda v: int(v * 0.85)))
    return img


# ---------------------------------------------------------------------------
# The camera iris: blades with chiaroscuro shading + a bright catchlight.
# ---------------------------------------------------------------------------
def draw_aperture(img):
    d = ImageDraw.Draw(img, "RGBA")
    R_barrel = S * 0.355
    R_blade = S * 0.320
    r_hole = S * 0.118
    N = 7
    spiral = 0.62
    base = -math.pi / 2

    # Lens barrel: dark ring with a lit rim arc (upper-left).
    d.ellipse([CX - R_barrel, CY - R_barrel, CX + R_barrel, CY + R_barrel],
              fill=(18, 19, 23, 255))
    rim = R_barrel * 1.005
    d.arc([CX - rim, CY - rim, CX + rim, CY + rim], start=150, end=330,
          fill=(150, 160, 176, 255), width=int(S * 0.012))
    d.arc([CX - rim, CY - rim, CX + rim, CY + rim], start=330, end=510,
          fill=(8, 9, 12, 255), width=int(S * 0.012))

    shadow = (26, 28, 33)
    litcol = (224, 229, 235)
    for i in range(N):
        a0 = base + 2 * math.pi * i / N
        a1 = base + 2 * math.pi * (i + 1) / N
        o0 = (CX + R_blade * math.cos(a0), CY + R_blade * math.sin(a0))
        o1 = (CX + R_blade * math.cos(a1), CY + R_blade * math.sin(a1))
        ai = a0 + spiral
        inner = (CX + r_hole * math.cos(ai), CY + r_hole * math.sin(ai))
        ai1 = a1 + spiral
        inner1 = (CX + r_hole * math.cos(ai1), CY + r_hole * math.sin(ai1))
        poly = [o0, o1, inner1, inner]

        # Shade by the blade centroid's direction relative to the light.
        mx = (o0[0] + o1[0]) / 2 - CX
        my = (o0[1] + o1[1]) / 2 - CY
        ml = math.hypot(mx, my) or 1
        ndot = (mx / ml) * LIGHT[0] + (my / ml) * LIGHT[1]
        t = clamp01((ndot + 1) / 2) ** 1.25
        d.polygon(poly, fill=lerp(shadow, litcol, t))
        d.line([inner, o0], fill=(8, 9, 12, 230), width=int(S * 0.004))

    # Inner edge of the hexagonal hole + the dark opening.
    hole = []
    for i in range(N):
        a = base + 2 * math.pi * i / N + spiral
        hole.append((CX + r_hole * math.cos(a), CY + r_hole * math.sin(a)))
    d.polygon(hole, fill=(6, 7, 10, 255))

    # Bright catchlight gleaming through the aperture.
    glow = Image.new("L", (256, 256), 0)
    gp = glow.load()
    for y in range(256):
        for x in range(256):
            dd = math.hypot(x - 128, y - 118) / 120
            gp[x, y] = int(255 * clamp01(1 - dd) ** 2.4)
    gs = int(r_hole * 2.4)
    glow = glow.resize((gs, gs), Image.BICUBIC)
    white = Image.new("RGB", (gs, gs), (236, 240, 247))
    img.paste(white, (int(CX - gs / 2), int(CY - gs / 2)), glow)
    return img


def main():
    img = make_background()
    img = add_blinds(img)
    img = add_vignette(img)
    img = draw_aperture(img)
    img = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")  # opaque, no alpha

    out_dir = os.path.join(
        os.path.dirname(__file__), "..",
        "Sources", "Assets.xcassets", "AppIcon.appiconset",
    )
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "icon-1024.png")
    img.save(out, "PNG")
    print("Wrote", os.path.normpath(out), f"({img.size[0]}x{img.size[1]}, opaque)")


if __name__ == "__main__":
    main()
