extends RefCounted
const Locality064=preload("res://scripts/expedition.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")
const Goods=preload("res://scripts/goods.gd")
const Damage=preload("res://scripts/damage.gd")
const CONTRACT_RADIUS: float=600.0

# Sea offers use the existing trader, water route, loaded holds and purse.
# No NPC is rerouted, stocked, attacked or held waiting for the player.
static func contracted(c,owner_id: String="") -> Dictionary:
	for job in c.state.get("voyageJobs",[]):
		if str(job.get("kind",""))=="escort" and (owner_id.is_empty() or str(job.get("ownerId",""))==owner_id):return job
	return {}

static func offer(c,owner_id: String) -> Dictionary:
	if not Locality064.home_local064(c.state):return {}
	if not c.travel_lock064.is_empty():return {}
	for event in c.events:
		if str(event.get("kind","")) in ["encounter","ocean_encounter066","defeat"]:return {}
	var client: Dictionary=c.fleet_owner(owner_id)
	var p: Dictionary=c.NavalAI._find_patrol(c.state,owner_id)
	if client.is_empty() or p.is_empty() or not client.get("active",false) or not p.get("active",false) or p.get("hidden",false) or p.get("holding",false):return {}
	if client.get("kind","")!="trader" or client.get("playerCompany",false) or c.Politics.hostile(c,client) or c.NavalAI.NavalOrders.enrolled066(c.state,owner_id):return {}
	if c.distance(c.state.position,p)>CONTRACT_RADIUS or p.get("course",[]).is_empty() or p.has("interceptPoint"):return {}
	var target: Dictionary=c.port(str(p.get("to","")))
	var home: Dictionary=c.port(str(client.get("homePort","")))
	if target.is_empty() or home.is_empty() or str(target.id)==str(home.id):return {}
	var good: String=str(client.get("tradeGood",""))
	var qty: float=float(client.get("tradeCargo",0))
	if not Goods.ITEMS.has(good) or qty<=0 or float(client.get("cargo",{}).get(good,0))+0.000001<qty:return {}
	var loaded: Dictionary=_load_plan(c,client)
	var escorts: Array=c.FleetSupport.combat(c)
	if not loaded.ok or escorts.is_empty() or client.boats.any(func(b):return b.get("sunk",false) or b.get("captureSecured",false) or float(b.crew)<float(b.crewMin)):return {}
	if Deployment.total(client.boats+escorts)>Deployment.LIMIT:return {}
	var remaining: float=maxf(0,float(p.get("courseLength",0))*(1.0-float(p.get("progress",0))))
	if remaining<160.0:return {} # A dockside acceptance is not an escorted leg.
	var speed: float=float(c.NavalAI.fleet_performance(client).speed)*0.38*float(c.data.get("CAMPAIGN_SCALE",1.0))
	var days: float=remaining/maxf(1.0,speed)/float(c.DAY_SECONDS)
	var fee: int=c.VoyageJobs._route_reward(c,days,"",false,home)
	if int(client.get("coins",0))<fee+int(c.Fleets.upkeep(client).wages):return {}
	var event: String="escort:%s:%d"%[owner_id,int(p.get("voyageSeq",0))]
	if c.state.get("escortEvents",{}).has(event) or c.VoyageJobs._is_closed(c.state,event):return {}
	var carrier_cargo: Dictionary={}
	for uid in loaded.carrierUids:carrier_cargo[uid]=loaded.carrierCargo[uid].duplicate(true)
	return {"id":event,"title":"Escort %s to %s"%[client.name,target.name],"description":"The convoy client escrows its own coins. Stay within 600 along the remaining water route; keep the original loaded carriers and complete their real sale at the named harbor. If intercepted, every carrier must physically escape. Loss, withdrawal, route change or leaving the convoy refunds the client. Your fuel, wages and repairs remain paid costs.","kind":"escort","port":str(home.id),"targetPort":str(target.id),"ownerId":owner_id,"payerKey":"coins","reward":fee,"escrow":0,"freight":{},"state":"offered","deadlineDay":float(c.state.day)+ceilf(days*2.0)+2.0,"acceptedDay":0.0,"escort":{"voyageSeq":int(p.get("voyageSeq",0)),"fromPort":str(p.get("from","")),"carrierUids":loaded.carrierUids.duplicate(),"carrierCargo":carrier_cargo,"tradeGood":good,"tradeQty":qty,"baselineDelivered":float(client.get("tradeDelivered",0)),"routeDistance":remaining,"accompaniedDistance":0.0,"playerDistance":0.0,"lastPosition":c.state.position.duplicate(),"lastConvoyPosition":{"x":float(p.x),"y":float(p.y)},"lastDay":float(c.state.day),"arrived":false,"battlePending":false,"exitSecured":false,"failure":""}}

