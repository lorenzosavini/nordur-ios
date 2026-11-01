"""'This beach has killed 6 people' — Reynisfjara sneaker waves + 4 tourist mistakes in Iceland (safety reel, ties to Norður alerts).
Usage: python reynis_reel.py <work> <fonts> <out_dir> [test frame numbers...]
<work>/reynis/: *.img photos + v_windy.mp4 (projects/reynis/dl.py), credits.json, voice/{narration.wav,timeline.json}
<work>/logo/nordur-logo-horizontal-3840-white.png, <work>/icons/*.png (copy of tools/social/icons).
New in this reel (reynis_fx.py): procedural sea/foam, scrolling black sand, pulsing basalt hexes, whip-pans with motion blur,
wave-wipe and zoom match-cut transitions, 2.5D parallax, speed-ramped footage, synthesized SFX + music with ducking."""
import sys, os, json, math, subprocess, numpy as np, cv2, soundfile as sf
from PIL import Image, ImageDraw, ImageFilter, ImageOps
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reelkit as rk, reynis_fx as rx
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
V = os.path.join(P, "reynis"); TLL = json.load(open(os.path.join(V, "voice", "timeline.json")))
TL = {l["id"]: l for l in TLL}; ORDER = [l["id"] for l in TLL]
def st(i): return TL[i]["start"]
def en(i): return TL[i]["start"] + TL[i]["dur"]
TOTAL = en("cta") + 0.9
ACC, BLUE, AUR, TEXT, DIM, YEL, RED = (255, 90, 31), (120, 170, 255), (61, 224, 168), (246, 246, 242), (180, 186, 192), (255, 196, 40), (240, 50, 45)
CRED = json.load(open(os.path.join(V, "credits.json")))
_IMG, _BIG = {}, {}
def img(k):
    if k not in _IMG:
        p = os.path.join(V, k + ".img"); _IMG[k] = Image.open(p).convert("RGB") if os.path.exists(p) and os.path.getsize(p) > 1000 else None
    return _IMG[k]
def big(k, s=1.3):
    if (k, s) not in _BIG: _BIG[(k, s)] = rx.cover(img(k), s) if img(k) else np.full((int(H * s), int(W * s), 3), 20, np.float32)
    return _BIG[(k, s)]
def photo(k, lt, dur, zoom=(1.0, 1.12), pan=(0.0, 0.0), depth=60): return rx.parallax(big(k), lt, dur, zoom, pan, depth)

# ——— footage (speed ramped) ———
_VID = []
def vid_frames():
    if not _VID:
        cap = cv2.VideoCapture(os.path.join(V, "v_windy.mp4"))
        while True:
            ok, f = cap.read()
            if not ok: break
            h, w = f.shape[:2]; cw = int(h * W / H); x0 = (w - cw) // 2 + int(w * 0.08)
            _VID.append(cv2.cvtColor(f[:, x0:x0 + cw], cv2.COLOR_BGR2RGB))
    return _VID
def vid(ts):
    fr = vid_frames(); i = min(len(fr) - 1, max(0, int(ts * 25)))
    return cv2.resize(fr[i], (W, H), interpolation=cv2.INTER_CUBIC).astype(np.float32)
def ramp(lt, slow=0.35, fast=2.2, tsw=1.2, d=0.4):
    """Source time for a speed ramp: slow-mo until tsw, then ramps to fast over d s."""
    if lt < tsw: return lt * slow
    k = min(1, (lt - tsw) / d); a = tsw * slow
    if lt < tsw + d: return a + (lt - tsw) * (slow + (fast - slow) * k / 2)
    return a + d * (slow + fast) / 2 + (lt - tsw - d) * fast

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
    return st(line)
