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
  const base = sanitize({ announcement: { texts: { it: { title: "F35 chiusa", text: "…" } }, until: "2000-01-01" } });
  assert.equal(publicConfig(base).announcement, null);
  const live = sanitize({ announcement: { texts: { it: { title: "F35 chiusa" } }, level: "warning" } });
  assert.equal(publicConfig(live).announcement.level, "warning");
});
