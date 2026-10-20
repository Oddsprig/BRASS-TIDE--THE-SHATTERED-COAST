'use strict';

const assert = require('node:assert/strict');
const BrassData = require('../dist/content.js');

function pointInPolygon(px, py, points) {
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const xi = points[i][0], yi = points[i][1];
    const xj = points[j][0], yj = points[j][1];
    const intersect = ((yi > py) !== (yj > py)) &&
      (px < ((xj - xi) * (py - yi)) / ((yj - yi) || 1e-12) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

function distToSegment(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) return Math.hypot(px - x1, py - y1);
  const t = Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / lenSq));
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
}

function ccw(ax, ay, bx, by, cx, cy) {
  return (cy - ay) * (bx - ax) > (by - ay) * (cx - ax);
}

function segmentsIntersect(ax, ay, bx, by, cx, cy, dx, dy) {
  return (ccw(ax, ay, cx, cy, dx, dy) !== ccw(bx, by, cx, cy, dx, dy)) &&
         (ccw(ax, ay, bx, by, cx, cy) !== ccw(ax, ay, bx, by, dx, dy));
}

function segmentIntersectsPolygon(x1, y1, x2, y2, points) {
  if (pointInPolygon(x1, y1, points) || pointInPolygon(x2, y2, points)) return true;
  for (let i = 0; i < points.length; i++) {
    const [ax, ay] = points[i];
    const [bx, by] = points[(i + 1) % points.length];
    if (segmentsIntersect(x1, y1, x2, y2, ax, ay, bx, by)) return true;
  }
  const steps = 20;
  for (let s = 1; s < steps; s++) {
    const t = s / steps;
    const mx = x1 + (x2 - x1) * t;
    const my = y1 + (y2 - y1) * t;
    if (pointInPolygon(mx, my, points)) return true;
  }
  return false;
}

// 1. Top-level contract and global exposure
assert.equal(globalThis.BrassData, BrassData, 'BrassData must be exposed on globalThis');
assert.equal(BrassData.TITLE, 'BRASS TIDE');
assert.equal(BrassData.SUBTITLE, 'THE SHATTER COAST');
assert.equal(BrassData.VERSION, '1.0.0');
assert.deepEqual(BrassData.WORLD, { width: 2600, height: 1800 });

