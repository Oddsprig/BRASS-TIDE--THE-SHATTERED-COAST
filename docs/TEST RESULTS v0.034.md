# v0.034 focused verification

Source: `a38c972ad9ad38088d64da307ac41d4db21fd748`. Job: `8d8c9384f1244baba94fa0c2a50688a5`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| coastal-encounters034 | 56 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **37.275seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

Retained coastal-navigation034:58 checks/0 failures in TestBridge d967fda5362149cfa2bc4aa49a148a8e; all9 starting NPC courses usable. Production source hashes matched the final candidate; only the coastal encounter fixture changed. The final batch runs that remaining fixture, export and portable startups.
