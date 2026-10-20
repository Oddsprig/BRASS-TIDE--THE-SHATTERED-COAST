'use strict';
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const data=require(path.join(root,'dist/content.js'));
const build=Number(fs.readFileSync(path.join(root,'game/scripts/version.gd'),'utf8').match(/BUILD: int = (\d+)/)[1]);
const world=JSON.parse(JSON.stringify(data));
world.BUILD=build;world.VERSION=(build/1000).toFixed(3);
world.HULLS.find(h=>h.id==='krill_torpedo').name='Tallowfin Torpedo Boat';
// Earlier drafting used an existing reference game's boat name. The release uses an original name.
// Hull values are calculated by construction.gd from materials and paid occupations.
for(const hull of world.HULLS) delete hull.price;
delete world.START.credits;
world.START.coins=world.START.crew*100*30; // inherited thirty days of ordinary payroll
for(const mission of world.MISSIONS) delete mission.reward; // funded offers calculated from hull value
world.CURRENCY={name:'bronze cash',ordinaryDailyWage:100,coinsPerString:1000};
fs.writeFileSync(path.join(root,'game/data/world.json'),JSON.stringify(world,null,2)+'\n');
console.log(`World data ${world.VERSION}: ${world.HULLS.length} hulls, ${world.PORTS.length} ports, ${world.MISSIONS.length} story contracts`);
