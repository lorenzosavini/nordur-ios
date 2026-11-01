import json, numpy as np, soundfile as sf
from kokoro_onnx import Kokoro
k = Kokoro("kokoro-v1.0.onnx", "voices-v1.0.bin")
lines = json.load(open("script.json")); out = []; t = 0.35; sr = 24000
audio = [np.zeros(int(0.35 * sr), np.float32)]
for i, l in enumerate(lines):
    s, sr = k.create(l["say"], voice="am_michael", speed=1.02, lang="en-us")
    s = s.astype(np.float32)
    # trim leading/trailing near-silence
    nz = np.where(np.abs(s) > 0.01)[0]; s = s[max(0, nz[0] - 600): nz[-1] + 1200]
    out.append({"start": t, "dur": len(s) / sr, **l}); audio.append(s); t += len(s) / sr
    gap = {"hook": 0.25, "swim": 0.5, "rate": 0.45, "wait": 0.55, "silfra": 0.45, "opens": 0.6, "erupt": 0.4, "look": 0.5}.get(l["id"], 0.3)
    audio.append(np.zeros(int(gap * sr), np.float32)); t += gap
a = np.concatenate(audio); a = a / max(1e-6, np.abs(a).max()) * 0.92
sf.write("narration.wav", a, sr); json.dump(out, open("timeline.json", "w"), indent=1)
print(round(t, 2)); [print(round(o["start"], 2), round(o["dur"], 2), o["show"][:40]) for o in out]
