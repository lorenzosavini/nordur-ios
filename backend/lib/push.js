// Push notifications through Apple (APNs), for the notices of the admin panel.
//
// Needs, in the Vercel environment variables, a key made in Apple Developer ›
// Certificates, Identifiers & Profiles › Keys (Apple Push Notifications service):
//   APNS_KEY     the content of the .p8 file (with its BEGIN/END lines)
//   APNS_KEY_ID  the key's 10-character ID
//   APNS_TEAM_ID the team ID (Membership)
//   APNS_TOPIC   the app's bundle ID (default it.lorenzosavini.nordur)
// The phones register their token at /api/health?device=1; tokens Apple
// refuses are forgotten.
import crypto from "node:crypto";
import http2 from "node:http2";
import { readObject, writeObject, listObjects, deleteObjects, hmac } from "./core.js";

const KEY = (process.env.APNS_KEY || "").replace(/\\n/g, "\n").trim();
const KEY_ID = (process.env.APNS_KEY_ID || "").trim();
const TEAM_ID = (process.env.APNS_TEAM_ID || "").trim();
const TOPIC = (process.env.APNS_TOPIC || "it.lorenzosavini.nordur").trim();
export const pushReady = Boolean(KEY && KEY_ID && TEAM_ID);

const devicePath = (token) => `devices/${hmac(token, "device")}.bin`;
const LANGS = ["it", "en", "de", "fr", "es"];

/** A phone's token: kept 180 days from its last launch. */
export async function registerDevice(body) {
  const token = String(body.token || "").toLowerCase();
  if (!/^[0-9a-f]{64,200}$/.test(token)) return { error: "token" };
  const env = body.env === "development" ? "development" : "production";
  const lang = LANGS.includes(body.lang) ? body.lang : "en";
  await writeObject(devicePath(token), { token, env, lang, at: new Date().toISOString() }, { ttl: 180 * 86400 });
  return { ok: true };
}

export async function deviceCount() {
  return (await listObjects("devices/")).length;
}

let jwt = null;
function bearer() {
  if (jwt && Date.now() - jwt.at < 40 * 60e3) return jwt.token;
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const head = enc({ alg: "ES256", kid: KEY_ID }), claims = enc({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) });
  const sig = crypto.sign("sha256", Buffer.from(`${head}.${claims}`), { key: KEY, dsaEncoding: "ieee-p1363" }).toString("base64url");
  jwt = { at: Date.now(), token: `${head}.${claims}.${sig}` };
  return jwt.token;
}

function send(client, token, payload, priority) {
  return new Promise((resolve) => {
    const req = client.request({
      ":method": "POST", ":path": `/3/device/${token}`,
      authorization: `bearer ${bearer()}`, "apns-topic": TOPIC, "apns-push-type": "alert",
      "apns-priority": String(priority), "content-type": "application/json",
    });
    let status = 0, body = "";
    req.on("response", (h) => (status = h[":status"]));
    req.on("data", (c) => (body += c));
    req.on("end", () => resolve({ status, reason: body ? JSON.parse(body).reason : null }));
    req.on("error", (e) => resolve({ status: 0, reason: e.message }));
    req.setTimeout(10e3, () => { req.close(); resolve({ status: 0, reason: "timeout" }); });
    req.end(JSON.stringify(payload));
  });
}

/** Sends a notice to every registered phone, in its language. */
export async function pushNotice(notice) {
  if (!pushReady) return { sent: 0, failed: 0, removed: 0, error: "Push non configurate (APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID)" };
  const keys = (await listObjects("devices/")).map((o) => o.pathname);
  const devices = [];
  for (let i = 0; i < keys.length; i += 50) devices.push(...(await Promise.all(keys.slice(i, i + 50).map((k) => readObject(k).then((d) => d && { ...d, key: k }).catch(() => null)))).filter(Boolean));
  const clients = {};
  const client = (env) => (clients[env] ||= http2.connect(env === "development" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com"));
  const result = { sent: 0, failed: 0, removed: 0, reasons: {} };
  const gone = [];
  const priority = notice.level === "info" ? 5 : 10;
  for (let i = 0; i < devices.length; i += 40) {
    await Promise.all(devices.slice(i, i + 40).map(async (d) => {
      const t = notice.texts[d.lang] || notice.texts.en || notice.texts.it || Object.values(notice.texts)[0];
      const payload = {
        aps: {
          alert: { title: t.title, subtitle: "Norður", body: t.text || "" },
          sound: "default", "thread-id": "notice", "content-available": 1,
          "interruption-level": notice.level === "danger" ? "time-sensitive" : "active",
        },
        alertID: `notice:${notice.id}`, notice: notice.id,
      };
      let r = await send(client(d.env), d.token, payload, priority);
      // A phone that guessed its environment wrong (a development build): the other one, remembered.
      if (r.reason === "BadDeviceToken") {
        const other = d.env === "development" ? "production" : "development";
        const again = await send(client(other), d.token, payload, priority);
        if (again.status === 200) { r = again; await writeObject(d.key, { ...d, key: undefined, env: other }, { ttl: 180 * 86400 }).catch(() => {}); }
      }
      if (r.status === 200) result.sent++;
      else {
        result.failed++;
        result.reasons[r.reason || r.status] = (result.reasons[r.reason || r.status] || 0) + 1;
        if (r.status === 410 || ["BadDeviceToken", "Unregistered"].includes(r.reason)) gone.push({ pathname: d.key, url: d.key });
      }
    }));
  }
  Object.values(clients).forEach((c) => c.close());
  if (gone.length) { await deleteObjects(gone); result.removed = gone.length; }
  return result;
}
