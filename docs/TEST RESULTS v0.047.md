# v0.047 focused verification

Source: `9cc0f35af3c1be3b9a764ce80696c8433b0bc5c5`. Job: `0d02c1e892234a778177b5554c85d60a`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| battle-commands | 57 | passed |
| battle-layout | 57 | passed |
| tactical-runtime-regression | 146 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **71.287seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

260 focused native checks/0 failures:57 command semantics,57 actual Control geometry/callbacks across1600x1000 and1280x800 including visible minimap,146 tactical runtime regressions. Export+three portable startups passed, whole batch71.287s including setup/cleanup. Native0d02c1e892234a778177b5554c85d60a. Root inspected actual exported stills aff259a4b41c4747b3d04b96f8859830 and09c0f04afc8a492cbf55ffd26cc9d891 at those sizes; minimap overlap from first review corrected. No motion/listening/playfeel/performance acceptance claim. v0.046 measured full300DP light4.605FPS/mixed17.084FPS remainsUNMET;051gateOPEN. Tested source9cc0f35af3c1be3b9a764ce80696c8433b0bc5c5; root4a4e55e has identical game tree.
