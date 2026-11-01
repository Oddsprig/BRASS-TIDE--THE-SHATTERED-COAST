extends RefCounted
## Copied-data fleet policy. Sampled goals never contain physical certificates.
const Roles=preload("res://scripts/tactical_role_plans.gd")
const Stations=preload("res://scripts/tactical_stations.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const SAMPLE_SECONDS: float=0.15
const BATCH_SECONDS: float=0.10
const CHOICE_SECONDS: float=0.45

static func plan051(data: Dictionary) -> Dictionary:
	var view: Dictionary=data.view
	var context: Dictionary=Roles.ships_by_id(view)
	# This preparation is local to ONE copied SIDE job, never a live borrow.
	view._observation051=Roles._prepare_observation051(view,context)
	var private_state: Dictionary={"time":view.time,"tactical":{"routeCache":data.cache}}
	var reservations: Dictionary={}
	var goals: Dictionary={}
	# All automated side members are sampled together. Prior reservations for
	# those same members cannot veto their replacements or reserve old stations.
	for id: String in data.order:
		var ship: Dictionary=context[id]
		var previous: Dictionary=data.memory.byId.get(id,{})
		var decision: Dictionary=Roles.decide(view,ship,previous,context,reservations)
		var state: Dictionary=decision.state
		var budget: Dictionary=data.budgets[id]
		budget.clearanceExhausted=0
		# Candidates already rank sampled exposure, role, commitment and sectors.
		# Keep the ordinary <=8 offers, including the existing local crowd escape.
		var requests: Array=Stations._candidates_crowd051(view,ship,decision,context,reservations)
		var blocked_escape051: bool=bool(previous.get("blockedCrowdEscape051",false)) and int(previous.get("orderRevision",-1))==int(ship.orderRevision)
		var preferred_escape051: bool=false
		if bool(previous.get("blockedStation",false)) and not blocked_escape051:
			# A sampled preference only: the ordinary existing escape still needs
			# static routing here and current crowd-floor/terrain checks at helm.
			# A live-vetoed escape keeps its ordinary final fallback position.
			for request: Dictionary in requests:
				if Routes._is_crowd_escape051(request):
					requests.erase(request);requests.push_front(request);preferred_escape051=true;break
		var candidate: Dictionary={}
		var reservation: Dictionary={}
		var risk: float=clampf(float(ship.water)/maxf(1.0,float(ship.capacity)),0.0,1.0)
		var offer_count051: int=mini(Stations.MAX_OFFERS,requests.size())
		var first_offer051: int=0
		if bool(previous.get("blockedStation",false)) and not preferred_escape051 and int(previous.get("orderRevision",-1))==int(ship.orderRevision):
			first_offer051=clampi(int(previous.get("routeOfferCursor051",0)),0,maxi(0,offer_count051-1))
		var next_offer051: int=first_offer051
		var pending_offer051: bool=false
		var initial_tests051: int=int(budget.clearanceTests)
		for offset051: int in range(offer_count051):
			var index: int=(first_offer051+offset051)%offer_count051
			var request: Dictionary=requests[index]
			if not Stations.valid_candidate(request):continue
			if str(ship.order)=="engage" and not request.fireMountIds.is_empty() and risk>float(decision.riskLimit):continue
			# Static land routing ONLY. No long-horizon moving-hull forecast and
			# no Fire/rollout/certificate work: real safe_step owns current traffic.
			var routed: Dictionary=Routes.refine(private_state,data.geometry,ship,request,budget)
			if routed.status!="valid":
				if routed.status=="pending" and not pending_offer051 and int(budget.clearanceTests)>initial_tests051:
					# A fresh sample must not spend every slice on the same costly
					# prefix. Give the first unserved offer a turn; if it already
					# started this sample, yield to its next ordinary/fallback offer.
					next_offer051=(index+1)%offer_count051 if offset051==0 else index
					pending_offer051=true
				continue
			var choice: Dictionary=routed.candidate
			# Deployment/sample origin is not a station to drive BACK toward at
			# adoption. Main starts the selected route at its actual current pose.
			if choice.approach.size()>1 and choice.approach[0]==Roles.pos(ship):choice.approach.pop_front()
			if not Stations.valid_candidate(choice) or not Stations.same_request(request,choice):continue
			var shape: Dictionary=Stations._reservation_begin051(choice,ship,float(view.time),SAMPLE_SECONDS)
			var conflict: bool=false
			for other: Dictionary in reservations.values():
				# Direct pure implementation avoids the optional global MAIN-only
				# veto recorder in Stations._conflict_begin051.
				if Stations._conflict(shape,other,budget,int(budget.clearanceLimit),true):
					conflict=true;break
			if conflict:continue
			candidate=choice;reservation=shape
			# Remember the NEXT ordinary offer even after static success. Only a
			# subsequent real helm veto consumes it; a working station keeps its
			# commitment. A repeated live refusal cannot retry offer zero forever.
			next_offer051=(index+1)%offer_count051
			break
		if not candidate.is_empty():
			if state.get("targetId")!=candidate.targetId or state.get("sector")!=candidate.sector or float(state.get("commitUntil",0.0))<=float(view.time):
				state.commitUntil=float(view.time)+Roles.COMMIT_SECONDS
			state.targetId=str(candidate.targetId);state.sector=int(candidate.sector)
			state.anchor=Stations.anchor(candidate);state.waitSince=-1.0;state.blockedStation=false
			state.nextRouteOffer080=next_offer051
			reservations[id]=reservation
		else:
			# An actual sampled observation may publish while no route is ready.
			# It grants neither helm nor fire and never becomes a complete proof.
			state.blockedStation=true;state.commitUntil=0.0
			# Only an unsuccessful real search carries this bounded preference.
			# Roles' fixed state copy clears it on success or a changed command.
			state.routeOfferCursor051=next_offer051
			# Route-pending samples cannot forget the last real escape veto.
			if blocked_escape051:state.blockedCrowdEscape051=true
			if float(state.get("waitSince",-1.0))<0.0:state.waitSince=float(view.time)
			state.reason="Waiting for a route or a clear shared approach."
		# Every job performs a full tactical search. chosenAt starts at this REAL
		# input sample, not completion/adoption; there is no semantic-age renewal.
		goals[id]={"candidate":candidate,"state":state,"chosenAt":float(view.time),"sampledAt":float(view.time),"sampledRisk":risk,"reservation":reservation}
	view.erase("_observation051") # Never publish the worker-local object graph.
	return {"goals051":goals,"cache":data.cache,"budgets":data.budgets}
