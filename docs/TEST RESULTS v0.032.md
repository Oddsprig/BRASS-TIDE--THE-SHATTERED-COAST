# v0.032 focused verification

Source: `1ac7789546f649a38701c54e201ccbdc35df33a9`. Job: `d08ed9fe34464bf9ae5c4625b31aa5ba`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| convoy-objectives | 57 | passed |
| convoy-recovery-voyage | 62 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **44.135seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.
