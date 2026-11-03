// Volcano status from real api.vedur.is answers (3 November 2026, trimmed).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { slimVolcanoes, latestWeekly, combine } from "../lib/volcanoes.js";

const raw = JSON.parse(readFileSync(new URL("./fixtures/volcanoes.json", import.meta.url)));
const vwr = JSON.parse(readFileSync(new URL("./fixtures/vwr.json", import.meta.url)));

test("only Iceland's volcanoes, with coordinates and codes", () => {
  const list = slimVolcanoes(raw);
  assert.deepEqual(list.map((v) => v.code).sort(), ["ASK", "KAT", "REY"]);
  const rey = list.find((v) => v.code === "REY");
  assert.equal(rey.aviation, "YELLOW");
  assert.equal(rey.level, 2);
  assert.equal(rey.levelText, "Heightened volcanic unrest");
  assert.ok(Math.abs(rey.lat - 63.817) < 1e-6 && Math.abs(rey.lon + 22.717) < 1e-6);
});

test("latest weekly report", () => {
  const w = latestWeekly(vwr);
  assert.equal(w.date, "2026-10-28T09:23:28.314083Z");
  assert.match(w.lines.REY, /Svartsengi/);
  assert.equal(w.notes, null);
  assert.equal(latestWeekly([]), null);
});

test("combined answer", () => {
  const body = combine(slimVolcanoes(raw), latestWeekly(vwr));
  assert.match(body.volcanoes.find((v) => v.code === "REY").report, /uplift/);
  assert.equal(body.volcanoes.find((v) => v.code === "KAT").report, null);
  assert.ok(JSON.stringify(body).length < 20000);
});

test("free translations: volcano terms corrected", async () => {
  const { applyFixes } = await import("../api/translate.js");
  assert.equal(applyFixes("it", "Disordini vulcanici intensificati"), "Attività vulcanica molto aumentata");
  assert.equal(applyFixes("it", "che una diga magmatica si propagherà verso la fila del cratere Sundhnúkur"),
    "che un dicco magmatico si propagherà verso l'allineamento di crateri Sundhnúkur");
  assert.equal(applyFixes("it", "La valutazione dei pericoli del Met Office islandese"), "La valutazione dei pericoli di Veðurstofa Íslands");
  assert.equal(applyFixes("de", "unverändert"), "unverändert");
});
