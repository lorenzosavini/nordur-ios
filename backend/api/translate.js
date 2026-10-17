// POST /api/translate  { to: "it" | "en", texts: [string] }  ->  { translations: [string] }
//
// Text that the app shows from the web (IMO warnings, SafeTravel notices,
// Vegagerðin road news and hazards, Herjólfur notices, NOAA alerts) in the
// language of the interface. Translated by Claude with a brief on Icelandic
// weather, roads and space weather; every result is cached (memory + Blob,
// encrypted) so a text is translated once for everyone.
// Needs ANTHROPIC_API_KEY; without it the endpoint answers 503 and the app
// keeps the original text.
import crypto from "node:crypto";
import { readObject, writeObject, readJSON, send } from "../lib/core.js";

const MODEL = process.env.TRANSLATE_MODEL || "claude-sonnet-5-5";
const MAX_TEXTS = 25, MAX_CHARS = 12000, MAX_TEXT = 4000;
const memory = new Map(); // `${to}:${sha}` -> translation
const perClient = new Map(); // ip -> { minute, count }

const LANG = { it: "Italian", en: "English" };

export function systemPrompt(to) {
  const lang = LANG[to];
  return `You translate short texts for Norður, an iPhone app for travellers in Iceland, into ${lang}.
The texts come from official sources: the Icelandic Met Office (weather warnings), SafeTravel.is (travel notices),
Vegagerðin / umferdin.is (road conditions, closures, roadworks, weight limits), the Herjólfur ferry, NOAA SWPC (space weather alerts).
They can be in English, Icelandic or ${lang} already.

Write as a careful native ${lang} editor would for an official notice: correct grammar, natural phrasing, no calques, no added or removed information.
${to === "it" ? `Italian conventions: "allerta gialla/arancione/rossa" for IMO warning colours; "raffiche" for gusts; "strada impraticabile", "tratti ghiacciati", "strada scivolosa", "neve sulla carreggiata", "lavori stradali", "limite di peso per asse"; "tempesta geomagnetica" (G1–G5), "indice K"; times stay in 24-hour form; keep m/s, km/h, °C, mm.` : `British English spelling; keep the official English wording used by the Icelandic Met Office and NOAA where the source already is English.`}
Never translate proper names: Icelandic place names, mountain passes, road names and numbers (e.g. "Hellisheiði", "road 1", "F35"), region names, organisation names, ship names. Keep numbers, units, dates, times, URLs and phone numbers exactly.
If a text is already in ${lang}, return it unchanged.
Answer with JSON only: {"translations": [...]} with exactly one string per input text, in the same order.`;
}

const sha = (to, text) => crypto.createHash("sha1").update(`${to}\n${text}`).digest("hex");

async function claude(to, texts) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": process.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8000,
      system: systemPrompt(to),
      messages: [{ role: "user", content: JSON.stringify({ texts }) }],
    }),
    signal: AbortSignal.timeout(40000),
  });
  if (!res.ok) throw new Error(`Anthropic ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const json = await res.json();
  return parseTranslations(json.content?.map((c) => c.text || "").join("") || "", texts.length);
}

/** The JSON object in the model's answer (tolerates a code fence). */
export function parseTranslations(answer, count) {
  const start = answer.indexOf("{"), end = answer.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error("no JSON in answer");
  const out = JSON.parse(answer.slice(start, end + 1)).translations;
  if (!Array.isArray(out) || out.length !== count || out.some((t) => typeof t !== "string")) throw new Error("bad translations");
  return out;
}

export default async function handler(req, res) {
  if (req.method !== "POST") return send(res, 405, { error: "method" });
  const body = await readJSON(req).catch(() => ({}));
  const to = body.to === "en" ? "en" : body.to === "it" ? "it" : null;
  const texts = Array.isArray(body.texts) ? body.texts : null;
  if (!to || !texts || !texts.length || texts.length > MAX_TEXTS || texts.some((t) => typeof t !== "string" || t.length > MAX_TEXT)
      || texts.reduce((n, t) => n + t.length, 0) > MAX_CHARS) {
    return send(res, 400, { error: "Richiesta non valida" });
  }

  const out = new Array(texts.length).fill(null);
  const missing = [];
  await Promise.all(texts.map(async (text, i) => {
    const key = `${to}:${sha(to, text)}`;
    let hit = memory.get(key);
    if (hit == null) {
      const stored = await readObject(`translations/${to}/${sha(to, text)}.bin`).catch(() => null);
      if (stored?.t) { hit = stored.t; memory.set(key, hit); }
    }
    if (hit != null) out[i] = hit; else missing.push(i);
  }));

  if (missing.length) {
    if (!process.env.ANTHROPIC_API_KEY) return send(res, 503, { error: "Traduzione non configurata" });
    // A light limit per client: translations are cached, so normal use stays far below it.
    const ip = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "?";
    const minute = Math.floor(Date.now() / 60e3);
    const c = perClient.get(ip);
    const count = c && c.minute === minute ? c.count + missing.length : missing.length;
    perClient.set(ip, { minute, count });
    if (count > 200) return send(res, 429, { error: "Troppe richieste" });

    let translated;
    try {
      translated = await claude(to, missing.map((i) => texts[i]));
    } catch (e) {
      console.error("translate", e.message);
      return send(res, 502, { error: "Traduzione non disponibile" });
    }
    await Promise.all(missing.map(async (i, j) => {
      const t = translated[j];
      out[i] = t;
      memory.set(`${to}:${sha(to, texts[i])}`, t);
      await writeObject(`translations/${to}/${sha(to, texts[i])}.bin`, { t }).catch((e) => console.error("translate cache", e.message));
    }));
  }
  if (memory.size > 20000) memory.clear();
  return send(res, 200, { translations: out });
}
