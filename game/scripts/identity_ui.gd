extends RefCounted
## Read-only selected-boat desk; paid actions refresh and revalidate explicitly.
const Identity=preload("res://scripts/fleet_identity.gd")
const Service=preload("res://scripts/equipment_service.gd")
const Refits=preload("res://scripts/refit.gd")

## Reuse the existing detached permission facade; never build a campaign/nav.
class ConversionView extends Service.DetachedCampaignView:
	func find_boat(uid: String) -> Dictionary:
		for boat in state.get("fleet",[]):
			if str(boat.get("uid",""))==uid:return boat
		return {}
	func fitted_spec(boat: Dictionary) -> Dictionary:
		for base in data.get("HULLS",[]):
			if str(base.id)==str(boat.get("type","")):
				return Refits.effective_spec(base,boat.get("loadout",Refits.defaults(base)))
		return boat.get("spec",{}).duplicate(true)

static func service_summary(boat: Dictionary) -> String:
	var s: Dictionary=boat.get("service",{})
	return "%d battles · %d wins · %d rescues · %d trades · %d surveys"%[int(s.get("battles",0)),int(s.get("wins",0)),int(s.get("rescues",0)),int(s.get("trades",0)),int(s.get("surveys",0))]

static func act(ui,uid: String,action: String,value: String="",role: String="auto") -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var result: Dictionary
	match action:
		"command":result=Identity.set_command_preference(c,uid,value,role)
		"hire":result=Identity.hire_specialist(c,uid,value)
		"dismiss":result=c.FleetSupport.dismiss(c,value)
		"reserve":result=c.FleetSupport.reserve(c,uid)
		"conversion":result=Identity.install_conversion(c,uid,value)
		"repair":result=c.repair_boat(uid)
		"recruit":result=c.recruit_crew(uid,1)
		_:return
	ui.host.respond(result)
	if result.get("ok",false):
		if action in ["hire","conversion"]:
			c.fit_boat(c.find_boat(uid));c.apply_morale();c.Manifest.allocate(c.state)
		ui.host.save_game(false)
	open(ui,uid)

static func _intent(ui,body: Node,uid: String,preference: Dictionary) -> void:
	var line=ui.row(body)
	ui.label(line,"Next battle",15,ui.GOLD)
	var doctrine=OptionButton.new()
	doctrine.name="BoatDoctrine060"
	for item in ["cautious","steady","aggressive"]:
		doctrine.add_item(str(item).capitalize())
		doctrine.set_item_metadata(doctrine.item_count-1,item)
		if item==preference.doctrine:doctrine.select(doctrine.item_count-1)
	line.add_child(doctrine)
	var role=OptionButton.new()
	role.name="BoatRole060"
	for item in ["auto","skirmisher","striker","heavy","screen","support"]:
		role.add_item(str(item).capitalize())
		role.set_item_metadata(role.item_count-1,item)
		if item==preference.role:role.select(role.item_count-1)
	line.add_child(role)
	ui.button(line,"Save command intent",func():act(ui,uid,"command",str(doctrine.get_selected_metadata()),str(role.get_selected_metadata())),true,false)
	ui.paragraph(body,"Saved: %s / %s. Doctrine sets risk and withdrawal intent; role guides autopilot. Fitted weapons, crew, ammunition and safety still constrain the boat. Later battle orders take precedence."%[str(preference.doctrine).capitalize(),str(preference.role).capitalize()],14)

