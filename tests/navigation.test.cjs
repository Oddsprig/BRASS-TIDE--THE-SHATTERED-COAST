'use strict';
const assert=require('node:assert/strict'),N=require('../dist/navigation.js');
const box=(x,y,w,h)=>({points:[[x,y],[x+w,y],[x+w,y+h],[x,y+h]]});
function safe(nav,path){for(let i=1;i<path.length;i++){const a=path[i-1],b=path[i],n=Math.ceil(Math.hypot(b.x-a.x,b.y-a.y)/2);for(let k=0;k<=n;k++)assert(N.isWater(nav,a.x+(b.x-a.x)*k/n,a.y+(b.y-a.y)*k/n),'segment stays clear of land');}}
let nav=N.create([],600,400),from={x:30,y:200},to={x:570,y:200};
assert.deepEqual(N.findPath(nav,from,to),[from,to]);
nav=N.create([box(250,100,100,200)],600,400);let path=N.findPath(nav,from,to);assert(path.length>=3);assert.deepEqual(path[0],from);assert.deepEqual(path.at(-1),to);safe(nav,path);
assert.deepEqual(N.findPath(nav,from,{x:300,y:200}),[]);assert.deepEqual(N.findPath(nav,{x:NaN,y:200},to),[]);
nav=N.create([box(0,190,600,20)],600,400);assert.deepEqual(N.findPath(nav,{x:100,y:100},{x:100,y:300}),[],'solid barrier cannot be crossed');
nav=N.create([box(80,0,40,80),box(0,80,80,40)],200,200,40);
assert.deepEqual(N.findPath(nav,{x:40,y:40},{x:160,y:160}),[],'diagonally touching corners cannot be cut');
nav=N.create([box(120,70,100,160)],400,300,40);from={x:108,y:150};to={x:350,y:150};path=N.findPath(nav,from,to);assert(path.length);safe(nav,path);assert.deepEqual(path[0],from);
nav=N.create([],2600,1800,1);assert(nav.nodes.length<5000);assert(N.findPath(nav,{x:30,y:30},{x:2500,y:1700}).flatMap(p=>[p.x,p.y]).every(Number.isFinite));
console.log('navigation: direct, island detour, blocked targets, barriers, diagonal corners, shore connections and bounded finite graph passed');
