extends SceneTree
## Pure headless checks for v0.004 typed combat events, effect metadata, persistent wrecks and mount timestamps.
## Root runs this serially and headless; this helper script never launches an engine process itself.

const B = preload("res://scripts/battle.gd")
const D = preload("res://scripts/damage.gd")
const E = preload("res://scripts/combat_events.gd")
const R = preload("res://scripts/refit.gd")

const WOOD_SPEC = {
	"id": "tin_skiff", "name": "Tinwake Skiff", "faction": "compact", "role": "skiff", "tier": 1,
	"hp": 150.0, "armor": 2.0, "crewMin": 3.0, "crewOptimal": 5.0, "crewMax": 8.0,
	"size": 14.0, "speed": 118.0, "turn": 2.65, "pumps": 2.4,
	"weapon": "gun", "damage": 12.0, "fireRate": 2.2, "range": 550.0, "deploymentPoints": 15
}

const ARMOR_SPEC = {
	"id": "iron_monitor", "name": "Cinder Monitor", "faction": "forge", "role": "gunboat", "tier": 3,
	"hp": 420.0, "armor": 12.0, "crewMin": 6.0, "crewOptimal": 10.0, "crewMax": 14.0,
	"size": 24.0, "speed": 82.0, "turn": 1.6, "pumps": 3.5,
	"weapon": "cannon", "damage": 36.0, "fireRate": 1.1, "range": 600.0, "deploymentPoints": 45
}

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL combat_events: " + message)

func four_family_spec(base: Dictionary, heavy: bool = false) -> Dictionary:
	var spec: Dictionary = base.duplicate(true)
	spec.speed = 0.0
	spec.weaponMounts = [
		{"id": "m_gun", "moduleId": "heavy_gun" if heavy else "rapid_gun", "size": 2 if heavy else 1, "kind": "gun", "damage": 16.0 if heavy else 11.0, "fireRate": 4.0, "range": 750.0, "speed": 900.0, "ammoCost": 1, "x": 8.0, "y": -4.0, "arc": TAU, "angle": 0.0},
		{"id": "m_cannon", "moduleId": "heavy_cannon" if heavy else "light_cannon", "size": 3 if heavy else 1, "kind": "cannon", "damage": 48.0 if heavy else 26.0, "fireRate": 1.0, "range": 750.0, "speed": 650.0, "ammoCost": 1, "x": 6.0, "y": 4.0, "arc": TAU, "angle": 0.0},
		{"id": "m_rocket", "moduleId": "salvo_rocket" if heavy else "fire_rocket", "size": 3 if heavy else 1, "kind": "rocket", "damage": 48.0 if heavy else 32.0, "fireRate": 0.8, "range": 750.0, "speed": 730.0, "ammoCost": 1, "x": -2.0, "y": -4.0, "arc": TAU, "angle": 0.0},
		{"id": "m_torpedo", "moduleId": "heavy_torpedo" if heavy else "light_torpedo", "size": 3 if heavy else 1, "kind": "torpedo", "damage": 58.0 if heavy else 38.0, "fireRate": 0.6, "range": 750.0, "speed": 260.0, "ammoCost": 1, "x": -2.0, "y": 4.0, "arc": TAU, "angle": 0.0}
	]
	return spec

