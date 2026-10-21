extends RefCounted
const Home=preload("res://scripts/home_harbor.gd")
const Money=preload("res://scripts/money.gd")
## Two watch/maintenance worker-days per eight small berths: 25 wages + 3 registry coins.
const PUBLIC_SLOT_DAY: int=28
const PRIVATE_SLOTS: int=8
static func slots(b: Dictionary) -> int:
	return maxi(1,ceili(float(b.spec.get("size",14))/20.0))

static func ensure(c) -> void:
	Home.ensure(c.state)
	for b in c.state.fleet:
		if not b.has("berthArrears"):b.berthArrears=0

static func warehouse(c,port_id: String) -> Dictionary:
	for b in c.state.get("businesses",[]):
		if b.kind=="warehouse" and b.homePort==port_id and not b.paused:return b
	return {}

static func room(c,port_id: String) -> Dictionary:
	var private_used: int=0;var public_used: int=0
	for boat in c.state.fleet:
		if boat.get("storedPort","")!=port_id:continue
		if private_used+slots(boat)<=PRIVATE_SLOTS and not warehouse(c,port_id).is_empty():private_used+=slots(boat)
		else:public_used+=slots(boat)
	var p: Dictionary=c.port(port_id)
	return {"privateUsed":private_used,"publicUsed":public_used,"publicCapacity":maxi(0,int(p.get("publicWorkers",0))*4),"privateCapacity":PRIVATE_SLOTS if not warehouse(c,port_id).is_empty() else 0}

static func can_store(c,boat: Dictionary,p: Dictionary) -> Dictionary:
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	var r: Dictionary=room(c,p.id)
	if r.privateUsed+slots(boat)>r.privateCapacity and r.publicUsed+slots(boat)>r.publicCapacity:return c.fail("The actual harbor watch has no free berth slots. Use another port or establish a staffed warehouse.")
	return c.ok("Staffed private berth or public watch berth available.")

static func pay_arrears(c,uid: String) -> Dictionary:
	var boat: Dictionary=c.find_boat(uid)
	var p: Dictionary=c.current_port()
	if boat.is_empty() or p.is_empty() or str(boat.get("storedPort",""))!=str(p.id):return c.fail("Visit the harbor storing this boat to settle its berth account.")
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	var amount: int=int(boat.get("berthArrears",0))
	if amount<=0:return c.fail("No berth arrears are due.")
	if not Money.move(c.state,"coins",p,"governmentPurse",amount,"Public berth arrears",c.state.moneyLog):return c.fail("The berth account needs %d coins."%amount)
	boat.berthArrears=0
	return c.ok("Paid %d coins of berth arrears; the stored hull remains safe."%amount)

static func daily(c) -> void:
	ensure(c)
	for message in Home.tick(c,1):c.log_entry(str(message))
	var private_used: Dictionary={}
	for boat in c.state.fleet:
		var port_id: String=str(boat.get("storedPort",""))
		if boat.sunk or port_id.is_empty():continue
		var p: Dictionary=c.port(port_id)
		if p.is_empty():continue
		var used: int=int(private_used.get(port_id,0))
		if not warehouse(c,port_id).is_empty() and used+slots(boat)<=PRIVATE_SLOTS:
			boat.storageProvider="Staffed warehouse";private_used[port_id]=used+slots(boat)
			continue
		boat.storageProvider="Public harbor watch"
		var due: int=slots(boat)*PUBLIC_SLOT_DAY
		var paid: int=mini(int(c.state.coins),due)
		Money.move(c.state,"coins",p,"governmentPurse",paid,"Public berth watch and registry",c.state.moneyLog)
		boat.berthArrears=int(boat.get("berthArrears",0))+due-paid
		if paid<due:c.log_entry("%s berth short by %d coins. Hull held safely until its account is paid."%[boat.name,due-paid])
