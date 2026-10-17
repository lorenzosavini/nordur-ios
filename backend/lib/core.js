// Shared helpers: encryption, password hashing, tokens and Blob storage.
import crypto from "node:crypto";
import { put, get, del, list } from "@vercel/blob";

const SECRET = process.env.APP_SECRET || "";
if (!SECRET || SECRET.length < 32) console.warn("APP_SECRET missing or too short");

const key = (purpose) => crypto.createHmac("sha256", SECRET).update(purpose).digest();
const ENC_KEY = key("enc"); // 32 bytes for AES-256-GCM

export const hmac = (value, purpose = "path") =>
  crypto.createHmac("sha256", key(purpose)).update(String(value)).digest("hex").slice(0, 40);

export function encrypt(obj) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", ENC_KEY, iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(obj), "utf8"), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), data]);
}

export function decrypt(buf) {
  const iv = buf.subarray(0, 12), tag = buf.subarray(12, 28), data = buf.subarray(28);
  const decipher = crypto.createDecipheriv("aes-256-gcm", ENC_KEY, iv);
  decipher.setAuthTag(tag);
  return JSON.parse(Buffer.concat([decipher.update(data), decipher.final()]).toString("utf8"));
}

export async function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const hash = await new Promise((resolve, reject) =>
    crypto.scrypt(password, salt, 64, { N: 16384, r: 8, p: 1 }, (err, out) => (err ? reject(err) : resolve(out.toString("hex"))))
  );
  return { salt, hash };
}

export function safeEqual(a, b) {
  const x = Buffer.from(a, "hex"), y = Buffer.from(b, "hex");
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

const b64 = (s) => Buffer.from(s).toString("base64url");
const TOKEN_DAYS = 365;

export function issueToken(uid) {
  const body = b64(JSON.stringify({ uid, exp: Date.now() + TOKEN_DAYS * 864e5 }));
  const sig = crypto.createHmac("sha256", key("token")).update(body).digest("base64url");
  return `${body}.${sig}`;
}

export function verifyToken(header) {
  const token = (header || "").replace(/^Bearer\s+/i, "");
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  const expected = crypto.createHmac("sha256", key("token")).update(body).digest("base64url");
  if (sig.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  return payload.exp > Date.now() ? payload.uid : null;
}

// Storage: Redis when connected (Vercel Marketplace), otherwise the private
// Vercel Blob store. Two kinds of connection: Upstash's REST API
// (KV_REST_API_URL / KV_REST_API_TOKEN, UPSTASH_REDIS_REST_URL / _TOKEN) or a
// plain Redis URL (REDIS_URL, redis:// or rediss://). Any prefix chosen when
// connecting the integration works (KV_, STORAGE_, kv_, …). Keys are paths
// derived with a secret; content is always encrypted. Redis has a far larger
// free allowance: the Blob store was suspended for exceeding the Hobby
// operations quota.
const envKeys = Object.keys(process.env);
const restPrefix = envKeys.find((k) => k.endsWith("_REST_API_URL") && process.env[k.replace(/_URL$/, "_TOKEN")]);
const REST_URL = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL || (restPrefix ? process.env[restPrefix] : "") || "";
const REST_TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN || (restPrefix ? process.env[restPrefix.replace(/_URL$/, "_TOKEN")] : "") || "";
const urlKey = ["REDIS_URL", "KV_URL"].find((k) => process.env[k])
  || envKeys.find((k) => /(^|_)(REDIS|KV)_URL$/i.test(k) && /^rediss?:\/\//.test(process.env[k] || ""));
const TCP_URL = urlKey ? process.env[urlKey] : "";
export const storage = (REST_URL && REST_TOKEN) || TCP_URL ? "redis" : "blob";

let tcpClient = null;
async function tcp() {
  if (!tcpClient) {
    const { createClient } = await import("redis");
    const client = createClient({ url: TCP_URL, socket: { connectTimeout: 8000 } });
    client.on("error", (e) => console.error("redis", e.message));
    tcpClient = client.connect().then(() => client).catch((e) => { tcpClient = null; throw e; });
  }
  return tcpClient;
}

async function redis(...command) {
  if (!(REST_URL && REST_TOKEN)) {
    const client = await tcp();
    return client.sendCommand(command.map(String));
  }
  const res = await fetch(REST_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${REST_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify(command),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || json.error) throw new Error(`redis ${command[0]}: ${json.error || res.status}`);
  return json.result;
}

export async function readObject(pathname) {
  if (storage === "redis") {
    const value = await redis("GET", pathname);
    return value == null ? null : decrypt(Buffer.from(value, "base64"));
  }
  const result = await get(pathname, { access: "private", useCache: false });
  if (!result) return null;
  const chunks = [];
  for await (const chunk of result.stream) chunks.push(Buffer.from(chunk));
  return decrypt(Buffer.concat(chunks));
}

/** `ttl` (seconds) only applies with Redis: caches expire on their own. */
export async function writeObject(pathname, obj, { overwrite = true, ttl } = {}) {
  if (storage === "redis") {
    const args = ["SET", pathname, encrypt(obj).toString("base64")];
    if (!overwrite) args.push("NX");
    if (ttl) args.push("EX", String(Math.round(ttl)));
    const ok = await redis(...args);
    if (!overwrite && ok == null) throw new Error("blob already exists");
    return;
  }
  await put(pathname, encrypt(obj), {
    access: "private",
    addRandomSuffix: false,
    allowOverwrite: overwrite,
    contentType: "application/octet-stream",
  });
}

/** Objects under a prefix: [{ pathname, url, uploadedAt }] (uploadedAt is null with Redis). */
export async function listObjects(prefix, { limit = Infinity } = {}) {
  const out = [];
  if (storage === "redis") {
    let cursor = "0";
    do {
      const [next, keys] = await redis("SCAN", cursor, "MATCH", `${prefix}*`, "COUNT", "1000");
      out.push(...keys.map((k) => ({ pathname: k, url: k, uploadedAt: null })));
      cursor = next;
    } while (cursor !== "0" && out.length < limit);
    return out.slice(0, limit === Infinity ? undefined : limit);
  }
  let cursor;
  do {
    const page = await list({ prefix, cursor, limit: Math.min(1000, limit) });
    out.push(...page.blobs);
    cursor = page.hasMore && out.length < limit ? page.cursor : undefined;
  } while (cursor);
  return out;
}

/** Deletes objects returned by listObjects. */
export async function deleteObjects(objects) {
  if (!objects.length) return;
  if (storage === "redis") {
    for (let i = 0; i < objects.length; i += 500) await redis("DEL", ...objects.slice(i, i + 500).map((o) => o.pathname));
    return;
  }
  await del(objects.map((o) => o.url));
}

export const userPath = (email) => `users/${hmac(email.trim().toLowerCase(), "user")}.bin`;
export const docPrefix = (uid) => `data/${hmac(uid, "data")}/`;
export const docPath = (uid, doc) => `${docPrefix(uid)}${doc}.bin`;
/** Written when an account is deleted: its tokens can no longer write anything. */
export const revokedPath = (uid) => `revoked/${hmac(uid, "revoked")}.bin`;
export async function isRevoked(uid) {
  return Boolean(await readObject(revokedPath(uid)).catch(() => null));
}

export async function readJSON(req) {
  if (req.body && typeof req.body === "object") return req.body;
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const text = Buffer.concat(chunks).toString("utf8");
  return text ? JSON.parse(text) : {};
}

export function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  if (!res.getHeader("Cache-Control")) res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}
