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
	for id in Stories.CHAINS077:
		Stories.reconcile_knowledge(c.state,str(id))
	for id in Stories.CHAINS087:
		Stories.reconcile_knowledge(c.state,str(id))

static func start(c,id: String) -> Dictionary:
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	c.Contacts.visit(c.state,c.current_port(),c.state.day)
	ensure(c)
	for offer in Stories.available(c):
		if offer.id!=id:continue
		c.state.stories.chains[id]={"stage":offer.stage,"flags":[],"leads":[],"done":false,"startedDay":c.state.day}
		if id=="common_passage110":c.Arc110.accept_lead(c)
		Stories.reconcile_knowledge(c.state,id)
		c.log_entry("New coastal lead: %s. %s"%[offer.title,offer.nextAction])
		return c.ok("Lead entered in the journal. "+offer.nextAction)
	return c.fail("Meet this contact at the starting harbor to hear the lead.")

static func apply_pending(c) -> void:
	for entry in c.state.stories.consequences:
		if entry.get("applied",false):continue
		var effect_id: String=str(entry.id)
		# Factions retains only80characters. New long story prefixes must not
		# collapse different targets into one execution id; journal ids stay readable.
		if effect_id.begins_with("story:common_passage110:"):
			effect_id="arc110:"+effect_id.sha256_text()
		elif effect_id.begins_with("story:inverted_tide077:") or effect_id.begins_with("story:last_soundings077:"):
			effect_id="story077:"+effect_id.sha256_text()
		elif effect_id.begins_with("story:broken_meridian087:") or effect_id.begins_with("story:unfinished_keel087:") or effect_id.begins_with("story:two_lantern_anchorage087:"):
			effect_id="story087:"+effect_id.sha256_text()
		if entry.kind=="faction":c.Factions.adjust(c.state,entry.target,int(entry.amount),entry.reason,effect_id)
		elif entry.kind=="contact":c.Contacts.record(c.state,entry.target,entry.id,int(entry.amount))
		entry.applied=true

static func choose(c,id: String,choice: String) -> Dictionary:
	ensure(c)
	var rec: Dictionary=c.state.stories.chains.get(id,{})
	if rec.is_empty():return c.fail("Start the lead with its harbor contact first.")
	var chain: Dictionary=Stories._chain_def(c.state,id)
	var stage: Dictionary=Stories._stage_def(chain,str(rec.stage))
	if id=="last_soundings077" and choice in ["record_empty_to_wren077","record_empty_to_cass077"]:
		if bool(rec.get("done",false)) or str(rec.get("stage",""))!="marked_recovery":return c.fail("Check exhaustion during the active cache stage.")
		var exhausted: Dictionary=_exhausted_longglass077(c,rec)
		if not exhausted.ok:return exhausted
	if id=="unfinished_keel087" and choice=="record_exhausted_keel087":
		if bool(rec.get("done",false)) or str(rec.get("stage",""))!="decide_keel_recovery":return c.fail("Check slipway exhaustion during the active recovery stage.")
		var keel_exhausted: Dictionary=_exhausted_keel087(c,rec)
		if not keel_exhausted.ok:return keel_exhausted
	if id=="unfinished_keel087" and choice=="leave_keel_for_margin087":
		if bool(rec.get("done",false)) or str(rec.get("stage",""))!="decide_keel_recovery":return c.fail("Weigh slipway recovery during the active recovery stage.")
		var intact: Dictionary=_intact_keel087(c,rec)
		if not intact.ok:return intact
	if stage.get("gate",{}).get("type","")=="at_port":
		var permission: Dictionary=c.Politics.permit(c,"service","",c.work_port070() if c.current_port().is_empty() and c.has_method("work_port070") else {})
		if not permission.ok:return permission
	if id=="common_passage110":
		var permission111: Dictionary=c.Arc111.choice_gate(c,choice)
		if not permission111.ok:return permission111
	var result: Dictionary=Stories.choose(c,id,choice)
	if not result.ok:return result
	if id=="common_passage110":c.Arc111.after_choice(c,choice,result)
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
	_seed_surveyed_keel087(c)

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

# Called only with the original receipt from successful Remote067.recover.
static func after_recovery077(c,wreck_id: String,result: Dictionary) -> void:
	if c==null or not (c.get("state") is Dictionary) or wreck_id.is_empty():return
	if result.get("ok",false)!=true or result.get("completed",false)!=true:return
	if not Stories._is_num(result.get("quantity",null)) or float(result.quantity)<=0.0:return
	var rec: Dictionary=Stories._record(c.state,"last_soundings077")
	_after_keel_recovery087(c,wreck_id)
	if rec.is_empty() or bool(rec.get("done",false)) or str(rec.get("stage",""))!="marked_recovery":return
	if not (rec.get("flags") is Array) or (rec["flags"] as Array).has("paid_longglass077"):return
	for wreck in c.state.get("wrecks",[]):
		if not (wreck is Dictionary) or str(wreck.get("id",""))!=wreck_id:continue
		if str(wreck.get("sourceId",""))==Stories.LONGGLASS_SOURCE077:
			rec["flags"].append("paid_longglass077")
		return

