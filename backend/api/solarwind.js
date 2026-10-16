// GET /api/solarwind -> last 3 hours of real-time solar wind at L1 (NOAA SWPC RTSW,
// operational spacecraft only: DSCOVR/ACE/IMAP), 1-minute samples, compact.
//   { source, spacecraft, mag: [[t, bt, by, bz]], plasma: [[t, speed, density]] }
// The raw NOAA files are ~2 MB each; this is a few kB. CDN cache: 60 s.
import { send } from "../lib/core.js";

const BASE = "https://services.swpc.noaa.gov/json/rtsw/";

async function load(name) {
  const response = await fetch(BASE + name, {
    headers: { "User-Agent": "nordur-api (github.com/lorenzosavini/nordur-ios)" },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`${name} ${response.status}`);
  return response.json();
}

const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : null);

export default async function handler(req, res) {
  try {
    const [mag, wind] = await Promise.all([load("rtsw_mag_1m.json"), load("rtsw_wind_1m.json")]);
    const cutoff = Date.now() - 3 * 3600e3;
    const time = (s) => Date.parse(s.endsWith("Z") ? s : s + "Z");

    const magRows = mag
      .filter((r) => r.active && time(r.time_tag) >= cutoff)
      .map((r) => [Math.round(time(r.time_tag) / 1000), num(r.bt), num(r.by_gsm), num(r.bz_gsm)])
      .filter((r) => r[3] !== null)
      .sort((a, b) => a[0] - b[0]);
    const plasmaRows = wind
      .filter((r) => r.active && time(r.time_tag) >= cutoff)
      .map((r) => [Math.round(time(r.time_tag) / 1000), num(r.proton_speed), num(r.proton_density)])
      .filter((r) => r[1] !== null)
      .sort((a, b) => a[0] - b[0]);
    const spacecraft = (mag.find((r) => r.active) || {}).source || null;

    res.setHeader("Cache-Control", "public, s-maxage=60, stale-while-revalidate=300");
    return send(res, 200, { source: "NOAA SWPC RTSW", spacecraft, mag: magRows, plasma: plasmaRows });
  } catch (e) {
    console.error(e);
    return send(res, 502, { error: "NOAA RTSW non raggiungibile" });
  }
}
