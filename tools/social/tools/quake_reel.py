"""Reel: the Grindavík earthquake swarm (Oct–Dec 2023), real EMSC catalogue, over shaded relief."""
import sys, os, json, math, datetime, numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo, reelkit as rk
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
Z = 11; LON0, LON1 = -22.80, -21.88
x0, _ = geo.lonlat_to_px(LON0, 64, Z); x1, _ = geo.lonlat_to_px(LON1, 64, Z)
pxw = x1 - x0; pxh = pxw * H / W
_, yc = geo.lonlat_to_px(0, 63.885, Z)
n = 2 ** Z * 256
def y2lat(y): return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
GY0, GY1 = yc - pxh / 2, yc + pxh / 2
LAT1, LAT0 = y2lat(GY0), y2lat(GY1)
cache = os.path.join(P, "geo", "base-quake.png")
if not os.path.exists(cache):
    e, _ = geo.dem(LON0, LAT0, LON1, LAT1, Z)
    im, _ = geo.shade(e, (W, H), cellsize=pxw / W * 20, hmax=600, ice_at=9999, exag=1.6)
    im.save(cache)
base = Image.open(cache).convert("RGBA")
def to_px(lon, lat):
    x, y = geo.lonlat_to_px(lon, lat, Z); return (x - x0) / pxw * W, (y - GY0) / pxh * H
Q = []
for f in json.load(open(os.path.join(P, "geo", "quakes-2023.json")))["features"]:
    p = f["properties"]; t = datetime.datetime.fromisoformat(p["time"].replace("Z", "+00:00")).replace(tzinfo=None)
    x, y = to_px(p["lon"], p["lat"])
    Q.append((t, p["mag"], x, y))
Q.sort()
D = datetime.datetime
# time warp: (video seconds, real datetime)
KEYS = [(0.0, D(2023, 10, 24)), (4.5, D(2023, 11, 9, 12)), (6.0, D(2023, 11, 10, 15)), (11.0, D(2023, 11, 11, 6)), (15.0, D(2023, 12, 18, 21)), (16.0, D(2023, 12, 18, 22, 17))]
def real(t):
    for (a, ra), (b, rb) in zip(KEYS, KEYS[1:]):
        if t <= b: return ra + (rb - ra) * ((t - a) / (b - a))
    return KEYS[-1][1]
def vt(rt):  # inverse: real → video time
    for (a, ra), (b, rb) in zip(KEYS, KEYS[1:]):
        if rt <= rb: return a + (b - a) * ((rt - ra) / (rb - ra))
    return KEYS[-1][0]
QV = [(vt(t), t, m, x, y) for t, m, x, y in Q if t <= KEYS[-1][1]]
ERUPT = 16.0; END = 22.0; CTA = 3.4; TOTAL = END + CTA
PLACES = [("Reykjavík", -21.9426, 64.1466), ("Keflavík Airport", -22.6056, 63.985), ("Blue Lagoon", -22.4495, 63.8804), ("Grindavík", -22.4338, 63.8424)]
FISSURE = [(-22.410, 63.866), (-22.400, 63.878), (-22.392, 63.889), (-22.384, 63.900)]   # Sundhnúkur crater row, 18 Dec 2023 (approx.)
def mcol(m):
    if m >= 4.5: return (255, 59, 48)
    if m >= 4.0: return (255, 140, 30)
    if m >= 3.5: return (242, 200, 40)
    return (255, 236, 200)
