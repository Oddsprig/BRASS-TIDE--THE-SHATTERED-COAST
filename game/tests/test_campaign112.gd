extends SceneTree
## tests/test_campaign112.gd
##
## SOURCE-ONLY HANDOFF: not executed by this author.
## Root must run this through Test Bridge with an external 28-second cap.
## The internal budget starts before Preview construction and is 25 seconds.
##
## Declared private fixture:
## - Stock career, seed 123.
## - Native main-story start, followed by an explicitly declared 112 boundary.
##   No earned 110/111 completion claim.
## - Original Kelp merchant and player initially placed together on the final
##   200 units of that merchant's EXISTING native water course.
## - Quiet branch uses actual campaign steps, docking, sale and fee closure.
## - Tactical branch uses original native fleets and Battle.update.
##   A declared short water-safe reference exit bounds CPU work; native deployment is unchanged.
## - No supplied positive result, damage, HP, boats, coins or cargo.
## - Not a full voyage, campaign playthrough, FPS test or store screenshot.

class Preview extends "res://scripts/main.gd":
	const Check112 = preload("res://scripts/campaign_validation112.gd")
	const LIMIT112_MS: int = 25000

	var began112: int = 0
	var output112: String = ""
	var finished112: bool = false
	var client_id112: String = ""
	var enemy_id112: String = ""
	var job_id112: String = ""
	var original_uids112: Array = []
	var proof112: Dictionary = {
		"checks": [],
		"fixture": "Controlled private v112 fixture; declared story boundary, late campaign leg and authored short reference exit; not an earned campaign or store capture",
		"supplied": false,
		"supplied_means": "No supplied positive outcome, damage, HP, boats, coins or cargo. The empty-won negative API probe is identified separately.",
		"owner_profile_used": false,
		"earned_111_claim": false,
		"full_voyage_claim": false,
		"external_wall_cap_seconds": 28,
		"internal_budget_ms": LIMIT112_MS,
		"declarations": [],
	}

	func _ready() -> void:
		output112 = OS.get_environment("GAME_TEST_ARTIFACTS").replace("\\", "/").path_join("campaign112")
		if OS.get_environment("GAME_TEST_ARTIFACTS").is_empty():
			push_error("CAMPAIGN112 requires a private GAME_TEST_ARTIFACTS directory.")
			get_tree().quit(2)
			return
		if DirAccess.make_dir_recursive_absolute(output112) != OK:
			push_error("CAMPAIGN112 could not create its private artifact directory.")
			get_tree().quit(2)
			return
		save_directory = output112.path_join("saves")
		if DirAccess.make_dir_recursive_absolute(save_directory) != OK:
			push_error("CAMPAIGN112 could not create its private save directory.")
			get_tree().quit(2)
			return
		qa_ocean066 = true
		super._ready()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		run112.call_deferred()

	func elapsed112() -> int:
		return Time.get_ticks_msec() - began112

	func json112(name: String, value) -> bool:
		var file = FileAccess.open(output112.path_join(name), FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(JSON.stringify(value, "\t"))
		file.flush()
		file.close()
		return FileAccess.file_exists(output112.path_join(name))

	func snapshot112() -> Dictionary:
		var value = JSON.parse_string(JSON.stringify(core.state))
		return value if value is Dictionary else {}

	func restore112(value: Dictionary) -> bool:
		# Detached JSON input prevents a probe from mutating its retained checkpoint.
		var detached = JSON.parse_string(JSON.stringify(value))
		if not detached is Dictionary:
			return false
		var restored: Dictionary = core.restore(detached)
		if not restored.get("ok", false):
			proof112.last_restore_error = str(restored.get("message", "Restore refused without a message."))
			print("CAMPAIGN112_RESTORE_REFUSED " + proof112.last_restore_error)
		return bool(restored.get("ok", false))

	func same112(a, b) -> bool:
		if (a is int or a is float) and (b is int or b is float):
			return float(a) == float(b)
		if a is Dictionary and b is Dictionary:
			if a.size() != b.size():
				return false
			for key in a:
				if not b.has(key) or not same112(a[key], b[key]):
					return false
			return true
		if a is Array and b is Array:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not same112(a[i], b[i]):
					return false
			return true
		return typeof(a) == typeof(b) and a == b

	func conserved112() -> bool:
		return core.Money.total(core.state) == int(core.state.coinSupply)

	func finish112(passed: bool) -> void:
		if finished112:
			return
		finished112 = true
		proof112.passed = passed
		proof112.elapsed_ms = elapsed112()
		proof112.check_count = proof112.checks.size()
		if not core.state.is_empty():
			json112("final-state.json", snapshot112())
			proof112.final_state_sha256 = FileAccess.get_sha256(output112.path_join("final-state.json"))
		var saved: bool = json112("evidence.json", proof112)
		if passed and saved:
			print("CAMPAIGN112_DONE checks=%d elapsed_ms=%d controlled_private_fixture=true" % [
				proof112.checks.size(), elapsed112()
			])
			get_tree().quit(0)
		else:
			print("CAMPAIGN112_FAIL checks=%d elapsed_ms=%d" % [
				proof112.checks.size(), elapsed112()
			])
			get_tree().quit(2)

	func verify112(condition: bool, message: String) -> bool:
		if finished112:
			return false
		proof112.checks.append({"name": message, "passed": condition})
		if not condition:
			push_error("CAMPAIGN112 " + message)
			finish112(false)
			return false
		return true

	func budget112(phase: String) -> bool:
		if finished112:
			return false
		if elapsed112() >= LIMIT112_MS:
			return verify112(false, "Bounded native fixture exceeded its internal budget during " + phase)
		return true

	func advance112(dt: float) -> bool:
		if not budget112("campaign stepping"):
			return false
		core.step(dt)
		sync_economy()
		for event in core.pop_events():
			if str(event.get("kind", "")) in ["encounter", "ocean_encounter066", "defeat"]:
				proof112.interruption = event.duplicate(true)
				return verify112(false, "Quiet native branch encountered an actual interruption; no supplied victory")
		if not conserved112():
			return verify112(false, "Native campaign step failed coin conservation")
		return true

	func dock112() -> bool:
		var target: String=str(core.Arc112.work(core).targetPort)
		if str(core.current_port().get("id",""))==target:return true
		var plotted: Dictionary=core.chart_course(core.port(target),target)
		if not plotted.get("ok",false):return verify112(false,"Native water course to the report harbor is unavailable")
		var sailed: float=0.0
		while str(core.current_port().get("id",""))!=target and sailed<90:
			if not advance112(0.25):return false
			sailed+=0.25
		return verify112(str(core.current_port().get("id",""))==target,"Native water travel reached the actual report harbor")

	func native_job112() -> Dictionary:
		return core.VoyageJobs._find(core.state, job_id112)

	func client112() -> Dictionary:
		return core.fleet_owner(client_id112)

	func patrol112() -> Dictionary:
		return core.NavalAI._find_patrol(core.state, client_id112)

	func choose_client112() -> Dictionary:
		for patrol in core.state.patrols:
			if not patrol.get("active", false) or patrol.get("holding", false):
				continue
			if str(patrol.get("from", "")) != "kelp_reach":
				continue
			if float(patrol.get("courseLength", 0)) <= 240.0 or patrol.get("course", []).size() < 2:
				continue
			var owner: Dictionary = core.fleet_owner(str(patrol.id))
			if owner.is_empty() or not owner.get("active", false) or str(owner.get("kind", "")) != "trader":
				continue
			var plan: Dictionary = core.EscortOps._load_plan(core, owner)
			if plan.get("ok", false):
				return {"owner": owner, "patrol": patrol}
		return {}

	func choose_enemy112() -> Dictionary:
		for patrol in core.state.patrols:
			var owner: Dictionary = core.fleet_owner(str(patrol.id))
			if owner.is_empty() or not owner.get("active", false) or str(owner.get("kind", "")) != "raider":
				continue
			if owner.boats.any(func(boat): return not boat.get("sunk", false)):
				return owner
		return {}

	func context112() -> Dictionary:
		return {
			"kind": "escort",
			"id": enemy_id112,
			"ownerId": enemy_id112,
			"allyOwnerId": client_id112,
			"escortEvent": job_id112,
			"escortJobId": job_id112,
			"name": "Controlled private native112 escort encounter",
		}

	func all_arrived112() -> bool:
		var w: Dictionary = core.Arc112.work(core)
		if w.is_empty() or w.outcomes.size() != original_uids112.size():
			return false
		for uid in original_uids112:
			if str(w.outcomes.get(uid, {}).get("fate", "")) != "arrived":
				return false
		return true

	func left_harbor112() -> bool:
		var owner: Dictionary = client112()
		var patrol: Dictionary = patrol112()
		var w: Dictionary = core.Arc112.work(core)
		var dock: Dictionary = core.port(str(w.targetPort))
		return not owner.is_empty() and not patrol.is_empty() and not dock.is_empty() \
			and str(owner.get("atPort", "")) != str(w.targetPort) \
			and not patrol.get("holding", true) and core.distance(patrol, dock) >= 40.0

	func picture112() -> void:
		if not budget112("journal capture"):
			return
		chart.step(0)
		ui.update_hud()
		ui.StoryUI.open(ui)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not budget112("journal capture"):
			return
		var image = get_viewport().get_texture().get_image()
		verify112(image != null and image.save_png(output112.path_join("withdrawal.png")) == OK,
			"Saved the actual controlled112 account journal, not store media")

	func run112() -> void:
		if not budget112("startup"):
			return

		var fresh: Dictionary = core.new_game(123)
		mode = "campaign"
		paused = true
		ui.close_modal()
		ui.build_hud()
		chart.center_camera()
		if not verify112(fresh.get("ok", false) and int(core.state.coins) == 15000
			and core.state.fleet.size() == 1 and int(core.crew_count()) == 5 and conserved112(),
			"Stock native career retains its original boat, five crew and15000coins"):
			return

		core.Contacts.visit(core.state, core.current_port(), core.state.day)
		var started: Dictionary = core.StoryOps.start(core, core.Arc110.ID)
		if started.get("ok", false):
			# Declared precondition, not earned chapter111 progress.
			core.Arc110.record(core).stage = "withdrawal_work112"
		proof112.declarations.append("Native story start at Brass; stage explicitly declared withdrawal_work112, without earned111 flags or work.")
		if not verify112(started.get("ok", false)
			and str(core.Arc110.record(core).stage) == "withdrawal_work112",
			"Native story starts before the explicitly declared112 fixture boundary"):
			return

		var selected: Dictionary = choose_client112()
		var enemy: Dictionary = choose_enemy112()
		var terms: Dictionary = {}
		if not selected.is_empty() and not enemy.is_empty():
			var owner: Dictionary = selected.owner
			var patrol: Dictionary = selected.patrol
			client_id112 = str(owner.id)
			enemy_id112 = str(enemy.id)
			var old_progress: float = float(patrol.progress)
			patrol.progress = 1.0 - 200.0 / float(patrol.courseLength)
			core.place_patrol(patrol)
			owner.progress = patrol.progress
			core.state.position.x = float(patrol.x)
			core.state.position.y = float(patrol.y)
			core.NavalAI.observe(core.state)
			proof112.declarations.append({
				"kind": "controlled_late_campaign_leg",
				"ownerId": client_id112,
				"fromPort": str(patrol.from),
				"targetPort": str(patrol.to),
				"existingCourseLength": float(patrol.courseLength),
				"oldProgress": old_progress,
				"initialProgress": float(patrol.progress),
				"remainingCourseUnits": 200.0,
				"playerInitialPosition": core.state.position.duplicate(true),
				"no_full_voyage_claim": true,
			})
			for offer in core.Arc112.offers(core):
				if str(offer.get("ownerId", "")) == client_id112:
					terms = offer.duplicate(true)
					break
		if not verify112(not terms.is_empty() and not enemy.is_empty(),
			"An original loaded Kelp merchant on an existing water course has an actual funded native offer"):
			return

		var wrong: Dictionary = terms.duplicate(true)
		wrong.reward = int(wrong.reward) + 1
		var jobs_before: int = core.state.voyageJobs.size()
		var coins_before: int = int(core.state.coins)
		var refused: Dictionary = core.Arc112.accept(core, wrong)
		if not verify112(not refused.get("ok", false)
			and core.state.voyageJobs.size() == jobs_before
			and int(core.state.coins) == coins_before and core.Arc112.work(core).is_empty()
			and conserved112(),
			"Changed quotation refuses without creating a job, binding or player payment"):
			return

		var accepted: Dictionary = core.Arc112.accept(core, terms)
		var w: Dictionary = core.Arc112.work(core)
		if not w.is_empty():
			job_id112 = str(w.jobId)
			original_uids112 = w.carrierUids.duplicate()
		var bound_job: Dictionary = native_job112()
		if not verify112(accepted.get("ok", false) and not original_uids112.is_empty()
			and not bound_job.is_empty() and str(bound_job.kind) == "escort"
			and str(w.ownerId) == client_id112
			and same112(w.carrierUids, bound_job.escort.carrierUids)
			and same112(w.carrierCargo, bound_job.escort.carrierCargo)
			and conserved112(),
			"Native acceptance funds the fee and binds the actual original carrier IDs and cargo"):
			return

		var active: Dictionary = snapshot112()
		# Compare the actual serialized checkpoint with its restored value. Raw
		# pre-serialization route coordinates can differ at JSON's last digit.
		var active_work: Dictionary = active.stories.chains[core.Arc110.ID].work112.duplicate(true)
		var active_job: Dictionary = {}
		for saved_job in active.voyageJobs:
			if str(saved_job.id) == job_id112:
				active_job = saved_job.duplicate(true)
				break
		if not verify112(restore112(active)
			and same112(core.Arc112.work(core), active_work)
			and same112(native_job112(), active_job) and conserved112(),
			"Active binding and native escrow survive detached JSON and full native restore"):
			return

		var unknown_refused: bool = not core.StoryOps.choose(core, core.Arc110.ID, "report_withdrawal112").get("ok", false)
		var abandoned_unknown: Dictionary = core.VoyageJobs.abandon(core, job_id112)
		w = core.Arc112.work(core)
		var still_unknown: bool = str(w.status) == "withdrawn" \
			and int(core.Arc112.counts(core).unresolved) == original_uids112.size() \
			and not core.StoryOps.choose(core, core.Arc110.ID, "report_withdrawal112").get("ok", false)
		var impossible: Dictionary = snapshot112()
		impossible.stories.chains[core.Arc110.ID].work112.reported = true
		impossible.stories.chains[core.Arc110.ID].work112.resolution = "clear"
		impossible.stories.chains[core.Arc110.ID].stage = "wren_account112"
		var invalid_message: String = Check112.validate(impossible)
		var invented_refused: bool = not invalid_message.is_empty() and not core.restore(impossible).get("ok", false)
		var unknown_restored: bool = restore112(active)
		proof112.unknown_report_rejection = invalid_message
		if not verify112(unknown_refused and abandoned_unknown.get("ok", false)
			and still_unknown and invented_refused and unknown_restored and conserved112(),
			"Unknown boats remain unreportable after native refund; invented terminal completion cannot restore"):
			return

		# Intentionally supplied EMPTY legacy result is a negative probe only.
		# It is never retained as positive physical evidence.
		core.battle_settled("won", [], context112())
		var empty_won_refused: bool = core.Arc112.work(core).outcomes.is_empty() \
			and not core.Arc112.choice_gate(core, "report_withdrawal112").get("ok", false)
		proof112.empty_won_probe = {
			"negative_only": true,
			"physical_battle_supplied": false,
			"progress_granted": not empty_won_refused,
		}
		var empty_restored: bool = restore112(active)
		if not verify112(empty_won_refused and empty_restored and conserved112(),
			"Generic empty won grants no original-carrier outcome and its private probe rolls back"):
			return

		# Quiet physical-arrival branch.
		# Set the ordinary chapter follow request, then use shipped core.step.
		core.Arc112.work(core).follow = true
		proof112.declarations.append("Quiet branch sets the chapter follow request directly; it does not claim UI input coverage.")
		var quiet_simulated: float = 0.0
		while not all_arrived112() and quiet_simulated < 180.0:
			if not advance112(0.25):
				return
			quiet_simulated += 0.25
		w = core.Arc112.work(core)
		var arrival: Dictionary = w.arrival.duplicate(true)
		var quiet_unpaid_report_refused: bool = not core.StoryOps.choose(core, core.Arc110.ID, "report_withdrawal112").get("ok", false)
		if not verify112(all_arrived112() and arrival.get("witnessed", false)
			and int(arrival.get("sequence", -1)) == 0 and str(arrival.get("source", "")).is_empty()
			and float(arrival.get("deliveredQty", 0)) + 0.000001 >= float(w.tradeQty)
			and str(w.status) == "carried" and quiet_unpaid_report_refused and conserved112(),
			"Actual witnessed quiet docking and sale credit arrived while the separate open fee still blocks report"):
			return

		if not dock112():return
		core.stop_sailing()
		var departure_simulated: float = 0.0
		while not left_harbor112() and departure_simulated < 360.0:
			if not advance112(0.5):
				return
			departure_simulated += 0.5
		if not verify112(left_harbor112()
			and same112(core.Arc112.work(core).arrival, arrival)
			and all_arrived112() and conserved112(),
			"Merchant actually leaves harbor without erasing its retained witnessed docking"):
			return

		# Declared knowledge-only branch: the actual docking receipt remains,
		# but its witness flag/outcome projection is absent after lost contact.
		var seen_dock: Dictionary=snapshot112()
		core.Arc112.work(core).outcomes={}
		core.Arc112.work(core).arrival.witnessed=false
		var record_lookup: Dictionary=core.Arc112.check_arrival_record(core)
		var record_restored: bool=restore112(snapshot112())
		if not verify112(record_lookup.get("ok",false) and record_restored and all_arrived112() and conserved112(),"Actual harbor record resolves lost contact without a witness or invented docking"):return
		if not restore112(seen_dock):
			verify112(false,"Witnessed docking checkpoint did not restore");return

		var quiet_payment: Dictionary = core.settle_voyage_job(job_id112)
		w = core.Arc112.work(core)
		if not verify112(quiet_payment.get("ok", false) and str(w.status) == "paid"
			and int(w.payment) == int(w.reward) and all_arrived112()
			and core.state.doneVoyageJobs.has(job_id112) and conserved112(),
			"Native fee collection succeeds after merchant departure and preserves the arrival account"):
			return

		var quiet_report: Dictionary = core.StoryOps.choose(core, core.Arc110.ID, "report_withdrawal112")
		var quiet_checkpoint: Dictionary = snapshot112()
		var quiet_saved: bool = json112("quiet-checkpoint.json", quiet_checkpoint)
		var quiet_reloaded: bool = quiet_saved and restore112(
			JSON.parse_string(FileAccess.get_file_as_string(output112.path_join("quiet-checkpoint.json"))))
		w = core.Arc112.work(core)
		proof112.quiet = {
			"campaignSimulatedSeconds": quiet_simulated,
			"departureSimulatedSeconds": departure_simulated,
			"arrival": arrival,
			"payment": quiet_payment.duplicate(true),
			"work": w.duplicate(true),
			"checkpoint": "quiet-checkpoint.json",
		}
		if not verify112(quiet_report.get("ok", false) and quiet_reloaded
			and w.reported and str(w.resolution) == "clear"
			and str(core.Arc110.record(core).stage) == "wren_account112" and conserved112(),
			"Explicit native quiet report records Clear and its private checkpoint restores"):
			return

		# Knowledge-only probe: erase the observations, never invent a physical
		# result. An ended passage can be reported honestly as unconfirmed.
		core.Arc110.record(core).stage = "withdrawal_work112"
		w = core.Arc112.work(core)
		w.reported = false
		w.resolution = ""
		w.outcomes = {}
		w.arrival = {}
		var unknown_coins: int = int(core.state.coins)
		var unknown_report: Dictionary = core.StoryOps.choose(core, core.Arc110.ID, "report_withdrawal112")
		if not verify112(unknown_report.get("ok", false) and w.reported and w.resolution == "unconfirmed"
			and core.Arc112.counts(core).unresolved == original_uids112.size()
			and Check112.validate(core.state).is_empty() and int(core.state.coins) == unknown_coins and conserved112(),
			"Ended passage permits an explicit unconfirmed report without invented arrivals or extra payment"):
			return

		if not verify112(restore112(active)
			and same112(core.Arc112.work(core), active_work)
			and same112(native_job112(), active_job) and conserved112(),
			"Tactical branch restores the original active pre-arrival binding without quiet progress"):
			return

		# Declared post-public-start contract flags mirror EscortOps.start.
		# This does not claim execution of its threaded UI start path.
		var client: Dictionary = client112()
		enemy = core.fleet_owner(enemy_id112)
		var allies: Array = client.boats.filter(func(boat): return not boat.get("sunk", false))
		var enemies: Array = enemy.boats.filter(func(boat): return not boat.get("sunk", false))
		var enemy_specs: Array = enemies.map(func(boat): return boat.spec.duplicate(true))
		var cargo_before: Dictionary = client.cargo.duplicate(true)
		var trade_before: float = float(client.tradeCargo)
		var mission: Dictionary = core.EscortOps._mission(core, client, "escort")
		mission.allyUids = allies.map(func(boat): return str(boat.uid))
		# Authored reference exit; actors keep their stock native deployment.
		# This proves physical exit logic, not stock arena geography or balance.
		mission.exit.x=740.0
		mission.exit.y=850.0
		mission.exit.radius=140.0
		var job: Dictionary = native_job112()
		job.escort.battlePending = true
		job.escort.interceptions = int(job.escort.get("interceptions", 0)) + 1
		proof112.declarations.append("Tactical branch declares only the native post-start battlePending/interceptions flags; no threaded UI-start claim.")
		var physical: Dictionary = Battle.create({
			"fleet": core.active_fleet() + allies,
			"enemyFleet": enemies,
			"mission": mission,
			"seed": 112,
			"islands": [],
		})
		physical.chartPosition = core.state.position.duplicate(true)
		physical.world064 = core.world_location064().world064
		var exit_value = physical.get("mission", {}).get("exit", {})
		var exit_valid: bool = exit_value is Dictionary and exit_value.has("x") and exit_value.has("y")
		if not verify112(str(physical.get("startError", "")).is_empty()
			and physical.get("result") == null and physical.has("convoy")
			and same112(physical.convoy.uids, original_uids112) and exit_valid and conserved112(),
			"Native Battle deploys original player, client carriers and raider with the actual convoy mission"):
			Battle.update(physical, 0)
			return

		var starts: Dictionary={}
		for uid in original_uids112:
			var actor: Dictionary=physical.convoy.actors.get(uid,{})
			if not actor.is_empty():starts[uid]={"x":float(actor.x),"y":float(actor.y)}
		proof112.declarations.append({"kind":"authored_short_reference_exit","exit":exit_value.duplicate(true),"native_deployment_unchanged":true,"no_stock_arena_or_balance_claim":true})

		while physical.result == null and float(physical.time) < 180.0 and elapsed112() < 23000:
			Battle.update(physical, 1.0 / 30.0)
		Battle.update(physical, 0) # End native equipment/cache borrows before settlement.

		var moved_and_escaped: bool = starts.size() == original_uids112.size()
		var physical_carriers: Array = []
		for uid in original_uids112:
			var actor: Dictionary = physical.convoy.actors.get(uid, {})
			var initial: Dictionary = starts.get(uid, {})
			var moved: bool = not actor.is_empty() and not initial.is_empty() \
				and absf(float(actor.x) - float(initial.x)) + absf(float(actor.y) - float(initial.y)) > 0.01
			var escaped: bool = not actor.is_empty() and actor.get("battleEscaped", false) and not actor.get("sunk", false)
			moved_and_escaped = moved_and_escaped and moved and escaped
			physical_carriers.append({
				"uid": str(uid),
				"movedByNativeUpdate": moved,
				"nativeBattleEscaped": escaped,
				"finalPosition": {"x": actor.get("x"), "y": actor.get("y")},
			})
		proof112.reference_combat = {
			"result": physical.result,
			"simulatedSeconds": physical.time,
			"carriers": physical_carriers,
			"actual_native_updates": true,
			"supplied_positive_result": false,
		}
		if not verify112(physical.result == "won" and moved_and_escaped and elapsed112() < 23000,
			"Native Battle.update physically moves every original carrier into its actual exit"):
			return

		var context: Dictionary = context112()
		var report: Dictionary = core.battle_settled(str(physical.result), enemy_specs, context, physical)
		w = core.Arc112.work(core)
		var sequence: int = int(physical.get("campaignSequence111", -1))
		var counts: Dictionary = core.Arc112.counts(core)
		if not verify112(sequence > int(w.battleFloor) and int(w.lastSequence) == sequence
			and int(counts.escaped) == original_uids112.size() and int(counts.arrived) == 0
			and int(counts.unresolved) == 0 and same112(client112().cargo, cargo_before)
			and float(client112().tradeCargo) == trade_before and conserved112(),
			"Canonical physical settlement records fresh original escapes and conserves cargo and coins"):
			return

		proof112.reference_combat.sequence = sequence
		if not verify112(core.Arc112.delivery_pending(core) and core.Arc112.protection_gate(core).get("ok", false),
			"Successful first exit keeps protection available for the still-carried original delivery"):
			return
		proof112.reference_combat.outcomes = w.outcomes.duplicate(true)
		proof112.reference_combat.cargoBefore = cargo_before
		proof112.reference_combat.cargoAfter = client112().cargo.duplicate(true)
		var after_physical: Dictionary = snapshot112()
		var retained_work: Dictionary = after_physical.stories.chains[core.Arc110.ID].work112.duplicate(true)
		var retained_coins: int = int(core.state.coins)
		var retained_sequence: int = int(core.state.battleSeq)
		core.battle_settled(str(physical.result), enemy_specs, context, physical)
		if not verify112(same112(core.Arc112.work(core), retained_work)
			and int(core.state.coins) == retained_coins and int(core.state.battleSeq) == retained_sequence
			and same112(client112().cargo, cargo_before) and conserved112(),
			"Cached settlement repeats neither payment, encounter sequence nor original-carrier evidence"):
			return

		# Private rejection probes alter only the chapter evidence book, then
		# restore the actual post-settlement native checkpoint.
		w = core.Arc112.work(core)
		w.outcomes = {}
		w.arrival = {}
		w.battleFloor = sequence
		w.lastSequence = sequence
		w.lastSource = ""
		core.state.battleSeq = maxi(int(core.state.battleSeq), sequence + 1)
		core.Arc112.after_battle(core, str(physical.result), context, physical, report)
		var stale_refused: bool = w.outcomes.is_empty() and int(w.lastSequence) == sequence and str(w.lastSource).is_empty()
		var stale_restored: bool = restore112(after_physical)
		if not verify112(stale_refused and stale_restored and conserved112(),
			"Advancing the global counter cannot freshen a physical encounter at the bound stale floor"):
			return

		w = core.Arc112.work(core)
		w.outcomes = {}
		w.arrival = {}
		w.lastSequence = int(active_work.battleFloor)
		w.lastSource = ""
		var unrelated: Dictionary = context.duplicate(true)
		unrelated.allyOwnerId = enemy_id112
		core.Arc112.after_battle(core, str(physical.result), unrelated, physical, report)
		var unrelated_refused: bool = w.outcomes.is_empty() \
			and int(w.lastSequence) == int(active_work.battleFloor) and str(w.lastSource).is_empty()
		var unrelated_restored: bool = restore112(after_physical)
		if not verify112(unrelated_refused and unrelated_restored
			and same112(core.Arc112.work(core), retained_work) and conserved112(),
			"An unrelated owner context cannot attach the actual physical receipt to this binding"):
			return

		if not dock112():return
		var before_withdrawal: Dictionary = native_job112().duplicate(true)
		var physical_outcomes: Dictionary = core.Arc112.work(core).outcomes.duplicate(true)
		var withdrawal: Dictionary = core.VoyageJobs.abandon(core, job_id112)
		w = core.Arc112.work(core)
		proof112.withdrawal = {
			"nativeJobBefore": before_withdrawal,
			"nativeResult": withdrawal.duplicate(true),
			"closure": w.closure.duplicate(true),
			"coinTotal": core.Money.total(core.state),
			"coinSupply": int(core.state.coinSupply),
		}
		if not verify112(withdrawal.get("ok", false) and str(w.status) == "withdrawn"
			and int(w.payment) == 0 and native_job112().is_empty()
			and core.state.doneVoyageJobs.has(job_id112)
			and same112(w.outcomes, physical_outcomes) and not w.reported
			and core.Arc112.choice_gate(core, "report_withdrawal112").get("ok", false)
			and conserved112(),
			"Ordinary native withdrawal closes the escrow with conserved coins while retaining physical escapes"):
			return

		var reported: Dictionary = core.StoryOps.choose(core, core.Arc110.ID, "report_withdrawal112")
		w = core.Arc112.work(core)
		if not verify112(reported.get("ok", false) and w.reported and not w.follow
			and str(w.resolution) == "clear" and str(w.status) == "withdrawn"
			and str(core.Arc110.record(core).stage) == "wren_account112"
			and same112(w.outcomes, physical_outcomes) and conserved112(),
			"Explicit native report records Clear independently of the withdrawn fee and stops at Wren's account"):
			return

		await picture112()
		if finished112:
			return

		var boundary: Dictionary = core.StoryOps.choose(core, core.Arc110.ID, "hear_useful_enemy112")
		var boundary_work: Dictionary = core.Arc112.work(core).duplicate(true)
		var repeated_boundary: Dictionary = core.StoryOps.choose(core, core.Arc110.ID, "hear_useful_enemy112")
		var repeated_cover: Dictionary = core.StoryOps.choose(core, core.Arc110.ID, "cover_withdrawal112")
		if not verify112(boundary.get("ok", false)
			and str(core.Arc110.record(core).stage) == "useful_enemy113"
			and not repeated_boundary.get("ok", false) and not repeated_cover.get("ok", false)
			and same112(core.Arc112.work(core), boundary_work) and conserved112(),
			"Native story transition reaches the unreleased113 boundary and refuses earlier chapter choices"):
			return

		if not budget112("final state"):
			return
		var final_snapshot: Dictionary = snapshot112()
		boundary_work = final_snapshot.stories.chains[core.Arc110.ID].work112.duplicate(true)
		var final_written: bool = json112("final-state.json", final_snapshot)
		var final_read = JSON.parse_string(FileAccess.get_file_as_string(output112.path_join("final-state.json"))) if final_written else null
		var final_read_ok: bool = final_read is Dictionary and same112(final_read, final_snapshot)
		var final_restored: bool = final_read_ok and restore112(final_read)
		if not verify112(final_written and final_read_ok and final_restored
			and same112(core.Arc112.work(core), boundary_work)
			and str(core.Arc110.record(core).stage) == "useful_enemy113"
			and native_job112().is_empty() and conserved112() and elapsed112() < LIMIT112_MS,
			"Final actual native state writes, reads and restores with the terminal carrier book, fee closure and coin conservation"):
			return

		proof112.final = {
			"stage": str(core.Arc110.record(core).stage),
			"work": core.Arc112.work(core).duplicate(true),
			"counts": core.Arc112.counts(core).duplicate(true),
			"coinTotal": core.Money.total(core.state),
			"coinSupply": int(core.state.coinSupply),
			"restore_scope": "Full native restore accepted; exact work112, terminal stage, closed job and coin conservation checked.",
			"artifacts": ["withdrawal.png", "evidence.json", "final-state.json", "quiet-checkpoint.json"],
			"not_claimed": ["earned110/111", "full campaign", "full outward voyage", "all partial/loss combinations", "rendered FPS", "store media"],
		}
		finish112(true)


func _initialize() -> void:
	var began: int = Time.get_ticks_msec()
	var preview = Preview.new()
	preview.began112 = began
	root.add_child(preview)
