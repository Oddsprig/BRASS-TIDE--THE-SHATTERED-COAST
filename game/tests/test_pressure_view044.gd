extends SceneTree
## Focused source candidate: canonical current values and the actual HUD update.
## Root alone runs this through Test Bridge; no Main scene, saves or audio needed.
const View=preload("res://scripts/combat_pressure_view044.gd")
const TacticsUI=preload("res://scripts/tactics_ui.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Damage=preload("res://scripts/damage.gd")
const Battle=preload("res://scripts/battle.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")

class Host extends RefCounted:
	const Battle=preload("res://scripts/battle.gd")
	const Damage=preload("res://scripts/damage.gd")
	var battle: Dictionary={}
	var selected_battle_ids: Array=[]

class HUD extends RefCounted:
	var host
	var objective_label: Label
	var battle_points_label=Label.new()
	var autopilot_button=Button.new()
	var battle_control_label=Label.new()
	var tactical_intent_label=Label.new()
	func release() -> void:
		for node in [battle_points_label,autopilot_button,battle_control_label,tactical_intent_label]:node.free()

var checks: int=0
var failures: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL pressure_view044: "+message)

func _initialize() -> void:call_deferred("run")

func damage_item(boat: Dictionary,location: String) -> bool:
	for item in boat.moduleCondition.items.values():
		if str(item.location)==location:
			return bool(Core.apply_component_damage(boat.moduleCondition,{"itemUid":str(item.itemUid),"loss":0.85,"cause":"HUD readiness fixture"}).ok) and bool(Records.publish(boat).ok)
	return false

func exercise(st: Dictionary) -> void:
	var players: Array=st.ships.filter(func(s):return s.team=="player")
	var source: Dictionary=players[0]
	var ally: Dictionary=players[1]
	var enemy: Dictionary=st.ships.filter(func(s):return s.team=="enemy")[0]
	var selected: Dictionary=View.selection(st,[enemy.id,"missing",ally.id,source.id,ally.id])
	check(is_same(selected.boat,ally) and int(selected.count)==2,"selection follows actual owned order, excludes enemy/stale IDs and deduplicates")
	ally.sunk=true
	check(is_same(View.selection(st,[ally.id,source.id]).boat,source),"sunk selection cannot leave another boat's values on screen")
	ally.sunk=false;ally.captureSecured=true
	check(View.selection(st,[ally.id]).boat.is_empty(),"secured prize is not an active owned selection")
	ally.erase("captureSecured")

	source.water=float(source.capacity)*0.1;source.breaches=[{"area":1000.0,"section":"bow"}]
	source.fuel=0.0;source.supplies=6.5;source.policy="fight"
	var flow: Dictionary=Damage.get_status(source)
	var lines: String="\n".join(View.readiness(source,flow))
	check(float(flow.inflow)>float(flow.bailing) and "Water 10%" in lines and "rising" in lines,"water pressure uses current canonical inflow minus bailing")
	check("NO FUEL" in lines and "kits 6.5" in lines and "%.1f hands"%float(flow.crewRepair) in lines,"finite engine/repair readiness reads this boat's actual stores and available hands")
	source.breaches.clear();source.policy="bail";source.supplies=0.0
	flow=Damage.get_status(source);lines="\n".join(View.readiness(source,flow))
	check("draining" in lines and "NO KITS" in lines and float(flow.handBailing)>0.0,"crew can bail without repair kits or powered pumps")
	var water_before: float=source.water
	Damage.tick_ship(source,1.0/60.0,{"inCombat":true})
	check(float(source.water)<water_before and source.supplies==0.0 and source.fuel==0.0,"the reported draining direction agrees with a real bounded damage tick without free stores")
	check(damage_item(source,"engine"),"actual canonical engine damage is published")
	flow=Damage.get_status(source);lines="\n".join(View.readiness(source,flow))
	check(float(flow.engineHp)>0.0 and float(flow.engineFactor)==0.0 and "disabled" in lines,"engine readiness obeys disabled hysteresis rather than positive raw HP")
	source.supplies=8.5;source.policy="repair"
	flow=Damage.get_status(source);lines="\n".join(View.readiness(source,flow))
	check(float(flow.crewRepair)>0.0 and "%.1f hands"%float(flow.crewRepair) in lines and "kits 8.5" in lines,"repair assignment and finite kits refresh immediately after actual policy/store changes")
	source.wounded=source.crew
	flow=Damage.get_status(source)
	check("Repair 0.0 hands" in "\n".join(View.readiness(source,flow)),"all wounded crew cannot be presented as available repair hands")
	source.wounded=0.0

	var status: Dictionary=Battle.tactical_status(st,str(source.id))
	check(status.mounts.size()>1,"real fitted battery supplies distinct physical mount timers")
	if status.mounts.size()<2:return
	var mount: Dictionary=status.mounts[0]
	flow=Damage.get_status(source)
	source.weaponCooldowns[0]=0.4;source.cooldown=1.7
	check(View.weapon_state(source,mount,0,flow,"Reloading")=="Reload 1.7s","primary reload respects both live timer sources")
	source.weaponCooldowns[1]=2.4
	check(View.weapon_state(source,status.mounts[1],1,flow,"Reloading")=="Reload 2.4s","another physical mount keeps its own timer")
	source.weaponCooldowns[0]=0.0;source.cooldown=0.0
	check(View.weapon_state(source,mount,0,flow,"Reloading")=="Loaded · waiting for shot","a stale reason cannot extend reload or promise a clear shot")
	for reason in ["Ally in firing lane","Automatic fire held","Keeping working ammunition reserve","Manual aim and trigger"]:
		check(reason in View.weapon_state(source,mount,0,flow,reason),"reload completion retains the real firing restriction: "+reason)
	source.ammo=float(mount.ammoCost)-0.5
	check(View.weapon_state(source,mount,0,flow,"Reloading")=="No ammo","less than a mount's actual round cost cannot read Loaded")
	source.ammo=20.0
	check(damage_item(source,str(mount.slotId)),"actual mounted weapon damage is published")
	flow=Damage.get_status(source)
	check(View.weapon_state(source,mount,0,flow,"Manual aim and trigger")=="Weapon disabled","live equipment condition overrides a stale working weapon reason")
	var unknown: Dictionary=source.duplicate(true)
	unknown.erase("weaponCooldowns")
	check(View.weapon_state(unknown,status.mounts[1],1,flow,"Reloading")=="Reload unavailable","missing secondary timer cannot manufacture a ready state")
	var corrupt: Dictionary=source.duplicate(true)
	corrupt.moduleCondition={"bad":true}
	var bad_flow: Dictionary=Damage.get_status(corrupt)
	check(View.readiness(corrupt,bad_flow)==["Damage control unavailable"] and View.weapon_state(corrupt,mount,0,bad_flow,"")=="Weapon status unavailable","invalid equipment stays visibly unavailable")
	var before: PackedByteArray=var_to_bytes([source,flow,mount,status])
	View.readiness(source,flow);View.weapon_state(source,mount,0,flow,"Reloading");View.selection(st,[source.id])
	check(var_to_bytes([source,flow,mount,status])==before,"presentation does not change live boats, supplied status or physical mounts")

	var host=Host.new();host.battle=st;host.selected_battle_ids=[ally.id]
	var ui=HUD.new();ui.host=host
	ally.water=float(ally.capacity)*0.25
	var ships_before: PackedByteArray=var_to_bytes(st.ships)
	TacticsUI.update(ui)
	check("SELECTED · "+str(ally.name) in ui.tactical_intent_label.text and "Water 25%" in ui.tactical_intent_label.text and not str(source.name) in ui.tactical_intent_label.text,"actual HUD update describes the selected ally rather than the flagship")
	host.selected_battle_ids=[source.id,ally.id];TacticsUI.update(ui)
	check("SELECTED · "+str(source.name)+" (1 of 2)" in ui.tactical_intent_label.text and "Weapon disabled" in ui.tactical_intent_label.text,"group HUD names the boat whose current readiness is shown")
	host.selected_battle_ids=[];TacticsUI.update(ui)
	check(ui.tactical_intent_label.text=="Select a boat to see its intent.","empty selection clears previous readiness instead of inventing flagship values")
	check(var_to_bytes(st.ships)==ships_before,"actual HUD refresh leaves every deployed boat unchanged")
	ui.release()

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var created: Dictionary=Lab.create(world,{"player":[Lab.entry(world,"iron_bastion"),Lab.entry(world,"lantern_skiff")],"enemy":[Lab.entry(world,"tin_skiff")]},4401)
	check(bool(created.ok),"canonical boats use existing laboratory birth, fitting and deployment")
	if created.ok:exercise(created.battle)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file: FileAccess=FileAccess.open(arg.substr(6),FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures}));file.close()
	print("pressure_view044: %d checks, %d failures; current-value presentation only"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
