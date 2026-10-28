extends RefCounted
## Original small nautical illustrations, placed over the authored chart only.
## These are observations and objects, never filled replacement islands, terrain,
## rewards or a second navigation model. Preparation creates no render resources.

const TEMPLATE_LIMIT: int=64
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

static func _observation(kind: String) -> String:
	match kind:
		"freshwater_cove":return "Gulls over still water"
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
			for i in range(3):
				var y: float=3.0+float(i)*5.0
				_stroke(out,[[-22,y],[-9,y-2],[7,y-1],[21,y-4]],Color(FOAM,0.32),1.2)
			if kind=="freshwater_cove":
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
	var kind: String=str(site.get("kind","sighting"))
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
