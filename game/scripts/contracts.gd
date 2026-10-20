extends RefCounted
const Money = preload("res://scripts/money.gd")
const Goods = preload("res://scripts/goods.gd")

static func available(core) -> Array:
	var offers: Array = []
	if core.state.missionIndex < core.data.MISSIONS.size():
		var story: Dictionary = core.data.MISSIONS[core.state.missionIndex].duplicate(true)
		story.story = true
		story.ownerId = "story-%d"%core.state.missionIndex
		var enemy_value: float = 0.0
		for id in story.enemyHulls:
			enemy_value += core.hull(id).price
		story.reward = ceili(enemy_value*0.85+core.crew_count()*Goods.SAILOR_WAGE*4)
		offers.append(story)
	var p: Dictionary = core.current_port()
	if p.is_empty():
		return offers
	var day: int = int(core.state.day)
	var destination: Dictionary = core.state.ports[(core.state.ports.find(p)+day%3+1)%core.state.ports.size()]
	var grade: int = mini(3,1+int(core.state.missionIndex/3))
	var enemy_ids: Array = ["bilge_punt"]
	if grade >= 2:
		enemy_ids.append("scab_cutter")
	if grade >= 3:
		enemy_ids.append("barbed_lance")
	var bounty_id: String = "bounty-%s-%d"%[p.id,day]
	if not bounty_id in core.state.doneSide:
		var target_owner: Dictionary = {}
		for owner in core.state.fleetOwners:
			if owner.kind == "raider" and str(owner.id).begins_with("patrol-") and owner.active:
				target_owner = owner
				break
		if not target_owner.is_empty():
			var enemy_value: float = 0.0
			enemy_ids.clear()
			for boat in target_owner.boats:
				if not boat.sunk:
					enemy_ids.append(boat.type)
					enemy_value += core.hull(boat.type).price
			offers.append({"id":bounty_id,"title":"Coastal patrol: %s"%destination.name,"description":"The harbor government escrows the bounty. Destroy the named raider fleet to release it.","kind":"bounty","port":p.id,"targetPort":destination.id,"enemyHulls":enemy_ids,"ownerId":target_owner.id,"reward":ceili(enemy_value*0.45+grade*Goods.SAILOR_WAGE*10),"renown":8*grade,"story":false})
	var delivery_id: String = "delivery-%s-%d"%[p.id,day]
	if not delivery_id in core.state.doneSide:
		var travel_days: float = core.distance(p,destination)/maxf(1.0,core.travel_speed())/core.DAY_SECONDS
		var reward: int = ceili(core.crew_count()*Goods.SAILOR_WAGE*maxf(1.0,travel_days)*2.0+Goods.cost("supplies")*2.0)
		offers.append({"id":delivery_id,"title":"Sealed dispatch to %s"%destination.name,"description":"A business pays from its own purse. Carry its sealed medical kits; payment waits in escrow.","kind":"delivery","port":p.id,"targetPort":destination.id,"enemyHulls":[],"cargo":{"good":"supplies","qty":8},"reward":reward,"renown":5,"story":false})
	return offers

static func accept(core, id: String) -> Dictionary:
	if not core.state.activeContract.is_empty():
		return core.fail("Finish or abandon your current contract first.")
	var contract: Dictionary = {}
	for offer in available(core):
		if offer.id == id:
			contract = offer.duplicate(true)
	if contract.is_empty():
		return core.fail("This contract is no longer available.")
	var p: Dictionary = core.current_port()
	if p.is_empty() or p.id != contract.port:
		return core.fail("Accept this contract at its sponsoring harbor.")
	var payer_key: String = "cash" if contract.kind == "delivery" else "governmentPurse"
	if p[payer_key] < contract.reward:
		return core.fail("The sponsor cannot fund this contract's escrow today.")
	if contract.has("cargo"):
		var good: String = contract.cargo.good
		var qty: int = int(contract.cargo.qty)
		if core.cargo_weight()+qty*core.Economy.GOODS[good].weight > core.capacity() or p.stocks[good] < qty:
			return core.fail("The sponsor lacks that cargo, or your hold is full.")
		p.stocks[good] -= qty
		core.state.freight = contract.cargo.duplicate(true)
	contract.escrow = 0
	contract.payerKey = payer_key
	Money.move(p,payer_key,contract,"escrow",int(contract.reward),"Sponsor funds contract escrow",core.state.moneyLog)
	contract.cleared = contract.enemyHulls.is_empty()
	core.state.activeContract = contract
	core.log_entry("Accepted %s; %d cash moved from the sponsor into escrow."%[contract.title,contract.reward])
	return core.ok("Contract funded. Chart its destination.")

static func finish(core) -> Dictionary:
	if not core.contract_ready() or not core.state.activeContract.get("cleared",false):
		return core.fail("Reach the destination and clear its hostile boats first.")
	var contract: Dictionary = core.state.activeContract
	var paid: int = int(contract.get("escrow",0))
	if paid != int(contract.reward):
		return core.fail("The contract escrow is incomplete.")
	Money.move(contract,"escrow",core.state,"coins",paid,"Contract payment from escrow",core.state.moneyLog)
	if not core.state.freight.is_empty():
		var target: Dictionary = core.port(contract.targetPort)
		target.stocks[core.state.freight.good] += core.state.freight.qty
	core.state.renown += contract.renown
	core.state.morale = minf(100.0,core.state.morale+4)
	if contract.get("story",false):
		core.state.missionIndex += 1
	else:
		core.state.doneSide.append(contract.id)
	core.state.activeContract = {}
	core.state.freight = {}
	core.state.completed = core.state.missionIndex >= core.data.MISSIONS.size()
	core.log_entry("Completed %s: %d bronze cash released by its sponsor."%[contract.title,paid])
	return {"ok":true,"message":"Contract paid: %d cash."%paid,"reward":paid,"completed":core.state.completed}

static func abandon(core) -> Dictionary:
	if core.state.activeContract.is_empty():
		return core.fail("No active contract.")
	var contract: Dictionary = core.state.activeContract
	var sponsor: Dictionary = core.port(contract.port)
	Money.move(contract,"escrow",sponsor,contract.payerKey,int(contract.escrow),"Abandoned contract escrow refunded",core.state.moneyLog)
	if not core.state.freight.is_empty():
		var dock: Dictionary = core.current_port()
		if not dock.is_empty():
			dock.stocks[core.state.freight.good] += core.state.freight.qty
	core.state.activeContract = {}
	core.state.freight = {}
	core.state.renown = maxi(0,core.state.renown-5)
	return core.ok("Escrow refunded. Sealed freight unloaded or jettisoned; five renown lost.")
