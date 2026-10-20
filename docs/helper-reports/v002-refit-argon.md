# Boat Refits Helper Report (`v0.002`)

## Files Created (Allowlist Only)
- `game/scripts/refit.gd`
- `game/tests/test_refit.gd`
- `docs/helper-reports/v002-refit.md`

No existing tracked files were modified or deleted.

## Public API (`res://scripts/refit.gd`, `extends RefCounted`)
Preloads only `Goods`, `Money`, `Deployment`, and `Construction` (no `Campaign`, `Battle`, `Harbor`, or `Economy` preloads).

- `static func catalog() -> Dictionary`
  Returns `{"weapons": Dictionary, "engines": Dictionary, "armor": Dictionary}` keyed by module ID, enriched with `id`, `name`, `slotKind`, `kind`/`family`, `size` (`1..3`), `sizeLabel` (`"Small" | "Medium" | "Large"`), `op`/`points`/`fittingPoints`, `dpDelta`, `materials`, `ordinaryLabor`, `expertLabor`, `workerDays`, `expertDays`, and `description`.
  - **Weapons (12 modules; 3 per family)**:
    - `gun` (`bullet`, `ammoCost: 1`): `gun_pintle` (size 1, 4 OP), `gun_rotary` (size 1, 6 OP), `gun_casemate` (size 2, 9 OP)
    - `cannon` (`shell`, `ammoCost: 1..2`): `cannon_pounder` (size 1, 5 OP), `cannon_turret` (size 2, 9 OP), `cannon_siege` (size 3, 15 OP)
    - `rocket` (`rocket`, `ammoCost: 1..2`): `rocket_rail` (size 1, 6 OP), `rocket_battery` (size 2, 10 OP), `rocket_salvo` (size 3, 15 OP)
    - `torpedo` (`torpedo`, `ammoCost: 1..2`): `torpedo_collar` (size 1, 6 OP), `torpedo_twin` (size 2, 10 OP), `torpedo_heavy` (size 3, 15 OP)
  - **Engines (4 modules: stock + 3 refit options)**:
    - `stock_engine` (size 1, 0 OP, 1.0x speed, 1.0x fuelBurn), `economy_diesel` (size 1, 2 OP, 0.93x/-4 speed, 0.75x fuelBurn, +0.6 pumps), `tuned_hydro` (size 1, 4 OP, 1.12x/+8 speed, 1.12x turn, 1.22x fuelBurn, +0.2 pumps), `overcharged_turbine` (size 2, 7 OP, 1.22x/+15 speed, 1.06x turn, 1.45x fuelBurn, +0.8 pumps)
  - **Armor (4 modules: stock + 3 refit options)**:
    - `stock_armor` (size 1, 0 OP, +0 armor, 1.0x HP, 1.0x speed), `light_strakes` (size 1, 2 OP, +2 armor, 1.08x/+18 HP, 0.96x speed), `riveted_belt` (size 2, 5 OP, +5 armor, 1.18x/+45 HP, 0.90x speed), `casemate_bulwark` (size 3, 9 OP, +9 armor, 1.30x/+85 HP, 0.82x speed)
- `static func hardpoints(spec: Dictionary) -> Array`
  Returns array of `{id, slot, index, label, size, sizeLabel, x, y, arc, angle}` (`id` is `"weapon:0"`, `"weapon:1"`, etc.; 2 mounts on small hulls `size <= 16`, 3 on medium `size <= 22.5`, 4 on capital hulls `size > 22.5`).
- `static func defaults(spec: Dictionary) -> Dictionary`
  Returns `{"weapons": Array, "engine": "stock_engine", "armor": "stock_armor"}` with `weapons[0]` mapped from `spec.weapon` (`gun_pintle`, `cannon_pounder`, `rocket_rail`, `torpedo_collar`) and extra weapon mounts set to `""`.
- `static func normalize(spec: Dictionary, loadout: Variant) -> Dictionary`
  Validates loadout structure, module IDs, mount/hull size limits, non-empty primary `weapon:0`, and fitting-point budget (`usedPoints <= maxPoints`). Rejects invalid/oversized/over-budget loadouts with `{ok: false, error, message, usedPoints, maxPoints}`; returns `{ok: true, weapons, engine, armor, loadout, usedPoints, maxPoints}` when valid.
- `static func effective_spec(base: Dictionary, loadout: Dictionary = {}) -> Dictionary`
  Returns full combat/campaign spec including `weaponMounts` (`{id, slot, index, label, name, kind, damage, fireRate, range, speed, ammoCost, x, y, arc, angle, size, mountSize}`), `deploymentPoints` (via `Deployment.cost`), `speed`, `turn`, `hp`, `armor`, `pumps`, `fuelBurn`, `usedPoints`, `maxPoints`, and `loadout`. Default fittings reproduce `base` performance and `Deployment.cost(base)` identically.
- `static func ensure(ship: Dictionary, base: Dictionary = {}) -> void`
  Idempotently initializes/updates `ship.baseSpec`, `ship.loadout`, `ship.refitLocker`, `ship.spec`, `ship.maxHp`, `ship.armor`, and `ship.weaponCooldowns`. Never heals hull damage (`ship.hp` is clamped to `[0.0, ship.maxHp]`), never refills stores, and never recruits crew. Safe on legacy `v0.001` saves.
- `static func quote(port: Dictionary, ship: Dictionary, slot: String, module_id: String) -> Dictionary`
  Returns `{ok, message, cost, materials, workerWages, expertWages, tax, businessIncome, workerDays, expertDays, newLoadout, newSpec, usedPoints, maxPoints, fromLocker, removedModule, lineItems}` without mutating `port` or `ship`.
- `static func install(state: Dictionary, port: Dictionary, ship: Dictionary, slot: String, module_id: String) -> Dictionary`
  Preflights on deep copies, verifies captain `coins`, harbor `stocks`, and shared yard ordinary/specialist workforce (`availableWorkers`, `availableSpecialists`, `_yardWorkersUsed`, `_yardSpecialistsUsed`), transfers exact integer coins (`cost == businessIncome + workerWages + expertWages + tax`) via `Money.move`, consumes physical stocks, tracks removed modules in `ship.refitLocker` (reinstalling locker parts bills labor/margin/tax with zero new materials and consumes the locker item without duplication), and applies `ensure`.

## Economic & Fitting Assumptions
- Anchored to `100` bronze coins per ordinary sailor/laborer day and `Goods.WAGES` (`shipwright` 125, `mechanic`/`gunsmith` 150, `foreman` 175, `engineer`/`master shipwright` 200).
- Local harbor buy prices are resolved from `Goods.cost(good)` and harbor scarcity/industry/specialty/blockade factors (or explicit `port.prices` overrides) without preloading `Economy`.
- Yard rigging overhead is `0.10` ordinary worker-days per ordinary fitting day; shipyard operating margin is `8%` (`Construction.MARGIN_RATE`); harbor refit duty is `5%` (`Construction.TAX_RATE`).
- Reinstalling an owned module from `ship.refitLocker` or unmounting a secondary weapon slot (`""`) consumes `0` physical materials and bills `0.65x` fitting/rigging labor, overhead, margin, and tax so removal/reinstallation is never free and never mints modules or coins.

## Tests Written (`game/tests/test_refit.gd`) — Unexecuted by Helper
Per team contract instructions ("Do not launch ANY Godot/test/game process (root serializes)... report unrun tests honestly"), **no Godot or test process was launched in this helper session**.
`game/tests/test_refit.gd` is ready for root to execute via:
`Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_refit.gd`
