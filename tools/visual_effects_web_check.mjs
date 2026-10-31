// Dedicated test export: tests/visual_effects_fixture.tscn as main, tests included.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';

const root = path.resolve(process.env.EFFECTS_WEB_ROOT || 'build/effects-web');
const artifacts = path.join(process.env.LOCALAPPDATA, 'Temp/opencode');
const profile = await fs.mkdtemp(path.join(artifacts, 'effects-chrome-'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const errors = [];
const server = http.createServer(async (req, res) => {
  try {
    const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
    if (!file.startsWith(root + path.sep)) throw new Error('Invalid path');
    const data = await fs.readFile(file);
    res.writeHead(200, {'Content-Type': {'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm', '.png':'image/png'}[path.extname(file)] || 'application/octet-stream'});
    res.end(data);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = spawn(process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--remote-debugging-port=0', '--remote-allow-origins=*', '--no-first-run', '--no-default-browser-check',
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--user-data-dir=' + profile, 'about:blank'
], {stdio:'ignore'});
let ws;
try {
  let port;
  for (let i = 0; i < 100; i++) {
    try { port = (await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]; break; }
    catch { await sleep(100); }
  }
  if (!port) throw new Error('Chrome debugging unavailable');
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
      if (data.params.type === 'error') errors.push(text);
      console.log('BROWSER ' + text);
    } else if (data.method === 'Log.entryAdded' && data.params.entry.level === 'error') errors.push(data.params.entry.text);
  });
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = next++;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('CDP timeout: ' + method)); }, 20000);
    pending.set(id, {resolve, reject, timer}); ws.send(JSON.stringify({id, method, params}));
  });
  const evaluate = async expression => (await call('Runtime.evaluate', {expression, returnByValue:true})).result.value;
  const wait = async (predicate, message, seconds = 12) => {
    let state;
    for (let i = 0; i < seconds * 20; i++) {
      state = await evaluate('window.effectsTelemetry');
      if (state && predicate(state)) return state;
      await sleep(50);
    }
    throw new Error(message + ': ' + JSON.stringify(state));
  };
  const command = value => evaluate('window.effectsCommand = ' + JSON.stringify(value));
  const capture = async name => {
    const image = await call('Page.captureScreenshot', {format:'png'});
    await fs.writeFile(path.join(artifacts, 'effects_web_' + name + '.png'), Buffer.from(image.data, 'base64'));
  };
  await call('Runtime.enable'); await call('Log.enable'); await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride', {width:1280, height:720, deviceScaleFactor:1, mobile:false});
  await call('Page.navigate', {url:'http://127.0.0.1:' + server.address().port + '/'});
  await wait(s => s.width === 256 && s.height === 144 && s.world_rendering && !s.crt, 'Low-res world failed', 40);
  await capture('world_clean');
  await command('scare');
  await wait(s => s.anxiety > 0.5 && s.smear, 'Stationary scare missing');
  await capture('world_anxiety');
  await wait(s => s.anxiety === 0 && !s.smear, 'Scare did not clear', 6);
  await command('pc');
  await wait(s => s.crt && !s.world_rendering && s.mode === 2, 'PC CRT/render gating failed');
  // Read screenshot pixels, not just a visibility flag. This column is empty
  // desktop background, so scanline contrast cannot come from changing UI text.
  const desktopColumn = async () => {
    const shot = await call('Page.captureScreenshot', {format:'png'});
    const expression = `(async () => {
      const blob = await (await fetch('data:image/png;base64,${shot.data}')).blob();
      const image = await createImageBitmap(blob);
      const canvas = new OffscreenCanvas(image.width, image.height);
      const context = canvas.getContext('2d');
      context.drawImage(image, 0, 0);
      const pixels = context.getImageData(1150, 240, 1, 240).data;
      image.close();
      return Array.from({length:240}, (_, i) => pixels[i * 4]);
    })()`;
    const result = await call('Runtime.evaluate', {expression, returnByValue:true, awaitPromise:true});
    if (result.exceptionDetails) throw new Error('Screenshot pixel decode failed');
    return result.result.value;
  };
  await command('crt_off'); await wait(s => !s.crt, 'CRT disable failed');
  await sleep(100);
  const plain = await desktopColumn();
  await command('crt_on'); await wait(s => s.crt, 'CRT enable failed');
  await sleep(100);
  const filtered = await desktopColumn();
  const ratios = filtered.map((value, i) => value / Math.max(plain[i], 1));
  const contrast = Math.max(...ratios) - Math.min(...ratios);
  if (contrast < 0.10) throw new Error('CRT is visible in telemetry but absent in pixels: ' + contrast);
  console.log('CRT pixel contrast: ' + contrast);
  await capture('desktop_crt');
  await command('cctv'); await sleep(800);
  await command('scare');
  await wait(s => s.cctv_anxiety > 0.5 && !s.smear, 'CCTV anxiety isolation failed');
  await capture('desktop_crt_anxiety');
  await call('Emulation.setDeviceMetricsOverride', {width:640, height:360, deviceScaleFactor:1, mobile:false});
  await sleep(400); await capture('small_desktop');
  await command('leave');
  await wait(s => s.world_rendering && !s.crt && s.mode === 0 && s.camera_error < 0.001, 'Return camera failed');
  await capture('small_world');
  await call('Emulation.setDeviceMetricsOverride', {width:1000, height:720, deviceScaleFactor:1, mobile:false});
  // Project stretch/aspect=keep letterboxes a 16:9 design view in this window.
  await wait(s => s.width === 256 && s.height === 144 && s.camera_error < 0.001, 'Letterboxed aspect ratio failed');
  await capture('non_widescreen');
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('VISUAL EFFECTS WEB: PASS');
  await call('Browser.close');
} finally {
  if (ws) ws.close();
  browser.kill();
  server.close();
}
