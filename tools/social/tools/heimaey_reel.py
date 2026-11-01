"""'They fought a volcano with seawater' — Eldfell eruption, Heimaey (Westman Islands), 1973.
Usage: python heimaey_reel.py <work> <fonts> <out_dir> [test frame numbers...]
<work>/heimaey/: *.img photos + v_lava.webm (projects/heimaey/dl.py), credits.json, voice/{narration.wav,timeline.json}.
Level-up vs earlier reels: procedural animated textures, motion-blurred whip pans / zoom cuts / crack & lava wipes,
2.5D parallax, speed-ramped footage, text filled with live lava/water textures, and a synthesised sound design
(sfx synced to every transition + ducked music bed) — see motionkit.py and sfxkit.py."""
import sys, os, json, math, subprocess, numpy as np, cv2, soundfile as sf
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reelkit as rk, motionkit as mk, sfxkit as sx
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
V = os.path.join(P, "heimaey"); TLL = json.load(open(os.path.join(V, "voice", "timeline.json")))
TL = {l["id"]: l for l in TLL}; ORDER = [l["id"] for l in TLL]
def st(i): return TL[i]["start"]
def en(i): return TL[i]["start"] + TL[i]["dur"]
TOTAL = en("cta") + 1.0
ACC, BLUE, GREEN, TEXT, DIM, RED = (255, 90, 31), (120, 170, 255), (61, 224, 168), (246, 246, 242), (180, 186, 192), (255, 59, 48)
BG = (7, 9, 12)
CRED = json.load(open(os.path.join(V, "credits.json"))) if os.path.exists(os.path.join(V, "credits.json")) else {}

# ——— word timing ———
WORDS = []
for i in ORDER:
    if i == "cta": continue
    l = TL[i]; ws = l["show"].split(); tot = sum(len(w) + 2 for w in ws); t0 = l["start"]
    for j, w in enumerate(ws):
        dd = l["dur"] * (len(w) + 2) / tot; WORDS.append((t0, t0 + dd, w, l["start"], l["start"] + l["dur"], i, j)); t0 += dd
def wt(line, word, nth=0):
    for w in WORDS:
        if w[5] == line and w[2].strip(".,?!").lower().startswith(word.strip(".,?!").lower()):
            if nth == 0: return w[0]
            nth -= 1
    raise KeyError((line, word))

# ——— media ———
_IMG = {}
def photo(k):
    if k not in _IMG:
        p = os.path.join(V, k + ".img")
        _IMG[k] = np.asarray(Image.open(p).convert("RGB"), np.float32) if os.path.exists(p) and os.path.getsize(p) > 1000 else None
    return _IMG[k]
_BB = {}
def blurbg(k, dark=0.35):
    if (k, dark) not in _BB:
        a = photo(k)
        _BB[(k, dark)] = (cv2.GaussianBlur(mk.cover(a, W // 4, H // 4, 1.1), (0, 0), 5) if a is not None else np.zeros((H // 4, W // 4, 3), np.float32) + BG)
        _BB[(k, dark)] = mk.up(_BB[(k, dark)]) * dark
    return _BB[(k, dark)].copy()
class Clip:
    """Speed-rampable footage: an all-intra mp4 so random seeks are cheap."""
    def __init__(self, path): self.cap = cv2.VideoCapture(path) if os.path.exists(path) else None; self.n = int(self.cap.get(7)) if self.cap else 0; self.last = (-1, None)
    def at(self, src_t):
        if not self.cap: return None
        i = int(src_t * 30) % max(1, self.n)
        if self.last[0] == i: return self.last[1]
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, i); ok, f = self.cap.read()
        if not ok: return self.last[1]
        f = cv2.cvtColor(f, cv2.COLOR_BGR2RGB).astype(np.float32); self.last = (i, f); return f
def prep_clip(src, dst, crop, ss=0, dur=None):
    """Portrait all-intra proxy of a Commons clip (cheap random seeks)."""
    src, dst = os.path.join(V, src), os.path.join(V, dst)
    if os.path.exists(src) and not os.path.exists(dst):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(ss), "-i", src] + (["-t", str(dur)] if dur else []) +
                       ["-an", "-vf", crop + ",scale=540:960:flags=lanczos", "-c:v", "libx264", "-g", "1", "-crf", "15", dst])
    return Clip(dst)
LAVA = prep_clip("v_lava.webm", "lava_full.mp4", "crop=405:720:560:0")          # whole 64 s, segments picked per shot
WAVES = prep_clip("v_waves.webm", "waves.mp4", "crop=608:1080:1180:0")
def footage(clip, src_t, z=1.06, fy=0.5, dark=1.0):
    f = clip.at(src_t); return mk.cover(f, W, H, z, 0.5, fy) * dark if f is not None else mk.lava_field(src_t)
def fullbleed(k, t, t0, fi, cy=760, scale=1.18, sepia=0.2, push=0.03, dark=0.55):
    """Low-res landscape archive photo shown full-bleed: blurred self as the full-screen base, the sharp frame
    at full width on top (no card), soft-edged, archive film look, slow push-in."""
    a = photo(k); img = blurbg(k, dark)
    if a is None: return img
    lt = max(0, t - t0); ih, iw = a.shape[:2]; w = int(W * (scale + push * lt)); h = int(w * ih / iw)
    key = ("fb", k, w)
    if key not in _CARD:
        sh = cv2.resize(a, (w, h), interpolation=cv2.INTER_CUBIC); _CARD.clear() if len(_CARD) > 40 else None
        _CARD[key] = np.clip(sh + (sh - cv2.GaussianBlur(sh, (0, 0), 2.2)) * 0.6, 0, 255)
    ph = mk.archive(_CARD[key], t, fi, sepia, hash(k) % 97)
    x0 = (w - W) // 2; ph = ph[:, x0:x0 + W]; y0 = int(cy - h / 2)
    e = np.minimum(1, np.minimum(np.arange(h) / 60, (h - 1 - np.arange(h)) / 60))[:, None, None].astype(np.float32)
    ya, yb = max(0, y0), min(H, y0 + h); img[ya:yb] = img[ya:yb] * (1 - e[ya - y0:yb - y0]) + ph[ya - y0:yb - y0] * e[ya - y0:yb - y0]
    return img
