// GET /api/sites -> hourly sky forecast (cloud layers, fog) for the reference
// observing sites in Iceland, from MET Norway Locationforecast 2.0 (MEPS 2.5 km,
// run with the Icelandic Met Office). One server-side fetch per site every
// 30 minutes, whatever the number of users, as MET's terms ask.
// The app combines it with the aurora state to rank the sites.
import { fetchJSON, utc } from "../lib/fetch.js";
import { send } from "../lib/core.js";
import { SITES } from "../lib/archive.js";

const NAMES = {
  reykjavik: "Reykjavík", keflavik: "Keflavík", vik: "Vík í Mýrdal", skogar: "Skógar", hofn: "Höfn", jokulsarlon: "Jökulsárlón",
  akureyri: "Akureyri", myvatn: "Mývatn", egilsstadir: "Egilsstaðir", isafjordur: "Ísafjörður", grundarfjordur: "Grundarfjörður", husavik: "Húsavík",
};
const TTL = 30 * 60e3;
let memory = null;

async function site([id, lat, lon]) {
  const url = `https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=${lat.toFixed(4)}&lon=${lon.toFixed(4)}`;
  const json = await fetchJSON(url, { timeout: 12000, retries: 1 });
  const horizon = Date.now() + 72 * 3600e3;
  const hours = (json.properties?.timeseries || [])
    .map((e) => ({ t: utc(e.time), d: e.data?.instant?.details || {}, step: e.data?.next_1_hours ? 1 : 6 }))
    .filter((e) => e.t && e.t <= horizon)
    .map((e) => ({
      t: new Date(e.t).toISOString(), step: e.step,
      total: e.d.cloud_area_fraction ?? null, low: e.d.cloud_area_fraction_low ?? null,
      mid: e.d.cloud_area_fraction_medium ?? null, high: e.d.cloud_area_fraction_high ?? null, fog: e.d.fog_area_fraction ?? null,
    }));
  return { id, name: NAMES[id] || id, lat, lon, modelUpdated: json.properties?.meta?.updated_at || null, hours };
}

export default async function handler(req, res) {
  if (!memory || Date.now() - memory.at > TTL) {
    const results = await Promise.allSettled(SITES.map(site));
    const sites = results.filter((r) => r.status === "fulfilled").map((r) => r.value);
    const errors = results.filter((r) => r.status === "rejected").map((r) => String(r.reason?.message || r.reason));
    if (sites.length) memory = { at: Date.now(), body: { generated: new Date().toISOString(), provider: "MET Norway Locationforecast 2.0", sites, errors } };
    else if (!memory) return send(res, 502, { error: "MET Norway non raggiungibile", errors });
  }
  res.setHeader("Cache-Control", "public, s-maxage=1800, stale-while-revalidate=3600");
  return send(res, 200, memory.body);
}
