// Language menu with flags, for the landing and the legal page.
// NordurLangPicker(element, currentLang, onChange) replaces the element's content.
(() => {
  const FLAGS = {
    it: '<rect width="3" height="2" fill="#fff"/><rect width="1" height="2" fill="#009246"/><rect x="2" width="1" height="2" fill="#ce2b37"/>',
    fr: '<rect width="3" height="2" fill="#fff"/><rect width="1" height="2" fill="#0055a4"/><rect x="2" width="1" height="2" fill="#ef4135"/>',
    de: '<rect width="3" height="2" fill="#ffce00"/><rect width="3" height=".667" fill="#000"/><rect y=".667" width="3" height=".667" fill="#dd0000"/>',
    es: '<rect width="3" height="2" fill="#aa151b"/><rect y=".5" width="3" height="1" fill="#f1bf00"/>',
    en: '<rect width="3" height="2" fill="#012169"/><path d="M0 0L3 2M3 0L0 2" stroke="#fff" stroke-width=".4"/><path d="M0 0L3 2M3 0L0 2" stroke="#c8102e" stroke-width=".16"/><path d="M1.5 0V2M0 1H3" stroke="#fff" stroke-width=".6"/><path d="M1.5 0V2M0 1H3" stroke="#c8102e" stroke-width=".34"/>',
  };
  const NAMES = { it: "Italiano", en: "English", de: "Deutsch", fr: "Français", es: "Español" };
  const flag = (l) => `<svg class="flag" viewBox="0 0 3 2" aria-hidden="true" preserveAspectRatio="none">${FLAGS[l]}</svg>`;

  window.NordurLangPicker = (root, current, onChange) => {
    let lang = current;
    root.classList.add("langpick");
    const render = () => {
      root.innerHTML = `<button type="button" class="langpick-btn" aria-haspopup="listbox" aria-expanded="false" aria-label="Language: ${NAMES[lang]}">${flag(lang)}<span>${lang.toUpperCase()}</span><i aria-hidden="true"></i></button>
        <ul class="langpick-menu" role="listbox" hidden>${Object.keys(NAMES).map((l) => `<li role="option" tabindex="-1" data-l="${l}" aria-selected="${l === lang}">${flag(l)}<span>${NAMES[l]}</span></li>`).join("")}</ul>`;
      const btn = root.querySelector("button"), menu = root.querySelector("ul");
      const close = () => { menu.hidden = true; btn.setAttribute("aria-expanded", "false"); };
      const open = () => { menu.hidden = false; btn.setAttribute("aria-expanded", "true"); (menu.querySelector('[aria-selected="true"]') || menu.firstElementChild).focus(); };
      btn.onclick = (e) => { e.stopPropagation(); menu.hidden ? open() : close(); };
      const pick = (l) => { close(); if (l && l !== lang) { lang = l; render(); onChange(l); } btn.focus(); };
      menu.onclick = (e) => { const li = e.target.closest("li"); if (li) pick(li.dataset.l); };
      menu.onkeydown = (e) => {
        const items = [...menu.children], i = items.indexOf(document.activeElement);
        if (e.key === "ArrowDown") { e.preventDefault(); items[(i + 1) % items.length].focus(); }
        if (e.key === "ArrowUp") { e.preventDefault(); items[(i - 1 + items.length) % items.length].focus(); }
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); pick(document.activeElement.dataset.l); }
        if (e.key === "Escape") { e.preventDefault(); pick(null); }
      };
    };
    document.addEventListener("click", (e) => {
      const menu = root.querySelector("ul"), btn = root.querySelector("button");
      if (menu && !root.contains(e.target)) { menu.hidden = true; btn.setAttribute("aria-expanded", "false"); }
    });
    render();
    return { set(l) { lang = l; render(); } };
  };
})();
