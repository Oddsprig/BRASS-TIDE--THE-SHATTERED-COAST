extends RefCounted
const Ops=preload("res://scripts/worker_ops.gd")
const Conditions=preload("res://scripts/worker_conditions.gd")
static func act(ui,id: String,mode: String) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var result: Dictionary=Ops.negotiate(c,id) if mode=="negotiate" else Ops.policy(c,id,mode)
	ui.host.respond(result)
	if result.ok:ui.host.save_game(false)
	open(ui)
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	Ops.ensure(c)
	ui.modal_kind="worker_conditions"
	var body=ui.modal("People & working conditions","FOOD · PAY · PAID SHIFTS · RECOVERY",1080,800)
	ui.paragraph(body,"Food security records real purchases. Town health and unrest describe those facts. Your workplace policies use its actual staff, purse and private food; productive overtime is paid and fatigue needs elapsed rest.",16)
	for p in c.state.ports:
		var report: Dictionary=Conditions.report(p)
		ui.paragraph(body,str(p.name)+": "+str(report.get("summary",report.get("message","Awaiting facts"))),17,ui.TEAL)
		for reason in report.get("reasons",[]):ui.paragraph(body,str(reason),14,ui.MUTED)
	ui.rule(body)
	for b in c.state.businesses:
		var id: String=b.id
		var l: Dictionary=Conditions._labor(b)
		ui.label(body,str(b.name)+" · "+str(c.port(b.homePort).name),22,ui.GOLD,true)
		ui.paragraph(body,"%s · fatigue %d · unrest %d · %s coins in arrears · %s coins operating capital"%[str(l.policy).capitalize(),int(l.fatigue),int(l.unrest),ui.money(int(b.arrearsHousehold)+int(b.arrearsExpert)),ui.money(int(b.coins))],16)
		ui.paragraph(body,str(l.notice),15,ui.MUTED)
		ui.paragraph(body,"Overtime pays an extra half wage to every employee for up to25% more paid work. Default daily extra-spend cap:5,000 coins. Rest retains base payroll with no output. Food relief consumes one privately owned food per employee and uses10% preparation time.",14)
		if c.current_port().get("id","")!=b.homePort:
			ui.paragraph(body,"Visit this home harbor to set policy or negotiate.",14);continue
		var row=ui.row(body)
		for policy in ["normal","overtime","rest","relief"]:
			var mode: String=policy
			ui.button(row,mode.capitalize(),func():act(ui,id,mode))
		if l.striking:
			ui.paragraph(body,"Restart needs all recorded arrears,25 clerk and44 registry-foreman coins, one food per employee, one kit, and two later fully paid rest days. The actual paid public registry must have foreman time available.",15,ui.GOLD)
			ui.button(body,"Negotiate funded restart",func():act(ui,id,"negotiate"))
	if c.state.businesses.is_empty():ui.paragraph(body,"Establish a staffed shore business to direct its shifts.",16)
	ui.button(body,"Close",ui.close_modal,true)
