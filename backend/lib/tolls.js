// Tolls, toll tunnels and paid parking: a small curated catalog the app shows
// (GET /api/tolls, kept on the phone for use offline) and the owner edits in
// the admin panel without a new version of the app. Until the panel saves its
// own copy, the first edition in tolls-data.js is served.
//
// Every entry carries its official source and the day it was checked: the app
// always shows "checked on <date>" and "indicative prices, check the official site".
import { readObject, writeObject, listObjects, deleteObjects, readJSON, hmac } from "./core.js";
import { TOLLS_SEED } from "./tolls-data.js";

export const TYPES = ["toll_tunnel", "toll_road", "paid_parking", "info"];
const UNITS = ["trip", "day", "hour", "km"];
const METHODS = ["online", "account", "app", "machine", "bank", "kiosk"];
const LANGS = ["it", "en", "de", "fr", "es"];
const TEXT_FIELDS = ["summary", "payment", "window", "penalty", "rental", "alternative", "note"];
const PATH = "config/tolls.bin";
let memory = null;

const text = (v, max) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const https = (v) => (typeof v === "string" && /^https:\/\/[^\s]+$/.test(v.trim()) ? v.trim().slice(0, 400) : null);
const num = (v) => (typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v.replace(",", ".")) : NaN);
// Iceland and a margin: a typo in the panel can't put a tunnel in the ocean.
const inIceland = (lat, lon) => lat >= 62.8 && lat <= 67.6 && lon >= -25.5 && lon <= -12.5;

function point(p) {
  if (!Array.isArray(p) || p.length !== 2) return null;
  const lat = num(p[0]), lon = num(p[1]);
  return Number.isFinite(lat) && Number.isFinite(lon) && inIceland(lat, lon) ? [Math.round(lat * 1e5) / 1e5, Math.round(lon * 1e5) / 1e5] : null;
}

/**
 * One entry as the app understands it, or { error } saying what is wrong.
 * Unknown fields are dropped; a missing source or check date is an error.
 */
export function sanitizeEntry(e, index = 0) {
  const where = `Voce ${index + 1}${e?.id ? ` (${e.id})` : ""}`;
  if (!e || typeof e !== "object") return { error: `${where}: non è un oggetto` };
  const id = text(e.id, 40);
  if (!/^[a-z0-9_-]{2,40}$/.test(id)) return { error: `${where}: id mancante o non valido (lettere minuscole, numeri, - e _)` };
  if (!TYPES.includes(e.type)) return { error: `${where}: tipo non valido (${TYPES.join(", ")})` };
  const name = text(e.name, 80);
  if (!name) return { error: `${where}: nome mancante` };
  const source_url = https(e.source_url);
  if (!source_url) return { error: `${where}: source_url ufficiale mancante (https://…)` };
  const verified_at = typeof e.verified_at === "string" && /^\d{4}-\d{2}-\d{2}$/.test(e.verified_at) && !Number.isNaN(Date.parse(e.verified_at)) ? e.verified_at : null;
  if (!verified_at) return { error: `${where}: verified_at mancante (AAAA-MM-GG)` };

  const out = { id, type: e.type, name, source_name: text(e.source_name, 120) || null, source_url, verified_at };
  const lat = num(e.lat), lon = num(e.lon);
  if (Number.isFinite(lat) && Number.isFinite(lon)) {
    if (!inIceland(lat, lon)) return { error: `${where}: coordinate fuori dall'Islanda` };
    out.lat = Math.round(lat * 1e5) / 1e5;
    out.lon = Math.round(lon * 1e5) / 1e5;
  } else if (e.type !== "info") {
    return { error: `${where}: coordinate lat/lon mancanti` };
  }
  for (const key of ["points", "path"]) {
    if (e[key] == null) continue;
    if (!Array.isArray(e[key])) return { error: `${where}: ${key} deve essere un elenco di [lat, lon]` };
    const list = e[key].slice(0, 400).map(point);
    if (list.some((p) => !p)) return { error: `${where}: un punto di ${key} non è valido` };
    if (list.length) out[key] = list;
  }
  const radius = num(e.radius_m);
  if (Number.isFinite(radius)) out.radius_m = Math.min(5000, Math.max(50, Math.round(radius)));

  out.prices = [];
  for (const p of Array.isArray(e.prices) ? e.prices.slice(0, 16) : []) {
    const cls = text(p?.class, 24), isk = num(p?.isk), unit = UNITS.includes(p?.unit) ? p.unit : null;
    if (!/^[a-z0-9_]{1,24}$/.test(cls) || !Number.isFinite(isk) || isk < 0 || isk > 1e6 || !unit) return { error: `${where}: un prezzo non è valido (class, isk, unit: ${UNITS.join("/")})` };
    out.prices.push({ class: cls, isk: Math.round(isk * 100) / 100, unit });
  }
  const pay = https(e.pay_url);
  if (pay) out.pay_url = pay;
  const methods = (Array.isArray(e.pay_methods) ? e.pay_methods : []).filter((m) => METHODS.includes(m));
  if (methods.length) out.pay_methods = [...new Set(methods)];
  const app = text(e.app_name, 40);
  if (app) out.app_name = app;
  for (const key of ["window_before_h", "window_after_h"]) {
    const h = num(e[key]);
    if (Number.isFinite(h) && h > 0 && h <= 24 * 30) out[key] = Math.round(h);
  }
  if (typeof e.since === "string" && /^\d{4}-\d{2}-\d{2}$/.test(e.since)) out.since = e.since;
  if (typeof e.until === "string" && /^\d{4}-\d{2}-\d{2}$/.test(e.until)) out.until = e.until;

  out.texts = {};
  for (const lang of LANGS) {
    const t = e.texts?.[lang];
    if (!t) continue;
    const kept = {};
    for (const f of TEXT_FIELDS) if (text(t[f], 800)) kept[f] = text(t[f], 800);
    if (Object.keys(kept).length) out.texts[lang] = kept;
  }
  if (!out.texts.it && !out.texts.en) return { error: `${where}: serve almeno il testo in italiano o in inglese (texts.it.summary)` };

  out.sources = [];
  for (const s of Array.isArray(e.sources) ? e.sources.slice(0, 6) : []) {
    const url = https(s?.url);
    if (url) out.sources.push({ name: text(s.name, 160) || url, url });
  }
  if (!out.sources.length) delete out.sources;
  return { entry: out };
}

