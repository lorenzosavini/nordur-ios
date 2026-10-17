// node --test backend/test
import test from "node:test";
import assert from "node:assert/strict";
import { mergeSeries, analyse, newellCoupling, newellKp, shockCandidates, propagation, nowcast } from "../lib/solarwind.js";
import { blend, weighted } from "../lib/kp.js";
import { utc } from "../lib/fetch.js";

const T0 = Date.parse("2026-10-16T12:00:00Z");
const minute = 60e3;

test("utc parses NOAA, DONKI and zone-less timestamps as UTC", () => {
  assert.equal(utc("2026-10-16T14:43:00"), Date.parse("2026-10-16T14:43:00Z"));
  assert.equal(utc("2026-10-14T03:00Z"), Date.parse("2026-10-14T03:00:00Z"));
  assert.equal(utc("2026-10-16 14:19:49.850"), Date.parse("2026-10-16T14:19:49.850Z"));
  assert.equal(utc(null), null);
});

test("dynamic pressure uses 1.6726e-6 · n · v² (nPa)", () => {
  const [row] = mergeSeries([{ t: T0, bt: 5, by: 0, bz: -5 }], [{ t: T0, v: 400, n: 5 }]);
  assert.ok(Math.abs(row.pdyn - 1.338) < 0.001);
});

test("Newell coupling is zero for northward IMF and maximal for southward", () => {
  assert.equal(newellCoupling({ v: 400, by: 0, bz: 5 }), 0);
  const south = newellCoupling({ v: 400, by: 0, bz: -5 });
  // v^4/3 · B^2/3 · sin^8/3(90°) = 400^(4/3) · 5^(2/3)
  assert.ok(Math.abs(south - Math.pow(400, 4 / 3) * Math.pow(5, 2 / 3)) < 1e-6);
});

test("Newell Kp grows with southward field and speed, and stays within 0–9", () => {
  const rows = (bz, v) => Array.from({ length: 60 }, (_, i) => ({ t: T0 + i * minute, by: 0, bz, v, n: 5 }));
  const quiet = newellKp(rows(3, 350)), storm = newellKp(rows(-20, 700));
  assert.ok(quiet < storm);
  assert.ok(storm <= 9 && quiet >= 0);
  assert.equal(newellKp(rows(-5, 400).slice(0, 5)), null); // too few samples
});

test("shock candidate needs speed, density and field jumps together", () => {
  const rows = Array.from({ length: 40 }, (_, i) => {
    const after = i >= 20;
    return { t: T0 + i * minute, v: after ? 520 : 420, n: after ? 12 : 5, bt: after ? 14 : 5, bz: -2 };
  });
  const found = shockCandidates(rows);
  assert.equal(found.length, 1);
  assert.equal(found[0].t, T0 + 20 * minute);
  const speedOnly = rows.map((r, i) => ({ ...r, n: 5, bt: 5 }));
  assert.equal(shockCandidates(speedOnly).length, 0);
});

test("propagation uses spacecraft X_GSE and |Vx|", () => {
  const rows = Array.from({ length: 30 }, (_, i) => ({ t: T0 + i * minute, v: 500, vx: -500 }));
  const p = propagation(rows, { x: 1.5e6, t: "2026-10-16T12:00:00Z" });
  assert.equal(p.minutes, 50);
  assert.ok(p.uncertaintyMinutes >= 10);
  assert.equal(propagation(rows, null), null);
});

test("nowcast: plasma measured at L1 is shifted to its arrival time at Earth", () => {
  // 90 min of data at 500 km/s from 1.5 million km: 50 min travel time.
  // Bz turns south at minute 60 at L1, i.e. it reaches Earth at minute 110.
  const rows = mergeSeries(
    Array.from({ length: 90 }, (_, i) => ({ t: T0 + i * minute, bt: 10, by: 0, bz: i >= 60 ? -10 : 3 })),
    Array.from({ length: 90 }, (_, i) => ({ t: T0 + i * minute, v: 500, n: 5, vx: -500 })),
  );
  const now = T0 + 90 * minute;
  const n = nowcast(rows, { x: 1.5e6 }, { now });
  assert.equal(n.steps.length, 7);
  assert.ok(n.coveredMinutes >= 48 && n.coveredMinutes <= 50, String(n.coveredMinutes));
  assert.equal(n.steps[0].bz, 3);
  assert.equal(n.steps[3].bz, -10);
  assert.ok(n.steps[4].newellKp > n.steps[0].newellKp);
  assert.equal(n.steps[6].known, false);
  assert.equal(nowcast(rows, null, { now }), null);
});

test("analyse reports persistence of southward Bz and moving averages", () => {
  const rows = mergeSeries(
    Array.from({ length: 90 }, (_, i) => ({ t: T0 + i * minute, bt: 8, by: 1, bz: i >= 60 ? -8 : 2 })),
    Array.from({ length: 90 }, (_, i) => ({ t: T0 + i * minute, v: 450, n: 4, vx: -450 })),
  );
  const a = analyse(rows, { now: T0 + 90 * minute });
  assert.equal(a.bzSouth.continuousMinutes, 30);
  assert.equal(a.averages[15].bz, -8);
  assert.equal(a.averages[60].samples, 60);
  assert.ok(Math.abs(a.bzSouth.fraction60 - 0.5) < 0.02);
});

