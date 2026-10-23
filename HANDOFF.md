# Brass Tide: v0.028 delivered; AI and civilian roadmap amended

23 October 2026. Current task is planning only, expanded by the owner to require
deep campaign and battle AI, independent pirate/faction conflict, light-boat
encirclement/harassment, fishing/cargo/tanker progression and high-ranking yachts.
No new game build has been started. The minimum quality target the owner admires
in Starsector has not yet been demonstrated by this game.

Delivered game stays v0.028; exact game commit
`2b11d4d1af69b62a2f8436bcdee4a5675432bd98`. Current world has24 original hulls.
All completed .019-.028 builds/tags/archives and old saves/music remain preserved;
Desktop/game-launchers/Brass Tide.lnk continues to point at the verified .028.
Publication remains a separate receipt; no upload is part of this amendment.

Read ROADMAP.md, VERSION MAP.txt and:
- docs/FLEET CAMPAIGN VERSION MAP v0.029-v0.038.txt — ten sequential scopes/gates.
- docs/AI BEHAVIOR STANDARD v0.029-v0.038.txt — role/pack tactics, autonomous
  campaign decisions, observed knowledge, three-way hostility, exclusive ship
  encounter custody, near/distant calibration and concrete behavior matrix.
- docs/CIVILIAN FLEET PLAN v0.029-v0.038.txt — target 12 new original designs:
  3 fishing, 4 cargo through galleon-scale motor merchantman,2 tankers, 3 yachts.
  Real capacities, funded acquisition/work, vulnerable manifests, actual fuel
  transfer and guest/cohort accounting. Do not claim36 delivered hulls yet.

Sequence changes: .030 owns coordinated flank/encircle/harass and counters;
.033 owns independent NPC conflict and sighting-led lifecycle; .035 now delivers
civilian hulls, .036 working fishing/freight/refuelling/yacht/piracy traffic and
captain memory. .037 supplies a faction operation and .038 proves behavior,
six careers, tanker support and scale/performance. The previous two extra
expedition branches move after .038. Existing four stories/exploration remain.
A later explicit instruction is needed to implement any of these future builds.

One initial roadmap advisor (c74659fa4ebb) and one successful amendment advisor
(31552a21d757) used pinned gpt-6.1-sol via Codex/ChatGPT plan at Max. An intermediate
request returned missing context and supplied no accepted findings; its raw reply
is preserved in work/roadmap-ai-civilian. See docs/PLANNING REVIEW v0.029-v0.038.txt
for a separate lead verdict and unchanged raw reports in docs/planning/.
The current advisor reviewed the supplied contract, not repository code.

Before source work read maps/PROJECT MAP.txt, CODE MAP.md and targeted system
maps. Existing code is still game/ at BUILD28. .028 verification remains in its
native report/export/delivery receipts:66 suites and7 battle CPU fixtures. Those
results do not prove the new AI behavior, human audio quality or rendered FPS.

Finite coins/people/goods and physical hull/mount IDs remain canonical. Captured
or support-designated civilian boats must not evade real manifest risk. New
capacity creates no crew/guests/money. Shared catches cannot be harvested twice.
Large central scripts need focused modules/small integration hooks. Retain cheap
2D water, numerical crew, default autopilot, WASD and 300 DP. Copied-port workers
cap 8 on verified 24 logical processors, join before main-thread transactions/UI.
Rendering is Separate; profile before raising concurrency.

All tests remain hidden/background/silent and serialized, one engine at a time.
No mouse/keyboard/focus, global installs/settings, save overwrite or old-release
removal. No engines/gameplay tests were run for this planning task. Required
behavior cannot be marked delivered merely because tests exit0; future builds
need their own actual scenario, visual/motion, schema and Windows export evidence.
Prior planning texts are preserved losslessly under
`docs/history/2026-10-23 before AI civilian fleet planning/`.