func check_event_schema(ev: Dictionary, context: String) -> void:
	check(ev is Dictionary and not ev.is_empty(), context + ": event dictionary present")
	var id_val: int = int(ev.get("id", 0))
	check(id_val > 0 and id_val == int(ev.get("seq", -1)) and id_val == int(ev.get("sequence", -1)), context + ": monotonic id/seq/sequence match")
	check(str(ev.get("kind", "")) in E.EVENT_KINDS and str(ev.get("type", "")) == str(ev.get("kind", "")), context + ": valid event kind/type")
	check(str(ev.get("material", "")) in E.MATERIALS, context + ": valid event material")
	check(ev.get("position") is Vector2 and is_finite(float(ev.get("x", NAN))) and is_finite(float(ev.get("y", NAN))), context + ": finite position and x/y")
	check(is_equal_approx(ev.position.x, float(ev.x)) and is_equal_approx(ev.position.y, float(ev.y)), context + ": Vector2 position matches x/y")
	check(ev.get("direction") is Vector2 and is_equal_approx(ev.direction.length(), 1.0), context + ": unit direction vector")
	check(is_finite(float(ev.get("angle", NAN))) and is_finite(float(ev.get("magnitude", NAN))) and float(ev.get("magnitude", 0.0)) > 0.0, context + ": finite angle and positive magnitude")
	check(is_finite(float(ev.get("time", NAN))) and float(ev.get("time", -1.0)) >= 0.0, context + ": nonnegative event timestamp")
	check(str(ev.get("source", "")) == str(ev.get("sourceId", "")) and str(ev.get("target", "")) == str(ev.get("targetId", "")) and str(ev.get("mount", "")) == str(ev.get("mountId", "")), context + ": source/target/mount aliases match")

func check_effect_schema(ef: Dictionary, context: String) -> void:
	check(ef is Dictionary and not ef.is_empty(), context + ": effect dictionary present")
	check(str(ef.get("type", "")) in ["muzzle", "hit", "splash", "explosion"], context + ": legacy effect type preserved")
	check(str(ef.get("kind", "")) in E.EVENT_KINDS, context + ": effect kind in EVENT_KINDS")
	check(str(ef.get("family", "")) in ["gun", "cannon", "rocket", "torpedo", "hull"], context + ": effect has weapon/hull family")
	check(str(ef.get("material", "")) in E.MATERIALS, context + ": effect has valid material")
	check(ef.get("direction") is Vector2 and is_equal_approx(ef.direction.length(), 1.0), context + ": effect has unit direction")
	check(is_finite(float(ef.get("angle", NAN))) and is_finite(float(ef.get("magnitude", NAN))) and float(ef.get("magnitude", 0.0)) > 0.0, context + ": effect has finite angle and magnitude")
	check(is_finite(float(ef.get("radius", NAN))) and float(ef.get("radius", 0.0)) > 0.0 and float(ef.get("life", 0.0)) > 0.0, context + ": effect has positive radius and life")

func test_pop_drain_and_determinism() -> void:
	var a: Dictionary = B.create({"fleet": [D.create_ship(WOOD_SPEC)], "enemySpecs": [WOOD_SPEC], "seed": 42})
	var b: Dictionary = B.create({"fleet": [D.create_ship(WOOD_SPEC)], "enemySpecs": [WOOD_SPEC], "seed": 42})
	check(a.events is Array and a.events.is_empty(), "new battle starts with empty events array")
	check(B.pop_events(a).is_empty() and B.pop_events(b).is_empty(), "initial pop_events returns empty array")
	for s in [a.ships[0], b.ships[0]]:
		s.x = 500.0
		s.y = 850.0
	for s in [a.ships[1], b.ships[1]]:
		s.x = 760.0
		s.y = 850.0
	B.update(a, 1.0 / 30.0)
	B.update(b, 1.0 / 30.0)
	var batch_a1: Array = B.pop_events(a)
	var batch_b1: Array = B.pop_events(b)
	check(not batch_a1.is_empty() and batch_a1 == batch_b1, "identical seeds emit identical combat events")
	check(a.events.is_empty() and B.pop_events(a).is_empty() and B.pop_events(b).is_empty(), "pop_events consumes queued events once")
	var last_id: int = 0
	for ev in batch_a1:
		check_event_schema(ev, "batch1")
		check(int(ev.id) > last_id, "event sequence increases strictly within step")
		last_id = int(ev.id)
	for i in range(45):
		B.update(a, 1.0 / 30.0)
		B.update(b, 1.0 / 30.0)
	var batch_a2: Array = B.pop_events(a)
	var batch_b2: Array = B.pop_events(b)
	check(not batch_a2.is_empty() and batch_a2 == batch_b2, "subsequent steps remain deterministic")
	check(a.ships == b.ships and a.projectiles == b.projectiles and a.effects == b.effects, "ships, projectiles and effects remain deterministic")
	for ev in batch_a2:
		check_event_schema(ev, "batch2")
		check(int(ev.id) > last_id, "event sequence continues monotonically after pop_events")
		last_id = int(ev.id)

