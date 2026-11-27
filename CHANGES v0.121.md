# Brass Tide v0.121 - island coastlines

Island coasts now have rounded headlands and irregular coves across campaign, regional and battle maps. Shore shading follows the curves. Rendering, navigation and collision share the same physical land boundary.

Terrain is prepared once and cached. Existing navigable water, berths, saved voyages, coins, crews and progression remain usable. Detailed battle-coast queries use conservative bounds and buffered native containment with the original distance/intersection tests retained. No expensive water simulation or battle-rate reduction was added.

The Windows build, desktop launchers and marketplace screenshots/download now match v0.121. Price remains$9.99. Game is in early development.

## Verification

323 native checks, 0 failures. Actual exported42-boat/300DP-per-side sample at1920x1200: 60.014FPS, p95 17.887ms, p99 21.634ms, command 16.993ms, worker 29.799Hz, peak lag 169.155ms, end drift 80.485ms. Every unchanged release floor passed in a 24.047s batch on this PC; stricter raw diagnostics remain in the receipt.

Root and the independent reviewer viewed the actual coastlines, distinct gallery and complete desktop store page. A clean final capture and full protected ZIP readback passed. Historical failed/interrupted attempts remain separate. This is a bounded update on the tested PC, not competitor-parity or universal-hardware certification.
