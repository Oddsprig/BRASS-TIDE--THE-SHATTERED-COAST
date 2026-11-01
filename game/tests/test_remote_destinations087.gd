extends SceneTree
## v0.087 focused verification for Distinct Remote Destinations:
## - broken_meridian087 (connected two-group remote expedition with secrecy/turn-back vs full survey)
## - unfinished_keel087 (remote slipway discovery with finite seeded workboat cradle and paid recovery)
## - two_lantern_anchorage087 (frontier headland chart + 4-kit harbor delivery + night-range settlement)

const Campaign = preload("res://scripts/campaign.gd")
const Stories = preload("res://scripts/coastal_stories.gd")
const StoryOps = preload("res://scripts/story_ops.gd")
const Offers = preload("res://scripts/story_offers.gd")
const Salvage = preload("res://scripts/salvage.gd")
const Remote067 = preload("res://scripts/remote_expedition067.gd")
const Money = preload("res://scripts/money.gd")
const Custody = preload("res://scripts/equipment_campaign.gd")
const EconomyWorkers = preload("res://scripts/economy_workers.gd")

const SEED := 87087
const BODY_LIMIT_MS := 55000
const MERIDIAN := "broken_meridian087"
const KEEL := "unfinished_keel087"
const LANTERN := "two_lantern_anchorage087"

var started: int = 0
var c = null
var workers: EconomyWorkers = EconomyWorkers.new()

func _initialize() -> void:
	started = Time.get_ticks_msec()
	_run.call_deferred()
var checks: int = 0
var failures: int = 0
var failure_labels: Array = []
var events: Array = []
var accountfacts: Array = []
var recovery_facts: Array = []
var artifacts: Dictionary = {}
var complete: bool = false
var expired: bool = false

var home_data: Dictionary = {}
var home_nav: Dictionary = {}
var home_context: Dictionary = {}
var home_anchors: Dictionary = {}
var supply: int = 0
var initial_people: int = 0
var geography: String = ""
var initial_items: Array = []
var initial_boats: Array = []

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		failure_labels.append(label)
		printerr("FAIL: " + label)
	return condition

func note(kind: String, payload: Dictionary = {}) -> void:
	var row: Dictionary = payload.duplicate(true)
	row["kind"] = kind
	row["elapsed_ms"] = Time.get_ticks_msec() - started
	if c != null and c.get("state") is Dictionary and not c.state.is_empty():
		row["day"] = float(c.state.get("day", 0.0))
		row["econDay"] = int(c.state.get("econDay", 0))
	events.append(row)

func bounded() -> bool:
	if expired:
		return false
	if Time.get_ticks_msec() - started >= BODY_LIMIT_MS:
		expired = true
		return check(false, "Bounded body stays below the fifty-five-second ceiling")
	return true

func normalized(value) -> String:
	return JSON.stringify(value, "", true, true)

func fleet_book(state: Dictionary) -> Array:
	var rows: Array = []
	for key in ["fleet", "boardingPrizes"]:
		for boat in state.get(key, []):
			if boat is Dictionary:
				rows.append(boat)
	for owner in state.get("fleetOwners", []):
		if owner is Dictionary:
			for boat in owner.get("boats", []):
				if boat is Dictionary:
					rows.append(boat)
	for company in state.get("companies", {}).get("list", []):
		if company is Dictionary:
			for boat in company.get("boats", []):
				if boat is Dictionary:
					rows.append(boat)
	return rows

func people(state: Dictionary) -> int:
	var total: int = 0
	for port in state.get("ports", []):
		if port is Dictionary:
			total += int(port.get("workforce", 0)) + int(port.get("experts", 0))
	for boat in fleet_book(state):
		if not bool(boat.get("sunk", false)):
			total += int(boat.get("crew", 0))
	for yard in state.get("homeYards", []):
		if yard is Dictionary:
			total += int(yard.get("workers", 0)) + int(yard.get("specialists", 0))
	for row in state.get("harborDevelopment", {}).get("projects", []):
		if row is Dictionary:
			total += int(row.get("workers", 0)) + int(row.get("experts", 0))
	for job in state.get("voyageJobs", []):
		if job is Dictionary and str(job.get("kind", "")) == "passenger_charter":
			var group = job.get("passengers", {})
			if group is Dictionary:
				total += int(group.get("n", 0))
	for job in state.get("regionalCrises", {}).get("jobs", []):
		if job is Dictionary and str(job.get("stage", "")) != "holding":
			total += int(job.get("n", 0))
	for unit in state.get("workerUnits", []):
		if unit is Dictionary:
			total += int(unit.get("count", 0))
	return total

func assets() -> String:
	var boats: Array = []
	for boat in c.state.get("fleet", []):
		if boat is Dictionary:
			boats.append({
				"uid": boat.get("uid"), "type": boat.get("type"), "crew": boat.get("crew"),
				"wounded": boat.get("wounded"), "shoreCrew": boat.get("shoreCrew", 0),
				"hp": boat.get("hp"), "fuel": boat.get("fuel"), "ammo": boat.get("ammo"),
				"supplies": boat.get("supplies"), "loadout": boat.get("loadout")
			})
	return normalized({
		"coins": c.state.get("coins"), "crewPurse": c.state.get("crewPurse"),
		"total": Money.total(c.state), "cargo": c.state.get("cargo"),
		"boats": boats, "wrecks": c.state.get("wrecks"), "ports": c.state.get("ports")
	})

func query_purity(label: String) -> bool:
	var before: PackedByteArray = var_to_bytes([c.state, c.events, c.pending_days])
	var _a: Array = Stories.available(c)
	var _b: Array = Offers.available(c)
	var _d: Dictionary = Stories.destinations087(c.state)
	var _j: Array = Stories.journal(c.state)
	for cid in Stories.CHAINS087:
		var _l: Array = Stories.earned_leads(c.state, str(cid))
	var _v: Array = c.Exploration.visible_sites(c.state)
	return check(var_to_bytes([c.state, c.events, c.pending_days]) == before,
		label + ": story/offer/destination/journal/exploration queries are read-only")

func point(label: String) -> Dictionary:
	if not bounded():
		return {}
	var parsed = JSON.parse_string(JSON.stringify(c.state))
	if not check(parsed is Dictionary, label + ": JSON checkpoint round-trip decodes"):
		return {}
	return {
		"label": label,
		"saved": parsed,
		"bytes": var_to_bytes(parsed),
		"world": c.world_location064().world064.duplicate(true)
	}

