# Content Report (`BrassData` v1.0.0)

## What Changed
- `dist/content.js:1-978`: Implemented the dependency-free IIFE + CommonJS module exposing `globalThis.BrassData` and `module.exports`.
  - `dist/content.js:4-7`: Set `TITLE = 'BRASS TIDE'`, `SUBTITLE = 'THE SHATTER COAST'`, `VERSION = '1.0.0'`, and `WORLD = { width: 2600, height: 1800 }`.
  - `dist/content.js:9-38`: Defined 4 original factions (`compact`, `forge`, `reed`, `raiders`) with colors, descriptions, and doctrines.
  - `dist/content.js:42-607`: Authored 24 original buyable hulls across 8 combat roles (`skiff`, `cutter`, `raider`, `corvette`, `torpedo`, `gunboat`, `rocket`, `cruiser`) with 3 escalating variants each (`tier` 1..4). Starter hull `tin_skiff` (`dist/content.js:44-66`) costs 750 credits with 150 HP, 5 optimal crew, `'gun'` weapon, 12 damage, 340 range, and 2.2 fireRate; apex hull `maiden_dreadnought` (`dist/content.js:584-606`) costs 24,000 credits.
  - `dist/content.js:610-709`: Defined 8 archipelago island polygons (`isl_lantern` to `isl_shatter`) inside `2600x1800`.
  - `dist/content.js:712-844`: Placed 10 coastal ports (`brass_haven` to `shatter_spire`) within `x: 495..2225, y: 390..1280` spanning all 7 industries (`trade`, `fishery`, `timber`, `agriculture`, `foundry`, `shipyard`, `refinery`) with specialties and ship rosters.
  - `dist/content.js:847-867`: Defined 19 open-water routes connecting all 10 ports without intersecting island polygons.
  - `dist/content.js:870-954`: Created 8 sequential story missions (`mission_1_lantern_sweep` to `mission_8_shatter_throne`) mixing `battle`, `delivery`, and `bounty`, escalating from 1 weak skiff (`bilge_punt`) to the dreadnought flagship plus 2 escorts (`maiden_dreadnought`, `iron_bastion`, `wraith_rocket`).
  - `dist/content.js:956-965`: Defined `START` (`hull: 'tin_skiff'`, `credits: 1800`, `port: 'brass_haven'`, `supplies: 20`, `food: 30`, `fuel: 60`, `ammo: 80`, `crew: 5`).
- `tests/content.test.cjs:1-285`: Added Node assert suite checking reference validity, finite stat bounds, port/route polygon clearance, BFS connectivity, mission escalation, and `START` crew/hull rules.

## What Ran & Found
- Ran `node tests/content.test.cjs`: caught and fixed an initial route crossing `isl_fen` (`dist/content.js:674-685, 792-804`) and tightened `shatter_spire` shoreline distance (`dist/content.js:698-708, 831-843`).
- Re-ran `node tests/content.test.cjs`: exited 0 (`ALL CONTENT TESTS PASSED`).
