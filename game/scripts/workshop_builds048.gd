extends RefCounted
## Design comparisons only. Quotes/payment/stock/condition remain FleetWorkshop's.
const Refits=preload("res://scripts/refit.gd")
const HULL_ID: String="iron_bastion"

## Recommendations are knowledge, never inventory or tactical-option changes.
## Unsupported hulls return no examples; never silently put a Bastion fit on one.
static func examples(base: Dictionary) -> Array:
	if str(base.get("id",""))!=HULL_ID:return []
	var candidates: Array=[
		{"id":"bastion_harasser048","name":"Fast gun pressure","role":"skirmisher",
			"summary":"Twin machine guns, an aft Needle and a racing engine for close firing passes. Select Skirmisher tactics to harass; automatic cruiser tactics still favor anchoring.",
			"tradeoff":"Shortest reach and original armor; highest fuel demand. Fast raw fire spends shared rounds quickly, and light hits struggle against heavy armor. This remains a large cruiser, not a light interceptor.",
			"loadout":{"weapons":["heavy_gun","rapid_gun","",""],"engine":"boost_drive","armor":"stock_armor"}},
		{"id":"bastion_anchor048","name":"Armored cannon anchor","role":"heavy",
			"summary":"A Long iron cannon covers the bow while aft twin machine guns defend close approaches. A naval belt increases protection without raising hull health or pump capacity.",
			"tradeoff":"Slowest speed and turning. The main cannon has a committed forward arc and reload window; flankers can get outside it. The belt needs substantially more iron and paid yard labor.",
			"loadout":{"weapons":["heavy_cannon","heavy_gun","",""],"engine":"stock_engine","armor":"naval_plating"}},
		{"id":"bastion_strike048","name":"Economical torpedo striker","role":"striker",
			"summary":"A bow Deepwater tube reaches beyond the gun fit, with an aft Needle for close defense. The long-voyage engine uses less fuel and light plates retain more turning than the anchor.",
			"tradeoff":"Narrow bow launch arc, slow torpedoes and three shared rounds per launch. Less armor than the anchor and much less speed than the gun fit; a miss still spends ammunition. The heavy cannon can match its reach.",
			"loadout":{"weapons":["heavy_torpedo","rapid_gun","",""],"engine":"economy_drive","armor":"scout_plating"}}
	]
	var result: Array=[]
	for candidate in candidates:
		var normalized: Dictionary=Refits.normalize(base,candidate.loadout)
		if not bool(normalized.get("ok",false)):continue
		candidate.loadout=normalized.loadout.duplicate(true)
		result.append(candidate)
	return result

## Effective fitted design, not a prediction of live crew/damage/accuracy/AI.
## UI may call metrics(q.beforeSpec/afterSpec) for actual identity/morale bonuses.
static func describe_fit(base: Dictionary,loadout: Dictionary) -> Dictionary:
	var normalized: Dictionary=Refits.normalize(base,loadout)
	if not bool(normalized.get("ok",false)):
		return {"ok":false,"message":str(normalized.get("message","Invalid fitting."))}
	var spec: Dictionary=Refits.effective_spec(base,normalized.loadout)
	var result: Dictionary=metrics(spec)
	result.ok=true;result.message="Design at full equipment and crew efficiency."
	result.loadout=normalized.loadout.duplicate(true)
	result.usedPoints=int(normalized.usedPoints);result.maxPoints=int(normalized.maxPoints)
	result.spec=spec.duplicate(true)
	return result

## No invented DPS or endurance promise: arcs, shared ammunition, reload gates,
## crew, damage, safety, acceleration and target motion constrain actual fire.
static func metrics(spec: Dictionary) -> Dictionary:
	var capacity: float=maxf(0.0,float(spec.get("ammoCapacity",0.0)))
	var mounts: Array=[]
	var full_rate_ammo: float=0.0
	var reach: float=0.0
	for raw in spec.get("weaponMounts",[]):
		var mount: Dictionary=raw.duplicate(true)
		var rate: float=maxf(0.0,float(mount.get("fireRate",0.0)))
		var cost: float=maxf(0.0,float(mount.get("ammoCost",0.0)))
		mount.reloadSeconds=1.0/rate if rate>0.0 else 0.0
		mount.arcDegrees=rad_to_deg(float(mount.get("arc",TAU)))
		# Each count assumes THIS mount alone spends the full shared capacity.
		mount.capacityShotsAlone=int(floor(capacity/cost)) if cost>0.0 else 0
		mount.fullRateAmmoPerSecond=rate*cost
		mounts.append(mount)
		full_rate_ammo+=rate*cost
		reach=maxf(reach,float(mount.get("range",0.0)))
	var turn: float=maxf(0.0,float(spec.get("turn",0.0)))
	return {
		"mounts":mounts,"range":reach,"deploymentPoints":int(spec.get("deploymentPoints",0)),
		"handling":{"speed":float(spec.get("speed",0.0)),"turn":turn,"fuelUse":float(spec.get("fuelUse",1.0)),"minimumHalfTurnSeconds":PI/turn if turn>0.0 else 0.0},
		"survival":{"hp":float(spec.get("hp",0.0)),"armor":float(spec.get("armor",0.0)),"pumps":float(spec.get("pumps",0.0)),"crewMin":float(spec.get("crewMin",0.0)),"crewOptimal":float(spec.get("crewOptimal",0.0))},
		"ammo":{"capacity":capacity,"fullRateUnitsPerSecond":full_rate_ammo,"fullRateSeconds":capacity/full_rate_ammo if full_rate_ammo>0.0 else 0.0},
		"basis":"Design only. Reloads/turning assume full efficiency; all mounts share the carried rounds. Full-rate seconds assume every fitted mount fires continuously within arc, without reserve or safety holds. Fuel-use multiplier is not voyage or battle endurance. Prices, scarce stock, labor, condition and payment come from the current workshop quote."
	}
