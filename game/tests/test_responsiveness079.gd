extends "res://tests/test_publication072.gd"
## Focused status equivalence only; PUBLICATION072 retains joined isolation/poses
## and worker051 retains FIFO/retirement. Root alone runs the native fixtures.
## This controlled duel supplies no performance or earned-career evidence.

func status_equivalent079(st: Dictionary,label: String) -> Dictionary:
	# Exercise the actual driver's post-step phase before the null/fresh reference.
	# A stale accepted route or mount factor remains visible in this first row.
	var published: Dictionary=Driver._snapshot(st,true)
	var id: String=str(st.playerId)
	check(published.tactical.statusById051[id]==T.status(st,id),label+": tactical status equals fresh public read")
	check(published.tactical.damageStatusById051[id]==D.get_status(st.ships[0]),label+": damage projection equals fresh public read")
	return published

func run() -> void:
	began_us=Time.get_ticks_usec()
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var st: Dictionary=publication_arena(world)
	if st.is_empty():quit(1);return
	st.ships[1].ammo=0.0 # Isolate repair from a second, unrelated enemy hit.
	var ship: Dictionary=st.ships[0]
	var id: String=str(ship.id)
	var first: Dictionary=status_equivalent079(st,"initial canonical manual hull")
	var initial_factor: float=float(first.tactical.damageStatusById051[id].weaponFactors.mount0)
	var rng: RandomNumberGenerator=RandomNumberGenerator.new()
	rng.seed=79079
	# Enough real damage to enter the existing at-sea jury-repair range.
	var events: Array=D._apply_hit_in_battle051(ship,{"damage":80.0,"kind":"bullet","section":"mount0"},rng,st.tactical.damageCache,st.get("_damageOwned051"))
	var damaged: Dictionary=status_equivalent079(st,"official mount hit")
	var damaged_factor: float=float(damaged.tactical.damageStatusById051[id].weaponFactors.mount0)
	check(not events.is_empty() and damaged_factor<initial_factor,"real installed weapon damage changes the published capability")
	check(B.set_crew_policy(st,[id],"repair") and B.set_repair_priority(st,[id],"weapons"),"ordinary policy and installed-equipment priority commands are accepted")
	var commanded: Dictionary=status_equivalent079(st,"zero-step priority change")
	check(commanded.tactical.damageStatusById051[id].repairPriority=="weapons" and float(st.time)==0.0,"unsealed status observes current priority without advancing combat")
	var supplies: float=float(ship.supplies)
	for index in range(3):B.update(st,STEP,{"manual":true})
	var repaired: Dictionary=status_equivalent079(st,"three real funded repair steps")
	check(float(ship.supplies)<supplies and float(repaired.tactical.damageStatusById051[id].weaponFactors.mount0)>damaged_factor,"finite supplies fund actual installed weapon recovery before publication")
	# Retaining and editing a phase-produced row cannot poison the next one.
	var retained: Dictionary=repaired.tactical.statusById051[id]
	var expected: Dictionary=retained.duplicate(true)
	retained.mounts[0].fireRate=-1.0
	for mount_id in retained.weapons:retained.weapons[mount_id]="edited retained HUD"
	var edited: Dictionary=retained.duplicate(true)
	var next: Dictionary=status_equivalent079(st,"retained HUD mutation")
	check(next.tactical.statusById051[id]==expected and retained==edited,"later canonical status is unpoisoned and leaves the retained mutable HUD unchanged")
	B.set_autopilot(st,true)
	check(B.issue_order(st,[id],"hold",{}),"ordinary Hold command is accepted")
	B.update(st,STEP,{})
	var held: Dictionary=status_equivalent079(st,"autopilot Hold after real step")
	check(held.tactical.statusById051[id].order=="hold","phase-aware status reports the current accepted order")
	T.retire_planning051(st);T.drain_planning051();B._close_damage_owned051(st)
	print("RESPONSIVENESS079: %d checks, %d failures; bodyUs=%d"%[checks,failures,Time.get_ticks_usec()-began_us])
	quit(1 if failures else 0)
