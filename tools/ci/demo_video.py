#!/usr/bin/env python3
"""Records a demo video of Norður in the simulator, through every section:
Today (aurora now), the Aurora screen, Roads (critical sections and one
section), Webcams, Volcanoes and earthquakes, the alert inbox and one alert,
Weather, every Map layer and a tap on the map, Drive, Trip (an itinerary,
one stop, and adding a stop with the place picker).

Needs idb (idb-companion + fb-idb). Usage: demo_video.py <udid> <out.mp4>
"""
import json, signal, subprocess, sys, time

udid, out = sys.argv[1], sys.argv[2]

def idb(*args):
    return subprocess.run(["idb", *args, "--udid", udid], capture_output=True, text=True, timeout=60)

def elements():
    try:
        r = idb("ui", "describe-all", "--json")
        data = json.loads(r.stdout)
    except Exception:
        try:
            data = [json.loads(line) for line in r.stdout.splitlines() if line.strip().startswith("{")]
        except Exception:
            data = []
    return data if isinstance(data, list) else [data]

def find(ident=None, label=None, exact=False):
    for e in elements():
        if ident and e.get("AXUniqueId") == ident:
            return e
        text = e.get("AXLabel") or ""
        if label and (text == label if exact else text.startswith(label)):
            return e
    return None

W, H = 402, 874
for _ in range(20):
    found = elements()
    if found and "frame" in found[0]:
        W, H = found[0]["frame"]["width"], found[0]["frame"]["height"]
        break
    time.sleep(3)
print("screen", W, H)

def tap_at(x, y, pause=1.2):
    idb("ui", "tap", str(round(x)), str(round(y)))
    time.sleep(pause)

def swipe(x1, y1, x2, y2, duration=0.5, pause=0.9):
    idb("ui", "swipe", str(round(x1)), str(round(y1)), str(round(x2)), str(round(y2)), "--duration", str(duration))
    time.sleep(pause)

def scroll(times=1, distance=0.45, pause=1.1):
    for _ in range(times):
        swipe(W / 2, H * 0.74, W / 2, H * (0.74 - distance), 0.45, pause)

def scroll_top():
    for _ in range(4):
        swipe(W / 2, H * 0.25, W / 2, H * 0.85, 0.2, 0.3)
    time.sleep(0.8)

def back():
    swipe(3, H * 0.5, W * 0.85, H * 0.5, 0.3, 1.4)

def dismiss_sheet():
    swipe(W / 2, H * 0.12, W / 2, H * 0.95, 0.35, 1.6)

def tap(ident=None, label=None, exact=False, pause=1.8, scrolls=0, anywhere=False, fallback=None):
    """Taps an element, scrolling down to find it (up to `scrolls` times);
    `fallback` (x, y as fractions of the screen) when it is not in the tree."""
    for attempt in range(scrolls + 3):
        e = find(ident=ident, label=label, exact=exact)
        if e and (anywhere or e["frame"]["y"] + e["frame"]["height"] / 2 < H * 0.88):
            f = e["frame"]
            tap_at(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2, pause)
            return True
        if attempt < scrolls:
            scroll(1, 0.35, 0.8)
        else:
            time.sleep(1)
    if fallback:
        print(f"fallback tap: {ident or label}")
        tap_at(W * fallback[0], H * fallback[1], pause)
        return True
    print(f"not found: {ident or label}")
    return False

# Tab bar: five equal buttons under the pages.
TABS = ["Oggi", "Meteo", "Mappa", "Guida", "Viaggio"]

def tab(name):
    i = TABS.index(name)
    tap(label=name, exact=True, pause=2.2, anywhere=True, fallback=((i + 0.5) / 5, 0.955))

def ids(where):
    print(where, sorted({e.get("AXUniqueId") for e in elements() if e.get("AXUniqueId")}))

rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", out])
time.sleep(2.5)

# 1 · Today and the aurora now.
time.sleep(2)
scroll(1, 0.3, 2.2)
ids("today")
if tap(ident="tile.Aurora", pause=3, scrolls=3) or tap(ident="today.aurora", pause=3):
    scroll(5, 0.5, 1.2)       # Aurora: hour by hour, solar wind, Kp, Hp30, magnetometer
    back()

# 2 · Roads: critical sections, then one section.
scroll_top()
if tap(ident="tile.Strade", pause=2.5, scrolls=3):
    ids("roads")
    tap(label="Critici", exact=True, pause=2, fallback=(0.36, 0.426))
    if tap(ident="road.row", pause=2.5):
        scroll(1, 0.4, 1.4)
        back()
    back()

# 3 · Volcanoes and earthquakes.
if tap(ident="tile.Vulcani e terremoti", pause=2.5, scrolls=3):
    scroll(1, 0.4, 1.4)
    back()

# 4 · Webcams (Today › details).
if tap(label="WEBCAM", exact=True, pause=2.5, scrolls=4):
    scroll(1, 0.3, 1.5)

# 5 · The alert inbox and one alert.
scroll_top()
if tap(ident="today.alerts", pause=2.2) or tap(label="Allerte", exact=True, pause=2.2, fallback=(1 - 27 / 402, 64 / 874)):
    ids("alerts")
    if tap(ident="alert.row", pause=2.5):
        scroll(1, 0.4, 1.4)
        back()
    dismiss_sheet()

# 6 · Weather.
tab("Meteo")
scroll(4, 0.5, 1.1)

# 7 · Map: every layer, then a tap for the values at a point.
tab("Mappa")
time.sleep(1.5)
for layer, wait in [("wind", 4), ("gust", 2.2), ("temperature", 2.2), ("precipitation", 2), ("snow", 1.8), ("cloud", 1.8), ("aurora", 3), ("radar", 3), ("wind", 1.5)]:
    tap(ident=f"layer.{layer}", pause=wait)
tap_at(W * 0.45, H * 0.4, 3.5)
# The tap may open a road section or the values card: close it so the tab bar is free.
dismiss_sheet()
tap_at(W * 0.5, H * 0.08, 0.8)

# 8 · Drive.
tab("Guida")
scroll(3, 0.5, 1.1)

# 9 · Trip: the itinerary, one stop, then adding a stop.
tab("Viaggio")
scroll(2, 0.45, 1.4)
if tap(ident="trip.stop", pause=2.5):
    scroll(1, 0.4, 1.2)
    dismiss_sheet()
scroll_top()
if tap(ident="trip.add", pause=2.2):
    if tap(ident="stop.place", pause=2):
        if not tap(ident="place.Jökulsárlón", pause=1.8, scrolls=6):
            dismiss_sheet()
    scroll(1, 0.4, 1.2)
    if not tap(ident="stop.save", pause=2.5, scrolls=3):
        dismiss_sheet()
scroll(2, 0.45, 1.2)

# 10 · Back to Today.
tab("Oggi")
time.sleep(2)

rec.send_signal(signal.SIGINT)
rec.wait(timeout=60)
print("video saved", out)
