"""'This crack is tearing Iceland in two' — narrated reel, stylised paper-cut maps + real footage."""
import sys, os, json, math, subprocess, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo, paper, reelkit as rk
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
R = os.path.join(P, "rift"); A = os.path.join(P, "avatar")
TL = {l["id"]: l for l in json.load(open(os.path.join(A, "timeline.json")))}
ORDER = [l["id"] for l in json.load(open(os.path.join(A, "timeline.json")))]
def st(i): return TL[i]["start"]
def en(i): return TL[i]["start"] + TL[i]["dur"]
TOTAL = en("cta") + 1.0
ease = rk.ease

DARK_LAND = [(0, (52, 70, 66)), (80, (58, 76, 70)), (250, (66, 82, 76)), (500, (78, 90, 84)), (750, (92, 100, 96)),
             (1000, (108, 114, 112)), (1200, (176, 192, 204)), (1450, (206, 218, 228)), (1750, (232, 238, 244))]
DARK_SEA = [(-3000, (6, 10, 16)), (-1500, (8, 14, 22)), (-600, (10, 18, 28)), (-200, (13, 24, 36)), (-60, (17, 30, 44))]
class Base:
    def __init__(self, name, lon0, lat0, lon1, lat1, z, fade=True, **kw):
        self.z = z; self.zk = 2.0 ** (8 - z); self.x0, self.y0 = geo.lonlat_to_px(lon0, lat1, z)
        c = os.path.join(R, f"paper-{name}.png")
        if not os.path.exists(c):
            e, _ = geo.dem(lon0, lat0, lon1, lat1, z)
            Image.fromarray(paper.papercut(e, (e.shape[1], e.shape[0]), **kw).astype(np.uint8)).save(c)
        self.img = np.asarray(Image.open(c).convert("RGB")).astype(np.float32); self.h, self.w = self.img.shape[:2]
        self.edge = np.array(kw.get("sea", paper.SEA)[0][1], np.float32)
        yy, xx = np.mgrid[0:self.h, 0:self.w]; dd = np.minimum(np.minimum(xx, self.w - 1 - xx), np.minimum(yy, self.h - 1 - yy)).astype(np.float32)
        if fade:
            f = np.clip(dd / (220 / self.zk), 0, 1)[..., None]
            self.img = self.img * f + self.edge * (1 - f)
        self.alpha = np.clip(dd / 220, 0, 1).astype(np.float32)
    def px(self, lon, lat):
        x, y = geo.lonlat_to_px(lon, lat, self.z); return x - self.x0, y - self.y0
ICE = Base("ice9dark", -25.8, 62.9, -12.4, 66.9, 9, land=DARK_LAND, sea=DARK_SEA, shadow=(10, 13), soft=10)
def _dark(e):
    for (a, ca), (b, cb) in zip(DARK_LAND, DARK_LAND[1:]):
        if e < b: k = (e - a) / (b - a); return tuple(int(x + (y - x) * k) for x, y in zip(ca, cb))
    return DARK_LAND[-1][1]
TH_LAND = [(100 + 7 * i, tuple(c + (5 if i % 2 else -3) for c in _dark(100 + 7 * i))) for i in range(31)] + [(330, _dark(330)), (450, _dark(450)), (650, _dark(650)), (900, _dark(900))]
TH_SEA = [(-3000, (8, 14, 22)), (-50, (10, 18, 28)), (-5, (13, 24, 36)), (60, (17, 30, 44))]
THING = Base("thing4dark", -21.20, 64.215, -20.98, 64.33, 13, fade=False, land=TH_LAND, sea=TH_SEA, shadow=(4, 6), soft=4, hill=0.45)

RIDGE = [(-27.4, 62.0), (-25.0, 63.1), (-22.72, 63.81), (-22.0, 63.93), (-21.3, 64.08), (-21.1, 64.27), (-20.2, 64.6), (-19.0, 64.75),
         (-18.0, 64.72), (-17.3, 64.62), (-16.75, 65.05), (-16.78, 65.7), (-16.75, 66.1), (-17.6, 66.6), (-18.6, 67.5)]
