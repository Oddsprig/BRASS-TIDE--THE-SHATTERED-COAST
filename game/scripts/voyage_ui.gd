extends RefCounted
const Choices=preload("res://scripts/civilian_choices059.gd")
const VoyagePanel=preload("res://scripts/voyage_panel070.gd")
## Several funded commitments, original contacts and honest dated reports.
static func open(ui,tab: String="Work board") -> void:
	if tab=="Fishing":review_fishing(ui);return
	ui.host.sync_economy()
	var c=ui.host.core
	c.VoyageJobs.ensure(c)
	c.VoyageJobs._expire_overdue(c,c.state)
	ui.modal_kind="voyage_jobs"
	var body=ui.modal("Voyage jobs & contacts","PLAN A ROUTE WITH SEVERAL REASONS TO SAIL",1040,820)
	ui.button(body,"Coastal stories & leads",func():ui.StoryUI.open(ui))
	ui.button(body,"Trade chart & observed prices",func():ui.TradeUI.open(ui))
	ui.button(body,"Coastal traffic",func():ui.NavalUI.open(ui))
	ui.button(body,"Factions & safe passage",func():ui.FactionUI.open(ui))
	var tabs=ui.row(body)
	for value in ["Work board","Fishing","Contacts","Market notes"]:
		var selected: String=value
		ui.button(tabs,selected,func():open(ui,selected),selected==tab,false)
	if tab=="Contacts":contacts(ui,body);return
	if tab=="Market notes":intel(ui,body);return
	ui.paragraph(body,"Carry up to six compatible side jobs alongside your story contract. Freight uses real hold space; rewards are reserved in escrow. Relief cargo is purchased by its sponsoring treasury, then entrusted to your fleet.",16)
	_paint_board_context(ui,body,c)
	ui.label(body,"%d / 6 commitments · Hold %.1f / %.1f"%[c.state.voyageJobs.size(),c.cargo_weight(),c.capacity()],22,ui.GOLD,true)
	for raw in c.state.voyageJobs:
		var job: Dictionary=raw.duplicate(true)
		ui.rule(body)
		ui.label(body,job.title,24,ui.GOLD,true)
		if not str(job.get("sponsorContactId","")).is_empty():ui.paragraph(body,sponsor_reason(c,job),15,ui.TEAL)
		ui.paragraph(body,"%s · %.1f days remaining · %s coins reserved"%[str(job.state).capitalize(),job.deadlineDay-c.state.day,ui.money(job.escrow)],15,ui.TEAL)
		if not str(job.get("carrierUid","")).is_empty():
			var boat: Dictionary=c.find_boat(str(job.carrierUid))
			ui.paragraph(body,"Carrier: %s"%str(boat.get("name","Carrier unavailable")),15,ui.GOLD)
		if not job.get("freight",{}).is_empty():ui.paragraph(body,"Sealed cargo: %.0f %s"%[float(job.freight.qty),str(c.Goods.ITEMS.get(job.freight.good,{}).get("name",job.freight.good))],15)
		if job.kind=="passenger_charter":ui.paragraph(body,"%d passengers aboard · %.2f ration bales reserved"%[int(job.get("passengers",{}).get("n",0)),float(job.get("charterFood",{}).get("food",0))],15)
		if job.get("failed",false):ui.paragraph(body,"Freight lost: this job needs to be closed at a harbor.",15,ui.RED)
		if job.kind=="survey":ui.paragraph(body,survey_terms(c,job),15,ui.TEAL)
		if str(job.kind) in Choices.CIVILIAN_KINDS:ui.button(body,"Review remaining costs, load and carrier",func():review_job(ui,job),false,false)
		else:ui.button(body,"Review remaining costs and readiness",func():review_estimate(ui,job),false,false)
		ui.button(body,"Complete & release escrow",func():settle(ui,job.id,false),true)
		ui.button(body,"Abandon / unload remaining freight",func():settle(ui,job.id,true))
	ui.rule(body)
	ui.label(body,"Available at this harbor",25,ui.GOLD,true)
	var offers: Array=VoyagePanel.listed_offers(c)
	if offers.is_empty():ui.paragraph(body,_empty_board(c),16)
	for item in offers:
		var offer: Dictionary=item.duplicate(true)
		ui.label(body,offer.title,23,ui.TEXT,true)
		ui.paragraph(body,offer.description,15)
		if offer.kind=="survey":ui.paragraph(body,survey_terms(c,offer),15,ui.TEAL)
		if not str(offer.get("sponsorContactId","")).is_empty():ui.paragraph(body,sponsor_reason(c,offer),15,ui.TEAL)
		if not str(offer.get("loadTier","")).is_empty():ui.paragraph(body,"%s load · %s"%[str(offer.loadTier).capitalize(),str(offer.get("demandPurpose",offer.description))],15,ui.TEAL)
		ui.paragraph(body,"%s → %s"%[VoyagePanel.origin_name(c,offer),VoyagePanel.destination_name(c,offer)],15,ui.TEAL)
		ui.paragraph(body,"Gross fee %s · deadline day %.0f"%[ui.money(int(offer.get("reward",0))),float(offer.get("deadlineDay",0))],16,ui.GOLD)
		if str(offer.kind) in Choices.CIVILIAN_KINDS:
			ui.button(body,"Review voyage costs, load and carrier",func():review_job(ui,offer),true,false)
		else:
			ui.button(body,"Review voyage costs and readiness",func():review_estimate(ui,offer),false,false)
			ui.button(body,"Accept funded job",func():ui.host.accept_voyage_job(offer.id);open(ui),true).disabled=c.state.voyageJobs.size()>=6
		ui.rule(body)
	ui.button(body,"Story contracts & captain's log",ui.open_contracts)