static func _contract_failure(c,job: Dictionary,reason: String) -> void:
	job.failed=true;job.escort.failure=reason
	c.VoyageJobs._expire_overdue(c,c.state)
	c.log_entry("Escort ended: %s. Unearned escrow returns to its original client; actual voyage costs remain."%reason)

static func advance_contract(c,job: Dictionary) -> void:
	var route: Dictionary=job.escort
	if route.arrived or route.battlePending:return
	var client: Dictionary=c.fleet_owner(str(job.ownerId))
	var p: Dictionary=c.NavalAI._find_patrol(c.state,str(job.ownerId))
	if not Locality064.home_local064(c.state) or client.is_empty() or p.is_empty() or not client.get("active",false) or c.active_fleet().is_empty():_contract_failure(c,job,"The escort or original client is no longer on this coastal passage.");return
	for uid in route.carrierUids:
		if not client.boats.any(func(b):return str(b.get("uid",""))==str(uid) and not b.get("sunk",false) and not b.get("captureSecured",false)):_contract_failure(c,job,"An original loaded carrier was lost or captured.");return
	if int(p.get("voyageSeq",0))!=int(route.voyageSeq) or str(p.get("to",""))!=str(job.targetPort):_contract_failure(c,job,"The client left the contracted route before completing delivery.");return
	var near: bool=c.distance(c.state.position,p)<=CONTRACT_RADIUS and c.distance(route.lastPosition,route.lastConvoyPosition)<=CONTRACT_RADIUS
	if not near:_contract_failure(c,job,"You left the convoy's 600-unit protection radius.");return
	var moved: float=c.distance(p,route.lastConvoyPosition)
	route.accompaniedDistance=float(route.accompaniedDistance)+moved
	route.playerDistance=float(route.playerDistance)+c.distance(c.state.position,route.lastPosition)
	route.lastPosition=c.state.position.duplicate();route.lastConvoyPosition={"x":float(p.x),"y":float(p.y)};route.lastDay=float(c.state.day)
	var dock: Dictionary=c.port(str(job.targetPort))
	var delivered: float=float(client.get("tradeDelivered",0))-float(route.baselineDelivered)
	if str(client.get("atPort",""))==str(job.targetPort) and p.get("holding",false) and not dock.is_empty() and c.distance(p,dock)<40.0 and delivered+0.000001>=float(route.tradeQty):
		# Endpoint proximity/acceptance alone never pays. Both real participants
		# must traverse the protected leg, and the original client must sell it.
		if float(route.accompaniedDistance)+40.0<float(route.routeDistance)*0.8 or float(route.playerDistance)+40.0<float(route.routeDistance)*0.8:return
		if int(route.get("interceptions",0))>0 and not route.exitSecured:return
		route.arrived=true;route.deliveredQty=delivered;route.arrivedDay=float(c.state.day)
		c.log_entry("Escorted loaded carriers delivered at %s. Report there to release %d held client coins."%[dock.name,job.reward])
		return
	if str(client.get("tradeGood",""))!=str(route.tradeGood) or float(client.get("tradeCargo",0))+0.000001<float(route.tradeQty) or float(client.get("cargo",{}).get(str(route.tradeGood),0))+0.000001<float(route.tradeQty):_contract_failure(c,job,"The contracted trade cargo did not remain aboard through delivery.")