RPX = np.array([ICE.px(lo, la) for lo, la in RIDGE], np.float32)
wm = Image.new("L", (ICE.w, ICE.h), 0)
ImageDraw.Draw(wm).polygon([(-4000, ICE.h + 4000)] + [tuple(p) for p in RPX] + [(-4000, -4000)], fill=255)
WEST = np.asarray(wm.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255
LANDM = cv2.GaussianBlur((ICE.img[..., 0] > ICE.img[..., 2] + 8).astype(np.float32), (0, 0), 2)
ON_LAND = [i for i, (lo, la) in enumerate(RIDGE) if -22.8 <= lo <= -16.6 and 63.75 <= la <= 66.2]

def camera(base, cx, cy, zoom, tilt=0.0, gap=0.0):
    """Homography: base px → screen. zoom in z8 units (screen px per z8 px); gap shifts the image sideways in screen px."""
    zoom = zoom * base.zk
    A = np.array([[zoom, 0, W / 2 - cx * zoom + gap], [0, zoom, H / 2 - cy * zoom], [0, 0, 1]], np.float32)
    s = tilt * W * 0.5
    src = np.float32([[0, 0], [W, 0], [W, H], [0, H]]); dst = np.float32([[s, H * tilt * 0.18], [W - s, H * tilt * 0.18], [W + s * 0.25, H], [-s * 0.25, H]])
    return cv2.getPerspectiveTransform(src, dst) @ A
def warp(img, Hm, border=cv2.BORDER_REPLICATE, val=None):
    if val is not None: return cv2.warpPerspective(img, Hm, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=val)
    return cv2.warpPerspective(img, Hm, (W, H), flags=cv2.INTER_LINEAR, borderMode=border)
SEAC = tuple(float(c) for c in DARK_SEA[0][1])
def pts(Hm, arr):
    return cv2.perspectiveTransform(np.asarray(arr, np.float32).reshape(-1, 1, 2), Hm).reshape(-1, 2)
def sky(img, tilt):
    if tilt <= 0.01: return img
    hh = int(H * tilt * 0.18) + 40
    g = np.linspace(1, 0, hh)[:, None, None] ** 1.5
    img[:hh] = img[:hh] * (1 - g) + np.array([7, 9, 12]) * g
    return img

def iceland(cx, cy, zoom, tilt, gap, t, glow=1.0, line=1.0, tint=0.0):
    """The paper map, optionally split along the ridge with lava in between."""
    Hw = camera(ICE, cx, cy, zoom, tilt, -gap); He = camera(ICE, cx, cy, zoom, tilt, gap)
    if gap < 0.3:
        out = warp(ICE.img, Hw, val=SEAC); hole = np.zeros((H, W, 1), np.float32)
        wmask = warp(WEST, Hw)[..., None]
    else:
        wi, ei = warp(ICE.img, Hw, val=SEAC), warp(ICE.img, He, val=SEAC)
        wmask = warp(WEST, Hw)[..., None]; emask = 1 - warp(WEST, He)[..., None]
        out = wi * wmask + ei * emask
        hole = np.clip(1 - wmask - emask, 0, 1)
        fl = 0.9 + 0.1 * math.sin(t * 14)
        lava = np.empty_like(out); lava[...] = (255, 90, 31)
        core = np.clip(hole * 1.6 - 0.3, 0, 1)
        out = out * (1 - hole) + (lava * hole + np.array([255, 220, 120]) * core * 0.6) * fl
        out += np.array([255, 110, 30]) * cv2.GaussianBlur(hole, (0, 0), 18)[..., None] * 0.6 * glow
    if tint > 0:
        lm = warp(LANDM, Hw, val=0)[..., None] * 0.32 * tint
        out = out * (1 - lm) + (np.array([120, 170, 255]) * wmask + np.array([61, 224, 168]) * (1 - wmask)) * lm
    Hm = camera(ICE, cx, cy, zoom, tilt)
    out = sky(out, tilt)
    return np.clip(out, 0, 255), Hm

def glow_line(im, p, width=10, col=(255, 90, 31), core=(255, 214, 170), dash=False):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    p = [tuple(map(float, q)) for q in p]
    if len(p) < 2: return
    if dash:
        for a, b in zip(p, p[1:]):
            L = math.dist(a, b); n = max(1, int(L / 26))
            for k in range(0, n, 2):
                u0, u1 = k / n, min(1, (k + 1) / n)
                d.line([(a[0] + (b[0] - a[0]) * u0, a[1] + (b[1] - a[1]) * u0), (a[0] + (b[0] - a[0]) * u1, a[1] + (b[1] - a[1]) * u1)], fill=core + (255,), width=width // 2)
        im.alpha_composite(lay); return
    d.line(p, fill=col + (255,), width=width * 2, joint="curve")
    im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(width)))
    ImageDraw.Draw(im).line(p, fill=core + (255,), width=max(3, width // 3), joint="curve")

def flag(im, x, y, w=96):
    """Flag of Iceland, official proportions 25×18 (7-1-2-1-14 / 7-1-2-1-7)."""
    u = w / 25; h = 18 * u
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    d.rounded_rectangle((x + 3, y + 6, x + w + 3, y + h + 6), 6, fill=(0, 0, 0, 120)); lay = lay.filter(ImageFilter.GaussianBlur(5)); d = ImageDraw.Draw(lay)
    d.rectangle((x, y, x + w, y + h), fill=(2, 82, 156))
    d.rectangle((x + 7 * u, y, x + 11 * u, y + h), fill=(255, 255, 255)); d.rectangle((x, y + 7 * u, x + w, y + 11 * u), fill=(255, 255, 255))
    d.rectangle((x + 8 * u, y, x + 10 * u, y + h), fill=(220, 30, 53)); d.rectangle((x, y + 8 * u, x + w, y + 10 * u), fill=(220, 30, 53))
    im.alpha_composite(lay)
def country(im, Hm, a=1.0):
    """'ICELAND' written across the island, with its flag; Reykjavík and the ocean labelled."""
    x, y = pts(Hm, [ICE.px(-18.6, 64.98)])[0]
    d = ImageDraw.Draw(im, "RGBA"); f = COND(96); txt = "ICELAND"
    tw = d.textlength(txt, font=f) + 16 * 6
    xx = x - tw / 2 + 60
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
    cx = xx
    for ch in txt: dl.text((cx, y - 50), ch, font=f, fill=(0, 0, 0, int(220 * a))); cx += d.textlength(ch, font=f) + 16
    im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(8)))
    cx = xx
    for ch in txt: d.text((cx, y - 50), ch, font=f, fill=(255, 255, 255, int(255 * a))); cx += d.textlength(ch, font=f) + 16
    if a > 0.5: flag(im, int(xx - 130), int(y - 34), 104)
    rx, ry = pts(Hm, [ICE.px(-21.94, 64.146)])[0]
    d.ellipse((rx - 9, ry - 9, rx + 9, ry + 9), fill=(255, 255, 255, int(255 * a)), outline=(7, 9, 12, int(255 * a)), width=3)
    d.text((rx - 150, ry + 14), "Reykjavík", font=SANS(30), fill=(235, 238, 240, int(255 * a)))
