extends RefCounted
## Time-limited protection and withdrawal objectives; the normal battle remains annihilation.
static func update(st: Dictionary) -> void:
	var mission: Dictionary=st.get("mission",{})
	if mission.is_empty() or st.result!=null:return
	if mission.get("kind","")=="escort":
		var protected: Array=st.ships.filter(func(b):return str(b.get("uid","")) in mission.get("allyUids",[]))
		if protected.is_empty() or protected.any(func(b):return b.sunk):
			st.result="lost";st.objectiveSuccess=false
		elif st.time>=float(mission.get("duration",45)):
			st.result="won";st.objectiveSuccess=true
			st.objectiveOnly=st.ships.any(func(b):return b.team=="enemy" and not b.sunk)

static func label(st: Dictionary) -> String:
	var mission: Dictionary=st.get("mission",{})
	if mission.get("kind","")=="escort":return "Protect the convoy · %.0fs remaining"%maxf(0,float(mission.get("duration",45))-float(st.time))
	return "Defeat the opposing fleet; withdraw when the cost is too high."
