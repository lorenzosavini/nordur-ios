// GET /api/horizon?lat=64.15&lon=-21.94 -> terrain horizon angle for 16 azimuths.
// Coordinates are rounded to 0.01° (~1 km) so the CDN can cache the answer
// for a year: terrain does not change, and OpenTopoData allows 1 call/s.
import { send } from "../lib/core.js";
import { horizon } from "../lib/horizon.js";

const memory = new Map();

export default async function handler(req, res) {
  const q = new URL(req.url, "http://x").searchParams;
  const lat = Math.round(Number(q.get("lat")) * 100) / 100, lon = Math.round(Number(q.get("lon")) * 100) / 100;
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 85 || Math.abs(lon) > 180) return send(res, 400, { error: "coordinate" });
  const key = `${lat},${lon}`;
  try {
    if (!memory.has(key)) memory.set(key, await horizon(lat, lon));
    res.setHeader("Cache-Control", "public, s-maxage=31536000, immutable");
    return send(res, 200, memory.get(key));
  } catch (e) {
    console.error(e);
    res.setHeader("Cache-Control", "public, s-maxage=600");
    return send(res, 502, { error: "Modello del terreno non raggiungibile" });
  }
}
