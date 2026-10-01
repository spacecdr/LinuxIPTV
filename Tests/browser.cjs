const path=require('node:path');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert=require('node:assert/strict');
(async()=>{
const browser=await chromium.launch({...(process.env.CHROME_PATH ? {executablePath:process.env.CHROME_PATH}:{}),headless:true});
try{
const page=await browser.newPage({viewport:{width:1280,height:800}}),errors=[];
page.on('pageerror',e=>errors.push(e.message));
await page.addInitScript(()=>{window.calls=[];window.webkit={messageHandlers:{native:{postMessage(m){calls.push(m);if(m.action==='favorite'){const f=new Set(favorites);if(!f.delete(m.id))f.add(m.id);receiveFavorites([...f])}if(m.action==='play')receiveState({current:m.id,name:'Test',status:'In riproduzione',active:true,volume:70,muted:false,floating:false})}}}}});
await page.goto(pathToFileURL(path.resolve(__dirname,'../Resources/index.html')).href);
await page.evaluate(()=>receiveCatalog({channels:Array.from({length:6442},(_,i)=>({id:String(i),name:i===0?'<img src=x onerror=alert(1)>':`Canale ${i}`,group:`Gruppo ${i%159}`,url:'https://example.org/'+('stream/'.repeat(30))+i,logo:'',headers:{}})),favorites:[],source:''}));
assert.equal(await page.locator('.channel').count(),60);
assert((await page.locator('.workspace').boundingBox()).y<140);
await page.locator('#listButton').click();assert(await page.locator('#settings').isVisible());assert(await page.locator('#settings #addPlaylist').isVisible());await page.keyboard.press('Escape');assert(!(await page.locator('#settings').isVisible()));
await page.locator('#epgButton').click();assert(await page.locator('#epgPanel').isVisible());await page.keyboard.press('Escape');assert(!(await page.locator('#epgPanel').isVisible()));
assert.equal(await page.locator('#groups button').count(),161);
assert.equal(await page.locator('.title').first().textContent(),'<img src=x onerror=alert(1)>');
await page.locator('.play').first().focus();await page.keyboard.press('ArrowRight');assert.equal(await page.evaluate(()=>document.activeElement.id),'play-1');
await page.keyboard.press('Enter');assert.equal(await page.evaluate(()=>calls.at(-1).action),'play');
await page.keyboard.press('p');assert.equal(await page.locator('#fav-1').textContent(),'★');
await page.keyboard.press('Backspace');assert.equal(await page.evaluate(()=>document.activeElement.dataset.group),'@all');
await page.keyboard.press('Backspace');assert.equal(await page.evaluate(()=>calls.at(-1).action),'hide');
await page.keyboard.press('Escape');assert.equal(await page.evaluate(()=>calls.at(-1).action),'escape');
await page.evaluate(()=>receiveState({current:'',active:false,name:'',status:'Stop',volume:70,muted:false,floating:false}));assert.equal(await page.locator('#transport').count(),0);
await page.evaluate(()=>receiveState({current:'1',active:true,name:'Test',status:'Play',volume:70,muted:false,floating:false}));assert.equal(await page.locator('#transport').count(),0);
await page.locator('#groups button').first().click();assert.equal(await page.locator('.channel').count(),1);
await page.locator('.play').first().focus();await page.keyboard.press('Backspace');assert.equal(await page.evaluate(()=>document.activeElement.dataset.group),'@fav');
await page.locator('#groups button').nth(1).click();await page.locator('#search').fill('Canale 6400');assert.equal(await page.locator('.channel').count(),1);
await page.keyboard.press('Backspace');assert.equal(await page.locator('#search').inputValue(),'Canale 640');
await page.locator('#search').fill('');await page.locator('#next').click();assert.equal(await page.locator('.play').first().getAttribute('id'),'play-60');
await page.locator('#listMode').click();assert.equal(await page.locator('#cards.list').count(),1);
await page.evaluate(()=>receiveEPG({programmes:Object.fromEntries(channels.map(c=>[c.id,{now:{title:'Programma dimostrativo con un titolo lungo',start:Date.now()/1000-600,end:Date.now()/1000+600}}])),diagnostics:{}}));
assert.equal(await page.locator('.link').count(),0);assert.equal(await page.locator('#cards.list .channel>.guide-now progress').count(),60);
assert.equal(await page.locator('#cards').textContent().then(t=>t.includes('https://example.org')),false);
for(const width of [1280,800,640,420]){await page.setViewportSize({width,height:width===420?500:720});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`Overflow ${width}`);assert((await page.locator('.channel').first().boundingBox()).height<70,'Compact EPG row')}
await page.setViewportSize({width:1280,height:800});await page.locator('#gridMode').click();await page.screenshot({path:path.join(__dirname,'catalog.png')});
await page.goto(pathToFileURL(path.resolve(__dirname,'../Resources/info.html')).href);
await page.evaluate(()=>{document.body.classList.add('shown');renderInfo({name:'Test',resolution:'HD',logo:'',volume:42,muted:false,buffer:3})});
await page.locator('#mute').click();assert.equal(await page.evaluate(()=>calls.at(-1).action),'mute');assert.equal(await page.locator('#volume').inputValue(),'42');
assert.deepEqual(errors,[]);console.log('PASS 6442 channels, pagination, groups, search, escaped metadata, keyboard navigation, favorites, playback bridge, backspace editing, grid/list, responsive sizes, no JS errors');
}finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
