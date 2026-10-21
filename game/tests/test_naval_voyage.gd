extends SceneTree
const C=preload("res://scripts/campaign.gd")
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL naval voyage: ",message)
func _initialize():
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(131)
	var supply: int=M.total(c.state)
	check(c.state.navalAi.ordersByOwner.size()==17,"Real campaign initializes all existing fleet objectives without recursion")
	var story_before: Dictionary=c.fleet_owner("story-0").boats[0].duplicate(true)
	var owner: Dictionary=c.fleet_owner("patrol-0")
	var guard: Dictionary=c.fleet_owner("patrol-2")
	var p: Dictionary=c.NavalAI._find_patrol(c.state,owner.id)
	var g: Dictionary=c.NavalAI._find_patrol(c.state,guard.id)
	for patrol in c.state.patrols:patrol.x=500+c.state.patrols.find(patrol)*700;patrol.y=250
	p.x=4200;p.y=3100;g.x=4230;g.y=3110;p.holding=true;g.holding=true
	c.state.day=3;c.state.path=[];c.state.encounterGrace=0
	c.state.position={"x":4200,"y":3100}
	c.step(0)
	check(c.pop_events().any(func(e):return e.kind=="encounter"),"Stationary player can be intercepted; waiting at sea is not immunity")
	var shots: float=owner.boats[0].ammo+guard.boats[0].ammo
	c.NavalLifecycle.daily(c)
	check(owner.boats[0].ammo+guard.boats[0].ammo<shots,"Integrated daily decisions resolve an actual offscreen engagement")
	check(c.fleet_owner("story-0").boats[0].hp==story_before.hp,"Automatic fights preserve authored story opponents")
	c.Factions.set_relation(c.state,owner.faction,guard.faction,0,"Fixture negotiated ceasefire")
	check(not preload("res://scripts/naval_combat.gd").are_hostile(c.state,owner,p,guard,g),"NPC hostility reads actual symmetric diplomacy")
	check(M.total(c.state)==supply,"Daily orders, fighting and replacements conserve all purses")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual restore preserves AI orders and damaged boats")
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("naval-voyage-fixture");scene.new_game()
	scene.ui.NavalUI.open(scene.ui)
	check(scene.ui.modal_kind=="sea_traffic","Coastal traffic window renders observed fleet roles")
	scene.queue_free();await process_frame
	print("naval voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