def pill(im, text, x, y, fg=(18, 22, 28), bg=(255, 255, 255), size=34, anchor="c", a=1.0):
    d = ImageDraw.Draw(im, "RGBA"); f = SANS(size); tw = d.textlength(text, font=f); w, h = tw + size * 1.1, size * 1.75
    if anchor == "c": x -= w / 2
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
    dl.rounded_rectangle((x + 4, y + 8, x + w + 4, y + h + 8), h / 2, fill=(0, 0, 0, int(110 * a)))
    im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(8)))
    d.rounded_rectangle((x, y, x + w, y + h), h / 2, fill=bg + (int(255 * a),))
    d.text((x + size * 0.55, y + size * 0.3), text, font=f, fill=fg + (int(255 * a),))
def cartoon_arrow(im, x, y, dirx, col, a=1.0, L=190):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    x2 = x + dirx * L; poly = [(x, y - 16), (x2, y - 16), (x2, y - 40), (x2 + dirx * 54, y), (x2, y + 40), (x2, y + 16), (x, y + 16)]
    sh = [(px + 6, py + 10) for px, py in poly]
    d.polygon(sh, fill=(0, 0, 0, int(90 * a))); lay = lay.filter(ImageFilter.GaussianBlur(6)); d = ImageDraw.Draw(lay)
    d.polygon(poly, fill=col + (int(255 * a),), outline=(255, 255, 255, int(255 * a)), width=6)
    im.alpha_composite(lay)

def photo(path, t, z0, z1, fy0, fy1, dur, grade=1.0):
    im = Image.open(path).convert("RGB")
    k = ease(t / dur); z = z0 + (z1 - z0) * k; fy = fy0 + (fy1 - fy0) * k
    s = max(W / im.width, H / im.height) * z
    r = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x = (r.width - W) // 2; y = int((r.height - H) * fy)
    return ImageEnhance.Contrast(r.crop((x, y, x + W, y + H))).enhance(1.06).convert("RGBA")
_photo_cache = {}
def photo_c(path, t, *a):
    key = (path,) + a[:4]
    if key not in _photo_cache: _photo_cache[key] = Image.open(path).convert("RGB")
    return photo(path, t, *a)
