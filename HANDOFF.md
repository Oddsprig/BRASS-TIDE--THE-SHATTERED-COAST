# Brass Tide v0.051 delivered

BRASS TIDE v0.051 - First voyage and threaded fleet combat
DELIVERED SCOPED WINDOWS BUILD
Source/tag: e9c499e / v0.051
Test Bridge: 3873d885a89f4747934a9fff2564d18c
5692 focused checks, 0 failures; menu/campaign/battle startup passed.
Selected batch plus setup: 83.810s; owned cleanup verified.

- Present a useful first voyage, operating reserves and the next fitting or fleet goal using the existing campaign.
- Correct four remaining bow assets while retaining all36boatdesigns and physical mounts.
- Run authoritative combat on an owned30Hz worker with100ms tactical choices, queued commands and independent interpolated rendering.
- Restore roughly60FPS in measured42boat/full300DP and16boat/mixed battles; reduce worker snapshot copying43->14ms light and24->7ms mixed.
- Preserve stores, numerical crew and repairs, original ship/port owners and event ordering; background checks stay below120s.

Later roadmap scopes remain separate. No full-game/rendered/audio acceptance claim.

Verification and remaining limits

The complete native/export batch passed 5,692 assertions with no failures,
including worker ownership/HUD, real flood and paid repair, damage behavior,
feedback, Windows export and menu/campaign/battle starts. It took 83.735 seconds
including setup and cleanup. An earlier identical attempt yielded to another
game; its interruption is preserved and is not counted as a passed batch.

The actual exported game ran 42 light boats and 16 mixed boats, with 300 points
per side, on the Core Ultra 9 / RTX 5090 Laptop GPU. Combat uses a 30 Hz worker;
Engine callbacks remain 60 Hz and drawing interpolates independently. Results:
- Light: 59.999 FPS; 99.72% of frames within 20 ms; snapshot median 14.443 ms.
- Mixed: 59.987 FPS; all frames within 20 ms; snapshot median 7.446 ms.
- Both: no frame above 50 ms, no unresolved planner stalls, full movement,
  firing, hits and relevant flooding/missile coverage. Both end PNGs reviewed.
- Main publication P95: 0.345 ms light / 0.189 ms mixed.

THE RAW AUTOMATED QUALITY FLAG REMAINS FALSE. Light worker capacity P95 was
38.435 ms against a 33.333 ms target; maximum lag was 151.409 ms against 100 ms.
Simultaneous impacts explain the largest peaks. The raw strict >=60 FPS check
also reports a miss for the measured values above. No threshold or receipt was
changed. Root accepts this useful, scoped v0.051 improvement and carries those
exact remaining performance targets into the v0.061 whole-game milestone.
This release does not claim full-game quality, recorded-motion, listening or
Starsector-equivalent acceptance.

Evidence: R69 retry 3873d885a89f4747934a9fff2564d18c, actual R36
470ecd2b7c8e40d7949cffcf71d80e53, tested release source 08a03ff51c2bee4c0b540305e4c9ff595eb8649a.
R68 command57, R66 goals851/fire123 and R67 hull205/weapon2292 are retained with
their unchanged dependencies; current damage451 and feedback5121 were rerun.
Root e9c499e has the same Git game tree as the tested release; all 705 files
match content after Windows newline normalization. Actual tested bytes remain
bound by the R69 plan. Later delivery records are metadata, not a new game build.


Continue with the next saved version scope after v0.051; preserve the shared lane and120-second limit.
