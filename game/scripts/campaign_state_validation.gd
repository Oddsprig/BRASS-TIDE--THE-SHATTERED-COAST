extends RefCounted
## Optional campaign-extension schema; legacy voyages omit these fields.
static func number(value,low: float=0.0,high: float=1000000000.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func validate(s: Dictionary,world: Dictionary) -> String:
	if s.has("surveyFoodCredit") and not number(s.surveyFoodCredit,0,1000):return "Invalid prepaid survey rations."
	if s.has("exploration"):
		if not s.exploration is Dictionary:return "Invalid exploration record."
		var ex: Dictionary=s.exploration
		if not ex.get("catalog") is Array or ex.catalog.size()>128 or not ex.get("sites") is Dictionary or ex.sites.size()>128:return "Invalid island catalog/progress."
		var ids: Dictionary={}
		for site in ex.catalog:
			if not site is Dictionary or not site.get("id") is String or ids.has(site.id):return "Invalid or duplicate island site."
			if not number(site.get("x"),0,float(world.WORLD.width)) or not number(site.get("y"),0,float(world.WORLD.height)):return "Invalid island location."
			for key in ["name","kind","region","clue","discovery","hazard","resource","leadId"]:
				if not site.get(key) is String:return "Invalid island text."
			ids[site.id]=true
		for id in ex.sites:
			var rec=ex.sites[id]
			if not ids.has(id) or not rec is Dictionary or not number(rec.get("level"),0,3) or not rec.get("rewarded") is bool:return "Invalid island progress."
		if not ex.get("assignment") is Dictionary:return "Invalid survey assignment."
		var a: Dictionary=ex.assignment
		if not a.is_empty():
			if not ids.has(a.get("siteId","")) or a.get("action","") not in ["chart","survey"]:return "Unknown survey site/action."
			for key in ["crewReserved","daysTotal","daysDone","foodSpent","suppliesSpent","targetLevel"]:
				if not number(a.get(key),0,1000):return "Invalid survey accounting."
			if float(a.daysTotal)<=0 or float(a.daysDone)>float(a.daysTotal):return "Invalid survey duration."
		for key in ["leads","log"]:
			if not ex.get(key) is Array or ex[key].size()>128:return "Invalid exploration "+key+"."
	if s.has("wrecks"):
		if not s.wrecks is Array or s.wrecks.size()>128:return "Invalid persistent wreck collection."
		var wreck_ids: Dictionary={}
		for w in s.wrecks:
			if not w is Dictionary or not w.get("id") is String or wreck_ids.has(w.id):return "Invalid or duplicate wreck identity."
			wreck_ids[w.id]=true
			if not number(w.get("x"),0,float(world.WORLD.width)) or not number(w.get("y"),0,float(world.WORLD.height)):return "Invalid wreck location."
			if w.get("status","") not in ["unclaimed","stripped","towed"]:return "Invalid wreck status."
			if w.has("sourceLoadout") and not w.sourceLoadout is Dictionary:return "Invalid wreck equipment."
			for key in ["stores","components"]:
				if not w.get(key) is Dictionary:return "Invalid wreck inventory."
				for good in w[key]:
					if not good in ["food","logs","timber","ore","charcoal","iron","copper","saltpeter","sulfur","gunpowder","ammo","crude","fuel","supplies","engines","guns"] or not number(w[key][good]):return "Invalid wreck material quantity."
	if s.has("blueprints"):
		if not s.blueprints is Dictionary or s.blueprints.size()>128:return "Invalid blueprint library."
		for key in s.blueprints:
			if not s.blueprints[key] is bool or not world.HULLS.any(func(h):return h.id==key):return "Unknown recovered hull design."
	for key in ["wreckSeededSources","wreckHazards"]:
		if s.has(key) and (not s[key] is Dictionary or s[key].size()>512):return "Invalid wreck provenance ledger."
	if s.has("voyageJobs"):
		if not s.voyageJobs is Array or s.voyageJobs.size()>6:return "Invalid voyage commitment collection."
		var jobs: Dictionary={}
		var ports: Array=[]
		for p in world.PORTS:ports.append(p.id)
		for job in s.voyageJobs:
			if not job is Dictionary or not job.get("id") is String or jobs.has(job.id):return "Invalid or duplicate voyage job."
			jobs[job.id]=true
			if job.get("kind","") not in ["freight","survey","bounty"] or job.get("state","") not in ["active","expired"]:return "Invalid voyage job kind/state."
			if not job.get("port","") in ports or not job.get("targetPort","") in ports or job.get("payerKey","") not in ["cash","governmentPurse"]:return "Unknown voyage sponsor/destination."
			for key in ["reward","escrow","deadlineDay","acceptedDay"]:
				if not number(job.get(key)):return "Invalid voyage job accounting."
			if floorf(float(job.escrow))!=float(job.escrow) or float(job.escrow)>float(job.reward):return "Invalid voyage escrow."
			if not job.get("freight") is Dictionary:return "Invalid sealed voyage freight."
			var freight: Dictionary=job.freight
			if not freight.is_empty():
				if not freight.get("good") is String or not number(freight.get("qty")) or not freight.good in ["food","logs","timber","ore","charcoal","iron","copper","saltpeter","sulfur","gunpowder","ammo","crude","fuel","supplies","engines","guns"]:return "Invalid sealed voyage goods."
			for key in ["title","description","siteId","ownerId"]:
				if not job.get(key) is String:return "Invalid voyage text."
	if s.has("doneVoyageJobs") and (not s.doneVoyageJobs is Array or s.doneVoyageJobs.size()>128):return "Invalid completed voyage records."
	if s.has("contacts"):
		if not s.contacts is Array or s.contacts.size()>32:return "Invalid contact list."
		for person in s.contacts:
			if not person is Dictionary or not person.get("id") is String or not number(person.get("trust"),-100,100) or not person.get("met") is bool:return "Invalid contact identity/trust."
	if s.has("marketSnapshots"):
		if not s.marketSnapshots is Dictionary or s.marketSnapshots.size()>32:return "Invalid market reports."
		for id in s.marketSnapshots:
			var snap=s.marketSnapshots[id]
			if not snap is Dictionary or not number(snap.get("day")) or not number(snap.get("cash")) or not snap.get("stocks") is Dictionary:return "Invalid dated market observation."
	if s.has("relationships"):
		if not s.relationships is Dictionary:return "Invalid faction record."
		var b: Dictionary=s.relationships
		for key in ["factions","pairs","contacts","commission","seen","portIndex"]:
			if not b.get(key) is Dictionary or b[key].size()>128:return "Invalid faction book "+key+"."
		for id in b.factions:
			var f=b.factions[id]
			if not f is Dictionary or not number(f.get("score"),-100,100) or not number(f.get("witnessed"),-100,100) or f.get("band","") not in ["hostile","wary","neutral","friendly","trusted"] or not f.get("claims") is Dictionary:return "Invalid faction standing."
			for port_id in f.claims:
				if not number(f.claims[port_id],0,100):return "Invalid harbor claim."
		for value in b.pairs.values():
			if not number(value,-100,100):return "Invalid faction diplomacy."
		for key in ["log","seenOrder"]:
			if not b.get(key) is Array or b[key].size()>128:return "Invalid faction history."
		for key in ["safeConduct","inspections"]:
			if b.has(key) and (not b[key] is Dictionary or b[key].size()>128):return "Invalid faction permits."
		for value in b.get("safeConduct",{}).values():
			if not number(value):return "Invalid safe conduct duration."
	if s.has("navalAi"):
		if not s.navalAi is Dictionary:return "Invalid naval activity book."
		for key in ["encounters","replacements"]:
			if not s.navalAi.get(key) is Array or s.navalAi[key].size()>24:return "Invalid bounded naval history."
		for key in ["spatialGrid","ordersByOwner"]:
			if not s.navalAi.get(key) is Dictionary or s.navalAi[key].size()>128:return "Invalid naval index."
		if not number(s.navalAi.get("tickCount")) or not number(s.navalAi.get("lastDay")):return "Invalid naval day counter."
	if s.has("tradeIntel"):
		if not s.tradeIntel is Dictionary:return "Invalid trade intelligence."
		var ti: Dictionary=s.tradeIntel
		if not ti.get("observations") is Dictionary or ti.observations.size()>16 or not ti.get("blockades") is Dictionary or ti.blockades.size()>32 or not ti.get("events") is Array or ti.events.size()>40:return "Invalid bounded trade intelligence."
		for record in ti.observations.values():
			if not record is Dictionary or not number(record.get("day")) or not number(record.get("businessFunds")):return "Invalid dated buyer observation."
			for key in ["stocks","buy","sell"]:
				if not record.get(key) is Dictionary or record[key].size()>16:return "Invalid observed market."
				for value in record[key].values():
					if not number(value):return "Invalid observed market value."
	if s.has("specialists"):
		if not s.specialists is Array or s.specialists.size()>1024:return "Invalid specialist ledger."
		var specialist_ids: Dictionary={}
		for r in s.specialists:
			if not r is Dictionary or not r.get("id") is String or specialist_ids.has(r.id) or r.get("role","") not in ["pilot","gunner","chief_engineer","surveyor","quartermaster"]:return "Invalid specialist identity."
			specialist_ids[r.id]=true
			for key in ["coins","arrears","premiumPerDay","hiredDay"]:
				if not number(r.get(key)):return "Invalid specialist accounting."
			if not r.get("boatUid") is String or not r.get("portId") is String or not r.get("active") is bool:return "Invalid specialist assignment."
	for b in s.get("fleet",[]):
		if b.has("conversion") and b.conversion not in ["","cargo_rig","survey_rig","workshop_rig","tug_rig","auxiliary_tanks"]:return "Unknown support conversion."
		if b.has("supportOnly") and not b.supportOnly is bool:return "Invalid support deployment policy."
		if b.has("serviceHistory") and (not b.serviceHistory is Array or b.serviceHistory.size()>12):return "Invalid boat service history."
	if s.has("campaignFacts"):
		if not s.campaignFacts is Dictionary or s.campaignFacts.size()>32:return "Invalid campaign achievements."
		for value in s.campaignFacts.values():
			if not number(value):return "Invalid campaign achievement count."
	if s.has("escortEvents") and (not s.escortEvents is Dictionary or s.escortEvents.size()>256):return "Invalid escorted passage ledger."
	if s.has("battleSeq") and not number(s.battleSeq):return "Invalid engagement sequence."
	if s.has("stories"):
		if not s.stories is Dictionary:return "Invalid coastal story book."
		var stories: Dictionary=s.stories
		if not stories.get("catalog") is Array or stories.catalog.size()>16 or not stories.get("chains") is Dictionary or stories.chains.size()>16:return "Invalid bounded story catalog/progress."
		for key in ["events","consequences","notified"]:
			if not stories.get(key) is Array or stories[key].size()>128:return "Invalid story event history."
		for rec in stories.chains.values():
			if not rec is Dictionary or not rec.get("stage") is String or not rec.get("done") is bool or not rec.get("flags") is Array or not rec.get("leads") is Array:return "Invalid story progress."
		for e in stories.consequences:
			if not e is Dictionary or not e.get("id") is String or e.get("kind","") not in ["faction","contact"] or not number(e.get("amount"),-25,25) or not e.get("applied") is bool:return "Invalid story consequence."
	if s.has("storyRights"):
		if not s.storyRights is Dictionary:return "Invalid story rights."
		var r: Dictionary=s.storyRights
		for key in ["openField","privateField","workshopCharter","privateOre","publicCharts","privateCharts"]:
			if not r.get(key) is bool:return "Invalid story permission."
		if r.get("buyer","") not in ["","compact","forge"] or not r.get("usedOffers") is Dictionary or r.usedOffers.size()>8 or not r.get("salvageWork") is Dictionary or r.salvageWork.size()>32:return "Invalid story opportunity ledger."
	return ""
