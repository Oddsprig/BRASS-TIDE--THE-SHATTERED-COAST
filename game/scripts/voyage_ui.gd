extends RefCounted
const Choices=preload("res://scripts/civilian_choices059.gd")
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
		if str(job.kind) in Choices.CIVILIAN_KINDS:ui.button(body,"Review remaining voyage & client",func():review_job(ui,job),false,false)
		if job.get("failed",false):ui.paragraph(body,"Freight lost: this job needs to be closed at a harbor.",15,ui.RED)
		var target: Dictionary=c.port(job.targetPort)
		if job.kind=="survey":
			var s: Dictionary=c.Exploration.catalog_site(c.state,job.siteId)
			var progress: int=int(c.state.exploration.sites.get(job.siteId,{}).get("level",0))
			if progress<3:target=s
			ui.paragraph(body,survey_terms(c,job),15,ui.TEAL)
		ui.button(body,"Chart next destination",func():ui.host.respond(c.chart_course(target,str(target.get("id","")) if c.port(str(target.get("id",""))).size()>0 else ""));ui.close_modal())
		ui.button(body,"Complete & release escrow",func():settle(ui,job.id,false),true)
		ui.button(body,"Abandon / unload remaining freight",func():settle(ui,job.id,true))
	ui.rule(body)
	ui.label(body,"Available at this harbor",25,ui.GOLD,true)
	var offers: Array=c.VoyageJobs.available(c)
	if offers.is_empty():ui.paragraph(body,"Enter a harbor for funded work. Offers need an actual sponsor purse and physical cargo; completed jobs do not reroll.",16)
	for item in offers:
		var offer: Dictionary=item.duplicate(true)
		ui.label(body,offer.title,23,ui.TEXT,true)
		ui.paragraph(body,offer.description,15)
		if offer.kind=="survey":ui.paragraph(body,survey_terms(c,offer),15,ui.TEAL)
		if not str(offer.get("sponsorContactId","")).is_empty():ui.paragraph(body,sponsor_reason(c,offer),15,ui.TEAL)
		ui.paragraph(body,"%s coins · deadline day%.0f"%[ui.money(offer.reward),offer.deadlineDay],15,ui.GOLD)
		if not str(offer.get("loadTier","")).is_empty():ui.paragraph(body,"%s load · %s"%[str(offer.loadTier).capitalize(),str(offer.get("demandPurpose",offer.description))],15,ui.TEAL)
		if str(offer.kind) in Choices.CIVILIAN_KINDS:
			ui.button(body,"Review load, carrier & operating budget",func():review_job(ui,offer),true,false)
		else:
			ui.button(body,"Accept funded job",func():ui.host.respond(c.accept_voyage_job(offer.id));ui.host.save_game(false);open(ui),true).disabled=c.state.voyageJobs.size()>=6
		ui.rule(body)
	ui.button(body,"Story contracts & captain's log",ui.open_contracts)

static func survey_terms(c,job: Dictionary) -> String:
	var harbor: Dictionary=c.port(str(job.get("port","")))
	var terms: String="Paid work: fully surveyed (level 3), then report at %s. Budget charting plus the full survey, with four spare sailors above boat minimums; wages and provisions continue ashore."%str(harbor.get("name","the sponsoring harbor"))
	if str(job.get("siteId",""))=="middle_chart_rock":terms+=" Wren's rock clue needs only charted level 2; that clue alone does not release escrow. The extra survey normally takes 2.5 days and 2 kits, adjusted by your actual survey equipment."
	return terms

static func settle(ui,id: String,abandon: bool) -> void:
	ui.host.respond(ui.host.core.settle_voyage_job(id,abandon))
	ui.host.save_game(false)
	open(ui)

static func contacts(ui,body) -> void:
	var c=ui.host.core
	var offers: Array=c.VoyageJobs.available(c)
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

