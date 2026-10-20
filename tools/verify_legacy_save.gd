extends SceneTree
## Read-only migration check against a real portable save; no save files are written.
const Campaign=preload("res://scripts/campaign.gd")
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0

func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		print("FAIL legacy: "+message)

func _initialize():
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path=arg.trim_prefix("--save=")
	if path.is_empty():
		push_error("Pass --save=<real v0.001 voyage.json>")
		quit(1)
		return
	var original: String=FileAccess.get_file_as_string(path)
	var saved=JSON.parse_string(original)
	if not saved is Dictionary:
		push_error("The selected save is not a JSON dictionary.")
		quit(1)
		return
	var snapshot: Dictionary=saved.duplicate(true)
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var core=Campaign.new(world)
	var result: Dictionary=core.restore(saved)
	check(result.ok,"real portable voyage restores: "+str(result.message))
	check(saved==snapshot,"migration leaves the supplied save dictionary untouched")
	if result.ok:
		check(Money.total(core.state)==int(saved.coinSupply),"all real purses conserve the original coin supply")
		check(core.state.fleet.size()==saved.fleet.size(),"all owned boats survive migration")
		for previous in saved.fleet:
			var boat: Dictionary=core.find_boat(previous.uid)
			for field in ["hp","crew","wounded","water","ammo","fuel","supplies","engine"]:
				check(is_equal_approx(float(boat[field]),float(previous[field])),"migration preserves "+previous.uid+" "+field)
			check(boat.has("loadout") and boat.spec.has("weaponMounts"),"canonical default fittings added to "+previous.uid)
	check(FileAccess.get_file_as_string(path)==original,"original save bytes are unchanged")
	print("legacy migration: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
