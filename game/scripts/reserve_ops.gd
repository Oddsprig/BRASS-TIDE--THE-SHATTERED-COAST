extends RefCounted
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
const Navigation=preload("res://scripts/navigation.gd")

static func ensure(c) -> void:
	for p in c.state.ports:
		if not p.get("reserves") is Dictionary:
			Reserves.ensure(p)
			var nearest: Dictionary={}
			var distance: float=INF
			for other in c.state.ports:
				if other.id==p.id:continue
				var length: float=c.distance(p,other)
				if length<distance:distance=length;nearest=other
			if not nearest.is_empty():
				var path: Array=Navigation.find_path(c.nav,p,nearest)
				var length: float=0
				for i in range(1,path.size()):length+=c.distance(path[i-1],path[i])
				var transport_speed: float=maxf(10,float(c.hull("bilge_punt").get("speed",70))*1.55*float(c.data.get("CAMPAIGN_SCALE",1.0)))
				p.reserves.resupplyDays=clampf(1.0+2.0*length/(transport_speed*c.DAY_SECONDS),1.0,14.0)
	refresh(c)

static func refresh(c) -> void:
	for p in c.state.ports:
		Reserves.ensure(p)
		p.reserves.availableRecipes=Economy._build_recipes(Economy.INDUSTRIES.get(str(p.industry),Economy.INDUSTRIES.trade),str(p.get("specialty","")))
		var demand: Dictionary={}
		for good in p.get("lastProduction",{}):
			var batches: float=float(p.lastProduction[good])
			if not is_finite(batches) or batches<0 or batches>1000000000:batches=0
			for ingredient in Goods.ITEMS.get(good,{}).get("inputs",{}):
				demand[ingredient]=float(demand.get(ingredient,0))+batches*float(Goods.ITEMS[good].inputs[ingredient])
		for good in p.get("lastPublicUse",{}):demand[good]=float(demand.get(good,0))+float(p.lastPublicUse[good])
		for owner in c.state.fleetOwners:
			if str(owner.homePort)!=str(p.id):continue
			demand.food=float(demand.get("food",0))+maxf(0,float(owner.get("lastFoodConsumed",0)))
			demand.fuel=float(demand.get("fuel",0))+maxf(0,float(owner.get("lastFuelConsumed",0)))
		p.reserves.observedDemand=demand
		var incoming: Dictionary={}
		for owner in c.state.fleetOwners:
			if not owner.active or owner.get("kind","")!="trader" or str(owner.get("destination",""))!=str(p.id) or not str(owner.get("atPort","")).is_empty():continue
			var good: String=str(owner.get("tradeGood",""))
			if Goods.ITEMS.has(good):incoming[good]=float(incoming.get(good,0))+minf(float(owner.get("tradeCargo",0)),float(owner.cargo.get(good,0)))
		p.reserves.incoming=incoming
		# Current freight/build contracts physically withdraw stock on acceptance.
		# They are carried by their owner, so no remaining port lot is reserved.
		p.reserves.contractedLots={}

static func policy(c,policy_id: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var p: Dictionary=c.current_port()
	if int(Factions.standing(c.state,p.faction).score)<20:return c.fail("Friendly standing is required to advise this harbor's reserve policy.")
	var result: Dictionary=Reserves.set_policy(p,policy_id)
	if result.ok:c.log_entry(p.name+": "+str(result.message))
	return result

static func release_food(c) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var p: Dictionary=c.current_port()
	if int(Factions.standing(c.state,p.faction).score)<20:return c.fail("Earn friendly standing before requesting a public granary release.")
	var quantity: float=minf(float(p.publicStores.get("food",0)),maxf(1,float(p.workforce)*Economy.DAILY_FOOD_PER_PERSON))
	if quantity<=0:return c.fail("The public granary has no physical food to release.")
	var clerk: int=ceili(0.25*Goods.WAGES.laborer)
	var overseer: int=ceili(0.125*Goods.WAGES.foreman)
	if int(c.state.coins)<clerk+overseer:return c.fail("The release needs %d coins for clerk and oversight time."%(clerk+overseer))
	if int(p.availableWorkers)-ceili(float(p.get("_yardWorkersUsed",0)))<1 or int(p.availableSpecialists)-ceili(float(p.get("_yardSpecialistsUsed",0)))<1:return c.fail("The harbor office has no free staff today.")
	Money.move(c.state,"coins",p,"householdPurse",clerk,"Public granary clerk",c.state.moneyLog)
	Money.move(c.state,"coins",p,"expertPurse",overseer,"Public granary oversight",c.state.moneyLog)
	p._yardWorkersUsed=float(p.get("_yardWorkersUsed",0))+1
	p._yardSpecialistsUsed=float(p.get("_yardSpecialistsUsed",0))+1
	p.publicStores.food-=quantity;p.stocks.food+=quantity
	refresh(c)
	c.log_entry("Released %.2f actual food lots from %s public granary into its commercial store."%[quantity,p.name])
	return c.ok("Public food now enters ordinary local sales and resident consumption; no goods were copied.")
