// Export tests/threat_fairness_input_fixture.tscn with tests included, in a copy.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
const root = path.resolve(process.env.FAIRNESS_WEB_ROOT || 'build/fairness-web');
const artifacts = path.join(process.env.LOCALAPPDATA, 'Temp/opencode');
const profile = await fs.mkdtemp(path.join(artifacts, 'fairness-chrome-'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const errors = [];
const server = http.createServer(async (req, res) => {
  try {
    const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
    if (!file.startsWith(root + path.sep)) throw new Error('Invalid path');
    const bytes = await fs.readFile(file);
    res.writeHead(200, {'Content-Type': {'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm'}[path.extname(file)] || 'application/octet-stream'});
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
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
      const request = pending.get(data.id);
      if (request) {
        pending.delete(data.id); clearTimeout(request.timer);
        data.error ? request.reject(new Error(JSON.stringify(data.error))) : request.resolve(data.result);
      }
    } else if (data.method === 'Runtime.exceptionThrown') errors.push(JSON.stringify(data.params));
    else if (data.method === 'Runtime.consoleAPICalled' && data.params.type === 'error') {
      errors.push(data.params.args.map(a => a.value ?? a.description ?? '').join(' '));
    }
  });
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = next++;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('CDP timeout: ' + method)); }, 20000);
    pending.set(id, {resolve, reject, timer}); ws.send(JSON.stringify({id, method, params}));
  });
  const evaluate = async expression => (await call('Runtime.evaluate', {expression, returnByValue:true})).result.value;
  const command = async value => {
    await evaluate('window.fairnessCommand = ' + JSON.stringify(value));
    for (let i = 0; i < 100; i++) {
      await sleep(30);
      if (await evaluate('window.fairnessCommand === null')) return;
    }
    throw new Error('Unconsumed fixture command: ' + value);
  };
  const wait = async (predicate, message, seconds = 10) => {
    let state;
    for (let i = 0; i < seconds * 20; i++) {
      state = await evaluate('window.fairnessTelemetry');
      if (state && predicate(state)) {
        const browserLocked = await evaluate('!!document.pointerLockElement');
        if (state.captured === browserLocked) return state;
      }
      await sleep(50);
    }
    throw new Error(message + ': ' + JSON.stringify(state) + ' browser=' + JSON.stringify(await evaluate('({focus:document.hasFocus(), lock:!!document.pointerLockElement})')) + ' errors=' + JSON.stringify(errors));
  };
  const tap = async (code, key, windowsVirtualKeyCode) => {
    for (const type of ['keyDown', 'keyUp']) await call('Input.dispatchKeyEvent', {type, code, key, windowsVirtualKeyCode});
    await sleep(100);
  };
  const click = async () => {
    await call('Input.dispatchMouseEvent', {type:'mouseMoved', x:640, y:360});
    for (const type of ['mousePressed', 'mouseReleased']) await call('Input.dispatchMouseEvent', {type, x:640, y:360, button:'left', buttons:type === 'mousePressed' ? 1 : 0, clickCount:1});
  };
  const capture = async name => {
    const image = await call('Page.captureScreenshot', {format:'png'});
    await fs.writeFile(path.join(artifacts, 'fairness_web_' + name + '.png'), Buffer.from(image.data, 'base64'));
  };
  await call('Runtime.enable'); await call('Page.enable');
  await call('Emulation.setFocusEmulationEnabled', {enabled:true});
  for (const locale of ['ru', 'en']) {
    await call('Emulation.setDeviceMetricsOverride', {width:1280, height:720, deviceScaleFactor:1, mobile:false});
    await call('Page.navigate', {url:'http://127.0.0.1:' + server.address().port + '/?lang=' + locale});
    await wait(s => s.mode === 0, 'Initial walking unavailable', 40);
    await call('Page.bringToFront');
    await sleep(800);
    await capture(locale + '_initial');
    await click(); await wait(s => s.captured, 'Initial real click did not capture');
    await command('pc'); await wait(s => s.mode === 2 && !s.captured, 'PC did not release pointer');
    await command('police');
    await wait(s => s.mode === 0 && s.police_visible && s.warning_visible && s.warning === (locale === 'ru' ? 'ПРЯЧЬСЯ' : 'HIDE'), 'Police forced exit or localization failed');
    await capture(locale + '_hide');
    await sleep(2200); await click(); await wait(s => s.captured, 'Pointer not recoverable after forced PC exit');
    await command('wardrobe'); await sleep(150); await tap('KeyE', 'e', 69);
    await wait(s => s.hidden && !s.warning_visible, 'Real E did not hide or warning stayed');
    await command('search'); await wait(s => s.held_door && !s.ended, 'Hidden player failed police entry');
    await command('departure'); await command('gone');
    await wait(s => !s.held_door, 'Police did not release door');
    await tap('KeyE', 'e', 69); await wait(s => !s.hidden && !s.ended, 'Real E exit after departure failed');
    await command('police'); await sleep(100); await command('search'); await sleep(100); await command('detect');
    await wait(s => s.capture === 'POLICE_DEATH' && !s.ended, 'Confirmed sight did not start staging');
    const captureStart = Date.now();
    await capture(locale + '_capture');
    await tap('Escape', 'Escape', 27);
    await tap('KeyE', 'e', 69);
    await tap('KeyW', 'w', 87);
    await call('Emulation.setDeviceMetricsOverride', {width:960, height:540, deviceScaleFactor:1, mobile:false});
    await wait(s => s.capture_elapsed >= 3 && !s.ended && s.mode === 8 && s.capture_duration >= 5, 'Long defeat scene was skipped or ended early');
    await capture(locale + '_police_pin');
    await wait(s => s.ended && s.reason === 'POLICE_DEATH' && s.notes === 'web evidence', 'Staged capture result or notes failed');
    if (Date.now() - captureStart < 4500) throw new Error('Defeat did not play for its full real-time duration');
    await call('Emulation.setDeviceMetricsOverride', {width:1280, height:720, deviceScaleFactor:1, mobile:false});
    await command('blackout'); await wait(s => s.flashlight && !s.ended, 'Blackout reset failed');
    await command('fusebox'); await wait(s => s.mode === 5, 'Fusebox did not open');
    await command('encounter'); await wait(s => s.mode === 0 && s.entity_phase === 2 && s.warning_duration === 4 && s.warning === (locale === 'ru' ? 'ЗАМРИ' : 'FREEZE'), 'Entity forced exit and technical allowance failed');
    await sleep(2200); await click(); await wait(s => s.captured, 'Pointer unavailable after fusebox exit');
    await tap('KeyF', 'f', 70); await wait(s => !s.flashlight, 'Real F failed after forced exit');
    await call('Emulation.setDeviceMetricsOverride', {width:960, height:540, deviceScaleFactor:1, mobile:false});
    await sleep(200);
    await capture(locale + '_freeze_resized');
    await tap('Escape', 'Escape', 27); await wait(s => !s.captured, 'Esc did not release pointer');
    await sleep(2200); await click(); await wait(s => s.captured, 'Pointer not recoverable after Esc');
    // Do not navigate away with an unresolved pointer-lock request from this page.
    await tap('Escape', 'Escape', 27);
    await wait(s => !s.captured, 'Pointer did not unlock before locale reload');
    await sleep(2200);
    console.log('FAIRNESS INPUT ' + locale.toUpperCase() + ': PASS');
  }
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('FAIRNESS INPUT WEB: PASS (real click/E/F/Esc, forced exits, RU/EN, staging, resize).');
} finally {
  if (ws?.readyState === 1) ws.close();
  browser.kill();
  server.close(); server.closeAllConnections();
}
