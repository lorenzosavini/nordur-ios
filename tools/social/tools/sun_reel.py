"""Reel: Reykjavík's real sun path through the year (astronomical computation, NOAA formulas)."""
import sys, os, math, datetime, numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reelkit as rk
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
LAT, LON = 64.1466, -21.9426
def sunpos(dt):
    """Altitude and azimuth (deg, azimuth from north clockwise) for a UTC datetime."""
    jd = dt.timestamp() / 86400 + 2440587.5; T = (jd - 2451545) / 36525
    L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360; M = 357.52911 + T * (35999.05029 - 0.0001537 * T)
    e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
    C = math.sin(math.radians(M)) * (1.914602 - T * (0.004817 + 0.000014 * T)) + math.sin(math.radians(2 * M)) * (0.019993 - 0.000101 * T) + math.sin(math.radians(3 * M)) * 0.000289
    lam = L0 + C - 0.00569 - 0.00478 * math.sin(math.radians(125.04 - 1934.136 * T))
    eps = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60 + 0.00256 * math.cos(math.radians(125.04 - 1934.136 * T))
    dec = math.degrees(math.asin(math.sin(math.radians(eps)) * math.sin(math.radians(lam))))
    y = math.tan(math.radians(eps / 2)) ** 2
    eot = 4 * math.degrees(y * math.sin(2 * math.radians(L0)) - 2 * e * math.sin(math.radians(M)) + 4 * e * y * math.sin(math.radians(M)) * math.cos(2 * math.radians(L0)) - 0.5 * y * y * math.sin(4 * math.radians(L0)) - 1.25 * e * e * math.sin(2 * math.radians(M)))
    tst = (dt.hour * 60 + dt.minute + dt.second / 60 + eot + 4 * LON) % 1440
    ha = tst / 4 - 180
    la, de, h = map(math.radians, (LAT, dec, ha))
    alt = math.degrees(math.asin(math.sin(la) * math.sin(de) + math.cos(la) * math.cos(de) * math.cos(h)))
    az = math.degrees(math.atan2(math.sin(h), math.cos(h) * math.sin(la) - math.tan(de) * math.cos(la))) + 180
    return alt, az % 360
def day_info(d):
    """Sunrise and sunset (minutes after local midnight; sunset may pass 24:00) by threshold crossing."""
    base = datetime.datetime(d.year, d.month, d.day)
    alts = [sunpos(base + datetime.timedelta(minutes=m))[0] for m in range(0, 1800)]
    th = -0.833
    rise = next((m for m in range(1, 1440) if alts[m - 1] <= th < alts[m]), None)
    if rise is None: return None, None, 0.0
    sset = next((m for m in range(rise + 1, 1800) if alts[m - 1] > th >= alts[m]), None)
    return rise, sset, (sset - rise) / 60
# layout: azimuth 0..360 → x across a wide band; we show azimuth 30..330 (N at the edges)
HY = 1120                         # horizon y
def X(az): return W / 2 + (az - 180) / 150 * (W / 2 - 40)
def Y(alt): return HY - alt * 14
SKY = [(-18, (4, 7, 14)), (-10, (10, 18, 40)), (-4, (40, 40, 80)), (-1, (150, 80, 70)), (2, (230, 140, 80)), (8, (110, 160, 210)), (30, (70, 140, 220)), (60, (60, 125, 215))]
def lerpc(stops, v):
    if v <= stops[0][0]: return np.array(stops[0][1], float)
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if v <= b: k = (v - a) / (b - a); return np.array(ca) * (1 - k) + np.array(cb) * k
    return np.array(stops[-1][1], float)
