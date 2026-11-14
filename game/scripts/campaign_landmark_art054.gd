extends RefCounted
## Original small nautical illustrations, placed over the authored chart only.
## These are observations and objects, never filled replacement islands, terrain,
## rewards or a second navigation model. Preparation creates no render resources.

const TEMPLATE_LIMIT: int=96
const COMMAND_LIMIT: int=80
const INK:=Color("31494b")
const LIGHT:=Color("d5c9a0")
const FOAM:=Color("99c4b3")
const RUST:=Color("ae795b")
const WOOD:=Color("977b56")
static var _templates: Dictionary={}

static func _poly(out: Array,pairs: Array,color: Color) -> void:
	var points:=PackedVector2Array()
	for p in pairs:points.append(Vector2(p[0],p[1]))
	out.append({"type":"poly","points":points,"color":color})

static func _stroke(out: Array,pairs: Array,color: Color,width: float=1.2) -> void:
	var points:=PackedVector2Array()
	for p in pairs:points.append(Vector2(p[0],p[1]))
	out.append({"type":"line","points":points,"color":color,"width":width})

static func _oval(out: Array,at: Vector2,size: Vector2,color: Color) -> void:
	var points:=PackedVector2Array()
	for i in range(12):points.append(at+Vector2.from_angle(float(i)*TAU/12.0)*size)
	out.append({"type":"poly","points":points,"color":color})

static func _box(out: Array,at: Vector2,size: Vector2,color: Color) -> void:
	var half: Vector2=size*0.5
	_poly(out,[[at.x-half.x,at.y-half.y],[at.x+half.x,at.y-half.y],[at.x+half.x,at.y+half.y],[at.x-half.x,at.y+half.y]],color)

static func _wash(out: Array,detail: bool) -> void:
	# Broken strokes describe water around the object; there is no opaque disk.
	_stroke(out,[[-28,13],[-20,12],[-11,13]],Color(FOAM,0.35),1.0)
	_stroke(out,[[8,17],[18,18],[28,16]],Color(FOAM,0.3),1.0)
	if detail:_stroke(out,[[-25,20],[-15,21],[-6,20]],Color(FOAM,0.22),1.0)

static func _spar(out: Array,x: float,y: float,lean: float,detail: bool) -> void:
	_stroke(out,[[x-7,y+7],[x-11,y-4],[x-2,y-8],[x+8,y-5],[x+11,y+2],[x+6,y+7]],WOOD,3.3)
	_stroke(out,[[x-7,y+6],[x+5,y+6]],LIGHT,1.1)
	_stroke(out,[[x,y+4],[x+lean,y-23]],Color("aeaa8c"),2.0)
	_stroke(out,[[x-8,y-9],[x+10,y-12]],RUST,1.6)
	if detail:
		_stroke(out,[[x-7,y+4],[x+lean,y-22],[x+9,y+3]],Color(LIGHT,0.55),0.8)
		for dx in [-5.0,0.0,5.0]:_stroke(out,[[x+dx,y-4],[x+dx+2,y+5]],INK,1.0)

static func _reeds(out: Array,detail: bool) -> void:
	for i in range(7 if detail else 4):
		var x: float=-22.0+float(i)*7.0
		var y: float=3.0+float(i%3)*2.0
		_stroke(out,[[x-3,y+8],[x,y-8-float(i%2)*5],[x+3,y+7]],Color("91a582"),1.3)
		_stroke(out,[[x,y-7],[x+5,y-11]],Color("b4b28a"),1.0)

static func _crown(out: Array,at: Vector2,size: float) -> void:
	# Irregular rounded crown rather than a map triangle; no ground silhouette.
	_oval(out,at+Vector2(2,2),Vector2(size,size*0.7),Color("365c4a"))
	_oval(out,at+Vector2(-2,-2),Vector2(size*0.8,size*0.6),Color("648264"))
	_stroke(out,[[at.x-size*0.3,at.y+size*0.45],[at.x,at.y-2],[at.x+size*0.4,at.y]],Color("8c9e75"),1.0)

