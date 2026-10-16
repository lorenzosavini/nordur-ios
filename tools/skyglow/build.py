import h5py, numpy as np, glob, sys, json
DATA = sys.argv[1]
G = 'HDFEOS/GRIDS/VIIRS_Grid_DNB_2d/Data Fields/'
# Mosaic of the two 10°x10° tiles (lon -30..-10, lat 60..70), 15" pixels.
tiles = {}
for f in sorted(glob.glob(DATA + '/*.h5')):
    h = h5py.File(f, 'r')
    r = h[G + 'AllAngle_Composite_Snow_Free'][:].astype(np.float64)
    q = h[G + 'AllAngle_Composite_Snow_Free_Quality'][:]
    m = h[G + 'Land_Water_Mask'][:]
    r[(r < 0) | (q == 255)] = 0.0
    # Natural background over land (airglow, residual moonlight, noise) is ~0.8–1 nW/cm²·sr; sea pixels are 0.
    r = np.maximum(r - 1.0, 0.0)
    tiles[int(h.attrs['WestBoundingCoord'])] = (r, h[G + 'lat'][:], h[G + 'lon'][:])
R = np.hstack([tiles[-30][0], tiles[-20][0]])
lat = tiles[-30][1]; lon = np.concatenate([tiles[-30][2], tiles[-20][2]])
# Restrict to Iceland + 1° margin and aggregate 6x6 pixels (≈ 2.5' ≈ 4.6 km x 2 km) to keep the convolution cheap.
la = (lat >= 62.3) & (lat <= 67.6); lo = (lon >= -26.5) & (lon <= -11.5)
R = R[np.ix_(la, lo)]; lat = lat[la]; lon = lon[lo]
k = 6
n0, n1 = R.shape[0] // k * k, R.shape[1] // k * k
Rb = R[:n0, :n1].reshape(n0 // k, k, n1 // k, k).mean(axis=(1, 3))
latb = lat[:n0].reshape(-1, k).mean(1); lonb = lon[:n1].reshape(-1, k).mean(1)
# Emitted power per block ∝ radiance × area (area ∝ cos φ).
P = Rb * np.cos(np.radians(latb))[:, None]
LA, LO = np.meshgrid(latb, lonb, indexing='ij')

def skyglow(plat, plon):
    # Walker's law: sky brightness from a source falls as d^-2.5 (≈ 1–100 km).
    dy = (LA - plat) * 111.2
    dx = (LO - plon) * 111.2 * np.cos(np.radians(plat))
    d = np.hypot(dx, dy)
    w = np.where(d <= 80, np.maximum(d, 1.0) ** -2.5, 0.0)
    return float((P * w).sum())

# Output grid over Iceland.
LAT0, LAT1, DLAT = 63.20, 66.70, 0.05
LON0, LON1, DLON = -24.60, -13.40, 0.10
lats = np.round(np.arange(LAT0, LAT1 + 1e-9, DLAT), 3); lons = np.round(np.arange(LON0, LON1 + 1e-9, DLON), 3)
S = np.array([[skyglow(a, b) for b in lons] for a in lats])
np.save(sys.argv[2] + '/skyglow.npy', S)
json.dump({'lat0': LAT0, 'dlat': DLAT, 'nlat': len(lats), 'lon0': LON0, 'dlon': DLON, 'nlon': len(lons)}, open(sys.argv[2] + '/grid.json', 'w'))
print(S.shape, 'max', S.max(), 'p50', np.median(S), 'p90', np.percentile(S, 90))
