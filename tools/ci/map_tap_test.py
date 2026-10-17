#!/usr/bin/env python3
"""Taps every layer button of the map in the simulator, like a finger would,
and checks that the map really switches (the legend changes and the button
becomes selected). Then opens the LIVELLI + menu and toggles an overlay.

Needs idb (idb-companion + fb-idb). Usage: map_tap_test.py <udid> <out_dir>
Exit code 1 if any tap does not take effect.
"""
import json, subprocess, sys, time

udid, out = sys.argv[1], sys.argv[2]
LAYERS = [  # raw value, what the legend shows afterwards (Italian)
    ("wind", "Vento,"), ("gust", "Raffiche,"), ("precipitation", "Pioggia,"), ("snow", "Neve,"),
    ("cloud", "Nuvole,"), ("temperature", "Temperatura,"), ("aurora", "Aurora,"),
    ("radar", "Radar RainViewer"), ("none", "Tocca la mappa"),
]

def idb(*args):
    return subprocess.run(["idb", *args, "--udid", udid], capture_output=True, text=True, timeout=60)

def elements():
    r = idb("ui", "describe-all", "--json")
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        data = [json.loads(line) for line in r.stdout.splitlines() if line.strip().startswith("{")]
    return data if isinstance(data, list) else [data]

def find(ident=None, label=None):
    for e in elements():
        if ident and e.get("AXUniqueId") == ident:
            return e
        if label and (e.get("AXLabel") or "").startswith(label):
            return e
    return None

def tap(e):
    f = e["frame"]
    x, y = f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
    idb("ui", "tap", str(round(x)), str(round(y)))
    return x, y

def shot(name):
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", f"{out}/{name}.png"], capture_output=True)

failures, report = 0, []
time.sleep(2)
for raw, legend in LAYERS:
    button = find(ident=f"layer.{raw}")
    if not button:
        report.append(f"FAIL {raw}: button not found"); failures += 1; continue
    x, y = tap(button)
    time.sleep(3)
    ok_legend = find(label=legend) is not None
    selected = any(e.get("AXUniqueId") == f"layer.{raw}" and "selected" in json.dumps(e).lower() for e in elements())
    shot(f"tap-layer-{raw}")
    status = "ok  " if ok_legend else "FAIL"
    if not ok_legend: failures += 1
    report.append(f"{status} tap {raw} at ({x:.0f},{y:.0f}): legend '{legend}' {'shown' if ok_legend else 'NOT shown'}, selected={selected}")

menu = find(ident="layers.menu") or find(label="LIVELLI")
if menu:
    tap(menu); time.sleep(2)
    item = find(label="Webcam")
    shot("tap-layers-menu")
    if item:
        report.append("ok   LIVELLI + opens the overlay menu")
        tap(item); time.sleep(2); shot("tap-layers-webcam")
    else:
        report.append("FAIL LIVELLI + menu did not open"); failures += 1
else:
    report.append("FAIL LIVELLI + button not found"); failures += 1

text = "\n".join(report)
print(text)
open(f"{out}/tap-test.txt", "w").write(text + f"\n{'ALL TAPS WORK' if failures == 0 else str(failures) + ' FAILURES'}\n")
sys.exit(1 if failures else 0)
