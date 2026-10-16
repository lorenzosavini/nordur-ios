// Aurora sightings reported by signed-in users (kept separate from forecasts
// and measurements).
//   POST /api/sightings  { lat, lon, nakedEye, camera, strength }  (Bearer token)
//   GET  /api/sightings?hours=3  -> reports aggregated on a 0.5° grid, no identities
//
// Safeguards: account required, one report per user every 20 minutes,
// coordinates must be at northern auroral latitudes (≥ 40°N), the report time
// is the server time (no back-dating), duplicates in the same cell/30 min from
// the same user are rejected. Absence of reports does not mean absence of aurora.
import crypto from "node:crypto";
import { list } from "@vercel/blob";
import { verifyToken, readObject, writeObject, readJSON, send, hmac } from "../lib/core.js";

const lastByUser = new Map(); // per instance, first line of defence; the blob key enforces the rest

export default async function handler(req, res) {
  if (req.method === "POST") {
    const uid = verifyToken(req.headers.authorization);
    if (!uid) return send(res, 401, { error: "Accedi per inviare un avvistamento" });
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
    const record = {
      t: new Date(now).toISOString(),
      lat: Math.round(lat * 100) / 100, lon: Math.round(lon * 100) / 100, // ~1 km: enough, not a home address
      nakedEye: Boolean(body.nakedEye), camera: Boolean(body.camera),
      strength: ["debole", "moderata", "forte"].includes(body.strength) ? body.strength : null,
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
    const days = [...new Set([0, 1].map((d) => new Date(Date.now() - d * 864e5).toISOString().slice(0, 10)))];
    const keys = [];
    for (const day of days) {
      const page = await list({ prefix: `sightings/${day}/`, limit: 500 });
      keys.push(...page.blobs.filter((b) => Date.parse(b.uploadedAt) >= since).map((b) => b.pathname));
    }
    const records = (await Promise.all(keys.slice(0, 200).map((k) => readObject(k).catch(() => null)))).filter(Boolean);
    const cells = new Map();
    for (const r of records) {
      const key = `${Math.round(r.lat * 2) / 2},${Math.round(r.lon * 2) / 2}`;
      const c = cells.get(key) || { lat: Math.round(r.lat * 2) / 2, lon: Math.round(r.lon * 2) / 2, reports: 0, nakedEye: 0, camera: 0, latest: r.t };
      c.reports++; if (r.nakedEye) c.nakedEye++; if (r.camera) c.camera++; if (r.t > c.latest) c.latest = r.t;
      cells.set(key, c);
    }
    res.setHeader("Cache-Control", "public, s-maxage=120");
    return send(res, 200, { hours, total: records.length, cells: [...cells.values()] });
  }
  return send(res, 405, { error: "method" });
}
