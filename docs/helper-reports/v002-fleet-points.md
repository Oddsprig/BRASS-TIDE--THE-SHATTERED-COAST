# v0.002 fleet points / campaign-save integration — helper report

Helper: Opus 5.5 Medium via Google plan (Antigravity), as the owner asked. Worktree: `work/v002-fleet` (branch state at 5aa4dff plus uncommitted edits).
Scope: only the "Campaign/save integration" section of `briefs/V0.002 TEAM CONTRACT.md`.

## Execution status (please read first)

- **Nothing has been run.** I did not start Godot, any test, or the game. I did not commit, push, delete or install anything, and I started no other helpers.
- `game/scripts/deployment.gd` and `game/scripts/refit.gd` are not in this worktree. `campaign.gd`, `save_validation.gd` and the new test `preload` them by their contract paths, so **none of these files will parse until root copies in both modules.** I did not write stand-in or duplicate modules.
- No other check was run either: no syntax check, no import, no map regeneration.

## Files changed (allowlist only)

| File | Change |
|---|---|
| `game/scripts/campaign.gd` | Preloads Deployment/Refits. `MAX_FLEET` is now only a roster safety cap (= `SaveValidation.MAX_ROSTER` = 48). New: `fitted_spec`, `fit_boat`, `hull_points`, `fleet_points`, `fleet_limit`, `can_add_boat`, `points_refusal`, `refit_boat`, `canonical_npc_boat`. `new_game` and `add_boat` apply default fittings; `restore` rebuilds fitted stats. `apply_morale` scales the fitted design. Salvage and rescue no longer use the eight-boat cap. |
| `game/scripts/harbor.gd` | Buy, commission and collect check `core.can_add_boat(h)` instead of `MAX_FLEET`. A finished hull that is over the limit stays on the slip. |
| `game/scripts/save_validation.gd` | Preloads Refits (read-only use). Roster cap goes from 8 to `MAX_ROSTER`=48. Checks optional `loadout`, `refitLocker` and `baseSpec`, plus stored `spec.weaponMounts` shape. `maxHp` must match the canonical effective HP of the validated loadout, or the hull HP if there is no loadout. |
| `game/tests/test_fleet_points.gd` (new) | 7 test groups, described below. Not run. |
| `docs/helper-reports/v002-fleet-points.md` (new) | This report. |

## Contract APIs used (no invented alternatives)

`Deployment.LIMIT`, `Deployment.cost(ship_or_spec)`, `Deployment.total(fleet)`, `Deployment.split(fleet)` (test only). `Refits.catalog()`, `defaults(spec)`, `normalize(spec,loadout)`, `effective_spec(base,loadout)`, `ensure(ship,base)`, `install(state,port,ship,slot,module_id)`, `quote(...)` (test only).

Assumption about `Refits.normalize` on success: the contract only defines the failure shape (`{ok:false,error}`). On success I use `result.loadout` if it exists. Otherwise I use the result itself with `ok` and `error` removed. This is `SaveValidation._normalized_loadout`, and the test uses it too. Root should check this against Argon's real return value.

## Behaviour

- **Ownership limit:** `can_add_boat(spec)` is true when `fleet_points() + hull_points(spec) <= 300` and the roster is under the 48-boat safety cap. `hull_points` prices the hull with its *default* fitting, so the points counted after the boat is added match the check. `fleet_points()` is `Deployment.total` over all living owned boats, including mothballed ones.
- **Legacy over-cap rosters** are kept whole. They are never trimmed, mothballed or stranded. They just can't buy, commission, collect or salvage more. Battle deployment and reserves belong to Deployment/Battle.
- **Rescue:** the old rule reused `fleet[0]` only when 8 boats were owned. Now it re-crews an owned living hull whenever one exists, and buys only when the fleet is empty. This follows "never strand living boats", avoids an extra loan, and keeps the existing cash and campaign rescue fixtures intact.
- **Fittings:** `fit_boat` rebuilds `baseSpec` from world data, calls `Refits.ensure`, sets `spec = effective_spec(canonical base, loadout)`, sets `maxHp` and `armor` from it, and clamps `hp` to `maxHp` without healing. Only `add_boat`/`new_game` (newly built hulls) start at full fitted HP. Stores, crew and coins are untouched.
- **Restore:** validation runs before any mutation, as before. Then every player boat goes through `fit_boat`, so serialized `spec`, `baseSpec`, `armor` and `deploymentPoints` are not trusted. NPC boats get `spec`, `maxHp` and `armor` rebuilt from the hull, re-scaled by their saved `economyFactor`. `economyBase*` keys are only rewritten if already present, so existing save round-trip key comparisons still match.
- **`refit_boat(uid,slot,module)`** checks the boat exists and isn't sunk, and that it is docked (`current_port()` non-empty and no course set). Then it calls `Refits.install`. On failure it returns `{ok:false}` and leaves no mutation or log entry of its own; atomicity of the install itself is Refit's contract. On success it re-canonicalizes the boat, re-applies morale, logs the result and checks coin conservation.
- **Morale** now also scales `weaponMounts[i].fireRate`, so fitted boats feel morale the same way the old single weapon did.

