#!/usr/bin/env python3
"""Norður notification sounds, synthesised from code (no recordings, no rights
to clear): one family, short (1–3 s), each kind of alert recognisable by ear.

  python3 tools/brand/make_sounds.py   (needs numpy; writes Nordur/Sounds/*.wav)

iOS plays them from the app bundle: 16-bit PCM WAV, under 30 s.
"""
import os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "Nordur/Sounds")
SR = 44100

def t(sec): return np.arange(int(SR * sec)) / SR

def bell(freq, sec, decay=3.0, harmonics=((1, 1), (2.76, 0.35), (5.4, 0.12))):
    x = t(sec)
    s = sum(a * np.sin(2 * np.pi * freq * m * x) for m, a in harmonics)
    env = np.exp(-decay * x) * np.minimum(1, x / 0.004)
    return s * env

def tone(freq, sec, attack=0.01, release=0.05, shape="sine"):
    x = t(sec)
    if shape == "sine":
        s = np.sin(2 * np.pi * freq * x)
    else:  # softened square
        s = np.tanh(3 * np.sin(2 * np.pi * freq * x))
    env = np.minimum(1, x / attack) * np.minimum(1, (sec - x) / release)
    return s * env

def place(total, parts):
    out = np.zeros(int(SR * total))
    for start, sig in parts:
        i = int(SR * start)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n]
    return out

def reverb(x, amount=0.35):
    y = x.copy()
    for delay, gain in ((0.031, 0.5), (0.047, 0.4), (0.071, 0.3), (0.113, 0.22), (0.163, 0.15)):
        d = int(SR * delay)
        y[d:] += amount * gain * x[:-d]
    return y

def write(name, x, peak=0.8):
    x = x / (np.max(np.abs(x)) or 1) * peak
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())

def noise(sec, seed=1):
    return np.random.default_rng(seed).standard_normal(int(SR * sec))

def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc); y[i] = acc
    return y

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    # Aurora, go out now: a rising shimmer of glass bells (C major pentatonic), full.
    notes = [1046.5, 1318.5, 1568.0, 1760.0, 2093.0, 2637.0]
    write("aurora_now", reverb(place(3.0, [(0.11 * i, bell(f, 2.6, 2.2)) for i, f in enumerate(notes)] +
                                      [(0.75, 0.5 * bell(1046.5 / 2, 2.2, 1.6))]), 0.5))
    # Aurora, get ready / tonight: the same opening, three notes, lighter.
    write("aurora_soon", reverb(place(1.8, [(0.13 * i, bell(f, 1.6, 2.8)) for i, f in enumerate(notes[:3])]), 0.4), 0.65)
    # Official weather warning: two clear tones, twice; urgent (orange/red): three times, firmer.
    pair = lambda: [(0, tone(880, 0.22)), (0.26, tone(660, 0.3))]
    write("warning", place(1.25, [(s + o, sig) for o in (0, 0.62) for s, sig in pair()]))
    write("warning_urgent", place(1.9, [(s + o, tone(f, d, shape="square") * 0.8) for o in (0, 0.62, 1.24)
                                        for s, f, d in ((0, 880, 0.22), (0.26, 660, 0.3))]))
    # Wind: a short gust of filtered noise that rises and falls.
    n = lowpass(noise(1.4), 0.06); x = t(1.4)
    write("wind", n * np.sin(np.pi * x / 1.4) ** 2 + 0.15 * tone(220, 1.4, 0.3, 0.4) * np.sin(np.pi * x / 1.4))
    # Roads: a dry double beep.
    write("road", place(0.5, [(0, tone(1046.5, 0.11, 0.004, 0.02)), (0.18, tone(1046.5, 0.11, 0.004, 0.02))]))
    # Earthquake: one deep thump with a low rumble.
    x = t(1.4)
    thump = np.sin(2 * np.pi * (55 + 30 * np.exp(-6 * x)) * x) * np.exp(-3.5 * x)
    rumble = lowpass(noise(1.4, 3), 0.02) * np.exp(-2.5 * x) * 2.5
    write("quake", thump + rumble)
    # SafeTravel and general news: one neutral chime.
    write("info", reverb(bell(784, 1.2, 3.2), 0.3), 0.6)
    # Flights: the airport ding-dong.
    write("flight", reverb(place(1.6, [(0, bell(659.3, 1.2, 2.5)), (0.42, bell(523.3, 1.2, 2.2))]), 0.3))
    # Ferry: a short ship's horn.
    x = t(1.1)
    horn = sum(np.sin(2 * np.pi * 110 * k * x) / k for k in range(1, 7)) * np.minimum(1, x / 0.08) * np.minimum(1, (1.1 - x) / 0.2)
    write("ferry", horn, 0.7)
    # Speed while driving: three quick, high beeps (heard over the road noise).
    write("speed", place(0.6, [(0.16 * i, tone(1568, 0.09, 0.003, 0.02, "square")) for i in range(3)]))
    print("ok", sorted(os.listdir(OUT)))
