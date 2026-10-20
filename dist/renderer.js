(function(root){
'use strict';
const TAU=Math.PI*2, C={sea:'#173d47',deep:'#102b38',foam:'#93c8bc',gold:'#dfbc7e',text:'#d4dfcf',red:'#e48a70'};
function hash(n){let x=Math.sin(n*127.1+311.7)*43758.5453;return x-Math.floor(x);}
class Renderer{
 constructor(canvas){this.canvas=canvas;this.ctx=canvas.getContext('2d',{alpha:false});this.zoom=1;this.time=0;this.cam={x:1300,y:900,scale:.45};this.width=innerWidth;this.height=innerHeight;this.quality=1.5;this.lastMode='';this.resize();addEventListener('resize',()=>this.resize());}
 resize(){this.width=innerWidth;this.height=innerHeight;const dpr=Math.min(devicePixelRatio||1,this.quality);this.canvas.width=Math.round(this.width*dpr);this.canvas.height=Math.round(this.height*dpr);this.ctx.setTransform(dpr,0,0,dpr,0,0);this.dpr=dpr;}
 project(x,y,z=0){const dx=x-this.cam.x,dy=y-this.cam.y;return {x:this.width/2+(dx-dy)*.82*this.cam.scale,y:this.height/2+(dx+dy)*.41*this.cam.scale-z*this.cam.scale};}
 unproject(x,y){const px=(x-this.width/2)/(.82*this.cam.scale),py=(y-this.height/2)/(.41*this.cam.scale);return {x:this.cam.x+(px+py)/2,y:this.cam.y+(py-px)/2};}
 path(points,z=0){const c=this.ctx;c.beginPath();points.forEach((p,i)=>{const s=this.project(p[0],p[1],z);i?c.lineTo(s.x,s.y):c.moveTo(s.x,s.y);});c.closePath();}
 line(points,color,width=1,dash=[]){const c=this.ctx;c.beginPath();points.forEach((p,i)=>{const s=this.project(p.x??p[0],p.y??p[1]);i?c.lineTo(s.x,s.y):c.moveTo(s.x,s.y);});c.strokeStyle=color;c.lineWidth=width;c.setLineDash(dash);c.stroke();c.setLineDash([]);}
 render(game,dt){this.time+=dt;const mode=game.scene,c=this.ctx;if(mode==='title'){this.cam.x=1130;this.cam.y=710;this.cam.scale=Math.min(this.width/1700,this.height/1000)*.95;}
  else if(mode==='battle'&&game.battle){const s=root.BrassBattle.getFlagship(game.battle)||game.battle.ships[0];if(s){const rate=1-Math.exp(-dt*3);this.cam.x+=(s.x-this.cam.x)*rate;this.cam.y+=(s.y-this.cam.y)*rate;}this.cam.scale=Math.max(.47,Math.min(.9,this.width/1500))*this.zoom;}
  else{this.cam.x=1300;this.cam.y=900;this.cam.scale=Math.min((this.width-110)/3608,(this.height-160)/1804)*this.zoom;}
  if(this.lastMode!==mode){if(mode==='battle'&&game.battle){const s=root.BrassBattle.getFlagship(game.battle);if(s){this.cam.x=s.x;this.cam.y=s.y;}}this.lastMode=mode;}
  const bg=c.createLinearGradient(0,0,this.width,this.height);bg.addColorStop(0,'#183c47');bg.addColorStop(.55,'#1b454d');bg.addColorStop(1,'#0f2b38');c.fillStyle=bg;c.fillRect(0,0,this.width,this.height);
  this.drawSea();
  if(mode==='battle'&&game.battle)this.drawBattle(game);
  else if(mode==='title')this.drawTitle(game);
  else this.drawCampaign(game);
 }
 drawSea(){const c=this.ctx;c.lineWidth=1;for(let i=0;i<48;i++){const x=hash(i+9)*this.width,y=(hash(i+103)*this.height+this.time*(1+hash(i)*2))%this.height,len=10+hash(i+5)*30;c.strokeStyle=`rgba(134,191,183,${.035+hash(i+8)*.035})`;c.beginPath();c.moveTo(x,y);c.quadraticCurveTo(x+len*.5,y+2,x+len,y);c.stroke();}}
 island(island,index,battle=false){const c=this.ctx,p=island.points;if(!p?.length)return;let cx=0,cy=0;p.forEach(v=>{cx+=v[0]/p.length;cy+=v[1]/p.length;});
  for(let r=2;r>=1;r--){const expanded=p.map(v=>[cx+(v[0]-cx)*(1+r*.10),cy+(v[1]-cy)*(1+r*.10)]);this.path(expanded,-8);c.fillStyle=r===2?'#2c5a5a66':'#386d6466';c.fill();}
  this.path(p,-16);c.fillStyle='#0d2935';c.fill();this.path(p,0);c.fillStyle='#c0b384';c.fill();c.strokeStyle='#86b2a059';c.lineWidth=1;c.stroke();
  const inner=p.map(v=>[cx+(v[0]-cx)*.91,cy+(v[1]-cy)*.91]);this.path(inner,7);c.fillStyle=island.color||(battle?'#51655a':['#4c6d58','#56705b','#46665b','#61705a'][index%4]);c.fill();
  const core=p.map(v=>[cx+(v[0]-cx)*.69,cy+(v[1]-cy)*.69]);this.path(core,17);c.fillStyle=battle?'#52655b':'#385747';c.fill();
  const spanX=Math.max(...p.map(v=>v[0]))-Math.min(...p.map(v=>v[0])),spanY=Math.max(...p.map(v=>v[1]))-Math.min(...p.map(v=>v[1]));
  for(let k=0;k<(battle?12:27);k++){const x=cx+(hash(index*91+k*7)-.5)*spanX*.7,y=cy+(hash(index*37+k*17)-.5)*spanY*.7;if(!this.pointInside(x,y,p))continue;const s=this.project(x,y,20),size=(5+hash(k+index)*9)*this.cam.scale;c.fillStyle=k%4===0?'#67856c':'#284d43';c.beginPath();c.moveTo(s.x,s.y-size*2);c.lineTo(s.x-size,s.y+size*.3);c.lineTo(s.x+size,s.y+size*.3);c.closePath();c.fill();}
  if(!battle&&this.cam.scale>.20){const s=this.project(cx,cy,30);c.font=`italic ${Math.max(10,18*this.cam.scale)}px Georgia`;c.textAlign='center';c.fillStyle='#e5dfbb70';c.fillText((island.name||'').toUpperCase(),s.x,s.y);}
 }
 pointInside(x,y,p){let a=false;for(let i=0,j=p.length-1;i<p.length;j=i++){if((p[i][1]>y)!==(p[j][1]>y)&&x<(p[j][0]-p[i][0])*(y-p[i][1])/(p[j][1]-p[i][1])+p[i][0])a=!a;}return a;}
 town(port,index){const c=this.ctx;const faction=root.BrassData.FACTIONS.find(f=>f.id===port.faction),color=faction?.color||C.gold;const s=this.project(port.x,port.y);const selected=root.BrassGame?.selectedPort===port.id;
  c.strokeStyle=selected?C.gold:'#78b7ae60';c.lineWidth=selected?2:1;c.beginPath();c.ellipse(s.x,s.y,selected?17:11,selected?8:5,0,0,TAU);c.stroke();
  for(let i=0;i<4;i++){const pt=this.project(port.x+(i-1.5)*18,port.y-14,5),w=7,h=7+hash(index*4+i)*8;c.fillStyle='#153b42';c.fillRect(pt.x-w/2,pt.y-h,w,h);c.fillStyle=i===0?color:'#b1b595';c.beginPath();c.moveTo(pt.x-w/2-1,pt.y-h);c.lineTo(pt.x,pt.y-h-4);c.lineTo(pt.x+w/2+1,pt.y-h);c.closePath();c.fill();}
  c.fillStyle=color;c.fillRect(s.x+9,s.y-35,1,24);c.beginPath();c.moveTo(s.x+10,s.y-35);c.lineTo(s.x+22,s.y-31);c.lineTo(s.x+10,s.y-27);c.fill();
  c.textAlign='center';c.font=selected?'600 13px Segoe UI':'11px Segoe UI';c.fillStyle=selected?'#f0d09a':'#d3dfd0';c.shadowColor='#0a2534';c.shadowBlur=6;c.fillText(port.name,s.x,s.y+25);c.shadowBlur=0;c.font='8px Consolas';c.fillStyle='#a6c4b3';c.fillText((port.industry||'harbor').toUpperCase(),s.x,s.y+38);
 }
 ship(ship,options={}){const c=this.ctx,spec=ship.spec||ship,scale=options.scale||1,size=(spec.size||18)*scale,angle=ship.angle||0,color=options.color||C.gold;const x=ship.x||0,y=ship.y||0;
  const transform=(a,b,z=0)=>this.project(x+Math.cos(angle)*a-Math.sin(angle)*b,y+Math.sin(angle)*a+Math.cos(angle)*b,z);
  const shape=(points,z)=>{c.beginPath();points.forEach((p,i)=>{const s=transform(p[0]*size,p[1]*size,z);i?c.lineTo(s.x,s.y):c.moveTo(s.x,s.y);});c.closePath();};
  const velocity=Math.hypot(ship.vx||0,ship.vy||0);if(velocity>8||options.wake){const wave=(this.time*velocity*.4)%20;for(let i=0;i<5;i++){const tail=transform(-size*(1.4+i*.5)-wave,-0,0),width=(size*.4+i*size*.16)*this.cam.scale;c.strokeStyle=`rgba(178,220,199,${.19-i*.03})`;c.lineWidth=1;c.beginPath();c.ellipse(tail.x,tail.y,width,width*.22,Math.atan2(.41*(Math.cos(angle)+Math.sin(angle)),.82*(Math.cos(angle)-Math.sin(angle)))+Math.PI/2,0,Math.PI);c.stroke();}}
  const hull=[[1.85,0],[.6,-.61],[-1.35,-.55],[-1.65,-.27],[-1.65,.27],[-1.35,.55],[.6,.61]];
  if(options.selected){const s=this.project(x,y);c.strokeStyle='#d9bc79';c.lineWidth=1;c.setLineDash([4,5]);c.beginPath();c.ellipse(s.x,s.y,size*2.4*this.cam.scale,size*1.15*this.cam.scale,0,0,TAU);c.stroke();c.setLineDash([]);}
  shape(hull,-5);c.fillStyle='#061d28c0';c.fill();shape(hull,4);c.fillStyle='#122d37';c.fill();c.strokeStyle=color;c.lineWidth=Math.max(1,this.cam.scale*1.7);c.stroke();
  const deck=hull.map(p=>[p[0]*.84,p[1]*.76]);shape(deck,8);c.fillStyle=options.enemy?'#885d47':'#a49669';c.fill();
  if((spec.role||'').toLowerCase().includes('cat')||(spec.id||'').includes('cat')){shape([[1.5,-.8],[-1.6,-.8],[-1.6,-.57],[1.3,-.57]],3);c.fillStyle='#1b3b40';c.fill();shape([[1.5,.8],[-1.6,.8],[-1.6,.57],[1.3,.57]],3);c.fill();}
  shape([[-.7,-.33],[.05,-.33],[.05,.33],[-.7,.33]],15);c.fillStyle='#c4bf9c';c.fill();shape([[-.64,-.26],[-.12,-.26],[-.12,.26],[-.64,.26]],17);c.fillStyle='#37545a';c.fill();
  // Fixed helmsman and gunner marks are part of this small boat drawing.
  const helm=transform(-.08*size,0,19);c.fillStyle='#d5c5a4';c.beginPath();c.arc(helm.x,helm.y,Math.max(1.1,1.7*this.cam.scale),0,TAU);c.fill();
  const gun=transform(.72*size,0,13),turret=ship.turretAngle??angle,tip=this.project(x+Math.cos(angle)*.72*size+Math.cos(turret)*size*.9,y+Math.sin(angle)*.72*size+Math.sin(turret)*size*.9,13);c.fillStyle='#233f44';c.beginPath();c.ellipse(gun.x,gun.y,size*.21*this.cam.scale,size*.13*this.cam.scale,0,0,TAU);c.fill();c.strokeStyle='#d1d0ae';c.lineWidth=Math.max(1.5,3*this.cam.scale);c.beginPath();c.moveTo(gun.x,gun.y);c.lineTo(tip.x,tip.y);c.stroke();
  if(spec.tier>=3){const stern=transform(-1.15*size,0,10);c.fillStyle=color;c.fillRect(stern.x-3*this.cam.scale,stern.y-3*this.cam.scale,6*this.cam.scale,6*this.cam.scale);}
  if(ship.fire>0){const s=this.project(x,y,15);for(let i=0;i<3;i++){c.fillStyle=i%2?'#f3c56c88':'#ed8558aa';c.beginPath();c.arc(s.x+Math.sin(this.time*12+i)*size*.25,s.y-(5+i*4)*this.cam.scale,(4+i*2)*this.cam.scale,0,TAU);c.fill();}}
  if(ship.hp!=null&&!options.noBars){const s=this.project(x,y,-28),w=Math.max(28,size*2*this.cam.scale);c.fillStyle='#06212dc9';c.fillRect(s.x-w/2,s.y,w,3);c.fillStyle=ship.hp/ship.maxHp<.3?C.red:color;c.fillRect(s.x-w/2,s.y,w*Math.max(0,ship.hp/ship.maxHp),3);if(ship.water>1){c.fillStyle='#7cb8dc';c.fillRect(s.x-w/2,s.y+5,w*ship.water/ship.capacity,2);}}
 }
 drawCampaign(game){const c=this.ctx,d=root.BrassData,w=game.world;if(!w)return;const ports=w.ports;
  c.strokeStyle='#85c5b108';c.lineWidth=1;for(let x=0;x<=2600;x+=200)this.line([{x,y:0},{x,y:1800}],'#8cc9bd08');for(let y=0;y<=1800;y+=200)this.line([{x:0,y},{x:2600,y}],'#8cc9bd08');
  (d.ROUTES||[]).forEach(route=>{const a=ports.find(p=>p.id===route[0]),b=ports.find(p=>p.id===route[1]);if(a&&b)this.line([a,b],'#9cc4ae1c',1,[2,7]);});
  d.ISLANDS.forEach((island,i)=>this.island(island,i));
  if(w.path?.length)this.line([w.position,...w.path],'#ddbd77a0',1.5,[4,5]);
  (w.patrols||[]).forEach((p,i)=>{if(!p.active)return;const s=this.project(p.x,p.y);c.save();c.translate(s.x,s.y);c.rotate(Math.PI/4);c.fillStyle=p.hostile?'#d88e7280':'#84bbaf66';c.strokeStyle=p.hostile?'#efa487':'#8abfb0';c.lineWidth=1;c.fillRect(-4,-4,8,8);c.strokeRect(-4,-4,8,8);c.restore();if(game.hoverPatrol===p.id){c.font='10px Consolas';c.fillStyle=C.text;c.textAlign='center';c.fillText(p.name,s.x,s.y-15);}});
  ports.forEach((p,i)=>this.town(p,i));
  const fleet=w.fleet.filter(s=>!s.sunk);fleet.slice(0,8).forEach((s,i)=>{const offset=i===0?{x:0,y:0}:{x:-35*Math.ceil(i/2),y:(i%2?1:-1)*26};this.ship({...s,x:w.position.x+offset.x,y:w.position.y+offset.y,angle:w.heading||0,vx:w.path?.length?30:0,vy:0},{scale:1.1,color:i===0?C.gold:'#8bc1b1',noBars:true,selected:i===0});});
  const pos=this.project(w.position.x,w.position.y,25);c.textAlign='center';c.font='9px Consolas';c.fillStyle=C.gold;c.fillText('YOUR FLEET',pos.x,pos.y-22);
  const contract=game.activeContract;if(contract){const target=ports.find(p=>p.id===contract.targetPort);if(target){const s=this.project(target.x,target.y,55);c.strokeStyle=C.gold;c.lineWidth=1;c.beginPath();c.moveTo(s.x,s.y-9);c.lineTo(s.x+7,s.y);c.lineTo(s.x,s.y+9);c.lineTo(s.x-7,s.y);c.closePath();c.stroke();}}
  this.compass();
 }
 drawTitle(game){const d=root.BrassData;const islands=d?.ISLANDS?.length?d.ISLANDS:[{points:[[400,250],[680,220],[800,400],[650,540],[380,470]],name:'THE SHATTER COAST'}];islands.forEach((is,i)=>this.island(is,i));
  const hull=d?.HULLS?.[Math.min(8,d.HULLS.length-1)]||{size:27,tier:3};const t=this.time;this.ship({spec:hull,x:1350+Math.sin(t*.07)*100,y:640+Math.cos(t*.07)*100,angle:.9,vx:50,vy:30},{scale:2.2,color:C.gold,noBars:true,wake:true});this.ship({spec:d?.HULLS?.[2]||hull,x:1150+Math.sin(t*.07)*100,y:750+Math.cos(t*.07)*100,angle:.9,vx:50,vy:30},{scale:1.5,color:'#a0b4a3',noBars:true,wake:true});
  const c=this.ctx;c.textAlign='right';c.fillStyle='#acd1bd55';c.font='10px Consolas';c.fillText('14° 27′ N   /   108° 12′ E',this.width-40,this.height-40);this.compass();
 }
 drawBattle(game){const b=game.battle,c=this.ctx;b.islands.forEach((is,i)=>this.island(is,i,true));
  const flagship=root.BrassBattle.getFlagship(b);if(flagship){const p=this.project(flagship.x,flagship.y);const range=flagship.spec.range*this.cam.scale;c.strokeStyle='#b9ce9b10';c.setLineDash([2,9]);c.lineWidth=1;c.beginPath();c.ellipse(p.x,p.y,range*1.16,range*.58,0,0,TAU);c.stroke();c.setLineDash([]);}
  b.wrecks.forEach(w=>{const p=this.project(w.x,w.y);c.fillStyle='#09232a77';c.beginPath();c.ellipse(p.x,p.y,w.size*2*this.cam.scale,w.size*.9*this.cam.scale,0,0,TAU);c.fill();});
  b.ships.filter(s=>!s.sunk).sort((a,b)=>(a.x+a.y)-(b.x+b.y)).forEach(s=>this.ship(s,{color:s.team==='enemy'?C.red:s.id===b.playerId?C.gold:'#90cabb',selected:s.id===b.playerId,enemy:s.team==='enemy'}));
  b.projectiles.forEach(p=>{const a=this.project(p.px,p.py,8),z=this.project(p.x,p.y,8);c.lineWidth=p.kind==='torpedo'?3:2;c.strokeStyle=p.kind==='torpedo'?'#99dbc7':p.team==='enemy'?'#edaa7d':'#f7dba2';c.beginPath();c.moveTo(a.x,a.y);c.lineTo(z.x,z.y);c.stroke();if(p.kind==='torpedo'){c.strokeStyle='#a9d4bf77';c.lineWidth=1;c.beginPath();c.moveTo(z.x-10,z.y+5);c.lineTo(z.x,z.y);c.stroke();}});
  b.effects.forEach(e=>{const p=this.project(e.x,e.y,8),progress=e.age/e.life,r=(e.type==='explosion'?30:e.type==='muzzle'?12:15)*this.cam.scale*(.2+progress);c.globalAlpha=1-progress;c.fillStyle=e.type==='splash'?'#a6ddcf99':e.type==='muzzle'?'#ffe0a2':'#edac6a';c.beginPath();c.arc(p.x,p.y,r,0,TAU);c.fill();c.strokeStyle='#eee7bb';c.lineWidth=1;c.stroke();c.globalAlpha=1;});
  if(flagship){const foe=b.ships.filter(s=>s.team==='enemy'&&!s.sunk).sort((a,z)=>Math.hypot(a.x-flagship.x,a.y-flagship.y)-Math.hypot(z.x-flagship.x,z.y-flagship.y))[0];if(foe){const p=this.project(foe.x,foe.y),sx=Math.max(335,Math.min(this.width-335,p.x)),sy=Math.max(115,Math.min(this.height-160,p.y));if(p.x!==sx||p.y!==sy){c.save();c.translate(sx,sy);c.rotate(Math.atan2(p.y-sy,p.x-sx));c.fillStyle=C.red;c.beginPath();c.moveTo(10,0);c.lineTo(-6,-5);c.lineTo(-6,5);c.fill();c.restore();c.font='10px Consolas';c.fillStyle=C.red;c.textAlign='center';c.fillText(Math.round(Math.hypot(foe.x-flagship.x,foe.y-flagship.y))+' m',sx,sy+20);}}}
  this.minimap(b);
  if(game.paused){c.fillStyle='#0a20285e';c.fillRect(0,70,this.width,this.height-70);c.textAlign='center';c.font='32px Georgia';c.fillStyle=C.gold;c.fillText('Tactical pause',this.width/2,120);c.font='10px Consolas';c.fillStyle=C.text;c.fillText('SET DAMAGE CONTROL & FLEET ORDERS · SPACE TO RESUME',this.width/2,145);}
 }
 minimap(b){const c=this.ctx,x=this.width-205,y=this.height-270,w=170,h=125;c.fillStyle='#071d27bd';c.fillRect(x,y,w,h);c.strokeStyle='#789f8f55';c.strokeRect(x,y,w,h);const point=(px,py)=>[x+px/2300*w,y+py/1700*h];b.islands.forEach(is=>{c.beginPath();is.points.forEach((p,i)=>{const s=point(...p);i?c.lineTo(...s):c.moveTo(...s);});c.closePath();c.fillStyle='#637966';c.fill();});b.ships.filter(s=>!s.sunk).forEach(s=>{const p=point(s.x,s.y);c.fillStyle=s.team==='enemy'?C.red:s.id===b.playerId?C.gold:'#83c6b4';c.beginPath();c.arc(...p,s.id===b.playerId?3:2,0,TAU);c.fill();});c.font='8px Consolas';c.fillStyle='#b4c9bc';c.textAlign='left';c.fillText('TACTICAL CHART',x+5,y-8);}
 compass(){const c=this.ctx,x=this.width-70,y=this.height-125;c.save();c.translate(x,y);c.strokeStyle='#a3c9b340';c.lineWidth=1;c.beginPath();c.arc(0,0,24,0,TAU);c.moveTo(-31,0);c.lineTo(31,0);c.moveTo(0,-31);c.lineTo(0,31);c.stroke();c.fillStyle='#c4d1b56b';c.beginPath();c.moveTo(0,-24);c.lineTo(4,0);c.lineTo(-4,0);c.fill();c.font='8px Consolas';c.textAlign='center';c.fillText('N',0,-35);c.restore();}
}
root.BrassRenderer=Renderer;
})(globalThis);
