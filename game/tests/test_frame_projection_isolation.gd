extends SceneTree
## Bounded native fixture for R3 frame equipment projection cache admission, copy isolation,
## invalidation, legacy/null/invalid owner safety, and instantaneous vs tick-average status separation.

const Damage = preload("res://scripts/damage.gd")
const EquipmentDamage = preload("res://scripts/equipment_damage.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")
const Records = preload("res://scripts/equipment_records.gd")
const Core = preload("res://scripts/equipment_condition.gd")
const Refit = preload("res://scripts/refit.gd")

var world: Dictionary = {}
var catalog: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL frame_projection_isolation: " + message)

func _approx(a: float, b: float, tol: float = 0.0001) -> bool:
	return absf(a - b) <= tol

func _hull_by_id(hull_id: String) -> Dictionary:
	for h in world.get("HULLS", []):
		if str(h.get("id", "")) == hull_id:
			return h.duplicate(true)
	return world.HULLS[0].duplicate(true)

func _canonical_boat(hull_id: String, identity: String, overrides: Dictionary = {}, custom_loadout: Dictionary = {}) -> Dictionary:
	var base: Dictionary = _hull_by_id(hull_id)
	var boat: Dictionary = Damage.create_ship(base, overrides)
	boat.baseSpec = base.duplicate(true)
	if not custom_loadout.is_empty():
		var norm: Dictionary = Refit.normalize(base, custom_loadout)
		check(norm.ok, "custom loadout normalizes for " + identity)
		boat.loadout = norm.loadout
	Refit.ensure(boat, base)
	boat.uid = identity
	var init_res: Dictionary = Records.initialize(boat, {"base": base, "loadout": boat.loadout, "catalog": catalog, "identity": identity, "knownUids": []})
	check(init_res.ok, "Records.initialize succeeded for " + identity)
	return boat

func _item_at(condition: Dictionary, location: String) -> Dictionary:
	for uid in condition.get("items", {}).keys():
		var item: Dictionary = condition.items[uid]
		if str(item.get("location", "")) == location:
			return item
	return {}

