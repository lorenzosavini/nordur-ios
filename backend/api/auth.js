// Account management.
//   POST   /api/auth { mode: "register", email, password }            -> { token, userId, email, recoveryCode }
//   POST   /api/auth { mode: "login", email, password }               -> { token, userId, email }
//   POST   /api/auth { mode: "forgot", email, lang }                   -> { sent }   (e-mails a 6-digit code)
//   POST   /api/auth { mode: "reset", email, recoveryCode | emailCode, password } -> { token, userId, email, recoveryCode }
//   POST   /api/auth { mode: "change", email, password, newPassword } -> { ok }            (Bearer)
//   POST   /api/auth { mode: "recovery", email, password }            -> { recoveryCode }  (Bearer)
//   DELETE /api/auth { email, password }                              -> { ok, deleted }   (Bearer)
//
// E-mails (when a sender is configured, see lib/mail.js): welcome, new
// sign-in, password reset code (15 minutes, 5 tries), password reset or
// changed, recovery code renewed, account deleted. Password recovery also
// works without e-mail, with the one-time recovery code shown at sign-up
// (stored only as a scrypt hash, replaced after each use).
// Deleting the account removes the user record, every backed-up document and
// the user's aurora sightings.
import crypto from "node:crypto";
import { accountMail, mailer } from "../lib/mail.js";
import { hashPassword, safeEqual, issueToken, verifyToken, readObject, writeObject, userPath, listObjects, deleteObjects, readJSON, send, hmac } from "../lib/core.js";
import { deleteAccount, accountStatus } from "../lib/accounts.js";

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

function newRecoveryCode() {
  const bytes = crypto.randomBytes(16);
  const chars = [...bytes].map((b) => ALPHABET[b % ALPHABET.length]).join("");
  return chars.match(/.{4}/g).join("-"); // 16 chars ≈ 80 bits
}
const resetPath = (email) => `resets/${hmac(email, "reset")}.bin`;
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
    const lang = body.lang === "en" ? "en" : body.lang === "it" ? "it" : existing?.lang || "it";

    if (req.method === "DELETE") {
      const uid = verifyToken(req.headers.authorization);
      if (!uid || !existing || existing.userId !== uid) return send(res, 401, { error: "Sessione non valida, accedi di nuovo" });
      if (!(await checkPassword(existing, body.password))) return send(res, 401, { error: "Password errata" });
      // Tokens are stateless: the account is marked so they can no longer write.
      const deleted = await deleteAccount(existing);
      await accountMail("deleted", email, lang);
      return send(res, 200, { ok: true, deleted });
    }

    if (req.method !== "POST") return send(res, 405, { error: "method" });
    const mode = body.mode;

    if (mode === "register" || mode === "login" || mode === "reset") {
      if (String(body.password || "").length < 8) return send(res, 400, { error: "La password deve avere almeno 8 caratteri" });
    }

    if (mode === "register") {
      if (existing) return send(res, 409, { error: "Esiste già un account con questa email" });
      const { salt, hash } = await hashPassword(body.password);
      const { user, code } = await withRecovery({ userId: crypto.randomUUID(), email, salt, hash, lang, created: new Date().toISOString() });
      try {
        await writeObject(path, user, { overwrite: false });
      } catch (e) {
        if (/already exists/.test(e.message)) return send(res, 409, { error: "Esiste già un account con questa email" });
        throw e;
      }
      await accountMail("welcome", email, lang);
      return send(res, 200, { token: issueToken(user.userId), userId: user.userId, email, recoveryCode: code });
    }

    // The account's state for the app: Pro given by the admin, blocked.
    if (mode === "me") {
      const uid = verifyToken(req.headers.authorization);
      if (!uid || !existing || existing.userId !== uid) return send(res, 401, { error: "Sessione non valida, accedi di nuovo" });
      const day = new Date().toISOString().slice(0, 10);
      if (existing.lastSeen !== day) await writeObject(path, { ...existing, lastSeen: day }).catch(() => {});
      return send(res, 200, await accountStatus(existing));
    }

    if (mode === "login") {
      if (!(await checkPassword(existing, body.password))) return send(res, 401, { error: "Email o password errate" });
      if (existing.blocked) return send(res, 403, { error: "Account sospeso: scrivi al supporto di Norður" });
      await writeObject(path, { ...existing, lang: body.lang ? lang : existing.lang, lastLogin: new Date().toISOString() });
      await accountMail("login", email, lang);
      return send(res, 200, { token: issueToken(existing.userId), userId: existing.userId, email });
    }

    if (mode === "forgot") {
      if (!mailer) return send(res, 503, { error: "Invio email non attivo: usa il codice di recupero" });
      // The same answer whether or not the account exists.
      if (existing) {
        const rp = resetPath(email);
        const previous = await readObject(rp).catch(() => null);
        const now = Date.now();
        if (previous && now - previous.sentAt < 60e3) return send(res, 429, { error: "Attendi un minuto prima di chiedere un nuovo codice" });
        const code = String(crypto.randomInt(0, 1e6)).padStart(6, "0");
        const { salt, hash } = await hashPassword(code);
        await writeObject(rp, { salt, hash, sentAt: now, exp: now + 15 * 60e3, tries: 0 }, { ttl: 15 * 60 });
        if (!(await accountMail("resetCode", email, lang, code))) {
          return send(res, 502, { error: "Invio dell'email non riuscito: riprova o usa il codice di recupero" });
        }
      }
      return send(res, 200, { sent: true });
    }

    if (mode === "reset") {
      if (body.emailCode != null) {
        const rp = resetPath(email);
        const pending = existing ? await readObject(rp).catch(() => null) : null;
        const code = String(body.emailCode).replace(/\D/g, "");
        if (!pending || pending.exp < Date.now() || pending.tries >= 5 || code.length !== 6) {
          return send(res, 401, { error: "Codice scaduto o non valido: chiedine uno nuovo" });
        }
        const { hash: codeHash } = await hashPassword(code, pending.salt);
        if (!safeEqual(codeHash, pending.hash)) {
          const ttl = Math.max(1, Math.ceil((pending.exp - Date.now()) / 1000));
          await writeObject(rp, { ...pending, tries: pending.tries + 1 }, { ttl });
          return send(res, 401, { error: "Codice errato" });
        }
        await deleteObjects(await listObjects(rp, { limit: 1 }));
      } else {
        const code = normalizeCode(body.recoveryCode);
        if (!existing || !existing.recoveryHash || code.length !== 16) return send(res, 401, { error: "Email o codice di recupero errati" });
        const { hash: codeHash } = await hashPassword(code, existing.recoverySalt);
        if (!safeEqual(codeHash, existing.recoveryHash)) return send(res, 401, { error: "Email o codice di recupero errati" });
      }
      const { salt, hash } = await hashPassword(body.password);
      const { user, code: fresh } = await withRecovery({ ...existing, salt, hash, lang, passwordChanged: new Date().toISOString() });
      await writeObject(path, user);
      await accountMail("resetDone", email, lang);
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
        await accountMail("changed", email, lang);
        return send(res, 200, { ok: true });
      }
      const { user, code } = await withRecovery(existing);
      await writeObject(path, user);
      await accountMail("recovery", email, lang);
      return send(res, 200, { recoveryCode: code });
    }

    return send(res, 400, { error: "mode" });
  } catch (e) {
    console.error(e);
    return send(res, 500, { error: "Errore del server" });
  }
}
