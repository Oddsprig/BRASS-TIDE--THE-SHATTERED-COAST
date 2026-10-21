extends RefCounted
## Short, shaped effects in the same cheap 2D projection as boats.
static func effect(chart,e: Dictionary):
	var t: float=clampf(float(e.age)/maxf(0.01,float(e.life)),0,1)
	var alpha: float=1.0-t
	var position=Vector2(e.x,e.y)
	var p: Vector2=chart.project(position,float(e.get("height",0)))
	var direction=Vector2.from_angle(float(e.get("angle",0)))
	var screen_dir: Vector2=(chart.project(position+direction*20.0,float(e.get("height",0)))-p).normalized()
	var side: Vector2=screen_dir.orthogonal()
	var scale_value: float=maxf(0.4,chart.scale_factor)
	var family: String=str(e.get("family","gun"))
	var kind: String=str(e.get("kind","hit"))
	var radius: float=float(e.get("radius",12))*scale_value
	if kind=="fire" and family!="torpedo":
		if t<0.45:
			var length_value: float=float(e.get("length",14))*scale_value*(1.0-t)
			var width: float=float(e.get("width",5))*scale_value
			var points=PackedVector2Array([p-side*width*0.4,p+screen_dir*length_value-side*width*0.18,p+screen_dir*length_value*1.5,p+screen_dir*length_value+side*width*0.18,p+side*width*0.4])
			chart.draw_colored_polygon(points,Color(1,0.65,0.22,alpha))
			chart.draw_line(p,p+screen_dir*length_value,Color(1,0.96,0.76,alpha),maxf(1.0,3.0*scale_value),true)
		if family in ["cannon","rocket"]:
			for i in range(3):
				var drift=-screen_dir*(5+t*18)+side*(i-1)*radius*0.28
				chart.draw_circle(p+drift+Vector2(0,-t*16),radius*(0.2+t*0.4),Color(0.24,0.26,0.25,alpha*0.22))
		return
	if bool(e.get("splash",false)) or family=="torpedo" or e.type=="splash":
		var ground: Vector2=chart.project(position)
		var height_value: float=(8.0 if family=="gun" else 38.0 if family=="cannon" else 60.0)*scale_value*sin(t*PI)
		var spread: float=radius*(0.15+t*0.7)
		for i in range(5):
			var x: float=(i-2)*spread*0.25
			var top=ground+Vector2(x,-height_value*(1.0-absf(i-2)*0.16))
			chart.draw_line(ground+Vector2(x,0),top,Color(0.73,0.91,0.86,alpha*0.8),maxf(1.0,3*scale_value),true)
			chart.draw_circle(top,1.2*scale_value,Color(0.91,0.98,0.91,alpha))
		chart.draw_arc(ground,spread,0.1,PI-0.1,12,Color(0.65,0.88,0.82,alpha*0.5),1.0,true)
		if kind=="miss" or family=="torpedo":return
	if family=="rocket" or kind=="sink":
		for i in range(5):
			var offset=Vector2.from_angle(i*TAU/5.0+float(e.get("seq",0)))*radius*t*0.55
			chart.draw_circle(p+offset+Vector2(0,-t*radius),radius*(0.32+0.18*t),Color(0.28,0.25,0.22,alpha*0.5))
		if t<0.45:chart.draw_circle(p,radius*(0.3+0.4*t),Color(1.0,0.53,0.16,alpha))
	for i in range(mini(7,int(e.get("fragments",4)))):
		var angle: float=float(i)*2.399+float(e.get("seq",0))*0.4
		var delta=Vector2.from_angle(angle)*radius*(0.2+t*1.5)
		var endpoint=p+delta+Vector2(0,t*t*12-t*10)
		var color=Color(1.0,0.8,0.38,alpha) if e.get("material","")=="armor" else Color(0.68,0.48,0.28,alpha)
		chart.draw_line(endpoint,endpoint-delta.normalized()*maxf(2,5*scale_value),color,maxf(1,1.6*scale_value),true)

static func wreck(chart,w: Dictionary):
	var t: float=float(w.get("sinkProgress",1.0))
	var center: Vector2=chart.project(Vector2(w.x,w.y))
	if t<1.0 and w.get("spec") is Dictionary:
		var boat: Dictionary={"spec":w.spec,"x":w.x,"y":w.y,"angle":w.angle+float(w.get("listAngle",0))*t,"turretAngle":w.get("turretAngle",w.angle),"vx":0,"vy":0,"water":0,"fire":0,"breaches":[]}
		var projector=func(pos: Vector2,h: float):return chart.project(pos,h*(1.0-t)-t*12.0)
		chart.BoatArt.draw_boat(chart,projector,boat,{"lod":1,"px":maxf(2,w.size*chart.scale_factor),"accent":Color("65746b")})
	for i in range(5):
		var offset=Vector2.from_angle(i*1.8)*float(w.size)*(0.2+i*0.15)
		var p: Vector2=chart.project(Vector2(w.x,w.y)+offset)
		chart.draw_line(p,p+Vector2(4,1),Color(0.61,0.75,0.66,0.25),1.3,true)
	if float(w.get("age",0))<3.0:chart.draw_arc(center,float(w.size)*chart.scale_factor*(0.8+t),0,TAU,20,Color(0.64,0.85,0.77,(1.0-t)*0.4),1.2,true)
