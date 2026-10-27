extends SceneTree
## SOURCE CANDIDATE, NATIVE UNRUN. Root integrates both 048 source commits and host seam.
## One existing starter, two native viewport layouts, no external input or simulation loop.
const WorkshopUI=preload("res://scripts/workshop_ui.gd")
const Comparison=preload("res://scripts/workshop_comparison048.gd")
const EquipmentPicker=preload("res://scripts/equipment_picker.gd")
const Portrait=preload("res://scripts/boat_portrait.gd")
const Refits=preload("res://scripts/refit.gd")
const Builds=preload("res://scripts/workshop_builds048.gd")
var game
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL workshop_layout048: "+message)

func nodes(node: Node) -> Array:
	var result: Array=[node]
	for child in node.get_children():result.append_array(nodes(child))
	return result

func text() -> String:
	var lines: Array[String]=[]
	for node in nodes(game.ui.overlay):
		if node is Label or node is Button:lines.append(str(node.text))
	return "\n".join(lines)

func button(prefix: String):
	for node in nodes(game.ui.overlay):
		if node is Button and str(node.text).begins_with(prefix):return node
	return null

func press(prefix: String) -> bool:
	var action=button(prefix)
	check(action is Button and not action.disabled,"enabled native action: "+prefix)
	if not action is Button or action.disabled:return false
	action.pressed.emit()
	return true

func geometry(uid: String,draft: Dictionary,viewport: Vector2i) -> void:
	root.content_scale_size=viewport;root.size=viewport
	await process_frame;await process_frame
	WorkshopUI.open(game.ui,uid,draft,1)
	await process_frame;await process_frame
	var screen: Rect2=Rect2(Vector2.ZERO,Vector2(viewport))
	var panel=game.ui.overlay.get_child(1)
	check(panel is PanelContainer and screen.encloses(panel.get_global_rect().grow(-0.5)),"fitting modal remains inside "+str(viewport))
	var trial=game.ui.overlay.find_child("WorkshopTryDraft",true,false)
	check(trial is Button and screen.encloses(trial.get_global_rect().grow(-0.5)),"current-draft Lab action is visible before scrolling at "+str(viewport))
	var narrow: bool=true
	for node in nodes(game.ui.overlay):
		if node is ScrollContainer:narrow=narrow and node.get_h_scroll_bar().max_value<=node.size.x+1.0
		if node is GridContainer and node.name in ["WorkshopFitComparison","WorkshopMountComparison"]:
			var area: Rect2=node.get_global_rect()
			narrow=narrow and area.position.x>=panel.position.x and area.end.x<=panel.get_global_rect().end.x
			for cell in node.get_children():
				narrow=narrow and cell.get_global_rect().position.x>=area.position.x-0.5 and cell.get_global_rect().end.x<=area.end.x+0.5
	check(narrow,"comparison columns fit the existing vertical scroll without horizontal clipping at "+str(viewport))

