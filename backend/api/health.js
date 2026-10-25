// GET  /api/health                -> service status
// GET  /api/health?config=1       -> what is free, Pro or off in the app, the App Store products, the notice (public)
// POST /api/health?admin=1        -> the admin panel's actions (lib/admin.js)
// POST /api/health?device=1 { token, env, lang } -> the phone's push token (lib/push.js)
import { storage } from "../lib/core.js";
import { mailer } from "../lib/mail.js";
import { adminHandler } from "../lib/admin.js";
import { readConfig, publicConfig } from "../lib/features.js";
import { registerDevice } from "../lib/push.js";
import { readJSON, send } from "../lib/core.js";

export default async function handler(req, res) {
  const params = new URL(req.url, "http://x").searchParams;
  if (params.has("admin")) return adminHandler(req, res);
  if (params.has("device")) {
    if (req.method !== "POST") return send(res, 405, { error: "method" });
    const r = await registerDevice(await readJSON(req).catch(() => ({})));
    return send(res, r.error ? 400 : 200, r);
  }
  res.setHeader("Content-Type", "application/json");
  if (params.has("config")) {
    const config = publicConfig(await readConfig().catch(() => ({ mode: "free", features: {}, products: [] })));
    res.setHeader("Cache-Control", "public, s-maxage=120, stale-while-revalidate=600");
    return res.end(JSON.stringify(config));
  }
  res.end(JSON.stringify({ ok: true, service: "nordur-api", blob: Boolean(process.env.BLOB_READ_WRITE_TOKEN), storage, mail: mailer || "off", secret: Boolean(process.env.APP_SECRET), admin: (process.env.ADMIN_PASSWORD || "").length >= 12 }));
}
