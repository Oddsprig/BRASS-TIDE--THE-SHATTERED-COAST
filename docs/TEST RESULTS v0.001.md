# v0.001 verification — 20 October 2026

All testing after the owner's background-only instruction uses sequential headless Godot processes. No foreground window, focus, mouse or keyboard control is used. The small checked-in runner limits each process to 60 seconds and rejects logged script errors even if Godot returns exit 0.

| Current native suite | Result | Coverage |
|---|---|---|
| damage | Pass | Hull/holes/flooding, pumps/bailing, finite kits, crew policies, fire/wounds/sinking |
| battle | Pass | Fixed-step combat, manual flagship cooldown, swept shots/terrain, orders/retreat, actual NPC stores |
| navigation | Pass | Direct/detour/blocked routes, shore connectors, bounded graph, 10 ports and 19 shipping routes |
| economy | 73,591 checks | Paid input chains, purses, stock, recruitment, whole coins and exact 365-day conservation |
| construction | 2,827 checks | All 24 physical bills/builds, whole engines/guns, supervision, escrow, simultaneous total/specialist limits |
| fleet economy | 1,190 checks | Actual owner/crew accounts, paid stores/repairs, trade, morale, fixed workforce and 365-day integration |
| cash campaign | 418 checks | Real hull/crew/repair/salvage/loan/contract transfers, construction, 100 days, shared workers and atomic saves |
| save validation | 83 checks | Actual JSON saves, damaged boats and funded contracts; malformed types/coins/IDs/geometry rejected without mutation |
| runtime | 120 checks | Actual Main scene, current harbor/finance screens, pending-worker transactions, opening fight, save/load, replay and sampled NPC water courses |
| voyage | 66 checks | All eight real battles/routes using earned money, purchased supplies, actual recruits, salvage and hull upgrades |

The eight-contract automated voyage starts with the inherited skiff and five sailors, grows to eight hulls, and wins the finale with five boats surviving. It does not mint money, inject crew/stock, force campaign combat results or bypass the actual battle simulation. Random contacts are avoided through the same course/grace option available in the game. Combat uses a deterministic programmatic captain, not desktop automation or a human playtest. Some boats sink; progression is tested with actual losses.

The runtime UI transition test uses a fixed combat seed and predictive aiming, so its pass does not depend on the wall clock. Quick-battle result-screen isolation has its own explicit forced-result fixture; that fixture is not used as evidence for campaign combat winnability. Financial protocol tests move existing treasury money and may prepare physical fixtures to isolate transactions; only the separate voyage suite demonstrates earned progression.

Every native suite takes less than four seconds on this machine. Raw local output is retained in the task's work/qa/final folder. Source import completed headless without script errors. Exported-executable startup, embedded icon and portable-save checks are recorded by tools/release_game.py in RELEASE.json and separate release logs when packaging completes.

Issues found and corrected include missing HUD fields during battle entry; snapshot publication after transactions; identical-order escrow undercounting; free rescue workers/hulls; invalid-save replacement; double-booked construction/repair workers; depleted recruit pools; and new captains overbuying full fuel tanks. A volunteer-test fixture incorrectly froze future employment; root separated volunteer updates from actual paid-job allocation instead of reporting unpaid people as employed. A mechanic fixture was updated to include the real specialists the service requires. See ROOT VERDICT in the preserved helper-report directory.

Prior graphical inspection, before the background-only constraint, covered the title/chart and an earlier harbor UI. It does not validate the final cash screens or battle visuals. Current foreground graphics, human feel and GPU frame pacing remain unmeasured; no FPS claim is made.

Separate rendering is the requested default. Godot reports that mode experimental. The prior graphical run produced an engine font-atlas error matching the confirmed [Godot issue122206](https://github.com/godotengine/godot/issues/122206) on Windows/Vulkan/RTX5090. Stable Rendering.vbs provides the documented per-launch Safe renderer fallback. The CLI modes were verified in the installed engine's help. Foreground re-testing is deferred under the owner's instruction.

Remaining play questions are in TO BE TESTED.md. This is a complete small v0.001 campaign, not a claim of commercial polish or exhaustive platform testing. Android is not a release target.
