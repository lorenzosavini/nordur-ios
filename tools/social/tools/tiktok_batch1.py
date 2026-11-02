"""TikTok batch 1 — six short "text + trending sound" videos for Norður (silent mp4s, sound added in TikTok).
Usage: python tiktok_batch1.py <media_dir> <fonts_dir> <out_dir> <video 1-6|all> [procs] [test frame numbers...]
<media_dir>: Commons downloads (see projects/tiktok1/dl.py) + credits.json. Icons: tools/social/icons, logo: site/landing/img/icon.png.
1 weather · 2 starter pack · 3 tell me you're in Iceland · 4 wait for it (Strokkur) · 5 expectation vs reality · 6 makes sense in Iceland."""
import sys, os, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps, ImageEnhance
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tiktok as tk
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
ICONS = os.path.join(REPO, "tools", "social", "icons"); APPICON = os.path.join(REPO, "site", "landing", "img", "icon.png")
M, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]; WHICH = sys.argv[4]
PROCS = int(sys.argv[5]) if len(sys.argv) > 5 else 4; TEST = sys.argv[6:]
tk.setup(FONTS, bpm=120); W, H, FPS = tk.W, tk.H, tk.FPS; B = tk.beat()      # B = 0.5 s
CRED = json.load(open(os.path.join(M, "credits.json")))
def cr(k): return CRED[k]["credit"]
def mp(k): return os.path.join(M, k + ".mp4")
def ph(k): return os.path.join(M, k + ".img")

# ————————————————————————— shared bits —————————————————————————
def src(k, **kw):
    """Media key → Photo or Video (kwargs: focus/z/drift for photos, start/dur/xshift/speed for videos)."""
    if k.startswith("v_"):
        return tk.Video(mp(k), **{a: b for a, b in kw.items() if a in ("start", "dur", "xshift", "speed", "loop", "fit", "size")})
    return tk.Photo(ph(k), **{a: b for a, b in kw.items() if a in ("focus", "z", "dur", "drift", "over", "size")})
def chip(im, text, t, t0, t1, icon_name=None, y=0.80, col=tk.INK, bg=(255, 255, 255)):
    """Small label chip (time / place) with an optional icon, bottom-centre."""
    if t < t0 or t >= t1: return
    tk.caption(im, text, t, t0, t1, y=y, size=64, fill=col, box=bg, anim="pop", tin=0.2, name="IBMPlexSans-SemiBold")
def particles(im, t, kind, n=260, seed=1):
    """Procedural rain streaks or snowflakes over the frame."""
    r = np.random.default_rng(seed); L = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(L)
    xs, ys, sp, sz = r.uniform(0, W, n), r.uniform(0, H, n), r.uniform(0.6, 1.4, n), r.uniform(0.5, 1.5, n)
    if kind == "rain":
        for x, y, v, z in zip(xs, ys, sp, sz):
            yy = (y + t * 2600 * v) % (H + 200) - 100; xx = (x - t * 500 * v) % W
            d.line((xx, yy, xx - 14 * z, yy + 70 * z), fill=(220, 230, 240, int(120 * z)), width=max(1, int(2 * z)))
    else:
        for x, y, v, z in zip(xs, ys, sp, sz):
            yy = (y + t * 260 * v) % (H + 40) - 20; xx = (x + t * 340 * v + 30 * math.sin(t * 2 + y)) % W; rr = 3 + 5 * z
            d.ellipse((xx - rr, yy - rr, xx + rr, yy + rr), fill=(255, 255, 255, int(150 + 80 * (z - 0.5))))
    im.alpha_composite(L.filter(ImageFilter.GaussianBlur(0.8)))
def grade(img, kind):
    if kind == "grey": return ImageEnhance.Color(ImageEnhance.Brightness(img).enhance(0.9)).enhance(0.6)
    if kind == "warm": return ImageEnhance.Color(img).enhance(1.15)
    return img

