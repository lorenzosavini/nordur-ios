"""script.json → narration.wav + timeline.json (Kokoro am_michael). Usage: python narrate.py <avatar_dir> [out_dir]"""
import json, sys, os, numpy as np, soundfile as sf
from kokoro_onnx import Kokoro
AV = sys.argv[1] if len(sys.argv) > 1 else "../../avatar"; OUT = sys.argv[2] if len(sys.argv) > 2 else "."
k = Kokoro(os.path.join(AV, "kokoro-v1.0.onnx"), os.path.join(AV, "voices-v1.0.bin"))
lines = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "voice", "script.json"))); out = []; t = 0.35; sr = 24000
audio = [np.zeros(int(0.35 * sr), np.float32)]
GAP = {"hook": 0.35, "names": 0.4, "shoe": 0.45, "dad": 0.35, "cave": 0.45, "statue": 0.4, "poem": 0.45, "end": 0.5}
for l in lines:
    s, sr = k.create(l["say"], voice="am_michael", speed=1.02, lang="en-us"); s = s.astype(np.float32)
    nz = np.where(np.abs(s) > 0.01)[0]; s = s[max(0, nz[0] - 600): nz[-1] + 1200]
    out.append({"start": t, "dur": len(s) / sr, **l}); audio.append(s); t += len(s) / sr
    g = GAP.get(l["id"], 0.3); audio.append(np.zeros(int(g * sr), np.float32)); t += g
a = np.concatenate(audio); a = a / max(1e-6, np.abs(a).max()) * 0.92
sf.write(os.path.join(OUT, "narration.wav"), a, sr); json.dump(out, open(os.path.join(OUT, "timeline.json"), "w"), indent=1, ensure_ascii=False)
print(round(t, 2)); [print(round(o["start"], 2), round(o["dur"], 2), o["show"][:40]) for o in out]
