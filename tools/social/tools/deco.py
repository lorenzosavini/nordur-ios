# Background decoration for posts/carousels: topographic contour lines that run continuously
# across the slides of a carousel (one wide map, sliced), plus a faint aurora glow at the top.
import numpy as np, zlib
def _field(seed, w, h):
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    f = np.zeros((h, w), np.float32)
    for _ in range(9):                      # a few smooth "mountains"
        cx, cy = rng.uniform(-0.1, 1.1) * w, rng.uniform(-0.1, 1.1) * h
        r = rng.uniform(260, 620); a = rng.uniform(0.6, 1.4) * rng.choice([1, 1, -0.6])
        f += a * np.exp(-(((xs - cx) ** 2 + (ys - cy) ** 2) / (2 * r * r)))
    for _ in range(4):                      # gentle ridges
        k = rng.uniform(0.002, 0.005); ang = rng.uniform(0, np.pi); ph = rng.uniform(0, 6.3)
        f += 0.12 * np.sin(k * (xs * np.cos(ang) + ys * np.sin(ang)) + ph)
    return f
_cache = {}
def decorate(im, key, i, n, BG):
    from PIL import Image
    W, H = im.size
    if key not in _cache:
        S = 0.5                              # compute at half resolution, then upscale
        _cache[key] = _field(zlib.crc32(key.encode()), int(W * n * S), int(H * S))
    f = _cache[key]
    sl = f[:, int(f.shape[1] * (i - 1) / n): int(f.shape[1] * i / n)]
    lv = sl * 9.0                            # contour interval
    fr = np.abs(lv - np.round(lv))
    g = np.hypot(*np.gradient(lv)) + 1e-4
    line = np.clip(1 - fr / (g * 1.1), 0, 1)                 # ~1 px anti-aliased isolines
    major = (np.abs(np.round(lv)) % 5 == 0)
    a = line * np.where(major, 0.16, 0.08)
    A = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)).astype(np.float32) / 255
    ys = np.linspace(0, 1, H)[:, None]; xs = np.linspace(0, 1, W)[None, :]
    glow = np.exp(-(((xs - 0.85) / 0.55) ** 2 + ((ys + 0.05) / 0.28) ** 2)) * 0.22
    base = np.array(BG, np.float32)[None, None, :] * np.ones((H, W, 1), np.float32)
    aur = np.array((61, 224, 168), np.float32)
    bg = base * (1 - glow[..., None]) + aur * glow[..., None]
    bg = bg * (1 - A[..., None]) + np.array((150, 200, 185), np.float32) * A[..., None]
    cur = np.asarray(im.convert("RGB")).astype(np.int16)
    plain = (np.abs(cur - np.array(BG)).sum(axis=2) <= 3)[..., None]
    out = np.where(plain, bg, cur.astype(np.float32)).astype(np.uint8)
    im.paste(Image.fromarray(out).convert("RGBA"), (0, 0))

def progress(im, i, n, ACCENT, TEXT, MONO):
    """Segmented progress bar + a 'next' arrow, bottom right, aligned with the nordur.info footer."""
    if n < 2: return
    from PIL import ImageDraw
    W, H = im.size; d = ImageDraw.Draw(im, "RGBA")
    y = H - 64; seg = 34; gap = 8
    total = n * seg + (n - 1) * gap
    x0 = W - 64 - total - (64 if i < n else 0)
    for k in range(1, n + 1):
        x = x0 + (k - 1) * (seg + gap)
        d.rounded_rectangle((x, y, x + seg, y + 6), 3, fill=(ACCENT + (255,)) if k <= i else (255, 255, 255, 60))
    if i < n:
        ax = W - 64 - 40; ay = y + 3
        d.line((ax, ay, ax + 36, ay), fill=TEXT, width=4)
        d.polygon([(ax + 40, ay), (ax + 26, ay - 10), (ax + 26, ay + 10)], fill=TEXT)

