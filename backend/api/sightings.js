// Aurora sightings reported by signed-in users (kept separate from forecasts
// and measurements).
//   POST /api/sightings  { lat, lon, seen, nakedEye, camera, strength, sky }  (Bearer token)
//        seen = false is a negative report ("I'm looking, no aurora"), with the sky
//        as the observer saw it: a clear-sky negative is evidence, a cloudy one is not.
//   GET  /api/sightings?hours=3  -> reports aggregated on a 0.5° grid, plus the
//        individual reports (time, position rounded to 0.1°, what was seen), no identities
//
// Safeguards: account required, one report per user every 20 minutes,
// coordinates must be at northern auroral latitudes (≥ 40°N), the report time
// is the server time (no back-dating), duplicates in the same cell/30 min from
// the same user are rejected. Absence of reports does not mean absence of aurora.
import crypto from "node:crypto";
import { verifyToken, readObject, writeObject, listObjects, readJSON, send, hmac, isRevoked } from "../lib/core.js";

const lastByUser = new Map(); // per instance, first line of defence; the blob key enforces the rest
const recentCache = new Map(); // hours -> { at, body }: one storage listing per minute at most

export default async function handler(req, res) {
  if (req.method === "POST") {
    const uid = verifyToken(req.headers.authorization);
    if (!uid || (await isRevoked(uid))) return send(res, 401, { error: "Accedi per inviare un avvistamento" });
    const body = await readJSON(req).catch(() => ({}));
    const lat = Number(body.lat), lon = Number(body.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || lat < 40 || lat > 90 || lon < -180 || lon > 180) {
      return send(res, 400, { error: "Posizione non valida" });
    }
    const now = Date.now();
    if (now - (lastByUser.get(uid) || 0) < 20 * 60e3) return send(res, 429, { error: "Puoi inviare un avvistamento ogni 20 minuti" });
    const user = hmac(uid, "sighting");
    const slot = Math.floor(now / (30 * 60e3));
    const cell = `${Math.round(lat * 2) / 2}_${Math.round(lon * 2) / 2}`;
    const day = new Date(now).toISOString().slice(0, 10);
    const key = `sightings/${day}/${slot}-${cell}-${user.slice(0, 16)}.bin`;
    const seen = body.seen !== false;
    const record = {
      t: new Date(now).toISOString(),
      lat: Math.round(lat * 100) / 100, lon: Math.round(lon * 100) / 100, // ~1 km: enough, not a home address
      seen,
      nakedEye: seen && Boolean(body.nakedEye), camera: seen && Boolean(body.camera),
      strength: seen && ["debole", "moderata", "forte"].includes(body.strength) ? body.strength : null,
      sky: ["sereno", "parziale", "coperto"].includes(body.sky) ? body.sky : null,
      id: crypto.randomUUID(),
    };
    try {
      await writeObject(key, record, { overwrite: false });
    } catch (e) {
      if (/exist/i.test(e.message)) return send(res, 409, { error: "Avvistamento già registrato per questa zona" });
      console.error(e);
      return send(res, 500, { error: "Errore del server" });
    }
    lastByUser.set(uid, now);
    return send(res, 200, { ok: true });
  }

  if (req.method === "GET") {
    const hours = Math.min(24, Math.max(1, Number(new URL(req.url, "http://x").searchParams.get("hours")) || 3));
    const since = Date.now() - hours * 3600e3;
    res.setHeader("Cache-Control", "public, s-maxage=60");
    const hit = recentCache.get(hours);
    if (hit && Date.now() - hit.at < 60e3) return send(res, 200, hit.body);
    const days = [...new Set([0, 1].map((d) => new Date(Date.now() - d * 864e5).toISOString().slice(0, 10)))];
    const sinceSlot = Math.floor(since / (30 * 60e3));
    const keys = [];
    for (const day of days) {
      // The key starts with the 30-minute slot of the report: no upload time needed.
      const objects = await listObjects(`sightings/${day}/`, { limit: 500 });
      keys.push(...objects.map((b) => b.pathname).filter((k) => Number(k.split("/").pop().split("-")[0]) >= sinceSlot));
    }
    const records = (await Promise.all(keys.slice(0, 200).map((k) => readObject(k).catch(() => null)))).filter(Boolean);
    const body = { hours, ...aggregate(records, since) };
    recentCache.set(hours, { at: Date.now(), body });
    return send(res, 200, body);
  }
  return send(res, 405, { error: "method" });
}

/** Grid cells (positive reports only, as before) and the individual reports, anonymous and coarsened. */
export function aggregate(records, since = 0) {
  const recent = records
    .filter((r) => Date.parse(r.t) >= since)
    .sort((a, b) => (a.t < b.t ? 1 : -1));
  const cells = new Map();
  for (const r of recent) {
    const seen = r.seen !== false;
    const key = `${Math.round(r.lat * 2) / 2},${Math.round(r.lon * 2) / 2}`;
    const c = cells.get(key) || { lat: Math.round(r.lat * 2) / 2, lon: Math.round(r.lon * 2) / 2, reports: 0, nakedEye: 0, camera: 0, negative: 0, latest: r.t };
    if (seen) { c.reports++; if (r.nakedEye) c.nakedEye++; if (r.camera) c.camera++; } else c.negative++;
    if (r.t > c.latest) c.latest = r.t;
    cells.set(key, c);
  }
  return {
    total: recent.filter((r) => r.seen !== false).length,
    negative: recent.filter((r) => r.seen === false).length,
    cells: [...cells.values()],
    recent: recent.map((r) => ({
      t: r.t, lat: Math.round(r.lat * 10) / 10, lon: Math.round(r.lon * 10) / 10,
      seen: r.seen !== false, nakedEye: Boolean(r.nakedEye), camera: Boolean(r.camera), strength: r.strength || null, sky: r.sky || null,
    })),
  };
}
