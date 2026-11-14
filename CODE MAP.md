v0.109 — Current source map (delivery candidate)

Read docs/roadmap/QUALITY DELIVERY MAP v0.100-v0.109.txt for the ten bounded milestones. Version acceptance and limitations belong in CHANGES v0.100.md through CHANGES v0.109.md. Historical source-map/status text is preserved under docs/history/quality100-108 and in Git.

Native project: game/. Canonical catalogue and geography: game/data/world.json. Version identity: game/scripts/version.gd, game/project.godot and game/export_presets.cfg. Detailed subsystem navigation: maps/PROJECT MAP.txt and maps/.

Main/Interface: game/scripts/main.gd owns scene modes, input, worker publication and verified saves. interface.gd owns title, settings, HUD, modals and literal player labels. Settings Back/Esc share leave_settings; first title action retains keyboard focus. Modal callbacks must use actual API return meanings.

Campaign: campaign.gd owns career state and normal economic actions. Daily worker publication is joined before explicit save/retirement; automatic saves wait for a settled worker. sector_world069, ocean_world064, ocean_campaign066, ocean_travel066, shipping068 and shipping_flow068 implement seeded island groups, Open Seas travel and physical shipments. Naval contact observations retain date and loaded status; do not expose unobserved live cargo or promise unfunded jobs.

Combat: battle_driver051 owns the detached authoritative 30Hz data worker. tactical_runtime builds role/target plans on its existing cadence. Main owns input, command publication, rendering, UI and audio; chart interpolates published poses. tactical_role_plans handles survival before missing-protector fallback. battle_commands047 carries native orders. Tests must wait for a newer successful command receipt and reacquire the published boat ID.

Presentation: boat_art and boat_sprite_art use the existing authored/cached hull assets and compatible physical sockets. wake_art045 and chart draw short wakes and bounded effects; the battle minimap is reserved HUD space. campaign_fleet_art054, campaign_landmark_art054, nautical_art and coastal terrain draw campaign boats/harbors. harbor_route104 previews the actual route and reserve report before applying course.

Equipment/economy: workshop, workshop_comparison048 and equipment_* retain compatible mounts, equipment UIDs and paid stock/labor quotes. voyage_preparation_ui065 exposes funded voyage choices and reserve shortfalls. naval_ui and escort_ops expose observed loaded traffic and real client-funded escort review. core/Money transfers conserve actual purses; payroll allowance, booked wages, escrow and inventory use are different quantities.

Bounded verification: game/tests contains retained useful fixtures. Current private queue tools, raw images, receipts and source bindings are in parent work/quality-v100-v109-2026-11-14. Retained earned checkpoint105 is an actual completed public journey copied into private profiles; it is not owner data or supplied victory. Retail exports exclude tests, private notes, profiles and evidence.

v0.109 prepares distinct current gameplay media, a plain $9.99 Windows store listing and a verified current download. Delivery is pending until the actual media, complete rendered page, clean portable and live purchase/library/download path are reviewed. Export success alone does not establish art, performance or game quality.
