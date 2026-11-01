"""'This plane lost both engines over Iceland' — the 1973 US Navy C-117D on Sólheimasandur (story + safety reel, closes on Norður alerts).
Usage: python sol_reel.py <work> <fonts> <out_dir> [test frame numbers… | chunk i n | mux n | audio]
<work>/sol/: *.jpg photos, v_c47.mp4, v_storm.mp4, map.png (+ map_origin.json), voice/{narration.wav,timeline.json}
             (projects/solheimasandur/dl.py lists every file, licence and how it was fetched).
<work>/icons/ = copy of tools/social/icons. The logo is composed from site/landing/img/icon.png (found via <fonts>/../img).
New in this reel: map camera (pan/zoom over a z9 paper-cut DEM) with a flying plane and route, carburettor-icing
diagram, twin RPM gauges, frost creep, archive-photo grading, timeline rail, real app screenshot in a phone frame,
synthesized radial-engine drone that sputters and dies."""
import sys, os, json, math, subprocess, numpy as np, cv2, soundfile as sf
from PIL import Image, ImageDraw, ImageFilter, ImageOps
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reelkit as rk, reynis_fx as rx, geo
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
V = os.path.join(P, "sol"); TLL = json.load(open(os.path.join(V, "voice", "timeline.json")))
TL = {l["id"]: l for l in TLL}; ORDER = [l["id"] for l in TLL]
def st(i): return TL[i]["start"]
def en(i): return TL[i]["start"] + TL[i]["dur"]
TOTAL = en("cta") + 0.9
ACC, BLUE, AUR, TEXT, DIM, YEL, RED, ICE = (255, 90, 31), (120, 170, 255), (61, 224, 168), (246, 246, 242), (180, 186, 192), (255, 196, 40), (240, 50, 45), (190, 235, 255)
CR = {"ce": "Christoffer Engström · CC0", "aj": "Anders Jildén · CC0", "fuji": "US Navy, 1952 · Public domain", "c47j": "US Navy · Public domain",
      "stok": "Syrio · CC BY-SA 4.0", "kef62": "US Navy, 1962 · Public domain", "r1820": "Cpl. L.G. Gyorfi, USMC · Public domain",
      "jh72": "Jakub Hałun · CC BY 4.0", "v_c47": "Martin Kraft · CC BY 4.0", "bf": "Blair Fraser · CC0", "ch19": "US Navy, c.1965 · Public domain",
      "jh47": "Jakub Hałun · CC BY 4.0", "jh60": "Jakub Hałun · CC BY 4.0", "sk59": "sikeri · CC BY 2.0", "hd161": "H. de Saint-Rambert · CC BY-SA 4.0",
      "jh63": "Jakub Hałun · CC BY 4.0", "v_storm": "Jakub Hałun · CC BY-SA 4.0", "jh69": "Jakub Hałun · CC BY 4.0", "beard": "US Navy, 1961 · Public domain",
      "map": "Relief: Mapzen Terrarium DEM (AWS open data)"}
_IMG, _BIG = {}, {}
def img(k):
    if k not in _IMG: _IMG[k] = Image.open(os.path.join(V, k + ".jpg")).convert("RGB")
    return _IMG[k]
def big(k, s=1.3):
    if (k, s) not in _BIG: _BIG[(k, s)] = rx.cover(img(k), s)
    return _BIG[(k, s)]
def photo(k, lt, dur, zoom=(1.0, 1.12), pan=(0.0, 0.0), depth=60, fx=0.5, fy=0.5): return rx.parallax(big(k), lt, dur, zoom, pan, depth, fx, fy)
def archive(a, fi, sepia=0.25):
    """Old-print look for the 1950s–70s Navy photos: lifted blacks, warm tint, flicker."""
    g = a.mean(2, keepdims=True); a = a * (1 - sepia) + g * sepia * np.array([1.08, 1.0, 0.86])
    return a * (0.92 + 0.04 * math.sin(fi * 2.3)) + 10
def fullbleed(k, lt, dur, zoom=(1.0, 1.1), fit_w=1.0, yc=0.5):
    """Low-res landscape archive photo: sharp copy fit to width over a blurred, dark cover copy of itself."""
    if ("fb", k) not in _BIG:
        bg = cv2.GaussianBlur(rx.cover(img(k), 1.0), (0, 0), 30) * 0.35
        _BIG[("fb", k)] = bg
    bg = _BIG[("fb", k)][:H, :W].copy(); z = zoom[0] + (zoom[1] - zoom[0]) * rx.ease(lt / dur)
    im = img(k); w = int(W * fit_w * z); h = int(im.height * w / im.width)
    fg = np.asarray(im.resize((w, h), Image.LANCZOS), np.float32); x0 = (W - w) // 2; y0 = int(H * yc - h / 2)
    xa, ya = max(0, x0), max(0, y0); xb, yb = min(W, x0 + w), min(H, y0 + h)
    bg[ya:yb, xa:xb] = fg[ya - y0:yb - y0, xa - x0:xb - x0]
    return bg

# ——— footage ———
_CL = {}
def clip(key, ts, start, dur, xshift=0.0):
    if (key, start) not in _CL:
        cap = cv2.VideoCapture(os.path.join(V, key + ".mp4")); fps = cap.get(cv2.CAP_PROP_FPS) or 25; cap.set(cv2.CAP_PROP_POS_MSEC, start * 1000); fr = []
        for _ in range(int(dur * fps) + 1):
            ok, f = cap.read()
            if not ok: break
            h, w = f.shape[:2]; cw = int(h * W / H); x0 = int(min(w - cw, max(0, (w - cw) / 2 + xshift * w)))
            fr.append(cv2.cvtColor(f[:, x0:x0 + cw], cv2.COLOR_BGR2RGB))
        _CL[(key, start)] = (fr, fps)
    fr, fps = _CL[(key, start)]; i = min(len(fr) - 1, max(0, int(ts * fps)))
    return cv2.resize(fr[i], (W, H), interpolation=cv2.INTER_CUBIC).astype(np.float32)

# ——— words / captions / chapters ———
WORDS = []
for i in ORDER:
    if i == "cta": continue
    l = TL[i]; ws = l["show"].split(); tot = sum(len(w) + 2 for w in ws); t0 = l["start"]
    for j, w in enumerate(ws):
        dd = l["dur"] * (len(w) + 2) / tot; WORDS.append((t0, t0 + dd, w, l["start"], l["start"] + l["dur"], i, j)); t0 += dd
def wt(line, word, nth=0):
    for w in WORDS:
        if w[5] == line and w[2].strip(".,?!:…").lower().startswith(word.lower()):
            if nth == 0: return w[0]
            nth -= 1
    raise KeyError((line, word))
