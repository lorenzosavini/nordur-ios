"""Synthesised sound design for reels (numpy only, no samples): whooshes, impacts, rumble, sizzle/steam,
risers, UI pings, an ambient music bed, voice ducking and a safe final mix.
All functions return float32 mono arrays at SR; place them on a timeline with `Track.add`."""
import numpy as np
SR = 48000
_rng = np.random.default_rng(11)
def noise(dur, seed=None):
    r = np.random.default_rng(seed) if seed is not None else _rng
    return r.standard_normal(int(dur * SR)).astype(np.float32)
def band(x, lo, hi):
    """Brick-ish band-pass via FFT with soft edges (offline, whole buffer)."""
    n = len(x); X = np.fft.rfft(x); f = np.fft.rfftfreq(n, 1 / SR)
    g = np.clip((f - lo * 0.7) / (lo * 0.3 + 1e-6), 0, 1) if lo > 0 else np.ones_like(f)
    g *= np.clip((hi * 1.3 - f) / (hi * 0.3), 0, 1)
    return np.fft.irfft(X * g, n).astype(np.float32)
def lowpass_sweep(x, f0, f1, curve=1.0):
    """Time-varying one-pole low-pass: cutoff moves f0→f1 (whoosh 'swish')."""
    n = len(x); fc = f0 + (f1 - f0) * np.linspace(0, 1, n) ** curve
    a = np.exp(-2 * np.pi * fc / SR).astype(np.float32); y = np.empty_like(x); s = 0.0
    for i in range(n): s = a[i] * s + (1 - a[i]) * x[i]; y[i] = s
    return y
def env_ad(n, att, dec, shape=2.0):
    """Attack/decay envelope; att, dec in seconds; n samples."""
    t = np.arange(n) / SR; e = np.where(t < att, (t / max(att, 1e-4)), np.exp(-(t - att) / max(dec, 1e-4) * shape))
    return e.astype(np.float32)
def norm(x, peak=1.0): return (x / (np.abs(x).max() + 1e-9) * peak).astype(np.float32)

def whoosh(dur=0.55, up=True, seed=1):
    """Air swish for whip pans: noise through a sweeping low-pass, bell envelope peaking at 60%."""
    n = int(dur * SR); x = noise(dur, seed)
    y = lowpass_sweep(x, 300, 5000, 1.5) if up else lowpass_sweep(x, 5000, 300, 0.7)
    t = np.linspace(0, 1, n); e = np.sin(np.pi * np.clip(t / 0.6, 0, 1) * 0.5) ** 2 * np.where(t > 0.6, np.exp(-(t - 0.6) * 9), 1)
    y = y - lowpass_sweep(y, 120, 120)                      # drop the mud
    return norm(y * e, 0.9)
def impact(dur=1.4, f0=90, f1=32, seed=2):
    """Cinematic hit: pitch-dropping sine thump + noise crack + sub tail."""
    n = int(dur * SR); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 9); ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 3.2)
    crack = band(noise(dur, seed), 800, 7000) * np.exp(-t * 38)
    tail = band(noise(dur, seed + 1), 20, 180) * np.exp(-t * 2.2) * 0.6
    return norm(np.tanh(1.6 * (body + 0.45 * crack / (np.abs(crack).max() + 1e-9) + tail / (np.abs(tail).max() + 1e-9) * 0.35)), 0.95)
def rumble(dur=4.0, seed=3, lfo=0.7):
    """Deep volcanic rumble: brown-ish noise below 120 Hz with slow amplitude swell."""
    n = int(dur * SR); t = np.arange(n) / SR; x = band(noise(dur, seed), 18, 120)
    m = 0.65 + 0.35 * np.sin(2 * np.pi * lfo * t + 1.3) * np.sin(2 * np.pi * lfo * 0.37 * t)
    fade = np.minimum(1, np.minimum(t / 0.6, (dur - t) / 0.8))
    return norm(x * m * fade, 0.9)
