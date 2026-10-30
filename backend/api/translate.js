// POST /api/translate  { to: "it" | "en" | "de" | "fr" | "es", texts: [string] }  ->  { translations: [string] }
//
// Text that the app shows from the web (IMO warnings, SafeTravel notices,
// Vegagerðin road news and hazards, Herjólfur notices, NOAA alerts) in the
// language of the interface. Translated by Claude with a brief on Icelandic
// weather, roads and space weather; every result is cached (memory + Blob,
// encrypted) so a text is translated once for everyone.
// With ANTHROPIC_API_KEY: Claude. Without it (or when it fails): MyMemory, a
// free machine translator with a daily allowance, kept 7 days only so that
// Claude's translations replace them once the key is set.
import crypto from "node:crypto";
import { readObject, writeObject, readJSON, send } from "../lib/core.js";

const MODEL = process.env.TRANSLATE_MODEL || "claude-sonnet-5-5";
const MAX_TEXTS = 25, MAX_CHARS = 12000, MAX_TEXT = 4000;
const memory = new Map(); // `${to}:${sha}` -> translation
const perClient = new Map(); // ip -> { minute, count }

const LANG = { it: "Italian", en: "English", de: "German", fr: "French", es: "Spanish" };

const CONVENTIONS = {
  it: `Italian conventions: "allerta gialla/arancione/rossa" for IMO warning colours; "raffiche" for gusts; "strada impraticabile", "tratti ghiacciati", "strada scivolosa", "neve sulla carreggiata", "lavori stradali", "limite di peso per asse"; "tempesta geomagnetica" (G1–G5), "indice K"; times stay in 24-hour form; keep m/s, km/h, °C, mm.`,
  en: `British English spelling; keep the official English wording used by the Icelandic Met Office and NOAA where the source already is English.`,
  de: `German conventions: "gelbe/orange/rote Warnung" for IMO warning colours; "Böen" for gusts; "Straße unpassierbar", "glatte Abschnitte", "Schnee auf der Fahrbahn", "Bauarbeiten", "Achslastbeschränkung"; "geomagnetischer Sturm" (G1–G5), "K-Index"; times stay in 24-hour form; keep m/s, km/h, °C, mm.`,
  fr: `French conventions: "vigilance jaune/orange/rouge" for IMO warning colours; "rafales" for gusts; "route impraticable", "plaques de verglas", "neige sur la chaussée", "travaux", "limitation de charge par essieu"; "tempête géomagnétique" (G1–G5), "indice K"; times stay in 24-hour form; keep m/s, km/h, °C, mm.`,
  es: `Spanish conventions: "aviso amarillo/naranja/rojo" for IMO warning colours; "rachas" for gusts; "carretera intransitable", "tramos helados", "nieve en la calzada", "obras", "limitación de peso por eje"; "tormenta geomagnética" (G1–G5), "índice K"; times stay in 24-hour form; keep m/s, km/h, °C, mm.`,
};

export function systemPrompt(to) {
  const lang = LANG[to];
  return `You translate short texts for Norður, an iPhone app for travellers in Iceland, into ${lang}.
The texts come from official sources: the Icelandic Met Office (weather warnings), SafeTravel.is (travel notices),
Vegagerðin / umferdin.is (road conditions, closures, roadworks, weight limits), the Herjólfur ferry, NOAA SWPC (space weather alerts).
They can be in English, Icelandic or ${lang} already.

Write as a careful native ${lang} editor would for an official notice: correct grammar, natural phrasing, no calques, no added or removed information.
${CONVENTIONS[to]}
Never translate proper names: Icelandic place names, mountain passes, road names and numbers (e.g. "Hellisheiði", "road 1", "F35"), region names, organisation names, ship names. Keep numbers, units, dates, times, URLs and phone numbers exactly.
If a text is already in ${lang}, return it unchanged.
Answer with JSON only: {"translations": [...]} with exactly one string per input text, in the same order.`;
}

