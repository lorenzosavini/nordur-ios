// POST /api/auth  { mode: "register" | "login", email, password }  ->  { token, userId, email }
import crypto from "node:crypto";
import { hashPassword, safeEqual, issueToken, readObject, writeObject, userPath, readJSON, send } from "../lib/core.js";

export default async function handler(req, res) {
  if (req.method !== "POST") return send(res, 405, { error: "method" });
  try {
    const { mode, email, password } = await readJSON(req);
    const normalized = String(email || "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized)) return send(res, 400, { error: "Email non valida" });
    if (String(password || "").length < 8) return send(res, 400, { error: "La password deve avere almeno 8 caratteri" });

    const path = userPath(normalized);
    const existing = await readObject(path);

    if (mode === "register") {
      if (existing) return send(res, 409, { error: "Esiste già un account con questa email" });
      const { salt, hash } = await hashPassword(password);
      const user = { userId: crypto.randomUUID(), email: normalized, salt, hash, created: new Date().toISOString() };
      await writeObject(path, user);
      return send(res, 200, { token: issueToken(user.userId), userId: user.userId, email: normalized });
    }

    if (mode === "login") {
      if (!existing) return send(res, 401, { error: "Email o password errate" });
      const { hash } = await hashPassword(password, existing.salt);
      if (!safeEqual(hash, existing.hash)) return send(res, 401, { error: "Email o password errate" });
      return send(res, 200, { token: issueToken(existing.userId), userId: existing.userId, email: normalized });
    }

    return send(res, 400, { error: "mode" });
  } catch (e) {
    console.error(e);
    return send(res, 500, { error: "Errore del server" });
  }
}
