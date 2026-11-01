// Dedicated export: main = tests/chat_fixture.tscn, tests/* included. Node 22 + Chrome.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
const root=path.resolve(process.env.RESIDENTS_WEB_ROOT || process.env.FIREWALL_WEB_ROOT || process.env.IDIOT_WEB_ROOT || process.env.OUTAGE_WEB_ROOT || process.env.POLICE_WEB_ROOT || process.env.NEIGHBOR_WEB_ROOT || process.env.THREAT_WEB_ROOT || process.env.CHAT_WEB_ROOT || 'build/chat-web');
const artifacts=path.join(process.env.LOCALAPPDATA,'Temp/opencode');
const profile=await fs.mkdtemp(path.join(artifacts,'chat-chrome-'));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const errors=[];
const shiftMode=process.env.SHIFT_WEB==='1';
const threatMode=process.env.THREAT_WEB==='1';
const neighborMode=process.env.NEIGHBOR_WEB==='1';
const policeMode=process.env.POLICE_WEB==='1';
const outageMode=process.env.OUTAGE_WEB==='1';
const idiotMode=process.env.IDIOT_WEB==='1';
const firewallMode=process.env.FIREWALL_WEB==='1';
const residentsMode=process.env.RESIDENTS_WEB==='1';
const server=http.createServer(async(req,res)=>{
  try {
    const name=new URL(req.url,'http://localhost').pathname;
    const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));
    if(!file.startsWith(root+path.sep))throw Error('Invalid path');
    const bytes=await fs.readFile(file);
    res.writeHead(200,{'Content-Type':{'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm'}[path.extname(file)]||'application/octet-stream'});res.end(bytes);
  } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=spawn(process.env.CHROME||'C:/Program Files/Google/Chrome/Application/chrome.exe',[
  '--remote-debugging-port=0','--remote-allow-origins=*','--no-first-run',
  '--disable-backgrounding-occluded-windows','--disable-renderer-backgrounding','--disable-background-timer-throttling',
  '--window-size=1280,720','--user-data-dir='+profile,'about:blank'],{stdio:'ignore'});
