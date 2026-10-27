extends SceneTree
const Layout = preload("res://scripts/mount_layout.gd")
const Refit = preload("res://scripts/refit.gd")
const Deployment = preload("res://scripts/deployment.gd")

var world: Dictionary = {}
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL mount_layout: " + message)

func _rect_overlap(a: Dictionary, b: Dictionary) -> bool:
	var ax: float = float(a.get("x", 0.0))
	var ay: float = float(a.get("y", 0.0))
	var al: float = float(a.get("length", a.get("len", 0.0))) * 0.5
	var aw: float = float(a.get("width", a.get("wid", 0.0))) * 0.5
	var bx: float = float(b.get("x", 0.0))
	var by: float = float(b.get("y", 0.0))
	var bl: float = float(b.get("length", b.get("len", 0.0))) * 0.5
	var bw: float = float(b.get("width", b.get("wid", 0.0))) * 0.5
	return absf(ax - bx) < (al + bl) and absf(ay - by) < (aw + bw)

func test_all_24_hulls() -> void:
	var hulls: Array = world.get("HULLS", [])
	check(hulls.size() == 24, "world.json defines all 24 canonical hulls")
	var archetypes: Dictionary = {}
	for raw in hulls:
		var hull: Dictionary = raw
		var snapshot: Dictionary = hull.duplicate(true)
		var hid: String = str(hull.get("id", "unknown"))
		var sz: float = float(hull.get("size", 14.0))
		var is_cat: bool = str(hull.get("role", "")) == "raider"
		var ref_pts: Array = Refit.hardpoints(hull)
		var pts: Array = Layout.hardpoints(hull)
		var st: Dictionary = Layout.structure(hull)
		archetypes[str(st.get("archetype", ""))] = true

		# 1. Exact count, IDs, labels, size thresholds, and fitting budgets vs Refit.
		check(pts.size() == ref_pts.size(), hid + ": hardpoint count matches Refit (%d)" % pts.size())
		check(Layout._size(hull) == Refit._size(hull), hid + ": mount size class matches Refit")
		check(Layout.fitting_budget(hull) == Refit._budget(hull), hid + ": fitting budget matches Refit")
		for i in range(pts.size()):
			var p: Dictionary = pts[i]
			var rp: Dictionary = ref_pts[i]
			check(str(p.get("id", "")) == str(rp.get("id", "")), "%s mount %d id == %s" % [hid, i, rp.id])
			check(str(p.get("label", "")) == str(rp.get("label", "")), "%s mount %d label == %s" % [hid, i, rp.label])
			check(int(p.get("size", 0)) == int(rp.get("size", -1)), "%s mount %d size == %d" % [hid, i, rp.size])
			check(is_equal_approx(float(p.get("arc", 0.0)), float(rp.get("arc", -1.0))), "%s %s preserves normal gun arc" % [hid, p.id])
			check(is_equal_approx(float(p.get("angle", 0.0)), float(rp.get("angle", -1.0))), "%s %s preserves socket outward angle" % [hid, p.id])
			check(is_equal_approx(float(p.get("x", 0.0)), float(p.get("localX", 0.0)) * sz), "%s %s world x == localX * size" % [hid, p.id])
			check(is_equal_approx(float(p.get("y", 0.0)), float(p.get("localY", 0.0)) * sz), "%s %s world y == localY * size" % [hid, p.id])
			check(float(p.get("footprintRadius", 0.0)) > 0.10 and float(p.get("elevation", 0.0)) > 0.0 and float(p.get("muzzleOffset", 0.0)) > 0.0, "%s %s has explicit footprintRadius, elevation and muzzleOffset hints" % [hid, p.id])

		# 2. Deck bounds and socket zone placement checks.
		var bounds: Dictionary = st.get("bounds", {})
		var max_abs_y: float = 0.95 if is_cat else 0.60
		for p in pts:
			var lx: float = float(p.localX)
			var ly: float = float(p.localY)
			var r: float = float(p.footprintRadius)
			check(lx - r >= -1.80 and lx + r <= 2.20, "%s %s footprint x [%.2f, %.2f] inside [-1.8, 2.2]" % [hid, p.id, lx - r, lx + r])
			check(absf(ly) + r <= max_abs_y + 0.0001, "%s %s footprint |y|+r (%.2f) <= %.2f" % [hid, p.id, absf(ly) + r, max_abs_y])
			check(lx - r >= float(bounds.get("sternX", -1.80)) - 0.0001 and lx + r <= float(bounds.get("bowX", 2.20)) + 0.0001, "%s %s inside hull longitudinal bounds" % [hid, p.id])
			check(absf(ly) + r <= float(bounds.get("halfBeam", max_abs_y)) + 0.0001, "%s %s inside hull halfBeam" % [hid, p.id])

		check(float(pts[0].localX) >= 0.95 and float(pts[0].localX) <= 1.10 and is_zero_approx(float(pts[0].localY)), hid + ": mount0 on bow centerline (~1.0)")
		check(float(pts[1].localX) >= -1.55 and float(pts[1].localX) <= -1.45 and is_zero_approx(float(pts[1].localY)), hid + ": mount1 on aft centerline (~-1.5)")
		if pts.size() >= 3:
			check(float(pts[2].localX) >= 0.45 and float(pts[2].localX) <= 0.55 and float(pts[2].localY) <= -0.42 and float(pts[2].localY) >= -0.60, hid + ": mount2 on port side (~0.5, -0.42..-0.60)")
		if pts.size() >= 4:
			check(is_equal_approx(float(pts[3].localX), float(pts[2].localX)) and is_equal_approx(float(pts[3].localY), -float(pts[2].localY)), hid + ": mount3 mirrors mount2 on starboard side")

		# 3. Structure placement and zero socket-structure / socket-socket overlap.
		var cabin: Dictionary = st.get("cabin", {})
		var engine: Dictionary = st.get("engine", {})
		check(float(cabin.get("x", 0.0)) >= -0.35 and float(cabin.get("x", 0.0)) <= -0.25, hid + ": bridge center x near -0.3")
		check(float(cabin.get("length", 0.0)) >= 0.66 and float(cabin.get("length", 0.0)) <= 0.78 and float(cabin.get("width", 0.0)) >= 0.46 and float(cabin.get("width", 0.0)) <= 0.62, hid + ": compact bridge dimensions (~0.75 x ~0.60)")
		check(float(engine.get("x", 0.0)) >= -1.05 and float(engine.get("x", 0.0)) <= -0.95, hid + ": engine bay near x ~ -1.0 clear of rear socket")
		check(not _rect_overlap(cabin, engine), hid + ": cabin and engine footprints do not overlap")

		var footprints: Array = st.get("footprints", [])
		check(footprints.size() >= 3, hid + ": structure exposes cabin, engine and vent/stack footprints")
		for p in pts:
			for fp in footprints:
				var clearance: float = Layout.footprint_clearance(p, fp)
				check(clearance > 0.04, "%s %s clears %s by %.3f" % [hid, p.id, str(fp.get("id", "struct")), clearance])
		for i in range(pts.size()):
			for j in range(i + 1, pts.size()):
				var a: Dictionary = pts[i]
				var b: Dictionary = pts[j]
				var d: float = Vector2(float(a.localX) - float(b.localX), float(a.localY) - float(b.localY)).length()
				var min_d: float = float(a.footprintRadius) + float(b.footprintRadius)
				check(d > min_d + 0.05, "%s %s and %s sockets do not overlap (d=%.3f > %.3f)" % [hid, a.id, b.id, d, min_d])

		# 4. Caller immutability and DP preservation.
		check(hull == snapshot and Deployment.cost(hull) == Deployment.cost(snapshot), hid + ": layout queries never mutate hull spec or DP")
	check(archetypes.size() == 7, "all 7 visual hull archetypes covered across 24 hulls")

