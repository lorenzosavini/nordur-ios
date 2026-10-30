// The app's admin panel (backend/public/admin/), served by /api/health?admin=1
// (the Hobby plan allows 12 functions, all taken).
//
// Access: the password in the ADMIN_PASSWORD environment variable (at least
// 12 characters) and, when ADMIN_TOTP_SECRET is set, the 6-digit code of an
// authenticator app. Five wrong attempts lock the address for 15 minutes.
// A session lasts 8 hours. Every action is written to the log (kept 400 days).
//
// What it does not do: read the contents of backups (trips, drives,
// settings). Their names, sizes and dates are shown; the contents leave only
// in a GDPR export asked for by the user, and that is logged too.
import crypto from "node:crypto";
import { readObject, writeObject, listObjects, deleteObjects, readJSON, send, hmac, userPath, docPrefix, revokedPath, storage } from "./core.js";
import { mailer } from "./mail.js";
import { deleteAccount, granted, sightingTag, bannedSighterPath } from "./accounts.js";
import { FEATURES, readConfig, writeConfig, publicConfig, fillLanguages } from "./features.js";
import { translateTexts } from "../api/translate.js";
import { pushReady, pushNotice, deviceCount } from "./push.js";

const PASSWORD = process.env.ADMIN_PASSWORD || "";
const TOTP = (process.env.ADMIN_TOTP_SECRET || "").replace(/\s/g, "").toUpperCase();
const SESSION_HOURS = 8;

// ——— Access ———

const digest = (s) => crypto.createHash("sha256").update(String(s)).digest();

function base32(s) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const c of s.replace(/=+$/, "")) { const v = alphabet.indexOf(c); if (v < 0) return null; bits += v.toString(2).padStart(5, "0"); }
  return Buffer.from(bits.match(/.{8}/g)?.map((b) => parseInt(b, 2)) || []);
}

/** RFC 6238 code (30 s, 6 digits, SHA-1) for a step. */
export function totp(secret, step) {
  const key = base32(secret);
  if (!key) return null;
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const h = crypto.createHmac("sha1", key).update(counter).digest();
  const o = h[h.length - 1] & 15;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1e6).padStart(6, "0");
}

function codeOk(code) {
  if (!TOTP) return true;
  const step = Math.floor(Date.now() / 30e3);
  const given = String(code || "").replace(/\D/g, "");
  return [-1, 0, 1].some((d) => totp(TOTP, step + d) === given);
}

function issueSession() {
  const body = Buffer.from(JSON.stringify({ exp: Date.now() + SESSION_HOURS * 3600e3, n: crypto.randomUUID() })).toString("base64url");
  return `${body}.${hmac(body, "admin-session")}`;
}

function sessionOk(token) {
  const [body, sig] = String(token || "").split(".");
  if (!body || !sig || sig.length !== 40) return false;
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(hmac(body, "admin-session")))) return false;
  try { return JSON.parse(Buffer.from(body, "base64url").toString("utf8")).exp > Date.now(); } catch { return false; }
}

const ipOf = (req) => String(req.headers["x-forwarded-for"] || req.socket?.remoteAddress || "").split(",")[0].trim();
const failPath = (req) => `admin/fail/${hmac(ipOf(req), "admin-ip")}.bin`;

async function log(req, action, detail = {}) {
  const at = new Date().toISOString();
  await writeObject(`admin/log/${at}-${crypto.randomBytes(3).toString("hex")}.bin`, { at, action, detail, ip: hmac(ipOf(req), "admin-ip").slice(0, 8) }, { ttl: 400 * 86400 }).catch(() => {});
}

// ——— Data ———

let usersCache = null;
async function allUsers(fresh = false) {
  if (!fresh && usersCache && Date.now() - usersCache.at < 60e3) return usersCache.list;
  const keys = (await listObjects("users/")).map((o) => o.pathname);
  const list = [];
  for (let i = 0; i < keys.length; i += 25) {
    const batch = await Promise.all(keys.slice(i, i + 25).map((k) => readObject(k).catch(() => null)));
    list.push(...batch.filter(Boolean));
  }
  usersCache = { at: Date.now(), list };
  return list;
}