class Clip:
    def __init__(self, path, start, n, vf):
        p = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(start), "-i", path, "-vf", vf + ",fps=30,format=rgb24", "-frames:v", str(n), "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
        raw = p.stdout.read(); p.wait(); self.f = [np.frombuffer(raw[i * W * H * 3:(i + 1) * W * H * 3], np.uint8).reshape(H, W, 3) for i in range(len(raw) // (W * H * 3))]
    def at(self, t): return self.f[min(int(t * FPS), len(self.f) - 1)]
V2 = os.path.join(R, "v2.webm")
VF = f"scale=-2:{H},crop={W}:{H}"
CL = {"top": Clip(V2, 42.2, 130, f"scale=-2:{int(H*1.0)},crop={W}:{H}"),
      "a": Clip(V2, 57.5, 150, VF), "b": Clip(V2, 86.0, 150, VF)}

def section(im, t, rise):
    """Cartoon cross-section: ridge under the ocean, Iceland rising above sea level."""
    x0, y0, w, h = 70, 1010, W - 140, 330
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    d.rounded_rectangle((x0, y0, x0 + w, y0 + h), 30, fill=(12, 16, 22, 240), outline=(40, 48, 58, 255), width=2)
    sea = y0 + 110
    d.rectangle((x0 + 20, sea, x0 + w - 20, y0 + h - 20), fill=(20, 40, 60, 255))
    xs = np.linspace(x0 + 20, x0 + w - 20, 200); u = (xs - xs[0]) / (xs[-1] - xs[0])
    floor = y0 + h - 40 - 120 * np.exp(-((u - 0.5) / 0.18) ** 2) - 18 * np.sin(u * 40) * np.exp(-((u - 0.5) / 0.3) ** 2)
    isl = rise * 150 * np.exp(-((u - 0.5) / 0.06) ** 2)
    top = floor - isl
    poly = [(xs[0], y0 + h - 20)] + list(zip(xs, top)) + [(xs[-1], y0 + h - 20)]
    d.polygon(poly, fill=(78, 90, 84, 255))
    above = [(x, y) for x, y in zip(xs, top) if y < sea]
    if len(above) > 2: d.polygon([(above[0][0], sea)] + above + [(above[-1][0], sea)], fill=(61, 224, 168, 255))
    d.line((x0 + 20, sea, x0 + w - 20, sea), fill=(200, 230, 255, 200), width=3)
    im.alpha_composite(lay)
    d = ImageDraw.Draw(im, "RGBA")
    d.text((x0 + 36, y0 + 30), "CROSS-SECTION", font=MONO(26), fill=(200, 210, 220))
    d.text((x0 + 36, sea + 30), "Atlantic Ocean", font=SANS(28), fill=(200, 225, 245))
    mid = xs[100]; d.text((mid - 120, y0 + h - 70), "ridge · km below", font=SANS(26), fill=(255, 220, 190))
    if rise > 0.6: pill(im, "Iceland", mid, sea - 120, size=30, a=min(1, (rise - 0.6) / 0.3))

LANDGJ = json.load(open(os.path.join(R, "ne_110m_land.geojson")))["features"]
MAR = [(-17.5, 67.5), (-24, 62.5), (-29, 57), (-30, 52), (-28.5, 45), (-30, 38), (-36, 30), (-45, 22), (-46, 12), (-38, 6), (-28, 1), (-15, -6), (-13, -15), (-14, -27), (-13, -38), (-16, -48), (-10, -54)]
def globe(im, x, y, R_, rot, a=1.0):
    """Orthographic mini-globe centred over the North Atlantic, Iceland pulsing, ridge simplified."""
    lon0, lat0 = math.radians(-28 + rot), math.radians(38)
    def proj(lon, lat):
        lo, la = math.radians(lon), math.radians(lat)
        c = math.sin(lat0) * math.sin(la) + math.cos(lat0) * math.cos(la) * math.cos(lo - lon0)
        px = R_ * math.cos(la) * math.sin(lo - lon0); py = R_ * (math.cos(lat0) * math.sin(la) - math.sin(lat0) * math.cos(la) * math.cos(lo - lon0))
        return x + px, y - py, c > 0
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    d.ellipse((x - R_ - 6, y - R_ - 6, x + R_ + 6, y + R_ + 6), fill=(61, 224, 168, int(40 * a)))
    d.ellipse((x - R_, y - R_, x + R_, y + R_), fill=(14, 24, 36, int(250 * a)), outline=(70, 90, 110, int(255 * a)), width=2)
    for f in LANDGJ:
        g = f["geometry"]; polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for poly in polys:
            ring = [proj(lo, la) for lo, la in poly[0]]
            vis = [(px, py) for px, py, v in ring if v]
            if len(vis) > 2 and len(vis) > 0.6 * len(ring): d.polygon(vis, fill=(72, 86, 84, int(255 * a)))
    rp = [(px, py) for px, py, v in (proj(lo, la) for lo, la in MAR) if v]
    if len(rp) > 1: d.line(rp, fill=(255, 90, 31, int(255 * a)), width=3)
    ix, iy, v = proj(-18.6, 64.9)
    pr = 6 + 10 * (0.5 + 0.5 * math.sin(rot * 3))
    d.ellipse((ix - pr, iy - pr, ix + pr, iy + pr), outline=(255, 90, 31, int(200 * a)), width=3); d.ellipse((ix - 6, iy - 6, ix + 6, iy + 6), fill=(255, 255, 255, int(255 * a)))
    im.alpha_composite(lay)
    ImageDraw.Draw(im, "RGBA").text((x - R_, y + R_ + 14), "MID-ATLANTIC RIDGE (simplified)", font=MONO(16), fill=(170, 180, 190, int(255 * a)))
def graticule(im, Hm, a=1.0):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    for lat in np.arange(62.5, 68.0, 0.5):
        p = pts(Hm, [ICE.px(lo, lat) for lo in np.linspace(-27, -11, 40)]); d.line([tuple(q) for q in p], fill=(160, 190, 220, int(28 * a)), width=2)
        if lat % 1 == 0:
            q = p[2]; d.text((q[0] + 6, q[1] - 26), f"{int(lat)}°N", font=MONO(20), fill=(160, 190, 220, int(110 * a)))
    for lon in range(-27, -10, 1):
        p = pts(Hm, [ICE.px(lon, la) for la in np.linspace(62.4, 67.6, 30)]); d.line([tuple(q) for q in p], fill=(160, 190, 220, int(28 * a)), width=2)
    im.alpha_composite(lay)
def compass(im, x, y, a=1.0):
    d = ImageDraw.Draw(im, "RGBA")
    d.ellipse((x - 34, y - 34, x + 34, y + 34), outline=(200, 210, 220, int(160 * a)), width=2)
    d.polygon([(x, y - 30), (x - 9, y), (x + 9, y)], fill=(255, 90, 31, int(255 * a))); d.polygon([(x, y + 30), (x - 9, y), (x + 9, y)], fill=(200, 210, 220, int(200 * a)))
    d.text((x - 7, y - 66), "N", font=SANS(24), fill=(230, 235, 240, int(255 * a)))
def scalebar(im, Hm, x, y, km=100, a=1.0):
    p = pts(Hm, [ICE.px(-19.0, 65.0), ICE.px(-19.0 + km / (111.32 * math.cos(math.radians(65))), 65.0)])
    L = float(abs(p[1][0] - p[0][0])); d = ImageDraw.Draw(im, "RGBA")
    d.rectangle((x, y, x + L, y + 8), fill=(230, 235, 240, int(220 * a))); d.rectangle((x + L / 2, y, x + L, y + 8), fill=(60, 70, 80, int(220 * a)))
    d.text((x, y + 14), f"{km} km", font=MONO(20), fill=(200, 210, 220, int(220 * a)))
CHAPTERS = [("THE SEAM", "ridge", "plates"), ("THE PLATES", "plates", "wait"), ("THE CRACKS", "wait", "opens"), ("THE FIRE", "opens", "look")]
def chapters(im, t):
    if not (st("ridge") <= t < st("look")): return
    d = ImageDraw.Draw(im, "RGBA"); x0, y0, gap = 60, 150, 12; w = (W - 120 - gap * 3) / 4
    for i, (name, a, b) in enumerate(CHAPTERS):
        x = x0 + i * (w + gap); on = st(a) <= t < st(b); done = t >= st(b)
        k = 1.0 if done else (np.clip((t - st(a)) / (st(b) - st(a)), 0, 1) if on else 0)
        d.rounded_rectangle((x, y0, x + w, y0 + 8), 4, fill=(255, 255, 255, 60)); d.rounded_rectangle((x, y0, x + w * k, y0 + 8), 4, fill=(255, 90, 31, 255)) if k > 0.01 else None
        d.text((x, y0 + 16), name, font=MONO(20), fill=(255, 255, 255, 230 if on else 120))
_ic = {}
def ico(name, size):
    k = (name, size)
    if k not in _ic: _ic[k] = Image.open(os.path.join(P, "icons", name + ".png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    return _ic[k]
def chip(im, icon_name, text, x, y, a=1.0, bg=(255, 255, 255), fg=(12, 14, 18), col=(255, 90, 31)):
    """Stat chip: coloured icon disc + text, slides in from the left."""
    d = ImageDraw.Draw(im, "RGBA"); f = SANS(34); tw = d.textlength(text, font=f); h = 76; w = tw + h + 40
    x = x - (1 - a) * 60
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
    dl.rounded_rectangle((x + 4, y + 8, x + w + 4, y + h + 8), h / 2, fill=(0, 0, 0, int(120 * a))); im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(8)))
    d.rounded_rectangle((x, y, x + w, y + h), h / 2, fill=bg + (int(255 * a),))
    d.ellipse((x + 6, y + 6, x + h - 6, y + h - 6), fill=col + (int(255 * a),))
    ic = ico(icon_name, 40).copy(); ic.putalpha(ic.getchannel("A").point(lambda v: int(v * a))); im.alpha_composite(ic, (int(x + (h - 40) / 2), int(y + (h - 40) / 2)))
    d.text((x + h + 14, y + 17), text, font=f, fill=fg + (int(255 * a),))
_rng = np.random.default_rng(5)
EMB = [(_rng.uniform(0, W), _rng.uniform(H * 0.35, H), _rng.uniform(40, 140), _rng.uniform(2, 5)) for _ in range(45)]
BUB = [(_rng.uniform(80, W - 80), _rng.uniform(0, H), _rng.uniform(60, 160), _rng.uniform(4, 14)) for _ in range(70)]
def particles(im, t, kind):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    for x, y, v, r in (EMB if kind == "ember" else BUB):
        yy = (y - t * v) % H; xx = x + math.sin(t * 2 + y) * (10 if kind == "ember" else 6)
        if kind == "ember": d.ellipse((xx - r, yy - r, xx + r, yy + r), fill=(255, 140 + int(r * 10), 40, 200))
        else: d.ellipse((xx - r, yy - r, xx + r, yy + r), outline=(220, 240, 255, 150), width=2)
    if kind == "ember": im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(1.5)))
    im.alpha_composite(lay)