let ws;
try {
  let port;
  for(let i=0;i<100;i++) {try {port=(await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0];break;}catch{await sleep(100);}}
  const tabs=await(await fetch('http://127.0.0.1:'+port+'/json')).json();
  ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
  await new Promise(r=>ws.addEventListener('open',r,{once:true}));
  let id=0;const requests=new Map();
  ws.addEventListener('message',event=>{
    const d=JSON.parse(event.data);
    if(d.id) {const p=requests.get(d.id);if(p){clearTimeout(p.timer);requests.delete(d.id);d.error?p.reject(Error(JSON.stringify(d.error))):p.resolve(d.result);}}
    else if(d.method==='Runtime.exceptionThrown')errors.push(JSON.stringify(d.params));
    else if(d.method==='Runtime.consoleAPICalled'){
      const text=d.params.args.map(a=>a.value??a.description??'').join(' ');console.log(text);
      if(d.params.type==='error')errors.push(text);
    }
  });
  const call=(method,params={})=>new Promise((resolve,reject)=>{
    const n=++id;const timer=setTimeout(()=>reject(Error('CDP timeout '+method)),20000);
    requests.set(n,{resolve,reject,timer});ws.send(JSON.stringify({id:n,method,params}));
  });
  const evaluate=async expression=>(await call('Runtime.evaluate',{expression,returnByValue:true})).result.value;
  const state=()=>evaluate(residentsMode?'window.residentsTelemetry':firewallMode?'window.firewallTelemetry':idiotMode?'window.idiotTelemetry':outageMode?'window.outageTelemetry':policeMode?'window.policeTelemetry':neighborMode?'window.neighborTelemetry':'window.chatTelemetry');
  const expect=(value,message)=>{if(!value)throw Error(message);};
  const wait=async(predicate,message,seconds=10)=>{
    for(let i=0;i<seconds*20;i++){const s=await state();if(s&&predicate(s))return s;await sleep(50);}
    throw Error(message+' '+JSON.stringify(await state()));
  };
  const tap=async(code,key,vkey,text)=>{
    await call('Input.dispatchKeyEvent',{type:'keyDown',code,key,windowsVirtualKeyCode:vkey,...(text?{text,unmodifiedText:text}:{})});
    await call('Input.dispatchKeyEvent',{type:'keyUp',code,key,windowsVirtualKeyCode:vkey});
  };
  const click=async(p,clickCount=1)=>{
    await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:p[0],y:p[1]});
    for(const type of ['mousePressed','mouseReleased'])await call('Input.dispatchMouseEvent',{type,x:p[0],y:p[1],button:'left',buttons:type==='mousePressed'?1:0,clickCount});
    await sleep(100);
  };
  const capture=async name=>{const d=await call('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(artifacts,'chat_web_'+name+'.png'),Buffer.from(d.data,'base64'));};
  const answer=async index=>{
    await wait(s=>s.pending===0&&s.options.length>0,'No reply choices');
    // Containers need a layout frame after the newly delivered question.
    await sleep(200);
    const s=await state();
    await click(s.options[index]);
    const draft=await wait(s=>s.selected.length>0,'Reply not selected');
    expect(draft.options.length===0&&draft.draft_visible&&draft.placeholder&&!draft.send_visible,'Draft must replace choices and explain typing');
    await capture('draft_'+(await evaluate('new URL(location.href).searchParams.get("lang")')));
    const before=(await state()).presses;
    await tap('Enter','Enter',13);await sleep(80);
    expect((await state()).selected.length>0,'Incomplete answer submitted');
    let typed=await state();
    const count=Math.ceil(typed.length/2);
    for(let i=0;i<count;i++)await tap('KeyZ','z',90,'z');
    typed=await wait(s=>s.typed===s.length,'Text did not type');
    expect(typed.send_visible&&!typed.placeholder,'Complete draft must reveal Send');
    expect(typed.presses===before+count+1,'Audio must trigger once per press');
    await tap('Enter','Enter',13);
    await wait(s=>s.selected==='', 'Reply not sent');
  };
  await call('Runtime.enable');await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
  const url='http://127.0.0.1:'+server.address().port+'/';
  if(residentsMode){
    let commandID=0;
    const command=async(name,button='')=>{
      const id=++commandID;
      await evaluate('window.residentsCommand='+JSON.stringify({id,name,button}));
      return wait(s=>s.command===id,'Residents command not acknowledged: '+name);
    };
    const trigger=async button=>{
      await call('Input.dispatchKeyEvent',{type:'keyDown',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await wait(s=>s.dev,'Dev menu did not open');
      await call('Input.dispatchKeyEvent',{type:'keyUp',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await command('reveal',button);await sleep(150);
      await click((await state()).buttons[button]);
      await wait(s=>!s.dev,'Dev trigger did not close menu');
    };
    for(const lang of ['ru','en']){
      await call('Page.navigate',{url:url+'?lang='+lang});
      await wait(s=>s.mode===2&&s.notes==='Resident evidence','Residents fixture not ready',30);
      await call('Page.bringToFront');
      await trigger('TriggerQuestionPopup');
      let s=await wait(s=>s.question&&!s.busy&&s.deck===11,'Question failed to release spawn slot');
      const first=s.key;
      expect(s.text.length>25&&!s.text.startsWith('AQ_'),'Missing translation');
      const old=s.rect,at=[old[0]+100,old[1]+20];
      await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:at[0],y:at[1]});
      await call('Input.dispatchMouseEvent',{type:'mousePressed',x:at[0],y:at[1],button:'left',buttons:1,clickCount:1});
      await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:at[0]+55,y:at[1]+25,buttons:1});
      await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:at[0]+55,y:at[1]+25,button:'left',buttons:0,clickCount:1});
      await sleep(150);s=await state();expect(s.rect[0]>old[0]+30,'Question drag failed');
      await tap('KeyZ','z',90,'z');await sleep(100);
      const notes=(await state()).notes;
      expect(notes!==s.notes&&(await state()).app==='notepad','Question blocked surrounding app keyboard');
      await capture('residents_question_'+lang);
      await call('Emulation.setDeviceMetricsOverride',{width:800,height:600,deviceScaleFactor:1,mobile:false});
      await sleep(250);s=await state();
      const [x,y,w,h]=s.rect,[ax,ay,aw,ah]=s.area;
      expect(x>=ax-1&&y>=ay-1&&x+w<=ax+aw+1&&y+h<=ay+ah+1,'Question escaped resized workspace');
      await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
      await sleep(250);await click((await state()).close);
      await wait(s=>!s.question,'Question cross failed');
      await command('question');s=await wait(s=>s.question&&s.deck===10,'Repeat question failed');
      expect(s.key!==first,'Question text repeated');
      await trigger('TriggerFirewallBreach');
      await wait(s=>s.busy&&s.modal&&!s.question,'Firewall did not remove persistent question');
      await command('cancel');
      await trigger('TriggerBathroomApparition');
      s=await wait(s=>s.figure&&!s.busy,'Figure did not release spawn slot');
      expect(!s.audio,'Missing sound must remain silent');
      await tap('Escape','Escape',27);await wait(s=>s.mode===0,'Esc failed');
      await command('wall');await sleep(250);expect((await state()).figure,'Wall counted as sight');
      await command('away');await sleep(150);expect((await state()).figure,'Offscreen figure disappeared');
      await command('peripheral');s=await wait(s=>!s.figure&&s.figure_reason==='seen','Rendered peripheral glimpse did not dismiss figure');
      expect(s.projected[0]<200||s.projected[0]>1080,'Glimpse was not peripheral');
      await command('figure');s=await state();expect(!s.request&&!s.figure,'Dev materialized figure into visible spot');
      await command('away');await sleep(150);await command('figure');await wait(s=>s.figure,'Hidden spawn did not recover');
      await command('threat');s=await wait(s=>!s.figure&&s.figure_reason==='threat_started','Threat did not remove decorative figure');
      await command('disable_threats');await command('return');await wait(s=>s.mode===2,'Return failed');
      await command('question');await command('figure');await wait(s=>s.question&&s.figure,'Residents not prepared for report');
      await command('quiz');s=await wait(s=>s.quiz&&!s.question&&!s.figure,'Report left persistent objects');
      expect(s.notes===notes,'Residents changed evidence');
    }
  }else if(firewallMode){
    let commandID=0;
    const command=async(name,seconds=0)=>{
      const id=++commandID;
      await evaluate('window.firewallCommand='+JSON.stringify({id,name,seconds}));
      return wait(s=>s.command===id,'Firewall command not acknowledged: '+name);
    };
    const solve=async()=>{
      for(const p of (await state()).ports.filter(p=>p.open))await click(p.point);
      return wait(s=>s.block_enabled&&s.ports.every(p=>!p.open),'Grid did not become green');
    };
    for(const lang of ['ru','en']){
      await call('Page.navigate',{url:url+'?lang='+lang});
      await wait(s=>s.mode===2&&s.notes==='Firewall evidence stays','Firewall fixture not ready',30);
      await call('Page.bringToFront');
      await call('Input.dispatchKeyEvent',{type:'keyDown',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await wait(s=>s.dev,'Dev menu did not open');
      await call('Input.dispatchKeyEvent',{type:'keyUp',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await command('reveal_trigger');await sleep(150);
      await click((await state()).trigger);
      let s=await wait(s=>s.active&&s.modal&&!s.dev,'Dedicated firewall trigger failed');
      expect(s.ports.filter(p=>p.open).length===6&&!s.block_enabled,'Wrong initial grid');
      await tap('KeyZ','z',90,'z');
      await click(s.start);
      s=await state();
      expect(s.notes==='Firewall evidence stays'&&!s.menu&&s.app==='notepad','Modal leaked input into desktop');
      await click(s.block);expect((await state()).round_state===0,'Disabled BLOCK accepted click');
      await capture('firewall_active_'+lang);
      await call('Emulation.setDeviceMetricsOverride',{width:800,height:600,deviceScaleFactor:1,mobile:false});
      await sleep(250);s=await state();
      const [x,y,w,h]=s.panel,[ax,ay,aw,ah]=s.area;
      expect(x>=ax-1&&y>=ay-1&&x+w<=ax+aw+1&&y+h<=ay+ah+1,'Firewall escaped resized desktop');
      await capture('firewall_small_'+lang);
      await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
      await sleep(250);
      s=await state();await click(s.ports.find(p=>!p.open).point);
      await wait(s=>s.ports.filter(p=>p.open).length===7,'Green click did not open port');
      await command('due');await solve();
      s=await command('advance',0.69);expect(s.block_enabled,'Grace ended too early');
      s=await command('advance',0.02);expect(!s.block_enabled&&s.ports.filter(p=>p.open).length===1,'Reopening failed after grace');
      await solve();await click((await state()).block);
      await wait(s=>s.round_state===1&&s.modal,'BLOCK did not show victory');
      await capture('firewall_won_'+lang);
      s=await command('advance',0.99);expect(s.active,'Victory confirmation ended too early');
      await command('advance',0.02);s=await wait(s=>!s.active&&!s.modal&&s.outcome==='won','Won result/cleanup failed');
      expect(s.opened.notepad&&s.opened.calculator&&s.opened.cctv,'Victory closed applications');
      await command('start');await command('minimize_calc');await command('advance',15);
      s=await wait(s=>!s.active&&s.outcome==='lost','Timeout did not lose');
      expect(Object.values(s.opened).every(v=>!v),'Loss did not close every application');
      expect(s.notes==='Firewall evidence stays'&&s.calc==='73'&&s.history,'Loss erased app data');
      await click(s.note_icon);await click(s.note_icon,2);await wait(s=>s.opened.notepad&&s.app==='notepad','Notepad could not reopen');
      await command('start');await tap('Escape','Escape',27);
      await wait(s=>s.mode===0&&!s.visible&&s.active,'Esc failed to leave locked PC');
      s=await command('advance',1);expect(s.elapsed===1,'Outside clock stopped');
      await command('return');await wait(s=>s.mode===2&&s.modal&&s.visible,'Return bypassed firewall');
      await tap('Escape','Escape',27);await wait(s=>s.mode===0,'Could not leave again');
      await command('advance',14);s=await wait(s=>!s.active&&s.outcome==='lost','Outside deadline did not lose');
      expect(Object.values(s.opened).every(v=>!v)&&s.notes==='Firewall evidence stays','Outside loss failed preservation/closure');
      await command('return');await wait(s=>s.mode===2,'Return after loss failed');
      await click((await state()).note_icon);await click((await state()).note_icon,2);await wait(s=>s.opened.notepad,'Reopen after outside loss failed');
      await command('start');await command('cancel');s=await state();
      expect(s.opened.notepad&&!s.modal&&s.outcome==='cancelled','Cancellation applied loss penalty');
      await command('start');await command('quiz');
      s=await wait(s=>s.quiz&&!s.active&&!s.modal,'Quiz did not cancel firewall');
      expect(s.opened.notepad&&s.notes==='Firewall evidence stays','Quiz cancellation closed or erased apps');
    }
  }else if(idiotMode){
    let commandID=0;
    const command=async(name,seconds=0)=>{
      const id=++commandID;
      await evaluate('window.idiotCommand='+JSON.stringify({id,name,seconds}));
      return wait(s=>s.command===id,'Idiot command not acknowledged: '+name);
    };
    const closePopup=async count=>{
      const s=await state();
      await click(s.windows.at(-1).close);
      await wait(s=>s.windows.length===count,'Cross did not produce '+count+' windows');
    };
    for(const lang of ['ru','en']){
      await call('Page.navigate',{url:url+'?lang='+lang});
      await wait(s=>s.mode===2,'Idiot fixture did not reach PC',30);
      await call('Page.bringToFront');
      await command('cctv');
      await call('Input.dispatchKeyEvent',{type:'keyDown',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await wait(s=>s.dev,'Dev menu did not open');
      await call('Input.dispatchKeyEvent',{type:'keyUp',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await command('reveal_trigger');await sleep(150);
      await click((await state()).trigger);
      let s=await wait(s=>s.active&&!s.dev&&s.windows.length===1,'Dedicated dev trigger failed');
      expect(!s.chaotic&&s.audio,'First popup should be stationary with one laugh');
      const before=s.windows[0].rect;
      const drag=[before[0]+100,before[1]+15];
      await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:drag[0],y:drag[1]});
      await call('Input.dispatchMouseEvent',{type:'mousePressed',x:drag[0],y:drag[1],button:'left',buttons:1,clickCount:1});
      await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:drag[0]+55,y:drag[1]+25,buttons:1});
      await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:drag[0]+55,y:drag[1]+25,button:'left',buttons:0,clickCount:1});
      await sleep(150);s=await state();
      expect(Math.abs(s.windows[0].rect[0]-before[0])>30,'Real browser mouse drag failed');
      await capture('idiot_single_'+lang);
      await closePopup(2);
      expect((await state()).chaotic,'Cross should activate movement');
      const stationary=(await state()).windows[0].rect;
      await command('advance',0.4);
      expect((await state()).windows[0].rect[0]!==stationary[0],'Popup did not move');
      for(let count=3;count<=8;count++)await closePopup(count);
      expect((await state()).closing,'Eight windows should latch closing mode');
      await command('advance',0.6);
      await capture('idiot_eight_'+lang);
      await click((await state()).start);
      await wait(s=>s.menu&&s.windows.length===8,'Popups blocked taskbar');
      await tap('Escape','Escape',27);
      await wait(s=>s.mode===0&&!s.visible,'Esc did not leave PC');
      const elapsed=(await state()).elapsed;
      s=await command('advance',1);
      expect(s.audio&&s.elapsed>elapsed,'Leaving PC stopped positional sound or clock');
      await command('return');await wait(s=>s.mode===2&&s.visible,'Return did not restore popups');
      await call('Emulation.setDeviceMetricsOverride',{width:800,height:600,deviceScaleFactor:1,mobile:false});
      await sleep(250);await command('advance',0.2);s=await state();
      for(const w of s.windows){
        const [x,y,width,height]=w.rect,[ax,ay,aw,ah]=s.workspace;
        expect(x>=ax-1&&y>=ay-1&&x+width<=ax+aw+1&&y+height<=ay+ah+1,'Popup escaped resized workspace');
      }
      await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
      await sleep(250);
      for(let count=7;count>=0;count--)await closePopup(count);
      s=await command('advance',0.1);expect(s.volume < -10,'Sound did not fade');
      await command('advance',0.11);await wait(s=>!s.active&&!s.audio,'Early completion left event/audio');
      await command('start');await wait(s=>s.active,'Dev replay failed');
      s=await command('advance',14.9);
      expect(s.windows.length===1&&!s.chaotic&&s.volume < -10,'Ignored popup should remain one and fade naturally');
      await command('advance',0.11);await wait(s=>!s.active,'Fifteen-second expiry failed');
      await command('start');await command('quiz');
      await wait(s=>s.quiz&&!s.active&&!s.audio,'Quiz did not clean event');
    }
  }else if(outageMode){
    const command=async name=>{
      await evaluate('window.outageTelemetry.command="";window.outageCommand='+JSON.stringify(name));
      await wait(s=>s.command===name,'Outage test command not acknowledged: '+name);
    };
    for(const lang of ['ru','en']){
      await call('Page.navigate',{url:url+'?lang='+lang});
      await wait(s=>s.mode===2&&s.powered,'Outage PC fixture did not load',30);
      await call('Page.bringToFront');
      await call('Input.dispatchKeyEvent',{type:'keyDown',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await wait(s=>s.dev,'Outage F7 menu did not open');
      await call('Input.dispatchKeyEvent',{type:'keyUp',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await sleep(300);
      await click((await state()).buttons.TriggerPowerOutage);
      await wait(s=>!s.dev&&!s.powered&&s.mode===0&&s.light,'TriggerPowerOutage did not cut power and eject into the dark');
      await capture('outage_blackout_'+lang);
      await command('corridor');
      await sleep(2200); // Browser cooldown after the dev-menu pointer release.
      await click([640,360]);
      await wait(s=>s.captured&&s.in_corridor,'Corridor pointer capture failed');
      await tap('KeyF','f',70,'f');
      await wait(s=>!s.light,'Real F did not turn off the flashlight');
      await tap('KeyF','f',70,'f');
      await wait(s=>s.light,'Real F did not turn the flashlight back on');
      await command('encounter');
      await wait(s=>s.phase===2&&s.visible&&s.warn&&s.state===2,'Encounter warning did not start from a corridor route');
      await capture('outage_warning_'+lang);
      await command('active');
      await wait(s=>s.phase===3&&s.steps&&!s.warn,'Danger window did not replace the warning with steps');
      await capture('outage_entity_'+lang);
      await command('die');
      await wait(s=>s.chasing,'Movement exposure did not provoke pursuit');
      await wait(s=>s.ended&&s.reason==='ENTITY_DEATH','Contact with the pursuing entity did not cause death');
      await capture('outage_death_'+lang);
    }
  }else if(policeMode){
    const command=async name=>{
      await evaluate('window.policeTelemetry.command="";window.policeCommand='+JSON.stringify(name));
      await wait(s=>s.command===name,'Police test command not acknowledged: '+name);
    };
    for(const lang of ['ru','en']){
      await call('Page.navigate',{url:url+'?lang='+lang});
      await wait(s=>s.mode===2,'Police PC fixture did not load',30);
      await call('Page.bringToFront');
      await call('Input.dispatchKeyEvent',{type:'keyDown',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await wait(s=>s.dev,'Police F7 menu did not open');
      await call('Input.dispatchKeyEvent',{type:'keyUp',code:'F7',key:'F7',windowsVirtualKeyCode:118});
      await sleep(300);
      await click((await state()).buttons.TriggerPolice);
      await wait(s=>!s.dev&&s.visit===1&&s.knock,'TriggerPolice did not start knock warning');
      await tap('Escape','Escape',27);
      await wait(s=>s.mode===0,'Could not leave PC during warning');
      await command('wardrobe');
      await sleep(2200);
      await click([640,360]);
      await wait(s=>s.captured&&s.interaction==='hide_wardrobe','Wardrobe interaction ray missing');
      await tap('KeyE','e',69,'e');
      let hidden=await wait(s=>s.hidden&&!s.controls,'Physical E did not enter wardrobe');
      const body=hidden.body,camera=hidden.camera;
      await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:1100,y:600});
      hidden=await wait(s=>Math.abs(s.look[0])>0.001,'Mouse look did not reach hiding camera');
      expect(Math.abs(hidden.look[0])<=12*Math.PI/180+0.0001&&Math.abs(hidden.look[1])<=6*Math.PI/180+0.0001,'Wardrobe look escaped limits');
      await call('Input.dispatchKeyEvent',{type:'keyDown',code:'KeyW',key:'w',windowsVirtualKeyCode:87});
      await sleep(250);
      await call('Input.dispatchKeyEvent',{type:'keyUp',code:'KeyW',key:'w',windowsVirtualKeyCode:87});
      hidden=await state();
      expect(hidden.body.every((n,i)=>Math.abs(n-body[i])<0.001)&&hidden.camera.every((n,i)=>Math.abs(n-camera[i])<0.001),'WASD or look moved hidden player/camera');
      await command('active');
      await wait(s=>s.visit===2&&s.hidden&&s.open&&!s.ended,'Wardrobe did not survive closed-door raid');
      await capture('police_wardrobe_'+lang);
      await command('search_done');
      await wait(s=>s.visit===3&&s.hidden,'Police departure did not begin');
      await tap('Escape','Escape',27);
      await wait(s=>s.hidden&&!s.captured,'Esc exposed hidden player instead of releasing pointer');
      await sleep(2200);await click([640,360]);
      await wait(s=>s.hidden&&s.captured,'Cannot recapture pointer inside hiding');
      await command('gone');
      await wait(s=>s.state===0&&s.hidden&&!s.steps,'Police departure did not clean up');
      await tap('KeyE','e',69,'e');
      await wait(s=>s.mode===0&&!s.hidden&&!s.ended&&s.open,'Exit after departure was not safe');
      await command('bed');
      await wait(s=>s.interaction==='hide_bed','Bed interaction ray missing');
      await command('trigger');
      await tap('KeyE','e',69,'e');
      await wait(s=>s.hidden,'Physical E did not enter bed');
      await command('active');
      await wait(s=>s.hidden&&s.visit===2&&!s.ended,'Bed did not survive police entry');
      await capture('police_bed_'+lang);
      await tap('KeyE','e',69,'e');
      await wait(s=>s.ended&&s.reason==='POLICE_DEATH','Early E exit did not cause police death');
      await capture('police_death_'+lang);
    }
  }else if(neighborMode){
    const command=async name=>{
      await evaluate('window.neighborTelemetry.command="";window.neighborCommand='+JSON.stringify(name));
      await wait(s=>s.command===name,'Test command not acknowledged: '+name);
    };
    await call('Page.navigate',{url});
    await wait(s=>s.mode===0&&!s.open,'Door fixture did not load',30);
    await call('Page.bringToFront');
    await click([640,360]);
    await wait(s=>s.captured&&s.interaction==='room_door','Door pointer capture failed');
    await tap('KeyE','e',69,'e');
    await wait(s=>s.open,'Physical E did not open door');
    await command('look_leaf');
    await wait(s=>s.interaction==='room_door','Open leaf ray did not update');
    await tap('KeyE','e',69,'e');
    await wait(s=>!s.open,'Physical E did not close leaf');
    await call('Input.dispatchKeyEvent',{type:'keyDown',code:'F7',key:'F7',windowsVirtualKeyCode:118});
    await wait(s=>s.dev,'F7 menu did not open');
    await call('Input.dispatchKeyEvent',{type:'keyUp',code:'F7',key:'F7',windowsVirtualKeyCode:118});
    await sleep(250);
    await click((await state()).buttons.TriggerNeighbor);
    await wait(s=>s.state===1&&s.steps&&!s.dev,'Dev command did not start audible approach');
    await command('active');
    await wait(s=>s.state===2&&s.visit===2,'Closed door did not protect against neighbor');
    await command('look_door');
    await sleep(2200); // Browser cooldown after dev-menu pointer release.
    await click([640,360]);
    await wait(s=>s.captured,'Pointer recapture failed');
    await tap('KeyE','e',69,'e');
    await wait(s=>s.open&&s.visit===3,'Opening during visit did not start entry');
    await capture('neighbor_entry');
    await command('look_leaf');
    await wait(s=>s.interaction==='room_door','Rescue ray did not update');
    await tap('KeyE','e',69,'e');
    await wait(s=>!s.open&&s.visit===2&&!s.ended,'Physical E did not save player');
    await command('leave');
    await wait(s=>s.state===0&&!s.ended,'Neighbor did not leave');
    await command('computer');
    await wait(s=>s.mode===2,'PC did not open after survival');
    await sleep(300);
    await capture('neighbor_pc_before_file');
    await click((await state()).file);
    await click((await state()).file,2);
    await wait(s=>s.active==='night_note','Double-click did not open night.txt');
    await capture('neighbor_txt');
    await tap('Escape','Escape',27);
    await wait(s=>s.mode===0,'Could not leave PC after reading TXT');
    await command('look_door');
    await sleep(2200);
    await click([640,360]);
    await wait(s=>s.captured&&s.interaction==='room_door','Could not return to door');
    await tap('KeyE','e',69,'e');
    await wait(s=>s.open,'Door did not reopen');
    await command('trigger');await command('active');await command('die');
    await wait(s=>s.ended&&s.reason==='NEIGHBOR_DEATH','Open door did not cause death');
    await capture('neighbor_death');
  }else if(threatMode){
    await call('Page.navigate',{url});
    let result;
    for(let i=0;i<600;i++){
      result=await evaluate('window.threatTestResult');
      if(result)break;
      await sleep(50);
    }
    expect(result&&result.failures===0,'Threat checks failed or timed out: '+JSON.stringify(result));
  }else for(const perfect of [true,false]) {
    await call('Page.navigate',{url:url+'?lang='+(perfect?'ru':'en')});
    await wait(s=>s.mode===2&&s.active==='chat','First-login chat failed',30);
    await call('Page.bringToFront');
    await wait(s=>s.pending===0,'Intro did not arrive');await capture('intro');
    await answer(0);await answer(0);await answer(0);
    await wait(s=>s.intro===3&&s.pending===0,'Tutorial not completed');
    if(shiftMode){
      const command=async name=>{await evaluate('window.shiftCommand='+JSON.stringify(name));await sleep(250);};
      const shiftState=()=>evaluate('window.shiftTelemetry');
      await command('hack');
      await click((await shiftState()).hack);
      expect((await shiftState()).state===2,'Alarm button did not start the route');
      await command('next');
      expect((await shiftState()).state===2,'Empty atmosphere pool should continue without scare pause');
      expect((await shiftState()).stage===1&&(await shiftState()).cameras===3,'Shop camera replacement failed');
      await command('next');
      expect((await shiftState()).stage===2,'Street did not start');
      await command('next');await command('return');
      await wait(s=>s.quiz&&s.mode===2,'Live report did not open');
    }else{
    await call('Input.dispatchKeyEvent',{type:'keyDown',code:'F7',key:'F7',windowsVirtualKeyCode:118});
    await wait(s=>s.dev,'Dev menu did not open');
    await call('Input.dispatchKeyEvent',{type:'keyUp',code:'F7',key:'F7',windowsVirtualKeyCode:118});
    await sleep(250); // Let the newly opened overlay finish container layout and telemetry.
    await click((await state()).buttons.DEV_CHAT_REPORT);
    await wait(s=>s.quiz&&!s.dev,'Report command failed');
    }
    await wait(s=>s.pending===0,'Report did not arrive');await capture('quiz');
    if(perfect){
      await call('Emulation.setDeviceMetricsOverride',{width:640,height:360,deviceScaleFactor:1,mobile:false});
      await sleep(300);await capture('small');
      await call('Emulation.setDeviceMetricsOverride',{width:1280,height:720,deviceScaleFactor:1,mobile:false});
      await sleep(300);
    }
    if(shiftMode){
      for(let q=0;q<3;q++){
        await wait(s=>s.pending===0&&s.options.length>0,'No live question');
        const correct=(await evaluate('window.shiftTelemetry')).correct;
        await answer(!perfect&&q===0?(correct+1)%3:correct);
      }
    }else{await answer(perfect?0:1);await answer(1);await answer(2);}
    const final=await wait(s=>s.frozen,'Result did not end run');
    expect(final.score===(perfect?3:2)&&!final.audio,'Wrong score / audio after ending');
    await capture(perfect?'win':'lose');
  }
  expect(errors.length===0,'Browser errors: '+errors.join('\n'));
  console.log(residentsMode?'RESIDENTS INPUT WEB: PASS (RU/EN dev buttons, question drag/close/repeat/resize, rendered peripheral sight, occlusion, threats and report cleanup).':firewallMode?'FIREWALL WEB: PASS (RU/EN dev click, ports/BLOCK, modal input, grace, win/loss, preservation, Esc/return, resize and cancellation).':idiotMode?'IDIOT WEB: PASS (RU/EN real dev click, drag/crosses, cap, taskbar/Esc, return, resize, fades and cleanup).':outageMode?'OUTAGE INPUT WEB: PASS (RU/EN, F7 trigger, blackout eject, F flashlight, encounter, provoked chase, contact death).':policeMode?'POLICE INPUT WEB: PASS (RU/EN, F7, PC escape, E hiding/exit, clamped mouse look, blocked walking, safe departure, early-exit death).':neighborMode?'NEIGHBOR INPUT WEB: PASS (pointer capture, real E, F7 trigger, rescue, TXT double-click, death).':threatMode?'THREAT WEB: PASS (shared scheduler and integration checks).':shiftMode?'SHIFT WEB: PASS (alarm click, scene transitions, live quiz input, 3/3 win, 2/3 loss).':'CHAT WEB: PASS (real choice clicks, key typing, Enter, audio triggers, F7 report, 3/3 win, 2/3 loss).');
} finally {ws?.close();browser.kill();server.close();}