rng = np.random.default_rng(3); STARS = [(rng.uniform(0, W), rng.uniform(0, HY - 40), rng.uniform(0.6, 2.2)) for _ in range(260)]
# timeline: 21 Dec 2025 → 21 Jun 2026 → 21 Dec 2026 over SWEEP seconds; sun laps one day per LAP seconds
D0 = datetime.date(2025, 12, 21); SWEEP = 16.0; LAP = 1.1; HOLD_DEC = 4.8; Q = 2.4; CTA = 3.2
TOTAL = HOLD_DEC + SWEEP + Q + CTA
def date_at(t):
    if t < HOLD_DEC: return D0, 0.0
    k = min(1, (t - HOLD_DEC) / SWEEP); k = 0.5 - 0.5 * math.cos(math.pi * k)  # slow at both solstices
    days = k * 365; return D0 + datetime.timedelta(days=int(days)), days % 1
info_cache = {}
def info(d):
    if d not in info_cache: info_cache[d] = day_info(d)
    return info_cache[d]
arc_cache = {}
def arc(d):
    if d not in arc_cache:
        pts = []
        for m in range(0, 1441, 6):
            a, z = sunpos(datetime.datetime(d.year, d.month, d.day) + datetime.timedelta(minutes=m))
            if 30 <= z <= 330: pts.append((X(z), Y(a), a))
            else: pts.append(None)
        arc_cache[d] = pts
    return arc_cache[d]
