import { storage } from "../lib/core.js";
import { mailer } from "../lib/mail.js";
export default function handler(req, res) {
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify({ ok: true, service: "nordur-api", blob: Boolean(process.env.BLOB_READ_WRITE_TOKEN), storage, mail: mailer || "off", secret: Boolean(process.env.APP_SECRET) }));
}
