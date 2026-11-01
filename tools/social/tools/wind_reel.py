"""Reel: Iceland's wind, real ERA5 data of the 6 Feb 2025 storm, as moving particles over shaded relief."""
import sys, os, json, math, subprocess, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
TEST = sys.argv[4:]          # frame numbers to dump as png instead of video
W, H, FPS = 1080, 1920, 30
F = lambda n, s: ImageFont.truetype(f"{FONTS}/{n}.woff", s)
COND = lambda s: F("BarlowCondensed-Bold", s); SANS = lambda s: F("IBMPlexSans-SemiBold", s); MONO = lambda s: F("IBMPlexMono-SemiBold", s)
TEXT = (246, 246, 242); DIM = (190, 196, 200); ACCENT = (255, 90, 31)

# ——— basemap: full-frame Mercator box centred on Iceland ———
Z = 7; LON0, LON1 = -25.6, -12.0
x0, _ = geo.lonlat_to_px(LON0, 65, Z); x1, _ = geo.lonlat_to_px(LON1, 65, Z)
pxw = x1 - x0; pxh = pxw * H / W
_, yc = geo.lonlat_to_px(0, 64.75, Z)
def px_to_lat(y):
    n = 2 ** Z * 256; t = math.pi * (1 - 2 * y / n); return math.degrees(math.atan(math.sinh(t)))
LAT1, LAT0 = px_to_lat(yc - pxh / 2 + 120), px_to_lat(yc + pxh / 2 + 120)   # shift so Iceland sits a bit higher
cache = os.path.join(P, "geo", "base-wind.png")
if not os.path.exists(cache):
    e, _ = geo.dem(LON0, LAT0, LON1, LAT1, Z)
    im, land = geo.shade(e, (W, H), cellsize=pxw / W * 1200 / 2)
    im.save(cache); np.save(cache + ".land.npy", land)
base = np.asarray(Image.open(cache).convert("RGB")).astype(np.float32)
land = np.load(cache + ".land.npy")
gx0, gy0 = geo.lonlat_to_px(LON0, LAT1, Z); gx1, gy1 = geo.lonlat_to_px(LON1, LAT0, Z)
def to_lonlat(px, py):
    lon = LON0 + px / W * (LON1 - LON0)
    gy = gy0 + py / H * (gy1 - gy0)
    n = 2 ** Z * 256; lat = np.degrees(np.arctan(np.sinh(np.pi * (1 - 2 * gy / n))))
    return lon, lat
def to_px(lon, lat):
    x, y = geo.lonlat_to_px(lon, lat, Z)
    return (x - gx0) / (gx1 - gx0) * W, (y - gy0) / (gy1 - gy0) * H

# ——— wind field ———
D = json.load(open(os.path.join(P, "geo", "wind-feb2025.json")))
lats, lons, times = np.array(D["lats"]), np.array(D["lons"]), D["times"]
nla, nlo, nt = len(lats), len(lons), len(times)
spd = np.array(D["speed"]).reshape(nla, nlo, nt); dr = np.radians(np.array(D["dir"]).reshape(nla, nlo, nt))
gst = np.array(D["gust"]).reshape(nla, nlo, nt)
U = -spd * np.sin(dr); V = -spd * np.cos(dr)
def sample(field, lon, lat, th):
    fi = np.clip((lat - lats[0]) / (lats[1] - lats[0]), 0, nla - 1.001); fj = np.clip((lon - lons[0]) / (lons[1] - lons[0]), 0, nlo - 1.001)
    i0 = fi.astype(int); j0 = fj.astype(int); a = fi - i0; b = fj - j0
    t0 = int(min(th, nt - 1.001)); c = th - t0
    def at(t): return (field[i0, j0, t] * (1 - a) * (1 - b) + field[i0 + 1, j0, t] * a * (1 - b) + field[i0, j0 + 1, t] * (1 - a) * b + field[i0 + 1, j0 + 1, t] * a * b)
    return at(t0) * (1 - c) + at(t0 + 1) * c
# land grid points (for "strongest gust on land")
gl = np.zeros((nla, nlo), bool)
for i, la in enumerate(lats):
    for j, lo in enumerate(lons):
        x, y = to_px(lo, la)
        if 0 <= x < W and 0 <= y < H: gl[i, j] = land[int(y), int(x)]
