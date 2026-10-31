/* Visual verification only. Generated screenshots stay outside the deliverable. */
const {chromium}=require('/Users/junxuanb/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const out=path.join(root,'tmp/design-qa');
fs.mkdirSync(out,{recursive:true});
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  const page=await browser.newPage({viewport:{width:1680,height:1180},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('file://'+path.join(root,'design/index.html'));
  await page.evaluate(()=>document.fonts.ready);
  await page.screenshot({path:path.join(out,'overview.png'),fullPage:true});
  const groups=await page.evaluate(()=>VIA_DESIGN.groups.map(g=>({id:g.id,ids:g.ids})));
  const layouts=[];
  for(const g of groups){
    await page.evaluate(id=>VIA_DESIGN.renderGroup(id,false),g.id);
    await page.evaluate(()=>document.fonts.ready);
    for(const id of g.ids){
      const problems=await page.locator('#art-'+id).evaluate(el=>{
        const body=el.querySelector('.screen-body');
        const result=[];
        if(body){
          const rect=body.getBoundingClientRect();
          const children=[...body.children].filter(e=>!e.classList.contains('spacer'));
          for(const c of children){const r=c.getBoundingClientRect();if(r.bottom>rect.bottom+2)result.push({kind:'body-overflow',element:c.className||c.tagName,px:Math.ceil(r.bottom-rect.bottom)});}
        }
        for(const t of el.querySelectorAll('.hero,.card,.live-card,.widget,.list-group,.notice,.transfer-strip,.ipad-main,.ipad-sidebar')){
          if(t.scrollWidth>t.clientWidth+2)result.push({kind:'horizontal-overflow',element:t.className,px:t.scrollWidth-t.clientWidth});
          if(t.scrollHeight>t.clientHeight+3)result.push({kind:'vertical-overflow',element:t.className,px:t.scrollHeight-t.clientHeight});
        }
        return result;
      });
      layouts.push({id,problems});
      await page.locator('#art-'+id).screenshot({path:path.join(out,id+'.png')});
    }
  }
  const responsive=[];
  for(const width of [1440,1024,768,390,320]){
    await page.setViewportSize({width,height:1000});
    for(const group of ['journey','ipad','live','widget']){
      await page.evaluate(id=>VIA_DESIGN.renderGroup(id,false),group);
      await page.evaluate(()=>resizeArtboards());
      const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2);
      responsive.push({width,group,overflow});
    }
  }
  const deadLinks=await page.evaluate(()=>[...new Set(Object.values(VIA_DESIGN.screens).flatMap(s=>[...s.html.matchAll(/data-jump="([^"]+)"/g)].map(m=>m[1])))].filter(id=>!VIA_DESIGN.screens[id]));
  const report={screenCount:layouts.length,groupCount:groups.length,errors,deadLinks,layouts:layouts.filter(x=>x.problems.length),responsive:responsive.filter(x=>x.overflow)};
  fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
  await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
