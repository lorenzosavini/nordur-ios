// Per-account documents (trip, settings, alerts, drives…).
//   GET    /api/data            -> { docs: [{ doc, updatedAt, size }] }
//   GET    /api/data?doc=trip   -> { doc, updatedAt, payload }
//   PUT    /api/data?doc=trip   { updatedAt, payload } -> { ok }
//   DELETE /api/data?doc=trip   -> { ok }
// Trips shared between accounts, by e-mail address:
//   POST   /api/data?share=trip { email, to, title, payload } -> { ok, notified }
//   GET    /api/data?inbox=1&email=…                         -> { items: [{ id, from, title, createdAt, payload }] }
//   DELETE /api/data?inbox=<id>&email=…                      -> { ok }
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