static func _settle_contract_battle(c,result: String,context: Dictionary,outcome: Dictionary) -> void:
	var job: Dictionary=c.VoyageJobs._find(c.state,str(context.get("escortJobId","")))
	if job.is_empty() or str(job.kind)!="escort" or job.state!="active" or not job.escort.battlePending:return
	if str(job.ownerId)!=str(context.get("allyOwnerId","")) or str(job.id)!=str(context.get("escortEvent","")):return
	var cargo: float=0.0
	var uids: Array=[]
	for row in outcome.get("carriers",[]):
		uids.append(str(row.uid));cargo+=float(row.get("cargoAboard",{}).get(str(job.escort.tradeGood),0))
	if result!="won" or not outcome.get("success",false) or int(outcome.get("escaped",0))!=int(outcome.get("total",-1)) or uids!=job.escort.carrierUids or str(outcome.get("exit",{}).get("portId",""))!=str(job.targetPort) or cargo+0.000001<float(job.escort.tradeQty):
		job.escort.battlePending=false;_contract_failure(c,job,"Physical interception ended in loss, withdrawal or an incomplete loaded-carrier escape.");return
	job.escort.battlePending=false;job.escort.exitSecured=true

# One review reached through ordinary Coastal traffic -> Hail. The existing
# encounter/protect button remains available for voluntary rescues as before.
static func review(ui,owner_id: String) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var job: Dictionary=contracted(c,owner_id)
	var shown: Dictionary=offer(c,owner_id) if job.is_empty() else job
	ui.modal_kind="escort_review"
	var body=ui.modal("Paid convoy escort","ACTUAL CLIENT, CARGO AND ROUTE",760,700)
	if shown.is_empty():ui.paragraph(body,"No funded loaded passage is available here. Approach within 600 of a sailing peaceful convoy; it needs an existing load, safe route, crew and enough operating coins.",17)
	else:
		ui.label(body,str(shown.title),23,ui.GOLD,true)
		ui.paragraph(body,str(shown.description),17)
		ui.paragraph(body,"%d coins %s · %.1f %s · %d original loaded carrier(s) · report at %s · deadline day %.2f"%[int(shown.reward),"held in client-funded escrow" if not job.is_empty() else "from the client's own purse",float(shown.escort.tradeQty),str(shown.escort.tradeGood),shown.escort.carrierUids.size(),c.port(str(shown.targetPort)).get("name",shown.targetPort),float(shown.deadlineDay)],16,ui.GOLD)
		if job.is_empty():ui.button(body,"Accept funded escort (%d coins)"%int(shown.reward),func():_respond(ui,c.VoyageJobs.accept_escort(c,owner_id,int(shown.reward)),owner_id))
		else:
			ui.paragraph(body,"Status: %s. Accompanied %.0f / %.0f route units. %s"%[str(job.state),float(job.escort.accompaniedDistance),float(job.escort.routeDistance),str(job.escort.get("failure",""))],16)
			if job.state=="active" and job.escort.arrived:ui.button(body,"Claim held fee at delivery harbor",func():_respond(ui,c.settle_voyage_job(str(job.id)),owner_id))
			if job.state=="active" and not job.escort.arrived and not threat(c,c.fleet_owner(owner_id)).is_empty():ui.button(body,"Protect convoy to its exit",func():start(ui.host,owner_id))
			ui.button(body,"Withdraw contract; refund client",func():_respond(ui,c.VoyageJobs.abandon(c,str(job.id)),owner_id))
	var p: Dictionary=c.NavalAI._find_patrol(c.state,owner_id)
	if Locality064.home_local064(c.state) and not p.is_empty() and p.get("active",false) and not p.get("hidden",false) and c.distance(c.state.position,p)<=1800.0:
		ui.button(body,"Plot course to current convoy position",func():ui.host.respond(c.chart_course({"x":float(p.x),"y":float(p.y)}));ui.close_modal())
		ui.button(body,"Exchange signals / encounter",func():ui.host.show_patrol_encounter(owner_id))

static func _respond(ui,result: Dictionary,owner_id: String) -> void:
	ui.host.respond(result)
	if result.get("ok",false):ui.host.save_game(false)
	review(ui,owner_id)

