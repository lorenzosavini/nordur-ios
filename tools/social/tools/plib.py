"""Norður posts v2 (1080×1350): real photographs of Iceland, real app screens, frames of the
3D flight; every carousel numbered on its own. Usage: posts_v2.py <shots> <fonts> <heroes dir> <flight frame> <out>"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
SHOTS, FONTS, HEROES, FLIGHT, OUT = sys.argv[1:6]
import json
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "deco.py")).read())
W, H = 1080, 1350
BG = (7, 9, 12); TEXT = (246, 246, 242); DIM = (186, 186, 182); ACCENT = (255, 90, 31); AURORA = (61, 224, 168)
RED = (255, 59, 48); YELLOW = (242, 184, 7); PURPLE = (200, 60, 210); CARD = (18, 22, 28); BLUE = (120, 170, 255)
def font(n, s): return ImageFont.truetype(os.path.join(FONTS, n), s)
COND = lambda s: font("BarlowCondensed-Bold.woff", s)
SANS = lambda s: font("IBMPlexSans-Medium.woff", s)
SANSB = lambda s: font("IBMPlexSans-SemiBold.woff", s)
MONO = lambda s: font("IBMPlexMono-SemiBold.woff", s)

# Photographs bundled with the app (Wikimedia Commons, free licences, credited on the slide).
CREDIT = {"aurora": "Photo: AstroAnthony · CC BY 4.0", "roads": "Photo: Winniepix · CC BY 2.0", "weather": "Photo: Thomas Heins · CC BY 4.0",
          "trip": "Photo: Steven Diaz · CC0", "drive": "Photo: Petr Kraumann · CC BY 3.0", "map": "Image: NASA Goddard · public domain"}

def photo(name):
    return Image.open(os.path.join(HEROES, f"hero-{name}.imageset", f"hero-{name}.jpg")).convert("RGB")

def cover(img, w, h, fx=0.5, fy=0.5):
    s = max(w / img.width, h / img.height)
    r = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x = round((r.width - w) * fx); y = round((r.height - h) * fy)
    return r.crop((x, y, x + w, y + h))

def canvas():
    return Image.new("RGBA", (W, H), BG + (255,))

def header_photo(im, name, h=620, fy=0.5, fx=0.5, tint=None, credit=True, src=None):
    """A photograph across the top, fading into the dark page."""
    p = cover(src or photo(name), W, h, fx, fy)
    if tint:
        g = ImageEnhance.Color(p).enhance(0.25)
        p = Image.blend(g, Image.new("RGB", p.size, tint), 0.35)
    p = p.convert("RGBA")
    fade = Image.new("L", (W, h), 0); d = ImageDraw.Draw(fade)
    for y in range(h):
        d.line((0, y, W, y), fill=int(255 * max(0, (y - h * 0.45) / (h * 0.55)) ** 1.4))
    im.paste(p, (0, 0)); im.paste(Image.new("RGBA", (W, h), BG + (255,)), (0, 0), fade)
    top = Image.new("L", (W, 220), 0); dt = ImageDraw.Draw(top)
    for y in range(220): dt.line((0, y, W, y), fill=int(150 * (1 - y / 220)))
    im.paste(Image.new("RGBA", (W, 220), (0, 0, 0, 255)), (0, 0), top)
    if credit and name in CREDIT:
        d = ImageDraw.Draw(im); t = CREDIT[name]; f = MONO(17)
        d.text((W - 40 - d.textlength(t, font=f), h - 160), t, font=f, fill=(210, 210, 205))

def full_photo(im, src, dark=0.55, fy=0.5, fx=0.5):
    p = cover(src, W, H, fx, fy)
    p = Image.blend(p, Image.new("RGB", p.size, BG), dark)
    im.paste(p.convert("RGBA"), (0, 0))

def brand(im, counter=None):
    d = ImageDraw.Draw(im)
    icon = Image.open(os.path.join(FONTS, "..", "img", "icon.png")).convert("RGBA").resize((48, 48), Image.LANCZOS)
    m = Image.new("L", (48, 48), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 47, 47), 11, fill=255)
    im.paste(icon, (64, 56), m); d.text((124, 56), "NORÐUR", font=COND(42), fill=TEXT)
    if counter:
        t = f"{counter[0]}/{counter[1]}"; f = MONO(26)
        w = d.textlength(t, font=f)
        d.rounded_rectangle((W - 64 - w - 28, 56, W - 64, 104), 24, fill=(0, 0, 0, 150))
        d.text((W - 64 - w - 14, 64), t, font=f, fill=TEXT)

def footer(im, text="nordur.info"):
    d = ImageDraw.Draw(im); f = MONO(26)
    d.text((64, H - 78), text, font=f, fill=ACCENT)

def swipe(im, y):
    d = ImageDraw.Draw(im); f = MONO(28)
    d.text((64, y), "SWIPE", font=f, fill=TEXT)
    x = 64 + d.textlength("SWIPE", font=f) + 18
    d.line((x, y + 18, x + 70, y + 18), fill=ACCENT, width=5); d.polygon([(x + 70, y + 8), (x + 88, y + 18), (x + 70, y + 28)], fill=ACCENT)

def wrap(d, text, f, width):
    out, line = [], ""
    for w in text.split(" "):
        t = (line + " " + w).strip()
        if d.textlength(t, font=f) <= width or not line: line = t
        else: out.append(line); line = w
    if line: out.append(line)
    return out

def heading(im, kicker, text, y, size=96, color=TEXT, width=W - 128):
    d = ImageDraw.Draw(im)
    if kicker: d.text((64, y), kicker.upper(), font=MONO(26), fill=ACCENT); y += 48
    for ln in wrap(d, text, COND(size), width): d.text((64, y), ln, font=COND(size), fill=color); y += round(size * 1.02)
    return y

def para(im, text, y, size=40, color=DIM, width=W - 128):
    d = ImageDraw.Draw(im)
    for ln in wrap(d, text, SANS(size), width): d.text((64, y), ln, font=SANS(size), fill=color); y += round(size * 1.38)
    return y

def phone(name, height):
    shot = Image.open(os.path.join(SHOTS, name + ".png")).convert("RGB")
    w = round(height * shot.width / shot.height); shot = shot.resize((w, height), Image.LANCZOS)
    r = round(w * 0.11); pad = 8
    m = Image.new("L", (w, height), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, height - 1), r, fill=255)
    fr = Image.new("RGBA", (w + 2 * pad, height + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(fr).rounded_rectangle((0, 0, w + 2 * pad - 1, height + 2 * pad - 1), r + pad, fill=(44, 48, 54, 255))
    fr.paste(shot, (pad, pad), m)
    sh = Image.new("RGBA", (fr.width + 80, fr.height + 80), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((40, 52, fr.width + 40, fr.height + 52), r, fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(20)); sh.paste(fr, (40, 40), fr)
    return sh

def save(im, folder, i):
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    im.convert("RGB").save(os.path.join(OUT, folder, f"{i:02d}.jpg"), quality=93)

def balance(im, top=140, bottom=H - 150):
    """Slides without a photo: centre the content block vertically instead of leaving the bottom empty."""
    import numpy as np
    a = np.asarray(im.convert("RGB")).astype(int)
    diff = (np.abs(a - np.array(BG)).sum(axis=2) > 18)
    if diff[20].any(): return            # a photo reaches the top: layout is already anchored
    rows_ = np.where(diff[top:bottom].any(axis=1))[0]
    if not len(rows_): return
    y0, y1 = top + rows_[0], top + rows_[-1] + 1
    shift = ((bottom - y1) - (y0 - top)) // 2
    if shift < 20: return
    blk = im.crop((0, y0, W, y1))
    ImageDraw.Draw(im).rectangle((0, y0, W, y1), fill=BG + (255,))
    im.paste(blk, (0, y0 + shift))

FULLBG = {}
def carousel(folder, slides):
    n = len(slides)
    for i, make in enumerate(slides, start=1):
        key = None
        if isinstance(make, tuple): make, key = make
        key = key or FULLBG.get(folder, {}).get(i)
        im = canvas(); make(im); balance(im)
        if key: fullbg(im, K(key, f"{folder}/{i:02d}")[0], BG)
        else: decorate(im, folder, i, n, BG)
        brand(im, (i, n)); footer(im); progress(im, i, n, ACCENT, TEXT, MONO); save(im, folder, i)