# ————————————————————————— 1 · WEATHER IN ONE AFTERNOON —————————————————————————
def v1():
    TOTAL = 13.0; SEG = 2.0                                   # 4 beats per weather
    segs = [("p_ring", "1:00 PM", "sun", None, dict(focus=(0.5, 0.55), z=(1.0, 1.1))),
            ("p_rain", "2:00 PM", "cloud", "rain", dict(focus=(0.3, 0.5), z=(1.04, 1.12))),
            ("v_windy", "3:00 PM", "wind", None, dict(start=0.5, dur=2.2, xshift=0.05)),
            ("p_drive", "4:00 PM", "snowflake", "snow", dict(focus=(0.5, 0.5), z=(1.0, 1.1))),
            ("p_ring2", "5:00 PM", "sun", None, dict(focus=(0.5, 0.5), z=(1.0, 1.06), dur=5.0))]
    S = [src(k, dur=kw.pop("dur", SEG), **kw) for k, _, _, _, kw in segs]
    cuts = [i * SEG for i in range(5)]
    icons = {n: tk.icon(os.path.join(ICONS, n + ".png"), 70, tk.INK) for n in ("sun", "cloud", "wind", "snowflake")}
    words_ = {"sun": "sun", "cloud": "rain", "wind": "wind", "snowflake": "snow"}
    def frame(fi):
        t = fi / FPS; i, lt = tk.segment(t, cuts); k, clock, ic, fx, _ = segs[i]
        im = tk.canvas(S[i].frame(lt, tk.punch(t, cuts[1:], 0.07, 0.3)), tk.shake(t, cuts[1:4], 12, 0.2))
        if fx and lt < SEG: particles(im, t, fx, 420 if fx == "rain" else 300, seed=i)
        tk.flash(im, t, cuts[1:], 0.1, strength=0.6)
        tk.caption(im, "POV: ONE afternoon\nin Iceland", t, 0.0, 10.0, y=0.17, size=112, anim="pop")
        if t < 10.0:                                           # clock + weather chip
            tk.caption(im, f"{clock}  ·  {words_[ic]}", t, cuts[i], cuts[i] + SEG, y=0.78, size=66, fill=tk.INK, box=(255, 255, 255), anim="pop", tin=0.18, name="IBMPlexSans-SemiBold")
        if 10.0 <= t < 12.0:
            tk.caption(im, "“If you don’t like the weather, wait five minutes.”", t, 10.0, 12.0, y=0.36, size=96, anim="pop", width=900)
            tk.caption(im, "— old Icelandic saying", t, 10.5, 12.0, y=0.50, size=56, anim="up", name="IBMPlexSans-SemiBold")
        if t >= 12.0: tk.caption(im, "Norður checks it for you", t, 12.0, y=0.40, size=110, anim="slam", tin=0.18)
        credits = [(0.1, "p_ring"), (2.1, "p_rain"), (4.1, "v_windy"), (6.1, "p_drive"), (8.1, "p_ring2")]
        for c0, ck in credits: tk.credit(im, cr(ck), t, c0, c0 + 1.8)
        tk.endcard(im, t, TOTAL, APPICON, dim=0.25, y=0.80)
        return im
    return frame, TOTAL, "1-iceland-weather-one-afternoon.mp4"