static func _resolve_kind(site: Dictionary) -> String:
	var raw_kind: String=str(site.get("kind","")).strip_edges()
	var sid: String=str(site.get("id","")).strip_edges()
	var clue: String=str(site.get("clue","")).strip_edges().to_lower()
	var res: String=str(site.get("resource","")).strip_edges().to_lower()
	if raw_kind in ["bearing_marker","signal_log","expedition_cache","survey_terrace","survey_timber","survey_ore","survey_crude","survey_herbs","survey_saltpeter"]:
		return raw_kind
	match sid:
		"glasswind_west_marker":return "bearing_marker"
		"glasswind_crown_log":return "signal_log"
		"glasswind_south_wreck":return "expedition_cache"
	if raw_kind=="sector_survey" or sid.ends_with("_survey") or (raw_kind.is_empty() and not clue.is_empty()):
		if clue.contains("terrace") or res=="food":return "survey_terrace"
		if clue.contains("dark stands") or clue.contains("trunk") or res=="logs":return "survey_timber"
		if clue.contains("rust-colored") or clue.contains("ore") or res=="ore":return "survey_ore"
		if clue.contains("dark sheen") or clue.contains("seep") or res=="crude":return "survey_crude"
		if clue.contains("pale-leaved") or clue.contains("medicinal") or res=="medicinal_plants":return "survey_herbs"
		if clue.contains("white mineral") or clue.contains("crust") or res=="saltpeter":return "survey_saltpeter"
		if raw_kind=="sector_survey" or sid.ends_with("_survey"):return "survey_terrace"
	return raw_kind if not raw_kind.is_empty() else "sighting"

static func _observation(kind: String) -> String:
	match kind:
		"freshwater_cove":return "Unsurveyed site"
		"shoal_shortcut":return "Pale lane through kelp"
		"defended_camp":return "Smoke along the shore"
		"timber_stand":return "Dark coastal crowns"
		"salt_seam":return "Glittering tidal flats"
		"marsh_landing":return "Reed bundles on poles"
		"ore_seam":return "Rust-red shore scree"
		"workshop_ruin":return "Broken shore gantry"
		"sheltered_inlet":return "Calm behind the headland"
		"oil_seep":return "Rainbow surface sheen"
		"sulfur_vents":return "Yellow shore staining"
		"chart_fragment":return "Cairn and bottle-post"
		"salvage_anchorage":return "Leaning spars in a bay"
		"wreck_field":return "Breakers over dark shapes"
		"bearing_marker":return "Pale stones above landing"
		"signal_log":return "Broken ridge signal frame"
		"expedition_cache":return "Split timbers in pale surf"
		"survey_terrace","sector_survey":return "Terraced slope above landing"
		"survey_timber":return "Dark ridge stands above shore"
		"survey_ore":return "Rust-banded coastal rock"
		"survey_crude":return "Dark sheen in tidal rock"
		"survey_herbs":return "Pale-leaved growth in saddle"
		"survey_saltpeter":return "White-crusted dry ledges"
	return "Coastal sighting"

