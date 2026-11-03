// The map grid (Open-Meteo, 0.3° × 0.6°) corrected with Veðurstofa Íslands, so
// that the map does not contradict the Weather tab: for every hour, at every IMO
// station, the difference between IMO and the model there; spread to the grid
// points the station stands for (same rule as the app's choice of a station:
// near and at a similar height), fading with distance and height difference.
//
//   - mean wind, direction, temperature, cloud, precipitation: IMO forecast;
//   - the current hour (and fading over the next three): IMO's measurements
//     of the last 10 minutes, wind, gust, direction and temperature;
//   - gusts: the model's, never below the corrected mean wind (as in the app);
//   - snow: the model's (IMO does not forecast it).
// Every difference is capped, so one odd station cannot paint nonsense.

// vedur.is first: a station stands for the land around it up to 30 km at full
// weight, fading to none at 60 km (always at a similar height); the model is
// left alone only where no station reaches (inner Highlands, glaciers, open sea).
const FULL_KM = 30, ZERO_KM = 60;
const FULL_DH = 100, ZERO_DH = 300;   // full weight up to 100 m of height difference, none past 300
const CAP = { T: 6, F: 8, N: 60, R: 3, G: 10 };
const OBS_MAX_AGE = 30 * 60;          // a measurement older than 30 minutes is not "now"

const clamp = (v, cap) => Math.max(-cap, Math.min(cap, v));
const round1 = (v) => Math.round(v * 10) / 10;

