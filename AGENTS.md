# Brass Tide — current working instructions

Installed build: v0.062 DELIVERED, localtag79ebbaa; coast/readability corrections.
Whole quality milestone OPEN. SourceRoot8ca2477/testedreleased4e5ad1, identical
game tree71a69f4. Clean638component checks43.603s plus196paidvoyage/Windows86.893s.
18scope views+4activebattlePNGs Rootreviewed; opening31.075/coast30.663/runtime
59.050s, noinput/focus/privateDesktopactivation. Allhelpersidle.
TrialC2320371b was removed by7983166 after2failedpost-terminalnativeexits;
assert120/0wasNOTnativepass. Controlledremoval+allfinalprocessesclean, detailed
nativecrashcauseunproved; do not restore that trial without specific diagnosis.
Actual062qualityflagFALSE: lightworkerP9538.807ms/lag150.222ms, catchup/planner
criterionunmet; mixedP9520.187/lag50meetsbut93.889%frames<=20msmisses95%.
Bothstrict59.997630/59.998430FPS<60;no>50msframes. No improvement/parityclaim.
Currentstate/scope/evidence work/quality-v062; oldreceiptswork/quality-v042-v061.
Do notprepare062again. Preserve2voyages/18MP3+2notes/olderbuilds/oneplainicon.

Owner: "OKAY - BUILD ONE VERSION ON TOP OF THE OTHER 3 SOL 6.1 MAX - YOU CAN
USE GROK 4.7 ON HIGH TO HELP." Majority source implementation through Bridge;
Root coordinates/reviews/integrates and alone owns all engine/GPU jobs. Maximum3
active Sol6.1MAX; optional Grok4.7HIGH. No native/nested helpers, new chats,
ask_project/AI brain, model substitution or paid-API fallback. Isolated allowlists,
source-only helpers; integrate named commits. Completed helpers stay idle until
given another bounded task. Finish the current delivery before advancing the next saved release.

Roadmap056-062 remains saved in docs/roadmap/STARSECTOR QUALITY ROADMAP.txt.
Strict performance and whole-game quality remain OPEN at062. Do not reopen051
fine-tuning as a prerequisite for each later bounded scope. 051 receipts remain
unchanged: light workerP9538.435ms exceeds33.333ms, maxlag151.409ms exceeds100ms;
measured light59.999155/mixed59.987253FPS misses strict>=60, rawqualityflagFALSE.
Full facts/receipts are in tools/quality051, DEVELOPER LESSONS, current task and
DELIVERED v0.051.json; historical checkpoint text is archived in the task.

Architecture: authoritative combat30Hz on a data worker, role/target choices100ms
per side. Main owns input/command publication, UI/audio/render submission and
independently interpolated poses. Workers own detached plain data/RNG/contexts;
retirement joins children and reconciles original physical owners. Public
synchronous Battle APIs remain references. Safe render mode1 is active; Separate2
previously caused native errors and must not be claimed active.

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
fluid simulation, actor deletion or fake idle-FPS acceptance. The owner-authorized
30Hz worker cadence above replaces the old 60Hz simulation requirement.

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
