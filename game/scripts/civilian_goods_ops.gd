extends RefCounted
const Regional=preload("res://scripts/regional_goods.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")

static func prepare(saved: Dictionary) -> Dictionary:
	# A copied legacy snapshot gets only absent zero-valued commodity columns.
	# Existing stock and purses are preserved, including malformed values for
	# the normal read-only validator to reject.
	var copy: Dictionary=saved.duplicate(true)
	if copy.has("economyGoodsRevision"):return copy
	if copy.get("cargo") is Dictionary:fill(copy.cargo)
	for p in copy.get("ports",[]) if copy.get("ports") is Array else []:
		if not p is Dictionary:continue
		for key in ["stocks","publicStores"]:
			if p.get(key) is Dictionary:fill(p[key])
	for owner in copy.get("fleetOwners",[]) if copy.get("fleetOwners") is Array else []:
		if owner is Dictionary and owner.get("cargo") is Dictionary:fill(owner.cargo)
	copy.economyGoodsRevision=1
	return copy

static func fill(stock: Dictionary) -> void:
	for good in Regional.IDS:
		if not stock.has(good):stock[good]=0.0

static func ensure(c) -> void:
	if not c.state.has("economyGoodsRevision"):c.state.economyGoodsRevision=1
	fill(c.state.cargo)
	for p in c.state.ports:
		fill(p.stocks)
		if p.get("publicStores") is Dictionary:fill(p.publicStores)
		Regional.ensure(p)
	for owner in c.state.fleetOwners:fill(owner.cargo)

static func daily(p: Dictionary,days: float) -> void:
	var household_before: int=int(p.householdPurse)
	var expert_before: int=int(p.expertPurse)
	Regional.daily(p,days)
	var report: Dictionary=Regional.report(p)
	if report.has("error"):return
	for good in report.lastProduction:
		p.lastProduction[good]=float(report.lastProduction[good])/maxf(0.001,days)
		p.projectedProduction[good]=p.lastProduction[good]
	var regional_jobs: int=ceili(float(report.workersUsed))
	p.lastEmployed=mini(int(p.workforce),int(p.lastEmployed)+regional_jobs)
	p.lastPaid=mini(int(p.lastEmployed),int(p.lastPaid)+regional_jobs)
	p.employedWorkers=mini(int(p.workforce),int(p.employedWorkers)+regional_jobs)
	p.workers=p.employedWorkers
	p.lastPayroll.total+=int(report.lastWages)
	p.lastPayroll.business+=int(report.lastWages)
	var household_paid: int=int(p.householdPurse)-household_before+int(report.lastSpent)
	var expert_paid: int=int(p.expertPurse)-expert_before
	p.lastPayroll.household+=household_paid
	p.lastPayroll.expert+=expert_paid
	p.employedByOccupation=p.employed.duplicate(true)
	if int(report.lastWages)>0:
		Economy._append_ledger(p,{"type":"regional_payroll","from":"cash","to":"householdPurse+expertPurse","coins":int(report.lastWages),"household":household_paid,"expert":expert_paid})
	if int(report.lastSpent)>0:
		Economy._append_ledger(p,{"type":"regional_household_purchase","from":"householdPurse","to":"cash","coins":int(report.lastSpent),"goods":report.lastConsumption.duplicate(true)})
	# Household/expert deltas remain the actual payment facts in report; no
	# second money transfer or fabricated tax is applied by this adapter.

static func validate(state: Dictionary) -> String:
	if state.get("economyGoodsRevision",0)!=1:return "Unsupported civilian-goods revision."
	for p in state.ports:
		var error: String=Regional.validate(p)
		if not error.is_empty():return error
	return ""