def fullcover(k, t, t0, fi, dur=3.5, horizon=0.5, z0=1.04, z1=1.14, pan=50, fx=0.5, fy=0.5, arch=False, dark=1.0):
    a = photo(k)
    if a is None: return mk.lava_field(t)
    if arch: a = mk.archive(a, t, fi, 0.2, hash(k) % 97)
    return mk.parallax(a, t - t0, dur, horizon, 0.14, z0, z1, 0.08, pan, fx, fy) * dark
_ICON = {}
def icon(name, size, col=(255, 255, 255)):
    key = (name, size, col)
    if key not in _ICON:
        L = Image.open(os.path.join(P, "icons", name + ".png")).convert("RGBA").resize((size, size), Image.LANCZOS)
        a = np.asarray(L.getchannel("A"), np.float32) / 255; _ICON[key] = np.dstack([np.full((size, size, 3), col, np.float32), a[..., None]])
    return _ICON[key]

# ——— text as cached RGBA layers (placed with mk.over: scale / rotate / fade) ———
_TL = {}
def tlayer(text, size, col=TEXT, font="cond", stroke=8, shadow=True, track=0):
    key = (text, size, col, font, stroke, shadow, track)
    if key not in _TL:
        f = {"cond": COND, "sans": SANS, "mono": MONO}[font](size); d = ImageDraw.Draw(Image.new("L", (4, 4)))
        tw = int(d.textlength(text, font=f) + track * len(text)) + 2 * stroke + 60; th = int(size * 1.35) + 2 * stroke + 60
        L = Image.new("RGBA", (tw, th), (0, 0, 0, 0)); dl = ImageDraw.Draw(L); x = 30 + stroke
        def draw(dd, fill, sw, sf):
            xx = x
            if track:
                for ch in text: dd.text((xx, 30), ch, font=f, fill=fill, stroke_width=sw, stroke_fill=sf); xx += d.textlength(ch, font=f) + track
            else: dd.text((xx, 30), text, font=f, fill=fill, stroke_width=sw, stroke_fill=sf)
        if shadow:
            S = Image.new("RGBA", L.size, (0, 0, 0, 0)); draw(ImageDraw.Draw(S), (0, 0, 0, 200), stroke + 4, (0, 0, 0, 200)); L.alpha_composite(S.filter(ImageFilter.GaussianBlur(10)))
        draw(dl, col + (255,), stroke, (8, 8, 10, 255))
        a = np.asarray(L, np.float32); _TL[key] = np.dstack([a[..., :3], a[..., 3:] / 255])
    return _TL[key]
_TM = {}
def tmask(text, size, track=0):
    """Text alpha mask (for filling letters with live textures)."""
    key = (text, size, track)
    if key not in _TM:
        f = COND(size); d = ImageDraw.Draw(Image.new("L", (4, 4))); tw = int(d.textlength(text, font=f) + track * len(text)) + 40
        L = Image.new("L", (tw, int(size * 1.3) + 20), 0); dl = ImageDraw.Draw(L); x = 20
        for ch in text: dl.text((x, 10), ch, font=f, fill=255); x += d.textlength(ch, font=f) + track
        _TM[key] = np.asarray(L, np.float32) / 255
    return _TM[key]
def tex_text(img, text, size, cy, tex, t, t0=-99, track=4, stroke=10, base=None):
    """Big headline whose letters are filled with a moving texture (lava / water), dark outline + glow; auto-fits width."""
    m = tmask(text, size, track)
    while m.shape[1] > W - 60 and size > 40: size -= 10; m = tmask(text, size, track)
    h, w = m.shape; k = mk.ease((t - t0) / 0.35) if t0 > -99 else 1
    if k <= 0: return img
    s = 0.75 + 0.25 * back(k)
    m2 = cv2.resize(m, (max(1, int(w * s)), max(1, int(h * s)))); h2, w2 = m2.shape
    x0 = int((W - w2) / 2); y0 = int(cy - h2 / 2)
    xs0, ys0 = max(0, -x0), max(0, -y0); x0c, y0c = max(0, x0), max(0, y0); x1c, y1c = min(W, x0 + w2), min(H, y0 + h2)
    m2 = m2[ys0:ys0 + y1c - y0c, xs0:xs0 + x1c - x0c] * min(1, k * 1.5)
    o = cv2.dilate(m2, np.ones((stroke * 2 + 1, stroke * 2 + 1), np.uint8)); g = cv2.GaussianBlur(m2, (0, 0), 16)
    reg = img[y0c:y1c, x0c:x1c]; tx = tex[y0c:y1c, x0c:x1c]
    reg *= (1 - o[..., None] * 0.92)
    reg += g[..., None] * tx.mean(axis=(0, 1)) * 0.6
    fill = np.minimum(255, tx * 1.3 + 20)
    if base is not None: fill = np.maximum(fill, np.array(base, np.float32) * 0.8)
    img[y0c:y1c, x0c:x1c] = reg * (1 - m2[..., None]) + fill * m2[..., None]
    return img
def back(x, s=1.7): x = max(0.0, min(1.0, x)); x -= 1; return x * x * ((s + 1) * x + s) + 1
def slam(img, text, cy, t, t0, size=160, col=TEXT, t1=None, cx=W / 2, font="cond", rot=0):
    """Text slams in from 1.8× (impact), optional fade-out at t1."""
    if t < t0 or (t1 is not None and t > t1): return 0
    k = mk.ease((t - t0) / 0.16); s = 1.8 - 0.8 * k; a = min(1, (t - t0) / 0.08)
    if t1 is not None: a *= 1 - mk.ease((t - (t1 - 0.2)) / 0.2)
    L = tlayer(text, size, col, font); mk.over(img, L, cx, cy, s, rot, a)
    return 1
def rise(img, text, cy, t, t0, size=90, col=TEXT, t1=None, cx=W / 2, font="cond", stroke=7):
    if t < t0 or (t1 is not None and t > t1): return
    k = back((t - t0) / 0.4); a = min(1, (t - t0) / 0.15)
    if t1 is not None: a *= 1 - mk.ease((t - (t1 - 0.2)) / 0.2)
    mk.over(img, tlayer(text, size, col, font, stroke), cx, cy + 70 * (1 - k), 1, 0, a)