const publicUser = (u) => ({
  email: u.email, created: u.created || null, lastLogin: u.lastLogin || null, lastSeen: u.lastSeen || null,
  lang: u.lang || null, pro: granted(u), grant: u.grant || null, blocked: Boolean(u.blocked), note: u.note || null,
});

async function userByEmail(email) {
  const e = String(email || "").trim().toLowerCase();
  return e ? readObject(userPath(e)) : null;
}

async function sightingsSince(days) {
  const out = [];
  for (let d = 0; d < days; d++) {
    const day = new Date(Date.now() - d * 864e5).toISOString().slice(0, 10);
    const keys = (await listObjects(`sightings/${day}/`, { limit: 1000 })).map((o) => o.pathname);
    const records = await Promise.all(keys.map(async (key) => ({ key, r: await readObject(key).catch(() => null) })));
    for (const { key, r } of records) if (r) out.push({ key, tag: key.split("-").pop().replace(/\.bin$/, ""), ...r });
  }
  return out.sort((a, b) => (a.t < b.t ? 1 : -1));
}

// ——— Actions ———

const ACTIONS = {
  async overview() {
    const users = await allUsers();
    const day = (iso) => (iso || "").slice(0, 10);
    const today = new Date().toISOString().slice(0, 10);
    const daysAgo = (n) => new Date(Date.now() - n * 864e5).toISOString().slice(0, 10);
    const perDay = [];
    for (let n = 29; n >= 0; n--) { const d = daysAgo(n); perDay.push({ day: d, created: users.filter((u) => day(u.created) === d).length }); }
    const sightings = await sightingsSince(7);
    const config = await readConfig();
    return {
      users: users.length,
      newToday: users.filter((u) => day(u.created) === today).length,
      new7: users.filter((u) => day(u.created) >= daysAgo(6)).length,
      active7: users.filter((u) => (day(u.lastSeen) || day(u.lastLogin)) >= daysAgo(6)).length,
      pro: users.filter(granted).length,
      blocked: users.filter((u) => u.blocked).length,
      langs: Object.entries(users.reduce((m, u) => ({ ...m, [u.lang || "?"]: (m[u.lang || "?"] || 0) + 1 }), {})),
      perDay,
      sightings7: sightings.filter((s) => s.seen !== false).length,
      negative7: sightings.filter((s) => s.seen === false).length,
      system: { storage, mail: mailer || "off", totp: Boolean(TOTP), mode: config.mode, configUpdated: config.updatedAt },
    };
  },

  async users(body) {
    const q = String(body.query || "").trim().toLowerCase();
    const filter = body.filter || "all";
    let list = (await allUsers(body.fresh)).map(publicUser);
    if (q) list = list.filter((u) => u.email.includes(q));
    if (filter === "pro") list = list.filter((u) => u.pro);
    if (filter === "blocked") list = list.filter((u) => u.blocked);
    list.sort((a, b) => ((a.created || "") < (b.created || "") ? 1 : -1));
    const page = Math.max(0, Number(body.page) || 0), size = 50;
    return { total: list.length, page, size, users: list.slice(page * size, page * size + size) };
  },

  async user(body) {
    const u = await userByEmail(body.email);
    if (!u) return { error: "Utente non trovato", status: 404 };
    const docs = await listObjects(docPrefix(u.userId));
    const tag = sightingTag(u.userId);
    const banned = Boolean(await readObject(bannedSighterPath(tag)).catch(() => null));
    const mine = (await listObjects("sightings/")).filter((b) => b.pathname.endsWith(`-${tag}.bin`));
    return {
      user: publicUser(u), tag, sightingsBanned: banned, sightings: mine.length,
      docs: docs.map((d) => ({ doc: d.pathname.split("/").pop().replace(/\.bin$/, ""), size: d.size ?? null, uploadedAt: d.uploadedAt || null })),
    };
  },

  async grant(body, req) {
    const u = await userByEmail(body.email);
    if (!u) return { error: "Utente non trovato", status: 404 };
    const until = body.until && !Number.isNaN(Date.parse(body.until)) ? new Date(body.until).toISOString() : null;
    const next = body.remove ? { ...u, grant: null } : { ...u, grant: { until, note: String(body.note || "").slice(0, 200), at: new Date().toISOString() } };
    await writeObject(userPath(u.email), next);
    usersCache = null;
    await log(req, body.remove ? "pro-remove" : "pro-grant", { email: u.email, until });
    return { user: publicUser(next) };
  },

  async note(body, req) {
    const u = await userByEmail(body.email);
    if (!u) return { error: "Utente non trovato", status: 404 };
    const next = { ...u, note: String(body.note || "").slice(0, 500) || null };
    await writeObject(userPath(u.email), next);
    usersCache = null;
    await log(req, "note", { email: u.email });
    return { user: publicUser(next) };
  },

  async block(body, req) {
    const u = await userByEmail(body.email);
    if (!u) return { error: "Utente non trovato", status: 404 };
    const blocked = Boolean(body.blocked);
    await writeObject(userPath(u.email), { ...u, blocked, blockedAt: blocked ? new Date().toISOString() : null });
    // Its tokens stop writing (backups, sightings) while blocked.
    if (blocked) await writeObject(revokedPath(u.userId), { blocked: new Date().toISOString() });
    else await deleteObjects(await listObjects(revokedPath(u.userId), { limit: 1 }));
    usersCache = null;
    await log(req, blocked ? "block" : "unblock", { email: u.email });
    return { ok: true };
  },

  async delete(body, req) {
    const u = await userByEmail(body.email);
    if (!u) return { error: "Utente non trovato", status: 404 };
    if (String(body.confirm || "").trim().toLowerCase() !== u.email) return { error: "Scrivi l'email dell'utente per confermare", status: 400 };
    const deleted = await deleteAccount(u);
    usersCache = null;
    await log(req, "delete", { email: u.email, ...deleted });
    return { ok: true, deleted };
  },

  /** GDPR: everything stored about the user, to send to them. */
  async export(body, req) {
    const u = await userByEmail(body.email);
    if (!u) return { error: "Utente non trovato", status: 404 };
    const docs = await listObjects(docPrefix(u.userId));
    const documents = {};
    for (const d of docs) documents[d.pathname.split("/").pop().replace(/\.bin$/, "")] = await readObject(d.pathname).catch(() => null);
    const tag = sightingTag(u.userId);
    const sightings = [];
    for (const b of (await listObjects("sightings/")).filter((o) => o.pathname.endsWith(`-${tag}.bin`))) sightings.push(await readObject(b.pathname).catch(() => null));
    await log(req, "export", { email: u.email, documents: docs.length });
    const { salt, hash, recoverySalt, recoveryHash, ...account } = u;
    return { exported: new Date().toISOString(), account, documents, sightings: sightings.filter(Boolean) };
  },

  async sightings(body) {
    const days = Math.min(14, Math.max(1, Number(body.days) || 3));
    const list = await sightingsSince(days);
    const bannedKeys = new Set((await listObjects("sightings-banned/")).map((o) => o.pathname.split("/").pop().replace(/\.bin$/, "")));
    return { days, sightings: list.slice(0, 500).map((s) => ({ ...s, banned: bannedKeys.has(s.tag) })) };
  },

  async "sighting-delete"(body, req) {
    const key = String(body.key || "");
    if (!/^sightings\/\d{4}-\d{2}-\d{2}\/[\w.-]+\.bin$/.test(key)) return { error: "Chiave non valida", status: 400 };
    await deleteObjects(await listObjects(key, { limit: 1 }));
    await log(req, "sighting-delete", { key });
    return { ok: true };
  },

  async "sighter-ban"(body, req) {
    const tag = String(body.tag || "");
    if (!/^[0-9a-f]{16}$/.test(tag)) return { error: "Utente non valido", status: 400 };
    if (body.banned) await writeObject(bannedSighterPath(tag), { at: new Date().toISOString() });
    else await deleteObjects(await listObjects(bannedSighterPath(tag), { limit: 1 }));
    if (body.banned && body.purge) {
      const mine = (await listObjects("sightings/")).filter((b) => b.pathname.endsWith(`-${tag}.bin`));
      await deleteObjects(mine);
    }
    await log(req, body.banned ? "sighter-ban" : "sighter-unban", { tag, purge: Boolean(body.purge) });
    return { ok: true };
  },

  async config() {
    return { config: await readConfig(), features: FEATURES, public: publicConfig(await readConfig()), push: { ready: pushReady, devices: await deviceCount() } };
  },

  /** The current notice again as a push, to every phone. */
  async "notice-push"(body, req) {
    const live = publicConfig(await readConfig()).announcement;
    if (!live) return { error: "Nessun avviso attivo da inviare", status: 400 };
    const push = await pushNotice(live);
    await log(req, "notice-push", { id: live.id, sent: push.sent, failed: push.failed });
    return { push };
  },

  async "config-save"(body, req) {
    const before = (await readConfig()).announcement?.id || null;
    // The other languages translated automatically from the one written by hand.
    const input = { ...(body.config || {}) };
    if (input.announcement?.texts) input.announcement = { ...input.announcement, texts: await fillLanguages(input.announcement.texts, translateTexts) };
    if (input.paywall) input.paywall = await fillLanguages(input.paywall, translateTexts);
    const saved = await writeConfig(input);
    // A new notice, live now: pushed to every phone at once (unless asked not to).
    let push = null;
    const live = publicConfig(saved).announcement;
    if (live && live.id !== before && body.push !== false) push = await pushNotice(live);
    await log(req, "config-save", { mode: saved.mode, pro: Object.values(saved.features).filter((v) => v === "pro").length, off: Object.values(saved.features).filter((v) => v === "off").length, products: saved.products.length, announcement: saved.announcement?.id || null, pushed: push?.sent ?? null });
    return { config: saved, push };
  },

  async log() {
    const keys = (await listObjects("admin/log/")).map((o) => o.pathname).sort().reverse().slice(0, 150);
    const entries = (await Promise.all(keys.map((k) => readObject(k).catch(() => null)))).filter(Boolean);
    return { entries };
  },
};

