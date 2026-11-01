"""Overlay system: cards that enter and leave with precise transitions."""
import math, numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps
W, H = 1080, 1920
def ease_out(x): x = max(0.0, min(1.0, x)); return 1 - (1 - x) ** 3
def ease_in(x): x = max(0.0, min(1.0, x)); return x ** 3
def back(x, s=1.7): x = max(0.0, min(1.0, x)); x -= 1; return x * x * ((s + 1) * x + s) + 1
def env(t, t0, t1, tin=0.35, tout=0.3):
    """0..1 in, 1 hold, 1..0 out. Returns (phase_in, phase_out) progress."""
    if t < t0 or t > t1: return None
    return min(1.0, (t - t0) / tin), max(0.0, min(1.0, (t - (t1 - tout)) / tout))
def frame_photo(img, w, h, border=14, radius=22, rot=0, caption=None, font=None, credit=None, cfont=None, style="card"):
    """A photo card: white frame (polaroid-like) or rounded card with shadow; returns RGBA."""
    im = ImageOps.fit(img.convert("RGB"), (w, h), Image.LANCZOS)
    if style == "polaroid":
        cap = 90 if caption else border
        card = Image.new("RGBA", (w + 2 * border, h + border + cap), (246, 244, 238, 255))
        card.paste(im, (border, border))
        d = ImageDraw.Draw(card)
        if caption: d.text((border + 6, h + border + 18), caption, font=font, fill=(30, 30, 30))
    else:
        card = Image.new("RGBA", (w + 2 * border, h + 2 * border), (0, 0, 0, 0))
        m = Image.new("L", card.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius + border, fill=255)
        bg = Image.new("RGBA", card.size, (255, 255, 255, 255)); card.paste(bg, (0, 0), m)
        m2 = Image.new("L", (w, h), 0); ImageDraw.Draw(m2).rounded_rectangle((0, 0, w - 1, h - 1), radius, fill=255)
        card.paste(im, (border, border), m2)
    if credit:
        d = ImageDraw.Draw(card); tw = d.textlength(credit, font=cfont)
        d.rounded_rectangle((card.width - border - tw - 22, card.height - border - (110 if style == "polaroid" and caption else 0) - 38, card.width - border - 6, card.height - border - (110 if style == "polaroid" and caption else 0) - 8), 10, fill=(0, 0, 0, 150))
        d.text((card.width - border - tw - 14, card.height - border - (110 if style == "polaroid" and caption else 0) - 35), credit, font=cfont, fill=(235, 235, 235))
    sh = Image.new("RGBA", (card.width + 80, card.height + 80), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((40, 56, card.width + 40, card.height + 56), radius + border, fill=(0, 0, 0, 160))
    sh = sh.filter(ImageFilter.GaussianBlur(18)); sh.alpha_composite(card, (40, 40))
    if rot: sh = sh.rotate(rot, resample=Image.BICUBIC, expand=True)
    return sh
def place(base, layer, cx, cy, t, t0, t1, enter="pop", exit="fade", tin=0.4, tout=0.3, rot_in=0):
    """Composite `layer` centred at (cx, cy) with entrance/exit animations."""
    e = env(t, t0, t1, tin, tout)
    if e is None: return
    pi, po = e
    a = 1.0; s = 1.0; dx = dy = 0.0; r = 0.0
    if enter == "pop": s = 0.6 + 0.4 * back(pi); a = min(1, pi * 2)
    elif enter == "left": dx = -W * (1 - ease_out(pi)); a = min(1, pi * 3)
    elif enter == "right": dx = W * (1 - ease_out(pi)); a = min(1, pi * 3)
    elif enter == "up": dy = H * 0.5 * (1 - ease_out(pi)); a = min(1, pi * 3)
    elif enter == "drop": dy = -H * 0.6 * (1 - back(pi, 1.2)); r = rot_in * (1 - ease_out(pi)); a = min(1, pi * 3)
    elif enter == "spin": s = 0.3 + 0.7 * back(pi); r = -25 * (1 - ease_out(pi)); a = min(1, pi * 2)
    elif enter == "fade": a = ease_out(pi)
    elif enter == "zoom": s = 1.25 - 0.25 * ease_out(pi); a = ease_out(pi)
    if po > 0:
        if exit == "fade": a *= 1 - ease_in(po)
        elif exit == "left": dx -= W * ease_in(po)
        elif exit == "right": dx += W * ease_in(po)
        elif exit == "down": dy += H * 0.6 * ease_in(po)
        elif exit == "shrink": s *= 1 - 0.9 * ease_in(po); a *= 1 - ease_in(po)
        elif exit == "up": dy -= H * 0.6 * ease_in(po)
    if a <= 0.01 or s <= 0.02: return
    L = layer
    if r: L = L.rotate(r, resample=Image.BICUBIC, expand=True)
    if abs(s - 1) > 0.01: L = L.resize((max(1, int(L.width * s)), max(1, int(L.height * s))), Image.BILINEAR)
    if a < 0.999:
        L = L.copy(); L.putalpha(L.getchannel("A").point(lambda v: int(v * a)))
    base.alpha_composite(L, (int(cx + dx - L.width / 2), int(cy + dy - L.height / 2)))
def wipe_reveal(base, layer, x, y, t, t0, t1, dur=0.6):
    """Left-to-right reveal (like ink on parchment)."""
    if t < t0 or t > t1: return
    k = ease_out((t - t0) / dur); w = int(layer.width * k)
    if w < 2: return
    base.alpha_composite(layer.crop((0, 0, w, layer.height)), (int(x), int(y)))
def stamp(text, font, col=(220, 40, 40), rot=-12, pad=26):
    """Rubber-stamp label."""
    d = ImageDraw.Draw(Image.new("RGB", (4, 4))); tw = d.textlength(text, font=font)
    L = Image.new("RGBA", (int(tw + pad * 2 + 20), int(font.size * 1.6 + pad)), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    d.rounded_rectangle((6, 6, L.width - 6, L.height - 6), 14, outline=col + (255,), width=8)
    d.text((pad + 10, pad * 0.5), text, font=font, fill=col + (255,))
    return L.rotate(rot, resample=Image.BICUBIC, expand=True)
def grain(img_np, t, amount=6):
    n = np.random.default_rng(int(t * 30)).normal(0, amount, img_np.shape[:2])[..., None]
    return np.clip(img_np + n, 0, 255)
def vignette(im, strength=0.55):
    yy, xx = np.mgrid[0:H, 0:W]; r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    v = np.clip((r - 0.6) / 0.8, 0, 1) * strength
    return v
