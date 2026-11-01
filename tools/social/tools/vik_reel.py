"""'Columbus wasn't first' — Leif Erikson, Iceland → Vinland. Narrated, dark paper map, overlays, footage."""
import sys, os, json, math, subprocess, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageOps
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo, reelkit as rk, fx
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
V = os.path.join(P, "vik"); TLL = json.load(open(os.path.join(V, "voice", "timeline.json")))
TL = {l["id"]: l for l in TLL}; ORDER = [l["id"] for l in TLL]
def st(i): return TL[i]["start"]
def en(i): return TL[i]["start"] + TL[i]["dur"]
TOTAL = en("cta") + 1.0
ACC, BLUE, GREEN, TEXT, DIM = (255, 90, 31), (120, 170, 255), (61, 224, 168), (246, 246, 242), (180, 186, 192)
CRED = json.load(open(os.path.join(V, "credits.json"))) if os.path.exists(os.path.join(V, "credits.json")) else {}
def img(k):
    for ext in (".img",):
        p = os.path.join(V, k + ext)
        if os.path.exists(p) and os.path.getsize(p) > 1000: return Image.open(p).convert("RGB")
    return None
# ——— map ———
Z = 5; LON0, LAT0, LON1, LAT1 = -72, 40, 18, 73.5
MAP = np.asarray(Image.open(os.path.join(V, "natl.png")).convert("RGB")).astype(np.float32); MS = 2.0
MX0, MY0 = geo.lonlat_to_px(LON0, LAT1, Z)
def mpx(lon, lat): x, y = geo.lonlat_to_px(lon, lat, Z); return (x - MX0) * MS, (y - MY0) * MS
SEAC = (6.0, 10.0, 16.0)
def cam(cx, cy, zoom):
    return np.float32([[zoom, 0, W / 2 - cx * zoom], [0, zoom, H / 2 - cy * zoom]])
def mapview(lon, lat, zoom):
    cx, cy = mpx(lon, lat); M = cam(cx, cy, zoom)
    out = cv2.warpAffine(MAP, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=SEAC)
    return out, M
def tp(M, lon, lat): x, y = mpx(lon, lat); return M[0, 0] * x + M[0, 2], M[1, 1] * y + M[1, 2]
def lerp(a, b, k): return a + (b - a) * k
def graticule(im, M, a=1.0):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    for lat in range(40, 75, 5):
        p = [tp(M, lo, lat) for lo in range(-72, 19, 3)]; d.line(p, fill=(150, 180, 210, int(30 * a)), width=2)
        q = tp(M, -30, lat); d.text((q[0] + 6, q[1] - 24), f"{lat}°N", font=MONO(18), fill=(150, 180, 210, int(90 * a)))
    for lon in range(-70, 20, 10):
        p = [tp(M, lon, la) for la in range(40, 74)]; d.line(p, fill=(150, 180, 210, int(30 * a)), width=2)
    im.alpha_composite(lay)
# route: Norway → Iceland (874 settlement) → Greenland (985) → Vinland (~1000)
STOPS = [("Norway", 5.3, 60.4), ("Iceland", -21.9, 64.15), ("Greenland", -45.5, 61.15), ("Vinland", -55.53, 51.6)]
def route_pts(M, a, b, n=60, bend=0.18):
    (x0, y0), (x1, y1) = tp(M, *a), tp(M, *b)
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2; nx, ny = -(y1 - y0), (x1 - x0)
    cx, cy = mx + nx * bend, my + ny * bend
    return [((1 - u) ** 2 * x0 + 2 * (1 - u) * u * cx + u * u * x1, (1 - u) ** 2 * y0 + 2 * (1 - u) * u * cy + u * u * y1) for u in np.linspace(0, 1, n)]
def dashed(d, pts, k, col, w=6):
    n = int(len(pts) * k)
    for i in range(0, n - 1, 2): d.line([pts[i], pts[i + 1]], fill=col, width=w)
