// Ingestion + normalisation of the official space-weather feeds.
// Every loader returns { data, meta } where meta records provider, endpoint,
// the time the data refers to and when it was published, so the client can
// show provenance and refuse to present old data as live.
import { fetchJSON, fetchText, utc, iso } from "./fetch.js";
import { mergeSeries, analyse } from "./solarwind.js";

const SWPC = "https://services.swpc.noaa.gov";

const meta = (provider, endpoint, extra = {}) => ({ provider, endpoint, fetchedAt: iso(Date.now()), ...extra });
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : typeof v === "string" && v.trim() !== "" && Number.isFinite(+v) ? +v : null);

// ---------- Kp ----------

/** NOAA 3-hour Kp: observed + estimated + predicted blocks (each block starts at time_tag). */
export async function kpForecast() {
  const endpoint = `${SWPC}/products/noaa-planetary-k-index-forecast.json`;
  const rows = await fetchJSON(endpoint);
  const data = rows
    .map((r) => (Array.isArray(r) ? { time_tag: r[0], kp: r[1], observed: r[2] } : r))
    .map((r) => ({ t: utc(r.time_tag), kp: num(r.kp), kind: r.observed || "predicted" }))
    .filter((r) => r.t && r.kp != null && r.kind !== "observed_kp")
    .sort((a, b) => a.t - b.t);
  const lastObserved = data.filter((r) => r.kind === "observed").at(-1);
  return { data, meta: meta("NOAA SWPC", endpoint, { validFrom: iso(data[0]?.t), validTo: iso(data.at(-1)?.t + 3 * 3600e3), lastObserved: iso(lastObserved?.t) }) };
}

/** NOAA estimated planetary Kp, 1-minute cadence (provisional, not the official Kp). */
export async function kpEstimated() {
  const endpoint = `${SWPC}/json/planetary_k_index_1m.json`;
  const rows = await fetchJSON(endpoint);
  const data = rows.map((r) => ({ t: utc(r.time_tag), kp: num(r.estimated_kp) })).filter((r) => r.t && r.kp != null);
  return { data, meta: meta("NOAA SWPC", endpoint, { observedAt: iso(data.at(-1)?.t) }) };
}

// GFZ answers in a fraction of a second or not at all (30+ s): a short timeout,
// no retry, and the last good answer of this instance when it does not answer.
const GFZ = { timeout: 5000, retries: 0 };
const lastGood = new Map();
async function remembered(name, load) {
  try {
    const result = await load();
    lastGood.set(name, result);
    return result;
  } catch (e) {
    const previous = lastGood.get(name);
    if (previous) return { ...previous, meta: { ...previous.meta, cachedCopy: true, error: String(e.message || e) } };
    throw e;
  }
}

/** GFZ Potsdam Kp (the official producer of Kp): definitive / preliminary / nowcast, CC BY 4.0. */
export async function kpGFZ() { return remembered("kpGFZ", kpGFZLive); }
async function kpGFZLive() {
  const start = new Date(Date.now() - 3 * 864e5).toISOString().slice(0, 10) + "T00:00:00Z";
  const end = new Date(Date.now() + 864e5).toISOString().slice(0, 10) + "T00:00:00Z";
  const endpoint = `https://kp.gfz.de/app/json/?start=${start}&end=${end}&index=Kp&status=all`;
  const json = await fetchJSON(endpoint, GFZ);
  const data = (json.datetime || []).map((t, i) => ({ t: utc(t), kp: num(json.Kp?.[i]), status: json.status?.[i] || null })).filter((r) => r.t && r.kp != null);
  return { data, meta: meta("GFZ Potsdam", "https://kp.gfz.de/app/json/", { license: json.meta?.license || "CC BY 4.0", observedAt: iso(data.at(-1)?.t) }) };
}

/** GFZ Hp30: the Kp scale over 30 minutes instead of 3 hours (CC BY 4.0). */
export async function hp30() { return remembered("hp30", hp30Live); }
async function hp30Live() {
  const start = new Date(Date.now() - 864e5).toISOString().slice(0, 19) + "Z";
  const end = new Date(Date.now() + 3600e3).toISOString().slice(0, 19) + "Z";
  const endpoint = `https://kp.gfz.de/app/json/?start=${start}&end=${end}&index=Hp30`;
  const json = await fetchJSON(endpoint, GFZ);
  const data = (json.datetime || []).map((t, i) => ({ t: utc(t), hp30: num(json.Hp30?.[i]) })).filter((r) => r.t && r.hp30 != null);
  if (!data.length) throw new Error("Hp30 vuoto");
  return { data, meta: meta("GFZ Potsdam", "https://kp.gfz.de/app/json/", { license: json.meta?.license || "CC BY 4.0", observedAt: iso(data.at(-1).t) }) };
}

