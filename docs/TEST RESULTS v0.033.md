# v0.033 focused verification

Source: `3b8be1dd8227866857dd2a7de4de35c5690965e9`. Job: `b0e766a7043b487f8ff0d4f66befdbbd`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| campaign-lifecycle033 | 55 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **37.373seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

Retained campaign-fleets033:99 checks/0 failures in TestBridge080685a3f4274776be23bcde5b399fb3. Production source hashes matched the final candidate; only the lifecycle fixture changed. The final batch runs the remaining lifecycle checks, export and portable startups.