func test_aim_and_mounts_normalization() -> void:
	var big: Dictionary = world.HULLS[23]
	var pts: Array = Layout.hardpoints(big)
	var expected_angles: Array = [0.0, PI, -PI / 2.0, PI / 2.0]
	for i in range(pts.size()):
		var p: Dictionary = pts[i]
		var orig_aim: Dictionary = Layout.weapon_aim(p, "cannon", true)
		var cannon_arc: float = PI * 0.75 if i == 0 else float(p.arc)
		check(is_equal_approx(float(orig_aim.arc), cannon_arc) and is_zero_approx(float(orig_aim.angle)), "declared original cannon aim on " + p.id)
		for gun_kind in ["gun", "cannon"]:
			var g_aim: Dictionary = Layout.weapon_aim(p, gun_kind, false)
			var expected_arc: float = cannon_arc if gun_kind == "cannon" else float(p.arc)
			check(is_equal_approx(float(g_aim.arc), expected_arc) and is_equal_approx(float(g_aim.angle), expected_angles[i]), "declared weapon arc on " + p.id)
		for fixed_kind in ["rocket", "torpedo"]:
			var f_aim: Dictionary = Layout.weapon_aim(p, fixed_kind, false)
			check(is_equal_approx(float(f_aim.arc), 0.9) and is_equal_approx(float(f_aim.angle), expected_angles[i]), "fixed launcher outward angle on " + p.id)

	var bare_mounts: Array = Layout.mounts_of(big)
	check(bare_mounts.size() == 1 and bare_mounts[0].id == "mount0" and is_equal_approx(float(bare_mounts[0].x), float(pts[0].localX)), "bare hull mounts_of uses mount0 socket without hidden coords")

	var fitted: Dictionary = big.duplicate(true)
	fitted.weaponMounts = []
	var kinds: Array = ["cannon", "gun", "rocket", "torpedo"]
	for i in range(pts.size()):
		var p: Dictionary = pts[i]
		var aim: Dictionary = Layout.weapon_aim(p, kinds[i], i == 0)
		fitted.weaponMounts.append({"id": p.id, "kind": kinds[i], "size": p.size, "x": p.x, "y": p.y, "arc": aim.arc, "angle": aim.angle})
	var norm_mounts: Array = Layout.mounts_of(fitted)
	check(norm_mounts.size() == 4, "fitted dreadnought normalizes all 4 sockets")
	for i in range(4):
		check(is_equal_approx(float(norm_mounts[i].x), float(pts[i].localX)) and is_equal_approx(float(norm_mounts[i].y), float(pts[i].localY)), "normalized mount %d matches socket localX/localY" % i)
		check(is_equal_approx(float(norm_mounts[i].angle), expected_angles[i]), "normalized mount %d retains socket outward angle" % i)

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	test_all_24_hulls()
	test_aim_and_mounts_normalization()
	print("mount_layout: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