func test_posttick_admission_and_same_id_copy_isolation() -> void:
	var fit: Dictionary = {"weapons": ["stock_primary", "rapid_gun"], "engine": "stock_engine", "armor": "stock_armor"}
	var live: Dictionary = _canonical_boat("tin_skiff", "proj-iso-live-1", {"id": "player-1", "hp": 100.0, "fuel": 45.0, "crew": 5.0, "supplies": 18.0}, fit)
	var frame_cache: Dictionary = {}

	# 1. Cold inspect_owner_cached / get_status_cached must NOT auto-admit on a cache miss.
	var cold_info: Dictionary = Damage.inspect_owner_cached(live, frame_cache)
	var cold_st: Dictionary = Damage.get_status_cached(live, frame_cache)
	check(bool(cold_info.get("ok", false)) and str(cold_info.get("mode", "")) == "canonical", "cold inspect_owner_cached returns valid canonical info")
	check(cold_st == Damage.get_status(live), "cold get_status_cached matches public Damage.get_status")
	check(frame_cache.is_empty(), "inspect_owner_cached miss never inserts into frame_cache before Damage.tick_ship")

	# 2. Damage.tick_ship is the sole admission point and seeds the post-tick live ship entry.
	var tick_st: Dictionary = Damage.tick_ship(live, 1.0 / 30.0, {"inCombat": true}, frame_cache)
	check(bool(tick_st.get("equipmentOk", false)) and frame_cache.size() == 1 and frame_cache.has("player-1"), "Damage.tick_ship admits live canonical ship into frame_cache")
	var live_entry: Dictionary = frame_cache["player-1"]
	var live_info: Dictionary = live_entry.info
	check(is_same(live_entry.shipRef, live), "frame_cache slot stores exact live ship reference")
	check(is_same(Damage.inspect_owner_cached(live, frame_cache), live_info), "subsequent inspect_owner_cached on live ship hits cached info reference")
	check(Damage.get_status_cached(live, frame_cache) == Damage.get_status(live), "warmed get_status_cached matches public Damage.get_status")

	# 3. Same-ID canonical copy with different HP/fuel/crew/gear gets fresh result and leaves frame_cache byte-equal.
	var cache_snap: Dictionary = frame_cache.duplicate(true)
	var cache_bytes: PackedByteArray = var_to_bytes(frame_cache)
	var copy_can: Dictionary = live.duplicate(true)
	copy_can.hp = 42.0
	copy_can.fuel = 0.0
	copy_can.crew = 2.0
	copy_can.wounded = 1.0
	copy_can.water = 50.0
	copy_can.breaches = [{"area": 14.0, "section": "bow"}]
	var copy_eng_uid: String = str(_item_at(copy_can.moduleCondition, "engine").itemUid)
	var copy_m0_uid: String = str(_item_at(copy_can.moduleCondition, "mount0").itemUid)
	check(Core.apply_component_damage(copy_can.moduleCondition, {"itemUid": copy_eng_uid, "loss": 0.55, "cause": "Copy engine wear"}).ok, "same-ID canonical copy engine damaged to 0.45")
	check(Core.apply_component_damage(copy_can.moduleCondition, {"itemUid": copy_m0_uid, "loss": 0.85, "cause": "Copy mount0 disabled"}).ok, "same-ID canonical copy mount0 disabled at 0.15")
	Records.publish(copy_can)

	var copy_info: Dictionary = Damage.inspect_owner_cached(copy_can, frame_cache)
	var copy_st_cached: Dictionary = Damage.get_status_cached(copy_can, frame_cache)
	var copy_st_fresh: Dictionary = Damage.get_status(copy_can)
	var copy_combat_st: Dictionary = EquipmentCombat.status_of(copy_can, {}, frame_cache)
	var copy_mounts: Array = EquipmentCombat.apply_mount_condition(copy_can, copy_can.spec.weaponMounts, {}, frame_cache)
	var copy_caps: Dictionary = EquipmentCombat.capability_fields(copy_can, {}, NAN, frame_cache)

	check(not is_same(copy_info, live_info) and _approx(float(copy_info.snapshot.engineFactor), 0.45), "same-ID canonical copy receives fresh inspect_owner projection (engineFactor=0.45)")
	check(copy_st_cached == copy_st_fresh and copy_combat_st == copy_st_fresh, "same-ID canonical copy get_status_cached and EquipmentCombat.status_of match fresh public get_status")
	check(_approx(float(copy_st_cached.pump), 0.0) and _approx(float(copy_st_cached.engineFactor), 0.45) and float(copy_st_cached.speedFactor) < float(tick_st.speedFactor), "same-ID copy reflects its own HP/fuel=0/crew=2/damaged engine rather than live ship cache")
	check(_approx(float(copy_mounts[0].damage), 0.0) and _approx(float(copy_caps.get("mount0", 1.0)), 0.0), "same-ID copy disabled mount0 is reported as 0.0 factor")
	check(frame_cache.size() == 1 and frame_cache.keys() == ["player-1"] and var_to_bytes(frame_cache) == cache_bytes and frame_cache == cache_snap, "same-ID canonical copy leaves frame_cache byte-equal without adding __ship_n entries")
	check(is_same(frame_cache["player-1"], live_entry) and is_same(Damage.inspect_owner_cached(live, frame_cache), live_info), "live ship entry and info reference remain untouched in frame_cache")

	# 4. Invalid and private copies never insert into or evict the live entry in frame_cache.
	var priv_view: Dictionary = live.duplicate(true)
	priv_view.erase("moduleCondition")
	priv_view.status = Damage.get_status(live)
	priv_view.fuel = 0.0
	priv_view.water = 60.0

	var priv_prefix: Dictionary = live.duplicate(true)
	Damage._tick_canonical_numeric(priv_prefix, 1.0 / 60.0, {"inCombat": true})

	var bad_seq_copy: Dictionary = live.duplicate(true)
	bad_seq_copy.moduleCondition.nextItemSeq = 0
	bad_seq_copy.status = Damage.get_status(live)

	var bad_foreign_copy: Dictionary = live.duplicate(true)
	bad_foreign_copy.weaponCondition = {"mount0":0.5}

	var bad_nopump_copy: Dictionary = live.duplicate(true)
	var pump_uid: String = str(_item_at(bad_nopump_copy.moduleCondition, "pumps").itemUid)
	bad_nopump_copy.moduleCondition.items.erase(pump_uid)

	var rng := RandomNumberGenerator.new(); rng.seed = 99
	for priv in [priv_view, priv_prefix]:
		var p_st: Dictionary = Damage.get_status_cached(priv, frame_cache)
		check(p_st == Damage.get_status(priv), "private copy get_status_cached matches fresh Damage.get_status")
		Damage.invalidate_frame_cache(frame_cache, priv)
	Damage.tick_ship(priv_view, 1.0 / 60.0, {}, frame_cache)
	Damage.apply_hit(priv_view, {"damage": 15.0, "kind": "bullet"}, rng, frame_cache)

	for bad_copy in [bad_seq_copy, bad_foreign_copy, bad_nopump_copy]:
		var b_info: Dictionary = Damage.inspect_owner_cached(bad_copy, frame_cache)
		var b_st: Dictionary = Damage.get_status_cached(bad_copy, frame_cache)
		var b_ec: Dictionary = EquipmentCombat.status_of(bad_copy, {}, frame_cache)
		check(not bool(b_info.get("ok", true)) and str(b_info.get("mode", "")) == "invalid", "corrupt same-ID copy inspect_owner_cached fails closed as invalid")
		check(not bool(b_st.get("equipmentOk", true)) and str(b_st.get("equipmentMode", "")) == "invalid" and _approx(float(b_st.speedFactor), 0.0) and _approx(float(b_st.turnFactor), 0.0) and _approx(float(b_st.weaponFactor), 0.0), "corrupt same-ID copy get_status_cached fails closed with zero factors")
		check(b_ec == b_st, "EquipmentCombat.status_of ignores stale ship.status on corrupt canonical copy")
		Damage.invalidate_frame_cache(frame_cache, bad_copy)
		Damage.tick_ship(bad_copy, 1.0 / 30.0, {"inCombat": true}, frame_cache)
		Damage.apply_hit(bad_copy, {"damage": 25.0, "kind": "shell"}, rng, frame_cache)

	check(frame_cache.size() == 1 and frame_cache.keys() == ["player-1"] and var_to_bytes(frame_cache) == cache_bytes and is_same(frame_cache["player-1"], live_entry) and is_same(Damage.inspect_owner_cached(live, frame_cache), live_info), "private and invalid copies never insert into or evict live entry from frame_cache")

