extends RefCounted
## Read-only presentation of an existing Workshop quote. No prices or live-state writes.
const Refits=preload("res://scripts/refit.gd")
const Deployment=preload("res://scripts/deployment.gd")

static func _value(number: float,places: int=1) -> String:
	if not is_finite(number):return "Unavailable"
	return ("%.0f"%number) if places==0 else (("%.2f"%number) if places==2 else ("%.1f"%number))

static func _row(label: String,before: float,after: float,places: int=1,unit: String="") -> Dictionary:
	var change: float=after-before
	var changed: bool=absf(change)>0.00001
	var delta: String=("+" if change>0 else "")+_value(change,places)+unit if changed else "Unchanged"
	return {"label":label,"before":_value(before,places)+unit,"after":_value(after,places)+unit,"delta":delta,"changed":changed}

static func stat_rows(base: Dictionary,quote: Dictionary) -> Array:
	if not bool(quote.get("validDraft",false)) or quote.get("beforeSpec",{}).is_empty() or quote.get("afterSpec",{}).is_empty():return []
	var before: Dictionary=quote.beforeSpec
	var after: Dictionary=quote.afterSpec
	var old_fit: Dictionary=Refits.normalize(base,quote.get("beforeLoadout",{}))
	var rows: Array=[_row("Fitting capacity / %d"%int(quote.maxPoints),float(old_fit.get("usedPoints",0)),float(quote.usedPoints),0),_row("Battle deployment",Deployment.cost(before),Deployment.cost(after),0," DP")]
	for item in [["Speed","speed",1,""],["Turn rate","turn",2," rad/s"],["Hull protection","armor",1,""],["Integral pump capacity","pumps",1,""],["Hold space","cargo",0,""],["Berths","crewMax",0,""],["Ammo rack capacity","ammoCapacity",0," rounds"],["Fuel consumption","fuelUse",2,"x"]]:
		rows.append(_row(str(item[0]),float(before.get(item[1],0)),float(after.get(item[1],0)),int(item[2]),str(item[3])))
	if float(before.get("turn",0))>0 and float(after.get("turn",0))>0:
		rows.append(_row("180-degree turn, minimum",PI/float(before.turn),PI/float(after.turn),2," s"))
	var reserve: Dictionary=quote.get("reserve",{})
	if not reserve.is_empty():
		for item in [["Fleet working-fuel endurance","fuelDays",1," days"],["Fleet free hold","freeCapacity",1,""],["Fleet payroll","dailyWages",0," coins/day"]]:
			rows.append(_row(str(item[0]),float(reserve.before.get(item[1],0)),float(reserve.after.get(item[1],0)),int(item[2]),str(item[3])))
	return rows

static func headline(quote: Dictionary) -> String:
	if not quote.get("validDraft",false) or quote.get("beforeSpec",{}).is_empty() or quote.get("afterSpec",{}).is_empty():return ""
	var lines: Array[String]=[]
	for item in [["Speed","speed",1],["Armor","armor",1],["Fuel use","fuelUse",2]]:
		var row: Dictionary=_row(str(item[0]),float(quote.beforeSpec.get(item[1],0)),float(quote.afterSpec.get(item[1],0)),int(item[2]),"x" if item[1]=="fuelUse" else "")
		lines.append("%s %s → %s (%s)"%[row.label,row.before,row.after,row.delta])
	return " | ".join(lines)

static func mount(spec: Dictionary,socket_id: String) -> Dictionary:
	for weapon in spec.get("weaponMounts",[]):
		if str(weapon.get("id",""))==socket_id:return weapon.duplicate(true)
	return {}

static func _mount_value(weapon: Dictionary,key: String) -> float:
	if key=="reload":return 1.0/maxf(0.000001,float(weapon.get("fireRate",0)))
	if key in ["arc","angle"]:return rad_to_deg(float(weapon.get(key,0)))
	return float(weapon.get(key,0))

