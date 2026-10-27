extends SceneTree
## One small integration fixture. Root owns native execution and the shared lane.
const Guidance=preload("res://scripts/campaign_guidance.gd")
const GuidanceUI=preload("res://scripts/guidance_ui.gd")
const Costs=preload("res://scripts/career_costs.gd")
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
	if not c.state.is_empty():
		_flow()
		_opening()
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

func _opening() -> void:
	var ui=scene.ui
	var saved: Dictionary=c.state.duplicate(true)
	var selected: String=scene.selected_port
	var before: PackedByteArray=var_to_bytes({"state":c.state,"data":c.data})
	var story: Dictionary={};var dispatch: Dictionary={}
	for offer in Costs.contract_offers(c):
		if offer.get("story",false):story=offer
		if offer.get("kind","")=="delivery":dispatch=offer
	check(not story.is_empty() and not dispatch.is_empty(),"actual opening supplies story and existing sealed-dispatch offers")
	if story.is_empty() or dispatch.is_empty():return
	var q: Dictionary=Costs.contract_quote(c,story)
	var budget: Dictionary=q.operatingCosts
	check(q.routeAvailable and float(q.routeDistance)>0 and int(budget.dailyWages)==c.crew_count()*100 and float(budget.days)>2 and int(budget.wageCoins)==ceili(float(budget.days)*int(budget.dailyWages)),"opening quotes actual safe route and full return payroll plus two contingency days")
	check(int(q.grossRewardCoins)==int(story.reward) and int(q.estimatedSurplusCoins)==int(story.reward)-int(budget.allowanceCoins),"gross funded reward stays separate from the full replacement allowance estimate")
	check(not q.secondHull.is_empty() and int(q.secondHull.gapCoins)==maxi(0,int(q.secondHull.entryCoins)-int(c.state.coins)+int(c.state.get("wageArrears",0))-int(story.reward)+int(budget.allowanceCoins)),"second-hull gap includes actual minimum crew advance and protects the voyage allowance")
	var pending: int=c.pending_days;c.pending_days=pending+1
	var prepare: Button=button_in(ui.chrome,"Prepare first voyage")
	check(prepare!=null,"compact HUD exposes the first-voyage action")
	if prepare!=null:prepare.pressed.emit()
	check(ui.modal_kind=="voyage_review" and text_in(ui.overlay,str(story.title)) and text_in(ui.overlay,"Full replacement values") and button_in(ui.overlay,"Paid fitting")!=null,"actual HUD opens quote, reserves and paid fitting without accepting a job")
	var close: Button=button_in(ui.overlay,"Close")
	if close!=null:close.pressed.emit()
	check(close!=null and c.pending_days==pending+1 and scene.economy_task<0 and var_to_bytes({"state":c.state,"data":c.data})==before,"detached quote opening and Close preserve complete typed state/world and pending economy")
	c.pending_days=pending
	GuidanceUI.open_voyage(ui)
	var fitting: Button=button_in(ui.overlay,"Paid fitting")
	if fitting!=null:fitting.pressed.emit()
	check(fitting!=null and ui.modal_kind=="port" and ui.port_tab=="Refit","paid fitting link opens the existing harbor refit roster")
	GuidanceUI.open_voyage(ui)
	var alternate: Button=button_in(ui.overlay,"Review sealed dispatch")
	if alternate!=null:alternate.pressed.emit()
	check(alternate!=null and text_in(ui.overlay,str(dispatch.title)) and Costs.contract_quote(c,dispatch).offer.id==dispatch.id,"secondary review reaches the actual existing dispatch")
	var sponsor: Dictionary=c.port(str(story.port));var cash: int=int(sponsor.governmentPurse)
	sponsor.governmentPurse=0;q=Costs.contract_quote(c,story);GuidanceUI.open_voyage(ui)
	var accept: Button=button_in(ui.overlay,"Accept contract")
	check(not q.funded and not q.ready and not q.canAccept and accept!=null and accept.disabled and text_in(ui.overlay,"FUNDING UNAVAILABLE"),"unfunded sponsor is visible and acceptance is disabled")
	sponsor.governmentPurse=cash
	var stock: float=float(sponsor.stocks.supplies);sponsor.stocks.supplies=0
	q=Costs.contract_quote(c,dispatch)
	check(not q.canAccept and not q.ready and str(q.blockers).contains("sealed cargo"),"dispatch quote refuses missing physical sponsor cargo")
	sponsor.stocks.supplies=stock
	var timber: float=float(c.state.cargo.get("timber",0));c.state.cargo.timber=100000.0
	q=Costs.contract_quote(c,dispatch)
	check(not q.canAccept and not q.ready,"dispatch quote refuses a full hold")
	c.state.cargo.timber=timber
	var navigation: Dictionary=c.nav;c.nav={}
	q=Costs.contract_quote(c,story);GuidanceUI.open_voyage(ui)
	check(not q.routeAvailable and q.estimatedSurplusCoins==null and not q.ready and not q.canAccept and text_in(ui.overlay,"Sailing quote unavailable"),"unsafe route remains unavailable with reserve-only costs")
	c.nav=navigation
	c.state=saved.duplicate(true);GuidanceUI.open_voyage(ui)
	accept=button_in(ui.overlay,"Accept contract")
	if accept!=null and not accept.disabled:accept.pressed.emit()
	check(c.state.activeContract.get("id","")==story.id and int(c.state.activeContract.get("escrow",0))==int(story.reward) and ui.modal_kind=="voyage_review","existing accept callback funds the actual contract then opens a fresh review")
	if c.state.activeContract.is_empty():c.state=saved;return
	var chart: Button=button_in(ui.overlay,"Chart destination")
	if chart!=null:chart.pressed.emit()
	check(chart!=null and c.state.destination==story.targetPort and not c.state.path.is_empty(),"accepted-contract chart button uses the existing safe-course API")
	var target: Dictionary=c.port(str(story.targetPort));c.state.position={"x":target.x,"y":target.y}
	GuidanceUI.open_voyage(ui)
	check(button_in(ui.overlay,"Engage hostile flotilla")!=null and Costs.contract_quote(c,story).atDestination,"at-destination uncleared contract exposes existing engagement without starting a battle")
	c.state.activeContract.cleared=true;GuidanceUI.open_voyage(ui)
	var collect: Button=button_in(ui.overlay,"Deliver & collect reward");var coins: int=int(c.state.coins)
	if collect!=null:collect.pressed.emit()
	check(collect!=null and c.state.activeContract.is_empty() and int(c.state.coins)==coins+int(story.reward) and c.state.missionIndex==int(saved.missionIndex)+1,"cleared contract collects escrow through the existing callback exactly once")
	var again: Dictionary=c.finish_contract()
	check(not again.ok and int(c.state.coins)==coins+int(story.reward),"a completed contract cannot release its reward twice")
	c.state=saved;scene.selected_port=selected;ui.close_modal();ui.build_hud()
	_compact_menus()

