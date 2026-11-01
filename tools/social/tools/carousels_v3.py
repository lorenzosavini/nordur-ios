"""15 more carousels: useful, data-driven, with real photographs and sources on every data slide.
Usage: carousels_v3.py <shots> <fonts> <heroes> <flight frame> <out> <stats.json> <stills dir>"""
import sys, os
STATS, STILLS = sys.argv[6], sys.argv[7]
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "plib.py")).read())
S = json.load(open(STATS))
flight = Image.open(FLIGHT).convert("RGB")
def still(name):
    im = Image.open(os.path.join(STILLS, name + ".png")).convert("RGB")
    return im.crop((480, 0, 3360, 2160)) if name.startswith("still-ak") else im
NASA_AK = "Photo: NASA/Mike Toillion · public domain"
NASA_ISS = "Image: NASA Johnson Space Center · public domain"

def credit_line(im, text, y=None):
    d = ImageDraw.Draw(im); f = MONO(17)
    d.text((W - 40 - d.textlength(text, font=f), y or H - 40), text, font=f, fill=(170, 170, 166))

def source(im, text):
    d = ImageDraw.Draw(im); f = MONO(20)
    d.text((64, H - 128), "Source: " + text, font=f, fill=(150, 150, 146))

def photo_header(im, src, h, credit, fy=0.5, fx=0.5):
    if src is None: return            # no fitting photograph: the slide is carried by its icon
    header_photo(im, None, h=h, fy=fy, fx=fx, src=src, credit=False)
    d = ImageDraw.Draw(im); f = MONO(17)
    d.text((W - 40 - d.textlength(credit, font=f), h - 160), credit, font=f, fill=(210, 210, 205))

_d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
def block_h(title, tsize, body=None, bsize=42, kicker=False, width=W - 128):
    h = len(wrap(_d, title, COND(tsize), width)) * round(tsize * 1.02) + (48 if kicker else 0)
    if body: h += 14 + len(wrap(_d, body, SANS(bsize), width)) * round(bsize * 1.38)
    return h
BOTTOM = H - 170   # text ends here: room for the source line and nordur.info

def cover_slide(src, credit, kicker, title, sub=None, fy=0.4, fx=0.5, size=112):
    def make(im):
        bh = block_h(title, size, sub, 42, True) + 36 + 40
        y0 = BOTTOM - bh
        photo_header(im, src, max(880, y0 + 90), credit, fy, fx)
        if src is None: icon(im, COVER_ICON[title], 64, y0 - 380, 300)
        y = heading(im, kicker, title, y0, size)
        if sub: y = para(im, sub, y + 18, 42, TEXT)
        swipe(im, y + 24)
    return make

MUTED = (72, 80, 94)
def bar(d, x0, x1, ybase, ytop, col):
    """A bar anchored on the baseline: square at the base, 4 px rounded at the data end."""
    up = ytop < ybase
    t, btm = (ytop, ybase) if up else (ybase, ytop)
    if btm - t < 5: d.rectangle((x0, t, x1, btm), fill=col); return
    d.rounded_rectangle((x0, t, x1, btm), 4, fill=col)
    if up: d.rectangle((x0, btm - 5, x1, btm), fill=col)
    else: d.rectangle((x0, t, x1, t + 5), fill=col)

