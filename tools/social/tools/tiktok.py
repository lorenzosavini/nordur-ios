"""TikTok/Reels "text + trending sound" style: full-screen real footage, big outlined captions, beat-synced cuts, no audio.

Light, reusable layer on top of reelkit (ffmpeg writer, W/H/FPS). Typical use:

    import tiktok as tk
    tk.setup("site/landing/fonts", bpm=120)
    v = tk.Video("v_strokkur.mp4", start=2.0, dur=6.0)          # only the needed seconds are decoded, cropped to 9:16
    def frame(fi):
        t = fi / tk.FPS
        im = tk.canvas(v.frame(t, zoom=tk.punch(t, [0, 2])))      # footage + zoom punch on the beat
        tk.caption(im, "Wait for it…", t, t0=0.2, y=0.42)        # pops in, white with a thick black outline
        tk.endcard(im, t, total=8.0, icon="site/landing/img/icon.png")
        return im.convert("RGB")
    tk.render(frame, 8.0, "out.mp4", procs=4)                    # silent mp4; the trending sound is added in TikTok

Everything is stateless per frame so renders can be split across processes (render(procs=n)).
"""
import os, math, subprocess, tempfile, multiprocessing as mp
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps
try:
    import cv2
except ImportError:                       # pip install opencv-python-headless
    cv2 = None
W, H, FPS = 1080, 1920, 30
WHITE, BLACK = (255, 255, 255), (0, 0, 0)
AURORA, ORANGE, INK, CREAM, YELLOW = (61, 224, 168), (255, 90, 31), (16, 18, 22), (250, 246, 236), (255, 214, 10)
BPM = 120.0
_F = {"dir": None}
def setup(fonts_dir, bpm=120.0):
    global BPM
    _F["dir"] = fonts_dir; BPM = float(bpm)
def font(size, name="BarlowCondensed-Bold"):
    key = (name, int(size))
    if key not in _F: _F[key] = ImageFont.truetype(os.path.join(_F["dir"], name + ".woff"), int(size))
    return _F[key]
def beat(n=1.0): return 60.0 / BPM * n                      # seconds in n beats (120 BPM → 0.5 s)

# ——— easing ———
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def ease_out(x): x = clamp(x); return 1 - (1 - x) ** 3
def ease_in(x): x = clamp(x); return x ** 3
def back(x, s=2.2): x = clamp(x) - 1; return x * x * ((s + 1) * x + s) + 1
def smooth(x): x = clamp(x); return x * x * (3 - 2 * x)

# ——— sources ———
def cover(img, w=W, h=H, focus=(0.5, 0.5)):
    """PIL image → RGB cover-crop at (w, h) around focus (fractions)."""
    img = img.convert("RGB"); s = max(w / img.width, h / img.height)
    nw, nh = math.ceil(img.width * s), math.ceil(img.height * s); im = img.resize((nw, nh), Image.LANCZOS)
    x = int(clamp(focus[0] * nw - w / 2, 0, nw - w)); y = int(clamp(focus[1] * nh - h / 2, 0, nh - h))
    return im.crop((x, y, x + w, y + h))
class Photo:
    """Still photo as a full-screen 'clip' with a slow Ken Burns push (zoom from z0 to z1 over dur)."""
    def __init__(self, path, focus=(0.5, 0.5), over=1.25, z=(1.0, 1.08), dur=2.0, drift=(0.0, 0.0), size=(W, H)):
        self.size = size; self.base = cover(Image.open(path), int(size[0] * over), int(size[1] * over), focus); self.over = over; self.z = z; self.dur = dur; self.drift = drift
    def frame(self, lt, zoom=1.0):
        k = smooth(lt / self.dur) if self.dur else 0; z = (self.z[0] + (self.z[1] - self.z[0]) * k) * zoom
        bw, bh = self.base.size; cw, ch = bw / self.over / z, bh / self.over / z      # crop size in base pixels
        cx = bw / 2 + self.drift[0] * bw * k; cy = bh / 2 + self.drift[1] * bh * k
        x0 = clamp(cx - cw / 2, 0, bw - cw); y0 = clamp(cy - ch / 2, 0, bh - ch)
        return self.base.resize(self.size, Image.BICUBIC, box=(x0, y0, x0 + cw, y0 + ch))