/**
 * Ground magnetometer nearest to Iceland with minute data in near real time:
 * Narsarsuaq, south Greenland (DTU Space, INTERMAGNET via BGS GIN). Leirvogur
 * (Iceland) is not published in real time. The range of the horizontal field
 * over the last hour says how disturbed the field is under the auroral oval.
 */
export async function magnetometer(now = Date.now()) {
  const code = "NAQ";
  const day = (t) => new Date(t).toISOString().slice(0, 10);
  const url = (d) => `https://imag-data.bgs.ac.uk/GIN_V1/GINServices?Request=GetData&format=json&testObsys=0&observatoryIagaCode=${code}&samplesPerDay=minute&publicationState=best-avail&dataStartDate=${d}&dataDuration=1&orientation=native`;
  const days = [...new Set([day(now - 3 * 3600e3), day(now)])];
  const parts = await Promise.all(days.map((d) => fetchJSON(url(d), { timeout: 15000 })));
  const rows = [];
  for (const json of parts) {
    (json.datetime || []).forEach((t, i) => {
      const x = num(json.X?.[i]), y = num(json.Y?.[i]);
      if (x != null && y != null && x < 90000) rows.push({ t: utc(t), h: Math.hypot(x, y) });
    });
  }
  const recent = rows.filter((r) => r.t <= now && r.t > now - 3 * 3600e3).sort((a, b) => a.t - b.t);
  if (!recent.length) throw new Error("magnetometro senza dati recenti");
  const last = recent.at(-1);
  const hour = recent.filter((r) => r.t > last.t - 3600e3).map((r) => r.h);
  const range = Math.round(Math.max(...hour) - Math.min(...hour));
  const level = range >= 400 ? 3 : range >= 150 ? 2 : range >= 50 ? 1 : 0;
  const series = recent.filter((_, i) => i % 10 === 0).map((r) => ({ t: iso(r.t), h: Math.round(r.h) }));
  return {
    data: { station: "Narsarsuaq (NAQ)", lat: 61.16, lon: -45.44, observed: iso(last.t), rangeNt: range, level, series },
    meta: meta("DTU Space · INTERMAGNET (BGS GIN)", "https://imag-data.bgs.ac.uk/GIN_V1/", { observedAt: iso(last.t) }),
  };
}

// ---------- Solar wind ----------

export async function solarWind() {
  const [mag, wind, eph] = await Promise.all([
    fetchJSON(`${SWPC}/json/rtsw/rtsw_mag_1m.json`, { timeout: 20000 }),
    fetchJSON(`${SWPC}/json/rtsw/rtsw_wind_1m.json`, { timeout: 20000 }),
    fetchJSON(`${SWPC}/json/rtsw/rtsw_ephemerides_1h.json`, { timeout: 20000 }).catch(() => []),
  ]);
  const cutoff = Date.now() - 3 * 3600e3;
  const magRows = mag.filter((r) => r.active && utc(r.time_tag) >= cutoff).map((r) => ({
    t: utc(r.time_tag), bt: num(r.bt), by: num(r.by_gsm), bz: num(r.bz_gsm), quality: num(r.overall_quality),
  })).filter((r) => r.bz != null);
  const windRows = wind.filter((r) => r.active && utc(r.time_tag) >= cutoff).map((r) => ({
    t: utc(r.time_tag), v: num(r.proton_speed), n: num(r.proton_density), temp: num(r.proton_temperature),
    vx: num(r.proton_vx_gse), quality: num(r.overall_quality),
  })).filter((r) => r.v != null);
  const spacecraft = (mag.find((r) => r.active) || wind.find((r) => r.active) || {}).source || null;
  const ephRow = eph.filter((r) => r.active && num(r.x_gse) != null).sort((a, b) => utc(b.time_tag) - utc(a.time_tag))[0];
  const ephemeris = ephRow ? { t: iso(utc(ephRow.time_tag)), x: num(ephRow.x_gse), y: num(ephRow.y_gse), z: num(ephRow.z_gse) } : null;
  const rows = mergeSeries(magRows, windRows);
  const analysis = analyse(rows, { ephemeris, spacecraft });
  return {
    data: analysis,
    meta: meta("NOAA SWPC RTSW", `${SWPC}/json/rtsw/`, { spacecraft, observedAt: iso(analysis?.lastSample) }),
  };
}

// ---------- OVATION ----------

/**
 * OVATION Prime short-term forecast. Values 0–100 on a 1°×1° grid; NOAA
 * labels them "probability of visible aurora" for the forecast time, i.e.
 * a model quantity, not a calibrated chance for a given observer.
 * Kept: northern hemisphere 30°N–90°N, row-major by latitude, 360 longitudes.
 */
