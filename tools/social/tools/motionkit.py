"""Motion toolkit for reels: animated procedural textures (lava, water, ash, embers, light leaks, scan lines),
archive-film treatment, 2.5D parallax, and transitions with real motion blur (whip pan, zoom match-cut,
circle / crack / lava-tongue mask wipes, steam flash) plus camera shake.
Images are numpy uint8/float arrays H×W×3 (RGB). Textures are computed at 1/4 resolution and upscaled."""
import math, numpy as np, cv2
W, H = 1080, 1920
LW, LH = W // 4, H // 4
def ease(x): x = min(1.0, max(0.0, x)); return x * x * (3 - 2 * x)
def ease_io(x): x = min(1.0, max(0.0, x)); return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2
def to_np(im): return np.asarray(im.convert("RGB"), np.float32) if hasattr(im, "convert") else np.asarray(im, np.float32)

# ——— noise ———
_R = np.random.default_rng(42)
_G = [cv2.resize(_R.random((LH // s + 3, LW // s + 3)).astype(np.float32), (LW * 2 + 2 * s, LH * 2 + 2 * s), interpolation=cv2.INTER_CUBIC)
      for s in (48, 24, 12, 6)]          # tileable-ish noise planes at 4 scales (2× size so we can scroll)
def fbm(t, speed=(8, 14), warp=18.0, octaves=4, seed=0):
    """Domain-warped fractal noise at LW×LH, values ~0..1, flowing with time."""
    out = np.zeros((LH, LW), np.float32); amp = 0.5; tot = 0
    for i, g in enumerate(_G[:octaves]):
        ox = int((t * speed[0] * (1 + i * 0.6) + seed * 37 + i * 50) % (g.shape[1] - LW)); oy = int((t * speed[1] * (1 + i * 0.4) + seed * 53 + i * 31) % (g.shape[0] - LH))
        out += g[oy:oy + LH, ox:ox + LW] * amp; tot += amp; amp *= 0.5
    out /= tot
    if warp:
        g = _G[1]; ox = int((t * 5 + 200 + seed * 11) % (g.shape[1] - LW)); oy = int((t * 3 + 90) % (g.shape[0] - LH))
        dx = (g[oy:oy + LH, ox:ox + LW] - 0.5) * warp * 2; dy = (_G[0][oy:oy + LH, ox:ox + LW] - 0.5) * warp * 2
        xx, yy = np.meshgrid(np.arange(LW, dtype=np.float32), np.arange(LH, dtype=np.float32))
        out = cv2.remap(out, xx + dx + 3 * math.sin(t * 0.7), yy + dy, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    return out
def palette(v, stops):
    """Map v (0..1) through colour stops [(pos, (r,g,b)), …]."""
    pos = np.array([s[0] for s in stops], np.float32); cols = np.array([s[1] for s in stops], np.float32)
    return np.stack([np.interp(v, pos, cols[:, c]) for c in range(3)], -1)
LAVA = [(0, (6, 4, 4)), (0.45, (28, 8, 5)), (0.7, (140, 20, 6)), (0.85, (255, 90, 31)), (0.95, (255, 196, 90)), (1, (255, 246, 210))]
WATER = [(0, (3, 8, 16)), (0.5, (8, 26, 52)), (0.78, (40, 90, 170)), (0.92, (120, 170, 255)), (1, (230, 244, 255))]
AURORA_P = [(0, (4, 8, 10)), (0.6, (8, 30, 30)), (0.85, (61, 224, 168)), (1, (210, 255, 240))]
def up(a): return cv2.resize(a, (W, H), interpolation=cv2.INTER_CUBIC)
def lava_field(t, heat=1.0, seed=0):
    """Glowing cracked crust: ridged warped noise → hot veins in a dark crust."""
    n = fbm(t, (6, 10), 22, 4, seed); r = 1 - np.abs(2 * n - 1)       # ridges where noise crosses 0.5
    v = np.clip(r ** (6 / heat) * 1.05 + 0.25 * fbm(t * 0.6, (3, 4), 0, 2, seed + 3) - 0.1, 0, 1)
    return up(palette(v, LAVA))
def water_field(t, seed=1):
    """Moving caustics on dark water."""
    n = fbm(t, (10, -16), 26, 4, seed); r = 1 - np.abs(2 * n - 1)
    return up(palette(np.clip(r ** 4 * 1.1, 0, 1), WATER))
def steam_field(t, seed=2):
    """Soft white fog (0..1 alpha at full res)."""
    n = fbm(t, (4, -22), 14, 3, seed); return up(np.clip((n - 0.35) * 2.2, 0, 1))
def scanlines(img, t, gap=6, a=0.10, speed=40):
    y = (np.arange(H) + t * speed) % gap; m = (y < gap / 2).astype(np.float32)[:, None, None]
    return img * (1 - a * m)
def stripes(t, col=(255, 90, 31), gap=46, width=10, angle=-20, speed=60, a=0.18):
    """Diagonal moving hazard lines as an additive layer."""
    yy, xx = np.mgrid[0:LH, 0:LW].astype(np.float32) * 4
    d = (xx * math.cos(math.radians(angle)) + yy * math.sin(math.radians(angle)) + t * speed) % gap
    m = up((d < width).astype(np.float32))[..., None]
    return m * np.array(col, np.float32) * a

# ——— particles ———
class Particles:
    def __init__(self, n, seed, kind):
        r = np.random.default_rng(seed); self.k = kind
        self.x, self.y = r.uniform(0, W, n), r.uniform(0, H, n)
        self.v, self.s, self.ph, self.f = r.uniform(40, 160, n), r.uniform(1.5, 6, n), r.uniform(0, 6.28, n), r.uniform(0.3, 1.4, n)
    def layer(self, t, a=1.0):
        """Returns (rgb_add, alpha) at full res; ash falls grey, embers rise orange with glow."""
        L = np.zeros((LH, LW), np.float32)
        if self.k == "ash": ys = (self.y + self.v * t * 0.8) % (H + 40) - 20; xs = (self.x + 30 * np.sin(t * self.f + self.ph) - 25 * t) % W
        else: ys = (self.y - self.v * t * 1.6) % (H + 40) - 20; xs = (self.x + 40 * np.sin(t * self.f * 1.7 + self.ph)) % W
        for x, y, s, ph in zip(xs / 4, ys / 4, self.s, self.ph):
            fl = 0.6 + 0.4 * math.sin(t * 9 + ph * 3) if self.k == "ember" else 1
            cv2.circle(L, (int(x), int(y)), max(1, int(s / 3)), float(fl), -1, cv2.LINE_AA)
        if self.k == "ember": L = L + cv2.GaussianBlur(L, (0, 0), 3) * 1.5
        A = up(np.clip(L * a, 0, 1))[..., None]
        col = np.array((205, 200, 196) if self.k == "ash" else (255, 140, 50), np.float32)
        return A, col
    def apply(self, img, t, a=1.0):
        A, col = self.layer(t, a)
        return img * (1 - A * 0.85) + col * A if self.k == "ash" else np.minimum(255, img + col * A)
def light_leak(img, t, col=(255, 110, 40), a=0.35, seed=0):
    """Drifting warm light leak (screen blend)."""
    yy, xx = np.mgrid[0:LH, 0:LW].astype(np.float32)
    cx = LW * (0.5 + 0.6 * math.sin(t * 0.35 + seed)); cy = LH * (0.4 + 0.5 * math.sin(t * 0.23 + seed * 2))
    g = np.exp(-(((xx - cx) / (LW * 0.55)) ** 2 + ((yy - cy) / (LH * 0.35)) ** 2)) * (0.7 + 0.3 * math.sin(t * 1.3 + seed))
    L = up(g)[..., None] * np.array(col, np.float32) * a
    return 255 - (255 - img) * (255 - L) / 255
def grain(img, fi, amount=7):
    n = np.random.default_rng(fi).normal(0, amount, (LH, LW)).astype(np.float32)
    return img + cv2.resize(n, (W, H), interpolation=cv2.INTER_NEAREST)[..., None]
_VIG = None
def vignette(img, s=0.5):
    global _VIG
    if _VIG is None:
        yy, xx = np.mgrid[0:H, 0:W]; r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
        _VIG = np.clip((r - 0.55) / 0.9, 0, 1)[..., None].astype(np.float32)
    return img * (1 - _VIG * s)

# ——— archive film look for old photos ———
def archive(arr, t, fi, sepia=0.35, seed=0):
    """Warm, flickering, dusty 1970s print: tint, gate weave, flicker, dust specks and a scratch."""
    a = arr.astype(np.float32); g = a.mean(-1, keepdims=True)
    a = a * (1 - sepia) + g * np.array((1.08, 0.98, 0.84), np.float32) * sepia
    a *= 0.94 + 0.06 * math.sin(fi * 2.1) * math.sin(fi * 0.77 + seed)
    r = np.random.default_rng(fi * 7 + seed); h, w = a.shape[:2]
    for _ in range(r.integers(2, 6)):
        x, y = int(r.uniform(0, w)), int(r.uniform(0, h)); cv2.circle(a, (x, y), int(r.uniform(1, 3.5)), (20, 18, 16) if r.random() < 0.6 else (235, 230, 220), -1, cv2.LINE_AA)
    if r.random() < 0.35: x = int(r.uniform(0.1, 0.9) * w); cv2.line(a, (x, 0), (x + int(r.uniform(-8, 8)), h), (215, 210, 200), 1, cv2.LINE_AA)
    return np.clip(a, 0, 255)
def weave(fi, amp=2.0): return int(round(amp * math.sin(fi * 1.9))), int(round(amp * 0.7 * math.cos(fi * 1.3)))

# ——— framing helpers ———
def cover(arr, w, h, z=1.0, fx=0.5, fy=0.5, dx=0.0, dy=0.0):
    """Scale `arr` to cover w×h × z and crop around focus (fx, fy) with pixel pan (dx, dy)."""
    ih, iw = arr.shape[:2]; s = max(w / iw, h / ih) * z; nw, nh = int(iw * s + 1), int(ih * s + 1)
    x = int(np.clip((nw - w) * fx + dx, 0, nw - w)); y = int(np.clip((nh - h) * fy + dy, 0, nh - h))
    # crop in source space first (fast), then resize only what we need
    sx0, sy0, sw, sh = x / s, y / s, w / s, h / s
    M = np.array([[s, 0, -x], [0, s, -y]], np.float32)
    return cv2.warpAffine(arr.astype(np.float32), M, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
def parallax(arr, t, dur, horizon=0.5, soft=0.12, z0=1.08, z1=1.2, fg_extra=0.10, pan=60, fx=0.5, fy=0.5):
    """2.5D: split the photo at a horizon into sky/far and ground/near layers that zoom & pan at different rates."""
    k = ease(t / dur) if dur else 1
    bg = cover(arr, W, H, z0 + (z1 - z0) * k * 0.5, fx, fy, -pan * k * 0.4, 0)
    fg = cover(arr, W, H, z0 + (z1 - z0) * k + fg_extra * k, fx, fy, pan * k, -pan * 0.3 * k)
    y = np.linspace(0, 1, H, dtype=np.float32); m = np.clip((y - (horizon - soft)) / (2 * soft), 0, 1)[:, None, None]
    return bg * (1 - m) + fg * m
def card(arr, w, h, border=12, radius=20, shadow=True):
    """Photo in a white rounded frame with drop shadow → RGBA float (h+pad, w+pad, 4)."""
    im = cover(arr, w, h); pad = 60; cw, ch = w + 2 * border, h + 2 * border
    out = np.zeros((ch + 2 * pad, cw + 2 * pad, 4), np.float32)
    if shadow:
        s = np.zeros(out.shape[:2], np.float32); cv2.rectangle(s, (pad + 10, pad + 24), (pad + cw - 10, pad + ch + 6), 1.0, -1)
        out[..., 3] = cv2.GaussianBlur(s, (0, 0), 18) * 0.6
    m = np.zeros(out.shape[:2], np.float32); _rrect(m, pad, pad, cw, ch, radius + border)
    out[..., :3] = out[..., :3] * (1 - m[..., None]) + 246 * m[..., None]; out[..., 3] = np.maximum(out[..., 3], m)
    m2 = np.zeros((h, w), np.float32); _rrect(m2, 0, 0, w, h, radius)
    sl = out[pad + border:pad + border + h, pad + border:pad + border + w]; sl[..., :3] = sl[..., :3] * (1 - m2[..., None]) + im * m2[..., None]
    return out
def _rrect(m, x, y, w, h, r):
    cv2.rectangle(m, (x + r, y), (x + w - r, y + h), 1.0, -1); cv2.rectangle(m, (x, y + r), (x + w, y + h - r), 1.0, -1)
    for cx, cy in ((x + r, y + r), (x + w - r, y + r), (x + r, y + h - r), (x + w - r, y + h - r)): cv2.circle(m, (cx, cy), r, 1.0, -1, cv2.LINE_AA)
def over(base, rgba, cx, cy, s=1.0, rot=0.0, a=1.0):
    """Composite float RGBA layer centred at (cx, cy) with scale/rotation/opacity onto base (in place)."""
    if a <= 0.01 or s <= 0.02: return base
    h, w = rgba.shape[:2]; M = cv2.getRotationMatrix2D((w / 2, h / 2), rot, s); M[0, 2] += cx - w / 2; M[1, 2] += cy - h / 2
    x0, y0 = int(max(0, cx - w * s * 0.75 - 4)), int(max(0, cy - h * s * 0.75 - 4)); x1, y1 = int(min(W, cx + w * s * 0.75 + 4)), int(min(H, cy + h * s * 0.75 + 4))
    if x1 <= x0 or y1 <= y0: return base
    M[0, 2] -= x0; M[1, 2] -= y0
    L = cv2.warpAffine(rgba, M, (x1 - x0, y1 - y0), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    A = L[..., 3:4] * a; base[y0:y1, x0:x1] = base[y0:y1, x0:x1] * (1 - A) + L[..., :3] * A
    return base

# ——— transitions: a, b float RGB frames, k ∈ [0,1] ———
def _dblur(img, L, horizontal=True):
    """Directional motion blur at half resolution (fast) of length L px."""
    L = int(L / 2)
    if L < 2: return img
    sm = cv2.resize(img, (W // 2, H // 2), interpolation=cv2.INTER_AREA)
    sm = cv2.blur(sm, (L, 1) if horizontal else (1, L))
    return cv2.resize(sm, (W, H), interpolation=cv2.INTER_LINEAR)
def whip(a, b, k, direction=1):
    """Whip pan: both frames slide together, smeared by velocity-proportional motion blur."""
    e = ease_io(k); off = int(e * W) * direction; v = math.sin(math.pi * k)
    c = np.empty_like(a)
    if direction > 0:
        c[:, :W - off] = a[:, off:]; c[:, W - off:] = b[:, :off]
    else:
        off = -off; c[:, off:] = a[:, :W - off]; c[:, :off] = b[:, W - off:]
    return _dblur(c, 10 + 260 * v)
def whip_v(a, b, k, direction=1):
    """Vertical whip (up)."""
    e = ease_io(k); off = int(e * H); v = math.sin(math.pi * k); c = np.empty_like(a)
    c[:H - off] = a[off:]; c[H - off:] = b[:off]
    return _dblur(c, 10 + 300 * v, horizontal=False)
def _zoomblur(img, z, amount, cx=W / 2, cy=H / 2, n=6):
    sm = cv2.resize(img, (W // 2, H // 2), interpolation=cv2.INTER_AREA); acc = np.zeros_like(sm)
    for i in range(n):
        s = z * (1 + amount * i / n); M = cv2.getRotationMatrix2D((cx / 2, cy / 2), 0, s)
        acc += cv2.warpAffine(sm, M, (W // 2, H // 2), borderMode=cv2.BORDER_REFLECT)
    return cv2.resize(acc / n, (W, H), interpolation=cv2.INTER_LINEAR)
def zoom_cut(a, b, k, cx=W / 2, cy=H / 2):
    """Zoom match-cut: punch into A with radial blur, land on B coming out of a blur."""
    if k < 0.5: e = ease(k * 2); return _zoomblur(a, 1 + 1.4 * e ** 2, 0.25 * e, cx, cy)
    e = 1 - ease((k - 0.5) * 2); return _zoomblur(b, 1 + 0.5 * e ** 2, 0.25 * e, cx, cy)
def circle_wipe(a, b, k, cx=W / 2, cy=H / 2, edge=(255, 90, 31)):
    r = ease_io(k) * math.hypot(W, H) * 0.6; m = np.zeros((H, W), np.float32); cv2.circle(m, (int(cx), int(cy)), int(r), 1.0, -1, cv2.LINE_AA)
    ring = np.zeros((H, W), np.float32); cv2.circle(ring, (int(cx), int(cy)), int(r), 1.0, 10, cv2.LINE_AA)
    ring = cv2.GaussianBlur(ring, (0, 0), 6) * 1.5 * math.sin(math.pi * k)
    m = m[..., None]; return np.minimum(255, a * (1 - m) + b * m + ring[..., None] * np.array(edge, np.float32))
_CRACK = {}
def crack_dist(seed=0):
    """Low-res distance field (in full-res px) to a jagged random-walk crack with side branches, roughened (cached)."""
    if seed not in _CRACK:
        r = np.random.default_rng(seed); m = np.full((LH, LW), 255, np.uint8); x = LW * 0.5; pts = []
        for y in range(0, LH + 8, 8): x += r.normal(0, 7); x = np.clip(x, LW * 0.25, LW * 0.75); pts.append((int(x), y))
        cv2.polylines(m, [np.array(pts)], False, 0, 1)
        for _ in range(7):                                  # side branches
            i = r.integers(2, len(pts) - 2); bx, by = pts[i]; br = [(bx, by)]
            for j in range(r.integers(3, 7)): bx += r.normal(0, 6) + (8 if r.random() < 0.5 else -8); by += r.normal(5, 4); br.append((int(bx), int(by)))
            cv2.polylines(m, [np.array(br)], False, 0, 1)
        _CRACK[seed] = cv2.distanceTransform(m, cv2.DIST_L2, 5) * 4 + (fbm(seed * 3.1, (0, 0), 0, 3, seed) - 0.5) * 50
    return _CRACK[seed]
def crack_mask(k, seed=0):
    """Opening crack: full-res 0..1 mask (1 = opened) and glowing rim intensity."""
    d = crack_dist(seed); r = ease(k) ** 1.6 * 1300 + 2
    m = np.clip((r - d) / 6, 0, 1); rim = np.exp(-np.maximum(0, d - r) / 18) * (1 - m) + np.exp(-np.maximum(0, r - d) / 10) * m * 0.6
    return up(m), up(rim * (0.4 + 0.6 * math.sin(math.pi * min(1, k * 1.5))))
def crack_wipe(a, b, k, seed=0):
    m, rim = crack_mask(k, seed)
    glow = rim[..., None] * np.array((255, 120, 40), np.float32) * 1.6
    return np.minimum(255, a * (1 - m[..., None]) + b * m[..., None] + glow)
def lava_wipe(a, b, k, seed=3):
    """A noisy molten front climbs from the bottom and leaves B behind it."""
    n = fbm(k * 2 + seed, (0, 0), 10, 3, seed); y = np.linspace(1, 0, LH, dtype=np.float32)[:, None]
    f = y + (n - 0.5) * 0.25; lvl = ease_io(k) * 1.35 - 0.12
    m = up(np.clip((lvl - f) * 30, 0, 1))[..., None]; rim = up(np.exp(-np.abs(f - lvl) * 40))[..., None]
    lava = lava_field(k * 3 + seed, 1.4)
    return np.minimum(255, a * (1 - m) + b * m * (1 - rim) + lava * rim * 1.2)
def steam_flash(a, b, k, seed=2):
    """White steam swallows A, clears onto B."""
    fog = steam_field(k * 3 + seed, seed); s = math.sin(math.pi * k); base = a if k < 0.5 else b
    A = np.clip(fog * 1.4 * s + s ** 3 * 0.6, 0, 1)[..., None]
    return base * (1 - A) + 238 * A
def shake(img, amp, fi):
    if amp < 0.5: return img
    dx, dy = int(amp * math.sin(fi * 2.7)), int(amp * 0.7 * math.cos(fi * 3.3))
    M = np.float32([[1, 0, dx], [0, 1, dy]]); return cv2.warpAffine(img, M, (W, H), borderMode=cv2.BORDER_REFLECT)
def chroma(img, px=4):
    """Chromatic aberration split for impact frames."""
    if px < 1: return img
    o = img.copy(); o[..., 0] = np.roll(img[..., 0], px, 1); o[..., 2] = np.roll(img[..., 2], -px, 1); return o
def speed_map(t, segs):
    """Speed-ramp: segs = [(t_start, speed), …] piecewise-constant → source time at reel time t."""
    src, prev_t, prev_s = 0.0, segs[0][0], segs[0][1]
    for ts, s in segs[1:]:
        if t < ts: break
        src += (ts - prev_t) * prev_s; prev_t, prev_s = ts, s
    return src + (t - prev_t) * prev_s