class PhotoCard:
    """Photo shown whole as a rounded card over a blurred, darkened copy of itself (for text-heavy images like plaques)."""
    def __init__(self, path, width=900, cy=0.56, dur=2.0, z=(1.0, 1.05)):
        img = Image.open(path).convert("RGB"); self.dur, self.z = dur, z
        self.bg = ImageEnhance_brightness(cover(img).filter(ImageFilter.GaussianBlur(28)), 0.55)
        c = ImageOps.contain(img, (width, int(H * 0.55)), Image.LANCZOS)
        m = Image.new("L", c.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, c.width - 1, c.height - 1), 28, fill=255)
        self.card = Image.new("RGBA", c.size, (0, 0, 0, 0)); self.card.paste(c, (0, 0), m); self.card = sticker(self.card, border=10)
        self.cy = cy
    def frame(self, lt, zoom=1.0):
        im = self.bg.copy().convert("RGBA"); k = smooth(lt / self.dur); s = (self.z[0] + (self.z[1] - self.z[0]) * k) * zoom
        L = self.card.resize((int(self.card.width * s), int(self.card.height * s)), Image.BICUBIC)
        im.alpha_composite(L, (int((W - L.width) / 2), int(H * self.cy - L.height / 2))); return im.convert("RGB")
def ImageEnhance_brightness(img, k):
    from PIL import ImageEnhance
    return ImageEnhance.Brightness(img).enhance(k)