_ship = None
def ship_icon():
    global _ship
    if _ship is None:
        s = Image.new("RGBA", (120, 110), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
        d.polygon([(8, 70), (112, 70), (96, 96), (24, 96)], fill=(255, 255, 255, 255))
        d.line([(60, 10), (60, 72)], fill=(255, 255, 255, 255), width=5)
        d.polygon([(62, 14), (100, 30), (98, 62), (62, 62)], fill=ACC + (255,))
        for x in range(64, 100, 9): d.line([(x, 18), (x, 60)], fill=(255, 255, 255, 140), width=3)
        d.polygon([(8, 70), (0, 50), (14, 66)], fill=(255, 255, 255, 255)); d.polygon([(112, 70), (120, 50), (106, 66)], fill=(255, 255, 255, 255))
        _ship = s
    return _ship
def map_label(im, M, name, lon, lat, a=1.0, col=TEXT, dot=True, dy=-56, size=40):
    x, y = tp(M, lon, lat); d = ImageDraw.Draw(im, "RGBA")
    if dot:
        d.ellipse((x - 11, y - 11, x + 11, y + 11), fill=ACC + (int(255 * a),), outline=(255, 255, 255, int(255 * a)), width=3)
    f = COND(size); tw = d.textlength(name, font=f)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ImageDraw.Draw(lay).text((x - tw / 2, y + dy), name, font=f, fill=(0, 0, 0, int(220 * a)))
    im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(6))); d.text((x - tw / 2, y + dy), name, font=f, fill=col + (int(255 * a),))
def flag_is(im, x, y, w=90):
    u = w / 25; h = 18 * u; d = ImageDraw.Draw(im)
    d.rectangle((x, y, x + w, y + h), fill=(2, 82, 156)); d.rectangle((x + 7 * u, y, x + 11 * u, y + h), fill=(255, 255, 255)); d.rectangle((x, y + 7 * u, x + w, y + 11 * u), fill=(255, 255, 255))
    d.rectangle((x + 8 * u, y, x + 10 * u, y + h), fill=(220, 30, 53)); d.rectangle((x, y + 8 * u, x + w, y + 10 * u), fill=(220, 30, 53))
