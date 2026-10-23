extends SceneTree
## Native scene/control signals only; no desktop input, capture, or owner profile.
const Refit=preload("res://scripts/refit.gd")
const Money=preload("res://scripts/money.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const LabUI=preload("res://scripts/lab_ui.gd")
const Portrait=preload("res://scripts/boat_portrait.gd")
var workshop: Script
var game
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL workshop UI: "+message)

func descendants(node: Node) -> Array:
	var result: Array=[node]
	for child in node.get_children():result.append_array(descendants(child))
	return result

func visible_text() -> String:
	var text: Array[String]=[]
	for node in descendants(game.ui.overlay):
		if node is Label or node is Button:text.append(str(node.text))
	return "\n".join(text)

func find_button(prefix: String):
	for node in descendants(game.ui.overlay):
		if node is Button and str(node.text).begins_with(prefix):return node
	return null

func press(prefix: String) -> bool:
	var button=find_button(prefix)
	check(button!=null and not button.disabled,"real control is available: "+prefix)
	if button==null or button.disabled:return false
	button.pressed.emit()
	return true

func module_button(name: String):
	var selected: bool=false
	for node in descendants(game.ui.overlay):
		if node is Label and str(node.text)==name:selected=true
		elif selected and node is Button:return node
	return null

func portraits() -> Array:
	return descendants(game.ui.overlay).filter(func(node):return node.get_script()==Portrait)

func condition(ship: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in ["hp","maxHp","water","engine","crew","wounded","ammo","fuel","supplies","breaches","fire","sunk"]:
		var value=ship[key]
		result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	return result

func property_without_templates(state: Dictionary) -> Dictionary:
	var result: Dictionary=state.duplicate(true)
	result.erase("fitTemplates")
	return result

func exercise_workshop() -> bool:
	var core=game.core
	var ship: Dictionary=core.state.fleet[0]
	var uid: String=ship.uid
	ship.hp-=7.0;ship.engine=0.81;ship.wounded=1.0
	ship.ammo-=5.0;ship.fuel-=3.0;ship.supplies-=2.0
	var health: Dictionary=condition(ship)
	game.save_game(false)
	var before: Dictionary=core.state.duplicate(true)
	var original_file: String=FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))
	game.ui.open_refit(uid)
	var text: String=visible_text()
	check(game.ui.modal_kind=="refit" and "FLEET WORKSHOP" in text,"existing fleet entry opens the actual workshop")
	for label in ["CURRENT FITTING","DRAFT FITTING","Fitting capacity","Battle deployment","Hold","Berths","DAILY & RETURN OBLIGATIONS"]:
		check(label in text,"workspace explains distinct player capacity/budget: "+label)
	var views: Array=portraits()
	check(views.size()==2,"current and draft have separate physical boat previews")
	if views.size()!=2:return false
	check(views[0].show_sockets and views[0].get("show_arcs") and views[1].get("show_arcs"),"numbered socket/arc overlays use actual BoatPortrait controls")
	views[1].mount_selected.emit(1)
	var use=module_button(str(Refit.catalog().weapons.rapid_gun.name))
	check(use!=null and not use.disabled and use.text=="Use in draft","physical second socket offers a compatible real machine gun")
	if use==null or use.disabled:return false
	use.pressed.emit()
	var fit: Dictionary=ship.loadout.duplicate(true)
	fit.weapons[1]="rapid_gun"
	check(game.ui.workshop_drafts[uid]==fit and core.state==before,"native draft control changes UI knowledge only, preserving every canonical asset")
	var q: Dictionary=workshop.preview(core,uid,fit)
	views=portraits()
	check(views.size()==2 and views[0].boat.spec==q.beforeSpec and views[1].boat.spec==q.afterSpec,"actual previews display the quoted current and draft specifications")
	check(FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))==original_file,"browsing/drafting cannot autosave a free installed module")
	game.ui.close_modal();game.ui.open_refit(uid)
	check(game.ui.workshop_drafts[uid]==fit and core.state==before,"reopening preserves the UI-only unsaved draft")
	if not press("Compare known hulls"):return false
	var hull_picker=null
	for node in descendants(game.ui.overlay):
		if node is OptionButton and node.item_count==game.data.HULLS.size():hull_picker=node;break
	check(hull_picker!=null,"known-hull comparison includes the actual catalogue")
	if hull_picker==null:return false
	var last: int=hull_picker.item_count-1
	hull_picker.select(last);hull_picker.item_selected.emit(last)
	check(core.state==before and core.state.fleet.size()==1,"comparing another known hull purchases no hull and mints no capital")
	if not press("Back to owned draft"):return false
	if not press("Fitting templates"):return false
	var fields: Array=descendants(game.ui.overlay).filter(func(node):return node is LineEdit)
	check(fields.size()==1 and fields[0].max_length==48,"actual template-name field exposes its bounded length")
	if fields.size()!=1:return false
	fields[0].text="UI starter defense"
	if not press("Save draft template"):return false
	check(property_without_templates(core.state)==property_without_templates(before),"saving through Main's template control changes knowledge only")
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json")))
	check(saved.get("fitTemplates",[]).size()==1 and saved.fleet[0].loadout==before.fleet[0].loadout,"real career file contains a template and retains the actually installed fit")
	check(not saved.has("workshop_drafts"),"unsaved UI draft is not serialized as career inventory")
	game.load_game();game.paused=true
	core=game.core;ship=core.find_boat(uid)
	check(game.ui.workshop_drafts.is_empty() and condition(ship)==health,"actual Main load clears transient drafts and preserves damaged hull/stores")
	game.ui.open_refit(uid)
	if not press("Fitting templates"):return false
	before=core.state.duplicate(true)
	if not press("Load into draft"):return false
	check(game.ui.workshop_drafts[uid]==fit and core.state==before,"saved template restores the same draft through its actual load control without granting equipment")
	var port: Dictionary=core.current_port()
	q=workshop.preview(core,uid,fit)
	check(q.applicable and q.affordable and q.cost<=int(world_start_coins()),"starter's actual remaining purse and workforce cover the draft")
	if not q.applicable:return false
	var good: String=str(q.materials.keys()[0])
	var stock: float=float(port.stocks[good])
	var other: Dictionary=core.state.ports[1]
	other.stocks[good]+=stock;port.stocks[good]=0.0
	before=core.state.duplicate(true)
	if not press("Review whole-fit quote"):return false
	var apply=find_button("Apply reviewed fitting")
	check(apply!=null and apply.disabled,"actual reviewed bill disables apply for missing physical harbor stock")
	text=visible_text()
	for label in ["COINS TOTAL","Physical materials","Ordinary fitter wages","Expert wages","Registry duty","BOAT LOCKER AFTER THE FIT"]:
		check(label in text,"review exposes the complete real bill: "+label)
	check(core.state==before and condition(ship)==health,"unavailable UI review leaves canonical state EXACT")
	other.stocks[good]-=stock;port.stocks[good]=stock
	if not press("Back to draft"):return false
	if not press("Review whole-fit quote"):return false
	# Alter one real purse after review while remaining affordable. The existing
	# button retains its old quote closure, so this exercises the actual stale UI.
	check(Money.move(core.state,"coins",port,"governmentPurse",1,"Fixture deposit after review",core.state.moneyLog),"stale-review setup conserves the finite coin supply")
	before=core.state.duplicate(true)
	var file_before: String=FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))
	if not press("Apply reviewed fitting"):return false
	check(core.state==before and FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json"))==file_before,"real stale apply refuses before mutation or autosave")
	var state_ref: Dictionary=core.state
	var ship_ref: Dictionary=ship
	var port_ref: Dictionary=port
	q=workshop.preview(core,uid,fit)
	if not press("Review whole-fit quote"):return false
	if not press("Apply reviewed fitting"):return false
	check(ship.loadout==fit and int(core.state.coins)==int(before.coins)-int(q.cost),"actual native apply installs the reviewed draft and debits the exact bill once")
	check(condition(ship)==health and is_same(core.state,state_ref) and is_same(core.find_boat(uid),ship_ref) and is_same(core.current_port(),port_ref),"Main apply preserves live callers, damaged hull, crew and paid stores")
	check(Money.total(core.state)==int(core.state.coinSupply),"actual UI apply conserves the full world coin ledger")
	saved=JSON.parse_string(FileAccess.get_file_as_string(game.save_directory.path_join("voyage.json")))
	check(saved.fleet[0].loadout==fit and saved.fitTemplates.size()==1,"successful Main apply saves installed fitting and retained knowledge together")
	apply=find_button("Review whole-fit quote")
	check(apply!=null and apply.disabled,"fresh workspace cannot apply the same installed fitting a second time")
	return ship.loadout==fit

func world_start_coins() -> int:
	return int(game.data.START.coins)

func exercise_lab() -> void:
	var career=game.core
	var ship: Dictionary=career.state.fleet[0]
	var expected: Dictionary=workshop.preview(career,ship.uid,ship.loadout).afterSpec
	var snapshot: Dictionary=career.state.duplicate(true)
	var player: Dictionary=Lab.entry(game.data,str(ship.type))
	player.loadout=ship.loadout.duplicate(true)
	game.open_lab()
	game.lab_config={"player":[player],"enemy":[Lab.entry(game.data,str(ship.type))]}
	game.lab_seed=29083
	LabUI.edit(game.ui,"player",0)
	var choices: Array=descendants(game.ui.overlay).filter(func(node):return node is OptionButton)
	var sockets: Array=Refit.hardpoints(ship.baseSpec)
	check(choices.size()==sockets.size()+2,"actual lab fitting includes every physical socket plus engine and armor")
	var cat: Dictionary=Refit.catalog()
	for i in range(mini(sockets.size(),choices.size())):
		for j in range(choices[i].item_count):
			var id: String=str(choices[i].get_item_metadata(j))
			check(cat.weapons.has(id) and int(cat.weapons[id].size)<=int(sockets[i].size) and (id!="stock_primary" or i==0),"lab offers only compatible real weapon modules for socket %d: %s"%[i,id])
	check(career.state==snapshot,"lab fitting inspection cannot bill or alter the saved career")
	if not press("Apply fitting"):return
	game.start_lab();game.paused=true
	check(game.lab_active and game.quick_mode and game.core!=career and game.career_core==career,"actual laboratory battle isolates the career object")
	var players: Array=game.battle.ships.filter(func(boat):return boat.team=="player")
	check(players.size()==1 and players[0].spec.weaponMounts==expected.weaponMounts,"native battle has the previewed module IDs, physical origins and firing arcs")
	for i in range(30):game.Battle.update(game.battle,1.0/30.0,{})
	check(career.state==snapshot,"one second of actual lab battle spends only isolated fixture stores")
	game.return_to_campaign();game.paused=true
	check(game.core==career and career.state==snapshot,"leaving lab returns the unchanged paid career and template library")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()!="headless":
		check(false,"this suite requires the root's hidden headless/silent engine lease")
	elif not ResourceLoader.exists("res://scripts/fleet_workshop.gd") or not ResourceLoader.exists("res://scripts/workshop_ui.gd"):
		check(false,"root must integrate helper B's actual workshop modules before this suite runs")
	else:
		workshop=load("res://scripts/fleet_workshop.gd")
		game=load("res://main.tscn").instantiate()
		root.add_child(game)
		game.set_process(false);game.set_physics_process(false)
		game.audio.enabled=false;game.music.enabled=false
		game.save_directory=OS.get_user_data_dir().path_join("workshop-ui-%d"%Time.get_ticks_usec())
		await process_frame
		game.new_game();game.paused=true
		game.core.state.seed=29083
		if exercise_workshop():exercise_lab()
		game.queue_free()
		await process_frame
	print("workshop UI: %d checks, %d failures; native controls only, background/headless/silent"%[checks,failures])
	quit(0 if failures==0 else 1)