class Video:
    """A slice of a real clip: decodes only [start, start+dur], crops to 9:16 (xshift = fraction of width off-centre).
    frame(lt) returns a PIL RGB frame at clip-local time lt (speed multiplies source time; loops if loop=True)."""
    def __init__(self, path, start=0.0, dur=3.0, xshift=0.0, speed=1.0, loop=False, fit="cover", size=(W, H)):
        self.path, self.start, self.dur, self.xshift, self.speed, self.loop, self.fit, self.size = path, start, dur, xshift, speed, loop, fit, size
        self._fr = None
    def _load(self):
        cap = cv2.VideoCapture(self.path); self.fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        cap.set(cv2.CAP_PROP_POS_MSEC, self.start * 1000); fr = []
        for _ in range(int(self.dur * self.speed * self.fps) + 2):
            ok, f = cap.read()
            if not ok: break
            h, w = f.shape[:2]
            if self.fit == "cover" and w / h > self.size[0] / self.size[1]:
                cw = int(h * self.size[0] / self.size[1]); x0 = int(clamp((w - cw) / 2 + self.xshift * w, 0, w - cw)); f = f[:, x0:x0 + cw]
            fr.append(cv2.cvtColor(f, cv2.COLOR_BGR2RGB))
        self._fr = fr or [np.zeros((H, W, 3), np.uint8)]
    def frame(self, lt, zoom=1.0):
        if self._fr is None: self._load()
        n = len(self._fr); i = int(lt * self.speed * self.fps)
        i = i % n if self.loop else int(clamp(i, 0, n - 1))
        f = self._fr[i]; h, w = f.shape[:2]
        if self.fit == "blur":                                  # landscape in a blurred copy of itself (no crop)
            bg = cv2.GaussianBlur(cv2.resize(f, (W // 4, H // 4)), (0, 0), 6); bg = cv2.resize(bg, (W, H))
            nh = int(h * W / w); fg = cv2.resize(f, (W, nh), interpolation=cv2.INTER_AREA); y = (H - nh) // 2
            bg[y:y + nh] = fg; f = bg; h, w = H, W
        if zoom > 1.001:
            cw, ch = w / zoom, h / zoom; x0, y0 = (w - cw) / 2, (h - ch) / 2
            return Image.fromarray(f).resize(self.size, Image.BICUBIC, box=(x0, y0, x0 + cw, y0 + ch))
        return Image.fromarray(cv2.resize(f, self.size, interpolation=cv2.INTER_CUBIC))

# ——— beat helpers ———
def punch(t, cuts, amount=0.06, dur=0.35):
    """Zoom multiplier: a quick punch-in right after each cut time, easing back to 1."""
    z = 1.0
    for c in cuts:
        if c <= t < c + dur: z = 1 + amount * (1 - ease_out((t - c) / dur))
    return z
def flash(im, t, cuts, dur=0.12, col=WHITE, strength=0.85):
    """White flash for a few frames on each cut."""
    for c in cuts:
        if c <= t < c + dur:
            a = int(255 * strength * (1 - (t - c) / dur)); im.alpha_composite(Image.new("RGBA", im.size, col + (a,)))
def shake(t, cuts, px=18, dur=0.25):
    for c in cuts:
        if c <= t < c + dur:
            k = 1 - (t - c) / dur; r = np.random.default_rng(int(t * FPS))
            return int(r.uniform(-px, px) * k), int(r.uniform(-px, px) * k)
    return 0, 0
def canvas(frame_img, offset=(0, 0)):
    """RGBA working canvas; offset (shake) is applied inside a slightly enlarged frame so no black edges show."""
    if offset == (0, 0): return frame_img.convert("RGBA")
    m = max(abs(offset[0]), abs(offset[1])) + 2; big = frame_img.resize((W + 2 * m, H + 2 * m * H // W), Image.BILINEAR)
    x, y = m - offset[0], (big.height - H) // 2 - offset[1]
    return big.crop((x, y, x + W, y + H)).convert("RGBA")
def segment(t, cuts):
    """Index of the segment containing t and its local time, for a list of cut times starting at 0."""
    i = max(0, sum(1 for c in cuts if c <= t) - 1); return i, t - cuts[i]

# ——— text ———
def wrap(text, f, width):
    d = ImageDraw.Draw(Image.new("L", (4, 4))); out = []
    for para in text.split("\n"):
        line = ""
        for w_ in para.split():
            tt = (line + " " + w_).strip()
            if d.textlength(tt, font=f) <= width or not line: line = tt
            else: out.append(line); line = w_
        out.append(line)
    return out
def text_layer(text, size=112, fill=WHITE, stroke=BLACK, sw=None, width=940, name="BarlowCondensed-Bold", lh=1.02, box=None, upper=False, shadow=True):
    """Centred multi-line caption as an RGBA layer: TikTok look (white + thick black outline) or box label (box=(r,g,b))."""
    if upper: text = text.upper()
    f = font(size, name); sw = round(size * 0.11) if sw is None else sw
    lines = wrap(text, f, width); d = ImageDraw.Draw(Image.new("L", (4, 4)))
    lhpx = round(size * lh); ws = [d.textlength(l, font=f) for l in lines]
    pad = sw + 30 + (24 if box else 0); Lw = int(max(ws) + pad * 2); Lh = int(lhpx * len(lines) + pad * 2 + size * 0.25)
    L = Image.new("RGBA", (Lw, Lh), (0, 0, 0, 0)); dl = ImageDraw.Draw(L)
    for i, (ln, w_) in enumerate(zip(lines, ws)):
        x = (Lw - w_) / 2; y = pad + i * lhpx
        if box:
            asc, desc = f.getmetrics()
            dl.rounded_rectangle((x - 26, y - 6, x + w_ + 26, y + asc + desc * 0.6 + 6), radius=round(size * 0.22), fill=box + (255,))
    if shadow and not box:
        sh = Image.new("RGBA", L.size, (0, 0, 0, 0)); ds = ImageDraw.Draw(sh)
        for i, (ln, w_) in enumerate(zip(lines, ws)):
            ds.text(((Lw - w_) / 2, pad + i * lhpx + size * 0.05), ln, font=f, fill=(0, 0, 0, 150), stroke_width=sw, stroke_fill=(0, 0, 0, 150))
        L.alpha_composite(sh.filter(ImageFilter.GaussianBlur(size * 0.08)))
    for i, (ln, w_) in enumerate(zip(lines, ws)):
        dl.text(((Lw - w_) / 2, pad + i * lhpx), ln, font=f, fill=fill, stroke_width=0 if box else sw, stroke_fill=stroke)
    return L
_TL = {}
def caption(im, text, t, t0=0.0, t1=1e9, y=0.5, x=0.5, size=112, anim="pop", out="cut", tin=0.22, **kw):
    """Draw a caption between t0 and t1. anim: pop | slam | up | type | none. out: cut | fade | down.
    y/x are fractions of the frame for the caption centre."""
    if t < t0 or t >= t1: return
    key = (text, size, tuple(sorted((k, str(v)) for k, v in kw.items())))
    if key not in _TL: _TL[key] = text_layer(text, size, **kw)
    L = _TL[key]; p = (t - t0) / tin; s, a, dy, rot = 1.0, 1.0, 0.0, 0.0
    if anim == "pop": s = 0.55 + 0.45 * back(p); a = clamp(p * 3)
    elif anim == "slam": s = 1.0 + 0.9 * (1 - ease_out(p)); a = clamp(p * 4)
    elif anim == "up": dy = 90 * (1 - ease_out(p)); a = clamp(p * 2)
    elif anim == "wobble": s = 0.55 + 0.45 * back(p); rot = 6 * math.sin(p * 6) * (1 - clamp(p / 2.5))
    elif anim == "type":
        n = max(1, int(len(text) * clamp(p / 3)))
        if n < len(text): L = text_layer(text[:n], size, **kw)
    if out == "fade" and t1 < 1e8: a *= clamp((t1 - t) / 0.2)
    if out == "down" and t1 < 1e8: dy += 300 * ease_in(1 - clamp((t1 - t) / 0.2))
    if a <= 0.01: return
    if rot: L = L.rotate(rot, Image.BICUBIC, expand=True)
    if abs(s - 1) > 0.005: L = L.resize((max(1, int(L.width * s)), max(1, int(L.height * s))), Image.BILINEAR)
    if a < 0.999: L = L.copy(); L.putalpha(L.getchannel("A").point(lambda v: int(v * a)))
    im.alpha_composite(L, (int(W * x - L.width / 2), int(H * y - L.height / 2 + dy)))
def words(im, text, t, t0, step=None, y=0.5, size=120, max_lines=None, **kw):
    """Word-by-word reveal on the beat (step defaults to half a beat): each new word pops, earlier ones stay."""
    step = beat(0.5) if step is None else step; ws = text.split(); n = int((t - t0) / step) + 1
    if t < t0: return
    shown = " ".join(ws[:min(len(ws), n)])
    caption(im, shown, t, t0=t0 + (min(len(ws), n) - 1) * step if n <= len(ws) else t0 - 1, y=y, size=size, anim="none" if n > len(ws) else "pop", tin=0.12, **kw)
def credit(im, text, t, t0, t1, corner="bl", size=24, y=None):
    """Small licence credit in a corner (shown 1–2 s per source)."""
    if t < t0 or t >= t1: return
    f = font(size, "IBMPlexSans-Medium"); d = ImageDraw.Draw(im); tw = d.textlength(text, font=f)
    x = 34 if corner[1] == "l" else W - 34 - tw
    y = (H - 230 if corner[0] == "b" else 150) if y is None else y                        # stay clear of TikTok's UI
    a = clamp(min(t - t0, t1 - t) / 0.15)
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0)); dl = ImageDraw.Draw(lay)
    dl.rounded_rectangle((x - 12, y - 6, x + tw + 12, y + size + 10), 10, fill=(0, 0, 0, int(120 * a)))
    dl.text((x, y), text, font=f, fill=(255, 255, 255, int(235 * a))); im.alpha_composite(lay)

# ——— stickers (starter-pack / meme look) ———
def sticker(layer, border=16, col=WHITE, shadow=True, rot=0):
    """Die-cut sticker: thick white outline around the alpha shape + soft drop shadow."""
    L = layer.convert("RGBA"); pad = border * 2 + 30
    big = Image.new("RGBA", (L.width + pad * 2, L.height + pad * 2), (0, 0, 0, 0)); big.alpha_composite(L, (pad, pad))
    a = big.getchannel("A").point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(border * 2 + 1))
    out = Image.new("RGBA", big.size, (0, 0, 0, 0))
    if shadow:
        sh = Image.new("RGBA", big.size, (0, 0, 0, 0)); sh.paste((0, 0, 0, 110), (0, 0), a.filter(ImageFilter.GaussianBlur(10)))
        out.alpha_composite(sh, (6, 14))
    out.paste(col + (255,), (0, 0), a); out.alpha_composite(big)
    if rot: out = out.rotate(rot, Image.BICUBIC, expand=True)
    return out
def place(im, L, cx, cy, t, t0, anim="pop", tin=0.3, t1=1e9):
    """Composite a layer centred at (cx, cy) px with an entrance (pop | drop | spin | slide)."""
    if t < t0 or t >= t1: return
    p = (t - t0) / tin; s, dx, dy, r, a = 1.0, 0, 0, 0, 1.0
    if anim == "pop": s = 0.3 + 0.7 * back(p); a = clamp(p * 3)
    elif anim == "drop": dy = -700 * (1 - back(p, 1.4)); r = 14 * (1 - ease_out(p))
    elif anim == "spin": s = 0.2 + 0.8 * back(p); r = -40 * (1 - ease_out(p))
    elif anim == "slide": dx = W * (1 - ease_out(p))
    if r: L = L.rotate(r, Image.BICUBIC, expand=True)
    if abs(s - 1) > 0.005: L = L.resize((max(1, int(L.width * s)), max(1, int(L.height * s))), Image.BILINEAR)
    if a < 0.999: L = L.copy(); L.putalpha(L.getchannel("A").point(lambda v: int(v * a)))
    im.alpha_composite(L, (int(cx + dx - L.width / 2), int(cy + dy - L.height / 2)))
def icon(path, size, col=None):
    """Load a (monochrome) icon PNG, resized to `size`, optionally recoloured."""
    L = Image.open(path).convert("RGBA"); L = L.crop(L.getbbox()) if L.getbbox() else L
    L = ImageOps.contain(L, (size, size), Image.LANCZOS)
    if col: c = Image.new("RGBA", L.size, col + (255,)); c.putalpha(L.getchannel("A")); L = c
    return L
def rounded(img, size, radius=None):
    img = ImageOps.fit(img.convert("RGBA"), (size, size), Image.LANCZOS); m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius or size // 4.4, fill=255); img.putalpha(m); return img

# ——— end card: tiny logo in the last second only ———
_ICON = {}
def endcard(im, t, total, icon_path, url="nordur.info", dur=1.0, dim=0.35, y=0.80, dark_text=False):
    """Small app icon + 'nordur.info' that pops in during the final `dur` seconds (no full-screen card)."""
    t0 = total - dur
    if t < t0: return
    p = (t - t0) / 0.25
    if dim: im.alpha_composite(Image.new("RGBA", im.size, (0, 0, 0, int(255 * dim * clamp(p)))))
    if icon_path not in _ICON: _ICON[icon_path] = sticker(rounded(Image.open(icon_path), 150), border=8)
    ic = _ICON[icon_path]; f = font(84); d = ImageDraw.Draw(Image.new("L", (4, 4))); tw = d.textlength(url, font=f)
    gw = ic.width - 40 + 16 + tw; x0 = (W - gw) / 2; cy = H * y
    place(im, ic, x0 + (ic.width - 40) / 2, cy, t, t0, "pop", 0.3)
    caption(im, url, t, t0=t0 + 0.08, x=(x0 + ic.width - 40 + 16 + tw / 2) / W, y=y, size=84, anim="pop", tin=0.25,
            fill=INK if dark_text else WHITE, stroke=WHITE if dark_text else BLACK, sw=7)

# ——— render ———
def _writer(path):
    return subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium", "-an", "-movflags", "+faststart", path],
                            stdin=subprocess.PIPE)
_JOB = {}
def _chunk(args):
    a, b, path = args; frame = _JOB["frame"]; pr = _writer(path)
    for fi in range(a, b): pr.stdin.write(frame(fi).convert("RGB").tobytes())
    pr.stdin.close(); pr.wait(); return path
def render(frame, total, out_path, procs=1, test=None):
    """Silent 1080×1920 mp4. test=[frame numbers] only saves PNGs next to out_path. procs>1 renders chunks in parallel (fork)."""
    n = int(round(total * FPS))
    if test:
        for fi in test: frame(int(fi)).convert("RGB").save(out_path.replace(".mp4", f"-test-{int(fi)}.png"))
        return
    _JOB["frame"] = frame                                    # inherited by forked workers (closures can't be pickled)
    if procs <= 1: _chunk((0, n, out_path)); print("done", out_path, n); return
    tmp = tempfile.mkdtemp(prefix="tk-"); step = math.ceil(n / procs)
    jobs = [(i, min(n, i + step), os.path.join(tmp, f"c{k}.mp4")) for k, i in enumerate(range(0, n, step))]
    with mp.get_context("fork").Pool(len(jobs)) as pool: parts = pool.map(_chunk, jobs)
    lst = os.path.join(tmp, "list.txt"); open(lst, "w").write("".join(f"file '{p}'\n" for p in parts))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", "-movflags", "+faststart", out_path], check=True)
    print("done", out_path, n)