def captions(im, t):
    cur = [w for w in WORDS if w[3] <= t < w[4] + 0.12]
    if not cur: return
    line = [w for w in WORDS if w[3] == cur[0][3]]
    k = next((i for i, w in enumerate(line) if w[0] <= t < w[1]), len(line) - 1)
    c0 = (k // 3) * 3; chunk = line[c0:c0 + 3]
    d = ImageDraw.Draw(im, "RGBA"); f = COND(98); txt = " ".join(w[2] for w in chunk)
    while d.textlength(txt, font=f) > W - 90: f = COND(f.size - 6)
    x = (W - d.textlength(txt, font=f)) / 2; y = 1390; pop = rx.eout((t - line[k][0]) / 0.12)
    for j, w in enumerate(chunk):
        on = c0 + j == k; s = f if not on else COND(int(f.size * (1.12 - 0.12 * pop)))
        d.text((x, y - (10 if on else 0) * pop + (f.size - s.size) * 0.5), w[2], font=s, fill=ACC if on else (255, 255, 255), stroke_width=7, stroke_fill=(6, 8, 10))
        x += d.textlength(w[2], font=s) + d.textlength(" ", font=f)
CH = [("THE BEACH", "place", "turn"), ("1 · WIND", "door", "froad"), ("2 · F-ROADS", "froad", "sheep"), ("3 · SHEEP", "sheep", "stop"), ("4 · PHOTO STOP", "stop", "app")]
def chapters(im, t):
    if not (st("place") <= t < st("app")): return
    d = ImageDraw.Draw(im, "RGBA"); x0, y0, gap = 50, 130, 10; ws = [1.5, 1, 1.15, 1, 1.45]; tw = (W - 100 - gap * 4) / sum(ws); x = x0
    for (name, a, b), wk in zip(CH, ws):
        w = tw * wk; on = st(a) <= t < st(b); k = 1.0 if t >= st(b) else (np.clip((t - st(a)) / (st(b) - st(a)), 0, 1) if on else 0)
        d.rounded_rectangle((x, y0, x + w, y0 + 8), 4, fill=(255, 255, 255, 60))
        if k > 0.01: d.rounded_rectangle((x, y0, x + w * k, y0 + 8), 4, fill=ACC + (255,))
        d.text((x, y0 + 16), name, font=MONO(19), fill=(255, 255, 255, 235 if on else 105)); x += w + gap
def credit(im, text, y=1325):
    if not text: return
    d = ImageDraw.Draw(im, "RGBA"); f = MONO(18); tw = d.textlength(text, font=f)
    d.rounded_rectangle((W - 40 - tw - 20, y, W - 40, y + 32), 8, fill=(0, 0, 0, 150)); d.text((W - 40 - tw - 10, y + 6), text, font=f, fill=(225, 225, 225))

# ——— drawing helpers ———
def icon(name, size, col=(255, 255, 255)):
    a = Image.open(os.path.join(P, "icons", name + ".png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", a.size, col + (255,)); out.putalpha(a.getchannel("A")); return out
def alpha(L, a):
    if a >= 0.999: return L
    L = L.copy(); L.putalpha(L.getchannel("A").point(lambda v: int(v * a))); return L
def put(im, L, cx, cy, t, t0, t1=None, enter="pop", tin=0.35, tout=0.25):
    """Place layer centred at cx,cy with pop/slide-in and fade-out. Returns local progress or None."""
    if t < t0 or (t1 is not None and t > t1): return None
    pi = min(1, (t - t0) / tin); po = 0 if t1 is None else max(0, min(1, (t - (t1 - tout)) / tout))
    s, dx, dy = 1, 0, 0
    if enter == "pop": s = 0.55 + 0.45 * rk_back(pi)
    elif enter == "slam": s = 1 + 1.2 * (1 - rx.eout(pi))
    elif enter == "left": dx = -W * (1 - rx.eout(pi))
    elif enter == "right": dx = W * (1 - rx.eout(pi))
    elif enter == "up": dy = 500 * (1 - rx.eout(pi))
    a = min(1, pi * 2.5) * (1 - rx.ein(po))
    if a <= 0.01: return pi
    L2 = L if abs(s - 1) < 0.01 else L.resize((max(1, int(L.width * s)), max(1, int(L.height * s))), Image.BILINEAR)
    im.alpha_composite(alpha(L2, a), (int(cx + dx - L2.width / 2), int(cy + dy - L2.height / 2)))
    return pi
def rk_back(x, s=1.7): x = max(0.0, min(1.0, x)) - 1; return x * x * ((s + 1) * x + s) + 1
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
    """App-style UI card (dark glass, coloured icon tile)."""
    L = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0)); sh = Image.new("RGBA", L.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((20, 28, w + 20, h + 28), 34, fill=(0, 0, 0, 170)); L.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(L); d.rounded_rectangle((20, 20, w + 20, h + 20), 34, fill=(17, 22, 28, 238), outline=(255, 255, 255, 38), width=2)
    d.rounded_rectangle((44, 20 + (h - 100) // 2, 144, 120 + (h - 100) // 2), 26, fill=col + (255,))
    L.alpha_composite(icon(ic, 64, (10, 12, 14)), (62, 38 + (h - 100) // 2))
    d.text((172, 20 + h * 0.18), title, font=SANS(40), fill=TEXT); d.text((172, 20 + h * 0.56), sub, font=SANS(30), fill=sub_col)
    return L
def chip(txt, col=ACC, ic=None, size=34):
    d = ImageDraw.Draw(Image.new("RGBA", (4, 4))); f = SANS(size); tw = d.textlength(txt, font=f); h = int(size * 2); w = int(tw + h * (1.5 if ic else 0.9))
    L = Image.new("RGBA", (w + 30, h + 30), (0, 0, 0, 0)); sh = Image.new("RGBA", L.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((15, 21, w + 15, h + 21), h // 2, fill=(0, 0, 0, 140)); L.alpha_composite(sh.filter(ImageFilter.GaussianBlur(8)))
    d = ImageDraw.Draw(L); d.rounded_rectangle((15, 15, w + 15, h + 15), h // 2, fill=(255, 255, 255, 250))
    if ic: L.alpha_composite(icon(ic, int(size * 1.15), col), (15 + h // 3, 15 + (h - int(size * 1.15)) // 2)); x = 15 + h // 3 + int(size * 1.5)
    else: d.ellipse((30, 15 + h / 2 - 9, 48, 15 + h / 2 + 9), fill=col + (255,)); x = 60
    d.text((x, 15 + h * 0.22), txt, font=f, fill=(12, 14, 18)); return L
def stamp(txt, col=RED, size=84, rot=-10):
    d = ImageDraw.Draw(Image.new("RGBA", (4, 4))); f = COND(size); tw = d.textlength(txt, font=f)
    L = Image.new("RGBA", (int(tw + 80), int(size * 1.5)), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((6, 6, L.width - 6, L.height - 6), 14, outline=col + (255,), width=9, fill=(0, 0, 0, 90)); d.text((40, size * 0.12), txt, font=f, fill=col + (255,))
    return L.rotate(rot, resample=Image.BICUBIC, expand=True)
def traffic_light(state, k):
    """Generic 3-lamp warning light (drawn). state: 'yellow'/'red'; k: glow 0..1."""
    L = Image.new("RGBA", (420, 980), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((120, 40, 300, 940), 30, fill=(30, 32, 36, 255)); d.rounded_rectangle((60, 40, 360, 640), 60, fill=(18, 20, 24, 255), outline=(70, 74, 80, 255), width=6)
    for i, (c, name) in enumerate([(RED, "red"), (YEL, "yellow"), ((60, 200, 120), "green")]):
        cy = 150 + i * 180; on = state == name and name != "green"
        col = c if on else tuple(int(v * 0.22) for v in c)
        if on:
            g = Image.new("RGBA", L.size, (0, 0, 0, 0)); ImageDraw.Draw(g).ellipse((210 - 150, cy - 150, 210 + 150, cy + 150), fill=c + (int(200 * k),)); L.alpha_composite(g.filter(ImageFilter.GaussianBlur(40)))
            d = ImageDraw.Draw(L)
        d.ellipse((130, cy - 80, 290, cy + 80), fill=col + (255,), outline=(0, 0, 0, 255), width=6)
        if on: d.ellipse((165, cy - 60, 215, cy - 20), fill=(255, 255, 255, 110))
    return L
def car(angle):
    """Side-view car (facing right) whose front door swings open by `angle` degrees about its front hinge."""
    L = Image.new("RGBA", (980, 560), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((60, 250, 900, 420), 60, fill=(222, 226, 230, 255)); d.polygon([(250, 255), (330, 130), (640, 130), (760, 255)], fill=(222, 226, 230, 255))
    d.polygon([(275, 250), (345, 150), (480, 150), (480, 250)], fill=(40, 60, 80, 255)); d.polygon([(500, 250), (500, 150), (625, 150), (720, 250)], fill=(40, 60, 80, 255))
    for x in (230, 730): d.ellipse((x - 80, 350, x + 80, 510), fill=(20, 20, 22, 255)); d.ellipse((x - 38, 392, x + 38, 468), fill=(150, 154, 160, 255))
    d.rectangle((860, 300, 900, 330), fill=ACC + (255,))
    hx, top, bot, dw = 700, 140, 410, 210                               # front door: hinge at its front edge (x=700)
    a = math.radians(angle); far = hx - dw * math.cos(a); grow = 1 + 0.28 * math.sin(a)
    mid = (top + bot) / 2; ft, fb = mid - (mid - top) * grow, mid + (bot - mid) * grow
    inner = math.cos(a) < 0
    if angle > 2:
        d.rectangle((hx - dw, top + 110, hx, bot), fill=(14, 16, 20, 255))  # open doorway
        d.polygon([(hx, top + 10), (far, ft + 10), (far, fb), (hx, bot)], fill=(150, 156, 164, 255) if inner else (205, 210, 216, 255), outline=(30, 30, 34, 255))
        d.polygon([(hx, top + 10), (far, ft + 10), (far + (hx - far) * 0.15, ft + 100), (hx, top + 110)], fill=(40, 60, 80, 220))
    else:
        d.line((hx - dw, top + 110, hx - dw, bot), fill=(150, 154, 160, 255), width=4); d.rounded_rectangle((hx - dw + 30, 280, hx - dw + 80, 292), 4, fill=(120, 124, 130, 255))
    return L
def sheep_draw(s=1.0, flip=False, step=0.0):
    L = Image.new("RGBA", (int(380 * s), int(300 * s)), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    for i, (dx, dy) in enumerate([(0, 0), (1, 0.3), (-1, 0.4), (0.4, -0.5), (-0.5, -0.4)]):
        pass
    leg = 12 * math.sin(step)
    for x, ph in ((110, 1), (150, -1), (240, -1), (280, 1)): d.rounded_rectangle(((x + ph * leg) * s, 170 * s, (x + 16 + ph * leg) * s, 270 * s), 6 * s, fill=(30, 28, 26, 255))
    for cx, cy, r in ((130, 140, 62), (190, 120, 66), (250, 140, 62), (170, 175, 55), (230, 175, 55), (95, 160, 40), (285, 160, 40)):
        d.ellipse(((cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s), fill=(240, 238, 230, 255), outline=(200, 196, 186, 255), width=max(1, int(3 * s)))
    d.ellipse((290 * s, 80 * s, 370 * s, 170 * s), fill=(36, 32, 30, 255)); d.ellipse((330 * s, 105 * s, 344 * s, 119 * s), fill=(250, 250, 250, 255))
    d.ellipse((276 * s, 92 * s, 312 * s, 116 * s), fill=(36, 32, 30, 255))
    return L.transpose(Image.FLIP_LEFT_RIGHT) if flip else L

# ——— scenes: each returns float32 HxWx3; `ov` collects PIL drawing on top ———
def to_pil(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")
def dark(a, k): return a * k
SHAKE = []
def kick(t, t0, amt=16, d=0.35):
    if t0 <= t < t0 + d: SHAKE.append(amt * (1 - (t - t0) / d))

def s_hook(t):
    lt = t - st("hook"); a = vid(0.6 + ramp(lt, 0.3, 2.0, 1.6))
    a = a * np.array([1.0, 0.9, 0.88]) * (0.75 - 0.15 * rx.ease(lt / 3)); im = to_pil(a)
    put(im, T("THIS BEACH", 190), W / 2, 420, t, -1)
    put(im, T("HAS KILLED", 150, ACC), W / 2, 590, t, -1 if t < 0.05 else 0, None, "pop")
    ts = wt("hook", "six")
    if t >= ts - 0.05:
        put(im, T("6", 520, TEXT, 14), W / 2, 930, t, ts - 0.05, None, "slam", 0.18); kick(t, ts + 0.1, 22)
        put(im, T("PEOPLE · SINCE 2007", 70, DIM, 6), W / 2, 1200, t, wt("hook", "people"), None, "up")
    else:
        n = int(min(5, (t - 0.45) / 0.25 + 1))
        if n >= 1: put(im, T(str(n), 520, (120, 120, 120), 14), W / 2, 930, t, -1)
    credit(im, "Reynisfjara · " + CRED.get("v_windy", ""))
    return im
def s_place(t):
    lt = t - st("place"); tb = wt("place", "basalt"); tw = wt("place", "waves")
    if t < tb - 0.15:
        a = photo("stacks", lt, 3.0, (1.05, 1.2), (0.05, 0), 80); im = to_pil(a * 0.85)
        put(im, card("Reynisfjara", "Black sand beach · near Vík · South Iceland", "map-pin", ACC), W / 2, 330, t, st("place") + 0.25, None, "left")
        put(im, T("BLACK SAND", 150), W / 2, 1060, t, wt("place", "Black") - 0.05)
        credit(im, "Reynisdrangar · " + CRED.get("stacks", "")); return im
    if t < tw - 0.1:
        lb = t - (tb - 0.15); ph = photo("basalt", lb, 2.4, (1.25, 1.05), (0, -0.05), 40)
        hx = rx.basalt(t * 1.5, ACC); m = rx.ease((lb - 0.15) / 0.5)            # hex pattern dissolves into the real columns
        a = hx * (1 - m) + (ph * 0.9 + hx * 0.25) * m; im = to_pil(a)
        put(im, T("BASALT COLUMNS", 130), W / 2, 1060, t, tb); credit(im, "Basalt columns · " + CRED.get("basalt", "")); return im
    lw = t - tw; a = photo("winter", lw, 2.0, (1.0, 1.18), (0, 0.08), 90); a = rx.shake(a, int(t * 30), 8 * max(0, 1 - lw * 2))
    im = to_pil(a * 0.9); put(im, T("DON'T PLAY FAIR", 140, ACC), W / 2, 1060, t, wt("place", "play") - 0.05, None, "slam", 0.2)
    credit(im, "Winter waves, Reynisfjara · " + CRED.get("winter", "")); return im
LMOST, LSURGE, PERSON = 1180, 470, 700
def runup(lt, tsurge):
    """Water line (px) over time: small waves to LMOST, then a sneaker wave to LSURGE."""
    base = 1640
    if lt < tsurge:
        ph = (lt % 1.7) / 1.7; r = math.sin(math.pi * ph) ** 1.5; reach = LMOST + 20 + 60 * ((int(lt / 1.7) % 2))
        return base - (base - reach) * r
    k = lt - tsurge
    if k < 1.3: return base - (base - LSURGE) * rx.eout(k / 1.3)
    return LSURGE + (base - 120 - LSURGE) * rx.ease((k - 1.6) / 2.4) if k > 1.6 else LSURGE
def s_sneak(t):
    lt = t - st("sneak"); tsg = wt("sneak", "surges") - st("sneak") - 0.15
    sandA = rx.sand(t, 0, dark=1.0); y = runup(lt, tsg)
    m, f = rx.wave_mask(t, y, 22, 110); wet = np.clip((np.arange(H)[:, None] - y + 90) / 90, 0, 1)[..., None] * 0.35
    a = sandA * (1 - wet) + rx.sea(t) * m[..., None] + sandA * (1 - m[..., None]) * 0 + f[..., None] * 240
    a = a * (1 - 0) ; a = np.where(m[..., None] > 0, a, sandA * (1 - wet))
    a = a + f[..., None] * 240
    surged = lt > tsg
    if surged:
        k = rx.ease((lt - tsg) / 0.6); zone = (np.arange(H)[:, None, None] > LSURGE - 40) * (np.arange(H)[:, None, None] < LMOST) * 0.22 * k
        a = a * (1 - zone) + np.array(RED, np.float32) * zone
    im = to_pil(a); d = ImageDraw.Draw(im, "RGBA")
    if t >= wt("sneak", "Most") - 0.1:
        for x in range(40, W - 40, 50): d.line((x, LMOST, x + 28, LMOST), fill=BLUE + (255,), width=6)
        put(im, chip("MOST WAVES STOP HERE", BLUE), W / 2, LMOST + 70, t, wt("sneak", "Most") - 0.1, None, "left")
    pk = 0.5 + 0.5 * math.sin(t * 8) if surged else 0
    pc = RED if surged and y < PERSON + 60 else TEXT
    pl = icon("users", 120, pc); im.alpha_composite(pl, (W // 2 - 60, PERSON - 60))
    if surged:
        d.line((40, LSURGE - 40, W - 40, LSURGE - 40), fill=ACC + (255,), width=8)
        put(im, chip("SNEAKER WAVE", ACC, "alert-triangle"), W / 2, LSURGE - 120, t, st("sneak") + tsg + 0.3, None, "pop")
        kick(t, st("sneak") + tsg + 0.9, 18)
    put(im, T("SNEAKER WAVES", 130), W / 2, 330, t, st("sneak"), wt("sneak", "Most") - 0.05) if not surged else None
    put(im, T("NO WARNING", 120, RED), W / 2, 1070, t, wt("sneak", "without"), None, "slam", 0.18)
    d = ImageDraw.Draw(im, "RGBA"); d.text((40, 1260), "ILLUSTRATION · NOT TO SCALE", font=MONO(18), fill=(255, 255, 255, 120))
    return im
def s_pull(t):
    lt = t - st("pull"); tsw = wt("pull", "swept") - 0.15
    if t < tsw:
        a = photo("waves", lt, 3.2, (1.25, 1.05), (-0.05, 0), 60) * np.array([0.82, 0.92, 1.05]); a = rx.shake(a, int(t * 30), 9 * max(0, 1 - abs(t - wt("pull", "brutal")) * 3))
        im = to_pil(a * 0.85); credit(im, "Waves crashing at Reynisfjara · " + CRED.get("waves", ""))
        put(im, card("Freezing water", "Ice-cold North Atlantic", "temperature", BLUE), W / 2, 380, t, wt("pull", "freezing") - 0.1, None, "left")
        put(im, card("Brutal backwash", "pulls back towards the sea", "ripple", ACC), W / 2, 580, t, wt("pull", "backwash") - 0.1, None, "right")
        kick(t, wt("pull", "brutal"), 14); return im
    l2 = t - tsw; a = vid(5.2 - ramp(l2, 0.25, 0.8, 0.8)) * 0.8 * np.array([0.85, 0.95, 1.05])       # footage reversed: water pulling back
    im = to_pil(a); put(im, T("SWEPT OUT", 160, TEXT), W / 2, 520, t, tsw + 0.05, None, "slam", 0.2); put(im, T("TO SEA", 160, RED), W / 2, 690, t, wt("pull", "sea"), None, "slam", 0.2)
    credit(im, "Reynisfjara · " + CRED.get("v_windy", "")); return im
def s_lights(t):
    lt = t - st("lights"); ty = wt("lights", "Yellow"); tr = wt("lights", "Red")
    if t < ty - 0.15:
        a = photo("hazsys", lt, 2.4, (1.0, 1.15), (0, 0), 30); im = to_pil(a * 0.8)
        put(im, T("SINCE 2022", 170, YEL), W / 2, 380, t, st("lights") + 0.15, None, "slam", 0.2); kick(t, st("lights") + 0.25, 12)
        credit(im, "Warning system, Reynisfjara · " + CRED.get("hazsys", "")); return im
    l2 = t - (ty - 0.15); bgk = "hazsign"
    a = photo(bgk, l2, 6, (1.15, 1.25), (0, 0), 0); a = cv2.GaussianBlur(a, (0, 0), 14) * 0.35
    red = t >= tr - 0.05; col = RED if red else YEL
    a = rx.light_leak(a, t, 0.45, col); im = to_pil(a)
    k = 0.75 + 0.25 * math.sin(t * 9); TLG = traffic_light("red" if red else "yellow", k)
    im.alpha_composite(TLG.resize((300, 700)), (70, 420))
    if not red:
        put(im, T("YELLOW", 150, YEL), 700, 560, t, ty - 0.05, None, "right"); put(im, T("STAY OUT OF", 70, TEXT, 6), 700, 720, t, wt("lights", "stay"), None, "up")
        put(im, T("THE YELLOW ZONE", 70, TEXT, 6), 700, 800, t, wt("lights", "yellow", 1), None, "up")
    else:
        put(im, T("RED", 190, RED), 700, 560, t, tr - 0.05, None, "slam", 0.2); kick(t, tr, 14)
        put(im, T("DON'T GO PAST", 70, TEXT, 6), 700, 740, t, wt("lights", "don't"), None, "up"); put(im, T("THE LIGHT", 70, TEXT, 6), 700, 820, t, wt("lights", "light"), None, "up")
    credit(im, "Background: hazard sign, Reynisfjara · " + CRED.get("hazsign", "")); return im
def s_rule(t):
    lt = t - st("rule"); a = photo("warning", lt, 3.2, (1.25, 1.05), (0, 0.04), 20); im = to_pil(a * 0.55)
    put(im, T("NEVER", 230, ACC), W / 2, 420, t, wt("rule", "never") - 0.05, None, "slam", 0.18); kick(t, wt("rule", "never"), 14)
    put(im, T("TURN YOUR BACK", 130), W / 2, 640, t, wt("rule", "turn") - 0.05, None, "up"); put(im, T("ON THE OCEAN", 130), W / 2, 790, t, wt("rule", "ocean") - 0.1, None, "up")
    credit(im, "Warning sign, Reynisfjara · " + CRED.get("warning", "")); return im
def s_turn(t):
    lt = t - st("turn"); a = photo("lowsun", lt, 2.8, (1.0, 1.2), (0, 0), 60) * 0.45 + rx.sand(t, 260) * 0.4
    im = to_pil(a); tf = wt("turn", "Four") - 0.05
    put(im, T("4", 640, ACC, 16), W / 2, 760, t, tf, None, "slam", 0.18); kick(t, tf + 0.05, 20)
    put(im, T("MORE MISTAKES", 130), W / 2, 1110, t, wt("turn", "mistakes") - 0.1, None, "up"); credit(im, "Reynisfjara · " + CRED.get("lowsun", "")); return im
def s_door(t):
    lt = t - st("door"); tg = wt("door", "gust") - 0.05; tr = wt("door", "rentals") - 0.15
    if t < tr:
        a = rx.sand(t, 30, (0.9, 0.95, 1.05), 0.9) + rx.spray(t, 110, 5, 1, 900)[..., None]
        im = to_pil(a); ang = 0 if t < wt("door", "car") else (35 * rx.ease((t - wt("door", "car")) / 0.6) if t < tg else 35 + 125 * rx.eout((t - tg) / 0.25))
        if t >= tg: kick(t, tg + 0.2, 20)
        im.alpha_composite(car(ang), (50 + int(math.sin(t * 40) * 3 * (t > tg)), 620))
        im.alpha_composite(icon("wind", 140, BLUE), (60, 400))
        put(im, T("STRONG WIND", 130, BLUE), W / 2 + 80, 470, t, wt("door", "strong") - 0.05, None, "left")
        put(im, stamp("BENT BACK", RED, 96), W / 2 + 160, 1180, t, tg + 0.15, None, "slam", 0.18)
        return im
    l2 = t - tr; a = photo("winds", l2, 3, (1.1, 1.25), (0, 0), 40) * 0.7 + rx.spray(t, 80, 9, 0.8, 1100)[..., None]
    im = to_pil(a)
    put(im, card("Wind damage to doors", "often NOT covered by rental insurance", "car", ACC, 900, 160, (255, 160, 120)), W / 2, 520, t, tr + 0.05, None, "pop")
    put(im, chip("Hold the door with both hands", AUR, "hand-stop", 34), W / 2, 760, t, tr + 1.0, None, "up")
    credit(im, "Wind at Reynisfjara · " + CRED.get("winds", "")); return im
def s_froad(t):
    lt = t - st("froad"); a = rx.sand(t, 140, (1.05, 1.0, 0.95), 1.1); im = to_pil(a); d = ImageDraw.Draw(im)
    d.polygon([(470, 560), (610, 560), (1000, 1320), (80, 1320)], fill=(92, 84, 74)); d.polygon([(0, 560), (1080, 560), (1080, 420), (760, 300), (520, 410), (300, 330), (0, 470)], fill=(34, 38, 46))
    for y in range(560 + int(lt * 300) % 120 - 120, 1320, 120): d.ellipse((520 + (y - 560) * 0.02, y, 560 + (y - 560) * 0.06, y + 26), fill=(70, 64, 56))
    badge = Image.new("RGBA", (300, 300), (0, 0, 0, 0)); d = ImageDraw.Draw(badge); d.rounded_rectangle((10, 10, 290, 290), 40, fill=(250, 250, 250, 255), outline=(20, 20, 20, 255), width=10)
    d.text((150, 150), "F", font=COND(240), fill=(20, 20, 20, 255), anchor="mm")
    put(im, badge, 220, 420, t, wt("froad", "F-road") - 0.1, None, "slam", 0.2); kick(t, wt("froad", "F-road"), 10)
    put(im, chip("2WD", RED, "car-off"), 720, 340, t, wt("froad", "2WD") - 0.1, None, "right")
    if t > wt("froad", "F-road") + 0.1: put(im, stamp("NO", RED, 90, 8), 760, 345, t, wt("froad", "F-road") + 0.1, None, "slam", 0.15)
    put(im, T("4x4 BY LAW", 150, AUR), W / 2, 760, t, wt("froad", "law") - 0.05, None, "slam", 0.2); kick(t, wt("froad", "law"), 12)
    put(im, chip("Most open only in summer", YEL, "calendar"), W / 2, 960, t, wt("froad", "summer") - 0.3, None, "up")
    d = ImageDraw.Draw(im, "RGBA"); d.text((40, 1300), "ILLUSTRATION", font=MONO(18), fill=(255, 255, 255, 120)); return im
def s_sheep(t):
    lt = t - st("sheep"); ts = wt("sheep", "See") - 0.1
    if t < ts:
        a = photo("froad", lt, 3, (1.0, 1.15), (0.04, 0), 80); im = to_pil(a * 0.85)
        put(im, T("FREE-ROAMING", 130), W / 2, 380, t, wt("sheep", "roam") - 0.1, None, "up"); credit(im, "Sheep by the F208, Fjallabak · " + CRED.get("froad", "")); return im
    l2 = t - ts; a = rx.sand(t, 0, dark=0.8); im = to_pil(a); d = ImageDraw.Draw(im)
    d.polygon([(380, 280), (700, 280), (1080, 1300), (0, 1300)], fill=(46, 48, 52)); [d.rectangle((532, y, 548, y + 60), fill=(240, 240, 240)) for y in range(300 + int(l2 * 400) % 140 - 140, 1300, 140)]
    im.alpha_composite(sheep_draw(1.1, False, t * 9), (W - 400 - int(60 * rx.ease(l2 / 2)), 760))
    im.alpha_composite(sheep_draw(0.6, True, t * 9), (20 + int(30 * math.sin(t * 3)), 980))
    put(im, chip("lamb", AUR), 140, 950, t, wt("sheep", "lamb") - 0.1, None, "pop")
    sign = Image.new("RGBA", (360, 360), (0, 0, 0, 0)); sd = ImageDraw.Draw(sign); sd.polygon([(180, 8), (352, 180), (180, 352), (8, 180)], fill=YEL + (255,), outline=(20, 20, 20, 255)); sd.polygon([(180, 30), (330, 180), (180, 330), (30, 180)], outline=(20, 20, 20, 255), width=8)
    sign.alpha_composite(sheep_draw(0.55), (75, 100))
    put(im, sign, W / 2, 470, t, wt("sheep", "Slow") - 0.1, None, "slam", 0.2); kick(t, wt("sheep", "Slow"), 12)
    put(im, T("SLOW DOWN", 120, YEL), W / 2, 720, t, wt("sheep", "Slow"), None, "up")
    d = ImageDraw.Draw(im, "RGBA"); d.text((40, 1300), "ILLUSTRATION", font=MONO(18), fill=(255, 255, 255, 120)); return im
def s_stop(t):
    lt = t - st("stop"); tp = wt("stop", "pull-off") - 0.15
    if t < tp:
        a = photo("ring", lt, 2.6, (1.0, 1.15), (0, 0.02), 90); im = to_pil(a * 0.85)
        cx = W / 2 + 40 - 500 * (1 - rx.eout((t - st("stop")) / 1.2))
        im.alpha_composite(icon("car", 200, (250, 250, 250)), (int(cx - 100), 900))
        put(im, T("RING ROAD", 140), W / 2, 380, t, wt("stop", "Ring") - 0.05, None, "slam", 0.2)
        put(im, stamp("NOT HERE", RED, 100), W / 2, 640, t, wt("stop", "photo") - 0.05, None, "slam", 0.18); kick(t, wt("stop", "photo"), 14)
        credit(im, "Route 1, Mýrdalshreppur · " + CRED.get("ring", "")); return im
    l2 = t - tp; a = photo("ring2", l2, 2.6, (1.2, 1.05), (0, 0), 60); im = to_pil(a * 0.85)
    put(im, chip("Use a pull-off", AUR, "map-pin", 44), W / 2, 420, t, tp + 0.05, None, "pop"); credit(im, "Route 1 & Reynisfjall · " + CRED.get("ring2", "")); return im
APP = [("weather", "Yellow warning · wind", "Official IMO warning for your area", "alert-triangle", YEL),
       ("gusts", "Gusts 27 m/s nearby", "Road weather station · 9 km", "wind", BLUE),
       ("wave", "Wave height 5.1 m", "Sea forecast for the coast", "ripple", BLUE),
       ("road", "Road conditions", "Closures and slippery stretches ahead", "road", ACC),
       ("SafeTravel", "SafeTravel alert", "Official travel safety notices", "alert-triangle", RED)]
_LOGO = {}
def s_app(t):
    lt = t - st("app"); a = rx.basalt(t, AUR) * 0.45; a = rx.light_leak(a, t, 0.35, AUR); im = to_pil(a)
    if "l" not in _LOGO:
        lg = Image.open(os.path.join(P, "logo", "nordur-logo-horizontal-3840-white.png")).convert("RGBA"); _LOGO["l"] = lg.resize((420, round(lg.height * 420 / lg.width)), Image.LANCZOS)
    put(im, _LOGO["l"], W / 2, 260, t, st("app") - 0.1, None, "pop")
    for i, (wd, ti, su, ic, col) in enumerate(APP):
        t0 = wt("app", wd) - 0.15
        if put(im, card(ti, su, ic, col, 900, 150), W / 2, 420 + i * 175, t, t0, None, "right" if i % 2 else "left", 0.3) is not None: kick(t, t0 + 0.25, 5, 0.2)
    d = ImageDraw.Draw(im, "RGBA"); d.text((W / 2, 1310), "SAMPLE VALUES · ILLUSTRATION", font=MONO(18), fill=(255, 255, 255, 120), anchor="mm")
    return im
def s_end(t):
    lt = t - st("end"); tb = wt("end", "Because") - 0.1
    if t < tb:
        a = photo("cave", lt, 1.6, (1.0, 1.12), (0, 0), 50); im = to_pil(a * 0.7)
        put(im, T("CHECK BEFORE", 150), W / 2, 420, t, st("end"), None, "up"); put(im, T("YOU GO", 150, ACC), W / 2, 590, t, wt("end", "you") - 0.05, None, "up")
        credit(im, "Hálsanefshellir · " + CRED.get("cave", "")); return im
    a = vid(0.6) * np.array([1.0, 0.9, 0.88]) * 0.75; im = to_pil(a)          # same composition as frame 0 → loop
    put(im, T("THIS BEACH", 190), W / 2, 420, t, tb, None, "slam", 0.2); return im
def s_cta(t):
    lt = t - st("cta"); a = vid(0.6) * np.array([1.0, 0.9, 0.88]) * 0.75; im = to_pil(a)
    rk.cta(im, rx.eout(lt / 0.4), P, "Weather warnings, wind, roads and SafeTravel alerts for your Iceland trip.",
           "Photos & video: Wikimedia Commons (CC0, CC BY, CC BY-SA) · full credits in caption · graphics: Norður · AI voice")
    if t > TOTAL - 0.35:                                                     # dissolve back into frame 0 for a seamless loop
        k = (t - (TOTAL - 0.35)) / 0.35; return Image.blend(im, s_hook(0.0), rx.ease(k))
    return im
SC = {"hook": s_hook, "place": s_place, "sneak": s_sneak, "pull": s_pull, "lights": s_lights, "rule": s_rule, "turn": s_turn,
      "door": s_door, "froad": s_froad, "sheep": s_sheep, "stop": s_stop, "app": s_app, "end": s_end, "cta": s_cta}
TR = {"place": ("whip", 1), "sneak": ("zoom", 0), "pull": ("wave", 0), "lights": ("whip", -1), "rule": ("zoom", 0), "turn": ("wave", 0),
      "door": ("whip", 1), "froad": ("whip", -1), "sheep": ("whip", 1), "stop": ("whip", -1), "app": ("wave", 0), "end": ("zoom", 0)}
TW = 0.2
def scene_at(t):
    cur = max([i for i in ORDER if st(i) - TW <= t] or ["hook"], key=st)
    return cur
def render(i, t): return np.asarray(SC[i](t).convert("RGB"), np.float32)
VIG = rx.vignette_map()
def frame(fi):
    t = fi / FPS; SHAKE.clear()
    idx = ORDER.index(scene_at(t)) if t >= 0 else 0; cur = ORDER[idx]
    T0 = st(cur)
    if cur in TR and T0 - TW <= t < T0 + TW and idx > 0:
        p = (t - (T0 - TW)) / (2 * TW); a = render(ORDER[idx - 1], min(t, T0 - 0.01)); b = render(cur, max(t, T0))
        kind, dr = TR[cur]
        out = rx.whip(a, b, p, dr) if kind == "whip" else rx.zoom_cut(a, b, p) if kind == "zoom" else rx.wave_wipe(a, b, p, t)
    else:
        out = render(cur, t)
    if cur == "cta" and t < st("cta") + 0.01: pass
    if cur not in ("cta",): out = rx.light_leak(out, t, 0.12)
    out = rx.grain(out * VIG, fi, 6)
    out = rx.shake(out, fi, max(SHAKE) if SHAKE else 0)
    im = to_pil(out)
    if cur != "cta":
        g = Image.new("L", (1, 520)); [g.putpixel((0, y), int(190 * (y / 520) ** 1.5)) for y in range(520)]
        im.paste(Image.new("RGBA", (W, 520), (4, 6, 10, 255)), (0, H - 520), g.resize((W, 520)))
        captions(im, t)
    chapters(im, t)
    return im.convert("RGB")

# ——— sound design ———
def soundtrack(path):
    SR = rx.SR; n = int(TOTAL * SR)
    v, vsr = sf.read(os.path.join(V, "voice", "narration.wav"), dtype="float32")
    if v.ndim > 1: v = v.mean(1)
    v = np.interp(np.arange(int(len(v) * SR / vsr)) / SR, np.arange(len(v)) / vsr, v).astype(np.float32)
    voice = np.zeros(n, np.float32); voice[:min(n, len(v))] = v[:n]
    sfx = np.zeros(n, np.float32)
    for i, (kind, _) in TR.items(): rx.add(sfx, rx.whoosh(0.5 if kind == "whip" else 0.8, 250 if kind == "wave" else 400), st(i) - TW - 0.1, 0.55 if kind != "wave" else 0.7)
    for i in ("pull", "turn", "app"):
        if TR.get(i, ("",))[0] == "wave": rx.add(sfx, rx.surf_bed(1.6, 1.6), st(i) - 0.5, 0.5)
    hits = [wt("hook", "six"), wt("sneak", "surges") + 0.75, wt("pull", "brutal"), wt("pull", "swept") - 0.1, st("lights") + 0.2, wt("lights", "Red"),
            wt("rule", "never"), wt("turn", "Four"), wt("door", "gust") + 0.15, wt("froad", "F-road"), wt("froad", "law"), wt("sheep", "Slow"), wt("stop", "photo")]
    for h in hits: rx.add(sfx, rx.impact(), h, 0.62)
    for h in (wt("lights", "Yellow"), wt("lights", "Red")): rx.add(sfx, rx.ping(1.1, 987.8), h, 0.5)
    for w in ("weather", "gusts", "wave", "road", "SafeTravel"): rx.add(sfx, rx.ping(0.7, 1318.5), wt("app", w) - 0.05, 0.32)
    for w in ("Most",): rx.add(sfx, rx.ping(0.8, 659.3), wt("sneak", w), 0.35)
    for k in range(5): rx.add(sfx, rx.tick(), 0.45 + k * 0.25, 0.6)                       # counter ticks 0→5
    for i in ("turn", "app", "lights"): rx.add(sfx, rx.riser(1.6), st(i) - 1.6, 0.4)
    surf = rx.surf_bed(st("turn") + 1.0, 5.5, (wt("sneak", "surges") - 0.2, wt("sneak", "surges") + 1.2))
    sfx[:len(surf)] += surf * np.clip(np.arange(len(surf)) / SR / 0.2, 0, 1) * np.clip((st("turn") + 1.0 - np.arange(len(surf)) / SR) / 1.0, 0, 1) * 0.30
    wind = rx.wind_bed(TOTAL); wm = np.zeros(n, np.float32); tt = np.arange(n) / SR
    wm += np.clip((tt - st("door") + 0.3) / 0.5, 0, 1) * np.clip((st("froad") - tt) / 0.5, 0, 1) * 0.42
    wm += np.clip((st("place") - tt) / 1.0, 0, 1) * 0.25
    gst = wt("door", "gust"); wm += np.exp(-((tt - gst) / 0.35) ** 2) * 0.5
    sfx += wind[:n] * wm
    mus = rx.music(TOTAL)[:n]
    env = rx.envelope(voice); duck = 1 - 0.62 * np.clip(env / 0.06, 0, 1)
    duck = np.convolve(duck, np.ones(int(0.12 * SR)) / int(0.12 * SR), "same")
    mus *= 0.22 * duck * np.clip(tt / 0.3, 0, 1) * np.clip((TOTAL - tt) / 0.6, 0, 1)
    sfx *= (1 - 0.35 * np.clip(env / 0.06, 0, 1))
    mix = voice * 0.92 + sfx * 0.55 + mus
    mix = np.tanh(mix * 1.1) / np.tanh(1.1)                              # soft limiter
    mix = mix / np.abs(mix).max() * 0.89                                  # −1 dBFS peak
    sf.write(path, np.stack([mix, mix], 1), SR, subtype="PCM_16")
    rms = 20 * np.log10(np.sqrt(np.mean(mix ** 2))); print("mix peak", round(20 * np.log10(np.abs(mix).max()), 2), "dBFS · RMS", round(rms, 1), "dBFS")

tmp = os.path.join(OUT, "reynis-silent.mp4")
if TEST and TEST[0] == "audio": soundtrack(os.path.join(OUT, "reynis-mix.wav")); sys.exit()
if TEST and TEST[0] == "chunk":                                         # chunk i n → part file (render in parallel, then concat)
    i, nn = int(TEST[1]), int(TEST[2]); N = int(TOTAL * FPS); a, b = N * i // nn, N * (i + 1) // nn
    pr = rk.writer(os.path.join(OUT, f"reynis-part{i}.mp4"))
    for fi in range(a, b): pr.stdin.write(frame(fi).tobytes())
    pr.stdin.close(); pr.wait(); sys.exit()
if TEST and TEST[0] == "mux":
    with open(os.path.join(OUT, "parts.txt"), "w") as fl: fl.writelines(f"file 'reynis-part{i}.mp4'\n" for i in range(int(TEST[1])))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", os.path.join(OUT, "parts.txt"), "-c", "copy", tmp]); TEST = []
else: rk.run(frame, TOTAL, tmp, TEST)
if not TEST:
    wav = os.path.join(OUT, "reynis-mix.wav"); soundtrack(wav)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-i", wav, "-c:v", "copy", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac", "-b:a", "192k", "-shortest", os.path.join(OUT, "reynisfjara-sneaker-waves.mp4")])
    print("muxed")
