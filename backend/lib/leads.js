// Launch list for the landing page (public/index.html) and its admin panel
// (public/admin/). Served by api/data.js (?lead=… and ?admin=…): the Hobby plan
// allows 12 functions.
//
// Public
//   POST /api/data?lead=subscribe { email, name?, lang, interests[], travel?, consentPrivacy, consentUpdates, policyVersion, consentText, hp, elapsed }
//        -> { ok, status }   (sends the confirmation e-mail when a sender is configured)
//   GET  /api/data?lead=confirm&t=…       -> redirect to /?confirmed=1
//   GET  /api/data?lead=unsubscribe&t=…   -> redirect to /?unsubscribed=1 (consent withdrawn, data kept 30 days then erased)
//   POST /api/data?lead=forget { t }      -> { ok } (erases everything at once)
//   GET  /api/data?lead=status            -> { status, legal, mail, count }
// Admin (Bearer token of a Norður account whose e-mail is in ADMIN_EMAILS, header X-Admin-Email)
//   GET    ?admin=leads                   -> { leads, stats, mail }
//   GET    ?admin=export                  -> CSV with the consent records
//   DELETE ?admin=lead&id=…               -> { ok }
//   PUT    ?admin=status { status, legal } -> { ok }
//   POST   ?admin=send { subject, text, lang, test, offset, campaign } -> { sent, next, total, campaign }
//   POST   ?admin=reconfirm { offset }    -> confirmation e-mails to the leads still waiting
//   GET    ?admin=campaigns               -> { campaigns }
//
// Personal data is encrypted at rest (lib/core.js). Each lead keeps the
// consent records: what was accepted, the text and policy version shown, when,
// from which page, the IP shortened (last block removed) and the browser.
import crypto from "node:crypto";
import { readObject, writeObject, listObjects, deleteObjects, readJSON, send, hmac, verifyToken, userPath } from "./core.js";
import { sendMail, mailer } from "./mail.js";

const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const LANGS = ["it", "en", "de", "fr", "es"];
const INTERESTS = ["aurora", "weather", "roads", "trip", "drive", "other"];
const PREFIX = "leads/";
const STATUS = "site/status.bin";
const leadPath = (id) => `${PREFIX}${id}.bin`;
const leadId = (email) => hmac(email.trim().toLowerCase(), "lead").slice(0, 32);
// The API (links in the e-mails) and the site (where those links land), which
// can be on another host: SITE_URL, e.g. https://www.example.com
const API_URL = (process.env.API_URL || "https://nordur-api.vercel.app").replace(/\/$/, "");
const SITE = (process.env.SITE_URL || API_URL).replace(/\/$/, "");

const tokenFor = (id, purpose) => `${id}.${hmac(id, `lead-${purpose}`).slice(0, 24)}`;
function idFrom(token, purpose) {
  const [id, sig] = String(token || "").split(".");
  if (!id || !sig || !/^[0-9a-f]{32}$/.test(id)) return null;
  const expected = hmac(id, `lead-${purpose}`).slice(0, 24);
  return sig.length === expected.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected)) ? id : null;
}

/** IPv4 without the last block, IPv6 without the last 80 bits: enough as proof, not enough to point at a device. */
function shortIP(req) {
  const ip = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
  if (!ip) return null;
  if (ip.includes(".")) return ip.split(".").slice(0, 3).join(".") + ".0";
  return ip.split(":").slice(0, 3).join(":") + "::";
}

// A few sign-ups per address per hour, against scripts.
const hits = new Map();
function limited(req) {
  const key = shortIP(req) || "?";
  const hour = Math.floor(Date.now() / 3600e3);
  const h = hits.get(key);
  if (!h || h.hour !== hour) { hits.set(key, { hour, n: 1 }); return false; }
  h.n += 1;
  return h.n > 8;
}

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

// ——— E-mails ———

