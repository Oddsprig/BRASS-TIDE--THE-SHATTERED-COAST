# Brass Tide v0.121 — island coastlines

Island outlines now use curved headlands and irregular coves across the home chart, regional charts and practice battles. Shore shading follows those curves. Rendering, navigation and collision use the same physical land boundary.

Terrain is prepared and cached at load/encounter boundaries, with at most96vertices per accepted replacement ring. Existing water routes, harbors and saved voyages remain usable; canonical saved sector definitions and player progress are unchanged. Distant collision and firing-ray queries skip island-edge work when their bounds cannot overlap.

Water, crew, economy, fleet roles and combat timing retain their existing systems. No expensive water simulation was added.

The Windows release, desktop launcher and marketplace will be updated together after current actual-image review. Price remains$9.99. Game is in early development.

## Verification

Current native safety/contact checks:418passed,0failed. The actual42boat/300DP-per-side NORMAL-priority exported sample passed the unchanged frame, command, worker and simulation-backlog floors. Twelve angle scores are retained as art diagnostics (three unmet); actual screenshots and independent visual review determine appearance. Historical failed/cancelled runs remain recorded separately. Final current media, installation and public download readback are pending.

Current art follow-up: the local-normal cove version passed418hard checks and all retail floors at ordinary NORMAL owned-process priority, but the actual images still show inherited pointed horn caps. The final dense path therefore uses one native round-join erosion/expansion opening at6%breadth (max95world units), then bounded simplification and the SAME actual original-footprint clip/full-edge guards. This rounds at a visible spatial scale while preserving old water, area>=50% and96vertex cap. No threshold, boat, crew, economic or per-frame-generation change; new actual visual review remains mandatory.
