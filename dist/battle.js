(function(root,factory){var api=factory(typeof module==='object'&&module.exports?require('./systems.js'):root.BrassSystems);if(typeof module==='object'&&module.exports)module.exports=api;root.BrassBattle=api;})(typeof globalThis!=='undefined'?globalThis:this,function(Systems){
'use strict';
var TAU=Math.PI*2, WIDTH=2300, HEIGHT=1700;
function clamp(v,a,b){return Math.max(a,Math.min(b,v));}
function angleDelta(a,b){var d=(b-a)%TAU;return d>Math.PI?d-TAU:d< -Math.PI?d+TAU:d;}
function distance(a,b){return Math.hypot(a.x-b.x,a.y-b.y);}
function radius(s){return Math.max(10,Number(s.spec.size)||16);}
function rng(seed){var n=(Number(seed)||1)>>>0;return function(){n=(Math.imul(n,1664525)+1013904223)>>>0;return n/4294967296;};}
function inside(x,y,points){var yes=false;for(var i=0,j=points.length-1;i<points.length;j=i++){var a=points[i],b=points[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])yes=!yes;}return yes;}
function segmentDistance(x,y,a,b){var dx=b[0]-a[0],dy=b[1]-a[1],t=clamp(((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy||1),0,1);return Math.hypot(x-a[0]-t*dx,y-a[1]-t*dy);}
function blocked(state,x,y,r){if(x<r||x>WIDTH-r||y<r||y>HEIGHT-r)return true;return state.islands.some(function(island){var p=island.points;if(inside(x,y,p))return true;for(var i=0;i<p.length;i++)if(segmentDistance(x,y,p[i],p[(i+1)%p.length])<r)return true;return false;});}
function segmentHit(p,s){var dx=p.x-p.px,dy=p.y-p.py,t=clamp(((s.x-p.px)*dx+(s.y-p.py)*dy)/(dx*dx+dy*dy||1),0,1);return {t:t,hit:Math.hypot(s.x-p.px-t*dx,s.y-p.py-t*dy)<radius(s)+p.radius};}
function effect(st,x,y,type){st.effects.push({x:x,y:y,type:type,age:0,life:type==='explosion'?1.3:type==='muzzle'?0.16:0.45});if(st.effects.length>200)st.effects.shift();}
function log(st,message){st.log.push(message);if(st.log.length>12)st.log.shift();}
function create(options){options=options||{};var st={ships:[],projectiles:[],effects:[],wrecks:[],time:0,result:null,playerId:null,order:'engage',rng:rng(options.seed),location:options.location||{name:'Open water'},islands:[],log:[],retreatTimer:null};
  st.islands=(options.islands||[]).map(function(i){return {points:(i.points||i).map(function(p){return [p[0],p[1]];})};}).filter(function(i){return i.points.length>=3;});
  // Margin rocks provide cover without blocking the central deployment corridor.
  if(!st.islands.length)st.islands=[{points:[[850,80],[1130,120],[1210,310],[1030,420],[820,300]]},{points:[[1040,1320],[1240,1250],[1430,1450],[1320,1640],[1070,1580]]}];
  function deploy(ship,index,team){ship.team=team;ship.id=team+'-'+index+'-'+(ship.type||ship.id||'boat');ship.x=(team==='player'?520:1600)+(index%2)*65;ship.y=850+(Math.floor(index/2)-(Math.ceil((team==='player'?(options.fleet||[]).length:(options.enemySpecs||[]).length)/2)-1)/2)*85;ship.angle=team==='player'?0:Math.PI;ship.turretAngle=ship.angle;ship.vx=0;ship.vy=0;ship.cooldown=0;ship._wreckRecorded=false;
    if(blocked(st,ship.x,ship.y,radius(ship))){for(var k=0;k<40;k++){var nx=team==='player'?300:1950,ny=200+k*32;if(!blocked(st,nx,ny,radius(ship))){ship.x=nx;ship.y=ny;break;}}}st.ships.push(ship);}
  (options.fleet||[]).forEach(function(s,i){deploy(s,i,'player');});
  (options.enemySpecs||[]).forEach(function(s,i){deploy(Systems.createShip(s),i,'enemy');});
  var first=st.ships.find(function(s){return s.team==='player'&&!s.sunk;});st.playerId=first?first.id:null;return st;
}
function getFlagship(st){return st.ships.find(function(s){return s.id===st.playerId&&!s.sunk;})||null;}
function selectFlagship(st,id){var s=st.ships.find(function(s){return s.id===id&&s.team==='player'&&!s.sunk;});if(!s)return false;st.playerId=id;return true;}
function setOrder(st,order){if(['engage','escort','hold','withdraw'].indexOf(order)!==-1)st.order=order;return st.order;}
function retreat(st){if(st.result||st.retreatTimer!==null)return;st.retreatTimer=12;setOrder(st,'withdraw');log(st,'Fleet withdrawing — 12 seconds to escape');}
function fire(st,s,target){if(s.cooldown>0||s.ammo<1||s.sunk||st.projectiles.length>=400)return;
  var status=Systems.getStatus(s);if(status.weaponFactor<=0.01)return;
  var weapon=s.spec.weapon||'gun',kind=weapon==='torpedo'?'torpedo':weapon==='gun'?'bullet':'shell';
  var speed=weapon==='torpedo'?240:weapon==='rocket'?730:weapon==='cannon'?620:850;
  var angle=Math.atan2(target.y-s.y,target.x-s.x);s.turretAngle=angle;
  var spread=(st.rng()-0.5)*(weapon==='torpedo'?0.025:0.045);angle+=spread;
  var r=radius(s)+6,x=s.x+Math.cos(angle)*r,y=s.y+Math.sin(angle)*r;
  st.projectiles.push({x:x,y:y,px:x,py:y,vx:Math.cos(angle)*speed+s.vx*0.2,vy:Math.sin(angle)*speed+s.vy*0.2,team:s.team,damage:(Number(s.spec.damage)||10)*(weapon==='torpedo'?1.8:1),kind:kind,life:(Number(s.spec.range)||400)/speed,owner:s.id,radius:kind==='torpedo'?5:2});
  s.ammo-=1;s.cooldown=1/(Math.max(0.05,Number(s.spec.fireRate)||1)*Math.max(0.15,status.weaponFactor));effect(st,x,y,'muzzle');
}
function nearest(st,s){var best=null,d=Infinity;st.ships.forEach(function(t){if(t.team!==s.team&&!t.sunk){var n=distance(s,t);if(n<d){d=n;best=t;}}});return best;}
function move(st,s,dt,desired,throttle,boost){var turn=Number(s.spec.turn)||1.8;s.angle+=clamp(angleDelta(s.angle,desired),-turn*dt,turn*dt);var speed=(Number(s.spec.speed)||90)*Systems.getStatus(s).speedFactor*(s.fuel>0?1:0.2)*throttle*(boost?1.2:1);
  var vx=Math.cos(s.angle)*speed,vy=Math.sin(s.angle)*speed,mix=1-Math.exp(-dt*4);s.vx+=(vx-s.vx)*mix;s.vy+=(vy-s.vy)*mix;var x=s.x+s.vx*dt,y=s.y+s.vy*dt;
  if(!blocked(st,x,y,radius(s))){s.x=x;s.y=y;}else{s.vx*=0.1;s.vy*=0.1;}
  if(Math.hypot(s.vx,s.vy)>5)s.fuel=Math.max(0,s.fuel-dt*(boost?0.018:0.01));
}
function ai(st,s,dt){var target=nearest(st,s);if(!target){move(st,s,dt,s.angle,0,false);return;}var desired=Math.atan2(target.y-s.y,target.x-s.x),d=distance(s,target),range=Number(s.spec.range)||400,throttle=d>range*0.72?0.85:d<range*0.35?-0.25:0.22;
  if(s.team==='player'){
    if(st.order==='withdraw'){desired=Math.PI;throttle=1;}
    if(st.order==='hold')throttle=0;
    if(st.order==='escort'){var lead=getFlagship(st);if(lead&&lead!==s&&distance(s,lead)>140){desired=Math.atan2(lead.y-s.y,lead.x-s.x);throttle=0.9;}}
  }
  // Look ahead and choose the clearest side; small incremental turn avoids shore jitter.
  var look=radius(s)+75;if(throttle>0&&blocked(st,s.x+Math.cos(desired)*look,s.y+Math.sin(desired)*look,radius(s)+8)){
    var offsets=[0.7,-0.7,1.3,-1.3,Math.PI];for(var k=0;k<offsets.length;k++){var a=desired+offsets[k];if(!blocked(st,s.x+Math.cos(a)*look,s.y+Math.sin(a)*look,radius(s)+8)){desired=a;break;}}
  }
  move(st,s,dt,desired,throttle,false);s.turretAngle=Math.atan2(target.y-s.y,target.x-s.x);if(d<range)fire(st,s,target);
}
function update(st,dt,input){if(st.result)return st;dt=clamp(Number(dt)||0,0,1/30);if(!dt)return st;input=input||{};st.time+=dt;
  if(!getFlagship(st)){var next=st.ships.find(function(s){return s.team==='player'&&!s.sunk;});if(next)st.playerId=next.id;}
  var flagship=getFlagship(st);
  st.ships.forEach(function(s){if(s.sunk)return;
    Systems.tickShip(s,dt,{inCombat:true});if(s.sunk)return;
    if(s===flagship&&st.order!=='withdraw'){
      var desired=s.angle+((input.right?1:0)-(input.left?1:0))*(Number(s.spec.turn)||1.8)*dt;
      move(st,s,dt,desired,(input.forward?1:0)-(input.backward?0.55:0),!!input.boost);
      if(Number.isFinite(input.aimX)&&Number.isFinite(input.aimY)){s.turretAngle=Math.atan2(input.aimY-s.y,input.aimX-s.x);if(input.fire)fire(st,s,{x:input.aimX,y:input.aimY});}
    }else ai(st,s,dt);
  });
  // Resolve overlap as hull-only contact: no cascading collision damage.
  for(var i=0;i<st.ships.length;i++)for(var j=i+1;j<st.ships.length;j++){var a=st.ships[i],b=st.ships[j];if(a.sunk||b.sunk)continue;var d=distance(a,b),min=radius(a)+radius(b);if(d<min){var nx=d?(b.x-a.x)/d:1,ny=d?(b.y-a.y)/d:0,push=(min-d)*0.51;
    var ax=a.x-nx*push,ay=a.y-ny*push,bx=b.x+nx*push,by=b.y+ny*push;
    if(!blocked(st,ax,ay,radius(a))){a.x=ax;a.y=ay;}if(!blocked(st,bx,by,radius(b))){b.x=bx;b.y=by;}}
  }
  st.projectiles=st.projectiles.filter(function(p){p.px=p.x;p.py=p.y;p.x+=p.vx*dt;p.y+=p.vy*dt;p.life-=dt;
    var hit=null,first=Infinity;st.ships.forEach(function(s){if(s.sunk||s.team===p.team)return;var test=segmentHit(p,s);if(test.hit&&test.t<first){hit=s;first=test.t;}});
    // Sample the short swept path for terrain, stopping shots at rocky cover.
    var landT=Infinity,steps=Math.max(1,Math.ceil(Math.hypot(p.x-p.px,p.y-p.py)/6));for(var k=1;k<=steps;k++){var t=k/steps;if(blocked(st,p.px+(p.x-p.px)*t,p.py+(p.y-p.py)*t,p.radius)){landT=t;break;}}
    if(hit&&first<landT){var hx=p.px+(p.x-p.px)*first,hy=p.py+(p.y-p.py)*first;var events=Systems.applyHit(hit,{damage:p.damage,kind:p.kind,section:st.rng()<0.25?'engine':'bow'},st.rng);effect(st,hx,hy,p.kind==='torpedo'?'explosion':'hit');if(events.length)log(st,hit.name+': '+events[0]);return false;}
    if(landT!==Infinity||p.life<=0){effect(st,p.x,p.y,'splash');return false;}return true;
  });
  st.effects=st.effects.filter(function(e){e.age+=dt;return e.age<e.life;});
  st.ships.forEach(function(s){if(s.sunk&&!s._wreckRecorded){s._wreckRecorded=true;st.wrecks.push({x:s.x,y:s.y,angle:s.angle,name:s.name,team:s.team,size:radius(s)});effect(st,s.x,s.y,'explosion');log(st,s.name+' sunk');}});
  var players=st.ships.filter(function(s){return s.team==='player'&&!s.sunk;}),enemies=st.ships.filter(function(s){return s.team==='enemy'&&!s.sunk;});
  if(!getFlagship(st)&&players.length)st.playerId=players[0].id;
  if(!players.length)st.result='lost';else if(!enemies.length)st.result='won';else if(st.retreatTimer!==null){st.retreatTimer=Math.max(0,st.retreatTimer-dt);if(st.retreatTimer<=1e-8)st.result='retreated';}
  return st;
}
return {create:create,update:update,setOrder:setOrder,selectFlagship:selectFlagship,getFlagship:getFlagship,retreat:retreat,WIDTH:WIDTH,HEIGHT:HEIGHT};
});
