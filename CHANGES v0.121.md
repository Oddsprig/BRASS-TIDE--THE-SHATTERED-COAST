# Brass Tide v0.121 — island coastlines

Island outlines now use curved headlands and irregular coves across the home chart, regional charts and practice battles. Shore shading follows those curves. Rendering, navigation and collision use the same physical land boundary.

Terrain is prepared and cached at load/encounter boundaries, with at most96vertices per accepted replacement ring. Existing water routes, harbors and saved voyages remain usable; canonical saved sector definitions and player progress are unchanged. Distant collision and firing-ray queries skip island-edge work when their bounds cannot overlap.

Water, crew, economy, fleet roles and combat timing retain their existing systems. No expensive water simulation was added.

The Windows release, desktop launcher and marketplace will be updated together after current actual-image review. Price remains$9.99. Game is in early development.

## Verification

Current native safety/contact checks:418passed,0failed. R14 met all12angle diagnostics, which do not replace actual visual review. The exported42boat/300DP-per-side sample failed peak simulation lag230.269ms against the unchanged200ms floor; seven other floors passed. R13 PASS and an interrupted R14 confirmation remain separately recorded. Current confirmation, media review, installation and public download readback are pending. No v0.121 release accepted yet.

Current coast-query repair: after two current R14 samples missed only the unchanged peak-lag floor, detailed-ring edge queries now reject strict radius-expanded segment-box misses before running their original distance/intersection kernels. The uncached legacy path keeps complete edge math, so the existing real contact/ray comparisons remain an independent parity check. Physical30Hz, display scheduling, elapsed debt, worker ownership and acceptance thresholds are unchanged. New bounded native/export/retail confirmation and actual-image review are required; no pass asserted yet.

Current containment repair: cache a packed copy of the same immutable battle coastline and use native containment only in queries with contact/shot radius>=1world unit. Boundary-inclusive classification is covered by that existing positive distance buffer; uncached and zero/sub-unit queries keep the original predicate. Every possible edge contact still runs original distance/intersection math. Existing boundary/ray parity plus a2048-query native-versus-legacy grid and a non-gating query-time diagnostic verify this path. R15 still failed peak backlog325.514ms; new419-check/export/retail results pending. Worker/publication/rate/debt/RNG and thresholds stay unchanged.

Current cache ownership repair: packed coast accelerators now live in private top-level battle state, copied once into the authoritative worker and excluded by existing publication sanitization. Public island records, terrain JSON hashes and planner copies no longer carry the derived packed-ring cache. Original points, bounds, query/contact semantics and all worker/rate/debt/gates remain unchanged. A native snapshot contract checks this ownership boundary (420expected checks); actual performance remains unverified. R16 completed419/0 but failed worker rate/lag/end drift; accepted120 control is queued to distinguish environment and regression. No release accepted.