# colour scale (m/s)
STOPS = [(0, (120, 150, 160)), (8, (170, 230, 215)), (12, (61, 224, 168)), (15, (242, 200, 40)), (20, (255, 140, 30)), (25, (255, 59, 48)), (30, (215, 70, 230)), (40, (255, 170, 255))]
def colour(s):
    s = np.asarray(s)[..., None]
    out = np.zeros(s.shape[:-1] + (3,), np.float32)
    for (a, ca), (b, cb) in zip(STOPS, STOPS[1:]):
        k = np.clip((s - a) / (b - a), 0, 1)
        m = (s >= a) & (s < b)
        out = np.where(m, np.array(ca) * (1 - k) + np.array(cb) * k, out)
    return np.where(s >= STOPS[-1][0], np.array(STOPS[-1][1], np.float32), out)

# ——— timeline ———
T0 = times.index("2025-02-05T06:00")
STORM = 17.0; Q = 2.6; CTA = 3.4; TOTAL = STORM + Q + CTA
HOURS = 40.0
def hour_at(t): return T0 + min(t, STORM + Q) / STORM * HOURS if t < STORM else T0 + HOURS + (t - STORM) * 0.6
# peak land gust over the playback
peak_v, peak_h = 0, 0
for h in range(T0, T0 + int(HOURS)):
    m = np.max(np.where(gl, gst[:, :, h], 0))
    if m > peak_v: peak_v, peak_h = m, h
PEAK_T = (peak_h - T0) / HOURS * STORM
print("peak land gust", peak_v, times[peak_h], "at t", round(PEAK_T, 1))

# ——— particles ———
rng = np.random.default_rng(7)
N = 3200
px = rng.uniform(0, W, N); py = rng.uniform(0, H, N); age = rng.integers(0, 90, N)
trail = np.zeros((H, W, 3), np.float32)
K = 0.42                        # px per frame per m/s

def shadow_text(img, text, y, f, fill=TEXT, center=True, x=None):
    d = ImageDraw.Draw(img)
    w = d.textlength(text, font=f); x = (W - w) / 2 if center else x
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0)); ImageDraw.Draw(lay).text((x, y), text, font=f, fill=(0, 0, 0, 230))
    img.alpha_composite(lay.filter(ImageFilter.GaussianBlur(9)))
    ImageDraw.Draw(img).text((x, y), text, font=f, fill=fill)
def wrap(d, text, f, width):
    out, line = [], ""
    for w_ in text.split():
        t = (line + " " + w_).strip()
        if d.textlength(t, font=f) <= width or not line: line = t
        else: out.append(line); line = w_
    return out + [line]
def block(img, text, y, size, fill=TEXT, k=1.0):
    d = ImageDraw.Draw(img); f = COND(size)
    for i, ln in enumerate(wrap(d, text, f, 960)):
        shadow_text(img, ln, y + i * round(size * 1.05) + (1 - k) * 24, f, fill)
    return y + len(wrap(d, text, f, 960)) * round(size * 1.05)
def ease(x): x = max(0, min(1, x)); return x * x * (3 - 2 * x)
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
import datetime
logo = Image.open(os.path.join(P, "logo", "nordur-logo-horizontal-3840-white.png")).convert("RGBA")
logo = logo.crop(logo.getbbox()); lw = 560; logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)

