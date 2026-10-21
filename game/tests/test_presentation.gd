extends SceneTree
const Main=preload("res://scripts/main.gd")
const Profiles=preload("res://scripts/hull_profiles.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const Geometry=preload("res://scripts/weapon_geometry.gd")
const Refit=preload("res://scripts/refit.gd")
const Battle=preload("res://scripts/battle.gd")
const Damage=preload("res://scripts/damage.gd")
const Preferences=preload("res://scripts/preferences.gd")
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error("PRESENTATION: "+message)

func _initialize():call_deferred("run")

func run():
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var signatures: Dictionary={}
	check(Profiles.hull_ids().size()==24,"complete original hull profile roster")
	for spec in world.HULLS:
		var original: Dictionary=spec.duplicate(true)
		check(Profiles.has_hull(spec.id),"profile exists "+spec.id)
		var profile: Dictionary=Profiles.profile(spec)
		var stations: Array=profile.stations
		signatures[str(stations)]=true
		check(stations.size()>=7 and stations[-1].y==0,"closed original prow "+spec.id)
		for i in range(1,stations.size()):check(stations[i].x>stations[i-1].x,"ordered hull sections "+spec.id)
		for point in Layout.hardpoints(spec):
			var supported=true
			if profile.archetype!="catamaran":
				for offset in [-point.footprintRadius,0.0,point.footprintRadius]:
					var x: float=point.localX+offset
					var width: float=0.0
					for i in range(stations.size()-1):
						if x>=stations[i].x and x<=stations[i+1].x:
							width=lerpf(stations[i].y,stations[i+1].y,(x-stations[i].x)/(stations[i+1].x-stations[i].x))*0.97
					if absf(float(point.localY))+float(point.footprintRadius)>width+0.001:supported=false
			else:supported=point.localX-point.footprintRadius>=-1.80 and point.localX+point.footprintRadius<=1.45
			check(supported,"physical socket supported by actual hull deck "+spec.id+" "+point.id)
		check(spec==original,"art profiles leave numerical hull untouched "+spec.id)
		for weapon in ["rapid_gun","light_cannon","fire_rocket","light_torpedo"]:
			var fit: Dictionary=Refit.defaults(spec)
			fit.weapons[0]=weapon
			var effective: Dictionary=Refit.effective_spec(spec,fit)
			var ship: Dictionary=Damage.create_ship(effective)
			var target: Dictionary=Damage.create_ship(world.HULLS[23],{"ammo":0.0})
			var battle: Dictionary=Battle.create({"fleet":[ship],"enemyFleet":[target],"seed":613})
			ship.x=500.0;ship.y=850.0;ship.angle=0.0
			target.x=750.0;target.y=850.0
			Battle._fire(battle,ship,Vector2(target.x,target.y))
			check(battle.projectiles.size()==1,"real fitted weapon launches "+spec.id+" "+weapon)
			if not battle.projectiles.is_empty():
				var mount: Dictionary=effective.weaponMounts[0]
				var shot: Dictionary=battle.projectiles[0]
				var origin=Vector2(ship.x+mount.x,ship.y+mount.y)
				var bearing: float=(Vector2(target.x,target.y)-origin).angle()
				var expected: Vector2=origin+Vector2.from_angle(bearing)*Geometry.muzzle(mount.kind,spec.size,mount.size)
				check(Vector2(shot.x,shot.y).distance_to(expected)<0.001,"projectile begins at displayed barrel/tube tip "+spec.id+" "+weapon)
				check(is_equal_approx(float(shot.height),Geometry.height(mount.kind,spec.size,mount.size)),"projectile uses physical firing height / torpedo waterline")
	check(signatures.size()==24,"all24 silhouette station sequences are distinct")
	var game=Main.new();root.add_child(game);await process_frame
	game.save_directory=OS.get_user_data_dir().path_join("presentation-saves")
	game.preferences_path=OS.get_user_data_dir().path_join("presentation-options.json")
	game.new_game();game.paused=true
	game.chart.territory_view()
	check(game.chart.camera==Vector2(world.WORLD.width,world.WORLD.height)*0.5 and game.chart.zoom<0.4,"M frames actual expanded territory")
	game.chart.center_camera()
	check(game.chart.zoom==1.0 and game.chart.follow_camera,"Home restores regional fleet view")
	game.chart.camera=Vector2(world.WORLD.width-10,world.WORLD.height-10)
	game.chart.pan_camera(Vector2.RIGHT,1.0,true)
	check(game.chart.camera.x>2600 and game.chart.camera.x<=world.WORLD.width+450,"camera can pan beyond legacy map within current bounds")
	game.audio.weapon_volume=0.27;game.audio.ambience_volume=0.14;game.music.volume=0.32;game.dev_enabled=true
	game.save_preferences()
	var options: Dictionary=Preferences.load_options(game.preferences_path)
	check(is_equal_approx(options.weapon_volume,0.27) and is_equal_approx(options.music_volume,0.32) and options.dev_enabled,"portable options round-trip separately from voyage")
	var malformed: Dictionary=Preferences.sanitize({"weapon_volume":NAN,"music_volume":9.0,"frame_cap":999,"dev_enabled":"yes"})
	check(malformed.weapon_volume==0.85 and malformed.music_volume==1.0 and malformed.frame_cap==120 and malformed.dev_enabled==false,"malformed options cannot poison audio/video state")
	var roles: Dictionary={}
	for track in game.music.tracks:roles[track.role]=true
	for role in ["title","travel","harbor","contact","combat","finale","victory","loss"]:check(roles.has(role),"owner music available for "+role)
	game.music.set_context("harbor")
	var variations: Dictionary={}
	var harbor_pool: Array=game.music.tracks.filter(func(track):return track.role=="harbor")
	for i in range(harbor_pool.size()):
		game.music.next_track();variations[game.music.current]=true
	check(variations.size()==harbor_pool.size(),"music cycles every supplied harbor variation before repeating")
	game.ui.open_menu();await process_frame;game.ui.close_modal()
	game.queue_free();await process_frame
	print("PRESENTATION: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
