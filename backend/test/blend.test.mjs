// The map grid corrected with Veðurstofa Íslands (lib/blend.js) and the IMO
// parsing on the server (lib/imo.js), with real answers of 3 November 2026.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { correctGrid, weight, bilinear } from "../lib/blend.js";
import { parseForecasts, parseAWS, imoTime, STATIONS } from "../lib/imo.js";

const t0 = imoTime("2026-11-03 16:00:00"), t1 = t0 + 3600;
const lats = [64.0, 64.3], lons = [-22.0, -21.4];
const cell = () => ({ elevation: 10, hourly: { time: [t0, t1], temperature_2m: [5, 5], wind_speed_10m: [5, 5], wind_direction_10m: [180, 180],
  cloud_cover: [50, 50], precipitation: [0, 0], wind_gusts_10m: [8, 8], snowfall: [0, 0] } });
const grid = () => [cell(), cell(), cell(), cell()]; // (64,-22) (64,-21.4) (64.3,-22) (64.3,-21.4)
const station = { id: 1, name: "Test", lat: 64.0, lon: -22.0, elev: 10 };
const imo = new Map([[1, { steps: [{ t: t0, F: 10, D: 225, T: 8, N: 90, R: 0.4 }, { t: t1, F: 9, D: 225, T: 8, N: 90, R: 0 }] }]]);

test("IMO station forecasts parsed on the server (real answer)", () => {
  const list = parseForecasts(readFileSync(new URL("./fixtures/imo-forecasts.xml", import.meta.url), "utf8"));
  assert.deepEqual(list.map((f) => f.id), [1, 5544]);
  assert.equal(list[0].issued, imoTime("2026-11-03 15:00:00"));
  assert.deepEqual(list[0].steps[0], { t: t0, F: 5, D: 247.5, T: 7, N: 70, R: 0, hours: 1 });
  assert.equal(list[0].steps[4].R, 1);
});

test("10-minute measurements parsed (real answer)", () => {
  const m = parseAWS([{ station: 1350, time: "2026-11-03T17:40:00", t: 4.99, f: 3.75, fg: 4.54, d: 202 }]);
  assert.deepEqual(m.get(1350), { t: imoTime("2026-11-03 17:40:00"), F: 3.75, FG: 4.54, D: 202, T: 4.99 });
});

test("station bundle copied from the app", () => {
  const app = JSON.parse(readFileSync(new URL("../../Shared/Services/imo-stations.json", import.meta.url)));
  assert.deepEqual(STATIONS, app);
});

test("weights: distance and height", () => {
  assert.equal(weight(0, 0), 1);
  assert.equal(weight(20, 100), 1);
  assert.equal(weight(30, 0), 0.5);
  assert.equal(weight(45, 0), 0);
  assert.equal(weight(5, 400), 0);
  assert.equal(bilinear([1, 3, 1, 3], lats, lons, 64.0, -21.7), 2);
});

test("at the station the map takes IMO's values, far away the model's", () => {
  const r = correctGrid(grid(), lats, lons, [station], imo, new Map(), t0 - 86400);
  const at = r.forecasts[0].hourly, near = r.forecasts[1].hourly, far = r.forecasts[3].hourly;
  assert.equal(at.temperature_2m[0], 8);
  assert.equal(at.wind_speed_10m[0], 10);
  assert.equal(at.wind_direction_10m[0], 225);
  assert.equal(at.cloud_cover[0], 90);
  assert.equal(at.precipitation[0], 0.4);
  assert.equal(at.wind_gusts_10m[0], 10, "gust never below the corrected mean wind");
  assert.ok(near.temperature_2m[0] > 5 && near.temperature_2m[0] < 8, `fades with distance: ${near.temperature_2m[0]}`);
  assert.equal(far.temperature_2m[0], 5);
  assert.equal(r.stations[0].wind[0], 10);
  assert.equal(r.used, 1);
});

test("a station at another height corrects nothing", () => {
  const r = correctGrid(grid(), lats, lons, [{ ...station, elev: 600 }], imo, new Map(), t0 - 86400);
  assert.equal(r.forecasts[0].hourly.temperature_2m[0], 5);
});

test("now: the 10-minute measurement, fading into the forecast", () => {
  const obs = new Map([[1, { t: t0 - 300, F: 12, FG: 20, D: 270, T: 9 }]]);
  const r = correctGrid(grid(), lats, lons, [station], imo, obs, t0);
  const h = r.forecasts[0].hourly;
  assert.equal(h.temperature_2m[0], 9);
  assert.equal(h.wind_speed_10m[0], 12);
  assert.equal(h.wind_direction_10m[0], 270);
  assert.equal(h.wind_gusts_10m[0], 18, "gust difference capped at 10 m/s");
  assert.equal(h.temperature_2m[1], 8.8, "an hour later: 3/4 measurement, 1/4 forecast");
  assert.equal(r.stations[0].wind[0], 12);
  assert.equal(r.stations[0].obs.gust, 20);
  // A measurement older than 30 minutes is not "now".
  const old = correctGrid(grid(), lats, lons, [station], imo, new Map([[1, { t: t0 - 3600, F: 14, FG: 20, D: 270, T: 9 }]]), t0);
  assert.equal(old.forecasts[0].hourly.wind_speed_10m[0], 10);
});

test("differences are capped", () => {
  const wild = new Map([[1, { steps: [{ t: t0, F: 40, D: 180, T: 30, N: 50, R: 0 }] }]]);
  const r = correctGrid(grid(), lats, lons, [station], wild, new Map(), t0 - 86400);
  assert.equal(r.forecasts[0].hourly.temperature_2m[0], 11);
  assert.equal(r.forecasts[0].hourly.wind_speed_10m[0], 13);
});

test("a sheltered station does not calm a whole cell", () => {
  const calm = new Map([[1, { steps: [{ t: t0, F: 0, D: 180, T: 5, N: 50, R: 0 }] }]]);
  const g = grid(); g[0].hourly.wind_speed_10m[0] = 6;
  const r = correctGrid(g, lats, lons, [station], calm, new Map(), t0 - 86400);
  assert.equal(r.forecasts[0].hourly.wind_speed_10m[0], 2.4);
});