def chip(img, text, x, y, t, t0, t1, col=ACC, ic=None, size=34):
    """White pill with coloured dot/icon, slides in from the left."""
    if t < t0 or t > t1: return
    pi = min(1, (t - t0) / 0.35); po = max(0, (t - (t1 - 0.25)) / 0.25); a = min(1, pi * 2) * (1 - po)
    key = ("chip", text, col, ic, size)
    if key not in _TL:
        f = SANS(size); d = ImageDraw.Draw(Image.new("L", (4, 4))); tw = d.textlength(text, font=f); h = int(size * 2.0); w = int(tw + h * 0.9 + (30 if ic else 0))
        L = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0)); S = Image.new("RGBA", L.size, (0, 0, 0, 0))
        ImageDraw.Draw(S).rounded_rectangle((24, 28, w + 24, h + 28), h / 2, fill=(0, 0, 0, 130)); L.alpha_composite(S.filter(ImageFilter.GaussianBlur(8)))
        dl = ImageDraw.Draw(L); dl.rounded_rectangle((20, 20, w + 20, h + 20), h / 2, fill=(250, 250, 248, 255))
        if ic:
            I = Image.open(os.path.join(P, "icons", ic + ".png")).convert("RGBA").resize((int(h * 0.62),) * 2, Image.LANCZOS)
            col_l = Image.new("RGBA", I.size, col + (255,)); col_l.putalpha(I.getchannel("A")); L.alpha_composite(col_l, (20 + int(h * 0.3), 20 + int(h * 0.19)))
            tx = 20 + int(h * 0.3) + int(h * 0.62) + 14
        else:
            dl.ellipse((34, 20 + h / 2 - 9, 52, 20 + h / 2 + 9), fill=col + (255,)); tx = 66
        dl.text((tx, 20 + h * 0.22), text, font=f, fill=(12, 14, 18, 255))
        A = np.asarray(L, np.float32); _TL[key] = np.dstack([A[..., :3], A[..., 3:] / 255])
    L = _TL[key]; dx = -90 * (1 - mk.ease(pi)) - 90 * mk.ease(po)
    mk.over(img, L, x + L.shape[1] / 2 + dx, y + L.shape[0] / 2, 1, 0, a)
def credit(img, text, y=1268):
    if not text: return
    L = tlayer(text, 19, (228, 228, 228), "mono", 0, False)
    h, w = L.shape[:2]; x1 = W - 40; x0 = int(x1 - (w - 60) - 24)
    img[y:y + 34, x0:x1] *= 0.42
    mk.over(img, L, x0 + 12 + w / 2 - 30, y + 17 + 3, 1, 0, 1)
