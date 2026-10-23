extends RefCounted
## Paid cohort training. Qualified counts are eligibility subsets, never extra people.
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const Economy=preload("res://scripts/economy.gd")
const ROLES: Dictionary={
	"sailor":{"days":4.0,"instructor":"mechanic"},
	"gunner":{"days":6.0,"instructor":"gunsmith"},
	"mechanic":{"days":8.0,"instructor":"engineer"},
	"boarder":{"days":6.0,"instructor":"foreman"}
}
const MAX_JOBS: int=16
const MAX_PEOPLE: int=100

static func ensure(p: Dictionary) -> void:
	if p.get("training") is Dictionary:return
	var eligible: int=mini(int(p.get("workforce",0)),int(p.get("recruits",0)))
	p.training={"schema":1,"nextId":0,"qualified":{"sailor":maxi(0,eligible),"gunner":0,"mechanic":0,"boarder":0},"jobs":[]}

static func quote(p: Dictionary,count: int,role: String="sailor") -> Dictionary:
	ensure(p)
	if not ROLES.has(role) or count<1 or count>MAX_PEOPLE:return {"ok":false,"message":"Choose a course for 1–100 existing workers."}
	var r: Dictionary=ROLES[role]
	var days: float=float(r.days)
	var ordinary: int=count+1 # trainees plus one reserved instructor
	var unqualified: int=maxi(0,int(p.workforce)-int(p.training.qualified.sailor))
	var free: int=maxi(0,int(p.get("availableWorkers",0))-ceili(float(p.get("_yardWorkersUsed",0))))
	var experts: int=maxi(0,int(p.get("availableSpecialists",0))-ceili(float(p.get("_yardSpecialistsUsed",0))))
	var food: float=snappedf(float(ordinary)*0.08*days,0.01)
	var kits: float=snappedf(float(count)*0.25*days,0.01)
	var materials: Dictionary={"food":food,"supplies":kits}
	var material_cost: int=ceili(food*Economy.price(p,"food"))+ceili(kits*Economy.price(p,"supplies"))
	var trainee_wages: int=ceili(float(count)*days*Goods.SAILOR_WAGE)
	var instructor_wages: int=ceili(days*int(Goods.WAGES[str(r.instructor)]))
	var oversight: int=ceili(0.25*int(Goods.WAGES.foreman))
	var margin: int=ceili(float(material_cost+trainee_wages+instructor_wages+oversight)*0.08)
	var duty: int=ceili(float(material_cost+trainee_wages+instructor_wages+oversight)*0.05)
	var total: int=material_cost+trainee_wages+instructor_wages+oversight+margin+duty
	var q: Dictionary={"ok":true,"role":role,"count":count,"days":days,"cost":total,"materials":materials,"materialCost":material_cost,"traineeWages":trainee_wages,"instructorWages":instructor_wages,"oversight":oversight,"margin":margin,"duty":duty,"reservedWorkers":ordinary,"message":"%d %s trainees · %.0f days · %d materials + %d trainee pay + %d instruction + %d oversight + %d facility + %d duty = %d coins."%[count,role,days,material_cost,trainee_wages,instructor_wages,oversight,margin,duty,total]}
	if p.training.jobs.size()>=MAX_JOBS:q.ok=false;q.message="This academy already holds sixteen courses."
	elif free<ordinary or unqualified<ordinary or experts<1:q.ok=false;q.message="Training needs %d free unqualified workers, including one available instructor."%ordinary
	else:
		for good in materials:
			if float(p.stocks.get(good,0))<float(materials[good]):q.ok=false;q.message="The academy lacks physical "+str(Goods.ITEMS[good].name)+"."
	return q