## Tests written (`game/tests/test_fleet_points.gd`, NOT run)

1. API and starter boat: limit 300, safety cap ≥ 38, starter has `baseSpec`/`loadout`, its fitted stats match the canonical base, default weapon matches the hull.
2. More than 8 of the cheapest hull fit within 300, the next one is refused, no coins move, a large legal roster validates and restores.
3. Over the limit: buy, commission, salvage and collect are all refused with **no state change** (deep compare), and the refusal message mentions deployment points.
4. A legacy v0.001-style save (8 boats, over 300 DP, no refit fields) validates and restores. Every boat keeps uid, damage, stores, crew and status, and gets a default fitting. No coins are created, the roster stays over cap and can't buy, and `Deployment.split` keeps every boat in deployment or reserve.
5. Fitted round-trip with a tampered save (`spec.damage`/`range`/`speed`/`armor`, `armor`, `baseSpec.hp`, `deploymentPoints`): stats are rebuilt from the loadout, damage isn't healed, stores aren't refilled, DP is unchanged. An inflated `maxHp` is rejected with the live voyage untouched.
6. Invalid modules: unknown armor, engine or weapon, a non-dictionary loadout, an unknown or malformed locker, or a malformed `baseSpec` are each rejected by validation and by restore, with input and live state unchanged. Unknown module, slot or boat in `refit_boat` causes no mutation.
7. Atomicity: a refit away from harbor is refused with no change. A broke captain (coins moved to harbor cash, total conserved) can't install, and nothing changes. A positive install runs **only if** the start harbor can supply it; otherwise it prints a skip line and asserts nothing. That path is weaker by design.

`tools/check_game.py` builds test paths as `res://tests/test_{suite}.gd`. Root must add `fleet_points` to its suite list (tools are outside my allowlist).

## Notes for root (outside my allowlist)

- `game/scripts/interface.gd:665` disables the salvage button with `fleet.size() >= core.MAX_FLEET`. It should use `core.can_add_boat(core.hull(state.recoverable.hull))` and could show `core.points_refusal(...)`.
- `game/tests/test_voyage.gd` uses `core.MAX_FLEET` in its expansion logic. With the 48 safety cap it never sells to make room. Purchases over the point limit just fail and it moves on. Its "flotilla grows" check should still hold, but the voyage may grow past 8 boats.
- `game/tests/test_campaign.gd:329` ("Rescue never exceeds eight-hull cap") and `test_campaign_cash.gd:263` should still pass under the new rescue rule (re-crew an existing hull). `test_campaign.gd` is listed in HANDOFF as a historical prototype.
- Open question: refits that raise a boat's DP are **not** blocked by the 300 ownership limit, because the contract limits acquisitions only. Battle deployment still enforces 300 per side. Root decides whether refits should be blocked too.
- `refit_boat` relies on `Refits.install` keeping the contract's "commit only on success" guarantee. Test 7 checks that through the campaign.
- Locker format isn't fixed by the contract. Validation accepts an array of module IDs, an array of `{id, count?}`, or `{id: count}`. All IDs must be in `Refits.catalog()`, with at most 256 entries.

## Late observation

At the end of the task an untracked `game/scripts/deployment.gd` showed up in this worktree. I did not create or edit it; presumably root or the Combat helper placed it. I read it: `LIMIT=300`, `cost`, `total`, `fits` and `split` match the calls above. Its `cost()` trusts `spec.deploymentPoints` when present, so the restore-time spec rebuild matters, and test 5 covers it. With its formula, tin_skiff costs 15 DP (20 fit within 300) and the dearest hull is capped at 75 DP, so the legacy fixture is about 540 DP. These are hand calculations, not test runs. `refit.gd` is still absent.