func _compact_menus() -> void:
	var ui=scene.ui
	var more: Button=button_in(ui.chrome,"More charts & business")
	check(more!=null and button_in(ui.chrome,"Island charts & surveys     I")==null,"specialist navigation is folded out of the campaign HUD")
	if more!=null:more.pressed.emit()
	for caption in ["Captain's priorities","Prepare expedition","Island charts & surveys     I","Wrecks & recovery","Voyage jobs & contacts     K","Coastal stories & leads","Home harbors & warehouses","Regional goals                    L"]:
		var link: Button=button_in(ui.overlay,caption)
		check(link!=null and link.pressed.get_connections().size()>0,"campaign menu retains callback: "+caption)
	var priorities: Button=button_in(ui.overlay,"Captain's priorities")
	if priorities!=null:priorities.pressed.emit()
	check(priorities!=null and ui.modal_kind=="captain_priorities","folded priorities callback still opens the existing panel")
	ui.open_port("Market")
	for tab in ["Market","Boatyard","Crew & repairs","Refit","Economy","Contracts"]:check(button_in(ui.overlay,tab)!=null,"harbor keeps immediate tab: "+tab)
	check(button_in(ui.overlay,"Trade estimates & observed shortages")==null,"specialist harbor links are folded behind one menu")
	var services: Button=button_in(ui.overlay,"Advanced harbor services")
	if services!=null:services.pressed.emit()
	for caption in ["Trade estimates & observed shortages","Faction standing & safe passage","Voyage jobs, contacts & intelligence","Fishing crews & civilian voyages","Coastal stories & expedition leads","Home harbor, storage & business","Crew training & harbor workforce","Supply coverage & protected stocks","Recovered machinery & workshop development","People, paid shifts & working conditions","Regional goods & coastal trades","Shipping companies & route accounts","Cargo declarations, licences & customs","Boarding crews & coastal defense","Regional crises & civilian passage"]:
		var link: Button=button_in(ui.overlay,caption)
		check(link!=null and link.pressed.get_connections().size()>0,"harbor menu retains callback: "+caption)
	if c.current_port().get("industry","")=="shipyard":check(button_in(ui.overlay,"Recovered drawings & design licenses")!=null,"shipyard retains conditional blueprint callback")
	var trade: Button=button_in(ui.overlay,"Trade estimates & observed shortages")
	if trade!=null:trade.pressed.emit()
	check(trade!=null and ui.modal_kind=="trade_intel","folded trade callback still opens the existing panel")
