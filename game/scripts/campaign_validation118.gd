extends RefCounted
## Raw optional absence, finite exact coins and original identities, before
## native/story normalization. No mutation of 117 or native financial books.
const P=preload("res://scripts/campaign_validation117.gd")
const ID: String="common_passage110"
const PORT: String="naphtha_bay"
const BRASS: String="brass_haven"
const BEFORE_FIELDS: Array=["port","day","qty","price","cost","buyerBefore","sellerBefore","stockBefore","holdBefore"]
const FUEL_FIELDS: Array=["port","day","qty","price","cost","buyerBefore","buyerAfter","sellerBefore","sellerAfter","stockBefore","stockAfter","holdBefore","holdAfter"]
const WORK_FIELDS: Array=["schema","startedDay","passage","fuel","fuelReported","fuelReportDay","warrantDay","attempt","warrantReported","warrantReportDay","warrantPort","resolution","tobin"]
const AFTER_FUEL: Array=["fuel_account118","last_warrant118","warrant_work118","warrant_account118","common_passage119"]

static func fuel_valid(r,started: float,now: float) -> bool:
	if not P.shape(r,FUEL_FIELDS) or r.port!=PORT or not P.number(started,1,now) or not P.number(r.day,started,now):return false
	if not P.number(r.qty,1,1000000,true) or not P.number(r.price,1,1000000000,true) or not P.number(r.cost,1,P.COINS,true):return false
	if not P.same_value(r.cost,int(r.qty)*int(r.price)):return false
	for key in ["buyerBefore","buyerAfter","sellerBefore","sellerAfter"]:
		if not P.number(r[key],0,P.COINS,true):return false
	for key in ["stockBefore","stockAfter","holdBefore","holdAfter"]:
		if not P.number(r[key]):return false
	if int(r.buyerBefore)-int(r.buyerAfter)!=int(r.cost) or int(r.sellerAfter)-int(r.sellerBefore)!=int(r.cost):return false
	# Economy._add_stock rounds float cargo to six decimals. Coins above are exact.
	return float(r.stockBefore)>=float(r.qty) and absf(float(r.stockBefore)-float(r.stockAfter)-float(r.qty))<=0.000001 and absf(float(r.holdAfter)-float(r.holdBefore)-float(r.qty))<=0.000001

static func _passage(r,started: float,now: float) -> bool:
	if not P.shape(r,["port","mode","day","cost","claim","until"]) or r.port!=PORT or r.mode not in ["legal","parley"]:return false
	if not P.number(r.day,started,now) or not P.number(r.cost,0,P.COINS,true) or not P.number(r.claim,0,1000000,true) or not P.number(r.until):return false
	if r.mode=="legal":return r.cost==0 and r.until==0
	return P.same_value(r.cost,1000+100*int(r.claim)) and P.same_value(r.until,float(r.day)+3.0)

static func earlier_job(rec: Dictionary,id: String) -> bool:
	var old=rec.get("work116",{})
	if old is Dictionary and old.get("priority",{}) is Dictionary and old.get("priority",{}).get("jobId")==id:return true
	var prior=rec.get("work117",{})
	if prior is Dictionary and prior.get("attempts",[]) is Array:
		for row in prior.get("attempts",[]):
			if row is Dictionary and row.get("binding",{}) is Dictionary and row.get("binding",{}).get("jobId")==id:return true
	return false

static func _crew(rows,b: Dictionary,closing: bool) -> bool:
	if not rows is Array or rows.size()!=b.carrierUids.size():return false
	for i in range(rows.size()):
		var r=rows[i]
		if not P.shape(r,["uid","state","crew"] if closing else ["uid","crew"]) or r.uid!=b.carrierUids[i]:return false
		if not P.number(r.crew,-1 if closing else 0,1000000,true):return false
		if closing:
			if r.state not in ["unobserved","afloat","sunk","captured"] or (r.state=="unobserved" and r.crew!=-1):return false
	return true

