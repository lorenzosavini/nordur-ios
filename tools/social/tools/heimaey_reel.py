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
def prep_clip():
    src, dst = os.path.join(V, "v_lava.webm"), os.path.join(V, "lava_portrait.mp4")
    if os.path.exists(src) and not os.path.exists(dst):   # 1280×720 → centred 405×720 portrait crop, 9 s, all-intra
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "14", "-i", src, "-t", "9", "-an", "-vf", "crop=405:720:560:0,scale=540:960:flags=lanczos",
                        "-c:v", "libx264", "-g", "1", "-crf", "14", dst])
    return Clip(dst)
LAVA = prep_clip()
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
    img = bg_lava(t, 0.75)
    wl = mk.water_field(t)
    img = mk.light_leak(img, t, ACC, 0.25)
    rise(img, "IN 1973 THEY FOUGHT", 520, t, -1, 96, TEXT)
    tex_text(img, "A VOLCANO", 250, 720, mk.lava_field(t * 1.5, 1.4) * 1.1 + 40, t, base=ACC)
    rise(img, "WITH", 900, t, -1, 96, TEXT)
    tex_text(img, "SEAWATER", 250, 1080, wl * 1.2 + 30, t, base=BLUE)
    return img
def s_erupt(t, fi):
    t0 = SH_T["erupt"]; img = blurbg("simkin", 0.42); img = ASH.apply(img, t, 0.8)
    archive_card(img, "simkin", t, fi, 1000, W / 2, 800, t0, 99, "pop", -1.5, 0.15)
    slam(img, "RIGHT NEXT TO A TOWN", 330, t, wt("hook", "right") , 110, TEXT)
    credit(img, "Heimaey, 1973 · " + CRED.get("simkin", ""))
    return img
def s_vs(t, fi):
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]; xx = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    lt = t - SH_T["vs"]; edge = 0.5 + 0.06 * np.sin(xx * 9 + t * 3) - 0.12 * (xx - 0.5) + 0.04 * math.sin(t * 2)
    m = np.clip((yy - edge) * 60, 0, 1)[..., None]
    lava, water = mk.lava_field(t, 1.2), mk.water_field(t)
    img = lava * (1 - m) + water * m
    seam = np.exp(-np.abs(yy - edge) * 160)[..., None]; img = np.minimum(255, img + seam * np.array((255, 245, 230), np.float32) * 0.9)
    img = mk.Particles.apply(EMB, img, t, 0.6)
    slam(img, "FIRE", 560, t, SH_T["vs"] + 0.02, 230, ACC)
    slam(img, "vs", 960, t, SH_T["vs"] + 0.3, 110, TEXT)
    slam(img, "SEAWATER", 1240, t, wt("hook", "seawater") - 0.05, 210, BLUE)
    return img
