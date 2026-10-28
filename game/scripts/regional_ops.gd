extends RefCounted
## Main-thread adapter: verified physical events -> bounded regional facts.
const Regional=preload("res://scripts/regional_campaigns.gd")
const Rules=preload("res://scripts/regional_rules.gd")
const Politics=preload("res://scripts/politics.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const Lifecycle=preload("res://scripts/naval_lifecycle.gd")

static func ensure(c) -> void:
	Regional.ensure(c.state)
	if not c.state.get("regionalFacts") is Dictionary:c.state.regionalFacts={"deliveries":{},"passages":{}}
	if not c.state.get("campaignFocus") is Dictionary:
		var first: String=str(c.state.get("lastPort",""))
		if c.port(first).is_empty():first=str(c.state.ports[0].id)
		var nearest: String=""
		var best: float=INF
		for p in c.state.ports:
			if p.id==first:continue
			var d: float=c.distance(c.port(first),p)
			if d<best:nearest=p.id;best=d
		c.state.campaignFocus={"fromPort":first,"toPort":nearest,"portId":first,"peaceA":"compact","peaceB":"raiders"}
	if not c.state.has("regionalOrigin"):c.state.regionalOrigin=""

static func start(c,id: String) -> Dictionary:
	ensure(c)
	if id!="survey":
		var permission: Dictionary=Politics.permit(c,"service")
		if not permission.ok:return permission
		var p: Dictionary=c.current_port()
		if id=="harbor" and str(c.state.campaignFocus.portId)!=p.id:return c.fail("Start harbor development at the selected harbor.")
		if id=="corridor" and not p.id in [str(c.state.campaignFocus.fromPort),str(c.state.campaignFocus.toPort)]:return c.fail("Visit one of the chosen corridor's harbors to organize its watch.")
	var result: Dictionary=Regional.start(c,id)
	if result.ok and not str(result.get("ownerId","")).is_empty():
		refresh(c)
	if result.ok:c.log_entry("Regional goal: "+str(Regional.TITLES[id])+".")
	return result

static func contribute(c,id: String,good: String,qty: int) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var result: Dictionary=Regional.contribute(c,id,good,qty)
	if result.ok:
		c.Manifest.allocate(c.state)
		if id=="corridor":refresh(c)
	return result

static func selected_status(c,id: String="corridor") -> Dictionary:
	return Regional.selected_status(c,id)

static func continue_watch(c) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var op: Dictionary=c.state.get("regionalCampaigns",{}).get("operations",{}).get("corridor",{})
	var p: Dictionary=c.current_port()
	if not str(p.id) in op.get("ends",[]):return c.fail("Visit one of the existing corridor's harbors to continue its paid watch.")
	var result: Dictionary=Regional.continue_watch(c)
	if result.ok and result.changed:
		refresh(c)
		c.log_entry("Regional corridor watch continued with its original paid patrol and reserves.")
	return result

static func withdraw_watch(c) -> Dictionary:
	# Withdrawing needs no new harbor service or payment. Caller joins workers.
	var result: Dictionary=Regional.withdraw_watch(c)
	if result.ok and result.changed:
		refresh(c)
		c.log_entry("Regional corridor watch withdrawn; its paid fleet and achievement remain.")
	return result

static func refresh(c) -> Dictionary:
	var op: Dictionary=c.state.get("regionalCampaigns",{}).get("operations",{}).get("corridor",{})
	var owner: Dictionary=c.fleet_owner(str(op.get("ownerId","")))
	if owner.is_empty():return {}
	var patrol: Dictionary=Orders.find_patrol(c.state,str(owner.id))
	if not Orders.RegionalOrders.assigned(op):
		if op.has("currentPlan"):
			# Release a formerly published regional plan once. Returning uses the
			# existing physical route and paid recovery; no dock/service is replayed.
			var home: String=str(owner.get("homePort",""))
			if not c.port(home).is_empty():
				var release_context: Dictionary={"nav":c.nav,"scale":c.data.get("CAMPAIGN_SCALE",1),"daySeconds":c.DAY_SECONDS}
				var release_quote: Dictionary=Orders.RegionalOrders.readiness(c.state,owner,home,release_context)
				var release_plan: Dictionary={"ownerId":str(owner.id),"completionId":str(op.completionId),"purpose":"withdraw","destination":home,"targetOwnerId":"","convoyOwnerId":"","ready":bool(release_quote.ready),"hold":not bool(release_quote.ready) and (str(owner.get("atPort",""))!="" or not bool(release_quote.get("canReturn",false))),"reason":"Regional assignment ended; returning for normal paid harbor service. "+str(release_quote.reason),"readiness":release_quote}
				var released: Dictionary=Orders.apply_regional_plan(c.state,owner,release_plan)
				if not released.is_empty() and not patrol.is_empty() and patrol.get("active",false):
					if released.get("hold",false):
						patrol.to=str(released.destination);patrol.holding=true;patrol.course=[];patrol.progress=0.0;owner.progress=0.0
						patrol.erase("interceptPoint")
					else:Lifecycle.route(c,patrol,str(released.destination))
			for key in ["currentPlan","readiness","stallReason","planIdentity"]:op.erase(key)
		return {}
	var context: Dictionary={"nav":c.nav,"scale":c.data.get("CAMPAIGN_SCALE",1),"daySeconds":c.DAY_SECONDS}
	var plan: Dictionary=Orders.RegionalOrders.plan(c.state,owner,str(owner.get("atPort","")),context)
	var applied: Dictionary=Orders.apply_regional_plan(c.state,owner,plan)
	if applied.is_empty():return {}
	Regional.observe_plan(c.state,owner,applied)
	if not patrol.is_empty() and patrol.get("active",false):
		var dest: String=str(applied.destination)
		var point: Dictionary=applied.get("interceptPoint",{})
		if applied.get("hold",false):
			patrol.to=dest;patrol.holding=true;patrol.course=[];patrol.progress=0.0;owner.progress=0.0
			patrol.erase("interceptPoint")
		elif str(patrol.to)!=dest or patrol.get("interceptPoint",{})!=point or (patrol.get("holding",false) and str(owner.get("atPort",""))!=dest and str(patrol.get("routeFailure","")).is_empty()):
			Lifecycle.route(c,patrol,dest,point)
	return applied

static func delivered(c,to: String,qty: float,from: String="",player: bool=true) -> void:
	if qty<=0 or c.port(to).is_empty():return
	ensure(c)
	if player:
		c.state.campaignFacts.goodsDelivered=int(c.state.campaignFacts.get("goodsDelivered",0))+floori(qty)
		var deliveries: Dictionary=c.state.regionalFacts.deliveries
		deliveries[to]=float(deliveries.get(to,0))+qty
	if from!=to and not c.port(from).is_empty():
		var key: String=Rules.route_key([from,to])
		c.state.regionalFacts.passages[key]=int(c.state.regionalFacts.passages.get(key,0))+1

static func battle(c,owner: Dictionary,result: String,objective_only: bool) -> void:
	if result!="won" or owner.is_empty():return
	ensure(c)
	if owner.get("kind","")=="raider" and not objective_only:c.state.campaignFacts.bountyWins=int(c.state.campaignFacts.get("bountyWins",0))+1
	var op: Dictionary=c.state.regionalCampaigns.operations.get("corridor",{})
	if op.get("status","")!="active":return
	var pos:=Vector2(float(c.state.position.x),float(c.state.position.y))
	if Rules.near_corridor(c.state,op,pos) and (objective_only or owner.get("kind","")=="raider"):op.playerAction=true

static func begin_day(c) -> void:
	for e in Rules.expire(c.state,Regional.ensure(c.state)):
		Regional._note(c.state.regionalCampaigns,e)
		c.log_entry("Regional treaty expired: "+str(e.target)+". "+str(e.cause))

static func daily(c) -> void:
	for e in Regional.tick(c,1):
		c.log_entry("Regional "+str(e.kind)+": "+str(e.get("completionId",e.get("target","")))+". "+str(e.cause))
		if e.get("kind","")=="complete" and e.get("goal","")=="corridor":refresh(c)
