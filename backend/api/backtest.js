// GET /api/backtest?days=7 -> accuracy of the archived Kp forecasts against
// the Kp observed afterwards (GFZ Potsdam where available, else NOAA observed).
//
// Two forecasts are scored: NOAA's own and the combined one (blend).
// Metrics per lead-time bucket: n, MAE, bias, RMSE, and for the events
// Kp ≥ 4 and Kp ≥ 5 a contingency table with precision, POD (recall), FAR
// and the Brier score of the 0/1 forecast. These are deterministic forecasts:
// the Brier score here equals the error rate, it is not a probabilistic score.
import { list } from "@vercel/blob";
import { readObject, send } from "../lib/core.js";
import { fetchJSON, utc } from "../lib/fetch.js";
import * as S from "../lib/sources.js";

const BUCKETS = [["0-3 h", 0, 3], ["3-24 h", 3, 24], ["24-72 h", 24, 72]];

async function truth(days) {
  const out = new Map();
  try {
    const f = await S.kpForecast();
    for (const r of f.data) if (r.kind === "observed") out.set(r.t, { kp: r.kp, source: "NOAA" });
  } catch {}
  try {
    const start = new Date(Date.now() - (days + 4) * 864e5).toISOString().slice(0, 10) + "T00:00:00Z";
    const end = new Date().toISOString().slice(0, 19) + "Z";
    const g = await fetchJSON(`https://kp.gfz.de/app/json/?start=${start}&end=${end}&index=Kp&status=all`);
    (g.datetime || []).forEach((t, i) => { if (g.Kp?.[i] != null) out.set(utc(t), { kp: g.Kp[i], source: `GFZ ${g.status?.[i] || ""}`.trim() }); });
  } catch {}
  return out;
}

function score(pairs) {
  if (!pairs.length) return { n: 0 };
  const err = pairs.map(([f, o]) => f - o);
  const n = pairs.length;
  const events = {};
  for (const threshold of [4, 5]) {
    let tp = 0, fp = 0, fn = 0, tn = 0;
    for (const [f, o] of pairs) {
      const F = f >= threshold, O = o >= threshold;
      if (F && O) tp++; else if (F) fp++; else if (O) fn++; else tn++;
    }
    events[`kp${threshold}`] = {
      tp, fp, fn, tn,
      precision: tp + fp ? +(tp / (tp + fp)).toFixed(2) : null,
      pod: tp + fn ? +(tp / (tp + fn)).toFixed(2) : null,
      far: tp + fp ? +(fp / (tp + fp)).toFixed(2) : null,
      brier01: +((fp + fn) / n).toFixed(3),
    };
  }
  return {
    n,
    mae: +(err.reduce((a, e) => a + Math.abs(e), 0) / n).toFixed(2),
    bias: +(err.reduce((a, e) => a + e, 0) / n).toFixed(2),
    rmse: +Math.sqrt(err.reduce((a, e) => a + e * e, 0) / n).toFixed(2),
    events,
  };
}

export default async function handler(req, res) {
  const days = Math.min(14, Math.max(1, Number(new URL(req.url, "http://x").searchParams.get("days")) || 7));
  try {
    const keys = [];
    for (let d = 0; d <= days; d++) {
      const prefix = `archive/aurora/${new Date(Date.now() - d * 864e5).toISOString().slice(0, 10)}/`;
      const page = await list({ prefix, limit: 100 });
      keys.push(...page.blobs.map((b) => b.pathname));
    }
    const snapshots = [];
    for (let i = 0; i < keys.length; i += 10) {
      const batch = await Promise.all(keys.slice(i, i + 10).map((k) => readObject(k).catch(() => null)));
      snapshots.push(...batch.filter(Boolean));
    }
    const observed = await truth(days);
    const pairs = Object.fromEntries(BUCKETS.map(([name]) => [name, { noaa: [], blend: [] }]));
    for (const s of snapshots) {
      const issued = Date.parse(s.issuedAt);
      for (const b of s.kpBlocks || []) {
        if (b.kind === "observed") continue;
        const t = Date.parse(b.t), o = observed.get(t);
        if (!o) continue;
        const lead = (t - issued) / 3600e3;
        const bucket = BUCKETS.find(([, lo, hi]) => lead >= lo - 3 && lead < hi); // the current block has lead in (-3, 0]
        if (!bucket) continue;
        pairs[bucket[0]].noaa.push([b.noaa, o.kp]);
        pairs[bucket[0]].blend.push([b.value, o.kp]);
      }
    }
    const result = Object.fromEntries(Object.entries(pairs).map(([k, v]) => [k, { noaa: score(v.noaa), blend: score(v.blend) }]));
    const total = Object.values(pairs).reduce((a, v) => a + v.noaa.length, 0);
    res.setHeader("Cache-Control", "public, s-maxage=21600");
    return send(res, 200, {
      generated: new Date().toISOString(),
      days, snapshots: snapshots.length, verifiedPairs: total,
      sufficient: total >= 100,
      note: total >= 100 ? null : "Campione ancora troppo piccolo per conclusioni: servono almeno ~100 coppie previsione/osservazione.",
      truth: "Kp GFZ Potsdam (definitivo/preliminare) dove disponibile, altrimenti Kp osservato NOAA",
      buckets: result,
    });
  } catch (e) {
    console.error(e);
    return send(res, 500, { error: "backtest non disponibile" });
  }
}
