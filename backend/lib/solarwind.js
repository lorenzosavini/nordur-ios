// Real-time solar wind analysis (NOAA SWPC RTSW, 1-minute data, operational
// spacecraft only). Everything here is derived from measured values; when a
// quantity cannot be computed it is null, never guessed.
//
// Conventions
//   B in nT, GSM frame for By/Bz (the frame that matters for coupling).
//   v in km/s (bulk proton speed), n in protons/cm³, T in K.
//   Pdyn ≈ 1.6726e-6 · n · v² nPa (protons only; alphas, typically 2–5 % by
//   number, are ignored, so the true value is usually a few % higher).

const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : null);

export function mergeSeries(mag, wind) {
  const byMinute = new Map();
  const minute = (t) => Math.floor(t / 60000);
  for (const r of mag) {
    byMinute.set(minute(r.t), { t: r.t, bt: r.bt, by: r.by, bz: r.bz, magQuality: r.quality });
  }
  for (const r of wind) {
    const key = minute(r.t);
    const row = byMinute.get(key) || { t: r.t };
    Object.assign(row, { v: r.v, n: r.n, temp: r.temp, vx: r.vx, plasmaQuality: r.quality });
    byMinute.set(key, row);
  }
  return [...byMinute.values()]
    .sort((a, b) => a.t - b.t)
    .map((r) => ({ ...r, pdyn: r.n != null && r.v != null ? 1.6726e-6 * r.n * r.v * r.v : null }));
}

const mean = (rows, key) => {
  const values = rows.map((r) => r[key]).filter((v) => v != null);
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
};
const extreme = (rows, key, fn) => {
  const values = rows.map((r) => r[key]).filter((v) => v != null);
  return values.length ? fn(...values) : null;
};
const round = (v, d = 2) => (v == null ? null : Math.round(v * 10 ** d) / 10 ** d);

/** Newell et al. (2007) coupling dΦMP/dt = v^4/3 · BT^2/3 · sin^8/3(θc/2), BT and θc in the GSM y–z plane. */
export function newellCoupling(r) {
  if (r.v == null || r.by == null || r.bz == null) return null;
  const bt = Math.hypot(r.by, r.bz);
  const theta = Math.atan2(r.by, r.bz);
  return Math.pow(r.v, 4 / 3) * Math.pow(bt, 2 / 3) * Math.pow(Math.abs(Math.sin(theta / 2)), 8 / 3);
}

/** Kp fitted from solar wind (Newell et al. 2007/2008): statistical, hourly-scale, biased high when quiet. */
export function newellKp(rows) {
  const terms = rows
    .map((r) => ({ c: newellCoupling(r), p: r.n != null && r.v != null ? Math.sqrt(r.n) * r.v * r.v : null }))
    .filter((x) => x.c != null && x.p != null);
  if (terms.length < 10) return null;
  const c = terms.reduce((a, x) => a + x.c, 0) / terms.length;
  const p = terms.reduce((a, x) => a + x.p, 0) / terms.length;
  return Math.min(9, Math.max(0, 0.05 + 2.244e-4 * c + 2.844e-6 * p));
}

/**
 * Candidate interplanetary shocks: speed, density and field all jump between
 * an 8-minute upstream and an 8-minute downstream window. Thresholds follow
 * the usual automated-detection criteria (Δv ≥ 20 km/s, n and B ratios ≥ 1.2);
 * a candidate is not a confirmed shock.
 */
export function shockCandidates(rows, { window = 8 } = {}) {
  // Consecutive qualifying minutes form one event, dated where the speed jump peaks.
  const out = [];
  let run = null;
  const close = () => {
    if (run && (!out.length || run.t - out[out.length - 1].t > 30 * 60e3)) out.push(run);
    run = null;
  };
  for (let i = window; i + window <= rows.length; i++) {
    const up = rows.slice(i - window, i), down = rows.slice(i, i + window);
    const vu = mean(up, "v"), vd = mean(down, "v"), nu = mean(up, "n"), nd = mean(down, "n"), bu = mean(up, "bt"), bd = mean(down, "bt");
    const ok = ![vu, vd, nu, nd, bu, bd].some((x) => x == null) && nu > 0 && bu > 0 && vd - vu >= 20 && nd / nu >= 1.2 && bd / bu >= 1.2;
    if (!ok) { close(); continue; }
    const candidate = { t: rows[i].t, dv: round(vd - vu, 0), densityRatio: round(nd / nu), fieldRatio: round(bd / bu) };
    if (!run || candidate.dv > run.dv) run = candidate;
  }
  close();
  return out;
}

/**
 * Flat-delay propagation from the spacecraft to Earth: t = X_GSE / |Vx|.
 * X_GSE is the spacecraft's real sunward distance (ephemerides), Vx the
 * measured radial speed. Typical error of the flat-delay method is ±10–15 min
 * (tilted fronts, structure evolution); the plasma then takes further minutes
 * to tens of minutes to drive a magnetospheric response.
 */
export function propagation(rows, ephemeris) {
  const recent = rows.slice(-30);
  const vx = mean(recent.map((r) => ({ vx: r.vx != null ? Math.abs(r.vx) : r.v })), "vx");
  if (!ephemeris || ephemeris.x == null || !vx) return null;
  const seconds = ephemeris.x / vx;
  return {
    distanceKm: Math.round(ephemeris.x),
    speedKmS: round(vx, 0),
    minutes: round(seconds / 60, 0),
    uncertaintyMinutes: Math.max(10, round((seconds / 60) * 0.15, 0)),
    ephemerisTime: ephemeris.t,
  };
}