trails = Image.new("RGBA", (W, H), (0, 0, 0, 0)); last_trail = [None]
def hm(m): m = m % 1440; return f"{int(m // 60):02d}:{int(m % 60):02d}"
def frame(fi):
    t = fi / FPS; d, frac = date_at(min(t, HOLD_DEC + SWEEP))
    minute = ((t / LAP) % 1) * 1440
    alt, az = sunpos(datetime.datetime(d.year, d.month, d.day) + datetime.timedelta(minutes=minute))
    # sky
    top = lerpc(SKY, alt) * 0.55; hor = lerpc(SKY, alt + 3)
    g = np.linspace(0, 1, HY)[:, None] ** 1.6
    sky = (top[None, :] * (1 - g) + hor[None, :] * g)
    img = np.zeros((H, W, 3), np.float32); img[:HY] = sky[:, None, :]
    sea = np.linspace(0, 1, H - HY)[:, None]; img[HY:] = (hor * 0.35 * (1 - sea) + np.array([3, 6, 10]) * sea)[:, None, :]
    im = Image.fromarray(img.clip(0, 255).astype(np.uint8)).convert("RGBA"); dr = ImageDraw.Draw(im, "RGBA")
    night = max(0.0, min(1.0, (-alt - 4) / 8))
    for x, y, r in STARS: dr.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, int(200 * night)))
    # fan of past arcs (every ~12 days)
    if last_trail[0] is None or (d - last_trail[0]).days >= 12 or (d < last_trail[0]):
        pts = [p for p in arc(d) if p and p[2] > -0.5]
        if len(pts) > 1:
            col = lerpc([(0, (120, 170, 255)), (25, (255, 200, 90)), (50, (255, 140, 60))], max(p[2] for p in pts))
            ImageDraw.Draw(trails).line([(p[0], p[1]) for p in pts], fill=tuple(int(c) for c in col) + (90,), width=3)
        last_trail[0] = d
    im.alpha_composite(trails)
    # today's arc (above horizon solid, below dashed)
    pts = arc(d)
    seg = []
    for p in pts + [None]:
        if p and p[2] > -0.833: seg.append((p[0], p[1]))
        else:
            if len(seg) > 1: dr.line(seg, fill=(255, 230, 170, 230), width=5)
            seg = []
    # horizon + compass
    dr.line((0, HY, W, HY), fill=(255, 255, 255, 120), width=2)
    for name, z in (("E", 90), ("SE", 135), ("S", 180), ("SW", 225), ("W", 270)):
        x = X(z); dr.line((x, HY, x, HY + 16), fill=(255, 255, 255, 140), width=2)
        f = MONO(26); dr.text((x - dr.textlength(name, font=f) / 2, HY + 24), name, font=f, fill=(200, 205, 210))
    # the sun
    if 30 <= az <= 330:
        sx, sy = X(az), Y(alt)
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ImageDraw.Draw(glow).ellipse((sx - 70, sy - 70, sx + 70, sy + 70), fill=(255, 200, 100, 150 if alt > -1 else 40))
        im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(30)))
        ImageDraw.Draw(im).ellipse((sx - 22, sy - 22, sx + 22, sy + 22), fill=(255, 236, 180, 255 if alt > -0.833 else 90))
    # sea covers the sun below the horizon
    sea_img = Image.fromarray(img[HY:].clip(0, 255).astype(np.uint8)).convert("RGBA"); im.alpha_composite(sea_img, (0, HY))
    dr = ImageDraw.Draw(im, "RGBA"); dr.line((0, HY, W, HY), fill=(255, 255, 255, 120), width=2)
    for name, z in (("E", 90), ("SE", 135), ("S", 180), ("SW", 225), ("W", 270)):
        x = X(z); dr.line((x, HY, x, HY + 16), fill=(255, 255, 255, 140), width=2)
        f = MONO(26); dr.text((x - dr.textlength(name, font=f) / 2, HY + 24), name, font=f, fill=(200, 205, 210))
    # panel
    sr, ss, hours = info(d)
    rk.shadow_text(im, d.strftime("%-d %B").upper(), 1290, COND(120), rk.TEXT, center=False, x=64)
    rk.shadow_text(im, "DAYLIGHT IN REYKJAVÍK", 1432, MONO(24), rk.DIM, center=False, x=64)
    rk.shadow_text(im, f"{int(hours)} h {int(round(hours % 1 * 60)) % 60:02d}", 1460, COND(76), (255, 214, 120), center=False, x=64)
    if sr is not None:
        rk.shadow_text(im, "SUNRISE", 1432, MONO(24), rk.DIM, center=False, x=560); rk.shadow_text(im, hm(sr), 1460, COND(76), rk.TEXT, center=False, x=560)
        rk.shadow_text(im, "SUNSET", 1432, MONO(24), rk.DIM, center=False, x=800); rk.shadow_text(im, hm(ss), 1460, COND(76), rk.TEXT, center=False, x=800)
    # clock of the travelling sun
    rk.shadow_text(im, hm(minute), 300 + 0 * 0, MONO(28), rk.DIM) if False else None
    # captions
    if t < 2.4: y = rk.block(im, "Iceland's sun, for a whole year.", 290, 104, k=rk.ease(t / 0.3)); rk.shadow_text(im, "Real sun path over Reykjavík", y + 14, SANS(40), rk.DIM)
    elif t < HOLD_DEC + 0.8: y = rk.block(im, "December: it barely clears the horizon.", 290, 96, k=rk.ease((t - 2.4) / 0.3))
    elif abs((d - datetime.date(2026, 6, 21)).days) < 22: y = rk.block(im, "June: it hardly sets at all.", 290, 104, (255, 214, 120))
    elif t < HOLD_DEC + SWEEP: y = rk.block(im, "Watch the arc grow…" if d < datetime.date(2026, 6, 21) else "…and shrink again.", 290, 104)
    elif t < HOLD_DEC + SWEEP + Q: y = rk.block(im, "Winter or summer?", 300, 120, k=rk.ease((t - HOLD_DEC - SWEEP) / 0.3)); rk.shadow_text(im, "Tell me which Iceland you'd pick", y + 14, SANS(42), rk.DIM)
    if t >= HOLD_DEC + SWEEP + Q: rk.cta(im, rk.ease((t - HOLD_DEC - SWEEP - Q) / 0.5), P, "Daylight, darkness and aurora hours, where you are.", "Sun positions computed for Reykjavík (64.15°N) with NOAA solar formulas")
    return im.convert("RGB")
print("check", day_info(datetime.date(2025, 12, 21)), day_info(datetime.date(2026, 6, 21)))
rk.run(frame, TOTAL, os.path.join(OUT, "sun-year.mp4"), TEST)
