# v0.036 focused verification

Source: `0b8e36c2a91105c193d6e6bab8953ec99ed8e230`. Job: `a3fbf931f934431cb57eeb4d5d4893b8`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| civilian-flow036 | 68 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **40.400seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

Retained civilian-work036:63 checks/0 failures from3aab39798eb44644b6ed1825950de1f2. Production source hashes match; only flow fixture contact ordering comparison changed. Earlier import-name collision and two fixture representation/order failures are preserved; final batch runs remaining flow, export and portable startups.
