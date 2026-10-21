# v0.011 source verification

All 30 native suites passed in isolated background/headless processes, serialized by tools/check_game.py. No owner save, desktop input or focus was used.

| Suite | Actual log result |
| --- | --- |
| damage | damage: all native tests passed |
| battle | battle: all native tests passed |
| navigation | navigation: direct, island detour, blocked targets, barriers, diagonal corners, shore connections, bounded finite graph, 10 ports and 19 routes passed |
| economy | ALL NATIVE ECONOMY TESTS PASSED (73591 checks in 2074 ms) |
| construction | CONSTRUCTION PASS: 2827 checks in 15 ms |
| fleet_economy | fleet cash: 1190 checks, 0 failures, 2917 ms |
| campaign_cash | campaign cash: 418 checks, 0 failures, 1435 ms |
| save_validation | save validation: 89 checks, 0 failures, 456ms |
| runtime | runtime: 120 checks, 0 failures, 1845ms; background/headless only |
| voyage | voyage: 67 checks, 0 failures, 7849ms; largest fleet15 |
| tactics | tactics: 114 checks, 0 failures |
| refit | refit: 348 checks, 0 failures |
| fleet_points | fleet points: 99 checks, 0 failures, 879ms |
| commander | commander: 24 checks, 0 failures; background only |
| autovoyage | voyage: 67 checks, 0 failures, 7916ms; largest fleet13 |
| laboratory | LABORATORY: 81 checks, 0 failures |
| combat_events | combat_events: 10131 checks, 0 failures |
| audio | AUDIO: 1233 checks, 0 failures; decoding/scheduling only, no audition |
| map_revision | map revision: 361 checks, 0 failures, 2579ms |
| mount_layout | mount_layout: 1483 checks, 0 failures |
| presentation | PRESENTATION: 611 checks, 0 failures |
| feedback | FEEDBACK: 3952 checks, 0 failures |
| expedition | expedition: 23 checks, 0 failures |
| campaign_logistics | campaign logistics: 16 checks, 0 failures |
| exploration | exploration: 270 checks, 0 failures |
| island_voyage | island voyage: 12 checks, 0 failures |
| salvage | salvage: 70 checks, 0 failures |
| salvage_voyage | salvage voyage: 14 checks, 0 failures |
| voyage_jobs | voyage_jobs: 69 checks, 0 failures |
| voyage_flow | voyage flow: 12 checks, 0 failures |

This report establishes source checks. Exact tagged export identity, native Windows startup/save/battle and file hashes are recorded separately in portable RELEASE.json. No human listening, subjective fun or GPU frame-pacing claim is made.
