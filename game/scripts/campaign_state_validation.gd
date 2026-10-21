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
	return ""