# ————————————————————————— 3 · TELL ME YOU'RE IN ICELAND —————————————————————————
def v3():
    TOTAL = 9.0
    segs = [("p_hotspring", "hot spring + snow", dict(focus=(0.5, 0.3), z=(1.0, 1.12), dur=2.0)),
            ("v_horses", "the horses", dict(start=0.2, dur=1.1, xshift=0.17)),
            ("p_midnight", "the sun at midnight", dict(focus=(0.55, 0.5), z=(1.05, 1.15), dur=1.0)),
            ("p_sheep2", "the locals", dict(focus=(0.55, 0.5), z=(1.02, 1.12), dur=1.0)),
            ("v_windy", "black sand beach", dict(start=3.0, dur=1.1, xshift=0.04)),
            ("v_strokkur", "a geyser on schedule", dict(start=2.6, dur=1.1, xshift=-0.012)),
            ("v_hotdog", "the hot dog stand", dict(start=1.0, dur=2.1, xshift=0.05))]
    S = [src(k, **kw) for k, _, kw in segs]; cuts = [0.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
    def frame(fi):
        t = fi / FPS; i, lt = tk.segment(t, cuts); k, lab, kw = segs[i]
        z = tk.punch(t, cuts[1:], 0.08, 0.3) * (1.25 if k == "v_strokkur" else 1.0)
        im = tk.canvas(S[i].frame(lt, z)); tk.flash(im, t, cuts[1:], 0.08, strength=0.5)
        tk.caption(im, "Tell me you’re in Iceland without telling me", t, 0.0, 2.0, y=0.30, size=118, anim="pop", width=900)
        if t >= 2.0: tk.caption(im, "without telling me:", t, 2.0, 8.0, y=0.12, size=70, anim="none")
        tk.caption(im, lab, t, cuts[i] + (0.6 if i == 0 else 0.05), (cuts[i + 1] if i + 1 < len(cuts) else 8.0), y=0.74, size=66, fill=tk.INK, box=(255, 255, 255), anim="pop", tin=0.15, name="IBMPlexSans-SemiBold")
        tk.credit(im, cr(k), t, cuts[i] + 0.05, min(cuts[i] + 1.0, TOTAL - 1.0) if i else 1.9)
        tk.endcard(im, t, TOTAL, APPICON, dim=0.3, y=0.80)
        return im
    return frame, TOTAL, "3-tell-me-youre-in-iceland.mp4"

# ————————————————————————— 5 · EXPECTATION VS REALITY —————————————————————————
def v5():
    """Top half = expectation, bottom half = reality; reality slams in one beat later."""
    TOTAL = 12.0
    pairs = [(("v_aurora2", dict(start=0.0, dur=4.0, xshift=0.1)), ("v_aurora", dict(start=1.0, dur=4.0)), "Northern lights", "you see a faint glow behind clouds"),
             (("v_selja", dict(start=0.0, dur=4.0)), ("p_skogacrowd", dict(focus=(0.5, 0.6), z=(1.0, 1.1), dur=4.0)), "Waterfall day", "you, soaked by the spray"),
             (("v_godafoss", dict(start=0.0, dur=3.0)), ("p_blizzard", dict(focus=(0.45, 0.5), z=(1.0, 1.08), dur=3.0)), "Winter waterfall trip", "the drive there")]
    HH = H // 2
    S = [(src(a[0], size=(W, HH), **dict(a[1])), src(b[0], size=(W, HH), **dict(b[1]))) for a, b, _, _ in pairs]; cuts = [0.0, 4.0, 8.0]
    def half(img): return img
    def frame(fi):
        t = fi / FPS; i, lt = tk.segment(t, cuts); (a, b), (pa, pb, place_, joke) = S[i], pairs[i]
        im = Image.new("RGBA", (W, H), tk.INK + (255,))
        top = a.frame(lt, 1.0 + 0.05 * lt / 4); im.paste(half(top), (0, 0))
        if lt >= B * 2:                                        # reality lands on beat 3 of each pair
            bot = b.frame(lt - B * 2, tk.punch(lt, [B * 2], 0.08, 0.3)); im.paste(grade(half(bot), "grey" if pb[0].startswith("p_") else None), (0, HH))
            tk.flash(im, lt, [B * 2], 0.1, strength=0.6)
        else:
            ImageDraw.Draw(im).rectangle((0, HH, W, H), fill=(30, 32, 36))
            tk.caption(im, "…", t, cuts[i], cuts[i] + B * 2, y=0.75, size=160, anim="none")
        ImageDraw.Draw(im).rectangle((0, HH - 5, W, HH + 5), fill=(255, 255, 255))
        tk.caption(im, "EXPECTATION", t, cuts[i], cuts[i] + 4, y=0.07, size=92, anim="pop" if i == 0 else "none")
        tk.caption(im, place_, t, cuts[i] + 0.1, cuts[i] + 4, y=0.42, size=64, fill=tk.INK, box=(255, 255, 255), anim="pop", name="IBMPlexSans-SemiBold")
        if lt >= B * 2:
            tk.caption(im, "REALITY", t, cuts[i] + B * 2, cuts[i] + 4, y=0.57, size=92, anim="slam", tin=0.15)
            tk.caption(im, joke, t, cuts[i] + B * 3, cuts[i] + 4, y=0.92, size=56, fill=tk.INK, box=(255, 255, 255), anim="up", width=980, name="IBMPlexSans-SemiBold")
        tk.credit(im, cr(pa[0]), t, cuts[i] + 0.1, cuts[i] + 1.4, corner="br", y=HH - 50)
        tk.credit(im, cr(pb[0]), t, cuts[i] + 1.1, cuts[i] + 2.6, corner="bl")
        if t >= 10.0:
            im.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(170 * tk.clamp((t - 10.0) / 0.2)))))
            tk.caption(im, "Check before you go", t, 10.0, y=0.40, size=120, anim="slam", tin=0.18)
            tk.caption(im, "with Norður", t, 10.4, y=0.50, size=120, fill=tk.AURORA, anim="pop")
        tk.endcard(im, t, TOTAL, APPICON, dim=0.0, y=0.80)
        return im
    return frame, TOTAL, "5-expectation-vs-reality.mp4"