export function distanceKm(aLat, aLon, bLat, bLon) {
  const r = Math.PI / 180;
  const dLat = (bLat - aLat) * r, dLon = (bLon - aLon) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * r) * Math.cos(bLat * r) * Math.sin(dLon / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

/** How much a station stands for a point (0…1), by distance and height difference. */
export function weight(km, dh) {
  const fd = km <= FULL_KM ? 1 : km >= ZERO_KM ? 0 : (ZERO_KM - km) / (ZERO_KM - FULL_KM);
  if (dh == null) return fd;
  const a = Math.abs(dh);
  const fh = a <= FULL_DH ? 1 : a >= ZERO_DH ? 0 : (ZERO_DH - a) / (ZERO_DH - FULL_DH);
  return fd * fh;
}

/** Bilinear value of a lat-major field at a point; null outside or when a corner is missing. */
export function bilinear(values, lats, lons, lat, lon) {
  if (lat < lats[0] || lat > lats[lats.length - 1] || lon < lons[0] || lon > lons[lons.length - 1]) return null;
  let i = lats.findIndex((v) => v > lat) - 1; if (i < 0) i = lats.length - 2;
  let j = lons.findIndex((v) => v > lon) - 1; if (j < 0) j = lons.length - 2;
  const at = (a, b) => values[a * lons.length + b];
  const c = [at(i, j), at(i, j + 1), at(i + 1, j), at(i + 1, j + 1)];
  if (c.some((v) => v == null || !Number.isFinite(v))) return null;
  const ty = (lat - lats[i]) / (lats[i + 1] - lats[i]), tx = (lon - lons[j]) / (lons[j + 1] - lons[j]);
  const top = c[0] + (c[1] - c[0]) * tx, bottom = c[2] + (c[3] - c[2]) * tx;
  return top + (bottom - top) * ty;
}

const angle = (a, b) => ((((b - a) % 360) + 540) % 360) - 180; // b − a in −180…180

/**
 * forecasts: Open-Meteo answers in lat-major grid order (each with elevation and
 * hourly arrays, `time` in epoch seconds); lats/lons: the grid axes;
 * stations: [{ id, name, lat, lon, elev }]; imo: Map(id -> { steps }) from
 * parseForecasts; obs: Map(id -> { t, F, FG, D, T }); now: epoch seconds.
 * Returns { forecasts (corrected copies), stations (values for the map markers), used, coverage }.
 */
export function correctGrid(forecasts, lats, lons, stations, imo, obs, now) {
  const times = forecasts.find((f) => f?.hourly?.time?.length)?.hourly.time || [];
  const H = times.length, P = forecasts.length;
  const field = (name) => Array.from({ length: H }, (_, h) => forecasts.map((f) => f?.hourly?.[name]?.[h] ?? null));
  const model = { T: field("temperature_2m"), F: field("wind_speed_10m"), D: field("wind_direction_10m"),
                  N: field("cloud_cover"), R: field("precipitation"), G: field("wind_gusts_10m") };

  // The station's IMO value at each grid hour (IMO is hourly for ~3 days: exact steps only).
  const byStation = stations.map((s) => {
    const steps = new Map((imo.get(s.id)?.steps || []).map((x) => [x.t, x]));
    return { s, steps, obs: obs?.get(s.id) };
  }).filter((x) => x.steps.size || x.obs);

  // Weights of each station on each grid point (fixed geometry).
  const links = forecasts.map((f, p) => {
    const lat = lats[Math.floor(p / lons.length)], lon = lons[p % lons.length];
    return byStation.map((x, k) => [k, weight(distanceKm(lat, lon, x.s.lat, x.s.lon), f?.elevation != null && x.s.elev != null ? f.elevation - x.s.elev : null)])
      .filter(([, w]) => w > 0);
  });

  const nowHour = times.findIndex((t) => Math.abs(t - now) <= 1800);
  const out = forecasts.map((f) => f && { ...f, hourly: { ...f.hourly,
    temperature_2m: [...(f.hourly?.temperature_2m || [])], wind_speed_10m: [...(f.hourly?.wind_speed_10m || [])],
    wind_direction_10m: [...(f.hourly?.wind_direction_10m || [])], cloud_cover: [...(f.hourly?.cloud_cover || [])],
    precipitation: [...(f.hourly?.precipitation || [])], wind_gusts_10m: [...(f.hourly?.wind_gusts_10m || [])] } });
  const markers = byStation.map((x) => ({ id: x.s.id, name: x.s.name, lat: x.s.lat, lon: x.s.lon,
    wind: Array(H).fill(null), dir: Array(H).fill(null), temp: Array(H).fill(null),
    obs: x.obs && now - x.obs.t <= OBS_MAX_AGE ? { time: new Date(x.obs.t * 1000).toISOString(), wind: round1(x.obs.F ?? 0), gust: x.obs.FG == null ? null : round1(x.obs.FG), dir: x.obs.D, temp: x.obs.T == null ? null : round1(x.obs.T) } : null }));
  let used = 0;

  for (let h = 0; h < H; h++) {
    const at = (k) => (name) => bilinear(model[name][h], lats, lons, byStation[k].s.lat, byStation[k].s.lon);
    // Share of the measurement in this hour: 1 now, fading to 0 three hours later.
    const live = nowHour >= 0 && h >= nowHour && h < nowHour + 4 ? 1 - (h - nowHour) / 4 : 0;
    const deltas = byStation.map((x, k) => {
      const m = at(k);
      const fc = x.steps.get(times[h]);
      const o = live > 0 && x.obs && now - x.obs.t <= OBS_MAX_AGE ? x.obs : null;
      const d = {};
      const mix = (key, f, ob) => {
        const base = m(key);
        if (base == null) return;
        const a = f != null ? f - base : null, b = ob != null ? ob - base : null;
        // The measurement's share fades into the forecast's (or into the model when IMO has no forecast there).
        const v = a == null && b == null ? null : (b != null ? live * b : 0) + (a != null ? (b != null ? 1 - live : 1) * a : 0);
        if (v != null) d[key] = clamp(v, CAP[key]);
      };
      mix("T", fc?.T, o?.T);
      mix("F", fc?.F, o?.F);
      mix("N", fc?.N, null);
      mix("R", fc?.R, null);
      if (o?.FG != null && m("G") != null) d.G = clamp(live * (o.FG - m("G")), CAP.G);
      const dirIMO = o?.D != null && live >= 0.5 ? o.D : fc?.D;
      const dirModel = m("D");
      if (dirIMO != null && dirModel != null && (fc?.F ?? o?.F ?? 0) >= 1) d.D = angle(dirModel, dirIMO);
      // Marker values: the IMO value itself (measured now, else forecast).
      const mk = markers[k];
      const r1 = (v) => (v == null ? null : round1(v));
      mk.wind[h] = r1(o?.F != null && live === 1 ? o.F : fc?.F);
      mk.temp[h] = r1(o?.T != null && live === 1 ? o.T : fc?.T);
      mk.dir[h] = o?.D != null && live === 1 ? o.D : fc?.D ?? null;
      return Object.keys(d).length ? d : null;
    });
    if (deltas.some(Boolean)) used = Math.max(used, deltas.filter(Boolean).length);

    for (let p = 0; p < P; p++) {
      const f = out[p];
      if (!f) continue;
      const sum = { T: 0, F: 0, N: 0, R: 0, G: 0, D: 0 }, wsum = { T: 0, F: 0, N: 0, R: 0, G: 0, D: 0 };
      for (const [k, w] of links[p]) {
        const d = deltas[k];
        if (!d) continue;
        for (const key of Object.keys(d)) { sum[key] += w * d[key]; wsum[key] += w; }
      }
      const corr = (key) => (wsum[key] > 0 ? sum[key] / Math.max(1, wsum[key]) : 0);
      const hy = f.hourly;
      if (hy.temperature_2m[h] != null) hy.temperature_2m[h] = round1(hy.temperature_2m[h] + corr("T"));
      // A sheltered station must not calm a whole 30 km cell: at least 40% of the model's wind.
      if (hy.wind_speed_10m[h] != null) hy.wind_speed_10m[h] = round1(Math.max(0.4 * hy.wind_speed_10m[h], hy.wind_speed_10m[h] + corr("F")));
      if (hy.cloud_cover[h] != null) hy.cloud_cover[h] = Math.round(Math.min(100, Math.max(0, hy.cloud_cover[h] + corr("N"))));
      if (hy.precipitation[h] != null) hy.precipitation[h] = round1(Math.max(0, hy.precipitation[h] + corr("R")));
      if (hy.wind_direction_10m[h] != null && wsum.D > 0) hy.wind_direction_10m[h] = Math.round((hy.wind_direction_10m[h] + corr("D") + 360) % 360);
      if (hy.wind_gusts_10m[h] != null) {
        const g = hy.wind_gusts_10m[h] + corr("G");
        hy.wind_gusts_10m[h] = round1(Math.max(g, hy.wind_speed_10m[h] ?? 0));
      }
    }
  }
  // How much of each grid point comes from vedur.is (0 = model only), for the map's veil.
  const coverage = links.map((l) => Math.round(Math.min(1, l.reduce((a, [, w]) => a + w, 0)) * 100) / 100);
  return { forecasts: out, stations: markers.filter((m) => m.wind.some((v) => v != null) || m.obs), used, coverage };
}
