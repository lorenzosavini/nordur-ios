// GET /api/grid?v=2 -> the map grid corrected with Veðurstofa Íslands (lib/blend.js):
//   { version, generated, base, imo: { issued, measured, stations }, forecasts, stations }
// GET /api/live -> what IMO published last (stamps), checked at most once a minute.
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
import { STATIONS, fetchStamps, fetchAllForecasts, fetchAllAWS, imoTime } from "../lib/imo.js";

const iso = (seconds) => (Number.isFinite(seconds) ? new Date(seconds * 1000).toISOString() : null);
import { correctGrid } from "../lib/blend.js";

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

/** The Open-Meteo grid, refreshed hourly (its models update about once an hour). */
async function baseGrid() {
  // Refreshed at each new hour (Open-Meteo's models update about hourly): every server
  // instance then agrees on the grid's version, which is named after that hour.
  if (!memory || Date.now() - memory.at > TTL || hourOf(memory.at) !== hourOf(Date.now())) {
    try {
      memory = { at: Date.now(), body: await fetchGrid() };
      await writeObject(CACHE, memory, { ttl: 2 * 86400 }).catch((e) => console.error("grid cache", e.message));
    } catch (e) {
      console.error("grid", e.message);
      const stored = memory || (await readObject(CACHE).catch(() => null));
      if (!stored) throw new Error("Open-Meteo non raggiungibile");
      memory = { ...stored, failed: true };
    }
  }
  return memory;
}

// MARK: What IMO published last, and the grid corrected with it (lib/blend.js)

const STAMPS_TTL = 60e3;
const IMO_CACHE = "public/imo-forecasts.bin";
let stamps = null;     // { at, value }
let imoForecasts = null; // { issued, map }
let measurements = null; // { stamp, map }
let corrected = null;  // { version, body }

async function liveStamps() {
  if (stamps && Date.now() - stamps.at < STAMPS_TTL) return stamps.value;
  const value = await fetchStamps().catch(() => ({}));
  // A part that failed keeps its last known value.
  const merged = Object.fromEntries(["forecast", "obsHour", "obs10", "texts"].map((k) => [k, value[k] ?? stamps?.value?.[k] ?? null]));
  stamps = { at: Date.now(), value: merged };
  return merged;
}

const hourOf = (ms) => Math.floor(ms / 3600e3);
// Same on every instance: the model's hour, IMO's issue time, the latest measurement.
const gridVersion = (hour, issued, measured) => `${hour}.${issued || "-"}.${measured || "-"}`.replace(/[^0-9A-Za-z.-]/g, "");

async function correctedGrid() {
  const base = await baseGrid();
  const st = await liveStamps();
  if (st.forecast && imoForecasts?.issued !== st.forecast) {
    const stored = await readObject(IMO_CACHE).catch(() => null);
    if (stored?.issued === st.forecast) {
      imoForecasts = { issued: stored.issued, map: new Map(stored.list.map((f) => [f.id, f])) };
    } else {
      try {
        const map = await fetchAllForecasts();
        if (map.size) {
          imoForecasts = { issued: st.forecast, map };
          await writeObject(IMO_CACHE, { issued: st.forecast, list: [...map.values()] }, { ttl: 2 * 86400 }).catch(() => {});
        }
      } catch (e) { console.error("imo forecasts", e.message); }
    }
  }
  if (st.obs10 && measurements?.stamp !== st.obs10) {
    try { measurements = { stamp: st.obs10, map: await fetchAllAWS() }; } catch (e) { console.error("imo aws", e.message); }
  }
  // A stored copy (Open-Meteo down) keeps its own hour.
  const version = gridVersion(hourOf(base.failed ? base.at : Date.now()), imoForecasts?.issued, measurements?.stamp);
  if (corrected?.version === version) return corrected;
  const lats = steps(SOUTH, NORTH, LAT_STEP), lons = steps(WEST, EAST, LON_STEP);
  const r = correctGrid(base.body, lats, lons, STATIONS, imoForecasts?.map || new Map(), measurements?.map || new Map(), Math.round(Date.now() / 1000));
  corrected = { version, body: {
    version,
    generated: new Date().toISOString(),
    base: new Date(base.at).toISOString(),
    imo: { issued: iso(imoTime(imoForecasts?.issued)), measured: iso(measurements?.stamp ? Date.parse(measurements.stamp.slice(0, 19) + "Z") / 1000 : null), stations: r.used },
    forecasts: r.forecasts,
    stations: r.stations,
    coverage: r.coverage,
  } };
  return corrected;
}

export default async function handler(req, res) {
  const params = new URL(req.url, "http://x").searchParams;
  // /api/live: what IMO published last; the app fetches again only what changed.
  if (params.get("live")) {
    const st = await liveStamps();
    res.setHeader("Cache-Control", "public, s-maxage=60, stale-while-revalidate=60");
    return send(res, 200, { ...st, grid: gridVersion(hourOf(Date.now()), st.forecast, st.obs10), checked: new Date(stamps.at).toISOString() });
  }
  let grid;
  try {
    grid = await correctedGrid();
  } catch (e) {
    return send(res, 502, { error: e.message });
  }
  res.setHeader("X-Grid-Generated", new Date(memory.at).toISOString());
  // A request naming its version gets a URL of its own: it can stay on the CDN.
  res.setHeader("Cache-Control", memory.failed ? "public, s-maxage=120" : params.get("ver") ? "public, s-maxage=900" : "public, s-maxage=60, stale-while-revalidate=60");
  // v=2: the corrected grid with its sources and the IMO station values; older apps get the bare array.
  return send(res, 200, params.get("v") === "2" ? grid.body : grid.body.forecasts);
}