def chart(im, values, labels, y0, height, colors, fmt, ticks, show=(), x0=64 + 70, unit=""):
    """Bar chart: recessive grid with tick labels on the left, true zero, values only where they matter."""
    d = ImageDraw.Draw(im, "RGBA")
    lo, hi = min(ticks), max(ticks)
    Y = lambda v: y0 + height - (v - lo) / (hi - lo) * height
    for tv in ticks:
        yy = Y(tv)
        d.line((x0, yy, W - 64, yy), fill=(255, 255, 255, 70 if tv == 0 else 22), width=2 if tv == 0 else 1)
        t = f"{tv:g}{unit}"; f = MONO(22)
        d.text((x0 - 14 - d.textlength(t, font=f), yy - 13), t, font=f, fill=(150, 150, 146))
    n = len(values); gap = 10; bw = (W - 64 - x0 - gap * (n - 1)) / n
    for i, (v, lab) in enumerate(zip(values, labels)):
        x = x0 + i * (bw + gap)
        bar(d, x, x + bw, Y(max(lo, 0)), Y(v), colors[i])
        if i in show:
            t = fmt(v); f = MONO(26)
            ty = Y(v) - 36 if v >= 0 else Y(v) + 8
            d.text((x + (bw - d.textlength(t, font=f)) / 2, ty), t, font=f, fill=TEXT)
        f2 = MONO(22) if len(lab) <= 2 else SANS(26)
        d.text((x + (bw - d.textlength(lab, font=f2)) / 2, y0 + height + 16), lab, font=f2, fill=TEXT if i in show else DIM)

