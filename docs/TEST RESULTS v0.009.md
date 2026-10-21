# v0.009 source verification

All 26 native suites passed in isolated background/headless processes, serialized by tools/check_game.py. No owner save, desktop input or focus was used.

| Suite | Actual log result |
| --- | --- |
| damage | damage: all native tests passed |
| battle | battle: all native tests passed |
| navigation | navigation: direct, island detour, blocked targets, barriers, diagonal corners, shore connections, bounded finite graph, 10 ports and 19 routes passed |
| economy | ALL NATIVE ECONOMY TESTS PASSED (73591 checks in 1888 ms) |
| construction | CONSTRUCTION PASS: 2827 checks in 15 ms |
| fleet_economy | fleet cash: 1190 checks, 0 failures, 2671 ms |
| campaign_cash | campaign cash: 418 checks, 0 failures, 1297 ms |
| save_validation | save validation: 89 checks, 0 failures, 417ms |
| runtime | runtime: 120 checks, 0 failures, 1667ms; background/headless only |
| voyage | voyage: 67 checks, 0 failures, 7206ms; largest fleet15 |
| tactics | tactics: 114 checks, 0 failures |
| refit | refit: 348 checks, 0 failures |
| fleet_points | fleet points: 99 checks, 0 failures, 837ms |
| commander | commander: 24 checks, 0 failures; background only |
| autovoyage | voyage: 67 checks, 0 failures, 7535ms; largest fleet13 |
| laboratory | LABORATORY: 81 checks, 0 failures |
| combat_events | combat_events: 10131 checks, 0 failures |
| audio | AUDIO: 1233 checks, 0 failures; decoding/scheduling only, no audition |
| map_revision | map revision: 361 checks, 0 failures, 2333ms |
| mount_layout | mount_layout: 1483 checks, 0 failures |
| presentation | PRESENTATION: 611 checks, 0 failures |
| feedback | FEEDBACK: 3952 checks, 0 failures |
| expedition | expedition: 23 checks, 0 failures |
| campaign_logistics | campaign logistics: 16 checks, 0 failures |
| exploration | exploration: 270 checks, 0 failures |
| island_voyage | island voyage: 12 checks, 0 failures |

This report establishes source checks. Exact tagged export identity, native Windows startup/save/battle and file hashes are recorded separately in portable RELEASE.json. No human listening, subjective fun or GPU frame-pacing claim is made.