static func _origin(r,s: Dictionary) -> bool:
	if not P.shape(r,["x","y","playerX","playerY"]):return false
	for key in r:
		if not P.number(r[key],-1000000000,1000000000):return false
	var brass: Dictionary=P._find(s.get("ports",[]),BRASS)
	if brass.is_empty() or not P.number(brass.get("x"),-1000000000,1000000000) or not P.number(brass.get("y"),-1000000000,1000000000):return false
	var convoy: Vector2=Vector2(float(r.x),float(r.y))
	return convoy.distance_to(Vector2(float(brass.x),float(brass.y)))<=1800.0 and convoy.distance_to(Vector2(float(r.playerX),float(r.playerY)))<=600.0

static func _attempt(a,s: Dictionary,rec: Dictionary,opened: float) -> String:
	if not P.shape(a,["binding","claimDay","claimStatus","origin","crew","status","closure","follow","followClock"]):return "118: invalid single bounded warrant attempt."
	if not P._binding(a.binding,s,opened):return "118: invalid native original owner, voyage, carrier UIDs or cargo identity."
	var b: Dictionary=a.binding
	if earlier_job(rec,str(b.jobId)):return "118: an earlier116/117 passage cannot count again."
	if a.claimStatus!="unverified" or not P.number(a.claimDay,opened,float(s.day)) or not P.same_value(a.claimDay,b.acceptedDay) or not _origin(a.origin,s) or not _crew(a.crew,b,false):return "118: invalid dated current claimant application or actual crew observations."
	if a.status not in ["carried","paid","abandoned"] or not a.follow is bool or not P.number(a.followClock,0,1) or not a.closure is Dictionary:return "118: invalid native warrant status or follow fields."
	var live: Dictionary=P._find(s.get("voyageJobs",[]),str(b.jobId))
	if a.status=="carried":
		if not a.closure.is_empty() or live.is_empty() or not P.same_value(P.identity(live),b) or s.get("doneVoyageJobs",[]).has(str(b.jobId)):return "118: carried original native escort changed, disappeared or already closed."
		if live.get("state") not in ["active","expired"] or not P.number(live.get("escrow"),0,float(b.reward),true):return "118: invalid actual carried escort escrow."
		if live.state=="active" and not P.same_value(live.escrow,b.reward):return "118: active original client escrow is incomplete."
		return ""
	if not live.is_empty() or a.follow:return "118: closed warrant still carried or followed."
	var q: Dictionary=a.closure
	if not P.shape(q,["jobId","ownerId","status","day","payment","sale","observations"]) or q.jobId!=b.jobId or q.ownerId!=b.ownerId or q.status!=a.status:return "118: invalid once-only original native closure."
	if not P.number(q.day,float(b.acceptedDay),float(s.day)) or not P.number(q.payment,0,float(b.reward),true) or not _crew(q.observations,b,true):return "118: invalid closure chronology, whole payment or physical observations."
	if a.status=="paid":
		if not P.same_value(q.payment,b.reward) or not P.sale_valid(q.sale,b,float(q.day)):return "118: paid account lacks original actual cargo sale, movement, exit or full payment."
	else:
		if q.payment!=0 or not q.sale is Dictionary or not q.sale.is_empty():return "118: abandoned passage claims payment or successful delivery."
	# Capture requires native closed ID; historical receipts survive its 128-ID cache.
	return ""

