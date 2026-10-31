const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require('/Users/junxuanb/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  try {
    const page=await browser.newPage({viewport:{width:1680,height:1180}});
    await page.goto('file://'+path.resolve(__dirname,'../index.html'));
    await page.evaluate(()=>VIA_DESIGN.renderGroup('select',false));
    await page.locator('#art-stations [data-open-station="board"]').click();
    await page.locator('#art-stations').screenshot({path:path.resolve(__dirname,'../../tmp/design-qa/station-sheet.png')});
    await page.locator('#art-stations .station-sheet [data-station-index="1"]').click();
    assert.match(await page.locator('#art-stations [data-open-station="board"]').textContent(),/Kingston/);
    await page.evaluate(()=>VIA_DESIGN.renderGroup('planning',false));
    assert.match(await page.locator('#art-departure').textContent(),/16:20/);
    assert.match(await page.locator('#art-travel').textContent(),/15:50/);
    await page.locator('#art-travel [data-travel-step="15"]').click();
    assert.match(await page.locator('#art-travel').textContent(),/15:35/);
    assert.match(await page.locator('#art-review').textContent(),/Kingston/);
    await page.evaluate(()=>VIA_DESIGN.renderGroup('transfers',false));
    assert.match(await page.locator('#art-transfer-review').textContent(),/Kingston → Ottawa → Montréal/);
    assert.match(await page.locator('#art-transfer-review').textContent(),/15:35/);
    await page.evaluate(()=>VIA_DESIGN.renderGroup('select',false));
    await page.locator('#art-stations [data-open-station="alight"]').click();
    assert.equal(await page.locator('#art-stations .station-sheet [data-station-index="0"]').isDisabled(),true);
    assert.equal(await page.locator('#art-stations .station-sheet [data-station-index="1"]').isDisabled(),true);
    await page.locator('#art-stations .station-sheet [data-station-index="2"]').click();
    assert.match(await page.locator('#art-stations [data-open-station="alight"]').textContent(),/Smiths Falls/);
    await page.evaluate(()=>VIA_DESIGN.renderGroup('transfers',false));
    assert.match(await page.locator('#art-add-transfer').textContent(),/没有从 Smiths Falls 出发的班次/);
    assert.equal(await page.locator('#art-add-transfer .train-option').count(),0);
    await page.evaluate(()=>VIA_DESIGN.renderGroup('ipad',false));
    await page.locator('#art-ipad-create [data-open-station="board"]').click();
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('.station-sheet').count(),0);
    assert.equal(await page.locator('#art-ipad-create [data-open-station="board"]').evaluate(el=>el===document.activeElement),true);
    assert.equal(await page.evaluate(()=>Object.values(VIA_DESIGN.screens).some(s=>s.html.includes('建议出门'))),false);
    assert.equal(await page.evaluate(()=>Object.keys(VIA_DESIGN.screens).includes('different-station')),false);
    console.log('PASS: station selection, station order, scheduled time propagation, 15-minute travel steps, same-station connections, iPad keyboard dismissal, and revised copy.');
  } finally {await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