func test_warmed_live_damage_repair_invalidation_and_public_get_status_fresh() -> void:
	var live: Dictionary = _canonical_boat("tin_skiff", "proj-iso-live-2", {"id": "player-2", "hp": 100.0, "fuel": 50.0, "supplies": 20.0, "policy": "repair"})
	var frame_cache: Dictionary = {}
	Damage.tick_ship(live, 1.0 / 30.0, {"inCombat": true}, frame_cache)
	check(frame_cache.has("player-2"), "live ship warmed in frame_cache after tick_ship")

	# 1. Live combat hit via Damage.apply_hit invalidates frame_cache and recomputes vs public get_status.
	var rng := RandomNumberGenerator.new(); rng.seed = 12345
	var events: Array = Damage.apply_hit(live, {"damage": 54.0, "kind": "shell", "penetration": 10.0, "section": "engine"}, rng, frame_cache)
	check(not events.is_empty() and frame_cache.is_empty(), "Damage.apply_hit on warmed live ship invalidates its frame_cache entry")
	var st_post_hit_cached: Dictionary = Damage.get_status_cached(live, frame_cache)
	var st_post_hit_public: Dictionary = Damage.get_status(live)
	check(st_post_hit_cached == st_post_hit_public and float(st_post_hit_cached.engineFactor) < 1.0 and float(live.hp) < 100.0, "post-hit get_status_cached recomputes damaged engine/hull matching public get_status")
	check(frame_cache.is_empty(), "post-hit get_status_cached miss stays uncached until next tick_ship seeds")

	# 2. Re-warm via tick_ship on independent canonical tin_skiff, then in-frame repair / component mutation evicts stale entry and recomputes matching public get_status.
	Damage.clear_frame_cache(frame_cache)
	var repair_live: Dictionary = _canonical_boat("tin_skiff", "proj-iso-live-2-repair", {"id": "player-2", "fuel": 50.0, "supplies": 20.0, "policy": "repair", "fire": 0.0, "water": 0.0, "breaches": []})
	var rep_eng_uid: String = str(_item_at(repair_live.moduleCondition, "engine").itemUid)
	var rep_dmg: Dictionary = Core.apply_component_damage(repair_live.moduleCondition, {"itemUid": rep_eng_uid, "loss": 0.5, "cause": "Repair isolation engine wear"})
	var rep_pub: Dictionary = Records.publish(repair_live)
	check(frame_cache.is_empty() and rep_dmg.ok and rep_pub.ok and _approx(float(_item_at(repair_live.moduleCondition, "engine").hp), 0.5) and float(_item_at(repair_live.moduleCondition, "engine").hp) < Core.JURY_CAP, "repair_live engine damaged to 0.5 below 0.75 jury cap after explicit cache clear")
	check(_approx(float(repair_live.hp), float(repair_live.maxHp)) and _approx(float(repair_live.crew), float(repair_live.crewOptimal)) and _approx(float(repair_live.wounded), 0.0) and _approx(float(repair_live.fire), 0.0) and _approx(float(repair_live.water), 0.0) and repair_live.breaches.is_empty() and _approx(Damage.sum_areas(repair_live), 0.0), "repair_live has full default hull HP/crew and zero competing fire/water/breach patch tasks")
	Damage.tick_ship(repair_live, 1.0 / 30.0, {"inCombat": true, "priority": "engine"}, frame_cache)
	check(frame_cache.has("player-2"), "next tick_ship re-seeds live ship in frame_cache")
	var eng_before_step: float = float(_item_at(repair_live.moduleCondition, "engine").hp)
	var supplies_before_step: float = float(repair_live.supplies)
	var rep_step: Dictionary = EquipmentDamage.tick_repair_step(repair_live, 1.0 / 30.0, 2.5, {"priority": "engine"})
	check(rep_step.ok and float(_item_at(repair_live.moduleCondition, "engine").hp) > eng_before_step and float(repair_live.supplies) < supplies_before_step and float(rep_step.get("usedSupplies", 0.0)) > 0.0, "in-frame tick_repair_step advances engine HP and consumes supplies")
	var st_after_rep_cached: Dictionary = Damage.get_status_cached(repair_live, frame_cache)
	var st_after_rep_public: Dictionary = Damage.get_status(repair_live)
	check(frame_cache.is_empty(), "stale warmed live entry is evicted when _cache_entry_valid detects in-frame repair")
	check(st_after_rep_cached == st_after_rep_public and _approx(float(st_after_rep_cached.engineHp), float(_item_at(repair_live.moduleCondition, "engine").hp)), "evicted live ship recomputes fresh repaired status matching public get_status")

	# 3. Re-warm via tick_ship, then repairPriority change alone evicts and recomputes.
	Damage.tick_ship(repair_live, 1.0 / 30.0, {"inCombat": true}, frame_cache)
	check(frame_cache.has("player-2"), "tick_ship re-warms live ship before priority change")
	check(Damage.set_repair_priority(repair_live, "weapons") == "weapons", "Damage.set_repair_priority updates repairPriority to weapons")
	var st_prio_cached: Dictionary = Damage.get_status_cached(repair_live, frame_cache)
	check(frame_cache.is_empty() and str(st_prio_cached.repairPriority) == "weapons" and st_prio_cached == Damage.get_status(repair_live), "repairPriority change invalidates cached live entry and matches public get_status")

	# 4. Public Damage.get_status is always fresh even if a warmed frame_cache exists or is tampered with.
	Damage.tick_ship(repair_live, 1.0 / 30.0, {"inCombat": true}, frame_cache)
	check(frame_cache.has("player-2"), "live ship warmed for public get_status freshness check")
	var tampered_cache: Dictionary = frame_cache.duplicate(true)
	tampered_cache["player-2"].info.snapshot.engineFactor = 0.01
	var pub_before: Dictionary = Damage.get_status(repair_live)
	repair_live.wounded = 2.0
	repair_live.water = 45.0
	repair_live.policy = "bail"
	var pub_after: Dictionary = Damage.get_status(repair_live)
	check(float(pub_after.speedFactor) < float(pub_before.speedFactor) and float(pub_after.bailing) > 0.0 and float(pub_after.engineFactor) > 0.40, "public Damage.get_status is always fresh and independent of any frame_cache")