# A known, fully surveyed and actually seeded empty source is not a paid load.
static func _exhausted_longglass077(c,rec: Dictionary) -> Dictionary:
	if (rec.get("flags",[]) as Array).has("paid_longglass077"):return c.fail("Your paid recovery is already recorded; use that receipt.")
	for site_id in ["glasswind_west_marker","glasswind_crown_log","glasswind_south_wreck"]:
		if Stories._site_level(c.state,str(site_id))<3:return c.fail("Fully survey all three Last Soundings sites first.")
	var cache: Dictionary=Stories._known_site(c.state,Stories.LONGGLASS_SITE077)
	if cache.is_empty() or int(cache.get("level",0))<3:return c.fail("Fully survey the actual Longglass cache before recording exhaustion.")
	var found: bool=false
	for wreck in c.state.get("wrecks",[]):
		if not (wreck is Dictionary) or str(wreck.get("sourceId",""))!=Stories.LONGGLASS_SOURCE077:continue
		found=true
		for key in ["components","stores"]:
			var stock= wreck.get(key,null)
			if not (stock is Dictionary):return c.fail("The cache inventory cannot establish exhaustion.")
			for good in stock:
				if not Stories._is_num(stock[good]) or float(stock[good])<0.0:return c.fail("The cache inventory cannot establish exhaustion.")
				if float(stock[good])>0.0:return c.fail("The cache still holds real stock; use normal paid recovery or leave it for another voyage.")
	if not found:return c.fail("The actual Longglass cache is absent; a missing source does not establish exhaustion.")
	return {"ok":true,"message":""}

static func _seed_surveyed_keel087(c) -> void:
	if c==null or not (c.get("state") is Dictionary) or not (c.get("events") is Array):return
	var keel_site: String=c.Salvage._bound_keel_site087(c.state)
	if keel_site.is_empty():return
	var rec: Dictionary=Stories._record(c.state,"unfinished_keel087")
	if rec.is_empty() or bool(rec.get("done",false)):return
	for ev in c.events:
		if ev is Dictionary and str(ev.get("kind",""))=="survey_complete" and str(ev.get("siteId",""))==keel_site and int(ev.get("level",0))>=3:
			c.Salvage.seed_keel087(c,keel_site)
			return

static func _after_keel_recovery087(c,wreck_id: String) -> void:
	var rec: Dictionary=Stories._record(c.state,"unfinished_keel087")
	if rec.is_empty() or bool(rec.get("done",false)) or not (str(rec.get("stage","")) in ["survey_stranded_slipway","decide_keel_recovery"]):return
	var source_id: String=c.Salvage.keel087_source(c.state)
	if source_id.is_empty() or not (rec.get("flags") is Array) or (rec["flags"] as Array).has("paid_keel_source087"):return
	for wreck in c.state.get("wrecks",[]):
		if wreck is Dictionary and str(wreck.get("id",""))==wreck_id and str(wreck.get("sourceId",""))==source_id:
			rec["flags"].append("paid_keel_source087")
			return

static func _intact_keel087(c,rec: Dictionary) -> Dictionary:
	if (rec.get("flags",[]) as Array).has("paid_keel_source087"):return c.fail("A paid recovery lot is already recorded for this slipway; log that recovery.")
	var site_id: String=c.Salvage._bound_keel_site087(c.state)
	if site_id.is_empty() or Stories._site_level(c.state,site_id)<3:return c.fail("Fully survey the stranded slipway first.")
	var source_id: String=c.Salvage.keel087_source(c.state)
	for wreck in c.state.get("wrecks",[]):
		if not (wreck is Dictionary) or str(wreck.get("sourceId",""))!=source_id:continue
		if not c.Salvage._strip_items(wreck).is_empty():return {"ok":true,"message":""}
		return c.fail("The slipway cradle has no remaining stock to leave behind; record verified exhaustion instead.")
	return c.fail("The canonical slipway workboat source is absent.")

static func _exhausted_keel087(c,rec: Dictionary) -> Dictionary:
	if (rec.get("flags",[]) as Array).has("paid_keel_source087"):return c.fail("Your paid slipway recovery is already recorded; use that receipt.")
	var site_id: String=c.Salvage._bound_keel_site087(c.state)
	if site_id.is_empty() or Stories._site_level(c.state,site_id)<3 or not (rec.get("flags",[]) as Array).has("keel_surveyed087"):
		return c.fail("Fully survey the stranded slipway and tally its manifest first.")
	var source_id: String=c.Salvage.keel087_source(c.state)
	if source_id.is_empty() or c.state.get("wreckSeededSources",{}).get(source_id,false)!=true:
		return c.fail("The canonical slipway source has not been seeded.")
	var found: bool=false
	for wreck in c.state.get("wrecks",[]):
		if not (wreck is Dictionary) or str(wreck.get("sourceId",""))!=source_id:continue
		found=true
		for key in ["components","stores"]:
			var stock=wreck.get(key,null)
			if not (stock is Dictionary):return c.fail("The slipway inventory cannot establish exhaustion.")
			for good in stock:
				if not Stories._is_num(stock[good]) or float(stock[good])<0.0:return c.fail("The slipway inventory cannot establish exhaustion.")
				if float(stock[good])>0.0:return c.fail("The slipway cradle still holds recoverable stock; complete a paid recovery or leave the frame for margin.")
	if not found:return c.fail("The canonical slipway workboat source is absent; a missing source does not establish exhaustion.")
	return {"ok":true,"message":""}
