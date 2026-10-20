# Native source map

The playable game is game/. dist/ and root tests/*.cjs preserve the first JavaScript reference; no browser game is shipped. All scripts below are in game/scripts/. Generated maps contain verified symbol names/line numbers; update with tools/update_maps.py.

- project.godot/main.tscn: native Windows entry, Separate rendering, fixed60Hz physics, cheap 2D Mobile renderer.
- main.gd: main-thread controller/input/UI, copied economy worker jobs, safe publication, battle transitions and portable JSON saves.
- campaign.gd: voyage/world, actual ownership, paid crew, morale, travel, salvage and treasury rescue loans.
- contracts.gd/money.gd: sponsor escrow, finite freight/rewards, atomic integer purse transfers and complete circulating coin counts.
- damage.gd/battle.gd: numerical crew tasks, hull/engine/fire/wounds, holes/flooding/patching/pumps, swept shots, AI fleets and withdrawal.
- goods.gd:16abstract lots, occupations,100cash sailor wage and recursive costs. industry_data.gd: regional industry and initial capital/stock assumptions.
- economy.gd: paid resident production, consumption, public work, tax, finite trade and recruitment from authoritative workforce.
- fleet_economy.gd: persistent NPC boats, owner/crew purses, payroll, cargo, trade, upkeep and morale/performance.
- construction.gd: physical boat bills, whole engine/gun assemblies, skilled labor/supervision, escrow and finite slipway work. harbor.gd: real hull purchases, orders, hires, repairs, sales and stores.
- navigation.gd: bounded water-only routes around the original archipelago.
- chart.gd: code-drawn villages/forest/isometric boats/shots/wrecks, flat gradient water and bounded decorative wakes.
- interface.gd/finance_ui.gd: title/campaign/combat/harbor/fleet/guide/settings UI and exposed recipe/boat costs, resident and owner accounts.
- sound.gd: original generated sound effects. game/assets/: original SVG/PNG/Windows ICO art.
- game/data/world.json: original24hulls,10ports,4factions,8missions/islands. tools/build_data.cjs regenerates it without legacy prices/rewards.
- version.gd: integer build;1→0.001. game/export_presets.cfg excludes development tests/tools from native x86_64 package.
- game/tests/: current native suites plus preserved superseded prototype campaign test. tools/check_game.py runs bounded sequential background-only checks and rejects logged script errors even on exit0.
- tools/update_maps.py generates maps. build_notices.gd extracts exact engine legal notices into docs/legal and is excluded from export.

Maps: campaign,combat,economy,construction,navigation,presentation. Verification: docs/TEST RESULTS v0.001.md. Human play questions: TO BE TESTED.md.