func restore_point(cp: Dictionary) -> bool:
	if not bounded():
		return false
	var candidate: Dictionary = (cp["saved"] as Dictionary).duplicate(true)
	var before_input: PackedByteArray = var_to_bytes(candidate)
	var candidate_campaign = Campaign.new(home_data, home_nav, false)
	candidate_campaign.ocean_context064 = home_context
	candidate_campaign.ocean_anchors064 = home_anchors
	var restored: Dictionary = candidate_campaign.restore(candidate)
	if not check(bool(restored.get("ok", false)), str(cp["label"]) + " restore: " + str(restored.get("message", ""))):
		return false
	if not check(var_to_bytes(candidate) == before_input and before_input == cp["bytes"],
		str(cp["label"]) + " restore leaves caller save dictionary untouched"):
		return false
	c = candidate_campaign
	return query_purity("Restored " + str(cp["label"]))

func settle_pending() -> bool:
	while c.pending_days > 0:
		if not bounded():
			return false
		var days: int = c.pending_days
		c.pending_days = 0
		var before_coins: int = int(c.state.coins)
		var before_purse: int = int(c.state.crewPurse)
		var wages: int = int(c.Economy.daily_upkeep(c.state.fleet).wages) * days
		var blockades: Array = c.TradeFlow.blockades(c)
		var job_seed: int = int(c.state.seed) + int(c.state.econDay) * 104729
		if not check(workers.start(c.state.ports, days, blockades, job_seed), "Economy worker starts for " + str(days) + " day(s)"):
			return false
		var done: Dictionary = workers.finish(true)
		if not check(bool(done.get("ok", false)), "Economy worker joins cleanly"):
			return false
		c.apply_economy(done.ports, done.events, int(done.days))
		if not check(int(c.state.coins) == before_coins - wages and int(c.state.crewPurse) == before_purse + wages and int(c.state.wageArrears) == 0,
			"Daily economy pays exact 100 coins/sailor-day wages into crewPurse"):
			return false
	return true

func advance(dt: float = 5.0) -> bool:
	if not bounded():
		return false
	c.advance(dt)
	for ev in c.events.duplicate(true):
		if ev is Dictionary and str(ev.get("kind", "")) in ["encounter", "defeat", "ocean_encounter066"]:
			return check(false, "Unexpected combat/defeat event interrupted bounded destination verification: " + normalized(ev))
	c.events.clear()
	if not settle_pending():
		return false
	return check(Money.total(c.state) == supply and people(c.state) == initial_people,
		"World coin supply and population stay conserved after clock advance")

func trade(good: String, qty: int, action: String = "buy") -> bool:
	if qty <= 0:
		return true
	var dock: Dictionary = c.current_port() if not c.current_port().is_empty() else c.work_port070()
	if not check(not dock.is_empty(), "Docked at a harbor before trading " + good):
		return false
	var stock_Now: int = floori(float(dock.stocks.get(good, 0.0)))
	var actual_qty: int = mini(qty, stock_Now) if action == "buy" else qty
	if actual_qty <= 0:
		return true
	var res: Dictionary = c.trade_good(good, actual_qty, action)
	return check(bool(res.get("ok", false)), "Trade " + action + " " + str(actual_qty) + " " + good + ": " + str(res.get("message", "")))

func provision(min_supplies: int = 12) -> bool:
	var boat_id: String = str(c.state.fleet[0].uid)
	for util in ["fuel", "supplies"]:
		var res: Dictionary = c.resupply_boat(boat_id, util)
		if not check(bool(res.get("ok", false)), "Resupply boat " + util + ": " + str(res.get("message", ""))):
			return false
	for row in [["food", 22], ["supplies", min_supplies], ["fuel", 6]]:
		var good: String = str(row[0])
		var wanted: int = int(row[1])
		var need: int = ceili(maxf(0.0, wanted - float(c.state.cargo.get(good, 0.0))))
		if not trade(good, need, "buy"):
			return false
	return true

func sail(target: Dictionary, port_id: String = "") -> bool:
	if not bounded():
		return false
	var route: Dictionary = c.chart_course({"x": float(target.x), "y": float(target.y)}, port_id)
	if not check(bool(route.get("ok", false)), "Course admission to " + port_id + ": " + str(route.get("message", ""))):
		return false
	for _slice in range(90):
		if c.state.path.is_empty():
			break
		if not advance():
			return false
	return check(c.state.path.is_empty(), "Sailing course completes within bounded steps")

func sail_port(port_id: String) -> bool:
	var cur: Dictionary = c.current_port() if not c.current_port().is_empty() else c.work_port070()
	if str(cur.get("id", "")) == port_id:
		return true
	var target: Dictionary = c.port(port_id)
	if not check(not target.is_empty(), "Harbor exists in state.ports: " + port_id):
		return false
	if not c.home_local064() and not c.ShippingFlow068.known069(c.state, port_id):
		if not sail(target, ""):
			return false
		c.ShippingFlow068.observe_sector069(c)
	var after_obs: Dictionary = c.current_port() if not c.current_port().is_empty() else c.work_port070()
	if str(after_obs.get("id", "")) != port_id:
		if not sail(target, port_id):
			return false
	var arrived: Dictionary = c.current_port() if not c.current_port().is_empty() else c.work_port070()
	return check(str(arrived.get("id", "")) == port_id, "Arrived at harbor berth: " + port_id)

func stage_region_berth(region_id: String, anchor_xy: Dictionary) -> bool:
	var physical: String = assets()
	var location: Dictionary = c.world_location064()
	var pos: Dictionary = {"x": float(anchor_xy.x), "y": float(anchor_xy.y)}
	if region_id == "shatter_coast":
		location.world064 = {"schema": 1, "layer": "home", "regionId": "shatter_coast"}
		var water_berth: Dictionary = c.Navigation.harbor_approach(c.nav, anchor_xy, c.Routes.clearance(c), 40.0)
		if not water_berth.is_empty():
			pos = water_berth
	else:
		location.world064 = {"schema": 1, "layer": "local", "regionId": region_id}
	location.position = pos
	location.path = []
	location.destination = ""
	var prepared: Dictionary = c.OceanWorld064.prepare_player(location, c.ocean_context064, c.Routes.clearance(c))
	if not check(bool(prepared.get("ok", false)), "Region berth passes OceanWorld064.prepare_player for " + region_id + ": " + str(prepared.get("message", ""))):
		return false
	c._publish_location064(prepared.location)
	c.ShippingFlow068.observe_sector069(c)
	StoryOps.ensure(c)
	return check(assets() == physical, "Region berth transition preserves all coins, cargo, fleet and ports")

