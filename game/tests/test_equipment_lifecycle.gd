extends SceneTree
## Unrun native fixture. Sol runs this. No pass is claimed here.
const Campaign = preload("res://scripts/campaign.gd")
const Lifecycle = preload("res://scripts/equipment_lifecycle.gd")
const Condition = preload("res://scripts/equipment_condition.gd")

var world: Dictionary
var c
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL equipment-lifecycle: " + message)

func fresh() -> void:
	var begun: Dictionary = c.new_game(31)
	check(begun.ok, "new career publishes")

func boat_by_uid(uid: String) -> Dictionary:
	for boat in c.state.get("fleet", []):
		if boat is Dictionary and str(boat.get("uid", "")) == uid:
			return boat
	for owner in c.state.get("fleetOwners", []):
		if not owner is Dictionary:
			continue
		for boat in owner.get("boats", []):
			if boat is Dictionary and str(boat.get("uid", "")) == uid:
				return boat
	return {}

func story_boat() -> Dictionary:
	for owner in c.state.get("fleetOwners", []):
		if owner is Dictionary and str(owner.get("id", "")) == "story-0" and owner.get("boats") is Array and not owner.boats.is_empty():
			return owner.boats[0]
	return {}

func engine_item(boat: Dictionary) -> Dictionary:
	for key in boat.moduleCondition.items.keys():
		var item: Dictionary = boat.moduleCondition.items[key]
		if str(item.get("location", "")) == "engine":
			return item
	return {}

func stocked_hull() -> Dictionary:
	var port: Dictionary = c.current_port()
	for id in port.get("shipIds", []):
		if int(port.shipStock.get(id, 0)) <= 0:
			continue
		var spec: Dictionary = c.hull(str(id))
		if not spec.is_empty() and int(spec.get("tier", 1)) < 5:
			return spec
	return {}

func fund_harbor() -> void:
	var port: Dictionary = c.current_port()
	c.state.coins = 500000
	port.recruits = 80
	port.workforce = 80
	port.cash = 500000

func career_shape() -> void:
	fresh()
	var starter: Dictionary = boat_by_uid("boat-1")
	var story: Dictionary = story_boat()
	check(starter.has("moduleCondition") and str(starter.moduleCondition.birthNamespace) == "boat-1", "boat-1 birth is its uid")
	check(str(story.get("uid", "")) == "legacy-story-0-0" and story.has("moduleCondition") and str(story.moduleCondition.birthNamespace) == "legacy-story-0-0", "story hull keeps the final legacy uid")
	var leaked := false
	for owner in c.state.fleetOwners:
		for boat in owner.get("boats", []):
			if str(boat.get("uid", "")) == "story-0-o0":
				leaked = true
	check(not leaked, "story-0-o0 is not assigned")

func publish_failure() -> void:
	fresh()
	var prior: Dictionary = c.state
	var coins := int(prior.coins)
	var broken: Dictionary = prior.duplicate(true)
	var story: Dictionary = {}
	for owner in broken.fleetOwners:
		if str(owner.get("id", "")) == "story-0":
			story = owner.boats[0]
	story.moduleCondition.birthNamespace = str(broken.fleet[0].moduleCondition.birthNamespace)
	var refused: Dictionary = c.publish_career(broken, prior, c.pending_days, c.events.duplicate(true))
	check(not refused.ok, "a shared birth refuses publication")
	check(is_same(c.state, prior) and int(c.state.coins) == coins, "failed publication keeps the prior career")

func workshop_request() -> void:
	fresh()
	var boat: Dictionary = c.state.fleet[0]
	var coins := int(c.state.coins)
	var bad: Dictionary = c.workshop_preview(str(boat.uid), boat.loadout, {"slots": {"nope": {"new": true}}})
	check(not bad.ok and str(bad.get("message", "")).contains("socket"), "preview receives the slot request")
	var part: Dictionary = engine_item(boat)
	var named: Dictionary = c.workshop_preview(str(boat.uid), boat.loadout, {"slots": {"engine": {"itemUid": str(part.itemUid)}}})
	check(named.ok, "the installed engine item is an exact slot")
	var refused: Dictionary = c.refit_boat(str(boat.uid), "engine", str(boat.loadout.engine), {"notAField": true})
	check(not refused.ok and int(c.state.coins) == coins, "a bad physical request does not pay")

