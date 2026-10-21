#!/usr/bin/env python3
"""Records a structured demo of Norður in the simulator and writes the
chapters (start time, title, subtitle) next to it, so the workflow can put a
caption on each.

Every chapter is its own short clip: the app is started straight on that
screen (the same launch arguments as the CI screenshots), a few swipes and
taps, then the clips are joined. One long take kept getting stuck: each step
depended on what the previous ones had left open, and idb's accessibility
queries could hang the app. Here nothing reads the screen and nothing carries
over from one chapter to the next.

Needs idb (idb-companion + fb-idb) for swipes and taps.
Usage: demo_video.py <udid> <out.mp4> <chapters.json>
"""
import json, os, signal, subprocess, sys, tempfile, time

udid, out, chapters_path = sys.argv[1], sys.argv[2], sys.argv[3]
BUNDLE = "it.lorenzosavini.nordur"
W, H = 402, 874   # iPhone 17 Pro, points
BASE = ["-ciAuroraDemo", "YES", "-ciDemoTrip", "YES", "-ciAlertsYellow", "YES", "-appearance", "dark",
        "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]

def idb(*args):
    # A slow answer from idb skips that step instead of ending the recording.
    try:
        subprocess.run(["idb", *args, "--udid", udid], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        print("idb timed out:", " ".join(args))

def tap(x, y, pause=2.2):
    idb("ui", "tap", str(round(x)), str(round(y)))
    time.sleep(pause)

def scroll(times=1, distance=0.45, pause=1.6):
    for _ in range(times):
        idb("ui", "swipe", str(W // 2), str(round(H * 0.74)), str(W // 2), str(round(H * (0.74 - distance))), "--duration", "0.5")
        time.sleep(pause)

def notify(command, pause=3):
    """Commands the app listens for in the demo run (CIRemote)."""
    subprocess.run(["xcrun", "simctl", "spawn", udid, "notifyutil", "-p", f"nordur.ci.{command}"], capture_output=True)
    time.sleep(pause)

def at(x, y, pause=2.2):
    tap(W * x / 402, H * y / 874, pause)

def launch(args, settle):
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    time.sleep(1)
    subprocess.run(["xcrun", "simctl", "launch", udid, BUNDLE, *BASE, *args], capture_output=True)
    time.sleep(settle)

tmp = tempfile.mkdtemp()
clips, chapters = [], []
elapsed = 0.0

def clip(title, subtitle, args, steps, settle=9, record_launch=False):
    """One chapter: start the app on its screen, record the steps."""
    global elapsed
    path = os.path.join(tmp, f"c{len(clips):02d}.mp4")
    if not record_launch:
        launch(args, settle)
    rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", path],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.2)
    start = time.time()
    marks = [(0.0, title, subtitle)]
    if record_launch:
        launch(args, settle)
    for step in steps:
        if step[0] == "chapter":
            marks.append((time.time() - start, step[1], step[2]))
        else:
            step[0](*step[1:])
    time.sleep(1.5)
    rec.send_signal(signal.SIGINT)
    try:
        rec.wait(timeout=60)
    except subprocess.TimeoutExpired:
        rec.kill()
    if not os.path.exists(path) or os.path.getsize(path) < 1000:
        print("no clip:", title, subtitle)
        return
    # Same size and frame rate for all, so they join without surprises.
    norm = path.replace(".mp4", "-n.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-vf", "scale=1080:-2,fps=30",
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-an", norm], check=True)
    length = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", norm],
                                  capture_output=True, text=True).stdout.strip() or 0)
    if length < 1:
        print("empty clip:", title, subtitle)
        return
    # The recording starts a little before `start`: the marks move by the clip's head.
    head = max(0.0, length - (time.time() - start))
    for t, ti, sub in marks:
        chapters.append({"t": round(elapsed + (0 if t == 0 else t + head), 2), "title": ti, "subtitle": sub})
    clips.append(norm)
    elapsed += length
    print(f"clip {len(clips)}: {title} · {subtitle} ({length:.1f} s)")

today = ["-initialTab", "today"]
trip = ["-initialTab", "trip"]

# 0 · Opening, with the launch animation
clip("Norður", "Islanda: aurora, meteo, strade e viaggio in un'app sola", today + ["-ciShowLaunch", "YES"], [], settle=10, record_launch=True)

# 1 · Today
clip("1 · Oggi", "In breve: aurora stanotte, prossime ore, strade e allerte", today, [
    (time.sleep, 2), (scroll, 1, 0.3, 2.5),
    ("chapter", "1 · Oggi", "Il viaggio di oggi e l'aurora adesso, con «vedo / non vedo»"),
    (scroll, 1, 0.35, 3), (scroll, 1, 0.4, 2.5),
    ("chapter", "1 · Oggi", "Esplora: da vedere, strade, vulcani, webcam"),
    (scroll, 1, 0.45, 3), (scroll, 1, 0.45, 2),
    ("chapter", "1 · Oggi", "Terra, mare e servizi: carburante, voli, spesa"),
    (scroll, 2, 0.45, 2),
])
clip("Da vedere", "Cascate, belvedere, sorgenti calde: 1.300 luoghi su mappa", today + ["-ciScreen", "sights"], [
    (time.sleep, 2.5), (scroll, 1, 0.4, 2.5),
    ("chapter", "Da vedere", "Foto, tempi di visita e avvertenze per ogni luogo"),
    (scroll, 2, 0.45, 2.2),
])
clip("Strade", "Condizioni in tempo reale di Vegagerðin: chiuse, ghiaccio, vento", today + ["-ciScreen", "roads"], [
    (time.sleep, 2.5), (scroll, 2, 0.45, 2.2),
])
clip("Vulcani e terremoti", "Scosse delle ultime 48 ore dall'IMO", today + ["-ciScreen", "quakes"], [
    (time.sleep, 3), (scroll, 1, 0.45, 2.5),
])
clip("Webcam", "Le strade come sono adesso", today + ["-ciScreen", "webcams"], [
    (time.sleep, 3), (scroll, 1, 0.45, 2.5),
])

# 2 · Weather
clip("2 · Meteo", "MET Norway + Open-Meteo, ora per ora, con i rischi", ["-initialTab", "weather"], [
    (time.sleep, 2.5), (scroll, 3, 0.45, 2),
])

# 3 · Aurora
clip("3 · Aurora", "Attività, osservabilità qui, affidabilità", ["-initialTab", "aurora"], [
    (time.sleep, 3), (scroll, 1, 0.4, 2.5),
    ("chapter", "3 · Aurora", "Tempo reale: vento solare, Bz, Hp30, magnetometro, Kp"),
    (scroll, 3, 0.5, 2),
])
clip("3 · Aurora", "Previsione a 24 ore e località migliori stanotte", ["-initialTab", "aurora", "-auroraMode", "day"], [
    (time.sleep, 3), (scroll, 2, 0.45, 2),
])
clip("3 · Aurora", "Tre giorni: Kp a blocchi di 3 ore e le notti", ["-initialTab", "aurora", "-auroraMode", "three"], [
    (time.sleep, 3), (scroll, 2, 0.45, 2),
])
clip("3 · Aurora", "Visione notturna rossa: non perdi l'adattamento al buio", ["-initialTab", "aurora", "-nightVision", "YES"], [
    (time.sleep, 4),
])

# 4 · Map (taps by position: layer chips, play, a point at sea, full screen)
clip("4 · Mappa", "Vento, raffiche, pioggia, neve, nuvole, temperatura, aurora, radar", ["-initialTab", "map"], [
    (time.sleep, 3),
    *[(at, x, y, 2.6) for x, y in [(250, 130), (62, 166), (150, 166), (237, 166), (75, 201), (185, 201), (275, 201), (157, 130)]],
    (at, 31, 719, 5), (at, 31, 719, 1.5),
    (at, 360, 505, 3.5),
    ("chapter", "4 · Mappa", "Tocca un punto: meteo, aurora e strada in quel posto"),
    (time.sleep, 2),
    (at, 367, 604, 3),
    ("chapter", "4 · Mappa", "A schermo intero, legenda e tempo sopra la mappa"),
    (time.sleep, 3),
])

# 5 · Trip
clip("5 · Viaggio", "Giorno per giorno: tragitto, notte, meteo e attrazioni con orari", trip + ["-trip.view", "days"], [
    (time.sleep, 3), (scroll, 1, 0.4, 2.5), (scroll, 2, 0.45, 2.5),
])
clip("5 · Viaggio", "Le tappe: dove dormi, con il tragitto tra l'una e l'altra", trip + ["-trip.view", "stops"], [
    (time.sleep, 3), (scroll, 2, 0.4, 2.2),
])
clip("5 · Viaggio", "Il percorso sulla mappa, tappe numerate e attrazioni", trip + ["-trip.view", "map"], [
    (time.sleep, 5),
])
clip("5 · Viaggio", "Condividi: modificatelo insieme, o una copia via email", trip + ["-trip.view", "days"], [
    (notify, "trip.share", 4), (scroll, 1, 0.4, 2.5),
])
clip("5 · Viaggio", "Ricevuti: inviti a modificare insieme e copie", trip + ["-trip.view", "days"], [
    (notify, "trip.inbox", 4.5),
])

# 6 · Drive
clip("6 · Guida", "Registra il percorso: strade davanti, vento, avvisi vocali", trip, [
    (notify, "trip.drive", 4), (scroll, 2, 0.45, 2.2),
])
clip("6 · Guida", "Ogni percorso: mappa, dati, GPX, rifallo con Mappe", today, [
    (notify, "drive.demo", 7), (scroll, 1, 0.45, 2.5),
    (notify, "drive.share", 9),
    ("chapter", "6 · Guida", "Condividi su Instagram: immagine e video in 3D"),
    (time.sleep, 5),
])

# 7 · Settings
clip("7 · Impostazioni", "Backup automatico, visione notturna, fonti e stato dei dati", today + ["-ciScreen", "settings"], [
    (time.sleep, 2.5), (scroll, 2, 0.4, 2.2),
])
clip("7 · Impostazioni", "Fonti e stato dei dati: ogni fonte, quando è stata aggiornata", today + ["-ciScreen", "sources"], [
    (time.sleep, 3), (scroll, 1, 0.45, 2.5),
])

# Closing
clip("Norður", "Dal 6 al 13 novembre in Islanda: lo provo sul campo", today, [(time.sleep, 4)])

with open(os.path.join(tmp, "list.txt"), "w") as f:
    f.writelines(f"file '{c}'\n" for c in clips)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", os.path.join(tmp, "list.txt"),
                "-c", "copy", out], check=True)
json.dump({"chapters": chapters, "duration": round(elapsed, 2)}, open(chapters_path, "w"), ensure_ascii=False, indent=1)
print("clips", len(clips), "chapters", len(chapters), "duration", round(elapsed, 1))
