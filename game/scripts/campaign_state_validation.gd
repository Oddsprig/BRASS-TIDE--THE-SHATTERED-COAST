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
	return ""