static func _load_plan(c,owner: Dictionary) -> Dictionary:
	var boats: Array=owner.get("boats",[]).filter(func(b):return not b.get("sunk",false) and not b.get("captureSecured",false))
	boats.sort_custom(func(a,b):return str(a.get("uid",""))<str(b.get("uid","")))
	var manifest: Dictionary={}
	var free: Dictionary={}
	for b in boats:
		var uid: String=str(b.get("uid",""))
		if uid.is_empty() or manifest.has(uid):return {"ok":false,"message":"Convoy carrier identities are unavailable."}
		manifest[uid]={}
		free[uid]=maxf(0.0,float(b.spec.get("cargo",0))-c.Expedition.store_overflow(b))
	var goods: Array=owner.get("cargo",{}).keys();goods.sort()
	for good in goods:
		var left: float=Damage.number(owner.cargo[good],NAN)
		if not Goods.ITEMS.has(good) or not is_finite(left) or left<0:return {"ok":false,"message":"The convoy's actual cargo is invalid."}
		for b in boats:
			var uid: String=str(b.uid)
			var weight: float=float(Goods.ITEMS[good].weight)
			var qty: float=minf(left,float(free[uid])/weight)
			if qty<=0:continue
			manifest[uid][good]=qty;free[uid]-=qty*weight;left-=qty
			if left<=0.000001:break
		if left>0.000001:return {"ok":false,"message":"The convoy's actual cargo exceeds its surviving physical holds."}
	var uids: Array=[]
	for b in boats:
		if not manifest[str(b.uid)].is_empty():uids.append(str(b.uid))
	return {"ok":not uids.is_empty(),"message":"Only a loaded convoy has a cargo passage to protect or intercept.","carrierCargo":manifest,"carrierUids":uids}

static func _mission(c,owner: Dictionary,kind: String) -> Dictionary:
	var loaded: Dictionary=_load_plan(c,owner)
	if not loaded.ok:return {"startError":str(loaded.message)}
	var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(owner.id))
	return {"kind":kind,"carrierTeam":"player" if kind=="escort" else "enemy","carrierOwnerId":str(owner.id),"carrierUids":loaded.carrierUids,"carrierCargo":loaded.carrierCargo,"exit":{"x":2180.0 if kind=="escort" else 120.0,"y":850.0,"radius":70.0,"portId":str(patrol.get("to","")),"portName":str(c.port(str(patrol.get("to",""))).get("name",patrol.get("to","")))}}

static func prepare_intercept(c,context: Dictionary) -> Dictionary:
	var owner: Dictionary=c.fleet_owner(str(context.get("ownerId",context.get("id",""))))
	if owner.is_empty() or owner.get("kind","")!="trader" or float(owner.get("tradeCargo",0))<=0:return context
	var out: Dictionary=context.duplicate(true)
	var mission: Dictionary=_mission(c,owner,"intercept")
	if mission.has("startError"):out.startError=mission.startError;return out
	var error: String=Objectives.deployment_error(c.FleetSupport.combat(c),owner.boats.filter(func(b):return not b.sunk),mission)
	if not error.is_empty():out.startError=error;return out
	out.mission=mission
	return out
static func threat(c,convoy: Dictionary) -> Dictionary:
	if not Locality064.home_local064(c.state):return {}
	var chart: Dictionary=c.NavalAI._find_patrol(c.state,str(convoy.get("id","")))
	if chart.is_empty() or c.distance(c.state.position,chart)>1800:return {}
	var nearest: Dictionary={};var distance: float=1800
	for p in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(p.id)
		if owner.is_empty() or not owner.active or not p.active or c.Factions.relation(c.state,convoy.faction,owner.faction)>-20:continue
		if not owner.boats.any(func(b):return not b.sunk and b.ammo>0 and b.crew>=b.crewMin):continue
		var d: float=c.distance(p,chart)
		if d<distance:distance=d;nearest=owner
	return nearest

