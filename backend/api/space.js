// GET /api/space -> NASA CCMC DONKI digest (storms, WSA-ENLIL CME arrivals, M/X flares).
// Kept for older app builds; /api/aurora includes the same data.
import { send } from "../lib/core.js";
import { loadDonki } from "../lib/donki.js";

export default async function handler(req, res) {
  const d = await loadDonki();
  if (!d.digest) {
    res.setHeader("Cache-Control", "public, s-maxage=300");
    return send(res, 503, { source: "NASA CCMC DONKI", generated: null, stale: true, errors: d.errors, storms: [], arrivals: [], flares: [] });
  }
  res.setHeader("Cache-Control", d.stale ? "public, s-maxage=300" : "public, s-maxage=1800, stale-while-revalidate=3600");
  return send(res, 200, { source: "NASA CCMC DONKI", generated: new Date(d.fetchedAt).toISOString(), stale: d.stale, errors: d.errors, ...d.digest });
}