dots = Image.new("RGBA", (W, H), (0, 0, 0, 0))
done = [0]
shake = [0.0]
def frame(fi):
    t = fi / FPS; im = base.copy(); d = ImageDraw.Draw(im, "RGBA")
    # accumulated dots
    while done[0] < len(QV) and QV[done[0]][0] <= t:
        _, _, m, x, y = QV[done[0]]; r = 2 + (m - 2.8) * 2.2
        ImageDraw.Draw(dots).ellipse((x - r, y - r, x + r, y + r), fill=mcol(m) + (150,))
        if m >= 4.5: shake[0] = max(shake[0], 1.0)
        done[0] += 1
    im.alpha_composite(dots)
    # live rings for the last 1.2 s
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dg = ImageDraw.Draw(glow)
    for tv, _, m, x, y in QV[max(0, done[0] - 200):done[0]]:
        a = t - tv
        if 0 <= a < 1.2:
            k = a / 1.2; R = (14 + (m - 2.8) * 26) * (0.3 + 1.4 * k)
            dg.ellipse((x - R, y - R, x + R, y + R), outline=mcol(m) + (int(255 * (1 - k)),), width=4)
            dg.ellipse((x - 7, y - 7, x + 7, y + 7), fill=mcol(m) + (int(255 * (1 - k)),))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(1.2))); im.alpha_composite(glow)
    # eruption
    if t >= ERUPT:
        k = rk.ease((t - ERUPT) / 1.5)
        pts = [to_px(lo, la) for lo, la in FISSURE]
        seg = max(2, int(1 + k * (len(pts) - 1)) + 1)
        lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
        fl = 0.85 + 0.15 * math.sin(t * 17) * math.sin(t * 7)
        dl.line(pts[:seg], fill=(255, 120, 20, int(255 * fl)), width=60, joint="curve")
        im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(26))); im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(10)))
        ImageDraw.Draw(im).line(pts[:seg], fill=(255, 235, 170, 255), width=11, joint="curve")
    # place labels
    for name, lo, la in PLACES:
        x, y = to_px(lo, la); d.ellipse((x - 6, y - 6, x + 6, y + 6), fill=(255, 255, 255, 230))
        f = SANS(32); tw = ImageDraw.Draw(im).textlength(name, font=f)
        lx = x - tw - 14 if name in ("Reykjavík", "Blue Lagoon") else x + 14
        rk.shadow_text(im, name, y - 20, f, rk.TEXT, center=False, x=lx, blur=5)
    rk.gradients(im, 520, 600)
    # panel
    rt = real(min(t, ERUPT))
    cnt = done[0]; big = max([q[2] for q in QV[:cnt]] or [0])
    rk.shadow_text(im, rt.strftime("%-d %b %Y · %H:00").upper(), 1352, MONO(30), rk.DIM, center=False, x=64)
    rk.shadow_text(im, "EARTHQUAKES M2.8+", 1400, MONO(24), rk.DIM, center=False, x=64)
    rk.shadow_text(im, f"{cnt}", 1428, COND(110), rk.TEXT, center=False, x=64)
    rk.shadow_text(im, "LARGEST", 1400, MONO(24), rk.DIM, center=False, x=600)
    if big: rk.shadow_text(im, f"M{big:.1f}", 1428, COND(110), mcol(big), center=False, x=600)
    # captions
    if t < 4.3: y = rk.block(im, "Watch the ground under this town.", 260, 104, k=rk.ease(t / 0.3)); rk.shadow_text(im, "Grindavík, Iceland · real earthquake data", y + 16, SANS(40), rk.DIM)
    elif t < 6.0: rk.block(im, "10 November 2023.", 300, 112, k=rk.ease((t - 4.3) / 0.3))
    elif t < 11.0:
        y = rk.block(im, "Hundreds of quakes in one night.", 260, 104, rk.TEXT)
        if t > 7.5: rk.shadow_text(im, "The whole town is evacuated.", y + 12, COND(76), rk.ACCENT)
    elif t < ERUPT: rk.block(im, "Five weeks later…", 300, 112, k=rk.ease((t - 11) / 0.3))
    elif t < 19.0: rk.block(im, "18 December: the ground opens.", 260, 104, rk.ACCENT, k=rk.ease((t - ERUPT) / 0.3))
    elif t < END: y = rk.block(im, "It has erupted again many times since.", 260, 96); rk.shadow_text(im, "Would you still visit? Tell me below", y + 16, SANS(40), rk.DIM)
    else: rk.cta(im, rk.ease((t - END) / 0.5), P, "Quakes, eruptions and closed roads, where you are.", "Data: EMSC earthquake catalogue (M2.8+) · relief: Mapzen Terrain Tiles · eruption fissure position approximate")
    out = im.convert("RGB")
    if shake[0] > 0.02:
        s = shake[0]; dx = int(math.sin(fi * 2.3) * 14 * s); dy = int(math.cos(fi * 3.1) * 10 * s)
        out = Image.fromarray(np.roll(np.roll(np.asarray(out), dy, 0), dx, 1)); shake[0] *= 0.82
    return out
rk.run(frame, TOTAL, os.path.join(OUT, "grindavik-quakes.mp4"), TEST)
