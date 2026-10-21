extends SceneTree
const C=preload("res://scripts/campaign.gd")
const Money=preload("res://scripts/money.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Workers=preload("res://scripts/economy_workers.gd")
const Deployment=preload("res://scripts/deployment.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL logistics: ",message)

func _initialize():
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(data)
	c.new_game(83)
	var initial: Dictionary=c.state.fleet[0]
	var extra: Dictionary=c.add_boat(c.hull(initial.type),0)
	check(is_equal_approx(c.capacity(),initial.spec.cargo),"An inactive uncrewed boat creates no usable hold")
	var coins: int=Money.total(c.state)
	check(c.toggle_storage(extra.uid).ok,"Uncrewed extra hull can be stored")
	check(extra.storedPort==c.current_port().id and not c.active_fleet().has(extra),"Stored hull stays at its harbor")
	var cargo_before: Dictionary=c.state.cargo.duplicate(true)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	check(c.restore(saved).ok,"Storage and cargo save roundtrip")
	check(c.find_boat(extra.uid).storedPort==c.current_port().id and c.state.cargo==cargo_before,"Restore keeps location and every item")
	check(Money.total(c.state)==coins,"Storage/migration conserve all coins")
	for i in range(8):c.add_boat(c.hull("maiden_dreadnought"),0)
	check(c.fleet_points()>300 and c.can_add_boat(c.hull(initial.type)),"Ownership may exceed300 while allowing more reserves")
	check(Deployment.split(c.active_fleet()).points<=300,"Battle deployment remains300")
	var carrier: Dictionary=c.state.fleet[0]
	Manifest.allocate(c.state)
	var held: Dictionary=c.state.cargoManifest.get(carrier.uid,{}).duplicate(true)
	carrier.sunk=true
	Manifest.losses(c.state)
	for good in held:
		if not str(good).begins_with("@"):
			check(is_equal_approx(c.state.cargo[good],maxf(0,cargo_before.get(good,0)-held[good])),"Cargo loss follows actual carrier")
	var after: Dictionary=c.state.cargo.duplicate(true)
	Manifest.losses(c.state)
	check(c.state.cargo==after,"Sunk carrier losses settle once")
	c.new_game(83)
	var before: int=Money.total(c.state)
	var original: Array=c.state.ports.duplicate(true)
	var worker=Workers.new()
	worker.start(c.state.ports,1,[],83)
	var result: Dictionary=worker.finish(true)
	check(c.state.ports==original,"Workers never mutate the live harbor array")
	c.apply_economy(result.ports,result.events,1)
	check(Money.total(c.state)==before,"Parallel production and publication conserve coins")
	check(result.workers>=1 and result.workers<=8,"Hardware worker budget stays bounded")
	check(worker.group_id==-1,"Completed group is joined and cleaned up")
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("logistics-fixture")
	scene.new_game()
	scene.ui.CampaignUI.expedition(scene.ui)
	check(scene.ui.modal_kind=="expedition" and scene.ui.modal_open,"Preparation window is reachable in actual Main")
	scene.ui.CampaignUI.notes(scene.ui)
	check(scene.ui.modal_kind=="developer_notes","TXT developer notes open in actual Main")
	scene.queue_free()
	await process_frame
	print("campaign logistics: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
