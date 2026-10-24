extends SceneTree
## Detached records only. Pure work/material allowances are NOT live payment proof.
const Records=preload("res://scripts/equipment_records.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const Refit=preload("res://scripts/refit.gd")
const Damage=preload("res://scripts/damage.gd")
var checks: int=0
var failures: int=0
var observations: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL records catalogue: "+message)

func item_at(boat: Dictionary,location: String) -> Dictionary:
	for item in boat.moduleCondition.items.values():
		if str(item.location)==location:return item
	return {}

func context(base: Dictionary,boat: Dictionary,identity: String,known: Array=[]) -> Dictionary:
	return {"base":base,"loadout":boat.loadout.duplicate(true),"identity":identity,"catalog":Refit.catalog(),"knownUids":known.duplicate()}

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":quit(2);return
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):path=arg.substr(6)
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	check(world.HULLS.size()==24,"all24 actual hulls are present")
	var owners: Array=[];var known: Array=[]
	for index in range(world.HULLS.size()):
		var base: Dictionary=world.HULLS[index].duplicate(true);var identity: String="catalogue-hull-%d"%index
		var boat: Dictionary=Damage.create_ship(base,{"uid":identity,"engine":0.65,"coins":12345})
		Refit.ensure(boat,base)
		var untouched: Dictionary={}
		for key in ["hp","maxHp","water","fire","supplies","ammo","fuel","crew","wounded","coins","loadout","spec"]:
			var value=boat[key];untouched[key]=value.duplicate(true) if value is Dictionary or value is Array else value
		var seeded: Dictionary=Records.initialize(boat,context(base,boat,identity,known))
		check(seeded.get("ok",false) and seeded.get("changed",false),str(base.id)+" initializes exact actual catalogue fit")
		if not seeded.get("ok",false):observations.append({"hull":str(base.id),"error":seeded});continue
		for key in untouched:check(boat[key]==untouched[key],str(base.id)+" initialization preserves "+str(key))
		var original: Dictionary=boat.moduleCondition.duplicate(true)
		var ids: Array=seeded.itemUids.duplicate();var sequence: int=int(boat.moduleCondition.nextItemSeq)
		boat=JSON.parse_string(JSON.stringify(boat));base=JSON.parse_string(JSON.stringify(base))
		var again: Dictionary=Records.initialize(boat,context(base,boat,identity,known))
		check(again.get("ok",false) and again.get("idempotent",false) and again.get("itemUids",[])==ids and int(boat.moduleCondition.nextItemSeq)==sequence,str(base.id)+" canonical whole-float JSON roundtrip is stable")
		var engine_uid: String=str(item_at(boat,"engine").itemUid)
		check(Core.apply_component_damage(boat.moduleCondition,{"itemUid":engine_uid,"loss":0.20,"cause":"Detached native catalogue check"}).ok,str(base.id)+" actual canonical engine damage")
		boat.engine=1.0
		check(Records.initialize(boat,context(base,boat,identity,known)).ok and is_equal_approx(float(item_at(boat,"engine").hp),0.45),str(base.id)+" idempotent initialization never regenerates or heals installed condition")
		boat.engine=0.35
		check(Records.absorb_legacy_damage(boat).ok and is_equal_approx(float(item_at(boat,"engine").hp),0.35),str(base.id)+" explicit downward legacy sync")
		var allowance: Dictionary=Core.repair_installed(boat.moduleCondition,{"work":0.15,"supplies":1.0,"hpPerWork":1.0,"suppliesPerHp":{"engines":1.0,"weapons":1.0,"pumps":1.0},"priority":"engine"})
		check(allowance.get("ok",false) and allowance.get("changed",false) and is_equal_approx(float(item_at(boat,"engine").hp),0.50),str(base.id)+" pure supplied repair allowance raises canonical engine")
		check(Records.publish(boat).ok and is_equal_approx(float(boat.engine),0.50),str(base.id)+" publish after repair retains repaired condition")
		check(int(boat.coins)==12345 and float(boat.supplies)==float(untouched.supplies),str(base.id)+" detached core neither invents a live payment nor debits career stores")
		var without: Dictionary=boat.duplicate(true);without.moduleCondition.items.erase(engine_uid)
		var without_before: Dictionary=without.duplicate(true)
		check(not Records.initialize(without,context(base,without,identity,known)).ok and without==without_before,str(base.id)+" missing installed engine is refused without regeneration")
		var corrupt: Dictionary=boat.duplicate(true);corrupt.moduleCondition.version=999
		var corrupt_before: Dictionary=corrupt.duplicate(true)
		check(not Records.initialize(corrupt,context(base,corrupt,identity,known)).ok and corrupt==corrupt_before,str(base.id)+" corrupt owner refused intact")
		var before: Dictionary=boat.duplicate(true)
		check(not Records.initialize(boat,context(base,boat,identity,[ids[0]])).ok and boat==before,str(base.id)+" external duplicate registry refuses existing part")
		var mismatched: Dictionary=context(base,boat,identity,known);mismatched.loadout.engine="economy_drive"
		check(not Records.initialize(boat,mismatched).ok and boat==before,str(base.id)+" mismatched actual loadout refused intact")
		var birth: String=str(boat.moduleCondition.birthNamespace);var canonical_before_capture: Dictionary=boat.moduleCondition.duplicate(true)
		boat.uid="captured-hull-%d"%index
		var acknowledged: Dictionary=Core.acknowledge_hull_uid(boat.moduleCondition,str(boat.uid))
		check(acknowledged.ok and boat.moduleCondition==canonical_before_capture and str(acknowledged.birthNamespace)==birth and acknowledged.itemUids==ids,str(base.id)+" changed hull custody label preserves birth/item/serial identity")
		check(Records.initialize(boat,context(base,boat,birth,known)).ok and boat.moduleCondition==canonical_before_capture,str(base.id)+" captured hull validates using stable birth identity")
		before=boat.duplicate(true)
		check(not Records.initialize(boat,context(base,boat,str(boat.uid),known)).ok and boat==before,str(base.id)+" replacing birth identity with new owner label fails closed")
		owners.append(boat.moduleCondition.duplicate(true));known=Core.collect_item_uids(owners).uids
		observations.append({"hull":str(base.id),"identity":birth,"capturedHullLabel":str(boat.uid),"itemUids":ids,"nextItemSeq":sequence,"canonicalEngineHp":float(item_at(boat,"engine").hp),"repairAllowanceResult":allowance,"initialCanonical":original,"finalSnapshot":Records.snapshot(boat)})
	check(owners.size()==24 and Core.collect_item_uids(owners).ok,"all24 canonical owners have globally unique real item UIDs")
	var duplicate: Array=owners.duplicate(true);duplicate.append(owners[0].duplicate(true))
	check(not Core.collect_item_uids(duplicate).ok,"duplicated actual canonical owner is rejected")
	var out: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if out==null:quit(2);return
	out.store_string(JSON.stringify({"scope":"Detached actual24-hull records and JSON only; no live capture/payment/adapter proof","checks":checks,"failures":failures,"hulls":observations}));out.close()
	print("Equipment catalogue: %d checks, %d failures;24 actual hulls/JSON, detached only"%[checks,failures])
	quit(0 if failures==0 else 1)
