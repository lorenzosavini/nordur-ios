// Account management.
//   POST   /api/auth { mode: "register", email, password }            -> { token, userId, email, recoveryCode }
//   POST   /api/auth { mode: "login", email, password }               -> { token, userId, email }
//   POST   /api/auth { mode: "reset", email, recoveryCode, password } -> { token, userId, email, recoveryCode }
//   POST   /api/auth { mode: "change", email, password, newPassword } -> { ok }            (Bearer)
//   POST   /api/auth { mode: "recovery", email, password }            -> { recoveryCode }  (Bearer)
//   DELETE /api/auth { email, password }                              -> { ok, deleted }   (Bearer)
//
// No e-mail is sent: password recovery uses a one-time recovery code shown at
// sign-up (stored only as a scrypt hash, replaced after each use).
// Deleting the account removes the user record, every backed-up document and
// the user's aurora sightings.
import crypto from "node:crypto";
import { hashPassword, safeEqual, issueToken, verifyToken, readObject, writeObject, userPath, docPrefix, revokedPath, listObjects, deleteObjects, readJSON, send, hmac } from "../lib/core.js";

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

function newRecoveryCode() {
  const bytes = crypto.randomBytes(16);
  const chars = [...bytes].map((b) => ALPHABET[b % ALPHABET.length]).join("");
  return chars.match(/.{4}/g).join("-"); // 16 chars ≈ 80 bits
}
const normalizeCode = (c) => String(c || "").toUpperCase().replace(/[^A-Z0-9]/g, "");

async function withRecovery(user) {
  const code = newRecoveryCode();
  const { salt, hash } = await hashPassword(normalizeCode(code));
  return { user: { ...user, recoverySalt: salt, recoveryHash: hash }, code };
}

async function checkPassword(user, password) {
  if (!user) return false;
  const { hash } = await hashPassword(String(password || ""), user.salt);
  return safeEqual(hash, user.hash);
}

export default async function handler(req, res) {
  try {
    const body = await readJSON(req).catch(() => ({}));
    const email = String(body.email || "").trim().toLowerCase();
    if (!EMAIL.test(email)) return send(res, 400, { error: "Email non valida" });
    const path = userPath(email);
    const existing = await readObject(path);

    if (req.method === "DELETE") {
      const uid = verifyToken(req.headers.authorization);
      if (!uid || !existing || existing.userId !== uid) return send(res, 401, { error: "Sessione non valida, accedi di nuovo" });
      if (!(await checkPassword(existing, body.password))) return send(res, 401, { error: "Password errata" });
      const docs = await listObjects(docPrefix(uid));
      await deleteObjects(docs);
      const tag = hmac(uid, "sighting").slice(0, 16);
      const mine = (await listObjects("sightings/")).filter((b) => b.pathname.endsWith(`-${tag}.bin`));
      await deleteObjects(mine);
      const sightings = mine.length;
      await deleteObjects(await listObjects(path, { limit: 1 }));
      // Tokens are stateless: mark the account so they can no longer write.
      await writeObject(revokedPath(uid), { deleted: new Date().toISOString() });
      return send(res, 200, { ok: true, deleted: { documents: docs.length, sightings } });
    }

    if (req.method !== "POST") return send(res, 405, { error: "method" });
    const mode = body.mode;

    if (mode === "register" || mode === "login" || mode === "reset") {
      if (String(body.password || "").length < 8) return send(res, 400, { error: "La password deve avere almeno 8 caratteri" });
    }

    if (mode === "register") {
      if (existing) return send(res, 409, { error: "Esiste già un account con questa email" });
      const { salt, hash } = await hashPassword(body.password);
      const { user, code } = await withRecovery({ userId: crypto.randomUUID(), email, salt, hash, created: new Date().toISOString() });
      await writeObject(path, user);
      return send(res, 200, { token: issueToken(user.userId), userId: user.userId, email, recoveryCode: code });
    }

    if (mode === "login") {
      if (!(await checkPassword(existing, body.password))) return send(res, 401, { error: "Email o password errate" });
      return send(res, 200, { token: issueToken(existing.userId), userId: existing.userId, email });
    }

    if (mode === "reset") {
      const code = normalizeCode(body.recoveryCode);
      if (!existing || !existing.recoveryHash || code.length !== 16) return send(res, 401, { error: "Email o codice di recupero errati" });
      const { hash: codeHash } = await hashPassword(code, existing.recoverySalt);
      if (!safeEqual(codeHash, existing.recoveryHash)) return send(res, 401, { error: "Email o codice di recupero errati" });
      const { salt, hash } = await hashPassword(body.password);
      const { user, code: fresh } = await withRecovery({ ...existing, salt, hash, passwordChanged: new Date().toISOString() });
      await writeObject(path, user);
      return send(res, 200, { token: issueToken(user.userId), userId: user.userId, email, recoveryCode: fresh });
    }

    if (mode === "change" || mode === "recovery") {
      const uid = verifyToken(req.headers.authorization);
      if (!uid || !existing || existing.userId !== uid) return send(res, 401, { error: "Sessione non valida, accedi di nuovo" });
      if (!(await checkPassword(existing, body.password))) return send(res, 401, { error: "Password errata" });
      if (mode === "change") {
        if (String(body.newPassword || "").length < 8) return send(res, 400, { error: "La nuova password deve avere almeno 8 caratteri" });
        const { salt, hash } = await hashPassword(body.newPassword);
        await writeObject(path, { ...existing, salt, hash, passwordChanged: new Date().toISOString() });
        return send(res, 200, { ok: true });
      }
      const { user, code } = await withRecovery(existing);
      await writeObject(path, user);
      return send(res, 200, { recoveryCode: code });
    }

    return send(res, 400, { error: "mode" });
  } catch (e) {
    console.error(e);
    return send(res, 500, { error: "Errore del server" });
  }
}
