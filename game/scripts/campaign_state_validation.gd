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
	return ""
