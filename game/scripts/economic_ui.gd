extends RefCounted
## Paid harbor work: one place to follow people, costs and opportunities.
const Training=preload("res://scripts/crew_training.gd")
const Ops=preload("res://scripts/training_ops.gd")

static func act(ui,action: String,count: int=1,role: String="sailor",id: String="") -> void:
	ui.host.sync_economy()
	var result: Dictionary=Ops.enroll(ui.host.core,count,role) if action=="enroll" else Ops.cancel(ui.host.core,id)
	ui.host.respond(result)
	if result.ok:ui.host.save_game(false)
	open(ui)

static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var p: Dictionary=c.current_port()
	if p.is_empty():
		ui.toast("Visit a harbor to arrange training.",true)
		return
	Ops.ensure(c)
	ui.modal_kind="economic_workforce"
	var body=ui.modal("Crew training & harbor workforce","EXISTING PEOPLE · PAID TIME · REAL SUPPLIES",1020,800)
	ui.paragraph(body,"A sailor earns 100 coins per day. Training pays trainees and an instructor, buys provisions and supplies, and reserves local people away from other work. Experienced sailors remain useful; no crew animation is needed.",16)
	ui.label(body,p.name,25,ui.GOLD,true)
	ui.paragraph(body,"%d civilian workers · %d currently available · %d recruitment volunteers"%[int(p.workforce),int(p.availableWorkers),int(p.recruits)],16,ui.TEAL)
	var r: Dictionary=Training.report(p)
	var qualified: Dictionary=r.get("qualified",{})
	ui.paragraph(body,"Qualified sailors: %d · Gunners: %d · Mechanics: %d · Boarders: %d"%[int(qualified.get("sailor",0)),int(qualified.get("gunner",0)),int(qualified.get("mechanic",0)),int(qualified.get("boarder",0))],17,ui.GOLD)
	for role_id in ["sailor","gunner","mechanic","boarder"]:
		var role: String=role_id
		ui.rule(body)
		ui.label(body,role.capitalize()+" training",22,ui.GOLD,true)
		for number in [1,3,5]:
			var count: int=number
			var q: Dictionary=Training.quote(p,count,role)
			ui.paragraph(body,str(q.get("message","Training quote unavailable.")),14)
			var caption: String="Train %d · %s coins"%[count,ui.money(int(q.get("cost",0)))]
			ui.button(body,caption,func():act(ui,"enroll",count,role)).disabled=not q.get("ok",false) or c.state.coins<int(q.get("cost",0))
	ui.rule(body)
	ui.label(body,"Training accounts",24,ui.GOLD,true)
	var jobs: Array=r.get("jobs",[])
	if jobs.is_empty():ui.paragraph(body,"No current training account. Materials and wages are charged only when you commission a course.",15)
	for entry in jobs:
		var job: Dictionary=entry
		var id: String=str(job.get("id",""))
		ui.paragraph(body,"%s · %d people · %.1f / %.1f days · %s coins held"%[str(job.get("role","sailor")).capitalize(),int(job.get("count",0)),float(job.get("progress",0)),float(job.get("days",0)),ui.money(int(job.get("escrow",0)))],16)
		if job.get("paused",false):ui.paragraph(body,"Paused: "+str(job.get("reason","Resolve the account's funding or supply issue.")),14,ui.RED)
		ui.button(body,"Cancel; return people and unspent wages",func():act(ui,"cancel",1,"sailor",id))
	ui.button(body,"Back to harbor",func():ui.open_port("Crew & repairs"),true)