def stamp_layer(text, col, size=86, rot=-10):
    key = ("stamp", text, col, size, rot)
    if key not in _TL:
        L = Image.new("RGBA", (10, 10)); f = COND(size); d = ImageDraw.Draw(L); tw = d.textlength(text, font=f); pad = 30
        L = Image.new("RGBA", (int(tw + pad * 2 + 20), int(size * 1.45 + pad)), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
        d.rounded_rectangle((6, 6, L.width - 6, L.height - 6), 16, outline=col + (255,), width=9, fill=(10, 10, 12, 150))
        d.text((pad + 10, pad * 0.35), text, font=f, fill=col + (255,))
        L = L.rotate(rot, resample=Image.BICUBIC, expand=True); A = np.asarray(L, np.float32); _TL[key] = np.dstack([A[..., :3], A[..., 3:] / 255])
    return _TL[key]
def stamp(img, text, cx, cy, t, t0, col=RED, size=86, rot=-10, t1=None):
    if t < t0 or (t1 is not None and t > t1): return
    k = mk.ease((t - t0) / 0.16); a = min(1, (t - t0) / 0.06)
    if t1 is not None: a *= 1 - mk.ease((t - (t1 - 0.2)) / 0.2)
    mk.over(img, stamp_layer(text, col, size, rot), cx, cy, 2.2 - 1.2 * k, 0, a)

# ——— framed archive photo (film look) ———
_CARD = {}
def archive_card(img, k, t, fi, w, cx, cy, t0, t1, enter="drop", rot=0.0, sepia=0.3, maxh=None):
    a = photo(k)
    if a is None or t < t0 or t > t1: return
    ih, iw = a.shape[:2]; h = int(w * ih / iw)
    if maxh and h > maxh: h = maxh; w = int(h * iw / ih)
    key = (k, w, h)
    if key not in _CARD:
        sharp = cv2.resize(a, (w, h), interpolation=cv2.INTER_CUBIC)
        sharp = np.clip(sharp + (sharp - cv2.GaussianBlur(sharp, (0, 0), 2.2)) * 0.6, 0, 255)   # mild unsharp after upscale
        _CARD[key] = (sharp, mk.card(sharp, w, h, 12, 14))
    sharp, C = _CARD[key]
    C = C.copy(); pad = 60 + 12; C[pad:pad + h, pad:pad + w, :3] = mk.archive(sharp, t, fi, sepia, hash(k) % 97)
    pi = min(1, (t - t0) / 0.45); po = max(0, (t - (t1 - 0.3)) / 0.3)
    dx, dy, s, r, al = 0, 0, 1, rot, 1
    if enter == "drop": dy = -900 * (1 - back(pi, 1.1)); r = rot + 14 * (1 - mk.ease(pi))
    elif enter == "pop": s = 0.55 + 0.45 * back(pi); al = min(1, pi * 2)
    elif enter == "right": dx = 1100 * (1 - mk.ease(pi))
    elif enter == "left": dx = -1100 * (1 - mk.ease(pi))
    elif enter == "none": pass
    if po > 0: al *= 1 - po; s *= 1 - 0.1 * po
    lt = t - t0; s *= 1 + 0.025 * lt                      # slow push-in while on screen
    wx, wy = mk.weave(fi, 1.5)
    mk.over(img, C, cx + dx + wx, cy + dy + wy, s, r, al)

# ——— recurring backgrounds ———
EMB = mk.Particles(170, 3, "ember"); ASH = mk.Particles(220, 5, "ash"); ASH2 = mk.Particles(120, 9, "ash")
def bg_lava(t, dark=1.0, heat=1.0, embers=True):
    a = mk.lava_field(t, heat) * dark
    return EMB.apply(a, t, 0.9) if embers else a
def bg_water(t, dark=1.0): return mk.water_field(t) * dark
def dim(img, k): return img * k

# ——— event list: drives camera shake AND the sound design ———
EV = []          # (time, kind, gain_db)
def ev(t, kind, g=0.0): EV.append((t, kind, g))

# ——— shots ———
def s_title(t, fi):
    img = footage(LAVA, 30 + t * 0.8, 1.1, dark=0.55)                                   # real lava as the base, type on top
    img = EMB.apply(img, t, 0.6)
    rise(img, "IN 1973 THEY FOUGHT", 520, t, -1, 96, TEXT)
    tex_text(img, "A VOLCANO", 250, 720, mk.lava_field(t * 1.5, 1.4) * 1.1 + 40, t, base=ACC)
    rise(img, "WITH", 900, t, -1, 96, TEXT)
    tex_text(img, "SEAWATER", 250, 1080, mk.water_field(t) * 1.2 + 30, t, base=BLUE)
    credit(img, CRED.get("v_lava", "").replace("Lava footage: ", "Footage: "))
    return img
def s_erupt(t, fi):
    t0 = SH_T["erupt"]; img = fullbleed("simkin", t, t0, fi, 800, 1.35, 0.12, 0.05, 0.55)
    img = ASH.apply(img, t, 0.6)
    slam(img, "RIGHT NEXT TO A TOWN", 330, t, wt("hook", "right"), 110, TEXT)
    if t > wt("hook", "So") - 0.1:
        slam(img, "SO THEY FOUGHT IT", 1090, t, wt("hook", "So") - 0.05, 90, TEXT)
        slam(img, "WITH SEAWATER", 1190, t, wt("hook", "seawater") - 0.05, 120, BLUE)
    credit(img, "Heimaey, 1973 · " + CRED.get("simkin", ""))
    return img
def s_clock(t, fi):
    t0 = SH_T["clock"]; lt = t - t0
    img = footage(LAVA, 2 + lt * 0.5, 1.25, 0.45, 0.32)                                 # night-time glow behind the clock
    img = mk.scanlines(img, t, 6, 0.10)
    rise(img, "23 JANUARY 1973", 470, t, t0 + 0.1, 92, DIM)
    m = min(59, 52 + int(max(0, lt) * 2.2))
    mk.over(img, tlayer(f"01:{m:02d}", 300, ACC, "mono", 10), W / 2, 740, 1 + 0.02 * math.sin(lt * 6), 0, min(1, lt / 0.2))
    rise(img, "A.M.", 930, t, t0 + 0.2, 70, TEXT, font="mono")
    chip(img, "Heimaey · Westman Islands, South Iceland", 70, 1060, t, wt("night", "Heimaey") - 0.1, 99, ACC, "volcano", 30)
    credit(img, "Illustrative footage: Iceland, 2021 · J. St. John · CC BY 2.0")
    return img
def s_fissure(t, fi):
    t0 = SH_T["fissure"]; ts = wt("night", "splits")
    src = 15 + mk.speed_map(t, [(t0 - 1, 0.45), (ts - 0.1, 1.8), (ts + 0.6, 0.9)])
    img = footage(LAVA, src, 1.06 + 0.04 * (t - t0))
    img = mk.light_leak(img, t, ACC, 0.2, 2)
    slam(img, "THE GROUND", 520, t, ts - 0.05, 170, TEXT)
    slam(img, "SPLITS OPEN", 700, t, ts + 0.12, 190, ACC)
    credit(img, "Illustrative footage: Iceland, 2021 · J. St. John · CC BY 2.0")
    return img
def s_harbour(t, fi):
    t0 = SH_T["harbour"]; a = photo("twovol"); lt = t - t0
    img = mk.cover(a, W, H, 1.05 + 0.03 * lt, 0.75 - 0.06 * lt, 0.5) if a is not None else bg_water(t)
    img = img * np.array((0.62, 0.68, 0.82), np.float32) + mk.stripes(t, (200, 220, 255), 34, 3, -72, 900, 0.16)
    slam(img, "THE FLEET WAS", 470, t, wt("fleet", "fishing") - 0.15, 120, TEXT)
    slam(img, "IN PORT", 620, t, wt("fleet", "port") - 0.05, 190, BLUE)
    chip(img, "A storm kept the boats home", 70, 1080, t, t0 + 0.15, 99, BLUE, "cloud", 32)
    credit(img, "Heimaey harbour today · " + CRED.get("twovol", ""))
    return img
def s_evac(t, fi):
    t0 = SH_T["evac"]; lt = t - t0
    img = fullbleed("after", t, t0, fi, 760, 1.3, 0.12, 0.04, 0.5)                    # 1973 harbour full of boats
    tw = wt("fleet", "Within"); ts = wt("fleet", "safe"); t5 = wt("fleet", "5,300")
    if t >= tw - 0.1:
        r = 110; cx, cy = W / 2, 330; prog = min(1, (t - tw) / 1.3)
        cv2.circle(img, (int(cx), int(cy)), r, (40, 50, 70), 16, cv2.LINE_AA)
        cv2.ellipse(img, (int(cx), int(cy)), (r, r), -90, 0, 360 * prog, ACC, 16, cv2.LINE_AA)
        mk.over(img, tlayer(f"{max(1, int(6 * prog))}h", 100, TEXT), cx, cy + 8, 1, 0, 1)
    if t >= t5 - 0.6:
        n = int(5300 * mk.ease((t - t5 + 0.6) / 0.6))
        mk.over(img, tlayer(f"{n:,}", 200, GREEN if t > ts else TEXT), W / 2, 1080, 1, 0, 1)
        rise(img, "PEOPLE SAFE" if t > ts else "PEOPLE", 1220, t, t5 - 0.6, 70, GREEN if t > ts else DIM)
    credit(img, "Heimaey harbour, 1973 · " + CRED.get("after", ""), 1240)
    return img
def s_street(t, fi):
    t0 = SH_T["street"]; img = fullbleed("street", t, t0, fi, 760, 1.4, 0.2, 0.05, 0.5)
    img = img * np.array((1.0, 0.86, 0.8), np.float32)
    slam(img, "LAVA IS COMING", 330, t, t0 + 0.05, 130, ACC)
    stamp(img, "HARBOUR AT RISK", W / 2, 1120, t, wt("threat", "harbour"), RED, 84)
    credit(img, "Lava enters a Heimaey street, 1973 · " + CRED.get("street", ""))
    return img
def s_ocean(t, fi):
    t0 = SH_T["ocean"]; img = footage(WAVES, 1 + (t - t0) * 0.8, 1.08, dark=0.75)
    slam(img, "PUMP", 520, t, wt("plan", "pump") - 0.05, 230, TEXT)
    tex_text(img, "THE OCEAN", 230, 760, mk.water_field(t * 2 + 3) * 1.3 + 40, t, wt("plan", "ocean") - 0.15, base=BLUE)
    slam(img, "ONTO THE LAVA", 990, t, wt("plan", "onto") - 0.05, 130, ACC)
    credit(img, "Icelandic coast · " + CRED.get("v_waves", ""))
    return img
def s_ship(t, fi):
    t0 = SH_T["ship"]; img = fullbleed("ship", t, t0, fi, 800, 1.35, 0.12, 0.05, 0.5)
    chip(img, "FIRE HOSES", 70, 300, t, wt("pumps", "Fire") - 0.1, 99, BLUE, "droplet", 38)
    chip(img, "A PUMP SHIP", 70, 410, t, wt("pumps", "pump") - 0.1, 99, BLUE, "droplet", 38)
    credit(img, "Ship spraying seawater onto the lava, 1973 · " + CRED.get("ship", ""))
    return img
def s_pumps(t, fi):
    t0 = SH_T["pumps"]; img = fullbleed("town73", t, t0, fi, 800, 1.45, 0.1, 0.05, 0.5)
    slam(img, "BIG PUMPS", 330, t, wt("pumps", "big") - 0.05, 150, TEXT)
    chip(img, "Leased from the United States", 70, 1120, t, wt("pumps", "U.S.") - 0.2, 99, ACC, "world", 32)
    credit(img, "Pumps on the pier, 1973 · " + CRED.get("town73", ""))
    return img
def s_steam(t, fi):
    t0 = SH_T["steam"]; img = fullbleed("steam", t, t0, fi, 800, 1.3, 0.12, 0.05, 0.5)
    slam(img, "PIPES ACROSS", 300, t, wt("pumps", "pipes") - 0.05, 120, TEXT)
    slam(img, "MOVING LAVA", 440, t, wt("pumps", "moving") - 0.05, 150, ACC)
    credit(img, "Steam over water-cooled lava, 1973 · " + CRED.get("steam", ""))
    return img
def s_data(t, fi):
    t0 = SH_T["data"]; to = wt("months", "Over")
    if t < to + 0.3:                                                                    # NASA thermal image of the cooled flow, full screen
        img = footage(LAVA, 20 + (t - t0) * 0.6, 1.2, 0.6, 0.5)
        rise(img, "5 MONTHS", 380, t, t0 + 0.05, 160, TEXT, t1=to + 0.3)
        rise(img, "AROUND THE CLOCK", 540, t, wt("months", "around") - 0.1, 100, ACC, t1=to + 0.3)
        x0, x1, y = 190, 890, 700; prog = mk.ease((t - t0) / 1.6)
        cv2.line(img, (x0, y), (x1, y), (60, 80, 110), 12, cv2.LINE_AA); cv2.line(img, (x0, y), (int(x0 + (x1 - x0) * prog), y), BLUE, 12, cv2.LINE_AA)
        mk.over(img, tlayer("6 FEB", 40, TEXT, "mono", 4), x0 + 50, y + 55, 1, 0, 1); mk.over(img, tlayer("10 JUL", 40, TEXT, "mono", 4), x1 - 50, y + 55, 1, 0, 1)
        credit(img, "Illustrative footage: Iceland, 2021 · J. St. John · CC BY 2.0")
    else:
        img = footage(WAVES, 5 + (t - to) * 0.6, 1.3, 0.6, 0.5)
        k = mk.ease((t - to) / 1.2); n = int(6_000_000 * k)
        rise(img, "MORE THAN", 520, t, to, 80, TEXT)
        tex_text(img, f"{n:,}", 200, 700, mk.water_field(t * 2 + 5) * 1.3 + 50, t, to, track=2, base=BLUE)
        slam(img, "CUBIC METRES", 880, t, to + 0.2, 110, TEXT)
        slam(img, "OF SEAWATER", 1010, t, to + 0.45, 110, BLUE)
        credit(img, "Icelandic coast · " + CRED.get("v_waves", ""))
    return img
def s_after(t, fi):
    t0 = SH_T["after"]; img = fullcover("thermo", t, t0, fi, 3.6, 0.5, 1.02, 1.12, 30, 0.5, 0.45, True, 0.75)
    slam(img, "IT WORKED", 340, t, wt("works", "works") - 0.05, 190, GREEN)
    stamp(img, "THE HARBOUR SURVIVED", W / 2, 1110, t, wt("works", "short"), GREEN, 70, 6)
    chip(img, "NASA thermal image: cooled lava beside the harbour", 50, 1180, t, wt("works", "lava") - 0.1, 99, GREEN, None, 26)
    credit(img, CRED.get("thermo", ""), 1290)
    return img
def s_fired(t, fi):
    t0 = SH_T["fired"]; lt = t - t0
    img = fullcover("fired", t, t0, fi, 3.0, 0.55, 1.06, 1.16, 40, 0.5, 0.4, True, 0.8)
    slam(img, "~300", 420, t, t0 + 0.05, 260, ACC)
    rise(img, "BUILDINGS LOST", 610, t, t0 + 0.25, 120, TEXT)
    credit(img, "A house set alight by lava, 1973 · " + CRED.get("fired", ""))
    return img
def s_ash(t, fi):
    t0 = SH_T["ash"]; img = fullcover("ash74", t, t0, fi, 2.5, 0.5, 1.05, 1.15, -50, 0.5, 0.5, True, 0.8)
    archive_card(img, "buried", t, fi, 400, 300, 1000, t0 + 0.05, 99, "drop", -6, 0.2)
    chip(img, "+ 60–70 homes buried by ash", 480, 1090, t, t0 + 0.2, 99, DIM, None, 28)
    rise(img, "~300 BUILDINGS LOST", 380, t, t0 - 1, 110, TEXT)
    credit(img, "1974 · Christian Bickel · CC BY-SA 2.0 de  |  inset: USGS 1973 · PD")
    return img
def s_shield(t, fi):
    t0 = SH_T["shield"]; img = fullcover("harbour", t, t0, fi, 3.0, 0.45, 1.05, 1.15, 60, 0.35, 0.5, False, 0.85)
    slam(img, "NEW LAVA = BREAKWATER", 400, t, wt("twist", "shields") - 0.1, 110, TEXT)
    chip(img, "The 1973 lava now shelters the harbour", 70, 1080, t, wt("twist", "harbour") - 0.1, 99, GREEN, "ripple", 30)
    credit(img, "Heimaey harbour and the 1973 lava today · " + CRED.get("harbour", ""))
    return img
def s_grow(t, fi):
    t0 = SH_T["grow"]; img = footage(LAVA, 45 + (t - t0) * 0.7, 1.1, dark=0.55)
    tg = wt("twist", "grew"); k = mk.ease((t - tg) / 1.0)
    rise(img, "THE ISLAND GREW", 520, t, t0 + 0.05, 120, TEXT)
    tex_text(img, f"+{int(round(20 * k))}%", 330, 820, mk.lava_field(t * 1.5, 1.5) * 1.2 + 40, t, tg - 0.1, track=2, base=ACC)
    rise(img, "NEW LAND FROM THE LAVA", 1060, t, tg + 0.2, 70, DIM)
    credit(img, "Illustrative footage: Iceland, 2021 · J. St. John · CC BY 2.0")
    return img
def s_eldfell(t, fi):
    t0 = SH_T["eldfell"]; img = fullcover("view", t, t0, fi, 3.2, 0.5, 1.04, 1.16, 70, 0.5, 0.5, False, 0.8)
    tex_text(img, "ELDFELL", 250, 470, mk.lava_field(t * 1.5, 1.4) * 1.1 + 40, t, wt("today", "Eldfell") - 0.1, track=6, base=ACC)
    slam(img, "= FIRE MOUNTAIN", 660, t, wt("today", "Fire") - 0.05, 120, TEXT)
    credit(img, "View from Eldfell's summit · " + CRED.get("view", ""))
    return img
def s_museum(t, fi):
    t0 = SH_T["museum"]; img = fullcover("museum", t, t0, fi, 3.5, 0.45, 1.04, 1.14, -60, 0.5, 0.55, False, 0.85)
    slam(img, "ELDHEIMAR", 440, t, wt("today", "Eldheimar") - 0.05, 200, TEXT)
    rise(img, "A HOUSE DUG OUT OF THE ASH", 300, t, t0 + 0.2, 70, TEXT, t1=wt("today", "Eldheimar"))
    chip(img, "Eruption museum · opened 2014", 70, 1080, t, wt("today", "Eldheimar") + 0.3, 99, ACC, "home", 30)
    credit(img, "Eldheimar museum below Eldfell · " + CRED.get("museum", ""))
    return img
def phone(img, t, cx, cy, notes):
    """Minimal phone with notification cards sliding in (UI demo, no real event data)."""
    w, h = 560, 1080; x0, y0 = int(cx - w / 2), int(cy - h / 2)
    sh = np.zeros((H, W), np.float32); cv2.rectangle(sh, (x0 + 10, y0 + 40), (x0 + w - 10, y0 + h + 10), 1, -1); sh = cv2.GaussianBlur(sh, (0, 0), 30)
    img *= (1 - sh[..., None] * 0.6)
    m = np.zeros((H, W), np.float32); mk._rrect(m, x0, y0, w, h, 70); img[:] = img * (1 - m[..., None]) + np.array((20, 22, 26), np.float32) * m[..., None]
    m2 = np.zeros((H, W), np.float32); mk._rrect(m2, x0 + 16, y0 + 16, w - 32, h - 32, 56)
    scr = mk.lava_field(t * 0.5, 0.8) * 0.35 + np.array(BG, np.float32) * 0.6
    img[:] = img * (1 - m2[..., None]) + scr * m2[..., None]
    mk.over(img, tlayer("9:41", 34, TEXT, "sans", 0, False), x0 + 90, y0 + 60, 1, 0, 1)
    for i, (tt, title, body, col, ic) in enumerate(notes):
        if t < tt: continue
        k = back((t - tt) / 0.45); key = ("note", title, body)
        if key not in _TL:
            L = Image.new("RGBA", (500, 170), (0, 0, 0, 0)); d = ImageDraw.Draw(L); d.rounded_rectangle((0, 0, 499, 169), 34, fill=(245, 245, 242, 250))
            I = Image.open(os.path.join(P, "icons", ic + ".png")).convert("RGBA").resize((70, 70), Image.LANCZOS)
            sq = Image.new("RGBA", (96, 96), (0, 0, 0, 0)); ImageDraw.Draw(sq).rounded_rectangle((0, 0, 95, 95), 22, fill=col + (255,))
            wI = Image.new("RGBA", I.size, (255, 255, 255, 255)); wI.putalpha(I.getchannel("A")); sq.alpha_composite(wI, (13, 13)); L.alpha_composite(sq, (24, 37))
            d.text((140, 30), "NORÐUR", font=MONO(22), fill=(110, 116, 124)); d.text((140, 62), title, font=COND(46), fill=(14, 16, 20)); d.text((140, 116), body, font=SANS(24), fill=(60, 64, 70))
            A = np.asarray(L, np.float32); _TL[key] = np.dstack([A[..., :3], A[..., 3:] / 255])
        mk.over(img, _TL[key], cx, y0 + 230 + i * 200 - 120 * (1 - k), 0.9 + 0.1 * k, 0, min(1, (t - tt) / 0.2))
def s_app(t, fi):
    t0 = SH_T["app"]; img = footage(LAVA, 52 + (t - t0) * 0.8, 1.1, dark=0.6)
    tn = wt("app", "Norður")
    if t < tn - 0.1:
        slam(img, "THE GROUND CAN", 560, t, t0 + 0.05, 130, TEXT)
        tex_text(img, "STILL SPLIT", 230, 760, mk.lava_field(t * 1.6, 1.5) * 1.1 + 40, t, wt("app", "still") - 0.1, base=ACC)
        slam(img, "OVERNIGHT", 960, t, wt("app", "overnight") - 0.05, 130, ACC)
    else:
        lt = t - tn; img *= 0.8
        phone(img, t, W / 2, 760 + 400 * (1 - back(lt / 0.6, 1.0)), [(tn + 0.35, "Volcano alert", "Eruptions near you", ACC, "volcano"),
                                                                (wt("app", "earthquake") - 0.05, "Earthquake alert", "Felt quakes nearby", BLUE, "ripple")])
    return img
def s_cta(t, fi):
    lt = t - st("cta"); img = footage(LAVA, 30 + t * 0.8, 1.1, dark=0.55)      # same footage as frame 0 → seamless loop
    return img

SHOTS = [("title", 0, s_title), ("erupt", wt("hook", "erupts") - 0.1, s_erupt),
         ("clock", st("night") - 0.05, s_clock), ("fissure", wt("night", "ground") - 0.25, s_fissure), ("harbour", st("fleet") - 0.1, s_harbour),
         ("evac", wt("fleet", "Within") - 0.6, s_evac), ("street", st("threat") - 0.1, s_street), ("ocean", st("plan") - 0.05, s_ocean),
         ("ship", st("pumps") - 0.1, s_ship), ("pumps", wt("pumps", "Then") - 0.05, s_pumps), ("steam", wt("pumps", "pipes") - 0.15, s_steam),
         ("data", st("months") - 0.1, s_data), ("after", st("works") - 0.1, s_after), ("fired", st("twist") - 0.1, s_fired), ("ash", wt("twist", "buildings") + 0.1, s_ash),
         ("shield", wt("twist", "But") - 0.05, s_shield), ("grow", wt("twist", "island") - 0.3, s_grow), ("eldfell", st("today") - 0.1, s_eldfell),
         ("museum", wt("today", "And") - 0.05, s_museum), ("app", st("app") - 0.1, s_app), ("cta", st("cta") - 0.2, s_cta)]
SH_T = {n: s for n, s, _ in SHOTS}
# transition INTO each shot: (kind, duration)
TR = {"erupt": ("crack", 0.5), "clock": ("whip", 0.36), "fissure": ("crack", 0.55), "harbour": ("whip", 0.36),
      "evac": ("zoom", 0.4), "street": ("lava", 0.5), "ocean": ("steam", 0.45), "ship": ("whipv", 0.4), "pumps": ("whip", 0.34),
      "steam": ("whipl", 0.34), "data": ("circle", 0.45), "after": ("zoom", 0.4), "fired": ("lava", 0.5), "ash": ("whipv", 0.36), "shield": ("whip", 0.36),
      "grow": ("zoom", 0.4), "eldfell": ("whipv", 0.4), "museum": ("circle", 0.45), "app": ("crack", 0.55), "cta": ("crack", 0.6)}
TRF = {"crack": lambda a, b, k, i: mk.crack_wipe(a, b, k, i), "steam": lambda a, b, k, i: mk.steam_flash(a, b, k, i),
       "whip": lambda a, b, k, i: mk.whip(a, b, k, 1), "whipl": lambda a, b, k, i: mk.whip(a, b, k, -1), "whipv": lambda a, b, k, i: mk.whip_v(a, b, k),
       "zoom": lambda a, b, k, i: mk.zoom_cut(a, b, k), "lava": lambda a, b, k, i: mk.lava_wipe(a, b, k, i), "circle": lambda a, b, k, i: mk.circle_wipe(a, b, k, W / 2, 800)}
# Sound design is deliberately sparse: effects only on the main transitions and on the hooks, well under the voice.
SFX_OF = {"crack": [(-0.05, "impact", -6)], "steam": [(-0.25, "splash", -8)], "lava": [(-0.25, "rumble", -6)]}
for name, s_, _ in SHOTS:
    if name in TR and TR[name][0] in SFX_OF and name in ("fissure", "ocean", "street", "fired", "app", "cta"):
        for dt, kind, g in SFX_OF[TR[name][0]]: ev(s_ + dt, kind, g)
for name in ("harbour", "eldfell"): ev(SH_T[name] - 0.3, "whoosh", -10)                 # two soft whooshes on chapter-level cuts
for tt in (wt("threat", "harbour"), wt("works", "works"), wt("twist", "grew")): ev(tt, "impact", -9)   # hooks
for tt in (st("plan"), st("works")): ev(tt - 1.4, "riser", -16)
ev(st("pumps") + 0.2, "sizzle_long", -18)
for tt in (wt("app", "Norður") + 0.35, wt("app", "earthquake") - 0.05): ev(tt, "ping", -14)
ev(0.0, "rumble_long", -10)

def shake_amp(t):
    a = 0.0
    for tt, kind, g in EV:
        if kind == "impact" and 0 <= t - tt < 0.45: a += 16 * (1 - (t - tt) / 0.45) ** 2 * 10 ** (g / 40)
        if kind == "thud" and 0 <= t - tt < 0.3: a += 6 * (1 - (t - tt) / 0.3) ** 2
    return min(a, 22)

# ——— chrome: chapter bar + captions ———
CH = [("THE NIGHT", "hook", "threat"), ("THE FIGHT", "threat", "twist"), ("THE ISLAND TODAY", "twist", "cta")]
def chapters(d, t):
    if not (st("night") - 0.3 <= t < st("cta")): return
    x0, y0, gap = 60, 150, 12; w = (W - 120 - gap * 2) / 3
    for i, (name, a, b) in enumerate(CH):
        x = x0 + i * (w + gap); on = st(a) <= t < st(b); k = 1.0 if t >= st(b) else (np.clip((t - st(a)) / (st(b) - st(a)), 0, 1) if on else 0)
        d.rounded_rectangle((x, y0, x + w, y0 + 8), 4, fill=(255, 255, 255, 60))
        if k > 0.01: d.rounded_rectangle((x, y0, x + w * k, y0 + 8), 4, fill=ACC + (255,))
        d.text((x, y0 + 16), name, font=MONO(20), fill=(255, 255, 255, 230 if on else 110))
def captions(d, t):
    cur = [w for w in WORDS if w[3] <= t < w[4] + 0.12]
    if not cur: return
    line = [w for w in WORDS if w[3] == cur[0][3]]
    k = next((i for i, w in enumerate(line) if w[0] <= t < w[1]), len(line) - 1)
    c0 = (k // 3) * 3; chunk = line[c0:c0 + 3]
    f = COND(100); txt = " ".join(w[2] for w in chunk)
    while d.textlength(txt, font=f) > W - 80: f = COND(f.size - 6)
    x = (W - d.textlength(txt, font=f)) / 2; y = 1380; pop = mk.ease((t - chunk[0][0]) / 0.12)
    for j, w in enumerate(chunk):
        on = c0 + j == k
        d.text((x, y - (8 if on else 0) * pop), w[2], font=f, fill=ACC if on else (255, 255, 255), stroke_width=7, stroke_fill=(8, 8, 10))
        x += d.textlength(w[2] + " ", font=f)
_GR = None
def bottom_grad(img):
    global _GR
    if _GR is None: y = np.linspace(0, 1, 600, dtype=np.float32); _GR = (y ** 1.5 * 0.8)[:, None, None]
    img[H - 600:] = img[H - 600:] * (1 - _GR) + np.array((4, 6, 10), np.float32) * _GR

def shot_at(t):
    i = max(j for j, s in enumerate(SHOTS) if s[1] <= t); return i
def frame(fi):
    t = fi / FPS; i = shot_at(t); img = None
    for j in (i, i + 1):
        if 0 < j < len(SHOTS):
            name, b, _ = SHOTS[j]; kind, d = TR.get(name, ("cut", 0))
            if d and b - d / 2 <= t < b + d / 2:
                k = (t - (b - d / 2)) / d
                img = TRF[kind](SHOTS[j - 1][2](t, fi), SHOTS[j][2](t, fi), k, j); break
    if img is None: img = SHOTS[i][2](t, fi)
    img = mk.vignette(img, 0.45); img = mk.grain(img, fi, 6)
    a = shake_amp(t)
    if a > 0.5: img = mk.chroma(mk.shake(img, a, fi), int(a / 5))
    if t < st("cta") - 0.2: bottom_grad(img)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA"); d = ImageDraw.Draw(im, "RGBA")
    chapters(d, t)
    if t < st("cta") - 0.2: captions(d, t)
    else:
        rk.cta(im, mk.ease((t - st("cta")) / 0.5), P, "Volcano and earthquake alerts, weather, roads and the stories behind every place.",
               "Photos: USGS, NASA, Smithsonian (public domain) · Óskar Elías Björnsson (CC BY 2.0) · Christian Bickel (CC BY-SA 2.0 de) · Szilas (PD) · Jasmin Engelhart (CC BY-SA 2.0) · Diego Delso (CC BY-SA 4.0) · footage: James St. John (CC BY 2.0), Alexander Grebenkov (CC BY 3.0) · AI voice · music & sfx: Norður")
    return im.convert("RGB")

# ——— sound design ———
def build_audio(path_out):
    v, sr = sf.read(os.path.join(V, "voice", "narration.wav"), dtype="float32")
    v = sx.resample(v if v.ndim == 1 else v.mean(1), sr); n = int(TOTAL * sx.SR) + sx.SR
    voice = np.zeros(n, np.float32); voice[:len(v)] = v[:n] * 0.95
    fx_ = sx.Track(TOTAL)
    lib = {"impact": lambda: sx.impact(1.3), "thud": lambda: sx.impact(0.6, 70, 40, 7) * 0.7, "rumble": lambda: sx.rumble(2.2, 3), "rumble_long": lambda: sx.rumble(7.5, 13, 0.4),
           "whoosh": lambda: sx.whoosh(0.55), "splash": lambda: sx.splash(1.2), "sizzle": lambda: sx.sizzle(1.6, 4), "sizzle_long": lambda: sx.sizzle(6.0, 14, 0.6),
           "riser": lambda: sx.riser(1.4), "ping": lambda: sx.ping(1320), "tick": lambda: sx.tick()}
    cache = {}
    for i, (tt, kind, g) in enumerate(EV):
        if kind not in cache or kind == "whoosh": cache[kind] = lib[kind]() if kind != "whoosh" else sx.whoosh(0.55, True, 100 + i)
        fx_.add(cache[kind], tt, g)
    music = sx.music_bed(TOTAL + 1, 96)
    sfx = fx_.x[:n]; vp = np.abs(voice).max(); win = int(0.05 * sx.SR)
    sp = np.sqrt(np.convolve(sfx ** 2, np.ones(win) / win, "same")).max() * 1.414          # short-term SFX peak
    vpk = np.sqrt(np.convolve(voice ** 2, np.ones(win) / win, "same")).max() * 1.414
    sfx_db = min(0.0, 20 * np.log10(vpk / (sp + 1e-9)) - 12)                                 # SFX ≥ 12 dB under the voice
    mix, stats = sx.master(voice, music[:n], sfx, music_db=-18, sfx_db=sfx_db, duck_db=-14)
    stats["sfx_gain_db"] = round(float(sfx_db), 1)
    mix = mix[:int(TOTAL * sx.SR)]
    sf.write(path_out, np.stack([mix, mix], 1), sx.SR, subtype="PCM_16")
    return stats

def render_part(i, n, path):
    """Render frames [i/n, (i+1)/n) of the reel into its own mp4 (for parallel CPU renders)."""
    N = int(TOTAL * FPS); a, b = N * i // n, N * (i + 1) // n; pr = rk.writer(path)
    for fi in range(a, b): pr.stdin.write(frame(fi).tobytes())
    pr.stdin.close(); pr.wait()
if __name__ == "__main__":
    tmp = os.path.join(OUT, "heimaey-silent.mp4"); final = os.path.join(OUT, "heimaey-1973-seawater-vs-volcano.mp4")
    wav = os.path.join(OUT, "heimaey-mix.wav")
    if TEST and TEST[0] == "audio":
        print(build_audio(wav)); sys.exit()
    if TEST and TEST[0] == "part":                       # python heimaey_reel.py … part <i> <n>
        render_part(int(TEST[1]), int(TEST[2]), os.path.join(OUT, f"part{int(TEST[1]):02d}.mp4")); sys.exit()
    if TEST and TEST[0] == "parallel":                   # python heimaey_reel.py … parallel <n>: n processes + concat + mux
        n = int(TEST[1]); ps = [subprocess.Popen([sys.executable, os.path.abspath(__file__), P, FONTS, OUT, "part", str(i), str(n)]) for i in range(n)]
        [p.wait() for p in ps]
        lst = os.path.join(OUT, "parts.txt"); open(lst, "w").write("".join(f"file 'part{i:02d}.mp4'\n" for i in range(n)))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", tmp])
        TEST = []
    else:
        rk.run(frame, TOTAL, tmp, TEST)
    if not TEST:
        print(build_audio(wav))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-i", wav, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", final])
        print("muxed", final)
