"""Renders tools/.cache/world.json (from export_world.luau) to a top-down PNG.

Terrain is coloured by zone/material and hill-shaded from the heightmap; parts
are drawn as projected footprints sorted by height so tall things sit on top.
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCALE = 4  # pixels per stud
CROP = None  # (x0, z0, x1, z1) in studs, set from argv[3]
data = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "tools/.cache/world.json"))
out_path = sys.argv[2] if len(sys.argv) > 2 else "tools/.cache/map.png"
step = data["step"]
origin = data["origin"]
samples = data["samples"]
n = len(samples)
size = n * step * SCALE

ZONE = {
    "basin": (78, 70, 110), "rim": (86, 168, 134), "meadow": (86, 168, 134),
    "river": (190, 172, 206), "outer": (86, 168, 134), "edge": (104, 94, 134),
}
PATH = {"road": (132, 124, 160), "spoke": (150, 140, 176), "plaza": (78, 70, 110)}
VOID = (14, 10, 30)
WATER = (70, 130, 210)
WATER_Y = 16.5

heights = np.full((n, n), np.nan)
colors = np.zeros((n, n, 3))
for zi, row in enumerate(samples):
    for xi, s in enumerate(row):
        if not s:
            colors[zi, xi] = VOID
            continue
        h, zone, path = s
        heights[zi, xi] = h
        col = PATH.get(path) or ZONE.get(zone, (120, 120, 120))
        if zone == "river" and h < WATER_Y:
            depth = min(1, (WATER_Y - h) / 7)
            col = tuple(int(a * (1 - 0.75 * depth) + b * 0.75 * depth) for a, b in zip(col, WATER))
        colors[zi, xi] = col

# Hill shading from the heightmap.
filled = np.where(np.isnan(heights), 0, heights)
gz, gx = np.gradient(filled, step)
light = np.array([-0.6, -0.8, 1.2])
light /= np.linalg.norm(light)
normal = np.dstack((-gx, -gz, np.ones_like(gx)))
normal /= np.linalg.norm(normal, axis=2, keepdims=True)
shade = np.clip((normal @ light) * 0.9 + 0.25, 0.35, 1.25)
height_tint = np.clip(0.85 + (filled - 10) / 80, 0.7, 1.2)
img = np.clip(colors * shade[..., None] * height_tint[..., None], 0, 255).astype(np.uint8)
image = Image.fromarray(img, "RGB").resize((size, size), Image.NEAREST).filter(ImageFilter.SMOOTH)
draw = ImageDraw.Draw(image, "RGBA")


def to_px(x, z):
    return ((x - origin) * SCALE, (z - origin) * SCALE)


def top_of(part):
    px, py, pz = part["p"]
    sx, sy, sz = part["s"]
    r, u, l = part["r"], part["u"], part["l"]
    return py + abs(r[1]) * sx / 2 + abs(u[1]) * sy / 2 + abs(l[1]) * sz / 2


parts = sorted(data["parts"], key=top_of)
for part in parts:
    px, py, pz = part["p"]
    sx, sy, sz = part["s"]
    if sy > 400:  # sky pillar etc.
        continue
    r, u, l = part["r"], part["u"], part["l"]
    color = tuple(part["c"])
    alpha = int(255 * (1 - part["t"]) * (0.9 if part["m"] != "ForceField" else 0.25))
    if part["m"] == "Neon":
        color = tuple(min(255, int(c * 1.25 + 30)) for c in color)
    # Project the oriented box onto the XZ plane: 8 corners -> convex hull.
    corners = []
    for a in (-0.5, 0.5):
        for b in (-0.5, 0.5):
            for c in (-0.5, 0.5):
                x = px + r[0] * sx * a + u[0] * sy * b - l[0] * sz * c
                z = pz + r[2] * sx * a + u[2] * sy * b - l[2] * sz * c
                corners.append(to_px(x, z))
    if part["shape"] in ("Ball", "Ellipsoid", "Cylinder"):
        xs = [p[0] for p in corners]
        zs = [p[1] for p in corners]
        cx, cz = sum(xs) / 8, sum(zs) / 8
        rx = (max(xs) - min(xs)) / 2
        rz = (max(zs) - min(zs)) / 2
        if part["shape"] == "Cylinder":
            # Cylinders lie along local X; a vertical one projects as a circle.
            if abs(r[1]) > 0.9:
                d = max(sy, sz) * SCALE / 2
                rx = rz = d
        draw.ellipse([cx - rx, cz - rz, cx + rx, cz + rz], fill=color + (alpha,))
    else:
        pts = sorted(set(corners))

        def cross(o, a, b):
            return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

        lower, upper = [], []
        for p in pts:
            while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
                lower.pop()
            lower.append(p)
        for p in reversed(pts):
            while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
                upper.pop()
            upper.append(p)
        hull = lower[:-1] + upper[:-1]
        if len(hull) >= 3:
            draw.polygon(hull, fill=color + (alpha,))

if len(sys.argv) > 3:
    x0, z0, x1, z1 = [float(v) for v in sys.argv[3].split(",")]
    box = (int((x0 - origin) * SCALE), int((z0 - origin) * SCALE), int((x1 - origin) * SCALE), int((z1 - origin) * SCALE))
    image = image.crop(box)
    image = image.resize((image.width * 2 if image.width < 600 else image.width, image.height * 2 if image.width < 600 else image.height), Image.LANCZOS)
else:
    image = image.resize((size // 2, size // 2), Image.LANCZOS)
image.save(out_path)
print("saved", out_path, image.size)