func test_both_teams_and_family_coverage() -> void:
	var p_ship: Dictionary = D.create_ship(four_family_spec(WOOD_SPEC, false), {"ammo": 80.0})
	var e_ship: Dictionary = D.create_ship(four_family_spec(ARMOR_SPEC, true), {"ammo": 80.0})
	var st: Dictionary = B.create({"fleet": [p_ship], "enemyFleet": [e_ship], "seed": 19})
	p_ship.x = 520.0
	p_ship.y = 850.0
	p_ship.angle = 0.0
	e_ship.x = 920.0
	e_ship.y = 850.0
	e_ship.angle = PI
	B.update(st, 1.0 / 30.0)
	var events: Array = B.pop_events(st)
	check(events.size() == 8, "both 4-mount boats emit fire events on opening salvo")
	var player_families: Dictionary = {}
	var enemy_families: Dictionary = {}
	var player_variants: Dictionary = {}
	var enemy_variants: Dictionary = {}
	for ev in events:
		check_event_schema(ev, "salvo")
		check(ev.kind == "fire", "opening salvo events are fire events")
		if ev.team == "player":
			check(ev.sourceId == p_ship.id and ev.targetId == e_ship.id, "player fire event records source and target IDs")
			player_families[ev.family] = true
			player_variants[ev.variant] = true
		elif ev.team == "enemy":
			check(ev.sourceId == e_ship.id and ev.targetId == p_ship.id, "enemy fire event records source and target IDs")
			enemy_families[ev.family] = true
			enemy_variants[ev.variant] = true
	for fam in E.FAMILIES:
		check(player_families.has(fam), "player emitted fire event for family " + fam)
		check(enemy_families.has(fam), "enemy emitted fire event for family " + fam)
	check(player_variants.has("light") and enemy_variants.has("heavy"), "light and heavy weapon variants distinguished")
	check(st.effects.size() == 8, "each mount shot creates a structured muzzle/launch effect")
	var effect_families: Dictionary = {}
	for ef in st.effects:
		check_effect_schema(ef, "salvo_effect")
		effect_families[ef.family] = true
		if ef.family == "cannon":
			check(ef.recoil > 0.2 and ef.smoke > 0.5, "cannon muzzle effect carries recoil and smoke attributes")
		elif ef.family == "gun":
			check(ef.life < 0.16 and ef.radius < 10.0, "machine gun muzzle flash is brief and compact")
		elif ef.family == "torpedo":
			check(ef.splash and ef.material == "water" and is_equal_approx(ef.height, 0.0), "torpedo launch effect sits at water height")
	for fam in E.FAMILIES:
		check(effect_families.has(fam), "muzzle effects cover family " + fam)

