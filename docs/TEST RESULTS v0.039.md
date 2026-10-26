# v0.039 focused verification

Source: `ba0fbfe94a92c204aa40a2ba3d4189248b4c850a`. Job: `d458da03b8624b619400eb28c88a3448`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| hotpath039 | 46 | passed |
| performance039 | 48 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **38.687seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

Baseline48/0 job18e4659b; final94/0 jobd458da03. Exact workload/fixture/world hashes match. Paired mount query9096->5674us for256calls each. Battle median29068.5->27673.5us, P9557813->58612us; tail not improved. Recorded per-tick actor/fire/projectile/effect fields match. One bounded snapshot-factor reuse; no new cache or broad refactor. Headless capped sample, not sustained/GPU FPS.
