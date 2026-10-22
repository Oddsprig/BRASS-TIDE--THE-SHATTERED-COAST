extends RefCounted
const Ops=preload("res://scripts/tooling_ops.gd")
const Tooling=preload("res://scripts/industrial_tooling.gd")
const Yard=preload("res://scripts/yard_development.gd")
const Home=preload("res://scripts/home_harbor.gd")
const Politics=preload("res://scripts/politics.gd")

static func act(ui,action: String,a: String="",b: String="") -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var result: Dictionary=c.fail("Unknown machinery action.")
	match action:
		"begin":result=Ops.begin(c,a,b)
		"claim":result=Ops.claim(c)
		"recall":result=Ops.cancel(c)
		"recipe":result=Ops.recipe(c,a,b)
		"cancel_batch":result=Ops.cancel_batch(c,a)
		"hire":result=Ops.staff(c,a,b,true)
		"dismiss":result=Ops.staff(c,a,b,false)
		"capital":result=Home.capital(c,a,1000)
		"bay":result=Yard.begin(c,a)
		"install","remove":
			var permission: Dictionary=Politics.permit(c,"service")
			result=permission
			if permission.ok:result=Tooling.install(c,a,b) if action=="install" else Tooling.remove(c,a)
	ui.host.respond(result)
	c.Manifest.allocate(c.state)
	if result.ok:ui.host.save_game(false)
	open(ui)

static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	Ops.ensure(c);Yard.ensure(c);c.HomeOps.ensure(c)
	ui.modal_kind="industrial_tooling"
	var body=ui.modal("Recovered machinery & workshops","RECOVER · TRANSPORT · RESTORE · STAFF",1120,850)
	ui.paragraph(body,"Machinery is a finite physical item. A surveyed source needs two spare sailors, actual elapsed recovery days and repair kits. Normal crew payroll pays those sailors once. Carry the item home, install it in a paid workshop and maintain it; every recipe still needs actual staff and ingredients.",16)
	var recovery: Dictionary=c.state.toolingRecovery
	if not recovery.is_empty():
		ui.label(body,"Recovery party ashore",24,ui.GOLD,true)
		ui.paragraph(body,"%s · ready after day %.2f · %s / %s coins of ordinary recovery crew wages earned"%[str(recovery.kind).replace("_"," ").capitalize(),float(recovery.readyAt),ui.money(int(recovery.paid)),ui.money(int(recovery.workerDays)*100)],16)
		ui.paragraph(body,"Close this panel and let campaign time run while remaining near the source. Boats must keep their minimum crews. Sufficient paid work and actual elapsed days are both required.",14)
		ui.button(body,"Claim completed machinery",func():act(ui,"claim"))
		ui.button(body,"Recall recovery party",func():act(ui,"recall"))
	ui.rule(body)
	ui.label(body,"Surveyed industrial leads",24,ui.GOLD,true)
	var leads: int=0
	for site_id in Ops.Sources:
		if int(c.state.exploration.sites.get(site_id,{}).get("level",0))<3:continue
		leads+=1
		var id: String=site_id
		var source: Dictionary=Ops.Sources[id]
		var kind: String=source.kind
		var site: Dictionary=c.Exploration.catalog_site(c.state,id)
		var extracted: bool=c.state.tooling.extracted.has(source.sourceId)
		ui.paragraph(body,"%s · %s · %d days · %.1f kits · %.0f hold space"%[str(site.name),str(Tooling.KINDS[kind].name),int(Tooling.KINDS[kind].recoveryDays),float(Tooling.KINDS[kind].recoveryDays)*0.5,float(Tooling.KINDS[kind].weight)],16,ui.TEAL)
		if extracted:ui.paragraph(body,"This source has already been extracted.",14,ui.MUTED)
		else:ui.button(body,"Land recovery party",func():act(ui,"begin",id,kind)).disabled=c.distance(c.state.position,site)>450 or not recovery.is_empty()
	if leads==0:ui.paragraph(body,"Fully survey abandoned workshops and salvage anchorages to identify recoverable equipment.",15)
	ui.rule(body)
	ui.label(body,"Your machinery",24,ui.GOLD,true)
	if c.state.tooling.items.is_empty():ui.paragraph(body,"No machinery recovered yet.",15,ui.MUTED)
	for item in Tooling.list_items(c):
		var id: String=item.id
		ui.paragraph(body,"%s · %s · %d%% condition · %s"%[str(Tooling.KINDS[item.kind].name),str(item.location).capitalize(),roundi(float(item.condition)*100),id],18,ui.GOLD)
		if item.location=="commissioning":ui.paragraph(body,"Paid installation team reserved until day %.2f."%float(item.readyAt),14)
		if item.location in ["commissioning","active"]:
			ui.button(body,"Remove / cancel installation; keep costs spent",func():act(ui,"remove",id))
		elif item.location=="cargo":
			for b in c.state.businesses:
				var business_id: String=b.id
				var q: Dictionary=Tooling.quote_install(c,id,business_id)
				if q.ok:
					ui.paragraph(body,"%s: %s materials + %s worker wages + %s oversight/trade wages = %s coins · %d commissioning days"%[str(b.name),ui.money(int(q.materialCoins)),ui.money(int(q.householdCoins)),ui.money(int(q.expertCoins)),ui.money(int(q.totalCoins)),int(q.commissioningDays)],14)
					ui.button(body,"Install at "+str(b.name),func():act(ui,"install",id,business_id))
		elif item.location=="lost":ui.paragraph(body,"Lost with its carrier. Its source remains spent.",14,ui.RED)
	ui.rule(body)
	ui.label(body,"Owned workshops",24,ui.GOLD,true)
	for b in c.state.businesses:
		if b.kind!="workshop":continue
		var business_id: String=b.id
		ui.paragraph(body,"%s at %s · %s coins · %d staff · %d coins/day · %s"%[str(b.name),str(c.port(b.homePort).name),ui.money(int(b.coins)),b.employees.size(),int(b.dailyWages),str(b.get("recipeGood","supplies"))],17,ui.TEAL)
		if c.current_port().get("id","")!=b.homePort:
			ui.paragraph(body,"Visit the actual home harbor to change staff, recipe, capital or equipment.",14);continue
		ui.button(body,"Add 1,000 coins of operating capital",func():act(ui,"capital",business_id))
		if float(b.get("productionProgress",0))>0:ui.button(body,"Cancel unfinished paid batch",func():act(ui,"cancel_batch",business_id))
		var recipes=ui.row(body)
		for recipe_id in Ops.RECIPES:
			var good: String=recipe_id
			ui.button(recipes,str(c.Economy.GOODS[good].name),func():act(ui,"recipe",business_id,good))
		for trade_id in ["carpenter","mechanic","engineer","gunsmith"]:
			var trade: String=trade_id
			var row=ui.row(body)
			ui.button(row,"Hire "+trade+" · 88 coins oversight",func():act(ui,"hire",business_id,trade))
			ui.button(row,"Discharge "+trade,func():act(ui,"dismiss",business_id,trade))
		var q: Dictionary=Yard.quote(c,business_id)
		ui.paragraph(body,str(q.message),14)
		if q.ok:ui.button(body,"Fund extra chartered drydock bay · %s coins"%ui.money(int(q.cost)),func():act(ui,"bay",business_id))
	for project in c.state.yardProjects:
		ui.paragraph(body,"%s: drydock %s · %.1f / 5 days · %s coins held"%[str(c.port(project.portId).name),str(project.status),float(project.progress),ui.money(int(project.escrow))],14)
	ui.button(body,"Close",ui.close_modal,true)
