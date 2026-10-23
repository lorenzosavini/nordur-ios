// Per-account documents (trip, settings, alerts, drives…).
//   GET    /api/data            -> { docs: [{ doc, updatedAt, size }] }
//   GET    /api/data?doc=trip   -> { doc, updatedAt, payload }
//   PUT    /api/data?doc=trip   { updatedAt, payload } -> { ok }
//   DELETE /api/data?doc=trip   -> { ok }
// Trips shared between accounts, by e-mail address:
//   POST   /api/data?share=trip { email, to, title, payload } -> { ok, notified }
//   GET    /api/data?inbox=1&email=…                         -> { items: [{ id, from, title, createdAt, payload }] }
//   DELETE /api/data?inbox=<id>&email=…                      -> { ok }
// Trips edited together (each member's app keeps its copy in step):
//   POST   /api/data?trip=new { email, title, stops, tombstones } -> { trip }
//   GET    /api/data?trip=<id>&email=…                       -> { trip }
//   PUT    /api/data?trip=<id> { email, stops, tombstones }  -> { trip }   (merged)
//   POST   /api/data?trip=<id>&invite=1 { email, to, lang }  -> { trip, notified }
//   DELETE /api/data?trip=<id>&email=…                       -> { ok }     (leave)
//   GET    /api/data?trips=1&email=…                         -> { trips: [{ id, title, members, owner, version, updatedAt }] }
// trip = { id, title, owner, members, version, updatedAt, stops, tombstones }.
// The addresses given are checked against the signed-in account.
import crypto from "node:crypto";
import { verifyToken, readObject, writeObject, listObjects, deleteObjects, docPrefix, docPath, readJSON, send, isRevoked, userPath, hmac } from "../lib/core.js";
import { sendMail } from "../lib/mail.js";

const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const inboxPrefix = (email) => `inbox/${hmac(email.trim().toLowerCase(), "inbox")}/`;

