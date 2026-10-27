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
Tested source Root709c26f/release0b5b26d; all36 designs and300DPside retained.
R59 PASS18052/0,70.828s whole, job0edbbafe118f4e11ab19b8f3c9669abc;
includes827sampled-goal/attack/manual/escape,451damage and14749wake checks.
R60 PASS2497/0,81.265s whole inclart/weapon/export/three starts;
job9022e517114e4b1fb04688c100a718a2. Same703gameinput hashes asR59.
R57's four new owned-fixture failures are preserved separately: legacy test
boats lacked canonical equipment. Fixture now uses real Records.initialize
and full zero-dt prepass. Production guards and old assertions unchanged.
R28 actual COMPLETE58.500s,cleanuptrue; QUALITY FAILED;
jobb491da26cf504b2aaaf05bfa45a08ba0. Both actual end PNGs Root viewed.
-42light/full300DPside:19.062FPS (R27:16.404;R26:7.525), simulation
 median12.377ms/P9518.577; all42moved,36moving,ZERO persistent stalls.
-16mixed/full300DPside:59.997FPS, simulation5.482ms/P959.613;
 15/16evermoved,12moving; enemy-5-barbed_lance pending3.183s for a route.
Both actual cases retain movement/fire/hits/flooding; mixed missiles observed.
Light CPUdrawing medians: preparation.465ms,hulls.278ms,motors.592ms,
weapons.517ms,damage2.946ms,totalboats5.192ms,wakes1.738ms.
Mixed damage2.5025ms,totalboats3.6895ms. Subclocks measure CPU submission,
not GPU execution. Largest drawing work is damage feedback, not hull sprites.
Light phases: begin2.321ms,helm2.888ms,damage1.523ms,mounts1.076ms,
firing1.035ms. Sampled goals retain150ms sample/450ms choice and current60Hz
helm/fire/damage/orders. No idle-FPS, lower actor count or lower simulationHz.
Next bounded source pass targets damage drawing, measured repeated main-thread
phase work and the actual mixed route stall. Majority via3BridgeSol6.1MAX.
No051tag/package/install and no052 expansion while the core gate is open.
Rejected slower retained native renderer remains reverted; do not repeat it.
All tests background/muted/sharedFIFO; each whole batch below120seconds.
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
