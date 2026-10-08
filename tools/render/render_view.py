"""Approximate 3D preview of the generated world (tools/.cache/world.json).

A small numpy software rasteriser: parts become triangle meshes, terrain a
heightmap mesh; flat diffuse lighting (sunny day from the exported Phase 5.5
palette, or the old night look with NIGHT=1), emissive Neon, distance fog and
a bloom pass. It is NOT Roblox's renderer, just a composition check.

usage: python3 render_view.py world.json out.png "camX,camY,camZ" "targetX,targetY,targetZ" [width height]
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageFilter

data = json.load(open(sys.argv[1]))
out_path = sys.argv[2]
cam = np.array([float(v) for v in sys.argv[3].split(",")])
target = np.array([float(v) for v in sys.argv[4].split(",")])
W = int(sys.argv[5]) if len(sys.argv) > 5 else 960
H = int(sys.argv[6]) if len(sys.argv) > 6 else 540
FOV = math.radians(70)

import os
PALETTE = data.get("palette")
DAY = PALETTE is not None and os.environ.get("NIGHT") != "1"
if DAY:
    # Sunny afternoon (Config/Palette.Lighting): bright ambient, warm sun.
    FOG = np.array(PALETTE["horizon"], dtype=float)
    FOG_DENSITY = float(os.environ.get("FOG", "0.0022"))
    AMBIENT = np.array([0.62, 0.62, 0.68])
    MOON_DIR = np.array([-0.45, 0.8, 0.35])
    MOON = np.array([0.55, 0.53, 0.48])
else:
    FOG = np.array([120, 96, 175], dtype=float)
    FOG_DENSITY = float(os.environ.get("FOG", "0.0042"))
    AMBIENT = np.array([0.40, 0.37, 0.58])
    MOON_DIR = np.array([-0.35, 0.85, 0.4])
    MOON = np.array([0.55, 0.55, 0.75])
MOON_DIR /= np.linalg.norm(MOON_DIR)

ZONE = {
    "basin": (78, 70, 110), "rim": (86, 168, 134), "meadow": (86, 168, 134),
    "river": (190, 172, 206), "outer": (86, 168, 134), "edge": (104, 94, 134),
}
PATH = {"road": (132, 124, 160), "spoke": (150, 140, 176), "plaza": (78, 70, 110)}
MATERIAL = {
    "Grass": (86, 168, 134), "LeafyGrass": (70, 148, 122), "Rock": (104, 94, 134), "Slate": (78, 70, 110),
    "Cobblestone": (150, 140, 176), "Pavement": (132, 124, 160), "Sand": (190, 172, 206), "Ground": (110, 96, 120),
    "Basalt": (54, 48, 76), "Limestone": (196, 186, 214), "CrackedLava": (255, 120, 90), "Water": (70, 130, 210),
}
WATER = np.array([70, 130, 210], dtype=float)
WATER_Y = 16.5
if DAY:
    MATERIAL.update({k: tuple(v) for k, v in PALETTE["terrain"].items()})
    WATER = np.array(PALETTE["water"], dtype=float)

tris = []  # (v0, v1, v2, color, emissive, alpha)


def add_tri(a, b, c, color, emissive=False, alpha=1.0):
    tris.append((a, b, c, color, emissive, alpha))


# --- terrain mesh -------------------------------------------------------
step = data["step"]
origin = data["origin"]
samples = data["samples"]
n = len(samples)
stride = 2  # every 2 samples -> 4 stud grid
grid = {}
for zi in range(0, n, stride):
    for xi in range(0, n, stride):
        s = samples[zi][xi]
        if s:
            x = origin + xi * step + step / 2
            z = origin + zi * step + step / 2
            h, zone, path = s[0], s[1], s[2]
            if len(s) > 3:
                col = np.array(MATERIAL.get(s[3], (120, 120, 120)), dtype=float)
            else:
                col = np.array(PATH.get(path) or ZONE.get(zone, (120, 120, 120)), dtype=float)
            if len(s) > 3 and s[3] == "CrackedLava":
                col = col * 1.1
            grid[(xi, zi)] = (np.array([x, h, z]), col, zone == "river" and h < WATER_Y)
for (xi, zi), (p00, c00, w00) in grid.items():
    p10 = grid.get((xi + stride, zi))
    p01 = grid.get((xi, zi + stride))
    p11 = grid.get((xi + stride, zi + stride))
    if p10 and p01 and p11:
        col = (c00 + p10[1] + p01[1] + p11[1]) / 4
        add_tri(p00, p11[0], p10[0], col)
        add_tri(p00, p01[0], p11[0], col)
        if w00 or p11[2]:
            y = WATER_Y
            add_tri(np.array([p00[0], y, p00[2]]), np.array([p11[0][0], y, p11[0][2]]), np.array([p10[0][0], y, p10[0][2]]), WATER, False, 0.55)
            add_tri(np.array([p00[0], y, p00[2]]), np.array([p01[0][0], y, p01[0][2]]), np.array([p11[0][0], y, p11[0][2]]), WATER, False, 0.55)

# --- part meshes -----------------------------------------------------------
BOX_FACES = [
    (0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3),
]


def icosphere():
    t = (1 + 5 ** 0.5) / 2
    verts = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    verts = [np.array(v) / np.linalg.norm(v) for v in verts]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
             (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    cache = {}

    def mid(a, b):
        key = tuple(sorted((a, b)))
        if key not in cache:
            m = verts[a] + verts[b]
            verts.append(m / np.linalg.norm(m))
            cache[key] = len(verts) - 1
        return cache[key]

    new = []
    for a, b, c in faces:
        ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
        new += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
    return np.array(verts), new


SPHERE_V, SPHERE_F = icosphere()

# Terrain fills: balls/cylinders/blocks of terrain. Carved (Air) blocks are
# drawn as tunnel walls only when the camera is close (cave views).
for fill in data.get("fills", []):
    p = np.array(fill["p"])
    r, u, l = np.array(fill["r"]), np.array(fill["u"]), np.array(fill["l"])
    sx, sy, sz = fill["s"]
    back = -l
    if fill["m"] == "Air":
        if fill["op"] != "Block" or np.linalg.norm(p - cam) > max(sz, 40):
            continue
        color = np.array(MATERIAL["Rock"], dtype=float) * 0.8
        corners = []
        for i in range(8):
            cx_ = (i >> 2 & 1) - 0.5
            cy_ = (i >> 1 & 1) - 0.5
            cz_ = (i & 1) - 0.5
            corners.append(p + r * cx_ * sx + u * cy_ * sy + back * cz_ * sz)
        for a, b, c, d in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6)]:
            add_tri(corners[a], corners[b], corners[c], color)
            add_tri(corners[a], corners[c], corners[d], color)
        continue
    if sy > 60 or sx > 120:
        continue  # underside mass: never in view
    color = np.array(MATERIAL.get(fill["m"], (110, 100, 140)), dtype=float)
    if fill["op"] == "Ball":
        for a, b, c in SPHERE_F:
            pts = [p + SPHERE_V[i] * sx / 2 for i in (a, b, c)]
            add_tri(pts[0], pts[1], pts[2], color)
    elif fill["op"] == "Cylinder":
        seg = 14
        for k in range(seg):
            a0 = 2 * math.pi * k / seg
            a1 = 2 * math.pi * (k + 1) / seg
            for end in (-0.5, 0.5):
                c = p + u * sy * end
                add_tri(c, c + r * math.cos(a0) * sx / 2 + back * math.sin(a0) * sz / 2, c + r * math.cos(a1) * sx / 2 + back * math.sin(a1) * sz / 2, color)
            b0 = p - u * sy / 2 + r * math.cos(a0) * sx / 2 + back * math.sin(a0) * sz / 2
            b1 = p - u * sy / 2 + r * math.cos(a1) * sx / 2 + back * math.sin(a1) * sz / 2
            add_tri(b0, b0 + u * sy, b1 + u * sy, color)
            add_tri(b0, b1 + u * sy, b1, color)

for part in data["parts"]:
    material = part["m"]
    if material == "ForceField" or part["t"] > 0.9:
        continue
    p = np.array(part["p"])
    r, u, l = np.array(part["r"]), np.array(part["u"]), np.array(part["l"])
    sx, sy, sz = part["s"]
    if sy > 400 or sx > 400:
        continue
    color = np.array(part["c"], dtype=float)
    emissive = material == "Neon"
    alpha = 1 - part["t"]
    if material == "Glass":
        alpha = min(alpha, 0.55)
    back = -l  # local +Z axis
    shape = part["shape"]
    if shape in ("Ball", "Ellipsoid"):
        for a, b, c in SPHERE_F:
            pts = []
            for i in (a, b, c):
                v = SPHERE_V[i]
                pts.append(p + r * v[0] * sx / 2 + u * v[1] * sy / 2 + back * v[2] * sz / 2)
            add_tri(pts[0], pts[1], pts[2], color, emissive, alpha)
    elif shape == "Cylinder":
        seg = 16
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            ring.append((math.cos(a), math.sin(a)))
        for end in (-0.5, 0.5):
            center = p + r * sx * end
            for k in range(seg):
                c0, s0 = ring[k]
                c1, s1 = ring[(k + 1) % seg]
                v0 = center + u * c0 * sy / 2 + back * s0 * sz / 2
                v1 = center + u * c1 * sy / 2 + back * s1 * sz / 2
                add_tri(center, v0, v1, color, emissive, alpha)
        for k in range(seg):
            c0, s0 = ring[k]
            c1, s1 = ring[(k + 1) % seg]
            a0 = p - r * sx / 2 + u * c0 * sy / 2 + back * s0 * sz / 2
            a1 = p - r * sx / 2 + u * c1 * sy / 2 + back * s1 * sz / 2
            b0 = a0 + r * sx
            b1 = a1 + r * sx
            add_tri(a0, b0, b1, color, emissive, alpha)
            add_tri(a0, b1, a1, color, emissive, alpha)
    else:
        corners = []
        for i in range(8):
            cx = (i >> 2 & 1) - 0.5
            cy = (i >> 1 & 1) - 0.5
            cz = (i & 1) - 0.5
            corners.append(p + r * cx * sx + u * cy * sy + back * cz * sz)
        if shape == "Block" and part["n"] in ("Ramp",):
            pass
        for a, b, c, d in BOX_FACES:
            add_tri(corners[a], corners[b], corners[c], color, emissive, alpha)
            add_tri(corners[a], corners[c], corners[d], color, emissive, alpha)

print("triangles:", len(tris))

# --- camera ---------------------------------------------------------------
forward = target - cam
forward /= np.linalg.norm(forward)
right = np.cross(forward, np.array([0, 1, 0]))
right /= np.linalg.norm(right)
up = np.cross(right, forward)
f = 1 / math.tan(FOV / 2)
aspect = W / H

V = np.array([[t[0], t[1], t[2]] for t in tris])  # (N,3,3)
rel = V - cam
cx = rel @ right
cy = rel @ up
cz = rel @ forward  # depth
NEAR = 0.5
keep = (cz > NEAR).all(axis=1)

# Lighting per triangle.
e1 = V[:, 1] - V[:, 0]
e2 = V[:, 2] - V[:, 0]
normals = np.cross(e1, e2)
lengths = np.linalg.norm(normals, axis=1, keepdims=True)
normals = normals / np.maximum(lengths, 1e-9)
centers = V.mean(axis=1)
to_cam = cam - centers
facing = np.sign((normals * to_cam).sum(axis=1))
normals = normals * facing[:, None]
diffuse = np.clip(normals @ MOON_DIR, 0, 1)
colors = np.array([t[3] for t in tris])
emissive = np.array([t[4] for t in tris])
alphas = np.array([t[5] for t in tris])
lit = colors * (AMBIENT + MOON * diffuse[:, None] * 0.9)
lit = np.where(emissive[:, None], np.clip(colors * 1.25 + 25, 0, 255), lit)
dist = np.linalg.norm(to_cam, axis=1)
fog = 1 - np.exp(-FOG_DENSITY * dist)
fog = np.where(emissive, fog * 0.45, fog)
shaded = lit * (1 - fog[:, None]) + FOG * fog[:, None]

sx_ = (cx / cz) * f / aspect
sy_ = (cy / cz) * f
px = (sx_ + 1) * 0.5 * W
py = (1 - sy_) * 0.5 * H

img = np.zeros((H, W, 3))
rng = np.random.default_rng(3)
if DAY:
    # Sky: blue gradient + a few puffy white clouds.
    top = np.array(PALETTE["sky"], dtype=float) * 0.82
    horizon = np.array(PALETTE["horizon"], dtype=float)
    for yy in range(H):
        t = min(1.0, yy / (H * 0.75))
        img[yy, :] = top * (1 - t) + horizon * t
    YY, XX = np.mgrid[0:H, 0:W]
    for _ in range(9):
        cx0, cy0 = rng.integers(0, W), rng.integers(int(H * 0.05), int(H * 0.45))
        for k in range(4):
            rx = rng.integers(int(W * 0.04), int(W * 0.08))
            ry = int(rx * 0.55)
            ox = cx0 + (k - 1.5) * rx * 0.9
            oy = cy0 + rng.integers(-ry // 2, ry // 2 + 1)
            mask = ((XX - ox) / rx) ** 2 + ((YY - oy) / ry) ** 2 < 1
            img[mask] = img[mask] * 0.15 + np.array([255, 255, 255]) * 0.85
else:
    # Sky: gradient + stars.
    for yy in range(H):
        t = yy / H
        img[yy, :] = np.array([22, 14, 52]) * (1 - t) + np.array([118, 92, 170]) * t
    for _ in range(500):
        x, y = rng.integers(0, W), rng.integers(0, int(H * 0.7))
        img[y, x] = [235, 230, 255]
zbuf = np.full((H, W), np.inf)
glow = np.zeros((H, W, 3))

order_opaque = [i for i in np.nonzero(keep)[0] if alphas[i] >= 0.99]
order_alpha = sorted([i for i in np.nonzero(keep)[0] if alphas[i] < 0.99], key=lambda i: -cz[i].mean())


def raster(i, blend):
    x0, x1, x2 = px[i]
    y0, y1, y2 = py[i]
    minx = max(int(math.floor(min(x0, x1, x2))), 0)
    maxx = min(int(math.ceil(max(x0, x1, x2))), W - 1)
    miny = max(int(math.floor(min(y0, y1, y2))), 0)
    maxy = min(int(math.ceil(max(y0, y1, y2))), H - 1)
    if minx > maxx or miny > maxy:
        return
    area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    if abs(area) < 1e-9:
        return
    xs = np.arange(minx, maxx + 1) + 0.5
    ys = np.arange(miny, maxy + 1) + 0.5
    X, Y = np.meshgrid(xs, ys)
    w0 = ((x1 - X) * (y2 - Y) - (x2 - X) * (y1 - Y)) / area
    w1 = ((x2 - X) * (y0 - Y) - (x0 - X) * (y2 - Y)) / area
    w2 = 1 - w0 - w1
    inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
    if not inside.any():
        return
    z0, z1, z2 = cz[i]
    depth = 1 / (w0 / z0 + w1 / z1 + w2 / z2)
    region = zbuf[miny:maxy + 1, minx:maxx + 1]
    mask = inside & (depth < region)
    if not mask.any():
        return
    col = shaded[i]
    target_region = img[miny:maxy + 1, minx:maxx + 1]
    if blend:
        a = alphas[i]
        target_region[mask] = target_region[mask] * (1 - a) + col * a
    else:
        target_region[mask] = col
        region[mask] = depth[mask]
        glow_region = glow[miny:maxy + 1, minx:maxx + 1]
        glow_region[mask] = col if emissive[i] else 0
        return
    if emissive[i]:
        glow[miny:maxy + 1, minx:maxx + 1][mask] = col


for i in order_opaque:
    raster(i, False)
for i in order_alpha:
    raster(i, True)

base = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
bloom = Image.fromarray(np.clip(glow, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius=9))
out = np.clip(np.asarray(base, dtype=float) + np.asarray(bloom, dtype=float) * (0.35 if DAY else 0.85), 0, 255).astype(np.uint8)
Image.fromarray(out).save(out_path)
print("saved", out_path)
