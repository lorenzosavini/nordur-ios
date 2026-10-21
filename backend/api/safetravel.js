// GET /api/safetravel -> SafeTravel.is alerts, passed through unchanged.
//
// The app reads safetravel.is directly; this copy is its second way in, for
// when the site does not answer the phone (it can stay unreachable from some
// networks for hours). Cached at the edge for 5 minutes; the last good answer
// is kept in memory for when the site fails here too.
import { fetchWithRetry } from "../lib/fetch.js";
import { send } from "../lib/core.js";

const SOURCE = "https://safetravel.is/wp-json/wp/v2/alert?per_page=20";
let last = null; // { at, body }

export default async function handler(req, res) {
  try {
    const response = await fetchWithRetry(SOURCE, { timeout: 15000, retries: 1 });
    const body = await response.json();
    if (!Array.isArray(body)) throw new Error("risposta non valida");
    last = { at: Date.now(), body };
  } catch (e) {
    if (!last) return send(res, 502, { error: `SafeTravel non risponde: ${e.message}` });
  }
  res.setHeader("Cache-Control", "public, s-maxage=300, stale-while-revalidate=3600");
  res.setHeader("X-Fetched-At", new Date(last.at).toISOString());
  send(res, 200, last.body);
}
