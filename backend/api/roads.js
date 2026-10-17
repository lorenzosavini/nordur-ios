// GET /api/roads -> live road information from Vegagerðin's umferdin.is.
//
// Source: the GraphQL API behind umferdin.is (public, no key, not formally
// documented): every serviced road section with its surface condition (and the
// previous one), roadworks and hazards with coordinates and dates, axle-load
// limits, tolls, winter-service hours and the road numbers it belongs to; plus
// the live road notifications (roadworks, closures, Highlands, weight limits).
// Fetched once every 5 minutes for everyone; last good copy kept in Blob.
import { fetchWithRetry } from "../lib/fetch.js";
import { send, readObject, writeObject } from "../lib/core.js";

const ENDPOINT = "https://umferdin.is/graphql";
const TTL = 5 * 60e3;
const CACHE = "public/roads.bin";

const SECTIONS = `query RoadCondition($lang: Languages) { RoadCondition(lang: $lang) { lastUpdate results {
  id name serviceCategory winterService
  condition { code category description date } conditionPrev { code category description date }
  conditionsOtherMarkers { id coordinates { lon lat } title description code dateFrom dateTo lastUpdate }
  conditionMarkers { description code lastUpdate }
  weightRestriction { limit description } toll { type description position { lat lon } }
  roads { name nr } lastUpdate serviceByDay { day type from to } bbox geometryCenter { lat lon } } } }`;
const NOTIFICATIONS = `query RoadNotifications($language: RoadNotificationsLanguage) { RoadNotifications(language: $language) {
  results { id category key subCategory text tags date } } }`;
const INFO = `query RoadConditionInfo($lang: Languages!) { RoadConditionInfo(lang: $lang) { title description code type } }`;

let memory = null; // { at, body }
let persistedAt = 0; // the storage copy is only a fallback: refreshed hourly, not every 5 minutes

async function graphql(query, variables) {
  const res = await fetchWithRetry(ENDPOINT, {
    timeout: 20000, retries: 1, method: "POST",
    headers: { "Content-Type": "application/json" }, body: JSON.stringify({ query, variables }),
  });
  const json = await res.json();
  if (json.errors?.length) throw new Error(json.errors[0].message || "GraphQL");
  return json.data;
}

const plain = (html) => (html || "").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim();
const point = (c) => (c && c.lat != null && c.lon != null ? { lat: c.lat, lon: c.lon } : null);
const condition = (c) => (c ? { code: c.code, category: c.category, text: c.description, date: c.date } : null);

export function compact(sections, notifications, info, now = Date.now()) {
  const results = (sections?.RoadCondition?.results || []).map((s) => ({
    id: String(s.id),
    name: s.name,
    roads: (s.roads || []).map((r) => ({ nr: String(r.nr), name: r.name })),
    service: s.serviceCategory ?? null,
    winterService: s.winterService || null,
    hours: (s.serviceByDay || []).map((d) => ({ day: d.day, type: d.type, from: d.from, to: d.to })),
    condition: condition(s.condition),
    previous: condition(s.conditionPrev),
    hazards: (s.conditionsOtherMarkers || [])
      .filter((m) => !m.dateTo || Date.parse(m.dateTo) > now)
      .map((m) => ({ id: String(m.id), code: m.code, title: m.title, text: plain(m.description), from: m.dateFrom, to: m.dateTo, at: point(m.coordinates) })),
    notes: (s.conditionMarkers || []).map((m) => ({ code: m.code, text: plain(m.description), date: m.lastUpdate })),
    weight: s.weightRestriction ? { limit: s.weightRestriction.limit, text: plain(s.weightRestriction.description) } : null,
    toll: s.toll ? { type: s.toll.type, text: plain(s.toll.description), at: point(s.toll.position) } : null,
    bbox: Array.isArray(s.bbox) && s.bbox.length === 4 ? s.bbox : null, // [west, south, east, north]
    center: point(s.geometryCenter),
    updated: s.lastUpdate,
  }));
  return {
    generated: new Date(now).toISOString(),
    source: "Vegagerðin · umferdin.is",
    lastUpdate: sections?.RoadCondition?.lastUpdate || null,
    sections: results,
    news: (notifications?.RoadNotifications?.results || []).map((n) => ({
      id: String(n.id), region: n.category, key: n.key, place: n.subCategory, text: plain(n.text), date: n.date,
    })),
    codes: (info?.RoadConditionInfo || []).map((c) => ({ code: c.code, type: c.type, title: c.title, text: plain(c.description) })),
  };
}

export default async function handler(req, res) {
  if (!memory || Date.now() - memory.at > TTL) {
    try {
      const [sections, notifications, info] = await Promise.all([
        graphql(SECTIONS, { lang: "EN" }),
        graphql(NOTIFICATIONS, { language: "EN" }),
        graphql(INFO, { lang: "EN" }),
      ]);
      memory = { at: Date.now(), body: compact(sections, notifications, info) };
      if (!memory.body.sections.length) throw new Error("umferdin.is: nessun tratto");
      if (Date.now() - persistedAt > 3600e3) {
        persistedAt = Date.now();
        await writeObject(CACHE, memory, { ttl: 2 * 86400 }).catch((e) => console.error("roads cache", e.message));
      }
    } catch (e) {
      console.error("roads", e.message);
      const stored = memory || (await readObject(CACHE).catch(() => null));
      if (!stored) return send(res, 502, { error: "umferdin.is non raggiungibile" });
      memory = stored;
      res.setHeader("Cache-Control", "public, s-maxage=60");
      return send(res, 200, { ...memory.body, stale: true });
    }
  }
  res.setHeader("Cache-Control", "public, s-maxage=300, stale-while-revalidate=300");
  return send(res, 200, memory.body);
}