func test_old_null_and_invalid_owners_safe() -> void:
	var live: Dictionary = _canonical_boat("tin_skiff", "proj-iso-live-3", {"id": "player-3"})
	var frame_cache: Dictionary = {}
	Damage.tick_ship(live, 1.0 / 30.0, {"inCombat": true}, frame_cache)
	var cache_bytes: PackedByteArray = var_to_bytes(frame_cache)
	var live_entry: Dictionary = frame_cache["player-3"]

	# 1. Old/legacy owner without moduleCondition.
	var base: Dictionary = _hull_by_id("tin_skiff")
	var old_ship: Dictionary = Damage.create_ship(base, {"id": "legacy-1", "engine": 0.65, "water": 18.0, "breaches": [{"area": 6.0, "section": "bow"}]})
	var old_info: Dictionary = Damage.inspect_owner_cached(old_ship, frame_cache)
	var old_st_cached: Dictionary = Damage.get_status_cached(old_ship, frame_cache)
	var old_st_public: Dictionary = Damage.get_status(old_ship)
	check(bool(old_info.get("ok", false)) and str(old_info.get("mode", "")) == "legacy" and bool(old_info.get("needsInitialize", false)), "legacy owner inspect_owner_cached reports legacy mode safely")
	check(old_st_cached == old_st_public and str(old_st_cached.get("equipmentMode", "")) == "legacy" and _approx(float(old_st_cached.get("turnFactor", 0.0)), 1.0) and _approx(float(old_st_cached.get("engineFactor", 0.0)), 0.65), "legacy owner get_status_cached matches public get_status")
	var rng := RandomNumberGenerator.new(); rng.seed = 777
	Damage.tick_ship(old_ship, 1.0 / 30.0, {}, frame_cache)
	Damage.apply_hit(old_ship, {"damage": 12.0, "kind": "bullet"}, rng, frame_cache)
	check(frame_cache.size() == 1 and var_to_bytes(frame_cache) == cache_bytes and is_same(frame_cache["player-3"], live_entry), "legacy owner tick_ship and apply_hit never insert into or evict live frame_cache")

	# New cache helpers reject null/empty inputs; existing typed Damage API stays unchanged.
	var null_owner = null
	var empty_owner: Dictionary = {}
	var null_info: Dictionary = Damage.inspect_owner_cached(null_owner, frame_cache)
	var empty_info: Dictionary = Damage.inspect_owner_cached(empty_owner, frame_cache)
	var null_st_cached: Dictionary = Damage.get_status_cached(null_owner, frame_cache)
	var empty_st_cached: Dictionary = Damage.get_status_cached(empty_owner, frame_cache)
	check(not bool(null_info.get("ok",true)) and not bool(empty_info.get("ok",true)) and str(null_info.get("mode",""))=="invalid" and str(empty_info.get("mode",""))=="invalid", "new cache helpers reject null and empty owners")
	for invalid_status in [null_st_cached,empty_st_cached]:
		check(not bool(invalid_status.get("equipmentOk",true)) and str(invalid_status.get("equipmentMode",""))=="invalid" and float(invalid_status.speedFactor)==0.0 and float(invalid_status.weaponFactor)==0.0 and float(invalid_status.turnFactor)==0.0, "invalid cache owner has explicit zero capabilities")
	Damage.invalidate_frame_cache(frame_cache,null_owner)
	Damage.invalidate_frame_cache(frame_cache,empty_owner)
	Damage.clear_frame_cache(null)
	check(frame_cache.size()==1 and var_to_bytes(frame_cache)==cache_bytes and is_same(frame_cache["player-3"],live_entry), "invalid cache helper calls leave live entries byte-equal")

	# 3. Invalid/corrupt standalone owner.
	var invalid_ship: Dictionary = _canonical_boat("tin_skiff", "proj-iso-corrupt-1", {"id": "corrupt-1"})
	invalid_ship.moduleCondition = "corrupt-non-dict"
	var inv_info: Dictionary = Damage.inspect_owner_cached(invalid_ship, frame_cache)
	var inv_st_cached: Dictionary = Damage.get_status_cached(invalid_ship, frame_cache)
	var inv_st_pub: Dictionary = Damage.get_status(invalid_ship)
	check(not bool(inv_info.get("ok", true)) and str(inv_info.get("mode", "")) == "invalid", "invalid owner inspect_owner_cached fails closed")
	check(inv_st_cached == inv_st_pub and not bool(inv_st_cached.get("equipmentOk", true)) and str(inv_st_cached.get("equipmentMode", "")) == "invalid", "invalid owner get_status_cached matches public get_status fail-closed")
	Damage.tick_ship(invalid_ship, 1.0 / 30.0, {}, frame_cache)
	Damage.apply_hit(invalid_ship, {"damage": 20.0}, rng, frame_cache)
	check(frame_cache.size() == 1 and var_to_bytes(frame_cache) == cache_bytes and is_same(frame_cache["player-3"], live_entry), "invalid standalone owner never inserts into or evicts live frame_cache")

