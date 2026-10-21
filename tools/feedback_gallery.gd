extends SceneTree
## Capture actual game draw calls in a reproducible damage/sinking fixture, without a window.
const Test=preload("res://tests/test_feedback.gd")
const Art=preload("res://scripts/boat_art.gd")
const FX=preload("res://scripts/combat_art.gd")
const Damage=preload("res://scripts/damage.gd")
const Battle=preload("res://scripts/battle.gd")
const Events=preload("res://scripts/combat_events.gd")
const Refit=preload("res://scripts/refit.gd")
var invalid: int=0

func _initialize() -> void:call_deferred("capture")

func panel(id: String,title: String,boat: Dictionary,time: float,mode: String="boat",state: Dictionary={}) -> Dictionary:
	var canvas:=Test.Recorder.new()
	canvas.scale_factor=(5.0 if float(boat.spec.size)<=17 else 3.5) if mode=="boat" else 3.2
	canvas.origin=Vector2(260,260)
	if mode=="wreck":
		FX.wreck(canvas,state.wrecks[0])
		for effect in state.effects:FX.effect(canvas,effect)
	else:
		Art.draw_boat(canvas,canvas.project,boat,{"lod":0,"px":float(boat.spec.size)*canvas.scale_factor,"clock":time,"combat":true,"battle_clock":time,"cache":true})
		for effect in state.get("effects",[]):FX.effect(canvas,effect)
	invalid+=canvas.invalid
	return {"id":id,"title":title,"width":520,"height":430,"background":"#183e4b","primitives":canvas.prims}

func capture() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var motor: Dictionary=Damage.create_ship(Refit.effective_spec(world.HULLS[0],Refit.defaults(world.HULLS[0])))
	motor.angle=-0.35;motor.vx=65.0
	var armed: Dictionary=Damage.create_ship(Refit.effective_spec(world.HULLS[15],Refit.defaults(world.HULLS[15])))
	armed.angle=-0.5
	var burning: Dictionary=armed.duplicate(true)
	burning.hp*=0.45;burning.engine=0.18;burning.fire=42.0
	var state: Dictionary=Battle.create({"fleet":[armed],"enemySpecs":[world.HULLS[0]],"seed":707})
	# Put the fixtures at the shared recorder's origin after deployment.
	armed.x=0.0;armed.y=0.0;armed.angle=-0.5
	var at: Vector2=Vector2(0.7,0.22).rotated(armed.angle)*float(armed.spec.size)
	Events.emit_hit(state,{"kind":"shell","vx":-200,"vy":0,"owner":"fixture","team":"enemy"},armed,at,"bow",["Breach: bow"],20)
	armed.hp*=0.7
	var sinking: Dictionary=Damage.create_ship(Refit.effective_spec(world.HULLS[10],Refit.defaults(world.HULLS[10])))
	sinking.x=0.0;sinking.y=0.0;sinking.angle=-0.45;sinking.sunk=true;sinking.hp=0.0;sinking.fire=35.0;sinking.engine=0.0
	var sink_state: Dictionary={"time":0.0,"effects":[],"wrecks":[]}
	Events.ensure_state(sink_state)
	var wreck: Dictionary=Events.record_wreck(sink_state,sinking,sinking.spec.size)
	Events.emit_sink(sink_state,sinking,wreck)
	var flooding: Dictionary=sinking.duplicate(true)
	flooding.hp=70.0;flooding.fire=0.0;flooding.water=flooding.capacity
	var flood_state: Dictionary={"time":0.0,"effects":[],"wrecks":[]}
	Events.ensure_state(flood_state)
	var flood_wreck: Dictionary=Events.record_wreck(flood_state,flooding,flooding.spec.size)
	Events.emit_sink(flood_state,flooding,flood_wreck)
	var frames: Array=[]
	var overview: Array=[]
	for i in range(45):
		var time: float=i/12.0
		for effect in state.effects:effect.age=fmod(time,1.15)
		for effect in sink_state.effects:effect.age=time
		for effect in flood_state.effects:effect.age=time
		wreck.age=time;wreck.sinkProgress=clampf(time/float(wreck.sinkDuration),0,1)
		flood_wreck.age=time;flood_wreck.sinkProgress=clampf(time/float(flood_wreck.sinkDuration),0,1)
		var panels: Array=[panel("motors","Transom motors",motor,time),panel("sparks","Armor impacts / deck fire",burning if time>1.15 else armed,time,"boat",state),panel("sink","Destroyed hull / sinking",sinking,time,"wreck",sink_state),panel("flood","Flooding / sinking",flooding,time,"wreck",flood_state)]
		frames.append({"time":time,"panels":panels})
		if i==2 or i==15 or i==26:overview.append_array(panels)
	var target: String=ProjectSettings.globalize_path("res://../qa/feedback.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):target=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	FileAccess.open(target,FileAccess.WRITE).store_string(JSON.stringify({"failures":invalid,"panels":overview,"frames":frames}))
	print("FEEDBACK GALLERY: %d frames, %d invalid primitives"%[frames.size(),invalid])
	quit(0 if invalid==0 else 1)
