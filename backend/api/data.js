// Per-account documents (trip, settings, alerts, drives…).
//   GET    /api/data            -> { docs: [{ doc, updatedAt, size }] }
//   GET    /api/data?doc=trip   -> { doc, updatedAt, payload }
//   PUT    /api/data?doc=trip   { updatedAt, payload } -> { ok }
//   DELETE /api/data?doc=trip   -> { ok }
import { verifyToken, readObject, writeObject, listObjects, deleteObjects, docPrefix, docPath, readJSON, send, isRevoked } from "../lib/core.js";

const DOC = /^[a-z0-9][a-z0-9_-]{0,80}$/;

export default async function handler(req, res) {
  const uid = verifyToken(req.headers.authorization);
  if (!uid) return send(res, 401, { error: "Sessione scaduta, accedi di nuovo" });
  const url = new URL(req.url, "http://x");
  const doc = url.searchParams.get("doc");
  if (doc && !DOC.test(doc)) return send(res, 400, { error: "doc" });

  try {
    if (req.method === "GET" && !doc) {
      const blobs = await listObjects(docPrefix(uid));
      const docs = blobs.map((b) => ({
        doc: b.pathname.split("/").pop().replace(/\.bin$/, ""),
        updatedAt: b.uploadedAt,
        size: b.size,
      }));
      return send(res, 200, { docs });
    }
    if (req.method === "GET") {
      const stored = await readObject(docPath(uid, doc));
      if (!stored) return send(res, 404, { error: "not found" });
      return send(res, 200, { doc, ...stored });
    }
    if (req.method === "PUT") {
      if (await isRevoked(uid)) return send(res, 401, { error: "Account eliminato" });
      const { payload, updatedAt } = await readJSON(req);
      if (payload === undefined) return send(res, 400, { error: "payload" });
      await writeObject(docPath(uid, doc), { payload, updatedAt: updatedAt || new Date().toISOString() });
      return send(res, 200, { ok: true });
    }
    if (req.method === "DELETE") {
      const blobs = await listObjects(docPrefix(uid));
      const target = doc ? blobs.filter((b) => b.pathname.endsWith(`/${doc}.bin`)) : blobs;
      await deleteObjects(target.map((b) => b.url));
      return send(res, 200, { ok: true });
    }
    return send(res, 405, { error: "method" });
  } catch (e) {
    console.error(e);
    return send(res, 500, { error: "Errore del server" });
  }
}