func buy_births() -> void:
	fresh()
	fund_harbor()
	var spec: Dictionary = stocked_hull()
	check(not spec.is_empty(), "the start harbor has a stocked hull")
	if spec.is_empty():
		return
	var port: Dictionary = c.current_port()
	var nxt := "boat-%d" % int(c.state.nextUid)
	story_boat().moduleCondition.birthNamespace = nxt
	var coins := int(c.state.coins)
	var stock := int(port.shipStock.get(spec.id, 0))
	var people := int(port.workforce)
	var recruits := int(port.recruits)
	var denied: Dictionary = c.buy_boat(str(spec.id))
	check(not denied.ok and str(denied.get("message", "")).contains("birth"), "a taken birth refuses the purchase")
	check(int(c.state.coins) == coins and int(port.shipStock.get(spec.id, 0)) == stock and int(port.workforce) == people and int(port.recruits) == recruits, "refused purchase changes no coins, stock, or people")
	fresh()
	fund_harbor()
	spec = stocked_hull()
	port = c.current_port()
	coins = int(c.state.coins)
	stock = int(port.shipStock.get(spec.id, 0))
	var before := int(c.state.fleet.size())
	var bought: Dictionary = c.buy_boat(str(spec.id))
	check(bought.ok and c.state.fleet.size() == before + 1, "paid birth adds one hull")
	if not bought.ok:
		return
	var boat: Dictionary = c.state.fleet[c.state.fleet.size() - 1]
	check(boat.has("moduleCondition") and str(boat.uid) == str(boat.moduleCondition.birthNamespace), "paid hull birth is its uid")
	check(is_zero_approx(float(boat.fuel)) and is_zero_approx(float(boat.ammo)) and is_zero_approx(float(boat.supplies)), "a new hull keeps empty stores")
	check(int(c.state.coins) < coins and int(port.shipStock.get(spec.id, 0)) == stock - 1, "payment and stock move only after the birth is accepted")

func part_of(boat: Dictionary) -> Dictionary:
	return engine_item(boat)

func roundtrip() -> void:
	fresh()
	var live: Dictionary = c.state.fleet[0]
	var part: Dictionary = part_of(live)
	part.hp = 0.4
	part.cause = "salt-crack"
	part.status = "damaged"
	live.moduleCondition.legacyEngineSynced = 0.4
	live.engine = 1.0
	var serial := int(live.moduleCondition.nextItemSeq)
	var birth := str(live.moduleCondition.birthNamespace)
	var item_uid := str(part.itemUid)
	var text := JSON.stringify(c.state)
	var parsed = JSON.parse_string(text)
	var restored: Dictionary = c.restore(parsed)
	check(restored.ok, "damaged equipment survives JSON restore")
	var again: Dictionary = boat_by_uid("boat-1")
	var kept: Dictionary = part_of(again)
	check(str(again.moduleCondition.birthNamespace) == birth and str(kept.itemUid) == item_uid and int(again.moduleCondition.nextItemSeq) == serial, "birth, item uid, and serial stay")
	check(is_equal_approx(float(kept.hp), 0.4) and str(kept.cause) == "salt-crack", "part hp and cause stay")

func legacy_restore() -> void:
	fresh()
	var saved: Dictionary = c.state.duplicate(true)
	var boat: Dictionary = saved.fleet[0]
	var locker: Dictionary = boat.refitLocker.duplicate(true) if boat.get("refitLocker") is Dictionary else {}
	var hull_hp := float(boat.hp) * 0.5
	boat.hp = hull_hp
	boat.erase("moduleCondition")
	boat.engine = 0.25
	boat.refitLocker = locker
	var restored: Dictionary = c.restore(saved)
	check(restored.ok, "a legacy hull restores")
	var again: Dictionary = boat_by_uid("boat-1")
	var part: Dictionary = part_of(again)
	check(again.has("moduleCondition") and is_equal_approx(float(part.hp), 0.25), "the lower engine scalar is absorbed")
	check(float(again.hp) <= hull_hp + 0.001, "legacy restore does not raise hull hp")
	var counts: Dictionary = again.refitLocker if again.get("refitLocker") is Dictionary else {}
	var same := true
	for key in locker.keys():
		if int(counts.get(key, 0)) != int(locker[key]):
			same = false
	check(same, "locker counts stay")

