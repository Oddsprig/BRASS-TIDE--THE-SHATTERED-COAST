# Damage model

`dist/systems.js` exposes `BrassSystems` in classic browser scripts and `module.exports` in Node. All contract methods are available; `CONSTANTS`, `constants`, `clamp`, and `sumAreas` are additional exports. No dependencies or rendering.

Water and capacity use liters; breaches use cm². Inflow and bailing telemetry use liters/second; repair uses cm²/second. Capacity is four liters per maximum hull HP (minimum 200). Breach flow increases with accumulated water. One able sailor bails 1.65 L/s; each powered pump removes 2.3 L/s scaled by engine health and requires fuel. Torpedo holes are roughly five times effective hit damage and can overwhelm a skiff over a battle. Hull damage can also sink a boat.

Crew means surviving crew including wounded. Able crew is crew minus wounded. Policies divide able crew between guns, bailing, and repair, using fractional labor so small boats remain playable. Inactive repair/bailing labor returns to guns. `getStatus` never mutates. `tickShip` internally substeps at 0.25 seconds, returning actual averaged flow/patch rates plus current crew allocations and performance factors. Sunk boats stop operating.

Repair consumes 0.018 supplies/cm² at 1.8 cm² per repair sailor per second. After holes close, repair policy restores 0.22 HP per sailor per second using 0.35 supplies/HP. Bailing consumes no supplies. Fire damages hull and engine and repair crew suppress it. Shots can wound at most one sailor; casualties require an already wounded sailor. There is no automatic crew recovery.

Port service incrementally patches, repairs hull, treats wounds, restores engine, extinguishes fire, drains water and replenishes supplies to 20. Every service costs credits and respects the integer budget. It cannot resurrect a sunk ship or replace dead crew. `repaired` is a boolean indicating any service. Existing ammunition/fuel are not replenished.

Validation: `node tests/systems.test.cjs` covers deterministic hits, flooding sink, policies, finite supplies, port budgets, read-only status and long simulation invariants.