func survey_site(site_id: String, required_level: int = 3) -> bool:
	var site: Dictionary = c.Exploration.catalog_site(c.state, site_id)
	if not check(not site.is_empty(), "Survey catalog contains " + site_id):
		return false
	var region_id: String = c.Exploration._site_region(site)
	var spot: Dictionary = c.Navigation.harbor_approach(c.nav, site, c.Routes.clearance(c), 160.0) if region_id == "shatter_coast" else {"x": float(site.x), "y": float(site.y)}
	if not check(not spot.is_empty() and c.distance(spot, site) <= 180.0, "Water-safe survey approach for " + site_id):
		return false
	if c.distance(c.state.position, spot) > 25.0:
		if not sail(spot):
			return false
	c.Exploration.discover_near(c.state, c.state.position, 620.0)
	StoryOps.ensure(c)
	if not check(Stories._site_level(c.state, site_id) >= 1, site_id + " is sighted in its own local chart before shore work"):
		return false
	var known: Dictionary = Stories._known_site(c.state, site_id)
	if not check(str(known.get("regionId", "")) == region_id and str(known.get("layer", "")) == ("home" if region_id == "shatter_coast" else "local"),
		"Known site DTO preserves regionId and layer for " + site_id):
		return false
	var actions_done: int = 0
	for action in ["chart", "survey"]:
		var target_level: int = 2 if action == "chart" else 3
		if target_level > required_level or Stories._site_level(c.state, site_id) >= target_level:
			continue
		var begun: Dictionary = c.begin_survey(site_id, action)
		if not check(bool(begun.get("ok", false)), "Begin " + action + " at " + site_id + ": " + str(begun.get("message", ""))):
			return false
		actions_done += 1
		for _slice in range(52):
			if c.state.exploration.assignment.is_empty():
				break
			if not advance():
				return false
		if not check(c.state.exploration.assignment.is_empty() and Stories._site_level(c.state, site_id) >= target_level,
			"Completed " + action + " at " + site_id + " to level " + str(target_level)):
			return false
		note("actual_survey087", {"siteId": site_id, "regionId": region_id, "action": action, "level": Stories._site_level(c.state, site_id)})
	return check(actions_done > 0 and Stories._site_level(c.state, site_id) >= required_level,
		"Site " + site_id + " reached required level " + str(required_level))

func decision(chain_id: String, choice_id: String, expected_flags: Array) -> bool:
	var res: Dictionary = StoryOps.choose(c, chain_id, choice_id)
	if not check(bool(res.get("ok", false)), chain_id + " -> " + choice_id + ": " + str(res.get("message", ""))):
		return false
	var rec: Dictionary = Stories._record(c.state, chain_id)
	for flag in expected_flags:
		if not check((rec.get("flags", []) as Array).has(str(flag)), chain_id + " records flag " + str(flag)):
			return false
	for effect in c.state.stories.get("consequences", []):
		if effect is Dictionary and str(effect.get("id", "")).begins_with("story:" + chain_id + ":"):
			if not check(bool(effect.get("applied", false)), "Consequence applied for " + str(effect.get("id", ""))):
				return false
	note("story_decision087", {"chainId": chain_id, "choiceId": choice_id, "stage": rec.get("stage"), "done": rec.get("done"), "flags": rec.get("flags", []).duplicate()})
	return query_purity(chain_id + ":" + choice_id)

func ensure_faction_access(faction_id: String) -> bool:
	for idx in range(6):
		var cur: int = int(c.Factions.standing(c.state, faction_id).score)
		if cur >= 15:
			break
		c.Factions.adjust(c.state, faction_id, mini(25, 15 - cur),
			"DECLARED087 service-access standing for destination harbor verification",
			"declared087-access:%s:%d" % [faction_id, idx])
	return check(int(c.Factions.standing(c.state, faction_id).score) >= 15,
		"Faction standing permits legal service access for " + faction_id)