func refusals() -> void:
	fresh()
	var prior: Dictionary = c.state
	var coins := int(prior.coins)
	var corrupt: Dictionary = prior.duplicate(true)
	corrupt.fleet[0].moduleCondition = {"broken": true}
	var denied: Dictionary = c.restore(corrupt)
	check(not denied.ok and is_same(c.state, prior) and int(c.state.coins) == coins, "corrupt equipment does not replace the career")
	var clash: Dictionary = prior.duplicate(true)
	var story: Dictionary = {}
	for owner in clash.fleetOwners:
		if str(owner.get("id", "")) == "story-0":
			story = owner.boats[0]
	story.moduleCondition.birthNamespace = str(clash.fleet[0].moduleCondition.birthNamespace)
	var dup: Dictionary = c.restore(clash)
	check(not dup.ok and is_same(c.state, prior) and int(c.state.coins) == coins, "a shared birth does not replace the career")

func retirement_and_wreck() -> void:
	fresh()
	var spec: Dictionary = c.hull(str(c.state.fleet[0].type))
	var nxt := "wreck-birth-1"
	var staged: Dictionary = Lifecycle.stage_birth(c.state, c.data, spec, nxt, {})
	check(staged.ok, "a detached wreck birth can be staged")
	if not staged.ok:
		return
	var saved: Dictionary = c.state.duplicate(true)
	var retired: Dictionary = saved.fleet[0].duplicate(true)
	retired.uid = "retired-hull"
	retired.sunk = true
	retired.hp = 1.0
	retired.erase("moduleCondition")
	retired.equipmentRetiredTo = "wreck-9"
	saved.fleet.append(retired)
	if not saved.get("wrecks") is Array:
		saved.wrecks = []
	saved.wrecks.append({
		"id": "wreck-9",
		"hull": str(spec.id),
		"status": "unclaimed",
		"equipmentCustody": "wreck",
		"stores": {},
		"components": {},
		"sourceModuleCondition": staged.boat.moduleCondition.duplicate(true),
		"sourceLoadout": staged.boat.loadout.duplicate(true),
		"x": 1.0,
		"y": 1.0
	})
	var restored: Dictionary = c.restore(saved)
	check(restored.ok, "retirement and an active wreck restore")
	if not restored.ok:
		print("FAIL equipment-lifecycle detail: " + str(restored.get("message", "")))
		return
	var kept: Dictionary = boat_by_uid("retired-hull")
	check(str(kept.get("equipmentRetiredTo", "")) == "wreck-9" and not kept.has("moduleCondition"), "a retirement marker is not seeded")
	var wreck: Dictionary = {}
	for row in c.state.get("wrecks", []):
		if row is Dictionary and str(row.get("id", "")) == "wreck-9":
			wreck = row
	check(wreck.has("sourceModuleCondition") and str(wreck.sourceModuleCondition.birthNamespace) == nxt, "retain keeps the wreck payload")

func preserved_adopt() -> void:
	fresh()
	var donor: Dictionary = c.state.fleet[0]
	var before: Dictionary = donor.moduleCondition.duplicate(true)
	var part: Dictionary = part_of(donor)
	part.hp = 0.35
	part.cause = "tow-shock"
	part.status = "damaged"
	donor.moduleCondition.legacyEngineSynced = 0.35
	donor.engine = 1.0
	var nxt := "boat-%d" % int(c.state.nextUid)
	var spec: Dictionary = c.hull(str(donor.type))
	var staged: Dictionary = Lifecycle.stage_birth(c.state, c.data, spec, nxt, {
		"moduleCondition": donor.moduleCondition.duplicate(true),
		"loadout": donor.loadout.duplicate(true),
		"hullHp": 12.0,
		"sourceUid": str(donor.uid)
	})
	check(staged.ok and bool(staged.fresh) == false, "preserved staging accepts the custodian")
	if not staged.ok:
		return
	donor.sunk = true
	donor.hp = 1.0
	donor.erase("moduleCondition")
	donor.equipmentRetiredTo = "wreck-held"
	var boat: Dictionary = c.add_boat(spec, 0, staged)
	var kept: Dictionary = part_of(boat)
	var old: Dictionary = {}
	for key in before.items.keys():
		if str(before.items[key].get("location", "")) == "engine":
			old = before.items[key]
	check(str(boat.uid) == nxt and str(boat.moduleCondition.birthNamespace) == "boat-1", "adoption uses the new uid and the old birth")
	check(str(kept.itemUid) == str(old.itemUid) and is_equal_approx(float(kept.hp), 0.35) and str(kept.cause) == "tow-shock", "item uid, hp, and cause stay")
	check(int(boat.moduleCondition.nextItemSeq) == int(before.nextItemSeq), "serial stays")
	check(float(boat.hp) <= 12.001 and is_zero_approx(float(boat.fuel)) and is_zero_approx(float(boat.ammo)) and is_zero_approx(float(boat.supplies)), "adoption does not heal the hull or fill stores")
	var clone: Dictionary = Lifecycle.stage_birth(c.state, c.data, spec, "boat-clone", {
		"moduleCondition": boat.moduleCondition.duplicate(true),
		"loadout": boat.loadout.duplicate(true),
		"hullHp": 12.0,
		"sourceUid": "missing-hull"
	})
	check(not clone.ok, "an unknown source uid does not authorize a clone")

