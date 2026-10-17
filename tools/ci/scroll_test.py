#!/usr/bin/env python3
"""Scrolls every screen to the very bottom with real swipes and takes a
screenshot there, to check that nothing ends up hidden behind the tab bar or
cut off. Also opens the map's point card (tap on the map) to check the bottom
panel. Usage: scroll_test.py <udid> <out_dir>
"""
import subprocess, sys, time

udid, out = sys.argv[1], sys.argv[2]
APP = "it.lorenzosavini.nordur"
# name, launch arguments
SCREENS = [
    ("today", ["-initialTab", "today"]), ("weather", ["-initialTab", "weather"]),
    ("drive", ["-initialTab", "drive"]), ("trip", ["-initialTab", "trip"]),
    ("aurora", ["-initialTab", "kp"]), ("aurora-live", ["-initialTab", "aurora"]),
    ("account", ["-initialTab", "account"]),
] + [(f"s.{s}", ["-ciScreen", s]) for s in
     ["alerts", "alertSettings", "info", "roads", "quakes", "warnings", "transport", "webcams", "offline", "stop", "settings"]]

def idb(*args):
    return subprocess.run(["idb", *args, "--udid", udid], capture_output=True, text=True, timeout=60)

def shot(name):
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", f"{out}/{name}.png"], capture_output=True)

def launch(args):
    subprocess.run(["xcrun", "simctl", "terminate", udid, APP], capture_output=True)
    subprocess.run(["xcrun", "simctl", "launch", udid, APP, *args, "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"], capture_output=True)

report = []
for name, args in SCREENS:
    launch(args)
    time.sleep(16)
    for _ in range(12):  # swipe up from the lower middle to the top: scrolls down the content
        idb("ui", "swipe", "200", "700", "200", "200", "--duration", "0.15")
        time.sleep(0.6)
    time.sleep(1.5)
    shot(f"bottom-{name}")
    report.append(f"bottom-{name}.png")

# Map with the point card open (tap on land), panel at its tallest.
launch(["-initialTab", "map"])
time.sleep(16)
idb("ui", "tap", "250", "560")
time.sleep(3)
shot("bottom-map-probe")
idb("ui", "swipe", "200", "690", "200", "560", "--duration", "0.2")  # scroll inside the panel
time.sleep(1.5)
shot("bottom-map-probe-scrolled")
report += ["bottom-map-probe.png", "bottom-map-probe-scrolled.png"]
open(f"{out}/scroll-test.txt", "w").write("\n".join(report) + "\n")
print("\n".join(report))
