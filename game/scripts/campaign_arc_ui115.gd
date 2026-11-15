extends RefCounted

static func _port(c,id: String) -> String:
	return str(c.port(id).get("name","the agreed harbor"))

static func _job(c,w: Dictionary) -> Dictionary:
	for j in c.state.get("regionalCrises",{}).get("jobs",[]):
		if str(j.get("id",""))==str(w.get("jobId","")):return j
	return {}

static func controls(ui,body: Node,entry: Dictionary) -> void:
	if not _live(ui) or str(entry.get("chainId",""))!="common_passage110":return
	if str(entry.get("stage","")) not in ["witness_board115","witness_account115"]:return
	var c=ui.host.core
	var w: Dictionary=c.Arc115.work(c)
	var destination: String=str(w.get("destination",""))
	if not destination.is_empty():ui.label(body,"Witness destination: "+_port(c,destination),20,ui.GOLD,true)
	var j: Dictionary=_job(c,w)
	if not j.is_empty():
		var stage: String=str(j.get("stage",""))
		var count: int=int(j.get("n",0))
		var boat: Dictionary=c.find_boat(str(c.state.passengerTransport.carriers.get(str(j.id),"")))
		ui.paragraph(body,"%d witnesses %s."%[count,"ashore in reception" if stage=="holding" else "aboard "+str(boat.get("name","the assigned boat"))],17)
		ui.paragraph(body,"Transport days: %d / %d. Reception days: %d / 2."%[int(j.get("progress",0)),int(j.get("days",0)),int(j.get("served",0))],16)
		ui.paragraph(body,"Passenger savings: %s coins. Transport allocation remaining: %s coins."%[ui.money(int(j.get("householdPurse",0))+int(j.get("expertPurse",0))),ui.money(j.get("escrow",0))],16)
		if stage=="holding":
			ui.paragraph(body,"Stay at the reception harbor for two distinct, provisioned service days. The assigned workers and specialist must be available.",16)
			ui.button(body,"Wait one day",func():ui.host.wait_one_day())
		elif stage=="returning":
			ui.button(body,"Return witnesses to Rust Anchorage",func():_action.call_deferred(ui,"home",str(j.id)))
		else:ui.button(body,"Register arrival at "+_port(c,str(j.destination)),func():_action.call_deferred(ui,"arrive",str(j.id)))
		ui.button(body,"Recall this passage",func():_action.call_deferred(ui,"recall",str(j.id)))
		ui.button(body,"Passenger manifests and provisions",func():ui.CrisisUI.open(ui))
		ui.button(body,"Review reception route",func():ui.HarborRoute104.open(ui,str(j.origin) if stage=="returning" else str(j.destination)))
	elif not str(w.get("jobId","")).is_empty() or w.get("reported",false):
		_outcome(ui,body,c,w)
	else:
		var q: Dictionary=c.Arc115.quote(c)
		if q.get("ok",false):
			ui.paragraph(body,"2 witnesses: Rust Anchorage to "+_port(c,str(q.destination)),18,ui.GOLD)
			ui.paragraph(body,"Sponsor allocation: %s coins. Included provision bill: %s coins."%[ui.money(q.funded),ui.money(q.foodCost)],16)
			var full_fee: int=maxi(0,int(q.count)*c.Goods.SAILOR_WAGE*int(q.days)-int(q.foodCost))
			ui.paragraph(body,"Full transport payment: %s coins. Your fleet pays its own sailor wages, fuel and repairs."%ui.money(full_fee),16)
			ui.paragraph(body,"The witnesses keep their existing savings. These terms include two paid reception days. Boarding reserves the reception places.",16)
		else:ui.paragraph(body,str(q.get("message","No funded, provisioned places are available for this passage.")),16,ui.GOLD)
		ui.button(body,"Board the two witnesses",func():_accept.call_deferred(ui,q.duplicate(true)),true).disabled=not q.get("ok",false)
		ui.button(body,"Review route to Rust Anchorage",func():ui.HarborRoute104.open(ui,"rust_anchorage"))
		ui.button(body,"Choose public reception at Reedwater Floats",func():_select.call_deferred(ui,"reed_floats"))
		ui.button(body,"Choose protected reception at Anvil Dock",func():_select.call_deferred(ui,"anvil_dock"))
	if not w.get("reported",false):
		var ready: Dictionary=c.Arc115.choice_gate(c,"report_witnesses115")
		if not str(ready.get("message","")).is_empty():ui.paragraph(body,str(ready.message),16,ui.TEAL if ready.get("ok",false) else ui.GOLD)
		ui.button(body,"Refresh",func():_refresh.call_deferred(ui))

static func _outcome(ui,body: Node,c,w: Dictionary) -> void:
	var status: String=str(w.get("status",""))
	var closure: Dictionary=w.get("closure",{})
	if status=="delivered":
		ui.label(body,"Witness reception completed",21,ui.GOLD,true)
		ui.paragraph(body,"Two witnesses completed reception at "+_port(c,str(w.get("destination","")))+".",17)
	elif status=="returned":
		ui.label(body,"Witnesses returned to Rust Anchorage",21,ui.GOLD,true)
		ui.paragraph(body,"The passage closed through the normal return arrangements. No testimony delivery is recorded.",17)
	elif status=="lost":
		ui.label(body,"Witness passage lost",21,ui.GOLD,true)
		ui.paragraph(body,"The carrier's loss was settled. The witnesses did not complete their reception.",17)
	elif status=="unfilled":
		ui.label(body,"Witness passage unfilled",21,ui.GOLD,true)
		ui.paragraph(body,"No witnesses embarked and no transport payment was earned.",17)
	else:
		ui.paragraph(body,"No completed passage has been recorded. Check the passenger manifest before reporting.",17,ui.GOLD)
	if not closure.is_empty():ui.paragraph(body,"Transport payment received: %s coins."%ui.money(closure.get("earned",0)),16)

static func _live(ui) -> bool:
	return ui!=null and is_instance_valid(ui) and ui.host!=null and is_instance_valid(ui.host) and ui.host.mode=="campaign"

static func _accept(ui,shown: Dictionary) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	_finish(ui,ui.host.core.Arc115.accept(ui.host.core,shown))

static func _select(ui,destination: String) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	_finish(ui,ui.host.core.Arc115.select(ui.host.core,destination))

static func _action(ui,kind: String,id: String) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	var c=ui.host.core
	var result: Dictionary=c.CrisisOps.arrive(c,id) if kind=="arrive" else c.CrisisOps.home(c,id) if kind=="home" else c.CrisisOps.recall(c,id)
	_finish(ui,result)

static func _refresh(ui) -> void:
	if not _live(ui):return
	ui.host.sync_economy()
	ui.host.save_game(false)
	ui.StoryUI.open(ui)

static func _finish(ui,result: Dictionary) -> void:
	ui.host.respond(result)
	ui.host.save_game(false)
	ui.StoryUI.open(ui)
