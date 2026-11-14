extends SceneTree
const Main=preload("res://scripts/main.gd")
const Route=preload("res://scripts/harbor_route104.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("HARBOR104 "+message)
func button(root_node: Node,caption: String) -> Button:
	if root_node is Button and root_node.text==caption:return root_node
	for child in root_node.get_children():
		var found: Button=button(child,caption)
		if found!=null:return found
	return null
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=Main.new()
	game.qa_ocean066=true
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.set_process_input(false);game.set_process_unhandled_input(false)
	var result: Dictionary=game.core.new_game(104104)
	check(bool(result.get("ok",false)),"ordinary fresh career starts")
	game.mode="campaign";game.paused=true;game.ui.build_hud()
	game.chart.step(0.0)
	var target: Dictionary=game.core.port("sawtooth_mill")
	check(not target.is_empty(),"known contrasting harbor exists")
	var before: PackedByteArray=var_to_bytes(game.core.state)
	var q: Dictionary=Route.quote(game.core,str(target.id))
	check(not q.is_empty() and bool(q.routeAvailable),"actual hull has a safe route")
	check(float(q.distance)>0 and float(q.endurance.outwardDays)>0,"route has real distance and travel time")
	check(var_to_bytes(game.core.state)==before,"preview preserves all campaign purses cargo and course")
	Route.open(game.ui,str(target.id))
	check(game.ui.modal_kind=="harbor_route104","route preview opens")
	check(button(game.ui.overlay,"Set course")!=null,"explicit sailing action is present")
	check(button(game.ui.overlay,"Cancel")!=null,"cancellation is present")
	check(var_to_bytes(game.core.state)==before,"opening the UI does not depart or spend")
	button(game.ui.overlay,"Cancel").pressed.emit()
	check(var_to_bytes(game.core.state)==before,"cancelling leaves the voyage unchanged")
	Route.open(game.ui,str(target.id))
	button(game.ui.overlay,"Set course").pressed.emit()
	check(str(game.core.state.destination)==str(target.id) and not game.core.state.path.is_empty(),"confirmation uses actual sailing path and destination")
	check(int(game.core.state.coins)==int(var_to_dict(before).get("coins",-1)),"charting the route does not buy stores")
	if has_method("capture104"):await capture104(game,q)
	print("HARBOR104_DONE ",JSON.stringify({"checks":checks,"failures":failures,"distance":q.distance,"days":q.endurance.outwardDays}))
	game.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
func var_to_dict(bytes: PackedByteArray) -> Dictionary:return bytes_to_var(bytes)
