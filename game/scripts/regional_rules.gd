extends RefCounted
## Root's sustained-progress rules. No money or physical goods are created here.
const Factions=preload("res://scripts/factions.gd")
const Trade=preload("res://scripts/trade_intel.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const Goods=preload("res://scripts/goods.gd")
const Home=preload("res://scripts/home_harbor.gd")
const CLEAR_DAYS: int=7
const HARBOR_LOTS: int=12
const STAFF_DAYS: int=3
const RELIEF_PER_SIDE: int=5
const TALKS_DAYS: int=3

static func today(s: Dictionary) -> int:
	return floori(minf(float(s.get("day",1)),float(s.get("econDay",s.get("day",1)))+1.0))

static func local_port(s: Dictionary) -> Dictionary:
	if not s.get("path",[]).is_empty():return {}
	var pos: Dictionary=s.get("position",{})
	if not pos.has("x") or not pos.has("y"):return {}
	for p in s.get("ports",[]):
		if Vector2(float(pos.x),float(pos.y)).distance_to(Vector2(float(p.x),float(p.y)))<65:return p
	return {}

static func may_deliver(s: Dictionary,p: Dictionary) -> bool:
	var here: Dictionary=local_port(s)
	if p.is_empty() or here.get("id","")!=p.id:return false
	if not s.has("relationships"):return true
	if Factions.access(s,p).legal:return true
	return float(s.relationships.get("safeConduct",{}).get(p.id,0))>float(s.get("day",1))

static func initialize(s: Dictionary,op: Dictionary) -> void:
	op.clearDays=0;op.lastAssessedDay=today(s);op.patrolVisits=0;op.playerAction=false
	op.patrolLastPort="";op.talksStartedDay=0;op.relief={};op.businessWages={}
	var facts: Dictionary=s.get("regionalFacts",{})
	op.passageBaseline=int(facts.get("passages",{}).get(route_key(op.get("ends",[])),0))
	op.deliveryBaseline=float(facts.get("deliveries",{}).get(str(op.portId),0))
	for b in s.get("businesses",[]):op.businessWages[b.id]=int(b.get("wagesPaid",0))
	if op.id=="harbor":_business_baseline(s,op)
	if op.id=="ceasefire":
		var focus: Dictionary=s.get("campaignFocus",{})
		op.peaceA=str(focus.get("peaceA","compact"));op.peaceB=str(focus.get("peaceB","raiders"))
		op.peaceKey=route_key([op.peaceA,op.peaceB])

static func route_key(ids: Array) -> String:
	if ids.size()!=2:return ""
	return str(ids[0])+"|"+str(ids[1]) if str(ids[0])<str(ids[1]) else str(ids[1])+"|"+str(ids[0])

static func near_corridor(s: Dictionary,op: Dictionary,pos: Vector2) -> bool:
	var ends: Array=op.get("ends",[])
	if ends.size()!=2:return false
	var a: Dictionary=Orders.find_port(s,str(ends[0]))
	var b: Dictionary=Orders.find_port(s,str(ends[1]))
	if a.is_empty() or b.is_empty():return false
	var av:=Vector2(float(a.x),float(a.y));var bv:=Vector2(float(b.x),float(b.y))
	return pos.distance_to(Geometry2D.get_closest_point_to_segment(pos,av,bv))<=300.0

static func threatened(s: Dictionary,op: Dictionary) -> bool:
	var blockades: Array=Trade.blockades(s)
	for id in op.ends:
		if blockades.has(str(id)):return true
	for owner in s.get("fleetOwners",[]):
		if str(owner.id).begins_with("story-") or not owner.get("active",false):continue
		var supplied: bool=false
		for b in owner.boats:
			if not b.sunk and float(b.crew)>=float(b.crewMin) and float(b.fuel)>=0.5 and float(b.ammo)>=10:supplied=true
		if not supplied or not near_corridor(s,op,Orders.owner_position(s,owner)):continue
		for id in op.ends:
			var p: Dictionary=Orders.find_port(s,str(id))
			if owner.get("faction","")!=p.get("faction","") and Factions.relation(s,str(owner.get("faction","")),str(p.get("faction","")))<=Factions.ENEMY_AT:return true
	return false

static func _business_baseline(s: Dictionary,op: Dictionary) -> void:
	op.businessDays={}
	for b in s.get("businesses",[]):
		if str(b.get("homePort",""))==str(op.portId):op.businessDays[str(b.id)]=int(b.get("paidWorkDays",0))

# Pure selected progress and owned books. Donated cargo never enters deliveries.
static func harbor_view(s: Dictionary,op: Dictionary) -> Dictionary:
	if str(op.get("id",""))!="harbor":return {}
	var delivered: float=maxf(0,float(s.get("regionalFacts",{}).get("deliveries",{}).get(str(op.portId),0))-float(op.get("deliveryBaseline",0)))
	var donated: int=0
	for value in op.get("contributed",{}).values():donated+=int(value)
	var known: bool=op.get("businessDays") is Dictionary
	var baselines: Dictionary=op.get("businessDays",{}) if known else {}
	var out: Dictionary={"portId":str(op.portId),"deliveredLots":delivered,"donatedLots":donated,"harborLots":delivered+float(donated),"lotsRequired":HARBOR_LOTS,"staffDays":0,"staffDaysRequired":STAFF_DAYS,"historyKnown":known,"staffReady":false,"ready":false,"businessId":"","business":{},"businesses":[],"stallReason":"","resumeReason":""}
	for b in s.get("businesses",[]):
		if str(b.get("homePort",""))!=str(op.portId):continue
		var row: Dictionary=Home.business_view(s,str(b.id))
		if row.is_empty():continue
		row.staffDays=maxi(0,int(row.paidWorkDays)-int(baselines.get(str(b.id),0))) if known else 0
		row.wagesSinceStart=maxi(0,int(row.get("wagesPaid",0))-int(op.get("businessWages",{}).get(str(b.id),0)))
		out.businesses.append(row)
		out.staffDays=maxi(int(out.staffDays),int(row.staffDays))
		if int(row.staffDays)>=STAFF_DAYS and bool(row.working):out.staffReady=true
		var selected: Dictionary=out.business
		if selected.is_empty() or int(row.staffDays)>int(selected.staffDays) or (int(row.staffDays)==int(selected.staffDays) and bool(row.working) and not bool(selected.working)):
			out.business=row;out.businessId=str(row.id)
	out.ready=float(out.harborLots)>=HARBOR_LOTS and bool(out.staffReady)
	if out.business.is_empty():
		out.stallReason="No owned staffed business at this harbor."
		out.resumeReason="Establish an optional paid local business using actual staff, setup materials and capital."
	elif not known:
		out.stallReason="No post-start working-day baseline is recorded; earlier wages prove no historical working days."
		out.resumeReason="The next authoritative goal step records a baseline; only later qualifying work days can count."
	elif not bool(out.staffReady):
		out.stallReason="Recorded paid working days: %d / %d. %s"%[int(out.staffDays),STAFF_DAYS,str(out.business.stallReason)]
		out.resumeReason=str(out.business.resumeReason)
	if float(out.harborLots)<HARBOR_LOTS:
		var supply: String="Receiving harbor still needs %.2f distinct sold/delivered or donated lots."%maxf(0,HARBOR_LOTS-float(out.harborLots))
		out.stallReason=supply+(" "+str(out.stallReason) if not str(out.stallReason).is_empty() else "")
		out.resumeReason="Bring and legally sell/deliver or explicitly donate actual cargo. Donations are unpaid. "+str(out.resumeReason)
	return out

static func progress(s: Dictionary,op: Dictionary) -> String:
	var day: int=today(s)
	if op.id=="corridor":
		if day>int(op.get("lastAssessedDay",op.startedDay)):
			op.clearDays=0 if threatened(s,op) else int(op.get("clearDays",0))+1
			op.lastAssessedDay=day
		var passages: int=int(s.get("regionalFacts",{}).get("passages",{}).get(route_key(op.ends),0))-int(op.get("passageBaseline",0))
		var proof: bool=passages>0 or bool(op.get("playerAction",false)) or int(op.get("patrolVisits",0))>=2
		return "sustained-corridor" if int(op.get("clearDays",0))>=CLEAR_DAYS and proof and not threatened(s,op) else ""
	if op.id=="harbor":
		if str(op.get("status",""))!="active":return ""
		# A legacy active goal anchors NOW; cumulative wages do not backfill days.
		if not op.get("businessDays") is Dictionary:_business_baseline(s,op)
		var view: Dictionary=harbor_view(s,op)
		op.harborLots=float(view.harborLots);op.staffDays=int(view.staffDays)
		return "paid-harbor-development" if bool(view.ready) else ""
	if op.id=="ceasefire":
		if relief_ready(op) and int(op.get("talksStartedDay",0))==0:op.talksStartedDay=day
	return ""

static func relief_ready(op: Dictionary) -> bool:
	return int(op.get("relief",{}).get(str(op.get("peaceA","")),0))>=RELIEF_PER_SIDE and int(op.get("relief",{}).get(str(op.get("peaceB","")),0))>=RELIEF_PER_SIDE

static func peace_conditions(s: Dictionary,op: Dictionary,a: String,b: String) -> Dictionary:
	var distinct: bool=a!=b and Factions.CANON.has(a) and Factions.CANON.has(b)
	var r: Dictionary={"distinct":distinct,"hostile":false,"goal":false,"offering":false,"party":false,"cooldown":true,"mandate":false,"talks":false,"reason":"Choose two different known factions."}
	if not distinct:return r
	r.hostile=Factions.relation(s,a,b)<=Factions.ENEMY_AT
	r.goal=not op.is_empty() and str(op.get("status",""))=="active" and str(op.get("peaceKey",""))==route_key([a,b])
	var previous: Dictionary=s.get("regionalCampaigns",{}).get("peace",{}).get(route_key([a,b]),{})
	r.cooldown=int(previous.get("cooldownUntil",0))<=today(s)
	r.offering=relief_ready(op)
	var p: Dictionary=local_port(s)
	r.party=not p.is_empty() and str(p.get("faction","")) in [a,b] and may_deliver(s,p)
	var left: Dictionary=Factions.standing(s,a);var right: Dictionary=Factions.standing(s,b)
	r.mandate=(int(left.get("public",0))>=Factions.FRIENDLY_ENTER or int(right.get("public",0))>=Factions.FRIENDLY_ENTER) and not left.get("hostile",true) and not right.get("hostile",true) and int(left.get("witnessed",0))>=0 and int(right.get("witnessed",0))>=0 and int(left.get("claimTotal",0))==0 and int(right.get("claimTotal",0))==0
	r.talks=int(op.get("talksStartedDay",0))>0 and today(s)-int(op.get("talksStartedDay",0))>=TALKS_DAYS
	for pair in [["hostile","These factions are already at peace."],["cooldown","The previous treaty's cooldown has not ended."],["goal","Choose this pair's ceasefire goal first."],["offering","Deliver five food or repair-kit lots to EACH faction's harbor."],["mandate","Earn Friendly standing with one party, access to both, and clear all witnessed offenses and claims."],["talks","Allow three published economic days for talks after relief reaches both sides."],["party","Return to a legal harbor belonging to either party for the agreement."]]:
		if not r[pair[0]]:r.reason=pair[1];return r
	r.reason="Both parties can sign a thirty-day truce; no player commission or reward is attached."
	return r

static func expire(s: Dictionary,book: Dictionary) -> Array:
	var events: Array=[]
	for rec in book.peace.values():
		if not bool(rec.get("active",true)) or today(s)<int(rec.untilDay):continue
		rec.active=false
		var current: int=Factions.relation(s,str(rec.a),str(rec.b))
		if current==0:Factions.set_relation(s,str(rec.a),str(rec.b),int(rec.before),"Thirty-day ceasefire expired; previous dispute resumes.")
		events.append({"day":today(s),"kind":"treaty-expired","goal":"ceasefire","target":str(rec.key),"cause":"prior-dispute-restored" if current==0 else "later-diplomacy-preserved"})
	return events
