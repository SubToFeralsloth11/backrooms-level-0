"""Sculpt the Hollow and the Watcher as signed-distance fields, mesh them with
marching cubes, auto-skin to a skeleton, and write meshes/<name>.crt for Godot.

Anatomy is built from bones (cone-capsules), muscle bellies (ellipsoids),
ribs, vertebrae, scapulae, tendons and carved sockets/mouth, blended with
smooth-min so it reads as one continuous gaunt body, plus fine skin noise.

Run: python3 tools/sculpt_creatures.py
"""
import os
import struct
import sys
import time

import numpy as np
from scipy import ndimage
from skimage.measure import marching_cubes

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "meshes")
os.makedirs(OUT, exist_ok=True)
V = np.array


def norm(v):
    v = np.asarray(v, np.float64)
    return v / np.linalg.norm(v)


# ------------------------------------------------------------------ SDF prims
class Prim:
    def __init__(self, kind, k, region=0, carve=False, **p):
        self.kind, self.k, self.region, self.carve, self.p = kind, k, region, carve, p

    def bbox(self):
        p = self.p
        if self.kind == "cap":
            r = max(p["ra"], p["rb"])
            lo = np.minimum(p["a"], p["b"]) - r
            hi = np.maximum(p["a"], p["b"]) + r
        else:  # ellipsoid
            r = np.max(p["r"])
            lo, hi = p["c"] - r, p["c"] + r
        pad = self.k * 2 + 0.01
        return lo - pad, hi + pad

    def sdf(self, X, Y, Z):
        p = self.p
        if self.kind == "cap":
            a, b, ra, rb = p["a"], p["b"], p["ra"], p["rb"]
            ba = b - a
            l2 = ba.dot(ba)
            px, py, pz = X - a[0], Y - a[1], Z - a[2]
            h = np.clip((px * ba[0] + py * ba[1] + pz * ba[2]) / l2, 0, 1)
            dx, dy, dz = px - ba[0] * h, py - ba[1] * h, pz - ba[2] * h
            return np.sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * h)
        # ellipsoid with orientation basis (rows = local axes)
        c, r, R = p["c"], p["r"], p["R"]
        px, py, pz = X - c[0], Y - c[1], Z - c[2]
        lx = (px * R[0, 0] + py * R[0, 1] + pz * R[0, 2]) / r[0]
        ly = (px * R[1, 0] + py * R[1, 1] + pz * R[1, 2]) / r[1]
        lz = (px * R[2, 0] + py * R[2, 1] + pz * R[2, 2]) / r[2]
        k0 = np.sqrt(lx * lx + ly * ly + lz * lz)
        k1 = np.sqrt((lx / r[0]) ** 2 + (ly / r[1]) ** 2 + (lz / r[2]) ** 2)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def cap(a, b, ra, rb=None, k=0.02, region=0):
    return Prim("cap", k, region, a=V(a, float), b=V(b, float), ra=ra, rb=ra if rb is None else rb)


def ell(c, r, axes=None, k=0.02, region=0, carve=False):
    R = np.eye(3) if axes is None else np.array([norm(a) for a in axes])
    return Prim("ell", k, region, carve, c=V(c, float), r=V(r, float), R=R)


def basis_from(up, fwd):
    up = norm(up)
    fwd = norm(np.asarray(fwd) - up * np.dot(fwd, up))
    side = np.cross(up, fwd)
    return side, up, fwd