const MAIL = {
  it: {
    confirmSubject: "Norður: conferma l'iscrizione",
    confirm: ["Ciao{name},", "grazie per esserti iscritto agli aggiornamenti su Norður, l'app per viaggiare in Islanda: aurora, meteo, strade e viaggio.", "Per confermare che l'indirizzo è tuo e iniziare a ricevere le novità e l'avviso del lancio, apri il link qui sotto. Se non sei stato tu, ignora questa email: senza conferma non ti scriveremo più."],
    confirmButton: "Conferma l'iscrizione",
    footer: "Ricevi questa email perché ti sei iscritto su {site}. Non vuoi più riceverle? Cancellati qui: {unsub}",
  },
  en: {
    confirmSubject: "Norður: confirm your sign-up",
    confirm: ["Hi{name},", "thanks for signing up for updates on Norður, the app for travelling in Iceland: aurora, weather, roads and your trip.", "To confirm this address is yours and start receiving news and the launch notice, open the link below. If it wasn't you, ignore this e-mail: without confirmation we won't write again."],
    confirmButton: "Confirm sign-up",
    footer: "You receive this e-mail because you signed up on {site}. Don't want them any more? Unsubscribe here: {unsub}",
  },
  de: {
    confirmSubject: "Norður: Anmeldung bestätigen",
    confirm: ["Hallo{name},", "danke für deine Anmeldung zu den Neuigkeiten über Norður, die App für Reisen in Island: Polarlicht, Wetter, Straßen und Reise.", "Öffne den Link unten, um zu bestätigen, dass die Adresse dir gehört, und Neuigkeiten sowie die Nachricht zum Start zu erhalten. Warst du das nicht, ignoriere diese E-Mail: Ohne Bestätigung schreiben wir dir nicht mehr."],
    confirmButton: "Anmeldung bestätigen",
    footer: "Du erhältst diese E-Mail, weil du dich auf {site} angemeldet hast. Keine E-Mails mehr? Hier abmelden: {unsub}",
  },
  fr: {
    confirmSubject: "Norður : confirmez votre inscription",
    confirm: ["Bonjour{name},", "merci de vous être inscrit aux nouvelles de Norður, l'application pour voyager en Islande : aurores, météo, routes et voyage.", "Pour confirmer que cette adresse est la vôtre et recevoir les nouveautés et l'annonce du lancement, ouvrez le lien ci-dessous. Si ce n'était pas vous, ignorez cet e-mail : sans confirmation, nous ne vous écrirons plus."],
    confirmButton: "Confirmer l'inscription",
    footer: "Vous recevez cet e-mail car vous vous êtes inscrit sur {site}. Vous ne souhaitez plus en recevoir ? Désinscrivez-vous ici : {unsub}",
  },
  es: {
    confirmSubject: "Norður: confirma tu suscripción",
    confirm: ["Hola{name},", "gracias por suscribirte a las novedades de Norður, la app para viajar por Islandia: auroras, tiempo, carreteras y viaje.", "Para confirmar que la dirección es tuya y empezar a recibir novedades y el aviso del lanzamiento, abre el enlace de abajo. Si no has sido tú, ignora este correo: sin confirmación no volveremos a escribirte."],
    confirmButton: "Confirmar suscripción",
    footer: "Recibes este correo porque te suscribiste en {site}. ¿Ya no quieres recibirlos? Date de baja aquí: {unsub}",
  },
};

function mailLayout(paragraphs, button, footer) {
  const body = paragraphs.map((p) => `<p style="margin:0 0 14px;font-size:15px;line-height:1.55;color:#0a0a0a">${esc(p).replace(/\n/g, "<br>")}</p>`).join("");
  const cta = button ? `<p style="margin:8px 0 22px"><a href="${esc(button.href)}" style="display:inline-block;background:#f04a00;color:#fff;text-decoration:none;font:600 14px/1 -apple-system,Helvetica,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;padding:14px 20px">${esc(button.label)}</a></p>` : "";
  return `<!doctype html><html><body style="margin:0;background:#f4f4f2;font-family:-apple-system,Helvetica,Arial,sans-serif">
<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:28px 12px">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#fff;border-top:4px solid #0a0a0a">
<tr><td style="padding:26px 28px 6px;font:700 30px/1 'Arial Narrow',Arial,sans-serif;letter-spacing:.02em;text-transform:uppercase;color:#0a0a0a">Norður<span style="color:#00a37a">.</span></td></tr>
<tr><td style="padding:16px 28px 8px">${body}${cta}</td></tr>
<tr><td style="padding:14px 28px 24px;border-top:1px solid rgba(0,0,0,.13);font-size:12px;line-height:1.5;color:#4f4f4f">${esc(footer)}</td></tr>
</table></td></tr></table></body></html>`;
}

