extends SceneTree
## Unrun headless native integration fixture for v0.031 equipment UI, controller, and part picker.
## Exercises EquipmentController, EquipmentUI, EquipmentPicker, RefitUI, WorkshopUI, and Interface
## against real Campaign, EquipmentCondition, EquipmentRecords, EquipmentDamage, Damage, Refit, and FleetWorkshop.
## Not registered in tools/check_game.py. Sol owns the sole engine lease and runs native checks.

const Core = preload("res://scripts/equipment_condition.gd")
const Records = preload("res://scripts/equipment_records.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const Damage = preload("res://scripts/damage.gd")
const Refit = preload("res://scripts/refit.gd")
const Workshop = preload("res://scripts/fleet_workshop.gd")
const EquipmentUI = preload("res://scripts/equipment_ui.gd")
const EquipmentController = preload("res://scripts/equipment_ui_controller.gd")
const EquipmentPicker = preload("res://scripts/equipment_picker.gd")
const RefitUI = preload("res://scripts/refit_ui.gd")
const WorkshopUI = preload("res://scripts/workshop_ui.gd")

var game
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL equipment UI integration: " + message)

func descendants(node: Node) -> Array:
	if node == null:
		return []
	var result: Array = [node]
	for child in node.get_children():
		result.append_array(descendants(child))
	return result

func visible_text() -> String:
	var text: Array[String] = []
	for node in descendants(game.ui.overlay):
		if node is Label or node is Button:
			text.append(str(node.text))
	return "\n".join(text)

func find_button(prefix: String) -> Button:
	for node in descendants(game.ui.overlay):
		if node is Button and str(node.text).begins_with(prefix):
			return node
	return null

func find_buttons(prefix: String) -> Array:
	var list: Array = []
	for node in descendants(game.ui.overlay):
		if node is Button and str(node.text).begins_with(prefix):
			list.append(node)
	return list

func press(prefix: String) -> bool:
	var button: Button = find_button(prefix)
	check(button != null and not button.disabled, "enabled button exists: " + prefix)
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true

func located_item(condition: Dictionary, location: String) -> Dictionary:
	if not (condition.get("items") is Dictionary):
		return {}
	for uid in condition.items.keys():
		var item: Dictionary = condition.items[uid]
		if str(item.get("location", "")) == location:
			return item
	return {}

func acquire_locker_spare(boat: Dictionary, family: String, type_id: String, hp: float, cause: String = "") -> String:
	var base: Dictionary = game.core.hull(str(boat.get("type", "")))
	var mount_count: int = Refit.hardpoints(base).size()
	var res: Dictionary = Core.accept_acquired_item(boat.moduleCondition, {
		"acquired": true,
		"family": family,
		"typeId": type_id,
		"originHullType": str(boat.get("type", "")),
		"location": "locker",
		"hp": hp,
		"cause": cause,
		"mountCount": mount_count,
		"hullType": str(boat.get("type", "")),
		"knownUids": []
	})
	check(res.get("ok", false), "acquired locker spare %s (%s)" % [type_id, str(res.get("error", ""))])
	var pub: Dictionary = Records.publish(boat)
	check(pub.get("ok", false), "published locker spare onto boat")
	return str(res.get("itemUid", ""))

func ensure_canonical_boat(boat: Dictionary) -> void:
	if EquipmentDamage.is_canonical_owner(boat):
		return
	var base: Dictionary = game.core.hull(str(boat.get("type", "")))
	var seeded: Dictionary = Records.initialize(boat, {
		"base": base,
		"loadout": boat.get("loadout", Refit.defaults(base)),
		"catalog": Refit.catalog(),
		"identity": str(boat.get("uid", "boat-1")),
		"knownUids": []
	})
	check(seeded.get("ok", false), "initialized canonical equipment condition for integration fixture")

func test_legacy_and_corrupt_refusal() -> void:
	var boat: Dictionary = game.core.state.fleet[0]
	var uid: String = str(boat.uid)
	var saved_cond = boat.get("moduleCondition", null)
	boat.erase("moduleCondition")
	var state_before: Dictionary = game.core.state.duplicate(true)

	var built_legacy: Dictionary = EquipmentController.build_model(game.ui, uid)
	check(not built_legacy.get("ok", false) and str(built_legacy.get("mode", "")) == "legacy", "legacy boat without moduleCondition is refused by build_model")
	check(not boat.has("moduleCondition"), "build_model never initializes moduleCondition on a legacy hull")
	check( not EquipmentController.open(game.ui, uid), "EquipmentController.open refuses uninitialized legacy hull")
	check(not boat.has("moduleCondition") and game.core.state == state_before, "opening equipment view on legacy hull leaves career state untouched")

	boat["moduleCondition"] = "corrupt-string"
	var corrupt_before: Dictionary = game.core.state.duplicate(true)
	check(not EquipmentController.open(game.ui, uid), "corrupt moduleCondition is refused on view")
	var prio_corrupt: Dictionary = EquipmentController.set_priority_action(game.ui, uid, "engine")
	check(not prio_corrupt.get("ok", false), "corrupt hull refuses priority change")
	var rep_corrupt: Dictionary = EquipmentController.repair_action(game.ui, uid)
	check(not rep_corrupt.get("ok", false), "corrupt hull refuses repair action")
	check(str(boat.get("moduleCondition", "")) == "corrupt-string" and game.core.state == corrupt_before, "corrupt hull remains untouched across view, priority, and repair refusal")

	boat.erase("moduleCondition")
	boat["weaponCondition"] = {"foreign": true}
	check(not EquipmentController.open(game.ui, uid), "foreign condition field is refused on view")
	boat.erase("weaponCondition")
	if saved_cond != null:
		boat["moduleCondition"] = saved_cond

func test_quote_translation() -> void:
	var boat: Dictionary = game.core.state.fleet[0]
	ensure_canonical_boat(boat)
	var port: Dictionary = game.core.current_port()
	var raw_quote: Dictionary = {
		"ok": true,
		"cost": 145,
		"materials": 38,
		"equipmentMaterials": {"engines": 1.0, "iron": 1.5},
		"purchase": 2.0,
		"own": 1.0,
		"ordinary": 52,
		"expert": 40,
		"fee": 15,
		"message": "Drydock quote ready."
	}
	var raw_copy: Dictionary = raw_quote.duplicate(true)
	var installed: Array = Core.inspect_installed(boat.moduleCondition).get("items", [])
	var translated: Dictionary = EquipmentController.translate_service_quote(game.core, boat, port, raw_quote, true, installed)
	check(raw_quote == raw_copy and typeof(raw_quote.materials) == TYPE_INT and int(raw_quote.materials) == 38, "translate_service_quote does not mutate backend raw_quote or overwrite integer materials coin cost")
	check(translated.get("materials") is Dictionary, "translated quote provides a Dictionary for pure EquipmentUI.open")
	check(is_equal_approx(float(translated.materials.get("engines", 0.0)), 1.0) and is_equal_approx(float(translated.materials.get("iron", 0.0)), 1.5), "translated quote preserves equipmentMaterials goods")
	check(is_equal_approx(float(translated.materials.get("supplies", 0.0)), 2.0) and is_equal_approx(float(translated.materials.get("own kits", 0.0)), 1.0), "translated quote includes purchased and own repair kits")
	check(int(translated.cost) == 145 and int(translated.ordinary) == 52 and int(translated.expert) == 40 and int(translated.fee) == 15, "translated quote preserves coin totals")

func test_condition_panel_priority_and_paid_repair() -> void:
	var boat: Dictionary = game.core.state.fleet[0]
	var uid: String = str(boat.uid)
	ensure_canonical_boat(boat)

	var eng_item: Dictionary = located_item(boat.moduleCondition, "engine")
	var eng_uid: String = str(eng_item.get("itemUid", ""))
	var hurt_eng: Dictionary = Core.apply_component_damage(boat.moduleCondition, {"itemUid": eng_uid, "loss": 0.45, "cause": "Cracked manifold"})
	check(hurt_eng.get("ok", false), "damaged installed engine to 55% for panel test")
	Records.publish(boat)

	var spare_gun_damaged: String = acquire_locker_spare(boat, "weapons", "rapid_gun", 0.42, "Salt corrosion")
	var spare_gun_ok: String = acquire_locker_spare(boat, "weapons", "rapid_gun", 1.0, "")
	var spare_eng_damaged: String = acquire_locker_spare(boat, "engines", "stock_engine", 0.58, "Scored cylinder")
	check(not spare_gun_damaged.is_empty() and not spare_gun_ok.is_empty() and not spare_eng_damaged.is_empty(), "minted distinct UIDs for three locker spares")

	game.dev_enabled = false
	game.ui.open_fleet()
	check(game.ui.modal_open and game.ui.modal_kind == "fleet", "opened fleet modal")
	var state_before_view: Dictionary = game.core.state.duplicate(true)
	check(press("Equipment & condition"), "fleet card has working Equipment & condition button")
	check(game.ui.modal_open and game.ui.modal_kind == "equipment", "Equipment & condition button opens equipment modal")
	check(game.core.state == state_before_view, "opening equipment modal is strictly read-only and does not mutate campaign state")

	var text_normal: String = visible_text()
	check("Condition 55%" in text_normal and "Cracked manifold" in text_normal, "equipment panel displays damaged installed engine and cause")
	check("Condition 42%" in text_normal and "Salt corrosion" in text_normal, "equipment panel displays damaged locker spare and cause")
	check(not (eng_uid in text_normal) and not (spare_gun_damaged in text_normal), "raw itemUids stay hidden when dev_enabled is false")

	game.dev_enabled = true
	EquipmentController.open(game.ui, uid)
	var text_dev: String = visible_text()
	check(eng_uid in text_dev and spare_gun_damaged in text_dev, "raw itemUids are visible when dev_enabled is true")
	game.dev_enabled = false
	EquipmentController.open(game.ui, uid)

	var supplies_before: float = float(boat.supplies)
	var coins_before: int = int(game.core.state.coins)
	var hp_before: float = float(located_item(boat.moduleCondition, "engine").get("hp", 0.0))
	check(press("Engine first"), "clicked Engine first repair priority button")
	check(str(boat.moduleCondition.get("repairPriority", "")) == "engine", "priority button persists repairPriority on boat.moduleCondition")
	check(is_equal_approx(float(located_item(boat.moduleCondition, "engine").get("hp", 0.0)), hp_before), "changing repair priority never performs a free heal")
	check(is_equal_approx(float(boat.supplies), supplies_before) and int(game.core.state.coins) == coins_before, "changing repair priority does not consume supplies or coins")

	boat.hp = maxf(1.0, float(boat.maxHp) - 18.0)
	var port: Dictionary = game.core.current_port()
	port.stocks["supplies"] = maxf(25.0, float(port.stocks.get("supplies", 0.0)))
	port.stocks["engines"] = maxf(10.0, float(port.stocks.get("engines", 0.0)))
	port.stocks["guns"] = maxf(10.0, float(port.stocks.get("guns", 0.0)))
	port.stocks["iron"] = maxf(20.0, float(port.stocks.get("iron", 0.0)))

	var saved_coins: int = int(game.core.state.coins)
	game.core.state.coins = 0
	EquipmentController.open(game.ui, uid)
	var denied_res: Dictionary = EquipmentController.repair_action(game.ui, uid)
	check(not denied_res.get("ok", false), "paid harbor repair is refused when player has 0 coins")
	check(int(game.core.state.coins) == 0 and float(boat.hp) < float(boat.maxHp), "refused harbor repair does not mint coins or heal hull for free")

	game.core.state.coins = maxi(saved_coins, 5000)
	var rich_before: int = int(game.core.state.coins)
	EquipmentController.open(game.ui, uid)
	var repair_btn: Button = find_button("Repair installed parts · ")
	check(repair_btn != null and not repair_btn.disabled, "harbor repair button shows coin quote and is enabled when affordable")
	if repair_btn != null and not repair_btn.disabled:
		repair_btn.pressed.emit()
	check(int(game.core.state.coins) < rich_before, "paid harbor repair deducts coins through core.repair_boat")
	check(is_equal_approx(float(boat.hp), float(boat.maxHp)), "paid harbor repair restores hull HP")

	# Re-damage the installed engine slightly so single-refit and workshop tests verify unhealed damage retention.
	Core.apply_component_damage(boat.moduleCondition, {"itemUid": eng_uid, "loss": 0.30, "cause": "Worn valve"})
	Records.publish(boat)

func test_single_refit_exact_part_choice() -> void:
	var boat: Dictionary = game.core.state.fleet[0]
	var uid: String = str(boat.uid)
	var port: Dictionary = game.core.current_port()
	for good in ["guns", "engines", "iron", "timber", "copper", "fuel", "supplies"]:
		port.stocks[good] = maxf(40.0, float(port.stocks.get(good, 0.0)))
	game.core.state.coins = maxi(int(game.core.state.coins), 8000)

	var spares: Array = Core.list_locker(boat.moduleCondition).get("items", [])
	var damaged_gun_uid: String = ""
	var ok_gun_uid: String = ""
	for item in spares:
		if str(item.get("typeId", "")) == "rapid_gun":
			if float(item.get("hp", 1.0)) < 0.5:
				damaged_gun_uid = str(item.get("itemUid", ""))
			else:
				ok_gun_uid = str(item.get("itemUid", ""))
	check(not damaged_gun_uid.is_empty() and not ok_gun_uid.is_empty(), "found both damaged (42%) and operational (100%) rapid_gun spares in locker")

	game.dev_enabled = false
	RefitUI.choose(game.ui, uid, "weapon:0")
	var choose_text: String = visible_text()
	check("Review bill · Buy new (100%)" in choose_text, "RefitUI.choose offers Review bill · Buy new (100%) option")
	check("Install spare #1 (Damaged · 42%)" in choose_text and "Install spare #2 (Operational · 100%)" in choose_text, "RefitUI.choose distinguishes damaged and operational locker spares of the same type")
	check(not (damaged_gun_uid in choose_text), "RefitUI.choose hides raw spare itemUid when dev_enabled is false")

	check(press("Install spare #1 (Damaged · 42%)"), "selected the 42% damaged spare in RefitUI.choose")
	var rev_text: String = visible_text()
	check("Selected part: Damaged · 42% condition" in rev_text and "stays at 42% condition after installation" in rev_text, "RefitUI.review warns that damaged spare retains 42% condition after install")
	check("This fitting is already owned. The bill covers installation work." in rev_text, "locker spare refit charges labor only with no new yard materials")

	var coins_before: int = int(game.core.state.coins)
	check(press("Install · "), "pressed Install button in RefitUI.review for damaged spare")
	var mount0_after: Dictionary = located_item(boat.moduleCondition, "mount0")
	check(str(mount0_after.get("itemUid", "")) == damaged_gun_uid and is_equal_approx(float(mount0_after.get("hp", 0.0)), 0.42), "exact damaged rapid_gun spare is now installed at mount0 with 42% HP preserved")
	check(str(boat.moduleCondition.items.get(ok_gun_uid, {}).get("location", "")) == "locker", "the operational rapid_gun spare remained in the locker untouched")
	check(int(game.core.state.coins) < coins_before, "installing locker spare paid fitter wages in coins")

func test_workshop_exact_choice_same_type_swap_and_no_double_use() -> void:
	var boat: Dictionary = game.core.state.fleet[0]
	var uid: String = str(boat.uid)
	var base: Dictionary = game.core.hull(str(boat.get("type", "")))
	if Refit.hardpoints(base).size() < 2:
		boat.type = "iron_skiff"
		boat.id = "iron_skiff"
		game.core.fit_boat(boat, true)
		boat.erase("moduleCondition")
		ensure_canonical_boat(boat)
		acquire_locker_spare(boat, "weapons", "rapid_gun", 0.42, "Salt corrosion")
		acquire_locker_spare(boat, "weapons", "rapid_gun", 1.0, "")
		acquire_locker_spare(boat, "engines", "stock_engine", 0.58, "Scored cylinder")
		base = game.core.hull(str(boat.get("type", "")))

	var spare_engine_uid: String = ""
	var spare_gun_uids: Array = []
	for item in Core.list_locker(boat.moduleCondition).get("items", []):
		if str(item.get("typeId", "")) == "stock_engine":
			spare_engine_uid = str(item.get("itemUid", ""))
		elif str(item.get("typeId", "")) == "rapid_gun":
			spare_gun_uids.append(str(item.get("itemUid", "")))
	if spare_gun_uids.is_empty():
		spare_gun_uids.append(acquire_locker_spare(boat, "weapons", "rapid_gun", 0.64, "Bent barrel"))
	var target_gun_uid: String = str(spare_gun_uids[0])
	var old_engine_uid: String = str(located_item(boat.moduleCondition, "engine").get("itemUid", ""))
	check(not spare_engine_uid.is_empty() and spare_engine_uid != old_engine_uid, "found distinct damaged stock_engine spare in locker for same-type swap")

	EquipmentPicker.clear_workshop_state(game.ui, uid)
	WorkshopUI.open(game.ui, uid)
	check(not game.core.state.has("workshop_requests"), "workshop_requests state lives on Interface outside campaign save state")

	var draft: Dictionary = game.ui.workshop_drafts.get(uid, {}).duplicate(true)
	if draft.weapons.size() >= 2:
		WorkshopUI.draft_set(game.ui, uid, draft, "weapon:0", "rapid_gun", {"itemUid": target_gun_uid})
		draft = game.ui.workshop_drafts.get(uid, {}).duplicate(true)
		var choices_m1: Array = EquipmentPicker.spare_choices(boat, base, "weapon:1", "rapid_gun", EquipmentPicker.workshop_slot_map(game.ui, uid, draft))
		var m1_entry: Dictionary = {}
		for row in choices_m1:
			if str(row.get("itemUid", "")) == target_gun_uid:
				m1_entry = row
		check(not m1_entry.is_empty() and not bool(m1_entry.get("compatible", true)) and "Mount 1" in str(m1_entry.get("reason", "")), "spare assigned to Mount 1 is marked incompatible for Mount 2 in the same draft")
		WorkshopUI.draft_set(game.ui, uid, draft, "weapon:1", "rapid_gun", {"itemUid": target_gun_uid})
		var slot_map_after: Dictionary = EquipmentPicker.workshop_slot_map(game.ui, uid)
		check(not slot_map_after.has("weapon:0") and str(slot_map_after.get("weapon:1", {}).get("itemUid", "")) == target_gun_uid, "assigning a spare to a second socket removes its prior socket assignment so one UID never fills two sockets")
		WorkshopUI.draft_set(game.ui, uid, draft, "weapon:1", str(boat.loadout.weapons[1]), {})
		draft = game.ui.workshop_drafts.get(uid, {}).duplicate(true)
		WorkshopUI.draft_set(game.ui, uid, draft, "weapon:0", str(boat.loadout.weapons[0]), {})
		draft = game.ui.workshop_drafts.get(uid, {}).duplicate(true)

	WorkshopUI.choose(game.ui, uid, draft, "engine")
	var eng_choose_text: String = visible_text()
	check("Already in draft" in eng_choose_text and "Buy new in draft (100%)" in eng_choose_text and "Draft spare #1 (Damaged · 58%)" in eng_choose_text, "WorkshopUI.choose supports same-type engine keep, new replacement, and locker spare swap")
	check(press("Draft spare #1 (Damaged · 58%)"), "selected 58% damaged stock_engine spare in WorkshopUI.choose")

	draft = game.ui.workshop_drafts.get(uid, {}).duplicate(true)
	var req_now: Dictionary = EquipmentPicker.workshop_request(game.ui, uid, draft)
	check(str(req_now.get("slots", {}).get("engine", {}).get("itemUid", "")) == spare_engine_uid, "workshop_request records exact spare_engine_uid for engine slot")

	check(press("Review whole-fit quote · "), "opened WorkshopUI.review for same-type spare engine swap")
	var ws_rev_text: String = visible_text()
	check("Selected part: Damaged · 58% condition" in ws_rev_text and "stays at 58% condition after installation" in ws_rev_text, "WorkshopUI.review displays exact damaged spare note")
	var coins_before_ws: int = int(game.core.state.coins)
	check(press("Apply reviewed fitting · "), "applied reviewed workshop fitting")
	var eng_after_ws: Dictionary = located_item(boat.moduleCondition, "engine")
	check(str(eng_after_ws.get("itemUid", "")) == spare_engine_uid and is_equal_approx(float(eng_after_ws.get("hp", 0.0)), 0.58), "workshop apply installed the exact 58% stock_engine spare into engine slot")
	check(str(boat.moduleCondition.items.get(old_engine_uid, {}).get("location", "")) == "locker", "previous installed stock_engine moved to locker with its own UID and condition")
	check(int(game.core.state.coins) < coins_before_ws, "workshop same-type swap paid labor bill")
	check(EquipmentPicker.workshop_slot_map(game.ui, uid).is_empty(), "workshop_requests cleared for hull after successful apply")

func test_invalidation_templates_and_career_replacement() -> void:
	var boat: Dictionary = game.core.state.fleet[0]
	var uid: String = str(boat.uid)
	ensure_canonical_boat(boat)

	WorkshopUI.open(game.ui, uid)
	var draft: Dictionary = game.ui.workshop_drafts.get(uid, {}).duplicate(true)
	WorkshopUI.draft_set(game.ui, uid, draft, "engine", "economy_drive", {"new": true})
	check(not EquipmentPicker.workshop_slot_map(game.ui, uid).is_empty(), "drafted new economy_drive in workshop_requests")

	check(press("Reset draft to current"), "pressed Reset draft to current in WorkshopUI")
	check(EquipmentPicker.workshop_slot_map(game.ui, uid).is_empty(), "Reset draft to current clears workshop_requests for the boat")

	draft = game.ui.workshop_drafts.get(uid, {}).duplicate(true)
	WorkshopUI.draft_set(game.ui, uid, draft, "engine", "economy_drive", {"new": true})
	draft = game.ui.workshop_drafts.get(uid, {}).duplicate(true)
	var saved_tpl: Dictionary = game.host_save_template(uid, "Coast Runner", draft) if game.has_method("host_save_template") else game.workshop_save_template(uid, "Coast Runner", draft)
	check(saved_tpl.get("ok", false), "saved workshop fitting template")
	var templates: Array = Workshop.template_list(game.core.state, str(boat.type))
	check(not templates.is_empty() and templates[0].size() == 4 and not templates[0].has("slots") and not templates[0].has("itemUid"), "saved template is knowledge-only with no itemUids or stock")

	WorkshopUI.templates(game.ui, uid, draft)
	check(press("Load into draft"), "loaded template into draft")
	check(EquipmentPicker.workshop_slot_map(game.ui, uid).is_empty(), "loading a template clears per-UID workshop_requests")

	# Career / boat object replacement invalidation & callback re-resolution check.
	WorkshopUI.draft_set(game.ui, uid, game.ui.workshop_drafts.get(uid, {}), "engine", "economy_drive", {"new": true})
	check(not EquipmentPicker.workshop_slot_map(game.ui, uid).is_empty(), "staged request before career boat replacement")
	EquipmentController.open(game.ui, uid)
	var detached_old_boat: Dictionary = boat
	var old_priority: String = str(detached_old_boat.moduleCondition.get("repairPriority", "auto"))

	var replacement_boat: Dictionary = boat.duplicate(true)
	replacement_boat.moduleCondition.repairPriority = "auto"
	game.core.state.fleet[0] = replacement_boat
	check(not is_same(detached_old_boat, game.core.state.fleet[0]), "replaced fleet[0] Dictionary reference to simulate career reload/replacement")

	EquipmentPicker.prune_requests(game.ui)
	check(EquipmentPicker.workshop_slot_map(game.ui, uid).is_empty() and not game.ui.workshop_drafts.has(uid), "prune_requests invalidates draft and slot requests when boat Dictionary reference changes")

	check(press("Hull first"), "invoked priority button from panel opened before boat reference replacement")
	check(str(game.core.state.fleet[0].moduleCondition.get("repairPriority", "")) == "hull", "callback re-resolves current live hull by uid and updates replacement boat")
	check(str(detached_old_boat.moduleCondition.get("repairPriority", "")) == old_priority, "callback never mutates the stale detached boat Dictionary")

func test_sixty_fifth_living_hull_draft_preview_and_pruning() -> void:
	check(EquipmentPicker.MAX_ROSTER_REQUESTS == 96, "EquipmentPicker.MAX_ROSTER_REQUESTS covers the full 96-hull SaveValidation.MAX_ROSTER / Campaign.MAX_FLEET cap")
	var saved_fleet: Array = game.core.state.fleet.duplicate(true)
	var template_boat: Dictionary = game.core.state.fleet[0]
	ensure_canonical_boat(template_boat)

	while game.core.state.fleet.size() < 65:
		var idx: int = game.core.state.fleet.size() + 1
		var clone_boat: Dictionary = template_boat.duplicate(true)
		clone_boat["uid"] = "fleet_hull_%d" % idx
		clone_boat["name"] = "Reserve Cutter %d" % idx
		clone_boat["sunk"] = false
		clone_boat["refitLocker"] = {}
		clone_boat.erase("moduleCondition")
		ensure_canonical_boat(clone_boat)
		game.core.state.fleet.append(clone_boat)

	check(game.core.state.fleet.size() == 65, "populated 65 living hulls in fleet roster within the 96-hull cap")
	var boat_65: Dictionary = game.core.state.fleet[64]
	var uid_65: String = str(boat_65.get("uid", ""))
	var base_65: Dictionary = game.core.hull(str(boat_65.get("type", "")))
	var spare_65_uid: String = acquire_locker_spare(boat_65, "engines", "stock_engine", 0.61, "Reserve wear")
	check(not spare_65_uid.is_empty(), "minted 61% damaged stock_engine locker spare on 65th living hull")

	EquipmentPicker.clear_workshop_state(game.ui, uid_65)
	WorkshopUI.open(game.ui, uid_65)
	var draft_65: Dictionary = game.ui.workshop_drafts.get(uid_65, {}).duplicate(true)
	check(not draft_65.is_empty(), "65th living hull opens a workshop draft without truncation")

	WorkshopUI.draft_set(game.ui, uid_65, draft_65, "engine", "stock_engine", {"itemUid": spare_65_uid})
	draft_65 = game.ui.workshop_drafts.get(uid_65, {}).duplicate(true)
	var living_map: Dictionary = EquipmentPicker.prune_requests(game.ui)
	check(living_map.size() == 65 and living_map.has(uid_65), "prune_requests retains all 65 living fleet hulls")

	var req_65: Dictionary = EquipmentPicker.workshop_request(game.ui, uid_65, draft_65)
	check(str(req_65.get("slots", {}).get("engine", {}).get("itemUid", "")) == spare_65_uid, "65th living hull binds and retains exact locker spare itemUid in workshop_request")

	var preview_65: Dictionary = EquipmentPicker.preview_workshop(game.ui, uid_65, draft_65)
	var found_65_sel: bool = false
	for change in preview_65.get("changes", []):
		if change is Dictionary and str(change.get("slot", "")) == "engine":
			var sel: Dictionary = change.get("selection", {}) if change.get("selection") is Dictionary else {}
			if str(sel.get("itemUid", "")) == spare_65_uid and is_equal_approx(float(sel.get("hp", 0.0)), 0.61):
				found_65_sel = true
	check(preview_65.get("ok", false) and not preview_65.get("changes", []).is_empty() and found_65_sel, "preview_workshop on 65th living hull previews exact 61% damaged locker spare swap")

	WorkshopUI.review(game.ui, uid_65, draft_65)
	var rev_65_text: String = visible_text()
	check("Selected part: Damaged · 61% condition" in rev_65_text and "stays at 61% condition after installation" in rev_65_text, "WorkshopUI.review on 65th living hull renders exact 61% spare selection note")

	# Inventory/locker pruning: transferring the drafted spare out of the 65th hull's locker prunes the stale slot request.
	var boat_0: Dictionary = game.core.state.fleet[0]
	var base_0: Dictionary = game.core.hull(str(boat_0.get("type", "")))
	var xfer: Dictionary = Core.transfer_exact(boat_65.moduleCondition, boat_0.moduleCondition, {
		"itemUid": spare_65_uid,
		"location": "locker",
		"mountCount": Refit.hardpoints(base_0).size(),
		"hullType": str(boat_0.get("type", "")),
		"sourceMountCount": Refit.hardpoints(base_65).size(),
		"sourceHullType": str(boat_65.get("type", "")),
		"knownUids": []
	})
	check(xfer.get("ok", false), "transferred spare_65_uid out of 65th hull locker to fleet[0] locker")
	Records.publish(boat_65)
	Records.publish(boat_0)
	EquipmentPicker.prune_requests(game.ui)
	check(EquipmentPicker.workshop_slot_map(game.ui, uid_65, draft_65).is_empty() and game.ui.workshop_drafts.has(uid_65), "inventory pruning clears stale slot request when locker spare leaves 65th hull while preserving draft loadout")

	# Career / boat Dictionary replacement pruning on the 65th hull.
	WorkshopUI.draft_set(game.ui, uid_65, draft_65, "engine", "economy_drive", {"new": true})
	check(not EquipmentPicker.workshop_slot_map(game.ui, uid_65).is_empty(), "staged new engine request on 65th hull before reference replacement")
	game.core.state.fleet[64] = boat_65.duplicate(true)
	EquipmentPicker.prune_requests(game.ui)
	check(EquipmentPicker.workshop_slot_map(game.ui, uid_65).is_empty() and not game.ui.workshop_drafts.has(uid_65), "career boat replacement on 65th hull prunes both draft and slot requests")

	# Dead / sunk hull pruning on the 65th hull.
	WorkshopUI.open(game.ui, uid_65)
	WorkshopUI.draft_set(game.ui, uid_65, game.ui.workshop_drafts.get(uid_65, {}), "engine", "economy_drive", {"new": true})
	check(not EquipmentPicker.workshop_slot_map(game.ui, uid_65).is_empty(), "re-staged request on 65th hull before sinking")
	game.core.state.fleet[64]["sunk"] = true
	EquipmentPicker.prune_requests(game.ui)
	check(EquipmentPicker.workshop_slot_map(game.ui, uid_65).is_empty() and not game.ui.workshop_drafts.has(uid_65), "sinking 65th hull prunes both draft and slot requests")

	game.core.state.fleet = saved_fleet
	EquipmentPicker.prune_requests(game.ui)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		check(false, "this integration suite requires the headless/silent engine lease")
	else:
		game = load("res://main.tscn").instantiate()
		root.add_child(game)
		game.set_process(false)
		game.set_physics_process(false)
		game.audio.enabled = false
		game.music.enabled = false
		game.save_directory = OS.get_user_data_dir().path_join("equipment-ui-int-%d" % Time.get_ticks_usec())
		await process_frame
		game.new_game()
		game.paused = true
		game.audio.enabled = false
		game.music.enabled = false
		test_legacy_and_corrupt_refusal()
		test_quote_translation()
		test_condition_panel_priority_and_paid_repair()
		test_single_refit_exact_part_choice()
		test_workshop_exact_choice_same_type_swap_and_no_double_use()
		test_invalidation_templates_and_career_replacement()
		test_sixty_fifth_living_hull_draft_preview_and_pruning()
		game.queue_free()
		await process_frame
	print("equipment UI integration: %d checks, %d failures; native controls only, background/headless/silent" % [checks, failures])
	quit(0 if failures == 0 else 1)