func captures() -> void:
	fresh()
	var owner: Dictionary = {}
	for row in c.state.fleetOwners:
		if str(row.get("id", "")) == "story-0":
			owner = row
	var prize: Dictionary = owner.boats[0]
	var birth := str(prize.moduleCondition.birthNamespace)
	prize.captureSecured = true
	prize.supportOnly = true
	prize.needsHarborRepair = true
	prize.sunk = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var battle: Dictionary = {"ships": [c.state.fleet[0], prize], "rng": rng, "captured": [prize], "boarding": {"clock": 0.0, "next": 1, "jobs": []}}
	var settled: Dictionary = c.BoardingOps.settle(c, battle)
	check(settled.ok, "owner capture settles")
	var still := false
	for boat in owner.boats:
		if is_same(boat, prize):
			still = true
	var held := false
	for boat in c.state.fleet + c.state.get("boardingPrizes", []):
		if is_same(boat, prize):
			held = true
	check(not still and held, "the same dictionary leaves the owner and has one holder")
	check(str(prize.moduleCondition.birthNamespace) == birth, "capture keeps the birth")
	fresh()
	var spec: Dictionary = c.hull(str(c.state.fleet[0].type))
	var staged: Dictionary = Lifecycle.stage_birth(c.state, c.data, spec, "captured-birth", {})
	check(staged.ok, "prize birth stages")
	if not staged.ok:
		return
	var incoming: Dictionary = staged.boat.duplicate(true)
	incoming.uid = "boat-1"
	incoming.captureSecured = true
	incoming.supportOnly = true
	incoming.needsHarborRepair = true
	incoming.sunk = false
	incoming.crew = 0.0
	incoming.boarders = 0
	incoming.captives = 0.0
	var birth_kept := str(incoming.moduleCondition.birthNamespace)
	var item_kept := str(engine_item(incoming).itemUid)
	rng = RandomNumberGenerator.new()
	rng.seed = 8
	battle = {"ships": [c.state.fleet[0], incoming], "rng": rng, "captured": [incoming], "boarding": {"clock": 0.0, "next": 1, "jobs": []}}
	settled = c.BoardingOps.settle(c, battle)
	check(settled.ok and str(incoming.uid) == "prize-1", "a colliding hull uid becomes prize-1")
	check(str(incoming.moduleCondition.birthNamespace) == birth_kept and str(engine_item(incoming).itemUid) == item_kept, "prize rename keeps birth and the item")
	var holders := 0
	for boat in c.state.fleet + c.state.get("boardingPrizes", []):
		if boat is Dictionary and boat.has("moduleCondition"):
			for uid in Condition._uid_list(boat.moduleCondition):
				if str(uid) == item_kept:
					holders += 1
	check(holders == 1, "the prize parts have one owner")


