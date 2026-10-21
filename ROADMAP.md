v0.010 SOURCE ACCEPTED — Salvage and recovery. 28 native suites accepted; exact-tag export has separate receipts. Continue the authorized sequence after preserving this build. Earlier planning/release records follow.

v0.009 SOURCE ACCEPTED — Island exploration. 26 native suites accepted; exact-tag export has separate receipts. Continue the authorized sequence after preserving this build. Earlier planning/release records follow.

# Brass Tide campaign roadmap

v0.008 source accepted: expedition preparation, separate ownership/deployment, storage and parallel production pass24native suites. Exact-tag Windows export has separate receipts. Current implementation team is root plus one Muse Wonder Full, one Argon High and one Grok4.7, superseding the historical team below. Continue v0.009 after preserving v0.008.

21 October 2026. The delivered game remains **v0.007**. The next playable build is **v0.008**. This update records proposed campaign work; it does not change the game, saves, release tags or launcher.

The purpose is a connected loop: hear a lead, prepare a fleet, explore/trade/fight, choose what to recover, return and reinvest, then follow the opportunities and consequences. Exploration, fleet composition, factions and economics should give one voyage several worthwhile possibilities.

Full design, current-source gaps, acceptance gates and a worked voyage: [CAMPAIGN ROADMAP.txt](docs/CAMPAIGN%20ROADMAP.txt).

| Proposed build | Playable outcome |
| --- | --- |
| v0.008 | Readable voyage costs/endurance and a consistent cargo manifest. Separate total fleet ownership, traveling boats and normal 300-point battle deployment; stored boats provide no afloat cargo. |
| v0.009 | Persistent island discoveries, coastal charts and numerical landed surveys with distinct resource, route, equipment and story opportunities. |
| v0.010 | Persistent wrecks, meaningful strip/tow/recover choices, and rare components/drawings that unlock paid production. |
| v0.011 | Several compatible funded contracts, initial persistent contacts and dated intelligence, so one trip can combine jobs and discoveries. |
| v0.012 | Player/faction/contact relationships, explained hostility, meaningful port access and commissions; viable independent play. |
| v0.013 | Purposeful NPC convoys, escorts, raiders and patrols; NPC-versus-NPC encounters, retreat, repair and funded replacement orders. |
| v0.014 | Physical trade disruptions, blockades and recovery affecting real stocks, production and opportunities; useful net-profit intelligence. |
| v0.015 | Stronger roles across the existing 24 hulls, paid specialists and support conversions, persistent boat/crew histories and voyage-related battle objectives. |
| v0.016 | Distinct regional discoveries, authored contact/story chains and sustained explorer, trader, escort and privateer careers. |
| v0.017 | Optional paid berth/warehouse and a chartered harbor business using actual workers, inputs, capital and shipping. |
| v0.018 | Sustained limited faction campaigns, peace/recovery and player-chosen late-game goals grounded in real logistics. |

These are sequencing targets, not dates or guaranteed feature counts per build. If a milestone needs several releases, increment every build by exactly 0.001 and move later targets forward. First prove the v0.008-v0.011 expedition loop, then the v0.012-v0.014 reacting coast. Keep cheap 2D water, numerical crews, default autopilot, original content, finite coins and background-only testing. Follow the existing two-Argon helper limit when implementation requires helpers.

Current-source gaps include the ownership/deployment limit coupling, phantom traveling capacity from mothballed hulls, single active contract, absent survey/reputation progression, fixed patrol routes and story-gated blockades. Existing production, purses, cargo, crews, fittings and combat remain the foundation. Proposed autonomous territorial operations are Brass Tide design, not a claim about base Starsector behavior.

# Delivered presentation releases

Current delivered release v0.007. Each version preserves the completed predecessor. Each version builds on the verified predecessor.

- v0.003: exported and verified — Removed displaced whole-hull shadows/reflections; opaque side faces connect the water surface and upper rim.
- v0.004: exported and verified — All-team typed firing/hit/miss/engine/sink events feed position-aware recorded sound; bounded queues and consume-once IDs.
- v0.005: exported and verified — Expanded original coast to10400x7200world units,16times the previous area; all ten ports retained with much wider separation.
- v0.006: exported and verified — Completed24distinct hull silhouettes/bridges/deck details; removed residual bow-outline foam and retained solid contact. Shared physical interchangeable sockets feed previews, paid fittings and combat.

- v0.007: exported and verified — stern machinery, localized/animated damage, material sparks, explosions, cause-aware sinking and a post-victory visual tail. Colored hull/equipment mesh caching keeps detailed fleet drawing cheap. Exact identity and checks are recorded in RELEASE.json.

Two Argon High helpers only; root owns integration and serialized background tests. Full BUILD PLAN.txt records acceptance. Previous portable releases and saves remain intact.

All four requested sequential versions are preserved as portable Windows builds and exact-tag source ZIPs. Further visual/mix/control refinement follows voluntary owner feedback; v0.007 follows the owner's subsequent engine/damage request.