def sizzle(dur=2.5, seed=4, crackle=1.0):
    """Water on lava: bright steam hiss + random crackle pops."""
    n = int(dur * SR); t = np.arange(n) / SR
    hiss = band(noise(dur, seed), 2500, 12000) * (0.55 + 0.45 * np.abs(np.sin(2 * np.pi * 3.1 * t + np.sin(7 * t))))
    r = np.random.default_rng(seed); pops = np.zeros(n, np.float32)
    for p in r.integers(0, n - 2000, int(dur * 70 * crackle)):
        L = r.integers(80, 600); pops[p:p + L] += r.standard_normal(L) * np.exp(-np.arange(L) / (L / 5)) * r.uniform(0.3, 1.0)
    pops = band(pops, 1200, 9000)
    fade = np.minimum(1, np.minimum(t / 0.15, (dur - t) / 0.5))
    return norm((hiss / (np.abs(hiss).max() + 1e-9) * 0.6 + pops / (np.abs(pops).max() + 1e-9) * 0.7) * fade, 0.9)
def riser(dur=1.6, seed=5):
    """Tension riser: noise with rising band + upward sine sweep, crescendo, cut dead at the end."""
    n = int(dur * SR); t = np.arange(n) / SR; k = t / dur
    x = lowpass_sweep(noise(dur, seed), 400, 9000, 2.0); x = x - lowpass_sweep(x, 200, 200)
    f = 180 * 2 ** (k * 2.5); s = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35
    return norm((x / (np.abs(x).max() + 1e-9) + s) * k ** 2.2, 0.85)
def ping(f=1320, dur=0.7):
    """Notification chime (two partials)."""
    t = np.arange(int(dur * SR)) / SR
    y = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.5 * t + 0.4)) * np.exp(-t * 7) * np.minimum(1, t / 0.004)
    return norm(y, 0.8)
def tick(dur=0.05, f=2400):
    t = np.arange(int(dur * SR)) / SR; return norm(np.sin(2 * np.pi * f * t) * np.exp(-t * 120) + band(noise(dur, 9), 3000, 9000) * 0.3 * np.exp(-t * 200), 0.6)
def splash(dur=1.2, seed=6):
    """Water crash: broadband noise burst with fast attack and bubbly low-mid tail."""
    n = int(dur * SR); t = np.arange(n) / SR
    burst = band(noise(dur, seed), 300, 9000) * np.exp(-t * 6)
    bub = band(noise(dur, seed + 1), 150, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 13 * t) ** 2) * np.exp(-t * 3)
    return norm(burst * np.minimum(1, t / 0.01) + bub * 0.5, 0.9)

# ——— music bed ———
def _saw(f, t, harm=14):
    y = np.zeros_like(t)
    for h in range(1, harm + 1): y += np.sin(2 * np.pi * f * h * t + h * 0.7) / h * (1 / (1 + (h / 6) ** 2))
    return y
