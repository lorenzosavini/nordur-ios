"""Shaded-relief basemaps of Iceland from AWS Terrarium tiles (public), Web Mercator."""
import math, os, io, urllib.request, numpy as np
from PIL import Image
TILES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "geo", "tiles")
def lonlat_to_px(lon, lat, z):
    n = 2 ** z * 256
    x = (lon + 180) / 360 * n
    y = (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n
    return x, y
def tile(z, x, y):
    p = os.path.join(TILES, f"{z}_{x}_{y}.png")
    if not os.path.exists(p):
        for _ in range(5):
            try:
                data = urllib.request.urlopen(f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png", timeout=30).read()
                open(p, "wb").write(data); break
            except Exception: import time; time.sleep(2)
    a = np.asarray(Image.open(p).convert("RGB")).astype(np.float32)
    return a[..., 0] * 256 + a[..., 1] + a[..., 2] / 256 - 32768
def dem(lon0, lat0, lon1, lat1, z):
    """Elevation raster covering the box, plus the pixel origin (global px) of its top-left corner."""
    x0, y0 = lonlat_to_px(lon0, lat1, z); x1, y1 = lonlat_to_px(lon1, lat0, z)
    tx0, ty0, tx1, ty1 = int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)
    rows = [np.concatenate([tile(z, tx, ty) for tx in range(tx0, tx1 + 1)], axis=1) for ty in range(ty0, ty1 + 1)]
    full = np.concatenate(rows, axis=0)
    ox, oy = tx0 * 256, ty0 * 256
    return full[int(y0 - oy):int(y1 - oy), int(x0 - ox):int(x1 - ox)], (int(x0), int(y0))
def shade(e, size, az=315, alt=40, exag=2.0, cellsize=1.0, hmax=1800, ice_at=1100):
    """A dark, quiet shaded relief: land in cool greys, sea near-black with faint depth."""
    E = np.asarray(Image.fromarray(e).resize(size, Image.BICUBIC)).astype(np.float32)
    gy, gx = np.gradient(E * exag / cellsize)
    slope = np.arctan(np.hypot(gx, gy)); aspect = np.arctan2(-gx, gy)
    a, al = math.radians(az), math.radians(alt)
    hs = np.clip(np.sin(al) * np.cos(slope) + np.cos(al) * np.sin(slope) * np.cos(a - aspect), 0, 1)
    land = E > 0.5
    h = np.clip(E / hmax, 0, 1)[..., None]
    low = np.array([38, 52, 50], np.float32); high = np.array([150, 158, 160], np.float32)
    col = low * (1 - h) + high * h
    col = col * (0.35 + 0.85 * hs[..., None])
    ice = (E > ice_at)[..., None]                      # glaciers sit high: a cold tint
    col = np.where(ice, col * 0.5 + np.array([200, 215, 225]) * 0.5 * (0.5 + 0.6 * hs[..., None]), col)
    depth = np.clip(-E / 1500, 0, 1)[..., None]
    sea = np.array([14, 24, 34], np.float32) * (1 - depth) + np.array([6, 10, 16], np.float32) * depth
    out = np.where(land[..., None], col, sea)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)), land
