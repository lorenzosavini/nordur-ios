import test from "node:test";
import assert from "node:assert/strict";

process.env.APP_SECRET ||= "test-secret-".repeat(4);
const { totp } = await import("../lib/admin.js");
const { sanitize, publicConfig } = await import("../lib/features.js");

test("TOTP matches RFC 6238 (SHA-1 test vector)", () => {
  // Secret "12345678901234567890" in base32; T = 59 s -> step 1 -> 94287082 (last 6 digits 287082).
  assert.equal(totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 1), "287082");
  assert.equal(totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 37037036), "081804");
});

test("config: unknown features, bad rules and products are dropped; free by default", () => {
  const c = sanitize({ mode: "freemium", features: { "drive.flight3d": "pro", "nope": "pro", "webcams": "maybe", "offline": "off" }, products: ["it.app.pro", "bad id!", "it.app.pro"], paidThroughBuild: "170" });
  assert.equal(c.mode, "freemium");
  assert.deepEqual(c.features, { "drive.flight3d": "pro", offline: "off" });
  assert.deepEqual(c.products, ["it.app.pro"]);
  assert.equal(c.paidThroughBuild, 170);
  assert.equal(sanitize({}).mode, "free");
});

test("announcement shows only inside its dates", () => {
  const base = sanitize({ announcement: { texts: { it: { title: "F35 chiusa", text: "…" } }, until: "2021-01-01" } });
  assert.equal(publicConfig(base).announcement, null);
  const live = sanitize({ announcement: { texts: { it: { title: "F35 chiusa" } }, level: "warning" } });
  assert.equal(publicConfig(live).announcement.level, "warning");
});

test("a two-digit year is no date: the notice starts at once", () => {
  const c = sanitize({ announcement: { texts: { it: { title: "x" } }, from: "0022-10-25T23:28:04.000Z" } });
  assert.equal(c.announcement.from, null);
  assert.ok(publicConfig(c).announcement);
});

test("languages left empty are filled from Italian, hand-written ones are kept", async () => {
  const { fillLanguages } = await import("../lib/features.js");
  const fake = async (to, parts) => parts.map((p) => `${to}:${p}`);
  const out = await fillLanguages({ it: { title: "Strada chiusa", text: "F35" }, de: { title: "Eigener Text", text: "" } }, fake);
  assert.deepEqual(out.en, { title: "en:Strada chiusa", text: "en:F35", auto: true });
  assert.deepEqual(out.de, { title: "Eigener Text", text: "" });
  assert.equal(out.it.title, "Strada chiusa");
  // An automatic translation is redone when the source changes.
  const again = await fillLanguages({ ...out, it: { title: "Strada aperta", text: "" } }, fake);
  assert.deepEqual(again.fr, { title: "fr:Strada aperta", text: "", auto: true });
});

test("long texts are cut at sentence ends for the free translator", async () => {
  const { chunks } = await import("../api/translate.js");
  const text = "Gul viðvörun. ".repeat(60).trim();
  const parts = chunks(text);
  assert.ok(parts.length > 1 && parts.every((p) => p.length <= 450));
  assert.equal(parts.join(" ").replace(/\s+/g, " "), text);
});