func opening_and_connected_work() -> bool:
	var dest: Dictionary = Stories.destinations087(c.state)
	if not check(bool(dest.get("bound", false)) and bool(dest.get("available", false)) and str(dest.get("status", "")) == "bound_sector069",
		"Fresh 48-group career binds v0.087 remote destination packages"):
		return false
	var pkgs: Dictionary = dest.get("packages", {})
	var mer: Dictionary = pkgs.get(MERIDIAN, {})
	var keel: Dictionary = pkgs.get(KEEL, {})
	var lan: Dictionary = pkgs.get(LANTERN, {})
	if not check(bool(mer.get("available", false)) and bool(keel.get("available", false)) and bool(lan.get("available", false)),
		"All three v0.087 destination packages are available on fresh seeded world"):
		return false
	var r1: String = str(mer.get("firstRegionId", ""))
	var r2: String = str(mer.get("secondRegionId", ""))
	var rk: String = str(keel.get("regionId", ""))
	var rl: String = str(lan.get("regionId", ""))
	if not check(r1 != r2 and r1 != rk and r2 != rk and rl != r1 and rl != r2 and rl != rk,
		"Packages bind three distinct remote groups plus a separate frontier group"):
		return false
	for sid in [mer.get("firstSiteId", ""), mer.get("secondSiteId", ""), keel.get("siteId", ""), lan.get("siteId", "")]:
		if not check(Stories._site_level(c.state, str(sid)) == 0, "Bound destination site starts unvisited (level 0): " + str(sid)):
			return false
	# Verify per-seed determinism without mutating the live campaign.
	var other_campaign = Campaign.new(home_data, home_nav, false)
	other_campaign.ocean_anchors064 = home_anchors
	var other_open: Dictionary = other_campaign.new_game(SEED + 1)
	if not check(bool(other_open.get("ok", false)), "Comparison seed initializes cleanly"):
		return false
	var other_dest: Dictionary = Stories.destinations087(other_campaign.state)
	check(normalized(other_dest.get("packages", {})) != normalized(pkgs),
		"Destination bindings derive deterministically from the campaign seed rather than hardcoded group IDs")
	other_campaign = null

	# Disclose finite 90-day preparation reserve from Silt Hollow governmentPurse, recruit 2 spare sailors, and run a real VoyageJob.
	var boat_id: String = str(c.state.fleet[0].uid)
	var dock0: Dictionary = c.current_port()
	var projected: Array = c.state.fleet.duplicate(true)
	projected[0].crew += 2
	var budget: int = int(c.Economy.daily_upkeep(projected).wages) * 90 + c.Economy.recruit_cost(dock0, 2) + 8000
	var funding: int = maxi(0, budget - int(c.state.coins))
	if not check(Money.move(dock0, "governmentPurse", c.state, "coins", funding,
		"Declared087 finite ninety-day expedition reserve", c.state.moneyLog),
		"Declared finite treasury transfer conserves world coins"):
		return false
	for owner in c.state.fleetOwners:
		owner.active = false
	for patrol in c.state.get("patrols", []):
		patrol.active = false
	var rec_res: Dictionary = c.recruit_crew(boat_id, 2)
	if not check(bool(rec_res.get("ok", false)) and people(c.state) == initial_people,
		"Recruiting two able sailors transfers harbor residents and conserves total population"):
		return false
	if not provision(14):
		return false

	# Connected outward preparation: accept and settle a real funded VoyageJobs freight contract in home waters.
	var job_offer: Dictionary = {}
	for cand in c.VoyageJobs.available(c):
		if str(cand.get("kind", "")) == "freight":
			job_offer = cand
			break
	if not check(not job_offer.is_empty(), "Home harbor offers a real funded VoyageJobs freight contract"):
		return false
	var job_id: String = str(job_offer.get("id", ""))
	var target_port: String = str(job_offer.get("targetPort", ""))
	var acc_res: Dictionary = c.accept_voyage_job(job_id)
	if not check(bool(acc_res.get("ok", false)), "Accept funded preparation voyage job: " + str(acc_res.get("message", ""))):
		return false
	if not sail_port(target_port):
		return false
	var coins_before_job: int = int(c.state.coins)
	var escrow_held: int = int(c.VoyageJobs._find(c.state, job_id).get("escrow", 0))
	var set_res: Dictionary = c.settle_voyage_job(job_id)
	if not check(bool(set_res.get("ok", false)) and int(c.state.coins) == coins_before_job + escrow_held,
		"Settling the preparation voyage job pays the exact held client escrow"):
		return false
	note("connected_preparation_job087", {"jobId": job_id, "targetPort": target_port, "escrowPaid": escrow_held})
	return query_purity("Opening and connected outward preparation")

func verify_broken_meridian() -> bool:
	if not sail_port("reed_floats") or not provision(14):
		return false
	var pkg: Dictionary = Stories.destinations087(c.state).packages[MERIDIAN]
	var r1: String = str(pkg.firstRegionId)
	var s1: String = str(pkg.firstSiteId)
	var r2: String = str(pkg.secondRegionId)
	var s2: String = str(pkg.secondSiteId)
	var started_res: Dictionary = StoryOps.start(c, MERIDIAN)
	if not check(bool(started_res.get("ok", false)), "Sister Wren starts The Broken Meridian at Reedwater Floats"):
		return false
	var rec0: Dictionary = Stories._record(c.state, MERIDIAN)
	if not check((rec0.get("leads", []) as Array).has(s1) and not (rec0.get("leads", []) as Array).has(s2) and Stories._site_level(c.state, s1) == 0,
		"Starting Broken Meridian records only the first lead and does not sight it while in Shatter Coast"):
		return false
	var site1_def: Dictionary = c.Exploration.catalog_site(c.state, s1)
	if not stage_region_berth(r1, site1_def) or not survey_site(s1, 2):
		return false
	var first_charted: Dictionary = point("meridian-first-post-charted")
	if first_charted.is_empty():
		return false

	# Branch A: turn_home_dated087 (secrecy / reserve turn-back after first post)
	if not decision(MERIDIAN, "turn_home_dated087", ["meridian_first_charted087", "meridian_turned_home087"]):
		return false
	var rec_turn: Dictionary = Stories._record(c.state, MERIDIAN)
	if not check(not (rec_turn.get("leads", []) as Array).has(s2) and Stories._site_level(c.state, s2) == 0 and Stories.earned_leads(c.state, MERIDIAN).size() == 1,
		"Turning home after the first post never reveals or sights the second remote post"):
		return false
	if not check(Stories.site_reflection(c.state, s1).find("turned home") >= 0,
		"Site reflection at first meridian post reflects the turn-home choice"):
		return false
	if not stage_region_berth("shatter_coast", c.port("reed_floats")) or not sail_port("reed_floats"):
		return false
	var refuse_full: Dictionary = StoryOps.choose(c, MERIDIAN, "publish_full_meridian087")
	if not check(not bool(refuse_full.get("ok", true)), "Full-table publication is refused when the expedition turned home early"):
		return false
	var wren_before_partial: int = int(c.Contacts._find(c.state, "sister_wren").loyalty)
	var reed_before_partial: int = int(c.Factions.standing(c.state, "reed").score)
	if not decision(MERIDIAN, "file_partial_meridian087", ["meridian_partial_filed087"]):
		return false
	if not check(int(c.Contacts._find(c.state, "sister_wren").loyalty) == wren_before_partial + 3 and int(c.Factions.standing(c.state, "reed").score) == reed_before_partial + 2,
		"Filing the single-station sight awards Reed +2 and Wren +3"):
		return false
	if not check(not Offers.available(c).any(func(o): return str(o.get("id", "")).begins_with("chainfreight-meridian-")),
		"Single-station partial filing does not unlock full-meridian follow-on freight"):
		return false

	# Branch B: restore first_charted, push_farther_meridian087 -> survey second site -> file full table
	if not restore_point(first_charted):
		return false
	if not decision(MERIDIAN, "push_farther_meridian087", ["meridian_first_charted087", "meridian_pushed_farther087"]):
		return false
	var rec_push: Dictionary = Stories._record(c.state, MERIDIAN)
	if not check((rec_push.get("leads", []) as Array).has(s2) and Stories._site_level(c.state, s2) == 0,
		"Pushing farther records the second remote lead without sighting it from the first group's chart"):
		return false
	var site2_def: Dictionary = c.Exploration.catalog_site(c.state, s2)
	if not stage_region_berth(r2, site2_def) or not survey_site(s2, 3):
		return false
	if not decision(MERIDIAN, "record_paired_meridian087", ["meridian_full_survey087"]):
		return false
	if not stage_region_berth("shatter_coast", c.port("reed_floats")) or not sail_port("reed_floats"):
		return false
	var ready_to_file: Dictionary = point("meridian-full-ready-to-file")
	if ready_to_file.is_empty():
		return false

	# Sub-branch B1: retain_full_meridian087 unlocks chainfreight-meridian-retained087 at Brass Haven
	if not decision(MERIDIAN, "retain_full_meridian087", ["meridian_retained087"]):
		return false
	if not sail_port("brass_haven"):
		return false
	if not check(Offers.available(c).any(func(o): return str(o.get("id", "")) == "chainfreight-meridian-retained087"),
		"Retaining the outer meridian arc unlocks the once-only factor passage at Brass Haven"):
		return false

	# Sub-branch B2: restore ready_to_file, publish_full_meridian087 and settle chainfreight-meridian-public087
	if not restore_point(ready_to_file):
		return false
	var wren_before: int = int(c.Contacts._find(c.state, "sister_wren").loyalty)
	var reed_before: int = int(c.Factions.standing(c.state, "reed").score)
	var compact_before: int = int(c.Factions.standing(c.state, "compact").score)
	if not decision(MERIDIAN, "publish_full_meridian087", ["meridian_public087"]):
		return false
	if not check(int(c.Contacts._find(c.state, "sister_wren").loyalty) == wren_before + 7
		and int(c.Factions.standing(c.state, "reed").score) == reed_before + 4
		and int(c.Factions.standing(c.state, "compact").score) == compact_before - 2,
		"Publishing the full meridian table applies Reed +4, Compact -2 and Wren +7"):
		return false
	if not check(Offers.available(c).any(func(o): return str(o.get("id", "")) == "chainfreight-meridian-public087"),
		"Publishing the full meridian table unlocks chainfreight-meridian-public087 at Reedwater Floats"):
		return false
	var acc_mer: Dictionary = c.accept_voyage_job("chainfreight-meridian-public087")
	if not check(bool(acc_mer.get("ok", false)), "Accept chainfreight-meridian-public087: " + str(acc_mer.get("message", ""))):
		return false
	if not sail_port("silt_hollow"):
		return false
	var del_mer: Dictionary = c.settle_voyage_job("chainfreight-meridian-public087")
	if not check(bool(del_mer.get("ok", false)) and bool(c.state.storyRights.usedOffers.get("chainfreight-meridian-public087", false)),
		"Deliver chainfreight-meridian-public087 at Silt Hollow once-only"):
		return false
	accountfacts.append({"package": MERIDIAN, "firstRegionId": r1, "secondRegionId": r2, "outcome": "meridian_public087"})
	return query_purity("Completed broken_meridian087")

