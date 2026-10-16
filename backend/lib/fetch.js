// Resilient fetch for external scientific sources: timeout, retry with
// exponential backoff on 429/5xx/network errors, and a per-instance circuit
// breaker so a dead source is not hammered on every request.

const UA = "nordur-api (github.com/lorenzosavini/nordur-ios)";
const breakers = new Map(); // host -> { failures, openUntil }

function breaker(host) {
  if (!breakers.has(host)) breakers.set(host, { failures: 0, openUntil: 0 });
  return breakers.get(host);
}

export class SourceError extends Error {
  constructor(message, { status = null, host = null } = {}) {
    super(message);
    this.status = status;
    this.host = host;
  }
}

export async function fetchWithRetry(url, { timeout = 12000, retries = 2, accept = "application/json" } = {}) {
  const host = new URL(url).host;
  const b = breaker(host);
  if (b.openUntil > Date.now()) throw new SourceError(`${host}: circuito aperto dopo errori ripetuti`, { host });

  let delay = 600;
  for (let attempt = 0; ; attempt++) {
    try {
      const response = await fetch(url, { headers: { "User-Agent": UA, Accept: accept }, signal: AbortSignal.timeout(timeout) });
      if (response.ok) {
        b.failures = 0;
        return response;
      }
      const transient = response.status === 429 || response.status >= 500;
      if (!transient || attempt >= retries) throw new SourceError(`${host} HTTP ${response.status}`, { status: response.status, host });
    } catch (e) {
      if (e instanceof SourceError && e.status && e.status < 500 && e.status !== 429) { trip(b); throw e; }
      if (attempt >= retries) {
        trip(b);
        throw e instanceof SourceError ? e : new SourceError(`${host}: ${e.cause?.code || e.name || e.message}`, { host });
      }
    }
    await new Promise((r) => setTimeout(r, delay));
    delay *= 2;
  }
}

function trip(b) {
  b.failures += 1;
  if (b.failures >= 3) {
    b.openUntil = Date.now() + 2 * 60e3;
    b.failures = 0;
  }
}

export async function fetchJSON(url, options) {
  const response = await fetchWithRetry(url, options);
  return response.json();
}

export async function fetchText(url, options) {
  const response = await fetchWithRetry(url, { ...options, accept: "text/plain" });
  return response.text();
}

/** NOAA timestamps often lack a zone: they are UTC. */
export function utc(text) {
  if (!text) return null;
  let s = String(text).trim().replace(" ", "T");
  if (/T\d{2}:\d{2}Z$/.test(s)) s = s.replace(/Z$/, ":00Z");
  if (!/[Zz]|[+-]\d{2}:?\d{2}$/.test(s)) s += "Z";
  const t = Date.parse(s);
  return Number.isFinite(t) ? t : null;
}

export const iso = (t) => (t == null ? null : new Date(t).toISOString());