static func start(host,convoy_id: String) -> void:
	host.sync_economy()
	var c=host.core
	var convoy: Dictionary=c.fleet_owner(convoy_id)
	var enemy: Dictionary=threat(c,convoy)
	if convoy.is_empty() or enemy.is_empty() or convoy.kind!="trader" or c.Politics.hostile(c,convoy):host.ui.toast("No nearby peaceful convoy with an observed armed threat.",true);return
	var escorts: Array=c.FleetSupport.combat(c)
	var allies: Array=convoy.boats.filter(func(b):return not b.sunk and b.crew>=b.crewMin)
	if escorts.is_empty() or allies.is_empty() or Deployment.total(allies+escorts)>Deployment.LIMIT:host.ui.toast("Every convoy boat and at least one of your crewed combat boats must fit together within 300 deployment points.",true);return
	var mission: Dictionary=_mission(c,convoy,"escort")
	if mission.has("startError"):host.ui.toast(str(mission.startError),true);return
	mission.allyUids=allies.map(func(b):return str(b.uid))
	var error: String=Objectives.deployment_error(allies+escorts,enemy.boats.filter(func(b):return not b.sunk),mission)
	if not error.is_empty():host.ui.toast(error,true);return
	var p: Dictionary=c.NavalAI._find_patrol(c.state,convoy_id)
	var event: String="escort:%s:%d"%[convoy_id,int(p.get("voyageSeq",0))]
	if c.state.escortEvents.has(event):host.ui.toast("This passage has already been credited. Let the convoy complete its delivery.",true);return
	var job: Dictionary=contracted(c,convoy_id)
	if not job.is_empty() and job.state=="active":
		if job.escort.arrived:host.ui.toast("This contracted delivery is complete. Report at its harbor for the held fee.");return
		advance_contract(c,job)
		if job.failed or str(job.id)!=event or mission.carrierUids!=job.escort.carrierUids:host.ui.toast("The contracted original loaded passage is no longer available.",true);return
	host.begin_battle(enemy.boats.filter(func(b):return not b.sunk).map(func(b):return b.spec),{"kind":"escort","ownerId":enemy.id,"allyOwnerId":convoy_id,"escortEvent":event,"escortJobId":str(job.get("id","")) if job.get("state","")=="active" else "","name":"Escort %s through the interception"%convoy.name,"mission":mission})
	# Main may refuse deployment. Only an actual begun battle locks this job.
	if host.mode=="battle" and str(host.battle_context.get("escortJobId",""))==str(job.get("id","")) and not job.is_empty():
		job=c.VoyageJobs._find(c.state,str(job.id));job.escort.battlePending=true;job.escort.interceptions=int(job.escort.get("interceptions",0))+1

static func settled(c,result: String,context: Dictionary,outcome: Dictionary={}) -> void:
	if context.get("kind","")!="escort":return
	_settle_contract_battle(c,result,context,outcome)
	var ally: Dictionary=c.fleet_owner(str(context.get("allyOwnerId","")))
	if ally.is_empty():return
	ally.active=ally.boats.any(func(b):return not b.sunk)
	if result!="won" or not ally.active or not outcome.get("success",false) or int(outcome.get("escaped",0))!=int(outcome.get("total",-1)):return
	var event: String=str(context.get("escortEvent",""))
	if c.state.escortEvents.has(event):return
	c.state.escortEvents[event]=true
	while c.state.escortEvents.size()>256:c.state.escortEvents.erase(c.state.escortEvents.keys()[0])
	c.state.campaignFacts.escortsSaved=int(c.state.campaignFacts.get("escortsSaved",0))+1
	c.Factions.adjust(c.state,ally.faction,5,"Protected an actual convoy passage",event)
	c.FleetIdentity.record_service(c,c.active_fleet().map(func(b):return b.uid),"rescue")
	c.log_entry("Convoy protected; its actual cargo and surviving boats continue their paid delivery. No bounty or enemy purse was promised.")

static func cargo_error(c,battle: Dictionary) -> String:
	if not battle.has("convoy"):return ""
	if battle.get("startError","")!="" or battle.get("result") not in ["won","lost","retreated"]:return "The physical convoy encounter has not finished."
	var owner: Dictionary=c.fleet_owner(str(battle.mission.get("carrierOwnerId","")))
	if owner.is_empty():
		return "" if battle.convoy.cargo.is_empty() else "The convoy cargo owner is unavailable."
	var totals: Dictionary={}
	for uid in battle.convoy.uids:
		var ship: Dictionary=battle.convoy.actors.get(uid,{})
		if ship.is_empty():return "An assigned convoy carrier is missing from settlement."
		for good in battle.convoy.cargo.get(uid,{}):
			var qty: float=Damage.number(battle.convoy.cargo[uid][good],NAN)
			if not Goods.ITEMS.has(good) or not is_finite(qty) or qty<0:return "The carrier cargo ledger is invalid."
			totals[good]=float(totals.get(good,0))+qty
	for good in totals:
		if float(totals[good])>Damage.number(owner.get("cargo",{}).get(good),-1.0)+0.000001:return "The convoy no longer holds its assigned cargo; retain this engagement."
	return ""

static func _held_prize(c,actor: Dictionary) -> Dictionary:
	for held in c.state.fleet+c.state.get("boardingPrizes",[]):
		if (is_same(held,actor) or str(held.get("uid",""))==str(actor.get("uid",""))) and held.get("captureSecured",false) and not held.get("sunk",false):return held
	return {}