func exercise() -> void:
	var career=game.core
	var ship: Dictionary=career.state.fleet[0]
	var uid: String=str(ship.uid)
	var draft: Dictionary=ship.loadout.duplicate(true)
	draft.engine="economy_drive";draft.weapons[1]="rapid_gun"
	check(Refits.normalize(career.hull(str(ship.type)),draft).ok,"starter supports the actual unpaid test draft")
	var saved: Dictionary=career.state.duplicate(true)
	var draft_bytes: Dictionary=draft.duplicate(true)
	for viewport in [Vector2i(1600,1000),Vector2i(1280,800)]:await geometry(uid,draft,viewport)
	var quote: Dictionary=EquipmentPicker.preview_workshop(game.ui,uid,draft)
	check(quote.validDraft and quote.changes.size()==2,"live fitting authority quotes the two real draft changes")
	var visible: String=text()
	for phrase in ["CURRENT","DRAFT","CHANGE","Stated reload","Rounds per shot","Fuel consumption","Fleet working-fuel endurance","100 coins per sailor-day","Integral pump"]:
		check(phrase in visible,"comparison exposes the relevant tradeoff: "+phrase)
	check(str(game.ui.overlay.find_child("WorkshopQuoteStatus",true,false).text).contains(game.ui.money(quote.cost)),"visible bill uses the exact whole-fit quote")
	var rows: Array=Comparison.stat_rows(career.hull(str(ship.type)),quote)
	var fuel: Array=rows.filter(func(row):return row.label=="Fuel consumption")
	check(fuel.size()==1 and str(fuel[0].delta).begins_with("-"),"an economy-drive draft visibly reduces fuel use instead of showing two unlabelled specs")
	var before_model: Dictionary=quote.duplicate(true)
	Comparison.mount_rows(quote.beforeSpec,quote.afterSpec,str(Refits.hardpoints(ship.baseSpec)[1].id),float(ship.ammo))
	check(quote==before_model and draft==draft_bytes and career.state==saved,"comparison and quote leave the complete career, draft input and quote unchanged")
	var views: Array=nodes(game.ui.overlay).filter(func(node):return node.get_script()==Portrait)
	check(views.size()==2 and views[1].selected_socket==1,"both actual BoatPortraits show the selected physical socket")
	if views.size()==2:views[1].mount_selected.emit(1)
	check(game.ui.overlay.find_child("WorkshopMountComparison",true,false)!=null and "SELECTED SOCKET 2" in text(),"physical portrait selection reaches mount compatibility and before/draft firing values")
	if not press("Back to whole fitting"):return
	if not press("Three build examples"):return
	var loads: Array=nodes(game.ui.overlay).filter(func(node):return node is Button and str(node.name).begins_with("WorkshopExample_"))
	check(loads.size()==3 and loads.all(func(node):return node.disabled),"three real examples are visible; an unsupported owned hull cannot receive their equipment")
	for example in Builds.examples(career.hull(Builds.HULL_ID)):check(str(example.tradeoff) in text(),"example shows its actual tradeoff: "+str(example.id))
	if not press("Compare known build"):return
	check("KNOWN DESIGNS" in text() and "stated reload" in text(),"known-build comparison exposes actual weapon implications without buying a hull")
	if not press("Back to owned draft"):return
	check(game.ui.workshop_drafts[uid]==draft and career.state==saved,"example browsing and return preserve the current unpaid draft and paid fleet")
	check(game.has_method("workshop_try_draft"),"Root's agreed isolated Lab host seam is integrated")
	if not game.has_method("workshop_try_draft"):return
	if not press("Try current draft in Lab"):return
	check(game.lab_config.player[0].loadout==draft,"native trial button passes this draft, rather than the installed loadout")
	check(game.lab_active,"the agreed trial action starts the existing Lab immediately")
	if not game.lab_active:return
	game.paused=true
	check(game.lab_active and game.career_core==career and game.core!=career and career.state==saved,"existing Lab isolates the whole paid career")
	var players: Array=game.battle.ships.filter(func(boat):return boat.team=="player")
	check(players.size()==1 and players[0].loadout==draft and float(players[0].ammo)>0 and float(players[0].fuel)>0,"actual Lab construction fits the draft with finite practice stores")
	game.return_to_campaign();game.paused=true
	check(game.core==career and career.state==saved,"returning from the unpaid trial preserves all original crew, condition, stores, stock and money")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()!="headless":check(false,"Root must use background/headless/Dummy and synthetic APPDATA through Test Bridge")
	else:
		game=load("res://main.tscn").instantiate();root.add_child(game)
		game.set_process(false);game.set_physics_process(false)
		game.audio.enabled=false;game.music.enabled=false
		game.save_directory=OS.get_user_data_dir().path_join("workshop048-%d"%Time.get_ticks_usec())
		await process_frame
		game.new_game();game.paused=true
		await exercise()
		game.queue_free();await process_frame
	print("workshop_layout048: %d checks, %d failures; native layout and draft callbacks only"%[checks,failures])
	quit(0 if failures==0 else 1)
