// Dedicated test export: tests/power_fixture.tscn as main, tests/* included.
// Production has no fixture bridge. Node 22+, Windows Chrome.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn, execFileSync} from 'node:child_process';
const root=path.resolve(process.env.POWER_WEB_ROOT || 'build/power-web');
const artifacts=path.join(process.env.LOCALAPPDATA,'Temp/opencode');
const profile=await fs.mkdtemp(path.join(artifacts,'power-chrome-'));
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const errors=[];
const server=http.createServer(async(req,res)=>{
  try {
    const name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));
    if(!file.startsWith(root+path.sep)) throw new Error('Invalid path');
    const data=await fs.readFile(file);
    res.writeHead(200,{'Content-Type':{'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.png':'image/png'}[path.extname(file)]||'application/octet-stream'});res.end(data);
  } catch {res.writeHead(404);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=spawn(process.env.CHROME||'C:/Program Files/Google/Chrome/Application/chrome.exe',[
  '--remote-debugging-port=0','--remote-allow-origins=*','--no-first-run',
  '--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding','--disable-background-timer-throttling',
  '--window-size=1280,720','--user-data-dir='+profile,'about:blank'
],{stdio:'ignore'});
let ws;
try {
  let port;
  for(let i=0;i<100;i++) {
    try {port=(await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0];break;} catch {await sleep(100);}
  }
  const tabs=await(await fetch('http://127.0.0.1:'+port+'/json')).json();
  ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
  await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
  let next=1;const pending=new Map();
  ws.addEventListener('message',event=>{
    const data=JSON.parse(event.data);
    if(data.id) {const p=pending.get(data.id);if(p){pending.delete(data.id);clearTimeout(p.timer);data.error?p.reject(new Error(JSON.stringify(data.error))):p.resolve(data.result);}}
    else if(data.method==='Runtime.exceptionThrown') errors.push(JSON.stringify(data.params));
    else if(data.method==='Runtime.consoleAPICalled') {
      const text=data.params.args.map(a=>a.value??a.description??'').join(' ');
      console.log('BROWSER '+data.params.type+': '+text);
      if(data.params.type==='error') errors.push(text);
    }
  });
  const call=(method,params={})=>new Promise((resolve,reject)=>{
    const id=next++;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('CDP timeout '+method));},20000);
    pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params}));
  });
  const evaluate=async expression=>(await call('Runtime.evaluate',{expression,returnByValue:true})).result.value;
  const state=()=>evaluate('window.powerTelemetry');
  const expect=(condition,message)=>{if(!condition)throw new Error(message);};
  const wait=async(predicate,message,seconds=5)=>{
    for(let i=0;i<seconds*20;i++){const s=await state();if(s&&predicate(s))return s;await sleep(50);}
    throw new Error(message+' '+JSON.stringify(await state()));
  };
  const key=async(type,code,key,vkey)=>call('Input.dispatchKeyEvent',{type,code,key,windowsVirtualKeyCode:vkey,nativeVirtualKeyCode:vkey});
  const tap=async(code,name,vkey)=>{await key('keyDown',code,name,vkey);await key('keyUp',code,name,vkey);await sleep(150);};
  const mouse=async(type,point,buttons=0)=>call('Input.dispatchMouseEvent',{type,x:point[0],y:point[1],button:type==='mouseMoved'?'none':'left',buttons,clickCount:type==='mouseMoved'?0:1});
  const click=async point=>{await mouse('mouseMoved',point);await mouse('mousePressed',point,1);await mouse('mouseReleased',point);await sleep(150);};
  const command=async name=>{const s=await state();expect(s.buttons[name], 'Missing dev button '+name);await click(s.buttons[name]);};
  const capture=async name=>{
    const image=await call('Page.captureScreenshot',{format:'png'});
    await fs.writeFile(path.join(artifacts,'power_web_'+name+'.png'),Buffer.from(image.data,'base64'));
    console.log('CAPTURE '+name+' '+JSON.stringify(await state()));
  };
  const openDev=async()=>{
    await key('keyDown','F7','F7',118);
    await sleep(4500);expect(!(await state()).dev,'Dev menu opened before five seconds');
    await wait(s=>s.dev,'F7 did not open dev',2);
    await key('keyUp','F7','F7',118);
  };
  const track=async(index,ms)=>{
    let s=await state();await mouse('mouseMoved',s.points[index]);
    await mouse('mousePressed',s.points[index],1);
    for(let elapsed=0;elapsed<ms;elapsed+=50) {
      s=await state();await mouse('mouseMoved',s.points[index],1);await sleep(50);
      if(s.latched[index])break;
    }
    s=await state();await mouse('mouseReleased',s.points[index]);
    return s;
  };
  await call('Runtime.enable');await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
  await call('Page.navigate',{url:'http://127.0.0.1:'+server.address().port+'/'});
  await wait(s=>s.powered,'Fixture load failed',30);
  await call('Page.bringToFront');
  execFileSync('powershell.exe',['-NoProfile','-Command',`(New-Object -ComObject WScript.Shell).AppActivate(${browser.pid}) | Out-Null`]);
  await sleep(400);
  await key('keyDown','F7','F7',118);await sleep(150);await key('keyUp','F7','F7',118);
  await sleep(200);expect(!(await state()).dev,'Brief F7 should not open dev');
  await openDev();await capture('dev');
  await command('DEV_UNLIMITED');expect((await state()).unlimited,'Unlimited toggle failed');
  await command('DEV_POWER_OFF');await wait(s=>!s.powered&&s.flashlight,'Dev outage failed');
  await command('DEV_CLEAR_COOLDOWN');expect((await state()).cooldown===0,'Clear cooldown failed');
  await command('BACK');await wait(s=>!s.dev,'Dev did not close');
  await click([640,360]);
  expect(await evaluate('!!document.pointerLockElement'),'Walking pointer lock failed');
  await tap('KeyE','e',69);await wait(s=>s.mode===5,'E failed to enter board');
  await capture('board');
  let s=await track(0,900);
  expect(s.progress[0]>0.1&&!s.latched[0],'Holding does not raise real 3D lever');
  await sleep(1400);expect((await state()).progress[0]===0,'Release should drop partial lever');
  s=await state();await mouse('mousePressed',s.points[0],1);await sleep(200);
  await mouse('mouseMoved',[50,50],1);await sleep(100);
  expect((await state()).held===-1,'Leaving lever should cancel hold');
  await mouse('mouseReleased',[50,50]);await sleep(1300);
  await tap('KeyS','s',83);await wait(s=>s.mode===0,'WASD failed to leave board');
  await sleep(300);
  if(!await evaluate('!!document.pointerLockElement')) {await sleep(2200);await click([640,360]);}
  await tap('KeyE','e',69);await wait(s=>s.mode===5,'Cannot re-enter after WASD');
  await track(0,4000);expect((await state()).latched[0],'First lever did not latch');
  await tap('Escape','Escape',27);await wait(s=>s.mode===0,'Esc failed to leave board');
  expect((await state()).latched[0],'Latched progress lost on exit');
  await sleep(2200);await click([640,360]);await tap('KeyE','e',69);
  await wait(s=>s.mode===5,'Cannot re-enter board');
  await track(1,4000);await track(2,4000);await track(3,4000);
  await wait(s=>s.powered&&s.mode===0,'All four did not restore power');
  expect(!(await state()).flashlight,'Flashlight remains on after repair');
  await capture('repaired');
  // Trigger while seated, preserving the real desktop rather than a parallel mock.
  await evaluate("window.powerCommand='pc'");await wait(s=>s.mode===2,'PC entry failed');
  await openDev();await command('DEV_POWER_OFF');
  await wait(s=>!s.powered&&s.mode===0&&!s.desktop,'Outage failed to eject seated player');
  expect(!(await state()).controls,'Dev overlay should still block walking');
  await command('DEV_POWER_ON');await command('BACK');
  expect((await state()).powered&&(await state()).controls,'Restore/close failed');
  expect(errors.length===0,'Console errors: '+errors.join('\n'));
  console.log('POWER WEB: PASS (real F7 hold, dev commands, physical mouse holds, leave-target cancellation, Esc, persistent latches, repair and PC ejection).');
} finally {ws?.close();browser.kill();server.close();}