static func _empty_board(c) -> String:
	var header: Dictionary=VoyagePanel.board_header(c)
	if not bool(header.get("berthKnown",false)):return "The work berth is not on this campaign yet. Published offers stay listed without a home-waters cost. Completed jobs do not reroll."
	if not bool(header.docked):return "Dock at a known harbor for funded work. Offers need an actual sponsor purse and physical cargo; completed jobs do not reroll."
	return "No funded offer is published at %s today. Offers need an actual sponsor purse and physical cargo; completed jobs do not reroll."%str(header.name)

static func _paint_board_context(ui,body,c) -> void:
	var header: Dictionary=VoyagePanel.board_header(c)
	var chart: String=str(header.region) if not str(header.region).is_empty() else "this chart"
	if not bool(header.get("berthKnown",false)):
		ui.paragraph(body,"No work berth is published on this campaign yet. This chart is %s. Gross fees below are the published offers. Review one job for its voyage estimate. Nothing on this board buys cargo or installs a fitting."%chart,16)
	elif not bool(header.docked):
		ui.paragraph(body,"No physical berth. Funded offers appear at a known harbor you are docked at. This chart is %s. Nothing on this board buys cargo or installs a fitting."%chart,16)
	else:
		var kind: String="Home harbor" if str(header.kind)=="home" else "Work berth"
		ui.paragraph(body,"%s: %s · %s. Gross fees below are the published offers. Review one job for voyage costs, the return reserve and readiness. This list does not buy cargo or install a fitting."%[kind,str(header.name),chart],16)
	var details=ui.column(body)
	details.visible=false
	for line in VoyagePanel.fleet_notes(c):ui.paragraph(details,str(line),14,ui.TEAL)
	var toggle=ui.button(body,"Current fleet roles and fitting quotes",func():details.visible=not details.visible,false,false)
	body.move_child(toggle,details.get_index())

static func review_estimate(ui,offer: Dictionary) -> void:
	var c=ui.host.core
	var view: Dictionary=VoyagePanel.selected_quote(c,offer)
	ui.modal_kind="voyage_review"
	var body=ui.modal("Voyage estimate","ONE JOB · CURRENT FLEET · NOT A PAYMENT",1020,800)
	_paint_selected(ui,body,c,offer,view)
	_prepare_button(ui,body,view)
	if str(offer.get("kind","")) not in Choices.CIVILIAN_KINDS and int(offer.get("escrow",0))<=0:
		ui.button(body,"Accept funded job",func():ui.host.accept_voyage_job(str(offer.get("id","")));open(ui),true).disabled=c.state.get("voyageJobs",[]).size()>=6
	ui.button(body,"Return to the work board",func():open(ui),false,false)

