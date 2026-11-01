"""'Iceland's Christmas is terrifying' — the 13 Yule Lads, Grýla, Leppalúði and the Yule Cat.
Usage: python jol_reel.py <work> <fonts> <out_dir> [test frame numbers...]
<work>/jol/: *.img photos (projects/jol/dl.py), credits.json, ice.png (Iceland paper map z7), voice/{narration.wav,timeline.json}."""
import sys, os, json, math, subprocess, numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageOps
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo, reelkit as rk, fx
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
V = os.path.join(P, "jol"); TLL = json.load(open(os.path.join(V, "voice", "timeline.json")))
TL = {l["id"]: l for l in TLL}; ORDER = [l["id"] for l in TLL]
def st(i): return TL[i]["start"]
def en(i): return TL[i]["start"] + TL[i]["dur"]
TOTAL = en("cta") + 1.0
ACC, BLUE, GREEN, TEXT, DIM, GOLD = (255, 90, 31), (120, 170, 255), (61, 224, 168), (246, 246, 242), (180, 186, 192), (255, 200, 80)
BG = (7, 9, 12)
CRED = json.load(open(os.path.join(V, "credits.json"))) if os.path.exists(os.path.join(V, "credits.json")) else {}
_IMG = {}
def img(k):
    if k not in _IMG:
        p = os.path.join(V, k + ".img"); _IMG[k] = Image.open(p).convert("RGB") if os.path.exists(p) and os.path.getsize(p) > 1000 else None
    return _IMG[k]
def solid(c=BG): return Image.new("RGBA", (W, H), c + (255,))

# ——— word timing (captions are word-by-word; overlays sync to words) ———
WORDS = []
for i in ORDER:
    if i == "cta": continue
    l = TL[i]; ws = l["show"].split(); tot = sum(len(w) + 2 for w in ws); t0 = l["start"]
    for j, w in enumerate(ws):
        dd = l["dur"] * (len(w) + 2) / tot; WORDS.append((t0, t0 + dd, w, l["start"], l["start"] + l["dur"], i, j)); t0 += dd
def wt(line, word):
    """Start time of the first word in `line` that begins with `word`."""
    for w in WORDS:
        if w[5] == line and w[2].strip(".,?!").lower().startswith(word.lower()): return w[0]
    return st(line)
def captions(im, t):
    cur = [w for w in WORDS if w[3] <= t < w[4] + 0.12]
    if not cur: return
    line = [w for w in WORDS if w[3] == cur[0][3]]
    k = next((i for i, w in enumerate(line) if w[0] <= t < w[1]), len(line) - 1)
    c0 = (k // 3) * 3; chunk = line[c0:c0 + 3]
    d = ImageDraw.Draw(im, "RGBA"); f = COND(100); txt = " ".join(w[2] for w in chunk)
    while d.textlength(txt, font=f) > W - 80: f = COND(f.size - 6)
    x = (W - d.textlength(txt, font=f)) / 2; y = 1360; pop = fx.ease_out((t - chunk[0][0]) / 0.12)
    for j, w in enumerate(chunk):
        on = c0 + j == k
        d.text((x, y - (8 if on else 0) * pop), w[2], font=f, fill=ACC if on else (255, 255, 255), stroke_width=7, stroke_fill=(8, 8, 10))
        x += d.textlength(w[2] + " ", font=f)
CH = [("THE LADS", "hook", "mom"), ("THE FAMILY", "mom", "cat"), ("THE CAT", "cat", "poem"), ("THE NAMES", "poem", "end")]
def chapters(im, t):
    if not (st("lads") <= t < st("end")): return
    d = ImageDraw.Draw(im, "RGBA"); x0, y0, gap = 60, 150, 12; w = (W - 120 - gap * 3) / 4
    for i, (name, a, b) in enumerate(CH):
        x = x0 + i * (w + gap); on = st(a) <= t < st(b); k = 1.0 if t >= st(b) else (np.clip((t - st(a)) / (st(b) - st(a)), 0, 1) if on else 0)
        d.rounded_rectangle((x, y0, x + w, y0 + 8), 4, fill=(255, 255, 255, 60))
        if k > 0.01: d.rounded_rectangle((x, y0, x + w * k, y0 + 8), 4, fill=ACC + (255,))
        d.text((x, y0 + 16), name, font=MONO(20), fill=(255, 255, 255, 230 if on else 110))
def credit(im, text, y=1290):
    if not text: return
    d = ImageDraw.Draw(im, "RGBA"); f = MONO(18); tw = d.textlength(text, font=f)
    d.rounded_rectangle((W - 50 - tw - 20, y, W - 50, y + 32), 8, fill=(0, 0, 0, 150)); d.text((W - 50 - tw - 10, y + 6), text, font=f, fill=(225, 225, 225))

# ——— generic helpers ———
def kenburns(src, t, dur, z0=1.05, z1=1.18, fy=0.5, fx_=0.5, dark=1.0):
    k = fx.ease_out(t / dur) if dur else 1; z = z0 + (z1 - z0) * k
    s = max(W / src.width, H / src.height) * z; r = src.resize((int(src.width * s) + 1, int(src.height * s) + 1), Image.BILINEAR)
    x = int((r.width - W) * fx_); y = int((r.height - H) * fy); im = r.crop((x, y, x + W, y + H))
    if dark != 1.0: im = ImageEnhance.Brightness(im).enhance(dark)
    return im.convert("RGBA")
_BB = {}
def blurbg(k, dark=0.4, tint=None):
    key = (k, dark, tint)
    if img(k) is None: return solid()
    if key not in _BB:
        im = ImageOps.fit(img(k), (W // 4, H // 4)).filter(ImageFilter.GaussianBlur(6)).resize((W, H), Image.BILINEAR)
        im = ImageEnhance.Brightness(im).enhance(dark).convert("RGBA")
        if tint: im.alpha_composite(Image.new("RGBA", (W, H), tint))
        _BB[key] = im
    return _BB[key].copy()
def chip(im, text, x, y, a=1.0, col=ACC, size=34):
    d = ImageDraw.Draw(im, "RGBA"); f = SANS(size); tw = d.textlength(text, font=f); h = size * 2.0; w = tw + h * 0.9
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
    dl.rounded_rectangle((x + 4, y + 8, x + w + 4, y + h + 8), h / 2, fill=(0, 0, 0, int(120 * a))); im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(8)))
    d.rounded_rectangle((x, y, x + w, y + h), h / 2, fill=(255, 255, 255, int(255 * a)))
    d.ellipse((x + 14, y + h / 2 - 9, x + 32, y + h / 2 + 9), fill=col + (int(255 * a),))
    d.text((x + 46, y + h * 0.24), text, font=f, fill=(12, 14, 18, int(255 * a)))
def chip_anim(im, text, x, y, t, t0, t1, col=ACC):
    e = fx.env(t, t0, t1, 0.35, 0.25)
    if e is None: return
    pi, po = e; a = min(1, pi * 2) * (1 - po)
    chip(im, text, x - 80 * (1 - fx.ease_out(pi)) - 80 * fx.ease_in(po), y, a, col)
def big_text(im, text, y, t, t0, size=230, col=TEXT, x=None, t1=None):
    if t < t0 or (t1 and t > t1): return
    k = fx.back((t - t0) / 0.45); a = 1.0 if not t1 else 1 - fx.ease_in((t - (t1 - 0.25)) / 0.25)
    f = COND(int(size * (0.7 + 0.3 * k))); d = ImageDraw.Draw(im, "RGBA"); tw = d.textlength(text, font=f)
    d.text(((W - tw) / 2 if x is None else x, y + (1 - k) * 40), text, font=f, fill=col + (int(255 * a),), stroke_width=10, stroke_fill=(10, 10, 12, int(255 * a)))
def stamp_in(im, L, cx, cy, t, t0, t1=None):
    if t < t0 or (t1 and t > t1): return 0
    k = fx.ease_out((t - t0) / 0.18); s = 2 - k
    L2 = L.resize((int(L.width * s), int(L.height * s)))
    if t1 and t > t1 - 0.25: L2 = L2.copy(); L2.putalpha(L2.getchannel("A").point(lambda v: int(v * (1 - fx.ease_in((t - t1 + 0.25) / 0.25)))))
    im.alpha_composite(L2, (int(cx - L2.width / 2), int(cy - L2.height / 2)))
    return 10 * (1 - (t - t0) / 0.4) if t - t0 < 0.4 else 0
def glow(L, r=26, k=1.0):
    g = L.filter(ImageFilter.GaussianBlur(r)); out = Image.new("RGBA", L.size, (0, 0, 0, 0))
    for _ in range(int(k * 2) or 1): out.alpha_composite(g)
    out.alpha_composite(L); return out

# ——— snow (deterministic particles) ———
RNG = np.random.default_rng(7); NF = 170
FL = dict(x=RNG.uniform(0, W, NF), y=RNG.uniform(0, H, NF), v=RNG.uniform(50, 170, NF), r=RNG.uniform(2, 7, NF), ph=RNG.uniform(0, 6.28, NF), f=RNG.uniform(0.4, 1.2, NF))
def snow(im, t, a=1.0):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    ys = (FL["y"] + FL["v"] * t) % (H + 40) - 20; xs = (FL["x"] + 28 * np.sin(t * FL["f"] + FL["ph"]) + 18 * t) % W
    for x, y, r in zip(xs, ys, FL["r"]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, int((90 + r * 22) * a)))
    im.alpha_composite(lay)