async function sendConfirmation(lead) {
  const m = MAIL[lead.lang] || MAIL.en;
  const href = `${API_URL}/api/data?lead=confirm&t=${tokenFor(lead.id, "confirm")}`;
  const unsub = `${API_URL}/api/data?lead=unsubscribe&t=${tokenFor(lead.id, "unsub")}`;
  const paragraphs = m.confirm.map((p) => p.replace("{name}", lead.name ? ` ${lead.name}` : ""));
  const footer = m.footer.replace("{site}", SITE.replace(/^https?:\/\//, "")).replace("{unsub}", unsub);
  return sendMail({
    to: lead.email, subject: m.confirmSubject,
    text: `${paragraphs.join("\n\n")}\n\n${m.confirmButton}: ${href}\n\n${footer}`,
    html: mailLayout(paragraphs, { href, label: m.confirmButton }, footer),
  });
}

async function sendUpdate(lead, subject, text) {
  const m = MAIL[lead.lang] || MAIL.en;
  const unsub = `${API_URL}/api/data?lead=unsubscribe&t=${tokenFor(lead.id, "unsub")}`;
  const footer = m.footer.replace("{site}", SITE.replace(/^https?:\/\//, "")).replace("{unsub}", unsub);
  const body = String(text).replace(/\{name\}/g, lead.name || "");
  return sendMail({
    to: lead.email, subject,
    text: `${body}\n\n—\n${footer}`,
    html: mailLayout(body.split(/\n{2,}/), null, footer),
  });
}

// ——— Public ———

async function loadStatus() {
  return (await readObject(STATUS).catch(() => null)) || {
    status: { phase: "beta", progress: 70, note: {}, items: [], updatedAt: null, showCount: false },
    legal: { controller: "", email: "", address: "", vat: "" },
  };
}

const legalReady = (legal) => Boolean(legal?.controller && legal?.email);

async function subscribe(req, res) {
  const b = await readJSON(req).catch(() => ({}));
  // Bots: a hidden field filled in, or the form sent within 2 s of opening the page.
  if (b.hp || (Number(b.elapsed) > 0 && Number(b.elapsed) < 2000)) return send(res, 200, { ok: true, status: "pending" });
  if (limited(req)) return send(res, 429, { error: "too_many" });
  const email = String(b.email || "").trim().toLowerCase();
  if (!EMAIL.test(email)) return send(res, 400, { error: "email" });
  if (b.consentPrivacy !== true || b.consentUpdates !== true) return send(res, 400, { error: "consent" });
  const { legal } = await loadStatus();
  if (!legalReady(legal)) return send(res, 503, { error: "not_ready" });

  const id = leadId(email);
  const now = new Date().toISOString();
  const lang = LANGS.includes(b.lang) ? b.lang : "en";
  const proof = { at: now, ip: shortIP(req), ua: String(req.headers["user-agent"] || "").slice(0, 300), source: String(req.headers.referer || "").slice(0, 300), version: String(b.policyVersion || "").slice(0, 40) };
  const existing = await readObject(leadPath(id)).catch(() => null);
  const lead = existing && existing.status !== "unsubscribed" ? existing : {
    id, email, createdAt: now, status: "pending", consents: existing?.consents || [], events: existing?.events || [],
  };
  lead.name = String(b.name || "").trim().slice(0, 60) || lead.name || "";
  lead.lang = lang;
  lead.interests = (Array.isArray(b.interests) ? b.interests : []).filter((x) => INTERESTS.includes(x));
  lead.travel = /^\d{4}-\d{2}$/.test(b.travel || "") ? b.travel : null;
  lead.consents.push(
    { type: "privacy", accepted: true, text: String(b.consentPrivacyText || "").slice(0, 600), ...proof },
    { type: "updates", accepted: true, text: String(b.consentText || "").slice(0, 600), ...proof },
  );
  lead.events.push({ t: existing ? "resubscribed" : "subscribed", at: now });
  if (existing?.status === "unsubscribed") { lead.status = "pending"; delete lead.unsubscribedAt; delete lead.eraseAfter; }
  if (lead.status === "pending" && mailer) {
    if (await sendConfirmation(lead)) { lead.events.push({ t: "confirmation_sent", at: now }); lead.lastMailAt = now; }
  }
  await writeObject(leadPath(id), lead);
  send(res, 200, { ok: true, status: lead.status, mail: Boolean(mailer) });
}

function redirect(res, to) {
  res.statusCode = 303;
  res.setHeader("Location", to);
  res.setHeader("Cache-Control", "no-store");
  res.end();
}

async function confirm(req, res, url) {
  const id = idFrom(url.searchParams.get("t"), "confirm");
  const lead = id && (await readObject(leadPath(id)).catch(() => null));
  if (!lead) return redirect(res, `${SITE}/?confirmed=0`);
  if (lead.status === "pending") {
    const now = new Date().toISOString();
    lead.status = "confirmed";
    lead.confirmedAt = now;
    lead.consents.push({ type: "double_opt_in", accepted: true, at: now, ip: shortIP(req), ua: String(req.headers["user-agent"] || "").slice(0, 300) });
    lead.events.push({ t: "confirmed", at: now });
    await writeObject(leadPath(id), lead);
  }
  redirect(res, `${SITE}/?confirmed=1&lang=${lead.lang}`);
}

async function unsubscribe(req, res, url) {
  const token = url.searchParams.get("t");
  const id = idFrom(token, "unsub");
  const lead = id && (await readObject(leadPath(id)).catch(() => null));
  if (!lead) return redirect(res, `${SITE}/?unsubscribed=0`);
  if (lead.status !== "unsubscribed") {
    const now = new Date().toISOString();
    lead.status = "unsubscribed";
    lead.unsubscribedAt = now;
    // Kept a little as proof of the withdrawal, then erased by the admin list.
    lead.eraseAfter = new Date(Date.now() + 30 * 864e5).toISOString();
    lead.consents.push({ type: "withdrawal", accepted: false, at: now, ip: shortIP(req) });
    lead.events.push({ t: "unsubscribed", at: now });
    await writeObject(leadPath(id), lead);
  }
  redirect(res, `${SITE}/?unsubscribed=1&lang=${lead.lang}&t=${encodeURIComponent(token)}`);
}

async function forget(req, res) {
  const b = await readJSON(req).catch(() => ({}));
  const id = idFrom(b.t, "unsub");
  if (!id) return send(res, 400, { error: "token" });
  await deleteObjects([{ pathname: leadPath(id), url: leadPath(id) }]).catch(() => {});
  send(res, 200, { ok: true });
}

async function publicStatus(res) {
  const { status, legal } = await loadStatus();
  let count = null;
  if (status.showCount) count = (await listObjects(PREFIX).catch(() => [])).length;
  res.setHeader("Cache-Control", "public, s-maxage=120, stale-while-revalidate=600");
  send(res, 200, { status, legal, ready: legalReady(legal), mail: Boolean(mailer), count });
}

// ——— Admin ———

const admins = () => (process.env.ADMIN_EMAILS || "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);

async function isAdmin(req) {
  const uid = verifyToken(req.headers.authorization);
  const email = String(req.headers["x-admin-email"] || "").trim().toLowerCase();
  if (!uid || !email || !admins().includes(email)) return false;
  const user = await readObject(userPath(email)).catch(() => null);
  return Boolean(user && user.userId === uid);
}

async function allLeads() {
  const objects = await listObjects(PREFIX);
  const out = [];
  for (let i = 0; i < objects.length; i += 50) {
    const batch = await Promise.all(objects.slice(i, i + 50).map((o) => readObject(o.pathname).catch(() => null)));
    out.push(...batch.filter(Boolean));
  }
  // Withdrawn more than 30 days ago, or never confirmed within 60 days: erased now.
  const now = Date.now();
  const expired = out.filter((l) => (l.eraseAfter && Date.parse(l.eraseAfter) < now)
    || (l.status === "pending" && Date.parse(l.createdAt) < now - 60 * 864e5));
  if (expired.length) await deleteObjects(expired.map((l) => ({ pathname: leadPath(l.id), url: leadPath(l.id) }))).catch(() => {});
  return out.filter((l) => !expired.includes(l)).sort((a, b) => (b.createdAt || "").localeCompare(a.createdAt || ""));
}

function stats(leads) {
  const by = (f) => leads.reduce((m, l) => { for (const k of [].concat(f(l))) m[k] = (m[k] || 0) + 1; return m; }, {});
  const days = {};
  for (const l of leads) { const d = (l.createdAt || "").slice(0, 10); days[d] = (days[d] || 0) + 1; }
  return { total: leads.length, status: by((l) => l.status), lang: by((l) => l.lang), interests: by((l) => l.interests || []), travel: by((l) => l.travel || "—"), days };
}

const csvCell = (v) => `"${String(v ?? "").replace(/"/g, '""')}"`;
function csv(leads) {
  const head = ["email", "name", "lang", "status", "created", "confirmed", "unsubscribed", "interests", "travel", "privacy_consent_at", "privacy_policy_version", "updates_consent_at", "updates_consent_text", "consent_ip", "double_opt_in_at", "events"];
  const rows = leads.map((l) => {
    const p = [...(l.consents || [])].reverse().find((c) => c.type === "privacy") || {};
    const u = [...(l.consents || [])].reverse().find((c) => c.type === "updates") || {};
    const d = (l.consents || []).find((c) => c.type === "double_opt_in") || {};
    return [l.email, l.name, l.lang, l.status, l.createdAt, l.confirmedAt, l.unsubscribedAt, (l.interests || []).join(" "), l.travel, p.at, p.version, u.at, u.text, u.ip, d.at,
      (l.events || []).map((e) => `${e.t}@${e.at}`).join(" ")].map(csvCell).join(",");
  });
  return "﻿" + [head.join(","), ...rows].join("\r\n");
}

async function admin(req, res, url) {
  if (!(await isAdmin(req))) return send(res, 401, { error: admins().length ? "not_admin" : "no_admins" });
  const what = url.searchParams.get("admin");

  if (what === "leads" && req.method === "GET") {
    const leads = await allLeads();
    const { status, legal } = await loadStatus();
    return send(res, 200, { leads, stats: stats(leads), mail: mailer || null, status, legal, site: SITE });
  }
  if (what === "export" && req.method === "GET") {
    const leads = await allLeads();
    res.statusCode = 200;
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", `attachment; filename="nordur-iscritti-${new Date().toISOString().slice(0, 10)}.csv"`);
    res.setHeader("Cache-Control", "no-store");
    return res.end(csv(leads));
  }
  if (what === "lead" && req.method === "DELETE") {
    const id = url.searchParams.get("id") || "";
    if (!/^[0-9a-f]{32}$/.test(id)) return send(res, 400, { error: "id" });
    await deleteObjects([{ pathname: leadPath(id), url: leadPath(id) }]);
    return send(res, 200, { ok: true });
  }
  if (what === "status" && req.method === "PUT") {
    const b = await readJSON(req);
    const current = await loadStatus();
    const s = b.status || current.status;
    const status = {
      phase: ["idea", "development", "beta", "testflight", "review", "launched"].includes(s.phase) ? s.phase : current.status.phase,
      progress: Math.max(0, Math.min(100, Math.round(Number(s.progress) || 0))),
      note: Object.fromEntries(LANGS.map((l) => [l, String(s.note?.[l] || "").slice(0, 600)])),
      items: (Array.isArray(s.items) ? s.items : []).slice(0, 20).map((i) => ({ label: Object.fromEntries(LANGS.map((l) => [l, String(i.label?.[l] || "").slice(0, 120)])), done: Boolean(i.done) })),
      appStoreUrl: /^https:\/\/apps\.apple\.com\//.test(s.appStoreUrl || "") ? s.appStoreUrl : "",
      showCount: Boolean(s.showCount),
      updatedAt: new Date().toISOString(),
    };
    const l = b.legal || current.legal;
    const legal = { controller: String(l.controller || "").slice(0, 120), email: EMAIL.test(l.email || "") ? l.email : "", address: String(l.address || "").slice(0, 200), vat: String(l.vat || "").slice(0, 40) };
    await writeObject(STATUS, { status, legal });
    return send(res, 200, { ok: true, status, legal });
  }
  if (what === "send" && req.method === "POST") {
    if (!mailer) return send(res, 503, { error: "no_mailer" });
    const b = await readJSON(req);
    const subject = String(b.subject || "").trim().slice(0, 150), text = String(b.text || "").trim().slice(0, 20000);
    if (!subject || !text) return send(res, 400, { error: "empty" });
    if (b.test) {
      const me = String(req.headers["x-admin-email"]).toLowerCase();
      const ok = await sendUpdate({ id: leadId(me), email: me, lang: "it", name: "" }, `[TEST] ${subject}`, text);
      return send(res, 200, { sent: ok ? 1 : 0, next: null, total: 1 });
    }
    const lang = LANGS.includes(b.lang) ? b.lang : "all";
    const targets = (await allLeads()).filter((l) => l.status === "confirmed" && (lang === "all" || l.lang === lang)).sort((a, c) => a.id.localeCompare(c.id));
    const offset = Math.max(0, Number(b.offset) || 0);
    const campaign = /^[0-9a-f]{16}$/.test(b.campaign || "") ? b.campaign : crypto.randomBytes(8).toString("hex");
    const now = new Date().toISOString();
    let sent = 0;
    for (const lead of targets.slice(offset, offset + 20)) {
      if (await sendUpdate(lead, subject, text)) {
        sent += 1;
        lead.events.push({ t: `mail:${campaign}`, at: now });
        lead.lastMailAt = now;
        await writeObject(leadPath(lead.id), lead);
      }
    }
    const next = offset + 20 < targets.length ? offset + 20 : null;
    const log = (await readObject(`campaigns/${campaign}.bin`).catch(() => null)) || { id: campaign, subject, lang, startedAt: now, sent: 0, total: targets.length };
    log.sent += sent;
    log.finishedAt = next == null ? now : null;
    await writeObject(`campaigns/${campaign}.bin`, log);
    return send(res, 200, { sent, next, total: targets.length, campaign });
  }
  if (what === "reconfirm" && req.method === "POST") {
    if (!mailer) return send(res, 503, { error: "no_mailer" });
    const b = await readJSON(req);
    const targets = (await allLeads()).filter((l) => l.status === "pending").sort((a, c) => a.id.localeCompare(c.id));
    const offset = Math.max(0, Number(b.offset) || 0);
    let sent = 0;
    for (const lead of targets.slice(offset, offset + 20)) {
      if (await sendConfirmation(lead)) {
        sent += 1;
        lead.events.push({ t: "confirmation_sent", at: new Date().toISOString() });
        await writeObject(leadPath(lead.id), lead);
      }
    }
    return send(res, 200, { sent, next: offset + 20 < targets.length ? offset + 20 : null, total: targets.length });
  }
  if (what === "campaigns" && req.method === "GET") {
    const objects = await listObjects("campaigns/");
    const campaigns = (await Promise.all(objects.map((o) => readObject(o.pathname).catch(() => null)))).filter(Boolean)
      .sort((a, b) => (b.startedAt || "").localeCompare(a.startedAt || ""));
    return send(res, 200, { campaigns });
  }
  send(res, 404, { error: "unknown" });
}

/** The site can be hosted elsewhere: these endpoints answer any origin (no cookies are used; the admin calls carry a Bearer token). */
export function cors(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Admin-Email");
  res.setHeader("Access-Control-Max-Age", "86400");
  if (req.method === "OPTIONS") { res.statusCode = 204; res.end(); return true; }
  return false;
}

export async function leads(req, res, url) {
  if (cors(req, res)) return;
  try {
    const lead = url.searchParams.get("lead");
    if (lead === "subscribe" && req.method === "POST") return await subscribe(req, res);
    if (lead === "confirm") return await confirm(req, res, url);
    if (lead === "unsubscribe") return await unsubscribe(req, res, url);
    if (lead === "forget" && req.method === "POST") return await forget(req, res);
    if (lead === "status") return await publicStatus(res);
    if (url.searchParams.get("admin")) return await admin(req, res, url);
    send(res, 404, { error: "unknown" });
  } catch (e) {
    console.error("leads", e);
    send(res, 500, { error: "server" });
  }
}