def s_clock(t, fi):
    t0 = SH_T["clock"]; lt = t - t0
    img = np.zeros((H, W, 3), np.float32) + np.array((6, 9, 16), np.float32)
    img = img + mk.water_field(t * 0.4) * 0.18; img = ASH2.apply(img, t, 0.5); img = mk.scanlines(img, t, 6, 0.12)
    rise(img, "23 JANUARY 1973", 470, t, t0 + 0.1, 92, DIM, font="cond")
    tb = wt("night", "before"); m = min(59, 52 + int(max(0, t - t0) * 2.2))
    L = tlayer(f"01:{m:02d}", 300, ACC if (fi // 8) % 2 else (255, 140, 90), "mono", 10)
    mk.over(img, L, W / 2, 740, 1 + 0.02 * math.sin(lt * 6), 0, min(1, lt / 0.2))
    rise(img, "A.M.", 930, t, t0 + 0.2, 70, TEXT, font="mono")
    chip(img, "Heimaey · Westman Islands, South Iceland", 70, 1060, t, wt("night", "Heimaey") - 0.1, 99, ACC, "volcano", 30)
    return img
def s_fissure(t, fi):
    t0 = SH_T["fissure"]; ts = wt("night", "splits")
    src = mk.speed_map(t, [(t0 - 1, 0.45), (ts - 0.1, 1.8), (ts + 0.6, 0.9)]) + 1.0
    f = LAVA.at(src)
    img = mk.cover(f, W, H, 1.06 + 0.04 * (t - t0)) if f is not None else mk.lava_field(t, 1.5)
    img = mk.light_leak(img, t, ACC, 0.25, 2)
    slam(img, "THE GROUND", 520, t, ts - 0.05, 170, TEXT)
    slam(img, "SPLITS OPEN", 700, t, ts + 0.12, 190, ACC)
    credit(img, "Illustrative footage: Iceland, 2021 · J. St. John · CC BY 2.0")
    return img
def s_harbour(t, fi):
    t0 = SH_T["harbour"]; a = photo("twovol"); lt = t - t0
    img = mk.cover(a, W, H, 1.05 + 0.03 * lt, 0.75 - 0.06 * lt, 0.5) if a is not None else bg_water(t)
    img = img * np.array((0.55, 0.62, 0.78), np.float32)                               # storm grade
    img = img + mk.stripes(t, (200, 220, 255), 34, 3, -72, 900, 0.22)                 # driving rain
    slam(img, "THE FLEET WAS", 470, t, wt("fleet", "fishing") - 0.15, 120, TEXT)
    slam(img, "IN PORT", 620, t, wt("fleet", "port") - 0.05, 190, BLUE)
    chip(img, "A storm kept the boats home", 70, 1080, t, t0 + 0.15, 99, BLUE, "cloud", 32)
    credit(img, "Heimaey harbour today · " + CRED.get("twovol", ""))
    return img
BOATS = [(0.0, 0.62, 1.0), (0.18, 0.7, 0.8), (0.33, 0.58, 0.9), (0.5, 0.76, 1.1), (0.66, 0.64, 0.85), (0.8, 0.72, 0.95), (0.92, 0.6, 0.8)]
def boat(img, x, y, s, t, ph):
    pts = np.array([(-90, 0), (90, 0), (60, 34), (-70, 34)], np.float32) * s
    cab = np.array([(-30, 0), (30, 0), (30, -40), (-30, -40)], np.float32) * s
    bob = 6 * math.sin(t * 3 + ph); r = 3 * math.sin(t * 2.2 + ph)
    M = cv2.getRotationMatrix2D((0, 0), r, 1)[:, :2]
    for poly, col in ((pts, (235, 238, 242)), (cab, (255, 90, 31))):
        p = (poly @ M.T + np.array([x, y + bob])).astype(np.int32); cv2.fillPoly(img, [p], col, cv2.LINE_AA)
    cv2.line(img, (int(x), int(y + bob - 40 * s)), (int(x - 6), int(y + bob - 100 * s)), (235, 238, 242), max(2, int(4 * s)), cv2.LINE_AA)
def s_evac(t, fi):
    t0 = SH_T["evac"]; lt = t - t0
    img = bg_water(t, 0.55)
    for i, (x0, yf, s) in enumerate(BOATS):                                          # the fleet sails out, wave lines scroll
        x = (x0 * 1300 + lt * 160 * (1 + 0.15 * i)) % 1400 - 160; boat(img, x, H * yf, s * 0.9, t, i)
    for j in range(6):
        y = int(H * 0.56 + j * 70); xs = np.arange(0, W + 20, 20); ys = y + 10 * np.sin(xs / 60 + t * 4 + j)
        cv2.polylines(img, [np.stack([xs, ys], 1).astype(np.int32)], False, (120, 170, 255), 2, cv2.LINE_AA)
    tw = wt("fleet", "Within"); ts = wt("fleet", "safe")
    k = mk.ease((t - wt("fleet", "5,300") + 0.3) / 1.0); n = int(5300 * k)
    if t >= tw - 0.1:
        r = 120; cx, cy = W / 2, 470; prog = min(1, (t - tw) / 1.3)                    # 6-hour ring fills
        cv2.circle(img, (int(cx), int(cy)), r, (40, 50, 70), 16, cv2.LINE_AA)
        cv2.ellipse(img, (int(cx), int(cy)), (r, r), -90, 0, 360 * prog, ACC, 16, cv2.LINE_AA)
        mk.over(img, tlayer(f"{max(1, int(6 * prog))}h", 110, TEXT), cx, cy + 8, 1, 0, 1)
        rise(img, "6 HOURS", 680, t, tw, 110, TEXT)
    if t >= wt("fleet", "5,300") - 0.3:
        L = tlayer(f"{n:,}", 220, GREEN if t > ts else TEXT); mk.over(img, L, W / 2, 900, 1, 0, 1)
        rise(img, "PEOPLE SAFE" if t > ts else "PEOPLE", 1080, t, wt("fleet", "5,300"), 80, GREEN if t > ts else DIM)
    return img
def s_street(t, fi):
    t0 = SH_T["street"]; img = bg_lava(t, 0.55, 1.3)
    img = img + mk.stripes(t, RED, 60, 14, -30, 120, 0.10)
    archive_card(img, "street", t, fi, 940, W / 2, 760, t0, 99, "right", 1.2, 0.2)
    slam(img, "LAVA IS COMING", 330, t, t0 + 0.05, 130, ACC)
    stamp(img, "HARBOUR AT RISK", W / 2, 1110, t, wt("threat", "harbour"), RED, 84)
    credit(img, "Lava enters a Heimaey street, 1973 · " + CRED.get("street", ""))
    return img
def s_ocean(t, fi):
    t0 = SH_T["ocean"]; img = bg_water(t * 1.6, 1.0)
    img = mk.light_leak(img, t, BLUE, 0.3, 4)
    slam(img, "PUMP", 520, t, wt("plan", "pump") - 0.05, 230, TEXT)
    tex_text(img, "THE OCEAN", 230, 760, mk.water_field(t * 2 + 3) * 1.3 + 40, t, wt("plan", "ocean") - 0.15, base=BLUE)
    slam(img, "ONTO THE LAVA", 990, t, wt("plan", "onto") - 0.05, 130, ACC)
    return img
def s_ship(t, fi):
    t0 = SH_T["ship"]; img = blurbg("ship", 0.4)
    fog = mk.steam_field(t, 5)[..., None]; img = img * (1 - fog * 0.35) + 200 * fog * 0.35
    archive_card(img, "ship", t, fi, 920, W / 2, 900, t0, 99, "drop", -2, 0.15)
    chip(img, "FIRE HOSES", 70, 300, t, wt("pumps", "Fire") - 0.1, 99, BLUE, "droplet", 38)
    chip(img, "A PUMP SHIP", 70, 410, t, wt("pumps", "pump") - 0.1, 99, BLUE, "droplet", 38)
    credit(img, "Ship spraying seawater onto the lava · " + CRED.get("ship", ""))
    return img
def s_pumps(t, fi):
    t0 = SH_T["pumps"]; img = blurbg("town73", 0.38)
    archive_card(img, "town73", t, fi, 1010, W / 2, 820, t0, 99, "pop", 1.0, 0.12)
    slam(img, "BIG PUMPS", 330, t, wt("pumps", "big") - 0.05, 150, TEXT)
    chip(img, "Leased from the United States", 70, 1110, t, wt("pumps", "U.S.") - 0.2, 99, ACC, "world", 32)
    credit(img, "Pumps on the pier, 1973 · " + CRED.get("town73", ""))
    return img
def s_steam(t, fi):
    t0 = SH_T["steam"]; img = bg_lava(t, 0.5, 1.2, False)
    archive_card(img, "steam", t, fi, 900, W / 2, 800, t0, 99, "left", -1.2, 0.15)
    fog = mk.steam_field(t * 1.5, 7)[..., None]; img = img * (1 - fog * 0.45) + 235 * fog * 0.45
    slam(img, "PIPES ACROSS", 300, t, wt("pumps", "pipes") - 0.05, 120, TEXT)
    slam(img, "MOVING LAVA", 440, t, wt("pumps", "moving") - 0.05, 150, ACC)
    credit(img, "Steam over the cooled lava · " + CRED.get("steam", ""))
    return img
def s_data(t, fi):
    t0 = SH_T["data"]; img = bg_water(t, 0.7); img = mk.scanlines(img, t, 8, 0.08)
    to = wt("months", "Over")
    # 1) five months timeline with the NASA thermal image
    if t < to + 0.3:
        archive_card(img, "thermo", t, fi, 420, W - 290, 760, t0, to + 0.3, "right", 2, 0.0, maxh=650)
        rise(img, "5 MONTHS", 380, t, t0 + 0.05, 150, TEXT, t1=to + 0.3, cx=380)
        rise(img, "24/7", 560, t, wt("months", "around") - 0.1, 150, ACC, t1=to + 0.3, cx=380)
        x0, x1, y = 110, 610, 760; prog = mk.ease((t - t0) / 1.6)
        cv2.line(img, (x0, y), (x1, y), (60, 80, 110), 12, cv2.LINE_AA); cv2.line(img, (x0, y), (int(x0 + (x1 - x0) * prog), y), BLUE, 12, cv2.LINE_AA)
        mk.over(img, tlayer("6 FEB", 40, DIM, "mono", 4), x0 + 50, y + 55, 1, 0, 1); mk.over(img, tlayer("10 JUL", 40, DIM, "mono", 4), x1 - 50, y + 55, 1, 0, 1)
        credit(img, CRED.get("thermo", ""))
    else:
        k = mk.ease((t - to) / 1.5); n = int(6_000_000 * k)
        tex_text(img, f"{n:,}", 200, 700, mk.water_field(t * 2 + 5) * 1.3 + 50, t, to, track=2, base=BLUE)
        slam(img, "CUBIC METRES", 880, t, to + 0.2, 110, TEXT)
        slam(img, "OF SEAWATER", 1010, t, to + 0.45, 110, BLUE)
        rise(img, "MORE THAN", 520, t, to, 80, DIM)
    return img
def s_after(t, fi):
    t0 = SH_T["after"]; img = blurbg("after", 0.4)
    archive_card(img, "after", t, fi, 1000, W / 2, 780, t0, 99, "pop", -1, 0.15)
    slam(img, "IT WORKED", 340, t, wt("works", "works") - 0.05, 190, GREEN)
    stamp(img, "THE HARBOUR SURVIVED", W / 2, 1110, t, wt("works", "short"), GREEN, 70, 6)
    credit(img, "Town and harbour after the eruption, 1973 · " + CRED.get("after", ""))
    return img
def s_fired(t, fi):
    t0 = SH_T["fired"]; a = photo("fired"); lt = t - t0
    img = mk.parallax(mk.archive(a, t, fi, 0.25), lt, 3.0, 0.55, 0.15, 1.06, 1.16, 0.06, 40, 0.5, 0.4) if a is not None else bg_lava(t)
    img = img * 0.8
    k = mk.ease((t - t0 - 0.1) / 1.0); slam(img, "~300", 420, t, t0 + 0.05, 260, ACC)
    rise(img, "BUILDINGS LOST", 610, t, t0 + 0.25, 120, TEXT)
    archive_card(img, "buried", t, fi, 380, 300, 960, wt("twist", "lost") + 0.2, 99, "drop", -6, 0.2)
    chip(img, "+ 60–70 homes buried by ash", 480, 1070, t, wt("twist", "lost") + 0.4, 99, DIM, None, 28)
    credit(img, "A house set alight by lava, 1973 · " + CRED.get("fired", ""))
    return img
def s_shield(t, fi):
    t0 = SH_T["shield"]; a = photo("harbour"); lt = t - t0
    img = mk.parallax(a, lt, 3.0, 0.42, 0.12, 1.05, 1.15, 0.08, 50, 0.45, 0.5) if a is not None else bg_water(t)
    img = img * 0.85
    slam(img, "NEW LAVA = BREAKWATER", 400, t, wt("twist", "shields") - 0.1, 120, TEXT)
    chip(img, "The new lava now shelters the harbour", 70, 1080, t, wt("twist", "harbour") - 0.1, 99, GREEN, "ripple", 30)
    credit(img, "Heimaey harbour and the 1973 lava today · " + CRED.get("harbour", ""))
    return img
def s_grow(t, fi):
    t0 = SH_T["grow"]; img = bg_lava(t, 0.45)
    tg = wt("twist", "grew"); k = mk.ease((t - tg) / 1.0)
    # abstract island: old outline + new land rim growing ≈ +20 % area (radius × √1.2)
    c = (W // 2, 780); R = 210
    ang = np.linspace(0, 2 * np.pi, 120); rr = R * (1 + 0.12 * np.sin(3 * ang + 1) + 0.07 * np.sin(5 * ang))
    grow = 1 + (math.sqrt(1.2) - 1) * k * (0.5 + 0.5 * np.cos(ang - 0.3)) * 1.9          # growth on the east side
    pn = np.stack([c[0] + rr * grow * np.cos(ang), c[1] + rr * grow * np.sin(ang) * 1.1], 1).astype(np.int32)
    po = np.stack([c[0] + rr * np.cos(ang), c[1] + rr * np.sin(ang) * 1.1], 1).astype(np.int32)
    cv2.fillPoly(img, [pn], ACC, cv2.LINE_AA); cv2.fillPoly(img, [po], (34, 40, 46), cv2.LINE_AA)
    cv2.polylines(img, [po], True, (200, 205, 210), 3, cv2.LINE_AA)
    tex_text(img, f"+{int(round(20 * k))}%", 260, 1130, mk.lava_field(t * 1.5, 1.5) * 1.2 + 40, t, tg - 0.1, track=2, base=ACC)
    rise(img, "THE ISLAND GREW", 380, t, t0 + 0.05, 110, TEXT)
    chip(img, "new land", 640, 600, t, tg + 0.3, 99, ACC, None, 28)
    return img
def s_eldfell(t, fi):
    t0 = SH_T["eldfell"]; a = photo("view"); lt = t - t0
    img = mk.parallax(a, lt, 3.2, 0.5, 0.14, 1.04, 1.16, 0.10, 70, 0.5, 0.5) * 0.8 if a is not None else bg_lava(t)
    tex_text(img, "ELDFELL", 250, 470, mk.lava_field(t * 1.5, 1.4) * 1.1 + 40, t, wt("today", "Eldfell") - 0.1, track=6, base=ACC)
    slam(img, "= FIRE MOUNTAIN", 660, t, wt("today", "Fire") - 0.05, 120, TEXT)
    credit(img, "View from Eldfell's summit · " + CRED.get("view", ""))
    return img
def s_museum(t, fi):
    t0 = SH_T["museum"]; a = photo("museum"); lt = t - t0
    img = mk.parallax(a, lt, 3.5, 0.45, 0.14, 1.04, 1.14, 0.08, -60, 0.5, 0.55) if a is not None else bg_lava(t)
    img = img * 0.82
    archive_card(img, "ash74", t, fi, 430, 290, 600, t0 + 0.2, wt("today", "Eldheimar") + 0.1, "drop", 7, 0.3)
    rise(img, "BURIED IN 1973", 400, t, t0 + 0.3, 70, DIM, t1=wt("today", "Eldheimar") + 0.1, cx=700)
    slam(img, "ELDHEIMAR", 440, t, wt("today", "Eldheimar") - 0.05, 200, TEXT)
    chip(img, "Eruption museum · opened 2014", 70, 1080, t, wt("today", "Eldheimar") + 0.3, 99, ACC, "home", 30)
    credit(img, "Eldheimar, house under the tephra · " + CRED.get("museum", "") + "  |  inset: " + CRED.get("ash74", ""))
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
    t0 = SH_T["app"]; img = bg_lava(t, 0.7)
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
    lt = t - st("cta"); img = bg_lava(t, 0.8)
    return img

SHOTS = [("title", 0, s_title), ("erupt", wt("hook", "erupts") - 0.1, s_erupt), ("vs", wt("hook", "So") - 0.05, s_vs),
         ("clock", st("night") - 0.05, s_clock), ("fissure", wt("night", "ground") - 0.25, s_fissure), ("harbour", st("fleet") - 0.1, s_harbour),
         ("evac", wt("fleet", "Within") - 0.6, s_evac), ("street", st("threat") - 0.1, s_street), ("ocean", st("plan") - 0.05, s_ocean),
         ("ship", st("pumps") - 0.1, s_ship), ("pumps", wt("pumps", "Then") - 0.05, s_pumps), ("steam", wt("pumps", "pipes") - 0.15, s_steam),
         ("data", st("months") - 0.1, s_data), ("after", st("works") - 0.1, s_after), ("fired", st("twist") - 0.1, s_fired),
         ("shield", wt("twist", "But") - 0.05, s_shield), ("grow", wt("twist", "island") - 0.3, s_grow), ("eldfell", st("today") - 0.1, s_eldfell),
         ("museum", wt("today", "And") - 0.05, s_museum), ("app", st("app") - 0.1, s_app), ("cta", st("cta") - 0.2, s_cta)]
SH_T = {n: s for n, s, _ in SHOTS}
# transition INTO each shot: (kind, duration)
TR = {"erupt": ("crack", 0.5), "vs": ("steam", 0.45), "clock": ("whip", 0.36), "fissure": ("crack", 0.55), "harbour": ("whip", 0.36),
      "evac": ("zoom", 0.4), "street": ("lava", 0.5), "ocean": ("steam", 0.45), "ship": ("whipv", 0.4), "pumps": ("whip", 0.34),
      "steam": ("whipl", 0.34), "data": ("circle", 0.45), "after": ("zoom", 0.4), "fired": ("lava", 0.5), "shield": ("whip", 0.36),
      "grow": ("zoom", 0.4), "eldfell": ("whipv", 0.4), "museum": ("circle", 0.45), "app": ("crack", 0.55), "cta": ("crack", 0.6)}
TRF = {"crack": lambda a, b, k, i: mk.crack_wipe(a, b, k, i), "steam": lambda a, b, k, i: mk.steam_flash(a, b, k, i),
       "whip": lambda a, b, k, i: mk.whip(a, b, k, 1), "whipl": lambda a, b, k, i: mk.whip(a, b, k, -1), "whipv": lambda a, b, k, i: mk.whip_v(a, b, k),
       "zoom": lambda a, b, k, i: mk.zoom_cut(a, b, k), "lava": lambda a, b, k, i: mk.lava_wipe(a, b, k, i), "circle": lambda a, b, k, i: mk.circle_wipe(a, b, k, W / 2, 800)}
SFX_OF = {"crack": [(-0.05, "impact", -2), (-0.1, "rumble", -3)], "steam": [(-0.25, "splash", -5), (-0.1, "sizzle", -8)], "whip": [(-0.3, "whoosh", -4)],
          "whipl": [(-0.3, "whoosh", -4)], "whipv": [(-0.3, "whoosh", -4)], "zoom": [(-0.28, "whoosh", -6), (0.0, "thud", -6)],
          "lava": [(-0.25, "rumble", -2), (0.0, "thud", -4)], "circle": [(-0.3, "whoosh", -7)]}
for name, s, _ in SHOTS:
    if name in TR:
        for dt, kind, g in SFX_OF[TR[name][0]]: ev(s + dt, kind, g)
# extra hits on slammed words / stamps (shake + impact), risers before the big hooks, sizzle under the pumping
for tt in (wt("night", "splits"), wt("threat", "harbour"), wt("works", "works"), st("twist") - 0.05, wt("twist", "grew"), wt("today", "Eldfell")):
    ev(tt, "impact", -5)
for tt in (wt("hook", "So"), st("plan"), st("works"), wt("twist", "island"), st("app")):
    ev(tt - 1.4, "riser", -12)
ev(st("pumps"), "sizzle_long", -12); ev(st("months"), "sizzle_long", -16)
for tt in (wt("app", "Norður") + 0.35, wt("app", "earthquake") - 0.05): ev(tt, "ping", -10)
for k in range(8): ev(SH_T["clock"] + 0.05 + k / 2.2, "tick", -18)
ev(0.0, "rumble_long", -6)

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
               "Photos: USGS, NASA, Smithsonian (public domain) · Óskar Elías Björnsson (CC BY 2.0) · Christian Bickel (CC BY-SA 2.0 de) · Szilas (PD) · bekassine (CC BY-SA 2.0) · Diego Delso (CC BY-SA 4.0) · footage: James St. John (CC BY 2.0) · AI voice · music & sfx: Norður")
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
    mix, stats = sx.master(voice, music[:n], fx_.x[:n], music_db=-19, sfx_db=-8)
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