# ————————————————————————— 6 · THINGS THAT JUST MAKE SENSE —————————————————————————
def v6():
    TOTAL = 15.0
    facts = [("v_lagoon", "Swimming outside\nat −5 °C", "geothermal water, all year round", dict(start=0.0, dur=2.6)),
             ("p_sunrise", "The sun rises\nat 11:20 a.m.", "Reykjavík, late December", dict(focus=(0.5, 0.5), z=(1.0, 1.1), dur=2.6)),
             ("p_galga", "Moving a 70-tonne\n“elf church” rock\nfor a new road", "Gálgahraun lava field, 2015", dict(focus=(0.5, 0.5), z=(1.0, 1.1), dur=2.6)),
             ("p_beer", "Beer was banned\nuntil 1989", "strong beer, 1915 – 1 March 1989", dict(focus=(0.5, 0.5), z=(1.0, 1.1), dur=2.6)),
             ("p_ok", "A glacier\nhad a funeral", "Okjökull, 18 August 2019", dict(focus=(0.5, 0.5), z=(1.0, 1.1), dur=2.6))]
    S = [src(k, **kw) for k, _, _, kw in facts]; cuts = [0.0, 1.5, 4.0, 6.5, 9.0, 11.5, 14.0]
    S[4] = tk.PhotoCard(ph("p_ok"), width=900, cy=0.53, dur=3.5)
    g = np.clip(1 - np.arange(H) / (H * 0.45), 0, 1) ** 1.4 * 200 + 40                 # dark top gradient + light overall dim
    TOPSHADE = Image.fromarray(np.dstack([np.zeros((H, W, 3), np.uint8), np.repeat(g.astype(np.uint8)[:, None], W, 1)]), "RGBA")
    def frame(fi):
        t = fi / FPS; i, lt = tk.segment(t, cuts); j = max(0, min(4, i - 1))
        base = S[0].frame(t, 1.15) if i == 0 else S[j].frame(lt if i <= 5 else lt + 2.5, tk.punch(t, cuts[1:6], 0.07, 0.3))
        im = tk.canvas(base); tk.flash(im, t, cuts[1:6], 0.08, strength=0.5)
        if i == 0:
            im.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, 90)))
            tk.caption(im, "Things that just make sense in Iceland", t, 0.0, 1.5, y=0.40, size=128, anim="pop", width=900)
            return im
        k, line, note, _ = facts[j]; t0 = cuts[min(i, 5)]
        im.alpha_composite(TOPSHADE)
        if i <= 5:
            tk.caption(im, f"{j + 1}/5", t, t0, t0 + 2.5, y=0.09, size=60, anim="none", name="IBMPlexSans-SemiBold")
            tk.caption(im, line, t, t0, t0 + 2.5, y=0.22, size=110, anim="slam", tin=0.16, width=900)
            tk.caption(im, note, t, t0 + 0.6, t0 + 2.5, y=0.78, size=54, fill=tk.INK, box=(255, 255, 255), anim="up", width=960, name="IBMPlexSans-SemiBold")
            tk.credit(im, cr(k), t, t0 + 0.1, t0 + 1.9)
        tk.endcard(im, t, TOTAL, APPICON, dim=0.3, y=0.80)
        return im
    return frame, TOTAL, "6-things-that-make-sense-in-iceland.mp4"