WORDS = []
for i in ORDER:
    l = TL[i]
    if i == "cta": continue
    ws = l["show"].split(); tot = sum(len(w) + 2 for w in ws); t0 = l["start"]
    for w in ws:
        d = l["dur"] * (len(w) + 2) / tot; WORDS.append((t0, t0 + d, w, l["start"], l["start"] + l["dur"])); t0 += d
def captions(im, t):
    cur = [w for w in WORDS if w[3] <= t < w[4] + 0.12]
    if not cur: return
    line = [w for w in WORDS if w[3] == cur[0][3]]
    k = next((i for i, w in enumerate(line) if w[0] <= t < w[1]), len(line) - 1)
    c0 = (k // 3) * 3; chunk = line[c0:c0 + 3]
    d = ImageDraw.Draw(im, "RGBA"); f = COND(104)
    txt = " ".join(w[2] for w in chunk); tw = d.textlength(txt, font=f); x = (W - tw) / 2; y = 1330
    pop = ease((t - chunk[0][0]) / 0.12)
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
    xx = x
    for j, w in enumerate(chunk):
        dl.text((xx, y), w[2], font=f, fill=(0, 0, 0, 255), stroke_width=10, stroke_fill=(0, 0, 0, 255)); xx += d.textlength(w[2] + " ", font=f)
    im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(6)))
    d = ImageDraw.Draw(im); xx = x
    for j, w in enumerate(chunk):
        on = c0 + j == k
        d.text((xx, y - (6 if on else 0) * pop), w[2], font=f, fill=(255, 90, 31) if on else (255, 255, 255), stroke_width=4, stroke_fill=(10, 10, 10))
        xx += d.textlength(w[2] + " ", font=f)