/** The whole catalog: { entries } or { error } with the first problem found. */
export function sanitizeTolls(list) {
  if (!Array.isArray(list)) return { error: "Il catalogo deve essere un elenco di voci" };
  if (list.length > 200) return { error: "Troppe voci (massimo 200)" };
  const entries = [];
  const ids = new Set();
  for (const [i, e] of list.entries()) {
    const r = sanitizeEntry(e, i);
    if (r.error) return { error: r.error };
    if (ids.has(r.entry.id)) return { error: `Voce ${i + 1}: l'id "${r.entry.id}" è già usato` };
    ids.add(r.entry.id);
    entries.push(r.entry);
  }
  return { entries };
}

/** The catalog as saved from the panel, or the first edition. */
export async function readTolls() {
  if (memory && Date.now() - memory.at < 30e3) return memory.value;
  const stored = await readObject(PATH).catch(() => null);
  let value;
  if (stored?.entries) value = { entries: stored.entries, updated_at: stored.updated_at || null, edited: true };
  else value = { entries: sanitizeTolls(TOLLS_SEED).entries, updated_at: null, edited: false };
  memory = { at: Date.now(), value };
  return value;
}

export async function writeTolls(list) {
  const r = sanitizeTolls(list);
  if (r.error) return r;
  const value = { entries: r.entries, updated_at: new Date().toISOString() };
  await writeObject(PATH, value);
  memory = { at: Date.now(), value: { ...value, edited: true } };
  return { entries: value.entries, updated_at: value.updated_at };
}

/** Back to the first edition (the panel's "restore"). */
export async function resetTolls() {
  return writeTolls(TOLLS_SEED);
}

export function publicTolls(catalog, reports = {}) {
  return { version: 1, updated_at: catalog.updated_at, entries: catalog.entries, reports };
}

// MARK: Prices reported by travellers
//
// Anyone using the app can say what they paid (no account: one report per
// toll, per day, per phone and network, kept 120 days). The app shows them
// next to the official price ("3 people reported 1,200 ISK") and warns when
// most recent reports disagree with it. They never replace the official
// price in the catalog: the admin panel lists them, to check and correct.

export const CLASSES = ["under_3_5t", "t3_5_7_5", "over_7_5t", "motorcycle", "car_5", "car_6_9", "bus_10_19", "bus_10_21", "bus_20_32", "bus_22_32", "bus_33"];
const REPORTS = "toll-reports/";
const REPORT_DAYS = 120;
const recentBySender = new Map(); // per instance: at most 10 reports an hour from the same sender
let reportsCache = null;

const ipOf = (req) => String(req.headers?.["x-forwarded-for"] || req.socket?.remoteAddress || "").split(",")[0].trim();

