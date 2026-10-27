# v0.043 focused verification

Source: `5ea0d04496d0e9beec74144553e718dec7c4bd9d`. Job: `3d452a9050794653a415b1c041330257`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| damage-hotpath | 289 | passed |
| tactical-runtime | 93 | passed |
| draw-inputs | 37 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **58.004seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

Actual rendered baseline/final: light3.749 ->4.330FPS; mixed16.903 ->28.686FPS at full300DP/side. All performance targets remain UNMET;42boatlightcase is unacceptable. Final rendered jobec34adcba0674f2b89667ff76c0df597 completed57.516s with active coverage and cleanup. This is a bounded measured-fix release; smoothness and milestone0.051 remain OPEN. See PERFORMANCE v0.043.txt.