# ——— drawn characters (original graphics: the 1932 illustrations are under copyright) ———
SK = 2
def _scale(L): return L.resize((L.width // SK, L.height // SK), Image.LANCZOS)
def prop(d, kind, x, y, s):
    """Draw a lad's 'speciality' prop centred at (x, y), size unit s."""
    if kind == "spoon":
        d.line((x - 1.1 * s, y + 1.1 * s, x + 0.5 * s, y - 0.5 * s), fill=(176, 120, 70), width=int(0.22 * s))
        d.ellipse((x + 0.25 * s, y - 1.05 * s, x + 1.05 * s, y - 0.25 * s), fill=(196, 140, 86), outline=(120, 80, 44), width=int(0.08 * s))
        d.ellipse((x + 0.4 * s, y - 0.9 * s, x + 0.9 * s, y - 0.4 * s), fill=(250, 246, 236))
    elif kind == "door":
        d.rectangle((x - 0.6 * s, y - 1.1 * s, x + 0.6 * s, y + 1.1 * s), fill=(150, 96, 56), outline=(80, 50, 30), width=int(0.08 * s))
        for k in (-0.3, 0, 0.3): d.line((x + k * s, y - 1.0 * s, x + k * s, y + 1.0 * s), fill=(110, 70, 40), width=int(0.05 * s))
        d.ellipse((x + 0.32 * s, y - 0.06 * s, x + 0.46 * s, y + 0.08 * s), fill=GOLD)
        for k in (-0.6, 0, 0.6): d.line((x - 1.25 * s, y + k * s, x - 0.85 * s, y + k * s * 1.2), fill=(255, 255, 255), width=int(0.08 * s))
    elif kind == "skyr":
        d.pieslice((x - 1.0 * s, y - 0.9 * s, x + 1.0 * s, y + 0.9 * s), 0, 180, fill=(120, 170, 255), outline=(60, 90, 150), width=int(0.08 * s))
        d.ellipse((x - 1.0 * s, y - 0.25 * s, x + 1.0 * s, y + 0.25 * s), fill=(250, 250, 246))
        d.ellipse((x - 0.2 * s, y - 0.9 * s, x + 0.4 * s, y - 0.1 * s), fill=(250, 250, 246))
    elif kind == "sausage":
        for i in range(3):
            cx = x - 0.9 * s + i * 0.9 * s; cy = y + (0.25 if i % 2 else -0.15) * s
            d.rounded_rectangle((cx - 0.45 * s, cy - 0.22 * s, cx + 0.45 * s, cy + 0.22 * s), int(0.22 * s), fill=(176, 64, 48), outline=(110, 36, 26), width=int(0.06 * s))
            d.line((cx - 0.2 * s, cy - 0.08 * s, cx + 0.15 * s, cy - 0.1 * s), fill=(230, 140, 120), width=int(0.06 * s))
    elif kind == "window":
        d.rectangle((x - 0.9 * s, y - 0.9 * s, x + 0.9 * s, y + 0.9 * s), fill=(36, 60, 110), outline=(240, 236, 226), width=int(0.16 * s))
        d.line((x, y - 0.9 * s, x, y + 0.9 * s), fill=(240, 236, 226), width=int(0.12 * s)); d.line((x - 0.9 * s, y, x + 0.9 * s, y), fill=(240, 236, 226), width=int(0.12 * s))
        d.ellipse((x - 0.65 * s, y - 0.62 * s, x - 0.25 * s, y - 0.22 * s), fill=(255, 255, 255)); d.ellipse((x - 0.5 * s, y - 0.48 * s, x - 0.36 * s, y - 0.34 * s), fill=(10, 10, 12))
    elif kind == "candle":
        d.rounded_rectangle((x - 0.25 * s, y - 0.5 * s, x + 0.25 * s, y + 1.1 * s), int(0.08 * s), fill=(250, 246, 230), outline=(200, 190, 170), width=int(0.05 * s))
        d.ellipse((x - 0.5 * s, y - 1.3 * s, x + 0.5 * s, y - 0.3 * s), fill=(255, 200, 80, 90))
        d.polygon([(x, y - 1.25 * s), (x + 0.2 * s, y - 0.75 * s), (x, y - 0.55 * s), (x - 0.2 * s, y - 0.75 * s)], fill=(255, 170, 40))
def lad(kind, cap=(170, 40, 40), w=300, h=330):
    L = Image.new("RGBA", (w * SK, h * SK), (0, 0, 0, 0)); d = ImageDraw.Draw(L); s = SK
    cx = w * s / 2
    d.ellipse((cx - 130 * s, 250 * s, cx + 130 * s, 420 * s), fill=(70, 66, 62))                     # wool coat
    d.ellipse((cx - 74 * s, 92 * s, cx + 74 * s, 236 * s), fill=(232, 196, 168))                      # face
    d.polygon([(cx - 80 * s, 170 * s), (cx + 80 * s, 170 * s), (cx + 60 * s, 270 * s), (cx, 320 * s), (cx - 60 * s, 270 * s)], fill=(228, 226, 220))  # beard
    d.ellipse((cx - 70 * s, 150 * s, cx + 70 * s, 270 * s), fill=(228, 226, 220))
    d.ellipse((cx - 48 * s, 176 * s, cx - 2 * s, 204 * s), fill=(214, 212, 206)); d.ellipse((cx + 2 * s, 176 * s, cx + 48 * s, 204 * s), fill=(214, 212, 206))
    d.ellipse((cx - 20 * s, 150 * s, cx + 20 * s, 190 * s), fill=(214, 128, 110))                     # nose
    for ex in (-34, 34):
        d.ellipse((cx + (ex - 9) * s, 132 * s, cx + (ex + 9) * s, 152 * s), fill=(20, 18, 20)); d.ellipse((cx + (ex - 3) * s, 135 * s, cx + (ex + 2) * s, 140 * s), fill=(255, 255, 255))
        d.line((cx + (ex - 18) * s, (122 - (ex > 0) * 6) * s, cx + (ex + 16) * s, (116 + (ex > 0) * 6) * s), fill=(150, 146, 140), width=6 * s)
    d.polygon([(cx - 84 * s, 118 * s), (cx + 84 * s, 118 * s), (cx + 40 * s, 40 * s), (cx + 120 * s, 4 * s), (cx - 10 * s, 18 * s)], fill=cap)  # floppy wool cap
    d.rounded_rectangle((cx - 90 * s, 100 * s, cx + 90 * s, 128 * s), 12 * s, fill=tuple(int(c * 0.75) for c in cap))
    d.ellipse((cx + 104 * s, -6 * s, cx + 136 * s, 26 * s), fill=(240, 236, 226))
    prop(d, kind, cx + 92 * s, 268 * s, 46 * s)
    return _scale(L)
def lad_card(kind, date, isl, eng, cap):
    w, h = 300, 400; c = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(c)
    d.rounded_rectangle((0, 0, w - 1, h - 1), 26, fill=(18, 24, 34, 245), outline=(255, 255, 255, 60), width=2)
    d.text((18, 14), date, font=MONO(24), fill=ACC)
    c.alpha_composite(lad(kind, cap, 260, 286), (20, 44))
    f = COND(46)
    while d.textlength(isl, font=f) > w - 30: f = COND(f.size - 2)
    d.text(((w - d.textlength(isl, font=f)) / 2, 318), isl, font=f, fill=TEXT)
    d.text(((w - d.textlength(eng, font=SANS(24))) / 2, 364), eng, font=SANS(24), fill=GREEN)
    sh = Image.new("RGBA", (w + 60, h + 60), (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle((30, 42, w + 30, h + 42), 26, fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(14)); sh.alpha_composite(c, (30, 30)); return sh
def gryla(w=760, h=900):
    L = Image.new("RGBA", (w * SK, h * SK), (0, 0, 0, 0)); d = ImageDraw.Draw(L); s = SK; cx = w * s / 2
    r = np.random.default_rng(3)
    d.ellipse((cx - 360 * s, 560 * s, cx + 360 * s, 1300 * s), fill=(34, 30, 34))                     # hunched shoulders / shawl
    for i in range(140):                                                                              # wild hair radiating from the head
        a = r.uniform(-math.pi * 1.05, math.pi * 0.05); l = r.uniform(80, 190); w0 = r.uniform(-0.25, 0.25)
        x0, y0 = cx + math.cos(a) * 160 * s, 430 * s + math.sin(a) * 210 * s
        pts = [(x0 + math.cos(a + w0 * math.sin(u * 3)) * l * u * s, y0 + math.sin(a + w0 * math.sin(u * 3)) * l * u * s + 40 * u * u * s) for u in np.linspace(0, 1, 6)]
        g = 50 + int(r.uniform(0, 40)); d.line(pts, fill=(g, g, g + 6), width=int(r.uniform(6, 14) * s), joint="curve")
    d.ellipse((cx - 190 * s, 210 * s, cx + 190 * s, 640 * s), fill=(96, 110, 98))                     # face
    for ex in (-80, 80):
        d.ellipse((cx + (ex - 46) * s, 330 * s, cx + (ex + 46) * s, 392 * s), fill=(255, 140, 40))
        d.ellipse((cx + (ex - 14) * s, 340 * s, cx + (ex + 14) * s, 384 * s), fill=(30, 10, 0))
        d.line((cx + (ex - 70) * s, (300 if ex < 0 else 330) * s, cx + (ex + 70) * s, (330 if ex < 0 else 300) * s), fill=(40, 40, 40), width=18 * s)
    d.polygon([(cx - 26 * s, 380 * s), (cx + 26 * s, 380 * s), (cx + 60 * s, 520 * s), (cx + 10 * s, 540 * s)], fill=(80, 94, 82))  # long nose
    d.ellipse((cx + 30 * s, 470 * s, cx + 60 * s, 500 * s), fill=(60, 50, 40))                        # wart
    d.chord((cx - 120 * s, 520 * s, cx + 120 * s, 640 * s), 0, 180, fill=(30, 10, 12))                 # mouth
    for i in range(6): x = cx - 100 * s + i * 40 * s; d.polygon([(x, 580 * s), (x + 30 * s, 580 * s), (x + 15 * s, (610 if i % 2 else 618) * s)], fill=(240, 232, 200))
    return _scale(L)
def pot(w=420, h=330):
    L = Image.new("RGBA", (w * SK, h * SK), (0, 0, 0, 0)); d = ImageDraw.Draw(L); s = SK
    d.chord((20 * s, 60 * s, (w - 20) * s, (h - 10) * s), 0, 180, fill=(24, 24, 28)); d.rectangle((20 * s, 120 * s, (w - 20) * s, 200 * s), fill=(24, 24, 28))
    d.ellipse((10 * s, 90 * s, (w - 10) * s, 150 * s), fill=(44, 44, 50)); d.ellipse((30 * s, 98 * s, (w - 30) * s, 142 * s), fill=(150, 90, 40))
    for x in (60, 160, 260, 340): d.ellipse(((x - 8) * s, 108 * s, (x + 8) * s, 122 * s), fill=(220, 160, 90))
    return _scale(L)
def leppaludi(w=420, h=470):
    L = Image.new("RGBA", (w * SK, h * SK), (0, 0, 0, 0)); d = ImageDraw.Draw(L); s = SK; cx = w * s / 2
    d.ellipse((cx - 190 * s, 300 * s, cx + 190 * s, 620 * s), fill=(70, 60, 54))
    d.ellipse((cx - 120 * s, 120 * s, cx + 120 * s, 380 * s), fill=(150, 150, 130))
    d.polygon([(cx - 130 * s, 190 * s), (cx + 130 * s, 190 * s), (cx + 170 * s, 100 * s), (cx + 220 * s, 210 * s), (cx + 60 * s, 40 * s), (cx - 80 * s, 60 * s)], fill=(110, 90, 140))  # nightcap
    d.ellipse((cx + 196 * s, 196 * s, cx + 236 * s, 236 * s), fill=(240, 236, 226))
    for ex in (-48, 48): d.chord((cx + (ex - 28) * s, 236 * s, cx + (ex + 28) * s, 272 * s), 0, 180, fill=(30, 30, 30))  # sleepy eyes
    d.ellipse((cx - 24 * s, 250 * s, cx + 24 * s, 310 * s), fill=(120, 130, 110)); d.ellipse((cx - 40 * s, 324 * s, cx + 40 * s, 350 * s), fill=(60, 40, 40))
    return _scale(L)
def cat_head(w=900, h=760):
    L = Image.new("RGBA", (w * SK, h * SK), (0, 0, 0, 0)); d = ImageDraw.Draw(L); s = SK; cx = w * s / 2
    d.polygon([(cx - 400 * s, 360 * s), (cx - 330 * s, 0), (cx - 120 * s, 200 * s), (cx + 120 * s, 200 * s), (cx + 330 * s, 0), (cx + 400 * s, 360 * s), (cx + 300 * s, 700 * s), (cx - 300 * s, 700 * s)], fill=(14, 14, 18))
    d.ellipse((cx - 420 * s, 160 * s, cx + 420 * s, 760 * s), fill=(14, 14, 18))
    for sx in (-1, 1):
        d.polygon([(cx + sx * 330 * s, 40 * s), (cx + sx * 280 * s, 190 * s), (cx + sx * 170 * s, 200 * s)], fill=(60, 30, 36))
        for k in range(3): d.line((cx + sx * 120 * s, (520 + k * 30) * s, cx + sx * 420 * s, (480 + k * 60) * s), fill=(90, 90, 96), width=4 * s)
    return _scale(L)
def cat_eyes(w=900, h=760, open_=1.0):
    L = Image.new("RGBA", (w * SK, h * SK), (0, 0, 0, 0)); d = ImageDraw.Draw(L); s = SK; cx = w * s / 2
    hh = 70 * open_
    for sx in (-1, 1):
        x = cx + sx * 170 * s
        if hh > 2:
            d.ellipse((x - 100 * s, (380 - hh) * s, x + 100 * s, (380 + hh) * s), fill=(255, 210, 40))
            d.ellipse((x - 16 * s, (380 - hh * 0.95) * s, x + 16 * s, (380 + hh * 0.95) * s), fill=(10, 8, 0))
    d.polygon([(cx - 30 * s, 470 * s), (cx + 30 * s, 470 * s), (cx, 500 * s)], fill=(80, 40, 50))
    return glow(_scale(L), 22, 1.5)
def window_scene(w=760, h=820):
    L = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((0, 0, w - 1, h - 120), 18, fill=(70, 46, 30))
    g = Image.new("RGBA", (w - 80, h - 200)); gd = ImageDraw.Draw(g)
    for y in range(g.height): gd.line((0, y, g.width, y), fill=(12 + y // 30, 22 + y // 22, 48 + y // 12))
    r = np.random.default_rng(5)
    for _ in range(40): x, y = r.uniform(0, g.width), r.uniform(0, g.height * 0.7); gd.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(255, 255, 255, 200))
    L.alpha_composite(g, (40, 40))
    d.line((w / 2, 40, w / 2, h - 160), fill=(70, 46, 30), width=22); d.line((40, (h - 120) / 2, w - 40, (h - 120) / 2), fill=(70, 46, 30), width=22)
    d.rounded_rectangle((-10 + 10, h - 140, w - 10, h - 90), 12, fill=(240, 240, 236))                  # snowy sill
    d.rounded_rectangle((10, h - 100, w - 10, h - 60), 10, fill=(90, 60, 40))
    return L
def shoe(w=300, h=200):
    L = Image.new("RGBA", (w * SK, h * SK), (0, 0, 0, 0)); d = ImageDraw.Draw(L); s = SK
    d.polygon([(30 * s, 40 * s), (130 * s, 40 * s), (140 * s, 110 * s), (260 * s, 130 * s), (285 * s, 170 * s), (280 * s, 190 * s), (20 * s, 190 * s)], fill=(120, 70, 40))
    d.rectangle((20 * s, 176 * s, 285 * s, 196 * s), fill=(40, 26, 18)); d.ellipse((30 * s, 30 * s, 132 * s, 56 * s), fill=(60, 36, 22))
    for i in range(4): d.line(((140 + i * 22) * s, (112 + i * 4) * s, (160 + i * 22) * s, (100 + i * 4) * s), fill=(240, 230, 210), width=4 * s)
    return _scale(L)
def gift(w=170, h=160):
    L = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rectangle((10, 50, w - 10, h - 4), fill=(220, 40, 50)); d.rectangle((w / 2 - 12, 50, w / 2 + 12, h - 4), fill=GOLD); d.rectangle((4, 40, w - 4, 66), fill=(190, 30, 40))
    d.ellipse((w / 2 - 50, 6, w / 2, 46), outline=GOLD, width=10); d.ellipse((w / 2, 6, w / 2 + 50, 46), outline=GOLD, width=10)
    return L
def potato(w=200, h=150):
    L = Image.new("RGBA", (w, h + 70), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.ellipse((10, 70, w - 10, h + 60), fill=(120, 96, 60)); d.ellipse((40, 80, 120, 130), fill=(140, 116, 76))
    for x, y in ((60, 140), (130, 110), (150, 160), (90, 170)): d.ellipse((x - 9, y - 7, x + 9, y + 7), fill=(70, 60, 40))
    for i, x in enumerate((60, 100, 140)): d.arc((x - 20, 6 + i * 6, x + 20, 66), 200, 340, fill=(140, 200, 80), width=6)
    return L
def book(names_k):
    w, h = 900, 600; L = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((0, 20, w, h), 20, fill=(120, 40, 36))
    d.polygon([(20, 30), (w / 2, 50), (w / 2, h - 16), (20, h - 30)], fill=(244, 236, 216)); d.polygon([(w - 20, 30), (w / 2, 50), (w / 2, h - 16), (w - 20, h - 30)], fill=(250, 244, 226))
    d.line((w / 2, 50, w / 2, h - 16), fill=(200, 190, 170), width=4)
    ink = (40, 30, 26)
    for i, (txt, f) in enumerate((("JÓLIN", COND(84)), ("KOMA", COND(84)))): d.text((60, 110 + i * 86), txt, font=f, fill=(150, 40, 36))
    d.text((60, 300), "Jóhannes úr Kötlum", font=SANS(30), fill=ink); d.text((60, 350), "1932", font=MONO(34), fill=ink)
    NAMES = ["Stekkjarstaur", "Giljagaur", "Stúfur", "Þvörusleikir", "Pottaskefill", "Askasleikir", "Hurðaskellir", "Skyrgámur", "Bjúgnakrækir", "Gluggagægir", "Gáttaþefur", "Ketkrókur", "Kertasníkir"]
    for i, n in enumerate(NAMES[:int(names_k)]): d.text((w / 2 + 40, 70 + i * 39), f"{i + 1:>2}. {n}", font=MONO(26), fill=ink)
    sh = Image.new("RGBA", (w + 80, h + 80), (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle((40, 60, w + 40, h + 50), 20, fill=(0, 0, 0, 180))
    sh = sh.filter(ImageFilter.GaussianBlur(18)); sh.alpha_composite(L, (40, 30)); return sh
def icon(name, size, col=(255, 255, 255)):
    p = os.path.join(P, "icons", name + ".png")
    if not os.path.exists(p): p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons", name + ".png")
    a = Image.open(p).convert("RGBA").resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", a.size, col + (255,)); out.putalpha(a.getchannel("A")); return out

# ——— pre-built graphics ———
CAPS = [(170, 40, 40), (60, 90, 140), (60, 120, 80), (150, 100, 40), (110, 60, 130), (170, 40, 40)]
CARDS = [lad_card(k, dt, isl, eng, CAPS[i]) for i, (k, dt, isl, eng) in enumerate([
    ("spoon", "DEC 15", "Þvörusleikir", "Spoon Licker"), ("door", "DEC 18", "Hurðaskellir", "Door Slammer"), ("skyr", "DEC 19", "Skyrgámur", "Skyr Gobbler"),
    ("sausage", "DEC 20", "Bjúgnakrækir", "Sausage Swiper"), ("window", "DEC 21", "Gluggagægir", "Window Peeper")])]
CANDLE_BIG = None
CANDLE = lad_card("candle", "DEC 24", "Kertasníkir", "Candle Beggar", (150, 30, 40))
CANDLE_BIG = CANDLE.resize((int(CANDLE.width * 1.45), int(CANDLE.height * 1.45)), Image.LANCZOS)
GRYLA = glow(gryla(), 30, 0.5); POT = pot(); LEPPA = leppaludi(); CAT = cat_head(); SHOE = shoe(); GIFT = gift(); POTATO = potato(); WIN = window_scene()
STAMP_EAT = fx.stamp("EATS PEOPLE", COND(100), (230, 50, 50), -10)
STAMP_STEW = fx.stamp("NAUGHTY = STEW", COND(84), (230, 50, 50), 8)
STAMP_POT = fx.stamp("ROTTEN POTATO", COND(80), (200, 170, 60), -8)
STAMP_LAZY = fx.stamp("LAZY", COND(90), (255, 200, 60), 10)
SHIRT = glow(icon("shirt", 240, GOLD), 18, 0.5)
ICE = Image.open(os.path.join(V, "ice.png")).convert("RGB") if os.path.exists(os.path.join(V, "ice.png")) else None
def ice_card():
    if ICE is None: return None
    Z = 7; x0, y0 = geo.lonlat_to_px(-25, 66.7, Z); m = ICE.resize((ICE.width // 3, ICE.height // 3), Image.LANCZOS).convert("RGBA")
    d = ImageDraw.Draw(m); px, py = geo.lonlat_to_px(-16.91, 65.59, Z); px, py = (px - x0) * 2 / 3, (py - y0) * 2 / 3
    d.ellipse((px - 26, py - 26, px + 26, py + 26), outline=ACC + (255,), width=5); d.ellipse((px - 10, py - 10, px + 10, py + 10), fill=ACC + (255,))
    d.text((px - 230, py - 74), "Dimmuborgir", font=COND(48), fill=TEXT, stroke_width=4, stroke_fill=(0, 0, 0))
    rx, ry = (geo.lonlat_to_px(-21.94, 64.15, Z)[0] - x0) * 2 / 3, (geo.lonlat_to_px(-21.94, 64.15, Z)[1] - y0) * 2 / 3
    d.ellipse((rx - 8, ry - 8, rx + 8, ry + 8), fill=(255, 255, 255, 255)); d.text((rx - 40, ry + 12), "Reykjavík", font=SANS(26), fill=DIM, stroke_width=3, stroke_fill=(0, 0, 0))
    return fx.frame_photo(m, m.width, m.height, border=8, radius=16)
MAPC = ice_card()
def pcard(k, w, h, style="card", cap=None, rot=0):
    s = img(k)
    if s is None: return None
    c = fx.frame_photo(s, w, h, style=style, caption=cap, font=SANS(30))
    return c.rotate(rot, resample=Image.BICUBIC, expand=True) if rot else c

# day-by-day count of Yule Lads in town: Dec 12 → Jan 6
DAYS = [("DEC", d) for d in range(12, 32)] + [("JAN", d) for d in range(1, 7)]
COUNT = [min(i + 1, 13) if i <= 12 else 13 - (i - 12) for i in range(len(DAYS))]   # 13 on Dec 24, last leaves Jan 6
def lads_chart(im, k, a=1.0):
    d = ImageDraw.Draw(im, "RGBA"); x0, x1, yb = 80, W - 80, 1180; bw = (x1 - x0) / len(DAYS); n = k * len(DAYS)
    d.rounded_rectangle((x0 - 30, yb - 560, x1 + 30, yb + 80), 26, fill=(8, 12, 18, int(200 * a)))
    d.text((x0, yb - 530), "YULE LADS IN TOWN", font=MONO(28), fill=(255, 255, 255, int(220 * a)))
    for i, c in enumerate(COUNT):
        if i >= n: break
        kk = min(1, n - i); hh = c * 30 * kk; col = GREEN if i <= 12 else ACC
        d.rounded_rectangle((x0 + i * bw + 3, yb - hh, x0 + (i + 1) * bw - 3, yb), 5, fill=col + (int(255 * a),))
    for i, lab in ((0, "DEC 12"), (12, "DEC 24"), (25, "JAN 6")):
        x = x0 + (i + 0.5) * bw; tw = d.textlength(lab, font=MONO(24)); d.text((min(max(x - tw / 2, x0 - 20), x1 + 20 - tw), yb + 22), lab, font=MONO(24), fill=(255, 255, 255, int(200 * a)))
    cur = COUNT[min(len(COUNT) - 1, max(0, int(n) - 1))]
    d.text((x1 - 140, yb - 540), f"{cur:>2}", font=COND(110), fill=(GREEN if n <= 13 else ACC) + (int(255 * a),))
def calendar(im, t, t0, a=1.0):
    d = ImageDraw.Draw(im, "RGBA"); tw, th, gx = 168, 150, 18; cols = 5
    for i in range(13):
        ti = t0 + i * 0.16
        if t < ti: break
        k = fx.back((t - ti) / 0.3); r, c = divmod(i, cols); x = (W - (cols * tw + (cols - 1) * gx)) / 2 + c * (tw + gx); y = 520 + r * (th + gx)
        if r == 2: x += (tw + gx)
        s = 0.6 + 0.4 * k; cx, cy = x + tw / 2, y + th / 2; ww, hh = tw * s / 2, th * s / 2
        d.rounded_rectangle((cx - ww, cy - hh, cx + ww, cy + hh), 18, fill=(250, 248, 242, int(245 * a)))
        d.rounded_rectangle((cx - ww, cy - hh, cx + ww, cy - hh + 36 * s), 18, fill=(200, 40, 40, int(255 * a)))
        f = MONO(int(22 * s)); d.text((cx - d.textlength("DEC", font=f) / 2, cy - hh + 6 * s), "DEC", font=f, fill=(255, 255, 255, int(255 * a)))
        f = COND(int(84 * s)); txt = str(12 + i); d.text((cx - d.textlength(txt, font=f) / 2, cy - hh + 34 * s), txt, font=f, fill=(20, 22, 26, int(255 * a)))

def frame(fi):
    t = fi / FPS; shake = 0
    # ——— 1 · hook: Reykjavík Christmas lights, "13 TROLLS", glowing cat eyes, EATS PEOPLE ———
    if t < st("lads"):
        lt = t - st("hook"); src = img("dec2014")
        im = kenburns(src, lt, 5, 1.05, 1.2, fx_=0.45, dark=0.5) if src else solid()
        credit(im, "Reykjavík in December · " + CRED.get("dec2014", ""))
        tt = wt("hook", "13")
        if t < tt:
            d = ImageDraw.Draw(im, "RGBA"); a = 1 - fx.ease_in((t - tt + 0.25) / 0.25)
            for j, (tx, sz, col) in enumerate((("ICELAND'S CHRISTMAS", 104, TEXT), ("IS TERRIFYING", 150, ACC))):
                f = COND(sz); d.text(((W - d.textlength(tx, font=f)) / 2, 300 + j * 120), tx, font=f, fill=col + (int(255 * a),), stroke_width=8, stroke_fill=(0, 0, 0, int(255 * a)))
        big_text(im, "13", 300, t, tt, 330, ACC, t1=wt("hook", "cat") - 0.1)
        if t > tt + 0.15 and t < wt("hook", "cat") - 0.1:
            d = ImageDraw.Draw(im); f = COND(110); d.text(((W - d.textlength("TROLLS", font=f)) / 2, 660), "TROLLS", font=f, fill=TEXT, stroke_width=8, stroke_fill=(0, 0, 0))
        tc = wt("hook", "cat")
        if t > tc - 0.3:
            im.alpha_composite(Image.new("RGBA", (W, H), (4, 6, 10, int(170 * fx.ease_out((t - tc + 0.3) / 0.4)))))
            k = fx.ease_out((t - tc) / 0.25); E = cat_eyes(open_=max(0.05, k))
            im.alpha_composite(E, ((W - E.width) // 2, 330))
        shake = stamp_in(im, STAMP_EAT, W / 2, 1000, t, wt("hook", "eats"))
    # ——— 2 · lads: real Yule Lads (Akureyri) + calendar Dec 12–24 ———
    elif t < st("names"):
        lt = t - st("lads"); im = blurbg("lads", 0.42)
        tf = wt("lads", "From")
        c = pcard("lads", 820, 610, "polaroid", "Yule Lads in Akureyri", -3)
        if c: fx.place(im, c, W / 2, 760, t, st("lads") - 0.05, tf + 0.1, "drop", "up", 0.45, 0.3, rot_in=-15); credit(im, CRED.get("lads", ""))
        d = ImageDraw.Draw(im); f = COND(96); tx = "JÓLASVEINAR"; d.text(((W - d.textlength(tx, font=f)) / 2, 240), tx, font=f, fill=TEXT, stroke_width=6, stroke_fill=(0, 0, 0))
        d.text(((W - d.textlength("THE YULE LADS", font=MONO(32))) / 2, 360), "THE YULE LADS", font=MONO(32), fill=GREEN)
        if t > tf: calendar(im, t, tf + 0.1)
        chip_anim(im, "One new arrival per night", 140, 1130, t, wt("lads", "new"), st("names"), GREEN)
    # ——— 3 · names: drawn character cards pop one by one on each name ———
    elif t < st("last"):
        lt = t - st("names"); im = solid((10, 14, 22)); snow(im, t, 0.6)
        d = ImageDraw.Draw(im); f = COND(80); tx = "EACH HAS A SPECIALITY"; d.text(((W - d.textlength(tx, font=f)) / 2, 240), tx, font=f, fill=TEXT)
        POS = [(190, 560), (540, 560), (890, 560), (365, 980), (715, 980)]
        for i, w_ in enumerate(("Spoon", "Door", "Skyr", "Sausage", "Window")):
            t0 = wt("names", w_) - 0.1
            fx.place(im, CARDS[i], *POS[i], t, t0, st("last") + 0.25, "pop" if i % 2 else "spin", "fade", 0.4, 0.25)
    # ——— 4 · last: Candle Beggar on Dec 24 → chart of lads in town until Jan 6 ———
    elif t < st("shoe"):
        lt = t - st("last"); src = img("hallgrims")
        im = kenburns(src, lt, 6.6, 1.05, 1.15, dark=0.42) if src else solid()
        credit(im, "Hallgrímskirkja at Christmas · " + CRED.get("hallgrims", ""))
        tl = wt("last", "Then")
        fx.place(im, CANDLE_BIG, W / 2, 720, t, st("last") - 0.05, tl + 0.2, "drop", "shrink", 0.45, 0.3, rot_in=10)
        if lt < tl - st("last") + 0.2: big_text(im, "CHRISTMAS EVE", 250, t, wt("last", "Christmas"), 110, GOLD)
        if t > tl - 0.1:
            a = fx.ease_out((t - tl + 0.1) / 0.3); lads_chart(im, np.clip((t - tl) / (en("last") - tl - 0.3), 0, 1), a)
            if t > wt("last", "January"): big_text(im, "JAN 6", 260, t, wt("last", "January"), 150, ACC)
    # ——— 5 · shoe: window, shoe, gift vs rotten potato ———
    elif t < st("mom"):
        lt = t - st("shoe"); src = img("odinstorg")
        im = blurbg("odinstorg", 0.4) if src else solid()
        fx.place(im, WIN, W / 2, 760, t, st("shoe") - 0.05, st("mom") + 0.25, "up", "down", 0.45, 0.3)
        ts = wt("shoe", "shoe")
        fx.place(im, SHOE, W / 2 + 60, 1060, t, ts - 0.05, st("mom") + 0.25, "drop", "down", 0.4, 0.3)
        tg, tb = wt("shoe", "gift"), wt("shoe", "Bad")
        fx.place(im, GIFT, W / 2 - 5, 985, t, tg - 0.2, tb, "drop", "up", 0.4, 0.25)
        fx.place(im, POTATO, W / 2 - 5, 975, t, wt("shoe", "rotten") - 0.15, st("mom") + 0.25, "drop", "down", 0.35, 0.3)
        chip_anim(im, "Good kids: a small gift", 70, 260, t, tg - 0.2, tb, GREEN)
        shake = stamp_in(im, STAMP_POT, W / 2, 470, t, wt("shoe", "potato"))
        if src: credit(im, "Reykjavík, December · " + CRED.get("odinstorg", ""))
    # ——— 6 · mom: Grýla rises over the lava field, the stew pot ———
    elif t < st("dad"):
        lt = t - st("mom"); src = img("dimm")
        im = kenburns(src, lt, 9.5, 1.05, 1.2, dark=0.32) if src else solid()
        im.alpha_composite(Image.new("RGBA", (W, H), (60, 0, 10, 70)))
        tg = wt("mom", "Grýla")
        fx.place(im, GRYLA, W / 2, 760, t, tg - 0.25, en("dad") + 0.4, "up", "fade", 0.6, 0.3)
        fx.place(im, POT, W / 2 + 230, 1150, t, wt("mom", "cooks") - 0.1, st("dad") + 0.2, "up", "down", 0.4, 0.25)
        if t < tg: big_text(im, "THE NICE PART", 560, t, st("mom") + 0.1, 120, TEXT)
        chip_anim(im, "Grýla · the ogress mother", 70, 250, t, tg, st("dad"), ACC)
        shake = stamp_in(im, STAMP_STEW, W / 2 - 140, 1180, t, wt("mom", "stew"))
        if src: credit(im, "Dimmuborgir · " + CRED.get("dimm", ""))
    # ——— 7 · dad: Leppalúði on the couch ———
    elif t < st("cave"):
        lt = t - st("dad"); src = img("dimm")
        im = kenburns(src, lt + en("mom") - st("mom") + 0.4, 9.5, 1.05, 1.2, dark=0.32) if src else solid()
        im.alpha_composite(Image.new("RGBA", (W, H), (60, 0, 10, 70)))
        g = GRYLA.resize((GRYLA.width * 2 // 3, GRYLA.height * 2 // 3)); im.alpha_composite(g, (-80, 420))
        fx.place(im, LEPPA, W / 2 + 230, 900, t, st("dad") - 0.05, st("cave") + 0.25, "right", "right", 0.45, 0.3)
        chip_anim(im, "Leppalúði · the father", 70, 250, t, st("dad") + 0.2, st("cave"), BLUE)
        shake = stamp_in(im, STAMP_LAZY, W / 2 + 230, 600, t, wt("dad", "lazy"), st("cave"))
        if lt > 0.3:
            d = ImageDraw.Draw(im); [d.text((W / 2 + 330 + i * 40, 640 - i * 50 - (lt * 20) % 30), "z", font=COND(60 + i * 14), fill=(255, 255, 255)) for i in range(3)]
        if src: credit(im, "Dimmuborgir · " + CRED.get("dimm", ""))
    # ——— 8 · cave: cave in Dimmuborgir + Iceland map pin + Kirkjan polaroid ———
    elif t < st("cat"):
        lt = t - st("cave"); src = img("cave")
        im = kenburns(src, lt, 4.8, 1.0, 1.15, fx_=0.45, dark=0.6) if src else solid()
        if MAPC: fx.place(im, MAPC, W / 2, 560, t, wt("cave", "Dimmuborgir") - 0.2, st("cat") + 0.2, "pop", "up", 0.4, 0.3)
        k = pcard("kirkjan", 260, 360, "polaroid", "Kirkjan", 5)
        if k: fx.place(im, k, W - 200, 1065, t, wt("cave", "lava") - 0.1, st("cat") + 0.2, "drop", "right", 0.45, 0.3, rot_in=20)
        chip_anim(im, "Near Lake Mývatn, North Iceland", 60, 1180, t, wt("cave", "near"), st("cat"), GREEN)
        if src: credit(im, "Cave, Dimmuborgir · " + CRED.get("cave", ""))
    # ——— 9 · cat: the Yule Cat rises; shirt check ———
    elif t < st("statue"):
        lt = t - st("cat"); im = solid((6, 8, 12)); snow(im, t, 0.5)
        k = fx.ease_out(lt / 1.2); y = 1100 - 520 * k
        im.alpha_composite(CAT, ((W - CAT.width) // 2, int(y)))
        blink = 1.0 if (lt % 2.2) > 0.12 else 0.1
        if lt > 0.6:
            E = cat_eyes(open_=blink * fx.ease_out((lt - 0.6) / 0.3)); im.alpha_composite(E, ((W - E.width) // 2, int(y)))
        d = ImageDraw.Draw(im); f = COND(110); tx = "JÓLAKÖTTURINN"; d.text(((W - d.textlength(tx, font=f)) / 2, 240), tx, font=f, fill=GOLD, stroke_width=7, stroke_fill=(0, 0, 0))
        tn = wt("cat", "new")
        if t > tn - 0.1:
            e = fx.env(t, tn - 0.1, st("statue") + 0.2, 0.35, 0.25); a = min(1, e[0] * 2) * (1 - e[1])
            box = Image.new("RGBA", (420, 260), (0, 0, 0, 0)); bd = ImageDraw.Draw(box); bd.rounded_rectangle((0, 0, 419, 259), 30, fill=(250, 248, 242, 245))
            box.alpha_composite(icon("shirt", 150, (30, 34, 40)), (40, 55)); bd.text((215, 70), "NEW", font=COND(70), fill=(30, 34, 40)); bd.text((215, 140), "CLOTHES?", font=COND(56), fill=(30, 34, 40))
            fx.place(im, box, W / 2, 1150, t, tn - 0.1, st("statue") + 0.2, "pop", "shrink", 0.35, 0.25)
        shake = stamp_in(im, STAMP_EAT, W / 2, 1150, t, wt("cat", "eats"))
    # ——— 10 · statue: the Yule Cat light sculpture, Reykjavík ———
    elif t < st("poem"):
        lt = t - st("statue"); src = img("yulecat")
        im = kenburns(src, lt, 5, 1.0, 1.12, fy=0.35, dark=0.85) if src else solid()
        credit(im, "Yule Cat, Lækjartorg, Reykjavík · " + CRED.get("yulecat", ""))
        big_text(im, "5 METRES", 230, t, wt("statue", "5-metre") - 0.05, 150, GOLD)
        chip_anim(im, "Lækjartorg, Reykjavík · since 2018", 70, 1170, t, st("statue") + 0.3, st("poem"), ACC)
    # ——— 11 · poem: the 1932 book, names roll in; laufabrauð card ———
    elif t < st("end"):
        lt = t - st("poem"); im = blurbg("laufa", 0.32) if img("laufa") else solid()
        snow(im, t, 0.4)
        tb = wt("poem", "fixed") - 0.2
        if t < tb: big_text(im, "13 NAMES?", 600, t, st("poem") + 0.05, 170, TEXT)
        else:
            nk = 1 + 12 * np.clip((t - tb - 0.3) / 2.6, 0, 1)
            fx.place(im, book(nk), W / 2, 760, t, tb, en("poem") + 0.6, "up", "down", 0.45, 0.3)
            big_text(im, "1932", 230, t, wt("poem", "1932") - 0.05, 160, ACC)
        chip_anim(im, "Poem 'Jólasveinarnir' in Jólin koma", 60, 1170, t, wt("poem", "Jóhannes"), en("poem") + 0.3, BLUE)
    # ——— 12 · end: laufabrauð + new shirt ———
    elif t < st("cta"):
        lt = t - st("end"); src = img("laufa")
        im = kenburns(src, lt, 3.8, 1.05, 1.18, dark=0.5) if src else solid()
        credit(im, "Laufabrauð, Icelandic Christmas bread · " + CRED.get("laufa", ""))
        fx.place(im, SHIRT, W / 2, 620, t, st("end") + 0.2, st("cta") + 0.2, "pop", "fade", 0.4, 0.25)
        big_text(im, "WEAR SOMETHING NEW", 290, t, st("end") + 0.3, 104, GOLD)
        e = fx.env(t, wt("end", "Just") - 0.1, st("cta") + 0.2)
        if e:
            E = cat_eyes(500, 420, max(0.05, fx.ease_out(e[0]) * (1 - e[1]))); im.alpha_composite(E, ((W - E.width) // 2, 820))
    else:
        lt = t - st("cta"); im = blurbg("house", 0.4); snow(im, t, 0.6)
        rk.cta(im, fx.ease_out(lt / 0.5), P, "Your guide to Iceland. Weather, roads, aurora and the stories behind every place.",
               "Photos: Wikimedia Commons (CC BY, CC BY-SA) · characters: original Norður illustrations · map: Mapzen Terrain Tiles · AI voice")
    if st("lads") <= t < st("cta") and not (st("names") <= t < st("last")) and not (st("cat") <= t < st("statue")) and not (st("poem") <= t < st("end")):
        snow(im, t, 0.45)
    chapters(im, t)
    if t < st("cta"):
        g = Image.new("L", (1, 560)); [g.putpixel((0, y), int(200 * (y / 560) ** 1.5)) for y in range(560)]
        im.paste(Image.new("RGBA", (W, 560), (4, 6, 10, 255)), (0, H - 560), g.resize((W, 560)))
        captions(im, t)
    for i in ORDER:
        dt = t - st(i)
        if 0 <= dt < 0.16 and i not in ("hook", "cta"):
            z = 1 + 0.035 * (1 - dt / 0.16); im = im.resize((round(W * z), round(H * z)), Image.BILINEAR).crop(((round(W * z) - W) // 2, (round(H * z) - H) // 2, (round(W * z) - W) // 2 + W, (round(H * z) - H) // 2 + H))
    out = im.convert("RGB")
    if shake: out = Image.fromarray(np.roll(np.roll(np.asarray(out), int(math.sin(fi * 2.7) * shake), 1), int(math.cos(fi * 3.3) * shake * 0.6), 0))
    return out
tmp = os.path.join(OUT, "jol-silent.mp4")
rk.run(frame, TOTAL, tmp, TEST)
if not TEST:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-i", os.path.join(V, "voice", "narration.wav"), "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", os.path.join(OUT, "iceland-christmas-yule-lads.mp4")])
    print("muxed")