static func _paint_selected(ui,body,c,offer: Dictionary,view: Dictionary) -> void:
	var gross: int=int(view.get("grossFee",offer.get("reward",0)))
	var region: String=str(view.get("targetRegionName","")).strip_edges()
	var place: String="%s → %s"%[VoyagePanel.origin_name(c,offer),VoyagePanel.destination_name(c,offer)]
	if not region.is_empty():place+=" · %s"%region
	ui.paragraph(body,place,16,ui.TEAL)
	ui.paragraph(body,"Gross fee %s."%ui.money(gross),20,ui.GOLD)
	if bool(view.get("remainingOnly",false)) or int(offer.get("escrow",0))>0:
		ui.paragraph(body,"Escrow holds %s. That sum is already set aside. This reading is not another payment."%ui.money(int(offer.get("escrow",0))),15,ui.TEAL)
	else:
		ui.paragraph(body,"Client funding %s is offered. Accepting moves it from the client's purse into escrow. It is not spendable before then."%ui.money(gross),15)
	if view.has("operatingCost") and view.has("returnReserves") and view.has("likelySurplus"):
		ui.paragraph(body,"Estimated voyage costs %s · return reserve %s · estimated surplus %s."%[ui.money(view.operatingCost),ui.money(view.returnReserves),ui.money(view.likelySurplus)],16,ui.GOLD)
		ui.paragraph(body,"Costs reflect your current fleet; delays and damage can increase them. Estimated surplus is the gross fee minus estimated voyage costs. The return reserve overlaps those costs and adds two contingency days. It is not subtracted again.",14,ui.TEAL)
	else:
		ui.paragraph(body,str(view.get("affordNote",view.get("message","Voyage costs are not estimated for this job."))),15,ui.GOLD)
	if view.has("holdNeed"):
		var hold: float=float(view.holdNeed)
		var hold_kind: String=str(view.get("kind",offer.get("kind","")))
		if hold<=0.000001 and hold_kind in ["survey","bounty"]:ui.paragraph(body,"No sealed cargo is reserved.",15)
		else:ui.paragraph(body,"Hold space needed %.1f."%hold,15)
	if view.has("passengerNeed") and (int(view.passengerNeed)>0 or str(offer.get("kind",""))=="passenger_charter"):
		ui.paragraph(body,"Passenger berths %d."%int(view.passengerNeed),15)
	if view.has("spareBerths"):ui.paragraph(body,"Spare berths %d on the roomiest hull, after its crew and anyone already assigned. That is accommodation, not extra sailors."%int(view.spareBerths),15)
	if bool(view.get("routeOk",false)):
		if str(offer.get("kind",""))=="survey":
			var hands: int=int(view.get("crewNeeded",0))
			if hands>0:ui.paragraph(body,"Spare hands required: %d. Survey parties need spare sailors beyond those required to operate your boats. Every sailor aboard earns wages, including spare hands."%hands,15,ui.GOLD)
			else:ui.paragraph(body,"No extra shore party is required for the remaining work. Every sailor still aboard earns wages.",15)
		var ready: bool=bool(view.get("readyForAllowance",false))
		ui.paragraph(body,"Readiness: the return allowance is covered for this estimate." if ready else "Readiness: the return allowance is not covered for this estimate.",15,ui.TEAL if ready else ui.GOLD)
	elif str(offer.get("kind",""))=="survey":
		ui.paragraph(body,"Spare hands and readiness stay off this survey until the selected quote has an actual route.",15,ui.GOLD)
	ui.paragraph(body,"Load fuel, ammunition and repair kits from the hold into your boats before sailing. Loose stores are not loaded reserves.",14)
	var blockers: Array=view.get("blockers",[]) if view.get("blockers") is Array else []
	for blocker in blockers:ui.paragraph(body,str(blocker),14,ui.RED)
	if view.has("operatingCost") and not str(view.get("message","")).is_empty():ui.paragraph(body,str(view.message),14,ui.TEAL)
	var extra: Array=VoyagePanel.support_lines(view)
	extra.append_array(VoyagePanel.leg_lines(view))
	if not extra.is_empty():
		var details=ui.column(body)
		details.visible=false
		for line in extra:ui.paragraph(details,str(line),14,ui.TEAL)
		var toggle=ui.button(body,"Fleet roles on this quote, and the route steps",func():details.visible=not details.visible,false,false)
		body.move_child(toggle,details.get_index())

