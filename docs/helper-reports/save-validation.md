# Save preflight validation — awaiting test slot

Added only `game/scripts/save_validation.gd`, `game/tests/test_save_validation.gd` and this report. No Godot or tests launched: root explicitly reserved the single engine instance for other checks.

Pure static `validate(saved,world)` returns `{ok,message}` and never mutates inputs. Call before Campaign.restore invokes Money.total or new_game. It validates container types before indexing, exact original harbor IDs/no duplicates, four integer coin purses and16finite stock keys, yard orders/escrow, player purses/liabilities, cargo, known hulls/unique player uids/crew and hull bounds, finite geometry, NPC boats/purses/cargo/routes, funded contract sponsor/escrow and campaign collections. Integer-valued JSON floats are accepted. Unknown extra fields are allowed. Finite boat stores may exceed refilling targets; sparse story-owner cargo and missing NPC uid are valid. Unsafe coin magnitudes beyond exact JSON integer range are refused before integer conversion.

Tests use actual Campaign.new_game serialized JSON, a genuinely damaged boat, actual construction-order schema and a funded contract. Malformations include null/string harbor elements or purses, fractional/overflow coins, missing/NaN stocks, NaN/infinite geometry, duplicate harbor/boat/owner IDs, unknown hulls, invalid crew/HP/flood bounds, negative stores, null breaches/orders/NPC boats and malformed sponsor/escrow. Every case checks useful rejection and input preservation; NaN-aware recursive comparison avoids false mutation failures.

Status: files written and statically reviewed only; no execution pass claimed. Root wires live-restore atomicity separately and will independently run or grant the headless test slot. No unowned edits, deletion or commits.
