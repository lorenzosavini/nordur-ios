import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
P, FONTS, OUT = sys.argv[1:4]
W, H = 1640, 720
F = lambda n, s: ImageFont.truetype(f"{FONTS}/{n}.woff", s)
src = Image.open(f"{P}/sheets/fb-src.png").convert("RGB").crop((340, 0, 3500, 2160))
s = W / src.width * 1.12; big = src.resize((round(src.width * s), round(src.height * s)), Image.LANCZOS)
x0 = big.width - W - 10; y0 = min(big.height - H, round(big.height * 0.36))
img = big.crop((x0, y0, x0 + W, y0 + H)); img = ImageEnhance.Contrast(img).enhance(1.08)
# left shade for the text, soft
sh = Image.new("L", (W, 1))
for x in range(W): sh.putpixel((x, 0), int(225 * max(0, min(1, (980 - x) / 760)) ** 1.15))
img = Image.composite(Image.new("RGB", (W, H), (4, 9, 10)), img, sh.resize((W, H)))
im = img.convert("RGBA")
def phone(name, h, angle):
    shot = Image.open(f"{P}/pack-src-en/{name}.png").convert("RGB")
    w = round(h * shot.width / shot.height); shot = shot.resize((w, h), Image.LANCZOS)
    r = round(w * 0.13); pad = 9
    m = Image.new("L", (w, h), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255)
    fr = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(fr).rounded_rectangle((0, 0, w + 2 * pad - 1, h + 2 * pad - 1), r + pad, fill=(30, 33, 38, 255), outline=(90, 95, 100, 255), width=2)
    fr.paste(shot, (pad, pad), m)
    shd = Image.new("RGBA", (fr.width + 120, fr.height + 120), (0, 0, 0, 0))
    ImageDraw.Draw(shd).rounded_rectangle((60, 80, fr.width + 60, fr.height + 80), r, fill=(0, 0, 0, 190))
    shd = shd.filter(ImageFilter.GaussianBlur(28)); shd.alpha_composite(fr, (60, 60))
    return shd.rotate(angle, resample=Image.BICUBIC, expand=True)
a = phone("map-aurora", 520, -5); b = phone("notifications-lock", 440, 6)
im.alpha_composite(b, (900, 150)); im.alpha_composite(a, (1060, 50))
d = ImageDraw.Draw(im)
X = 200
logo = Image.open(f"{P}/logo/nordur-logo-horizontal-3840-white.png").convert("RGBA"); logo = logo.crop(logo.getbbox())
lw = 430; logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
y = 120; im.alpha_composite(logo, (X, y)); y += logo.height + 34
for ln in ("Iceland,", "in one app."):
    d.text((X, y), ln, font=F("BarlowCondensed-Bold", 104), fill=(246, 246, 242)); y += 100
y += 18
d.text((X, y), "Aurora · weather · roads · trips · fuel", font=F("IBMPlexSans-Medium", 28), fill=(205, 215, 212)); y += 66
f = F("IBMPlexSans-SemiBold", 28); t = "Join the waitlist  →  nordur.info"; tw = d.textlength(t, font=f)
d.rounded_rectangle((X, y, X + tw + 56, y + 62), 31, fill=(255, 90, 31)); d.text((X + 28, y + 13), t, font=f, fill=(255, 255, 255))
c = "Aurora: NASA/Mike Toillion · public domain"; cf = F("IBMPlexMono-Regular", 15)
d.text((X, 672 - 26), c, font=cf, fill=(170, 185, 180))
im.convert("RGB").save(f"{OUT}/nordur-facebook-cover-1640x720.png")
