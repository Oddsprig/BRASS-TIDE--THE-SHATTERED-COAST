# v0.037 focused verification

Source: `b022ef79ae6eaec4a48f262c4ef958c830ff2182`. Job: `a663fd9c59684a70859ecceb2ebb3f69`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| operation-flow037 | 29 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **37.374seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

Retained supplied-operations037:27 checks/0 failures from1417a871480a4501a3d3936cb383e49c. Production hashes match; only flow fixture setup changed to pay crew and purchase actual food, and respect zero public grant without a threat. Final batch covers remaining flow, export and three startups. Earlier failed fixture preserved. The second failed fixture also assumed crew purses must increase despite ration purchases; the final assertion permits actual food spending while checking payroll and coin conservation. Production remains unchanged.
