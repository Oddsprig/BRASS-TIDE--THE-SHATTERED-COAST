(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.BrassSystems = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  var CONSTANTS = Object.freeze({ inflowPerArea: 0.055, bailPerCrew: 1.65,
    pumpRate: 2.3, patchPerCrew: 1.8, patchSupplyPerArea: 0.018,
    hullRepairPerCrew: 0.22, hullSupplyPerHp: 0.35, portHullCost: 3,
    portWoundCost: 12, portPatchCost: 0.6, portSupplyCost: 5 });
  function finite(n, fallback) { return Number.isFinite(n) ? n : fallback; }
  function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, finite(n, lo))); }
  function sumAreas(s) { return s.breaches.reduce(function (v, b) { return v + Math.max(0, finite(b.area, 0)); }, 0); }
  function createShip(spec, overrides) {
    spec = spec || {}; overrides = overrides || {};
    var maxHp = Math.max(1, finite(spec.hp, 100));
    var min = Math.max(0, finite(spec.crewMin, 2));
    var optimal = Math.max(min, finite(spec.crewOptimal, 5));
    var max = Math.max(optimal, finite(spec.crewMax, optimal + 2));
    var s = { id: spec.id, type: spec.id, name: spec.name || 'Boat', spec: Object.assign({}, spec),
      maxHp: maxHp, hp: maxHp, armor: Math.max(0, finite(spec.armor, 0)), crew: optimal,
      crewMin: min, crewOptimal: optimal, crewMax: max, wounded: 0, water: 0,
      capacity: Math.max(200, maxHp * 4), breaches: [], fire: 0, engine: 1,
      supplies: 20, ammo: 80, fuel: 60, sunk: false, policy: 'balanced',
      x: 0, y: 0, angle: 0, vx: 0, vy: 0, cooldown: 0 };
    Object.assign(s, overrides);
    s.spec = Object.assign({}, spec); s.breaches = (s.breaches || []).map(function(b) { return Object.assign({}, b); });
    sanitize(s); return s;
  }
  function sanitize(s) {
    s.hp = clamp(s.hp, 0, s.maxHp); s.crew = clamp(s.crew, 0, s.crewMax);
    s.wounded = clamp(s.wounded, 0, s.crew); s.water = clamp(s.water, 0, s.capacity);
    s.fire = clamp(s.fire, 0, 100); s.engine = clamp(s.engine, 0, 1);
    ['supplies', 'ammo', 'fuel'].forEach(function(k) { s[k] = Math.max(0, finite(s[k], 0)); });
    s.breaches = s.breaches.filter(function(b) { b.area = Math.max(0, finite(b.area, 0)); return b.area > 0.001; });
    if (s.hp <= 0 || s.water >= s.capacity) s.sunk = true;
  }
  function setPolicy(s, policy) {
    if (['balanced', 'bail', 'repair', 'fight'].indexOf(policy) !== -1) s.policy = policy;
    return s.policy;
  }
  function getStatus(s) {
    var able = Math.max(0, s.crew - s.wounded), area = sumAreas(s);
    var inflow = area * CONSTANTS.inflowPerArea * (1 + s.water / s.capacity * 0.45);
    var active = s.water > 0 || area > 0;
    var damage = area > 0 || s.fire > 0 || (s.policy === 'repair' && s.hp < s.maxHp);
    var weights = { balanced: [0.5, 0.28, 0.22], bail: [0.15, 0.65, 0.2],
      repair: [0.15, 0.2, 0.65], fight: [0.85, 0.1, 0.05] }[s.policy] || [0.5, 0.28, 0.22];
    var bail = active ? able * weights[1] : 0;
    var repair = damage && (s.supplies > 0 || s.fire > 0) ? able * weights[2] : 0;
    var guns = able - bail - repair;
    var pump = s.fuel > 0 ? Math.max(0, finite(s.spec.pumps, 0)) * CONSTANTS.pumpRate * s.engine : 0;
    var speed = clamp(s.engine * (1 - 0.78 * s.water / s.capacity) *
      Math.min(1, able / Math.max(1, s.crewMin)), 0, 1);
    var gunNeed = Math.max(1, s.crewOptimal * 0.5);
    if (s.sunk) { inflow = 0; bail = 0; repair = 0; guns = 0; pump = 0; speed = 0; }
    return { inflow: inflow, bailing: active && !s.sunk ? bail * CONSTANTS.bailPerCrew + pump : 0,
      repair: area > 0 && s.supplies > 0 ? repair * CONSTANTS.patchPerCrew : 0,
      crewGuns: guns, crewBail: bail, crewRepair: repair, speedFactor: speed,
      weaponFactor: s.sunk ? 0 : clamp(guns / gunNeed, 0, 1) * (1 - s.fire * 0.004), events: [] };
  }
  function applyHit(s, hit, rng) {
    if (s.sunk) return [];
    rng = rng || Math.random; hit = hit || {};
    var events = [], kind = hit.kind || 'bullet', raw = Math.max(0, finite(hit.damage, 0));
    if (!raw) return events;
    var explosive = kind === 'torpedo', shell = kind === 'shell' || kind === 'ram';
    var armor = Math.max(0, s.armor - Math.max(0, finite(hit.penetration, 0)));
    var damage = Math.max(raw * 0.22, raw - armor * (explosive ? 0.3 : 0.8));
    s.hp -= damage; events.push('Hull hit: ' + damage.toFixed(1) + ' HP');
    var chance = explosive ? 1 : shell ? 0.72 : 0.3;
    if (rng() < chance) {
      var area = damage * (explosive ? 5 : shell ? 1.1 : 0.45);
      s.breaches.push({ area: area, section: hit.section || 'bow' });
      events.push('Breach: ' + area.toFixed(1) + ' cm²');
    }
    if (rng() < (hit.section === 'engine' ? 0.65 : explosive ? 0.4 : 0.09)) {
      s.engine -= Math.min(0.35, damage / s.maxHp * 0.7); events.push('Engine damaged');
    }
    if (rng() < (explosive ? 0.35 : kind === 'shell' ? 0.2 : 0.05)) {
      s.fire += Math.min(28, damage * 0.55); events.push('Fire aboard');
    }
    // A hit can wound at most one sailor; an already wounded sailor can be lost.
    if (rng() < Math.min(0.4, damage / s.maxHp * (explosive ? 1.8 : 0.65))) {
      if (s.wounded >= 1 && rng() < 0.18) { s.crew -= 1; s.wounded -= 1; events.push('One crew lost'); }
      else if (s.crew - s.wounded >= 1) { s.wounded += 1; events.push('One crew wounded'); }
    }
    sanitize(s); if (s.sunk) events.push('Ship sunk'); return events;
  }
  function tickShip(s, dt, options) {
    options = options || {}; dt = Math.max(0, finite(dt, 0));
    var events = [], totalIn = 0, totalBail = 0, totalRepair = 0, elapsed = 0;
    // Bound internal steps so results remain stable for occasional slow frames.
    while (dt > 0 && !s.sunk) {
      var h = Math.min(0.25, dt), t = getStatus(s), before = s.water;
      s.water = clamp(s.water + (t.inflow - t.bailing) * h, 0, s.capacity);
      totalIn += t.inflow * h; totalBail += Math.min(t.bailing * h, before + t.inflow * h);
      var patch = Math.min(sumAreas(s), t.repair * h, s.supplies / CONSTANTS.patchSupplyPerArea);
      var left = patch;
      s.breaches.forEach(function(b) { var amount = Math.min(b.area, left); b.area -= amount; left -= amount; });
      s.supplies -= patch * CONSTANTS.patchSupplyPerArea; totalRepair += patch;
      if (!s.breaches.some(function(b) { return b.area > 0.001; }) && s.policy === 'repair' && s.supplies > 0) {
        var hull = Math.min(s.maxHp - s.hp, t.crewRepair * CONSTANTS.hullRepairPerCrew * h,
          s.supplies / CONSTANTS.hullSupplyPerHp);
        s.hp += hull; s.supplies -= hull * CONSTANTS.hullSupplyPerHp;
      }
      if (s.fire > 0) {
        s.hp -= s.fire * 0.003 * h; s.engine -= s.fire * 0.000025 * h;
        s.fire = clamp(s.fire + (0.08 - t.crewRepair * 0.65) * h, 0, 100);
      }
      // Engine operation spends fuel, but no open-water automatic crew or HP recovery.
      if (s.fuel > 0 && (s.water > 0 || Math.abs(s.vx) + Math.abs(s.vy) > 1)) s.fuel -= 0.006 * h;
      s.cooldown = Math.max(0, finite(s.cooldown, 0) - h);
      sanitize(s); dt -= h; elapsed += h;
      if (s.sunk) events.push('Ship sunk');
    }
    var status = getStatus(s);
    if (elapsed) { status.inflow = totalIn / elapsed; status.bailing = totalBail / elapsed; status.repair = totalRepair / elapsed; }
    status.events = events; return status;
  }
  function repairAtPort(s, budget) {
    budget = Math.max(0, Math.floor(finite(budget, 0)));
    if (s.sunk) return { cost: 0, repaired: false, error: 'A sunk boat cannot be serviced.' };
    var cost = 0, changed = false;
    function service(missing, unitCost, apply) {
      var amount = Math.min(Math.max(0, missing), (budget - cost) / unitCost);
      if (amount > 0) { var charge = Math.min(budget - cost, Math.ceil(amount * unitCost - 1e-9)); cost += charge; apply(amount); changed = true; }
    }
    service(sumAreas(s), CONSTANTS.portPatchCost, function(amount) {
      s.breaches.forEach(function(b) { var n = Math.min(amount, b.area); b.area -= n; amount -= n; });
    });
    service(s.maxHp - s.hp, CONSTANTS.portHullCost, function(n) { s.hp += n; });
    service(s.wounded, CONSTANTS.portWoundCost, function(n) { s.wounded -= n; });
    service(1 - s.engine, 80, function(n) { s.engine += n; });
    service(s.fire, 0.5, function(n) { s.fire -= n; });
    service(s.water, 0.02, function(n) { s.water -= n; });
    service(20 - s.supplies, CONSTANTS.portSupplyCost, function(n) { s.supplies += n; });
    sanitize(s); return { cost: cost, repaired: changed };
  }
  return { CONSTANTS: CONSTANTS, constants: CONSTANTS, createShip: createShip, applyHit: applyHit,
    tickShip: tickShip, getStatus: getStatus, setPolicy: setPolicy, repairAtPort: repairAtPort,
    clamp: clamp, sumAreas: sumAreas };
});