static func _prepare_button(ui,body,view: Dictionary) -> void:
	var ready: bool=VoyagePanel.prepare_ready(ui.host.core,view)
	var held: Dictionary=view.duplicate(true)
	ui.button(body,VoyagePanel.prepare_label(view) if ready else "No route step on this chart",func():VoyagePanel.prepare_from_quote(ui,held),true).disabled=not ready

static func survey_terms(c,job: Dictionary) -> String:
	var harbor: Dictionary=c.port(str(job.get("port","")))
	var terms: String="Paid work: fully surveyed (level 3), then report at %s. The voyage estimate counts spare sailors beyond the crew that operates your boats. Wages and provisions continue ashore."%str(harbor.get("name","the sponsoring harbor"))
	if str(job.get("siteId",""))=="middle_chart_rock":terms+=" Wren's rock clue needs only charted level 2; that clue alone does not release escrow. The extra survey normally takes 2.5 days and 2 kits, adjusted by your actual survey equipment."
	return terms

static func settle(ui,id: String,abandon: bool) -> void:
	ui.host.settle_voyage_job(id,abandon)
	open(ui)

static func contacts(ui,body) -> void:
	var c=ui.host.core
	var offers: Array=VoyagePanel.listed_offers(c)
	ui.paragraph(body,"Personal trust belongs to the person you helped. Visits, fulfilled promises and failures are remembered. Faction standing is a separate relationship.",16)
	for person in c.Contacts.list_contacts(c.state):
		var contact: Dictionary=person
		if contact.has("ownerId") and not contact.met:continue
		ui.rule(body)
		ui.label(body,contact.name,25,ui.GOLD,true)
		ui.paragraph(body,"%s · %s"%[contact.title,c.port(contact.port).name],16,ui.TEXT)
		ui.paragraph(body,"Trust %d · %s"%[contact.trust,"last visited day%.1f"%contact.lastVisitDay if contact.met else "not yet met"],15,ui.TEAL)
		ui.button(body,"Chart this harbor",func():ui.host.sail_to(contact.port);ui.close_modal())
		for entry in contact.log.slice(-3):
			var place: Dictionary=c.port(str(entry.get("port","")))
			ui.paragraph(body,"Day%.1f%s · %s · trust %+d"%[entry.day," at "+str(place.name) if not place.is_empty() else "",entry.get("detail",entry.event),entry.amount],13)
		for offer in offers:
			if str(offer.get("sponsorContactId",""))!=str(contact.id):continue
			ui.paragraph(body,sponsor_reason(c,offer),15,ui.TEAL)
			ui.button(body,"Review "+str(offer.title)+" on Work board",func():open(ui,"Work board"))
		if contact.get("workOpportunityUsed",false):ui.paragraph(body,"Earned introduction already taken. Its ordinary job terms still govern payment or failure.",14)

static func sponsor_reason(c,job: Dictionary) -> String:
	var contact: Dictionary=c.Contacts._find(c.state,str(job.get("sponsorContactId","")))
	var place: Dictionary=c.port(str(job.get("sponsorEventPort","")))
	var where: String=" at "+str(place.name) if not place.is_empty() else " (location not recorded)"
	var promise: String="your paid work"
	for entry in contact.get("log",[]):
		if str(entry.get("event",""))==str(job.get("sponsorEventId","")):promise=str(entry.get("detail",promise));break
	return "%s recommends this work because you completed %s on day%.1f%s. Payment is reserved from the harbor treasury when you accept."%[str(contact.get("name","Harbor contact")),promise,float(job.get("sponsorEventDay",0)),where]

