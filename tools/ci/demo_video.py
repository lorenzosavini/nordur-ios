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
time.sleep(4)
screen_size()
time.sleep(4)   # the data arrive

# 1 · Today
chapter("1 · Oggi", "In breve: aurora stanotte, prossime ore, strade e allerte")
time.sleep(3)
scroll(1, 0.3, 2.5)
chapter("1 · Oggi", "Il viaggio di oggi e l'aurora adesso, con «vedo / non vedo»")
scroll(1, 0.35, 2.8)
scroll(1, 0.4, 2.2)
chapter("1 · Oggi", "Esplora: da vedere, strade, vulcani, webcam")
if tap(ident="tile.Da vedere", pause=3, scrolls=2):
    chapter("Da vedere", "Cascate, belvedere, sorgenti calde: 1.300 luoghi su mappa")
    time.sleep(2)
    scroll(1, 0.4, 1.6)
    if tap(ident="sight.row", pause=3.5):
        chapter("Da vedere", "Ogni luogo: foto, descrizione, indicazioni, «aggiungi al viaggio»")
        time.sleep(2)
        scroll(1, 0.4, 1.8)
        dismiss_sheet()
    back()
if tap(ident="tile.Strade", pause=3, scrolls=2):
    chapter("Strade", "Condizioni in tempo reale di Vegagerðin: chiuse, ghiaccio, vento")
    scroll(1, 0.4, 1.8)
    if tap(ident="road.row", pause=3):
        scroll(1, 0.4, 1.6)
        back()
    back()
if tap(ident="tile.Vulcani e terremoti", pause=3, scrolls=2):
    chapter("Vulcani e terremoti", "Scosse delle ultime 48 ore dall'IMO")
    scroll(1, 0.4, 1.8)
    back()
scroll(2, 0.45, 1.5)
chapter("1 · Oggi", "Terra, mare e servizi: carburante, voli, spesa")
scroll(1, 0.45, 2)

# 2 · Weather
tab("Meteo")
chapter("2 · Meteo", "MET Norway + Open-Meteo, ora per ora, con i rischi")
time.sleep(2)
scroll(3, 0.45, 1.5)

# 3 · Aurora
tab("Aurora")
chapter("3 · Aurora", "Attività, osservabilità qui, affidabilità")
time.sleep(2.5)
if tap(label="Come si calcola", pause=3):
    chapter("3 · Aurora", "«Come si calcola»: la spiegazione in un riquadro")
    tap_at(W * 0.5, H * 0.08, 1)
scroll(1, 0.4, 2)
chapter("3 · Aurora", "Tempo reale: vento solare, Bz, Hp30, magnetometro, Kp")
scroll(3, 0.5, 1.5)
scroll_top()
for mode in ["24 ORE", "3 GIORNI"]:
    if tap(label=mode, exact=True, pause=2.5, scrolls=1):
        chapter("3 · Aurora", "Previsioni a 24 ore e a 3 giorni, località migliori")
        scroll(2, 0.45, 1.4)
        scroll_top()
tap(label="LIVE", exact=True, pause=1.5, scrolls=1)
if tap(ident="nightVision", pause=3.5, anywhere=True):
    chapter("3 · Aurora", "Visione notturna rossa: non perdi l'adattamento al buio")
    time.sleep(1.5)
    tap(ident="nightVision", pause=1.5, anywhere=True)

# 4 · Map
tab("Mappa")
chapter("4 · Mappa", "Vento, raffiche, pioggia, neve, nuvole, temperatura, aurora, radar")
time.sleep(3)
for layer in ["gust", "precipitation", "snow", "cloud", "temperature", "aurora", "radar", "wind"]:
    tap(ident=f"layer.{layer}", pause=2.2, anywhere=True)
if tap(label="Play", pause=4, anywhere=True) or tap(label="play", pause=4, anywhere=True):
    tap(label="Pausa", pause=1, anywhere=True)
