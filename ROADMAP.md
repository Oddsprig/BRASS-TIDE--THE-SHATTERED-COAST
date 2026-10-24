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

Equipment core has 90 native checks and remains unused by live adapters. Records
and equipment panel are detached candidates awaiting native verification. These
are components,not completed0.031. Combined tactical203fc79 has focused actual
AI 2,462, mount 1,449, paid refit 352 passes;full behavior/performance remains open.

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