static func review_job(ui,offer: Dictionary,carrier_uid: String="") -> void:
	var c=ui.host.core
	var model: Dictionary=Choices.job_review(c,offer,carrier_uid)
	ui.modal_kind="voyage_review" # Existing header-X contract: no economy sync.
	var body=ui.modal("Review civilian work","ONE LOAD · ACTUAL FLEET · RESERVED PAYMENT",1020,800)
	if not model.get("ok",false):
		ui.paragraph(body,str(model.message),17)
		ui.button(body,"Return to chart",ui.close_modal,false,false)
		return
	var job: Dictionary=model.job
	ui.paragraph(body,str(job.title),24,ui.GOLD)
	ui.paragraph(body,"%s → %s · deadline day %.1f"%[model.originName,model.targetName,float(job.deadlineDay)],16,ui.TEAL)
	if not model.active:
		var picker: OptionButton=carrier_picker(ui,body,str(job.kind),str(model.carrierUid))
		picker.item_selected.connect(func(_index: int):review_job(ui,offer,str(picker.get_selected_metadata())))
	ui.paragraph(body,str(job.get("demandPurpose",job.get("description","")))+" · quoted day %.1f"%float(job.get("quotedDay",job.get("acceptedDay",c.state.day))),16)
	var load: Dictionary=job.get("freight",{})
	var carrying: String="%.1f sealed %s · %.1f hold space"%[float(load.get("qty",0)),str(c.Goods.ITEMS.get(str(load.get("good","")),{"name":"cargo"}).name),float(model.loadWeight)]
	if str(job.kind)=="passenger_charter":carrying="%d passengers · %.2f dedicated ration bales"%[int(model.passengers),float(model.passengerFood)]
	ui.paragraph(body,carrying,18,ui.GOLD)
	ui.paragraph(body,"%s: %.2f physical hold free after its %.2f locker weight · %d spare berths. Whole fleet %.2f hold free."%[model.carrierName,model.holdFree,model.lockerWeight,model.spareBerths,model.fleetHoldFree],15)
	if str(job.kind)=="freight":ui.paragraph(body,"Freight uses the existing shared manifest across traveling boats; this picker inspects one hull, not a new carrier assignment.",14)
	var fee_text: String="Contracted fee %s coins"%ui.money(model.grossFee)
	if model.active:fee_text+=" · %s fee coins still reserved"%ui.money(model.feeReserved)
	ui.paragraph(body,fee_text,21,ui.GOLD)
	if str(job.kind)=="passenger_charter":ui.paragraph(body,"Passenger savings %s coins remain custody, separate from your fee and operating margin. Their bought rations stay on the selected carrier."%ui.money(model.savingsCustody),15,ui.TEAL)
	_budget(ui,body,model.budget,int(model.estimatedNet),bool(model.routeOk),bool(model.remainingOnly))
	_client(ui,body,model)
	if not model.recipient.is_empty():
		var recipient: Dictionary=model.recipient
		var place: String=str(c.port(str(recipient.currentPort)).get("name","At sea / not present"))
		ui.paragraph(body,"Recipient report day %.2f · age %.2f days · currently %s · need %.1f fuel. %s"%[float(recipient.observedDay),float(recipient.ageDays),place,float(recipient.demand),str(recipient.message)],15,ui.GOLD)
		ui.paragraph(body,"The fleet can leave or use other fuel before arrival. Tanks are not reserved; an interrupted delivery earns no fee and payroll continues.",14)
	_warnings(ui,body,model.warnings)
	ui.rule(body)
	if model.active:
		ui.button(body,"Chart this delivery harbor",func():ui.host.respond(c.chart_course(c.port(str(job.targetPort)),str(job.targetPort)));ui.close_modal()).disabled=not bool(model.routeOk)
	else:
		ui.button(body,"Accept reviewed funded job",func():_accept_reviewed(ui,job,str(model.carrierUid)),true).disabled=not bool(model.carrierFits) or not bool(model.allowanceFits) or c.state.get("voyageJobs",[]).size()>=6
	ui.button(body,"Leave review · return to chart" if model.active else "Decline · return to chart",ui.close_modal,false,false)

static func _accept_reviewed(ui,job: Dictionary,uid: String) -> void:
	var carrier: String=uid if str(job.kind) in ["fuel_delivery","passenger_charter"] else ""
	var result: Dictionary=ui.host.core.accept_voyage_job(str(job.id),carrier)
	ui.host.respond(result)
	if result.ok:ui.host.save_game(false);open(ui)

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
	ui.paragraph(details,"An estimate reserves nothing and proves no sale or career progression. An accepted job keeps its original terms. Prior travel/capital costs are excluded from a remaining-work view.",14)
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
		ui.button(body,"Chart return to %s · sailing ends fishing"%buyer.name,func():ui.host.respond(c.chart_course(c.port(str(buyer.portId)),str(buyer.portId)));ui.close_modal()).disabled=not bool(model.routeOk)
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