static func validate(s: Dictionary) -> String:
	var stories=s.get("stories",{})
	if not stories is Dictionary or not stories.get("chains",{}) is Dictionary:return "118: invalid raw story structure."
	var rec=stories.get("chains",{}).get(ID,{})
	if not rec is Dictionary:return "118: invalid main campaign record."
	var stage=rec.get("stage","")
	var required: bool=stage in ["fuel_work118","fuel_account118","last_warrant118","warrant_work118","warrant_account118","common_passage119"]
	if not rec.has("work118"):return "118: missing entered chapter record." if required else ""
	if not P.number(s.get("day"),1):return "118: invalid native calendar."
	for key in ["ports","voyageJobs","doneVoyageJobs"]:
		if not s.get(key,[]) is Array:return "118: validate native harbor and job arrays first."
	var w=rec.work118
	if not P.shape(w,WORK_FIELDS):return "118: invalid bounded chapter record."
	if not P.number(w.schema,1,1,true) or not w.fuelReported is bool or not w.warrantReported is bool or not w.warrantPort is String or not w.resolution is String:return "118: invalid raw chapter scalar types."
	for key in ["passage","fuel","attempt","tobin"]:
		if not w[key] is Dictionary:return "118: invalid optional chapter receipt container."
	var funding=rec.get("work117",{})
	if not w.tobin.is_empty():
		if not P.shape(w.tobin,["day"]) or not P.number(w.tobin.day,1,float(s.day)) or not stories.chains.get("tobin_clause111") is Dictionary:return "118: funding discussion lacks its actual optional history or date."
		if not funding is Dictionary or not funding.get("reported") is bool or not funding.reported or funding.get("model") not in ["mutual","separate"] or not P.number(funding.get("reportDay"),1,float(w.tobin.day)):return "118: Tobin discussion predates the chosen actual reported117 funding account."
		var optional: Dictionary=stories.chains.tobin_clause111
		if optional.get("stage") not in ["tobin_funding118","done"] and optional.get("done")!=true:return "118: funding discussion predates the actual later Tobin choice."
	var entered: bool=P.number(w.startedDay,1,float(s.day))
	if not entered:
		if required or not P.number(w.startedDay,-1,-1) or not w.passage.is_empty() or not w.fuel.is_empty() or w.fuelReported or not P.number(w.fuelReportDay,-1,-1) or not P.number(w.warrantDay,-1,-1) or not w.attempt.is_empty() or w.warrantReported or not P.number(w.warrantReportDay,-1,-1) or w.warrantPort!="" or w.resolution!="":return "118: unentered optional-only work claims main operation progress."
		return ""
	if stage=="fuel_has_owners118":return "118: chapter entry was recorded before its opening choice."
	if not funding is Dictionary or not funding.get("reported") is bool or not funding.reported or funding.get("model") not in ["mutual","separate"] or not P.number(funding.get("reportDay"),1,float(w.startedDay)):return "118: main operation predates the chosen actual reported117 funding account."
	if not w.passage.is_empty() and not _passage(w.passage,float(w.startedDay),float(s.day)):return "118: invalid zero-cost legal entry or actual native parley receipt."
	if not w.fuel.is_empty():
		if not fuel_valid(w.fuel,float(w.startedDay),float(s.day)) or w.passage.is_empty() or float(w.passage.day)>float(w.fuel.day):return "118: paid fuel lacks exact native buyer/seller and stock/hold evidence or preceding access."
	if w.fuelReported:
		if w.fuel.is_empty() or not P.number(w.fuelReportDay,float(w.fuel.day),float(s.day)) or stage=="fuel_work118":return "118: fuel report predates actual paid ownership."
	elif not P.number(w.fuelReportDay,-1,-1) or stage in AFTER_FUEL:return "118: progression precedes paid fuel reporting."
	var opened: bool=P.number(w.warrantDay,1,float(s.day))
	if opened:
		if not w.fuelReported or float(w.warrantDay)<float(w.fuelReportDay) or stage in ["fuel_work118","fuel_account118","last_warrant118"]:return "118: warrant admission predates its actual opening and fuel account."
	elif not P.number(w.warrantDay,-1,-1) or stage in ["warrant_work118","warrant_account118","common_passage119"]:return "118: missing warrant opening date."
	if not w.attempt.is_empty():
		if not opened:return "118: native warrant bound before the operation opened."
		var error: String=_attempt(w.attempt,s,rec,float(w.warrantDay))
		if not error.is_empty():return error
	if w.warrantReported:
		if not opened or w.warrantPort!=BRASS or w.resolution not in ["paid","abandoned","unresolved"] or stage=="warrant_work118":return "118: invalid completed warrant report or physical reporting harbor."
		var earliest: float=float(w.warrantDay)
		if w.resolution=="unresolved":
			if not w.attempt.is_empty():return "118: no-attempt unresolved report overwrote a real native attempt."
		else:
			if w.attempt.get("status")!=w.resolution or w.attempt.get("closure",{}).is_empty():return "118: report erased or relabeled the actual paid/abandoned outcome."
			earliest=float(w.attempt.closure.day)
		if not P.number(w.warrantReportDay,earliest,float(s.day)):return "118: warrant report predates actual closure or is in the future."
	elif not P.number(w.warrantReportDay,-1,-1) or w.warrantPort!="" or w.resolution!="" or stage in ["warrant_account118","common_passage119"]:return "118: warrant progression or report fields lack an honest recorded outcome."
	return ""