const sha = (to, text) => crypto.createHash("sha1").update(`${to}\n${text}`).digest("hex");

/** Texts translated now (no cache), for the admin panel's notices. */
export async function translateTexts(to, texts) {
  if (process.env.ANTHROPIC_API_KEY) {
    try { return await claude(to, texts); } catch (e) { console.error("translate claude", e.message); }
  }
  const out = [];
  for (const t of texts) out.push(await freeTranslate(to, t));
  return out;
}

/** Pieces of at most ~450 characters, cut at sentence ends (MyMemory's limit is 500 bytes). */
export function chunks(text, size = 450) {
  const out = [];
  let rest = text;
  while (rest.length > size) {
    const window = rest.slice(0, size);
    const cut = Math.max(window.lastIndexOf(". "), window.lastIndexOf("\n"), window.lastIndexOf("; "), window.lastIndexOf(", "));
    const at = cut > size / 3 ? cut + 1 : (window.lastIndexOf(" ") > 0 ? window.lastIndexOf(" ") : size);
    out.push(rest.slice(0, at).trim());
    rest = rest.slice(at).trim();
  }
  if (rest) out.push(rest);
  return out;
}

/** MyMemory (free, no key): the language of the source is detected. */
async function freeTranslate(to, text) {
  const parts = [];
  for (const piece of chunks(text)) {
    const url = `https://api.mymemory.translated.net/get?${new URLSearchParams({ q: piece, langpair: `Autodetect|${to}` })}`;
    const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
    const json = await res.json().catch(() => null);
    if (!res.ok || !json || json.quotaFinished || json.responseStatus !== 200) throw new Error(`MyMemory ${json?.responseStatus || res.status}`);
    const detected = String(json.responseData?.detectedLanguage || "").slice(0, 2);
    parts.push(detected === to ? piece : String(json.responseData?.translatedText || piece));
  }
  return parts.join(" ");
}

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
  const to = Object.hasOwn(LANG, body.to) ? body.to : null;
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
      // A free translation gives way to Claude's as soon as the key is there.
      if (stored?.t && !(stored.free && process.env.ANTHROPIC_API_KEY)) { hit = stored.t; memory.set(key, hit); }
    }
    if (hit != null) out[i] = hit; else missing.push(i);
  }));

  if (missing.length) {
    // A light limit per client: translations are cached, so normal use stays far below it.
    const ip = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "?";
    const minute = Math.floor(Date.now() / 60e3);
    const c = perClient.get(ip);
    const count = c && c.minute === minute ? c.count + missing.length : missing.length;
    perClient.set(ip, { minute, count });
    if (count > 200) return send(res, 429, { error: "Troppe richieste" });

    let translated = null, free = false;
    if (process.env.ANTHROPIC_API_KEY) {
      try { translated = await claude(to, missing.map((i) => texts[i])); } catch (e) { console.error("translate", e.message); }
    }
    if (!translated) {
      // The free translator, one text at a time; what it cannot do keeps the original.
      free = true;
      translated = [];
      for (const i of missing) {
        try { translated.push(await freeTranslate(to, texts[i])); } catch (e) { console.error("translate free", e.message); translated.push(null); }
      }
      if (translated.every((t) => t == null)) return send(res, 502, { error: "Traduzione non disponibile" });
    }
    await Promise.all(missing.map(async (i, j) => {
      const t = translated[j];
      if (t == null) { out[i] = texts[i]; return; }
      out[i] = t;
      memory.set(`${to}:${sha(to, texts[i])}`, t);
      await writeObject(`translations/${to}/${sha(to, texts[i])}.bin`, free ? { t, free: true } : { t }, { ttl: (free ? 7 : 120) * 86400 })
        .catch((e) => console.error("translate cache", e.message));
    }));
  }
  if (memory.size > 20000) memory.clear();
  return send(res, 200, { translations: out });
}
