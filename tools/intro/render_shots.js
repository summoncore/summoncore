// Screenshots for render_intro.py: node render_shots.js <render.html> <out dir> <style> <scene,scene,...>
// One 1024x512 still for each of a scene's three frames, as render_intro.ps1 takes them with headless Edge.
const { chromium } = require('playwright');
(async () => {
  const [page_, out, style, list] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 512 }, deviceScaleFactor: 1 });
  for (const n of list.split(',').map(Number)) {
    for (let f = 0; f < 3; f++) {
      await page.goto('about:blank');
      await page.goto('file://' + page_ + '#s=' + (n - 1) + '&f=' + f + (style === 'lines' ? '&line=1' : ''));
      await page.waitForTimeout(250);
      await page.screenshot({ path: `${out}/${style}_s${n - 1}_f${f}.png` });
    }
    console.log('rendered scene ' + n);
  }
  await browser.close();
})();
