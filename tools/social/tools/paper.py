"""Stylised 'paper-cut' relief: elevation bands in flat colours with soft drop shadows and rim light."""
import numpy as np, cv2, os
from PIL import Image
import geo
LAND = [(0, (122, 158, 104)), (60, (140, 170, 108)), (200, (168, 176, 112)), (400, (184, 170, 120)), (650, (170, 150, 118)),
        (900, (150, 134, 116)), (1150, (196, 206, 214)), (1400, (226, 234, 240)), (1700, (244, 248, 252))]
SEA = [(-3000, (24, 52, 78)), (-1500, (30, 64, 94)), (-600, (38, 80, 112)), (-200, (48, 98, 130)), (-60, (62, 118, 146))]
def papercut(e, size, land=LAND, sea=SEA, shadow=(7, 9), soft=7, scale_thr=1.0, hill=0.0):
    E = cv2.resize(e.astype(np.float32), size, interpolation=cv2.INTER_CUBIC)
    E = cv2.GaussianBlur(E, (0, 0), 1.6)                       # smoother, rounder 'cut' edges
    h, w = E.shape
    img = np.zeros((h, w, 3), np.float32); img[:] = sea[0][1]
    layers = [(t * scale_thr if t > 0 else t, c) for t, c in sea[1:] + land]
    for th, col in layers:
        m = (E >= th).astype(np.float32)
        if not m.any(): continue
        m = cv2.GaussianBlur(m, (0, 0), 0.8)
        sh = np.roll(np.roll(m, shadow[1], 0), shadow[0], 1)
        sh = cv2.GaussianBlur(sh, (0, 0), soft) * (1 - m)
        img *= (1 - 0.42 * sh[..., None])                      # soft shadow cast by this layer
        rim = np.clip(m - np.roll(np.roll(m, 2, 0), 2, 1), 0, 1)  # light catching the top-left edge
        lay = np.array(col, np.float32) * (1 + 0.16 * rim[..., None])
        img = img * (1 - m[..., None]) + lay * m[..., None]
    if hill > 0:
        gy, gx = np.gradient(E * 3.0)
        hs = np.clip(0.6 + (-gx * 0.7 - gy * 0.7) / 8.0, 0.2, 1.4)
        img = img * (1 - hill + hill * hs[..., None])
    return np.clip(img, 0, 255)
