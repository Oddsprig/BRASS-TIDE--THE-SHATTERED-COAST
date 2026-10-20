# v0.003 source verification

All engine processes serialized, hidden/headless, no input/focus or owner-save access. Script errors fail even on exit0; each test has a60second owned-process timeout.

| Suite | Actual result |
|---|---|
| damage | PASS · damage: all native tests passed |
| battle | PASS · battle: all native tests passed |
| navigation | PASS · Completed without error |
| economy | PASS · ALL NATIVE ECONOMY TESTS PASSED (73591 checks in 1895 ms) |
| construction | PASS · CONSTRUCTION PASS: 2827 checks in 17 ms |
| fleet_economy | PASS · fleet cash: 1190 checks, 0 failures, 2625 ms |
| campaign_cash | PASS · campaign cash: 418 checks, 0 failures, 1199 ms |
| save_validation | PASS · save validation: 83 checks, 0 failures, 396ms |
| runtime | PASS · runtime: 120 checks, 0 failures, 1589ms; background/headless only |
| voyage | PASS · voyage: 67 checks, 0 failures, 4655ms; largest fleet10 |
| tactics | PASS · tactics: 114 checks, 0 failures |
| refit | PASS · refit: 347 checks, 0 failures |
| fleet_points | PASS · fleet points: 98 checks, 0 failures, 497ms |
| commander | PASS · commander: 24 checks, 0 failures; background only |
| autovoyage | PASS · voyage: 67 checks, 0 failures, 5251ms; largest fleet10 |
| laboratory | PASS · LABORATORY: 67 checks, 0 failures |

Laboratory67checks; exact BoatArt capture93checks/33panels and software inspection; four supplied MP3 takes decode silently. Commander return-to-career bug fixed without changing the prior tests.

Raw evidence:
- work/qa/v003-candidate/damage.log
- work/qa/v003-candidate/battle.log
- work/qa/v003-candidate/navigation.log
- work/qa/v003-candidate/economy.log
- work/qa/v003-candidate/construction.log
- work/qa/v003-candidate/fleet_economy.log
- work/qa/v003-candidate/campaign_cash.log
- work/qa/v003-candidate/save_validation.log
- work/qa/v003-candidate/runtime.log
- work/qa/v003-candidate/voyage.log
- work/qa/v003-candidate/tactics.log
- work/qa/v003-candidate/refit.log
- work/qa/v003-candidate/fleet_points.log
- work/qa/v003-corrected/commander.log
- work/qa/v003-candidate/autovoyage.log
- work/qa/v003-corrected/laboratory.log

Release export runs from an exact-tag clean separate worktree, rechecks native suites and tests the resulting Windows EXE for menu, campaign/save and battle. See RELEASE.json for completed export facts; this document does not infer completion from a plan. No rendered FPS or human listening claim.
