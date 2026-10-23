extends RefCounted
const Routes=preload("res://scripts/route_cache.gd")
const Goods=preload("res://scripts/goods.gd")
const Economy=preload("res://scripts/economy.gd")
static func available(c) -> Array:
	if not c.state.get("storyRights") is Dictionary:return []
	var r: Dictionary=c.state.storyRights
	var definitions: Array=[]
	if str(r.get("buyer","")) in ["compact","forge"]:definitions.append(["ironwood-"+r.buyer,"sawtooth_mill","brass_haven" if r.buyer=="compact" else "anvil_dock","timber",5,"Ironwood first call"])
	if r.get("publicCharts",false):definitions.append(["public-charts","reed_floats","anvil_dock","supplies",4,"Public chart packets & survey tools"])
	if r.get("privateCharts",false):definitions.append(["private-charts","brass_haven","rust_anchorage","supplies",4,"Cass's private chart courier"])
	if r.get("privateOre",false):definitions.append(["private-ore","cinder_quay","brass_haven","ore",4,"Private ore bearing passage"])
	var p: Dictionary=c.current_port()
	if p.is_empty():return []
	var out: Array=[]
	for def in definitions:
		var id: String="chainfreight-"+str(def[0])
		if r.get("usedOffers",{}).has(id) or p.id!=def[1] or c.state.get("voyageJobs",[]).any(func(j):return j.id==id):continue
		var target: Dictionary=c.port(def[2])
		var good: String=def[3]
		var qty: int=int(def[4])
		if float(p.stocks.get(good,0))<qty:continue
		var route: Array=Routes.path(c,p,target)
		if route.size()<2:continue
		var distance: float=0
		for i in range(1,route.size()):distance+=c.distance(route[i-1],route[i])
		var reference: Dictionary=c.hull("tinwake")
		if reference.is_empty():reference=c.data.HULLS[0]
		var days: float=distance/maxf(1,float(reference.speed)*1.55*float(c.data.get("CAMPAIGN_SCALE",1)))/45.0
		var work: float=maxf(1,days*2)
		var reward: int=ceili((5*100*work+5*0.08*work*Economy.price(p,"food")+maxf(0.15,days*2)*0.65*Economy.price(p,"fuel")+0.25*Economy.price(p,"supplies")+Goods.WAGES.laborer)*1.25)
		var invoice: int=qty*Economy.price(p,good)
		if int(p.governmentPurse)<reward+invoice:continue
		out.append({"id":id,"title":str(def[5]),"description":"An opportunity earned by your coastal decision. The treasury buys these physical goods and escrows one small-fleet passage. This offer is issued once; a larger fleet costs more to operate.","kind":"freight","port":p.id,"targetPort":target.id,"reward":reward,"escrow":0,"payerKey":"governmentPurse","materialInvoice":invoice,"failed":false,"deadlineDay":floorf(float(c.state.day))+20,"acceptedDay":0,"freight":{"good":good,"qty":qty,"lost":false},"state":"offered","siteId":"","ownerId":""})
	return out
