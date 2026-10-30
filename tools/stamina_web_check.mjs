// Windows + Node 22+, dedicated TEST export with tests/stamina_fixture.tscn as main.
// Production exports exclude tests/* and do not expose fixture telemetry.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn, execFileSync} from 'node:child_process';

const root = path.resolve(process.env.STAMINA_WEB_ROOT || 'build/stamina-web');
const artifacts = path.join(process.env.LOCALAPPDATA, 'Temp/opencode');
const profile = await fs.mkdtemp(path.join(artifacts, 'stamina-chrome-'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const errors = [];
const server = http.createServer(async (req,res) => {
  try {
    const name = decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    const file = path.resolve(root, '.' + (name === '/' ? '/index.html' : name));
    if (!file.startsWith(root + path.sep)) throw new Error('Invalid path');
    const data = await fs.readFile(file);
    const type = {'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.png':'image/png'}[path.extname(file)] || 'application/octet-stream';
    res.writeHead(200,{'Content-Type':type}); res.end(data);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
const browser = spawn(process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe',[
  '--remote-debugging-port=0','--remote-allow-origins=*','--no-first-run','--no-default-browser-check',
  '--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding',
  '--disable-background-timer-throttling','--disable-features=CalculateNativeWinOcclusion',
  '--window-size=1280,720','--user-data-dir='+profile,'about:blank'
],{stdio:'ignore'});
let ws;
try {
  let port;
  for(let i=0;i<100;i++) {
    try { port=(await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0]; break; }
    catch { await sleep(100); }
  }
  if (!port) throw new Error('Chrome debugging unavailable');
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
    } else if(data.method==='Log.entryAdded' && data.params.entry.level==='error') errors.push(data.params.entry.text);
  });
  const call=(method,params={})=>new Promise((resolve,reject)=>{
    const id=next++;
    const timer=setTimeout(()=>{pending.delete(id);reject(new Error('CDP timeout: '+method));},20000);
    pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params}));
  });
  const evaluate=async expression=>(await call('Runtime.evaluate',{expression,returnByValue:true})).result.value;
  const state=()=>evaluate('window.staminaTelemetry');
  const assert=(condition,message)=>{if(!condition) throw new Error(message);};
  const wait=async (predicate,message,seconds=8)=>{
    for(let i=0;i<seconds*20;i++) {const s=await state();if(s&&predicate(s)) return s;await sleep(50);}
    throw new Error(message+'; telemetry='+JSON.stringify(await state()));
  };
  const capture=async name=>{
    const image=await call('Page.captureScreenshot',{format:'png'});
    await fs.writeFile(path.join(artifacts,'stamina_web_'+name+'.png'),Buffer.from(image.data,'base64'));
    console.log('CAPTURE stamina_web_'+name+': '+JSON.stringify(await state()));
  };
  const key=(type,code,key,vkey)=>call('Input.dispatchKeyEvent',{type,code,key,windowsVirtualKeyCode:vkey,nativeVirtualKeyCode:vkey});
  let pointerX=640;
  const move=async dx=>{pointerX+=dx;return call('Input.dispatchMouseEvent',{type:'mouseMoved',x:pointerX,y:360});};
  await call('Runtime.enable');await call('Log.enable');await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
  await call('Page.navigate',{url:'http://127.0.0.1:'+server.address().port+'/'});
  await wait(s=>s.value===1,'Fixture failed to load',30);
  await call('Page.bringToFront');
  execFileSync('powershell.exe',['-NoProfile','-Command',`(New-Object -ComObject WScript.Shell).AppActivate(${browser.pid}) | Out-Null`]);
  await call('Input.dispatchMouseEvent',{type:'mousePressed',x:640,y:360,button:'left',clickCount:1});
  await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:640,y:360,button:'left',clickCount:1});
  assert(await evaluate('!!document.pointerLockElement'),'Pointer lock failed');
  await key('keyDown','ShiftLeft','Shift',16);
  await key('keyDown','KeyW','w',87);
  const half=await wait(s=>s.value<0.53&&s.value>0.4,'Sprint did not consume stamina');
  assert(half.bar_ratio>half.value+0.15,'Bar is not deceptive');
  assert(Math.abs(half.bar_center-half.screen_center)<0.1,'Bar not centered');
  await capture('half');
  await wait(s=>s.exhausted,'Sprint did not exhaust',5);
  await key('keyUp','KeyW','w',87);
  await key('keyUp','ShiftLeft','Shift',16);
  await sleep(150);
  for(let n=0;n<8;n++) {await move(18);await sleep(20);}
  const moving=await wait(s=>s.effect_visible&&s.smear_pixels>0.5,'Exhausted turn did not activate smear',1);
  assert(moving.fatigue>0,'No fatigue while turning');
  await capture('turning');
  await sleep(450);
  const still=await state();
  assert(!still.effect_visible,'Stationary camera remains blurred');
  await capture('stationary');
  await wait(s=>s.value>=0.45,'Recovery did not clear fatigue');
  assert((await state()).fatigue===0,'Fatigue target remains above 45 percent');
  await wait(s=>s.value>=0.999,'Full recovery failed');
  await key('keyDown','ShiftLeft','Shift',16);
  await key('keyDown','KeyW','w',87);
  await wait(s=>s.exhausted,'Second sprint failed to exhaust');
  const resume=await wait(s=>s.sprinting&&s.value>0.25&&s.value<0.4,'Held Shift did not restart near 35 percent',6);
  assert(resume.value>=0.30,'Restart threshold too low');
  await key('keyUp','KeyW','w',87);
  await key('keyUp','ShiftLeft','Shift',16);
  await evaluate("window.staminaFixtureCommand='pc'");
  const pc=await wait(s=>s.mode===2,'PC transition failed');
  assert(!pc.hud_visible&&!pc.effect_visible,'Fatigue/HUD visible on desktop');
  await capture('pc');
  await call('Emulation.setDeviceMetricsOverride',{width:640,height:360,deviceScaleFactor:1,mobile:false});
  await evaluate("window.staminaFixtureCommand='leave'");
  await wait(s=>s.mode===0,'Exit from PC failed');
  const small=await state();
  assert(Math.abs(small.bar_center-small.screen_center)<0.1,'Resized bar not centered');
  assert(!small.effect_visible,'Stale smear after PC/resize');
  await capture('small');
  assert(errors.length===0,'Browser errors: '+errors.join('\n'));
  console.log('STAMINA WEB: PASS (telemetry assertions + real input). Inspect captures for visual quality.');
} finally {
  ws?.close();browser.kill();server.close();
}