static func open(ui,uid: String) -> void:
	var c=ui.host.core
	var v: Dictionary=c.FleetSupport.selected_view(c,uid)
	if not v.get("ok",false):ui.toast(str(v.get("message","That boat is no longer in the flotilla.")),true);return
	var boat: Dictionary=c.find_boat(uid).duplicate(true)
	var crew: Dictionary=v.crew
	var pay: Dictionary=v.payroll
	ui.modal_kind="fleet_identity"
	var body=ui.modal(str(v.name)+" · people & command","PAID CREW · ACTUAL FITTING · EARNED SERVICE",1050,820)
	ui.label(body,"%.0f able · %.0f wounded · %.0f ashore · %.0f minimum / %.0f working / %.0f berths"%[crew.able,crew.wounded,crew.ashore,crew.minimum,crew.optimal,crew.maximum],17,ui.GOLD)
	ui.paragraph(body,"%.0f sailors aboard · Fleet morale %.0f / 100 · Speed and firing factor %.0f%%"%[crew.aboard,v.morale.value,float(v.morale.factor)*100.0],15,ui.TEAL)
	ui.paragraph(body,"This boat: %s coins/day base (100 per sailor) + %s professional premiums = %s/day. Wounded sailors still receive base pay."%[ui.money(int(pay.basePerDay)),ui.money(int(pay.premiumPerDay)),ui.money(int(pay.totalPerDay))],15)
	ui.paragraph(body,"Separate accounts: fleet base arrears %s · this boat's premium arrears %s · fleet crew purse %s coins."%[ui.money(int(pay.fleetBaseArrears)),ui.money(int(pay.boatPremiumArrears)),ui.money(int(pay.fleetCrewPurse))],14,ui.RED if int(pay.fleetBaseArrears)+int(pay.boatPremiumArrears)>0 else ui.MUTED)
	_intent(ui,body,uid,v.commandPreference)
	ui.rule(body)
	ui.label(body,"Named staff",23,ui.GOLD,true)
	if v.staff.is_empty():ui.paragraph(body,"No specialist assigned. Ordinary sailors remain the numerical working crew.",15)
	for row in v.staff:
		var staff: Dictionary=row
		var id: String=str(staff.id)
		ui.label(body,"%s · %s · %s"%[staff.name,staff.roleName,"working" if staff.active else "benefit suspended"],18,ui.TEAL if staff.active else ui.RED)
		ui.paragraph(body,str(staff.effect),14)
		ui.paragraph(body,"100 base + %d premium / day · personal premium purse %s · premium arrears %s coins"%[int(staff.premiumPerDay),ui.money(int(staff.coins)),ui.money(int(staff.arrears))],14)
		ui.button(body,"Discharge %s with earned savings"%staff.name,func():act(ui,uid,"dismiss",id),false,false)
	ui.rule(body)
	ui.label(body,"Actual fitting",23,ui.GOLD,true)
	var fit: Dictionary=boat.get("loadout",{})
	ui.paragraph(body,"%s · %s · %s"%[str(Identity.conversions().get(boat.get("conversion",""),{}).get("name","Original interior")),ui.RefitUI.module_name(str(fit.get("engine","stock_engine"))),ui.RefitUI.module_name(str(fit.get("armor","stock_armor")))],15)
	var weapons: Array=fit.get("weapons",[])
	var sockets: Array=Refits.hardpoints(boat.get("baseSpec",{}))
	for index in range(weapons.size()):
		var socket: Dictionary=sockets[index] if index<sockets.size() else {}
		ui.paragraph(body,"%s: %s"%[str(socket.get("label","Mount %d"%(index+1))),ui.RefitUI.module_name(str(weapons[index]))],14)
	var spec: Dictionary=v.effectiveSpec
	ui.paragraph(body,"Current crew/morale fit: speed %.1f · turn %.2f · armor %.0f · %d physical weapon sockets. Damage and assigned hands further limit performance."%[float(spec.get("speed",0)),float(spec.get("turn",0)),float(spec.get("armor",0)),sockets.size()],14,ui.TEAL)
	var work=ui.row(body)
	ui.button(work,"Open paid fitting bay",func():ui.open_refit(uid),false,false)
	ui.button(work,"Interior conversion choices",func():conversions(ui,uid),false,false)
	ui.button(work,"Support reserve" if not boat.get("supportOnly",false) else "Include in battle deployment",func():act(ui,uid,"reserve"),false,false)
	ui.rule(body)
	ui.label(body,"Local hiring & care",23,ui.GOLD,true)
	ui.paragraph(body,"Each named specialist adds one real sailor and occupies a berth. The hiring advance enters the shared crew purse; the daily premium goes to that person's own purse. Quotes refresh when you hire.",14)
	for row in v.hiring:
		var hire: Dictionary=row
		var role: String=str(hire.role)
		ui.paragraph(body,"%s · %s coins advance · 100 base + %d premium/day · %s"%[hire.roleName,ui.money(int(hire.advance)),int(hire.premiumPerDay),str(hire.message)],14)
		ui.button(body,"Hire "+str(hire.roleName),func():act(ui,uid,"hire",role),false,false).disabled=not hire.eligible
	if not c.current_port().is_empty():
		var q: Dictionary=c.service_quote(c.find_boat(uid),c.current_port())
		ui.paragraph(body,str(q.get("message","Harbor service treats wounds and restores hull and installed equipment using paid labor and materials.")),14)
		var care=ui.row(body)
		ui.button(care,"Paid drydock · %s coins"%ui.money(int(q.get("cost",0))),func():act(ui,uid,"repair"),false,false).disabled=not q.get("ok",false)
		ui.button(care,"Recruit one sailor",func():act(ui,uid,"recruit"),false,false)
		ui.button(care,"Training eligibility & accounts",func():ui.EconomicUI.open(ui),false,false)
	else:ui.paragraph(body,"Visit a harbor for hiring, training, treatment and repairs.",14)
	ui.rule(body)
	ui.label(body,"Service & recovery history",23,ui.GOLD,true)
	ui.paragraph(body,service_summary(v),16,ui.TEAL)
	if not str(boat.get("salvageWreckId","")).is_empty():ui.paragraph(body,"Recovered from wreck %s. Preserved history belongs to this hull; new crew, repairs and stores are paid separately."%str(boat.salvageWreckId),14)
	if v.serviceHistory.is_empty():ui.paragraph(body,"No recorded service yet.",14)
	for entry in v.serviceHistory:
		ui.paragraph(body,"Day %.1f · %s · %s"%[float(entry.day),str(entry.event).capitalize(),str(entry.get("detail",""))],14)
	ui.button(body,"Close review",ui.close_modal,true,false)

