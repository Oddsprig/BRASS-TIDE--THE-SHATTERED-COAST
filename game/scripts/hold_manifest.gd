extends RefCounted
## Cargo is authoritative in state.cargo; this manifest assigns its real carriers.
const Tooling=preload("res://scripts/industrial_tooling.gd")
const Goods=preload("res://scripts/goods.gd")
const Expedition=preload("res://scripts/expedition.gd")

static func carriers(state: Dictionary) -> Array:
	return state.get("fleet",[]).filter(func(b):return not b.get("sunk",false) and not b.get("mothballed",false) and not b.get("needsHarborRepair",false) and str(b.get("storedPort","")).is_empty() and float(b.get("crew",0))>=float(b.get("crewMin",1)))

static func allocate(state: Dictionary) -> void:
	var boats: Array=carriers(state)
	var manifest: Dictionary={}
	var free: Dictionary={}
	for b in boats:
		manifest[b.uid]={}
		free[b.uid]=maxf(0,float(b.spec.cargo)-Expedition.store_overflow(b)-maxf(0,float(state.get("captiveBerths",{}).get(str(b.uid),0))-maxf(0,float(b.crewMax)-float(b.crew))))
	var load: Dictionary=state.get("cargo",{}).duplicate(true)
	var freight: Dictionary=state.get("freight",{})
	if not freight.is_empty():load["@freight"]=float(freight.get("qty",0))
	var job_goods: Dictionary={}
	for job in state.get("voyageJobs",[]):
		var lot: Dictionary=job.get("freight",{})
		if not lot.is_empty():
			var key: String="@job:"+str(job.id)
			load[key]=float(lot.get("qty",0))
			job_goods[key]=str(lot.get("good",""))
	var tool_weights: Dictionary={}
	for item in state.get("tooling",{}).get("items",[]):
		if item.get("location","")=="cargo":
			var key: String="@tool:"+str(item.id)
			load[key]=1;tool_weights[key]=float(Tooling.KINDS[item.kind].weight)
	var keys: Array=load.keys()
	keys.sort()
	for good in keys:
		var material: String=str(freight.get("good","")) if good=="@freight" else str(job_goods.get(good,good))
		var weight: float=float(tool_weights.get(good,Goods.ITEMS.get(material,{"weight":1}).weight))
		var left: float=float(load[good])
		for b in boats:
			var qty: float=minf(left,maxf(0,free[b.uid])/maxf(0.01,weight))
			if str(good).begins_with("@"):qty=floorf(qty)
			if qty<=0:continue
			manifest[b.uid][good]=qty
			free[b.uid]-=qty*weight
			left-=qty
			if left<0.00001:break
		if left>0.00001:manifest.get_or_add("unassigned",{})[good]=left
	state.cargoManifest=manifest

static func losses(state: Dictionary) -> Array:
	var lost: Array=[]
	var manifest: Dictionary=state.get("cargoManifest",{})
	for b in state.get("fleet",[]):
		if not b.get("sunk",false):continue
		var cargo: Dictionary=manifest.get(b.get("uid",""),{})
		for good in cargo:
			var qty: float=float(cargo[good])
			if str(good).begins_with("@tool:"):
				for item in state.get("tooling",{}).get("items",[]):
					if item.id==str(good).trim_prefix("@tool:"):item.location="lost"
			elif good=="@freight":
				state.freight.qty=maxf(0,float(state.freight.get("qty",0))-qty)
				state.freight.lost=true
			elif str(good).begins_with("@job:"):
				var id: String=str(good).trim_prefix("@job:")
				for job in state.get("voyageJobs",[]):
					if job.id==id:
						job.freight.qty=maxf(0,float(job.freight.get("qty",0))-qty)
						job.freight.lost=true;job.failed=true
			else:state.cargo[good]=maxf(0,float(state.cargo.get(good,0))-qty)
			lost.append({"boat":b.name,"good":good,"qty":qty})
		manifest.erase(b.get("uid",""))
	return lost