def frame(fi):
    global px, py, age, trail
    t = fi / FPS; th = hour_at(t)
    lon, lat = to_lonlat(px, py)
    u = sample(U, lon, lat, th); v = sample(V, lon, lat, th); s = np.hypot(u, v)
    nx = px + u * K; ny = py - v * K
    trail *= 0.86
    col = colour(s)
    for i in range(N):
        if age[i] > 2:
            cv2.line(trail, (int(px[i] * 4), int(py[i] * 4)), (int(nx[i] * 4), int(ny[i] * 4)), tuple(float(c) for c in col[i]), 1, cv2.LINE_AA, 2)
    px, py = nx, ny; age += 1
    dead = (px < 0) | (px >= W) | (py < 0) | (py >= H) | (age > 70 + (np.arange(N) % 40))
    px[dead] = rng.uniform(0, W, dead.sum()); py[dead] = rng.uniform(0, H, dead.sum()); age[dead] = 0
    img = np.clip(base * 1.05 + trail * 1.05, 0, 255).astype(np.uint8)
    im = Image.fromarray(img).convert("RGBA")
    d = ImageDraw.Draw(im, "RGBA")
    # top gradient for text
    g = Image.new("L", (1, 560)); [g.putpixel((0, y), int(200 * (1 - y / 560) ** 1.3)) for y in range(560)]
    im.alpha_composite(Image.new("RGBA", (W, 560), (4, 8, 12, 255)), (0, 0)) if False else im.paste(Image.new("RGBA", (W, 560), (4, 8, 12, 255)), (0, 0), g.resize((W, 560)))
    gb = g.resize((W, 560)).transpose(Image.FLIP_TOP_BOTTOM)
    im.paste(Image.new("RGBA", (W, 560), (4, 8, 12, 255)), (0, H - 560), gb)
    # live data panel
    if t < STORM + Q:
        hh = min(th, nt - 1.001); h0 = int(hh)
        dt = datetime.datetime.fromisoformat(times[h0]) + datetime.timedelta(hours=hh - h0)
        clock = f"{DAYS[dt.weekday()].upper()} {dt.day} FEB 2025 · {dt.hour:02d}:{(dt.minute // 10) * 10:02d}"
        shadow_text(im, clock, 1352, MONO(30), DIM, center=False, x=64)
        gnow = sample(gst, *np.meshgrid(lons, lats), hh) if False else None
        cur = gst[:, :, h0] * (1 - (hh - h0)) + gst[:, :, min(h0 + 1, nt - 1)] * (hh - h0)
        m = float(np.max(np.where(gl, cur, 0))); ij = np.unravel_index(np.argmax(np.where(gl, cur, 0)), cur.shape)
        shadow_text(im, "STRONGEST GUST ON LAND", 1400, MONO(24), DIM, center=False, x=64)
        cc = tuple(int(c) for c in colour(m))
        shadow_text(im, f"{m:.0f} m/s", 1428, COND(110), cc, center=False, x=64)
        shadow_text(im, f"{m * 3.6:.0f} km/h", 1462, COND(56), TEXT, center=False, x=400)
        # marker on the map where it is
        mx, my = to_px(lons[ij[1]], lats[ij[0]])
        r = 18 + 10 * (0.5 + 0.5 * math.sin(t * 6))
        d.ellipse((mx - r, my - r, mx + r, my + r), outline=cc + (255,), width=4)
        d.ellipse((mx - 6, my - 6, mx + 6, my + 6), fill=cc + (255,))
        # legend
        lx, ly, lw_ = 640, 1450, 376
        for k_ in range(lw_):
            d.line((lx + k_, ly, lx + k_, ly + 14), fill=tuple(int(c) for c in colour(5 + 30 * k_ / lw_)) + (255,))
        for val in (10, 20, 30):
            xx = lx + (val - 5) / 30 * lw_; d.text((xx - 12, ly + 22), str(val), font=MONO(22), fill=DIM)
        d.text((lx + lw_ - 40, ly - 34), "m/s", font=MONO(22), fill=DIM)
    # captions
    if t < 3.4: block(im, "This is Iceland's wind.", 300, 104, k=ease(t / 0.3)); shadow_text(im, "Real data · the storm of 5–6 February 2025", 425, SANS(40), DIM)
    elif t < PEAK_T - 1.2: block(im, "Every line is real wind, hour by hour.", 300, 92, k=ease((t - 3.4) / 0.3))
    elif t < PEAK_T + 3.0:
        block(im, f"Gusts of {peak_v:.0f} m/s.", 290, 120, ACCENT, k=ease((t - PEAK_T + 1.2) / 0.3))
        shadow_text(im, f"That's {peak_v * 3.6:.0f} km/h.", 430, COND(80))
    elif t < STORM: block(im, "Red warnings. Roads closed. Flights cancelled.", 300, 92, k=1)
    elif t < STORM + Q:
        y = block(im, "Would you have driven?", 300, 120, k=ease((t - STORM) / 0.3)); shadow_text(im, "Tell me in the comments", y + 14, SANS(44), DIM)
    else:
        k = ease((t - STORM - Q) / 0.5)
        ov = Image.new("RGBA", (W, H), (6, 9, 13, int(225 * k))); im.alpha_composite(ov)
        if k > 0.2:
            im.alpha_composite(logo, ((W - logo.width) // 2, 640))
            block(im, "Norður warns you before you get in the car.", 820, 78)
            shadow_text(im, "JOIN THE WAITLIST", 1060, MONO(44), ACCENT)
            shadow_text(im, "nordur.info", 1120, COND(150))
            shadow_text(im, "Data: ERA5 (Copernicus) via Open-Meteo · relief: Mapzen Terrain Tiles", 1490, MONO(20), DIM)
    return im.convert("RGB")

n = int(TOTAL * FPS)
if TEST:
    want = set(int(x) for x in TEST)
    for fi in range(max(want) + 1):
        im = frame(fi)
        if fi in want: im.save(os.path.join(OUT, f"test-{fi}.png"))
else:
    os.makedirs(OUT, exist_ok=True)
    pr = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium", "-movflags", "+faststart", os.path.join(OUT, "wind-storm.mp4")], stdin=subprocess.PIPE)
    for fi in range(n): pr.stdin.write(frame(fi).tobytes())
    pr.stdin.close(); pr.wait(); print("done", n)
