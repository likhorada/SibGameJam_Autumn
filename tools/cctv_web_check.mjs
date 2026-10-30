// Windows + Node 22+: export Web first, then node tools/cctv_web_check.mjs.
// Drives the actual game in Chrome; captures require visual inspection.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn, execFileSync} from 'node:child_process';

const root = path.resolve('build/web');
const artifacts = path.join(process.env.LOCALAPPDATA, 'Temp/opencode');
const profile = await fs.mkdtemp(path.join(artifacts, 'cctv-feed-chrome-'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const errors = [];
const server = http.createServer(async (req, res) => {
  try {
    const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
    if (!file.startsWith(root + path.sep)) throw new Error('Invalid path');
    const content = await fs.readFile(file);
    const type = {'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm', '.png':'image/png'}[path.extname(file)] || 'application/octet-stream';
    res.writeHead(200, {'Content-Type':type}); res.end(content);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = spawn(process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--remote-debugging-port=0', '--remote-allow-origins=*', '--no-first-run', '--no-default-browser-check',
  '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding',
  '--disable-background-timer-throttling', '--disable-features=CalculateNativeWinOcclusion',
  '--window-size=1280,720', '--user-data-dir=' + profile, 'about:blank'
], {stdio:'ignore'});
let ws;
try {
  let port;
  for (let n=0;n<100;n++) {
    try { port = (await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]; break; }
    catch { await sleep(100); }
  }
  if (!port) throw new Error('Chrome debugging port unavailable');
  const tabs = await (await fetch('http://127.0.0.1:' + port + '/json')).json();
  ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(resolve => ws.addEventListener('open', resolve, {once:true}));
  let next = 1;
  const pending = new Map();
  ws.addEventListener('message', event => {
    const data = JSON.parse(event.data);
    if (data.id) {
      const p = pending.get(data.id);
      if (p) { pending.delete(data.id); clearTimeout(p.timer); data.error ? p.reject(new Error(JSON.stringify(data.error))) : p.resolve(data.result); }
    } else if (data.method === 'Runtime.exceptionThrown') errors.push(JSON.stringify(data.params));
    else if (data.method === 'Runtime.consoleAPICalled') {
      const text = data.params.args.map(a => a.value ?? a.description ?? '').join(' ');
      console.log('BROWSER ' + data.params.type + ': ' + text);
      if (data.params.type === 'error') errors.push(text);
    } else if (data.method === 'Log.entryAdded' && data.params.entry.level === 'error') errors.push(data.params.entry.text);
  });
  const call = (method, params={}) => new Promise((resolve,reject) => {
    const id = next++;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('CDP timeout: '+method)); }, 20000);
    pending.set(id,{resolve,reject,timer}); ws.send(JSON.stringify({id,method,params}));
  });
  const evaluate = async expression => (await call('Runtime.evaluate', {expression,returnByValue:true})).result.value;
  const capture = async name => {
    await sleep(300);
    const image = await call('Page.captureScreenshot', {format:'png'});
    const file = path.join(artifacts, 'cctv_web_' + name + '.png');
    await fs.writeFile(file, Buffer.from(image.data,'base64'));
    console.log('CAPTURE: ' + file);
  };
  const focus = () => execFileSync('powershell.exe', ['-NoProfile','-Command', `(New-Object -ComObject WScript.Shell).AppActivate(${browser.pid}) | Out-Null`]);
  const move = (x,y) => call('Input.dispatchMouseEvent', {type:'mouseMoved',x,y});
  const click = async (x,y,count=1) => {
    focus(); await move(x,y);
    for(let n=1;n<=count;n++) {
      await call('Input.dispatchMouseEvent', {type:'mousePressed',x,y,button:'left',clickCount:n});
      await call('Input.dispatchMouseEvent', {type:'mouseReleased',x,y,button:'left',clickCount:n});
      if(n<count) await sleep(60);
    }
    await sleep(150);
  };
  const hold = async (x,y,ms) => {
    focus(); await move(x,y);
    await call('Input.dispatchMouseEvent', {type:'mousePressed',x,y,button:'left',clickCount:1});
    await sleep(ms);
    await move(1200,630);
    await call('Input.dispatchMouseEvent', {type:'mouseReleased',x:1200,y:630,button:'left',clickCount:1});
    await sleep(650);
  };
  const key = async (code,key,vkey,ms=50,text='') => {
    await call('Input.dispatchKeyEvent',{type:'keyDown',code,key,windowsVirtualKeyCode:vkey,nativeVirtualKeyCode:vkey,text});
    await sleep(ms);
    await call('Input.dispatchKeyEvent',{type:'keyUp',code,key,windowsVirtualKeyCode:vkey,nativeVirtualKeyCode:vkey});
  };
  await call('Runtime.enable'); await call('Log.enable'); await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride', {width:1280,height:720,deviceScaleFactor:1,mobile:false});
  await call('Page.navigate', {url:'http://127.0.0.1:'+server.address().port+'/'});
  let loaded = false;
  for (let n=0;n<150;n++) {
    loaded = await evaluate("!document.getElementById('status') || document.getElementById('status').style.visibility === 'hidden'");
    if (loaded) break;
    await sleep(200);
  }
  if (!loaded) throw new Error('Game did not finish loading');
  await sleep(2000);
  await call('Page.bringToFront');
  await click(640,360);
  if (!await evaluate('!!document.pointerLockElement')) throw new Error('Initial pointer capture failed');
  await move(640,440);
  await key('KeyW','w',87,1500);
  await sleep(250);
  await key('KeyE','e',69);
  await sleep(2000);
  if (await evaluate('!!document.pointerLockElement')) throw new Error('PC did not open; rerun with browser in foreground');
  await click(70,305,2);
  await sleep(900);
  await capture('shop_color');
  for (const [index,name] of ['shop_bw','yard_bw','yard_color'].entries()) {
    await click(1090,90);
    await click(700,151 + index * 27);
    await sleep(900);
    await capture(name);
  }
  await hold(445,534,1000);
  await hold(1010,534,1400);
  await capture('pan_zoom');
  await click(70,70,2);
  await click(210,190);
  for (const ch of 'Camera note 42') {
    const code = ch === ' ' ? 'Space' : /[0-9]/.test(ch) ? 'Digit'+ch : 'Key'+ch.toUpperCase();
    await key(code,ch,ch.toUpperCase().charCodeAt(0),25,ch);
  }
  await capture('notes');
  await click(900,450);
  await click(1018,58);
  await capture('minimized');
  await click(900,699);
  await sleep(900);
  await capture('restored_reset');
  await call('Emulation.setDeviceMetricsOverride', {width:640,height:360,deviceScaleFactor:1,mobile:false});
  await sleep(600);
  await capture('small');
  await key('Escape','Escape',27);
  await sleep(1500);
  await capture('exit');
  if (errors.length) throw new Error('Browser errors: '+errors.join('\n'));
  console.log('CCTV WEB: interactions complete, no console errors. Inspect screenshots for visual acceptance.');
} finally {
  ws?.close(); browser.kill(); server.close();
}