static func _commands(kind: String,detail: bool,identified: bool) -> Array:
	var key: String="%s:%s:%s"%[kind,str(detail),str(identified)]
	if _templates.has(key):return _templates[key]
	var out: Array=[]
	_wash(out,detail)
	match kind:
		"wreck_field","wreck":
			# A split hull, exposed ribs and a leaning spar, with broken foam lines.
			if identified:
				_poly(out,[[-23,2],[-18,-7],[-6,-10],[2,-5],[-3,0],[-17,6]],Color("766c50"))
				_poly(out,[[4,-8],[17,-6],[25,0],[17,6],[2,4],[7,0]],Color("978568"))
				_stroke(out,[[-21,0],[-16,-5],[-6,-7]],LIGHT,1.4)
				_stroke(out,[[5,-6],[17,-4],[22,0]],RUST,1.2)
				_stroke(out,[[-4,3],[-10,-23]],Color("b7b294"),2.1)
			else:
				_stroke(out,[[-22,1],[-11,-4],[-5,-2]],Color("738779"),3.0)
				_stroke(out,[[8,-2],[18,0],[22,-3]],Color("8d977e"),2.0)
			if detail:
				if identified:
					for x in [-17.0,-11.0,10.0,16.0]:_stroke(out,[[x,-5],[x+2,3]],INK,1.3)
				_stroke(out,[[-19,8],[-12,7],[-6,9]],Color(FOAM,0.8),1.3)
				_stroke(out,[[12,9],[20,8],[25,6]],Color(FOAM,0.8),1.3)
		"salvage_anchorage":
			_spar(out,-10,0,-6,detail)
			_spar(out,12,7,5,detail)
			if identified:_stroke(out,[[-26,4],[-22,-3],[-18,-1]],Color("c2a476"),2.3)
		"cargo_float":
			# A real jettison record has cargo floats rather than a promised hull.
			_poly(out,[[-21,-4],[-3,-10],[14,-4],[23,5],[5,12],[-16,8]],WOOD)
			for item in [Vector2(-9,-2),Vector2(4,1),Vector2(11,7)]:
				_box(out,item,Vector2(9,6),Color("b59b70"))
				_stroke(out,[[item.x-3,item.y-3],[item.x+3,item.y+3]],Color("746346"),1.0)
			_stroke(out,[[-19,4],[21,1]],Color("d6c295"),1.4)
			_stroke(out,[[17,2],[20,-10]],LIGHT,1.4)
			_box(out,Vector2(21,-11),Vector2(5,3),RUST)
		"workshop_ruin":
			_poly(out,[[-23,7],[-23,-8],[-14,-12],[-14,3],[-5,6],[-5,-4],[4,-1],[4,12]],Color("8d8a72"))
			_poly(out,[[3,8],[3,-3],[11,-6],[11,5],[23,8],[23,14]],Color("a59b7c"))
			_stroke(out,[[-17,3],[-17,-25],[17,-22],[17,8]],RUST,3.0)
			_stroke(out,[[-18,-23],[15,-20]],LIGHT,1.2)
			_stroke(out,[[9,-20],[9,-9],[12,-6]],INK,1.4)
			if detail:
				_stroke(out,[[-15,-19],[-6,-22],[-12,-10],[1,-21]],Color("5e665b"),1.0)
				for x in [-19.0,-12.0,16.0]:_box(out,Vector2(x,9),Vector2(5,2),Color("c1ad8b"))
		"chart_fragment":
			# Only the authored clue's rock/cairn is pictured; no new island contour.
			_poly(out,[[-13,8],[-8,-1],[1,-4],[10,2],[13,9],[1,13]],Color("858f81"))
			_poly(out,[[-7,2],[-3,-5],[4,-7],[8,1],[0,6]],Color("bcc0a1"))
			_poly(out,[[-3,-5],[0,-11],[4,-8],[4,-4]],Color("d2c8a3"))
			_stroke(out,[[14,6],[14,-18]],WOOD,2.0)
			_box(out,Vector2(15,-13),Vector2(5,7),Color("80a99a"))
			if detail:_stroke(out,[[13,-15],[16,-16]],LIGHT,1.0)
		"timber_stand":
			for item in [Vector3(-16,0,10),Vector3(0,-8,12),Vector3(16,1,9)]:
				_stroke(out,[[item.x,item.y+4],[item.x,item.y+12]],WOOD,2.2)
				_crown(out,Vector2(item.x,item.y),item.z)
			if detail:_stroke(out,[[-24,14],[-8,11],[7,14]],Color(LIGHT,0.5),1.1)
		"marsh_landing":
			_reeds(out,detail)
			_stroke(out,[[-17,5],[13,3]],WOOD,3.5)
			for x in [-15.0,9.0]:
				_stroke(out,[[x,8],[x,-16]],LIGHT,1.8)
				_box(out,Vector2(x+2,-10),Vector2(7,6),Color("a4a36f"))
			_stroke(out,[[-16,-13],[10,-13]],Color("c3b18a"),1.0)
		"shoal_shortcut":
			# Open pale water lane and separate kelp fronds, never opaque land.
			_stroke(out,[[-27,6],[-10,-3],[10,-1],[27,-10]],Color(FOAM,0.42),4.5)
			for i in range(6 if detail else 3):
				var x: float=-21.0+float(i)*8.0
				var y: float=-10.0 if i%2==0 else 11.0
				_stroke(out,[[x-3,y+4],[x,y],[x-1,y-6],[x+3,y-8]],Color("6b927b"),1.7)
				if detail:_stroke(out,[[x,y],[x+5,y-2]],Color("94ad82"),1.0)
		"freshwater_cove","sheltered_inlet":
			_poly(out,[[-23,6],[-16,-4],[-7,-2],[-11,8]],Color("7c8c7e"))
			for i in range(3):
				var y: float=3.0+float(i)*5.0
				_stroke(out,[[-22,y],[-9,y-2],[7,y-1],[21,y-4]],Color(FOAM,0.32),1.2)
			if kind=="freshwater_cove":
				_stroke(out,[[-14,-3],[-10,6]],Color(FOAM,0.72),1.5)
				for item in [Vector2(-15,-11),Vector2(2,-19),Vector2(17,-8)]:
					_stroke(out,[[item.x-5,item.y],[item.x-2,item.y-2],[item.x,item.y],[item.x+3,item.y-2],[item.x+6,item.y-1]],Color("d5d7bc"),1.3)
			else:
				_stroke(out,[[-17,-15],[-9,-15],[-9,-6],[-5,-2]],WOOD,2.1)
				if detail:_stroke(out,[[-7,-12],[0,-13],[6,-11]],Color(LIGHT,0.55),1.0)
		"defended_camp":
			# Sighted smoke never promises the hidden camp's defenders or rewards.
			for item in [Vector3(-4,5,5),Vector3(1,-4,6),Vector3(-4,-15,7)]:
				_oval(out,Vector2(item.x,item.y),Vector2(item.z,item.z*0.65),Color(Color("aeb5a1"),0.42))
			_stroke(out,[[-12,9],[-4,12],[5,9]],Color("a58458"),2.0)
			if identified:
				_poly(out,[[-25,10],[-18,-2],[-7,7],[-15,13]],Color("a69972"))
				_stroke(out,[[-18,-2],[-15,13]],LIGHT,1.2)
				_stroke(out,[[-5,8],[6,6],[14,9]],WOOD,1.6)
		"salt_seam","ore_seam","sulfur_vents":
			var tone: Color=Color("c1bc99") if kind=="salt_seam" else Color("b88262") if kind=="ore_seam" else Color("bdb573")
			for i in range(4 if detail else 3):
				var x: float=-21.0+float(i)*12.0
				var y: float=float(i%2)*7.0
				_poly(out,[[x-5,y+3],[x-3,y-5],[x+3,y-7],[x+7,y-1],[x+4,y+5]],tone.darkened(float(i%2)*0.13))
				_stroke(out,[[x-3,y-4],[x+1,y-5],[x+4,y-1]],tone.lightened(0.2),1.2)
			if kind=="sulfur_vents" and detail:
				_oval(out,Vector2(-9,-13),Vector2(5,3),Color(Color("c0c2a1"),0.3))
				_oval(out,Vector2(5,-20),Vector2(6,3),Color(Color("c0c2a1"),0.22))
		"oil_seep":
			for i in range(5 if detail else 3):
				var y: float=-9.0+float(i)*5.0
				var tones: Array=[Color("859d91"),Color("998e9b"),Color("a5a37d"),Color("729a9b"),Color("a68a7b")]
				_stroke(out,[[-24,y],[-11,y-4],[3,y-2],[20,y-6]],Color(tones[i],0.68),2.0)
		"bearing_marker":
			_poly(out,[[-22,10],[-12,4],[6,3],[21,9],[14,14],[-15,14]],Color("869488"))
			_poly(out,[[-11,7],[-13,-14],[-7,-18],[-4,-12],[-5,7]],Color("c9ceb8"))
			_poly(out,[[-11,7],[-13,-14],[-9,-16],[-8,6]],Color("e2dec0"))
			_poly(out,[[3,6],[2,-11],[7,-14],[10,-9],[9,6]],Color("b4baa4"))
			if identified:
				_stroke(out,[[-15,-9],[13,-6]],Color("d6b878"),1.6)
				_box(out,Vector2(-1,6),Vector2(7,4),Color("9ea596"))
			if detail:
				_stroke(out,[[-18,11],[-6,9],[11,10]],LIGHT,1.1)
		"signal_log":
			_poly(out,[[-23,11],[-14,2],[2,0],[19,5],[23,12],[-12,14]],Color("7f8d84"))
			_poly(out,[[-15,4],[-6,-2],[8,-1],[14,5],[-4,7]],Color("a8b1a2"))
			_poly(out,[[-8,4],[-5,-4],[4,-4],[7,4]],Color("9ca494"))
			_stroke(out,[[-11,5],[-4,-21],[3,4]],WOOD,2.4)
			_stroke(out,[[-16,-14],[11,-19]],Color("bfa87e"),2.0)
			if identified:
				_box(out,Vector2(9,-16),Vector2(6,5),RUST)
				_stroke(out,[[13,4],[13,-9]],LIGHT,1.4)
			if detail:
				_stroke(out,[[-17,3],[-4,-19],[14,4]],Color(LIGHT,0.5),1.0)
		"expedition_cache":
			_poly(out,[[-24,9],[-15,1],[-3,3],[2,11],[-18,13]],Color("697b75"))
			_poly(out,[[-17,6],[-12,-8],[1,-11],[6,-3],[-3,5]],WOOD)
			_stroke(out,[[-14,-5],[0,-8]],LIGHT,1.3)
			_poly(out,[[5,6],[7,-4],[18,-3],[20,7]],Color("8d7a58"))
			_stroke(out,[[6,1],[19,2]],LIGHT,1.2)
			if identified:
				_box(out,Vector2(13,-6),Vector2(8,5),Color("c8a96e"))
				_stroke(out,[[17,5],[17,-15]],LIGHT,1.4)
			if detail:
				for x in [-13.0,-8.0,-3.0]:_stroke(out,[[x,-4],[x+2,3]],INK,1.1)
		"survey_terrace","sector_survey":
			_poly(out,[[-23,11],[-15,4],[16,3],[23,10]],Color("8b9276"))
			_poly(out,[[-19,3],[-12,-4],[13,-5],[18,2]],Color("9ea87a"))
			_poly(out,[[-13,-5],[-7,-12],[9,-12],[13,-6]],Color("b3b888"))
			_stroke(out,[[-20,4],[19,3]],LIGHT,1.5)
			_stroke(out,[[-15,-4],[15,-5]],Color("c8c09a"),1.4)
			if identified:
				_stroke(out,[[12,3],[12,-17]],WOOD,1.8)
				_box(out,Vector2(14,-14),Vector2(5,4),Color("d5b97b"))
			if detail:
				_stroke(out,[[2,-12],[0,10]],Color(FOAM,0.75),1.5)
		"survey_timber":
			_poly(out,[[-22,10],[-14,2],[4,1],[20,7],[14,13],[-16,13]],Color("78886e"))
			for item in [Vector3(-14,-2,9),Vector3(-1,-9,11),Vector3(13,-1,9)]:
				_stroke(out,[[item.x,item.y+3],[item.x,item.y+11]],WOOD,2.2)
				_crown(out,Vector2(item.x,item.y),item.z)
			_stroke(out,[[-18,9],[8,6]],WOOD,2.6)
			if identified:
				_stroke(out,[[15,7],[15,-12]],LIGHT,1.5)
				_box(out,Vector2(17,-9),Vector2(5,4),RUST)
			if detail:
				_stroke(out,[[-16,9],[6,6]],LIGHT,1.0)
		"survey_ore":
			_poly(out,[[-23,10],[-17,-6],[-4,-13],[9,-9],[21,2],[17,11],[-14,12]],Color("7d8278"))
			_poly(out,[[-16,-5],[-4,-13],[8,-9],[2,-1]],Color("a3a596"))
			_poly(out,[[-18,4],[-8,-5],[2,-3],[-9,6]],RUST)
			_poly(out,[[-4,5],[6,-4],[15,-2],[5,7]],Color("c47b54"))
			if identified:
				_stroke(out,[[14,2],[14,-16]],LIGHT,1.6)
				_box(out,Vector2(16,-13),Vector2(5,4),RUST)
			if detail:
				_stroke(out,[[-15,1],[-7,-4]],Color("e0a97e"),1.2)
				_stroke(out,[[-1,2],[8,-3]],Color("e0a97e"),1.2)
		"survey_crude":
			_poly(out,[[-23,9],[-14,-2],[-2,-4],[-5,8]],Color("637270"))
			_poly(out,[[2,-5],[15,-3],[22,6],[9,10],[1,4]],Color("72827e"))
			_poly(out,[[-5,4],[-1,-5],[5,-3],[2,7]],Color("27383a"))
			for i in range(4 if detail else 2):
				var y: float=-2.0+float(i)*3.5
				var tones: Array=[Color("859d91"),Color("998e9b"),Color("c2a978"),Color("729a9b")]
				_stroke(out,[[-18,y],[-4,y-2],[7,y-1],[19,y-3]],Color(tones[i],0.75),1.7)
			if identified:
				_stroke(out,[[12,-2],[12,-18]],WOOD,1.8)
				_box(out,Vector2(14,-15),Vector2(5,4),Color("c2a978"))
		"survey_herbs":
			_poly(out,[[-24,10],[-19,-6],[-9,-8],[-4,4],[-14,11]],Color("7c8874"))
			_poly(out,[[6,4],[11,-7],[20,-5],[23,9],[12,11]],Color("8c9680"))
			_oval(out,Vector2(-3,2),Vector2(8,5),Color("6f926e"))
			_oval(out,Vector2(3,0),Vector2(7,4.5),Color("a3bd92"))
			_oval(out,Vector2(-1,-3),Vector2(6,3.5),Color("cfe0bc"))
			if identified:
				_stroke(out,[[-11,6],[10,6]],WOOD,2.0)
				_stroke(out,[[14,-4],[14,-17]],LIGHT,1.5)
			if detail:
				for dx in [-6.0,-1.0,4.0]:_stroke(out,[[dx,2],[dx+1,-5]],Color("e4edd2"),1.1)
		"survey_saltpeter":
			_poly(out,[[-23,10],[-18,-3],[-3,-8],[14,-6],[22,4],[15,11],[-15,11]],Color("7f7d6e"))
			_poly(out,[[-15,-3],[-3,-12],[12,-10],[16,-3]],Color("9a9582"))
			_poly(out,[[-16,2],[-7,-2],[4,-1],[-4,4]],Color("e3dec8"))
			_poly(out,[[1,-4],[11,-6],[17,-2],[8,0]],Color("ebe7d5"))
			_stroke(out,[[-14,-4],[12,-7]],Color("f2efe0"),1.6)
			if identified:
				_box(out,Vector2(13,4),Vector2(7,5),WOOD)
				_stroke(out,[[16,2],[16,-15]],LIGHT,1.5)
			if detail:
				_stroke(out,[[-12,3],[5,1]],Color("f7f4e8"),1.2)
		_:
			_stroke(out,[[-19,2],[-9,-3],[6,-1],[20,-7]],FOAM,1.4)
	if _templates.size()>=TEMPLATE_LIMIT:_templates.erase(_templates.keys()[0])
	_templates[key]=out
	return out