/**
 * The next hour at Earth. Each L1 sample reaches the bow shock after its own
 * flat delay X/|Vx|, so the plasma arriving between now and ~X/|Vx| from now
 * has already been measured. For every step: mean Bz, speed and density of the
 * plasma arriving in the 10 minutes before it, and the Newell-coupling Kp of the
 * 30 minutes before it. Steps past the last measured arrival are not known.
 * The magnetosphere and ionosphere then respond within minutes to tens of minutes.
 */
export function nowcast(rows, ephemeris, { now = Date.now(), horizon = 60, step = 10 } = {}) {
  if (!ephemeris || ephemeris.x == null || !rows.length) return null;
  const arriving = rows
    .map((r) => {
      const vx = r.vx != null ? Math.abs(r.vx) : r.v;
      return vx ? { ...r, at: r.t + (ephemeris.x / vx) * 1000 } : null;
    })
    .filter(Boolean);
  if (!arriving.length) return null;
  const lastArrival = Math.max(...arriving.map((r) => r.at));
  const steps = [];
  for (let m = 0; m <= horizon; m += step) {
    const t = now + m * 60e3;
    const recent = arriving.filter((r) => r.at > t - 10 * 60e3 && r.at <= t);
    const window = arriving.filter((r) => r.at > t - 30 * 60e3 && r.at <= t);
    steps.push({
      t: new Date(t).toISOString(), minutes: m, known: t <= lastArrival && recent.length > 0,
      bz: round(mean(recent, "bz"), 1), v: round(mean(recent, "v"), 0), n: round(mean(recent, "n"), 1),
      newellKp: round(newellKp(window), 2),
    });
  }
  return { coveredMinutes: Math.max(0, Math.round((lastArrival - now) / 60e3)), steps };
}

export function analyse(rows, { ephemeris = null, spacecraft = null, now = Date.now() } = {}) {
  if (!rows.length) return null;
  const last = rows[rows.length - 1];
  const tail = (minutes) => rows.filter((r) => r.t > last.t - minutes * 60e3);

  const averages = {};
  for (const m of [5, 15, 30, 60]) {
    const w = tail(m);
    averages[m] = {
      bz: round(mean(w, "bz"), 1), by: round(mean(w, "by"), 1), bt: round(mean(w, "bt"), 1),
      v: round(mean(w, "v"), 0), n: round(mean(w, "n"), 1), pdyn: round(mean(w, "pdyn")), samples: w.length,
    };
  }
  const hour = tail(60);
  let continuousSouth = 0;
  for (let i = rows.length - 1; i >= 0 && rows[i].bz != null && rows[i].bz < 0; i--) continuousSouth++;
  const bzKnown = hour.filter((r) => r.bz != null);
  const flagged = rows.filter((r) => (r.magQuality ?? 0) > 0 || (r.plasmaQuality ?? 0) > 0).length;
  const couplingNow = mean(tail(30).map((r) => ({ c: newellCoupling(r) })), "c");
  const couplingHour = mean(hour.map((r) => ({ c: newellCoupling(r) })), "c");
  const pdyn15 = mean(tail(15), "pdyn"), pdynPrev = mean(rows.filter((r) => r.t <= last.t - 45 * 60e3 && r.t > last.t - 75 * 60e3), "pdyn");

  return {
    spacecraft,
    lastSample: last.t,
    ageMinutes: round((now - last.t) / 60e3, 1),
    samples: rows.length,
    flaggedFraction: round(flagged / rows.length),
    latest: {
      bz: num(last.bz), by: num(last.by), bt: num(last.bt), v: num(last.v), n: num(last.n), temp: num(last.temp), pdyn: round(last.pdyn),
    },
    averages,
    extremes60: {
      bzMin: round(extreme(hour, "bz", Math.min), 1), bzMax: round(extreme(hour, "bz", Math.max), 1),
      vMax: round(extreme(hour, "v", Math.max), 0), nMax: round(extreme(hour, "n", Math.max), 1),
      pdynMax: round(extreme(hour, "pdyn", Math.max)),
    },
    bzSouth: {
      continuousMinutes: continuousSouth,
      fraction60: bzKnown.length ? round(bzKnown.filter((r) => r.bz < 0).length / bzKnown.length) : null,
      fractionBelow5: bzKnown.length ? round(bzKnown.filter((r) => r.bz <= -5).length / bzKnown.length) : null,
      fractionBelow10: bzKnown.length ? round(bzKnown.filter((r) => r.bz <= -10).length / bzKnown.length) : null,
    },
    pressureTrend: pdyn15 != null && pdynPrev != null && pdynPrev > 0 ? round(pdyn15 / pdynPrev) : null,
    coupling: { newell30: round(couplingNow, 0), newell60: round(couplingHour, 0) },
    newellKp: round(newellKp(hour), 2),
    shocks: shockCandidates(rows),
    propagation: propagation(rows, ephemeris),
    nowcast: nowcast(rows, ephemeris, { now }),
    series: rows.filter((_, i) => i % 2 === 0 || i === rows.length - 1).map((r) => [Math.round(r.t / 1000), num(r.bz), num(r.bt), num(r.v), num(r.n)]),
  };
}
