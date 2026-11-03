// GET /api/volcanoes -> the state of Iceland's volcanoes, from Veðurstofa Íslands
// (api.vedur.is/volcanoes, public):
//   - aviation colour code (VONA) and IMO alert level (VALS) of every volcano;
//   - the latest weekly report (one line per volcano with activity, and notes).
// The weekly reports come as one 1 MB list: fetched here every 30 minutes and
// sent to the phones slimmed to ~10 KB. Last good copy kept in storage.
import { fetchWithRetry } from "./fetch.js";
import { readObject, writeObject } from "./core.js";

const BASE = "https://api.vedur.is/volcanoes";
const TTL = 30 * 60e3;
const CACHE = "public/volcanoes.bin";
let memory = null; // { at, body }

/** Iceland's volcanoes with their current codes, from the raw `/volcanoes` list. */
export function slimVolcanoes(raw) {
  return (Array.isArray(raw) ? raw : []).flatMap((v) => {
    const c = v?.geom_point?.coordinates;
    if (v?.country?.iso_code !== "IS" || !Array.isArray(c) || c.length < 2) return [];
    const vona = v.vona?.current, vals = v.vals?.current;
    return [{
      code: v.code, name: v.name, lat: c[1], lon: c[0], height: v.height ?? null, zone: v.zone?.name_en ?? null,
      aviation: vona?.aviation_color?.code ?? null, aviationSince: vona?.published_at ?? null,
      aviationText: vona?.aviation_color?.description_en ?? null,
      level: vals?.alert_level_info?.level ?? null, levelSince: vals?.published_at ?? null,
      levelText: vals?.alert_level_info?.description_en ?? null,
    }];
  });
}

/** The latest weekly report: { date, notes, lines: { code: text } }. */
export function latestWeekly(list) {
  if (!Array.isArray(list) || !list.length) return null;
  const last = list.reduce((a, b) => ((b?.id ?? 0) > (a?.id ?? 0) ? b : a));
  const lines = {};
  for (const e of last.entries || []) {
    const t = (e?.status_text || "").trim();
    if (e?.volcano_code && t) lines[e.volcano_code] = t;
  }
  const notes = (last.additional_notes || "").trim();
  return { date: last.published_at || null, notes: notes || null, lines };
}

export function combine(volcanoes, weekly) {
  return {
    volcanoes: volcanoes.map((v) => ({ ...v, report: weekly?.lines?.[v.code] ?? null })),
    reportDate: weekly?.date ?? null,
    reportNotes: weekly?.notes ?? null,
    updated: new Date().toISOString(),
  };
}

async function load() {
  const [v, w] = await Promise.all([
    fetchWithRetry(`${BASE}/volcanoes`, { timeout: 20000, retries: 1 }).then((r) => r.json()),
    fetchWithRetry(`${BASE}/vwr`, { timeout: 30000, retries: 1 }).then((r) => r.json()).catch(() => null),
  ]);
  const volcanoes = slimVolcanoes(v);
  if (!volcanoes.length) throw new Error("api.vedur.is: nessun vulcano");
  return combine(volcanoes, latestWeekly(w));
}

export async function volcanoesHandler(res, send) {
  if (!memory || Date.now() - memory.at > TTL) {
    try {
      memory = { at: Date.now(), body: await load() };
      await writeObject(CACHE, memory, { ttl: 7 * 86400 }).catch((e) => console.error("volcanoes cache", e.message));
    } catch (e) {
      console.error("volcanoes", e.message);
      const stored = memory || (await readObject(CACHE).catch(() => null));
      if (!stored) return send(res, 502, { error: "Veðurstofa Íslands non raggiungibile" });
      memory = stored;
      res.setHeader("Cache-Control", "public, s-maxage=120");
      return send(res, 200, stored.body);
    }
  }
  res.setHeader("Cache-Control", "public, s-maxage=900, stale-while-revalidate=3600");
  return send(res, 200, memory.body);
}
