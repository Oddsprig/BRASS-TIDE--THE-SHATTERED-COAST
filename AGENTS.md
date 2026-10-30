# Brass Tide - current working instructions

Current verified release v0.071: combat presentation, stern wakes and recorded sound.
Tested 7ee3a993e697dabfc8260b057b47b49d93c11dc6;189 focused/0; Windows/menu and two reviewed private movie captures.
Receipts work/quality-v071/ACTUAL071 CHECKS.json and DELIVERED v0.071.json.
Do not rebuild071. Next072: complete voyage integration and measured runtime costs.
Whole-game quality/strict performance OPEN. Root owns tests and delivery.

ACTIVE SOURCE072: complete voyage integration and bounded current performance
measurement. work/quality-v072/SCOPE072.txt and isolated ROLE072.txt define the
exact four source roles. Finish072 before073. Historical063 costs justify one
small safe publication correction, not a new ownership/cache architecture or
fresh-baseline claim. No chase of fractional60FPS cap noise. Root alone queues
all actual engine/GPU tests; preserve installed071 until072 accepted. Metadata
for072 has not been prepared. Two SolMAX/two GrokHIGH through Bridge; requested
Gemini media work pending availability, no paid fallback; bounded Spark work is
reviewed before use. No new hull/AI/strategy/economy frameworks in072.

071 audible quality remains UNVERIFIED. Root reviewed20 temporal frames and
source/PCM integrity; this was not listening. Sparse sample and exact limits:
docs/audio/OFFLINE REVIEW v0.071.txt. Spark media route declined; explicit Google
plan audio call timed out. Two Spark text drafts reviewed; erroneous layer-level
sum rejected. No paid/model fallback. Gemini media reviews pending availability.

Owner campaign clarification, 29 October 2026: one ocean-covered planet, no
major continents. Open seas fill the hyperspace role; island groups fill the
star-system role; individual islands fill the planet role. Harbors/outposts are
markets/installations. Groups can contain islands and ports owned by different
factions, with peaceful mixed ownership or conflict. Geographic sectors and
political ownership/influence are distinct. Seeded generation, shipping/trading/
pirate actors, faction relationships and funded territorial expansion are the
required direction. docs/roadmap/OCEAN WORLD DESIGN.txt is authoritative for
this model. Current069 fresh careers contain48 seeded groups; older careers retain their two authored regions.
069 delivers seeded geography and starting asset ownership; retain068 physical shipping. Dynamic expansion/capture need explicit later bounded milestones.

Latest owner team authorization (29 October 2026): 2 Sol 6.1 MAX, 2 Grok 4.7
HIGH, 2 Gemini 3.8 Flash and 2 Muse Spark HIGH. Flash tasks must be small,
explicitly bounded and reviewed by Root/the specialists before integration.
Majority source implementation through Bridge. Phase tasks within Bridge limits;
Root coordinates/reviews/integrates and alone owns all engine/GPU jobs.
No native/nested helpers, new chats,
ask_project/AI brain, model substitution or paid-API fallback. Isolated allowlists,
source-only helpers; integrate named commits. Completed helpers stay idle until
given another bounded task. Finish the current delivery before advancing the next saved release.

Next ten scopes 069-078 are authoritative in docs/roadmap/QUALITY VERSION MAP
v0.069-v0.078.txt (29 October 2026 owner request). Existing 069-072 scopes are
preserved, followed by boat/weapon assets 073, tactical AI 074, faction strategy 075,
funded territorial change 076, exploration chains 077 and quality review 078.
Owner authorized implementation on 29 October: start 069 on accepted 068,
deliver one bounded version before advancing. Do not claim parity from tags.
063 through071 are scoped verified;072-078 remain planned. Earlier quality
limits remain. The older 063-072 map retains accepted history and context.
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

29October owner correction: finish and install the current version. Do not turn
elapsed test time into a stop-work rule before packaging. Keep each bounded batch below120seconds and the entire
selected verification suite below180seconds (latest owner three-minute ceiling),
including setup/import/export/startup/cleanup; queuewaitseparate. Reuse passed
unchanged components with strict source proof and avoid repeated unnecessary
checks. Continue through Windows export, actualscreenreview and launcher delivery.
Historical retries remain recorded honestly; they are not a lifetime version
budget or permission gate. No requesting another budget reset just to finish.

Whole selected test batches MUST finish below120seconds including setup/import,
export/startups and cleanup; queue wait is separate. Split useful small batches
before the limit. Retain passed unchanged component evidence with source hashes;
queued/interrupted/timed-out checks are not passes. Never weaken assertions just
to pass. Source/static checks are advisory, not native execution.

Background/hidden/silent only, synthetic APPDATA/saves and Dummy/muted audio.
No mouse/keyboard/focus/computer control, no Desktop game autolaunch. Keep owner
voyages/settings/20MP3s/older builds and one plain Brass Tide shortcut intact.
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
two voyages,20music tracks and the single unambiguous latest verified launcher.
No retagging rejected candidates. Retain failed receipts and distinguish source,
native checks, rendered measurement, art review, listening and actual play quality.

Owner permits routine pruning of obsolete scratch after preserving unique work,
useful evidence and lessons; follow docs/WORKSPACE MAINTENANCE.txt. Resolve and
verify absolute workspace containment, refuse reparse targets, preserve releases,
source archives/saves/music/launcher. No broad cleanup during an active test gate.
Historical instructions and measured results remain recoverable in Git and the
current task's evidence files; older contradictory scope/team/status paragraphs
were consolidated here on27October2026.
