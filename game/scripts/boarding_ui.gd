extends RefCounted
const Ops=preload("res://scripts/boarding_ops.gd")
static func result(ui,r: Dictionary) -> void:
	ui.host.respond(r)
	if r.ok:ui.host.save_game(false)
	open(ui)
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	Ops.ensure(c)
	ui.modal_kind="boarding"
	var body=ui.modal("Boarding parties & coastal defense","ACTUAL CREWS · DAMAGED PRIZES · PAID WATCH",1120,850)
	ui.paragraph(body,"Train boarders at the harbor academy, then hire them into spare boat berths. They are part of the crew and its normal wages. A boarding party leaves its source boat, so keep the minimum working crew aboard. Disable or weaken a target and close to contact. Captured boats retain damage, fittings and stores and need paid harbor repair before combat.",16)
	ui.button(body,"Paid harbor training",func():ui.EconomicUI.open(ui))
	for b in c.state.fleet:
		var uid: String=str(b.uid)
		ui.label(body,"%s · %.0f crew / %.0f berths · %d trained boarders"%[str(b.name),float(b.crew),float(b.crewMax),int(b.get("boarders",0))],19,ui.GOLD,true)
		ui.button(body,"Hire 1 trained boarder · 1,000 coins wage advance",func():result(ui,Ops.hire(c,uid,1)))
		if b.get("captureSecured",false):ui.paragraph(body,"Secured prize: weapons withheld; towing and real wages continue until paid repair.",14,ui.RED)
	ui.paragraph(body,"Captives aboard: %d · Saved prizes awaiting roster room: %d"%[int(c.state.captives),c.state.boardingPrizes.size()],17)
	ui.button(body,"Release all captives safely at this harbor",func():result(ui,Ops.release(c,int(c.state.captives))))
	ui.button(body,"Bring held prizes into available roster places",func():result(ui,Ops.promote(c)))
	var p: Dictionary=c.current_port()
	if not p.is_empty():
		ui.rule(body);ui.label(body,str(p.name)+" coastal watch",23,ui.TEAL,true)
		if p.get("defenses") is Dictionary:
			var d: Dictionary=p.defenses
			ui.paragraph(body,"%s × %d · %d crew · %d ammunition · %d coins unpaid · %s"%[str(d.kind).capitalize(),int(d.units),int(d.crew),int(d.ammo),int(d.arrears),str(d.reason)],16)
		for type in ["battery","garrison"]:
			var kind: String=type
			var q: Dictionary=Ops.Boarding.defense_quote(c,kind,1)
			ui.paragraph(body,("%s: %d coins; %d actual crew; %d construction labor; guns, ammunition, timber, iron and kits from public stores."%[kind.capitalize(),int(q.cost),int(q.crew),int(q.labor)]) if q.ok else kind.capitalize()+": "+str(q.reason),14)
			ui.button(body,"Commission one "+kind,func():result(ui,Ops.build(c,kind,1))).disabled=not q.ok
		ui.paragraph(body,"Friendly authority and real materials are required. Defense crews leave town jobs, earn 100 coins per day from the treasury and consume public food and kits. An unpaid or unprovisioned watch cannot fire. A nearby harbor brings its actual battery into a fleet engagement; each visible projectile spends held ammunition.",15)
	ui.button(body,"Close",ui.close_modal,true)
static func battle(ui) -> void:
	ui.modal_kind="boarding_orders"
	var st: Dictionary=ui.host.battle
	var body=ui.modal("Boarding orders","WEAKEN · APPROACH · CAPTURE",1000,760)
	ui.paragraph(body,"Choose a source boat with trained spare crew and a weakened enemy. The boat approaches automatically; its party leaves only at contact. Two-second exchanges use real people, and capture takes at least four seconds. Secured prizes leave combat and add no deployment points.",16)
	ui.button(body,"Cautious automatic boarding: "+("ON" if st.get("autoBoard",true) else "OFF"),func():st.autoBoard=not st.get("autoBoard",true);battle(ui))
	var sources=OptionButton.new();var source_ids: Array=[]
	var targets=OptionButton.new();var target_ids: Array=[]
	for b in st.ships:
		if b.sunk:continue
		if b.team=="player" and not b.get("captureSecured",false):source_ids.append(str(b.id));sources.add_item("%s · %d boarders"%[str(b.name),int(b.get("boarders",0))])
		elif b.team=="enemy":target_ids.append(str(b.id));targets.add_item("%s · %.0f%% hull"%[str(b.name),float(b.hp)/maxf(1,float(b.maxHp))*100])
	var line=ui.row(body);line.add_child(sources);line.add_child(targets)
	var count=SpinBox.new();count.min_value=1;count.max_value=128;count.value=3;line.add_child(count)
	if not source_ids.is_empty() and not target_ids.is_empty():
		ui.button(body,"Approach and board selected target",func():ui.host.respond(Ops.Combat.order(st,str(source_ids[sources.selected]),str(target_ids[targets.selected]),int(count.value)));ui.close_modal(),true)
	for job in st.get("boarding",{}).get("jobs",[]):
		ui.paragraph(body,"%s · %s · %d aboard target / %d returned / %d lost or killed"%[str(job.id),str(job.status),int(job.alive),int(job.returned),int(job.lost)+int(job.killed)],14)
		if job.status=="active":
			var id: String=str(job.id)
			ui.button(body,"Recall "+id+" if still in contact",func():var r: Dictionary=Ops.Boarding.abort(st,id);ui.host.respond({"ok":r.ok,"message":str(r.get("reason","Party recovery resolved using actual contact and berths."))});battle(ui))
	ui.button(body,"Close",ui.close_modal)