func verify_unfinished_keel() -> bool:
	if not sail_port("anvil_dock") or not provision(14):
		return false
	var pkg: Dictionary = Stories.destinations087(c.state).packages[KEEL]
	var rk: String = str(pkg.regionId)
	var sk: String = str(pkg.siteId)
	var source_id: String = str(pkg.sourceId)
	var started_res: Dictionary = StoryOps.start(c, KEEL)
	if not check(bool(started_res.get("ok", false)), "Mara Voss starts The Unfinished Keel at Anvil Dock"):
		return false
	var site_def: Dictionary = c.Exploration.catalog_site(c.state, sk)
	if not stage_region_berth(rk, site_def):
		return false
	if not check(not c.state.wrecks.any(func(w): return w is Dictionary and str(w.get("sourceId", "")) == source_id),
		"No slipway workboat wreck exists before the landing is fully surveyed"):
		return false
	if not survey_site(sk, 2):
		return false
	if not check(not c.state.wrecks.any(func(w): return w is Dictionary and str(w.get("sourceId", "")) == source_id),
		"Charting to level 2 does not prematurely seed the level-3 slipway wreck"):
		return false
	if not survey_site(sk, 3):
		return false
	var keel_wrecks: Array = c.state.wrecks.filter(func(w): return w is Dictionary and str(w.get("sourceId", "")) == source_id)
	if not check(keel_wrecks.size() == 1 and bool(c.state.get("wreckSeededSources", {}).get(source_id, false)),
		"Completing the level-3 survey seeds exactly one finite slipway wreck and records its tombstone"):
		return false
	var wreck: Dictionary = keel_wrecks[0]
	var wreck_id: String = str(wreck.id)
	if not check(normalized(wreck.get("stores", {})) == normalized(Salvage.KEEL087_STORES)
		and str(wreck.get("world064", {}).get("regionId", "")) == rk,
		"Seeded slipway wreck carries canonical finite stores in the bound remote local chart"):
		return false
	if not decision(KEEL, "inspect_keel_manifest087", ["keel_surveyed087"]):
		return false
	var keel_ready: Dictionary = point("keel-surveyed-before-recovery")
	if keel_ready.is_empty():
		return false

	# Premature choice refusals before paid recovery:
	var pre_paid: Dictionary = StoryOps.choose(c, KEEL, "log_paid_keel_strip087")
	var pre_empty: Dictionary = StoryOps.choose(c, KEEL, "record_exhausted_keel087")
	if not check(not bool(pre_paid.get("ok", true)) and not bool(pre_empty.get("ok", true)),
		"Paid-strip and exhaustion choices are refused while the slipway cradle is still unworked and stocked"):
		return false

	# Alternate Branch 2A: leave_keel_for_margin087 -> keep_private_keel_notes087
	if not decision(KEEL, "leave_keel_for_margin087", ["keel_left_intact087"]):
		return false
	if not stage_region_berth("shatter_coast", c.port("anvil_dock")) or not sail_port("anvil_dock"):
		return false
	var mara_before_priv: int = int(c.Contacts._find(c.state, "mara_voss").loyalty)
	var cass_before_priv: int = int(c.Contacts._find(c.state, "salvager_cass").loyalty)
	if not decision(KEEL, "keep_private_keel_notes087", ["keel_ledger_private087"]):
		return false
	if not check(int(c.Contacts._find(c.state, "mara_voss").loyalty) == mara_before_priv - 3
		and int(c.Contacts._find(c.state, "salvager_cass").loyalty) == cass_before_priv + 5,
		"Withholding the slipway notes applies Mara -3 and Cass +5 without claiming paid recovery"):
		return false

	# Alternate Branch 2A-2: declared exhausted vs missing slipway source
	if not restore_point(keel_ready):
		return false
	for w in c.state.wrecks:
		if w is Dictionary and str(w.get("sourceId", "")) == source_id:
			w["stores"] = {"engines": 0.0, "iron": 0.0, "supplies": 0.0, "timber": 0.0}
	if not decision(KEEL, "record_exhausted_keel087", ["keel_verified_empty087"]):
		return false
	if not check(not (Stories._record(c.state, KEEL).get("flags", []) as Array).has("paid_keel_source087"),
		"Verified exhaustion never claims paid_keel_source087"):
		return false
	if not restore_point(keel_ready):
		return false
	c.state.wrecks = c.state.wrecks.filter(func(w): return not (w is Dictionary and str(w.get("sourceId", "")) == source_id))
	var missing_exhausted: Dictionary = StoryOps.choose(c, KEEL, "record_exhausted_keel087")
	if not check(not bool(missing_exhausted.get("ok", true)),
		"Missing slipway source refuses exhaustion claim"):
		return false

	# Main Branch 2B: restore keel_ready, perform real paid recovery, and close ledger at Anvil Dock
	if not restore_point(keel_ready):
		return false
	var iron_before: float = float(c.state.cargo.get("iron", 0.0))
	var kits_before: float = float(c.Remote067.kits(c.state))
	var day_before: float = float(c.state.day)
	var quote: Dictionary = c.recovery_quote(wreck_id, "strip", "iron", 1)
	if not check(bool(quote.get("ok", false)) and bool(quote.get("cargoOnly", false)),
		"Remote067 recovery quote admits surveyed slipway workboat cradle"):
		return false
	var rec_receipt: Dictionary = c.recover_wreck(wreck_id, "strip", "iron", 1)
	if not check(bool(rec_receipt.get("ok", false)) and bool(rec_receipt.get("completed", false)),
		"Paid slipway recovery completes: " + str(rec_receipt.get("message", ""))):
		return false
	if not settle_pending():
		return false
	var wreck_after: Dictionary = c.find_wreck(wreck_id)
	var rec_keel: Dictionary = Stories._record(c.state, KEEL)
	if not check(float(c.state.cargo.get("iron", 0.0)) == iron_before + 1.0
		and float(wreck_after.stores.get("iron", 0.0)) == 5.0
		and float(c.Remote067.kits(c.state)) == kits_before - 0.25
		and float(c.state.day) > day_before
		and (rec_keel.get("flags", []) as Array).has("paid_keel_source087"),
		"Paid slipway recovery consumes 0.25 kit, advances clock, moves 1 iron from wreck to hold, and sets paid_keel_source087"):
		return false
	var leave_after_paid: Dictionary = StoryOps.choose(c, KEEL, "leave_keel_for_margin087")
	var empty_after_paid: Dictionary = StoryOps.choose(c, KEEL, "record_exhausted_keel087")
	if not check(not bool(leave_after_paid.get("ok", true)) and not bool(empty_after_paid.get("ok", true)),
		"Intact-leave and exhaustion branches are refused once a paid slipway recovery is recorded"):
		return false
	if not decision(KEEL, "log_paid_keel_strip087", ["keel_recovered_paid087"]):
		return false
	if not stage_region_berth("shatter_coast", c.port("anvil_dock")) or not sail_port("anvil_dock"):
		return false
	var forge_before: int = int(c.Factions.standing(c.state, "forge").score)
	var raiders_before: int = int(c.Factions.standing(c.state, "raiders").score)
	var mara_before: int = int(c.Contacts._find(c.state, "mara_voss").loyalty)
	if not decision(KEEL, "close_forge_keel_ledger087", ["keel_ledger_forge087"]):
		return false
	if not check(int(c.Factions.standing(c.state, "forge").score) == forge_before + 4
		and int(c.Factions.standing(c.state, "raiders").score) == raiders_before - 2
		and int(c.Contacts._find(c.state, "mara_voss").loyalty) == mara_before + 6,
		"Closing the slipway ledger at Anvil Dock applies Forge +4, Raiders -2 and Mara +6"):
		return false
	var after_keel_cp: Dictionary = point("keel-paid-and-closed")
	if after_keel_cp.is_empty() or not restore_point(after_keel_cp):
		return false
	var persisted_wrecks: Array = c.state.wrecks.filter(func(w): return w is Dictionary and str(w.get("sourceId", "")) == source_id)
	if not check(persisted_wrecks.size() == 1 and float(persisted_wrecks[0].stores.get("iron", 0.0)) == 5.0,
		"Save/restore preserves reduced slipway stock (5 iron) without refilling or re-seeding"):
		return false
	recovery_facts.append({
		"wreckId": wreck_id, "sourceId": source_id, "good": "iron", "qty": 1,
		"remainingIron": float(persisted_wrecks[0].stores.get("iron", 0.0)),
		"receipt": rec_receipt
	})
	accountfacts.append({"package": KEEL, "regionId": rk, "siteId": sk, "outcome": "keel_ledger_forge087"})
	return query_purity("Completed unfinished_keel087")