static func enroll(p: Dictionary,wallet: Dictionary,count: int,role: String="sailor") -> Dictionary:
	var q: Dictionary=quote(p,count,role)
	if not q.ok:return q
	if int(wallet.get("coins",0))<int(q.cost):return {"ok":false,"message":"Training requires %d coins."%q.cost}
	var book: Dictionary=p.training
	book.nextId+=1
	var job: Dictionary={"id":"course-%s-%d"%[str(p.get("id","port")),int(book.nextId)],"role":role,"count":count,"days":q.days,"progress":0.0,"escrow":0,"traineeTotal":q.traineeWages,"instructorTotal":q.instructorWages,"traineePaid":0,"instructorPaid":0,"paused":false,"payer":str(wallet.get("id","player")),"reservedWorkers":q.reservedWorkers}
	Money.move(wallet,"coins",p,"cash",int(q.materialCost)+int(q.margin),"Academy provisions, supplies and facility service")
	Money.move(wallet,"coins",p,"expertPurse",int(q.oversight),"Academy foreman oversight")
	Money.move(wallet,"coins",p,"governmentPurse",int(q.duty),"Academy duty")
	Money.move(wallet,"coins",job,"escrow",int(q.traineeWages)+int(q.instructorWages),"Reserved trainee and instructor wages")
	for good in q.materials:p.stocks[good]=maxf(0,float(p.stocks[good])-float(q.materials[good]))
	p.workforce-=int(q.reservedWorkers)
	p.availableWorkers=maxi(0,int(p.availableWorkers)-int(q.reservedWorkers))
	p.specialists=maxi(0,int(p.get("specialists",0))-1);p.specialistWorkers=p.specialists
	p.availableSpecialists=maxi(0,int(p.availableSpecialists)-1)
	Economy.sync_workforce(p)
	book.jobs.append(job)
	return {"ok":true,"id":job.id,"cost":q.cost,"message":q.message}

static func _return_people(p: Dictionary,job: Dictionary,qualified: bool) -> void:
	p.workforce+=int(job.reservedWorkers)
	p.specialists=int(p.get("specialists",0))+1
	if qualified and str(job.role) in ["gunner","mechanic"]:p.specialists+=int(job.count)
	p.specialistWorkers=p.specialists
	Economy.sync_workforce(p)
	if qualified:
		p.recruits=mini(int(p.workforce),int(p.recruits)+int(job.count))
		p.training.qualified.sailor+=int(job.count)
		if str(job.role)!="sailor":p.training.qualified[job.role]+=int(job.count)
	p.availableSpecialists=mini(int(p.availableWorkers),int(p.specialists))

static func cancel(p: Dictionary,wallet: Dictionary,id: String) -> Dictionary:
	ensure(p)
	for job in p.training.jobs:
		if str(job.id)!=id:continue
		if str(job.payer)!=str(wallet.get("id","player")):return {"ok":false,"message":"Only the funding owner may close this course."}
		var refund: int=int(job.escrow)
		Money.move(job,"escrow",wallet,"coins",refund,"Unspent training wages returned")
		_return_people(p,job,false)
		p.training.jobs.erase(job)
		return {"ok":true,"refund":refund,"message":"Course closed. People and %d unspent coins returned; consumed materials and earned wages stay spent."%refund}
	return {"ok":false,"message":"No open course with this identity."}

static func daily(p: Dictionary,days: float=1.0) -> void:
	ensure(p)
	if not is_finite(days) or days<=0:return
	var finished: Array=[]
	for job in p.training.jobs:
		var progress: float=minf(float(job.days),float(job.progress)+days)
		if progress+0.000001>=float(job.days):progress=float(job.days)
		var trainee_due: int=mini(int(job.traineeTotal),floori(float(job.traineeTotal)*progress/float(job.days)+0.0000001))-int(job.traineePaid)
		var instructor_due: int=mini(int(job.instructorTotal),floori(float(job.instructorTotal)*progress/float(job.days)+0.0000001))-int(job.instructorPaid)
		if int(job.escrow)<trainee_due+instructor_due:
			job.paused=true
			continue
		job.paused=false
		Money.move(job,"escrow",p,"householdPurse",trainee_due,"Trainees earn daily wages",[])
		Money.move(job,"escrow",p,"expertPurse",instructor_due,"Instructor earns daily wages",[])
		job.traineePaid+=trainee_due;job.instructorPaid+=instructor_due;job.progress=progress
		if progress+0.000001>=float(job.days):finished.append(job)
	for job in finished:
		_return_people(p,job,true)
		p.training.jobs.erase(job)

static func report(p: Dictionary) -> Dictionary:
	ensure(p)
	return {"qualified":p.training.qualified.duplicate(true),"jobs":p.training.jobs.duplicate(true),"escrow":escrow_total(p)}

static func escrow_total(p: Dictionary) -> int:
	var total: int=0
	for job in p.get("training",{}).get("jobs",[]):total+=int(job.get("escrow",0))
	return total

