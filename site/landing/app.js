// Norður landing: language, aurora sky, launch status, sign-up form.
(() => {
  const POLICY_VERSION = "2026-10-23";
  const LANGS = ["it", "en", "de", "fr", "es"];
  const API = `${window.NORDUR_API || ""}/api/data`;
  const qs = new URLSearchParams(location.search);
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch {} },
  };

  // ——— Language ———
  const browser = (navigator.languages || [navigator.language || "en"]).map((l) => l.slice(0, 2)).find((l) => LANGS.includes(l));
  let lang = [qs.get("lang"), store.get("nordur.lang"), browser, "en"].find((l) => l && LANGS.includes(l) && window.I18N[l]) || "it";
  const t = (k) => (window.I18N[lang] && window.I18N[lang][k] !== undefined ? window.I18N[lang][k] : window.I18N.en[k] ?? window.I18N.it[k] ?? "");
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  let statusData = null;

  function apply() {
    document.documentElement.lang = lang;
    document.title = t("meta.title");
    document.querySelector('meta[name="description"]').content = t("meta.description");
    document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
    document.querySelectorAll("[data-i18n-html]").forEach((el) => { el.innerHTML = t(el.dataset.i18nHtml); });
    document.querySelectorAll("[data-i18n-ph]").forEach((el) => { el.placeholder = t(el.dataset.i18nPh); });
    document.getElementById("lang").value = lang;
    document.getElementById("does").innerHTML = t("honest.do").map((x) => `<li>${esc(x)}</li>`).join("");
    document.getElementById("doesnt").innerHTML = t("honest.dont").map((x) => `<li>${esc(x)}</li>`).join("");
    document.getElementById("faqs").innerHTML = t("faq.items").map(([q, a]) => `<details><summary>${esc(q)}</summary><p>${esc(a)}</p></details>`).join("");
    const v = { it: ["Esci adesso", "Preparati", "Stanotte", "Non adesso"], en: ["Go out now", "Get ready", "Tonight", "Not now"], de: ["Jetzt raus", "Mach dich bereit", "Heute Nacht", "Nicht jetzt"], fr: ["Sortez maintenant", "Préparez-vous", "Cette nuit", "Pas maintenant"], es: ["Sal ahora", "Prepárate", "Esta noche", "Ahora no"] }[lang];
    document.getElementById("verdicts").innerHTML = ["now", "soon", "later", "no"].map((c, i) => `<span class="${c}">${esc(v[i])}</span>`).join("");
    // Interests and travel months
    const checked = new Set([...document.querySelectorAll("#interests input:checked")].map((i) => i.value));
    document.getElementById("interests").innerHTML = ["aurora", "weather", "roads", "trip", "drive", "other"]
      .map((k) => `<label><input type="checkbox" value="${k}"${checked.has(k) ? " checked" : ""}><span>${esc(t("interest." + k))}</span></label>`).join("");
    const sel = document.getElementById("travel"), current = sel.value;
    const fmt = new Intl.DateTimeFormat(lang, { month: "long", year: "numeric" });
    const now = new Date();
    let opts = `<option value="">${esc(t("form.travelNone"))}</option>`;
    for (let i = 0; i < 18; i++) {
      const d = new Date(now.getFullYear(), now.getMonth() + i, 1);
      const val = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      const label = fmt.format(d);
      opts += `<option value="${val}">${esc(label.charAt(0).toUpperCase() + label.slice(1))}</option>`;
    }
    sel.innerHTML = opts;
    sel.value = current;
    if (statusData) renderStatus(statusData);
  }
  document.getElementById("lang").addEventListener("change", (e) => { lang = e.target.value; store.set("nordur.lang", lang); apply(); });

  // ——— Gallery ———
  const shots = ["today", "aurora", "weather", "map-aurora", "map-wind", "trip", "roads", "explore", "quakes", "webcams", "alerts", "offline", "info", "map-radar"];
  document.getElementById("gallery").innerHTML = shots.map((s) => `<div class="phone"><img src="landing/img/${s}.webp" alt="" loading="lazy"></div>`).join("");

  // ——— Aurora sky: curtains that drift, slower and fainter for reduced motion ———
  const canvas = document.getElementById("sky");
  const ctx = canvas.getContext("2d");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let w = 0, h = 0, dpr = 1;
  const stars = Array.from({ length: 140 }, () => ({ x: Math.random(), y: Math.random() * 0.75, r: Math.random() * 1.1 + 0.2, a: Math.random() * 0.6 + 0.2 }));
  function resize() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    w = canvas.clientWidth; h = canvas.clientHeight;
    canvas.width = w * dpr; canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  const bands = [
    { y: 0.26, amp: 0.07, len: 1.3, speed: 0.00011, hue: 158, alpha: 0.42, height: 0.42 },
    { y: 0.18, amp: 0.05, len: 0.9, speed: -0.00008, hue: 168, alpha: 0.28, height: 0.32 },
    { y: 0.34, amp: 0.06, len: 1.7, speed: 0.00006, hue: 285, alpha: 0.12, height: 0.25 },
  ];
  function draw(time) {
    ctx.clearRect(0, 0, w, h);
    const sky = ctx.createLinearGradient(0, 0, 0, h);
    sky.addColorStop(0, "#020610"); sky.addColorStop(0.6, "#03090d"); sky.addColorStop(1, "#000");
    ctx.fillStyle = sky; ctx.fillRect(0, 0, w, h);
    for (const s of stars) {
      ctx.globalAlpha = s.a * (0.75 + 0.25 * Math.sin(time * 0.001 + s.x * 40));
      ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(s.x * w, s.y * h, s.r, 0, 6.283); ctx.fill();
    }
    ctx.globalCompositeOperation = "lighter";
    const step = Math.max(3, Math.round(w / 260));
    for (const b of bands) {
      for (let x = 0; x <= w; x += step) {
        const p = x / w;
        const wave = Math.sin(p * 6.283 * b.len + time * b.speed * 6.283) * 0.6 + Math.sin(p * 17 + time * b.speed * 9) * 0.25 + Math.sin(p * 41 - time * b.speed * 13) * 0.15;
        const top = (b.y + wave * b.amp) * h;
        const rays = 0.55 + 0.45 * Math.sin(p * 120 + time * 0.0007 + b.hue) * Math.sin(p * 37 - time * 0.0004);
        const edge = Math.min(1, p * 4, (1 - p) * 4);
        const a = b.alpha * rays * edge;
        const g = ctx.createLinearGradient(0, top, 0, top + b.height * h);
        g.addColorStop(0, `hsla(${b.hue + 40},90%,70%,0)`);
        g.addColorStop(0.08, `hsla(${b.hue},95%,62%,${a})`);
        g.addColorStop(0.45, `hsla(${b.hue - 8},90%,45%,${a * 0.35})`);
        g.addColorStop(1, `hsla(${b.hue - 20},80%,30%,0)`);
        ctx.fillStyle = g;
        ctx.globalAlpha = 1;
        ctx.fillRect(x, top, step + 1, b.height * h);
      }
    }
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
  }
  let visible = true;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(canvas);
  function loop(time) {
    if (visible) draw(reduce ? 20000 : time);
    if (!reduce) requestAnimationFrame(loop);
  }
  resize(); addEventListener("resize", () => { resize(); if (reduce) draw(20000); });
  requestAnimationFrame(loop);

  // ——— Reveal, lazy videos ———
  const io = new IntersectionObserver((entries) => entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: 0.15 });
  document.querySelectorAll(".reveal").forEach((el) => io.observe(el));
  const vio = new IntersectionObserver((entries) => entries.forEach((e) => {
    const v = e.target;
    if (e.isIntersecting) { if (!v.src && v.dataset.src) v.src = v.dataset.src; if (!reduce) v.play().catch(() => {}); } else v.pause();
  }), { threshold: 0.3 });
  document.querySelectorAll("video").forEach((v) => { if (reduce) v.removeAttribute("autoplay"); vio.observe(v); });

  // ——— Launch status ———
  const PHASES = ["idea", "development", "beta", "testflight", "review", "launched"];
  function renderStatus(d) {
    const s = d.status || {};
    const idx = Math.max(0, PHASES.indexOf(s.phase));
    document.getElementById("phases").innerHTML = PHASES.map((p, i) => `<div class="${i < idx ? "done" : i === idx ? "current" : ""}">${esc(t("phase." + p))}</div>`).join("");
    document.getElementById("bar").style.width = `${s.progress || 0}%`;
    document.getElementById("pct").textContent = `${s.progress || 0}%`;
    document.getElementById("updated").textContent = s.updatedAt ? `${t("status.updated")} ${new Intl.DateTimeFormat(lang, { day: "numeric", month: "long", year: "numeric" }).format(new Date(s.updatedAt))}` : "";
    const note = (s.note && (s.note[lang] || s.note.en || s.note.it)) || "";
    document.getElementById("note").textContent = note;
    document.getElementById("items").innerHTML = (s.items || []).map((i) => {
      const label = i.label && (i.label[lang] || i.label.en || i.label.it);
      return label ? `<li class="${i.done ? "done" : ""}">${esc(label)}</li>` : "";
    }).join("");
    document.getElementById("count").textContent = d.count ? `${d.count} ${t("status.subscribers")}` : "";
    document.getElementById("store").innerHTML = s.appStoreUrl ? `<a class="btn primary" href="${esc(s.appStoreUrl)}">${esc(t("status.download"))}</a>` : "";
    const l = d.legal || {};
    const parts = [l.controller, l.address, l.vat].filter(Boolean).map(esc);
    document.getElementById("legalInfo").innerHTML = parts.length ? `${esc(t("footer.controller"))}: ${parts.join(" · ")}${l.email ? `<br>${esc(t("footer.contact"))}: <a href="mailto:${esc(l.email)}">${esc(l.email)}</a>` : ""}` : "";
    if (!d.ready) {
      document.getElementById("err").textContent = t("form.notReady");
      document.getElementById("submit").disabled = true;
    }
  }
  fetch(`${API}?lead=status`).then((r) => r.json()).then((d) => { statusData = d; renderStatus(d); }).catch(() => {});

  // ——— Sign-up ———
  const opened = Date.now();
  const form = document.getElementById("signup");
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const err = document.getElementById("err"), btn = document.getElementById("submit");
    const email = form.email.value.trim();
    err.textContent = "";
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) { err.textContent = t("form.errEmail"); form.email.focus(); return; }
    const cP = document.getElementById("cPrivacy"), cU = document.getElementById("cUpdates");
    if (!cP.checked || !cU.checked) { err.textContent = t("form.errConsent"); return; }
    btn.disabled = true; btn.textContent = t("form.sending");
    const plain = (html) => { const d = document.createElement("div"); d.innerHTML = html; return d.textContent; };
    try {
      const r = await fetch(`${API}?lead=subscribe`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email, name: form.name.value.trim(), lang, travel: form.travel.value,
          interests: [...document.querySelectorAll("#interests input:checked")].map((i) => i.value),
          consentPrivacy: true, consentUpdates: true, policyVersion: POLICY_VERSION,
          consentPrivacyText: plain(t("form.consentPrivacy")), consentText: t("form.consentUpdates"),
          hp: form.website.value, elapsed: Date.now() - opened,
        }),
      });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) {
        err.textContent = { email: t("form.errEmail"), consent: t("form.errConsent"), too_many: t("form.errBusy"), not_ready: t("form.notReady") }[d.error] || t("form.errServer");
        btn.disabled = false; btn.textContent = t("form.submit");
        return;
      }
      document.getElementById("formbox").innerHTML = `<div class="form-ok"><h3>${esc(t("form.okTitle"))}</h3><p>${esc(d.mail ? t("form.okMail") : t("form.okNoMail"))}</p></div>`;
    } catch {
      err.textContent = t("form.errServer");
      btn.disabled = false; btn.textContent = t("form.submit");
    }
  });

  // ——— Banners after the e-mail links ———
  function banner(text, bad, extra = "") {
    const b = document.getElementById("banner");
    b.innerHTML = `<div class="banner${bad ? " bad" : ""}" role="status"><div style="flex:1"><p>${esc(text)}</p>${extra}</div><button class="close" aria-label="OK">×</button></div>`;
    b.querySelector(".close").onclick = () => { b.innerHTML = ""; };
  }
  if (qs.has("confirmed")) banner(qs.get("confirmed") === "1" ? t("banner.confirmed") : t("banner.confirmFail"), qs.get("confirmed") !== "1");
  if (qs.get("unsubscribed") === "1") {
    banner(t("banner.unsubscribed"), false, qs.get("t") ? `<button class="btn" id="forget">${esc(t("banner.forget"))}</button>` : "");
    const f = document.getElementById("forget");
    if (f) f.onclick = async () => {
      f.disabled = true;
      const r = await fetch(`${API}?lead=forget`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ t: qs.get("t") }) }).catch(() => null);
      if (r && r.ok) banner(t("banner.forgotten"), false); else f.disabled = false;
    };
  }
  if (qs.has("confirmed") || qs.has("unsubscribed")) history.replaceState(null, "", location.pathname);

  apply();
})();