/** What a report must be: an existing toll or car park, a known class, a believable amount. */
export function checkReport(body, entries) {
  const entry = entries.find((e) => e.id === body?.entry);
  if (!entry || entry.type === "info") return { error: "Pedaggio o parcheggio sconosciuto", code: "unknown" };
  const cls = String(body.class || "");
  if (!CLASSES.includes(cls)) return { error: "Tipo di veicolo non valido", code: "class" };
  const isk = Math.round(num(body.isk));
  if (!Number.isFinite(isk) || isk < 50 || isk > 100000) return { error: "Importo non valido (in corone, tra 50 e 100.000)", code: "amount" };
  const official = entry.prices?.find((p) => p.class === cls)?.isk;
  // Far from the official price for that class: a typo or a joke, not a change.
  if (official && (isk > official * 4 || isk < official / 4)) return { error: "L'importo è troppo lontano dal prezzo ufficiale: controlla di aver scritto le corone", code: "far" };
  return { entry, cls, isk };
}

export async function submitReport(req, body) {
  const catalog = await readTolls();
  const r = checkReport(body, catalog.entries);
  if (r.error) return { status: 400, body: { error: r.error, code: r.code } };
  const client = typeof body.client === "string" ? body.client.slice(0, 64) : "";
  const sender = hmac(`${ipOf(req)}|${client}`, "toll-report").slice(0, 16);
  const now = Date.now();
  const recent = (recentBySender.get(sender) || []).filter((t) => now - t < 3600e3);
  if (recent.length >= 10) return { status: 429, body: { error: "Troppe segnalazioni: riprova più tardi", code: "rate" } };
  recentBySender.set(sender, [...recent, now]);
  const day = new Date(now).toISOString().slice(0, 10);
  // The same sender, toll and day: the last report replaces the earlier one.
  await writeObject(`${REPORTS}${r.entry.id}/${day}-${sender}.bin`, { t: new Date(now).toISOString(), class: r.cls, isk: r.isk }, { ttl: REPORT_DAYS * 86400 });
  reportsCache = null;
  return { status: 200, body: { ok: true } };
}

/** Every stored report of the last REPORT_DAYS days: [{ key, entry, day, t, class, isk }]. */
export async function listReports(entryID) {
  const objects = await listObjects(entryID ? `${REPORTS}${entryID}/` : REPORTS, { limit: 3000 });
  const oldest = new Date(Date.now() - REPORT_DAYS * 864e5).toISOString().slice(0, 10);
  const fresh = objects.filter((o) => (o.pathname.split("/")[2] || "").slice(0, 10) >= oldest);
  const old = objects.filter((o) => !fresh.includes(o));
  if (old.length) deleteObjects(old).catch(() => {});
  const out = [];
  for (let i = 0; i < fresh.length; i += 50) {
    const batch = await Promise.all(fresh.slice(i, i + 50).map(async (o) => {
      const v = await readObject(o.pathname).catch(() => null);
      const [, entry, file] = o.pathname.split("/");
      return v ? { key: o.pathname, entry, day: file.slice(0, 10), t: v.t, class: v.class, isk: v.isk } : null;
    }));
    out.push(...batch.filter(Boolean));
  }
  return out.sort((a, b) => String(b.t).localeCompare(String(a.t)));
}

/** Per toll: [{ class, isk, count, last }], most reported first. */
export function aggregateReports(list) {
  const out = {};
  for (const r of list) {
    const groups = (out[r.entry] ||= []);
    let g = groups.find((x) => x.class === r.class && x.isk === r.isk);
    if (!g) groups.push((g = { class: r.class, isk: r.isk, count: 0, last: r.t }));
    g.count += 1;
    if (String(r.t) > String(g.last)) g.last = r.t;
  }
  for (const groups of Object.values(out)) groups.sort((a, b) => b.count - a.count || String(b.last).localeCompare(String(a.last)));
  return out;
}

async function reportsSummary() {
  if (reportsCache && Date.now() - reportsCache.at < 5 * 60e3) return reportsCache.value;
  const value = aggregateReports(await listReports());
  reportsCache = { at: Date.now(), value };
  return value;
}

export async function deleteReport(key) {
  if (!/^toll-reports\/[a-z0-9_-]{2,40}\/\d{4}-\d{2}-\d{2}-[0-9a-f]{16}\.bin$/.test(String(key || ""))) return { error: "Chiave non valida" };
  await deleteObjects(await listObjects(key, { limit: 1 }));
  reportsCache = null;
  return { ok: true };
}

export async function tollsHandler(req, res, send) {
  if (req.method === "POST") {
    const body = await readJSON(req).catch(() => ({}));
    const r = await submitReport(req, body).catch(() => ({ status: 500, body: { error: "Errore del server" } }));
    res.setHeader("Cache-Control", "no-store");
    return send(res, r.status, r.body);
  }
  const catalog = await readTolls().catch(() => ({ entries: sanitizeTolls(TOLLS_SEED).entries, updated_at: null }));
  const reports = await reportsSummary().catch(() => ({}));
  // A price corrected in the panel, or a new report, reaches the phones within minutes.
  res.setHeader("Cache-Control", "public, s-maxage=300, stale-while-revalidate=86400");
  return send(res, 200, publicTolls(catalog, reports));
}
