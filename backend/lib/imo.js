// Veðurstofa Íslands for the server: what changed and when (the "stamps" the
// app follows to fetch again only what IMO actually published anew), and the
// station forecasts and 10-minute measurements used to correct the map grid.
//
// Sources (public, docs/IMO.md): xmlweather.vedur.is (station forecasts,
// hourly observations, written forecasts) and api.vedur.is/weather (10-minute
// measurements of the automatic stations). IMO asks not to poll often: the
// stamps cost four small requests at most once a minute for all users, the
// full station forecasts are downloaded only when a new issue is out.
import crypto from "node:crypto";
import { readFileSync } from "node:fs";
import { fetchWithRetry } from "./fetch.js";

export const STATIONS = JSON.parse(readFileSync(new URL("./imo-stations.json", import.meta.url)));
const XML = "https://xmlweather.vedur.is/";
const AWS = "https://api.vedur.is/weather/observations/aws/10min/latest";
/** Text forecasts the app shows (lib mirrors IMOTexts.ids in the app). */
export const TEXT_IDS = [2, 3, 5, 6, 7, 9, 27, 42, ...Array.from({ length: 10 }, (_, i) => 30 + i), ...Array.from({ length: 9 }, (_, i) => 51 + i)];

const DIRS = { N: 0, NNE: 22.5, NE: 45, ENE: 67.5, E: 90, ESE: 112.5, SE: 135, SSE: 157.5, S: 180, SSW: 202.5, SW: 225, WSW: 247.5, W: 270, WNW: 292.5, NW: 315, NNW: 337.5 };
export const degrees = (d) => (d == null ? null : DIRS[String(d).trim().toUpperCase()] ?? null);

/** "2026-11-03 15:00:00" (Iceland = UTC) to epoch seconds. */
export function imoTime(s) {
  if (!s) return null;
  const t = Date.parse(String(s).trim().replace(" ", "T") + "Z");
  return Number.isFinite(t) ? Math.round(t / 1000) : null;
}

const num = (s) => {
  if (s == null || s === "") return null;
  const v = Number(String(s).replace(",", "."));
  return Number.isFinite(v) ? v : null;
};
const tag = (name, text) => {
  const m = text.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`));
  return m ? m[1].replace(/^<!\[CDATA\[|\]\]>$/g, "").trim() : null;
};

/** Station forecasts: [{ id, issued, steps: [{ t, F, D, T, N, R, hours }] }] (R per hour). */
export function parseForecasts(xml) {
  const out = [];
  for (const m of String(xml).matchAll(/<station id="(\d+)"\s*valid="(\d)">([\s\S]*?)<\/station>/g)) {
    if (m[2] !== "1") continue;
    const body = m[3];
    const steps = [];
    let previous = null;
    for (const f of body.matchAll(/<forecast>([\s\S]*?)<\/forecast>/g)) {
      const t = imoTime(tag("ftime", f[1]));
      if (t == null) continue;
      const hours = previous == null ? 1 : Math.max(1, Math.round((t - previous) / 3600));
      const R = num(tag("R", f[1]));
      steps.push({ t, F: num(tag("F", f[1])), D: degrees(tag("D", f[1])), T: num(tag("T", f[1])), N: num(tag("N", f[1])),
                   R: R == null ? null : R / hours, hours });
      previous = t;
    }
    out.push({ id: Number(m[1]), issued: imoTime(tag("atime", body)), steps });
  }
  return out;
}

/** 10-minute measurements: Map(id -> { t, F, FG, D, T }). */
export function parseAWS(list) {
  const out = new Map();
  for (const r of Array.isArray(list) ? list : []) {
    const t = Date.parse(String(r?.time || "").slice(0, 19) + "Z");
    if (!Number.isFinite(t) || r.station == null) continue;
    out.set(Number(r.station), { t: Math.round(t / 1000), F: num(r.f), FG: num(r.fg), D: num(r.d), T: num(r.t) });
  }
  return out;
}

async function text(url, timeout = 20000) {
  const res = await fetchWithRetry(url, { timeout, retries: 1, accept: "*/*" });
  return res.text();
}

const xmlURL = (q) => `${XML}?${new URLSearchParams({ op_w: "xml", lang: "en", view: "xml", ...q })}`;

/**
 * What IMO has published last: issue time of the station forecasts, time of the
 * latest hourly observation and 10-minute measurement, and a fingerprint of the
 * written forecasts. Each part independent: a failing one is null.
 */
export async function fetchStamps() {
  const [forecast, hourly, ten, texts] = await Promise.allSettled([
    text(xmlURL({ type: "forec", ids: "1", params: "T" })).then((x) => tag("atime", x)),
    text(xmlURL({ type: "obs", ids: "1;1475", params: "T", time: "1h", anytime: "1" })).then((x) =>
      [...x.matchAll(/<time>([^<]*)<\/time>/g)].map((m) => m[1]).sort().pop() || null),
    text(`${AWS}?station_id=1350&station_id=1361&station_id=1475`).then((x) =>
      JSON.parse(x).map((r) => r.time).sort().pop() || null),
    text(xmlURL({ type: "txt", ids: TEXT_IDS.join(";") })).then((x) => {
      const created = [...x.matchAll(/<text id="(\d+)">[\s\S]*?<creation>([^<]*)<\/creation>/g)].map((m) => `${m[1]}@${m[2]}`).join(",");
      return created ? crypto.createHash("sha1").update(created).digest("hex").slice(0, 12) : null;
    }),
  ]);
  const v = (r) => (r.status === "fulfilled" ? r.value : null);
  return { forecast: v(forecast), obsHour: v(hourly), obs10: v(ten), texts: v(texts) };
}

/** Every station's forecast (40 stations to a request). */
export async function fetchAllForecasts() {
  const ids = STATIONS.map((s) => s.id);
  const out = new Map();
  for (let i = 0; i < ids.length; i += 40) {
    const xml = await text(xmlURL({ type: "forec", ids: ids.slice(i, i + 40).join(";"), params: "F;D;T;N;R" }), 30000);
    for (const f of parseForecasts(xml)) out.set(f.id, f);
  }
  return out;
}

/** The latest 10-minute measurement of every automatic station (one request). */
export async function fetchAllAWS() {
  return parseAWS(JSON.parse(await text(AWS, 30000)));
}
