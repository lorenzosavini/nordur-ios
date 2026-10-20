import test from "node:test";
import assert from "node:assert/strict";

process.env.APP_SECRET ||= "test-secret-".repeat(4);
const { mergeTrip } = await import("../api/data.js");

test("shared trips: the newer stop and attraction win, deletions stick, order does not matter", () => {
  const phoneA = { stops: [{ id: "s1", date: 1, modified: 5, name: "Vík", visits: [{ id: "v1", modified: 5, date: 10 }, { id: "v2", modified: 5, date: 11 }] }], tombstones: {} };
  const phoneB = {
    stops: [{ id: "s1", date: 1, modified: 7, name: "Vík í Mýrdal", visits: [{ id: "v1", modified: 9, date: 12 }] }, { id: "s2", date: 2, modified: 6, visits: [] }],
    tombstones: { v2: 8 },
  };
  const ab = mergeTrip(phoneA, phoneB);
  assert.deepEqual(ab, mergeTrip(phoneB, phoneA));
  assert.equal(ab.stops.length, 2);
  assert.equal(ab.stops[0].name, "Vík í Mýrdal");
  assert.deepEqual(ab.stops[0].visits.map((v) => [v.id, v.date]), [["v1", 12]]);
  // A stop edited after it was deleted elsewhere comes back; one deleted later stays gone.
  assert.equal(mergeTrip({ stops: [{ id: "s3", modified: 20, visits: [] }], tombstones: {} }, { stops: [], tombstones: { s3: 10 } }).stops.length, 1);
  assert.equal(mergeTrip({ stops: [{ id: "s3", modified: 5, visits: [] }], tombstones: {} }, { stops: [], tombstones: { s3: 10 } }).stops.length, 0);
});
