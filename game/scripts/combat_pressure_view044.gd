extends RefCounted
## Read-only words for the existing selected-boat HUD. No timers or state retained.
const Damage = preload("res://scripts/damage.gd")
const EquipmentCombat = preload("res://scripts/equipment_combat.gd")

static func selection(battle: Dictionary, ids: Array) -> Dictionary:
	# Preserve selection order; the borrowed boat is for synchronous reading only.
	var first: Dictionary={}
	var count: int=0
	var seen: Dictionary={}
	for raw_id in ids:
		var id: String=str(raw_id)
		if seen.has(id):continue
		seen[id]=true
		for boat in battle.get("ships",[]):
			if str(boat.id)!=id or boat.team!="player" or boat.sunk or boat.get("captureSecured",false):continue
			if first.is_empty():first=boat
			count+=1
			break
	return {"boat":first,"count":count}

static func readiness(boat: Dictionary, flow: Dictionary) -> Array:
	if not bool(flow.get("equipmentOk",false)):
		return ["Damage control unavailable"]
	var water: float=Damage.number(boat.get("water"))
	var net: float=Damage.number(flow.get("inflow"))-Damage.number(flow.get("bailing"))
	var trend: String="steady"
	if net>0.0:trend="rising %.1f L/s"%net
	elif water>0.0 and net<0.0:trend="draining %.1f L/s"%(-net)
	elif water<=0.0:trend="dry"
	var engine: String="Engine %.0f%%"%(100.0*Damage.number(flow.get("engineHp")))
	if Damage.number(flow.get("engineFactor"))<=0.0:engine+=" disabled"
	var fuel: float=Damage.number(boat.get("fuel"))
	engine+=(" · fuel %.1f"%fuel if fuel>0.0 else " · NO FUEL")
	var repair: String="Repair %.1f hands"%Damage.number(flow.get("crewRepair"))
	var kits: float=Damage.number(boat.get("supplies"))
	repair+=(" · kits %.1f"%kits if kits>0.0 else " · NO KITS")
	var lines: Array=["Water %.0f%% · %s"%[water/maxf(1.0,Damage.number(boat.get("capacity")))*100.0,trend],engine,repair]
	if Damage.number(boat.get("fire"))>0.0:lines.append("Fire %.0f%%"%Damage.number(boat.get("fire")))
	return lines

static func weapon_state(boat: Dictionary, mount: Dictionary, index: int, flow: Dictionary, reason: String) -> String:
	# These are the current Battle firing prerequisites, not a new firing decision.
	if not bool(flow.get("equipmentOk",false)):return "Weapon status unavailable"
	if EquipmentCombat.mount_factor(boat,mount,index,flow)<=0.01 or Damage.number(mount.get("damage"))<=0.0:return "Weapon disabled"
	if Damage.number(boat.get("ammo"))<Damage.number(mount.get("ammoCost")):return "No ammo"
	if Damage.number(flow.get("weaponFactor"))<=0.01:return "No gun crew"
	var timers: Array=boat.get("weaponCooldowns",[]) if boat.get("weaponCooldowns") is Array else []
	var remaining: float=Damage.number(timers[index],NAN) if index>=0 and index<timers.size() else NAN
	if index==0:
		var primary: float=Damage.number(boat.get("cooldown"),NAN)
		if is_finite(primary):remaining=maxf(primary,remaining) if is_finite(remaining) else primary
	if not is_finite(remaining) or remaining<0.0:return "Reload unavailable"
	if remaining>0.0:
		return ("Reload %.1fs"%remaining)+(" · "+reason if not reason.is_empty() and reason!="Reloading" else "")
	# A tactical reason can still describe the preceding simulation step. An expired
	# timer proves only reload completion, never range, aim, reserve or a clear lane.
	return "Loaded · "+("waiting for shot" if reason.is_empty() or reason=="Reloading" else reason)
