#!/usr/bin/env python3
"""Puts the chapter captions on the demo video (a translucent band near the
bottom with the chapter and a line saying what is on screen) and makes the
final file: 1080 px wide, 30 fps, H.264, for Facebook / Instagram / WhatsApp.

The captions are drawn with Pillow as transparent pictures and laid over the
video, because the ffmpeg from Homebrew has no drawtext.

Usage: caption_video.py <raw.mp4> <chapters.json> <out.mp4>
"""
import json, os, subprocess, sys, tempfile, textwrap
from PIL import Image, ImageDraw, ImageFont

raw, chapters_path, out = sys.argv[1:4]
doc = json.load(open(chapters_path))
chapters = doc["chapters"]
duration = doc.get("duration", 9999)

probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                        "-of", "csv=p=0", raw], capture_output=True, text=True, check=True).stdout.strip().split(",")
W = 1080
H = int(round(int(probe[1]) * W / int(probe[0]) / 2)) * 2

def font(paths, size):
    for p in paths:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default(size)

bold = font(["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/Library/Fonts/Arial Bold.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"], int(H * 0.03))
regular = font(["/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"], int(H * 0.019))

tmp = tempfile.mkdtemp()
inputs, overlays = [], []
for i, c in enumerate(chapters):
    start = c["t"]
    end = min(chapters[i + 1]["t"] if i + 1 < len(chapters) else duration, start + 5.5)
    if end - start < 1.2:
        continue
    lines = textwrap.wrap(c["subtitle"], 38)[:3]
    band = 0.075 + 0.026 * len(lines)
    # Only the band, laid at its place: a full-frame picture makes the encoding far slower.
    top = int(H * 0.76)
    img = Image.new("RGBA", (W, int(H * band)), (0, 0, 0, 158))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, int(W * 0.012), int(H * band)], fill=(0xF0, 0x4A, 0x00, 255))
    d.text((int(W * 0.05), int(H * 0.775) - top), c["title"], font=bold, fill=(255, 255, 255, 255))
    for k, line in enumerate(lines):
        d.text((int(W * 0.05), int(H * (0.82 + 0.026 * k)) - top), line, font=regular, fill=(255, 255, 255, 235))
    path = os.path.join(tmp, f"c{i}.png")
    img.save(path)
    inputs += ["-i", path]
    overlays.append((start, end))

graph = [f"[0:v]scale={W}:{H}[v0]"]
for n, (start, end) in enumerate(overlays):
    graph.append(f"[v{n}][{n + 1}:v]overlay=0:{int(H * 0.76)}:enable='between(t,{start:.2f},{end:.2f})'[v{n + 1}]")
cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", raw, *inputs, "-filter_complex", ";".join(graph),
       "-map", f"[v{len(overlays)}]", "-r", "30", "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
       "-pix_fmt", "yuv420p", "-movflags", "+faststart", out]
subprocess.run(cmd, check=True)
print("captions", len(overlays), "->", out)
