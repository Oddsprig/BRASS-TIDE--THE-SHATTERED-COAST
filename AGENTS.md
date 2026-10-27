# Brass Tide - current working instructions

Owner authorization: "OKAY - BUILD ONE VERSION ON TOP OF THE OTHER
3 SOL 6.1 MAX - YOU CAN USE GROK 4.7 ON HIGH TO HELP."
Build the saved scopes0.042-0.061 in order. Majority implementation through
Bridge; Root coordinates, reviews, integrates and owns all engine/GPU jobs.
Maximum3 active Sol6.1MAX, optional Grok4.7HIGH. No native/nested helpers,
new chats, ask_project/AI brain, model substitution or paid-API fallback.
Read work/quality-v042-v061/CURRENT STATE.txt for exact active jobs/helper offsets.
Completed helpers stay idle until given a new bounded current-source task.

CURRENT CORE CHECKPOINT - 27 October 2026
Active0.051; Desktop remains verified0.050. Core gate OPEN; no052 breadth.
Current tested candidate: Rootf5381ee/release3b7e894; all36designs preserved.
R55 PASS2796/0 incl771sampled-goal checks and paid first voyage,69.844s whole;
job15b09b0dedc34cbe88cf7305bf488c45. Logic-only, no export in that batch.
R56 PASS60.953s incl import/export/three starts/cleanup;
job02376bfdba5f40b3a931f2bc6313b06c. Same703gameinput hashes asR55.
R27 actual COMPLETE59.438s, cleanuptrue; QUALITY FAILED:
jobb004006fa03847e9add1313605d14080. Both actual end PNGs Root viewed.
-42 light/300DPside:16.404FPS (R26:7.525), simulation median12.4545ms/P9520.122;
 all42 moved,35moving, ZERO persistent stalls;193catch-up frames/117over50ms.
-16 mixed/300DPside:59.887FPS, simulation median5.590ms/P958.787;
 all16moved,14moving, ZERO persistent stalls;98.19percentframes<=20ms.
Both cases have actual movement/fire/hits/flooding; mixed launches missiles.
New fleet policy removes MAIN multi-offer/refine/resolve work. Planning median
10.643->5.4905ms light,3.7995->2.378ms mixed; no sync fallback. Workers choose
actual sampled tactical goals (<=150ms,100ms SIDE refresh); chosenAt+.45 never
renews through adoption. Current60Hz helm/fire/damage/orders remain authoritative.
Ordinary1v1/direct legacy planner behavior unchanged. No fake full-route proof.
The sampled policy is component-tested and improves actual performance, but
large battle remains unusably slow; no051tag/package/install/no052 expansion.
Accepted float32 contact repair still has zero stalls in actualR27. Rejected
slower retained native renderer remains reverted, preserved with receipts in Git.
Reviewed source follow-up integrated: owned-phase goal capability reuse,
uncut indexed wake copy bypass, and pure repair-need OR short-circuit. No speed
claim before R28. Root adds opt-in drawing subclocks to the existing profiler.
Grok review found attack-target gating and repeated escape preference issues;
two Sol6.1MAX helpers own bounded fixes. Claimed manual-input regression was
rejected: Battle.update already applies real manual controls before AI helm.
R27 light costs: helmCurrent1.150ms,helmSafety1.655ms,damage1.5545ms,
mounts.989ms,firing1.223ms; boats5.040ms,wake1.663ms,presentation8.030ms.
Per-tick unaccounted median.567ms, not the difference of separately summed medians.
NativeR57 and actualR28 only after reviewed source; no speculative speedup claim.
Grok4.7HIGH review completed from its existing packet; Root verified the
attack gating defect and actual manual-input call chain. Escape fix is scoped.
Review is source evidence, not a native result or performance acceptance.
Earlier R55 queue attempts FAILED before engine (atomic status Move access)
or INTERRUPTED at queue app restart. They are not game assertion results.
Root owns all queued muted background tests, each whole batch below120seconds.
Source checks, native assertions and stills are not gameplay/FPS/audio acceptance.

## Scope and design

Each version advances0.001 and addresses its saved scope. Do not add unrelated
features, chase speculative edge cases, build duplicate test frameworks or call
an unfinished milestone complete. A failed quality gate gets a bounded fix to
its demonstrated failing part. Do not preserve expensive internal policy solely
to satisfy old implementation-shaped checks; explain an intentional policy
change and keep meaningful gameplay/accounting/physical regressions intact.
Read docs/roadmap/STARSECTOR QUALITY ROADMAP.txt for scopes and quality criteria.

