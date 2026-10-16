// Terrain horizon from a digital elevation model.
// Source: EU-DEM v1.1 25 m (Copernicus Land Monitoring Service, free reuse with
// attribution) via the OpenTopoData public API (≤100 points per request).
// For 16 azimuths × 12 distances (two requests, the API allows 100 points and
// 1 call per second) the horizon angle is the highest terrain elevation angle
// over samples at 1–40 km, corrected for Earth curvature and standard
// refraction (k = 0.13), seen from 2 m above the ground.
import { fetchJSON } from "./fetch.js";

export const AZIMUTHS = Array.from({ length: 16 }, (_, i) => i * 22.5);
export const DISTANCES_KM = [1, 1.5, 2.5, 3.5, 5, 7, 9, 12, 15, 20, 28, 40];
const R = 6371;
const K = 0.13;
const EYE = 2; // m

/** Point at `km` from (lat, lon) along `azimuth` (great circle). */
export function destination(lat, lon, azimuth, km) {
  const d = km / R, th = (azimuth * Math.PI) / 180, p1 = (lat * Math.PI) / 180, l1 = (lon * Math.PI) / 180;
  const p2 = Math.asin(Math.sin(p1) * Math.cos(d) + Math.cos(p1) * Math.sin(d) * Math.cos(th));
  const l2 = l1 + Math.atan2(Math.sin(th) * Math.sin(d) * Math.cos(p1), Math.cos(d) - Math.sin(p1) * Math.sin(p2));
  return [(p2 * 180) / Math.PI, (((l2 * 180) / Math.PI + 540) % 360) - 180];
}

/** Apparent elevation angle (°) of terrain `dh` m higher than the eye at `km`. */
export function terrainAngle(dh, km) {
  const drop = ((km * 1000) ** 2 / (2 * R * 1000)) * (1 - K);
  return (Math.atan2(dh - drop, km * 1000) * 180) / Math.PI;
}

export function profile(observerElevation, elevations) {
  // elevations: [azimuth][distance]
  return AZIMUTHS.map((az, i) => {
    let best = -90, at = null;
    DISTANCES_KM.forEach((km, j) => {
      const h = elevations[i][j];
      if (h == null) return;
      const a = terrainAngle(h - (observerElevation + EYE), km);
      if (a > best) { best = a; at = km; }
    });
    return { azimuth: az, angle: Math.round(Math.max(0, best) * 10) / 10, distanceKm: at };
  });
}

export async function horizon(lat, lon) {
  const points = [[lat, lon]];
  for (const az of AZIMUTHS) for (const km of DISTANCES_KM) points.push(destination(lat, lon, az, km));
  const values = [];
  for (let i = 0; i < points.length; i += 100) {
    if (i > 0) await new Promise((r) => setTimeout(r, 1100)); // 1 call per second
    const locations = points.slice(i, i + 100).map(([a, b]) => `${a.toFixed(5)},${b.toFixed(5)}`).join("|");
    const json = await fetchJSON(`https://api.opentopodata.org/v1/eudem25m?locations=${locations}`, { timeout: 15000, retries: 1 });
    if (json.status !== "OK") throw new Error(json.error || "OpenTopoData");
    values.push(...json.results.map((r) => (typeof r.elevation === "number" ? r.elevation : null)));
  }
  const observer = values[0] ?? 0;
  const grid = AZIMUTHS.map((_, i) => values.slice(1 + i * DISTANCES_KM.length, 1 + (i + 1) * DISTANCES_KM.length).map((v) => (v == null ? null : v)));
  return { lat, lon, elevation: Math.round(observer), dataset: "EU-DEM v1.1 25 m (Copernicus) via OpenTopoData", profile: profile(observer, grid) };
}
