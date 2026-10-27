# v0.044 focused verification

Source: `4f76384a32f71b6b2ff7e8aa46f8c17572519f45`. Job: `f0a2cd30d9074ed59330de5c9f9138d7`.

| Phase | Checks | Result |
| --- | --- | --- |
| import | build/startup | passed |
| mount-layout-existing | 2158 | passed |
| export | build/startup | passed |
| portable-menu | build/startup | passed |
| portable-campaign | build/startup | passed |
| portable-battle | build/startup | passed |

Whole selected batch including setup: **51.783seconds**. Owned process cleanup verified. Background/headless/Dummy; shared machine-wide queue.

This covers the selected version scope and portable startup only. It does not establish full-game, rendered motion, listening or FPS acceptance. Earlier failed attempts remain in TestBridge.

All six focused groups pass:55movement/recovery+249weaponcommitment+30HUD+173practice+484existingrefit+2158existinglayout=3149 checks/0. The final batch runs2158checks/export/3starts;991 earlier passed checks are retained only after exact source-hash proof that all production code is unchanged and only named tests differ. Initial HUDfixture had one gun, corrected to realtwo-gunfit. Existinglayout expected24boats, corrected to existing36. Earlier failedwholebatches remain failed. Source4f76384a32f71b6b2ff7e8aa46f8c17572519f45. Actual exported private still f8941f17ff7849428ef863036a69f2c1 completed32.719s; Root inspected selectedreload/water/engine/repair text and ordinary fourboatbattle. No motion/audio/full-fleet FPS orqualityparity acceptance. 043performance targets remainOPEN.