static func carrier_picker(ui,body,kind: String,selected_uid: String="") -> OptionButton:
	var c=ui.host.core
	var picker=OptionButton.new()
	picker.custom_minimum_size=Vector2(0,42)
	var names: Dictionary={"transport":"transport","tanker":"fuel tanker","yacht":"passenger yacht","fishing":"fishing boat"}
	for b in c.active_fleet():
		if kind=="fuel_delivery" and str(b.spec.get("civilianRole","")) not in ["transport","tanker"]:continue
		if kind=="passenger_charter" and str(b.spec.get("civilianRole","")) not in ["transport","yacht"]:continue
		if kind=="fishing" and str(b.spec.get("civilianRole",""))!="fishing":continue
		picker.add_item("%s · %s"%[b.name,str(names.get(str(b.spec.get("civilianRole","")),"working boat"))])
		picker.set_item_metadata(picker.item_count-1,str(b.uid))
		if str(b.uid)==selected_uid:picker.select(picker.item_count-1)
	body.add_child(picker)
	if picker.item_count==0:ui.paragraph(body,"No eligible active, crewed carrier. Prepare a suitable boat through Fleet and the harbor yard.",15,ui.GOLD)
	return picker

static func review_job(ui,offer: Dictionary,_carrier_uid: String="") -> void:
	var c=ui.host.core
	var job: Dictionary=offer
	var active: bool=false
	for carried in c.state.get("voyageJobs",[]):
		if str(carried.get("id",""))==str(offer.get("id","")):job=carried;active=true;break
	var view: Dictionary=VoyagePanel.selected_quote(c,job)
	ui.modal_kind="voyage_review" # Existing header-X contract: no economy sync.
	var body=ui.modal("Review civilian work","ONE LOAD · ACTUAL FLEET · SELECTED QUOTE",1020,800)
	ui.paragraph(body,str(job.get("title",offer.get("title",""))),24,ui.GOLD)
	ui.paragraph(body,str(job.get("demandPurpose",job.get("description",""))),16)
	var picked: Array=[str(job.get("carrierUid",""))]
	var needs_carrier: bool=false
	if not active and str(job.get("kind","")) in ["fuel_delivery","passenger_charter"]:
		var picker: OptionButton=carrier_picker(ui,body,str(job.kind),str(picked[0]))
		if picker.item_count>0 and str(picked[0]).is_empty():picked[0]=str(picker.get_item_metadata(picker.selected))
		picker.item_selected.connect(func(_index: int):picked[0]=str(picker.get_selected_metadata()))
		needs_carrier=picker.item_count==0
		ui.paragraph(body,"Acceptance checks the selected boat's real hold and berths. Choosing a boat does not buy cargo or reserve the fee.",14)
	var load: Dictionary=job.get("freight",{}) if job.get("freight") is Dictionary else {}
	if not load.is_empty():ui.paragraph(body,"Sealed cargo: %.0f %s"%[float(load.get("qty",0)),str(c.Goods.ITEMS.get(load.get("good",""),{}).get("name",load.get("good","")))],16,ui.GOLD)
	if str(job.get("kind",""))=="passenger_charter":ui.paragraph(body,"%d passengers · %.2f ration bales on the offer"%[int(job.get("passengers",{}).get("n",0)),float(job.get("charterFood",{}).get("food",0))],16,ui.GOLD)
	_paint_selected(ui,body,c,job,view)
	var memory: Dictionary=job.get("clientMemory",{}) if job.get("clientMemory") is Dictionary else {}
	if memory.is_empty():
		var contact_id: String=str(job.get("sponsorContactId",""))
		if contact_id.is_empty() and str(job.get("kind",""))=="fuel_delivery":contact_id="captain:"+str(job.get("ownerId",""))
		if not contact_id.is_empty():memory=c.Contacts.client_memory(c.state,contact_id)
	_client(ui,body,{"clientMemory":memory,"originName":VoyagePanel.origin_name(c,job),"job":job})
	if str(job.get("kind",""))=="fuel_delivery" and c.VoyageJobs!=null and c.VoyageJobs.has_method("recipient_status"):
		var recipient: Dictionary=c.VoyageJobs.recipient_status(c,job)
		var place: String=str(c.port(str(recipient.get("currentPort",""))).get("name","At sea / not present"))
		ui.paragraph(body,"Recipient report day %.2f · age %.2f days · currently %s · need %.1f fuel. %s"%[float(recipient.get("observedDay",0)),float(recipient.get("ageDays",0)),place,float(recipient.get("demand",0)),str(recipient.get("message",""))],15,ui.GOLD)
		ui.paragraph(body,"The fleet can leave or use other fuel before arrival. Tanks are not reserved; an interrupted delivery earns no fee and payroll continues.",14)
	_prepare_button(ui,body,view)
	if not active:
		ui.button(body,"Accept reviewed funded job",func():_accept_reviewed(ui,job,str(picked[0])),true).disabled=needs_carrier or c.state.get("voyageJobs",[]).size()>=6
	ui.button(body,"Leave review · return to chart" if active else "Decline · return to chart",ui.close_modal,false,false)

