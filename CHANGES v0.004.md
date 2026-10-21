# Brass Tide v0.004

20 October2026 · cumulative Windows PC release

- All-team typed firing/hit/miss/engine/sink events feed position-aware recorded sound; bounded queues and consume-once IDs.
- Real CC0 weapon/impact/water recording cuts replace synthesized gun pings, with source/credit/hash manifest.
- Distinct short muzzle flashes, cannon impact splinters, rocket ignition/trails and torpedo water columns; sinking animation and wreck detail.
- Prioritized bounded spatial voice pool, variations and separate weapon/ambience controls.
- Replaced oversized bar/disc guns with physical-sized receiver/breech/recoil models, shaded barrels, rocket tubes and torpedo cradles; equipment is separate from hull rendering.

Verified source checks: 18 native suites, serialized/background only. Exact geometry audit:6466029 polygons across24hulls,360headings,threeLODs and stationary/moving cases; zero invalid. Headless actual battle startup180frames passed. Background raster capture inspected; no listening or GPU FPS claim.

The preceding release remains intact. This version builds on it; no crew animation or water simulation was added. Exact clean export identity/hashes and standalone checks are recorded by RELEASE.json. Listening, foreground control feel and GPU frame timing remain human review items under the owner’s background-only rule.
