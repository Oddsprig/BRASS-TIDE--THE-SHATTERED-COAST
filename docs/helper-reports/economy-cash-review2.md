# Native Bronze Cash Economy Review 2 Report (`v0.001`)

## What Changed
- `game/scripts/economy.gd:548-568`:
  - Updated `Economy.recruit` to compute both `recruits_avail` (`port.get("recruits", 0)`) and authoritative `cur_workforce` (`port["workforce"]` if present, otherwise `port.get("workers", 0)`), and require `q <= mini(recruits_avail, cur_workforce)` before any wallet, purse, recruit pool, or workforce mutation.
  - Prevents malformed or external recruit pools (`recruits > workforce` or `workforce == 0`) from hiring phantom crew, and guarantees that every accepted hire reduces `port["workforce"]` by the exact hired count `q`.
- `game/tests/test_economy.gd:324-351`:
  - Added regression assertions in `_test_recruit_scarcity_and_purses` verifying:
    - Atomic rejection with zero state mutation when `recruits > workforce` (`recruits = 8`, `workforce = 2`) and `q = 3 > min(recruits, workforce)`.
    - Successful hire when `q = 2 <= min(recruits, workforce)` with exact authoritative workforce delta (`wf_before_hire - int(port["workforce"]) == 2`), `workforce == 0`, `recruits == 0`, `workers == 0`, and exact total coin conservation.
    - Atomic rejection with zero state mutation when `workforce == 0` even if `recruits = 5 > 0`.
- Preserved `docs/helper-reports/economy-native.md`, `docs/helper-reports/economy-cash.md`, and `docs/helper-reports/economy-cash-final.md` unchanged.

## What Ran & What Was Found
- Ran `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_economy.gd`: **73,562 checks passed in 1,907 ms (1.9 s)**, exit 0, with exact 365-day global bronze coin conservation (`diff == 0`).
