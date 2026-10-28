# Brass Tide v0.051 - First voyage and threaded fleet combat

- Clear first-voyage opportunity, operating reserves and next fleet/fitting goal.
- Four corrected bow assets, with all 36 designs and physical mounts retained.
- Worker-owned 30 Hz combat and 100 ms tactical decisions; queued commands and independently interpolated drawing.
- Measured 42-boat combat improved from roughly 22 to 60 FPS. Worker snapshots fell from 43 to 14 ms; mixed fleets from 24 to 7 ms.
- Current crew, flooding, paid repairs, weapon conditions and campaign accounting remain intact.

Native/export: 5,692 checks, zero failures; complete batch about 84 seconds.
Actual rendered test: about 58 seconds; full 300 points per side, active combat,
no frames above 50 ms or unresolved planner stalls.

Remaining strict targets are explicit: light worker P95 38.435 ms versus 33.333,
maximum lag 151.409 ms versus 100, and raw FPS values just below 60. The automated
quality flag remains false. This scoped release does not claim full-game,
recorded-motion, listening or Starsector-equivalent acceptance. Those measured
performance targets carry into v0.061; no threshold was changed.

See docs/TEST RESULTS v0.051.md and tests/ for receipts and exact source binding.