func test_fuel_cross_zero_instantaneous_vs_average_separate() -> void:
	# 1. Fuel crosses 0.0 mid-tick across the two 1/60s sub-steps of a 1/30s Damage.tick_ship call:
	#    sub-step 1 has fuel=0.00005 > 0 (motor pump active, pump=2.3), then burns 0.006*(1/60)=0.0001 -> fuel=0.0;
	#    sub-step 2 has fuel=0.0 (motor pump off, pump=0.0).
	#    tick_ship returns tick-averaged bailing/inflow, whereas post-tick get_status_cached / get_status report
	#    instantaneous fuel=0.0 status (pump=0.0, bailing=handBailing).
	var ship_a: Dictionary = _canonical_boat("tin_skiff", "proj-iso-fuel-a", {"id": "fuel-a", "water": 25.0, "supplies": 0.0, "policy": "bail", "fuel": 0.00005, "breaches": [{"area": 10.0, "section": "waterline"}]})
	var cache_a: Dictionary = {}
	var avg_st: Dictionary = Damage.tick_ship(ship_a, 1.0 / 30.0, {"inCombat": true}, cache_a)
	var inst_cached: Dictionary = Damage.get_status_cached(ship_a, cache_a)
	var inst_public: Dictionary = Damage.get_status(ship_a)
	check(_approx(float(ship_a.fuel), 0.0) and cache_a.has("fuel-a"), "ship_a fuel crosses 0.0 during 1/30s tick_ship and seeds cache_a")
	check(inst_cached == inst_public, "post-tick get_status_cached matches public get_status at fuel=0.0")
	check(_approx(float(inst_cached.pump), 0.0) and _approx(float(inst_cached.bailing), float(inst_cached.handBailing)), "instantaneous status at fuel=0.0 reports pump=0.0 and bailing=handBailing")
	check(float(avg_st.bailing) > float(inst_cached.bailing) + 1.0 and float(avg_st.inflow) != float(inst_cached.inflow), "tick_ship return preserves tick-averaged bailing/inflow separate from post-tick instantaneous get_status_cached")

	# 2. Fuel crosses 0.0 after tick_ship (e.g. Battle._move burning remaining fuel) while frame_cache stays a hit:
	#    inspect_owner_cached reuses the cached gear snapshot, while get_status_cached recomputes pump=0.0 at fuel=0.0.
	var ship_b: Dictionary = _canonical_boat("tin_skiff", "proj-iso-fuel-b", {"id": "fuel-b", "water": 25.0, "supplies": 0.0, "policy": "bail", "fuel": 0.0005, "breaches": [{"area": 10.0, "section": "waterline"}]})
	var cache_b: Dictionary = {}
	var tick_b: Dictionary = Damage.tick_ship(ship_b, 1.0 / 30.0, {"inCombat": true}, cache_b)
	var info_b_ref: Dictionary = cache_b["fuel-b"].info
	var st_with_fuel: Dictionary = Damage.get_status_cached(ship_b, cache_b)
	check(float(ship_b.fuel) > 0.0 and float(st_with_fuel.pump) > 2.0 and _approx(float(st_with_fuel.bailing), float(st_with_fuel.handBailing) + float(st_with_fuel.pump)), "before fuel exhaustion, get_status_cached includes active motor pump")
	ship_b.fuel = 0.0
	var info_b_after: Dictionary = Damage.inspect_owner_cached(ship_b, cache_b)
	var st_dry_cached: Dictionary = Damage.get_status_cached(ship_b, cache_b)
	var st_dry_public: Dictionary = Damage.get_status(ship_b)
	check(is_same(info_b_after, info_b_ref), "fuel crossing 0.0 after tick_ship keeps cached gear info reference valid")
	check(st_dry_cached == st_dry_public and _approx(float(st_dry_cached.pump), 0.0) and _approx(float(st_dry_cached.bailing), float(st_dry_cached.handBailing)) and float(st_dry_cached.bailing) < float(tick_b.bailing) - 2.0, "get_status_cached immediately recomputes pump=0.0 when fuel crosses 0.0 mid-frame")

func _initialize() -> void:
	ProjectSettings.set_setting("application/run/flush_stdout_on_print", true)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	catalog = Refit.catalog()
	test_posttick_admission_and_same_id_copy_isolation()
	test_warmed_live_damage_repair_invalidation_and_public_get_status_fresh()
	test_old_null_and_invalid_owners_safe()
	test_fuel_cross_zero_instantaneous_vs_average_separate()
	if failures > 0 or checks <= 0:
		push_error("frame_projection_isolation: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	print("frame_projection_isolation: %d checks, 0 failures" % checks)
	quit(0)