static func consume_qualified(p: Dictionary,count: int,role: String="sailor") -> void:
	if not p.get("training") is Dictionary:return
	var q: Dictionary=p.training.qualified
	var n: int=mini(maxi(0,count),int(q.sailor))
	# Role qualifications are subsets of total eligibility; ordinary hires take
	# unclassified sailors first, then remove the corresponding subset if needed.
	if role!="sailor" and q.has(role):q[role]=maxi(0,int(q[role])-n)
	q.sailor=maxi(0,int(q.sailor)-n)
	var overflow: int=maxi(0,int(q.gunner)+int(q.mechanic)+int(q.get("boarder",0))-int(q.sailor))
	var remove: int=mini(overflow,int(q.gunner));q.gunner-=remove;overflow-=remove
	remove=mini(overflow,int(q.mechanic));q.mechanic-=remove;overflow-=remove
	q.boarder=maxi(0,int(q.get("boarder",0))-overflow)

static func return_qualified(p: Dictionary,count: int,role: String="sailor") -> void:
	var already: bool=p.get("training") is Dictionary
	ensure(p)
	if not already:return
	var room: int=maxi(0,int(p.workforce)-int(p.training.qualified.sailor))
	var n: int=mini(room,maxi(0,count))
	p.training.qualified.sailor+=n
	if role in ["gunner","mechanic","boarder"]:p.training.qualified[role]+=n

static func _int(value,maximum: int=1000000000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=maximum and floorf(float(value))==float(value)

static func validate(p: Dictionary) -> String:
	if not p.has("training"):return ""
	var b=p.training
	if not b is Dictionary or b.get("schema")!=1 or not _int(b.get("nextId")):return "Invalid academy schema or identity sequence."
	var q=b.get("qualified")
	if not q is Dictionary:return "Invalid qualification pool."
	for key in ["sailor","gunner","mechanic","boarder"]:
		if not _int(q.get(key)):return "Invalid qualified "+key+"."
	if float(q.sailor)>float(p.get("workforce",0)) or int(q.gunner)+int(q.mechanic)+int(q.get("boarder",0))>int(q.sailor):return "Qualification subsets exceed real civilian workers."
	if not b.get("jobs") is Array or b.jobs.size()>MAX_JOBS:return "Invalid training queue."
	var ids: Dictionary={}
	for job in b.jobs:
		if not job is Dictionary or not job.get("id") is String or ids.has(job.id) or job.get("role") not in ROLES:return "Invalid or duplicate training identity."
		ids[job.id]=true
		var prefix: String="course-"+str(p.get("id","port"))+"-"
		var suffix: String=str(job.id).trim_prefix(prefix)
		if not str(job.id).begins_with(prefix) or not suffix.is_valid_int() or int(suffix)<1 or int(suffix)>int(b.nextId):return "Stale or noncanonical training identity."
		if not _int(job.get("count"),MAX_PEOPLE) or int(job.count)<1:return "Invalid trainee count."
		if not (job.get("progress") is int or job.get("progress") is float) or not is_finite(float(job.progress)) or job.progress<0 or job.progress>float(ROLES[job.role].days):return "Invalid training progress."
		if job.get("days")!=ROLES[job.role].days or job.get("reservedWorkers")!=int(job.count)+1:return "Invalid course duration or reserved people."
		for key in ["escrow","traineeTotal","instructorTotal","traineePaid","instructorPaid"]:
			if not _int(job.get(key)):return "Invalid training wage account."
		if int(job.traineePaid)>int(job.traineeTotal) or int(job.instructorPaid)>int(job.instructorTotal) or int(job.escrow)!=int(job.traineeTotal)+int(job.instructorTotal)-int(job.traineePaid)-int(job.instructorPaid):return "Training wages and escrow do not reconcile."
		if int(job.traineeTotal)!=ceili(float(job.count)*float(job.days)*Goods.SAILOR_WAGE) or int(job.instructorTotal)!=ceili(float(job.days)*int(Goods.WAGES[ROLES[job.role].instructor])):return "Noncanonical course wages."
		var expected_trainee: int=floori(float(job.traineeTotal)*float(job.progress)/float(job.days)+0.0000001)
		var expected_instructor: int=floori(float(job.instructorTotal)*float(job.progress)/float(job.days)+0.0000001)
		if int(job.traineePaid)!=expected_trainee or int(job.instructorPaid)!=expected_instructor:return "Earned training wages do not match elapsed paid work."
		if not job.get("paused") is bool or not job.get("payer") is String:return "Invalid training status or payer."
	return ""
