extends SceneTree
## Offline audition inputs only: labelled reported-event examples, not earned damage.
const SoundPolicy=preload("res://scripts/sound.gd")
func _initialize() -> void:
	var out: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not out.is_absolute_path():quit(2);return
	var rows: Array=[]
	var cases: Array=[
		["MG burst",0.0,"gun","fire","metal"],
		["MG wood contact",1.7,"gun","hit","wood"],
		["Cannon report",3.4,"cannon","fire","metal"],
		["Cannon armor hit",5.3,"cannon","hit","armor"],
		["Rocket launch",7.2,"rocket","fire","metal"],
		["Rocket hit",9.1,"rocket","hit","metal"],
		["Torpedo launch",11.0,"torpedo","fire","water"],
		["Torpedo hit",12.9,"torpedo","hit","water"],
		["Engine failure",15.0,"rocket","engine","engine"],
		["Sinking",16.9,"cannon","sink","wood"],
		["Cannon distance1600",19.0,"cannon","fire","metal"]]
	var checks: int=0
	var failures: int=0
	for index in range(cases.size()):
		var item: Array=cases[index]
		var event: Dictionary={"seq":index+1,"kind":item[3],"family":item[2],"material":item[4],"variant":"light","breach":item[3]=="hit","engineDamaged":item[3]=="engine"}
		var layers: Array=SoundPolicy.event_layers(event)
		checks+=1
		if layers.is_empty():failures+=1
		rows.append({"label":item[0],"seconds":item[1],"event":event,"layers":layers,"distanceDb":SoundPolicy.attenuation_db(1600.0 if index==cases.size()-1 else 0.0)})
	var file=FileAccess.open(out.path_join("audio-policy071.json"),FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"cases":rows,"scope":"Labelled offline policy examples; actual current Sound.event_layers, not live playback or witnessed battle damage","weaponVolume":0.85}));file.close()
	print(checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