# ——— footage ———
class Clip:
    def __init__(self, path, start, n, vf):
        self.f = []
        if not os.path.exists(path): return
        p = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(start), "-i", path, "-vf", vf + ",fps=30,format=rgb24", "-frames:v", str(n), "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
        raw = p.stdout.read(); p.wait(); self.f = [np.frombuffer(raw[i * W * H * 3:(i + 1) * W * H * 3], np.uint8).reshape(H, W, 3) for i in range(len(raw) // (W * H * 3))]
    def at(self, t): return self.f[min(int(t * FPS), len(self.f) - 1)] if self.f else None
VF = f"scale=-2:{H},crop={W}:{H}"
CL = {"ice": Clip(os.path.join(V, "v_ice.webm"), 4, 300, VF), "svea": Clip(os.path.join(V, "v_svea.webm"), 20, 240, VF),
      "old": Clip(os.path.join(V, "v_viking1928.webm"), 300, 200, f"scale=-2:{H},crop={W}:{H},eq=saturation=0:contrast=1.15")}
# ——— helpers ———
def kenburns(src, t, dur, z0=1.08, z1=1.2, fy=0.5, fx_=0.5, grade=None):
    k = fx.ease_out(t / dur) if dur else 1; z = z0 + (z1 - z0) * k
    s = max(W / src.width, H / src.height) * z; r = src.resize((int(src.width * s) + 1, int(src.height * s) + 1), Image.BILINEAR)
    x = int((r.width - W) * fx_); y = int((r.height - H) * fy); im = r.crop((x, y, x + W, y + H))
    if grade == "dark": im = ImageEnhance.Brightness(im).enhance(0.55)
    return im.convert("RGBA")
def blurbg(src, dark=0.45):
    im = ImageOps.fit(src, (W // 4, H // 4)).filter(ImageFilter.GaussianBlur(6)).resize((W, H), Image.BILINEAR)
    return ImageEnhance.Brightness(im).enhance(dark).convert("RGBA")
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
def big_number(im, text, y, t, t0, size=230, col=TEXT):
    k = fx.back((t - t0) / 0.45)
    if t < t0: return
    f = COND(int(size * (0.7 + 0.3 * k))); d = ImageDraw.Draw(im); tw = d.textlength(text, font=f)
    d.text(((W - tw) / 2, y + (1 - k) * 40), text, font=f, fill=col, stroke_width=10, stroke_fill=(10, 10, 12))
# timeline bar 1000 → 1492
def timeline(im, t, a=1.0, mark1021=False, gap=False):
    d = ImageDraw.Draw(im, "RGBA"); x0, x1, y = 110, W - 110, 1130
    yr = lambda Y: x0 + (Y - 950) / (1550 - 950) * (x1 - x0)
    d.rounded_rectangle((x0, y - 5, x1, y + 5), 5, fill=(255, 255, 255, int(90 * a)))
    for Y in range(1000, 1551, 100):
        d.line((yr(Y), y - 14, yr(Y), y + 14), fill=(255, 255, 255, int(120 * a)), width=2); d.text((yr(Y) - 30, y + 26), str(Y), font=MONO(24), fill=(200, 205, 210, int(220 * a)))
    if gap:
        k = fx.ease_out(gap)
        d.rounded_rectangle((yr(1021), y - 10, yr(1021) + (yr(1492) - yr(1021)) * k, y + 10), 10, fill=ACC + (int(255 * a),))
    for Y, lab, col in ((1021 if mark1021 else 1000, "Leif Erikson" if not mark1021 else "Vikings in America", GREEN), (1492, "Columbus", BLUE)):
        x = yr(Y); d.ellipse((x - 16, y - 16, x + 16, y + 16), fill=col + (int(255 * a),), outline=(255, 255, 255, int(255 * a)), width=4)
        f = SANS(32); tw = d.textlength(lab, font=f); d.text((x - tw / 2, y - 76), lab, font=f, fill=(255, 255, 255, int(255 * a)))
# captions
WORDS = []
for i in ORDER:
    if i == "cta": continue
    l = TL[i]; ws = l["show"].split(); tot = sum(len(w) + 2 for w in ws); t0 = l["start"]
    for w in ws:
        dd = l["dur"] * (len(w) + 2) / tot; WORDS.append((t0, t0 + dd, w, l["start"], l["start"] + l["dur"])); t0 += dd
def captions(im, t):
    cur = [w for w in WORDS if w[3] <= t < w[4] + 0.12]
    if not cur: return
    line = [w for w in WORDS if w[3] == cur[0][3]]
    k = next((i for i, w in enumerate(line) if w[0] <= t < w[1]), len(line) - 1)
    c0 = (k // 3) * 3; chunk = line[c0:c0 + 3]
    d = ImageDraw.Draw(im, "RGBA"); f = COND(100); txt = " ".join(w[2] for w in chunk); tw = d.textlength(txt, font=f); x = (W - tw) / 2; y = 1360
    pop = fx.ease_out((t - chunk[0][0]) / 0.12)
    xx = x
    for j, w in enumerate(chunk):
        on = c0 + j == k
        d.text((xx, y - (8 if on else 0) * pop), w[2], font=f, fill=ACC if on else (255, 255, 255), stroke_width=7, stroke_fill=(8, 8, 10))
        xx += d.textlength(w[2] + " ", font=f)
CH = [("THE MYTH", "hook", "father"), ("THE FAMILY", "father", "voyage"), ("THE VOYAGE", "voyage", "myth"), ("THE PROOF", "myth", "end")]
def chapters(im, t):
    if not (st("first") <= t < st("end")): return
    d = ImageDraw.Draw(im, "RGBA"); x0, y0, gap = 60, 150, 12; w = (W - 120 - gap * 3) / 4
    for i, (name, a, b) in enumerate(CH):
        x = x0 + i * (w + gap); on = st(a) <= t < st(b); k = 1.0 if t >= st(b) else (np.clip((t - st(a)) / (st(b) - st(a)), 0, 1) if on else 0)
        d.rounded_rectangle((x, y0, x + w, y0 + 8), 4, fill=(255, 255, 255, 60))
        if k > 0.01: d.rounded_rectangle((x, y0, x + w * k, y0 + 8), 4, fill=ACC + (255,))
        d.text((x, y0 + 16), name, font=MONO(20), fill=(255, 255, 255, 230 if on else 110))
def credit(im, text, y=1290):
    d = ImageDraw.Draw(im, "RGBA"); f = MONO(18); tw = d.textlength(text, font=f)
    d.rounded_rectangle((W - 50 - tw - 20, y, W - 50, y + 32), 8, fill=(0, 0, 0, 150)); d.text((W - 50 - tw - 10, y + 6), text, font=f, fill=(225, 225, 225))
# pre-built overlay cards
def card(k, w, h, style="card", cap=None, rot=0):
    src = img(k)
    if src is None: return None
    return fx.frame_photo(src, w, h, style=style, caption=cap, font=SANS(30), rot=rot)
CARDS = {}
def C(k, *a, **kw):
    key = (k,) + a + tuple(sorted(kw.items()))
    if key not in CARDS: CARDS[key] = card(k, *a, **kw)
    return CARDS[key]
STAMP_NOT = fx.stamp("NOT FIRST", COND(110), (230, 50, 50), -14)
STAMP_LEG = fx.stamp("LEGEND?", COND(100), (255, 200, 60), 10)
STAMP_REAL = fx.stamp("PROVEN", COND(110), GREEN, -10)

def frame(fi):
    t = fi / FPS; shake = 0
    # ——— 1 · hook: Columbus portrait, NOT FIRST stamp ———
    if t < st("first"):
        src = img("columbus") or img("krohg")
        im = kenburns(src, t, en("hook"), 1.05, 1.18, fy=0.25, grade="dark") if src else Image.new("RGBA", (W, H), (7, 9, 12, 255))
        g = Image.new("RGBA", (W, H), (7, 9, 12, 120)); im.alpha_composite(g)
        if src: credit(im, CRED.get("columbus", ""))
        d = ImageDraw.Draw(im); f = COND(64); txt = "CHRISTOPHER COLUMBUS, 1492"; tw = d.textlength(txt, font=f)
        d.text(((W - tw) / 2, 260), txt, font=f, fill=TEXT, stroke_width=4, stroke_fill=(0, 0, 0))
        if t > 2.2:
            k = fx.ease_out((t - 2.2) / 0.18); s = 2.2 - 1.2 * k
            L = STAMP_NOT.resize((int(STAMP_NOT.width * s), int(STAMP_NOT.height * s)))
            im.alpha_composite(L, (int(W / 2 - L.width / 2), int(820 - L.height / 2)))
            if t < 2.6: shake = 10 * (1 - (t - 2.2) / 0.4)
    # ——— 2 · first: map Iceland → America, timeline 1000 vs 1492 ———
    elif t < st("father"):
        lt = t - st("first"); k = fx.ease_out(lt / 3)
        a, M = mapview(lerp(-25, -38, k), lerp(63, 57, k), lerp(0.9, 0.5, k))
        im = Image.fromarray(a.astype(np.uint8)).convert("RGBA"); graticule(im, M)
        dd = ImageDraw.Draw(im, "RGBA")
        pts = route_pts(M, STOPS[1][1:], STOPS[3][1:], bend=0.12); dashed(dd, pts, fx.ease_out(lt / 2.5), ACC + (255,))
        map_label(im, M, "ICELAND", -18.5, 64.9, dot=False, dy=-30, size=58)
        flag_is(im, *[int(v) for v in tp(M, -24.5, 66.2)], 80)
        if lt > 1.6: map_label(im, M, "America", -60, 50, fx.ease_out((lt - 1.6) / 0.4))
        timeline(im, t, fx.ease_out((lt - 0.6) / 0.4))
    # ——— 3 · name: Krohg painting ———
    elif t < st("father"):
        lt = t - st("name"); src = img("krohg"); im = kenburns(src, lt, 2.2, 1.0, 1.12, fy=0.4, fx_=0.35)
        credit(im, CRED.get("krohg", ""))
        d = ImageDraw.Draw(im); f = COND(120); tw = d.textlength("LEIF ERIKSON", font=f)
        k = fx.back(lt / 0.5); d.text(((W - tw) / 2, 230 + (1 - k) * 60), "LEIF ERIKSON", font=f, fill=TEXT, stroke_width=8, stroke_fill=(0, 0, 0))
        chip_anim(im, "Born in Iceland, around 970", 140, 420, t, st("name") + 0.4, st("father") + 0.1, GREEN)
    # ——— 3b · father: Erik the Red ———
    elif t < st("green"):
        lt = t - st("father"); src = img("eiriks") or img("krohg")
        im = blurbg(src, 0.42)
        dd = ImageDraw.Draw(im); dd.text((80, 230), "HAUKADALUR, ICELAND · ~982 AD", font=MONO(28), fill=DIM)
        c = C("erik", 470, 660, "polaroid", "Erik the Red")
        if c: fx.place(im, c.rotate(-4, resample=Image.BICUBIC, expand=True), W / 2, 760, t, st("father"), st("green") + 0.3, "drop", "left", 0.5, 0.3, rot_in=-20); credit(im, CRED.get("erik", ""), 1180)
        chip_anim(im, "Outlawed for 3 years", 90, 1100, t, st("father") + 2.0, st("green") + 0.2, ACC)
        if lt > 0.3: credit(im, "Ruins at Eiríksstaðir · " + CRED.get("eiriks", ""), 1290)
    # ——— 4 · green: map zoom to Greenland, "GREENLAND" label pops, ice footage PIP ———
    elif t < st("voyage"):
        lt = t - st("green"); k = fx.ease_out(lt / 2.5)
        a, M = mapview(lerp(-24, -36, k), lerp(64.5, 66.5, k), lerp(1.2, 0.62, k))
        im = Image.fromarray(a.astype(np.uint8)).convert("RGBA"); graticule(im, M)
        dd = ImageDraw.Draw(im, "RGBA")
        pts = route_pts(M, STOPS[1][1:], STOPS[2][1:], bend=0.2); dashed(dd, pts, fx.ease_out(lt / 2.2), ACC + (255,))
        if lt < 2.4:
            sx, sy = pts[min(len(pts) - 1, int(fx.ease_out(lt / 2.2) * (len(pts) - 1)))]; s = ship_icon(); im.alpha_composite(s, (int(sx - 60), int(sy - 80)))
        map_label(im, M, "Iceland", -18.6, 64.9, dot=False, dy=-24, size=42)
        if lt > 2.2:
            kk = fx.back((lt - 2.2) / 0.45); f = COND(int(130 * kk) + 1); x, y = tp(M, -42, 70)
            dd.text((x - dd.textlength("GREENLAND", font=f) / 2, y), "GREENLAND", font=f, fill=TEXT, stroke_width=8, stroke_fill=(0, 0, 0))
        fr = CL["ice"].at(max(0, lt - 3.6))
        if fr is not None and lt > 3.6:
            pip = Image.fromarray(fr).crop((0, 300, W, 1500)).resize((520, 578))
            L = fx.frame_photo(pip, 520, 578, border=10, radius=18)
            fx.place(im, L, W - 330, 1000, t, st("green") + 3.6, st("voyage") + 0.2, "right", "right", 0.45, 0.3)
            chip_anim(im, "Mostly ice. Named 'green' on purpose", 70, 1180, t, st("green") + 4.4, st("voyage"), BLUE)
        if fr is not None and lt > 3.6: credit(im, "Footage: NASA · public domain", 1290)
    # ——— 5 · voyage: full Atlantic map, ship sails Greenland → Vinland ———
    elif t < st("vinland"):
        lt = t - st("voyage"); k = fx.ease_out(lt / 4)
        a, M = mapview(lerp(-30, -35, k), lerp(62, 59, k), lerp(0.62, 0.5, k))
        im = Image.fromarray(a.astype(np.uint8)).convert("RGBA"); graticule(im, M)
        dd = ImageDraw.Draw(im, "RGBA")
        for i in range(len(STOPS) - 1):
            pts = route_pts(M, STOPS[i][1:], STOPS[i + 1][1:], bend=0.15 if i else -0.12)
            dashed(dd, pts, 1.0 if i < 2 else fx.ease_out(lt / 3.2), (ACC if i == 2 else (255, 255, 255)) + (255 if i == 2 else 120,))
        pts = route_pts(M, STOPS[2][1:], STOPS[3][1:], bend=0.15); u = fx.ease_out(lt / 3.2)
        sx, sy = pts[min(len(pts) - 1, int(u * (len(pts) - 1)))]; im.alpha_composite(ship_icon(), (int(sx - 60), int(sy - 80)))
        for name, lo, la in STOPS[:3]: map_label(im, M, name, lo, la, 0.9, dy=-58, size=36)
        c = C("ship", 460, 300, "card")
        if c: fx.place(im, c, W / 2 + 200, 1100, t, st("voyage") + 0.6, st("vinland") + 0.1, "up", "down", 0.45, 0.3)
        if c and lt > 0.6: credit(im, "Viking ship (Gokstad) · " + CRED.get("ship", ""), 1290)
        big_number(im, "~1000 AD", 300, t, st("voyage") + 0.3, 150, ACC)
    # ——— 6 · vinland: Vinland pin, grapes, "WINE LAND" ———
    elif t < st("myth"):
        lt = t - st("vinland")
        fr = CL["svea"].at(lt)
        im = Image.fromarray(fr).convert("RGBA") if fr is not None else Image.new("RGBA", (W, H), (7, 9, 12, 255))
        im.alpha_composite(Image.new("RGBA", (W, H), (7, 9, 12, 90)))
        page = img("flatey")
        if page:
            L = fx.frame_photo(page.crop((0, 0, page.width, int(page.height * 0.62))), 520, 470, border=10, radius=14)
            fx.place(im, L, 330, 760, t, st("vinland") + 0.2, st("myth") + 0.2, "spin", "left", 0.5, 0.3)
            credit(im, CRED.get("flatey", "Flateyjarbók"), 1060)
        if lt > 2.9:
            k = fx.back((lt - 2.9) / 0.5); f = COND(int(170 * k) + 1); d = ImageDraw.Draw(im)
            tx = "VÍNLAND"; d.text((W - 80 - d.textlength(tx, font=f), 420), tx, font=f, fill=GREEN, stroke_width=9, stroke_fill=(0, 0, 0))
            if lt > 4.6:
                f2 = COND(80); d.text((W - 80 - d.textlength("= WINE LAND", font=f2), 600), "= WINE LAND", font=f2, fill=TEXT, stroke_width=6, stroke_fill=(0, 0, 0))
        chip_anim(im, "Saga of the Greenlanders · written ~1200", 70, 1150, t, st("vinland") + 0.6, st("myth"), BLUE)
        if fr is not None: credit(im, "Footage: Sailing Svea · CC BY 3.0", 1290)
    # ——— 7 · myth: old film (1928), LEGEND? stamp ———
    elif t < st("found"):
        lt = t - st("myth"); fr = CL["old"].at(lt)
        im = Image.fromarray(fr).convert("RGBA") if fr is not None else Image.new("RGBA", (W, H), (20, 20, 20, 255))
        a = np.asarray(im.convert("RGB")).astype(np.float32); a = fx.grain(a, t, 14) * np.array([1.0, 0.95, 0.85]); im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")
        if lt > 0.8:
            k = fx.ease_out((lt - 0.8) / 0.2); s = 2 - k
            L = STAMP_LEG.resize((int(STAMP_LEG.width * s), int(STAMP_LEG.height * s))); im.alpha_composite(L, (int(W / 2 - L.width / 2), int(700 - L.height / 2)))
        if fr is not None: credit(im, "The Viking (1928) · public domain", 1290)
    # ——— 8 · found: map zoom to Newfoundland, satellite card, longhouse polaroid ———
    elif t < st("date"):
        lt = t - st("found"); k = fx.ease_out(lt / 2.6)
        a, M = mapview(lerp(-40, -55.5, k), lerp(58, 51.6, k), lerp(0.5, 3.0, k))
        im = Image.fromarray(a.astype(np.uint8)).convert("RGBA"); graticule(im, M)
        map_label(im, M, "L'Anse aux Meadows", -55.53, 51.6, fx.ease_out((lt - 1.8) / 0.4), dy=-70, size=46)
        if lt < 2.6: map_label(im, M, "NEWFOUNDLAND, CANADA", -56.5, 49.2, 1 - fx.ease_out((lt - 1.6) / 0.4), dot=False, size=40)
        c = C("longhouse", 600, 400, "polaroid", "Rebuilt Norse longhouse")
        if c: fx.place(im, c.rotate(3, resample=Image.BICUBIC, expand=True), W / 2, 980, t, st("found") + 2.6, st("date") + 0.2, "drop", "down", 0.5, 0.3, rot_in=15)
        if c and lt > 2.6: credit(im, CRED.get("longhouse", ""), 1290)
        big_number(im, "1960", 240, t, st("found") + 0.8, 170, ACC)
    # ——— 9 · date: tree-ring rings drawing, "1021" ———
    elif t < st("storm"):
        lt = t - st("date"); src = img("longhouse") or img("krohg")
        im = blurbg(src, 0.35); d = ImageDraw.Draw(im, "RGBA")
        cx, cy = W / 2, 820; n = 29 + 1
        k = fx.ease_out(lt / 3.0)
        for i in range(int(n * k)):
            r = 40 + i * 11; col = (190, 140, 90, 255) if i % 2 else (150, 100, 60, 255)
            d.ellipse((cx - r * 1.05, cy - r, cx + r * 1.05, cy + r), outline=col, width=6)
        d.text((80, 230), "NATURE · 2021", font=MONO(30), fill=DIM)
        if lt > 3.4: big_number(im, "1021", 280, t, st("date") + 3.4, 230, GREEN)
        chip_anim(im, "Wood cut with metal tools", 70, 1150, t, st("date") + 1.2, st("storm"), ACC)
    # ——— 10 · storm: sun flare + ring highlighted ———
    elif t < st("gap"):
        lt = t - st("storm"); im = Image.new("RGBA", (W, H), (7, 9, 12, 255)); d = ImageDraw.Draw(im, "RGBA")
        cx, cy = W / 2, 860
        for i in range(30):
            r = 40 + i * 11; hl = (i == 1)
            d.ellipse((cx - r * 1.05, cy - r, cx + r * 1.05, cy + r), outline=(255, 90, 31, 255) if hl else ((120, 90, 60, 200) if i % 2 else (90, 66, 44, 200)), width=10 if hl else 6)
        sun = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ds = ImageDraw.Draw(sun); pulse = 1 + 0.08 * math.sin(lt * 8)
        ds.ellipse((W / 2 - 150 * pulse, 260 - 150 * pulse, W / 2 + 150 * pulse, 260 + 150 * pulse), fill=(255, 200, 80, 255))
        im.alpha_composite(sun.filter(ImageFilter.GaussianBlur(40))); im.alpha_composite(sun.filter(ImageFilter.GaussianBlur(6)))
        if lt > 0.8:
            yy = 260 + (cy - 52 - 260) * fx.ease_out((lt - 0.8) / 0.8); d.line((W / 2, 410, W / 2, yy), fill=(255, 200, 80, 220), width=8)
        chip_anim(im, "Solar storm of 993 → radiocarbon spike", 70, 1150, t, st("storm") + 0.5, st("gap"), ACC)
        chip_anim(im, "+29 rings → cut in 1021", 70, 1240, t, st("storm") + 1.6, st("gap"), GREEN)
    # ——— 11 · gap: timeline 1021 → 1492 grows, 471 ———
    elif t < st("end"):
        lt = t - st("gap"); src = img("krohg")
        im = blurbg(src, 0.3); timeline(im, t, 1.0, True, (lt - 0.3) / 1.6)
        big_number(im, "471 YEARS", 520, t, st("gap") + 0.8, 200, ACC)
        if lt > 2.0:
            k = fx.ease_out((lt - 2.0) / 0.2); s = 2 - k; L = STAMP_REAL.resize((int(STAMP_REAL.width * s), int(STAMP_REAL.height * s)))
            im.alpha_composite(L, (int(W / 2 - L.width / 2), int(860 - L.height / 2)))
    # ——— 12 · end: Leif statue in Reykjavík ———
    elif t < st("cta"):
        lt = t - st("end"); src = img("statue")
        im = kenburns(src, lt, 5.5, 1.05, 1.18, fy=0.3) if src else Image.new("RGBA", (W, H), (7, 9, 12, 255))
        im.alpha_composite(Image.new("RGBA", (W, H), (7, 9, 12, 70)))
        if src: credit(im, "Leif Erikson statue, Reykjavík · " + CRED.get("statue", ""))
        chip_anim(im, "Gift from the USA, 1930", 70, 300, t, st("end") + 1.0, st("cta"), BLUE)
        if lt > 3.8:
            flag_is(im, 80, 410, 110)
    else:
        lt = t - st("cta"); a, M = mapview(-35, 60, 0.85)
        im = Image.fromarray(a.astype(np.uint8)).convert("RGBA")
        rk.cta(im, fx.ease_out(lt / 0.5), P, "Your guide to Iceland. Weather, roads, aurora and the stories behind every place.",
               "Images: Wikimedia Commons (public domain, CC BY, CC BY-SA) and NASA · map: Mapzen Terrain Tiles · AI voice")
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
tmp = os.path.join(OUT, "vik-silent.mp4")
rk.run(frame, TOTAL, tmp, TEST)
if not TEST:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-i", os.path.join(V, "voice", "narration.wav"), "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", os.path.join(OUT, "vikings-before-columbus.mp4")])
    print("muxed")
