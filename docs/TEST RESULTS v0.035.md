# v0.035 focused verification

Source: `7c3bea4cbdb856d46fd6287924058c94b7fbb40d`. Job: `df31d4e06ab6490996696eb86430682e`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| civilian-roster035 | 372 | passed |
| civilian-art035 | 209 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **37.081seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

Exact native BoatArt draw primitives were rasterized with the existing CPU gallery tool and visually inspected. One observed stern-clipping defect was fixed in the shared civilian portrait/gallery span; all12 captured panels now pass12-pixel bounds. This is a software geometry preview, separate from foreground gameplay/audio acceptance.