tap_at(W * 0.45, H * 0.5, 3)
chapter("4 · Mappa", "Tocca un punto: meteo, aurora e strada in quel posto")
if tap(ident="map.fullscreen", pause=3, anywhere=True):
    chapter("4 · Mappa", "A schermo intero, legenda e tempo sopra la mappa")
    time.sleep(2)
    tap(ident="map.fullscreen", pause=2, anywhere=True)
if tap(ident="layers.menu", pause=2.5, anywhere=True):
    chapter("4 · Mappa", "Livelli: allerte, strade, webcam, distributori, attrazioni, viaggio")
    time.sleep(2)
    tap_at(W * 0.5, H * 0.92, 1.5)

# 5 · Trip
tab("Viaggio")
chapter("5 · Viaggio", "Giorno per giorno: tragitto, notte, meteo e attrazioni con orari")
time.sleep(3)
scroll(1, 0.4, 2.2)
if tap(ident="trip.visit", pause=3.5, scrolls=2):
    chapter("5 · Viaggio", "Ogni attrazione: foto, descrizione, giorno, ora e durata")
    scroll(1, 0.45, 1.8)
    dismiss_sheet()
scroll(2, 0.45, 1.6)
scroll_top()
if tap(label="Tappe", exact=True, pause=2.5, anywhere=True):
    chapter("5 · Viaggio", "Le tappe: dove dormi, con il tragitto tra l'una e l'altra")
    scroll(1, 0.4, 1.8)
    if tap(ident="trip.stop", pause=3, scrolls=1):
        chapter("5 · Viaggio", "Una tappa: meteo, programma, consigliati vicino e lungo la strada")
        scroll(3, 0.45, 1.6)
        back()
    scroll_top()
if tap(label="Mappa", exact=True, pause=3.5, anywhere=False):
    chapter("5 · Viaggio", "Il percorso sulla mappa, tappe numerate e attrazioni")
    time.sleep(1.5)
tap(label="Giorni", exact=True, pause=1.5)
if tap(ident="trip.share", pause=3, scrolls=1):
    chapter("5 · Viaggio", "Condividi: modificatelo insieme, o una copia via email")
    scroll(1, 0.4, 1.8)
    dismiss_sheet()
if tap(ident="trip.inbox", pause=3, anywhere=True):
    chapter("5 · Viaggio", "Ricevuti: inviti a modificare insieme e copie")
    dismiss_sheet()

# 6 · Drive
if tap(ident="trip.drive", pause=3, anywhere=True):
    chapter("6 · Guida", "Registra il percorso: strade davanti, vento, avvisi vocali")
    scroll(2, 0.45, 1.6)
    if tap(label="Costa sud", pause=3, scrolls=3):
        chapter("6 · Guida", "Ogni percorso: mappa, dati, GPX, rifallo con Mappe")
        scroll(1, 0.45, 1.6)
        if tap(ident="drive.shareCard", pause=9, scrolls=3):
            chapter("6 · Guida", "Condividi su Instagram: immagine e video in 3D")
            time.sleep(4)
            dismiss_sheet()
        back()
    tap(label="CHIUDI", pause=2, anywhere=True)

# 7 · Settings
tab("Oggi")
scroll_top()
notify("settings", 3)
if True:
    chapter("7 · Impostazioni", "Backup automatico, visione notturna, fonti e stato dei dati")
    scroll(1, 0.4, 2)
    if tap(label="Fonti e stato dei dati", pause=3, scrolls=2):
        scroll(1, 0.45, 1.8)
        back()
    dismiss_sheet()
chapter("Norður", "Dal 6 al 13 novembre in Islanda: lo provo sul campo")
time.sleep(3.5)

rec.send_signal(signal.SIGINT)
rec.wait(timeout=60)
json.dump({"chapters": chapters, "duration": round(time.time() - t0, 2)}, open(chapters_path, "w"), ensure_ascii=False, indent=1)
print("chapters", len(chapters))