static func _accept_reviewed(ui,job: Dictionary,uid: String) -> void:
	var carrier: String=uid if str(job.kind) in ["fuel_delivery","passenger_charter"] else ""
	var result: Dictionary=ui.host.accept_voyage_job(str(job.id),carrier)
	if result.ok:open(ui)

static func _budget(ui,body,r: Dictionary,net: int,route_ok: bool,remaining: bool=false) -> void:
	var basis: String="Remaining work + return" if remaining else "Work + return"
	if float(r.outwardDays)>0:basis="Remaining outward + work + return" if remaining else "Outward + work + return"
	ui.paragraph(body,"%s %.2f days · estimated operating cost %s coins"%[basis,float(r.operatingDays),ui.money(r.operatingCost)],18)
	if r.priced and route_ok:ui.paragraph(body,"Estimated %soperating surplus %s coins"%["remaining " if remaining else "",ui.money(net)],22,ui.TEAL if net>0 else ui.GOLD)
	else:ui.paragraph(body,"Margin unavailable until route and replacement prices are known.",18,ui.GOLD)
	ui.paragraph(body,"Keep %s coins for %.0f contingency days; this reserve is separate from spent operating costs. Departure payroll, existing dues and missing stores need %s coins (%s short)."%[ui.money(r.reserveFunding),r.reserveDays,ui.money(r.fundingRequired),ui.money(r.fundingShortfall)],15)
	var details=ui.column(body);details.visible=false
	ui.paragraph(details,"Payroll %s coins for %d rounded-up calendar days at %s/day, including stored crews and specialist premiums. Sailor wage anchor: 100 coins/day."%[ui.money(r.wages),int(r.payrollDays),ui.money(r.dailyWages)],14)
	ui.paragraph(details,"Replace %.2f food (%s coins) and %.2f working fuel (%s). Price basis: %s, day %.2f. Return %.2f days; work horizon %.2f days. Repairs, combat losses and delays are unpriced."%[r.food,ui.money(r.foodCost),r.fuel,ui.money(r.fuelCost),r.pricePort,r.priceDay,r.returnDays,r.workDays],14)
	ui.paragraph(details,"Existing dues %s · pending prior payroll %s · missing-store purchase estimate %s coins. Loaded food short %.2f; individual tank fuel short %.2f. %.2f loose fuel is cargo; load each real tank through Cargo."%[ui.money(r.arrears),ui.money(r.pendingPayroll),ui.money(r.preparationCost),r.foodShortfall,r.fuelShortfall,r.looseFuel],14)
	for boat in r.boats:ui.paragraph(details,"%s · %.2f fuel loaded / %.2f allowance, including contingency · %.2f beyond its tank"%[boat.name,boat.loaded,boat.required,boat.tankShortfall],14)
	ui.paragraph(details,"An estimate for the current fleet reserves nothing and proves no sale or career progression. An accepted job keeps its original terms. Prior travel/capital costs are excluded from a remaining-work view.",14)
	var toggle=ui.button(body,"Cost assumptions & individual tanks",func():details.visible=not details.visible,false,false)
	body.move_child(toggle,details.get_index())

static func _client(ui,body,model: Dictionary) -> void:
	var c=ui.host.core
	var memory: Dictionary=model.clientMemory
	if memory.is_empty():
		ui.paragraph(body,"Client: %s treasury. %s"%[model.originName,str(model.job.get("feeBasis","Ordinary funded work; the fee does not reimburse an arbitrary fleet."))],14)
	else:
		var port_name: String=str(c.port(str(memory.get("lastPort",""))).get("name","location unrecorded"))
		ui.paragraph(body,"%s remembers %d retained paid jobs; latest day %.1f at %s. %s"%[str(memory.name),int(memory.completedCount),float(memory.lastPaidDay),port_name,str(memory.detail)],15,ui.TEAL)
		ui.paragraph(body,str(model.job.get("feeBasis","This is ordinary paid work, with no separate repeat-client reward.")),14)

