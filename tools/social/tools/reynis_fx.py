"""Motion + sound helpers for the Reynisfjara reel (procedural textures, transitions, 2.5D parallax, synthesized SFX/music).
Everything is numpy/cv2 on CPU; textures are computed at reduced resolution and scaled up."""
import math, numpy as np, cv2
from PIL import Image
W, H, FPS, SR = 1080, 1920, 30, 48000
BG = (7, 9, 12); ACC = (255, 90, 31); AUR = (61, 224, 168); BLUE = (120, 170, 255)

def ease(x): x = min(1.0, max(0.0, x)); return x * x * (3 - 2 * x)
def eout(x): x = min(1.0, max(0.0, x)); return 1 - (1 - x) ** 3
def ein(x): x = min(1.0, max(0.0, x)); return x ** 3
def to_np(im): return np.asarray(im.convert("RGB"), dtype=np.uint8)
def to_im(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")

# ——— smooth value noise (precomputed octaves, animated by scrolling) ———
_RNG = np.random.default_rng(11)
_OCT = [cv2.resize(_RNG.random((s, s)).astype(np.float32), (512, 512), interpolation=cv2.INTER_CUBIC) for s in (6, 12, 24, 48)]
def noise(w, h, t, sx=0.0, sy=0.0, scale=1.0):
    """Tileable-ish fractal noise field (h, w) in 0..1, scrolling with time."""
    out = np.zeros((h, w), np.float32); amp, tot = 1.0, 0.0
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    for i, o in enumerate(_OCT):
        k = scale * (1 + i * 0.6); mx = ((xs * k + sx * t * (1 + i * 0.4) * 60 + i * 97) % 512).astype(np.float32)
        my = ((ys * k + sy * t * (1 + i * 0.4) * 60 + i * 53) % 512).astype(np.float32)
        out += amp * cv2.remap(o, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_WRAP); tot += amp; amp *= 0.55
    return out / tot

# ——— black sand: high-res grain tile that scrolls ———
_SAND = None
def sand(t, speed=60, tint=(1.0, 1.0, 1.05), dark=1.0):
    global _SAND
    if _SAND is None:
        r = np.random.default_rng(3)
        g = r.normal(0, 1, (H * 2 // 2, W // 2)).astype(np.float32)
        g = cv2.resize(g, (W, H * 2), interpolation=cv2.INTER_NEAREST) * 0.6 + cv2.GaussianBlur(r.normal(0, 1, (H * 2, W)).astype(np.float32), (0, 0), 1.2) * 1.6
        spark = (r.random((H * 2, W)) > 0.9985).astype(np.float32) * 120
        base = 22 + g * 9 + cv2.GaussianBlur(spark, (0, 0), 0.8) * 1.5
        _SAND = np.clip(base, 0, 255).astype(np.float32)
    off = int(t * speed) % H
    s = _SAND[off:off + H] * dark
    return np.stack([s * tint[0], s * tint[1], s * tint[2]], -1)

# ——— hexagonal basalt columns that pulse ———
_HEX = None
def basalt(t, glow=ACC, size=46):
    global _HEX
    w, h = W // 2, H // 2
    if _HEX is None:
        ys, xs = np.mgrid[0:h, 0:w].astype(np.float32); s = size / 2
        q = (math.sqrt(3) / 3 * xs - ys / 3) / s; r = (2 / 3 * ys) / s
        x, z = q, r; y = -x - z; rx, ry, rz = np.round(x), np.round(y), np.round(z)
        dx, dy, dz = abs(rx - x), abs(ry - y), abs(rz - z)
        c1 = (dx > dy) & (dx > dz); c2 = ~c1 & (dy > dz)
        rx = np.where(c1, -ry - rz, rx); ry = np.where(c2, -rx - rz, ry); rz = -rx - ry
        d = np.maximum(np.maximum(abs(x - rx), abs(y - ry)), abs(z - rz))      # 0 centre → 0.5 edge
        cell = (rx * 73.1 + rz * 31.7) % 1.0; cell = (np.sin(rx * 12.9898 + rz * 78.233) * 43758.5453) % 1.0
        _HEX = (d.astype(np.float32), cell.astype(np.float32), ys / h)
    d, cell, yy = _HEX
    face = 0.25 + 0.35 * cell + 0.25 * (0.5 - d)                    # bevelled column tops
    pulse = np.clip(np.sin(t * 2.2 - yy * 6 + cell * 6.28) * 0.5 + 0.5, 0, 1) ** 6
    edge = np.clip((d - 0.43) / 0.07, 0, 1)
    g = np.array(glow, np.float32) / 255
    rgb = face[..., None] * np.array([46, 50, 56], np.float32) * (1 - edge[..., None] * 0.85)
    rgb += (pulse * edge)[..., None] * g * 255 * 0.9 + (pulse * (1 - edge) * 0.10)[..., None] * g * 255
    return cv2.resize(rgb, (W, H), interpolation=cv2.INTER_LINEAR)

# ——— sea surface seen from above + foam edge (also used as the wave-wipe transition) ———
def sea(t, w=W // 3, h=H // 3):
    n = noise(w, h, t, 0.25, -0.6, 1.2); n2 = noise(w, h, t + 7, -0.3, -0.9, 2.4)
    v = n * 0.6 + n2 * 0.4
    deep = np.array([10, 30, 48], np.float32); hi = np.array([60, 120, 150], np.float32)
    rgb = deep + (hi - deep) * (v[..., None] ** 1.6)
    caust = np.clip(1 - abs(n2 - 0.5) * 14, 0, 1) ** 3
    rgb += caust[..., None] * 70
    return cv2.resize(rgb, (W, H), interpolation=cv2.INTER_CUBIC)
def wave_mask(t, line_y, amp=36, foam=90):
    """Per-pixel water coverage (water below a wobbling line at height line_y px). Returns (mask, foam) float32 (H, W)."""
    xs = np.arange(W, dtype=np.float32)
    edge = line_y + amp * np.sin(xs / 170 + t * 2.1) + amp * 0.6 * np.sin(xs / 61 - t * 3.3) + amp * 0.35 * np.sin(xs / 23 + t * 5)
    ys = np.arange(H, dtype=np.float32)[:, None]
    d = ys - edge[None, :]
    m = np.clip(d / 6 + 0.5, 0, 1)
    fn = cv2.resize(noise(W // 6, H // 6, t, 0.4, -0.8, 3.0), (W, H))
    f = np.clip(1 - d / foam, 0, 1) * (d > -4) * np.clip(fn * 2.2 - 0.4, 0, 1)
    return m.astype(np.float32), f.astype(np.float32)
def wave_wipe(a, b, p, t):
    """Transition: a wave sweeps up the screen; b is revealed behind its foam. a, b: float32 HxWx3."""
    y = H * 1.12 - (H * 1.35) * eout(p)
    m, f = wave_mask(t, y, 48, 160)
    trail = np.clip((np.arange(H)[:, None] - y) / 420, 0, 1)        # water thins out behind the front
    water = sea(t) * 0.9
    wm = (m * (1 - trail)).astype(np.float32)[..., None]
    out = a * (1 - m[..., None]) + b * m[..., None]
    out = out * (1 - wm * 0.85) + water * wm * 0.85
    out = out + f[..., None] * 235 * (1 - trail[..., None] * 0.5)
    return out

# ——— photo motion ———
def cover(src, scale=1.0):
    """Resize PIL image to cover W×H × scale (cached by caller). Returns float32 array."""
    s = max(W / src.width, H / src.height) * scale
    return np.asarray(src.convert("RGB").resize((int(src.width * s) + 2, int(src.height * s) + 2), Image.LANCZOS), np.float32)
_MAPS = {}
def parallax(big, t, dur, zoom=(1.0, 1.12), pan=(0.0, 0.0), depth_amp=60, fx_=0.5, fy=0.5):
    """2.5D: fake depth by vertical position (bottom = near) → near ground slides & scales more than the sky.
    big: float32 image already ≥ 1.25× cover. Returns HxWx3 float32."""
    k = ease(t / dur) if dur else 1.0
    z = zoom[0] + (zoom[1] - zoom[0]) * k
    bh, bw = big.shape[:2]
    key = (bw, bh)
    if key not in _MAPS:
        ys, xs = np.mgrid[0:H, 0:W].astype(np.float32); _MAPS[key] = (xs, ys, (ys / H) ** 1.6)
    xs, ys, dep = _MAPS[key]
    base = min(bw / W, bh / H) / 1.25                                   # 1 screen px in source px at z=1
    cx = bw * fx_ + pan[0] * k * W * base; cy = bh * fy + pan[1] * k * H * base
    zz = z * (1 + 0.10 * dep * k)                                       # foreground zooms faster
    sx = cx + (xs - W / 2) * base / zz + depth_amp * (k - 0.5) * dep * base
    sy = cy + (ys - H / 2) * base / zz
    return cv2.remap(big, sx, sy, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)

def whip(a, b, p, direction=1):
    """Whip-pan with true motion blur: A slides out, B slides in; blur ∝ velocity."""
    e = ease(p); off = int(W * e)
    strip = np.concatenate([a, b], 1) if direction > 0 else np.concatenate([b, a], 1)
    x0 = off if direction > 0 else W - off
    view = strip[:, x0:x0 + W]
    v = math.sin(math.pi * min(1, max(0, p)))                          # velocity profile
    k = int(2 + 240 * v)
    if k > 2: view = cv2.blur(view, (k, 1))
    return view
def zoom_cut(a, b, p):
    """Zoom match-cut: A punches in to 1.5× with radial-ish blur, B lands from 1.5× → 1."""
    def zb(img, z, bl):
        hh, ww = int(H / z), int(W / z); y0, x0 = (H - hh) // 2, (W - ww) // 2
        c = cv2.resize(img[y0:y0 + hh, x0:x0 + ww], (W, H), interpolation=cv2.INTER_LINEAR)
        if bl > 1: c = cv2.addWeighted(c, 0.5, cv2.resize(cv2.resize(c, (W // bl, H // bl)), (W, H)), 0.5, 0)
        return c
    if p < 0.5: q = ein(p * 2); return zb(a, 1 + 0.6 * q, int(1 + 10 * q))
    q = 1 - eout((p - 0.5) * 2); return zb(b, 1 + 0.6 * q, int(1 + 10 * q))
def flash(img, k, col=(255, 255, 255)): return img * (1 - k) + np.array(col, np.float32) * k
def light_leak(img, t, strength=0.35, col=ACC):
    w, h = W // 8, H // 8; ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx = w * (0.5 + 0.6 * math.sin(t * 0.37)); cy = h * (0.3 + 0.4 * math.sin(t * 0.23 + 1))
    g = np.exp(-(((xs - cx) / (w * 0.5)) ** 2 + ((ys - cy) / (h * 0.35)) ** 2))
    g = cv2.resize(g, (W, H))[..., None] * strength
    return img + g * np.array(col, np.float32) * (1 - img / 300)
_GR = [np.random.default_rng(i).normal(0, 1, (H // 2, W // 2)).astype(np.float32) for i in range(6)]
def grain(img, fi, amt=7):
    g = cv2.resize(_GR[fi % 6], (W, H), interpolation=cv2.INTER_NEAREST)
    return img + g[..., None] * amt
def vignette_map():
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32); r = np.sqrt(((xs - W / 2) / (W / 2)) ** 2 + ((ys - H / 2) / (H / 2)) ** 2)
    return (1 - np.clip((r - 0.55) / 0.9, 0, 1) * 0.6)[..., None]
def spray(t, n=140, seed=5, a=1.0, wind=600):
    """Wind-blown spray/streaks layer: returns float32 additive (H, W)."""
    r = np.random.default_rng(seed); x0 = r.uniform(0, W, n); y0 = r.uniform(0, H, n); v = r.uniform(0.5, 1.5, n); ln = r.uniform(30, 160, n)
    lay = np.zeros((H, W), np.float32)
    xs = (x0 + wind * v * t) % (W + 200) - 100; ys = y0 + 40 * np.sin(t * v + x0)
    for x, y, l, vv in zip(xs, ys, ln, v):
        cv2.line(lay, (int(x - l * vv), int(y)), (int(x), int(y)), float(160 * a * vv / 1.5), 2, cv2.LINE_AA)
    return cv2.GaussianBlur(lay, (0, 0), 1.2)
def shake(img, fi, amt):
    if amt <= 0.5: return img
    return np.roll(np.roll(img, int(math.sin(fi * 2.7) * amt), 1), int(math.cos(fi * 3.3) * amt * 0.7), 0)

# ——— SOUND (48 kHz mono float) ———
_R = np.random.default_rng(42)
def _bp(x, lo, hi):
    """FFT band-pass."""
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    m = ((f >= lo) & (f <= hi)).astype(np.float32); m = np.convolve(m, np.ones(31) / 31, "same")
    return np.fft.irfft(X * m, len(x)).astype(np.float32)
def _norm(x): return (x / (np.abs(x).max() + 1e-9)).astype(np.float32)
def whoosh(d=0.55, lo=300, hi=5000):
    n = int(d * SR); x = _R.normal(0, 1, n).astype(np.float32)
    a, b = _bp(x, lo, lo * 3), _bp(x, hi / 3, hi)
    tt = np.linspace(0, 1, n, dtype=np.float32); env = np.sin(np.pi * tt) ** 2 * (tt < 1)
    sweep = np.clip(tt * 1.6, 0, 1)
    return _norm((a * (1 - sweep) + b * sweep) * env) * 0.8
def impact(d=1.2, f0=70):
    n = int(d * SR); tt = np.arange(n) / SR
    f = f0 * (1 + 1.5 * np.exp(-tt * 18)); ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-tt * 3.2)
    click = _bp(_R.normal(0, 1, n).astype(np.float32), 80, 3000) * np.exp(-tt * 30) * 0.6
    return _norm(np.tanh((body + click) * 2.2)) * 0.95
def riser(d=1.8):
    n = int(d * SR); tt = np.linspace(0, 1, n, dtype=np.float32)
    x = _R.normal(0, 1, n).astype(np.float32); hi = _bp(x, 2000, 9000)
    f = 120 + 900 * tt ** 2; tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35 + np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR) * 0.15
    env = tt ** 2.2
    return _norm((hi * 0.6 + tone) * env) * 0.7
def ping(d=1.0, f=1318.5):
    n = int(d * SR); tt = np.arange(n) / SR
    s = (np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 1.5 * tt) * (tt > 0.11)) * np.exp(-tt * 6)
    return _norm(s * np.minimum(1, tt * 400)) * 0.55
def tick(d=0.08):
    n = int(d * SR); tt = np.arange(n) / SR
    return _norm(_bp(_R.normal(0, 1, n).astype(np.float32), 2500, 8000) * np.exp(-tt * 70)) * 0.4
def surf_bed(total, swells, surge=None):
    """Sea ambience: brown noise in two bands, amplitude follows wave periods; `surge` (t0, t1) adds a big rising run-up."""
    n = int(total * SR); w = _R.normal(0, 1, n).astype(np.float32)
    lo, mid = _bp(w, 40, 400), _bp(w, 400, 3500)
    tt = np.arange(n) / SR
    env = 0.35 + 0.65 * np.clip(np.sin(2 * np.pi * tt / swells) * 0.5 + 0.5, 0, 1) ** 3
    if surge:
        a, b = surge; g = np.clip((tt - a) / (b - a), 0, 1); s = np.where(tt < b, g ** 2, np.exp(-(tt - b) * 1.2)) * (tt > a)
        env = env + s * 2.2
    return _norm(lo * env * 1.2 + mid * env ** 1.5 * 0.5)
def wind_bed(total):
    n = int(total * SR); w = _R.normal(0, 1, n).astype(np.float32); tt = np.arange(n) / SR
    b1 = _bp(w, 250, 900); b2 = _bp(w, 900, 2600)
    l = 0.5 + 0.5 * np.sin(2 * np.pi * tt * 0.23) * np.sin(2 * np.pi * tt * 0.071 + 1)
    return _norm(b1 * (0.4 + 0.6 * l) + b2 * l ** 2 * 0.5)
def music(total, bpm=92):
    """Tense ambient pad (Dm–B♭–F–C) + soft pulse; synthesized."""
    n = int(total * SR); tt = np.arange(n) / SR; out = np.zeros(n, np.float32)
    bar = 4 * 60 / bpm
    chords = [(146.83, 174.61, 220.0), (116.54, 146.83, 174.61), (174.61, 220.0, 261.63), (130.81, 164.81, 196.0)]
    for i in range(int(total / bar) + 1):
        ch = chords[i % 4]; a = int(i * bar * SR); b = min(n, int((i + 1) * bar * SR) + int(0.6 * SR))
        if a >= n: break
        t = np.arange(b - a) / SR; env = np.minimum(1, t / 0.8) * np.exp(-np.maximum(0, t - bar) * 4)
        s = sum(np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.003 * t + 1) + 0.25 * np.sin(2 * np.pi * f * 2.001 * t) for f in ch)
        s += 0.8 * np.sin(2 * np.pi * ch[0] / 2 * t)
        out[a:b] += (s * env * 0.12).astype(np.float32)
    beat = 60 / bpm
    for i in range(int(total / beat)):                                   # soft heartbeat pulse
        a = int(i * beat * SR); k = impact(0.35, 52) * (0.5 if i % 2 else 0.8)
        out[a:a + len(k)] += k[:n - a] * 0.35
        if i % 2 == 1:
            tk = tick(); out[a + int(beat / 2 * SR): a + int(beat / 2 * SR) + len(tk)] += tk[:max(0, n - a - int(beat / 2 * SR))] * 0.25
    return _norm(out)
def add(track, clip, t, gain=1.0):
    a = int(t * SR)
    if a >= len(track): return
    if a < 0: clip = clip[-a:]; a = 0
    m = min(len(clip), len(track) - a); track[a:a + m] += clip[:m] * gain
def envelope(x, win=0.08):
    k = int(win * SR); e = np.sqrt(np.convolve(x ** 2, np.ones(k) / k, "same")); return e