ICON_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons")
def icon(im, name, x, y, size=132, alpha=235):
    """A Tabler line icon (MIT), white, pasted at x, y."""
    from PIL import Image
    ic = Image.open(os.path.join(ICON_DIR, name + ".png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    a = ic.getchannel("A").point(lambda v: v * alpha // 255); ic.putalpha(a)
    im.alpha_composite(ic, (int(x), int(y)))

def rows(im, items, y, h=150, big=72, left=360, icons=None):
    """Editorial rows: hairline separators, coloured label, plain text; optional icon on the right."""
    from PIL import ImageDraw
    d = ImageDraw.Draw(im, "RGBA")
    right = W - 64 - (90 if icons else 0)
    for k, (a, b, col) in enumerate(items):
        d.rectangle((64, y, W - 64, y + 1), fill=(255, 255, 255, 46))
        d.text((64, y + (h - big) / 2 - 8), a, font=COND(big), fill=col)
        f = SANS(36); lines = wrap(d, b, f, right - left - 16)
        ty = y + (h - len(lines) * 46) / 2
        for ln in lines: d.text((left, ty), ln, font=f, fill=TEXT); ty += 46
        if icons and icons[k]: icon(im, icons[k], W - 64 - 64, y + (h - 64) / 2, 64, 200)
        y += h
    d.rectangle((64, y, W - 64, y + 1), fill=(255, 255, 255, 46))
    return y + 16

# ——— Image pool: every background is used once, across all posts and carousels ———
import json as _json
_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
_REG = os.path.join(_ROOT, "pool", "used.json")
_FLY_CREDIT = "Norður 3D flight · imagery Apple Maps"
_AK, _ISS = "Photo: NASA/Mike Toillion · public domain", "Image: NASA Johnson Space Center · public domain"
_HERO = {"aurora": "Photo: AstroAnthony · CC BY 4.0", "roads": "Photo: Winniepix · CC BY 2.0", "weather": "Photo: Thomas Heins · CC BY 4.0",
         "trip": "Photo: Steven Diaz · CC0", "drive": "Photo: Petr Kraumann · CC BY 3.0", "map": "Image: NASA Goddard · public domain"}
_NASA = {"glacier": ("15037---Icelandic-Glacier_print.jpg", "Image: NASA/USGS Landsat · public domain", (0, 0, 1280, 600)),
         "plume": ("EO1_volcano_1024x576.jpg", "Image: NASA EO-1 · public domain", (0, 40, 1024, 576)),
         "blooms": ("phytoplankton_iceland_2008192.png", "Image: NASA Aqua/MODIS · public domain", (1900, 150, 4104, 2050))}
def reset_pool():
    _json.dump({}, open(_REG, "w"))
def K(key, where=""):
    """(image, credit) for a pool key; refuses a key that has already been used anywhere."""
    used = _json.load(open(_REG)) if os.path.exists(_REG) else {}
    if key in used: raise SystemExit(f"image {key} already used in {used[key]} (now: {where})")
    used[key] = where or "?"; _json.dump(used, open(_REG, "w"))
    kind, name = key.split(":", 1)
    if kind == "hero":
        img = Image.open(os.path.join(HEROES, f"hero-{name}.imageset", f"hero-{name}.jpg")); cr = _HERO[name]
    elif kind == "fly":
        p = os.path.join(_ROOT, "pool", "fly2", name + ".jpg")
        img = Image.open(p if os.path.exists(p) else os.path.join(_ROOT, "pool", "extra", name + ".jpg")); cr = _FLY_CREDIT
    elif kind == "ak":
        img = Image.open(os.path.join(_ROOT, "pool", "aur", f"ak-{name}.jpg")); img = img.crop((240, 0, 1680, img.height)); cr = _AK
    elif kind == "iss":
        img = Image.open(os.path.join(_ROOT, "pool", "aur", f"iss-{name}.jpg")); img = img.crop((0, 0, img.width, img.height - 60)); cr = _ISS
    elif kind == "nasa":
        f, cr, box = _NASA[name]; img = Image.open(os.path.join(_ROOT, "pool", "nasa", f)).crop(box)
    elif kind == "lore":
        meta = _json.load(open(os.path.join(_ROOT, "lore", "img", "meta.json")))
        img = Image.open(os.path.join(_ROOT, "lore", "img", name + ".jpg")); cr = meta[name]["credit"]
    else: raise SystemExit("unknown key " + key)
    return img.convert("RGB"), cr

def fullbg(im, src, BG):
    """Fill every plain-background pixel with a blurred, darkened photograph."""
    from PIL import Image as _I, ImageFilter as _F
    W_, H_ = im.size
    s = max(W_ / src.width, H_ / src.height); b = src.resize((round(src.width * s) + 1, round(src.height * s) + 1))
    b = b.crop(((b.width - W_) // 2, (b.height - H_) // 2, (b.width - W_) // 2 + W_, (b.height - H_) // 2 + H_)).filter(_F.GaussianBlur(10))
    b = _I.blend(b, _I.new("RGB", (W_, H_), BG), 0.62)
    cur = np.asarray(im.convert("RGB")).astype(np.int16)
    plain = (np.abs(cur - np.array(BG)).sum(axis=2) <= 3)[..., None]
    im.paste(_I.fromarray(np.where(plain, np.asarray(b), cur).astype(np.uint8)).convert("RGBA"), (0, 0))
