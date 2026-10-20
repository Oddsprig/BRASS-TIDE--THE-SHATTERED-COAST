# Native Economy Volunteer Pool Report (`v0.001`)

## What Changed
- `game/scripts/economy.gd`:
  - `DEFAULT_RECRUIT_POOL_RATE = 0.06`, `DAILY_VOLUNTEER_RATE = 0.01` (`L29-L30`), and `default_recruit_pool(workforce)` (`L78-L79`): Set initial default volunteer recruit pool to `min(workforce, ceili(workforce * 0.06))` when `workforce > 0` (removing the old 42 cap while preserving explicit `recruits` fixtures in `create_port` at `L233-L237`).
  - `tick_ports` (`L770-L782`, `L1126-L1154`): Added daily volunteer replenishment from existing idle civilians at rate `workforce * 0.01 / day` with accumulated fractional remainder (`recruitRemainder`), bounded by `min(workforce, availableWorkers, ceili(workforce * 0.06))`. Updates willingness pool only (`recruits`, `recruitRemainder`), never modifying authoritative `workforce`, cash purses, or goods.
- `game/tests/test_economy.gd`:
  - `_test_create_port_and_coin_seeding` (`L98-L104`): Verified `min(workforce, ceili(workforce * 0.06))` default pool scaling (>1000 workforce -> 63) and explicit `recruits` fixture preservation.
  - `_test_recruit_scarcity_and_purses` (`L360-L434`): Verified pool recovery from zero with fractional remainder accumulation, constant authoritative `workforce`, bounds when no idle workers (`availableWorkers == 0`), partial idle workers (`availableWorkers < target`), or zero workforce (`workforce == 0`), and exact coin invariance.
- `docs/helper-reports/economy-volunteers.md`: Saved this report while preserving prior reports untouched.

## What Ran & What Was Found
- Executed `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_economy.gd`:
  - `ALL NATIVE ECONOMY TESTS PASSED (73589 checks in 1911 ms)`, exit code 0, with exact 365-day global bronze coin conservation (`diff == 0`).
