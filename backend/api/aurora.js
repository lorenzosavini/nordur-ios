// GET /api/aurora -> validated, normalised space-weather state for the app.
//
// One request here replaces ~15 requests (and ~6 MB) per device: the result is
// cached on Vercel's CDN for 60 s, so NOAA/GFZ/NASA see one request per minute
// at most, whatever the number of users.
//
// Each source carries provenance (provider, endpoint, observed/valid times)
// and a status: ok, stale (too old to be shown as live) or error.
// A snapshot is archived once per 3-hour Kp block for backtesting.
import * as S from "../lib/sources.js";
import { loadDonki } from "../lib/donki.js";
import { blend } from "../lib/kp.js";
import { send } from "../lib/core.js";
import { archiveSnapshot } from "../lib/archive.js";
import { watchConditions } from "../lib/watch.js";

// Maximum age before a "live" source is flagged stale (minutes).
const LIVE_LIMITS = { solarWind: 15, kpEstimated: 20, ovation: 25, hemisphericPower: 25, magnetometer: 45, hp30: 120 };

// No source may hold the whole answer: past 9 s it counts as not answering.
const SOURCE_BUDGET_MS = 9000;

async function settle(name, loader) {
  try {
    const r = await Promise.race([
      loader(),
      new Promise((_, reject) => setTimeout(() => reject(new Error(`timeout ${SOURCE_BUDGET_MS / 1000} s`)), SOURCE_BUDGET_MS)),
    ]);
    return [name, { status: "ok", ...r }];
  } catch (e) {
    console.error(name, e.message);
    return [name, { status: "error", error: String(e.message || e), data: null, meta: null }];
  }
}

function ageMinutes(isoTime, now) {
  const t = Date.parse(isoTime || "");
  return Number.isFinite(t) ? (now - t) / 60e3 : null;
}

export async function buildState(now = Date.now()) {
  const entries = await Promise.all([
    settle("kpForecast", S.kpForecast),
    settle("kpEstimated", S.kpEstimated),
    settle("kpGFZ", S.kpGFZ),
    settle("solarWind", S.solarWind),
    settle("ovation", S.ovation),
    settle("enlil", S.enlil),
    settle("scales", S.scales),
    settle("alerts", S.alerts),
    settle("hemisphericPower", S.hemisphericPower),
    settle("hp30", S.hp30),
    settle("magnetometer", () => S.magnetometer(now)),
    settle("outlook27", S.outlook27),
    settle("forecast45", S.forecast45),
    settle("donki", async () => {
      const d = await loadDonki();
      if (!d.digest) throw new Error(d.errors.join("; ") || "DONKI non disponibile");
      return { data: d.digest, meta: { provider: "NASA CCMC DONKI", endpoint: "https://ccmc.gsfc.nasa.gov/DONKI-API/get/", fetchedAt: new Date(d.fetchedAt).toISOString(), cachedCopy: d.stale, errors: d.errors } };
    }),
  ]);
  const src = Object.fromEntries(entries);

  // Freshness: a source that answered but carries old data is "stale".
  const observedAt = {
    solarWind: src.solarWind.meta?.observedAt,
    kpEstimated: src.kpEstimated.meta?.observedAt,
    ovation: src.ovation.meta?.observedAt,
    hemisphericPower: src.hemisphericPower.meta?.observedAt,
    magnetometer: src.magnetometer.meta?.observedAt,
    hp30: src.hp30.meta?.observedAt,
  };
  for (const [name, limit] of Object.entries(LIVE_LIMITS)) {
    const age = ageMinutes(observedAt[name], now);
    if (src[name].status === "ok" && (age == null || age > limit)) src[name].status = "stale";
    if (src[name].meta) src[name].meta.ageMinutes = age == null ? null : Math.round(age);
  }
  if (src.donki.meta?.cachedCopy) src.donki.status = "stale";

  const usable = (name) => (src[name].status === "ok" ? src[name].data : null);
  const kpBlocks = src.kpForecast.data
    ? blend({
        forecast: src.kpForecast.data,
        estimated: usable("kpEstimated"),
        gfz: src.kpGFZ.data,
        newellKp: usable("solarWind")?.newellKp ?? null,
        donki: src.donki.data,
        enlil: src.enlil.data,
        now,
      })
    : [];

  const sources = Object.fromEntries(Object.entries(src).map(([k, v]) => [k, { status: v.status, error: v.error || null, ...(v.meta || {}) }]));
  const est = src.kpEstimated.data || [];
  return {
    generated: new Date(now).toISOString(),
    sources,
    kp: {
      blocks: kpBlocks,
      estimated: est.length ? { t: new Date(est.at(-1).t).toISOString(), kp: est.at(-1).kp, series: est.filter((_, i) => i % 10 === 0).slice(-18).map((r) => ({ t: new Date(r.t).toISOString(), kp: r.kp })) } : null,
      gfz: (src.kpGFZ.data || []).slice(-8).map((r) => ({ t: new Date(r.t).toISOString(), kp: r.kp, status: r.status })),
    },
    solarWind: src.solarWind.data,
    ovation: src.ovation.data,
    enlil: src.enlil.data,
    scales: src.scales.data,
    alerts: src.alerts.data,
    hemisphericPower: src.hemisphericPower.data,
    // Kept apart from Kp: Hp30 (GFZ, every 30 min) and the ground magnetometer (Narsarsuaq, every minute).
    hp30: (src.hp30.data || []).slice(-16).map((r) => ({ t: new Date(r.t).toISOString(), hp30: r.hp30 })),
    magnetometer: usable("magnetometer"),
    donki: src.donki.data,
    longTerm: { outlook27: src.outlook27.data, forecast45: src.forecast45.data },
  };
}

