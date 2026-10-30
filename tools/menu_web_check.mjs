// Run after a normal Web export. Screenshots require visual review.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn, execFileSync} from 'node:child_process';
const root = path.resolve('build/web');
const artifacts = path.join(process.env.LOCALAPPDATA, 'Temp/opencode');
const profile = await fs.mkdtemp(path.join(artifacts, 'menu-chrome-'));
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
  '--remote-debugging-port=0', '--remote-allow-origins=*', '--no-first-run',
  '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding',
  '--disable-background-timer-throttling', '--window-size=1280,720', '--user-data-dir='+profile, 'about:blank'
], {stdio:'ignore'});
let ws;
try {
  let port;
  for (let i=0; i<100; i++) {
    try { port=(await fs.readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]; break; }
    catch { await sleep(100); }
  }
  const tabs=await (await fetch('http://127.0.0.1:'+port+'/json')).json();
  ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
  await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
  let next=1;
  const pending=new Map();
  ws.addEventListener('message',event=>{
    const data=JSON.parse(event.data);
    if(data.id) {
      const p=pending.get(data.id);
      if(p) { pending.delete(data.id); clearTimeout(p.timer); data.error?p.reject(new Error(JSON.stringify(data.error))):p.resolve(data.result); }
    } else if(data.method==='Runtime.exceptionThrown') errors.push(JSON.stringify(data.params));
    else if(data.method==='Runtime.consoleAPICalled') {
      const text=data.params.args.map(a=>a.value??a.description??'').join(' ');
      console.log('BROWSER '+data.params.type+': '+text);
      if(data.params.type==='error') errors.push(text);
    }
  });
  const call=(method,params={})=>new Promise((resolve,reject)=>{
    const id=next++;
    const timer=setTimeout(()=>{pending.delete(id);reject(new Error('CDP timeout '+method));},20000);
    pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params}));
  });
  const evaluate=async expression=>(await call('Runtime.evaluate',{expression,returnByValue:true})).result.value;
  const click=async(x,y)=>{
    await call('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button:'left',clickCount:1});
    await call('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button:'left',clickCount:1});
    await sleep(250);
  };
  const key=async(key,code,vkey)=>{
    for(const type of ['keyDown','keyUp']) await call('Input.dispatchKeyEvent',{type,key,code,windowsVirtualKeyCode:vkey,nativeVirtualKeyCode:vkey});
    await sleep(150);
  };
  const capture=async name=>{
    const image=await call('Page.captureScreenshot',{format:'png'});
    await fs.writeFile(path.join(artifacts,'menu_web_'+name+'.png'),Buffer.from(image.data,'base64'));
    console.log('CAPTURE '+name);
  };
  await call('Runtime.enable'); await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
  await call('Page.navigate',{url:'http://127.0.0.1:'+server.address().port+'/'});
  await sleep(12000);
  await call('Page.bringToFront');
  execFileSync('powershell.exe',['-NoProfile','-Command',`(New-Object -ComObject WScript.Shell).AppActivate(${browser.pid}) | Out-Null`]);
  await sleep(500);
  await capture('main');
  await click(130,535);
  await capture('settings');
  // Volume gets keyboard focus when opening settings. Home attempts zero.
  await key('Home','Home',36);
  await capture('minimum_volume');
  // Keyboard navigation: sensitivity, fullscreen, language.
  await key('Tab','Tab',9);
  await key('ArrowRight','ArrowRight',39);
  await key('Tab','Tab',9);
  await key(' ','Space',32);
  await sleep(700);
  console.log('FULLSCREEN '+await evaluate('!!document.fullscreenElement'));
  if(!await evaluate('!!document.fullscreenElement')) throw new Error('Fullscreen click/key request failed');
  await key(' ','Space',32);
  await click(550,429);
  await key('ArrowDown','ArrowDown',40);
  await key('ArrowDown','ArrowDown',40);
  await key('Enter','Enter',13);
  await capture('russian');
  await key('Escape','Escape',27);
  await click(110,590);
  await capture('credits');
  await key('Escape','Escape',27);
  await call('Emulation.setDeviceMetricsOverride',{width:640,height:360,deviceScaleFactor:1,mobile:false});
  await sleep(300);
  await capture('small');
  // Godot's design viewport stretches to fit the smaller canvas.
  await click(65,267);
  await capture('small_settings');
  await key('Escape','Escape',27);
  await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
  await call('Page.reload');
  await sleep(8000);
  await click(130,535);
  await capture('persisted');
  await key('Escape','Escape',27);
  await click(110,480);
  await sleep(5000);
  await capture('game');
  await click(640,360);
  if(!await evaluate('!!document.pointerLockElement')) throw new Error('Game pointer lock failed');
  if(errors.length) throw new Error(errors.join('\n'));
  console.log('MENU WEB: interactions complete; fullscreen and gameplay pointer lock PASS. Review screenshots for localization, persistence and layout.');
} finally {
  ws?.close();browser.kill();server.close();
}