static func conversions(ui,uid: String) -> void:
	var c=ui.host.core
	var snapshot: Dictionary=c.state.duplicate(true)
	var p: Dictionary={}
	var port_id: String=str(c.current_port().get("id",""))
	for candidate in snapshot.get("ports",[]):
		if str(candidate.id)==port_id:p=candidate;break
	var view=ConversionView.new(snapshot,c.data,p)
	var boat: Dictionary=view.find_boat(uid)
	if boat.is_empty():return
	ui.modal_kind="fleet_conversions"
	var body=ui.modal(str(boat.name)+" · interior conversions","REAL MATERIALS · PAID HARBOR LABOR",1020,800)
	ui.paragraph(body,"Interior conversions retain the boat's physical weapon sockets and fitted weapons. Review is free; installation refreshes the account and rechecks money, materials, workers and cargo space.",15)
	for id in Identity.conversions():
		var key: String=id
		var info: Dictionary=Identity.conversions()[key]
		var q: Dictionary=Identity.quote_conversion(view,uid,key)
		ui.rule(body)
		ui.label(body,str(info.name),22,ui.GOLD,true)
		ui.paragraph(body,str(info.trade),14)
		ui.paragraph(body,str(q.get("message","")),14)
		ui.button(body,"Install "+str(info.name),func():act(ui,uid,"conversion",key),false,false).disabled=not q.get("ok",false) or int(snapshot.coins)<int(q.get("cost",0))
	ui.button(body,"Back to boat",func():open(ui,uid),true,false)
