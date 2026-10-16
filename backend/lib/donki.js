// NASA CCMC DONKI: geomagnetic storms, WSA-ENLIL CME simulations, flares.
// CCMC moved the DONKI API on 2026-09-30: the old kauai/webtools hosts now
// answer with an HTML announcement. Hosts are tried in order; the last
// complete digest is kept in Blob and served as stale when DONKI is down
// (it is written only when its content changes).
import crypto from "node:crypto";
import { fetchJSON, utc, iso } from "./fetch.js";
import { readObject, writeObject } from "./core.js";

const HOSTS = ["https://ccmc.gsfc.nasa.gov/DONKI-API/get/"];
const GATEWAY = "https://api.nasa.gov/DONKI/";
const CACHE = "public/donki.bin";
const MAX_AGE = 30 * 60e3;

let memory = null; // { digest, fetchedAt }

const day = (offset) => new Date(Date.now() + offset * 864e5).toISOString().slice(0, 10);

async function donki(path, query) {
  const qs = new URLSearchParams(query).toString();
  const urls = [...HOSTS.map((h) => `${h}${path}?${qs}`), `${GATEWAY}${path}?${qs}&api_key=${process.env.NASA_API_KEY || "DEMO_KEY"}`];
  let last;
  for (const url of urls) {
    try {
      const data = await fetchJSON(url, { timeout: 9000, retries: 0 });
      return Array.isArray(data) ? data : [];
    } catch (e) {
      last = e;
    }
  }
  throw last;
}

const kpRange = (s) => {
  const values = [s.kp_18, s.kp_90, s.kp_135, s.kp_180].filter((v) => typeof v === "number");
  return values.length ? { min: Math.min(...values), max: Math.max(...values) } : null;
};

export function digest(gst, enlil, flr, now = Date.now()) {
  const storms = gst.map((s) => ({
    id: s.gstID,
    start: iso(utc(s.startTime)),
    maxKp: Math.max(0, ...(s.allKpIndex || []).map((k) => k.kpIndex || 0)),
    kp: (s.allKpIndex || []).map((k) => ({ time: iso(utc(k.observedTime)), kp: k.kpIndex, source: k.source || null })),
    link: s.link || null,
  }));

  const byCME = new Map();
  for (const sim of enlil) {
    const inputs = sim.cmeInputs || [];
    const cme = inputs.find((c) => c.isMostAccurate) || inputs[0];
    const earthImpact = (sim.impactList || []).find((i) => /earth/i.test(i.location || ""));
    const arrival = utc(sim.estimatedShockArrivalTime || earthImpact?.arrivalTime);
    if (!arrival) continue;
    const entry = {
      id: cme?.cmeid || sim.simulationID,
      launched: iso(utc(cme?.cmeStartTime)),
      speed: cme?.speed ?? null,
      halfAngle: cme?.halfAngle ?? null,
      latitude: cme?.latitude ?? null,
      longitude: cme?.longitude ?? null,
      arrival: iso(arrival),
      // CCMC quotes about ±7 h (1σ ~10 h) for ENLIL shock arrival times.
      arrivalUncertaintyHours: 7,
      durationHours: sim.estimatedDuration ?? null,
      glancing: Boolean(sim.isEarthGB || earthImpact?.isGlancingBlow),
      kp: kpRange(sim),
      modelRun: iso(utc(sim.modelCompletionTime)),
      link: sim.link || null,
    };
    const previous = byCME.get(entry.id);
    if (!previous || (entry.modelRun || "") > (previous.modelRun || "")) byCME.set(entry.id, entry);
  }
  const arrivals = [...byCME.values()]
    .filter((a) => Date.parse(a.arrival) > now - 2 * 864e5)
    .sort((a, b) => Date.parse(a.arrival) - Date.parse(b.arrival));

  const flares = flr
    .filter((f) => /^[MX]/.test(f.classType || ""))
    .map((f) => ({ id: f.flrID, peak: iso(utc(f.peakTime)), classType: f.classType, region: f.activeRegionNum ?? null }));

  return { storms, arrivals, flares };
}

/** Returns { digest, fetchedAt, stale, errors } — digest null if never available. */
export async function loadDonki({ force = false } = {}) {
  if (!force && memory && Date.now() - memory.fetchedAt < MAX_AGE) return { ...memory, stale: false, errors: [] };
  const results = await Promise.allSettled([
    donki("GST", { startDate: day(-30), endDate: day(0) }),
    donki("WSAEnlilSimulations", { startDate: day(-10), endDate: day(0) }),
    donki("FLR", { startDate: day(-3), endDate: day(0) }),
  ]);
  const errors = results.filter((r) => r.status === "rejected").map((r) => String(r.reason?.message || r.reason));
  if (!errors.length) {
    const [gst, enlil, flr] = results.map((r) => r.value);
    const fresh = { digest: digest(gst, enlil, flr), fetchedAt: Date.now() };
    memory = fresh;
    try {
      const stored = await readObject(CACHE).catch(() => null);
      const hash = (x) => crypto.createHash("sha1").update(JSON.stringify(x)).digest("hex");
      if (!stored || hash(stored.digest) !== hash(fresh.digest)) await writeObject(CACHE, fresh);
    } catch (e) {
      console.error("donki cache", e.message);
    }
    return { ...fresh, stale: false, errors };
  }
  const cached = memory || (await readObject(CACHE).catch(() => null));
  return cached ? { ...cached, stale: true, errors } : { digest: null, fetchedAt: null, stale: true, errors };
}
