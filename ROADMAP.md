# Active stage: finish tactical verification and build v0.031

The owner restored development and testing with Sol6.1Max,Grok4.7 and
Gemini4ArgonHigh through Bridge. Root coordinates/reviews/integrates; helpers
perform most implementation. No extra/nested helper or provider substitution.

The preserved v0.030 portable is its original untested build. Verified0.029
remains available. Runtime corrections will ship with0.031 after verification;
existing releases/tags and owner saves/music are preserved.

Current work:
- Finish actual light-boat passes,escort protection,retreat and strict orders;
  mixed guns/rockets/torpedoes use independently checked mount arcs/targets.
- Diagnose observed actor-screen and early40-hull fire failures. Complete
  regression,motion/heldout,larger-fleet CPU and Windows gates. Retain failures.
- Connect exact physical equipment condition to actual guns,engines,pumps and
  armor;crew repairs share finite labor and consume actual supplies.
- Preserve damaged item IDs/condition through paid fitting,harbor repair,
  saved voyages,capture,wrecks and recovery. No healing by refit or cloning.
- Show clear part status/repair priorities and real material/labor/coin bills.
  Crew stay numerical;rendering/assets use existing shared physical sockets.

BRASS TIDE - VERIFIED WORKING INTEGRATION; RELEASE STILL OPEN
2026-10-25T13:16:29.916626+00:00
Main checkpoint3946a9bc; current runtime/test GDScript matches frozenR4.
Fourteen runtime modules and six fixtures integrated. Still24 boats.
Preserved .030/tag7492fb7 is UNTESTED; verified .029/44e2a46 is available.
No .031 version bump, release tag, export, launcher change or upload.

COMBINED GAME FLOW VERIFIED
Lab99/0, equipment voyage67/0, salvage voyage14/0. Full Main UI167/0, save89/0,
player repairs204/0, NPC repairs140/0 and coin accounting458/0 also pass.
Root independently checked exact source/import/external/tool/engine hashes,
raw logs/reports, shared-lane completion and exited owned children. Condition,
part identity, finite crew supplies, paid labor and custody survive the voyage.
ROOT COMBINED R4 GATES VERIFIED.json and ROOT SCENE VOYAGES VERIFIED.json bind
actual jobs; MAIN EQUIPMENT INTEGRATION CANDIDATE.json lists copied file hashes.

PERFORMANCE IS NOT ACCEPTED
Canonical40 retry b144fdc5 completed only88/150 warmup updates within40s work
bound:40.594s update time, about461.3ms per warmup update. All40 remained afloat;
no measured windows or1800-profile samples were produced. This is incomplete
capacity, not stable FPS/quantiles. Root proof: ROOT CANONICAL40 PARTIAL VERIFIED.
Native scope was headless CPU; no idle-host, render or Starsector-parity claim.
Source-only cost diagnostics are next; do not repeat the unchanged capacity run.

PRESERVED FAILURES AND LESSONS
Lab99/1 snapshot preceded constructor price initialization; corrected setup
retains all99 original assertions and passes. Extra legacy campaign619/17 assumes
new careers are unseeded; its explicit old-save setup is being corrected in an
isolated fixture. It is separate from actual save89/0. Player-service2dc8 ended
incomplete, then unchanged controlled retry108a passed204/0. Coins535e attempt001
yielded correctly to another game; attempt002 passed458/0. Capacity708 failed
supervisor owned.json.tmp rename (WinError5); its result is distinct from b144.
All original artifacts and old source bytes remain preserved.

NEXT GATES AND OWNERS
Profile and improve canonical fleet CPU cost; finish remaining .030 regression,
held-out behavior, motion/listening and clean Windows release proof. .032 convoy
extraction and material-derived loose equipment cargo weight are isolated source
work, not delivered features. Other .032-.038 stages remain sequential.
Root owns Main/integration/notes. Same three Bridge helpers: QA Sol6.1MAX is sole
native submitter; Grok4.7 and ArgonHIGH own isolated code. Tests use shared FIFO,
hidden/headless/Dummy/BelowNormal and synthetic profiles; queue behind existing
Godot/Unity apps and leases. Never take input/focus or control another app.
Owner saves, music, previous releases and desktop launcher are preserved.


All tests stay silent/headless,lowpriority,isolated and serialized. No taking
mouse/keyboard/focus,foreground game or unrelated process control. Keep scenes,
UI and publishing on main;worker tasks own copies and join before publishing.
The owner's24-thread machine already uses Separate rendering and bounded economy
workers;change concurrency only with actual measurements.

After clean0.031 source/tag/Windows proof,continue0.032–0.038 one on top of the
other. VERSION MAP.txt has current stages; detailed AI/civilian plans remain in
docs/. Twelve extra civilian hulls and six complete careers remain future work.
Earlier roadmap text is preserved unchanged in docs/roadmap/. No remote upload
is proved;no false complete-game,visual/audio-quality or Starsector-parity claim.