export async function ovation() {
  const endpoint = `${SWPC}/json/ovation_aurora_latest.json`;
  const json = await fetchJSON(endpoint, { timeout: 20000 });
  const latMin = 30, rows = 61;
  const grid = new Array(rows * 360).fill(0);
  for (const [lon, lat, value] of json.coordinates || []) {
    if (lat < latMin || lat > 90) continue;
    const x = ((Math.round(lon) % 360) + 360) % 360;
    grid[(Math.round(lat) - latMin) * 360 + x] = Math.round(value);
  }
  const observation = utc(json["Observation Time"]), forecast = utc(json["Forecast Time"]);
  return {
    data: { observationTime: iso(observation), forecastTime: iso(forecast), latMin, rows, grid },
    meta: meta("NOAA SWPC OVATION Prime", endpoint, { observedAt: iso(observation), validAt: iso(forecast) }),
  };
}

export function ovationAt(o, lat, lon) {
  if (!o || lat < o.latMin || lat > 90) return null;
  const x = ((Math.round(lon) % 360) + 360) % 360;
  return o.grid[(Math.round(lat) - o.latMin) * 360 + x];
}

// ---------- ENLIL (NOAA run) ----------

/**
 * NOAA SWPC WSA-ENLIL time series at Earth: predicted solar-wind speed and
 * density for the next days, with the "cloud" field marking CME material.
 * The model does not predict Bz, so it cannot by itself predict storm strength.
 */
export async function enlil() {
  const endpoint = `${SWPC}/json/enlil_time_series.json`;
  const rows = await fetchJSON(endpoint, { timeout: 20000 });
  const series = rows.map((r) => ({ t: utc(r.time_tag), v: num(r.v_r), n: num(r.earth_particles_per_cm3), cloud: num(r.cloud) }))
    .filter((r) => r.t && r.v != null).sort((a, b) => a.t - b.t);
  const now = Date.now();
  const hourly = [];
  for (let t = Math.ceil(now / 3600e3) * 3600e3; t <= (series.at(-1)?.t ?? 0); t += 3 * 3600e3) {
    const near = series.reduce((best, r) => (Math.abs(r.t - t) < Math.abs(best.t - t) ? r : best), series[0]);
    if (Math.abs(near.t - t) > 2 * 3600e3) continue;
    hourly.push({ t: iso(t), v: Math.round(near.v), n: Math.round(near.n * 10) / 10, pdyn: Math.round(1.6726e-6 * near.n * near.v * near.v * 100) / 100, cloud: (near.cloud ?? 0) > 0 });
  }
  const arrivals = [];
  for (let i = 1; i < series.length; i++) {
    if ((series[i].cloud ?? 0) > 0 && !((series[i - 1].cloud ?? 0) > 0) && series[i].t > now - 12 * 3600e3) {
      const block = series.slice(i, i + 200).filter((r) => (r.cloud ?? 0) > 0);
      arrivals.push({ t: iso(series[i].t), peakSpeed: Math.round(Math.max(...block.map((r) => r.v))) });
    }
  }
  return {
    data: { modelStart: iso(series[0]?.t), modelEnd: iso(series.at(-1)?.t), samples: hourly, cmeArrivals: arrivals },
    meta: meta("NOAA SWPC WSA-ENLIL", endpoint, { validFrom: iso(series[0]?.t), validTo: iso(series.at(-1)?.t) }),
  };
}

// ---------- Scales, alerts, hemispheric power ----------

export async function scales() {
  const endpoint = `${SWPC}/products/noaa-scales.json`;
  const json = await fetchJSON(endpoint);
  const data = Object.entries(json).map(([k, v]) => ({ index: +k, date: v.DateStamp, g: num(v.G?.Scale) ?? 0, gText: v.G?.Text ?? null }))
    .filter((r) => r.index >= 0).sort((a, b) => a.index - b.index).map((r) => ({ ...r, forecast: r.index > 0 }));
  return { data, meta: meta("NOAA SWPC", endpoint) };
}

