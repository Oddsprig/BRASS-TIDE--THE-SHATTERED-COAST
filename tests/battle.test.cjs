'use strict';
const assert=require('node:assert/strict'),S=require('../dist/systems.js'),B=require('../dist/battle.js');
const spec={id:'skiff',name:'Skiff',hp:130,armor:1,crewMin:2,crewOptimal:5,crewMax:7,size:16,speed:100,turn:2,pumps:1,weapon:'gun',damage:12,fireRate:2,range:550};
function create(n=1){return B.create({fleet:Array.from({length:n},()=>S.createShip(spec)),enemySpecs:[spec],seed:42});}
function step(st,n,input){for(let i=0;i<n;i++)B.update(st,1/30,input||{});}
let st=create(2),actual=st.ships[0];assert.strictEqual(B.getFlagship(st),actual);
assert(B.selectFlagship(st,st.ships[1].id));assert(!B.selectFlagship(st,st.ships[2].id));
st.ships[1].sunk=true;step(st,1);assert.strictEqual(B.getFlagship(st),actual);assert.equal(st.wrecks.length,1);
let enemy=st.ships[2];enemy.x=actual.x+180;enemy.y=actual.y;enemy.spec.speed=0;
const hp=enemy.hp;step(st,50,{fire:true,aimX:enemy.x,aimY:enemy.y});assert(enemy.hp<hp,'swept projectile hits damage enemy');assert(actual.ammo<80);
assert.strictEqual(st.ships[0],actual,'campaign boat reference retained');
enemy.sunk=true;step(st,1);assert.equal(st.result,'won');const frozen=st.time;step(st,20);assert.equal(st.time,frozen);
st=create();st.ships[0].sunk=true;step(st,1);assert.equal(st.result,'lost');
st=create();st.ships.forEach(s=>s.ammo=0);B.retreat(st);step(st,361);assert.equal(st.result,'retreated');
let a=create(),b=create();for(let i=0;i<3600;i++){const e=a.ships[1],input={forward:i<200,fire:true,aimX:e.x,aimY:e.y};B.update(a,1/30,input);B.update(b,1/30,input);}
function serial(s){return JSON.stringify(s,(k,v)=>typeof v==='function'?undefined:v);}
assert.equal(serial(a),serial(b),'same seed and input yield identical state');
for(const boat of a.ships)for(const key of ['x','y','angle','vx','vy','hp','water','fuel','ammo'])assert(Number.isFinite(boat[key]),key);
assert(a.effects.length<=200&&a.projectiles.length<=400);assert(a.log.length<=12);
st=create();st.ships[0].ammo=0;step(st,120,{fire:true,aimX:1600,aimY:850});assert(!st.projectiles.some(p=>p.team==='player'));
console.log('battle: deterministic simulation, hits, references, flagship, outcomes, retreat, stocks and caps passed');