static func _warnings(ui,body,items: Array) -> void:
	if items.is_empty():return
	ui.paragraph(body,str(items[0]),15,ui.GOLD)
	if items.size()==1:return
	var details=ui.column(body);details.visible=false
	for text in items.slice(1):ui.paragraph(details,str(text),14,ui.GOLD)
	var toggle=ui.button(body,"Other preparation & access cautions (%d)"%(items.size()-1),func():details.visible=not details.visible,false,false)
	body.move_child(toggle,details.get_index())

static func fishing(ui,_body) -> void:
	review_fishing(ui)

static func review_fishing(ui,boat_uid: String="",days: float=1.0,crew: int=0,buyer_port_id: String="") -> void:
	var c=ui.host.core
	var uid: String=boat_uid
	if uid.is_empty():
		for b in c.active_fleet():
			if str(b.spec.get("civilianRole",""))=="fishing":uid=str(b.uid);break
	ui.modal_kind="voyage_review"
	var body=ui.modal("Fishing ground & return buyer","FINITE CATCH · REAL STORES · DATED SALE ESTIMATE",1020,800)
	ui.paragraph(body,"Set gear in safe open water. Recall when the ground, hold or stores make further work unhelpful; choose another ground on the normal chart or sail back and sell whole lots at a real Market.",16)
	var picker: OptionButton=carrier_picker(ui,body,"fishing",uid)
	if picker.item_count==0:
		ui.button(body,"Return to chart",ui.close_modal,false,false)
		return
	uid=str(picker.get_selected_metadata())
	var model: Dictionary=Choices.fishing_review(c,uid,days,crew,buyer_port_id)
	var quote: Dictionary=model.quote
	picker.item_selected.connect(func(_index: int):review_fishing(ui,str(picker.get_selected_metadata()),days,0,buyer_port_id))
	for work in c.CivilianWork.fishing_status(c):
		if str(work.boatUid)!=uid:continue
		ui.paragraph(body,"Gear set: %d sailors · %.2f / %.2f working days · %.2f lots caught. Recall before moving to another ground."%[int(work.crew),float(work.daysDone),float(work.daysTotal),float(work.catch)],16,ui.TEAL)
		ui.button(body,"Recall this boat's gear",func():ui.host.respond(c.cancel_fishing(uid));ui.host.save_game(false);review_fishing(ui,uid,days,crew,buyer_port_id))
	var options=ui.row(body)
	ui.label(options,"Elapsed forecast days",14)
	var duration=SpinBox.new();duration.min_value=0.25;duration.max_value=3.0;duration.step=0.25;duration.value=clampf(days,0.25,3);options.add_child(duration)
	ui.label(options,"Assigned sailors",14)
	var hands=SpinBox.new();hands.min_value=1;hands.max_value=maxi(1,int(c.find_boat(uid).get("crew",0)));hands.step=1;hands.value=maxi(1,int(quote.crew));options.add_child(hands)
	var buyers=OptionButton.new();buyers.custom_minimum_size.y=42
	for p in Choices.buyer_ports(c):
		buyers.add_item(str(p.name));buyers.set_item_metadata(buyers.item_count-1,str(p.id))
		if str(p.id)==str(model.buyer.portId):buyers.select(buyers.item_count-1)
	body.add_child(buyers)
	ui.button(body,"Update selected crew, horizon & buyer estimate",func():review_fishing(ui,uid,float(duration.value),int(hands.value),str(buyers.get_selected_metadata()) if buyers.item_count>0 else ""),false,false)
	ui.paragraph(body,"Day %.2f · ground %.1f / %.0f lots remain today · at most %.2f new fish lots in %.2f elapsed days"%[quote.day,quote.quotaRemaining,quote.quotaDaily,quote.catchMax,quote.requestedDays],21,ui.GOLD)
	var fill: String="will not fill the current free hold in this horizon" if float(quote.timeToFillDays)<0 else "could fill the current free hold in %.2f days"%float(quote.timeToFillDays)
	ui.paragraph(body,"%d sailors · %.2f lots per working day · %s. Limit: %s. Physical boat hold %.2f; whole fleet %.2f."%[int(quote.crew),quote.catchRate,fill,str(quote.limitingCause).capitalize(),quote.holdFree,quote.fleetHoldFree],15)
	ui.paragraph(body,"Loaded engine fuel %.2f; forecast work uses %.2f. Loaded crew food %.2f; work uses %.2f. More sailors can fill sooner; they share the same ground quota. Return and calendar payroll are budgeted below."%[quote.fuelLoaded,quote.fuelNeeded,quote.foodLoaded,quote.foodNeeded],15)
	if not quote.ok:ui.paragraph(body,str(quote.message),16,ui.GOLD)
	var buyer: Dictionary=model.buyer
	if buyer.seen:
		ui.paragraph(body,"%s · %s day %.2f (%.1f days old) · %d coins/whole lot · buyer purse %s coins"%[buyer.name,"current harbor quote" if buyer.live else "visit quote",buyer.day,buyer.age,int(buyer.sellQuote),ui.money(buyer.businessFunds)],16,ui.TEAL)
		ui.paragraph(body,"At most %d forecast whole lots fit that purse: %s gross coins. Prices and buyer funds can change; this is no guaranteed sale. %.2f existing fish lots aboard are separate."%[int(buyer.saleLots),ui.money(buyer.estimatedGross),model.carriedFish],15)
	else:ui.paragraph(body,"Visit a harbor Market to record a dated fish buyer and replacement prices. No sale estimate is available yet.",16,ui.GOLD)
	_budget(ui,body,model.budget,int(model.estimatedNet),bool(model.routeOk) and bool(buyer.seen) and bool(quote.ok))
	_warnings(ui,body,model.warnings)
	ui.paragraph(body,"The forecast horizon includes quota pauses. Setting gear requests that many earned working days; recall at your chosen elapsed horizon to keep this estimate's time budget.",14)
	var launch=ui.button(body,"Set gear for the reviewed crew & working days",func():_start_fishing(ui,uid,float(quote.requestedDays),int(quote.crew)),true)
	launch.disabled=not bool(quote.ok)
	var changed: Callable=func(_value: float):launch.disabled=true
	duration.value_changed.connect(changed);hands.value_changed.connect(changed)
	if buyers.item_count>0:buyers.item_selected.connect(func(_index: int):launch.disabled=true)
	if not str(buyer.portId).is_empty():
		ui.button(body,"Prepare route to %s · sailing ends fishing"%buyer.name,func():VoyagePanel.prepare_known_point(ui,c.port(str(buyer.portId)),str(buyer.portId)),true).disabled=str(buyer.portId).is_empty()
		if str(c.current_port().get("id",""))==str(buyer.portId):ui.button(body,"Open buyer Market · sell actual whole lots",func():ui.open_port("Market"))
	ui.button(body,"Close review · return to chart",ui.close_modal,false,false)

static func _start_fishing(ui,uid: String,days: float,crew: int) -> void:
	var result: Dictionary=ui.host.core.start_fishing(uid,days,crew)
	ui.host.respond(result)
	if result.ok:ui.host.save_game(false);ui.close_modal()

static func intel(ui,body) -> void:
	var c=ui.host.core
	ui.paragraph(body,"These are observations from your actual harbor visits. Remote reports age; they do not guarantee current stock, prices or a buyer's funds.",16)
	for id in c.state.get("marketSnapshots",{}):
		var snap: Dictionary=c.state.marketSnapshots[id]
		ui.rule(body)
		ui.label(body,"%s · %.1f days old"%[c.port(id).name,maxf(0,c.state.day-snap.day)],23,ui.GOLD,true)
		ui.paragraph(body,"Observed business purse: %s coins"%ui.money(snap.cash),15)
		for good in ["food","timber","iron","fuel","supplies"]:ui.paragraph(body,"%s · %.1f observed lots"%[c.Goods.ITEMS[good].name,snap.stocks.get(good,0)],14)
	if c.state.get("marketSnapshots",{}).is_empty():ui.paragraph(body,"Visit a harbor and enter its market to record your first observations.",17)
