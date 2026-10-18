#!/usr/bin/env python3
"""Records a demo video of Norður in the simulator: every tab, scrolling,
the aurora screen, the map layers (wind particles, gusts, temperature,
aurora oval, radar), a tap on the map, Drive and Trip.

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
    except (json.JSONDecodeError, subprocess.TimeoutExpired):
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

def tap_at(x, y, pause=1.5):
    idb("ui", "tap", str(round(x)), str(round(y)))
    time.sleep(pause)

def tap(ident=None, label=None, exact=False, pause=2.0):
    for _ in range(4):
        e = find(ident=ident, label=label, exact=exact)
        if e:
            f = e["frame"]
            tap_at(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2, pause)
            return True
        time.sleep(1.5)
    print(f"not found: {ident or label}")
    return False

# Screen size in points, from the application element (the accessibility
# tree can take a while to answer after launch); iPhone Pro size otherwise.
W, H = 402, 874
for _ in range(20):
    found = elements()
    if found and "frame" in found[0]:
        W, H = found[0]["frame"]["width"], found[0]["frame"]["height"]
        break
    time.sleep(3)
print("screen", W, H)

def scroll(times=1, distance=0.45, pause=1.6):
    for _ in range(times):
        idb("ui", "swipe", str(round(W / 2)), str(round(H * 0.72)), str(round(W / 2)), str(round(H * (0.72 - distance))), "--duration", "0.7")
        time.sleep(pause)

def scroll_top():
    for _ in range(3):
        idb("ui", "swipe", str(round(W / 2)), str(round(H * 0.3)), str(round(W / 2)), str(round(H * 0.85)), "--duration", "0.3")
        time.sleep(0.4)

def back():
    # The navigation back button sits top left.
    tap_at(28, 70, 1.8)

rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", out])
time.sleep(3)

# Today: header, aurora now, explore tiles, next hours, details.
time.sleep(4)
scroll(1, 0.3, 2.5)
scroll(3)
scroll_top()
time.sleep(1)

# Aurora screen from the Today panel.
if tap(label="AURORA ADESSO", pause=3.5) or tap(label="Aurora", pause=3.5):
    scroll(4, 0.45, 2.0)
    back()
scroll_top()

# Weather.
tap(label="Meteo", exact=True, pause=3)
scroll(4)

# Map: layers, then a tap on the map for the values there.
tap(label="Mappa", exact=True, pause=4)
for layer, wait in [("wind", 6), ("gust", 3.5), ("temperature", 3.5), ("precipitation", 3), ("aurora", 4), ("radar", 4), ("wind", 2)]:
    tap(ident=f"layer.{layer}", pause=wait)
tap_at(W * 0.45, H * 0.42, 4)

# Drive and Trip.
tap(label="Guida", exact=True, pause=3)
scroll(3)
tap(label="Viaggio", exact=True, pause=3)
scroll(2)

# Back to Today.
tap(label="Oggi", exact=True, pause=3)
time.sleep(2)

rec.send_signal(signal.SIGINT)
rec.wait(timeout=60)
print("video saved", out)
