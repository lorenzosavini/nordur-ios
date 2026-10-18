// The current conditions for the Garmin watch app, computed as the iPhone app
// does (MET Norway for the instant values, Open-Meteo for gusts and as
// fallback), with the place name and the aurora (Kp) in a few hundred bytes.
import { readObject, writeObject } from "./core.js";
import { ovationAt } from "./sources.js";

const UA = "nordur-api/1.0 (github.com/lorenzosavini/nordur-ios)";
const places = new Map();

async function json(url, timeout = 8000) {
  const res = await fetch(url, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(timeout) });
  if (!res.ok) throw new Error(`${new URL(url).host} ${res.status}`);
  return res.json();
}

/** Name of the place (town or village), from OpenStreetMap; cached for 30 days. */
async function placeName(lat, lon, lang) {
  const key = `${lang}:${lat.toFixed(2)},${lon.toFixed(2)}`;
  if (places.has(key)) return places.get(key);
  const path = `places/${key.replace(/[^a-z0-9.,-]/gi, "_")}.bin`;
  let name = (await readObject(path).catch(() => null))?.name;
  if (!name) {
    const r = await json(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=12&accept-language=${lang}&lat=${lat}&lon=${lon}`).catch(() => null);
    const a = r?.address || {};
    name = a.city || a.town || a.village || a.hamlet || a.municipality || a.county || r?.name || null;
    if (name) await writeObject(path, { name }, { ttl: 30 * 86400 }).catch(() => {});
  }
  places.set(key, name);
  if (places.size > 5000) places.clear();
  return name;
}

const SKY = [
  [/thunder/, "storm"], [/snow|sleet/, "snow"], [/rain|showers/, "rain"], [/fog/, "fog"],
  [/clearsky|fair/, "clear"], [/partlycloudy/, "partly"], [/cloudy/, "cloudy"],
];

function skyFromWmo(code) {
  if (code == null) return null;
  if (code >= 95) return "storm";
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow";
  if (code >= 51) return "rain";
  if (code === 45 || code === 48) return "fog";
  if (code <= 1) return "clear";
  if (code === 2) return "partly";
  return "cloudy";
}

/** Sun altitude in degrees (NOAA solar position, accurate to a fraction of a degree). */
export function sunAltitude(lat, lon, now = Date.now()) {
  const rad = Math.PI / 180;
  const d = now / 864e5 + 2440587.5 - 2451545.0;
  const g = (357.529 + 0.98560028 * d) * rad;
  const q = 280.459 + 0.98564736 * d;
  const L = (q + 1.915 * Math.sin(g) + 0.02 * Math.sin(2 * g)) * rad;
  const e = (23.439 - 0.00000036 * d) * rad;
  const ra = Math.atan2(Math.cos(e) * Math.sin(L), Math.cos(L));
  const dec = Math.asin(Math.sin(e) * Math.sin(L));
  const gmst = (18.697374558 + 24.06570982441908 * d) % 24;
  const ha = (gmst * 15 + lon) * rad - ra;
  return Math.asin(Math.sin(lat * rad) * Math.sin(dec) + Math.cos(lat * rad) * Math.cos(dec) * Math.cos(ha)) / rad;
}

/**
 * The aurora at one place: OVATION probability overhead and toward the
 * northern horizon (up to ~8° of latitude away, as the aurora is seen low in
 * the sky from farther south), boosted by what the ground magnetometer and Bz
 * say now; then darkness and clouds decide whether it can be seen.
 *   level 0 none · 1 weak · 2 possible · 3 likely · 4 strong
 */
export function auroraHere(state, lat, lon, clouds, now = Date.now()) {
  const o = state?.ovation;
  const overhead = o ? ovationAt(o, lat, lon) ?? 0 : 0;
  let horizon = 0;
  if (o) {
    for (let dl = 1; dl <= 8; dl++) {
      for (let dx = -4; dx <= 4; dx++) {
        const v = ovationAt(o, lat + dl, lon + dx) ?? 0;
        horizon = Math.max(horizon, v * (1 - dl / 10));
      }
    }
  }
  const activity = Math.max(overhead, horizon * 0.6);
  let level = activity >= 50 ? 4 : activity >= 25 ? 3 : activity >= 10 ? 2 : activity >= 3 ? 1 : 0;
  const bz = state?.solarWind?.averages?.["15"]?.bz ?? state?.solarWind?.latest?.bz;
  const mag = state?.magnetometer?.level ?? 0;
  if (level >= 1 && (mag >= 2 || (bz != null && bz <= -8))) level = Math.min(4, level + 1);
  const sun = sunAltitude(lat, lon, now);
  const dark = sun < -10;
  const cloudy = clouds != null && clouds >= 75;
  return {
    level,
    overhead: Math.round(overhead),
    horizon: Math.round(horizon),
    sun: Math.round(sun),
    dark,
    clouds: clouds ?? null,
    visible: level >= 2 && dark && !cloudy,
  };
}

export async function watchConditions(lat, lon, lang = "it", now = Date.now()) {
  const la = Math.round(lat * 1e4) / 1e4, lo = Math.round(lon * 1e4) / 1e4;
  const [met, om, aurora, place] = await Promise.all([
    json(`https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=${la}&lon=${lo}`).catch(() => null),
    json(`https://api.open-meteo.com/v1/forecast?latitude=${la}&longitude=${lo}&current=temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,weather_code,is_day,cloud_cover&wind_speed_unit=ms&timeformat=unixtime`).catch(() => null),
    // The full state (cached by the CDN for a minute): OVATION grid, Kp blocks, solar wind.
    json("https://nordur-api.vercel.app/api/aurora", 15000).catch(() => null),
    placeName(la, lo, lang).catch(() => null),
  ]);
  const o = om?.current || {};
  const step = met?.properties?.timeseries?.find((t) => Date.parse(t.time) + 3600e3 > now);
  const d = step?.data?.instant?.details || {};
  const symbol = step?.data?.next_1_hours?.summary?.symbol_code || "";
  const round = (v, n = 1) => (typeof v === "number" ? Math.round(v * 10 ** n) / 10 ** n : null);
  const wind = d.wind_speed ?? o.wind_speed_10m;
  if (wind == null) throw new Error("no weather");
  const blocks = aurora?.kp?.blocks || [];
  const currentIndex = blocks.findLastIndex((b) => Date.parse(b.t) <= now);
  const current = blocks[currentIndex];
  const next = blocks.slice(Math.max(0, currentIndex), Math.max(0, currentIndex) + 8);
  const sw = aurora?.solarWind;
  const clouds = d.cloud_area_fraction ?? o.cloud_cover ?? null;
  return {
    place,
    lat: round(la, 3), lon: round(lo, 3),
    t: Math.round(now / 1000),
    temp: round(d.air_temperature ?? o.temperature_2m),
    wind: round(wind),
    // Same rule as the app: the gust is never below the mean wind.
    gust: round(Math.max(o.wind_gusts_10m ?? 0, wind)),
    dir: round(d.wind_from_direction ?? o.wind_direction_10m, 0),
    sky: SKY.find(([re]) => re.test(symbol))?.[1] || skyFromWmo(o.weather_code),
    day: o.is_day ?? null,
    clouds: round(clouds, 0),
    // Space weather, each signal on its own.
    kp: round(current?.value),
    kpMax: round(next.slice(0, 8).reduce((m, b) => Math.max(m, b.value ?? 0), 0)),
    kp24: next.map((b) => round(b.value)),
    kpStart: next[0] ? Math.round(Date.parse(next[0].t) / 1000) : null,
    hp30: round(aurora?.hp30?.at(-1)?.hp30),
    bz: round(sw?.averages?.["5"]?.bz ?? sw?.latest?.bz),
    speed: round(sw?.averages?.["15"]?.v ?? sw?.latest?.v, 0),
    arrival: sw?.propagation?.minutes ?? null,
    mag: aurora?.magnetometer?.level ?? null,
    magNt: aurora?.magnetometer?.rangeNt ?? null,
    g: (aurora?.scales || []).filter((x) => x.index > 0).reduce((m, x) => Math.max(m, x.g || 0), 0),
    // The aurora where you are.
    aurora: aurora ? auroraHere(aurora, la, lo, clouds, now) : null,
    src: [step ? "MET Norway" : null, om ? "Open-Meteo" : null].filter(Boolean).join(" + "),
  };
}
