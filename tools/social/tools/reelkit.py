"""Shared drawing helpers for the animated reels."""
import os, math, subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter
W, H, FPS = 1080, 1920, 30
TEXT = (246, 246, 242); DIM = (190, 196, 200); ACCENT = (255, 90, 31); AURORA = (61, 224, 168); RED = (255, 59, 48); YELLOW = (242, 200, 40)
class Fonts:
    def __init__(self, d): self.d = d
    def __call__(self, n, s): return ImageFont.truetype(os.path.join(self.d, n + ".woff"), s)
def setup(fonts_dir):
    global COND, SANS, MONO
    F = Fonts(fonts_dir)
    COND = lambda s: F("BarlowCondensed-Bold", s); SANS = lambda s: F("IBMPlexSans-SemiBold", s); MONO = lambda s: F("IBMPlexMono-SemiBold", s)
    return COND, SANS, MONO
def ease(x): x = max(0.0, min(1.0, x)); return x * x * (3 - 2 * x)
def shadow_text(img, text, y, f, fill=TEXT, center=True, x=None, blur=9):
    d = ImageDraw.Draw(img); w = d.textlength(text, font=f); x = (W - w) / 2 if center else x
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0)); ImageDraw.Draw(lay).text((x, y), text, font=f, fill=(0, 0, 0, 230))
    img.alpha_composite(lay.filter(ImageFilter.GaussianBlur(blur)))
    ImageDraw.Draw(img).text((x, y), text, font=f, fill=fill)
    return w
def wrap(d, text, f, width):
    out, line = [], ""
    for w_ in text.split():
        t = (line + " " + w_).strip()
        if d.textlength(t, font=f) <= width or not line: line = t
        else: out.append(line); line = w_
    return out + [line]
def block(img, text, y, size, fill=TEXT, k=1.0):
    d = ImageDraw.Draw(img); f = COND(size); lines = wrap(d, text, f, 960)
    for i, ln in enumerate(lines): shadow_text(img, ln, y + i * round(size * 1.05) + (1 - k) * 24, f, fill)
    return y + len(lines) * round(size * 1.05)
def gradients(im, top=560, bottom=560, strength=200):
    g = Image.new("L", (1, top)); [g.putpixel((0, y), int(strength * (1 - y / top) ** 1.3)) for y in range(top)]
    im.paste(Image.new("RGBA", (W, top), (4, 8, 12, 255)), (0, 0), g.resize((W, top)))
    g = Image.new("L", (1, bottom)); [g.putpixel((0, y), int(strength * (y / bottom) ** 1.3)) for y in range(bottom)]
    im.paste(Image.new("RGBA", (W, bottom), (4, 8, 12, 255)), (0, H - bottom), g.resize((W, bottom)))
_logo = {}
def cta(im, k, P, line, credit):
    if "l" not in _logo:
        lg = Image.open(os.path.join(P, "logo", "nordur-logo-horizontal-3840-white.png")).convert("RGBA"); lg = lg.crop(lg.getbbox())
        _logo["l"] = lg.resize((560, round(lg.height * 560 / lg.width)), Image.LANCZOS)
    im.alpha_composite(Image.new("RGBA", (W, H), (6, 9, 13, int(228 * k))))
    if k > 0.2:
        lg = _logo["l"]; im.alpha_composite(lg, ((W - lg.width) // 2, 640))
        block(im, line, 820, 78)
        shadow_text(im, "JOIN THE WAITLIST", 1060, MONO(44), ACCENT)
        shadow_text(im, "nordur.info", 1120, COND(150))
        d = ImageDraw.Draw(im)
        for i, ln in enumerate(wrap(d, credit, MONO(20), 960)): shadow_text(im, ln, 1460 + i * 28, MONO(20), DIM)
def writer(path):
    return subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium", "-movflags", "+faststart", path], stdin=subprocess.PIPE)
def run(frame, total, out_path, test):
    n = int(total * FPS)
    if test:
        want = set(int(x) for x in test)
        for fi in range(max(want) + 1):
            im = frame(fi)
            if fi in want: im.save(out_path.replace(".mp4", f"-test-{fi}.png"))
        return
    pr = writer(out_path)
    for fi in range(n): pr.stdin.write(frame(fi).tobytes())
    pr.stdin.close(); pr.wait(); print("done", out_path, n)