static func take_prize_cargo(c,uid: String,good: String,qty: float) -> Dictionary:
	if not Goods.ITEMS.has(good) or not is_finite(qty) or qty<=0:return c.fail("Choose a positive quantity of actual prize cargo.")
	var prize: Dictionary={}
	for held in c.state.fleet+c.state.get("boardingPrizes",[]):
		if str(held.get("uid",""))==uid and not held.get("sunk",false):prize=held;break
	if prize.is_empty() or qty>Damage.number(prize.get("convoyCargo",{}).get(good)):return c.fail("That prize does not hold the selected cargo.")
	if qty*float(Goods.ITEMS[good].weight)>maxf(0,c.capacity()-c.cargo_weight())+0.000001:return c.fail("The traveling boats need enough real hold space for the prize cargo.")
	prize.convoyCargo[good]=maxf(0,float(prize.convoyCargo[good])-qty)
	c.state.cargo[good]=float(c.state.cargo.get(good,0))+qty
	c.Manifest.allocate(c.state)
	return c.ok("Transferred %.1f %s from the actual prize into traveling holds."%[qty,good])

static func settle_cargo(c,battle: Dictionary,wrecks: Array) -> Dictionary:
	if not battle.has("convoy"):return {}
	if battle.get("convoySettlement") is Dictionary:return battle.convoySettlement.duplicate(true)
	var outcome: Dictionary=Objectives.snapshot(battle)
	var owner: Dictionary=c.fleet_owner(str(battle.mission.get("carrierOwnerId","")))
	var lost_wrecks: Dictionary={}
	var prizes: Dictionary={}
	# Resolve every destination before debiting any owner cargo.
	for row in outcome.carriers:
		if row.fate=="captured":
			prizes[row.uid]=_held_prize(c,battle.convoy.actors[row.uid])
			if prizes[row.uid].is_empty():return {"ok":false,"message":"The captured carrier must be held by the actual campaign prize roster before cargo can settle."}
		if row.fate!="sunk":continue
		for record in wrecks:
			if str(record.get("uid",""))==str(row.uid):lost_wrecks[row.uid]=c.Salvage.find_wreck(c.state,str(record.id));break
		if lost_wrecks.get(row.uid,{}).is_empty() and not row.cargoAboard.is_empty():return {"ok":false,"message":"The lost carrier needs its actual wreck before cargo can settle."}
	for row in outcome.carriers:
		var ship: Dictionary=battle.convoy.actors[row.uid]
		row.ownerId=str(owner.get("id",""))
		row.moduleCondition=ship.get("moduleCondition",{}).duplicate(true)
		if row.fate=="sunk":row.crewAlive=0.0;row.crewWounded=0.0
		if row.fate not in ["sunk","captured"] or owner.is_empty():continue
		var wreck: Dictionary={}
		if row.fate=="sunk":
			wreck=lost_wrecks.get(row.uid,{})
			row.sourceWreckId=str(wreck.get("id",""))
			row.moduleCondition=wreck.get("sourceModuleCondition",{}).duplicate(true)
		else:
			# Prize holds stay on the actual damaged hull; never bypass player hold capacity.
			var prize: Dictionary=prizes[row.uid]
			prize.convoyCargo=row.cargoAboard.duplicate(true)
			row.prizeUid=str(prize.uid)
			row.ownerId="player"
		for good in row.cargoAboard:
			var qty: float=float(row.cargoAboard[good])
			owner.cargo[good]=maxf(0.0,float(owner.cargo.get(good,0))-qty)
			if good==str(owner.get("tradeGood","")):owner.tradeCargo=maxf(0.0,float(owner.get("tradeCargo",0))-qty)
			if row.fate=="sunk":wreck.stores[good]=float(wreck.stores.get(good,0))+qty*0.5
	if not owner.is_empty():
		owner.active=owner.boats.any(func(b):return not b.sunk)
		var patrol: Dictionary=c.NavalAI._find_patrol(c.state,str(owner.id))
		if not patrol.is_empty():patrol.active=owner.active
	# This report is saved with the real campaign, without advancing a sea voyage to port.
	c.state.lastConvoyOutcome=outcome.duplicate(true)
	battle.convoySettlement=outcome.duplicate(true)
	return outcome
