# Bronze-Cash Boat Construction Review 2 Report (`v0.001`)

## Review 2 Fixes Applied
- **Total Idle Workforce Cap & Combined Reservation (`game/scripts/construction.gd:576-589, 629-640, 709-797`)**:
  - Treated `availableWorkers` (`workforce - workers - publicWorkers`) as TOTAL idle civilians with specialists/experts as a subset (`_available_total_workers`, `:576-589`).
  - Bounded `advance(port, order, days)` (`:643-876`) step fraction by `total_fraction_cap = (free_total * dt) / (ordinaryDays + expertDays)` alongside `ordinary_fraction_cap` and `expert_fraction_cap` (`:752-755`).
  - Reserved combined `(ordinary_worked + expert_worked) / dt` against total available workers (`_yardWorkersUsed` / `yardWorkersReserved`) and `expert_worked / dt` separately against specialists (`_yardSpecialistsUsed` / `yardSpecialistsReserved`, `:629-640, 791-797`).
- **`availableSpecialists` Priority (`game/scripts/construction.gd:592-608`)**:
  - `_available_specialists` (`:592-608`) now prioritizes `port.availableSpecialists` (bounded by `specialists - busySpecialists` when both exist) before falling back to total `specialists`, `supervisors`, `expertWorkers`, or `experts`.
- **Explicit `begin_day(port)` Reset API & Clean Port State (`game/scripts/construction.gd:611-626`)**:
  - Added static `begin_day(port)` (`:611-626`) to reset daily reservation counters (`_yardWorkersUsed`, `_yardOrdinaryUsed`, `_yardSpecialistsUsed`, `yardWorkersReserved`, `yardOrdinaryReserved`, `yardSpecialistsReserved`) once per port each day.
  - Removed `_sync_yard_step`, `_yardStepOrders`, and `_yardStepSig`; `port` stores only scalar numeric counters and never holds whole order dictionary references.
- **Updated & Expanded Headless Tests (`game/tests/test_construction.gd:1-434`)**:
  - Updated daily build loops to call `Construction.begin_day(port)` (`:104, 213, 406`).
  - Added assertions for `ordinaryWorked + expertWorked <= availableWorkers` across two simultaneous orders with abundant experts (`:272-315`), `availableSpecialists` priority over `specialists` (`:316-366`), explicit `begin_day(port)` reset behavior, and zero order/array/dictionary references in `port` (`:106, 368-390`).

## What Ran
- `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_construction.gd`: **PASS** (`2827 checks in 16 ms`, exit 0).
