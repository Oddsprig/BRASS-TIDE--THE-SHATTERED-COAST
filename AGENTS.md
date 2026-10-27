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
Verified gameplay/art source Root44ecfcc/releaseaf4b106; all36designs retained.
R61 PASS18150/0,81.265s whole;73405bdce40a42e9839d8da2270827b9.
R62 PASS7585/0,87.360s incl5088feedback/Art205/Weapon2292/export3starts;
1f4afa2a86eb4a7197175d1d13beba98. Same703gameinput hashes asR61.
R29 actual COMPLETE58.172s/cleanuptrue/QUALITY FAILED;
a80b735c9a47406e8343af9bfb37baa5. Both end PNGs Root viewed.
Light42/full300DPside22.605FPS,simulation11.454ms/P9518.151;
all42moved39moving,ZEROstalls. Mixed16~59.997FPS/5.226ms/P958.321;
15evermoved10moving,ZEROstalls. All real active-combat coverage retained.
Damage drawing fell2.946->2.5045ms light,2.5025->1.9255ms mixed;
route-pending offer fairness removed the R28 persistent wait in these runs.

Counter calibration COMPLETE; instrumentation does not explain the slowdown.
R63 export3starts PASS52.468s;bf12557538a7425d9bacae6f6a6a119b.
Root e7933d4/release6d98b63 differs fromR29 ONLY in runtime_profile043.gd;
other702trackedgame inputs unchanged. Same new exe/PCK used for both controls.
R30 OFF:f4c5cf3462cc4ed182d954919b947f1a COMPLETE57.937s/cleanuptrue;
light22.297FPS/11.8095ms/P9518.534; mixed59.970FPS/5.858ms/P959.658.
R31 ON:1f0447b973e5454883b53c600c192a23 COMPLETE59.937s/cleanuptrue;
light20.754FPS/11.728ms/P9518.511; mixed60FPS/5.5175ms/P958.687.
Both modes have ZEROstalls and complete real movement/fire/hits/flood/missiles.
All four actual end PNGs Root viewed. Exact criteria/workload/60Hz unchanged.
Original R31 08f57dc616224917a475702969c2246a failed BEFORE engine in shared
queue atomic Move/access; preserved separately, unchanged retry measured above.
Normal and detailed runs vary with worker timing; no exact attribution of small
timing differences. Fine counters off means attribution absent, not zero work.

Next bounded pass: reuse existing draw preparation for static engine/pump mark
anchors; build full AI observations when 100ms worker planning actually requests
them. Current poses/physics/collisions/status/ready-shot checks remain60Hz.
Main remains responsible for live simulation; current role/target/maneuver jobs
and campaign economy already use copied-data workers. Separate render thread
remains disabled after native errors; actual Godot renderer mode1 is safe.
No speculative parallel-helm implementation: read-only audit found limited
net opportunity without a deeper data split. No new profiler/framework/features.
Three BridgeSol6.1MAX source tasks; Root owns all muted background FIFO tests,
each whole batch below120seconds. No051tag/package/install/no052 expansion.
Source checks, native assertions and stills are not gameplay/FPS/audio acceptance.

LATEST USER OVERRIDE - 27 October2026
The owner rejects60Hz calculations and keeping most numerical battle work onMain.
Current implementation task: authoritative data-only battle worker at30Hz, with
independent60+FPS rendering/interpolation. Earlier60Hz physical-policy statements
are historical baseline requirements and are superseded by this explicit steer.
Read C:/Users/bligh/Documents/Codex/2026-10-20/how/work/quality-v042-v061/WORKER BATTLE051 CONTRACT.txt for shared ownership/API.
Keep live swept collisions/accounting; discloseactualworker/render cadences.
NoScene/UI/render objects onworkers; do not silentlychangeotherworkloads.

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
