#!/usr/bin/env python3
"""Norður app icon and logo mark, drawn from code (no stock art).

A tall "Ð" (the Icelandic eth of Norður, Barlow Condensed Bold, the app's display
face) in snow white, its crossbar in the app's signal orange, under a green
aurora curtain over a dark Arctic night sky and a mountain ridge.

  python3 tools/brand/make_icon.py   (needs Pillow; writes into the asset catalog)
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = os.path.join(ROOT, "Shared/Fonts/BarlowCondensed-Bold.ttf")
S = 1024
ORANGE = (240, 74, 0)
SNOW = (246, 246, 242)

def sky():
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        t = y / S
        c = (int(6 + 10 * t), int(10 + 22 * t), int(22 + 34 * t))
        for x in range(S):
            px[x, y] = c
    # stars
    rnd = random.Random(7)
    d = ImageDraw.Draw(img)
    for _ in range(140):
        x, y = rnd.randrange(S), rnd.randrange(int(S * 0.62))
        r = rnd.choice([1, 1, 1, 2])
        a = rnd.randrange(120, 230)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(a, a, min(255, a + 10)))
    return img

def aurora():
    """Green curtain: a wavy band with vertical rays, blurred."""
    layer = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(layer)
    for x in range(-40, S + 40, 2):
        base = S * 0.30 + 70 * math.sin(x / 150) + 25 * math.sin(x / 47 + 1.3)
        h = 210 + 80 * math.sin(x / 90 + 0.7)
        for k in range(int(h)):
            a = int(255 * (1 - k / h) ** 1.6 * (0.55 + 0.45 * math.sin(x / 9) ** 2))
            y = base - k
            d.point((x, y), fill=max(d.im.getpixel((min(max(x, 0), S - 1), min(max(int(y), 0), S - 1))) if 0 <= x < S and 0 <= y < S else 0, a))
    layer = layer.filter(ImageFilter.GaussianBlur(14))
    green = Image.new("RGB", (S, S), (61, 224, 168))
    glow = Image.new("RGB", (S, S), (20, 140, 120))
    return layer, green, glow

def ridge(img):
    d = ImageDraw.Draw(img)
    pts = [(0, S)]
    rnd = random.Random(3)
    for i, x in enumerate(range(0, S + 32, 32)):
        y = S * 0.80 - 90 * math.exp(-((x - S * 0.32) / 170) ** 2) - 55 * math.exp(-((x - S * 0.78) / 120) ** 2) + rnd.uniform(-6, 6)
        pts.append((x, y))
    pts.append((S, S))
    d.polygon(pts, fill=(4, 7, 14))

def glyph(img, mark_only=False):
    # Big: the letter fills about 84 % of the height, so the icon reads at a glance
    # (home screen, notifications, Settings) without opening the app.
    size = 1140
    font = ImageFont.truetype(FONT, size)
    d = ImageDraw.Draw(img)
    text = "D"
    l, t, r, b = d.textbbox((0, 0), text, font=font)
    w, h = r - l, b - t
    x = (S - w) / 2 - l + size * 0.045
    y = (S - h) / 2 - t - 4
    d.text((x, y), text, font=font, fill=SNOW)
    # Eth crossbar across the stem, in signal orange.
    stem_left = x + l
    bar_h = size * 0.095
    cy = y + t + h * 0.53
    d.rectangle((stem_left - size * 0.115, cy - bar_h / 2, stem_left + size * 0.245, cy + bar_h / 2), fill=ORANGE)

def icon():
    img = sky()
    mask, green, glow = aurora()
    img = Image.composite(glow, img, mask.filter(ImageFilter.GaussianBlur(60)).point(lambda v: min(255, int(v * 0.7))))
    img = Image.composite(green, img, mask.point(lambda v: min(255, int(v * 1.25))))
    ridge(img)
    glyph(img)
    return img

def tinted():
    """Tinted variant (iOS 18): grayscale glyph on black, the system tints it."""
    img = Image.new("RGB", (S, S), (0, 0, 0))
    glyph(img)
    return img.convert("L").convert("RGB")

# Every size iOS asks for, as PNG files: with only the 1024 px image some iOS
# versions show no icon in notifications and Settings for an app installed
# outside the App Store.
SIZES = [  # (idiom, points, scales)
    ("iphone", 20, (2, 3)), ("iphone", 29, (2, 3)), ("iphone", 40, (2, 3)), ("iphone", 60, (2, 3)),
    ("ipad", 20, (1, 2)), ("ipad", 29, (1, 2)), ("ipad", 40, (1, 2)), ("ipad", 76, (1, 2)), ("ipad", 83.5, (2,)),
]

if __name__ == "__main__":
    import json
    out = os.path.join(ROOT, "Nordur/Assets.xcassets/AppIcon.appiconset")
    for f in os.listdir(out):
        if f.endswith(".png"):
            os.remove(os.path.join(out, f))
    big = icon()
    big.save(os.path.join(out, "AppIcon-1024.png"))
    images = [{"filename": "AppIcon-1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"}]
    for idiom, pt, scales in SIZES:
        for sc in scales:
            px = int(round(pt * sc))
            name = f"AppIcon-{px}.png"
            if not os.path.exists(os.path.join(out, name)):
                big.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
            label = f"{pt:g}x{pt:g}"
            images.append({"filename": name, "idiom": idiom, "scale": f"{sc}x", "size": label})
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(out, "Contents.json"), "w"), indent=2)
    print("ok", len(images))