func test_mount_shot_timestamps() -> void:
	var p_ship: Dictionary = D.create_ship(four_family_spec(WOOD_SPEC, false), {"ammo": 80.0})
	var e_ship: Dictionary = D.create_ship(WOOD_SPEC, {"ammo": 0.0})
	e_ship.spec.speed = 0.0
	var st: Dictionary = B.create({"fleet": [p_ship], "enemyFleet": [e_ship], "seed": 23})
	p_ship.x = 520.0
	p_ship.y = 850.0
	e_ship.x = 880.0
	e_ship.y = 850.0
	for m_id in ["m_gun", "m_cannon", "m_rocket", "m_torpedo"]:
		check(B.mount_shot_time(p_ship, m_id) < 0.0 and not is_finite(B.mount_shot_age(p_ship, m_id)), "unfired mount has negative timestamp and infinite age: " + m_id)
	B.update(st, 1.0 / 30.0)
	B.pop_events(st)
	var first_time: float = st.time
	for idx in range(4):
		var m_id: String = ["m_gun", "m_cannon", "m_rocket", "m_torpedo"][idx]
		check(is_equal_approx(B.mount_shot_time(p_ship, m_id), first_time), "mount timestamp recorded by ID for " + m_id)
		check(is_equal_approx(B.mount_shot_time(p_ship, idx), first_time), "mount timestamp recorded by index for " + m_id)
		check(is_equal_approx(B.mount_shot_age(p_ship, m_id), 0.0), "mount shot age is zero on firing frame for " + m_id)
	for step in range(9):
		B.update(st, 1.0 / 30.0)
	B.pop_events(st)
	check(B.mount_shot_time(p_ship, "m_gun") > first_time, "rapid gun mount updates its shot timestamp on second shot")
	check(is_equal_approx(B.mount_shot_time(p_ship, "m_cannon"), first_time), "slower cannon mount retains its earlier shot timestamp while cooling")
	check(B.mount_shot_age(p_ship, "m_cannon") > B.mount_shot_age(p_ship, "m_gun") + 0.15, "mount_shot_age reflects elapsed time per mount")
	check(p_ship.lastShotMount == "m_gun" and p_ship.lastShotFamily == "gun", "ship tracks latest firing mount and family")

func test_hit_materials_and_blast() -> void:
	var wood_target: Dictionary = D.create_ship(WOOD_SPEC, {"hp": 500.0, "maxHp": 500.0, "ammo": 0.0})
	var armor_target: Dictionary = D.create_ship(ARMOR_SPEC, {"hp": 500.0, "maxHp": 500.0, "ammo": 0.0})
	var blast_neighbor: Dictionary = D.create_ship(WOOD_SPEC, {"hp": 500.0, "maxHp": 500.0, "ammo": 0.0})
	var shooter: Dictionary = D.create_ship(WOOD_SPEC, {"ammo": 0.0})
	for s in [wood_target, armor_target, blast_neighbor, shooter]:
		s.spec.speed = 0.0
	var st: Dictionary = B.create({"fleet": [shooter], "enemyFleet": [wood_target, armor_target, blast_neighbor], "seed": 31})
	shooter.x = 400.0
	shooter.y = 850.0
	wood_target.x = 700.0
	wood_target.y = 750.0
	armor_target.x = 700.0
	armor_target.y = 950.0
	blast_neighbor.x = 700.0
	blast_neighbor.y = 990.0
	check(B.hull_material(wood_target) == "wood" and B.hull_material(armor_target) == "armor", "hull_material distinguishes wood vs armor")
	st.projectiles.append({"x": 680.0, "y": 750.0, "px": 680.0, "py": 750.0, "vx": 900.0, "vy": 0.0, "team": "player", "damage": 18.0, "kind": "bullet", "family": "gun", "life": 1.0, "owner": shooter.id, "mountId": "m_gun", "radius": 2.0})
	st.projectiles.append({"x": 680.0, "y": 950.0, "px": 680.0, "py": 950.0, "vx": 730.0, "vy": 0.0, "team": "player", "damage": 40.0, "kind": "rocket", "family": "rocket", "life": 1.0, "owner": shooter.id, "mountId": "m_rocket", "radius": 3.0, "blastRadius": 36.0, "incendiary": true})
	st.projectiles.append({"x": 680.0, "y": 750.0, "px": 680.0, "py": 750.0, "vx": 600.0, "vy": 0.0, "team": "player", "damage": 35.0, "kind": "torpedo", "family": "torpedo", "life": 1.0, "owner": shooter.id, "mountId": "m_torpedo", "radius": 5.0, "penetration": 18.0})
	B.update(st, 1.0 / 30.0)
	var events: Array = B.pop_events(st)
	var hit_events: Array = events.filter(func(e): return e.kind == "hit")
	check(hit_events.size() == 4, "three direct projectiles plus one rocket blast emit four hit events")
	var wood_gun_hit: bool = false
	var armor_rocket_direct: bool = false
	var wood_rocket_blast: bool = false
	var wood_torpedo_hit: bool = false
	for ev in hit_events:
		check_event_schema(ev, "hit_event")
		if ev.family == "gun" and ev.targetId == wood_target.id:
			wood_gun_hit = ev.material == "wood" and ev.direct and ev.damage > 0.0
		elif ev.family == "rocket" and ev.targetId == armor_target.id:
			armor_rocket_direct = ev.material == "armor" and ev.direct and ev.incendiary
		elif ev.family == "rocket" and ev.targetId == blast_neighbor.id:
			wood_rocket_blast = ev.material == "wood" and not ev.direct and ev.subtype == "blast" and ev.reason == "blast"
		elif ev.family == "torpedo" and ev.targetId == wood_target.id:
			wood_torpedo_hit = ev.material == "wood" and ev.section == "waterline" and ev.breach and ev.splash
	check(wood_gun_hit, "gun hit on skiff records wood material and direct damage")
	check(armor_rocket_direct, "rocket direct hit on gunboat records armor material and incendiary flag")
	check(wood_rocket_blast, "rocket splash damage on nearby boat emits secondary blast hit event")
	check(wood_torpedo_hit, "torpedo hit records waterline breach and splash column")