# ------------------------------------------------------------------ anatomy
class Body:
    def __init__(self):
        self.prims = []
        self.bones = []  # (name, parent, head, tail)

    def add(self, p):
        self.prims.append(p)

    def bone(self, name, parent, head, tail):
        self.bones.append((name, parent, V(head, float), V(tail, float)))

    def limb(self, a, b, ra, rb, k=0.02):
        self.add(cap(a, b, ra, rb, k))

    def torso(self, hips, chest, neck, belly_dir, scale=1.0):
        hips, chest, neck = V(hips, float), V(chest, float), V(neck, float)
        s, u, f = basis_from(chest - hips, belly_dir)
        L = np.linalg.norm(neck - hips)
        mid = (hips + chest) * 0.5
        # pelvis + iliac crests
        self.add(ell(hips, V([0.15, 0.09, 0.09]) * scale, [s, u, f], k=0.04))
        for side in (-1, 1):
            self.add(ell(hips + s * side * 0.12 * scale + u * 0.05 + f * 0.03, V([0.035, 0.03, 0.04]) * scale, [s, u, f], k=0.03))
        # sunken abdomen, narrow waist
        self.add(ell(mid + f * 0.005, V([0.125, 0.17, 0.08]) * scale, [s, u, f], k=0.06))
        # obliques / love-handle remnants and lats give the waist a real silhouette
        for side in (-1, 1):
            self.add(ell(mid + s * side * 0.085 * scale + u * 0.02, V([0.035, 0.13, 0.06]) * scale, [s, u, f], k=0.05))
        # ribcage
        rc = chest + u * 0.06 * scale
        self.add(ell(rc, V([0.152, 0.205, 0.108]) * scale, [s, u, f], k=0.05))
        for side in (-1, 1):
            # pectorals, lats, trapezius: wasted but present
            self.add(ell(rc + s * side * 0.07 * scale + f * 0.07 * scale + u * 0.09 * scale, V([0.07, 0.055, 0.03]) * scale, [s, u, f], k=0.05))
            self.add(ell(rc + s * side * 0.11 * scale - f * 0.03 * scale + u * 0.0, V([0.04, 0.15, 0.07]) * scale, [s, u, f], k=0.05))
            self.add(ell(rc + s * side * 0.08 * scale - f * 0.05 * scale + u * 0.19 * scale, V([0.08, 0.04, 0.045]) * scale, [s, u, f], k=0.05))
        # ribs: arcs wrapping front and sides, slightly descending toward the front
        for i in range(8):
            y = (-0.14 + i * 0.035) * scale
            rx = (0.148 - abs(i - 4.5) * 0.006) * scale
            rz = 0.104 * scale * (1 - abs(i - 4) * 0.02)
            pts = []
            for t in np.linspace(-2.5, 2.5, 16):
                droop = -0.03 * scale * (np.cos(t) * 0.5 + 0.5)
                pts.append(rc + u * (y + droop) + s * np.sin(t) * rx + f * np.cos(t) * rz)
            for a, b in zip(pts, pts[1:]):
                self.add(cap(a * 0.985 + rc * 0.015, b * 0.985 + rc * 0.015, 0.0065 * scale, k=0.014))
        # sternum + clavicles
        self.add(cap(rc + f * 0.1 * scale - u * 0.1 * scale, rc + f * 0.105 * scale + u * 0.15 * scale, 0.012 * scale, k=0.02))
        top = rc + u * 0.19 * scale + f * 0.06 * scale
        for side in (-1, 1):
            self.add(cap(top, top + s * side * 0.16 * scale - f * 0.02, 0.012 * scale, 0.01 * scale, k=0.015))
            # scapula: flat plate on the back
            self.add(ell(rc + s * side * 0.09 * scale - f * 0.085 * scale + u * 0.06 * scale, V([0.06, 0.08, 0.012]) * scale, [s, u, f], k=0.03))
        # vertebrae bumps down the back
        n = 22
        for i in range(n):
            t = i / (n - 1)
            p = hips + (neck - hips) * t
            back = -f * (0.07 + 0.035 * np.sin(t * np.pi)) * scale
            self.add(ell(p + back, V([0.014, 0.014, 0.02]) * scale, [s, u, f], k=0.012))
        return s, u, f

    def neck_head(self, neck, head, crown_dir, face_dir, jaw_open=0.6, scale=1.0, eyes=False):
        neck, head = V(neck, float), V(head, float)
        s, u, f = basis_from(crown_dir, face_dir)
        # thin neck + tendons
        self.add(cap(neck, head - u * 0.02, 0.047 * scale, 0.04 * scale, k=0.035))
        for side in (-1, 1):
            self.add(cap(head + s * side * 0.05 * scale - f * 0.02 + u * 0.02, neck + s * side * 0.03 * scale + f * 0.06 * scale, 0.011 * scale, k=0.02))
        # cranium (elongated back), brow, cheekbones, temples carved
        cr = head + u * 0.1 * scale - f * 0.01 * scale
        self.add(ell(cr, V([0.078, 0.11, 0.105]) * scale, [s, u, f], k=0.03))
        self.add(ell(cr - f * 0.05 * scale + u * 0.02 * scale, V([0.07, 0.09, 0.08]) * scale, [s, u, f], k=0.03))
        self.add(cap(cr + f * 0.088 * scale + u * 0.0 + s * -0.05 * scale, cr + f * 0.088 * scale + s * 0.05 * scale, 0.014 * scale, k=0.02))
        for side in (-1, 1):
            self.add(ell(cr + s * side * 0.055 * scale + f * 0.06 * scale - u * 0.06 * scale, V([0.018, 0.016, 0.03]) * scale, [s, u, f], k=0.02))
            # sunken temples & cheeks
            self.add(ell(cr + s * side * 0.08 * scale + f * 0.03 * scale - u * 0.0, V([0.02, 0.035, 0.03]) * scale, [s, u, f], k=0.015, carve=True))
            self.add(ell(cr + s * side * 0.06 * scale + f * 0.055 * scale - u * 0.1 * scale, V([0.016, 0.025, 0.02]) * scale, [s, u, f], k=0.015, carve=True))
            # deep empty eye sockets (region 2 = wet black)
            self.add(ell(cr + s * side * 0.034 * scale + f * 0.1 * scale - u * 0.03 * scale, V([0.022, 0.017, 0.028]) * scale, [s, u, f], k=0.008, carve=True, region=2))
        # upper jaw / maxilla, nose cavity
        mx = cr + f * 0.085 * scale - u * 0.1 * scale
        self.add(ell(mx, V([0.045, 0.03, 0.035]) * scale, [s, u, f], k=0.025))
        self.add(ell(cr + f * 0.12 * scale - u * 0.06 * scale, V([0.012, 0.016, 0.02]) * scale, [s, u, f], k=0.006, carve=True, region=2))
        # mandible hanging open: rotate about jaw hinge around side axis
        hinge = cr - u * 0.07 * scale + f * 0.02 * scale
        ca, sa = np.cos(jaw_open), np.sin(jaw_open)
        ju = u * ca - f * sa
        jf = f * ca + u * sa
        chin = hinge - ju * 0.07 * scale + jf * 0.07 * scale
        for side in (-1, 1):
            self.add(cap(hinge + s * side * 0.055 * scale, chin + s * side * 0.02 * scale, 0.014 * scale, 0.012 * scale, k=0.02, region=0))
        self.add(cap(chin - s * 0.02 * scale, chin + s * 0.02 * scale, 0.014 * scale, k=0.02))
        # mouth cavity carved between jaws (region 1 = gums/flesh)
        mouth = (mx + chin) * 0.5 - u * 0.0 + f * 0.0
        self.add(ell(mouth + f * 0.01, V([0.035, 0.05, 0.045]) * scale, [s, (ju + u) / 2, f], k=0.01, carve=True, region=1))
        # teeth: separate mesh primitives
        teeth = []
        for row, (base, up_dir) in enumerate(((mx - u * 0.02 * scale, -u), (chin + ju * 0.015 * scale, ju))):
            for i in range(11):
                a = (i - 5) / 5 * 1.2
                p = base + s * np.sin(a) * 0.04 * scale + (f if row == 0 else jf) * (np.cos(a) * 0.03 - 0.005) * scale
                ln = (0.016 + 0.01 * np.random.rand()) * scale
                teeth.append(cap(p, p + up_dir * ln, 0.0045 * scale, 0.0018 * scale, k=0.001))
        return teeth, hinge, chin

    def hand(self, wrist, fwd, palm_n, side, scale=1.0, finger_len=1.0):
        """fwd: direction fingers point; palm_n: palm normal."""
        wrist = V(wrist, float)
        fwd = norm(fwd)
        palm_n = norm(np.asarray(palm_n) - fwd * np.dot(palm_n, fwd))
        across = np.cross(fwd, palm_n) * side
        self.add(ell(wrist, V([0.03, 0.02, 0.022]) * scale, [across, palm_n, fwd], k=0.015))
        tips = []
        for i in range(4):
            off = (i - 1.5) * 0.019 * scale
            base = wrist + across * off * 0.6 + fwd * 0.012 * scale
            knuckle = wrist + across * off + fwd * (0.085 - abs(i - 1.2) * 0.006) * scale
            self.add(cap(base, knuckle, 0.0085 * scale, 0.0095 * scale, k=0.012))  # metacarpal
            self.add(ell(knuckle - palm_n * 0.003, V([0.011, 0.01, 0.011]) * scale, k=0.006))
            L = V([0.06, 0.042, 0.036]) * finger_len * scale * (1.0 - abs(i - 1.3) * 0.08)
            d = fwd * np.cos(0.0) + across * (i - 1.5) * 0.06
            p = knuckle
            curl = 0.0
            for seg in range(3):
                curl += 0.28
                dd = norm(d * np.cos(curl) - palm_n * np.sin(curl))
                q = p + dd * L[seg]
                r0 = (0.0085 - seg * 0.0012) * scale
                r1 = (0.0075 - seg * 0.0016) * scale if seg < 2 else 0.0022 * scale
                self.add(cap(p, q, r0, r1, k=0.004, region=3 if seg == 2 else 0))
                p = q
            tips.append(p)
        # thumb
        tb = wrist + across * -0.03 * scale + fwd * 0.02 * scale - palm_n * 0.01
        td = norm(fwd * 0.6 - across * 0.6 - palm_n * 0.4)
        p = tb
        for seg, ln in enumerate((0.045, 0.035, 0.03)):
            q = p + td * ln * finger_len * scale
            self.add(cap(p, q, (0.012 - seg * 0.002) * scale, (0.01 - seg * 0.003) * scale, k=0.008, region=3 if seg == 2 else 0))
            td = norm(td + fwd * 0.3 - palm_n * 0.25)
            p = q
        return tips

    def arm(self, sh, el, wr, scale=1.0):
        sh, el, wr = V(sh, float), V(el, float), V(wr, float)
        self.add(ell(sh, V([0.055, 0.06, 0.055]) * scale, k=0.035))  # deltoid
        self.add(cap(sh, el, 0.036 * scale, 0.03 * scale, k=0.025))  # humerus
        mid = sh + (el - sh) * 0.4
        d = norm(el - sh)
        self.add(ell(mid, V([0.044, 0.12, 0.044]) * scale, basis_from(d, [0, 0, 1]), k=0.035))  # wasted bicep/tricep
        self.add(ell(el, V([0.03, 0.028, 0.03]) * scale, k=0.015))  # elbow knob
        # radius + ulna: two bones give the flat, bony forearm
        s, u, f = basis_from(wr - el, [0, 0, 1])
        self.add(cap(el + s * 0.012, wr + s * 0.014, 0.017 * scale, 0.012 * scale, k=0.012))
        self.add(cap(el - s * 0.012, wr - s * 0.012, 0.016 * scale, 0.011 * scale, k=0.012))
        self.add(ell(el + (wr - el) * 0.28, V([0.042, 0.11, 0.032]) * scale, [s, u, f], k=0.035))

    def leg(self, hp, kn, an, toe_dir, scale=1.0):
        hp, kn, an = V(hp, float), V(kn, float), V(an, float)
        self.add(cap(hp, kn, 0.05 * scale, 0.036 * scale, k=0.03))
        s, u, f = basis_from(hp - kn, toe_dir)
        self.add(ell(hp + (kn - hp) * 0.4 + f * 0.01, V([0.07, 0.19, 0.068]) * scale, [s, u, f], k=0.05))  # thigh
        self.add(ell(kn + f * 0.03 * scale, V([0.028, 0.032, 0.02]) * scale, [s, u, f], k=0.012))  # patella
        self.add(cap(kn, an, 0.03 * scale, 0.021 * scale, k=0.022))  # tibia
        s2, u2, f2 = basis_from(kn - an, toe_dir)
        self.add(ell(kn + (an - kn) * 0.3 - f2 * 0.025, V([0.048, 0.12, 0.045]) * scale, [s2, u2, f2], k=0.04))  # calf
        for side in (-1, 1):
            self.add(ell(an + s2 * side * 0.025 * scale, V([0.014, 0.014, 0.014]) * scale, k=0.01))  # malleoli
        # long bony foot with toes
        toe_dir = norm(toe_dir)
        heel = an - u2 * 0.04 * scale - toe_dir * 0.035 * scale
        ball = heel + toe_dir * 0.17 * scale
        self.add(cap(heel, ball, 0.03 * scale, 0.025 * scale, k=0.03))
        self.add(cap(an, ball + u2 * 0.015, 0.02 * scale, 0.015 * scale, k=0.02))
        for t in range(5):
            o = s2 * (t - 2) * 0.017 * scale
            self.add(cap(ball + o, ball + o + toe_dir * (0.05 - abs(t - 1) * 0.006) * scale - u2 * 0.01, 0.0095 * scale, 0.006 * scale, k=0.006, region=3))