test("blend keeps observed blocks, averages the current block, raises for NASA CMEs", () => {
  const now = Date.parse("2026-10-16T13:00:00Z");
  const forecast = [
    { t: Date.parse("2026-10-16T09:00:00Z"), kp: 2, kind: "observed" },
    { t: Date.parse("2026-10-16T12:00:00Z"), kp: 2, kind: "estimated" },
    { t: Date.parse("2026-10-17T12:00:00Z"), kp: 3, kind: "predicted" },
  ];
  const blocks = blend({
    forecast,
    estimated: [{ t: now - 5 * minute, kp: 4 }],
    newellKp: 3,
    donki: { arrivals: [{ arrival: "2026-10-17T14:00:00Z", durationHours: 12, glancing: false, kp: { min: 5, max: 7 } }] },
    now,
  });
  assert.equal(blocks[0].value, 2);
  assert.equal(blocks[0].driver, "osservato");
  assert.equal(blocks[1].value, weighted([[2, 1], [4, 2], [3, 1]])); // 3.25
  assert.equal(blocks[2].value, 5); // low end of NASA's 5–7 range
  assert.equal(blocks[2].driver, "CME NASA");
});

test("a stale 1-minute estimate is ignored", () => {
  const now = Date.parse("2026-10-16T13:00:00Z");
  const [b] = blend({ forecast: [{ t: Date.parse("2026-10-16T12:00:00Z"), kp: 2, kind: "estimated" }], estimated: [{ t: now - 3 * 3600e3, kp: 7 }], newellKp: null, now });
  assert.equal(b.value, 2);
});

import { destination, terrainAngle, profile, AZIMUTHS, DISTANCES_KM } from "../lib/horizon.js";

test("terrain: destination and curvature-corrected angles", () => {
  const [lat, lon] = destination(64, -21, 0, 111.2);
  assert.ok(Math.abs(lat - 65) < 0.01 && Math.abs(lon + 21) < 1e-9);
  assert.ok(Math.abs(terrainAngle(1000, 10) - 5.68) < 0.05); // atan(1000/10000) minus ~0.4 m-level drop
  assert.ok(terrainAngle(0, 40) < 0); // flat sea falls below the horizontal far away
  const flat = profile(0, AZIMUTHS.map(() => DISTANCES_KM.map(() => 0)));
  assert.ok(flat.every((p) => p.angle === 0));
  const north = profile(0, AZIMUTHS.map((_, i) => DISTANCES_KM.map((km) => (i === 0 && km === 5 ? 500 : 0))));
  assert.ok(north[0].angle > 5 && north[0].distanceKm === 5 && north[8].angle === 0);
});

import { digest } from "../lib/donki.js";

test("DONKI digest follows the documented WSA-ENLIL schema", () => {
  // Shape as published by CCMC (e.g. WSA-ENLIL run with Earth arrival 2024-06-09T22:07Z ±7 h, (kp)90=6).
  const enlil = [{
    simulationID: "WSA-ENLIL/31370/1", modelCompletionTime: "2024-06-08T10:00Z", au: 2,
    cmeInputs: [{ cmeStartTime: "2024-06-08T02:00Z", latitude: 5, longitude: -8, speed: 1265, halfAngle: 53, isMostAccurate: true, cmeid: "2024-06-08T02:00:00-CME-001" }],
    estimatedShockArrivalTime: "2024-06-09T22:07Z", estimatedDuration: 20, isEarthGB: false, kp_18: null, kp_90: 6, kp_135: 8, kp_180: 8,
    impactList: [{ location: "Earth", arrivalTime: "2024-06-09T22:07Z", isGlancingBlow: false }], link: "https://kauai.ccmc.gsfc.nasa.gov/DONKI/view/WSA-ENLIL/31370/1",
  }];
  const gst = [{ gstID: "2024-06-10T00:00:00-GST-001", startTime: "2024-06-10T00:00Z", allKpIndex: [{ observedTime: "2024-06-10T03:00Z", kpIndex: 6.33, source: "NOAA" }] }];
  const flr = [{ flrID: "F1", peakTime: "2024-06-08T01:50Z", classType: "X1.0", activeRegionNum: 13697 }, { flrID: "F2", peakTime: "2024-06-08T05:00Z", classType: "C3.2" }];
  const d = digest(gst, enlil, flr, Date.parse("2024-06-09T00:00:00Z"));
  assert.equal(d.arrivals.length, 1);
  assert.equal(d.arrivals[0].arrival, "2024-06-09T22:07:00.000Z");
  assert.deepEqual(d.arrivals[0].kp, { min: 6, max: 8 });
  assert.equal(d.arrivals[0].speed, 1265);
  assert.equal(d.storms[0].maxKp, 6.33);
  assert.deepEqual(d.flares.map((f) => f.classType), ["X1.0"]);
});