def music_bed(dur, bpm=96, chords=None, seed=8):
    """Dark ambient-cinematic bed: detuned saw pad through low-pass, sub pulse on each beat, soft ticks.
    chords: list of (root_hz, [semitone offsets]) cycled every 2 bars."""
    chords = chords or [(73.42, [0, 7, 12, 15]), (58.27, [0, 7, 12, 16]), (65.41, [0, 7, 12, 15]), (55.0, [0, 7, 12, 15])]   # Dm · Bb · Cm · Am-ish
    n = int(dur * SR); t = np.arange(n) / SR; beat = 60 / bpm; bar = beat * 4; seg = bar * 2
    pad = np.zeros(n, np.float32)
    for i in range(int(dur / seg) + 1):
        root, iv = chords[i % len(chords)]; a = int(i * seg * SR); b = min(n, int((i + 1) * seg * SR + 0.6 * SR))
        if a >= n: break
        tt = t[a:b] - t[a]; e = np.minimum(1, tt / 0.8) * np.minimum(1, (b - a) / SR - tt) ** 0.5
        for s in iv:
            f = root * 2 ** (s / 12)
            for det in (-0.12, 0.12): pad[a:b] += (_saw(f * 2 ** (det / 12), tt, 10) * e * 0.25).astype(np.float32)
    pad = band(pad, 40, 1800)
    sub = np.zeros(n, np.float32)
    for k in range(int(dur / beat)):
        a = int(k * beat * SR); L = min(n - a, int(0.45 * SR)); tt = np.arange(L) / SR
        root = chords[int(k * beat / seg) % len(chords)][0]
        sub[a:a + L] += np.sin(2 * np.pi * root * tt) * np.exp(-tt * 7) * (1.0 if k % 4 == 0 else 0.55)
    ticks = np.zeros(n, np.float32); tk = band(noise(0.03, seed), 5000, 12000) * np.exp(-np.arange(int(0.03 * SR)) / SR * 160)
    for k in range(int(dur / (beat / 2))):
        a = int(k * beat / 2 * SR)
        if a + len(tk) < n: ticks[a:a + len(tk)] += tk * (0.5 if k % 2 else 0.25)
    y = norm(pad) * 0.55 + norm(sub) * 0.5 + norm(ticks) * 0.12
    fade = np.minimum(1, np.minimum(t / 1.5, (dur - t) / 2.0))
    return norm(y * fade, 0.9)

class Track:
    def __init__(self, dur): self.x = np.zeros(int(dur * SR) + SR, np.float32)
    def add(self, sig, at, gain_db=0.0):
        a = int(max(0, at) * SR); s = sig[: max(0, len(self.x) - a)]
        self.x[a:a + len(s)] += s * 10 ** (gain_db / 20)
def resample(x, sr_in):
    if sr_in == SR: return x.astype(np.float32)
    n = int(len(x) * SR / sr_in); return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)
def duck_env(voice, depth_db=-10, att=0.05, rel=0.35):
    """Gain curve that dips by depth_db wherever the voice is present (smoothed RMS follower)."""
    win = int(0.03 * SR); p = np.sqrt(np.convolve(voice ** 2, np.ones(win) / win, "same"))
    on = (p > 0.02).astype(np.float32); g = np.empty_like(on); s = 0.0
    ka, kr = np.exp(-1 / (att * SR)), np.exp(-1 / (rel * SR))
    # follower on a decimated grid for speed
    step = 64; o = on[::step]; gg = np.empty_like(o)
    ka, kr = np.exp(-step / (att * SR)), np.exp(-step / (rel * SR))
    for i, v in enumerate(o): k = ka if v > s else kr; s = k * s + (1 - k) * v; gg[i] = s
    g = np.repeat(gg, step)[: len(on)]
    return (10 ** (depth_db * g / 20)).astype(np.float32)
def master(voice, music, sfx, music_db=-17, sfx_db=-4, peak_db=-1.0, drive=1.2):
    """voice + ducked music + sfx → soft-limited stereo-ready mono, peak-normalised. Returns (mix, stats)."""
    n = max(len(voice), len(music), len(sfx)); pad = lambda a: np.pad(a, (0, n - len(a)))
    v, m, s = pad(voice), pad(music), pad(sfx)
    m = m * 10 ** (music_db / 20) * duck_env(v); s = s * 10 ** (sfx_db / 20) * (0.55 + 0.45 * duck_env(v, -8))
    y = v + m + s
    y = y / (np.percentile(np.abs(v), 99.9) + 1e-9)             # voice peaks ≈ 1 before the limiter
    y = np.tanh(y * drive) / np.tanh(drive)                     # soft limiter: loud but never hard-clipped
    y = y / (np.abs(y).max() + 1e-9) * 10 ** (peak_db / 20)
    rms = 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-9); pk = 20 * np.log10(np.abs(y).max() + 1e-9)
    return y.astype(np.float32), {"peak_dbfs": round(pk, 2), "rms_dbfs": round(rms, 2), "clipped_samples": int((np.abs(y) >= 0.999).sum())}