func verify_two_lantern_anchorage() -> bool:
	if not sail_port("brass_haven") or not provision(14):
		return false
	var pkg: Dictionary = Stories.destinations087(c.state).packages[LANTERN]
	var rl: String = str(pkg.regionId)
	var sl: String = str(pkg.siteId)
	var pl: String = str(pkg.portId)
	var fl: String = str(pkg.faction)
	var started_res: Dictionary = StoryOps.start(c, LANTERN)
	if not check(bool(started_res.get("ok", false)), "Tobin Hale starts Two-Lantern Anchorage at Brass Haven"):
		return false
	var site_def: Dictionary = c.Exploration.catalog_site(c.state, sl)
	if not stage_region_berth(rl, site_def) or not survey_site(sl, 2):
		return false
	if not decision(LANTERN, "record_lantern_alignment087", ["lantern_headland_charted087"]):
		return false
	if not ensure_faction_access(fl) or not sail_port(pl):
		return false
	var frontier_port: Dictionary = c.work_port070()
	if not check(str(frontier_port.get("id", "")) == pl and is_same(frontier_port, c.port(pl)),
		"Docked at the bound frontier harbor account: " + pl):
		return false
	var player_kits_before: float = float(c.state.cargo.get("supplies", 0.0))
	var harbor_kits_before: float = float(frontier_port.stocks.get("supplies", 0.0))
	var tobin_before_kits: int = int(c.Contacts._find(c.state, "tobin_hale").loyalty)
	if not decision(LANTERN, "deliver_lantern_kits087", ["supplied_lantern_berth087"]):
		return false
	if not check(is_equal_approx(float(c.state.cargo.get("supplies", 0.0)), player_kits_before - 4.0)
		and is_equal_approx(float(frontier_port.stocks.get("supplies", 0.0)), harbor_kits_before + 4.0)
		and int(c.Contacts._find(c.state, "tobin_hale").loyalty) == tobin_before_kits + 4,
		"Delivering four repair kits transfers 4 supplies from player hold into the frontier harbor stock and records Tobin +4"):
		return false
	var lantern_supplied: Dictionary = point("lantern-supplied-at-frontier-harbor")
	if lantern_supplied.is_empty():
		return false

	# Alternate Branch 3A: post_open_lantern_notice087 (Reed +4, Compact -2, Wren +5)
	if not decision(LANTERN, "post_open_lantern_notice087", ["lantern_channel_public087"]):
		return false
	if not restore_point(lantern_supplied):
		return false

	# Main Branch 3B: bind_local_lantern_desk087 (Compact +4, Reed -2, Tobin +6) + follow-on freight
	var compact_before: int = int(c.Factions.standing(c.state, "compact").score)
	var reed_before: int = int(c.Factions.standing(c.state, "reed").score)
	var tobin_before: int = int(c.Contacts._find(c.state, "tobin_hale").loyalty)
	if not decision(LANTERN, "bind_local_lantern_desk087", ["lantern_channel_bonded087"]):
		return false
	if not check(int(c.Factions.standing(c.state, "compact").score) == compact_before + 4
		and int(c.Factions.standing(c.state, "reed").score) == reed_before - 2
		and int(c.Contacts._find(c.state, "tobin_hale").loyalty) == tobin_before + 6,
		"Bonding the frontier range applies Compact +4, Reed -2 and Tobin +6"):
		return false
	if not stage_region_berth("shatter_coast", c.port("brass_haven")) or not sail_port("brass_haven"):
		return false
	if not check(Offers.available(c).any(func(o): return str(o.get("id", "")) == "chainfreight-lantern-bonded087"),
		"Bonding the frontier range unlocks chainfreight-lantern-bonded087 at Brass Haven"):
		return false
	var acc_lan: Dictionary = c.accept_voyage_job("chainfreight-lantern-bonded087")
	if not check(bool(acc_lan.get("ok", false)), "Accept chainfreight-lantern-bonded087: " + str(acc_lan.get("message", ""))):
		return false
	if not sail_port("silt_hollow"):
		return false
	var del_lan: Dictionary = c.settle_voyage_job("chainfreight-lantern-bonded087")
	if not check(bool(del_lan.get("ok", false)) and bool(c.state.storyRights.usedOffers.get("chainfreight-lantern-bonded087", false)),
		"Deliver chainfreight-lantern-bonded087 at Silt Hollow once-only"):
		return false
	accountfacts.append({"package": LANTERN, "regionId": rl, "siteId": sl, "portId": pl, "outcome": "lantern_channel_bonded087"})
	return query_purity("Completed two_lantern_anchorage087")

