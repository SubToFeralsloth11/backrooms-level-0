"""Generate blood / damp-stain decals and the six keypad symbols.

Run: python3 tools/gen_decals.py   (from project root)
Outputs RGBA PNGs into textures/decals/ and textures/symbols/.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RNG = np.random.default_rng(1337)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEC = os.path.join(ROOT, "textures", "decals")
SYM = os.path.join(ROOT, "textures", "symbols")
os.makedirs(DEC, exist_ok=True)
os.makedirs(SYM, exist_ok=True)


def fbm(size, octaves=5, base=4):
    """Tileable-ish fractal value noise in [0,1]."""
    out = np.zeros((size, size), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        res = base * (2 ** o)
        grid = RNG.random((res + 1, res + 1)).astype(np.float32)
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        out += amp * (np.asarray(img, np.float32) / 255.0)
        total += amp
        amp *= 0.5
    return out / total


def save_rgba(path, color, alpha, shade=None):
    h, w = alpha.shape
    rgb = np.ones((h, w, 3), np.float32) * np.array(color, np.float32)[None, None, :]
    if shade is not None:
        rgb *= shade[..., None]
    arr = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    Image.fromarray((arr * 255).astype(np.uint8), "RGBA").save(path)


def blood_shade(alpha, size):
    # Thicker pools are darker; edges lighter/thinner, with clot noise.
    thick = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(size / 90)), np.float32) / 255
    n = fbm(size, 5, 8)
    return np.clip(1.25 - 0.45 * thick - 0.3 * n, 0.45, 1.3)


def splat(size=1024, drops=260):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    c = size / 2
    # core pool built from overlapping blobs
    for _ in range(40):
        r = RNG.uniform(0.05, 0.16) * size
        x, y = c + RNG.normal(0, size * 0.06), c + RNG.normal(0, size * 0.06)
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    # radial spatter streaks and droplets
    for _ in range(drops):
        ang = RNG.uniform(0, math.tau)
        dist = abs(RNG.normal(0, 0.22)) * size + 0.12 * size
        dist = min(dist, 0.47 * size)
        x, y = c + math.cos(ang) * dist, c + math.sin(ang) * dist
        r = max(1.5, RNG.exponential(0.008) * size * (1.0 - dist / size))
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        if RNG.random() < 0.25:  # elongated tail pointing away from impact
            tx, ty = x + math.cos(ang) * r * 4, y + math.sin(ang) * r * 4
            d.line([x, y, tx, ty], fill=255, width=max(1, int(r * 0.8)))
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(2.2)), np.float32) / 255
    edge = fbm(size, 5, 10)
    a = np.clip((a - 0.35 + 0.25 * (edge - 0.5)) * 6, 0, 1)
    return a


def smear(size=1024):
    """Drag smear: a body/hand dragged across carpet, streaky."""
    a = np.zeros((size, size), np.float32)
    ys = np.linspace(-1, 1, size)[:, None]
    xs = np.linspace(-1, 1, size)[None, :]
    width = 0.45 + 0.12 * np.sin(xs * 3.0) + 0.1 * xs
    band = np.exp(-(ys / width) ** 4 * 2.0)
    streak = fbm(size, 4, 6)
    streak = np.asarray(Image.fromarray((streak * 255).astype(np.uint8)).resize((size, 8)).resize((size, size), Image.BICUBIC), np.float32) / 255
    fade = np.clip((xs + 0.98) * 1.6, 0, 1) ** 0.6 * np.clip((0.98 - xs) * 4, 0, 1)
    a = band * (0.35 + 0.9 * streak) * fade
    a = np.clip((a - 0.18) * 1.6, 0, 1)
    return a


def handprint(size=512):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    s = size
    d.ellipse([s * 0.30, s * 0.45, s * 0.72, s * 0.88], fill=230)  # palm
    fingers = [(0.30, 0.30, 0.11), (0.42, 0.18, 0.10), (0.54, 0.16, 0.10), (0.65, 0.24, 0.09)]
    for fx, fy, fw in fingers:
        d.rounded_rectangle([s * fx, s * fy, s * (fx + fw), s * 0.55], radius=int(s * 0.05), fill=230)
    d.rounded_rectangle([s * 0.12, s * 0.50, s * 0.36, s * 0.62], radius=int(s * 0.05), fill=230)  # thumb
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(3)), np.float32) / 255
    skinlines = fbm(size, 6, 24)
    a = np.clip(a * (0.45 + 0.9 * skinlines) - 0.15, 0, 1)
    # vertical drips running down from the print
    out = Image.fromarray((a * 255).astype(np.uint8))
    d = ImageDraw.Draw(out)
    for _ in range(5):
        x = RNG.uniform(0.32, 0.7) * s
        y0 = RNG.uniform(0.6, 0.85) * s
        y1 = min(s - 4, y0 + RNG.uniform(0.08, 0.3) * s)
        w = int(RNG.uniform(3, 7))
        d.line([x, y0, x, y1], fill=200, width=w)
        d.ellipse([x - w, y1 - w, x + w, y1 + w], fill=200)
    return np.asarray(out, np.float32) / 255


def drips(size=1024):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    for _ in range(26):
        x = RNG.uniform(0.08, 0.92) * size
        y0 = RNG.uniform(0.0, 0.25) * size
        y1 = y0 + RNG.uniform(0.15, 0.75) * size
        w = RNG.uniform(3, 10)
        pts = []
        for t in np.linspace(0, 1, 30):
            pts.append((x + math.sin(t * 9 + x) * 2.0, y0 + (y1 - y0) * t))
        d.line(pts, fill=255, width=int(w * 0.8))
        d.ellipse([x - w * 0.7, y1 - w * 0.7, x + w * 0.7, y1 + w * 1.1], fill=255)
    for _ in range(14):
        x = RNG.uniform(0.05, 0.95) * size
        y = RNG.uniform(0, 0.2) * size
        r = RNG.uniform(20, 70)
        d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=255)
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    return np.clip(a * 1.3, 0, 1)


def damp(size=1024):
    n = fbm(size, 6, 3)
    yy, xx = np.mgrid[-1:1:size * 1j, -1:1:size * 1j]
    r = np.sqrt(xx ** 2 + yy ** 2) + (n - 0.5) * 0.6
    body = np.clip(1.0 - r, 0, 1)
    # tide-line rings typical of dried water stains
    ring = np.exp(-((r - 0.55) / 0.025) ** 2) * 0.8 + np.exp(-((r - 0.38) / 0.02) ** 2) * 0.5
    a = np.clip(body * 0.35 + ring * (r < 0.6), 0, 1) * (r < 0.62)
    return a.astype(np.float32)


for i in range(4):
    a = splat(1024, int(RNG.integers(160, 340)))
    save_rgba(os.path.join(DEC, f"blood_splat_{i + 1}.png"), (0.48, 0.03, 0.02), a, blood_shade(a, 1024))
for i in range(2):
    a = smear(1024)
    save_rgba(os.path.join(DEC, f"blood_smear_{i + 1}.png"), (0.40, 0.035, 0.02), a, blood_shade(a, 1024))
a = handprint(512)
save_rgba(os.path.join(DEC, "blood_hand.png"), (0.45, 0.02, 0.015), a, blood_shade(a, 512))
a = drips(1024)
save_rgba(os.path.join(DEC, "blood_drips.png"), (0.45, 0.02, 0.015), a, blood_shade(a, 1024))
for i in range(2):
    a = damp(1024)
    save_rgba(os.path.join(DEC, f"stain_damp_{i + 1}.png"), (0.22, 0.17, 0.08), a)


# ---------------- symbols: rough hand-painted strokes ----------------
def jitter_line(d, pts, w):
    out = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        for t in np.linspace(0, 1, 12):
            out.append((x0 + (x1 - x0) * t + RNG.normal(0, 3), y0 + (y1 - y0) * t + RNG.normal(0, 3)))
    d.line(out, fill=255, width=w, joint="curve")


def circle_pts(cx, cy, r, a0=0, a1=math.tau, n=48, spiral=0.0):
    return [(cx + math.cos(a) * (r + spiral * k), cy + math.sin(a) * (r + spiral * k)) for k, a in enumerate(np.linspace(a0, a1, n))]


S = 512
W = 34
symbols = {
    "eye": lambda d: (jitter_line(d, [(70, 256), (256, 150), (442, 256), (256, 362), (70, 256)], W),
                      d.ellipse([216, 216, 296, 296], fill=255)),
    "triangle": lambda d: jitter_line(d, [(256, 60), (450, 430), (62, 430), (256, 60)], W),
    "spiral": lambda d: jitter_line(d, circle_pts(256, 256, 20, 0, math.tau * 3.2, 140, spiral=1.35), W),
    "ladder": lambda d: (jitter_line(d, [(170, 50), (170, 462)], W), jitter_line(d, [(342, 50), (342, 462)], W),
                         [jitter_line(d, [(170, y), (342, y)], W) for y in (130, 256, 382)]),
    "cross": lambda d: (jitter_line(d, circle_pts(256, 256, 190), W), jitter_line(d, [(120, 120), (392, 392)], W), jitter_line(d, [(392, 120), (120, 392)], W)),
    "hand": lambda d: (jitter_line(d, [(256, 470), (256, 120)], W), jitter_line(d, [(256, 300), (130, 160)], W), jitter_line(d, [(256, 300), (382, 160)], W),
                       jitter_line(d, [(256, 230), (170, 70)], W), jitter_line(d, [(256, 230), (342, 70)], W)),
}
for idx, (name, fn) in enumerate(symbols.items()):
    im = Image.new("L", (S, S), 0)
    fn(ImageDraw.Draw(im))
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255
    rough = fbm(S, 5, 16)
    a = np.clip(a * (0.7 + 0.6 * rough), 0, 1)
    save_rgba(os.path.join(SYM, f"sym_{idx}.png"), (1, 1, 1), a)
    print("symbol", idx, name)
print("done")