func multiple_capture_custody() -> void:
	fresh()
	var enemies: Array = []
	for owner in c.state.fleetOwners:
		for boat in owner.get("boats", []):
			if boat is Dictionary and boat.get("moduleCondition") is Dictionary and not boat.get("sunk", false):
				enemies.append(boat)
				if enemies.size() == 2:
					break
		if enemies.size() == 2:
			break
	check(enemies.size() == 2, "two actual canonical enemy custodians exist")
	if enemies.size() != 2:
		return
	var before: Dictionary = c.state.duplicate(true)
	var result: Dictionary = Lifecycle.rehearse_captures(c.state, c.data, enemies)
	check(result.get("ok", false) and result.get("rows", []).size() == 2, "two distinct registered captures rehearse together without duplicating the first source")
	check(c.state == before, "successful multi-capture rehearsal leaves live campaign unchanged")
	var duplicate: Dictionary = Lifecycle.rehearse_captures(c.state, c.data, [enemies[0], enemies[0]])
	check(not duplicate.get("ok", false) and c.state == before, "a repeated capture is refused without live mutation")
	var spec: Dictionary = c.hull(str(enemies[0].type))
	var incoming: Dictionary = Lifecycle.stage_birth(c.state, c.data, spec, "detached-capture-birth", {})
	check(incoming.get("ok", false), "distinct detached incoming equipment birth can be staged")
	if not incoming.get("ok", false):
		return
	var detached: Dictionary = incoming.boat.duplicate(true)
	detached.uid = str(enemies[0].uid)
	var mixed: Dictionary = Lifecycle.rehearse_captures(c.state, c.data, [enemies[0], detached])
	check(mixed.get("ok", false) and mixed.get("rows", []).size() == 2 and c.state == before, "registered and detached capture with colliding hull UID keep distinct physical births")

func preserved_custodian_integrity() -> void:
	fresh()
	var donor: Dictionary = c.state.fleet[0]
	var spec: Dictionary = c.hull(str(donor.type))
	var part: Dictionary = engine_item(donor)
	var damage: Dictionary = Condition.apply_component_damage(donor.moduleCondition, {"itemUid": str(part.itemUid), "loss": 0.55, "cause": "Actual donor wear"})
	check(damage.get("ok", false), "custodian engine starts genuinely damaged")
	donor.hp = 80.0
	var payload: Dictionary = {"moduleCondition": donor.moduleCondition.duplicate(true), "loadout": donor.loadout.duplicate(true), "hullHp": 80.0, "sourceUid": str(donor.uid)}
	var before: Dictionary = c.state.duplicate(true)
	check(Lifecycle.stage_birth(c.state, c.data, spec, "preserved-clean", payload).get("ok", false), "exact damaged donor payload is accepted without trusting legacy engine mirror")
	for edit in ["part-hp", "cause", "serial", "hull-hp", "both-custodians"]:
		var forged: Dictionary = payload.duplicate(true)
		if edit == "part-hp":
			forged.moduleCondition.items[str(part.itemUid)].hp = 0.65
			forged.moduleCondition.legacyEngineSynced = 0.65
		elif edit == "cause":
			forged.moduleCondition.items[str(part.itemUid)].cause = "Forged provenance"
		elif edit == "serial":
			forged.moduleCondition.nextItemSeq = int(forged.moduleCondition.nextItemSeq) + 1
		elif edit == "hull-hp":
			forged.hullHp = 100.0
		else:
			forged.sourceWreckId = "ambiguous-wreck"
		check(Condition._records(forged.moduleCondition).get("ok", false), "forged %s is structurally valid, so structural validation cannot mask custody proof" % edit)
		var refused: Dictionary = Lifecycle.stage_birth(c.state, c.data, spec, "preserved-forged", forged)
		check(not refused.get("ok", false) and c.state == before, "preserved %s cannot alter the actual custodian payload" % edit)
	var detached: Dictionary = Lifecycle.stage_birth(c.state, c.data, spec, "unowned-detached-birth", {})
	check(detached.get("ok", false), "disjoint detached payload is structurally available")
	if detached.get("ok", false):
		var unowned: Dictionary = {"moduleCondition": detached.boat.moduleCondition.duplicate(true), "loadout": detached.boat.loadout.duplicate(true), "hullHp": 12.0}
		check(not Lifecycle.stage_birth(c.state, c.data, spec, "unowned-adopt", unowned).get("ok", false) and c.state == before, "public preserved adoption requires an explicit actual custodian")

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		print("FAIL equipment-lifecycle: fixture is headless only")
		quit(1)
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	career_shape()
	publish_failure()
	workshop_request()
	buy_births()
	roundtrip()
	legacy_restore()
	refusals()
	retirement_and_wreck()
	preserved_adopt()
	captures()
	multiple_capture_custody()
	preserved_custodian_integrity()
	print("Equipment lifecycle: %d checks, %d failures" % [checks, failures])
	print("NOTE equipment-lifecycle: this process was not a claimed pass.")
	quit(0 if failures == 0 else 1)
