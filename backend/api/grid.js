// GET /api/grid -> 48-hour forecast on the Iceland map grid (13 x 20 points,
// 0.3° x 0.6°): temperature, precipitation, snow, cloud, wind, gusts, direction.
//
// Open-Meteo counts every point of a multi-location request as one call and
// limits calls per IP, so 260 points per map refresh exhaust it quickly on
// shared networks (hotel Wi-Fi, carrier NAT, emulators). Here it is fetched
// once per hour for everyone and cached on the CDN; the last good grid is kept
// in Blob for when Open-Meteo is unavailable.
//
// The body is the array of Open-Meteo forecasts, in the app's point order
// (latitude-major), so the app decodes it exactly like a direct response.
import { fetchJSON } from "../lib/fetch.js";
import { send, readObject, writeObject } from "../lib/core.js";

// Same grid as WeatherGrid / WeatherGridService in the app.
const SOUTH = 63.1, NORTH = 66.8, WEST = -24.7, EAST = -13.3, LAT_STEP = 0.3, LON_STEP = 0.6;
const HOURLY = "temperature_2m,precipitation,snowfall,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m";
const TTL = 60 * 60e3;
const CACHE = "public/grid.bin";

let memory = null; // { at, body }

function steps(from, to, step) {
  const out = [];
  for (let i = 0; from + i * step <= to + 0.001; i++) out.push(from + i * step);
  return out;
}

export function gridPoints() {
  const points = [];
  for (const lat of steps(SOUTH, NORTH, LAT_STEP)) for (const lon of steps(WEST, EAST, LON_STEP)) points.push([lat, lon]);
  return points;
}

async function fetchGrid() {
  const points = gridPoints();
  const forecasts = [];
  for (let start = 0; start < points.length; start += 100) {
    const chunk = points.slice(start, start + 100);
    const qs = new URLSearchParams({
      latitude: chunk.map(([lat]) => lat.toFixed(2)).join(","),
      longitude: chunk.map(([, lon]) => lon.toFixed(2)).join(","),
      hourly: HOURLY,
      wind_speed_unit: "ms",
      forecast_hours: "48",
      timeformat: "unixtime",
      timezone: "GMT",
    });
    const data = await fetchJSON(`https://api.open-meteo.com/v1/forecast?${qs}`, { timeout: 20000, retries: 1 });
    forecasts.push(...(Array.isArray(data) ? data : [data]));
  }
  if (forecasts.length !== points.length) throw new Error(`Open-Meteo: ${forecasts.length} punti su ${points.length}`);
  return forecasts;
}

export default async function handler(req, res) {
  if (!memory || Date.now() - memory.at > TTL) {
    try {
      memory = { at: Date.now(), body: await fetchGrid() };
      await writeObject(CACHE, memory, { ttl: 2 * 86400 }).catch((e) => console.error("grid cache", e.message));
    } catch (e) {
      console.error("grid", e.message);
      const stored = memory || (await readObject(CACHE).catch(() => null));
      if (!stored) return send(res, 502, { error: "Open-Meteo non raggiungibile" });
      memory = stored;
      // Serve the last good grid, but let the CDN retry soon.
      res.setHeader("Cache-Control", "public, s-maxage=300");
      res.setHeader("X-Grid-Generated", new Date(memory.at).toISOString());
      return send(res, 200, memory.body);
    }
  }
  res.setHeader("Cache-Control", "public, s-maxage=3600, stale-while-revalidate=1800");
  res.setHeader("X-Grid-Generated", new Date(memory.at).toISOString());
  return send(res, 200, memory.body);
}
