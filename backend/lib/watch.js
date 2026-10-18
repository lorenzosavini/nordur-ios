// The current conditions for the Garmin watch app, computed as the iPhone app
// does (MET Norway for the instant values, Open-Meteo for gusts and as
// fallback), with the place name and the aurora (Kp) in a few hundred bytes.
import { readObject, writeObject } from "./core.js";

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

export async function watchConditions(lat, lon, lang = "it", now = Date.now()) {
  const la = Math.round(lat * 1e4) / 1e4, lo = Math.round(lon * 1e4) / 1e4;
  const [met, om, aurora, place] = await Promise.all([
    json(`https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=${la}&lon=${lo}`).catch(() => null),
    json(`https://api.open-meteo.com/v1/forecast?latitude=${la}&longitude=${lo}&current=temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,weather_code,is_day&wind_speed_unit=ms&timeformat=unixtime`).catch(() => null),
    json("https://nordur-api.vercel.app/api/aurora?compact=1", 10000).catch(() => null),
    placeName(la, lo, lang).catch(() => null),
  ]);
  const o = om?.current || {};
  const step = met?.properties?.timeseries?.find((t) => Date.parse(t.time) + 3600e3 > now);
  const d = step?.data?.instant?.details || {};
  const symbol = step?.data?.next_1_hours?.summary?.symbol_code || "";
  const round = (v, n = 1) => (typeof v === "number" ? Math.round(v * 10 ** n) / 10 ** n : null);
  const wind = d.wind_speed ?? o.wind_speed_10m;
  if (wind == null) throw new Error("no weather");
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
    kp: aurora?.kp ?? null,
    kpMax: aurora?.kpMax24 ?? null,
    g: aurora?.g ?? null,
    src: [step ? "MET Norway" : null, om ? "Open-Meteo" : null].filter(Boolean).join(" + "),
  };
}
