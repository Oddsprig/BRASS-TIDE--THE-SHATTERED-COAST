extends RefCounted
const Stories=preload("res://scripts/coastal_stories.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
static func ensure(c) -> void:
	Stories.ensure(c.state)
	if not c.state.get("storyRights") is Dictionary:c.state.storyRights={}
	var r: Dictionary=c.state.storyRights
	for key in ["openField","privateField","workshopCharter","privateOre","publicCharts","privateCharts"]:
		if not r.has(key):r[key]=false
	if not r.has("buyer"):r.buyer=""
	for key in ["usedOffers","salvageWork"]:
		if not r.get(key) is Dictionary:r[key]={}
	Stories.reconcile_knowledge(c.state,"middle_sea_chart")

static func start(c,id: String) -> Dictionary:
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	c.Contacts.visit(c.state,c.current_port(),c.state.day)
	ensure(c)
	for offer in Stories.available(c):
		if offer.id!=id:continue
		c.state.stories.chains[id]={"stage":offer.stage,"flags":[],"leads":[],"done":false,"startedDay":c.state.day}
		Stories.reconcile_knowledge(c.state,id)
		c.log_entry("New coastal lead: %s. %s"%[offer.title,offer.nextAction])
		return c.ok("Lead entered in the journal. "+offer.nextAction)
	return c.fail("Meet this contact at the starting harbor to hear the lead.")

static func apply_pending(c) -> void:
	for entry in c.state.stories.consequences:
		if entry.get("applied",false):continue
		if entry.kind=="faction":c.Factions.adjust(c.state,entry.target,int(entry.amount),entry.reason,entry.id)
		elif entry.kind=="contact":c.Contacts.record(c.state,entry.target,entry.id,int(entry.amount))
		entry.applied=true

static func choose(c,id: String,choice: String) -> Dictionary:
	ensure(c)
	var rec: Dictionary=c.state.stories.chains.get(id,{})
	if rec.is_empty():return c.fail("Start the lead with its harbor contact first.")
	var chain: Dictionary=Stories._chain_def(c.state,id)
	var stage: Dictionary=Stories._stage_def(chain,str(rec.stage))
	if stage.get("gate",{}).get("type","")=="at_port":
		var permission: Dictionary=c.Politics.permit(c,"service")
		if not permission.ok:return permission
	var result: Dictionary=Stories.choose(c,id,choice)
	if not result.ok:return result
	var r: Dictionary=c.state.storyRights
	match choice:
		"open_field":r.openField=true;r.privateField=false
		"exclusive_claim":r.privateField=true;r.openField=false
		"compact_first":r.buyer="compact"
		"forge_first":r.buyer="forge"
		"open_cut":r.publicCharts=true;r.privateCharts=false
		"keep_cut":r.privateCharts=true;r.publicCharts=false
		"revive_workshop":r.workshopCharter=true
		"keep_the_seam":r.privateOre=true
	apply_pending(c)
	c.Manifest.allocate(c.state)
	return result

static func refresh(c) -> void:
	ensure(c)
	apply_pending(c)
	for e in Stories.tick(c):c.log_entry("Coastal lead ready: "+str(e.nextAction))

static func daily(c) -> void:
	refresh(c)
	if not c.state.storyRights.openField:return
	for owner in c.state.fleetOwners:
		if not owner.active or owner.kind!="trader" or owner.faction!="reed":continue
		if int(c.state.storyRights.salvageWork.get(owner.id,-1))==int(c.state.econDay):continue
		var p: Dictionary=c.NavalAI._find_patrol(c.state,owner.id)
		if p.is_empty():continue
		var spare: int=0;var worker: Dictionary={}
		for b in owner.boats:
			if b.sunk:continue
			spare+=maxi(0,floori(b.crew-b.wounded-b.crewMin))
			if b.supplies>=0.25:worker=b
		if spare<2 or worker.is_empty():continue
		var free: float=maxf(0,c.Fleets._capacity(owner)-Economy.cargo_weight(owner.cargo))
		for wreck in c.state.wrecks:
			if wreck.sourceId!="site:shatter_wreck_field" or wreck.status!="unclaimed" or c.distance(p,wreck)>600:continue
			for good in wreck.components:
				if float(owner.tradeCargo)>0 and owner.tradeGood!=good:continue
				var qty: float=floorf(minf(float(wreck.components[good]),minf(2.0,free/float(Goods.ITEMS[good].weight))))
				if qty<=0:continue
				wreck.components[good]-=qty;wreck.hullStripped=true
				owner.cargo[good]=float(owner.cargo.get(good,0))+qty;owner.tradeGood=good;owner.tradeCargo+=qty
				worker.supplies-=0.25
				c.state.storyRights.salvageWork[owner.id]=int(c.state.econDay)
				c.log_entry("Public field: %s recovered %.0f %s using two working sailors and real kits."%[owner.name,qty,Goods.ITEMS[good].name])
				break
