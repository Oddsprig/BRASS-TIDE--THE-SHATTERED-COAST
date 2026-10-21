extends SceneTree
const C=preload("res://scripts/campaign.gd")
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL political voyage: ",message)
func _initialize():
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(121)
	check(c.Factions.relation(c.state,"reed","raiders")==-25 and c.Factions.relation(c.state,"raiders","reed")==-25,"Canonical pair ordering preserves Reed-raider hostility in both directions")
	var supply: int=M.total(c.state)
	check(c.Politics.access(c,c.current_port()).legal,"Neutral civilian harbor access")
	var before: String=JSON.stringify(c.state)
	check(not c.trade(c.current_port().id,"engines",1,"buy").ok and JSON.stringify(c.state)==before,"Restricted purchase fails atomically through actual campaign")
	check(c.Politics.permit(c,"service").ok and not c.Politics.permit(c,"military").ok,"Basic paid fittings available; advanced military gated")
	c.Factions.adjust(c.state,"compact",20,"Fixture fulfilled contracts")
	check(c.Politics.permit(c,"military").ok,"Friendly standing unlocks military equipment")
	var first: Dictionary=c.Factions.commission(c.state,"compact")
	check(not first.committed and M.total(c.state)==supply,"Commission first presents terms without a stipend")
	check(c.Factions.commission(c.state,"compact").committed and M.total(c.state)==supply,"Explicit acceptance applies political costs without coins")
	var enemy: Dictionary={"id":"peaceful-fixture","faction":"compact","homePort":"brass_haven"}
	c.Politics.declare_attack(c,enemy)
	c.Politics.settled(c,enemy,"won",{"aggression":true})
	check(c.Factions.is_hostile(c.state,"compact") and not c.Politics.permit(c,"service").ok,"Confirmed attack creates witnessed hostility independent of friendly public score")
	c.Factions.adjust(c.state,"compact",-25,"witness:Additional documented losses")
	c.Factions.adjust(c.state,"compact",-25,"witness:Additional documented losses")
	var p: Dictionary=c.current_port()
	var fee: int=1000+int(c.Politics.access(c,p).claim)*100
	var purse: int=c.state.coins
	check(c.Politics.parley(c).ok and purse-c.state.coins==fee and M.total(c.state)==supply,"Parley pays exact workers, experts and government; global coins conserved")
	check(c.Politics.permit(c,"service").ok and not c.Politics.permit(c,"military").ok,"Paid temporary civilian access does not buy military trust")
	check(not c.Politics.parley(c).ok,"Pass cannot stack")
	check(c.Politics.inspect(c).ok,"Actual inspected cargo admitted without invented fine")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Relationships and permit restore through real campaign schema")
	c.state.day+=3.1
	check(not c.Politics.permit(c,"service").ok,"Permit expires on the campaign clock")
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("political-voyage-fixture")
	scene.new_game();scene.ui.FactionUI.open(scene.ui)
	check(scene.ui.modal_kind=="factions","Actual faction menu renders")
	scene.ui.FactionUI.terms(scene.ui,"compact")
	check(scene.ui.modal_open,"Actual commission review renders")
	scene.queue_free();await process_frame
	print("political voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
