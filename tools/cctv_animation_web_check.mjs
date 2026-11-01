// Usage: node tools/cctv_animation_web_check.mjs <exported fixture directory>
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';

const root = path.resolve(process.argv[2]);
const artifacts = path.join(process.env.LOCALAPPDATA, 'Temp/opencode');
const profile = await fs.mkdtemp(path.join(artifacts, 'cctv-animation-chrome-'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const errors = [];
const server = http.createServer(async (req, res) => {
  try {
    const file = path.resolve(root, '.' + (req.url === '/' ? '/index.html' : req.url.split('?')[0]));
    if (!file.startsWith(root + path.sep)) throw Error('Invalid path');
    const body = await fs.readFile(file);
    res.writeHead(200, {'Content-Type': {'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm'}[path.extname(file)] || 'application/octet-stream'});
    res.end(body);
  } catch {res.writeHead(404); res.end();}
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = spawn(process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--remote-debugging-port=0', '--remote-allow-origins=*', '--no-first-run', '--no-default-browser-check',
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows',
  '--window-size=1280,720', '--user-data-dir=' + profile, 'about:blank'
], {stdio:'ignore'});
let ws;
try {
  let port;
  for (let n=0;n<100;n++) {
    try {port = (await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]; break;} catch {await sleep(100);}
  }
  if (!port) throw Error('Chrome debugging unavailable');
  const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(resolve => ws.addEventListener('open', resolve, {once:true}));
  let next = 0;
  const pending = new Map();
  ws.addEventListener('message', event => {
    const data = JSON.parse(event.data);
    if (data.id) {
      const p = pending.get(data.id);
      if (p) {pending.delete(data.id); clearTimeout(p.timer); data.error ? p.reject(Error(JSON.stringify(data.error))) : p.resolve(data.result);}
    } else if (data.method === 'Runtime.exceptionThrown') errors.push(JSON.stringify(data.params));
    else if (data.method === 'Runtime.consoleAPICalled') {
      const text = data.params.args.map(a => a.value ?? a.description ?? '').join(' ');
      if (data.params.type === 'error' && !text.startsWith('WARNING:') && !text.startsWith('   at:')) errors.push(text);
      console.log(text);
    }
  });
  const call = (method, params={}) => new Promise((resolve,reject) => {
    const id = ++next;
    const timer = setTimeout(() => {pending.delete(id); reject(Error('CDP timeout: ' + method));}, 20000);
    pending.set(id, {resolve,reject,timer}); ws.send(JSON.stringify({id,method,params}));
  });
  const evaluate = async expression => (await call('Runtime.evaluate', {expression,returnByValue:true})).result.value;
  const state = () => evaluate('window.animationTelemetry');
  const expect = (value,message) => {if (!value) throw Error(message);};
  const wait = async predicate => {
    for (let n=0;n<200;n++) {const s=await state(); if (s && predicate(s)) return s; await sleep(100);}
    throw Error('Fixture state timeout: ' + JSON.stringify(await state()));
  };
  let sequence = 0;
  const command = async (name, extra={}) => {
    const id = ++sequence;
    await evaluate('window.animationCommand=' + JSON.stringify({id,name,...extra}));
    return wait(s => s.command === id);
  };
  const capture = async label => {
    const data = await call('Page.captureScreenshot', {format:'png'});
    await fs.writeFile(path.join(artifacts, 'cctv_animation_web_' + label + '.png'), Buffer.from(data.data,'base64'));
  };
  await call('Runtime.enable'); await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride', {width:1280,height:720,deviceScaleFactor:1,mobile:false});
  await call('Page.navigate', {url:`http://127.0.0.1:${server.address().port}/`});
  const seated = await wait(s => s.activity === 'work');
  if (process.argv.includes('--shop')) {
    const drinks = ['OBS_WINE', 'OBS_GIN', 'OBS_VODKA'];
    for (let choice=0; choice<drinks.length; choice++) {
      await command('shop', {choice});
      expect((await state()).scene === 'res://scenes/cctv/locations/shop.tscn', 'Wrong shop scene');
      await command('camera', {index:1});
      await command('advance', {seconds:29.8});
      await sleep(700); await capture('shop_' + choice + '_shelf');
      await command('live', {enabled:true});
      await wait(s => s.holding);
      await sleep(700); await command('live', {enabled:false});
      expect((await state()).evidence === drinks[choice], 'Wrong physical bottle taken');
      await capture('shop_' + choice + '_held');
      await command('advance', {seconds:5.6});
      await command('live', {enabled:true});
      await wait(s => s.activity === 'carry_walk');
      await command('camera', {index:2});
      await sleep(700); await capture('shop_' + choice + '_carry');
      await command('live', {enabled:false});
      await command('advance', {seconds:8});
      const receipt = await wait(s => s.on_counter);
      expect(!receipt.holding && receipt.correct === receipt.evidence, 'Report disagrees with the bottle on checkout');
      expect(JSON.stringify(receipt.options) === JSON.stringify(drinks), 'Wrong alcohol answer options');
      await sleep(700); await capture('shop_' + choice + '_checkout');
    }
    expect(errors.length === 0, 'Browser errors: ' + errors.join('\n'));
    console.log('SHOP PURCHASE WEB: PASS (wine, gin, vodka)');
  } else {
  await sleep(800); await capture('work');
  await command('alarm'); await sleep(600);
  expect((await state()).activity === 'stand', 'Alarm did not trigger getting up');
  await capture('stand'); await sleep(1000);
  expect((await state()).head_y > seated.head_y + 0.35, 'Character did not rise from chair');
  await command('advance', {seconds:20});
  await command('advance', {seconds:30});
  await sleep(600);
  expect((await state()).holding, 'Purchase not attached to hand');
  await capture('pickup');
  await command('live', {enabled:true}); await sleep(800);
  expect((await state()).activity === 'carry_idle', 'Stationary purchase did not settle into carrying');
  await command('advance', {seconds:6}); await sleep(500);
  expect((await state()).activity === 'carry_walk', 'No carrying walk');
  await command('camera', {index:2}); await sleep(700); await capture('carry_walk');
  await command('live', {enabled:false});
  await command('checkout'); await sleep(600);
  expect(!(await state()).holding, 'Checkout did not release drink');
  await command('advance', {seconds:100}); await sleep(200);
  const street = await state();
  expect(street.stage === 2 && new Set(street.variants).size === 3, 'Street lacks distinct decoy model assets');
  await command('advance', {seconds:12});
  await command('live', {enabled:true}); await sleep(1200);
  const footA = (await state()).foot; await sleep(250); const footB = (await state()).foot;
  expect(Math.hypot(...footA.map((v,i) => v-footB[i])) > 0.01, 'Walk feet are frozen');
  await capture('street');
  expect(errors.length === 0, 'Browser errors: ' + errors.join('\n'));
  console.log('CCTV ANIMATION WEB: PASS');
  }
} finally {
  ws?.close(); browser.kill(); await new Promise(resolve => server.close(resolve));
}
