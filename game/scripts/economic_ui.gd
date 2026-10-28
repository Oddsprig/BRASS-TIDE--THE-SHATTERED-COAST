extends RefCounted
## Paid harbor work: one place to follow people, costs and opportunities.
const Training=preload("res://scripts/crew_training.gd")
const Ops=preload("res://scripts/training_ops.gd")
const Service=preload("res://scripts/equipment_service.gd")
const Politics=preload("res://scripts/politics.gd")

## One detached local account; normalizing quotes never touch the live harbor.
static func review(c,count: int=1) -> Dictionary:
	var snapshot: Dictionary=c.state.duplicate(true)
	var port_id: String=str(c.current_port().get("id",""))
	var p: Dictionary={}
	for candidate in snapshot.get("ports",[]):
		if str(candidate.id)==port_id:p=candidate;break
	if p.is_empty():return {}
	var view=Service.DetachedCampaignView.new(snapshot,c.data,p)
	var permission: Dictionary=Politics.permit(view,"service")
	var report: Dictionary=Training.report(p)
	var offers: Array=[]
	for role in ["sailor","gunner","mechanic","boarder"]:
		var q: Dictionary=Training.quote(p,count,role)
		q.allowed=bool(q.get("ok",false)) and permission.ok and int(snapshot.coins)>=int(q.get("cost",0))
		offers.append(q)
	return {"port":p,"report":report,"offers":offers,"permission":permission,"coins":int(snapshot.coins),"day":float(snapshot.day)}

static func act(ui,action: String,count: int=1,role: String="sailor",id: String="") -> void:
	ui.host.sync_economy()
	var result: Dictionary=Ops.enroll(ui.host.core,count,role) if action=="enroll" else Ops.cancel(ui.host.core,id)
	ui.host.respond(result)
	if result.ok:ui.host.save_game(false)
	open(ui)

static func open(ui,count: int=1) -> void:
	var c=ui.host.core
	var account: Dictionary=review(c,count)
	if account.is_empty():
		ui.toast("Visit a harbor to arrange training.",true)
		return
	var p: Dictionary=account.port
	ui.modal_kind="economic_workforce"
	var body=ui.modal("Crew training & harbor workforce","EXISTING PEOPLE · PAID TIME · REAL SUPPLIES",1020,800)
	ui.paragraph(body,"A sailor earns 100 coins per day. Courses reserve existing trainees and one instructor, buy real supplies, and hold wages in escrow. Qualifications make local people eligible to recruit; they add no people or boat experience.",15)
	ui.label(body,p.name,25,ui.GOLD,true)
	ui.paragraph(body,"Day %.1f account · %s coins available. Commissioning or cancellation refreshes and checks the harbor account."%[account.day,ui.money(account.coins)],14)
	ui.paragraph(body,"%d civilian workers · %d currently available · %d recruitment volunteers · %d available specialists"%[int(p.workforce),int(p.availableWorkers),int(p.recruits),int(p.get("availableSpecialists",0))],15,ui.TEAL)
	var r: Dictionary=account.report
	var qualified: Dictionary=r.get("qualified",{})
	ui.paragraph(body,"Recruitment eligibility: %d sailors, including %d gunners, %d mechanics and %d boarders. Specialist hiring can use sailor eligibility when its trade qualification is unavailable."%[int(qualified.get("sailor",0)),int(qualified.get("gunner",0)),int(qualified.get("mechanic",0)),int(qualified.get("boarder",0))],15,ui.GOLD)
	if not account.permission.ok:ui.paragraph(body,str(account.permission.message),14,ui.RED)
	var sizes=ui.row(body)
	ui.label(sizes,"Trainees per course",14)
	for number in [1,3,5]:
		var size: int=number
		ui.button(sizes,str(size),func():open(ui,size),size==count,false)
	for offer in account.offers:
		var q: Dictionary=offer
		var role: String=str(q.role)
		ui.rule(body)
		ui.label(body,role.capitalize()+" training",22,ui.GOLD,true)
		ui.paragraph(body,"%.0f days · %d reserved people (%d trainees + 1 instructor) · %.2f food + %.2f supplies"%[q.days,q.reservedWorkers,count,float(q.materials.food),float(q.materials.supplies)],14,ui.TEAL)
		ui.paragraph(body,str(q.get("message","Training quote unavailable.")),14)
		if int(account.coins)<int(q.cost):ui.paragraph(body,"Available coins do not cover this course.",14,ui.RED)
		ui.button(body,"Commission %d %s trainee%s · %s coins"%[count,role,"" if count==1 else "s",ui.money(int(q.cost))],func():act(ui,"enroll",count,role),false,false).disabled=not q.allowed
	ui.rule(body)
	ui.label(body,"Training accounts",24,ui.GOLD,true)
	ui.paragraph(body,"Cancellation returns reserved people and unspent wage escrow once. Earned wages, consumed materials, oversight, facility charges and duty stay spent.",14)
	var jobs: Array=r.get("jobs",[])
	if jobs.is_empty():ui.paragraph(body,"No current training account. Materials and wages are charged only when you commission a course.",15)
	for entry in jobs:
		var job: Dictionary=entry
		var id: String=str(job.get("id",""))
		ui.paragraph(body,"%s · %d trainees / %d reserved people · %.1f / %.1f days · %s unspent coins · %s wages earned"%[str(job.get("role","sailor")).capitalize(),int(job.get("count",0)),int(job.get("reservedWorkers",0)),float(job.get("progress",0)),float(job.get("days",0)),ui.money(int(job.get("escrow",0))),ui.money(int(job.get("traineePaid",0))+int(job.get("instructorPaid",0)))],15)
		if job.get("paused",false):ui.paragraph(body,"Paused: "+str(job.get("reason","Resolve the account's funding or supply issue.")),14,ui.RED)
		ui.button(body,"Cancel; return people and unspent wages",func():act(ui,"cancel",1,"sailor",id),false,false).disabled=not account.permission.ok
	ui.button(body,"Close review",ui.close_modal,true,false)
