// GET /api/sites?photo=1&name=…&lat=…&lon=…&lang=it[&wikidata=Q…][&wikipedia=en:Title]
//   -> { candidates: [{ imageURL, title, author, license, page }] }
//
// Free photos of a place from Wikimedia, best first: the Wikidata image, the
// linked or same-name Wikipedia article (app language, English, Icelandic),
// photos geotagged within 1 km, a search, the nearest article, Commons 5 km.
// Asked one request at a time with a descriptive User-Agent and kept 30 days
// (3 when nothing is found) for every user: phones asking Wikimedia directly,
// ten requests per place, were being refused for too many requests. The phone
// still checks each candidate for faces before showing it.
import { readObject, writeObject, send, hmac } from "./core.js";

const UA = "Nordur/1.0 (https://github.com/lorenzosavini/nordur-ios; travel app for Iceland)";
const NOT_A_VIEW = [".svg", "map", "kort", "flag", "coat_of_arms", "coat of arms", "skjaldarmerki", "location", "logo", "diagram"];
const memory = new Map();

async function api(host, params) {
  const url = `https://${host}/w/api.php?` + new URLSearchParams({ format: "json", formatversion: "2", ...params });
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch(url, { headers: { "User-Agent": UA, "Api-User-Agent": UA }, signal: AbortSignal.timeout(8000) }).catch(() => null);
    if (res?.ok) return res.json().catch(() => null);
    if (res && res.status !== 429 && res.status < 500) return null;
    await new Promise((r) => setTimeout(r, 800 * (attempt + 1)));
  }
  return null;
}

const plain = (html) => String(html || "").replace(/<[^>]+>/g, "").trim();
const freeLicence = (l) => /cc|public domain|pd/i.test(l || "");

/** Lead images of Wikipedia pages: [{ file, title, page }]. */
async function articles(lang, params) {
  const j = await api(`${lang}.wikipedia.org`, { action: "query", prop: "pageimages|info", inprop: "url", piprop: "name", pilicense: "free", redirects: "1", ...params });
  return (j?.query?.pages || []).filter((p) => p.pageimage).sort((a, b) => (a.index ?? 99) - (b.index ?? 99))
    .map((p) => ({ file: p.pageimage, title: p.title, page: p.fullurl }));
}

/** Commons files with thumbnail, licence and author. */
async function files(params) {
  const j = await api("commons.wikimedia.org", { action: "query", prop: "imageinfo", iiprop: "url|mime|extmetadata", iiurlwidth: "1200", ...params });
  return (j?.query?.pages || []).sort((a, b) => (a.index ?? 99) - (b.index ?? 99)).map((p) => {
    const info = p.imageinfo?.[0];
    if (!info || info.mime !== "image/jpeg" || !info.thumburl) return null;
    const license = info.extmetadata?.LicenseShortName?.value || null;
    if (!freeLicence(license)) return null;
    const author = plain(info.extmetadata?.Artist?.value).slice(0, 40) || null;
    return { imageURL: info.thumburl, title: p.title, author, license, page: info.descriptionurl || null };
  }).filter(Boolean);
}

async function lookup({ name, lat, lon, lang, wikidata, wikipedia }) {
  const out = [];
  const seen = new Set();
  const add = (list) => { for (const c of list) if (c && !seen.has(c.imageURL) && !NOT_A_VIEW.some((w) => c.title.toLowerCase().includes(w))) { seen.add(c.imageURL); out.push(c); } };
  // Lead images of articles: the files' details come from Commons in one request.
  const fromArticles = async (pages) => {
    const usable = pages.filter((p) => !NOT_A_VIEW.some((w) => p.file.toLowerCase().includes(w)));
    if (!usable.length) return [];
    const found = await files({ titles: usable.map((p) => `File:${p.file}`).join("|") });
    return usable.map((p) => {
      const f = found.find((x) => x.title.replace(/^File:/, "").replace(/_/g, " ") === p.file.replace(/_/g, " "));
      return f && { ...f, title: p.title, page: p.page };
    }).filter(Boolean);
  };
  const enough = () => out.length >= 4;

  if (wikidata) {
    const j = await api("www.wikidata.org", { action: "wbgetclaims", entity: wikidata, property: "P18" });
    const file = j?.claims?.P18?.[0]?.mainsnak?.datavalue?.value;
    if (file) add(await files({ titles: `File:${file}` }));
  }
  if (wikipedia && wikipedia.includes(":")) {
    const [l, ...t] = wikipedia.split(":");
    add(await fromArticles(await articles(l, { titles: t.join(":") })));
  }
  for (const l of [...new Set([lang, "en", "is"])]) {
    if (enough()) break;
    add(await fromArticles(await articles(l, { titles: name })));
  }
  if (!enough()) add((await files({ generator: "geosearch", ggscoord: `${lat}|${lon}`, ggsradius: "1000", ggsnamespace: "6", ggslimit: "12" })).slice(0, 6));
  if (!out.length) add(await fromArticles(await articles("en", { generator: "search", gsrsearch: `${name} Iceland`, gsrlimit: "3" })));
  if (!out.length) add(await fromArticles((await articles("en", { generator: "geosearch", ggscoord: `${lat}|${lon}`, ggsradius: "10000", ggslimit: "8" })).slice(0, 6)));
  if (!out.length) add((await files({ generator: "geosearch", ggscoord: `${lat}|${lon}`, ggsradius: "5000", ggsnamespace: "6", ggslimit: "12" })).slice(0, 6));
  return out.slice(0, 8);
}

export async function placePhotos(req, res, params) {
  const name = String(params.get("name") || "").replace(/\s*\(.*\)/, "").trim().slice(0, 120);
  const lat = Number(params.get("lat")), lon = Number(params.get("lon"));
  if (!name || !Number.isFinite(lat) || !Number.isFinite(lon)) return send(res, 400, { error: "place" });
  const lang = ["it", "en", "de", "fr", "es", "is"].includes(params.get("lang")) ? params.get("lang") : "en";
  const wikidata = /^Q\d+$/.test(params.get("wikidata") || "") ? params.get("wikidata") : null;
  const wikipedia = (params.get("wikipedia") || "").slice(0, 200) || null;
  const key = `photos/${hmac([name, lat.toFixed(2), lon.toFixed(2), lang, wikidata, wikipedia].join("|"), "photo").slice(0, 40)}.bin`;

  let entry = memory.get(key) || (await readObject(key).catch(() => null));
  const fresh = entry && Date.now() - entry.at < (entry.candidates.length ? 30 : 3) * 864e5;
  if (!fresh) {
    const candidates = await lookup({ name, lat: lat.toFixed(5), lon: lon.toFixed(5), lang, wikidata, wikipedia }).catch(() => null);
    if (candidates) {
      entry = { at: Date.now(), candidates };
      writeObject(key, entry, { ttl: 31 * 86400 }).catch(() => {});
    } else if (!entry) return send(res, 502, { error: "wikimedia" });
  }
  memory.set(key, entry);
  if (memory.size > 2000) memory.delete(memory.keys().next().value);
  res.setHeader("Cache-Control", `public, s-maxage=${entry.candidates.length ? 86400 : 21600}, stale-while-revalidate=604800`);
  send(res, 200, { candidates: entry.candidates });
}