/** The account's own address, or null when it is not the signed-in user's. */
async function ownEmail(uid, email) {
  if (!email || !EMAIL.test(email)) return null;
  const user = await readObject(userPath(email)).catch(() => null);
  return user && user.userId === uid ? email.trim().toLowerCase() : null;
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

async function share(req, res, uid) {
  const { email, to, title, payload, lang } = await readJSON(req);
  const from = await ownEmail(uid, email);
  if (!from) return send(res, 401, { error: "Sessione non valida, accedi di nuovo" });
  if (!to || !EMAIL.test(to)) return send(res, 400, { error: "Indirizzo email del destinatario non valido" });
  if (!Array.isArray(payload) || payload.length === 0) return send(res, 400, { error: "Viaggio vuoto" });
  if (JSON.stringify(payload).length > 600_000) return send(res, 413, { error: "Viaggio troppo grande" });
  const recipient = to.trim().toLowerCase();
  const id = crypto.randomUUID();
  const name = String(title || "Viaggio").slice(0, 120);
  await writeObject(`${inboxPrefix(recipient)}${id}.bin`, { id, from, title: name, createdAt: new Date().toISOString(), payload }, { ttl: 90 * 86400 });
  const en = lang === "en";
  const subject = en ? `${from} shared a trip with you on Norður` : `${from} ha condiviso con te un viaggio su Norður`;
  const lines = en
    ? [`${from} shared the trip “${name}” with you.`, "Open Norður › Trip › Received, signed in with this address, to see it and import it.", "No account yet? Create one in the app with this e-mail address: the trip will be waiting."]
    : [`${from} ha condiviso con te il viaggio «${name}».`, "Apri Norður › Viaggio › Ricevuti, con l'accesso fatto con questo indirizzo, per vederlo e importarlo.", "Non hai ancora un account? Crealo nell'app con questo indirizzo email: il viaggio ti aspetta lì."];
  const notified = await sendMail({
    to: recipient, subject,
    text: [...lines, "", "— Norður"].join("\n"),
    html: `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5;color:#111">${lines.map((l) => `<p>${esc(l)}</p>`).join("")}<p style="color:#888">— Norður</p></div>`,
  }).catch(() => false);
  return send(res, 200, { ok: true, notified: !!notified });
}

// MARK: Trips edited together

const tripPath = (id) => `trips/${id}.bin`;
const memberPrefix = (email) => `tripsof/${hmac(email, "trips")}/`;
const ID = /^[0-9a-f-]{36}$/;
const stamp = (x) => (typeof x?.modified === "number" ? x.modified : 0);

/**
 * Merges two copies of a trip, item by item: the newer version of each stop and
 * of each attraction wins, and a deletion wins over versions older than it. The
 * same rule runs in the app, so every copy ends up the same whatever the order.
 */
export function mergeTrip(a, b) {
  const tombstones = { ...(a.tombstones || {}) };
  for (const [k, t] of Object.entries(b.tombstones || {})) tombstones[k] = Math.max(tombstones[k] || 0, t);
  const alive = (x) => !(x.id in tombstones) || tombstones[x.id] < stamp(x);
  const byId = new Map();
  for (const s of [...(a.stops || []), ...(b.stops || [])]) {
    const prev = byId.get(s.id);
    if (!prev) { byId.set(s.id, s); continue; }
    const newer = stamp(s) > stamp(prev) ? s : prev;
    const visits = new Map();
    for (const v of [...(prev.visits || []), ...(s.visits || [])]) {
      const pv = visits.get(v.id);
      if (!pv || stamp(v) > stamp(pv)) visits.set(v.id, v);
    }
    byId.set(s.id, { ...newer, visits: [...visits.values()] });
  }
  const stops = [...byId.values()].filter(alive).map((s) => ({ ...s, visits: (s.visits || []).filter(alive) }))
    .sort((x, y) => (x.date || 0) - (y.date || 0));
  return { stops, tombstones };
}

async function readTrip(id) {
  return ID.test(id || "") ? readObject(tripPath(id)).catch(() => null) : null;
}

async function saveTrip(trip) {
  await writeObject(tripPath(trip.id), trip, { ttl: 365 * 86400 });
}

async function invite(trip, from, to, lang) {
  if (!trip.members.includes(to)) trip.members.push(to);
  await writeObject(`${memberPrefix(to)}${trip.id}.bin`, { id: trip.id }, { ttl: 365 * 86400 });
  const en = lang === "en";
  const lines = en
    ? [`${from} invited you to plan the trip “${trip.title}” together on Norður.`, "Open Norður › Trip, signed in with this address, and join it: every change either of you makes reaches the other."]
    : [`${from} ti ha invitato a organizzare insieme il viaggio «${trip.title}» su Norður.`, "Apri Norður › Viaggio, con l'accesso fatto con questo indirizzo, e partecipa: ogni modifica di uno arriva anche all'altro."];
  return sendMail({
    to, subject: en ? `${from} invited you to a trip on Norður` : `${from} ti ha invitato a un viaggio su Norður`,
    text: [...lines, "", "— Norður"].join("\n"),
    html: `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5;color:#111">${lines.map((l) => `<p>${esc(l)}</p>`).join("")}<p style="color:#888">— Norður</p></div>`,
  }).catch(() => false);
}

async function trips(req, res, uid, url) {
  const id = url.searchParams.get("trip");
  const body = req.method === "GET" || req.method === "DELETE" ? {} : await readJSON(req);
  const email = await ownEmail(uid, body.email || url.searchParams.get("email"));
  if (!email) return send(res, 401, { error: "Sessione non valida, accedi di nuovo" });

  if (url.searchParams.get("trips")) {
    const list = await Promise.all((await listObjects(memberPrefix(email))).map((b) => readObject(b.pathname).catch(() => null)));
    const found = (await Promise.all(list.filter(Boolean).map((m) => readTrip(m.id)))).filter((t) => t && t.members.includes(email));
    return send(res, 200, { trips: found.map(({ stops, tombstones, ...meta }) => ({ ...meta, stops: stops.length })) });
  }
  if (id === "new" && req.method === "POST") {
    if (JSON.stringify(body.stops || []).length > 600_000) return send(res, 413, { error: "Viaggio troppo grande" });
    const trip = { id: crypto.randomUUID(), title: String(body.title || "Viaggio").slice(0, 120), owner: email, members: [email],
      version: 1, updatedAt: new Date().toISOString(), ...mergeTrip({ stops: body.stops || [], tombstones: body.tombstones || {} }, {}) };
    await writeObject(`${memberPrefix(email)}${trip.id}.bin`, { id: trip.id }, { ttl: 365 * 86400 });
    await saveTrip(trip);
    return send(res, 200, { trip });
  }
  const trip = await readTrip(id);
  if (!trip || !trip.members.includes(email)) return send(res, 404, { error: "Viaggio non trovato o non condiviso con te" });
  if (req.method === "GET") return send(res, 200, { trip });
  if (req.method === "DELETE") {
    trip.members = trip.members.filter((m) => m !== email);
    await deleteObjects((await listObjects(memberPrefix(email))).filter((b) => b.pathname.endsWith(`/${trip.id}.bin`)));
    if (trip.members.length) await saveTrip(trip); else await deleteObjects([{ pathname: tripPath(trip.id), url: tripPath(trip.id) }]);
    return send(res, 200, { ok: true });
  }
  if (req.method === "POST" && url.searchParams.get("invite")) {
    const to = String(body.to || "").trim().toLowerCase();
    if (!EMAIL.test(to)) return send(res, 400, { error: "Indirizzo email non valido" });
    if (trip.members.length >= 12) return send(res, 400, { error: "Al massimo 12 persone per viaggio" });
    const notified = await invite(trip, email, to, body.lang);
    await saveTrip(trip);
    return send(res, 200, { trip, notified: !!notified });
  }
  if (req.method === "PUT") {
    if (JSON.stringify(body.stops || []).length > 600_000) return send(res, 413, { error: "Viaggio troppo grande" });
    const merged = mergeTrip(trip, { stops: body.stops || [], tombstones: body.tombstones || {} });
    const changed = JSON.stringify(merged) !== JSON.stringify({ stops: trip.stops, tombstones: trip.tombstones });
    const next = changed ? { ...trip, ...merged, title: body.title ? String(body.title).slice(0, 120) : trip.title,
      version: trip.version + 1, updatedAt: new Date().toISOString(), editedBy: email } : trip;
    if (changed) await saveTrip(next);
    return send(res, 200, { trip: next });
  }
  return send(res, 405, { error: "method" });
}

async function inbox(req, res, uid, url) {
  const email = await ownEmail(uid, url.searchParams.get("email"));
  if (!email) return send(res, 401, { error: "Sessione non valida, accedi di nuovo" });
  const prefix = inboxPrefix(email);
  if (req.method === "DELETE") {
    const id = url.searchParams.get("inbox");
    if (!/^[0-9a-f-]{36}$/.test(id || "")) return send(res, 400, { error: "id" });
    await deleteObjects((await listObjects(prefix)).filter((b) => b.pathname.endsWith(`/${id}.bin`)));
    return send(res, 200, { ok: true });
  }
  const blobs = await listObjects(prefix);
  const items = (await Promise.all(blobs.map((b) => readObject(b.pathname).catch(() => null)))).filter(Boolean)
    .sort((a, b) => (b.createdAt || "").localeCompare(a.createdAt || ""));
  return send(res, 200, { items });
}

const DOC = /^[a-z0-9][a-z0-9_-]{0,80}$/;

export default async function handler(req, res) {
  const uid = verifyToken(req.headers.authorization);
  if (!uid) return send(res, 401, { error: "Sessione scaduta, accedi di nuovo" });
  const url = new URL(req.url, "http://x");
  if (url.searchParams.get("share") && req.method === "POST") {
    if (await isRevoked(uid)) return send(res, 401, { error: "Account eliminato" });
    return share(req, res, uid).catch((e) => { console.error(e); send(res, 500, { error: "Errore del server" }); });
  }
  if (url.searchParams.get("trip") || url.searchParams.get("trips")) {
    if (req.method !== "GET" && (await isRevoked(uid))) return send(res, 401, { error: "Account eliminato" });
    return trips(req, res, uid, url).catch((e) => { console.error(e); send(res, 500, { error: "Errore del server" }); });
  }
  if (url.searchParams.get("inbox")) {
    return inbox(req, res, uid, url).catch((e) => { console.error(e); send(res, 500, { error: "Errore del server" }); });
  }
  const doc = url.searchParams.get("doc");
  if (doc && !DOC.test(doc)) return send(res, 400, { error: "doc" });

  try {
    if (req.method === "GET" && !doc) {
      const blobs = await listObjects(docPrefix(uid));
      // Redis keeps no upload time: read it from the (small) documents.
      const docs = await Promise.all(blobs.map(async (b) => ({
        doc: b.pathname.split("/").pop().replace(/\.bin$/, ""),
        updatedAt: b.uploadedAt || (await readObject(b.pathname).catch(() => null))?.updatedAt || null,
        size: b.size,
      })));
      return send(res, 200, { docs });
    }
    if (req.method === "GET") {
      const stored = await readObject(docPath(uid, doc));
      if (!stored) return send(res, 404, { error: "not found" });
      return send(res, 200, { doc, ...stored });
    }
    if (req.method === "PUT") {
      if (await isRevoked(uid)) return send(res, 401, { error: "Account eliminato" });
      const { payload, updatedAt } = await readJSON(req);
      if (payload === undefined) return send(res, 400, { error: "payload" });
      await writeObject(docPath(uid, doc), { payload, updatedAt: updatedAt || new Date().toISOString() });
      return send(res, 200, { ok: true });
    }
    if (req.method === "DELETE") {
      const blobs = await listObjects(docPrefix(uid));
      const target = doc ? blobs.filter((b) => b.pathname.endsWith(`/${doc}.bin`)) : blobs;
      await deleteObjects(target);
      return send(res, 200, { ok: true });
    }
    return send(res, 405, { error: "method" });
  } catch (e) {
    console.error(e);
    return send(res, 500, { error: "Errore del server" });
  }
}