func verify_guards_and_legacy_saves(opening_cp: Dictionary, completed_cp: Dictionary) -> bool:
	# 1. Visited-landing rebind before starting an unstarted 087 chain:
	if not restore_point(opening_cp):
		return false
	var before_keel_site: String = str(Stories.destinations087(c.state).packages[KEEL].siteId)
	c.state.exploration.sites[before_keel_site] = {"level": 1, "rewarded": false}
	StoryOps.ensure(c)
	var rebound_keel_site: String = str(Stories.destinations087(c.state).packages[KEEL].siteId)
	if not check(rebound_keel_site != before_keel_site and Stories._site_level(c.state, rebound_keel_site) == 0,
		"Visiting a landing before starting an 087 chain rebinds that unstarted chain to an unvisited landing"):
		return false

	# 2. Legacy two-region save compatibility (no reroll, 087 packages cleanly unavailable):
	var legacy: Dictionary = (opening_cp["saved"] as Dictionary).duplicate(true)
	for key in ["sector069", "sectorApplied069", "sectorKnowledge069", "islandOwnership069"]:
		legacy.erase(key)
	var base_port_ids: Dictionary = {}
	for p in home_data.get("PORTS", []):
		if p is Dictionary:
			base_port_ids[str(p.get("id", ""))] = true
	legacy["ports"] = (legacy.get("ports", []) as Array).filter(func(p): return p is Dictionary and base_port_ids.has(str(p.get("id", ""))))
	legacy["fleetOwners"] = (legacy.get("fleetOwners", []) as Array).filter(func(o): return o is Dictionary and base_port_ids.has(str(o.get("homePort", ""))))
	var gen_site_ids: Dictionary = {}
	for g in (opening_cp["saved"] as Dictionary).get("sector069", {}).get("groups", []):
		if g is Dictionary:
			for l in g.get("landings", []):
				if l is Dictionary:
					gen_site_ids[str(l.get("id", ""))] = true
	legacy["exploration"]["catalog"] = (legacy["exploration"]["catalog"] as Array).filter(func(s): return s is Dictionary and not gen_site_ids.has(str(s.get("id", ""))))
	for sid in gen_site_ids:
		legacy["exploration"]["sites"].erase(sid)
	legacy["stories"]["destinations087"] = {
		"schema": 1, "bound": false, "available": false,
		"status": "unavailable_legacy_two_region", "packages": {}
	}
	legacy["coinSupply"] = Money.total(legacy)
	var legacy_campaign = Campaign.new(home_data, home_nav, false)
	legacy_campaign.ocean_anchors064 = home_anchors
	var leg_res: Dictionary = legacy_campaign.restore(legacy)
	if not check(bool(leg_res.get("ok", false)) and not legacy_campaign.state.has("sector069"),
		"Legacy two-region save restores cleanly without rerolling sector069: " + str(leg_res.get("message", ""))):
		return false
	var leg_dest: Dictionary = Stories.destinations087(legacy_campaign.state)
	if not check(not bool(leg_dest.get("available", true)) and str(leg_dest.get("status", "")) == "unavailable_legacy_two_region",
		"Legacy two-region save reports v0.087 packages as unavailable_legacy_two_region"):
		return false
	if not check(not Stories.available(legacy_campaign).any(func(o): return str(o.get("id", "")) in Stories.CHAINS087),
		"Legacy two-region save never offers v0.087 remote destination chains"):
		return false
	legacy_campaign = null

	# 3. Corrupt raw save refusals:
	if not restore_point(completed_cp):
		return false
	for case_name in ["legacy_claimed_bound", "turned_home_with_second_lead", "forged_keel_wreck_without_tombstone"]:
		var bad: Dictionary = (completed_cp["saved"] as Dictionary).duplicate(true)
		if case_name == "legacy_claimed_bound":
			var bad_leg: Dictionary = legacy.duplicate(true)
			bad_leg["stories"]["destinations087"]["bound"] = true
			bad = bad_leg
		elif case_name == "turned_home_with_second_lead":
			bad["stories"]["chains"][MERIDIAN]["flags"].append("meridian_turned_home087")
		elif case_name == "forged_keel_wreck_without_tombstone":
			bad["wreckSeededSources"] = {}
		var probe = Campaign.new(home_data, home_nav, false)
		probe.ocean_context064 = home_context
		probe.ocean_anchors064 = home_anchors
		var refused: Dictionary = probe.restore(bad)
		if not check(not bool(refused.get("ok", true)),
			"Corrupt raw save case (" + case_name + ") is refused before publication"):
			return false
		note("corrupt_save_refused087", {"case": case_name, "message": str(refused.get("message", ""))})
	return true

