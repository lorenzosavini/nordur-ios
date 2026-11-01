const { chromium } = require('playwright'); const fs = require('fs');
const [dir, out, ...names] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 520, height: 520 } });
  for (const n of names) {
    let svg = fs.readFileSync(`${dir}/${n}.svg`, 'utf8').replace(/width="24"/, 'width="512"').replace(/height="24"/, 'height="512"')
      .replace(/stroke-width="2"/, 'stroke-width="1.5"').replace(/currentColor/g, '#ffffff');
    await p.setContent(`<html><body style="margin:0;background:transparent"><div id=i style="width:512px;height:512px">${svg}</div></body></html>`);
    await (await p.$('#i')).screenshot({ path: `${out}/${n}.png`, omitBackground: true });
  }
  await b.close();
})();
