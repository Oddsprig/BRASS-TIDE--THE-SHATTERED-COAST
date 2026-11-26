# Brass Tide v0.121 — island coastlines

Island outlines now use curved headlands and irregular coves across the home chart, regional charts and practice battles. Shore shading follows those curves. Rendering, navigation and collision use the same physical land boundary.

Terrain is prepared and cached at load/encounter boundaries, with at most96vertices per accepted replacement ring. Existing water routes, harbors and saved voyages remain usable; canonical saved sector definitions and player progress are unchanged. Distant collision and firing-ray queries skip island-edge work when their bounds cannot overlap.

Water, crew, economy, fleet roles and combat timing retain their existing systems. No expensive water simulation was added.

The Windows release, desktop launcher and marketplace will be updated together after current actual-image review. Price remains$9.99. Game is in early development.

## Verification

Current native safety/contact checks:418passed,0failed. R14 met all12angle diagnostics, which do not replace actual visual review. The exported42boat/300DP-per-side sample failed peak simulation lag230.269ms against the unchanged200ms floor; seven other floors passed. R13 PASS and an interrupted R14 confirmation remain separately recorded. Current confirmation, media review, installation and public download readback are pending. No v0.121 release accepted yet.

Current coast-query repair: after two current R14 samples missed only the unchanged peak-lag floor, detailed-ring edge queries now reject strict radius-expanded segment-box misses before running their original distance/intersection kernels. The uncached legacy path keeps complete edge math, so the existing real contact/ray comparisons remain an independent parity check. Physical30Hz, display scheduling, elapsed debt, worker ownership and acceptance thresholds are unchanged. New bounded native/export/retail confirmation and actual-image review are required; no pass asserted yet.
