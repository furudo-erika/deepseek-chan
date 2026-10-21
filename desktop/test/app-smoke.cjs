// End-to-end checks run against the packaged Windows executable in CI.
const { _electron: electron } = require('playwright');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
(async()=>{
 const temp=await fs.mkdtemp(path.join(os.tmpdir(),'chan-smoke-'));
 const env={...process.env,DEEPSEEK_CHAN_TEST:'1',CHAN_USAGE_FIXTURES:path.resolve(__dirname,'../../Tests/usage-fixtures.json'),DEEPSEEK_CHAN_TEST_HOME:path.join(temp,'prefs'),DEEPSEEK_CHAN_HOME:path.join(temp,'inbox')};
 delete env.ELECTRON_RUN_AS_NODE;
 const client=await electron.launch({...(process.env.CHAN_EXE?{executablePath:process.env.CHAN_EXE,args:[]}:{args:[path.resolve(__dirname,'..')]}),env,timeout:60000});
 try{
  const page=await client.firstWindow();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.waitForSelector('body[data-ready="true"]');await page.waitForFunction(()=>document.querySelector('#pet').dataset.action);
  assert.equal(await page.evaluate(()=>typeof require),'undefined');
  assert.equal(await page.locator('#action-list button').count(),279);
  await page.getByRole('button',{name:'Usage ♡',exact:true}).click();
  await page.locator('[data-provider="codex"]').filter({hasText:'76% left'}).waitFor();
  assert.equal(await page.locator('.usage-card').count(),6);
  assert.ok((await page.locator('[data-provider="deepseek"]').textContent()).includes('CNY 28.50'));
  assert.ok((await page.locator('[data-provider="openrouter"]').textContent()).includes('USD 12.75'));
  assert.equal(await page.getByRole('textbox',{name:'Message',exact:true}).count(),0);
  if(process.env.CHAN_SCREENSHOT)await page.screenshot({path:process.env.CHAN_SCREENSHOT,omitBackground:true});
  await page.getByRole('button',{name:'Close panel'}).click();await page.getByRole('button',{name:'Settings',exact:true}).click();await page.locator('#outfit').selectOption('halloween');await page.waitForFunction(()=>document.querySelector('#pet').dataset.action.startsWith('halloween_'));
  await page.getByRole('button',{name:'Close panel'}).click();await page.getByRole('button',{name:'Usage ♡',exact:true}).click();
  await fs.mkdir(path.join(temp,'inbox/tasks'),{recursive:true});
  await fs.writeFile(path.join(temp,'inbox/tasks/test.json'),JSON.stringify({version:1,event_id:'fixture',source:'codex',task_id:'smoke',title:'Smoke task',status:'waiting',updated_at:Date.now()/1000}));
  await page.waitForFunction(()=>document.querySelector('#task-list').textContent.includes('Smoke task'));
  await page.locator('#usage-panel').waitFor({state:'visible'});
  const originalBounds = await client.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].getBounds());
  await page.evaluate(()=>window.pet.command('test-reminder'));
  await page.getByRole('button',{name:'Rest 5 min ♡'}).waitFor({state:'visible'});
  await page.getByRole('button',{name:'In 5 min',exact:true}).click();
  await page.locator('#usage-panel').waitFor({state:'visible'});
  await page.waitForTimeout(850); // A cancelled center animation must not move the pet again.
  assert.deepEqual(await client.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].getBounds()), originalBounds);
  await page.getByRole('button',{name:'Close panel'}).click();
  await page.evaluate(()=>window.pet.command('rest'));await page.waitForFunction(()=>document.querySelector('#timer').textContent.includes('look far away'));
  await page.screenshot({path:path.join(temp,'pet.png'),omitBackground:true});

  assert.deepEqual(errors,[]);console.log('PASS: desktop app starts, 279 poses, isolated renderer, six provider quotas, Halloween, local tasks, usage panel preserved through reminders, five-minute rest, screenshot');
 }finally{await client.close();await fs.rm(temp,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
