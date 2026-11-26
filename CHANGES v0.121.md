# Brass Tide v0.121 — natural island coastlines

Home islands, Glasswind, generated/saved regional charts and practice terrain now share rounded, asymmetric physical coastlines. Coarse polygon corners gain curved headlands and recessed bays. Dense authored shapes receive macro corner rounding. The drawn land and actual navigation/collision boundary use the same points.

Geometry is prepared at load/world/encounter boundaries and cached for rendering, with accepted replacement rings capped at96vertices. Physical land is clipped inside its prior footprint, retaining existing water routes, berths and approaches. Saved canonical sector definitions and player progress stay unchanged; runtime markers prevent repeat shaping in translated encounters. No water simulation was added.

The release will replace marketplace images with fresh captures from the actual Windows121 build, including a clear whole-island view. Price remains$9.99; the game is in early development.

## Verification record

Pending Root's bounded native fixture, actual42actor/300DP-per-side retail sample and earned-save/media review. This source integration is not yet release approval. The independent review rejected the initial relay's concave-water intrusion, unchanged home/Glasswind paths and insufficient corner rounding; Root's final source addresses those findings with actual clipped land, complete-edge checks and explicit encounter markers. Actual outcomes will be reconciled here before completion.

R1 targeted native check stopped before export:197checks/26failures,1.437s pipeline. Dense/source fallback and retained macro-corner failures remain unaccepted; no shipping/media claim. Follow-up uses Muse's topology-guarded macro simplifier, retaining complete-edge containment and actual clipped physical land.

R2 kept native fallback/curvature failures (197checks/26failures) and stopped before export. Root repairs clip duplicate endpoints and derives convex-ear winding directly from signed area, avoiding coordinate-system convention ambiguity; numerical clip margin is0.5world units. App-queued attempts cancelled before execution remain distinct. Owner explicitly resumed background checks; direct shared-FIFO fallback retains the actual lease and55s watchdog, never claims a TestBridge-app PASS.
