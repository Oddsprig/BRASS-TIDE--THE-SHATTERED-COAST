# Bronze-Cash Boat Construction Final Report (`v0.001`)

## Review Corrections Applied
- **Whole Installed Engine & Gun Assemblies (`game/scripts/construction.gd:95-192`)**: Removed fractional `engines` and `guns` lots. `blueprint(spec)` (`:113-271`) rounds propulsion (`engine_units`, `:149`) and ordnance (`weapon_units`, `:156`) upward via `ceili` (`>= 1` integer assembly). `tin_skiff` uses `1` engine (`17,265` cash) and `1` gun (`7,809` cash); larger hulls scale up to `4` engines and `8` weapon assemblies (`maiden_dreadnought`).
- **`Goods.WAGES.laborer` (`game/scripts/construction.gd:13-45, 194-205, 293-305, 412`)**: Yard laborers now use `"laborer"` (`100` cash/day in `Goods.WAGES`) instead of `"woodcutter"`.
- **Simultaneous Order Workforce & Specialist Reservation (`game/scripts/construction.gd:599-900`)**: `advance(port, order, days)` (`:671-900`) tracks per-day order reservations on `port` (`_sync_yard_step`, `:638-657`; `_record_yard_reservation`, `:660-668`), deducting `ordinary_worked / dt` from `workforce - workers - publicWorkers` and `expert_worked / dt` from `specialists` so simultaneous orders on the same port never double-use ordinary workers or specialists in a day.
- **Expanded Tests (`game/tests/test_construction.gd:1-372`)**: Added whole-integer `>= 1` assembly checks (`:52-53, 253-263`), `"laborer"` occupation checks (`:57-58`), and 5 simultaneous-order contention/sharing/conservation scenarios (`:265-353`).

## Starter Quote & Derivation (`tin_skiff`)
- **Geometry (`construction.gd:131-143`)**: `role="skiff", size=14` -> `6.20 m × 2.11 m` (`depth 0.87 m`, area `27.45 m²`).
- **Materials (`29,790` cash, `:145-192`)**: `1 engines` (`17,265`), `1 guns` (`7,809`), `4.81 timber` (`1,864`), `1.89 logs` (`378`), `1.59 iron` (`1,272`), `0.79 copper` (`435`), `1.69 supplies` (`435`), `1.02 fuel` (`332`).
- **Yard Labor (`ordinaryDays=26.14`, `laborCost=3,264` -> `householdPurse`, `:194-205`)**: `7.00 laborer` (`700`), `12.30 shipwright` (`1,538`), `4.64 mechanic` (`696`), `2.20 gunsmith` (`330`).
- **Supervision (`expertDays=7.22`, `supervisionCost=1,353` -> `expertPurse`, `:207-217`)**: `3.66 foreman` (`641`), `1.60 master shipwright` (`320`), `1.96 engineer` (`392`).
- **Totals (`:334-491`)**: `workerDays=33.36`, `estimatedDays=6.54`, `overhead=373` (`3.73` days), `margin=2,782` (8%), `tax=1,878` (5%) -> **`commissionPrice / total = 39,440` cash** (`escrow = 4,617`, `readyPrice = 40,317`).

## What Ran
- `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_construction.gd`: **PASS** (`2399 checks in 22 ms`, exit 0).