# ————————————————————————— 4 · WAIT FOR IT (Strokkur) —————————————————————————
def v4():
    """Static wide shot, 'Wait for it…' → eruption exactly on beat 8 (4.0 s) → fast rewind back to the first frame (clean loop)."""
    TOTAL = 9.5; ERUPT = 4.0; S0 = 1.85                      # source second where the dome breaks
    v = tk.Video(mp("v_strokkur"), start=0, dur=7.0, xshift=-0.012)
    def src(t):
        if t < ERUPT: return S0 * t / ERUPT                    # slow-mo anticipation (0.36×)
        if t < 8.0: return S0 + (t - ERUPT) * 1.0              # real-time eruption
        k = tk.smooth((t - 8.0) / (TOTAL - 8.3)); return (S0 + 4.0) * (1 - min(1, k))   # rewind to frame 0
    def frame(fi):
        t = fi / FPS; z = 1.25 + 0.08 * tk.smooth(t / ERUPT) if t < ERUPT else 1.25 + 0.08 * (1 - tk.smooth((t - ERUPT) / 4))
        z *= tk.punch(t, [ERUPT], 0.10, 0.45); dx, dy = tk.shake(t, [ERUPT], 22, 0.5)
        im = tk.canvas(v.frame(src(t), z), (dx, dy) if (dx or dy) else (0, 0))
        tk.flash(im, t, [ERUPT], 0.15, strength=0.7)
        if t < ERUPT:
            dots = "." * (1 + int(t / B) % 3)
            tk.caption(im, "Wait for it" + dots, t, 0.15, ERUPT, y=0.30, size=128, anim="pop" if t < 0.6 else "none")
        tk.caption(im, "THERE SHE GOES", t, ERUPT, 6.0, y=0.24, size=150, anim="slam", tin=0.18)
        tk.caption(im, "Strokkur erupts every few minutes", t, 6.0, 8.0, y=0.24, size=100, anim="pop")
        tk.caption(im, "(so yes, you can watch it again)", t, 6.5, 8.0, y=0.33, size=64, anim="up")
        tk.credit(im, cr("v_strokkur"), t, 0.2, 2.2)
        tk.endcard(im, t, TOTAL, APPICON, dim=0.0, y=0.80)
        return im
    return frame, TOTAL, "4-wait-for-it-strokkur.mp4"

# ————————————————————————— 2 · STARTER PACK —————————————————————————
def beanie(size=220, col=(16, 18, 22)):
    """Outline beanie drawn in the same stroke style as the Tabler icons."""
    L = Image.new("RGBA", (512, 512), (0, 0, 0, 0)); d = ImageDraw.Draw(L); w = 34
    d.arc((86, 150, 426, 470), 180, 360, fill=col, width=w)                       # dome
    d.rounded_rectangle((70, 300, 442, 390), 26, outline=col, width=w)            # folded rib band
    for x in (150, 220, 290, 360): d.line((x, 318, x, 372), fill=col, width=18)
    d.ellipse((206, 60, 306, 160), outline=col, width=w)                         # pompom
    return ImageOps.contain(L, (size, size), Image.LANCZOS)
def spikes(size=220, col=(16, 18, 22)):
    L = tk.icon(os.path.join(ICONS, "shoe.png"), 512, col).copy(); bb = L.getbbox(); d = ImageDraw.Draw(L)
    y = bb[3] - 6
    for x in range(bb[0] + 40, bb[2] - 30, 62): d.polygon([(x, y), (x + 34, y), (x + 17, y + 46)], fill=col)
    return ImageOps.contain(L, (size, size), Image.LANCZOS)
