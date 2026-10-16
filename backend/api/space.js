// GET /api/space -> NASA DONKI (CCMC, Goddard) digest for the aurora forecast:
//   storms:   geomagnetic storms of the last 30 days with their observed Kp
//   arrivals: CMEs heading for Earth from the WSA-ENLIL model, with predicted
//             shock arrival time and the Kp range NASA expects
//   flares:   M/X flares of the last 3 days
// Cached on Vercel's CDN for 30 minutes so all devices share one NASA request.
// The last complete answer is kept in Blob and served (stale: true) when DONKI is down.
import { send, readObject, writeObject } from "../lib/core.js";

const HOSTS = [
  "https://kauai.ccmc.gsfc.nasa.gov/DONKI/WS/get/",
  "https://webtools.ccmc.gsfc.nasa.gov/DONKI/WS/get/",
];
const GATEWAY = "https://api.nasa.gov/DONKI/";
const CACHE = "public/donki.bin";

const day = (offset) => new Date(Date.now() + offset * 864e5).toISOString().slice(0, 10);

async function donki(path, query) {
  const qs = new URLSearchParams(query).toString();
  const attempts = [
    ...HOSTS.map((h) => `${h}${path}?${qs}`),
    `${GATEWAY}${path}?${qs}&api_key=${process.env.NASA_API_KEY || "DEMO_KEY"}`,
  ];
  let lastError;
  for (const url of attempts) {
    try {
      const response = await fetch(url, {
        headers: { "User-Agent": "nordur-api (github.com/lorenzosavini/nordur-ios)", Accept: "application/json" },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error(`${new URL(url).host} ${response.status}`);
      const text = await response.text();
      return text.trim() ? JSON.parse(text) : [];
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError;
}

const kpRange = (s) => {
  const values = [s.kp_18, s.kp_90, s.kp_135, s.kp_180].filter((v) => typeof v === "number");
  return values.length ? { min: Math.min(...values), max: Math.max(...values) } : null;
};

function digest(gst, enlil, flr) {
  const storms = (gst || []).map((s) => ({
    id: s.gstID,
    start: s.startTime,
    maxKp: Math.max(0, ...(s.allKpIndex || []).map((k) => k.kpIndex || 0)),
    kp: (s.allKpIndex || []).map((k) => ({ time: k.observedTime, kp: k.kpIndex, source: k.source || null })),
    link: s.link || null,
  }));

  // One entry per CME: the most recent model run wins.
  const byCME = new Map();
  for (const sim of enlil || []) {
    const inputs = sim.cmeInputs || [];
    const cme = inputs.find((c) => c.isMostAccurate) || inputs[0];
    const earthImpact = (sim.impactList || []).find((i) => /earth/i.test(i.location || ""));
    const arrival = sim.estimatedShockArrivalTime || earthImpact?.arrivalTime || null;
    if (!arrival) continue;
    const entry = {
      id: cme?.cmeid || sim.simulationID,
      launched: cme?.cmeStartTime || null,
      speed: cme?.speed ?? null,
      halfAngle: cme?.halfAngle ?? null,
      arrival,
      durationHours: sim.estimatedDuration ?? null,
      glancing: Boolean(sim.isEarthGB || earthImpact?.isGlancingBlow),
      kp: kpRange(sim),
      modelRun: sim.modelCompletionTime || null,
      link: sim.link || null,
    };
    const previous = byCME.get(entry.id);
    if (!previous || (entry.modelRun || "") > (previous.modelRun || "")) byCME.set(entry.id, entry);
  }
  const arrivals = [...byCME.values()]
    .filter((a) => Date.parse(a.arrival) > Date.now() - 2 * 864e5)
    .sort((a, b) => Date.parse(a.arrival) - Date.parse(b.arrival));

  const flares = (flr || [])
    .filter((f) => /^[MX]/.test(f.classType || ""))
    .map((f) => ({ id: f.flrID, peak: f.peakTime, classType: f.classType, region: f.activeRegionNum ?? null }));

  return { storms, arrivals, flares };
}

export default async function handler(req, res) {
  const results = await Promise.allSettled([
    donki("GST", { startDate: day(-30), endDate: day(0) }),
    donki("WSAEnlilSimulations", { startDate: day(-10), endDate: day(0) }),
    donki("FLR", { startDate: day(-3), endDate: day(0) }),
  ]);
  const [gst, enlil, flr] = results.map((r) => (r.status === "fulfilled" && Array.isArray(r.value) ? r.value : null));
  const errors = results.filter((r) => r.status === "rejected").map((r) => String(r.reason?.cause?.code || r.reason?.message || r.reason));
  const complete = [gst, enlil, flr].every((v) => v !== null);

  if (complete) {
    const body = { source: "NASA CCMC DONKI", generated: new Date().toISOString(), stale: false, ...digest(gst, enlil, flr) };
    try { await writeObject(CACHE, body); } catch (e) { console.error("cache write", e); }
    res.setHeader("Cache-Control", "public, s-maxage=1800, stale-while-revalidate=3600");
    return send(res, 200, body);
  }

  console.error("DONKI unavailable", errors);
  let cached = null;
  try { cached = await readObject(CACHE); } catch (e) { console.error("cache read", e); }
  res.setHeader("Cache-Control", "public, s-maxage=300");
  if (cached) return send(res, 200, { ...cached, stale: true, errors });
  return send(res, 503, { source: "NASA CCMC DONKI", generated: null, stale: true, errors, storms: [], arrivals: [], flares: [] });
}
