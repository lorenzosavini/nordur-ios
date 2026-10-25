// What the app sells and how: every feature that can be free, Pro or switched
// off, the App Store products that unlock Pro, the app's builds sold at a price
// (their buyers keep everything), and the notice shown in the app.
//
// Safety stays free and cannot be listed here: weather and road warnings,
// closures, earthquakes, SOS and the alerts about them.
import { readObject, writeObject } from "./core.js";

/** Keys must match `Feature` in the app (Nordur/State/Entitlements.swift). */
export const FEATURES = [
  { key: "aurora.alerts", label: "Notifiche aurora", group: "Aurora" },
  { key: "aurora.finder", label: "Bussola dell'aurora (dove guardare)", group: "Aurora" },
  { key: "aurora.live", label: "Mappa dell'ovale e avvistamenti", group: "Aurora" },
  { key: "aurora.report", label: "Inviare avvistamenti", group: "Aurora" },
  { key: "weather.map", label: "Mappa meteo a strati", group: "Meteo e strade" },
  { key: "webcams", label: "Webcam stradali", group: "Meteo e strade" },
  { key: "trip.planner", label: "Pianificatore di viaggio", group: "Viaggio" },
  { key: "trip.shared", label: "Viaggi condivisi e di gruppo", group: "Viaggio" },
  { key: "trip.files", label: "Import ed export GPX / KML", group: "Viaggio" },
  { key: "drive.record", label: "Registrazione dei percorsi in auto", group: "In auto" },
  { key: "drive.flight3d", label: "Volo 3D e video del percorso", group: "In auto" },
  { key: "drive.health", label: "Import da Apple Salute / Garmin", group: "In auto" },
  { key: "offline", label: "Pacchetto offline", group: "App" },
  { key: "backup", label: "Backup sul cloud e nuovo iPhone", group: "App" },
  { key: "currency.converter", label: "Convertitore valute", group: "App" },
];
const KEYS = new Set(FEATURES.map((f) => f.key));
const RULES = new Set(["free", "pro", "off"]);
const LANGS = ["it", "en", "de", "fr", "es"];

/** Everything free, no products: the app behaves as before until the admin decides. */
export const DEFAULT_CONFIG = {
  mode: "free",            // "free": everything open (also for an app sold at a price) · "freemium": the rules below
  features: {},            // key -> "free" | "pro" | "off" (missing = free)
  products: [],            // App Store product IDs that unlock Pro, in the order shown
  paidThroughBuild: null,  // buyers of a paid version up to this build keep Pro forever
  paywall: {},             // lang -> { title, text } shown above the products
  announcement: null,      // { id, level, from, until, url, texts: { lang: { title, text } } }
  updatedAt: null,
};

const PATH = "config/app.bin";
let memory = null;

export async function readConfig() {
  if (memory && Date.now() - memory.at < 30e3) return memory.value;
  const stored = await readObject(PATH).catch(() => null);
  const value = { ...DEFAULT_CONFIG, ...(stored || {}) };
  memory = { at: Date.now(), value };
  return value;
}

const text = (v, max) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const date = (v) => (v && !Number.isNaN(Date.parse(v)) ? new Date(v).toISOString() : null);

/** Keeps only what the app understands, so a typo in the panel can't break it. */
export function sanitize(input) {
  const out = { ...DEFAULT_CONFIG };
  out.mode = input?.mode === "freemium" ? "freemium" : "free";
  for (const [k, v] of Object.entries(input?.features || {})) if (KEYS.has(k) && RULES.has(v)) out.features[k] = v;
  out.products = [...new Set((input?.products || []).map((p) => text(p, 120)).filter((p) => /^[A-Za-z0-9._-]+$/.test(p)))].slice(0, 6);
  const build = Number(input?.paidThroughBuild);
  out.paidThroughBuild = Number.isInteger(build) && build > 0 ? build : null;
  out.paywall = {};
  for (const l of LANGS) {
    const p = input?.paywall?.[l];
    if (p && (text(p.title, 80) || text(p.text, 600))) out.paywall[l] = { title: text(p.title, 80), text: text(p.text, 600) };
  }
  const a = input?.announcement;
  if (a && Object.values(a.texts || {}).some((t) => text(t?.title, 120))) {
    const texts = {};
    for (const l of LANGS) if (text(a.texts?.[l]?.title, 120)) texts[l] = { title: text(a.texts[l].title, 120), text: text(a.texts[l].text, 600) };
    out.announcement = {
      id: text(a.id, 40) || `a${Date.now().toString(36)}`,
      level: ["info", "warning", "danger"].includes(a.level) ? a.level : "info",
      from: date(a.from), until: date(a.until),
      url: /^https:\/\//.test(a.url || "") ? text(a.url, 300) : null,
      texts,
    };
  }
  return out;
}

export async function writeConfig(input) {
  const value = { ...sanitize(input), updatedAt: new Date().toISOString() };
  await writeObject(PATH, value);
  memory = { at: Date.now(), value };
  return value;
}

/** What the app downloads (public, cached by the CDN for a few minutes). */
export function publicConfig(config) {
  const { mode, features, products, paidThroughBuild, paywall, announcement, updatedAt } = config;
  const now = Date.now();
  const live = announcement && (!announcement.from || Date.parse(announcement.from) <= now) && (!announcement.until || Date.parse(announcement.until) > now);
  return { mode, features, products, paidThroughBuild, paywall, announcement: live ? announcement : null, updatedAt };
}
