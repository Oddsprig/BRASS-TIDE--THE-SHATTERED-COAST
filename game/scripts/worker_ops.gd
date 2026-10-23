extends RefCounted
const Conditions=preload("res://scripts/worker_conditions.gd")
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const Politics=preload("res://scripts/politics.gd")

class ShiftContext:
	extends RefCounted
	var state: Dictionary
	func _init(current: Dictionary):
		# The campaign increments its counter after this completed daily step.
		# Containers remain actual references; only the processing stamp differs.
		state=current.duplicate(false)
		state.econDay=int(current.econDay)+1

static func step(c,b: Dictionary,p: Dictionary) -> Dictionary:
	return Conditions.business_step(ShiftContext.new(c.state),b,p,1.0)

static func ensure(c) -> void:
	Conditions.configure(Money.move,Goods.WAGES,Goods.ITEMS.keys(),"food","supplies",service_access)
	for p in c.state.ports:Conditions.ensure(p)

static func service_access(c,b: Dictionary,p: Dictionary) -> Dictionary:
	var here: Dictionary=c.current_port()
	var allowed: bool=here.get("id","")==b.homePort and c.state.path.is_empty() and Politics.permit(c,"service").ok
	# Public payroll explicitly records the existing registry foreman cohort.
	# It is already outside industrial availability; quarter-day case bookings
	# cannot allocate those same people to another public case today.
	var conditions: Dictionary=p.get("conditions",{})
	var booked: float=float(conditions.get("workerQ",0))*0.25 if int(conditions.get("serviceDay",-1))==int(c.state.econDay) else 0.0
	return {"allowed":allowed,"workers":maxi(0,floori(float(p.availableWorkers)-float(p.get("_yardWorkersUsed",0))+booked)),"foremen":maxi(0,int(p.get("publicForemen",0)))}

static func policy(c,id: String,mode: String,cap: int=5000) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	for b in c.state.businesses:
		if b.id==id:
			if c.current_port().id!=b.homePort:return c.fail("Visit this business's actual home harbor.")
			return Conditions.set_policy(c,id,{"policy":mode,"cap":cap})
	return c.fail("Unknown owned business.")

static func account_materials(b: Dictionary,before: Dictionary) -> void:
	var home_api: Script=load("res://scripts/home_harbor.gd")
	for good in ["food","supplies"]:
		var consumed: float=maxf(0,float(before.get(good,0))-float(b.inventory.get(good,0)))
		if consumed<=0:continue
		# Basis allocation uses the opening quantity before recording consumption.
		var current: float=float(b.inventory.get(good,0))
		b.inventory[good]=current+consumed
		b.otherExpenses=int(b.get("otherExpenses",0))+ceili(home_api._take_basis(b,good,consumed))
		b.inventory[good]=current

static func negotiate(c,id: String) -> Dictionary:
	ensure(c)
	for b in c.state.businesses:
		if b.id!=id:continue
		var before: Dictionary=b.inventory.duplicate(true)
		var result: Dictionary=Conditions.negotiate(c,id)
		if result.ok:
			account_materials(b,before)
			var p: Dictionary=c.port(b.homePort)
			p._yardWorkersUsed=float(p.get("_yardWorkersUsed",0))+0.25
		return result
	return c.fail("Unknown owned business.")

static func validate(state: Dictionary,world: Dictionary) -> String:
	for p in state.ports:
		if p.has("publicForemen") and not Conditions._whole(p.publicForemen,int(p.get("publicWorkers",0))):return "Invalid paid registry foreman cohort."
	for b in state.get("businesses",[]):
		if b.has("workFactor") and not Conditions._num(b.workFactor,0,1.25):return "Invalid paid workplace factor."
	var registry: Dictionary={}
	for b in state.get("businesses",[]):
		var suffix: String=str(b.id).trim_prefix("business-")
		if not str(b.id).begins_with("business-") or not suffix.is_valid_int() or int(suffix)<1 or int(suffix)>int(state.get("businessSeq",0)) or str(int(suffix))!=suffix:return "Noncanonical owned workplace identity."
		registry[b.id]=b.homePort
	return Conditions.validate_state(state,{"ports":state.ports,"businessHomes":registry})
