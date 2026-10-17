import { storage } from "../lib/core.js";
export default function handler(req, res) {
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify({ ok: true, service: "nordur-api", blob: Boolean(process.env.BLOB_READ_WRITE_TOKEN), storage, secret: Boolean(process.env.APP_SECRET) }));
}