func test_misses_land_vs_water_expiry() -> void:
	var shooter: Dictionary = D.create_ship(WOOD_SPEC, {"ammo": 0.0})
	var foe: Dictionary = D.create_ship(WOOD_SPEC, {"ammo": 0.0})
	shooter.spec.speed = 0.0
	foe.spec.speed = 0.0
	var st: Dictionary = B.create({
		"fleet": [shooter],
		"enemyFleet": [foe],
		"islands": [{"points": [[850.0, 750.0], [920.0, 750.0], [920.0, 950.0], [850.0, 950.0]]}],
		"seed": 51
	})
	shooter.x = 500.0
	shooter.y = 850.0
	foe.x = 1500.0
	foe.y = 850.0
	# Shot 1: hits the island shore around x=850.
	st.projectiles.append({"x": 830.0, "y": 850.0, "px": 830.0, "py": 850.0, "vx": 1800.0, "vy": 0.0, "team": "player", "damage": 26.0, "kind": "shell", "family": "cannon", "life": 1.0, "owner": shooter.id, "mountId": "m_cannon", "radius": 2.0})
	# Shot 2: expires over open water at y=500.
	st.projectiles.append({"x": 600.0, "y": 500.0, "px": 600.0, "py": 500.0, "vx": 600.0, "vy": 0.0, "team": "enemy", "damage": 12.0, "kind": "bullet", "family": "gun", "life": 0.01, "owner": foe.id, "mountId": "m_gun", "radius": 2.0})
	B.update(st, 1.0 / 30.0)
	var events: Array = B.pop_events(st)
	check(events.size() == 2, "land impact and open-water expiry both emit miss events")
	var land_ev: Dictionary = {}
	var water_ev: Dictionary = {}
	for ev in events:
		check_event_schema(ev, "miss_event")
		if ev.reason == "land":
			land_ev = ev
		elif ev.reason == "expired":
			water_ev = ev
	check(not land_ev.is_empty() and land_ev.kind == "miss" and land_ev.material == "land" and land_ev.land and not land_ev.splash and not land_ev.expired, "island collision emits land miss event without water splash")
	check(land_ev.x >= 845.0 and land_ev.x <= 855.0, "land miss position lies on the shoreline rather than inside the island")
	check(not water_ev.is_empty() and water_ev.kind == "miss" and water_ev.material == "water" and water_ev.splash and water_ev.expired and not water_ev.land, "open-water expiry emits splash miss event with water material")
	var land_effect: bool = false
	var water_effect: bool = false
	for ef in st.effects:
		check_effect_schema(ef, "miss_effect")
		if ef.reason == "land":
			land_effect = ef.type == "hit" and ef.material == "land" and ef.land and not ef.splash
		elif ef.reason == "expired":
			water_effect = ef.type == "splash" and ef.material == "water" and ef.splash and ef.expired and not ef.land
	check(land_effect and water_effect, "effects distinguish land impact from water splash")

