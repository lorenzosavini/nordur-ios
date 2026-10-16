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

// Private Blob store; paths derived with a secret, content encrypted.
export async function readObject(pathname) {
  const result = await get(pathname, { access: "private", useCache: false });
  if (!result) return null;
  const chunks = [];
  for await (const chunk of result.stream) chunks.push(Buffer.from(chunk));
  return decrypt(Buffer.concat(chunks));
}

export async function writeObject(pathname, obj, { overwrite = true } = {}) {
  await put(pathname, encrypt(obj), {
    access: "private",
    addRandomSuffix: false,
    allowOverwrite: overwrite,
    contentType: "application/octet-stream",
  });
}

export async function listObjects(prefix) {
  const out = [];
  let cursor;
  do {
    const page = await list({ prefix, cursor, limit: 1000 });
    out.push(...page.blobs);
    cursor = page.hasMore ? page.cursor : undefined;
  } while (cursor);
  return out;
}

export async function deleteObjects(urls) {
  if (urls.length) await del(urls);
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
