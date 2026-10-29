# Current verified release: v0.068 working interregional shipping

One funded Westglass branch and existing merchant connect the local charts
through open seas, retaining physical cargo, crews, purses and dated sightings.
555 focused checks/0failures and21reviewed private stills.
Earlier whole-game quality and strict performance targets remain open.
Next saved scope: v0.069 seeded sector geography and starting ownership.

Campaign design: one ocean-covered planet, no major continents. Open seas serve
the hyperspace role, archipelagos the star-system role, and individual islands
the planet role. Different factions may own islands and harbors inside the same
group. Generated geography, mixed ownership, shipping, diplomacy and funded
territorial expansion are required campaign systems. The current two-region
build is their foundation. See [Ocean world design](docs/roadmap/OCEAN%20WORLD%20DESIGN.txt).

| Version | Bounded scope |
| --- | --- |
| 0.063 | Verified: bounded copy/allocation correction; remaining targets recorded. |
| 0.064 | Verified prototype: ocean/local charts, Glasswind Keys, persistent round trip. |
| 0.065 | Verified: forecasts, return reserves, actual paid voyage and finite tank transfers. |
| 0.066 | Verified: ocean conditions, sightings, physical pursuit/interception and battle custody. |
| 0.067 | Verified: Glasswind surveys, paid shore parties, finite cargo recovery and physical return. |
| 0.068 | Verified: one funded Westglass branch, physical merchant shipping and scheduled distant activity. |
| 0.069 | Seed the wider core, frontier and remote world, including starting island/harbor ownership and mixed-faction groups. |
| 0.070 | Extend existing jobs and support-boat roles across ocean voyages. |
| 0.071 | Focused combat presentation, wakes, damage and sound corrections. |
| 0.072 | Complete voyage integration, career balance and sector performance. |

Detailed acceptance and exclusions: [Open ocean version map](docs/roadmap/OPEN%20OCEAN%20VERSION%20MAP%20v0.063-v0.072.txt).
Sector design target48groups:8settled/12frontier/28remote. First prove one crossing
and a worthwhile destination. Current settled home geography has8main islands,10ports and14survey sites.
v0.064 added ocean/local crossings and the three-island Glasswind Keys prototype;
v0.067 proved the first useful remote expedition. The full seeded world,
sector-wide political ownership and ongoing faction expansion remain open.
Expansion, capture and changing political control need explicit bounded
follow-on milestones; the existing068-072 sequence does not complete them.

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
