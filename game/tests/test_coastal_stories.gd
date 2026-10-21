extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const Stories = preload("res://scripts/coastal_stories.gd")
const Exploration = preload("res://scripts/exploration.gd")
const Contacts = preload("res://scripts/contacts.gd")
const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
var failures: Array = []
var checks: int = 0
var world: Dictionary
var c

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL " + message)

func reset() -> void:
	c.new_game(123)
	Stories.ensure(c.state)
	Contacts.ensure(c.state, world)

func goto_port(id: String) -> Dictionary:
	c.state.position = c.port_position(id)
	c.state.lastPort = id
	var p: Dictionary = c.port(id)
	Contacts.visit(c.state, p, c.state.day)
	return p

func set_site_level(site_id: String, level: int) -> void:
	# Fixture shortcut standing in for a completed real survey party; gate
	# logic is what this suite proves, survey pacing is proven elsewhere.
	Exploration.ensure(c.state, world)
	var rec: Dictionary = (c.state.exploration.sites as Dictionary).get(site_id, {"level": 0, "rewarded": false})
	rec["level"] = level
	c.state.exploration.sites[site_id] = rec

func entry(chain_id: String) -> Dictionary:
	for row in Stories.journal(c.state):
		if str(row.chainId) == chain_id:
			return row
	return {}

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	# The stories catalog declares site ids against the real exploration data.
	var sites_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/island_sites.json"))
	if sites_data is Dictionary:
		world["ISLAND_SITES"] = sites_data.get("sites", [])
	c = Campaign.new(world)
	_test_referenced_ids_valid()
	_test_merchant_progression()
	_test_explorer_branches_distinct()
	_test_privateer_npc_gate()
	_test_save_roundtrip()
	print("coastal_stories: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		quit(0)
	else:
		quit(1)

func _test_referenced_ids_valid() -> void:
	reset()
	var ports := {}
	for p in world.PORTS:
		ports[str(p.id)] = true
	var factions := {}
	for f in world.FACTIONS:
		factions[str(f.id)] = true
	var site_ids := {}
	for site in Exploration.sites(c.state):
		site_ids[str(site.id)] = true
	var contact_ids := {}
	for contact in Contacts.list_contacts(c.state):
		contact_ids[str(contact.id)] = true
	var catalog: Array = Stories.catalog(c.state)
	check(catalog.size() >= 3, "At least three authored chains exist")
	var approaches := {}
	for chain in catalog:
		approaches[str(chain.approach)] = true
		check(ports.has(str(chain.startPort)), "Real start port for " + str(chain.id))
		check(contact_ids.has(str(chain.startContact)), "Real start contact for " + str(chain.id))
		check((chain.stages as Array).size() >= 3, "At least three stages in " + str(chain.id))
		var stage_ids := {}
		for stage in chain.stages:
			stage_ids[str(stage.id)] = true
		for stage in chain.stages:
			var gate: Dictionary = stage.get("gate", {})
			if str(gate.get("type", "")) == "site":
				check(site_ids.has(str(gate.site)), "Real site gate " + str(gate.site))
			if str(gate.get("type", "")) in ["at_port", "visit"]:
				check(ports.has(str(gate.port)), "Real port gate " + str(gate.port))
			for choice in stage.get("choices", []):
				check(str(choice.next) == "done" or stage_ids.has(str(choice.next)), "Choice leads to a real stage in " + str(chain.id))
				var cost: Dictionary = choice.get("cost", {})
				if not cost.is_empty():
					check(Goods.ITEMS.has(str(cost.good)) and ports.has(str(cost.port)), "Delivery cost uses a real good and port")
				for lead in choice.get("leads", []):
					check(site_ids.has(str(lead)), "Real lead site " + str(lead))
				if str(choice.get("reveal", "")) != "":
					check(site_ids.has(str(choice.reveal)), "Real reveal site " + str(choice.reveal))
				for effect in choice.get("consequences", []):
					if str(effect.kind) == "faction":
						check(factions.has(str(effect.target)), "Real faction consequence " + str(effect.target))
					else:
						check(contact_ids.has(str(effect.target)), "Real contact consequence " + str(effect.target))
	check(approaches.has("explorer") and approaches.has("merchant") and approaches.has("privateer") and approaches.has("escort"), "Explorer, merchant, privateer and escort approaches all represented")

func _test_merchant_progression() -> void:
	reset()
	var total_before: int = Money.total(c.state)
	goto_port("brass_haven")
	var offers: Array = Stories.available(c)
	check(offers.any(func(o): return str(o.id) == "ironwood_for_the_mill"), "Ironwood chain offered at its real start harbor")
	# Starting at the harbor persists the chain even though stage 1 is elsewhere.
	check(not bool(Stories.choose(c, "ironwood_for_the_mill", "deliver_timber").ok), "Delivery choice refuses away from the mill")
	check(not entry("ironwood_for_the_mill").is_empty(), "Chain is started and journalled")
	check(str(entry("ironwood_for_the_mill").location.id) == "sawtooth_mill", "Journal points at the mill")
	# Gate/cost refusal is atomic: no cargo, stock, event or coin changes.
	goto_port("sawtooth_mill")
	c.state.cargo.timber = 2.0
	var stock_before: float = float(c.port("sawtooth_mill").stocks.timber)
	var events_before: int = (c.state.stories.events as Array).size()
	check(not bool(Stories.choose(c, "ironwood_for_the_mill", "deliver_timber").ok), "Delivery refuses without the promised timber")
	check(is_equal_approx(float(c.state.cargo.timber), 2.0) and is_equal_approx(float(c.port("sawtooth_mill").stocks.timber), stock_before), "Refused delivery moves no goods")
	check((c.state.stories.events as Array).size() == events_before, "Refused delivery records no event")
	c.state.cargo.timber = 9.0
	check(bool(Stories.choose(c, "ironwood_for_the_mill", "deliver_timber").ok), "Delivery succeeds with the goods aboard")
	check(is_equal_approx(float(c.state.cargo.timber), 4.0), "Delivered timber leaves the hold")
	check(is_equal_approx(float(c.port("sawtooth_mill").stocks.timber), stock_before + 5.0), "Delivered timber enters mill stocks")
	check(not bool(Stories.choose(c, "ironwood_for_the_mill", "deliver_timber").ok), "The same delivery cannot settle twice")
	# Survey gate, then the buyer decision records (never applies) consequences.
	check(not bool(Stories.choose(c, "ironwood_for_the_mill", "show_survey").ok), "Stand must be charted before buyers believe it")
	set_site_level("sawtooth_timber_stand", 2)
	check(bool(Stories.choose(c, "ironwood_for_the_mill", "show_survey").ok), "Charted stand advances the chain")
	goto_port("brass_haven")
	var picked: Dictionary = Stories.choose(c, "ironwood_for_the_mill", "forge_first")
	check(bool(picked.ok) and bool(picked.done), "Buyer decision finishes the merchant chain")
	check((picked.consequences as Array).size() == 2, "Both faction consequences are recorded for root")
	check(not bool(Stories.choose(c, "ironwood_for_the_mill", "compact_first").ok), "Finished chain accepts no second ending")
	check(Money.total(c.state) == total_before, "The whole merchant chain mints and moves no coins")

func _test_explorer_branches_distinct() -> void:
	# Shared-chart run.
	reset()
	goto_port("reed_floats")
	Stories.choose(c, "middle_sea_chart", "share_chart")
	set_site_level("middle_chart_rock", 2)
	check(bool(Stories.choose(c, "middle_sea_chart", "share_chart").ok), "Shared-chart branch settles after charting")
	set_site_level("shatter_wreck_field", 3)
	check(bool(Stories.choose(c, "middle_sea_chart", "mark_field").ok), "Surveyed field advances the shared run")
	goto_port("reed_floats")
	check(not bool(Stories.choose(c, "middle_sea_chart", "exclusive_claim").ok), "Secret ending is closed to the shared-chart captain")
	var shared_end: Dictionary = Stories.choose(c, "middle_sea_chart", "open_field")
	check(bool(shared_end.ok), "Shared run ends by opening the field")
	var shared_targets := []
	for effect in shared_end.consequences:
		shared_targets.append(str(effect.target))
	# Secret run: a different opportunity set, not a different payout.
	reset()
	goto_port("reed_floats")
	Stories.choose(c, "middle_sea_chart", "keep_secret")
	set_site_level("middle_chart_rock", 2)
	Stories.choose(c, "middle_sea_chart", "keep_secret")
	set_site_level("shatter_wreck_field", 3)
	Stories.choose(c, "middle_sea_chart", "mark_field")
	goto_port("reed_floats")
	check(not bool(Stories.choose(c, "middle_sea_chart", "open_field").ok), "Open ending is closed to the secret-keeping captain")
	var secret_end: Dictionary = Stories.choose(c, "middle_sea_chart", "exclusive_claim")
	check(bool(secret_end.ok), "Secret run ends with the exclusive claim")
	var secret_targets := []
	for effect in secret_end.consequences:
		secret_targets.append(str(effect.target))
	check(shared_targets != secret_targets, "Branches carry materially different consequences")
	check((c.state.stories.consequences as Array).all(func(e): return not bool(e.get("applied", true))), "Consequences wait pending for root to apply")

func _test_privateer_npc_gate() -> void:
	reset()
	goto_port("rust_anchorage")
	Stories.choose(c, "the_toll_camp", "report_sighting")
	check(not bool(Stories.choose(c, "the_toll_camp", "report_sighting").ok), "Camp must be sighted before reporting it")
	set_site_level("kelp_defended_camp", 1)
	var ready: Array = Stories.tick(c)
	check(ready.any(func(e): return str(e.chainId) == "the_toll_camp"), "tick announces the newly-ready stage once")
	check(Stories.tick(c).is_empty(), "tick never repeats the same notice")
	check(bool(Stories.choose(c, "the_toll_camp", "report_sighting").ok), "Sighted camp can be reported")
	check(not bool(Stories.choose(c, "the_toll_camp", "claim_the_break").ok), "Living toll fleet blocks the claim")
	var owner: Dictionary = c.fleet_owner("patrol-0")
	check(not owner.is_empty(), "The named toll fleet is a real campaign owner")
	owner.active = false
	check(bool(Stories.choose(c, "the_toll_camp", "claim_the_break").ok), "Defeated toll fleet opens the claim")
	set_site_level("kelp_shoal_cut", 2)
	check(bool(Stories.choose(c, "the_toll_camp", "open_cut").ok), "Charted cut can be published to finish")

func _test_save_roundtrip() -> void:
	reset()
	goto_port("anvil_dock")
	Stories.choose(c, "the_cold_workshop", "bring_the_survey")
	set_site_level("cinder_workshop_ruin", 3)
	Stories.choose(c, "the_cold_workshop", "bring_the_survey")
	var text: String = JSON.stringify(c.state)
	var restored = JSON.parse_string(text)
	check(restored is Dictionary, "State with stories survives JSON roundtrip")
	if restored is Dictionary:
		var c2 = Campaign.new(world)
		c2.state = restored
		Stories.ensure(c2.state)
		var rows: Array = Stories.journal(c2.state)
		check(rows.size() == 1 and str(rows[0].stage) == "stock_the_forge", "Chain stage survives the roundtrip")
		check((rows[0].leads as Array).has("cinder_ore_seam"), "Recorded lead survives the roundtrip")
		check((c2.state.stories.events as Array).has("story:the_cold_workshop:survey_the_ruin:bring_the_survey"), "Settled event id survives the roundtrip")
		check(not bool(Stories.choose(c2, "the_cold_workshop", "bring_the_survey").ok), "Settled choice cannot repeat after load")
	var legacy := {"coins": 3, "fleet": []}
	Stories.ensure(legacy)
	check(legacy.stories.chains is Dictionary and int(legacy.coins) == 3, "ensure() migrates legacy saves in place")
