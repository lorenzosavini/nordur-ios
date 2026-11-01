"""Norður posts v2 (1080×1350): real photographs of Iceland, real app screens, frames of the
3D flight; every carousel numbered on its own. Usage: posts_v2.py <shots> <fonts> <heroes dir> <flight frame> <out>"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
SHOTS, FONTS, HEROES, FLIGHT, OUT = sys.argv[1:6]
W, H = 1080, 1350
BG = (7, 9, 12); TEXT = (246, 246, 242); DIM = (186, 186, 182); ACCENT = (255, 90, 31); AURORA = (61, 224, 168)
RED = (255, 59, 48); YELLOW = (242, 184, 7); PURPLE = (200, 60, 210); CARD = (18, 22, 28); BLUE = (120, 170, 255)
def font(n, s): return ImageFont.truetype(os.path.join(FONTS, n), s)
COND = lambda s: font("BarlowCondensed-Bold.woff", s)
SANS = lambda s: font("IBMPlexSans-Medium.woff", s)
SANSB = lambda s: font("IBMPlexSans-SemiBold.woff", s)
MONO = lambda s: font("IBMPlexMono-SemiBold.woff", s)

# Photographs bundled with the app (Wikimedia Commons, free licences, credited on the slide).
CREDIT = {"aurora": "Photo: AstroAnthony · CC BY 4.0", "roads": "Photo: Winniepix · CC BY 2.0", "weather": "Photo: Thomas Heins · CC BY 4.0",
          "trip": "Photo: Steven Diaz · CC0", "drive": "Photo: Petr Kraumann · CC BY 3.0", "map": "Image: NASA Goddard · public domain"}

def photo(name):
    return Image.open(os.path.join(HEROES, f"hero-{name}.imageset", f"hero-{name}.jpg")).convert("RGB")

def cover(img, w, h, fx=0.5, fy=0.5):
    s = max(w / img.width, h / img.height)
    r = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x = round((r.width - w) * fx); y = round((r.height - h) * fy)
    return r.crop((x, y, x + w, y + h))

def canvas():
    return Image.new("RGBA", (W, H), BG + (255,))

def header_photo(im, name, h=620, fy=0.5, fx=0.5, tint=None, credit=True, src=None):
    """A photograph across the top, fading into the dark page."""
    cred = None
    if name and ":" in name: src, cred = K(name, "batch-1"); credit = True
    p = cover(src or photo(name), W, h, fx, fy)
    if tint:
        g = ImageEnhance.Color(p).enhance(0.25)
        p = Image.blend(g, Image.new("RGB", p.size, tint), 0.35)
    p = p.convert("RGBA")
    fade = Image.new("L", (W, h), 0); d = ImageDraw.Draw(fade)
    for y in range(h):
        d.line((0, y, W, y), fill=int(255 * max(0, (y - h * 0.45) / (h * 0.55)) ** 1.4))
    im.paste(p, (0, 0)); im.paste(Image.new("RGBA", (W, h), BG + (255,)), (0, 0), fade)
    top = Image.new("L", (W, 220), 0); dt = ImageDraw.Draw(top)
    for y in range(220): dt.line((0, y, W, y), fill=int(150 * (1 - y / 220)))
    im.paste(Image.new("RGBA", (W, 220), (0, 0, 0, 255)), (0, 0), top)
    if credit and (cred or name in CREDIT):
        d = ImageDraw.Draw(im); t = cred or CREDIT[name]; f = MONO(17)
        d.text((W - 40 - d.textlength(t, font=f), h - 205), t, font=f, fill=(210, 210, 205))

def full_photo(im, src, dark=0.55, fy=0.5, fx=0.5):
    p = cover(src, W, H, fx, fy)
    p = Image.blend(p, Image.new("RGB", p.size, BG), dark)
    im.paste(p.convert("RGBA"), (0, 0))

def brand(im, counter=None):
    d = ImageDraw.Draw(im)
    icon = Image.open(os.path.join(FONTS, "..", "img", "icon.png")).convert("RGBA").resize((48, 48), Image.LANCZOS)
    m = Image.new("L", (48, 48), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 47, 47), 11, fill=255)
    im.paste(icon, (64, 56), m); d.text((124, 56), "NORÐUR", font=COND(42), fill=TEXT)
    if counter:
        t = f"{counter[0]}/{counter[1]}"; f = MONO(26)
        w = d.textlength(t, font=f)
        d.rounded_rectangle((W - 64 - w - 28, 56, W - 64, 104), 24, fill=(0, 0, 0, 150))
        d.text((W - 64 - w - 14, 64), t, font=f, fill=TEXT)

def footer(im, text="nordur.info"):
    d = ImageDraw.Draw(im); f = MONO(26)
    d.text((64, H - 78), text, font=f, fill=ACCENT)

def swipe(im, y):
    d = ImageDraw.Draw(im); f = MONO(28)
    d.text((64, y), "SWIPE", font=f, fill=TEXT)
    x = 64 + d.textlength("SWIPE", font=f) + 18
    d.line((x, y + 18, x + 70, y + 18), fill=ACCENT, width=5); d.polygon([(x + 70, y + 8), (x + 88, y + 18), (x + 70, y + 28)], fill=ACCENT)

def wrap(d, text, f, width):
    out, line = [], ""
    for w in text.split(" "):
        t = (line + " " + w).strip()
        if d.textlength(t, font=f) <= width or not line: line = t
        else: out.append(line); line = w
    if line: out.append(line)
    return out

def heading(im, kicker, text, y, size=96, color=TEXT, width=W - 128):
    d = ImageDraw.Draw(im)
    if kicker: d.text((64, y), kicker.upper(), font=MONO(26), fill=ACCENT); y += 48
    for ln in wrap(d, text, COND(size), width): d.text((64, y), ln, font=COND(size), fill=color); y += round(size * 1.02)
    return y

def para(im, text, y, size=40, color=DIM, width=W - 128):
    d = ImageDraw.Draw(im)
    for ln in wrap(d, text, SANS(size), width): d.text((64, y), ln, font=SANS(size), fill=color); y += round(size * 1.38)
    return y

def rows(im, items, y, h=150, big=72, left=360):
    d = ImageDraw.Draw(im, "RGBA")
    for a, b, col in items:
        d.rounded_rectangle((64, y, W - 64, y + h), 20, fill=CARD + (245,)); d.rectangle((64, y, 74, y + h), fill=col)
        d.text((100, y + (h - big) / 2 - 8), a, font=COND(big), fill=col)
        f = SANS(34); lines = wrap(d, b, f, W - 64 - left - 32)
        ty = y + (h - len(lines) * 44) / 2
        for ln in lines: d.text((left, ty), ln, font=f, fill=TEXT); ty += 44
        y += h + 16
    return y

def phone(name, height):
    shot = Image.open(os.path.join(SHOTS, name + ".png")).convert("RGB")
    w = round(height * shot.width / shot.height); shot = shot.resize((w, height), Image.LANCZOS)
    r = round(w * 0.11); pad = 8
    m = Image.new("L", (w, height), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, height - 1), r, fill=255)
    fr = Image.new("RGBA", (w + 2 * pad, height + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(fr).rounded_rectangle((0, 0, w + 2 * pad - 1, height + 2 * pad - 1), r + pad, fill=(44, 48, 54, 255))
    fr.paste(shot, (pad, pad), m)
    sh = Image.new("RGBA", (fr.width + 80, fr.height + 80), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((40, 52, fr.width + 40, fr.height + 52), r, fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(20)); sh.paste(fr, (40, 40), fr)
    return sh

def save(im, folder, i):
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    im.convert("RGB").save(os.path.join(OUT, folder, f"{i:02d}.jpg"), quality=93)

exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "deco.py")).read())
reset_pool()
def carousel(folder, slides):
    n = len(slides)
    for i, make in enumerate(slides, start=1):
        key = None
        if isinstance(make, tuple): make, key = make
        im = canvas(); make(im)
        if key: fullbg(im, K(key, f"{folder}/{i:02d}")[0], BG)
        else: decorate(im, folder, i, n, BG)
        brand(im, (i, n)); footer(im); progress(im, i, n, ACCENT, TEXT, MONO); save(im, folder, i)

flight = Image.open(FLIGHT).convert("RGB")

_d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
def anchored(title, tsize, body, bsize=44, maxy=960):
    """Top of a title + text block that ends just above the footer."""
    h = len(wrap(_d, title, COND(tsize), W - 128)) * round(tsize * 1.02) + 20 + len(wrap(_d, body, SANS(bsize), W - 128)) * round(bsize * 1.38)
    return min(maxy, H - 170 - h)

# ——— C1 · Weather warnings (5 slides) ———
def ww_cover(im):
    header_photo(im, "hero:weather", h=860, fy=0.4)
    y = heading(im, "Iceland weather warnings", "Yellow, orange, red: what they really mean", 760, 100)
    swipe(im, y + 30)
def ww_level(col, name, line, advice, tint, key):
    def make(im):
        y0 = anchored(line, 100, advice)
        header_photo(im, key, h=y0 - 20, fy=0.5, tint=tint)
        d = ImageDraw.Draw(im, "RGBA")
        d.rounded_rectangle((64, y0 - 290, 64 + d.textlength(name, font=COND(150)) + 60, y0 - 120), 18, fill=col + (255,))
        d.text((94, y0 - 284), name, font=COND(150), fill=BG)
        icon(im, "alert-triangle", W - 64 - 140, y0 - 300, 140)
        y = heading(im, None, line, y0, 100)
        para(im, advice, y + 20, 44, TEXT)
    return make
def ww_app(im):
    y = heading(im, "With Norður", "Only where you'll actually be", 170, 88)
    para(im, "Warnings for your position, your trip stops and the places you follow. A notification only when one is new or gets worse.", y + 10, 34)
    p = phone("alerts", 820); im.paste(p, ((W - p.width) // 2, 430), p)
carousel("carousel-01-weather-warnings", [ww_cover,
    ww_level(YELLOW, "YELLOW", "Possible disruption", "Stay alert. Check the forecast and the roads before you set off: expect gusts and poor visibility in places.", (90, 70, 0), "fly:westfjords-2.7"),
    ww_level(ACCENT, "ORANGE", "Significant impacts", "Think about postponing the drive. Mountain passes and exposed coasts can become dangerous.", (110, 40, 0), "fly:glacier-lagoon-11"),
    ww_level(RED, "RED", "Extreme weather", "Don't travel. Follow official instructions and stay where you are.", (110, 10, 10), "fly:westfjords-3.5"),
    (ww_app, "iss:6")])

# ——— C2 · Aurora: Kp isn't everything (6 slides) ———
def au_cover(im):
    header_photo(im, "ak:19.5", h=900, fy=0.5)
    y = heading(im, "Northern lights", "Kp isn't everything", 800, 130)
    para(im, "4 things decide if you'll see the aurora", y + 18, 40, TEXT); swipe(im, y + 92)
def au_point(num, head, body, col, fx, fy, key):
    def make(im):
        y0 = anchored(head, 110, body)
        header_photo(im, key, h=y0 - 10, fx=0.5, fy=0.5)
        d = ImageDraw.Draw(im)
        d.text((64, y0 - 330), num, font=COND(220), fill=col)
        icon(im, {"Darkness": "stars", "A clear sky": "cloud-off", "Activity": "sun", "The Moon": "moon"}[head], W - 64 - 150, y0 - 330, 150)
        y = heading(im, None, head, y0, 110)
        para(im, body, y + 20, 44, TEXT)
    return make
def au_app(im):
    y = heading(im, "With Norður", "All four in one answer, where you are", 170, 88)
    a = phone("aurora", 720); b = phone("map-aurora", 660)
    im.paste(b, (W - b.width - 40, 470), b); im.paste(a, (40, 420), a)
carousel("carousel-02-aurora-kp", [au_cover,
    au_point("1", "Darkness", "The Sun must be well below the horizon. In Iceland that's late August to mid-April, best between 22:00 and 02:00.", AURORA, 0.2, 0.3, "ak:6"),
    au_point("2", "A clear sky", "Clouds beat everything: a strong aurora behind clouds is invisible. Check the clouds where you are, not in Reykjavík.", BLUE, 0.5, 0.2, "ak:15"),
    au_point("3", "Activity", "Iceland sits right under the auroral oval: even Kp 2–3 can give a show. What matters is the solar wind arriving now.", ACCENT, 0.8, 0.3, "iss:14"),
    au_point("4", "The Moon", "A bright Moon washes out faint auroras. Strong ones still shine through.", YELLOW, 0.5, 0.6, "ak:12"),
    (au_app, "iss:78")])

# ——— C3 · Everything Norður does (10 slides, screens over blurred photographs) ———
FEAT = [("today", "Your day, at a glance", "Weather, warnings, roads and aurora where you are", "weather"),
        ("notifications-lock", "Alerts on your lock screen", "Only when something is new or gets worse", "roads"),
        ("aurora", "Aurora: when and where to look", "Live chances for your sky", "aurora"),
        ("roads", "Roads and closures, live", "From Vegagerðin, plus 170+ webcams", "roads"),
        ("trip", "Your trip, day by day", "Weather and roads on every leg", "trip"),
        ("suggestions", "Ideas for every stop", "Waterfalls, hot springs, viewpoints", "trip"),
        ("share", "Your drive as a 3D flight", "A video over the real terrain", None),
        ("fuel", "The cheapest fuel near you", "Live prices, in your currency", "drive"),
        ("shops", "Supermarkets open now", "Opening hours and directions", "drive"),
        ("offline", "Works without signal", "Highlands, Westfjords, anywhere", "map")]
def feat(shot, t, s, bg):
    def make(im):
        src = Image.open(os.path.join(SHOTS, shot + ".png")).convert("RGB")
        b = cover(src, W, H).filter(ImageFilter.GaussianBlur(28))
        b = Image.blend(b, Image.new("RGB", (W, H), BG), 0.55); im.paste(b.convert("RGBA"), (0, 0))
        y = heading(im, None, t, 150, 80); para(im, s, y + 4, 36, TEXT)
        p = phone(shot, 880); im.paste(p, ((W - p.width) // 2, 330), p)
    return make
carousel("carousel-03-everything-norður-does", [feat(*f) for f in FEAT])

# ——— Singles ———
def single(folder, make, foot=True):
    im = canvas(); make(im); decorate(im, folder, 1, 1, BG); brand(im)
    if foot: footer(im)
    save(im, folder, 1)

def anchored_post(name, fy, body):
    """Text block ends just above the footer; the photograph grows down to meet it."""
    def make(im):
        end = body(canvas(), 0)
        y0 = H - 150 - end
        header_photo(im, name, h=y0 + 150, fy=fy)
        body(im, y0)
    return make

def b_emergency(im, y):
    y = heading(im, "Iceland · save this", "The numbers to know", y, 96)
    return rows(im, [("112", "Emergency: police, ambulance, fire, search and rescue.", RED),
              ("1777", "Road conditions and closures, from Vegagerðin.", YELLOW),
              ("1700", "Medical helpline, when it's not an emergency.", AURORA),
              ("SafeTravel", "Leave your plan on safetravel.is: rescuers know where to look.", ACCENT)], y + 36, h=150, big=64, left=420)
single("post-01-emergency-numbers", anchored_post("fly:ring-road-17", 0.55, b_emergency))

def b_wind(im, y):
    y = heading(im, "Iceland wind, explained", "What m/s really means", y, 96)
    return rows(im, [("15 m/s", "54 km/h · hold the car door with both hands", YELLOW), ("20 m/s", "72 km/h · hard to walk, gravel flies", ACCENT),
              ("25 m/s", "90 km/h · dangerous for vans and campers", RED), ("30+ m/s", "108+ km/h · don't drive", PURPLE)], y + 36, h=150, big=66, left=340)
single("post-02-wind-speed", anchored_post("hero:drive", 0.5, b_wind))

def b_check(im, y):
    y = heading(im, "Road trip · save this", "Before you drive, every day", y, 92)
    d = ImageDraw.Draw(im); y += 30
    for item in ["Weather warnings on your route", "Road conditions and closures (1777)", "Gusts: open car doors with both hands",
                 "Fuel up when half empty outside towns", "Headlights on, day and night: it's the law", "Never stop on the road for photos",
                 "F-roads: 4×4 only, and only when open"]:
        d.rounded_rectangle((64, y + 4, 104, y + 44), 10, outline=AURORA, width=4)
        d.line((74, y + 24, 82, y + 33), fill=AURORA, width=5); d.line((82, y + 33, 96, y + 15), fill=AURORA, width=5)
        d.text((128, y), item, font=SANS(38), fill=TEXT); y += 72
    d.text((64, y + 18), "Norður checks the first three for you.", font=SANSB(36), fill=ACCENT)
    return y + 66
single("post-03-driving-checklist", anchored_post("fly:golden-circle-14", 0.4, b_check))

def b_season(im, y):
    y = heading(im, "Northern lights in Iceland", "When to go", y, 104)
    return rows(im, [("Sep–Apr", "Aurora season: nights dark enough", AURORA), ("22–02", "The best hours, local time", BLUE),
              ("Nov–Feb", "Longest nights, more storms and clouds", ACCENT), ("Sep · Mar", "Equinox months: often the most active", YELLOW)], y + 36, h=140, big=62, left=380)
single("post-04-aurora-season", anchored_post("iss:58", 0.5, b_season))

def s_waitlist(im):
    _src, _cr = K("hero:aurora", "post-05"); full_photo(im, _src, dark=0.2, fy=0.5)
    # A dark band at the top for the text, over the sky: the church stays clear.
    fade = Image.new("L", (W, 760), 0); df = ImageDraw.Draw(fade)
    for y in range(760): df.line((0, y, W, y), fill=int(235 * min(1, (760 - y) / 380)))
    im.paste(Image.new("RGBA", (W, 760), BG + (255,)), (0, 0), fade)
    d = ImageDraw.Draw(im)
    def c(y, t, fo, col): d.text(((W - d.textlength(t, font=fo)) / 2, y), t, font=fo, fill=col)
    c(230, "Iceland, in one app.", COND(110), TEXT); c(380, "JOIN THE WAITLIST", MONO(40), ACCENT); c(430, "nordur.info", COND(150), TEXT)
    f = MONO(17); t = _cr; d.text((W - 40 - d.textlength(t, font=f), H - 40), t, font=f, fill=(200, 200, 196))
single("post-05-waitlist", s_waitlist, foot=False)

def s_field(im):
    _src, _cr = K("fly:golden-circle-17", "post-06"); full_photo(im, _src, dark=0.3, fy=0.45)
    g = Image.new("L", (1, 760)); [g.putpixel((0, y), int(235 * min(1, y / 420))) for y in range(760)]
    im.paste(Image.new("RGBA", (W, 760), BG + (255,)), (0, H - 760), g.resize((W, 760)))
    d = ImageDraw.Draw(im); f = MONO(17); d.text((W - 40 - d.textlength(_cr, font=f), H - 40), _cr, font=f, fill=(200, 200, 196))
    y = heading(im, "Field test · 6–13 November", "I'm taking Norður to Iceland", 760, 100)
    para(im, "Real roads, real weather, hopefully real auroras. Follow along.", y + 10, 40, TEXT)
single("post-06-field-test", s_field)
print("ok")
