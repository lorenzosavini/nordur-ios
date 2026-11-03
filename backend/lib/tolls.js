// Tolls, toll tunnels and paid parking: a small curated catalog the app shows
// (GET /api/tolls, kept on the phone for use offline) and the owner edits in
// the admin panel without a new version of the app. Until the panel saves its
// own copy, the first edition in tolls-data.js is served.
//
// Every entry carries its official source and the day it was checked: the app
// always shows "checked on <date>" and "indicative prices, check the official site".
import { readObject, writeObject } from "./core.js";
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

export function publicTolls(catalog) {
  return { version: 1, updated_at: catalog.updated_at, entries: catalog.entries };
}

export async function tollsHandler(res, send) {
  const catalog = await readTolls().catch(() => ({ entries: sanitizeTolls(TOLLS_SEED).entries, updated_at: null }));
  // A price corrected in the panel reaches the phones within minutes.
  res.setHeader("Cache-Control", "public, s-maxage=300, stale-while-revalidate=86400");
  return send(res, 200, publicTolls(catalog));
}
