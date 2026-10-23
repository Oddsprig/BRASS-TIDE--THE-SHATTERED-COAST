# Brass Tide — current working rules

Authoritative source is this Git repository. The **v0.029 source candidate passed
all 70 actual native suites**; root acceptance/tagging and its separate Windows
receipt remain pending. Delivered game is **v0.028**, 24 original hulls; game tag
commit `2b11d4d1af69b62a2f8436bcdee4a5675432bd98`. The .029–.038 AI/civilian roadmap
is AUTHORIZED FOR IMPLEMENTATION by the owner on23October2026; .030–.038 remain pending.
Build .029 through .038 sequentially on the verified predecessor. Codex coordinates;
majority implementation goes to up to THREE Sol6.1 MAX helpers THROUGH BRIDGE,
ChatGPT plan. No native helpers or model substitutions. Current milestone is .029;
future features stay pending until their predecessor is accepted. Read
briefs/V0.029-V0.038 TEAM CONTRACT.txt. Completed cleanup history is cold archived.

Read HANDOFF.md, CODE MAP.md and the relevant generated system map. Read
`docs/VERIFICATION INDEX.txt` before repeating checks and `docs/DEVELOPER LESSONS.txt`
before changing accounting, saves, combat or navigation. Use targeted searches;
read files over 40 KB in parts and split code approaching 60 KB. World/data and
actual native APIs/tests take precedence over old advisory reports.

Owner requirements: original motorboat fleets in Godot for Windows PC; cheap
beautiful 2D water, numerical crews and fixed asset helmsmen/gunners; WASD camera,
default flagship autopilot, 300 deployment points per side distinct from ownership.
Physical interchangeable mount IDs/positions/arcs must agree across refit, art,
aim and projectile origins. Use **coins**, 100 coins per sailor-day, finite people,
material and purses, paid workers/experts/construction and real shipowner budgets.
No copied Blood Wake/Starsector assets, code, stories or geography. Required AI
quality is a design target, not a verified existing achievement.

All game tests remain hidden/background/silent and serialized, one engine at a
time. Never take mouse, keyboard or focus. Prefer question-specific bounded checks;
never weaken assertions to pass. Preserve the owner’s saves/settings/music. Use
only owned explicit PIDs for timeout cleanup. No global installs/system changes.
Use the existing Godot 4.7.2 and local Python. Source/CPU tests, visual review,
listening, Windows export, launcher and remote publication require separate proof.

Keep UI/scene/resources on the main thread. Worker tasks own copied data, join,
then publish once on main. Rendering is Separate; current economy reserves two
logical CPUs and caps worker lanes at eight on the observed 24-thread machine.
Profile actual work before increasing concurrency. No expensive fluid simulation.

If helpers are needed and authorized, latest owner preference is up to three
Sol 6.1 Max helpers **through Bridge** for tracked usage; no silent model/provider
substitution. The owner now requests majority delegation for implementation. Lead owns taste,
integration, review and acceptance. Give each helper exact current inputs, its
own worktree and a file allowlist; no helper deletions or competing engine tests.
Preserve raw reports unchanged and write a separate lead verdict.

Owner authorizes pruning obsolete scratch, helper/release checkouts and redundant
test history after preserving unique edits, useful proof and lessons. Follow
`docs/WORKSPACE MAINTENANCE.txt`; validate absolute targets, refuse reparse paths,
archive unique work first, and leave portable releases/source ZIPs/original saves,
music and launcher intact. Host access requirements still apply. Do not invent a
new confirmation flow for ordinary already-authorized maintenance.

Per actual playable version: advance integer build by one (=0.001), finish the
previous build, update in-game notes/current TXT records/maps, commit named files
and preserve an annotated tag. Export only a clean exact-tag release worktree.
Never overwrite verified older releases or retag a rejected candidate as accepted.
Publish only to the verified owner repository when authorized and authenticated;
never claim a remote upload without remote hashes. Current upload remains pending.

Native checks: tools/check_game.py. Short fixtures: tools/qa_brass.py. Static maps:
tools/update_maps.py. Export: tools/release_game.py. Retain all current game/tests/.
Historical prototype dist/, root tests/ and build_data.cjs are cold archived.
