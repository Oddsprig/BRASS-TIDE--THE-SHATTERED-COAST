# Current verified release: v0.063 bounded fleet performance correction

Two reviewed copy/allocation changes and the real worker-publication regression
are verified. **839 unique focused checks passed**, Windows startup passed, and
both full300DP cases were measured. Observed worker P95 fell from38.807 to37.816ms
(light42boats) and20.187 to19.487ms (mixed16boats). Both frame-consistency targets
met in this short run. **Whole-game quality and strict performance remain open.**

Next: **v0.064**, ocean/local charts, the current Shatter Coast, one remote
prototype group, regional entry/exit and a persistent round trip. Finish that
scope before adding long-voyage mechanics or multiplying regions.

| Version | Bounded scope |
| --- | --- |
| 0.063 | Verified: bounded copy/allocation correction; remaining targets recorded. |
| 0.064 | Two-scale world; sail out, approach one remote group, return and save/load. |
| 0.065 | Fuel, wages, rations, maintenance and return reserves for longer voyages. |
| 0.066 | Ocean route choices, currents/weather, sightings, pursuit and interception. |
| 0.067 | Complete the first useful remote exploration expedition. |
| 0.068 | Interregional NPC shipping and scheduled distant economies/fleets. |
| 0.069 | Expand the proven pipeline into core, frontier and remote regions. |
| 0.070 | Extend existing jobs and support-boat roles across ocean voyages. |
| 0.071 | Focused combat presentation, wakes, damage and sound corrections. |
| 0.072 | Complete voyage integration, career balance and sector performance. |

Detailed acceptance and exclusions: [Open ocean version map](docs/roadmap/OPEN%20OCEAN%20VERSION%20MAP%20v0.063-v0.072.txt).
Sector design target48groups:8settled/12frontier/28remote. First prove one crossing
and a worthwhile destination. Current game geography remains8main islands,
10ports and14survey sites in one region; no ocean/local transition is built yet.

Remaining demonstrated gaps:
- Light workerP9537.816ms exceeds33.333ms;lag150ms exceeds100ms;catch-up/planner
  criteria remain unmet. Mixed worker/lag meet. Preserve actual actor counts,
  current simulation rates and thresholds. The rejected062phase trial stays out.
- Strict observedFPS59.996585/59.986463 remains below60; no threshold waiver or
  claim of fully solved performance. A short historical/current comparison is
  not a controlled causal estimate or long-play guarantee.
- Combat motion, boat separation, wakes, sound/listening and general artwork;
  four actual battle stills are only a bounded visual sanity review. Startup HUD
  briefly lacks worker status before the first publication. Settings/help renderer
  wording should reflect actual safeMode1, not imply Separate2 is active.
- Full six-career progression and profitable naturally seeded traffic/economies;
  prior composition proofs do not certify complete campaigns.

Use existing source/queue tools. Every selected whole batch<120seconds including
setup/import/export/startup/cleanup;queue wait separate. Background/private/muted,
shared FIFO, no mouse/focus or interference with other apps. Preserve voyages,
music, settings, physical owners/UIDs, finite goods and conserved coin purses.
Evidence: docs/PERFORMANCE v0.063.txt, docs/TEST RESULTS v0.063.md,
docs/VERIFICATION INDEX.txt and work/quality-v063/CURRENT STATE.txt.