func test_engine_failure_and_sinking_wrecks() -> void:
	var p_ship: Dictionary = D.create_ship(WOOD_SPEC, {"ammo": 0.0})
	var e_hull: Dictionary = D.create_ship(ARMOR_SPEC, {"ammo": 0.0, "hp": 10.0})
	var e_flood: Dictionary = D.create_ship(WOOD_SPEC, {"ammo": 0.0, "hp": 140.0, "fuel": 0.0, "water": 599.5, "capacity": 600.0, "breaches": [{"area": 300.0, "section": "waterline"}]})
	var e_survivor: Dictionary = D.create_ship(WOOD_SPEC, {"ammo": 0.0})
	for s in [p_ship, e_hull, e_flood, e_survivor]:
		s.spec.speed = 0.0
	var st: Dictionary = B.create({"fleet": [p_ship], "enemyFleet": [e_hull, e_flood, e_survivor], "seed": 64})
	p_ship.x = 450.0
	p_ship.y = 850.0
	e_hull.x = 750.0
	e_hull.y = 750.0
	e_flood.x = 750.0
	e_flood.y = 850.0
	e_survivor.x = 750.0
	e_survivor.y = 950.0
	# Trigger engine failure on e_survivor by dropping its engine into crippled stage.
	e_survivor.engine = 0.25
	# Lethal cannon shell against e_hull; e_flood will sink from flooding during Damage.tick_ship.
	st.projectiles.append({"x": 735.0, "y": 750.0, "px": 735.0, "py": 750.0, "vx": 900.0, "vy": 0.0, "team": "player", "damage": 120.0, "kind": "shell", "family": "cannon", "life": 1.0, "owner": p_ship.id, "mountId": "m_cannon", "radius": 2.0, "penetration": 10.0})
	B.update(st, 1.0 / 30.0)
	var events: Array = B.pop_events(st)
	var engine_events: Array = events.filter(func(e): return e.kind == "engine")
	var sink_events: Array = events.filter(func(e): return e.kind == "sink")
	check(not engine_events.is_empty() and engine_events.any(func(e): return e.targetId == e_survivor.id and e.material == "engine" and e.engineDamaged), "engine failure emits typed engine event")
	check(sink_events.size() == 2, "both hull-destroyed and flooded boats emit sink events")
	var saw_hull_sink: bool = false
	var saw_flood_sink: bool = false
	for ev in sink_events:
		check_event_schema(ev, "sink_event")
		if ev.targetId == e_hull.id:
			saw_hull_sink = ev.reason == "hull" and ev.sourceId == p_ship.id and ev.family == "cannon" and ev.hullMaterial == "armor" and ev.sunk
		elif ev.targetId == e_flood.id:
			saw_flood_sink = ev.reason == "flooding" and ev.hullMaterial == "wood" and ev.sunk
	check(saw_hull_sink, "hull-damage sinking event records killer source, family and armor hullMaterial")
	check(saw_flood_sink, "flooding sinking event records flooding reason and wood hullMaterial")
	check(st.wrecks.size() == 2, "two persistent wreck records created")
	for w in st.wrecks:
		check(w.has("x") and w.has("y") and w.has("angle") and w.has("name") and w.has("team") and w.has("size"), "wreck preserves legacy fields")
		check(w.has("id") and w.has("type") and w.has("archetype") and w.get("spec") is Dictionary and w.has("material") and w.has("cause"), "wreck includes persistent hull/material/cause details")
		check(w.sinking and is_equal_approx(float(w.age), 0.0) and is_equal_approx(float(w.sinkProgress), 0.0), "wreck starts at age 0 in sinking transition")
	# Advance 90 frames (3 seconds): neither the crippled engine nor the already-sunk boats may spam repeat events.
	var repeat_engine: int = 0
	var repeat_sink: int = 0
	for frame in range(90):
		B.update(st, 1.0 / 30.0)
		for ev in B.pop_events(st):
			if ev.kind == "engine" and ev.targetId == e_survivor.id:
				repeat_engine += 1
			if ev.kind == "sink":
				repeat_sink += 1
	check(repeat_engine == 0 and repeat_sink == 0, "persistent engine damage and sunken wrecks never emit repeated per-frame events")
	for w in st.wrecks:
		check(not w.sinking and is_equal_approx(float(w.sinkProgress), 1.0) and float(w.age) > 2.5, "wreck sinkProgress completes cleanly into persistent wreck state")

