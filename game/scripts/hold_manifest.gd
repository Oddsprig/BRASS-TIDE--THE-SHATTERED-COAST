extends RefCounted
## Cargo is authoritative in state.cargo; this manifest assigns its real carriers.
const Goods=preload("res://scripts/goods.gd")

static func carriers(state: Dictionary) -> Array:
	return state.get("fleet",[]).filter(func(b):return not b.get("sunk",false) and not b.get("mothballed",false) and str(b.get("storedPort","")).is_empty() and float(b.get("crew",0))>=float(b.get("crewMin",1)))

static func allocate(state: Dictionary) -> void:
	var boats: Array=carriers(state)
	var manifest: Dictionary={}
	var free: Dictionary={}
	for b in boats:
		manifest[b.uid]={}
		free[b.uid]=float(b.spec.cargo)
	var load: Dictionary=state.get("cargo",{}).duplicate(true)
	var freight: Dictionary=state.get("freight",{})
	if not freight.is_empty():load["@freight"]=float(freight.get("qty",0))
	var keys: Array=load.keys()
	keys.sort()
	for good in keys:
		var weight: float=float(Goods.ITEMS.get(freight.get("good","") if good=="@freight" else good,{"weight":1}).weight)
		var left: float=float(load[good])
		for b in boats:
			var qty: float=minf(left,maxf(0,free[b.uid])/maxf(0.01,weight))
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
			if good=="@freight":
				state.freight.qty=maxf(0,float(state.freight.get("qty",0))-qty)
				state.freight.lost=true
			else:state.cargo[good]=maxf(0,float(state.cargo.get(good,0))-qty)
			lost.append({"boat":b.name,"good":good,"qty":qty})
		manifest.erase(b.get("uid",""))
	return lost