ICX, ICY = ICE.px(-18.7, 64.95)
TCX, TCY = THING.px(-21.11, 64.262)
def frame(fi):
    t = fi / FPS; shake = 0
    if t < st("swim"):                                      # hook
        k = t / en("hook")
        g = 0 if t < 1.0 else 26 * ease((t - 1.0) / 0.5)
        img, Hm = iceland(ICX, ICY + 200, 0.64 + 0.08 * k, 0.30, g, t)
        im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
        n = int(2 + ease((t - 0.25) / 0.7) * (len(ON_LAND) - 1)) if t > 0.25 else 0
        if n >= 2 and g < 2: glow_line(im, pts(Hm, RPX[ON_LAND[0]:ON_LAND[0] + n]), 10)
        if 1.0 < t < 1.7: shake = 12 * (1 - (t - 1.0) / 0.7)
        graticule(im, Hm)
        if t < 1.0: country(im, Hm, 1.0)
        globe(im, W - 170, 330, 120, t * 6)
    elif t < st("ridge"):                                   # people swim in it
        lt = t - st("swim")
        im = photo(os.path.join(R, "silfra1.jpg"), lt, 1.18, 1.06, 0.55, 0.45, 1.7)
        particles(im, lt, "bubble")
        chip(im, "scuba-diving", "Silfra · between the plates", 60, 260, ease(lt / 0.3))
    elif t < st("deep"):                                    # ridge
        lt = t - st("ridge"); k = ease(lt / 5.5)
        img, Hm = iceland(ICX, ICY + 60, 0.62 - 0.22 * k, 0.32 - 0.1 * k, 0, t)
        im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
        p = pts(Hm, RPX); n = max(2, int(2 + ease(lt / 2.5) * (len(p) - 2)))
        glow_line(im, p[:n], 9)
        graticule(im, Hm); compass(im, W - 90, 300); scalebar(im, Hm, 70, 1200)
        country(im, Hm, 1 - ease((lt - 2.0) / 0.4))
        globe(im, W - 170, 1000, 110, 20 + lt * 6, 1 - ease((lt - 4.0) / 0.6))
        if lt > 2.2: pill(im, "MID-ATLANTIC RIDGE", W / 2, 420, bg=(255, 90, 31), fg=(255, 255, 255), size=34, a=ease((lt - 2.2) / 0.3))
        d = ImageDraw.Draw(im); d.text((90, 1100), "ATLANTIC OCEAN", font=MONO(30), fill=(120, 150, 180))
    elif t < st("plates"):                                  # deep
        lt = t - st("deep")
        img, Hm = iceland(ICX - 240, ICY + 840, 0.46, 0.22, 0, t)
        im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
        p = pts(Hm, RPX); glow_line(im, p[:3], 7, dash=True); glow_line(im, p[2:13], 8); glow_line(im, p[12:], 7, dash=True)
        graticule(im, Hm)
        section(im, lt, ease((lt - 4.2) / 1.6))
        if lt > 1.2: chip(im, "ripple", "Ridge: ~2.5 km below sea level", 60, 860, ease((lt - 1.2) / 0.3), col=(120, 170, 255))
    elif t < st("rate"):                                    # plates
        lt = t - st("plates"); k = ease(lt / 1.0)
        img, Hm = iceland(ICX, ICY, 0.5, 0.3, 0, t, tint=k)
        im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
        graticule(im, Hm); compass(im, W - 90, 300)
        glow_line(im, pts(Hm, RPX), 8)
        a1 = ease((lt - 0.3) / 0.4); a2 = ease((lt - 2.2) / 0.4)
        if a1 > 0: cartoon_arrow(im, 420, 520, -1, (120, 170, 255), a1); pill(im, "North American Plate", 300, 600, size=32, a=a1)
        if a2 > 0: cartoon_arrow(im, 660, 760, 1, (61, 224, 168), a2); pill(im, "Eurasian Plate", 790, 840, size=32, a=a2)
    elif t < st("wait"):                                    # rate
        lt = t - st("rate")
        g = 4 + 26 * ease(lt / 3.6)
        img, Hm = iceland(ICX, ICY, 0.52, 0.3, g, t, tint=1.0)
        im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
        graticule(im, Hm)
        k = ease((lt - 1.2) / 1.2); txt = f"{2 * k:.1f} cm"; d = ImageDraw.Draw(im)
        if lt > 2.6: chip(im, "ruler-measure", "≈ 20 cm in 10 years · 2 m in a century", 60, 900, ease((lt - 2.6) / 0.3), col=(61, 224, 168))
        if lt > 1.0:
            pill(im, "per year", W / 2, 760, size=40, a=ease((lt - 1.2) / 0.3))
            f = COND(240); d.text(((W - d.textlength(txt, font=f)) / 2, 440), txt, font=f, fill=(255, 255, 255), stroke_width=10, stroke_fill=(20, 20, 20))
    elif t < st("thing"):                                   # wait → dive in
        lt = t - st("wait"); k = ease(lt / (st("thing") - st("wait")))
        u = ease(lt / 1.1)
        lon = -18.7 + (-21.11 + 18.7) * u; lat = 64.95 + (64.262 - 64.95) * u
        z = 0.5 * (46.4 / 0.5) ** k
        cx, cy = ICE.px(lon, lat)
        img, Hm = iceland(cx, cy, z, 0.30, 30 * (1 - ease(lt / 0.8)), t, tint=1 - ease(lt / 0.8))
        bl = float(np.clip((z - 14) / 12.0, 0, 1))
        if bl > 0:
            HT = camera(THING, *THING.px(lon, lat), z, 0.30)
            it = warp(THING.img, HT, val=SEAC); at = warp(THING.alpha, HT, val=0)[..., None] * bl
            img = sky(img * (1 - at) + it * at, 0.30)
        im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")
        if lt < 0.25: im.alpha_composite(Image.new("RGBA", (W, H), (255, 255, 255, int(120 * (1 - lt / 0.25)))))
    elif t < st("silfra"):                                  # Þingvellir
        lt = t - st("thing"); k = ease(lt / 4.0)
        Hm = camera(THING, TCX, TCY, 46.4 * (1 + 0.14 * k), 0.30)
        img = sky(warp(THING.img, Hm, val=SEAC), 0.30)
        im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")
        for name, lo, la, dy in (("Almannagjá", -21.1235, 64.2575, -110), ("Silfra", -21.1175, 64.2555, 40), ("Lake Þingvallavatn", -21.11, 64.215, 0)):
            x, y = pts(Hm, [THING.px(lo, la)])[0]
            if 0 < x < W and 200 < y < 1250:
                ImageDraw.Draw(im).ellipse((x - 10, y - 10, x + 10, y + 10), fill=(255, 196, 64), outline=(20, 20, 20), width=3)
                pill(im, name, x, y + dy, size=30)
        pill(im, "ÞINGVELLIR NATIONAL PARK", W / 2, 230, bg=(20, 26, 34), fg=(255, 255, 255), size=30)
        a = ease((lt - 0.6) / 0.4)
        if a > 0: cartoon_arrow(im, 330, 1150, -1, (120, 170, 255), a, L=150); cartoon_arrow(im, 750, 1150, 1, (61, 224, 168), a, L=150)
        if a > 0: pill(im, "N. American plate", 250, 1215, size=26, a=a); pill(im, "Eurasian plate", 830, 1215, size=26, a=a)
        compass(im, W - 90, 330)
    elif t < st("opens"):                                   # Silfra
        lt = t - st("silfra")
        im = photo(os.path.join(R, "silfra3.jpg"), lt, 1.08, 1.2, 0.85, 0.55, 9.5)
        for i, (ic_, txt, at, col) in enumerate((("snowflake", "Glacier water from Langjökull", 1.0, (120, 170, 255)), ("mountain", "Filtered through lava for decades", 3.0, (255, 90, 31)),
                                                  ("eye", "Visibility: 100+ metres", 5.6, (61, 224, 168)), ("temperature", "Water: 2–4 °C, all year", 7.2, (120, 170, 255)))):
            a = ease((lt - at) / 0.35)
            if a > 0: chip(im, ic_, txt, 60, 280 + i * 100, a, col=col)
    elif t < st("erupt"):                                   # it opens
        lt = t - st("opens")
        im = Image.fromarray(CL["top"].at(lt)).convert("RGBA"); particles(im, lt, "ember")
        if lt < 1.4: im.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(200 * (1 - lt / 1.4)))))
    elif t < st("look"):                                    # eruptions
        lt = t - st("erupt")
        im = Image.fromarray(CL["a"].at(lt) if lt < 3.9 else CL["b"].at(lt - 3.9)).convert("RGBA")
        particles(im, lt, "ember")
        chip(im, "volcano", "Fagradalsfjall, Reykjanes · 2021", 60, 250, ease(lt / 0.3))
        if lt > 3.9: chip(im, "flame", "Lava: over 1,000 °C", 60, 350, ease((lt - 3.9) / 0.3), col=(255, 90, 31))
    elif t < st("cta"):                                     # look down
        lt = t - st("look"); k = ease(lt / 5.5)
        img, Hm = iceland(ICX, ICY, 0.85 - 0.33 * k, 0.32, 10 + 12 * k, t, tint=ease(lt / 0.8))
        im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
        a1 = ease((lt - 0.6) / 0.4)
        if a1 > 0:
            pill(im, "NORTH AMERICA", W * 0.27, 470, bg=(120, 170, 255), fg=(7, 9, 12), size=36, a=a1)
            pill(im, "EUROPE", W * 0.76, 470, bg=(61, 224, 168), fg=(7, 9, 12), size=36, a=a1)
        x, y = pts(Hm, [ICE.px(-21.11, 64.262)])[0]
        a2 = ease((lt - 2.2) / 0.4)
        if a2 > 0:
            b = abs(math.sin(lt * 4)) * 12
            d = ImageDraw.Draw(im); d.ellipse((x - 13, y - 13, x + 13, y + 13), fill=(255, 90, 31), outline=(255, 255, 255), width=4)
            pill(im, "Þingvellir: one foot on each plate", x + 170, y + 50 + b, bg=(255, 90, 31), fg=(255, 255, 255), size=30, a=a2)
    else:                                                   # CTA
        lt = t - st("cta")
        img, Hm = iceland(ICX, ICY, 0.52, 0.32, 22, t)
        im = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
        rk.cta(im, ease(lt / 0.5), P, "Norður keeps an eye on the ground, the roads and the sky.",
               "Eruption footage: Peter Peter, CC BY 3.0 · Silfra: Thomei08, public domain; Delahanty, CC BY 4.0 · relief: Mapzen Terrain Tiles · ridge simplified, split exaggerated · AI voice")
    chapters(im, t)
    if t < st("cta"):
        g = Image.new("L", (1, 520)); [g.putpixel((0, y), int(190 * (y / 520) ** 1.5)) for y in range(520)]
        im.paste(Image.new("RGBA", (W, 520), (4, 6, 10, 255)), (0, H - 520), g.resize((W, 520)))
        captions(im, t)
    # cut punch: small zoom-in at the start of every line
    for i in ORDER:
        dt = t - st(i)
        if 0 <= dt < 0.18 and i not in ("hook", "cta"):
            z = 1 + 0.04 * (1 - dt / 0.18)
            im = im.resize((round(W * z), round(H * z)), Image.BILINEAR).crop(((round(W * z) - W) // 2, (round(H * z) - H) // 2, (round(W * z) - W) // 2 + W, (round(H * z) - H) // 2 + H))
    out = im.convert("RGB")
    if shake: out = Image.fromarray(np.roll(np.roll(np.asarray(out), int(math.sin(fi * 2.7) * shake), 1), int(math.cos(fi * 3.3) * shake * 0.6), 0))
    return out
tmp = os.path.join(OUT, "rift3-silent.mp4")
rk.run(frame, TOTAL, tmp, TEST)
if not TEST:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-i", os.path.join(A, "narration.wav"), "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", os.path.join(OUT, "iceland-torn-in-two-v3.mp4")])
    print("muxed")