def captions(im, t):
    cur = [w for w in WORDS if w[3] <= t < w[4] + 0.12]
    if not cur: return
    line = [w for w in WORDS if w[3] == cur[0][3]]
    k = next((i for i, w in enumerate(line) if w[0] <= t < w[1]), len(line) - 1)
    c0 = (k // 3) * 3; chunk = line[c0:c0 + 3]
    d = ImageDraw.Draw(im, "RGBA"); f = COND(98); txt = " ".join(w[2] for w in chunk)
    while d.textlength(txt, font=f) > W - 90: f = COND(f.size - 6)
    x = (W - d.textlength(txt, font=f)) / 2; y = 1400; pop = rx.eout((t - line[k][0]) / 0.12)
    for j, w in enumerate(chunk):
        on = c0 + j == k; s = f if not on else COND(int(f.size * (1.12 - 0.12 * pop)))
        d.text((x, y - (10 if on else 0) * pop + (f.size - s.size) * 0.5), w[2], font=s, fill=ACC if on else (255, 255, 255), stroke_width=7, stroke_fill=(6, 8, 10))
        x += d.textlength(w[2], font=s) + d.textlength(" ", font=f)
CH = [("THE FLIGHT", "mission", "choice"), ("THE CHOICE", "choice", "saved"), ("THE WRECK", "saved", "storm"), ("THE DANGER", "storm", "app")]
def chapters(im, t):
    if not (st("mission") - 0.2 <= t < st("app")): return
    d = ImageDraw.Draw(im, "RGBA"); x0, y0, gap = 50, 120, 12; ws = [1.1, 1, 1.1, 1.1]; tw = (W - 100 - gap * 3) / sum(ws); x = x0
    for (name, a, b), wk in zip(CH, ws):
        w = tw * wk; on = st(a) <= t < st(b); k = 1.0 if t >= st(b) else (np.clip((t - st(a)) / (st(b) - st(a)), 0, 1) if on else 0)
        d.rounded_rectangle((x, y0, x + w, y0 + 8), 4, fill=(255, 255, 255, 60))
        if k > 0.01: d.rounded_rectangle((x, y0, x + w * k, y0 + 8), 4, fill=ACC + (255,))
        d.text((x, y0 + 16), name, font=MONO(19), fill=(255, 255, 255, 235 if on else 105)); x += w + gap
def credit(im, text, y=1328):
    if not text: return
    d = ImageDraw.Draw(im, "RGBA"); f = MONO(18); tw = d.textlength(text, font=f)
    while tw > W - 100: f = MONO(f.size - 1); tw = d.textlength(text, font=f)
    d.rounded_rectangle((W - 40 - tw - 20, y, W - 40, y + 32), 8, fill=(0, 0, 0, 150)); d.text((W - 40 - tw - 10, y + 6), text, font=f, fill=(225, 225, 225))
def note(im, text, y=1290):
    d = ImageDraw.Draw(im, "RGBA"); d.text((40, y), text, font=MONO(18), fill=(255, 255, 255, 130))

# ——— drawing helpers ———
def icon(name, size, col=(255, 255, 255)):
    a = Image.open(os.path.join(P, "icons", name + ".png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", a.size, col + (255,)); out.putalpha(a.getchannel("A")); return out
def alpha(L, a):
    if a >= 0.999: return L
    L = L.copy(); L.putalpha(L.getchannel("A").point(lambda v: int(v * a))); return L
def back_(x, s=1.7): x = max(0.0, min(1.0, x)) - 1; return x * x * ((s + 1) * x + s) + 1
def put(im, L, cx, cy, t, t0, t1=None, enter="pop", tin=0.35, tout=0.25, exit="fade", rot=0):
    """Place layer centred at cx,cy. enter: pop/slam/left/right/up/drop/spin/zoom; exit: fade/left/right/down/shrink."""
    if t < t0 or (t1 is not None and t > t1): return None
    pi = min(1, (t - t0) / tin); po = 0 if t1 is None else max(0, min(1, (t - (t1 - tout)) / tout))
    s, dx, dy, r = 1, 0, 0, 0
    if enter == "pop": s = 0.55 + 0.45 * back_(pi)
    elif enter == "slam": s = 1 + 1.2 * (1 - rx.eout(pi))
    elif enter == "left": dx = -W * (1 - rx.eout(pi))
    elif enter == "right": dx = W * (1 - rx.eout(pi))
    elif enter == "up": dy = 500 * (1 - rx.eout(pi))
    elif enter == "drop": dy = -H * 0.6 * (1 - back_(pi, 1.2)); r = rot * (1 - rx.eout(pi))
    elif enter == "spin": s = 0.3 + 0.7 * back_(pi); r = -25 * (1 - rx.eout(pi))
    elif enter == "zoom": s = 1.25 - 0.25 * rx.eout(pi)
    a = min(1, pi * 2.5)
    if po > 0:
        if exit == "fade": a *= 1 - rx.ein(po)
        elif exit == "left": dx -= W * rx.ein(po)
        elif exit == "right": dx += W * rx.ein(po)
        elif exit == "down": dy += H * 0.6 * rx.ein(po)
        elif exit == "shrink": s *= 1 - 0.9 * rx.ein(po); a *= 1 - rx.ein(po)
    if a <= 0.01 or s <= 0.02: return pi
    L2 = L.rotate(r, resample=Image.BICUBIC, expand=True) if abs(r) > 0.1 else L
    if abs(s - 1) > 0.01: L2 = L2.resize((max(1, int(L2.width * s)), max(1, int(L2.height * s))), Image.BILINEAR)
    im.alpha_composite(alpha(L2, a), (int(cx + dx - L2.width / 2), int(cy + dy - L2.height / 2)))
    return pi
def text_layer(txt, size, col=TEXT, stroke=10, font=None):
    f = (font or COND)(size); d = ImageDraw.Draw(Image.new("RGBA", (4, 4))); bb = d.textbbox((0, 0), txt, font=f, stroke_width=stroke)
    L = Image.new("RGBA", (bb[2] - bb[0] + 40, bb[3] - bb[1] + 40), (0, 0, 0, 0)); dl = ImageDraw.Draw(L)
    sh = Image.new("RGBA", L.size, (0, 0, 0, 0)); ImageDraw.Draw(sh).text((20 - bb[0], 26 - bb[1]), txt, font=f, fill=(0, 0, 0, 200), stroke_width=stroke, stroke_fill=(0, 0, 0, 200))
    L.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
    dl.text((20 - bb[0], 20 - bb[1]), txt, font=f, fill=col, stroke_width=stroke, stroke_fill=(8, 8, 10))
    return L
_TL = {}
def T(txt, size, col=TEXT, stroke=10):
    k = (txt, size, col, stroke)
    if k not in _TL: _TL[k] = text_layer(txt, size, col, stroke)
    return _TL[k]
def card(title, sub, ic, col, w=880, h=150, sub_col=DIM):
    L = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0)); sh = Image.new("RGBA", L.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((20, 28, w + 20, h + 28), 34, fill=(0, 0, 0, 170)); L.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(L); d.rounded_rectangle((20, 20, w + 20, h + 20), 34, fill=(17, 22, 28, 238), outline=(255, 255, 255, 38), width=2)
    d.rounded_rectangle((44, 20 + (h - 100) // 2, 144, 120 + (h - 100) // 2), 26, fill=col + (255,))
    L.alpha_composite(icon(ic, 64, (10, 12, 14)), (62, 38 + (h - 100) // 2))
    d.text((172, 20 + h * 0.18), title, font=SANS(40), fill=TEXT); d.text((172, 20 + h * 0.56), sub, font=SANS(30), fill=sub_col)
    return L
_CHIP = {}
def chip(txt, col=ACC, ic=None, size=34):
    k = (txt, col, ic, size)
    if k in _CHIP: return _CHIP[k]
    d = ImageDraw.Draw(Image.new("RGBA", (4, 4))); f = SANS(size); tw = d.textlength(txt, font=f); h = int(size * 2); w = int(tw + h * (1.5 if ic else 0.9))
    L = Image.new("RGBA", (w + 30, h + 30), (0, 0, 0, 0)); sh = Image.new("RGBA", L.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((15, 21, w + 15, h + 21), h // 2, fill=(0, 0, 0, 140)); L.alpha_composite(sh.filter(ImageFilter.GaussianBlur(8)))
    d = ImageDraw.Draw(L); d.rounded_rectangle((15, 15, w + 15, h + 15), h // 2, fill=(255, 255, 255, 250))
    if ic: L.alpha_composite(icon(ic, int(size * 1.15), col), (15 + h // 3, 15 + (h - int(size * 1.15)) // 2)); x = 15 + h // 3 + int(size * 1.5)
    else: d.ellipse((30, 15 + h / 2 - 9, 48, 15 + h / 2 + 9), fill=col + (255,)); x = 60
    d.text((x, 15 + h * 0.22), txt, font=f, fill=(12, 14, 18)); _CHIP[k] = L; return L
_ST = {}
def stamp(txt, col=RED, size=84, rot=-10):
    k = (txt, col, size, rot)
    if k in _ST: return _ST[k]
    d = ImageDraw.Draw(Image.new("RGBA", (4, 4))); f = COND(size); tw = d.textlength(txt, font=f)
    L = Image.new("RGBA", (int(tw + 80), int(size * 1.5)), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((6, 6, L.width - 6, L.height - 6), 14, outline=col + (255,), width=9, fill=(0, 0, 0, 110)); d.text((40, size * 0.12), txt, font=f, fill=col + (255,))
    _ST[k] = L.rotate(rot, resample=Image.BICUBIC, expand=True); return _ST[k]
_POL = {}
def polaroid(k, w, h, cap, rot=0, crop=(0.5, 0.5)):
    """Polaroid card with a handwritten-style caption line and the credit under it."""
    key = (k, w, h, cap, rot)
    if key in _POL: return _POL[key]
    im = ImageOps.fit(img(k), (w, h), Image.LANCZOS, centering=crop); b = 16
    c = Image.new("RGBA", (w + 2 * b, h + b + 96), (244, 242, 236, 255)); c.paste(im, (b, b)); d = ImageDraw.Draw(c)
    d.text((b + 4, h + b + 12), cap, font=SANS(30), fill=(28, 28, 30)); d.text((b + 4, h + b + 56), CR[k], font=MONO(17), fill=(110, 110, 112))
    sh = Image.new("RGBA", (c.width + 80, c.height + 80), (0, 0, 0, 0)); ImageDraw.Draw(sh).rectangle((40, 54, c.width + 40, c.height + 54), fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(16)); sh.alpha_composite(c, (40, 40))
    _POL[key] = sh.rotate(rot, resample=Image.BICUBIC, expand=True) if rot else sh; return _POL[key]
def to_pil(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")
SHAKE = []
def kick(t, t0, amt=16, d=0.35):
    if t0 <= t < t0 + d: SHAKE.append(amt * (1 - (t - t0) / d))

# ——— map camera ———
MAP = np.asarray(Image.open(os.path.join(V, "map.png")).convert("RGB"), np.float32)
MO = json.load(open(os.path.join(V, "map_origin.json")))           # {"z": 9, "x0": .., "y0": ..}
SEAC = np.array([6, 10, 16], np.float32)
def mp(lon, lat):
    x, y = geo.lonlat_to_px(lon, lat, MO["z"]); return x - MO["x0"], y - MO["y0"]
PT = {"hofn": (-15.2272, 64.2956), "stok": (-14.975, 64.245), "kef": (-22.605, 63.985), "wreck": (-19.3647, 63.4591),
      "glacier": (-19.10, 63.66), "fail": (-18.55, 64.02)}
def cam(cx, cy, z):
    """Map view centred on map px (cx, cy) at z screen px per map px. Returns float32 frame + projector."""
    M = np.float32([[z, 0, W / 2 - cx * z], [0, z, H / 2 - cy * z]])
    a = cv2.warpAffine(MAP, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=tuple(float(v) for v in SEAC))
    top = H / 2 - cy * z; bot = top + MAP.shape[0] * z                  # fade the cut map edges into the background
    ys = np.arange(H, dtype=np.float32)[:, None]
    m = np.clip((ys - top) / 160, 0, 1) * np.clip((bot - ys) / 160, 0, 1)
    a = a * m[..., None] + np.array(rx.BG, np.float32) * (1 - m[..., None])
    return a, (lambda X, Y: (W / 2 + (X - cx) * z, H / 2 + (Y - cy) * z))
def plane_icon(size=120, col=(250, 250, 250), dead=False):
    """Top view of a twin-engine prop plane pointing up (north)."""
    s = size / 120; L = Image.new("RGBA", (size, size), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    def P(pts): return [(x * s, y * s) for x, y in pts]
    d.polygon(P([(56, 8), (64, 8), (67, 30), (66, 100), (60, 112), (54, 100), (53, 30)]), fill=col + (255,))
    d.polygon(P([(4, 52), (116, 52), (116, 62), (66, 66), (54, 66), (4, 62)]), fill=col + (255,))
    d.polygon(P([(34, 100), (86, 100), (86, 106), (34, 106)]), fill=col + (255,))
    for ex in (34, 86):
        d.rounded_rectangle(P([(ex - 5, 40), (ex + 5, 66)]), int(3 * s), fill=(RED if dead else ACC) + (255,))
    return L
def heading(p0, p1): return math.degrees(math.atan2(p1[0] - p0[0], -(p1[1] - p0[1])))
def path_pts(pts, k):
    """Point & heading at fraction k along a polyline (map px)."""
    seg = [math.dist(a, b) for a, b in zip(pts, pts[1:])]; L = sum(seg); d = k * L
    for (a, b), s in zip(zip(pts, pts[1:]), seg):
        if d <= s or s == seg[-1] and (a, b) == (pts[-2], pts[-1]):
            f = 0 if s == 0 else min(1, d / s); return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f), heading(a, b)
        d -= s
    return pts[-1], heading(pts[-2], pts[-1])
def dashed(d, pts, col, width=6, dash=22, gap=16, upto=1.0):
    seg = [math.dist(a, b) for a, b in zip(pts, pts[1:])]; L = sum(seg) * upto; acc = 0
    for (a, b), s in zip(zip(pts, pts[1:]), seg):
        x = 0
        while x < s and acc + x < L:
            x1 = min(s, x + dash, L - acc); f0, f1 = x / s, x1 / s
            d.line((a[0] + (b[0] - a[0]) * f0, a[1] + (b[1] - a[1]) * f0, a[0] + (b[0] - a[0]) * f1, a[1] + (b[1] - a[1]) * f1), fill=col, width=width)
            x += dash + gap
        acc += s
def pin(d, x, y, col, r=16):
    d.ellipse((x - r * 2.2, y - r * 2.2, x + r * 2.2, y + r * 2.2), fill=col + (60,)); d.ellipse((x - r, y - r, x + r, y + r), fill=col + (255,), outline=(10, 10, 12, 255), width=4)
def label(im, txt, x, y, col=TEXT, size=46, anchor="l"):
    L = T(txt, size, col, 6); im.alpha_composite(L, (int(x - (L.width if anchor == "r" else L.width / 2 if anchor == "m" else 0)), int(y - L.height / 2)))

# ——— scenes ———
def s_hook(t):
    lt = t - st("hook"); ts = wt("hook", "50") - 0.12
    if t < ts:
        a = photo("ce", lt, ts, (1.22, 1.05), (0.0, 0.0), 40, 0.5, 0.55); a = a * np.array([0.88, 0.94, 1.04]) * 0.8
        te = wt("hook", "engines")
        if t > te: a = rx.shake(a, int(t * 30), 10 * max(0, 1 - (t - te) * 2.5))
        im = to_pil(a)
        put(im, T("LOST BOTH", 150), W / 2, 380, t, 0, None, "up"); put(im, T("ENGINES", 210, ACC), W / 2, 560, t, te - 0.05, None, "slam", 0.2); kick(t, te + 0.1, 18)
        tsv = wt("hook", "survived") - 0.1
        put(im, stamp("ALL 7 SURVIVED", AUR, 110, -8), W / 2, 1000, t, tsv, None, "slam", 0.2); kick(t, tsv + 0.12, 14)
        credit(im, "Sólheimasandur · " + CR["ce"]); return im
    l2 = t - ts; a = photo("aj", l2, en("hook") - ts + 0.5, (1.0, 1.12), (0.02, 0), 60, 0.5, 0.6) * 0.9; im = to_pil(a)
    put(im, T("50 YEARS ON", 150), W / 2, 420, t, ts, None, "up"); put(im, T("STILL HERE", 200, ACC), W / 2, 600, t, wt("hook", "still") - 0.05, None, "slam", 0.2)
    put(im, chip("Sólheimasandur · South Iceland", ACC, "map-pin", 32), W / 2, 1150, t, wt("hook", "here") - 0.2, None, "up")
    credit(im, "Sólheimasandur · " + CR["aj"]); return im
ROUTE = [mp(*PT["hofn"]), mp(*PT["fail"]), mp(*PT["kef"])]
def s_mission(t):
    lt = t - st("mission"); tm = wt("mission", "flies") - 0.15
    if t < tm:                                                            # archive: the Navy's Super DC-3 (R4D-8 = C-117D)
        a = archive(fullbleed("fuji", lt, tm - st("mission"), (1.0, 1.12), 1.25, 0.47), int(t * 30)); im = to_pil(a * 0.9)
        put(im, T("21 NOV 1973", 170, TEXT), W / 2, 300, t, st("mission") - 0.05, None, "slam", 0.2); kick(t, st("mission") + 0.1, 12)
        put(im, chip("US Navy · Douglas C-117D · BuNo 17171", BLUE, "plane-arrival", 30), W / 2, 1040, t, wt("mission", "Navy") - 0.1, None, "left")
        put(im, chip("a \"Super DC-3\"", ACC, None, 30), W / 2, 1150, t, wt("mission", "Super") - 0.1, None, "right")
        note(im, "SAME TYPE (R4D-8), 1952 · NOT THE CRASH AIRCRAFT"); credit(im, "R4D-8 over Mt Fuji · " + CR["fuji"]); return im
    l2 = t - tm; dur = en("mission") - tm + 0.25
    hx, hy = mp(*PT["hofn"]); kx, ky = mp(*PT["kef"]); cx = hx + (kx - hx) * 0.5; cy = (hy + ky) / 2 + 30
    z = 0.355 + 0.02 * rx.ease(l2 / dur); a, pr = cam(cx, cy, z); im = to_pil(a); d = ImageDraw.Draw(im, "RGBA")
    P = [pr(*p) for p in ROUTE]; dashed(d, P, (255, 255, 255, 170), 5, 18, 14)
    for key, col in (("hofn", ACC), ("kef", BLUE)): pin(d, *pr(*mp(*PT[key])), col, 13)
    label(im, "HÖFN", P[0][0] - 10, P[0][1] - 70, TEXT, 56, "r"); label(im, "KEFLAVÍK", P[-1][0] + 10, P[-1][1] + 72, TEXT, 56, "l")
    k = rx.ease(l2 / dur) * 0.62                                       # fly the first part of the route (Höfn → the failure point)
    (px, py), hd = path_pts(ROUTE, k); sx, sy = pr(px, py); pl = plane_icon(110).rotate(-hd, resample=Image.BICUBIC, expand=True)
    im.alpha_composite(pl, (int(sx - pl.width / 2), int(sy - pl.height / 2)))
    put(im, polaroid("stok", 330, 230, "Radar station, Stokksnes", 6), 790, 470, t, tm + 0.1, en("mission") + 0.2, "drop", 0.45, 0.25, "shrink", 14)
    put(im, chip("Supplied the radar station at Stokksnes", ACC, "map-pin", 28), W / 2, 1240, t, tm + 0.35, None, "up")
    put(im, polaroid("kef62", 330, 210, "NAS Keflavík, 1962", -5), 290, 470, t, wt("mission", "Keflavík") - 0.15, None, "left", 0.4, rot=-10)
    note(im, "ROUTE ILLUSTRATIVE"); credit(im, CR["map"]); return im
def venturi(k_ice, t, flow):
    """Carburettor throat cross-section: air (blue) through a venturi; ice (white) grows on the walls and chokes it."""
    w, h = 760, 640; L = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((0, 0, w - 1, h - 1), 40, fill=(12, 16, 22, 235), outline=(255, 255, 255, 40), width=2)
    cx = w / 2; ys = np.linspace(70, h - 60, 60)
    def half(y): u = (y - 70) / (h - 130); return 200 - 120 * math.exp(-((u - 0.5) / 0.22) ** 2)   # wall half-width
    for side in (-1, 1):
        wall = [(cx + side * half(y), y) for y in ys]
        d.polygon(wall + [(cx + side * 330, ys[-1]), (cx + side * 330, ys[0])], fill=(70, 78, 88, 255))
        if k_ice > 0:                                                     # ice: thickest at the throat, jagged edge
            ice = [(cx + side * (half(y) - k_ice * (60 + 70 * math.exp(-(((y - 70) / (h - 130) - 0.5) / 0.25) ** 2)) * (0.85 + 0.15 * math.sin(y * 0.31 + side))), y) for y in ys]
            d.polygon(ice + wall[::-1], fill=ICE + (255,)); d.line(ice, fill=(255, 255, 255, 255), width=3)
    gap = lambda y: half(y) - k_ice * (60 + 70 * math.exp(-(((y - 70) / (h - 130) - 0.5) / 0.25) ** 2))
    rng = np.random.default_rng(3); n = 46
    for i in range(n):                                                    # air particles slow down as the throat closes
        ph = (rng.random() + t * 0.9 * flow) % 1; y = 70 + ph * (h - 130); g = max(4, gap(y) - 14); x = cx + (rng.random() * 2 - 1) * g
        if flow > 0.05: d.line((x, y - 18 * flow, x, y), fill=BLUE + (int(220 * min(1, flow * 1.5)),), width=5)
    d.polygon([(cx - 26, h - 50), (cx + 26, h - 50), (cx, h - 22)], fill=(255, 255, 255, 120))
    d.text((24, 18), "CARBURETOR", font=MONO(26), fill=(255, 255, 255, 200)); d.text((w - 24, 18), "AIR ↓", font=MONO(26), fill=BLUE + (255,), anchor="ra")
    if k_ice > 0.15: d.text((cx + 210, h / 2), "ICE", font=COND(64), fill=ICE + (255,), anchor="mm"); d.text((cx - 210, h / 2), "ICE", font=COND(64), fill=ICE + (255,), anchor="mm")
    return L
def gauge(rpm, name, dead):
    s = 300; L = Image.new("RGBA", (s, s + 60), (0, 0, 0, 0)); d = ImageDraw.Draw(L); c = s / 2
    d.ellipse((6, 6, s - 6, s - 6), fill=(14, 18, 24, 240), outline=(RED if dead else (255, 255, 255)) + (200,), width=6)
    for i in range(11):
        a = math.radians(225 - i * 27); r0, r1 = c - 26, c - 10
        d.line((c + r0 * math.cos(a), c - r0 * math.sin(a), c + r1 * math.cos(a), c - r1 * math.sin(a)), fill=(220, 220, 220, 255), width=4 if i % 5 == 0 else 2)
    d.arc((22, 22, s - 22, s - 22), -45 - 27 * 2, -45, fill=RED + (255,), width=8)
    a = math.radians(225 - rpm / 3000 * 270); d.line((c, c, c + (c - 40) * math.cos(a), c - (c - 40) * math.sin(a)), fill=ACC + (255,), width=8)
    d.ellipse((c - 14, c - 14, c + 14, c + 14), fill=(230, 230, 230, 255))
    d.text((c, c + 62), f"{int(rpm):,}", font=MONO(34), fill=(RED if dead else TEXT) + (255,), anchor="mm"); d.text((c, c + 96), "RPM", font=MONO(18), fill=(160, 160, 160, 255), anchor="mm")
    d.text((c, s + 30), name, font=MONO(26), fill=(255, 255, 255, 220), anchor="mm"); return L
def frost(a, k, seed=7):
    """Frost creeping in from the frame edges (k 0..1)."""
    if k <= 0: return a
    if "fr" not in _BIG:
        ys, xs = np.mgrid[0:H // 4, 0:W // 4].astype(np.float32); e = np.minimum.reduce([xs, ys, W // 4 - xs, H // 4 - ys]) / (W // 8)
        n = rx.noise(W // 4, H // 4, 0, scale=2.2); cr = rx.noise(W // 4, H // 4, 3.1, scale=6.0)
        _BIG["fr"] = (cv2.resize(e, (W, H)), cv2.resize(n, (W, H)), cv2.resize(cr, (W, H)))
    e, n, cr = _BIG["fr"]; m = np.clip((k * 1.15 - e - 0.35 * n) / 0.12, 0, 1)
    tex = 170 + 85 * cr; col = np.stack([tex * 0.86, tex * 0.95, tex], 2)
    return a * (1 - 0.8 * m[..., None]) + col * 0.8 * m[..., None]
def s_ice(t):
    lt = t - st("ice"); tc = wt("ice", "chokes") - 0.1; tq = wt("ice", "quit") - 0.05; dur = en("ice") - st("ice") + 0.4
    a = archive(photo("r1820", lt, dur, (1.15, 1.3), (0.0, 0.02), 0, 0.42, 0.5), int(t * 30), 0.4) * 0.38
    a = frost(a, rx.ease((t - st("ice") + 0.2) / 2.6) * 0.75); im = to_pil(a)
    k_ice = rx.ease((t - tc + 0.3) / 1.6) * 0.9 if t > tc - 0.3 else 0
    flow = 1 - 0.95 * rx.ease((t - tc) / 1.8) if t > tc else 1.0
    put(im, T("ICE", 230, ICE), W / 2, 300, t, st("ice") - 0.05, tc + 0.05, "slam", 0.18, 0.2); kick(t, st("ice") + 0.1, 12)
    put(im, venturi(k_ice, t, flow), W / 2, 560, t, tc - 0.25, None, "pop", 0.3)
    dead = t >= tq; r1 = 2300 * (0.92 + 0.04 * math.sin(t * 13)) if t < tc else max(0, 2300 * (1 - rx.ease((t - tc) / (tq - tc + 0.35))) + 120 * math.sin(t * 19) * (t < tq))
    r2 = 2300 * (0.93 + 0.03 * math.sin(t * 11 + 1)) if t < tc + 0.4 else max(0, 2300 * (1 - rx.ease((t - tc - 0.4) / (tq - tc - 0.05))) + 150 * math.sin(t * 23) * (t < tq))
    gy = 1110
    put(im, gauge(r1, "ENGINE 1", dead and r1 < 1), 300, gy, t, st("ice") + 0.3, None, "left"); put(im, gauge(r2, "ENGINE 2", dead and r2 < 1), 780, gy, t, st("ice") + 0.45, None, "right")
    if t >= tq:
        kick(t, tq + 0.05, 22); im.alpha_composite(Image.new("RGBA", (W, H), RED + (int(70 * max(0, 1 - (t - tq) * 1.5)),)))
        put(im, stamp("BOTH ENGINES OUT", RED, 96, -6), W / 2, 560, t, tq, None, "slam", 0.18)
    note(im, "DIAGRAM · ILLUSTRATIVE"); credit(im, "C-117D engine (Wright R-1820) · " + CR["r1820"]); return im
def s_choice(t):
    lt = t - st("choice"); ts = wt("choice", "south") - 0.2; dur = en("choice") - st("choice") + 0.3
    wx, wy = mp(*PT["wreck"]); fx, fy = mp(*PT["fail"]); gx, gy = mp(*PT["glacier"])
    z = 1.26 + 0.06 * rx.ease(lt / dur); cx = (fx + wx) / 2 + 40; cy = fy + (960 - 500) / z
    a, pr = cam(cx, cy, z); im = to_pil(a); d = ImageDraw.Draw(im, "RGBA")
    if t < wt("choice", "Navy"):
        put(im, polaroid("jh72", 420, 240, "Mýrdalsjökull from the sands", -4), W / 2 + 120, 420, t, wt("choice", "glacier") - 0.25, wt("choice", "Navy") + 0.1, "right", 0.35, 0.25, "left")
    gpx = pr(gx, gy); label(im, "GLACIER", gpx[0] + 30, gpx[1] - 20, ICE, 64, "l") if t > wt("choice", "glacier") - 0.15 else None
    if t > wt("choice", "glacier") + 0.2: put(im, stamp("NO", RED, 80, 8), gpx[0] + 340, gpx[1] - 25, t, wt("choice", "glacier") + 0.2, None, "slam", 0.18)
    turn = [(fx, fy), (fx - 60, fy + 120), (wx + 40, wy - 180), (wx, wy)]
    k = 0 if t < ts else rx.ease((t - ts) / (en("choice") - ts - 0.15)) * 0.97
    P = [pr(*p) for p in turn]
    if t >= ts: dashed(d, P, ACC + (255,), 7, 20, 12, k)
    (px, py), hd = path_pts(turn, k) if t >= ts else ((fx, fy), -95 + 40 * rx.ease(lt / 1.0))
    sx, sy = pr(px, py); pl = plane_icon(130, dead=True).rotate(-hd, resample=Image.BICUBIC, expand=True)
    im.alpha_composite(pl, (int(sx - pl.width / 2), int(sy - pl.height / 2)))
    if k > 0.9: pin(d, *pr(wx, wy), AUR, 14); label(im, "SÓLHEIMASANDUR", pr(wx, wy)[0] + 50, pr(wx, wy)[1], AUR, 48, "l")
    sea = pr(wx, wy + 40); label(im, "SEA", sea[0] + 330, sea[1] + 60, BLUE, 80, "m")
    put(im, chip("Pilot: Greg Fletcher", ACC, "users", 32), W / 2, 480, t, wt("choice", "Greg") - 0.15, None, "up")
    if t > ts: put(im, T("SOUTH", 150, ACC), W / 2, 330, t, ts + 0.05, None, "slam", 0.18); kick(t, ts + 0.12, 10)
    note(im, "ROUTE ILLUSTRATIVE"); credit(im, CR["map"]); return im
def s_land(t):
    lt = t - st("land"); tb = wt("land", "All") - 0.2
    if t < tb:
        src = 0.3 + lt * 0.7; a = clip("v_c47", src, 0.0, 3.8, -0.04) * np.array([0.82, 0.9, 1.0]) * 0.85
        a = rx.shake(a, int(t * 30), 3); im = to_pil(a)
        put(im, T("COMING DOWN", 150), W / 2, 330, t, st("land") - 0.1, None, "up"); put(im, T("ON BLACK SAND", 110, ACC), W / 2, 480, t, wt("land", "black") - 0.1, None, "up")
        note(im, "A DC-3 FAMILY AIRCRAFT IN FLIGHT · ILLUSTRATIVE"); credit(im, "C-47 \"Miss Virginia\", 2018 · " + CR["v_c47"]); return im
    l2 = t - tb; a = photo("bf", l2, en("land") - tb + 0.4, (1.0, 1.1), (0.0, 0.0), 50, 0.5, 0.5) * 0.85; im = to_pil(a)
    if l2 < 0.3: im.alpha_composite(Image.new("RGBA", (W, H), (255, 255, 255, int(200 * (1 - l2 / 0.3)))))
    kick(t, tb + 0.05, 24)
    put(im, T("SÓLHEIMASANDUR", 130, TEXT), W / 2, 330, t, tb + 0.05, None, "up")
    put(im, chip("21 Nov 1973 · shortly after noon", BLUE, "clock-hour-3", 30), W / 2, 470, t, tb + 0.5, None, "left")
    ts = wt("land", "survive") - 0.1; put(im, stamp("ALL 7 SURVIVED", AUR, 120, -8), W / 2, 880, t, ts, None, "slam", 0.2); kick(t, ts + 0.12, 16)
    put(im, chip("0 injuries", AUR, "users", 40), W / 2, 1100, t, wt("land", "injury") - 0.25, None, "up")
    credit(im, "Sólheimasandur · " + CR["bf"]); return im
def s_saved(t):
    lt = t - st("saved"); tsr = wt("saved", "strips") - 0.15
    if t < tsr:
        a = archive(fullbleed("ch19", lt, tsr - st("saved"), (1.0, 1.1), 1.35, 0.48), int(t * 30), 0.3); im = to_pil(a * 0.9)
        put(im, T("RESCUED", 170, AUR), W / 2, 330, t, st("saved") - 0.05, None, "slam", 0.2); kick(t, st("saved") + 0.1, 10)
        put(im, chip("Flown out by helicopter", AUR, "users", 32), W / 2, 1130, t, wt("saved", "helicopter") - 0.1, None, "up")
        note(im, "NAVY RESCUE HELICOPTER FROM KEFLAVÍK, c.1965 · ILLUSTRATIVE"); credit(im, "CH-19E off Iceland · " + CR["ch19"]); return im
    l2 = t - tsr; a = photo("jh47", l2, en("saved") - tsr + 0.5, (1.0, 1.15), (0, 0.02), 30, 0.5, 0.45) * 0.8; im = to_pil(a)
    put(im, T("STRIPPED", 170, TEXT), W / 2, 330, t, tsr + 0.05, None, "slam", 0.2); kick(t, tsr + 0.12, 10)
    put(im, T("LEFT BEHIND", 130, ACC), W / 2, 500, t, wt("saved", "leaves") - 0.05, None, "up")
    credit(im, "Inside the wreck, 2024 · " + CR["jh47"]); return im
TLN = [(1973, "Landing"), (2015, "Bieber"), (2020, "Storm"), (2025, "Pilot returns")]
def timeline(im, t, active, y=1215):
    """Rail 1973 → 2025 with the current year highlighted."""
    d = ImageDraw.Draw(im, "RGBA"); x0, x1 = 150, W - 150; d.rounded_rectangle((60, y - 70, W - 60, y + 70), 30, fill=(10, 13, 18, 200))
    d.line((x0, y - 12, x1, y - 12), fill=(255, 255, 255, 90), width=4)
    for i, (yr, lab) in enumerate(TLN):
        x = x0 + (x1 - x0) * i / 3; on = yr == active; past = yr <= active
        r = 15 if on else 10; d.ellipse((x - r, y - 12 - r, x + r, y - 12 + r), fill=(ACC if on else (230, 230, 230) if past else (90, 90, 90)) + (255,))
        d.text((x, y + 24), str(yr), font=MONO(28 if on else 24), fill=(255, 255, 255, 255 if past else 120), anchor="mm")
        d.text((x, y - 50), lab, font=SANS(22), fill=(255, 255, 255, 230 if on else 110), anchor="mm")
def s_fame(t):
    lt = t - st("fame"); a = photo("jh60", lt, en("fame") - st("fame") + 0.4, (1.05, 1.2), (0.03, 0), 70, 0.5, 0.5) * 0.75; im = to_pil(a)
    put(im, T("AN ICON", 190, ACC), W / 2, 320, t, wt("fame", "icon") - 0.1, None, "slam", 0.2); kick(t, wt("fame", "icon"), 10)
    put(im, polaroid("sk59", 280, 380, "The cockpit", 7), 290, 720, t, st("fame") + 0.3, None, "drop", 0.45, rot=18)
    put(im, polaroid("hd161", 280, 380, "Nose on black sand", -6), 790, 760, t, st("fame") + 0.8, None, "drop", 0.45, rot=-18)
    put(im, chip("Justin Bieber · \"I'll Show You\" · 2015", ACC, "stars", 30), W / 2, 1060, t, wt("fame", "Bieber") - 0.15, None, "left")
    timeline(im, t, 2015 if t > wt("fame", "Bieber") else 1973)
    credit(im, "Visitors at the wreck, 2024 · " + CR["jh60"]); return im
def s_back(t):
    lt = t - st("back"); a = photo("jh63", lt, en("back") - st("back") + 0.4, (1.18, 1.04), (-0.03, 0), 40, 0.55, 0.5) * 0.7; im = to_pil(a)
    put(im, T("2025", 260, ACC), W / 2, 380, t, st("back") - 0.05, None, "slam", 0.2); kick(t, st("back") + 0.1, 14)
    put(im, chip("Greg Fletcher · 79 years old", AUR, "users", 34), W / 2, 640, t, wt("back", "79") - 0.15, None, "left")
    put(im, chip("First visit since 1973", ACC, "calendar", 34), W / 2, 780, t, wt("back", "first") - 0.15, None, "right")
    timeline(im, t, 2025); credit(im, "Sólheimasandur, 2024 · " + CR["jh63"]); return im
_SNOW = np.random.default_rng(4).random((260, 4)).astype(np.float32)
def snow(im, t, k=1.0, wind=900):
    d = ImageDraw.Draw(im, "RGBA")
    for x0, y0, v, s in _SNOW:
        x = (x0 * (W + 400) + wind * (0.6 + v) * t) % (W + 400) - 200; y = (y0 * H + 260 * (0.5 + v) * t) % H; r = 2 + 4 * s
        d.line((x - 26 * (0.6 + v), y - 6, x, y), fill=(255, 255, 255, int(150 * k * (0.4 + s))), width=int(r))
def s_storm(t):
    lt = t - st("storm"); a = clip("v_storm", lt * 0.85, 0.5, 8.5, 0.12)
    g = a.mean(2, keepdims=True); a = (a * 0.35 + g * 0.65) * np.array([0.62, 0.76, 1.0]) * (0.62 - 0.12 * rx.ease(lt / 6))   # cold, dark grade
    a = rx.shake(a, int(t * 30), 4); im = to_pil(a); snow(im, t)
    tk = wt("storm", "kill") - 0.1; put(im, T("THIS PLACE", 130), W / 2, 320, t, st("storm") - 0.05, None, "up")
    put(im, T("CAN KILL", 190, RED), W / 2, 480, t, tk, None, "slam", 0.2); kick(t, tk + 0.1, 16)
    put(im, chip("January 2020", BLUE, "calendar", 34), W / 2, 700, t, wt("storm", "January") - 0.15, None, "left")
    put(im, chip("2 young tourists died near the wreck", RED, "alert-triangle", 30), W / 2, 830, t, wt("storm", "tourists") - 0.15, None, "right")
    put(im, stamp("HYPOTHERMIA", ICE, 100, -6), W / 2, 1010, t, wt("storm", "hypothermia") - 0.1, None, "slam", 0.18); kick(t, wt("storm", "hypothermia"), 12)
    timeline(im, t, 2020); note(im, "SNOWSTORM FOOTAGE (POLAND) · ILLUSTRATIVE", 1288)
    credit(im, "Snowstorm, Babia Góra · " + CR["v_storm"]); return im
def s_walk(t):
    lt = t - st("walk"); dur = en("walk") - st("walk") + 0.4
    a = photo("jh69", lt, dur, (1.25, 1.45), (0.0, -0.01), 30, 0.48, 0.52) * 0.85; im = to_pil(a); d = ImageDraw.Draw(im, "RGBA")
    k = rx.ease((lt - 0.2) / 2.2); pts = [(W / 2 + 40, H + 40), (W / 2 - 90, 1180), (W / 2 + 30, 1000), (W / 2 - 20, 880)]
    dashed(d, pts, ACC + (255,), 9, 26, 18, k)
    put(im, T("≈ 4 KM", 210, ACC), W / 2, 330, t, wt("walk", "4") - 0.1, None, "slam", 0.2); kick(t, wt("walk", "4"), 12)
    put(im, T("EACH WAY", 110), W / 2, 500, t, wt("walk", "each") - 0.1, None, "up")
    put(im, chip("No cars since 2016", RED, "car-off", 32), W / 2, 640, t, wt("walk", "over") - 0.2, None, "left")
    put(im, chip("Open black sand", YEL, "wind", 32), W / 2, 760, t, wt("walk", "open") - 0.1, None, "right")
    credit(im, "Sólheimasandur · " + CR["jh69"]); return im
_PH = {}
def phone():
    if "p" not in _PH:
        sc = Image.open(os.path.join(FONTS, "..", "img", "en", "alerts.webp")).convert("RGB"); w = 560; h = int(sc.height * w / sc.width)
        sc = sc.resize((w, h), Image.LANCZOS); b = 22; L = Image.new("RGBA", (w + 2 * b + 80, h + 2 * b + 80), (0, 0, 0, 0))
        sh = Image.new("RGBA", L.size, (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle((40, 56, w + 2 * b + 40, h + 2 * b + 56), 90, fill=(0, 0, 0, 200)); L.alpha_composite(sh.filter(ImageFilter.GaussianBlur(24)))
        d = ImageDraw.Draw(L); d.rounded_rectangle((40, 40, w + 2 * b + 40, h + 2 * b + 40), 90, fill=(24, 26, 30, 255), outline=(90, 94, 100, 255), width=4)
        m = Image.new("L", (w, h), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), 70, fill=255); L.paste(sc, (40 + b, 40 + b), m)
        _PH["p"] = L
    return _PH["p"]
_LOGO = {}
def logo(w=520):
    if w not in _LOGO:
        ic = Image.open(os.path.join(FONTS, "..", "img", "icon.png")).convert("RGBA"); s = int(w * 0.26); ic = ic.resize((s, s), Image.LANCZOS)
        m = Image.new("L", (s, s), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, s - 1, s - 1), int(s * 0.22), fill=255); ic.putalpha(m)
        f = COND(int(s * 0.95)); d = ImageDraw.Draw(Image.new("RGBA", (4, 4))); tw = d.textlength("Norður", font=f)
        L = Image.new("RGBA", (int(s + 30 + tw), s), (0, 0, 0, 0)); L.alpha_composite(ic, (0, 0)); ImageDraw.Draw(L).text((s + 30, s * 0.5), "Norður", font=f, fill=TEXT, anchor="lm")
        _LOGO[w] = L
    return _LOGO[w]
def s_app(t):
    lt = t - st("app"); a = cam(*mp(*PT["wreck"]), 0.9 + 0.1 * rx.ease(lt / 5))[0]; a = cv2.GaussianBlur(a, (0, 0), 6) * 0.45; a = rx.light_leak(a, t, 0.3, AUR); im = to_pil(a)
    put(im, T("WEATHER CAN TURN", 120), W / 2, 270, t, st("app") - 0.05, None, "up"); put(im, T("IN AN HOUR", 150, ACC), W / 2, 410, t, wt("app", "hour") - 0.1, None, "slam", 0.2)
    kick(t, wt("app", "hour"), 10)
    put(im, phone().resize((420, int(phone().height * 420 / phone().width)), Image.LANCZOS), W / 2, 900, t, wt("app", "Norður") - 0.25, None, "up", 0.45)
    put(im, chip("Warns you before you go", AUR, "alert-triangle", 32), W / 2, 1260, t, wt("app", "warns") - 0.1, None, "pop")
    return im
def s_cta(t):
    lt = t - st("cta"); a = photo("aj", 3.0, 3.0, (1.0, 1.12), (0.02, 0), 60, 0.5, 0.6) * 0.9; im = to_pil(a)
    k = rx.eout(lt / 0.4); im.alpha_composite(Image.new("RGBA", (W, H), (6, 9, 13, int(228 * k))))
    if k > 0.2:
        L = logo(560); im.alpha_composite(alpha(L, k), ((W - L.width) // 2, 560))
        y = rk.block(im, "Weather warnings, wind, roads and SafeTravel alerts for your Iceland trip.", 760, 70) + 40
        rk.shadow_text(im, "JOIN THE WAITLIST", y, MONO(44), ACC); rk.shadow_text(im, "nordur.info", y + 60, COND(150))
        d = ImageDraw.Draw(im)
        for i, ln in enumerate(rk.wrap(d, "Photos & video: Wikimedia Commons (PD, CC0, CC BY, CC BY-SA) · full credits in caption · map: Mapzen DEM · graphics: Norður · AI voice", MONO(20), 960)):
            rk.shadow_text(im, ln, 1480 + i * 28, MONO(20), DIM)
    if t > TOTAL - 0.35:
        kk = (t - (TOTAL - 0.35)) / 0.35; return Image.blend(im, s_hook(0.0), rx.ease(kk))
    return im
SC = {"hook": s_hook, "mission": s_mission, "ice": s_ice, "choice": s_choice, "land": s_land, "saved": s_saved, "fame": s_fame,
      "back": s_back, "storm": s_storm, "walk": s_walk, "app": s_app, "cta": s_cta}
TR = {"mission": ("zoom", 0), "ice": ("whip", 1), "choice": ("zoom", 0), "land": ("whip", -1), "saved": ("whip", 1), "fame": ("zoom", 0),
      "back": ("whip", -1), "storm": ("zoom", 0), "walk": ("whip", 1), "app": ("zoom", 0)}
TW = 0.2
def scene_at(t): return max([i for i in ORDER if st(i) - TW <= t] or ["hook"], key=st)
def render(i, t): return np.asarray(SC[i](t).convert("RGB"), np.float32)
VIG = rx.vignette_map()
def frame(fi):
    t = fi / FPS; SHAKE.clear(); cur = scene_at(t); idx = ORDER.index(cur); T0 = st(cur)
    if cur in TR and T0 - TW <= t < T0 + TW and idx > 0:
        p = (t - (T0 - TW)) / (2 * TW); a = render(ORDER[idx - 1], min(t, T0 - 0.01)); b = render(cur, max(t, T0)); kind, dr = TR[cur]
        out = rx.whip(a, b, p, dr) if kind == "whip" else rx.zoom_cut(a, b, p)
    else: out = render(cur, t)
    if cur != "cta": out = rx.light_leak(out, t, 0.10)
    out = rx.grain(out * VIG, fi, 6); out = rx.shake(out, fi, max(SHAKE) if SHAKE else 0); im = to_pil(out)
    if cur != "cta":
        g = Image.new("L", (1, 560)); [g.putpixel((0, y), int(200 * (y / 560) ** 1.5)) for y in range(560)]
        im.paste(Image.new("RGBA", (W, 560), (4, 6, 10, 255)), (0, H - 560), g.resize((W, 560))); captions(im, t)
    chapters(im, t); return im.convert("RGB")

# ——— sound ———
def engine(total, die_at, sputter_from):
    """Two radial engines: low firing pulses + prop buzz; random misfires from `sputter_from`, silent after `die_at`."""
    SR = rx.SR; n = int(total * SR); tt = np.arange(n) / SR; r = np.random.default_rng(9)
    f = 34 * (1 - 0.35 * np.clip((tt - sputter_from) / (die_at - sputter_from), 0, 1))           # firing rate drops
    ph = np.cumsum(f) / SR; pulse = (np.sin(2 * np.pi * ph) > 0.6).astype(np.float32)
    w = r.normal(0, 1, n).astype(np.float32); body = rx._bp(w * pulse, 40, 600) + 0.3 * rx._bp(w, 80, 300)
    gate = np.ones(n, np.float32); x = sputter_from
    while x < die_at:
        d = r.uniform(0.06, 0.22); gate[int(x * SR):int((x + d) * SR)] = 0.08; x += d + r.uniform(0.1, 0.35)
    gate *= np.clip((die_at - tt) / 0.25, 0, 1); gate = np.convolve(gate, np.ones(400) / 400, "same")
    return rx._norm(body * gate)
def soundtrack(path):
    SR = rx.SR; n = int(TOTAL * SR); tt = np.arange(n) / SR
    v, vsr = sf.read(os.path.join(V, "voice", "narration.wav"), dtype="float32")
    if v.ndim > 1: v = v.mean(1)
    v = np.interp(np.arange(int(len(v) * SR / vsr)) / SR, np.arange(len(v)) / vsr, v).astype(np.float32)
    voice = np.zeros(n, np.float32); voice[:min(n, len(v))] = v[:n]; sfx = np.zeros(n, np.float32)
    for i, (kind, _) in TR.items(): rx.add(sfx, rx.whoosh(0.5 if kind == "whip" else 0.8, 400), st(i) - TW - 0.1, 0.5)
    hits = [wt("hook", "engines"), wt("hook", "survived"), st("mission"), wt("ice", "quit"), wt("choice", "south") - 0.15, wt("land", "black") - 0.1,
            wt("land", "survive"), wt("fame", "icon"), st("back"), wt("storm", "kill"), wt("storm", "hypothermia"), wt("walk", "4")]
    for h in hits: rx.add(sfx, rx.impact(), h, 0.45)
    for h in (wt("land", "injury"), wt("back", "first"), wt("app", "warns")): rx.add(sfx, rx.ping(0.9, 1318.5), h, 0.35)
    for i in ("ice", "land", "storm"): rx.add(sfx, rx.riser(1.4), st(i) - 1.4, 0.35)
    eng = engine(en("ice") + 1, wt("ice", "quit") + 0.1, wt("ice", "chokes") - 0.2)
    em = np.clip((tt[:len(eng)] - st("mission") - 2.5) / 0.8, 0, 1) * 0.45; sfx[:len(eng)] += eng * em
    wind = rx.wind_bed(TOTAL); wm = np.clip((tt - wt("ice", "quit")) / 0.4, 0, 1) * np.clip((st("land") + 1.2 - tt) / 0.6, 0, 1) * 0.35
    wm += np.clip((tt - st("storm") + 0.3) / 0.5, 0, 1) * np.clip((st("app") - tt) / 0.6, 0, 1) * 0.55
    sfx += wind[:n] * wm
    mus = rx.music(TOTAL, 84)[:n]; env = rx.envelope(voice); duck = 1 - 0.62 * np.clip(env / 0.06, 0, 1)
    duck = np.convolve(duck, np.ones(int(0.12 * SR)) / int(0.12 * SR), "same")
    mus *= 0.2 * duck * np.clip(tt / 0.3, 0, 1) * np.clip((TOTAL - tt) / 0.6, 0, 1)
    sfx *= (1 - 0.4 * np.clip(env / 0.06, 0, 1))
    mix = voice * 0.92 + sfx * 0.5 + mus; mix = np.tanh(mix * 1.1) / np.tanh(1.1); mix = mix / np.abs(mix).max() * 0.89
    sf.write(path, np.stack([mix, mix], 1), SR, subtype="PCM_16")
    print("mix peak", round(20 * np.log10(np.abs(mix).max()), 2), "dBFS · RMS", round(20 * np.log10(np.sqrt(np.mean(mix ** 2))), 1), "dBFS")

NAME = "solheimasandur-plane"; tmp = os.path.join(OUT, NAME + "-silent.mp4")
if TEST and TEST[0] == "audio": soundtrack(os.path.join(OUT, NAME + "-mix.wav")); sys.exit()
if TEST and TEST[0] == "chunk":
    i, nn = int(TEST[1]), int(TEST[2]); N = int(TOTAL * FPS); a, b = N * i // nn, N * (i + 1) // nn
    pr = rk.writer(os.path.join(OUT, f"{NAME}-part{i}.mp4"))
    for fi in range(a, b): pr.stdin.write(frame(fi).tobytes())
    pr.stdin.close(); pr.wait(); sys.exit()
if TEST and TEST[0] == "mux":
    with open(os.path.join(OUT, "parts.txt"), "w") as fl: fl.writelines(f"file '{NAME}-part{i}.mp4'\n" for i in range(int(TEST[1])))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", os.path.join(OUT, "parts.txt"), "-c", "copy", tmp]); TEST = []
else: rk.run(frame, TOTAL, tmp, TEST)
if not TEST:
    wav = os.path.join(OUT, NAME + "-mix.wav"); soundtrack(wav)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-i", wav, "-c:v", "copy", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac", "-b:a", "192k", "-shortest", os.path.join(OUT, NAME + ".mp4")])
    print("muxed")