static func _make(kind: String,level: int,center: Vector2,chart_scale: float,label: String) -> Dictionary:
	var lod: int=0 if chart_scale<0.18 else 1
	var factor: float=0.52 if lod==0 else clampf(0.85+chart_scale*0.45,0.95,1.35)
	var commands: Array=_commands(kind,lod>0,level>=2)
	var bounds:=Rect2(center,Vector2.ZERO)
	for command: Dictionary in commands:
		for point: Vector2 in command.points:bounds=bounds.expand(center+point*factor)
	return {"kind":kind,"knowledge":level,"identified":level>=2,"center":center,"bounds":bounds.grow(3.0),
		"lod":lod,"scale":factor,"commands":commands,"label":label,"primitive_count":commands.size()}

static func plan(site: Dictionary,level: int,center: Vector2,chart_scale: float) -> Dictionary:
	if level<=0:return {"kind":"hidden","knowledge":0,"identified":false,"center":center,"bounds":Rect2(),"lod":0,"scale":1.0,"commands":[],"label":"","primitive_count":0}
	var known: int=clampi(level,1,3)
	var kind: String=_resolve_kind(site)
	return _make(kind,known,center,chart_scale,str(site.get("name","Coastal site")) if known>=2 else _observation(kind))

static func wreck_plan(wreck: Dictionary,center: Vector2,chart_scale: float) -> Dictionary:
	if str(wreck.get("status",""))!="unclaimed":return plan({},0,center,chart_scale)
	var kind: String="cargo_float" if str(wreck.get("hull","")).is_empty() else "wreck"
	return _make(kind,2,center,chart_scale,"Cargo float" if kind=="cargo_float" else "Wreckage")

static func draw(canvas,art: Dictionary,selected: bool=false) -> int:
	if int(art.get("knowledge",0))<=0:return 0
	var center: Vector2=art.center
	var factor: float=art.scale
	var count: int=0
	for command: Dictionary in art.get("commands",[]):
		if count>=COMMAND_LIMIT:break
		var points:=PackedVector2Array()
		for point: Vector2 in command.points:points.append(center+point*factor)
		if str(command.type)=="poly":canvas.draw_colored_polygon(points,command.color)
		else:canvas.draw_polyline(points,command.color,maxf(0.8,float(command.width)*factor),true)
		count+=1
	if selected:
		var bounds: Rect2=Rect2(art.bounds).grow(4)
		# Two quiet corner marks behind/around the observation, never an icon fill.
		canvas.draw_polyline(PackedVector2Array([bounds.position+Vector2(0,7),bounds.position,bounds.position+Vector2(8,0)]),LIGHT,1.0,true)
		canvas.draw_polyline(PackedVector2Array([bounds.end-Vector2(0,7),bounds.end,bounds.end-Vector2(8,0)]),LIGHT,1.0,true)
		count+=2
	return count
