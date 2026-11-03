import test from "node:test";
import assert from "node:assert/strict";

const { sanitizeTolls, sanitizeEntry, publicTolls } = await import("../lib/tolls.js");
const { TOLLS_SEED } = await import("../lib/tolls-data.js");

test("tolls: the first edition is valid, every entry has an official source and a check date", () => {
  const r = sanitizeTolls(TOLLS_SEED);
  assert.equal(r.error, undefined, r.error);
  assert.equal(r.entries.length, TOLLS_SEED.length);
  for (const e of r.entries) {
    assert.match(e.source_url, /^https:\/\//);
    assert.match(e.verified_at, /^\d{4}-\d{2}-\d{2}$/);
    assert.ok(e.texts.it?.summary && e.texts.en?.summary, `${e.id}: summary it/en`);
  }
  const ids = r.entries.map((e) => e.id);
  assert.deepEqual(ids.filter((id, i) => ids.indexOf(id) !== i), []);
});

test("tolls: official prices of the first edition", () => {
  const byId = Object.fromEntries(sanitizeTolls(TOLLS_SEED).entries.map((e) => [e.id, e]));
  const price = (id, cls) => byId[id].prices.find((p) => p.class === cls)?.isk;
  assert.equal(price("vadlaheidargong", "under_3_5t"), 2216);
  assert.equal(price("hornafjordur", "under_3_5t"), 1500);
  assert.equal(price("thingvellir", "car_5"), 1000);
  assert.equal(price("skaftafell", "car_5"), 1110);
  assert.equal(price("landmannalaugar", "car_5"), 1500);
  assert.equal(price("dyrholaey", "car_5"), 750);
  assert.equal(price("kilometragjald", "under_3_5t"), 6.95);
  assert.equal(byId.hvalfjardargong.type, "info");
  assert.equal(byId.hvalfjardargong.prices.length, 0);
});

test("tolls: an entry without source, check date or a valid place is refused", () => {
  const base = { id: "x1", type: "paid_parking", name: "X", lat: 64.1, lon: -21.9, source_url: "https://example.is", verified_at: "2026-11-03", texts: { it: { summary: "s" } } };
  assert.ok(sanitizeEntry(base).entry);
  assert.match(sanitizeEntry({ ...base, source_url: "" }).error, /source_url/);
  assert.match(sanitizeEntry({ ...base, source_url: "http://x.is" }).error, /source_url/);
  assert.match(sanitizeEntry({ ...base, verified_at: "ieri" }).error, /verified_at/);
  assert.match(sanitizeEntry({ ...base, lat: 45, lon: 9 }).error, /Islanda/);
  assert.match(sanitizeEntry({ ...base, prices: [{ class: "car_5", isk: "mille", unit: "day" }] }).error, /prezzo/);
  assert.match(sanitizeEntry({ ...base, texts: {} }).error, /testo/);
  assert.match(sanitizeTolls([base, base]).error, /già usato/);
  // Unknown fields and payment methods are dropped, not passed to the app.
  const kept = sanitizeEntry({ ...base, secret: 1, pay_methods: ["online", "bitcoin"], pay_url: "javascript:alert(1)" }).entry;
  assert.equal(kept.secret, undefined);
  assert.deepEqual(kept.pay_methods, ["online"]);
  assert.equal(kept.pay_url, undefined);
});

test("tolls: public shape", () => {
  const p = publicTolls({ entries: [], updated_at: null });
  assert.deepEqual(p, { version: 1, updated_at: null, entries: [] });
});
