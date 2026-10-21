extends SceneTree
const C=preload("res://scripts/campaign.gd")
const Salvage=preload("res://scripts/salvage.gd")
const Damage=preload("res://scripts/damage.gd")
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL salvage voyage: ",message)

func _initialize():
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(world)
	c.new_game(83)
	var initial_food: float=c.state.cargo.food
	check(c.jettison("food",3).ok and c.state.cargo.food==initial_food-3,"A marked float contains actual offloaded goods")
	var float_id: String=c.state.wrecks[0].id
	check(c.recover_wreck(float_id,"strip").ok and c.state.cargo.food==initial_food,"The same finite food can be recovered into available space")
	check(not c.recover_wreck(float_id,"strip").ok,"Claimed cargo cannot duplicate")
	var site: Dictionary=c.state.position.duplicate(true)
	site.id="finite-test-site"
	var w: Dictionary=Salvage.seed_site_wreck(c,site,"harbor_sloop")
	check(Salvage.strip_good(c,w.id,"timber",0.1).ok,"Recover one selected component instead of the entire wreck")
	check(not Salvage.quote(c,w.id,"tow").ok,"Structural stripping forbids a second complete hull recovery")
	var amount: float=c.state.cargo.timber
	check(Salvage.strip_good(c,w.id,"timber",0.1).ok and is_equal_approx(c.state.cargo.timber,amount+0.1),"Remaining finite lots can still be stripped")
	var ship: Dictionary=Damage.create_ship(c.hull("tin_skiff"),{"ammo":2.25,"fuel":0.004,"supplies":0.004})
	ship.sunk=true;ship.team="enemy"
	var records: Array=Salvage.record_battle(c,{"ships":[ship]},"fractional-stores")
	check(is_equal_approx(records[0].stores.ammo,2.25/50.0),"Fractional ammo cases retain every original round without rounding up")
	check(is_equal_approx(records[0].stores.fuel,0.004),"Tiny remaining fuel is neither minted nor lost to display rounding")
	for i in range(140):Salvage.record_battle(c,{"ships":[ship]},"prune-fixture-%d"%i)
	check(c.state.wrecks.size()<=128,"Wreck history stays bounded")
	check(Salvage.seed_site_wreck(c,site,"harbor_sloop").is_empty(),"A pruned ancient site cannot spawn a fresh replacement wreck")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	check(c.restore(saved).ok,"Persistent wrecks and provenance pass actual campaign restore")
	check(Money.total(c.state)==int(c.state.coinSupply),"Recovery keeps the global coin ledger exact")
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("salvage-fixture")
	scene.new_game()
	scene.core.jettison("food",1)
	scene.ui.RecoveryUI.open(scene.ui)
	check(scene.ui.modal_kind=="recovery","Recovery board opens in actual Main")
	scene.ui.RecoveryUI.blueprints(scene.ui)
	check(scene.ui.modal_kind=="blueprints","Drawing library opens in actual Main")
	scene.queue_free()
	await process_frame
	print("salvage voyage: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
