extends SceneTree
## Native draw-call capture only. Root renders the JSON with the existing CPU tools.
const FeedbackTest=preload("res://tests/test_feedback.gd")
const Art=preload("res://scripts/boat_art.gd")
const Feedback=preload("res://scripts/hull_feedback.gd")
const FX=preload("res://scripts/combat_art.gd")
const Battle=preload("res://scripts/battle.gd")
const Events=preload("res://scripts/combat_events.gd")
const Damage=preload("res://scripts/damage.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Refit=preload("res://scripts/refit.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const Motors=preload("res://scripts/motor_art.gd")
const MeshCache=preload("res://scripts/boat_mesh_cache.gd")
const Chart=preload("res://scripts/chart.gd")
var checks: int=0
var failures: int=0
var invalid: int=0

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("PRESENTATION040: "+message)

func canonical(base: Dictionary,id: String,secondary: bool=false) -> Dictionary:
	var boat: Dictionary=Damage.create_ship(base,{"id":id,"uid":id})
	Refit.ensure(boat,base)
	if secondary and boat.loadout.weapons.size()>1:
		boat.loadout.weapons[1]="rapid_gun"
		boat.spec=Refit.effective_spec(base,boat.loadout)
	var seeded: Dictionary=Records.initialize(boat,{"base":base,"loadout":boat.loadout,"catalog":Refit.catalog(),"identity":id,"knownUids":[]})
	check(bool(seeded.ok),"canonical real installed loadout: "+id)
	boat.angle=-0.45
	return boat

func damage_parts(boat: Dictionary,loss: float) -> void:
	for item in boat.moduleCondition.items.values():
		if str(item.location) in ["mount0","engine","pumps"]:
			check(bool(Core.apply_component_damage(boat.moduleCondition,{"itemUid":item.itemUid,"loss":loss,"cause":"Presentation fixture hit"}).ok),"actual component damage: "+str(item.location))
	check(bool(Records.publish(boat).ok),"canonical engine condition published to existing scalar")

func recorder(scale_value: float=2.0):
	var rec=FeedbackTest.Recorder.new()
	rec.origin=Vector2(260,260);rec.scale_factor=scale_value
	return rec

func panel(id: String,title: String,rec) -> Dictionary:
	invalid+=int(rec.invalid)
	return {"id":id,"title":title,"width":520,"height":430,"background":"#183e4b","primitives":rec.prims}

func boat_panel(id: String,title: String,boat: Dictionary,time: float=0.0,lod: int=0) -> Dictionary:
	var before: PackedByteArray=var_to_bytes(boat)
	var rec=recorder()
	Art.draw_boat(rec,rec.project,boat,{"cache":true,"lod":lod,"px":float(boat.spec.size)*rec.scale_factor,"clock":time,"battle_clock":time,"combat":true})
	check(var_to_bytes(boat)==before,"cached drawing leaves complete boat unchanged: "+id)
	return panel(id,title,rec)

func marker_capture(boat: Dictionary,lod: int=0) -> Dictionary:
	var rec=recorder()
	var ctx: Dictionary={"canvas":rec,"proj":rec.project,"pos":Vector2.ZERO,"angle":boat.angle,"size":float(boat.spec.size),"px":float(boat.spec.size)*2.0,"lod":lod,"n":0,"npoly":0,"nline":0,"ncirc":0}
	Feedback.draw_equipment(ctx,boat,Art.mounts_of(boat.spec))
	check(rec.invalid==0 and rec.prims.size()==int(ctx.n) and int(ctx.n)<=18,"component overlay is finite, counted and bounded")
	return {"prims":rec.prims,"ctx":ctx}

func effect_panel(state: Dictionary) -> Dictionary:
	var before: PackedByteArray=var_to_bytes(state)
	var rec=recorder(2.0)
	for i in range(state.effects.size()):
		var column: int=int({"wood":0,"armor":1,"water":2}.get(str(state.effects[i].material),i))
		rec.origin=Vector2(90+column*170,250)
		var start: int=rec.prims.size()
		var count: int=FX.effect(rec,state.effects[i])
		check(count==rec.prims.size()-start and count<=FX.MAX_EFFECT_PRIMS,"actual material effect respects primitive cap")
	check(var_to_bytes(state)==before,"material drawing never edits actual effect state")
	return panel("impacts","Wood splinters / armor sparks / water plume",rec)

func effect_states(state: Dictionary) -> Array:
	var rows: Array=[]
	for effect in state.effects:
		rows.append({"seq":effect.seq,"family":effect.family,"material":effect.material,"age":effect.age,"life":effect.life,"position":[effect.x,effect.y]})
	return rows

func run() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var bases: Dictionary={}
	for hull in world.HULLS:bases[str(hull.id)]=hull
	check(world.HULLS.size()==36,"existing 36 hull roster retained")
	var intact: Dictionary=canonical(bases.maiden_dreadnought,"presentation040-equipment",true)
	var mounts: Array=Art.mounts_of(intact.spec)
	check(mounts.size()>=2 and Feedback.equipment_marks(intact,mounts).is_empty(),"healthy real fitted mounts have no damage marks")
	var damaged: Dictionary=intact.duplicate(true)
	damage_parts(damaged,0.45)
	var disabled: Dictionary=intact.duplicate(true)
	damage_parts(disabled,0.85)
	var structure: Dictionary=Layout.structure(intact.spec)
	var marks: Array=Feedback.equipment_marks(disabled,mounts)
	check(marks.size()==3,"only actual disabled gun, engine and integral pump are marked")
	for mark in marks:
		var expected: Vector2=Vector2(mounts[0].x,mounts[0].y) if str(mark.location)=="mount0" else Vector2(structure.engine.x,structure.engine.y) if str(mark.location)=="engine" else Vector2(structure.cabin.x,structure.cabin.y)
		check(mark.at==expected and str(mark.status)=="disabled","mark follows actual mount/engine/bilge position and canonical status: "+str(mark.location))
	var amber: Dictionary=marker_capture(damaged)
	var red: Dictionary=marker_capture(disabled)
	check(amber.prims!=red.prims and not red.prims.is_empty(),"damaged and disabled produce different actual symbols")
	check(marker_capture(disabled,2).prims.is_empty(),"far LOD adds no component overlay")
	var healthy_panel: Dictionary=boat_panel("healthy","Healthy fitted hull",intact)
	var damaged_panel: Dictionary=boat_panel("damaged","Damaged gun / engine / pumps: amber slash",damaged)
	var misses: int=MeshCache.misses
	var disabled_panel: Dictionary=boat_panel("disabled","Disabled gun / engine / pumps: red cross",disabled)
	check(MeshCache.misses==misses and damaged_panel.primitives!=disabled_panel.primitives,"live condition changes remain visible on reused geometry")
	# A real supply-debited jury repair must immediately change the overlay.
	var repair: Dictionary=Core.repair_installed(disabled.moduleCondition,{"work":float(disabled.crew),"supplies":float(disabled.supplies),"hpPerWork":0.04,"suppliesPerHp":{"weapons":1.0,"engines":1.5,"pumps":1.2},"priority":"auto"})
	disabled.supplies-=float(repair.get("usedSupplies",0.0))
	Records.publish(disabled)
	check(bool(repair.ok) and float(repair.get("usedSupplies",0))>0 and marker_capture(disabled).prims!=red.prims,"actual repair and consumed supplies immediately update condition marks")
	disabled=intact.duplicate(true);damage_parts(disabled,0.85)
	var copy: Dictionary=damaged.duplicate(true)
	check(marker_capture(copy).prims==amber.prims and marker_capture(disabled).prims==red.prims,"same-ID detached boats cannot inherit another boat's marks")
	# Real event metadata, not hand-authored Python effect geometry.
	var impact_state: Dictionary={"time":0.0,"result":"won","effects":[],"wrecks":[]}
	var shot: Dictionary={"kind":"shell","vx":-200.0,"vy":0.0,"owner":"presentation040-source","team":"enemy"}
	Events.emit_hit(impact_state,shot,canonical(bases.bilge_punt,"presentation040-wood"),Vector2.ZERO,"bow",[],0)
	Events.emit_hit(impact_state,shot,intact,Vector2.ZERO,"bow",[],0)
	Events.emit_miss(impact_state,shot,Vector2.ZERO,false)
	check(impact_state.effects.size()==3 and str(impact_state.effects[0].material)=="wood" and str(impact_state.effects[1].material)=="armor" and str(impact_state.effects[2].material)=="water","actual CombatEvents supply wood / armor / water metadata")
	var material_draws: Array=[]
	for effect in impact_state.effects:
		var rec=recorder();FX.effect(rec,effect);material_draws.append(rec.prims)
	check(material_draws[0]!=material_draws[1] and material_draws[1]!=material_draws[2] and material_draws[0]!=material_draws[2],"three materials have distinct native draw primitives")
	var runner: Dictionary=canonical(bases.bilge_punt,"presentation040-wake")
	var battle: Dictionary=Battle.create({"fleet":[runner],"enemySpecs":[bases.bilge_punt],"islands":[],"seed":400})
	check(not battle.has("startError") and battle.result==null,"bounded real movement fixture starts")
	# Initial pose/velocity only; every later position comes from ordinary Battle.update.
	runner.vx=60.0;runner.vy=0.0
	var start_position:=Vector2(runner.x,runner.y)
	var chart=Chart.new()
	var frames: Array=[]
	var overview: Array=[healthy_panel,damaged_panel,disabled_panel]
	var previous_effects: Array=effect_states(impact_state)
	var changed_effect_state: bool=false
	var max_wake: int=0
	for frame_index in range(16):
		var wake_rec=recorder(3.0)
		for _tick in range(3):
			Battle.update(battle,1.0/30.0,{"manual":true,"forward":true})
			chart.clock=battle.time;chart._update_wakes([runner])
		if frame_index>0:Battle.advance_visuals(impact_state,0.1)
		var current_effects: Array=effect_states(impact_state)
		changed_effect_state=changed_effect_state or current_effects!=previous_effects
		previous_effects=current_effects
		var origin:=Vector2(runner.x,runner.y)
		wake_rec.origin=Vector2(370,265)-Vector2((origin.x-origin.y)*0.82,(origin.x+origin.y)*0.41)*wake_rec.scale_factor
		var samples: Array=[]
		var recorded: Array=[]
		for sample in chart._wakes.get(str(runner.uid),[]):
			var age: float=chart.clock-float(sample.t)
			samples.append({"p":sample.p,"d":sample.d,"age":age,"w":sample.w})
			recorded.append({"p":[sample.p.x,sample.p.y],"d":[sample.d.x,sample.d.y],"age":age,"w":sample.w})
		var wake_count: int=Art.draw_wake(wake_rec,wake_rec.project,samples)
		max_wake=maxi(max_wake,wake_count)
		check(wake_count<=12 and wake_rec.prims.size()==wake_count,"actual recorded stern wake uses at most twelve foam strokes")
		Art.draw_boat(wake_rec,wake_rec.project,runner,{"cache":true,"lod":1,"px":float(runner.spec.size)*3.0,"clock":battle.time})
		var panels: Array=[boat_panel("damaged","Damaged gun / engine / pumps: amber slash",damaged,battle.time),boat_panel("disabled","Disabled gun / engine / pumps: red cross",disabled,battle.time),effect_panel(impact_state),panel("wake","Actual Battle motion / recorded stern foam",wake_rec)]
		frames.append({"time":battle.time,"panels":panels,"state":{"position":[runner.x,runner.y],"angle":runner.angle,"fuel":runner.fuel,"effects":current_effects,"wakeSamples":recorded}})
		if frame_index==2:overview.append_array(panels.slice(2))
	check(changed_effect_state and impact_state.effects.is_empty(),"actual cosmetic-tail updates age and expire impacts")
	check(Vector2(runner.x,runner.y).distance_to(start_position)>10 and max_wake>0 and chart._wakes.size()<=Chart.WAKE_MAX_BOATS,"ordinary Battle motion produces the bounded chart wake")
	var long_boat: Dictionary=Damage.create_ship(bases.blackwater_fleet_tanker)
	long_boat.angle=0.6
	var local_stern: Vector2=(Art.stern_of(long_boat)-Vector2(long_boat.x,long_boat.y)).rotated(-long_boat.angle)/float(long_boat.spec.size)
	check(local_stern.x<float(Motors._plan(long_boat.spec,long_boat).minX) and absf(local_stern.y)<0.0001,"long civilian wake starts behind actual transom machinery")
	check(invalid==0 and MeshCache._meshes.size()<=MeshCache.LIMIT,"all captured primitives finite and existing mesh pool bounded")
	chart.free()
	finish({"panels":overview,"frames":frames,"gallery":{"title":"PRESENTATION / ACTUAL PRIMITIVES","hull_ids":overview.map(func(p):return p.id)},"limits":"Actual native canvas calls and bounded Battle/effect states; CPU raster review only, no GPU FPS or listening acceptance.16 frames at0.1simulated seconds; stock profiles, mounts, numerical damage and effect caps unchanged."})

func finish(capture: Dictionary) -> void:
	capture.failures=failures+invalid;capture.checks=checks
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		var file=FileAccess.open(directory.path_join("presentation-flow040.json"),FileAccess.WRITE)
		check(file!=null,"primitive gallery artifact opens")
		if file!=null:
			capture.checks=checks;capture.failures=failures+invalid
			file.store_string(JSON.stringify(capture));file.close()
	print("PRESENTATION040: %d checks, %d failures"%[checks,failures+invalid])
	quit(0 if failures+invalid==0 else 1)
