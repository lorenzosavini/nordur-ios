"""Reel: 'Name the road from above' quiz, built on Norður's own 3D flights."""
import sys, os, math, subprocess, numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reelkit as rk
P, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; TEST = sys.argv[4:]
COND, SANS, MONO = rk.setup(FONTS); W, H, FPS = rk.W, rk.H, rk.FPS
FOOT = os.path.join(P, "aurora-src")
def grab(path, start, n, vf):
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(start), "-i", path, "-vf", vf + ",format=rgb24", "-frames:v", str(n), "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
    raw = p.stdout.read(); p.wait()
    w, h = map(int, vf.split("scale=")[1].split(",")[0].split(":")) if "scale=" in vf else (W, H)
    return [Image.fromarray(np.frombuffer(raw[i * w * h * 3:(i + 1) * w * h * 3], np.uint8).reshape(h, w, 3)) for i in range(len(raw) // (w * h * 3))]
ROUNDS = [
    ("flyover-snaefellsnes.mp4", 0.0, ["Westfjords", "Snæfellsnes peninsula", "Eastfjords"], 1),
    ("flyover-golden-circle.mp4", 4.5, ["The Golden Circle", "Lake Mývatn", "Akureyri"], 0),
    ("flyover-westfjords.mp4", 1.5, ["Tröllaskagi", "Eastfjords", "The Westfjords"], 2),
]
ROUND = 7.0; PLAY = 4.6; Q = 2.6; CTA = 3.2; TOTAL = len(ROUNDS) * ROUND + Q + CTA
WIN_Y, WIN_H = 420, 980
clips, ends = [], []
for f, st, _, _ in ROUNDS:
    clips.append(grab(os.path.join(FOOT, f), st, int(PLAY * FPS) + 2, f"crop=1080:980:0:170,scale=1080:980"))
    ends.append(grab(os.path.join(FOOT, f), 20.7, 1, "scale=1080:1920")[0])
bg_cache = {}
def frame(fi):
    t = fi / FPS
    r = int(t // ROUND)
    if r < len(ROUNDS):
        lt = t - r * ROUND; f, _, opts, ans = ROUNDS[r]
        if lt < PLAY + 0.8:
            clip = clips[r]; cf = clip[min(int(lt * FPS), len(clip) - 1)]
            if r not in bg_cache:
                bg_cache[r] = clip[0].resize((W, H)).filter(ImageFilter.GaussianBlur(40))
            im = Image.blend(bg_cache[r], Image.new("RGB", (W, H), (6, 9, 13)), 0.55).convert("RGBA")
            win = cf.convert("RGBA"); m = Image.new("L", win.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, W - 1, WIN_H - 1), 0, fill=255)
            im.paste(win, (0, WIN_Y), m)
            d = ImageDraw.Draw(im, "RGBA")
            if r == 0 and lt < 2.0:
                y = rk.block(im, "Can you name these Icelandic roads from above?", 150, 84, k=rk.ease(lt / 0.3))
            else:
                rk.shadow_text(im, f"ROUND {r + 1} / {len(ROUNDS)}", 190, MONO(32), rk.ACCENT)
                rk.block(im, "Which road is this?", 250, 104)
            # countdown ring
            if lt < PLAY:
                left = PLAY - lt; cx, cy, R = W - 110, WIN_Y + 100, 54
                d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=(6, 9, 13, 190))
                d.arc((cx - R, cy - R, cx + R, cy + R), -90, -90 + 360 * left / PLAY, fill=rk.ACCENT, width=8)
                n_ = str(math.ceil(left)); f_ = COND(64); d.text((cx - d.textlength(n_, font=f_) / 2, cy - 40), n_, font=f_, fill=rk.TEXT)
            # options
            for i, o in enumerate(opts):
                y0 = WIN_Y + WIN_H - 3 * 104 - 30 + i * 104; x0, x1 = 60, W - 60
                rev = lt >= PLAY; right = rev and i == ans
                fill = (61, 224, 168, 245) if right else ((10, 14, 20, 120) if rev else (10, 14, 20, 215))
                pop = rk.ease((lt - 0.25 - i * 0.12) / 0.25)
                if pop <= 0: continue
                d.rounded_rectangle((x0, y0, x1, y0 + 88), 44, fill=fill, outline=(255, 255, 255, 60 if not right else 0), width=2)
                letter = "ABC"[i]; fl = COND(56); col = (6, 9, 13) if right else (rk.TEXT if not rev else (150, 150, 150))
                d.text((x0 + 34, y0 + 12), letter, font=fl, fill=rk.ACCENT if not right and not rev else col)
                d.text((x0 + 96, y0 + 18), o, font=SANS(44), fill=col)
                if right: d.text((x1 - 70, y0 + 12), "✓" if False else "", font=fl, fill=col)
            if lt >= PLAY:
                rk.shadow_text(im, f"{'ABC'[ans]}: {opts[ans]}", WIN_Y + WIN_H + 30, COND(70), (61, 224, 168))
            return im.convert("RGB")
        # reveal: the full flight frame, with the app's own card
        k = rk.ease((lt - PLAY - 0.8) / 0.4)
        im = ends[r].convert("RGBA")
        im.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(120 * (1 - k)))))
        g = Image.new("L", (1, 460)); [g.putpixel((0, y), int(230 * min(1, (460 - y) / 200))) for y in range(460)]
        im.paste(Image.new("RGBA", (W, 460), (6, 9, 13, 255)), (0, 0), g.resize((W, 460)))
        rk.shadow_text(im, f"{'ABC'[ans]}. {opts[ans]}", 230, COND(96), (61, 224, 168))
        rk.shadow_text(im, "3D flight made with Norður", 340, SANS(40), rk.TEXT)
        return im.convert("RGB")
    tq = t - len(ROUNDS) * ROUND
    im = Image.blend(ends[-1].filter(ImageFilter.GaussianBlur(24)), Image.new("RGB", (W, H), (6, 9, 13)), 0.6).convert("RGBA")
    if tq < Q:
        y = rk.block(im, "How many did you get?", 640, 120, k=rk.ease(tq / 0.3))
        rk.shadow_text(im, "Comment your score: 0, 1, 2 or 3", y + 20, SANS(46), rk.DIM)
    else:
        rk.cta(im, rk.ease((tq - Q) / 0.5), P, "Turn your own drive into a 3D flight.", "3D flights rendered by the Norður app over real terrain and satellite imagery")
    return im.convert("RGB")
rk.run(frame, TOTAL, os.path.join(OUT, "quiz-roads-from-above.mp4"), TEST)