export async function adminHandler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "POST") return send(res, 405, { error: "method" });
  if (PASSWORD.length < 12) return send(res, 503, { error: "Pannello non attivo: imposta ADMIN_PASSWORD (almeno 12 caratteri) nelle variabili di Vercel" });
  const body = await readJSON(req).catch(() => ({}));
  try {
    if (body.action === "login") {
      const fp = failPath(req);
      const fails = (await readObject(fp).catch(() => null)) || { n: 0, at: 0 };
      if (fails.n >= 5 && Date.now() - fails.at < 15 * 60e3) return send(res, 429, { error: "Troppi tentativi: riprova tra 15 minuti" });
      const passOk = crypto.timingSafeEqual(digest(body.password), digest(PASSWORD));
      if (!passOk || !codeOk(body.code)) {
        await writeObject(fp, { n: (Date.now() - fails.at < 15 * 60e3 ? fails.n : 0) + 1, at: Date.now() }, { ttl: 15 * 60 });
        await log(req, "login-failed");
        return send(res, 401, { error: TOTP ? "Password o codice errati" : "Password errata" });
      }
      await deleteObjects(await listObjects(fp, { limit: 1 }));
      await log(req, "login");
      return send(res, 200, { token: issueSession(), hours: SESSION_HOURS, totp: Boolean(TOTP) });
    }
    if (!sessionOk(req.headers["x-admin-token"])) return send(res, 401, { error: "Sessione scaduta: accedi di nuovo" });
    const action = ACTIONS[body.action];
    if (!action) return send(res, 400, { error: "Azione sconosciuta" });
    const result = await action(body, req);
    if (result?.error) return send(res, result.status || 400, { error: result.error });
    return send(res, 200, result);
  } catch (e) {
    console.error("admin", e);
    return send(res, 500, { error: "Errore del server" });
  }
}
