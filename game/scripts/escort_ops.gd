extends RefCounted
const Locality064=preload("res://scripts/expedition.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Objectives=preload("res://scripts/battle_objectives.gd")
const Goods=preload("res://scripts/goods.gd")
const Damage=preload("res://scripts/damage.gd")

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
	host.begin_battle(enemy.boats.filter(func(b):return not b.sunk).map(func(b):return b.spec),{"kind":"escort","ownerId":enemy.id,"allyOwnerId":convoy_id,"escortEvent":event,"name":"Escort %s through the interception"%convoy.name,"mission":mission})

static func settled(c,result: String,context: Dictionary,outcome: Dictionary={}) -> void:
	if context.get("kind","")!="escort":return
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