def badge(icon_layer, disk_col, d=210, rot=0):
    D = Image.new("RGBA", (d, d), (0, 0, 0, 0)); ImageDraw.Draw(D).ellipse((0, 0, d - 1, d - 1), fill=disk_col + (255,))
    D.alpha_composite(icon_layer, ((d - icon_layer.width) // 2, (d - icon_layer.height) // 2))
    return tk.sticker(D, border=12, rot=rot)
def v2():
    TOTAL = 10.0; BG = tk.AURORA; INK = tk.INK
    ic = lambda n: tk.icon(os.path.join(ICONS, n + ".png"), 135, INK)
    items = [  # (layer, label, joke)
        (badge(ic("shirt"), (255, 214, 10), rot=-5), "Windproof jacket", "not optional"),
        (badge(beanie(150), (255, 140, 190), rot=4), "Beanie", "yes, in July too"),
        (badge(ic("swimming"), (120, 170, 255), rot=-3), "Swimsuit", "yes, in January"),
        (badge(ic("battery-charging"), (255, 255, 255), rot=5), "Power bank", "cold drains batteries"),
        (badge(ic("bottle"), (255, 190, 120), rot=-4), "Hand cream", "the wind is merciless"),
        (badge(spikes(150), (200, 210, 255), rot=3), "Microspikes", "icy paths are no joke"),
    ]
    app = tk.sticker(tk.rounded(Image.open(APPICON), 380), border=16, rot=-4)
    cells = [(280, 640), (800, 640), (280, 1060), (800, 1060), (280, 1480), (800, 1480)]
    T_IN = [1.0 + i * 1.0 for i in range(6)]; T_APP = 7.0; cuts = [0.0] + T_IN + [T_APP]
    rng = np.random.default_rng(3); dots = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dd = ImageDraw.Draw(dots)
    for y in range(0, H, 54):
        for x in range((y // 54) % 2 * 27, W, 54): dd.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(255, 255, 255, 60))
    def frame(fi):
        t = fi / FPS; im = Image.new("RGBA", (W, H), BG + (255,)); im.alpha_composite(dots)
        tk.caption(im, "Starter pack:", t, 0.0, y=0.085, size=90, fill=INK, stroke=(255, 255, 255), sw=0, shadow=False, anim="pop")
        tk.caption(im, "ICELAND TRIP", t, 0.25, y=0.155, size=140, fill=(255, 255, 255), stroke=INK, sw=14, anim="slam", tin=0.2)
        for (L, lab, joke), (cx, cy), t0 in zip(items, cells, T_IN):
            tk.place(im, L, cx, cy - 50, t, t0, "pop", 0.32)
            tk.caption(im, lab, t, t0 + 0.08, x=cx / W, y=(cy + 125) / H, size=68, fill=INK, stroke=(255, 255, 255), sw=7, shadow=False, anim="pop", width=500)
            tk.caption(im, joke, t, t0 + 0.25, x=cx / W, y=(cy + 192) / H, size=44, fill=(255, 255, 255), box=tk.ORANGE, anim="up", width=520, name="IBMPlexSans-SemiBold")
        if t >= T_APP:                                                  # punchline: grid dims, the app slams in
            im.alpha_composite(Image.new("RGBA", (W, H), INK + (int(170 * tk.clamp((t - T_APP) / 0.2)),)))
            tk.caption(im, "and the one you will actually use:", t, T_APP, y=0.30, size=70, anim="pop", width=900)
            tk.place(im, app, W / 2, H * 0.50, t, T_APP + 0.15, "spin", 0.4)
            tk.caption(im, "The Norður app", t, T_APP + 0.35, y=0.66, size=120, anim="slam", tin=0.18)
            tk.caption(im, "weather, roads & alerts", t, T_APP + 0.6, y=0.735, size=54, fill=INK, box=tk.AURORA, anim="up", width=900, name="IBMPlexSans-SemiBold")
        z = tk.punch(t, cuts[1:], 0.025, 0.25)
        if z > 1.001: im = im.resize((int(W * z), int(H * z)), Image.BILINEAR).crop((int(W * (z - 1) / 2), int(H * (z - 1) / 2), int(W * (z - 1) / 2) + W, int(H * (z - 1) / 2) + H))
        tk.flash(im, t, [T_APP + 0.15], 0.12, strength=0.5)
        if t >= TOTAL - 1.0:                                            # last second: small logo + url over a cream wash
            k = tk.clamp((t - TOTAL + 1.0) / 0.2); im.alpha_composite(Image.new("RGBA", (W, H), tk.CREAM + (int(250 * k),)))
            tk.endcard(im, t, TOTAL, APPICON, dim=0.0, y=0.5, dark_text=True)
        return im
    return frame, TOTAL, "2-starter-pack-iceland.mp4"

VIDEOS = {"1": v1, "2": v2, "3": v3, "4": v4, "5": v5, "6": v6}
if __name__ == "__main__":
    for k in (sorted(VIDEOS) if WHICH == "all" else [WHICH]):
        frame, total, name = VIDEOS[k]()
        tk.render(frame, total, os.path.join(OUT, name), procs=PROCS, test=TEST or None)