// 2. Factions check
const expectedFactionIds = ['compact', 'forge', 'reed', 'raiders'];
assert.equal(BrassData.FACTIONS.length, 4, 'Must have exactly 4 factions');
const factionIds = new Set();
for (const f of BrassData.FACTIONS) {
  assert.ok(f.id && typeof f.id === 'string');
  assert.ok(f.name && typeof f.name === 'string');
  assert.match(f.color, /^#[0-9a-fA-F]{6}$/);
  assert.ok(f.description && f.description.length > 10);
  assert.ok(f.doctrine && f.doctrine.length > 10);
  factionIds.add(f.id);
}
assert.deepEqual(Array.from(factionIds), expectedFactionIds);

// 3. Hulls check (24 hulls across 8 roles x 3 variants)
assert.equal(BrassData.HULLS.length, 24, 'Must have 24 original hulls');
const hullIds = new Set();
const roleCounts = new Map();
const allowedWeapons = new Set(['gun', 'cannon', 'torpedo', 'rocket']);

for (const h of BrassData.HULLS) {
  assert.ok(h.id && !hullIds.has(h.id), `Duplicate or missing hull id: ${h.id}`);
  hullIds.add(h.id);
  assert.ok(h.name && typeof h.name === 'string');
  assert.ok(factionIds.has(h.faction), `Hull ${h.id} has invalid faction ${h.faction}`);
  assert.ok(h.role && typeof h.role === 'string');
  roleCounts.set(h.role, (roleCounts.get(h.role) || 0) + 1);

  const numericFields = [
    'hp', 'armor', 'speed', 'turn', 'crewMin', 'crewOptimal', 'crewMax',
    'cargo', 'price', 'fireRate', 'damage', 'range', 'size', 'pumps', 'tier'
  ];
  for (const field of numericFields) {
    assert.ok(Number.isFinite(h[field]), `Hull ${h.id}.${field} must be finite`);
  }

  assert.ok(h.hp >= 100 && h.hp <= 700, `Hull ${h.id} hp out of range: ${h.hp}`);
  assert.ok(h.armor >= 0 && h.armor <= 20, `Hull ${h.id} armor out of range: ${h.armor}`);
  assert.ok(h.speed >= 55 && h.speed <= 150, `Hull ${h.id} speed out of range: ${h.speed}`);
  assert.ok(h.turn >= 1 && h.turn <= 3, `Hull ${h.id} turn out of range: ${h.turn}`);
  assert.ok(h.damage >= 8 && h.damage <= 50, `Hull ${h.id} damage out of range: ${h.damage}`);
  assert.ok(h.range >= 260 && h.range <= 620, `Hull ${h.id} range out of range: ${h.range}`);
  assert.ok(h.price >= 600 && h.price <= 24000, `Hull ${h.id} price out of range: ${h.price}`);
  assert.ok(h.crewOptimal >= 3 && h.crewOptimal <= 36, `Hull ${h.id} crewOptimal out of range`);
  assert.ok(h.crewMin >= 1 && h.crewMin <= h.crewOptimal && h.crewOptimal <= h.crewMax, `Hull ${h.id} crew bounds invalid`);
  assert.ok(h.size >= 12 && h.size <= 36, `Hull ${h.id} size out of range: ${h.size}`);
  assert.ok(h.fireRate > 0 && h.fireRate <= 5, `Hull ${h.id} fireRate invalid: ${h.fireRate}`);
  assert.ok(h.pumps > 0 && h.cargo > 0, `Hull ${h.id} pumps/cargo must be positive`);
  assert.ok(Number.isInteger(h.tier) && h.tier >= 1 && h.tier <= 4, `Hull ${h.id} tier invalid: ${h.tier}`);
  assert.ok(allowedWeapons.has(h.weapon), `Hull ${h.id} invalid weapon: ${h.weapon}`);
  assert.ok(h.description && h.description.length > 10);
}

assert.equal(roleCounts.size, 8, 'Must span 8 distinct combat roles');
for (const [role, count] of roleCounts.entries()) {
  assert.equal(count, 3, `Role ${role} must have 3 tier variants`);
}

const prices = BrassData.HULLS.map((h) => h.price);
const minPrice = Math.min(...prices);
const maxPrice = Math.max(...prices);
assert.ok(minPrice >= 600 && minPrice <= 1000, `Cheapest hull must be in 600..1000, got ${minPrice}`);
assert.equal(maxPrice, 24000, `Max tier price must be 24000, got ${maxPrice}`);

// 4. Islands and Ports geometry & reference validity
assert.ok(BrassData.ISLANDS.length >= 6, 'Should have archipelago islands');
const islandIds = new Set();
for (const isl of BrassData.ISLANDS) {
  assert.ok(isl.id && !islandIds.has(isl.id));
  islandIds.add(isl.id);
  assert.ok(isl.name && Array.isArray(isl.points) && isl.points.length >= 4);
  for (const [x, y] of isl.points) {
    assert.ok(Number.isFinite(x) && Number.isFinite(y));
    assert.ok(x >= 0 && x <= 2600 && y >= 0 && y <= 1800, `Island ${isl.id} vertex out of world bounds`);
  }
}

assert.ok(BrassData.PORTS.length === 9 || BrassData.PORTS.length === 10, 'Must have 9 or 10 ports');
const portIds = new Set();
const portById = new Map();
const allowedIndustries = new Set(['fishery', 'timber', 'foundry', 'refinery', 'shipyard', 'agriculture', 'trade']);

for (const p of BrassData.PORTS) {
  assert.ok(p.id && !portIds.has(p.id), `Duplicate or missing port id: ${p.id}`);
  portIds.add(p.id);
  portById.set(p.id, p);
  assert.ok(p.name && typeof p.name === 'string');
  assert.ok(factionIds.has(p.faction), `Port ${p.id} invalid faction ${p.faction}`);
  assert.ok(allowedIndustries.has(p.industry), `Port ${p.id} invalid industry ${p.industry}`);
  assert.ok(p.specialty && typeof p.specialty === 'string');
  assert.ok(p.description && typeof p.description === 'string');
  assert.ok(Number.isFinite(p.x) && p.x >= 180 && p.x <= 2420, `Port ${p.id} x out of bounds: ${p.x}`);
  assert.ok(Number.isFinite(p.y) && p.y >= 180 && p.y <= 1620, `Port ${p.id} y out of bounds: ${p.y}`);
  assert.ok(Number.isFinite(p.population) && p.population > 0);
  assert.ok(Number.isFinite(p.wealth) && p.wealth > 0 && p.wealth <= 100);

  if (Array.isArray(p.shipIds)) {
    for (const sid of p.shipIds) {
      assert.ok(hullIds.has(sid), `Port ${p.id} references unknown shipId ${sid}`);
    }
  }

  // Port must be ON WATER (outside every island polygon) and near an island shore
  let nearestShoreDist = Infinity;
  for (const isl of BrassData.ISLANDS) {
    assert.equal(
      pointInPolygon(p.x, p.y, isl.points),
      false,
      `Port ${p.id} (${p.x},${p.y}) lies inside island ${isl.id}`
    );
    for (let i = 0; i < isl.points.length; i++) {
      const [x1, y1] = isl.points[i];
      const [x2, y2] = isl.points[(i + 1) % isl.points.length];
      const d = distToSegment(p.x, p.y, x1, y1, x2, y2);
      assert.ok(d >= 15, `Port ${p.id} too close (${d.toFixed(1)}) to island ${isl.id} polygon edge`);
      if (d < nearestShoreDist) nearestShoreDist = d;
    }
  }
  assert.ok(nearestShoreDist <= 120, `Port ${p.id} should be near an island shoreline, got dist ${nearestShoreDist.toFixed(1)}`);
}

// 5. Routes validity, water navigability around islands, and full graph connectivity
assert.ok(Array.isArray(BrassData.ROUTES) && BrassData.ROUTES.length >= BrassData.PORTS.length);
const adj = new Map();
for (const pid of portIds) adj.set(pid, new Set());

for (const route of BrassData.ROUTES) {
  assert.ok(Array.isArray(route) && route.length === 2);
  const [a, b] = route;
  assert.notEqual(a, b, `Self-loop route on ${a}`);
  assert.ok(portIds.has(a), `Route references unknown port ${a}`);
  assert.ok(portIds.has(b), `Route references unknown port ${b}`);
  adj.get(a).add(b);
  adj.get(b).add(a);

  const pa = portById.get(a);
  const pb = portById.get(b);
  for (const isl of BrassData.ISLANDS) {
    assert.equal(
      segmentIntersectsPolygon(pa.x, pa.y, pb.x, pb.y, isl.points),
      false,
      `Route ${a} <-> ${b} intersects island ${isl.id}`
    );
    for (const [vx, vy] of isl.points) {
      const clearance = distToSegment(vx, vy, pa.x, pa.y, pb.x, pb.y);
      assert.ok(
        clearance >= 15,
        `Route ${a} <-> ${b} passes too close (${clearance.toFixed(1)}) to island ${isl.id}`
      );
    }
  }
}

const visited = new Set([BrassData.START.port]);
const queue = [BrassData.START.port];
while (queue.length > 0) {
  const cur = queue.shift();
  for (const nxt of adj.get(cur) || []) {
    if (!visited.has(nxt)) {
      visited.add(nxt);
      queue.push(nxt);
    }
  }
}
assert.equal(visited.size, BrassData.PORTS.length, 'Route graph must connect every port');

// 6. Missions check (8 sequential escalating missions)
assert.equal(BrassData.MISSIONS.length, 8, 'Must have 8 sequential story missions');
const missionIds = new Set();
const allowedKinds = new Set(['battle', 'delivery', 'bounty']);
const validGoods = new Set(['food', 'timber', 'steel', 'fuel', 'supplies', 'ammo', 'engines']);

let prevReward = 0;
for (let i = 0; i < BrassData.MISSIONS.length; i++) {
  const m = BrassData.MISSIONS[i];
  assert.ok(m.id && !missionIds.has(m.id));
  missionIds.add(m.id);
  assert.ok(m.title && typeof m.title === 'string');
  assert.ok(m.description && typeof m.description === 'string');
  assert.ok(allowedKinds.has(m.kind), `Invalid mission kind: ${m.kind}`);
  assert.ok(portIds.has(m.port), `Mission ${m.id} invalid source port ${m.port}`);
  assert.ok(portIds.has(m.targetPort), `Mission ${m.id} invalid targetPort ${m.targetPort}`);
  assert.notEqual(m.port, m.targetPort, `Mission ${m.id} source and target ports must differ`);
  assert.ok(adj.get(m.port).has(m.targetPort), `Mission ${m.id} ports ${m.port} -> ${m.targetPort} must be connected by a direct route`);
  if (i > 0) {
    assert.equal(m.port, BrassData.MISSIONS[i - 1].targetPort, `Mission ${m.id} should chain from previous mission targetPort`);
  }
  assert.ok(Array.isArray(m.enemyHulls) && m.enemyHulls.length >= 1);
  for (const eh of m.enemyHulls) {
    assert.ok(hullIds.has(eh), `Mission ${m.id} references unknown enemy hull ${eh}`);
  }
  assert.ok(Number.isFinite(m.reward) && m.reward > prevReward, `Mission ${m.id} reward must escalate`);
  prevReward = m.reward;
  assert.ok(Number.isFinite(m.renown) && m.renown > 0);
  if (m.kind === 'delivery' || m.cargo) {
    assert.ok(m.cargo && validGoods.has(m.cargo.good) && Number.isFinite(m.cargo.qty) && m.cargo.qty > 0);
  }
}

assert.equal(BrassData.MISSIONS[0].enemyHulls.length, 1, 'First mission must have 1 weak enemy hull');
assert.equal(BrassData.MISSIONS[7].enemyHulls.length, 3, 'Final mission must have flagship + 2 escorts');
const finalBossHull = BrassData.HULLS.find((h) => h.id === BrassData.MISSIONS[7].enemyHulls[0]);
assert.equal(finalBossHull.tier, 4, 'Final mission lead ship must be tier 4 flagship');

// 7. START check
const start = BrassData.START;
assert.ok(hullIds.has(start.hull), 'START.hull must be a valid hull id');
const startHull = BrassData.HULLS.find((h) => h.id === start.hull);
assert.equal(startHull.price, minPrice, 'START.hull must be the cheapest hull');
assert.equal(startHull.hp, 150);
assert.ok(startHull.damage >= 10 && startHull.damage <= 14);
assert.equal(startHull.range, 340);
assert.equal(startHull.fireRate, 2.2);
assert.equal(startHull.weapon, 'gun');
assert.equal(start.credits, 1800);
assert.ok(portIds.has(start.port), 'START.port must be a valid port id');
assert.equal(start.supplies, 20);
assert.equal(start.food, 30);
assert.equal(start.fuel, 60);
assert.equal(start.ammo, 80);
assert.equal(start.crew, 5);
assert.ok(start.crew >= startHull.crewMin && start.crew <= startHull.crewMax, 'START.crew must satisfy starting hull crew limits');
assert.ok(start.crew >= startHull.crewOptimal, 'START.crew should staff starting hull optimally');

console.log(`ALL CONTENT TESTS PASSED (${BrassData.HULLS.length} hulls, ${BrassData.PORTS.length} ports, ${BrassData.ISLANDS.length} islands, ${BrassData.ROUTES.length} water routes, ${BrassData.MISSIONS.length} missions).`);
