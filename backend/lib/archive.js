// Historical storage for validation. One snapshot per 3-hour Kp block (keyed by
// block start, never overwritten): what was forecast, when it was issued, and
// what the live sources said. Old forecasts are kept, so accuracy can be
// measured against the Kp that is observed later (see /api/backtest).
import { writeObject } from "./core.js";
import { ovationAt } from "./sources.js";

// Reference sites in Iceland where the OVATION value is recorded.
export const SITES = [
  ["reykjavik", 64.1466, -21.9426], ["keflavik", 63.985, -22.6056], ["vik", 63.4186, -19.006], ["skogar", 63.5321, -19.5114],
  ["hofn", 64.2539, -15.2082], ["jokulsarlon", 64.0784, -16.2306], ["akureyri", 65.6885, -18.1262], ["myvatn", 65.6436, -16.91],
  ["egilsstadir", 65.2653, -14.3948], ["isafjordur", 66.075, -23.135], ["grundarfjordur", 64.9419, -23.3067], ["husavik", 66.0449, -17.3389],
];

const BLOCK = 3 * 3600e3;
let lastSlot = null; // per instance: avoids a write attempt on every request

export function slotKey(now = Date.now()) {
  const start = Math.floor(now / BLOCK) * BLOCK;
  return { start, key: `archive/aurora/${new Date(start).toISOString().slice(0, 13).replace("T", "/")}.bin` };
}

export function snapshot(state) {
  const sw = state.solarWind;
  return {
    issuedAt: state.generated,
    sources: Object.fromEntries(Object.entries(state.sources).map(([k, v]) => [k, v.status])),
    kpBlocks: state.kp.blocks.map((b) => ({ t: b.t, kind: b.kind, noaa: b.noaa, value: b.value, nasa: b.nasa, driver: b.driver })),
    kpEstimated: state.kp.estimated ? { t: state.kp.estimated.t, kp: state.kp.estimated.kp } : null,
    solarWind: sw ? { lastSample: sw.lastSample, spacecraft: sw.spacecraft, averages60: sw.averages?.[60], bzSouth: sw.bzSouth, newellKp: sw.newellKp, propagation: sw.propagation, shocks: sw.shocks } : null,
    ovation: state.ovation ? { observationTime: state.ovation.observationTime, forecastTime: state.ovation.forecastTime, sites: Object.fromEntries(SITES.map(([id, lat, lon]) => [id, ovationAt(state.ovation, lat, lon)])) } : null,
    hemisphericPower: state.hemisphericPower?.latest ?? null,
    enlilArrivals: state.enlil?.cmeArrivals ?? [],
    donkiArrivals: (state.donki?.arrivals || []).map((a) => ({ id: a.id, arrival: a.arrival, kp: a.kp, glancing: a.glancing })),
    alerts: (state.alerts || []).map((a) => ({ id: a.id, headline: a.headline, kp: a.kp })),
  };
}

export async function archiveSnapshot(state) {
  const { key } = slotKey(Date.parse(state.generated));
  if (lastSlot === key) return false;
  lastSlot = key;
  try {
    await writeObject(key, snapshot(state), { overwrite: false });
    return true;
  } catch (e) {
    // Already archived by another instance: expected.
    if (/exist/i.test(e.message)) return false;
    throw e;
  }
}
