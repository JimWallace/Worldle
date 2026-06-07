#!/usr/bin/env python3
"""Render the app icon: a real 3D-looking globe (orthographic projection of the
actual continents from countries.json) with limb shading and a soft highlight.

Usage:  python3 tools/make_icon.py
Output: Globle/Assets.xcassets/AppIcon.appiconset/AppIcon.png  (1024x1024)
        plus /tmp/globle_icon_preview.png for quick viewing.
"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "Globle", "Resources", "countries.json")
OUT_DIR = os.path.join(HERE, "..", "Globle", "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024
CX = CY = SIZE / 2
R = 410.0
LAT0, LON0 = 20.0, 10.0           # view centered on Africa / Europe
OCEAN = (40, 96, 156)
LAND = (104, 173, 94)
BG_TOP = (28, 36, 74)
BG_BOTTOM = (12, 16, 36)


def project(lat, lon):
    """Orthographic projection. Returns (x, y, visible)."""
    la, lo = math.radians(lat), math.radians(lon)
    la0, lo0 = math.radians(LAT0), math.radians(LON0)
    cosc = math.sin(la0) * math.sin(la) + math.cos(la0) * math.cos(la) * math.cos(lo - lo0)
    x = math.cos(la) * math.sin(lo - lo0)
    y = math.cos(la0) * math.sin(la) - math.sin(la0) * math.cos(la) * math.cos(lo - lo0)
    return CX + x * R, CY - y * R, cosc >= 0


def visible_runs(ring):
    """Split a ring into runs of consecutive on-screen points (avoids limb chords)."""
    runs, current = [], []
    for lon, lat in ring:
        px, py, vis = project(lat, lon)
        if vis:
            current.append((px, py))
        elif current:
            runs.append(current); current = []
    if current:
        runs.append(current)
    return runs


def gradient_background():
    bg = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(bg)
    for y in range(SIZE):
        t = y / SIZE
        color = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (SIZE, y)], fill=color)
    return bg


def main():
    countries = json.load(open(DATA))

    img = gradient_background()

    # Atmosphere glow.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse([CX - R * 1.12, CY - R * 1.12, CX + R * 1.12, CY + R * 1.12],
                  fill=(90, 150, 230, 130))
    glow = glow.filter(ImageFilter.GaussianBlur(34))
    img.paste(glow, (0, 0), glow)

    # Globe ocean + land on its own layer.
    globe = img.copy()
    gd = ImageDraw.Draw(globe)
    gd.ellipse([CX - R, CY - R, CX + R, CY + R], fill=OCEAN)
    for country in countries:
        for polygon in country["geometry"]:
            for ring in polygon:
                for run in visible_runs(ring):
                    if len(run) >= 3:
                        gd.polygon(run, fill=LAND)

    # Limb darkening: bright core fading to dark edges.
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([CX - R * 0.72, CY - R * 0.72, CX + R * 0.72, CY + R * 0.72], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(R * 0.30))
    darker = ImageEnhance.Brightness(globe).enhance(0.45)
    shaded = Image.composite(globe, darker, mask)

    # Clip the shaded globe to the disk and paste onto the background.
    disk = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(disk).ellipse([CX - R, CY - R, CX + R, CY + R], fill=255)
    img.paste(shaded, (0, 0), disk)

    # Specular highlight, upper-left.
    hl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse([CX - R * 0.75, CY - R * 0.80, CX - R * 0.05, CY - R * 0.18],
                               fill=(255, 255, 255, 90))
    hl = hl.filter(ImageFilter.GaussianBlur(40))
    hl.putalpha(hl.getchannel("A").point(lambda a: a))
    img.paste(hl, (0, 0), Image.composite(hl.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), disk))

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "AppIcon.png")
    img.save(out)
    img.resize((256, 256)).save("/tmp/globle_icon_preview.png")
    print("Wrote", out)


if __name__ == "__main__":
    main()