static func mount_rows(before: Dictionary,after: Dictionary,socket_id: String,rounds: float) -> Array:
	var old: Dictionary=mount(before,socket_id)
	var next: Dictionary=mount(after,socket_id)
	var rows: Array=[]
	for item in [["Range","range",0,""],["Stated reload","reload",2," s"],["Firing arc","arc",0," deg"],["Mount bearing","angle",0," deg"],["Rounds per shot","ammoCost",0,""]]:
		var row: Dictionary=_row(str(item[0]),_mount_value(old,str(item[1])),_mount_value(next,str(item[1])),int(item[2]),str(item[3]))
		if old.is_empty():row.before="Empty"
		if next.is_empty():row.after="Empty"
		if old.is_empty() or next.is_empty():
			row.delta="Equipped" if old.is_empty() and not next.is_empty() else ("Removed" if not old.is_empty() else "Unchanged")
			row.changed=old.is_empty()!=next.is_empty()
		rows.append(row)
	var shots: Dictionary=_row("Shots from shared rounds, alone",floor(maxf(0,rounds)/maxf(1,float(old.get("ammoCost",1)))),floor(maxf(0,rounds)/maxf(1,float(next.get("ammoCost",1)))),0)
	if old.is_empty():shots.before="Empty"
	if next.is_empty():shots.after="Empty"
	if old.is_empty() or next.is_empty():
		shots.delta="-";shots.changed=old.is_empty()!=next.is_empty()
	rows.append(shots)
	return rows

static func compatibility(base: Dictionary,socket: Dictionary,module_id: String) -> String:
	if module_id.is_empty():return "Empty: no weapon fires from this position."
	var catalog: Dictionary=Refits.catalog().weapons
	if not catalog.has(module_id):return "Unknown weapon: choose a catalog module."
	var item: Dictionary=catalog[module_id]
	var first: Dictionary=Refits.hardpoints(base)[0]
	if module_id=="stock_primary" and str(first.id)!=str(socket.id):return "Original primary belongs in the main socket only."
	if int(item.size)>int(socket.size):return "Too large: size %d weapon, size %d socket."%[int(item.size),int(socket.size)]
	return "Fits this size %d socket; %d fitting points. The whole fit must also fit its budget."%[int(socket.size),int(item.op)]

static func mount_summary(spec: Dictionary,socket: Dictionary) -> String:
	var weapon: Dictionary=mount(spec,str(socket.id))
	if weapon.is_empty():return "Empty socket: no weapon fires here."
	return "%s | range %.0f | %.2f s stated reload | %d rounds/shot\n%.0f-degree arc | bearing %.0f degrees%s"%[str(weapon.kind).capitalize(),float(weapon.range),1.0/maxf(0.000001,float(weapon.fireRate)),int(weapon.ammoCost),rad_to_deg(float(weapon.arc)),rad_to_deg(float(weapon.angle))," | fixed launcher: hull must aim" if str(weapon.kind) in ["rocket","torpedo"] and str(weapon.get("moduleId",""))!="stock_primary" else ""]

static func basis() -> String:
	return "Fit values include this boat's morale, specialists and support conversion. Damage, wounded crew, flooding, heat, traverse and safe firing lanes can reduce live performance. Reload is the stated cadence, not a promise of continuous hits. The turn minimum uses the stated turn rate and excludes braking or acceleration."

static func stores_text(ship: Dictionary) -> String:
	return "Existing working stores: %.0f shared rounds | %.1f fuel | %.1f repair kits. A larger rack buys no ammunition. Shots shown assume this mount alone spends the shared pool; other guns compete for it. Fuel endurance is the fleet's existing harbor planning allowance, with no onward route selected. Fitting buys no stores or crew."%[float(ship.get("ammo",0)),float(ship.get("fuel",0)),float(ship.get("supplies",0))]

static func control_limit() -> String:
	return "Automatic weapon groups, hold fire and round reserves last for one battle. Try this draft in the Lab, then open Selected tactics & weapon groups for the real controls. Fitting templates save weapons, engine and armor; they do not save battle fire orders. Integral pumps stay with the hull; their condition and the crew's real repair kits still govern damage control."