func closing_accounts(label: String) -> bool:
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	if not check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), label + ": equipment custody stays canonical"):
		return false
	var items_now: Array = custody.itemUids.duplicate()
	items_now.sort()
	var boats_now: Array = []
	for boat in fleet_book(c.state):
		boats_now.append(str(boat.uid))
	boats_now.sort()
	if not check(items_now == initial_items and boats_now == initial_boats,
		label + ": no free hulls or equipment items were minted or deleted"):
		return false
	if not check(Money.total(c.state) == supply and people(c.state) == initial_people and int(c.state.wageArrears) == 0,
		label + ": world coin supply, total people and zero wage arrears are conserved"):
		return false
	if not check(normalized([c.state.sector069, c.state.islandOwnership069]) == geography,
		label + ": seeded 48-group geography and political island ownership remain unchanged"):
		return false
	for cid in Stories.CHAINS087:
		var rec: Dictionary = Stories._record(c.state, str(cid))
		if not check(bool(rec.get("done", false)), label + ": chain completed in final witness: " + str(cid)):
			return false
	return query_purity(label)

func write_completed_witness() -> bool:
	var dir_path: String = OS.get_environment("GAME_TEST_ARTIFACTS").strip_edges()
	if dir_path.is_empty():
		dir_path = "user://quality087_artifacts"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var out_path: String = dir_path.path_join("remote-destinations087-completed.json")
	var payload: String = JSON.stringify(c.state, "\t")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if not check(f != null, "Open witness artifact for writing: " + out_path):
		return false
	f.store_string(payload)
	f.close()
	var sha: String = FileAccess.get_sha256(out_path)
	artifacts["completedWitness"] = {"path": out_path, "sha256": sha, "bytes": payload.length()}
	return check(not sha.is_empty(), "Completed v0.087 witness JSON written and hashed")

func finish() -> void:
	var _joined: Dictionary = workers.finish(true)
	c = null
	var elapsed: int = Time.get_ticks_msec() - started
	check(elapsed < BODY_LIMIT_MS, "Body includes initialization, all three v0.087 destination packages, restores and cleanup below fifty-five seconds")
	print(JSON.stringify({
		"fixture": "remote_destinations087",
		"checks": checks,
		"failures": failures,
		"elapsed_ms": elapsed,
		"complete": complete and failures == 0 and not expired,
		"failure_labels": failure_labels,
		"events": events,
		"accountfacts": accountfacts,
		"recovery": recovery_facts,
		"artifacts": artifacts,
		"limits": "Declared finite treasury-funded ninety-day expedition reserve, staged regional local-chart berths, faction service-access adjustment for generated frontier harbor, and dormant unrelated NPC patrol profile; connected to an actual funded home-waters VoyageJobs freight contract and settlement, real shore chart/survey work, real paid slipway wreck recovery, and real 4-kit frontier harbor delivery. No rendering, listening or whole-game-quality claim."
	}))
	quit(0 if complete and failures == 0 and not expired else 1)

func _run() -> void:
	if not check(DisplayServer.get_name() == "headless", "Headless execution required for test_remote_destinations087"):
		finish()
		return
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not check(definitions is Dictionary, "World definitions decode cleanly"):
		finish()
		return
	c = Campaign.new(definitions)
	var opening: Dictionary = c.new_game(SEED)
	if not check(bool(opening.get("ok", false)), "Fresh 48-group campaign initializes for seed " + str(SEED)):
		finish()
		return
	home_data = c.data
	home_nav = c.nav
	home_context = c.ocean_context064
	home_anchors = c.ocean_anchors064
	supply = Money.total(c.state)
	initial_people = people(c.state)
	geography = normalized([c.state.sector069, c.state.islandOwnership069])
	var custody: Dictionary = Custody.check_state(c.state, c.data)
	if not check(bool(custody.get("ok", false)) and bool(custody.get("ready", false)), "Initial equipment custody is canonical"):
		finish()
		return
	initial_items = custody.itemUids.duplicate()
	initial_items.sort()
	for boat in fleet_book(c.state):
		initial_boats.append(str(boat.uid))
	initial_boats.sort()

	if not opening_and_connected_work():
		finish()
		return
	var opening_cp: Dictionary = point("after-connected-opening-preparation")
	if opening_cp.is_empty():
		finish()
		return
	if not verify_broken_meridian():
		finish()
		return
	if not verify_unfinished_keel():
		finish()
		return
	if not verify_two_lantern_anchorage():
		finish()
		return
	var completed_cp: Dictionary = point("all-three-087-packages-completed")
	if completed_cp.is_empty():
		finish()
		return
	if not verify_guards_and_legacy_saves(opening_cp, completed_cp):
		finish()
		return
	if not restore_point(completed_cp):
		finish()
		return
	if not closing_accounts("final-restored-087-witness") or not write_completed_witness():
		finish()
		return
	complete = true
	finish()