/** A few numbers for small screens (the Garmin watch app): Kp now and in the next 24 h, Bz, hemispheric power, G scale. */
export function compactState(state, now = Date.now()) {
  const blocks = state.kp?.blocks || [];
  const current = blocks.filter((b) => Date.parse(b.t) <= now).at(-1);
  const next24 = blocks.filter((b) => Date.parse(b.t) > now - 3 * 3600e3 && Date.parse(b.t) <= now + 24 * 3600e3);
  const round = (v) => (typeof v === "number" ? Math.round(v * 10) / 10 : null);
  return {
    generated: state.generated,
    kp: round(current?.value),
    kpMax24: round(next24.reduce((m, b) => (typeof b.value === "number" && b.value > m ? b.value : m), -1)),
    bz: round(state.solarWind?.latest?.bz),
    hp: state.hemisphericPower?.latest?.north ?? null,
    hp30: round(state.hp30?.at(-1)?.hp30),
    mag: state.magnetometer?.level ?? null,
    magNt: state.magnetometer?.rangeNt ?? null,
    g: (state.scales || []).filter((x) => x.index > 0).reduce((m, x) => Math.max(m, x.g || 0), 0),
  };
}

export default async function handler(req, res) {
  // /api/watch?lat=&lon=&lang= (rewritten here): conditions for the Garmin watch app.
  const query = new URL(req.url, "http://x").searchParams;
  if (query.get("watch") === "1") {
    const lat = Number(query.get("lat")), lon = Number(query.get("lon"));
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      return send(res, 400, { error: "lat/lon" });
    }
    try {
      const body = await watchConditions(lat, lon, query.get("lang") === "en" ? "en" : "it");
      res.setHeader("Cache-Control", "public, s-maxage=300, stale-while-revalidate=600");
      return send(res, 200, body);
    } catch (e) {
      console.error("watch", e.message);
      return send(res, 502, { error: "weather" });
    }
  }
  const state = await buildState();
  // Archive once per Kp block. Awaited (a serverless function may freeze once the
  // response is sent) but capped at 4 s; failures never affect the response.
  await Promise.race([
    archiveSnapshot(state).catch((e) => console.error("archive", e.message)),
    new Promise((resolve) => setTimeout(resolve, 4000)),
  ]);
  const essential = state.sources.kpForecast.status !== "error" || state.sources.solarWind.status !== "error";
  res.setHeader("Cache-Control", essential ? "public, s-maxage=60, stale-while-revalidate=3600" : "no-store");
  const compact = query.get("compact") === "1";
  return send(res, essential ? 200 : 502, compact ? compactState(state) : state);
}
