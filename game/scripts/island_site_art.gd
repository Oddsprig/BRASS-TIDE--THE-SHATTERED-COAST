extends RefCounted
## Small original chart landmarks. No textures, water simulation or animated crew.
static func draw_site(chart,site: Dictionary,level: int,selected: bool) -> void:
	var p: Vector2=chart.project(Vector2(site.x,site.y))
	if not chart.get_viewport_rect().grow(90).has_point(p):return
	var color: Color=Color("dfbd7d") if level<3 else Color("8ac9b6")
	var size: float=6.0 if chart.scale_factor<0.18 else 9.0
	chart.draw_circle(p,size+4,Color(color,0.10))
	chart.draw_arc(p,size+3,0,TAU,20,Color(color,0.7),1.0,true)
	var kind: String=str(site.get("kind",""))
	if level==1:
		chart.text_at("?",p+Vector2(0,4),13,color,chart.sans,true)
	elif kind in ["workshop_ruin","defended_camp"]:
		chart.draw_rect(Rect2(p+Vector2(-7,-3),Vector2(14,10)),Color("526d66"))
		chart.draw_colored_polygon(PackedVector2Array([p+Vector2(-10,-3),p+Vector2(0,-10),p+Vector2(10,-3)]),Color("bd9871"))
		chart.draw_line(p+Vector2(3,0),p+Vector2(3,6),color,2)
	elif kind in ["wreck_field","salvage_anchorage"]:
		chart.draw_line(p+Vector2(-8,5),p+Vector2(7,-5),Color("b89d79"),4)
		chart.draw_line(p+Vector2(-4,-7),p+Vector2(5,8),Color("596b67"),3)
		chart.draw_line(p+Vector2(0,0),p+Vector2(1,-12),color,1)
	elif kind in ["timber_stand","marsh_landing"]:
		for x in [-5,3]:chart.draw_colored_polygon(PackedVector2Array([p+Vector2(x,-10),p+Vector2(x-6,5),p+Vector2(x+6,5)]),Color("84a383"))
	else:
		chart.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(8,4),p+Vector2(0,8),p+Vector2(-8,4)]),color.darkened(0.25))
	if selected or chart.scale_factor>0.26:
		chart.text_at(str(site.name),p+Vector2(0,-24),12,color,chart.sans,true)
