extends SceneTree
## One small integration fixture. Root owns native execution and the shared lane.
const Guidance=preload("res://scripts/campaign_guidance.gd")
const GuidanceUI=preload("res://scripts/guidance_ui.gd")
const CAREERS=["explorer","merchant","escort","privateer","fisher","passenger"]
const DESTINATIONS={"exploration":"islands","trade":"trade_intel","jobs":"voyage_jobs","fishing":"voyage_jobs","traffic":"sea_traffic","contracts":"contracts","market":"port","yard":"port","catalog":"catalog","fleet":"fleet","law":"customs","boarding":"boarding","supply":"expedition","hold":"cargo"}
var checks: int=0
var failures: int=0
var scene
var c

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL career flow038: ",message)

func snapshot() -> String:
	return JSON.stringify({"state":c.state,"data":c.data})

func button_in(node: Node,caption: String) -> Button:
	if node is Button and node.text==caption:return node
	for child in node.get_children():
		var found: Button=button_in(child,caption)
		if found!=null:return found
	return null

func text_in(node: Node,needle: String) -> bool:
	if node is Label and needle in str(node.text):return true
	for child in node.get_children():
		if text_in(child,needle):return true
	return false

func picker_in(node: Node) -> OptionButton:
	if node is OptionButton:return node
	for child in node.get_children():
		var found: OptionButton=picker_in(child)
		if found!=null:return found
	return null

func _initialize() -> void:
	scene=load("res://main.tscn").instantiate();root.add_child(scene)
	await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	scene.save_directory=OS.get_user_data_dir().path_join("career-flow-038-%d"%Time.get_ticks_usec())
	scene.new_game();c=scene.core
	scene.selected_port="" # Exercise guidance with no chart destination selected.
	check(scene.mode=="campaign" and not c.state.is_empty(),"actual Main publishes an isolated career")
	if not c.state.is_empty():_flow()
	scene.sync_economy();scene.free()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _flow() -> void:
	var ui=scene.ui
	var prior_pending: int=c.pending_days
	c.pending_days=prior_pending+1 # Exercise the wrapper without starting a worker.
	var before: String=snapshot()
	var guide: Button=button_in(ui.root,"?  Guide")
	check(guide!=null,"campaign Guide button is available")
	if guide==null:c.pending_days=prior_pending;return
	guide.pressed.emit()
	check(text_in(ui.overlay,"Keep the water outside"),"existing useful Guide cards remain")
	var entry: Button=button_in(ui.overlay,"Career goals & first steps")
	check(entry!=null and not entry.disabled,"existing Guide exposes career entry")
	if entry==null:c.pending_days=prior_pending;return
	entry.pressed.emit()
	check(ui.modal_kind=="captain_priorities" and snapshot()==before,"Guide link opens the read-only priorities panel")
	var close: Button=button_in(ui.overlay,"Close")
	if close!=null:close.pressed.emit()
	check(close!=null and not ui.modal_open and c.pending_days==prior_pending+1 and scene.economy_task<0 and snapshot()==before,"Guide/priorities entry and Close preserve pending_days without a live worker")
	c.pending_days=prior_pending
	var navigation: Dictionary=c.nav
	scene.selected_port=str(c.state.ports[0].id);c.nav={} # Actual Routes.path returns no safe route.
	GuidanceUI.open(ui)
	check(text_in(ui.overlay,"No safe sailing route") and text_in(ui.overlay,"Sailing quote unavailable") and text_in(ui.overlay,"Reserve-only budget") and not text_in(ui.overlay,"The estimate is a round trip"),"unreachable selected harbor shows unavailable sailing quote and reserve-only budget")
	c.nav=navigation;scene.selected_port="";GuidanceUI.open(ui)
	var options: Array=Guidance.careers()
	var ids: Array=[]
	for option in options:ids.append(str(option.id))
	check(ids.has("captain") and ids.has("harbormaster") and CAREERS.all(func(id):return ids.has(id)),"six careers and both legacy choices are selectable")
	var routes: Dictionary={}
	for id in CAREERS:
		ui.guidance_career=id;before=snapshot();GuidanceUI.open(ui)
		var plan: Dictionary=Guidance.report(c,0.0,id).get("careerPlan",{})
		check(plan.get("id","")==id and not str(plan.get("firstGoal","")).is_empty() and not str(plan.get("nextStep","")).is_empty() and text_in(ui.overlay,str(plan.firstGoal)) and text_in(ui.overlay,str(plan.nextStep)),id+": actual first goal and next step displayed")
		var complete: bool=not plan.get("requirements",[]).is_empty()
		for requirement in plan.get("requirements",[]):complete=complete and text_in(ui.overlay,str(requirement))
		var costs: String=str(plan.get("operatingCosts",{}).get("summary",""))
		var reward: String=str(plan.get("rewardSource",""))
		check(complete and not costs.is_empty() and not reward.is_empty() and text_in(ui.overlay,costs) and text_in(ui.overlay,reward),id+": actual requirements, quote costs and reward source displayed")
		for key in ["actionId","nextActionId"]:
			var action: String=str(plan.get(key,""))
			var link: Button=button_in(ui.overlay,GuidanceUI.action_label(action))
			check(not action.is_empty() and DESTINATIONS.has(action) and link!=null and not link.disabled,id+": usable "+key+" even before owning its next boat")
			if not action.is_empty():routes[action]=id
		check(snapshot()==before,id+": reports and UI preserve complete state/world, including purses, goods and jobs")
	# Operate each distinct generated panel link, never an acceptance/purchase button.
	for action in routes:
		ui.guidance_career=routes[action];GuidanceUI.open(ui)
		var link: Button=button_in(ui.overlay,GuidanceUI.action_label(action))
		if link==null:continue
		link.pressed.emit()
		check(ui.modal_kind==DESTINATIONS.get(action,"missing"),"actual button opens existing "+str(action)+" panel")
		if action=="fishing":check(text_in(ui.overlay,"Dockside waiting earns no catch") and button_in(ui.overlay,"Begin fishing and return to sea")!=null,"fisher reaches actual K-board Fishing action")
		if action=="jobs":check(text_in(ui.overlay,"rewards are reserved in escrow"),"passenger/freight entry reaches funded work board")
		if action in ["market","yard"]:check(ui.port_tab==("Market" if action=="market" else "Boatyard"),"harbor action selects its actual service tab")
	ui.guidance_career="fisher";GuidanceUI.open(ui)
	check(not c.active_fleet().any(func(b):return str(b.spec.get("civilianRole",""))=="fishing") and text_in(ui.overlay,"Requirements & entry"),"starter without fishing hull still receives career entry guidance")
	ui.guidance_career="saved_future_career";before=snapshot();GuidanceUI.open(ui)
	var fallback: Dictionary=Guidance.report(c,0.0,"saved_future_career")
	var picker: OptionButton=picker_in(ui.overlay)
	check(fallback.career=="captain" and picker!=null and picker.selected==ids.find("captain") and snapshot()==before,"unknown saved choice visibly falls back to Captain without changing the voyage")
	if picker!=null:
		picker.item_selected.emit(ids.find("fisher"))
		check(ui.guidance_career=="fisher" and text_in(ui.overlay,"Reward source"),"real career selector changes the guidance view")
	for id in ["captain","harbormaster"]:
		ui.guidance_career=id;GuidanceUI.open(ui)
		var report: Dictionary=Guidance.report(c,0.0,id)
		check(report.career==id and not report.cards.is_empty() and text_in(ui.overlay,str(report.cards[0].title)),"legacy "+id+" cards remain usable")