Godot Windows PC, strategic coastal chart plus isometric battles, cheap beautiful
water, numerical crews and fixed asset helmsmen/gunners. Default autopilot and
WASD camera. Fleet ownership/storage is distinct from300DP battle deployment
per side. Interchangeable physical mount IDs/positions/arcs must agree across
art, refit, aiming and projectile origins. Use original boats/factions/geography;
do not copy Blood Wake/Starsector assets, names, stories, maps or code.
Coins,100coins per sailor-day, finite labor/materials/stores and conserved purses.
Real construction/repair/replacement wages and material costs; no free resources.

## Testing and machine use

<!-- GAME TEST LANE -->
Follow [Game testing rules](C:/Users/bligh/Documents/Codex/GAME%20TESTING%20RULES.md).
Before every engine/game/GPU test use the read-only process detector and shared
C:/Users/bligh/Documents/Codex/tools/game-testing/Invoke-GameTestLane.ps1 FIFO.
Queue behind Godot/Unity editors/players/renamed games and other test leases.
Never close, control or reconfigure another app. Failed process inspection queues.
One bounded engine/GPU job at a time. Test Bridge claims the SAME lane; submit
raw commands and never nest another lease. Preserve job IDs and actual receipts.
Yield only our own identity-verified process if another game starts.
<!-- END GAME TEST LANE -->

Whole selected test batches MUST finish below120seconds including setup/import,
export/startups and cleanup; queue wait is separate. Split useful small batches
before the limit. Retain passed unchanged component evidence with source hashes;
queued/interrupted/timed-out checks are not passes. Never weaken assertions just
to pass. Source/static checks are advisory, not native execution.

Background/hidden/silent only, synthetic APPDATA/saves and Dummy/muted audio.
No mouse/keyboard/focus/computer control, no Desktop game autolaunch. Keep owner
voyages/settings/18MP3s/older builds and one plain Brass Tide shortcut intact.
Cleanup must match PID AND creation time/retained handle; no broad process kills.
Use existing Godot4.7.2/Python, no global installs or system setting changes.
UI/Scene/resources remain on main; workers own copied data and publish only after
join. Actual safe render thread mode1: Separate2 caused native texture/finalizer
errors; never claim Separate active. Existing economy/tactical workers remain.
Profile actual representative battles before increasing concurrency. No expensive
fluid simulation, actor deletion, lower simulationHz or fake idle-FPS acceptance.

## Source, handoff and delivery

Read relevant maps and actual API/schema before editing. Use rg and bounded file
reads; docs/DEVELOPER LESSONS.txt and docs/VERIFICATION INDEX.txt hold reusable
lessons/evidence. Give helpers isolated checkouts, exact source and file allowlists.
No competing tests or deletion. Integrate named commits, not someone else's HEAD.
No git reset/amend/gc/maintenance/repair; no automatic remote publication.
Current session has no authorization for new GitHub pushes after the old028 push.

Update in-game DEVELOPER NOTES.txt, BUILD STATUS.txt, scope notes and current maps
with changes and actual limitations. tools/update_maps.py regenerates maps.
tools/check_preload_calls.py GAME RELATIVE_FILE... is one cheap source advisory;
it cannot prove native parsing/types/assertions. Read complete constructor chains.
Refits use weapons:Array; effective_spec returns the spec directly. Preserve UIDs.

Prepare each version once, build on the accepted predecessor and preserve exact
source/hash/tag provenance. Export from the isolated reviewed release checkout.
Tag/package/install only after that scope's acceptance. Preserve older releases,
two voyages,18music tracks and the single unambiguous latest verified launcher.
No retagging rejected candidates. Retain failed receipts and distinguish source,
native checks, rendered measurement, art review, listening and actual play quality.

Owner permits routine pruning of obsolete scratch after preserving unique work,
useful evidence and lessons; follow docs/WORKSPACE MAINTENANCE.txt. Resolve and
verify absolute workspace containment, refuse reparse targets, preserve releases,
source archives/saves/music/launcher. No broad cleanup during an active test gate.
Historical instructions and measured results remain recoverable in Git and the
current task's evidence files; older contradictory scope/team/status paragraphs
were consolidated here on27October2026.
