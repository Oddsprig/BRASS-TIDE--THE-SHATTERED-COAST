# v0.028 — Campaign balance guidance and performance

SOURCE ACCEPTED: 66 native suites pass; portable export evidence is recorded separately in RELEASE.json.

- Captain priorities provide five career views, actual readiness and return budgets, and direct links to existing campaign systems without changing game state.
- Paid physical companies, academy courses, customs expiry, defenses and civilian reception pass a combined60-day campaign; civilian wreck cargo and surviving-flagship restoration preserve exact accounting.
- Secured-prize sinking, manual-control exclusion and capture-capacity checks preserve actual people and wrecks. Bounded route reuse and charter records keep campaign work finite.
- Current portable play guides, native24-hull/20-good bills, scoped CPU measurements and original historical notes accompany the Windows build.

Continue the authorized sequential roadmap after verifying/preserving this version. Root + up to three Sol6.1 Max helpers through Bridge only. In-game notes: game/data/DEVELOPER NOTES.txt. Release checks: docs/TEST RESULTS v0.028.md and portable RELEASE.json. Preserve owner saves/music and all previous releases. Background-only tests, one engine at a time.

# Brass Tide v0.028 — final economy review

The owner authorized v0.019-v0.028 sequentially, with up to three Sol6.1 Max helpers through Bridge. All three helper projects finished. No additional helpers or later version has been started. Versions 0.019-0.027 have complete local delivery receipts; v0.028 source is undergoing its final full checks and export.

Current authoritative game is game/, using Godot 4.7.2 and version.gd integer BUILD/1000. The desktop launcher lives at Desktop/game-launchers/Brass Tide.lnk and must change only after a verified native export. Preserve all older releases, music and owner saves. Tests remain serialized, hidden/headless; never use desktop input/focus. The engine path is supplied to tools/check_game.py. Developer records and historical snapshots remain in docs/history/.

Read maps/PROJECT MAP.txt, CODE MAP.md, the relevant generated system map and docs/ECONOMY QUICK START.txt. In-game notes: game/data/DEVELOPER NOTES.txt; full previous notes: game/data/DEVELOPMENT HISTORY through v0.027.txt. Raw helper reports are retained unchanged in docs/ with separate root acceptance notes. Full raw Bridge payloads and adapted scratch remain in the parent task work/helper-results/ and work/economy-future/.

Implemented economy adapters are training_ops, reserve_ops, tooling_ops, yard_development, worker_ops, civilian_goods_ops, company_ops, law_ops, boarding_ops and crisis_ops. regional_ops remains the earlier regional-campaign adapter; do not replace it with civilian goods. Pure passenger_manifest reads keep hold accounting independent of main-thread transport transactions. Route caching belongs to each Campaign outside saved data, has at most 128 exact endpoint entries, returns detached paths and clears on new_game/restore. Pure Navigation and copied-port workers are unchanged by that cache.

Finite coins: Money.total counts harbor, crew, owner, company/business, course, yard, contact/job and passenger escrow/savings exactly once. Regional lost savings remain a counted estate purse. Qualification subsets are real worker eligibility, not extra people. Crews are numerical. Boat ownership, traveling cargo and 300-point deployment remain separate. Default combat control is autopilot with WASD camera. Captured prizes retain damage/fittings, require real paid harbor repair and do not participate as combatants while secured.

Root has reviewed all four final helper payloads and added actual game voyages for customs, boarding/defenses and crises. Final guidance uses actual law/labor/tooling fields and read-only readiness. The 60-day combined campaign and civilian wreck/flagship-loss regression pass targeted checks; full source and exact-checkout evidence belongs in docs/TEST RESULTS v0.028.md and portable RELEASE.json. Headless CPU timings do not establish GPU FPS or listening quality.

Use tools/finalize_campaign_release.py only with reviewed explicit paths and complete source logs. It checks a clean checkout before creating the annotated tag, then exports, hashes and archives. Post-delivery record commits may advance main while game/ stays identical to its exact tag. tools/publish_github.py verifies the owner's exact repository, ancestry and remote refs without force or sign-in UI. Local delivery and GitHub publication are separate facts.
