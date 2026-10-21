#!/usr/bin/env python3
"""Records a structured demo of Norður in the simulator, chapter by chapter,
and writes the chapters (start time, title, subtitle) next to the video so the
workflow can put a caption on each:

  0 Opening        the launch animation
  1 Today          at a glance, today's trip, aurora now and the report buttons,
                   next hours, explore (things to see, roads, volcanoes, webcams)
  2 Weather        the forecast
  3 Aurora         the three answers, "how it is worked out", live, 24 h, 3 days,
                   red night vision
  4 Map            every layer, time, full screen, a point, layers menu
  5 Trip           day by day, an attraction with photo and description, stops,
                   one stop with suggestions, the route map, sharing, received
  6 Drive          a recorded route and its 3D picture for Instagram
  7 Settings       backup, night vision, sources and data status

Needs idb (idb-companion + fb-idb). Usage: demo_video.py <udid> <out.mp4> <chapters.json>
"""
import json, signal, subprocess, sys, time

udid, out, chapters_path = sys.argv[1], sys.argv[2], sys.argv[3]
BUNDLE = "it.lorenzosavini.nordur"

def idb(*args):
    # A slow answer from idb skips that step instead of ending the recording.
    try:
        return subprocess.run(["idb", *args, "--udid", udid], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        print("idb timed out:", " ".join(args))
        return subprocess.CompletedProcess(args, 1, "", "")

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

def screen_size():
    global W, H
    for _ in range(20):
        found = elements()
        if found and "frame" in found[0]:
            W, H = found[0]["frame"]["width"], found[0]["frame"]["height"]
            return
        time.sleep(2)

def tap_at(x, y, pause=1.2):
    idb("ui", "tap", str(round(x)), str(round(y)))
    time.sleep(pause)

def swipe(x1, y1, x2, y2, duration=0.5, pause=0.9):
    idb("ui", "swipe", str(round(x1)), str(round(y1)), str(round(x2)), str(round(y2)), "--duration", str(duration))
    time.sleep(pause)

def scroll(times=1, distance=0.45, pause=1.3):
    for _ in range(times):
        swipe(W / 2, H * 0.74, W / 2, H * (0.74 - distance), 0.5, pause)

def scroll_top():
    for _ in range(5):
        swipe(W / 2, H * 0.25, W / 2, H * 0.85, 0.2, 0.3)
    time.sleep(0.8)

def back():
    swipe(3, H * 0.5, W * 0.85, H * 0.5, 0.3, 1.5)

def dismiss_sheet():
    swipe(W / 2, H * 0.1, W / 2, H * 0.97, 0.35, 1.6)

def tap(ident=None, label=None, exact=False, pause=1.8, scrolls=0, anywhere=False, fallback=None):
    """Taps an element, scrolling down to find it (up to `scrolls` times);
    `fallback` (x, y as fractions of the screen) when it is not in the tree."""
    for attempt in range(scrolls + 2):
        e = find(ident=ident, label=label, exact=exact)
        if e and (anywhere or e["frame"]["y"] + e["frame"]["height"] / 2 < H * 0.88):
            f = e["frame"]
            tap_at(f["x"] + f["width"] / 2, f["y"] + f["height"] / 2, pause)
            return True
        if attempt < scrolls:
            scroll(1, 0.35, 0.9)
        else:
            time.sleep(0.8)
    if fallback:
        print(f"fallback tap: {ident or label}")
        tap_at(W * fallback[0], H * fallback[1], pause)
        return True
    print(f"not found: {ident or label}")
    return False

# Tab bar: five equal buttons under the pages.
TABS = ["Oggi", "Meteo", "Aurora", "Mappa", "Viaggio"]

KEYS = ["today", "weather", "aurora", "map", "trip"]

def notify(command, pause=2.4):
    pause += 3   # the app closes what is open first, then opens (slow simulator)
    """The app listens for these in the demo run (CIRemote): taps from idb on
    the tab bar do not always land."""
    subprocess.run(["xcrun", "simctl", "spawn", udid, "notifyutil", "-p", f"nordur.ci.{command}"], capture_output=True)
    time.sleep(pause)

def tab(name):
    notify("tab." + KEYS[TABS.index(name)])

chapters = []
t0 = None

def chapter(title, subtitle):
    chapters.append({"t": round(time.time() - t0, 2), "title": title, "subtitle": subtitle})
    print("chapter", chapters[-1])

# The app is launched by the workflow (stopped first) inside the recording, so the opening is filmed.
subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", out])
t0 = time.time() + 0.6   # the recorder starts writing about half a second later
time.sleep(2.5)

# 0 · Opening
chapter("Norður", "Islanda: aurora, meteo, strade e viaggio in un'app sola")
subprocess.run(["xcrun", "simctl", "launch", udid, BUNDLE, "-initialTab", "today", "-ciShowLaunch", "YES", "-ciAuroraDemo", "YES", "-ciDemoTrip", "YES",
                "-ciAlertsYellow", "YES", "-appearance", "dark", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"], capture_output=True)
time.sleep(8)   # the data arrive

# No accessibility queries from here on: idb's describe-all can hang the app
# (screens with many map pins), so screens open with commands the app listens
# for in the demo run (notify) and the rest is swipes and taps by position
# (points on a 402 × 874 screen).
def at(x, y, pause=2.2):
    tap_at(W * x / 402, H * y / 874, pause)

# 1 · Today
chapter("1 · Oggi", "In breve: aurora stanotte, prossime ore, strade e allerte")
time.sleep(3)
scroll(1, 0.3, 2.5)
chapter("1 · Oggi", "Il viaggio di oggi e l'aurora adesso, con «vedo / non vedo»")
scroll(1, 0.35, 2.8)
scroll(1, 0.4, 2.2)
chapter("1 · Oggi", "Esplora: da vedere, strade, vulcani, webcam")
time.sleep(1.5)
notify("screen.sights", 3.5)
chapter("Da vedere", "Cascate, belvedere, sorgenti calde: 1.300 luoghi su mappa")
time.sleep(2)
scroll(1, 0.4, 2)
scroll(1, 0.45, 2.5)
notify("screen.roads", 3.5)
chapter("Strade", "Condizioni in tempo reale di Vegagerðin: chiuse, ghiaccio, vento")
scroll(1, 0.4, 2)
notify("screen.quakes", 3.5)
chapter("Vulcani e terremoti", "Scosse delle ultime 48 ore dall'IMO")
scroll(1, 0.4, 2)
notify("screen.webcams", 3.5)
chapter("Webcam", "Le strade come sono adesso")
scroll(1, 0.4, 2)
notify("dismiss", 1.5)
scroll(2, 0.45, 1.5)
chapter("1 · Oggi", "Terra, mare e servizi: carburante, voli, spesa")
scroll(1, 0.45, 2)

# 2 · Weather
tab("Meteo")
chapter("2 · Meteo", "MET Norway + Open-Meteo, ora per ora, con i rischi")
time.sleep(2)
scroll(3, 0.45, 1.6)

# 3 · Aurora
tab("Aurora")
notify("aurora.mode.live", 1)
scroll_top()
chapter("3 · Aurora", "Attività, osservabilità qui, affidabilità")
time.sleep(3)
scroll(1, 0.4, 2)
chapter("3 · Aurora", "Tempo reale: vento solare, Bz, Hp30, magnetometro, Kp")
scroll(3, 0.5, 1.6)
scroll_top()
notify("aurora.mode.day", 2.5)
chapter("3 · Aurora", "Previsione a 24 ore e località migliori stanotte")
scroll(2, 0.45, 1.5)
scroll_top()
notify("aurora.mode.three", 2.5)
chapter("3 · Aurora", "Tre giorni: Kp a blocchi di 3 ore e le notti")
scroll(2, 0.45, 1.5)
scroll_top()
notify("aurora.mode.live", 1.5)
notify("night", 3.5)
chapter("3 · Aurora", "Visione notturna rossa: non perdi l'adattamento al buio")
time.sleep(1.5)
notify("night", 1.5)

# 4 · Map
tab("Mappa")
chapter("4 · Mappa", "Vento, raffiche, pioggia, neve, nuvole, temperatura, aurora, radar")
time.sleep(3)
for x, y in [(250, 130), (62, 166), (150, 166), (237, 166), (75, 201), (185, 201), (275, 201), (157, 130)]:
    at(x, y, 2.6)
at(31, 719, 5)      # play the next hours
at(31, 719, 1.5)    # pause
at(360, 505, 3.5)   # a point at sea off the east coast, away from the pins
chapter("4 · Mappa", "Tocca un punto: meteo, aurora e strada in quel posto")
time.sleep(2)
at(367, 604, 3)     # full screen
chapter("4 · Mappa", "A schermo intero, legenda e tempo sopra la mappa")
time.sleep(2.5)
notify("dismiss", 1.5)

# 5 · Trip
tab("Viaggio")
notify("trip.mode.days", 1)
scroll_top()
chapter("5 · Viaggio", "Giorno per giorno: tragitto, notte, meteo e attrazioni con orari")
time.sleep(3)
scroll(1, 0.4, 2.2)
scroll(1, 0.45, 2.2)
scroll(1, 0.45, 2.2)
scroll_top()
notify("trip.mode.stops", 2.5)
chapter("5 · Viaggio", "Le tappe: dove dormi, con il tragitto tra l'una e l'altra")
scroll(2, 0.4, 2)
scroll_top()
notify("trip.mode.map", 3.5)
chapter("5 · Viaggio", "Il percorso sulla mappa, tappe numerate e attrazioni")
time.sleep(2)
notify("trip.mode.days", 1.5)
notify("trip.share", 3)
chapter("5 · Viaggio", "Condividi: modificatelo insieme, o una copia via email")
scroll(1, 0.4, 2)
notify("dismiss", 1.5)
notify("trip.inbox", 3)
chapter("5 · Viaggio", "Ricevuti: inviti a modificare insieme e copie")
notify("dismiss", 1.5)

# 6 · Drive
notify("trip.drive", 3)
chapter("6 · Guida", "Registra il percorso: strade davanti, vento, avvisi vocali")
scroll(2, 0.45, 1.8)
notify("drive.demo", 3.5)
chapter("6 · Guida", "Ogni percorso: mappa, dati, GPX, rifallo con Mappe")
scroll(1, 0.45, 1.8)
notify("drive.share", 10)
chapter("6 · Guida", "Condividi su Instagram: immagine e video in 3D")
time.sleep(5)
notify("dismiss", 1.5)

# 7 · Settings
tab("Oggi")
notify("settings", 3)
chapter("7 · Impostazioni", "Backup automatico, visione notturna, fonti e stato dei dati")
scroll(1, 0.4, 2)
scroll(1, 0.4, 2)
notify("screen.sources", 3.5)
chapter("7 · Impostazioni", "Fonti e stato dei dati: ogni fonte, quando è stata aggiornata")
scroll(1, 0.45, 2)
notify("dismiss", 2)
chapter("Norður", "Dal 6 al 13 novembre in Islanda: lo provo sul campo")
time.sleep(3.5)

rec.send_signal(signal.SIGINT)
rec.wait(timeout=60)
json.dump({"chapters": chapters, "duration": round(time.time() - t0, 2)}, open(chapters_path, "w"), ensure_ascii=False, indent=1)
print("chapters", len(chapters))
