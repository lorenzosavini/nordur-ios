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

// OpenStreetMap layers, in Overpass' own JSON shape (trimmed to the tags the app reads):
//   GET /api/roads?shops=1       -> supermarkets, mini-markets, malls and Vínbúðin
//   GET /api/roads?osm=sights    -> places to visit: waterfalls, viewpoints, hot springs,
//                                   geysers, caves, arches, volcanoes, glaciers, beaches,
//                                   museums, attractions and geothermal pools (named only)
// Public Overpass servers are often slow or busy for the whole country: fetched here
// with the mirrors raced over four smaller areas, refreshed by a weekly cron
// (&refresh=1), and the last good copy served to everyone straight away.
const OSM_REFRESH = 86400e3; // a refresh asked within a day of the last one is skipped
const OVERPASS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];
const AREAS = ["63.2,-24.6,64.6,-19.0", "64.6,-24.6,66.6,-19.0", "63.2,-19.0,64.9,-13.4", "64.9,-19.0,66.6,-13.4"];
const OSM_LAYERS = {
  shops: {
    cache: "public/shops.bin", min: 50,
    filters: ['nwr["shop"~"^(supermarket|convenience|mall|alcohol|department_store)$"]'],
    keep: ["shop", "name", "brand", "operator", "opening_hours", "addr:city", "addr:place"],
  },
  sights: {
    cache: "public/sights.bin", min: 200,
    filters: [
      'nwr["tourism"~"^(attraction|viewpoint|museum)$"]["name"]',
      'nwr["natural"~"^(waterfall|hot_spring|geyser|cave_entrance|arch|volcano|glacier|beach)$"]["name"]',
      'nwr["waterway"="waterfall"]["name"]',
      'nwr["amenity"="public_bath"]["name"]',
      'nwr["leisure"="swimming_pool"]["name"~"laug|lagoon",i]["access"!="private"]',
    ],
    keep: ["tourism", "natural", "waterway", "amenity", "leisure", "name", "name:en", "wikipedia", "wikidata",
      "description", "description:en", "fee", "opening_hours", "ele"],
  },
};
const osmMemory = {}; // layer -> { at, elements }

const osmQuery = (layer, bbox) => `[out:json][timeout:45];
(${layer.filters.map((f) => `${f}(${bbox});`).join("")});
out center tags;`;

export function compactOsm(json, keep = OSM_LAYERS.shops.keep) {
  return (json?.elements || []).map((e) => {
    const lat = e.lat ?? e.center?.lat;
    const lon = e.lon ?? e.center?.lon;
    if (lat == null || lon == null || !e.tags) return null;
    const tags = Object.fromEntries(keep.filter((k) => e.tags[k]).map((k) => [k, String(e.tags[k]).slice(0, 300)]));
    return { id: e.id, lat: Math.round(lat * 1e5) / 1e5, lon: Math.round(lon * 1e5) / 1e5, tags };
  }).filter(Boolean);
}
export const compactShops = (json) => compactOsm(json, OSM_LAYERS.shops.keep);

async function overpassArea(layer, bbox) {
  return Promise.any(OVERPASS.map(async (endpoint) => {
    const res = await fetch(endpoint, {
      method: "POST", body: new URLSearchParams({ data: osmQuery(layer, bbox) }),
      headers: { "User-Agent": "nordur-api (github.com/lorenzosavini/nordur-ios)", Accept: "application/json" },
      signal: AbortSignal.timeout(50000),
    });
    if (!res.ok) throw new Error(`${endpoint} ${res.status}`);
    const json = await res.json();
    if (json.remark && !json.elements?.length) throw new Error(`${endpoint}: ${json.remark}`);
    return compactOsm(json, layer.keep);
  }));
}

async function overpassLayer(layer) {
  const areas = await Promise.all(AREAS.map((bbox) => overpassArea(layer, bbox)));
  const seen = new Set();
  const elements = areas.flat().filter((e) => !seen.has(e.id) && seen.add(e.id));
  if (elements.length < layer.min) throw new Error(`solo ${elements.length} elementi`);
  return elements;
}

/** The stored copy of a layer, downloaded when there is none or on a refresh. */
async function osmLayer(name, refresh) {
  const layer = OSM_LAYERS[name];
  if (!osmMemory[name]) osmMemory[name] = await readObject(layer.cache).catch(() => null);
  if (!osmMemory[name] || (refresh && Date.now() - osmMemory[name].at > OSM_REFRESH)) {
    try {
      osmMemory[name] = { at: Date.now(), elements: await overpassLayer(layer) };
      await writeObject(layer.cache, osmMemory[name], { ttl: 60 * 86400 }).catch((e) => console.error(name, "cache", e.message));
    } catch (e) {
      console.error(name, e.errors?.map((x) => x.message).join("; ") || e.message);
    }
  }
  return osmMemory[name];
}

async function osm(res, name, refresh) {
  if (!OSM_LAYERS[name]) return send(res, 400, { error: "osm" });
  const stored = await osmLayer(name, refresh);
  if (!stored) return send(res, 502, { error: "OpenStreetMap non raggiungibile" });
  res.setHeader("Cache-Control", "public, s-maxage=86400, stale-while-revalidate=604800");
  return send(res, 200, { updated: new Date(stored.at).toISOString(), elements: stored.elements });
}

export default async function handler(req, res) {
  const params = new URL(req.url, "http://x").searchParams;
  const refresh = params.get("refresh") === "1";
  if (params.get("shops")) return osm(res, "shops", refresh);
  if (params.get("osm")) {
    // The weekly cron refreshes every layer.
    if (params.get("osm") === "all") {
      const done = await Promise.all(Object.keys(OSM_LAYERS).map(async (name) => [name, (await osmLayer(name, refresh))?.elements.length ?? 0]));
      return send(res, 200, Object.fromEntries(done));
    }
    return osm(res, params.get("osm"), refresh);
  }
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