# ------------------------------------------------------------------ meshing
def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax_sub(a, b, k):
    """carve b out of a (smooth subtraction)."""
    h = np.clip(0.5 - 0.5 * (a + b) / k, 0, 1)
    return a * (1 - h) + (-b) * h + k * h * (1 - h)


def mesh_prims(prims, res, noise_amp=0.0, seed=0):
    lo = np.min([p.bbox()[0] for p in prims if not p.carve], axis=0) - 0.02
    hi = np.max([p.bbox()[1] for p in prims if not p.carve], axis=0) + 0.02
    shape = np.ceil((hi - lo) / res).astype(int) + 1
    print("  grid", shape, "=", int(np.prod(shape)) // 1000, "k cells", file=sys.stderr)
    xs = lo[0] + np.arange(shape[0]) * res
    ys = lo[1] + np.arange(shape[1]) * res
    zs = lo[2] + np.arange(shape[2]) * res
    D = np.full(shape, 1.0, np.float32)
    region_d = {}
    for p in prims:
        blo, bhi = p.bbox()
        i0 = np.clip(np.floor((blo - lo) / res).astype(int), 0, shape - 1)
        i1 = np.clip(np.ceil((bhi - lo) / res).astype(int) + 1, 0, shape)
        if np.any(i1 <= i0):
            continue
        X, Y, Z = np.meshgrid(xs[i0[0]:i1[0]], ys[i0[1]:i1[1]], zs[i0[2]:i1[2]], indexing="ij")
        d = p.sdf(X, Y, Z).astype(np.float32)
        sl = (slice(i0[0], i1[0]), slice(i0[1], i1[1]), slice(i0[2], i1[2]))
        if p.carve:
            D[sl] = smax_sub(D[sl], d, p.k)
        else:
            D[sl] = smin(d, D[sl], p.k)
        if p.region:
            if p.region not in region_d:
                region_d[p.region] = np.full(shape, 1.0, np.float32)
            R = region_d[p.region]
            R[sl] = np.minimum(R[sl], np.abs(d) if p.carve else d)
    if noise_amp > 0:
        rng = np.random.default_rng(seed)
        for scale_cells, amp in ((6, noise_amp), (2.5, noise_amp * 0.35)):
            small = rng.standard_normal(np.maximum(shape // int(max(scale_cells, 1)) + 2, 2)).astype(np.float32)
            big = ndimage.zoom(small, np.array(shape) / np.array(small.shape), order=3)[: shape[0], : shape[1], : shape[2]]
            pad = [(0, s - b) for s, b in zip(shape, big.shape)]
            big = np.pad(big, pad, mode="edge")
            D += big * amp
    verts, faces, normals, _ = marching_cubes(D, 0.0, spacing=(res, res, res), gradient_direction="ascent")
    verts = verts + lo
    normals = -normals
    # vertex regions: 0 skin, 1 gums/mouth, 2 wet black socket, 3 nail/claw
    region = np.zeros(len(verts), np.float32)
    idx = np.clip(np.round((verts - lo) / res).astype(int), 0, shape - 1)
    for r, R in region_d.items():
        vals = R[idx[:, 0], idx[:, 1], idx[:, 2]]
        region[vals < res * 2.5] = r
    return verts.astype(np.float32), normals.astype(np.float32), faces.astype(np.int32), region


def seg_dist(P, a, b):
    ba = b - a
    l2 = max(ba.dot(ba), 1e-9)
    h = np.clip(((P - a) @ ba) / l2, 0, 1)
    return np.linalg.norm(P - a - h[:, None] * ba, axis=1)


def skin_weights(verts, bones, region=None):
    verts = verts.astype(np.float64)
    D = np.stack([seg_dist(verts, h, t) for _, _, h, t in bones], axis=1)
    order = np.argsort(D, axis=1)[:, :4]
    d4 = np.take_along_axis(D, order, axis=1)
    w = 1.0 / np.maximum(d4, 0.004) ** 4
    w[:, 1:] *= (d4[:, 1:] < d4[:, :1] * 1.6 + 0.02)  # don't bleed across distant parts
    w /= w.sum(axis=1, keepdims=True)
    return order.astype(np.int32), w.astype(np.float32)


def write_crt(path, bones, surfaces):
    with open(path, "wb") as fh:
        fh.write(b"CRT2")
        fh.write(struct.pack("<I", len(bones)))
        names = [b[0] for b in bones]
        for name, parent, head, tail in bones:
            nb = name.encode()
            pi = names.index(parent) if parent else -1
            ph = bones[pi][2] if pi >= 0 else np.zeros(3)
            local = head - ph
            fh.write(struct.pack("<B", len(nb)) + nb + struct.pack("<i3f", pi, *local))
        fh.write(struct.pack("<I", len(surfaces)))
        for verts, normals, faces, region, bi, bw in surfaces:
            fh.write(struct.pack("<II", len(verts), faces.size))
            fh.write(verts.tobytes())
            fh.write(normals.tobytes())
            fh.write(region.astype(np.float32).tobytes())
            fh.write(bi.tobytes())
            fh.write(bw.tobytes())
            # Godot wants clockwise front faces
            fh.write(faces[:, ::-1].copy().tobytes())
    print("  wrote", path, os.path.getsize(path) // 1024, "KiB", file=sys.stderr)


def build(name, body, teeth, res):
    t0 = time.time()
    # LOD / shadow proxy: same sculpt at ~2.2x coarser resolution, no noise, no teeth
    lv, ln, lf, lr = mesh_prims(body.prims, res * 2.2)
    lbi, lbw = skin_weights(lv, body.bones)
    write_crt(os.path.join(OUT, name + "_lod.crt"), body.bones, [(lv, ln, lf, lr, lbi, lbw)])
    print(f"  {name}_lod: {len(lf)} tris", file=sys.stderr)
    v, n, f, r = mesh_prims(body.prims, res, noise_amp=0.0011, seed=hash(name) % 1000)
    bi, bw = skin_weights(v, body.bones)
    tv, tn, tf, tr = mesh_prims(teeth, 0.0022)
    tr[:] = 4
    tbi, tbw = skin_weights(tv, body.bones)
    write_crt(os.path.join(OUT, name + ".crt"), body.bones, [(v, n, f, r, bi, bw), (tv, tn, tf, tr, tbi, tbw)])
    print(f"  {name}: {len(v)} verts {len(f)} tris, teeth {len(tf)} tris, {time.time() - t0:.1f}s", file=sys.stderr)


# ------------------------------------------------------------------ creatures
def hollow():
    """2.55 m eyeless gaunt biped, permanently hunched, arms past the knees. Faces +Z."""
    b = Body()
    hips, spine, chest, neck, head = V([0, 1.22, 0]), V([0, 1.42, 0.0]), V([0, 1.66, 0.07]), V([0, 1.95, 0.19]), V([0, 2.04, 0.27])
    b.bone("hips", None, hips, spine)
    b.bone("spine", "hips", spine, chest)
    b.bone("chest", "spine", chest, neck)
    b.bone("neck", "chest", neck, head)
    b.bone("head", "neck", head, head + V([0, 0.2, 0.03]))
    b.torso(hips, chest, neck, [0, 0, 1], scale=1.05)
    teeth, hinge, chin = b.neck_head(neck, head, [0, 1, 0.25], [0, -0.1, 1], jaw_open=0.55, scale=1.12)
    b.bone("jaw", "head", hinge, chin)
    for side, nm in ((1, "l"), (-1, "r")):
        sh = V([side * 0.2, 1.9, 0.11])
        el = V([side * 0.25, 1.4, 0.1])
        wr = V([side * 0.26, 0.92, 0.15])
        b.arm(sh, el, wr, scale=1.05)
        tips = b.hand(wr, [0.0, -1, 0.12], [-side, 0, 0.25], side, scale=1.2, finger_len=1.9)
        b.bone("shoulder_" + nm, "chest", sh, el)
        b.bone("elbow_" + nm, "shoulder_" + nm, el, wr)
        b.bone("wrist_" + nm, "elbow_" + nm, wr, wr + V([0, -0.1, 0.01]))
        b.bone("fingers_" + nm, "wrist_" + nm, wr + V([0, -0.1, 0.012]), np.mean(tips, axis=0))
        hp = V([side * 0.1, 1.17, 0.0])
        kn = V([side * 0.11, 0.64, 0.05])
        an = V([side * 0.11, 0.09, -0.03])
        b.leg(hp, kn, an, [side * 0.12, 0, 1], scale=1.05)
        b.bone("hip_" + nm, "hips", hp, kn)
        b.bone("knee_" + nm, "hip_" + nm, kn, an)
        b.bone("ankle_" + nm, "knee_" + nm, an, an + V([0, -0.05, 0.17]))
    build("hollow", b, teeth, 0.0072)


def watcher():
    """Crawler: torso slung horizontally ~0.65 m up, spider-splayed limbs, head
    hanging upside-down under the shoulders. Faces +Z."""
    b = Body()
    hips, spine, chest, neck, head = V([0, 0.66, -0.5]), V([0, 0.7, -0.22]), V([0, 0.72, 0.06]), V([0, 0.66, 0.38]), V([0, 0.46, 0.46])
    b.bone("hips", None, hips, spine)
    b.bone("spine", "hips", spine, chest)
    b.bone("chest", "spine", chest, neck)
    b.bone("neck", "chest", neck, head)
    b.bone("head", "neck", head, head + V([0, -0.2, 0.0]))
    b.torso(hips, chest, neck, [0, -1, 0], scale=0.98)
    # crown points at the floor, face looks forward: the head is upside down
    teeth, hinge, chin = b.neck_head(neck, head, [0, -1, -0.15], [0, 0, 1], jaw_open=0.85, scale=1.05)
    b.bone("jaw", "head", hinge, chin)
    for side, nm in ((1, "l"), (-1, "r")):
        sh = V([side * 0.18, 0.72, 0.28])
        el = V([side * 0.58, 1.0, 0.42])
        wr = V([side * 0.66, 0.08, 0.62])
        b.arm(sh, el, wr, scale=0.95)
        tips = b.hand(wr, [side * 0.25, -0.15, 1.0], [0, -1, 0], side, scale=1.15, finger_len=2.0)
        b.bone("shoulder_" + nm, "chest", sh, el)
        b.bone("elbow_" + nm, "shoulder_" + nm, el, wr)
        b.bone("wrist_" + nm, "elbow_" + nm, wr, wr + V([0, 0, 0.1]))
        b.bone("fingers_" + nm, "wrist_" + nm, wr + V([0, 0, 0.1]), np.mean(tips, axis=0))
        hp = V([side * 0.11, 0.64, -0.55])
        kn = V([side * 0.55, 0.98, -0.5])
        an = V([side * 0.62, 0.1, -0.78])
        b.leg(hp, kn, an, [side * 0.3, 0, -1], scale=0.95)
        b.bone("hip_" + nm, "hips", hp, kn)
        b.bone("knee_" + nm, "hip_" + nm, kn, an)
        b.bone("ankle_" + nm, "knee_" + nm, an, an + V([0, -0.05, -0.17]))
    build("watcher", b, teeth, 0.0072)


if __name__ == "__main__":
    np.random.seed(7)
    which = sys.argv[1:] or ["hollow", "watcher"]
    for w in which:
        print("sculpting", w, file=sys.stderr)
        globals()[w]()