def legs(im, items, y, unit_total=True):
    """The route as a line: a dot per stop, distance and time between them."""
    d = ImageDraw.Draw(im, "RGBA"); total_km = total_min = 0
    n = len(items); pitch = min(132, (H - 330 - y) // n)
    stops = [items[0][0]] + [b for _, b, _, _ in items]
    lx = 92
    d.line((lx, y + 22, lx, y + 22 + n * pitch), fill=(255, 255, 255, 110), width=3)
    for k, name in enumerate(stops):
        cy = y + 22 + k * pitch
        if k in (0, n): d.ellipse((lx - 12, cy - 12, lx + 12, cy + 12), fill=ACCENT)
        else: d.ellipse((lx - 10, cy - 10, lx + 10, cy + 10), fill=BG, outline=TEXT, width=3)
        d.text((140, cy - 26), name, font=SANSB(40), fill=TEXT)
        if k < n:
            _, _, km, mins = items[k]
            d.text((140, cy + pitch / 2 - 15), f"{km} km · {mins // 60} h {mins % 60:02d}", font=MONO(26), fill=DIM)
            total_km += km; total_min += mins
    y = y + 22 + n * pitch + 56
    f = SANSB(36); t1 = "Total  "; d.text((64, y), t1, font=f, fill=DIM)
    d.text((64 + d.textlength(t1, font=f), y), f"{total_km} km · {total_min // 60} h {total_min % 60:02d} min of driving", font=f, fill=TEXT)
    return y + 60

COVER_ICON = {"Distances, times and timing": "route", "The etiquette nobody tells you": "bath", "Cards, tips and fuel pumps": "coins"}
ICONS = {
    "people live in Iceland": "users", "foreign visitors a year": "plane-arrival", "km of Ring Road": "road",
    "of the land is glacier": "snowflake", "active volcanic systems": "volcano",
    "It's the wind, not the cold": "wind", "Iceland sits under the oval": "world", "Kp is a 3-hour average": "clock-hour-3",
    "years: one solar cycle": "sun", "May 2024: the strongest storm in 20 years": "bolt", "The best years are now": "calendar",
    "Headlights on, always": "car", "Never drive off-road": "car-off", "F-roads: 4×4 only": "mountain", "Never stop on the road": "hand-stop",
    "Check before every drive": "checklist", "Plan around daylight": "sunset", "Watch the wind": "wind", "Black ice near zero": "snowflake",
    "Keep the tank half full": "gas-station", "Leave your plan": "route", "Skip the umbrella": "umbrella-off",
    "Add 30–50% to the times": "clock-plus", "Go early, or late": "alarm",
    "homes heated by geothermal water": "home", "renewable electricity": "bolt", "Drink from the tap": "droplet",
    "Shower first, without swimsuit": "bath", "Conditioner for your hair": "bottle", "Natural springs can be boiling": "temperature-plus",
    "Leave no trace": "leaf", "Cards everywhere": "credit-card", "No need to tip": "receipt-off", "Fuel pumps want a PIN": "gas-station",
    "Turning your back to the sea": "ripple", "Ignoring a yellow warning": "alert-triangle", "Underestimating distances": "route",
    "Stopping on the road": "hand-stop", "Chasing the aurora on Kp alone": "cloud", "Better in two days": "calendar",
}

def text_slide(src, credit, num, title, body, col=ACCENT, fy=0.5, fx=0.5, h=None):
    def make(im):
        if src is None:
            # No fitting photograph: icon, number and text as one block (centred later by balance()).
            d = ImageDraw.Draw(im); y = 170
            icon(im, ICONS[title], 64, y, 200); y += 240
            if num: d.text((64, y - 30), num, font=COND(200), fill=col); y += 210
            y = heading(im, None, title, y, 100)
            para(im, body, y + 14, 42, TEXT)
            return
        y0 = min(960, BOTTOM - block_h(title, 100, body, 42))
        hh = y0 - 10
        photo_header(im, src, hh, credit, fy, fx)
        d = ImageDraw.Draw(im)
        if num: d.text((64, hh - 330), num, font=COND(200), fill=col)
        if src is None: icon(im, ICONS[title], 64, hh - (620 if num else 420), 240)
        elif title in ICONS: icon(im, ICONS[title], W - 64 - 140, hh - 320, 140)
        y = heading(im, None, title, y0, 100)
        para(im, body, y + 14, 42, TEXT)
    return make

def app_slide(shot, title, sub):
    def make(im):
        y = heading(im, "With Norður", title, 170, 84)
        y = para(im, sub, y + 16, 34)
        p = phone(shot, 720); im.paste(p, ((W - p.width) // 2, max(470, y + 30)), p)
    return make

FULLBG.update({
    "carousel-04-iceland-in-numbers": {7: "fly:westfjords-10.2"},
    "carousel-05-daylight": {2: "ak:4.5", 4: "ak:7.5"},
    "carousel-06-how-cold-is-iceland": {2: "fly:westfjords-0.5", 3: "fly:snaefellsnes-3.5", 5: "fly:westfjords-11"},
    "carousel-07-kp-scale": {2: "iss:30", 5: "iss:38"},
    "carousel-08-solar-maximum": {5: "iss:50"},
    "carousel-09-driving-rules": {2: "fly:snaefellsnes-5"},
    "carousel-11-packing-list": {2: "fly:westfjords-13.2", 3: "fly:westfjords-16.2"},
    "carousel-12-ring-road-7-days": {2: "fly:snaefellsnes-8", 4: "fly:snaefellsnes-9.5"},
    "carousel-13-golden-circle": {2: "fly:golden-circle-12.5", 4: "fly:snaefellsnes-6.5"},
    "carousel-14-geothermal": {5: "fly:westfjords-17"},
    "carousel-16-money-tips": {5: "fly:glacier-lagoon-6.5", 6: "fly:snaefellsnes-0.5"},
    "carousel-18-south-coast": {2: "fly:south-13", 4: "fly:westfjords-8"},
})
AK4, AK10, AK18 = still("still-ak4"), still("still-ak10"), still("still-ak18")
ISS25, ISS60 = still("still-iss25"), still("still-iss60")

# 04 · Iceland in numbers
def numbers_slide(big, label, note, col, src, credit, fy=0.5):
    def make(im):
        yl = min(1000, BOTTOM - block_h(label, 84, note, 40))
        photo_header(im, src, yl - 190, credit, fy)
        d = ImageDraw.Draw(im)
        d.text((64, yl - 290), big, font=COND(250), fill=col)
        if src is None: icon(im, ICONS[label], 64, yl - 560, 220)
        elif label in ICONS: icon(im, ICONS[label], W - 64 - 150, yl - 230, 150)
        y = heading(im, None, label, yl, 84)
        para(im, note, y + 8, 40)
    return make
carousel("carousel-04-iceland-in-numbers", [
    cover_slide(*K("hero:trip", 'A small country with very big '), "Iceland in numbers", "A small country with very big numbers", fy=0.5),
    numbers_slide("390,000", "people live in Iceland", "About as many as in a mid-size European city.", AURORA, *K("fly:golden-circle-3.5", '"people live in Iceland"')),
    numbers_slide("2.2 M", "foreign visitors a year", "Almost six visitors for every resident (2023–2024).", ACCENT, *K("fly:golden-circle-8", '"foreign visitors a year"')),
    numbers_slide("1,322", "km of Ring Road", "Route 1 circles the whole island.", YELLOW, *K("fly:ring-road-0.5", '"km of Ring Road"')),
    numbers_slide("11%", "of the land is glacier", "Vatnajökull alone covers about 8% of Iceland.", BLUE, *K("nasa:glacier", '"of the land is glacier"'), 0.55),
    numbers_slide("32", "active volcanic systems", "Monitored day and night by the Icelandic Met Office.", RED, *K("nasa:plume", '"active volcanic systems"')),
    lambda im: para(im, "Statistics Iceland (population) · Icelandic Tourist Board (departures via Keflavík) · Vegagerðin (Route 1) · Icelandic Met Office (glaciers, volcanic systems).", heading(im, "Sources", "Where the numbers come from", 200, 100) + 36, 44, TEXT),
])

# 05 · Daylight month by month (computed)
MON = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
def daylight_chart(im):
    y = heading(im, "Daylight in Reykjavík", "Hours of daylight, month by month", 170, 84)
    vals = [S["daylight"][str(m)] for m in range(1, 13)]
    cols = [MUTED] * 12; cols[5] = YELLOW; cols[11] = BLUE
    chart(im, vals, MON, 470, 600, cols, lambda v: f"{int(v)}h{round(v % 1 * 60):02d}", [0, 6, 12, 18, 24], show=(5, 11), unit="h")
    para(im, "Hours between sunrise and sunset on the 21st of each month.", 1130, 30)
    source(im, "sunrise/sunset computed for Reykjavík (64.15°N)")
def daylight_extremes(im):
    _i, _c = K("ak:9", "05/03"); photo_header(im, _i, 620, _c)
    d = ImageDraw.Draw(im)
    dec = S["daylight"]["12"]; jun = S["daylight"]["6"]
    icon(im, "moon", 64, 520, 84); icon(im, "sun", 560, 520, 84)
    d.text((64, 620), f"{int(dec)} h {round(dec % 1 * 60):02d}", font=COND(170), fill=BLUE)
    d.text((64, 800), "21 December", font=SANSB(40), fill=TEXT)
    d.text((560, 620), f"{int(jun)} h {round(jun % 1 * 60):02d}", font=COND(170), fill=YELLOW)
    d.text((560, 800), "21 June", font=SANSB(40), fill=TEXT)
    para(im, "Winter: long nights, perfect for the aurora, but plan drives in daylight. Summer: the midnight sun, no aurora at all.", 900, 38, TEXT)
    source(im, "computed for Reykjavík (64.15°N)")
carousel("carousel-05-daylight", [
    cover_slide(*K("ak:0.5", '"4 hours of daylight in Decemb'), "Iceland's light", "4 hours of daylight in December. 21 in June.", fy=0.5),
    daylight_chart, daylight_extremes,
    app_slide("today", "Sunrise, sunset and darkness for where you are", "And the hours when the aurora can actually be seen."),
])

# 06 · How cold is Iceland really? (ERA5)
def temp_compare(month, title):
    def make(im):
        y = heading(im, "Average temperature", title, 170, 84)
        names = ["Reykjavík", "New York", "Berlin", "Milan", "London"]
        vals = [S["temps"][n][str(month)] for n in names]
        hi = 30 if max(vals) > 15 else 10
        ticks = list(range(-5, hi + 1, 5)) if hi == 10 else list(range(0, 31, 10))
        cols = [AURORA] + [MUTED] * 4
        chart(im, vals, names, 500, 560, cols, lambda v: f"{v:+.1f}°", ticks, show=range(5), unit="°")
        source(im, "ERA5 reanalysis via Open-Meteo, 2015–2024 average")
    return make
carousel("carousel-06-how-cold-is-iceland", [
    cover_slide(*K("fly:glacier-lagoon-15.5", '"Reykjavík in January is about'), "How cold is Iceland, really?", "Reykjavík in January is about as cold as New York", fy=0.4),
    temp_compare(1, "January: Reykjavík vs the world"),
    temp_compare(7, "July: this is where Iceland is different"),
    text_slide(*K("fly:westfjords-14", '"It\'s the wind, not the cold"'), None, "It's the wind, not the cold", "Winter temperatures hover around zero, but gusts of 20–30 m/s make it feel much colder, and rain can freeze on the road.", h=620),
    app_slide("weather", "Feels-like, gusts and rain, hour by hour", "Two forecasts side by side: Icelandic Met Office and MET Norway."),
])

# 07 · The Kp scale explained
def kp_table(im):
    y = heading(im, "NOAA geomagnetic storm scale", "What Kp and G mean", 170, 84)
    rows(im, [("Kp 0–4", "Quiet to active. In Iceland, often already enough for aurora.", AURORA),
              ("G1 · Kp 5", "Minor storm", YELLOW), ("G2 · Kp 6", "Moderate storm", ACCENT),
              ("G3 · Kp 7", "Strong storm", RED), ("G4 · Kp 8", "Severe storm", PURPLE), ("G5 · Kp 9", "Extreme storm (May 2024)", (255, 255, 255))],
         y + 30, h=118, big=56, left=340)
    source(im, "NOAA Space Weather Prediction Center")
carousel("carousel-07-kp-scale", [
    cover_slide(*K("ak:3", '"The Kp scale, explained"'), "Aurora 101", "The Kp scale, explained", "And why Iceland doesn't need a big number", fy=0.5),
    kp_table,
    text_slide(*K("iss:22", '"Iceland sits under the oval"'), None, "Iceland sits under the oval", "The aurora forms a ring around the magnetic pole. Iceland lies right beneath it: a modest Kp 2–3 with a clear, dark sky can be enough.", h=620),
    text_slide(*K("ak:16.5", '"Kp is a 3-hour average"'), None, "Kp is a 3-hour average", "It reacts late. What matters right now is the solar wind reaching Earth, and that changes minute by minute.", h=620),
    app_slide("aurora", "The solar wind, live, turned into one answer", "Plus clouds and darkness where you are."),
])

# 08 · Solar maximum
carousel("carousel-08-solar-maximum", [
    cover_slide(*K("iss:66", '"We\'re at the peak of the sola'), "Why now?", "We're at the peak of the solar cycle", fy=0.4),
    text_slide(*K("iss:74", '"years: one solar cycle"'), "11", "years: one solar cycle", "The Sun's activity rises and falls about every 11 years. NASA and NOAA announced in October 2024 that the Sun had reached its maximum period.", AURORA, h=620),
    text_slide(*K("ak:18", '"May 2024: the strongest storm'), "G5", "May 2024: the strongest storm in 20 years", "Auroras were seen far south of the usual zone. Big storms followed in October 2024 and November 2025.", RED, h=620),
    text_slide(*K("ak:21", '"The best years are now"'), None, "The best years are now", "Activity stays high for a few years after the peak: winters 2025–2027 are a great time to go aurora hunting in Iceland.", h=620),
    app_slide("map-aurora", "Alerts when a storm is on its way", "NOAA warnings and NASA CME forecasts, filtered for you."),
])

# 09 · Driving rules
carousel("carousel-09-driving-rules", [
    cover_slide(*K("hero:roads", '"The rules every visitor shoul'), "Driving in Iceland", "The rules every visitor should know", fy=0.5),
    lambda im: (heading(im, "Speed limits", "Lower than you think", 200, 96),
                rows(im, [("90", "km/h on paved roads outside towns", AURORA), ("80", "km/h on gravel roads", YELLOW), ("50", "km/h in towns, often 30 in residential areas", ACCENT)], 480, h=170, big=96, left=260),
                source(im, "Icelandic Transport Authority (Samgöngustofa)")),
    text_slide(*K("fly:south-4", '"Headlights on, always"'), None, "Headlights on, always", "Day and night, all year. Seat belts for everyone in the car.", h=620),
    text_slide(*K("fly:golden-circle-15.5", '"Never drive off-road"'), None, "Never drive off-road", "Driving outside marked roads and tracks is illegal and damages the moss for decades. Fines are heavy.", RED, h=620),
    text_slide(*K("fly:westfjords-15.5", '"F-roads: 4×4 only"'), None, "F-roads: 4×4 only", "Highland roads open only in summer, usually from late June. Rivers are crossed without bridges: check before you go.", ACCENT, h=620),
    text_slide(*K("fly:glacier-lagoon-9.5", '"Never stop on the road"'), None, "Never stop on the road", "Not even for the perfect photo. Use the marked lay-bys: Icelandic roads have no hard shoulder.", YELLOW, h=620),
])

# 10 · Winter driving tips
def tip(n, title, body, src, credit, col=AURORA):
    return text_slide(src, credit, n, title, body, col, h=620)
carousel("carousel-10-winter-driving", [
    cover_slide(*K("fly:westfjords-18.5", '"6 tips for driving safely"'), "Winter in Iceland", "6 tips for driving safely", fy=0.6),
    tip("1", "Check before every drive", "Weather warnings on vedur.is and road conditions on umferdin.is (or call 1777). Conditions change in an hour.", *K("fly:westfjords-5", '"Check before every drive"')),
    tip("2", "Plan around daylight", "In December you have about 4 hours of daylight. Drive the long stretches while it's light.", *K("fly:south-1", '"Plan around daylight"'), BLUE),
    tip("3", "Watch the wind", "Above 20 m/s, park facing the wind and open doors with both hands: rental doors get bent every winter.", *K("fly:westfjords-6.5", '"Watch the wind"'), YELLOW),
    tip("4", "Black ice near zero", "Rain on a road around 0 °C freezes fast, especially on bridges and in shaded bends.", *K("fly:westfjords-9.5", '"Black ice near zero"'), RED),
    tip("5", "Keep the tank half full", "Distances between stations can be long, and you may need the heater if a road closes.", *K("fly:glacier-lagoon-5", '"Keep the tank half full"'), ACCENT),
    tip("6", "Leave your plan", "Register your route on safetravel.is. Rescuers will know where to look.", *K("fly:snaefellsnes-12.5", '"Leave your plan"')),
])

# 11 · Packing list
carousel("carousel-11-packing-list", [
    cover_slide(*K("fly:snaefellsnes-11", '"What to pack (and what to ski'), "Iceland in winter", "What to pack (and what to skip)", fy=0.5),
    lambda im: (heading(im, "Layers, not bulk", "The 3-layer rule", 200, 96),
                rows(im, [("1", "Wool base layer: warm even when damp", AURORA), ("2", "Fleece or light down", YELLOW), ("3", "Waterproof, windproof shell", ACCENT)], 480, h=170, big=96, left=200)),
    lambda im: (heading(im, "Don't forget", "Small things, big difference", 200, 96),
                rows(im, [("Spikes", "Microspikes for icy paths to waterfalls", BLUE), ("Light", "A head torch: days are short", YELLOW),
                          ("Swim", "Swimsuit for hot springs and pools", AURORA), ("Power", "Power bank: cold drains batteries", ACCENT)], 480, h=150, big=64, left=290)),
    text_slide(*K("fly:glacier-lagoon-14", '"Skip the umbrella"'), None, "Skip the umbrella", "With Icelandic wind it won't last a day. A good hood is all you need.", RED, h=620),
])

# 12 · Ring Road in 7 days (OSRM)
def ring_table(im):
    y = heading(im, "Ring Road · 7 days", "Day by day, by car", 160, 84)
    legs(im, S["ring"], y + 50)
    source(im, "OpenStreetMap / OSRM, fastest route, no stops")
carousel("carousel-12-ring-road-7-days", [
    cover_slide(*K("hero:map", '"The whole loop in 7 days"'), "Ring Road", "The whole loop in 7 days", "Real distances and driving times", fy=0.5),
    ring_table,
    text_slide(*K("fly:south-7", '"Add 30–50% to the times"'), None, "Add 30–50% to the times", "Photo stops, weather and gravel stretches: driving times on the map are the best case, especially in winter.", h=620),
    app_slide("trip", "Plan it day by day, with weather on every leg", "Stops, nights, attractions and road checks."),
])

# 13 · Golden Circle (OSRM)
def golden_table(im):
    y = heading(im, "The Golden Circle", "The classic day trip", 160, 84)
    legs(im, S["golden"], y + 50)
    source(im, "OpenStreetMap / OSRM, fastest route, no stops")
carousel("carousel-13-golden-circle", [
    cover_slide(*K("fly:golden-circle-0.5", '"Distances, times and timing"'), "Golden Circle", "Distances, times and timing"),
    golden_table,
    text_slide(*K("fly:golden-circle-18.5", '"Go early, or late"'), None, "Go early, or late", "Most tour buses come in the middle of the day. In winter, start at first light and end at Kerið for sunset.", h=620),
    app_slide("suggestions", "Ideas for every stop", "What to see nearby, with time needed and directions."),
])

# 14 · Geothermal Iceland
carousel("carousel-14-geothermal", [
    cover_slide(*K("nasa:blooms", '"How Iceland heats its homes"'), "Powered by the Earth", "How Iceland heats its homes", fy=0.4),
    numbers_slide("9 in 10", "homes heated by geothermal water", "Hot water from underground runs through district heating networks.", ACCENT, *K("fly:golden-circle-4.2", '"homes heated by geothermal wa')),
    numbers_slide("~100%", "renewable electricity", "About 70% hydropower and 30% geothermal.", AURORA, *K("fly:glacier-lagoon-13.2", '"renewable electricity"')),
    text_slide(*K("fly:glacier-lagoon-10.2", '"Drink from the tap"'), None, "Drink from the tap", "Cold tap water is among the cleanest in the world. Hot water may smell of sulphur: that's normal.", BLUE, h=620),
    lambda im: para(im, "National Energy Authority of Iceland (Orkustofnun): share of space heating from geothermal energy and electricity production by source.", heading(im, "Sources", "Where the numbers come from", 200, 100) + 36, 44, TEXT),
])

# 15 · Hot spring etiquette
carousel("carousel-15-hot-spring-etiquette", [
    cover_slide(*K("fly:golden-circle-10.2", '"The etiquette nobody tells yo'), "Hot springs", "The etiquette nobody tells you"),
    tip("1", "Shower first, without swimsuit", "It's the rule in every Icelandic pool and lagoon. Staff will check, and that's normal here.", *K("fly:golden-circle-16.2", '"Shower first, without swimsui')),
    tip("2", "Conditioner for your hair", "Silica and minerals leave hair stiff. Leave conditioner in, keep your head out of the water.", *K("fly:snaefellsnes-4.2", '"Conditioner for your hair"'), BLUE),
    tip("3", "Natural springs can be boiling", "Stay on paths and only bathe where it's marked as safe. Some are close to boiling.", *K("fly:golden-circle-7.2", '"Natural springs can be boilin'), RED),
    tip("4", "Leave no trace", "Many natural springs are on private land. Take everything back with you.", *K("fly:snaefellsnes-7.2", '"Leave no trace"'), YELLOW),
])

# 16 · Money in Iceland
carousel("carousel-16-money-tips", [
    cover_slide(*K("fly:golden-circle-5", '"Cards, tips and fuel pumps"'), "Money in Iceland", "Cards, tips and fuel pumps"),
    tip("1", "Cards everywhere", "Even for a coffee. Many visitors never touch cash during their whole trip.", *K("fly:snaefellsnes-13.2", '"Cards everywhere"')),
    tip("2", "No need to tip", "Service is included in prices. Rounding up for great service is welcome but not expected.", *K("fly:snaefellsnes-16.2", '"No need to tip"'), BLUE),
    tip("3", "Fuel pumps want a PIN", "Self-service pumps need a card with a PIN, or a prepaid card bought at the station.", *K("fly:glacier-lagoon-4.2", '"Fuel pumps want a PIN"'), YELLOW),
    lambda im: (icon(im, "coins", 64, 170, 200),
                para(im, "Rate of 31 October 2026. Check today's rate: it changes every day.", heading(im, "Króna in your currency", "1,000 kr ≈ €7.35", 420, 130) + 24, 40, TEXT),
                source(im, "ExchangeRate-API, 31 October 2026")),
    app_slide("currency", "Every currency in the world", "Prices in króna converted, and a converter."),
])

# 17 · 5 mistakes tourists make
carousel("carousel-17-tourist-mistakes", [
    cover_slide(*K("fly:ring-road-18.5", '"5 mistakes tourists make"'), "Iceland", "5 mistakes tourists make", "And how to avoid them", fy=0.5),
    tip("1", "Turning your back to the sea", "At Reynisfjara, sneaker waves reach far up the beach without warning. Watch the warning lights, stay well back.", *K("fly:glacier-lagoon-17", '"Turning your back to the sea"'), RED),
    tip("2", "Ignoring a yellow warning", "Yellow means disruption is possible: gusts, poor visibility. Check your route before you set off.", *K("fly:westfjords-4.2", '"Ignoring a yellow warning"'), YELLOW),
    tip("3", "Underestimating distances", "Maps say 3 hours. With weather, gravel and stops, plan for 4–5.", *K("fly:westfjords-7.2", '"Underestimating distances"'), ACCENT),
    tip("4", "Stopping on the road", "For a photo, a horse, the aurora. It causes accidents every year: use lay-bys.", *K("fly:glacier-lagoon-7.2", '"Stopping on the road"'), BLUE),
    tip("5", "Chasing the aurora on Kp alone", "Clouds and darkness matter more. Check the sky where you are.", *K("ak:22.5", '"Chasing the aurora on Kp alon'), AURORA),
])

# 18 · South coast
def south_table(im):
    y = heading(im, "South coast", "Reykjavík to the glacier lagoon", 160, 84)
    legs(im, S["south"], y + 50)
    source(im, "OpenStreetMap / OSRM, fastest route, no stops")
carousel("carousel-18-south-coast", [
    cover_slide(*K("fly:glacier-lagoon-0.5", '"Waterfalls, black sand, icebe'), "South coast", "Waterfalls, black sand, icebergs", fy=0.5),
    south_table,
    text_slide(*K("fly:glacier-lagoon-3.5", '"Better in two days"'), None, "Better in two days", "Seljalandsfoss, Skógafoss, Reynisfjara, Fjaðrárgljúfur, Jökulsárlón: with stops it's 2 days, not 1.", h=620),
    app_slide("stop-detail", "Every stop with weather, roads and ideas", "Including shops and fuel nearby."),
])
print("ok")