/** Geomagnetic watches/warnings/alerts of the last 48 h; cancellations remove the cancelled message. */
export async function alerts(hours = 48) {
  const endpoint = `${SWPC}/products/alerts.json`;
  const rows = await fetchJSON(endpoint);
  const cutoff = Date.now() - hours * 3600e3;
  const parsed = rows.map((r) => {
    const text = String(r.message || "").replace(/\r/g, "");
    const lines = text.split("\n").map((l) => l.trim());
    const serial = (text.match(/Serial Number:\s*(\d+)/) || [])[1] || null;
    const cancels = (text.match(/Cancel Serial Number:\s*(\d+)/) || [])[1] || null;
    const headline = lines.find((l) => /^(ALERT|WARNING|WATCH|EXTENDED WARNING|SUMMARY|CANCEL[A-Z ]*):/.test(l)) || "";
    const kp = (headline.match(/K-index of (\d)/) || [])[1];
    const g = (text.match(/\bG(\d)\b/) || [])[1];
    const extends_ = (text.match(/Extension to Serial Number:\s*(\d+)/) || [])[1] || null;
    const valid = (text.match(/(?:Valid To|Now Valid Until):\s*([0-9]{4} [A-Za-z]{3} \d{2} \d{4}) UTC/) || [])[1];
    const synoptic = (text.match(/Synoptic Period:\s*(\d{2})00-(\d{2})00/) || []);
    const issued = utc(r.issue_datetime);
    let validTo = valid ? Date.parse(valid.replace(/(\d{2})(\d{2})$/, "$1:$2") + " UTC") : null;
    // A K-index ALERT is valid for its 3-hour synoptic period.
    if (!validTo && synoptic[2] && issued) {
      const d = new Date(issued); d.setUTCHours(+synoptic[2] === 24 ? 24 : +synoptic[2], 0, 0, 0); validTo = d.getTime();
    }
    return {
      id: `${r.product_id}-${serial || r.issue_datetime}`,
      code: r.product_id, serial, cancels, extends: extends_,
      issued: iso(issued), validTo: iso(validTo),
      headline, kp: kp ? +kp : null, g: g ? +g : null,
      geomagnetic: /geomagnetic|K-index|Sudden Impulse/i.test(text),
    };
  });
  const cancelled = new Set(parsed.map((p) => p.cancels).filter(Boolean));
  const superseded = new Set(parsed.map((p) => p.extends).filter(Boolean));
  const now = Date.now();
  const data = parsed
    .filter((p) => p.geomagnetic && !p.cancels && !cancelled.has(p.serial) && !superseded.has(p.serial))
    .map((p) => ({ ...p, active: p.validTo ? Date.parse(p.validTo) > now : now - Date.parse(p.issued) < 3 * 3600e3 }))
    .filter((p) => p.active || Date.parse(p.issued) >= cutoff)
    .sort((a, b) => Date.parse(b.issued) - Date.parse(a.issued));
  return { data, meta: meta("NOAA SWPC", endpoint) };
}

/** OVATION hemispheric power (GW), 30-minute forecast, 5-minute cadence. */
export async function hemisphericPower() {
  const endpoint = `${SWPC}/text/aurora-nowcast-hemi-power.txt`;
  const text = await fetchText(endpoint);
  const rows = text.split("\n").filter((l) => l.trim() && !l.startsWith("#")).map((l) => l.trim().split(/\s+/))
    .map((c) => ({ observed: iso(utc(c[0]?.replace("_", "T"))), forecast: iso(utc(c[1]?.replace("_", "T"))), north: num(c[2]), south: num(c[3]) }))
    .filter((r) => r.north != null);
  const last = rows.at(-1) || null;
  return { data: { latest: last, series: rows.slice(-36).map((r) => ({ t: r.forecast, gw: r.north })) }, meta: meta("NOAA SWPC", endpoint, { observedAt: last?.observed, validAt: last?.forecast }) };
}

// ---------- Long term ----------

/** 27-day outlook: daily F10.7, planetary A index and largest expected Kp (issued weekly). */
export async function outlook27() {
  const endpoint = `${SWPC}/text/27-day-outlook.txt`;
  const text = await fetchText(endpoint);
  const issued = (text.match(/:Issued:\s*(.+UTC)/) || [])[1] || null;
  const data = [...text.matchAll(/^(\d{4} [A-Za-z]{3} \d{2})\s+(\d+)\s+(\d+)\s+(\d+)\s*$/gm)].map((m) => ({
    date: new Date(Date.parse(m[1] + " UTC")).toISOString().slice(0, 10), f107: +m[2], ap: +m[3], kpMax: +m[4],
  }));
  return { data, meta: meta("NOAA SWPC", endpoint, { issued: issued ? iso(Date.parse(issued.replace(/(\d{2})(\d{2}) UTC$/, "$1:$2 UTC"))) : null }) };
}

/** 45-day forecast of daily Ap and F10.7 (US Air Force / SWPC). */
export async function forecast45() {
  const endpoint = `${SWPC}/json/45-day-forecast.json`;
  const json = await fetchJSON(endpoint);
  const byDay = new Map();
  for (const r of json.data || []) {
    const d = String(r.time).slice(0, 10);
    const row = byDay.get(d) || { date: d };
    row[r.metric] = num(r.value);
    byDay.set(d, row);
  }
  return { data: [...byDay.values()].sort((a, b) => a.date.localeCompare(b.date)), meta: meta("NOAA SWPC", endpoint, { issued: json.issued || null }) };
}
