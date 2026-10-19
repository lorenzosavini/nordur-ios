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

// GET /api/roads?shops=1 -> supermarkets, mini-markets, malls and Vínbúðin from
// OpenStreetMap (Overpass), in Overpass' own JSON shape. Public Overpass servers
// are often slow or busy for the whole country: fetched here once a week, with
// the mirrors raced, and the last good copy served to everyone.
const SHOPS_CACHE = "public/shops.bin";
const SHOPS_TTL = 7 * 86400e3;
const OVERPASS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];
const SHOPS_QUERY = `[out:json][timeout:25];
(nwr["shop"~"^(supermarket|convenience|mall|alcohol|department_store)$"](63.2,-24.6,66.6,-13.4););
out center tags;`;
const KEEP = ["shop", "name", "brand", "operator", "opening_hours", "addr:city", "addr:place"];
let shopsMemory = null; // { at, elements }

export function compactShops(json) {
  return (json?.elements || []).map((e) => {
    const lat = e.lat ?? e.center?.lat;
    const lon = e.lon ?? e.center?.lon;
    if (lat == null || lon == null || !e.tags) return null;
    const tags = Object.fromEntries(KEEP.filter((k) => e.tags[k]).map((k) => [k, e.tags[k]]));
    return { id: e.id, lat: Math.round(lat * 1e5) / 1e5, lon: Math.round(lon * 1e5) / 1e5, tags };
  }).filter(Boolean);
}

async function overpassShops() {
  return Promise.any(OVERPASS.map(async (endpoint) => {
    const res = await fetch(endpoint, {
      method: "POST", body: new URLSearchParams({ data: SHOPS_QUERY }),
      headers: { "User-Agent": "nordur-api (github.com/lorenzosavini/nordur-ios)", Accept: "application/json" },
      signal: AbortSignal.timeout(26000),
    });
    if (!res.ok) throw new Error(`${endpoint} ${res.status}`);
    const elements = compactShops(await res.json());
    if (elements.length < 50) throw new Error(`${endpoint}: ${elements.length} negozi`);
    return elements;
  }));
}

async function shops(res) {
  if (!shopsMemory) shopsMemory = await readObject(SHOPS_CACHE).catch(() => null);
  if (!shopsMemory || Date.now() - shopsMemory.at > SHOPS_TTL) {
    try {
      shopsMemory = { at: Date.now(), elements: await overpassShops() };
      await writeObject(SHOPS_CACHE, shopsMemory, { ttl: 60 * 86400 }).catch((e) => console.error("shops cache", e.message));
    } catch (e) {
      console.error("shops", e.errors?.map((x) => x.message).join("; ") || e.message);
      if (!shopsMemory) return send(res, 502, { error: "OpenStreetMap non raggiungibile" });
    }
  }
  res.setHeader("Cache-Control", "public, s-maxage=86400, stale-while-revalidate=604800");
  return send(res, 200, { updated: new Date(shopsMemory.at).toISOString(), elements: shopsMemory.elements });
}

export default async function handler(req, res) {
  if (new URL(req.url, "http://x").searchParams.get("shops")) return shops(res);
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
