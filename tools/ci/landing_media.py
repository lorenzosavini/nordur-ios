#!/usr/bin/env python3
"""Screenshots and short loops of Norður in each language, for the website
(site/landing): the same screens and launch arguments as the CI screenshots,
dark appearance, demo trip and aurora. Written to <out>/<lang>/<name>.png|mp4.

Needs idb (idb-companion + fb-idb) for swipes and taps.
Usage: landing_media.py <udid> <out> [langs] [set]
  set: "site" (default, the website's media) or "post" (every screen, for social posts,
  with real notifications on the lock screen).
"""
import os, signal, subprocess, sys, time

udid, out = sys.argv[1], sys.argv[2]
langs = (sys.argv[3] if len(sys.argv) > 3 else "it,en,de,fr,es").split(",")
SET = sys.argv[4] if len(sys.argv) > 4 else "site"
BUNDLE = "it.lorenzosavini.nordur"
W, H = 402, 874
LOCALE = {"it": "it_IT", "en": "en_GB", "de": "de_DE", "fr": "fr_FR", "es": "es_ES"}

def idb(*args):
    try:
        subprocess.run(["idb", *args, "--udid", udid], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        print("idb timed out:", " ".join(args))

def scroll(times=1, distance=0.45, pause=1.6):
    for _ in range(times):
        idb("ui", "swipe", str(W // 2), str(round(H * 0.74)), str(W // 2), str(round(H * (0.74 - distance))), "--duration", "0.5")
        time.sleep(pause)

def at(x, y, pause=2.4):
    idb("ui", "tap", str(round(x)), str(round(y)))
    time.sleep(pause)

def notify(command, pause=3):
    subprocess.run(["xcrun", "simctl", "spawn", udid, "notifyutil", "-p", f"nordur.ci.{command}"], capture_output=True)
    time.sleep(pause)

def launch(lang, args, settle):
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    time.sleep(1)
    subprocess.run(["xcrun", "simctl", "launch", udid, BUNDLE, "-ciAuroraDemo", "YES", "-ciDemoTrip", "YES", "-ciAlertsYellow", "YES",
                    "-appearance", "dark", "-AppleLanguages", f"({lang})", "-AppleLocale", LOCALE[lang], *args], capture_output=True)
    time.sleep(settle)

def shot(lang, name, args, settle=18):
    launch(lang, args, settle)
    path = os.path.join(out, lang, f"{name}.png")
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", path], capture_output=True)
    print("shot", lang, name, os.path.exists(path))

def clip(lang, name, args, steps, settle=12):
    launch(lang, args, settle)
    path = os.path.join(out, lang, f"{name}.mp4")
    rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    for step in steps:
        step[0](*step[1:])
    time.sleep(1.2)
    rec.send_signal(signal.SIGINT)
    try:
        rec.wait(timeout=60)
    except subprocess.TimeoutExpired:
        rec.kill()
    print("clip", lang, name, os.path.getsize(path) if os.path.exists(path) else 0)

today, aurora = ["-initialTab", "today"], ["-initialTab", "aurora", "-ciAuroraMain", "YES"]
SHOTS = [
    ("today", today), ("aurora", aurora), ("weather", ["-initialTab", "weather"]),
    ("map-aurora", ["-initialTab", "map", "-map.layer", "aurora"]), ("map-wind", ["-initialTab", "map", "-map.layer", "wind"]),
    ("map-radar", ["-initialTab", "map", "-map.layer", "radar"]), ("trip", ["-initialTab", "trip", "-trip.view", "days"]),
    ("roads", today + ["-ciScreen", "roads"]), ("explore", today + ["-ciScreen", "sights"]), ("quakes", today + ["-ciScreen", "quakes"]),
    ("webcams", today + ["-ciScreen", "webcams"]), ("alerts", today + ["-ciScreen", "alertSettings"]),
    ("offline", today + ["-ciScreen", "offline"]), ("info", today + ["-ciScreen", "info"]),
]
ALLOW = {"it": "Consenti", "en": "Allow", "de": "Erlauben", "fr": "Autoriser", "es": "Permitir"}

def tap_label(label):
    """Taps the element whose accessibility label is `label` (the system's permission alert)."""
    try:
        r = subprocess.run(["idb", "ui", "describe-all", "--udid", udid], capture_output=True, text=True, timeout=60)
        import json
        for e in json.loads(r.stdout or "[]"):
            if (e.get("AXLabel") or "") == label:
                f = e["frame"]
                at(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2, 2)
                return True
    except Exception as ex:
        print("describe-all", ex)
    return False

def button(name, pause=2.5):
    idb("ui", "button", name)
    time.sleep(pause)

def capture(lang, name):
    path = os.path.join(out, lang, f"{name}.png")
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", path], capture_output=True)
    print("shot", lang, name, os.path.exists(path))

def notifications(lang):
    """Real notifications: banners while open, then the lock screen and Notification Centre."""
    launch(lang, today + ["-ciAskNotifications", "YES"], 10)
    tap_label(ALLOW[lang]) or tap_label("Allow")
    time.sleep(2)
    notify("notify.demo", 2)
    capture(lang, "notification-banner")
    time.sleep(4)
    button("HOME")
    button("LOCK", 3)
    button("HOME", 4)
    capture(lang, "notifications-lock")
    # Unlock (no passcode): a swipe up from the bottom edge.
    idb("ui", "swipe", str(W // 2), str(H - 4), str(W // 2), str(H // 3), "--duration", "0.3")
    time.sleep(3)
    shot(lang, "alerts-inbox", today + ["-ciScreen", "alerts"])

POST_SHOTS = [
    ("shops", today + ["-ciScreen", "shops"]), ("fuel", today + ["-ciScreen", "fuel"]),
    ("stop-detail", ["-initialTab", "trip", "-ciScreen", "stopDetail"]), ("suggestions", ["-initialTab", "trip", "-ciScreen", "suggestions"]),
    ("sight", today + ["-ciScreen", "sight"]), ("currency", today + ["-ciScreen", "currency"]),
    ("transport", today + ["-ciScreen", "transport"]), ("warnings", today + ["-ciScreen", "warnings"]),
    ("settings", today + ["-ciScreen", "settings"]), ("trip-stops", ["-initialTab", "trip", "-trip.view", "stops"]),
    ("trip-map", ["-initialTab", "trip", "-trip.view", "map"]), ("share", today + ["-ciScreen", "share"]),
]

if SET == "post":
    for lang in langs:
        os.makedirs(os.path.join(out, lang), exist_ok=True)
        launch(lang, today, 35)
        notifications(lang)
        for name, args in SHOTS + POST_SHOTS:
            shot(lang, name, args)
    sys.exit(0)

for lang in langs:
    os.makedirs(os.path.join(out, lang), exist_ok=True)
    # First launch in this language: data and photos load once.
    launch(lang, today, 35)
    clip(lang, "aurora", aurora, [(time.sleep, 2.5), (scroll, 1, 0.35, 2.5), (scroll, 1, 0.4, 2.5)])
    clip(lang, "today", today, [(time.sleep, 2), (scroll, 1, 0.3, 2.2), (scroll, 1, 0.4, 2.2), (scroll, 1, 0.4, 2)])
    clip(lang, "map", ["-initialTab", "map"], [(time.sleep, 2), *[(at, x, y, 2.4) for x, y in [(250, 130), (62, 166), (150, 166), (237, 166), (75, 201)]]])
    clip(lang, "trip", ["-initialTab", "trip", "-trip.view", "days"], [(time.sleep, 2.5), (scroll, 1, 0.4, 2.5), (scroll, 1, 0.45, 2.5)])
    clip(lang, "drive", today, [(notify, "drive.demo", 6), (scroll, 1, 0.45, 2.5)])
    for name, args in SHOTS:
        shot(lang, name, args)
