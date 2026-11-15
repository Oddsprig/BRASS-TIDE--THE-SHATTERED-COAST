v0.111 — Current source map (candidate)

Current original campaign design: docs/roadmap/CAMPAIGN BUILD MAP v0.110-v0.119.txt.110 delivers the first chapter;111–119 remain planned. Previous quality milestones and actual store109 evidence remain in their immutable CHANGES files and docs/store/CURRENT PUBLICATION.json. Game build, installed build and public download are separate delivery records.

Native project: game/. Canonical catalogue/geography: game/data/world.json. Identity: game/scripts/version.gd, game/project.godot, game/export_presets.cfg. Current campaign navigation: maps/campaign-main110.txt. The older generated inventory is a historical aid; use rg on named source for current symbols.

Main/Interface: main.gd owns modes, input, worker publication and saves. interface.gd owns title/settings/HUD/modals. Modal actions join the economy worker before mutation; manual saves/retirement settle workers and autosaves wait. Settings Back/Esc share leave_settings.

Campaign: campaign.gd owns career state/economic actions. sector_world069, ocean_world064, ocean_campaign066, ocean_travel066, shipping068/shipping_flow068 own island groups, Open Seas travel and physical shipments. Sightings retain date and observed load; they do not expose unseen live cargo.

Original storyline: campaign_main110.json appends one chain, common_passage110, without changing the nine legacy chains or eight missionIndex contracts. campaign_arc110 binds a native escort job/client/original carriers/load/voyage sequence; campaign_arc_ui110 provides observed offers, reserve review, follow, interception, collection and withdrawal. story_ui and the HUD expose the campaign. The released second_signature111 boundary is saved and non-advancing in110.

Native closure: VoyageJobs.finish/abandon call Campaign.campaign_job_closed110 only after the canonical payment/refund/close. Arc110 consumes the matching immediate paid record, retains its own bounded receipt and rejects stale or duplicate settlement. campaign_state_validation invokes strict native-job and Arc110 validation; unknown story gates fail closed. No operation uses the legacy contract.story flag or the eight-slot usedOffers as a twelve-operation book.

Follow alters only the player's existing water course at most once per simulated second. Manual course/Stop or invalid/lost/failed passage stops follow. NPC movement, cargo, purses and clocks are not changed to stage the mission. reserve_quote includes actual client pace, delivery route, water return to Brass and two contingency days.

Combat: battle_driver051 owns the detached30Hz authoritative data worker. tactical_runtime plans roles/targets on its existing cadence. Main owns input, commands, render/UI/audio; chart interpolates published poses. No threading or rendering rewrite in110.

Equipment/economy: workshop/workshop_comparison048 and equipment_* retain compatible sockets, original item UIDs and paid labor/stock quotes. Money transfers conserve actual purses. Expedition allowance, booked wages, escrow, inventory and fee are distinct. Existing boat art, cached sprites, short wakes and bounded effects remain unchanged.

110 acceptance:37 native gameplay/save/UI checks passed on4245483b, with two independently reviewed private images. Native child22.953s/exit0. Whole parent failed when the Windows exporter access-violated after writing the complete pack; this failure remains recorded. Separate audit validated all730 entries, matching campaign source, template code sections and PE version. The exact copied artifact subsequently passed five private headless packed startup checks with clean exit0. No repeat of37 and no whole-game quality/performance/audio claim.

Delivery evidence and tools: parent work/campaign-v110-v119-2026-11-14/v0.110, raw Test Bridge job receipts, clean package manifest and install readback. Retail excludes tests, private notes/profiles/evidence. Keep current+rollback and unique owner files. Released CHANGES are immutable; an existing authorized Sol performs post-merge notes reconciliation. Board watch remains paused.

111 candidate: campaign_arc111 owns separate work111 over native bounty/physical encounter/paid recovery/current custody. campaign_validation111 validates bounded types and native carried/closed equality. campaign_arc_ui111 reuses watch, real encounter, native recovery and contract closure. Existing110 schema stays intact. Selected verification pending.
