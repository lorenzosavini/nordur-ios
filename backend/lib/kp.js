// Kp: observed, estimated and predicted kept apart, then a combined series.
//
// For each 3-hour block:
//   observed blocks  -> NOAA observed Kp (GFZ value attached for comparison)
//   current block    -> weighted mean of NOAA forecast (×1), NOAA 1-min
//                       estimate (×2, a measurement) and the solar-wind Newell
//                       Kp (×1, a statistical fit, biased high when quiet)
//   future blocks    -> NOAA forecast, raised to the low end of NASA's Kp range while a
//                       DONKI/ENLIL CME is predicted to pass (window opened
//                       6 h early for the ±7 h arrival uncertainty)
// The result is a deterministic forecast, not a probability.

const BLOCK = 3 * 3600e3;

export function weighted(items) {
  const present = items.filter(([v]) => v != null);
  const total = present.reduce((a, [, w]) => a + w, 0);
  return total ? present.reduce((a, [v, w]) => a + v * w, 0) / total : null;
}

export function blend({ forecast, estimated, gfz, newellKp, donki, enlil, now = Date.now() }) {
  const estimateNow = estimated?.length && now - estimated.at(-1).t < 20 * 60e3 ? estimated.at(-1).kp : null;
  const arrivals = (donki?.arrivals || []).filter((a) => a.kp);
  const enlilClouds = (enlil?.cmeArrivals || []).map((a) => Date.parse(a.t));

  return forecast
    .filter((p) => p.t + BLOCK > now - 24 * 3600e3)
    .map((p) => {
      const start = p.t, end = p.t + BLOCK;
      const g = gfz?.find((x) => x.t === start);
      const base = { t: new Date(start).toISOString(), kind: p.kind, noaa: p.kp, gfz: g?.kp ?? null, gfzStatus: g?.status ?? null };
      if (p.kind === "observed") return { ...base, value: p.kp, nowcast: null, nasa: null, driver: "osservato" };

      const nasa = arrivals
        .map((a) => {
          const arrival = Date.parse(a.arrival);
          const leave = arrival + (a.durationHours ?? 18) * 3600e3;
          // CCMC notes that ENLIL runs tend to overestimate the impact at Earth:
          // use the low end of NASA's Kp range.
          return arrival - 6 * 3600e3 < end && start < leave ? a.kp.min : null;
        })
        .filter((v) => v != null)
        .reduce((m, v) => Math.max(m, v), -1);
      const isCurrent = start <= now && now < end;
      const nowcast = isCurrent ? weighted([[p.kp, 1], [estimateNow, 2], [newellKp, 1]]) : null;
      const baseValue = nowcast ?? p.kp;
      const value = Math.max(baseValue, nasa >= 0 ? nasa : 0);
      const driver = nasa >= 0 && nasa > baseValue ? "CME NASA" : nowcast != null && Math.abs(nowcast - p.kp) >= 0.3 ? "misure attuali" : "previsione NOAA";
      const enlilCloud = enlilClouds.some((t) => t - 6 * 3600e3 < end && start < t + 18 * 3600e3);
      const leadHours = Math.max(0, (start - now) / 3600e3);
      const reliability = isCurrent ? "alta" : leadHours < 24 ? "media" : "bassa";
      return { ...base, value: Math.round(value * 100) / 100, nowcast: nowcast == null ? null : Math.round(nowcast * 100) / 100, nasa: nasa >= 0 ? nasa : null, enlilCloud, driver, leadHours: Math.round(leadHours), reliability };
    });
}