func test_caps_and_forty_boat_scenario() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var hulls: Dictionary = {}
	for h in world.HULLS:
		hulls[str(h.id)] = h
	var players: Array = []
	var enemies: Array = []
	# Canonical 15-point hulls give exactly forty active boats plus one safe reserve.
	# Four-family/light-heavy coverage is tested separately above.
	for rep in range(21):
		var base: Dictionary=hulls.tin_skiff
		var ship: Dictionary=D.create_ship(base)
		ship.uid="p-%d"%rep;R.ensure(ship,base);ship.ammo=float(ship.spec.ammoCapacity)
		players.append(ship)
		if rep<20:
			var enemy: Dictionary=D.create_ship(base)
			enemy.uid="e-%d"%rep;R.ensure(enemy,base);enemy.ammo=float(enemy.spec.ammoCapacity)
			enemies.append(enemy)
	var st: Dictionary = B.create({"fleet": players, "enemyFleet": enemies, "seed": 83})
	check(st.ships.size()==40 and st.deployment.player==300 and st.deployment.enemy==300 and st.reserves.player.size()==1,"forty active boats at exactly300points per side plus one reserve")
	var reserved_before: Array = st.reserves.player.duplicate(true)
	# Phase 1: run 120 frames WITHOUT draining pop_events to verify buffer caps hold under heavy load.
	for frame in range(120):
		if st.result != null:
			break
		B.update(st, 1.0 / 30.0)
		check(st.events.size() <= B.MAX_EVENTS, "queued events never exceed MAX_EVENTS")
		check(int(st.get("_stepEvents", 0)) <= B.MAX_STEP_EVENTS, "per-step events never exceed MAX_STEP_EVENTS")
		check(st.effects.size() <= B.MAX_EFFECTS and st.projectiles.size() <= 400 and st.wrecks.size() <= B.MAX_WRECKS, "effects, projectiles and wrecks respect caps")
	var undrained: Array = B.pop_events(st)
	check(not undrained.is_empty() and undrained.size() <= B.MAX_EVENTS, "pop_events drains capped buffer")
	var prev_seq: int = 0
	for ev in undrained:
		check_event_schema(ev, "capped_undrained")
		check(int(ev.seq) > prev_seq, "capped ring buffer preserves strictly increasing sequence order")
		prev_seq = int(ev.seq)
	# Phase 2: run 120 frames draining events each frame, checking both-team contribution.
	var teams_seen: Dictionary = {}
	var kinds_seen: Dictionary = {}
	for frame in range(120):
		if st.result != null:
			break
		B.update(st, 1.0 / 30.0)
		for ev in B.pop_events(st):
			check_event_schema(ev, "drained_step")
			check(int(ev.seq) > prev_seq, "drained step events maintain monotonic sequence")
			prev_seq = int(ev.seq)
			teams_seen[ev.team] = true
			kinds_seen[ev.kind] = true
	check(teams_seen.has("player") and teams_seen.has("enemy"), "both player and enemy fleets emit combat events in fleet battle")
	check(kinds_seen.has("fire") and (kinds_seen.has("hit") or kinds_seen.has("miss")), "fleet battle emits fire and impact/miss events")
	check(st.reserves.player == reserved_before, "undeployed reserve boats remain untouched by combat events and updates")

func _initialize() -> void:
	test_pop_drain_and_determinism()
	test_both_teams_and_family_coverage()
	test_mount_shot_timestamps()
	test_hit_materials_and_blast()
	test_misses_land_vs_water_expiry()
	test_engine_failure_and_sinking_wrecks()
	test_caps_and_forty_boat_scenario()
	print("combat_events: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
