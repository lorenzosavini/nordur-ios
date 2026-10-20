#!/usr/bin/env python3
"""Puts the chapter captions on the demo video (a translucent band near the
bottom with the chapter and a line saying what is on screen) and makes the
final file: 1080 px wide, 30 fps, H.264, for Facebook / Instagram / WhatsApp.

Usage: caption_video.py <raw.mp4> <chapters.json> <out.mp4>
"""
import json, os, subprocess, sys, tempfile, textwrap

raw, chapters_path, out = sys.argv[1:4]
doc = json.load(open(chapters_path))
chapters = doc["chapters"]
duration = doc.get("duration", 9999)

bold = next((f for f in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/Library/Fonts/Arial Bold.ttf",
                         "/System/Library/Fonts/Helvetica.ttc"] if os.path.exists(f)), None)
regular = next((f for f in ["/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf",
                            "/System/Library/Fonts/Helvetica.ttc"] if os.path.exists(f)), bold)
tmp = tempfile.mkdtemp()
filters = ["scale=1080:-2"]
for i, c in enumerate(chapters):
    start = c["t"]
    end = min(chapters[i + 1]["t"] if i + 1 < len(chapters) else duration, start + 5.5)
    if end - start < 1.2:
        continue
    tp = os.path.join(tmp, f"t{i}.txt")
    open(tp, "w").write(c["title"])
    lines = textwrap.wrap(c["subtitle"], 38)[:3]
    on = f"enable='between(t,{start:.2f},{end:.2f})'"
    band = 0.075 + 0.026 * len(lines)
    filters.append(f"drawbox=x=0:y=ih*0.76:w=iw:h=ih*{band:.3f}:color=black@0.62:t=fill:{on}")
    filters.append(f"drawbox=x=0:y=ih*0.76:w=iw*0.012:h=ih*{band:.3f}:color=0xF04A00@1:t=fill:{on}")
    filters.append(f"drawtext=fontfile='{bold}':textfile='{tp}':fontcolor=white:fontsize=h*0.03:x=w*0.05:y=h*0.775:{on}")
    for k, line in enumerate(lines):
        lp = os.path.join(tmp, f"s{i}_{k}.txt")
        open(lp, "w").write(line)
        filters.append(f"drawtext=fontfile='{regular}':textfile='{lp}':fontcolor=white@0.92:fontsize=h*0.019:x=w*0.05:y=h*{0.82 + 0.026 * k:.3f}:{on}")
cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-vf", ",".join(filters), "-r", "30",
       "-c:v", "libx264", "-preset", "slow", "-crf", "22", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out]
subprocess.run(cmd, check=True)
print("captions", len(chapters), "->", out)
