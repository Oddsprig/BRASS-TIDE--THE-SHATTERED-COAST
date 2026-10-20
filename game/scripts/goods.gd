extends RefCounted
## Fictional production lots, valued in bronze cash through paid worker-days.
## Ingredient lots are economic abstractions, not manufacturing instructions.
const SAILOR_WAGE: int = 100
const ROUNDS_PER_CASE: int = 50
const WAGES: Dictionary = {
	"laborer":100,"farmer":100,"fisher":100,"woodcutter":100,"miner":100,"charcoal burner":100,
	"carpenter":125,"smelter":125,"refiner":125,"shipwright":125,
	"powder worker":150,"gunsmith":150,"mechanic":150,
	"foreman":175,"engineer":200,"master shipwright":200
}
const ITEMS: Dictionary = {
	"food":{"name":"Rice & Fish Rations","unit":"ration bales","weight":1,"color":"#d9a441","inputs":{},"labor":{"farmer":2.0}},
	"logs":{"name":"Raw Logs","unit":"log loads","weight":3,"color":"#99714a","inputs":{},"labor":{"woodcutter":2.0}},
	"timber":{"name":"Seasoned Planks","unit":"plank bundles","weight":2,"color":"#b48b56","inputs":{"logs":1.0},"labor":{"carpenter":1.5}},
	"ore":{"name":"Iron Ore","unit":"ore lots","weight":3,"color":"#88786b","inputs":{},"labor":{"miner":2.0}},
	"charcoal":{"name":"Charcoal","unit":"sacks","weight":1,"color":"#697176","inputs":{"logs":0.5},"labor":{"charcoal burner":1.0}},
	"iron":{"name":"Worked Iron","unit":"iron lots","weight":3,"color":"#8e9b9e","inputs":{"ore":2.0,"charcoal":0.75},"labor":{"smelter":2.0}},
	"copper":{"name":"Copper Stock","unit":"metal lots","weight":2,"color":"#c58756","inputs":{},"labor":{"miner":3.0,"smelter":2.0}},
	"saltpeter":{"name":"Saltpeter","unit":"sealed lots","weight":1,"color":"#c3c5a3","inputs":{},"labor":{"miner":3.0,"refiner":1.0}},
	"sulfur":{"name":"Sulfur","unit":"sealed lots","weight":1,"color":"#c6b45e","inputs":{},"labor":{"miner":2.0,"refiner":1.0}},
	"gunpowder":{"name":"Gunpowder","unit":"sealed powder lots","weight":1,"color":"#7d8377","inputs":{"saltpeter":1.0,"sulfur":1.0,"charcoal":1.0},"labor":{"powder worker":3.0}},
	"ammo":{"name":"Ammunition Cases","unit":"50-round cases","weight":1,"color":"#c48767","inputs":{"iron":0.1,"copper":0.1,"gunpowder":0.05},"labor":{"gunsmith":1.0}},
	"crude":{"name":"Seep Oil","unit":"raw drums","weight":1,"color":"#88745e","inputs":{},"labor":{"miner":2.0}},
	"fuel":{"name":"Distilled Fuel","unit":"drums","weight":1,"color":"#c58b53","inputs":{"crude":1.0},"labor":{"refiner":1.0}},
	"supplies":{"name":"Drydock & Repair Kits","unit":"kits","weight":1,"color":"#84a36f","inputs":{"timber":0.4,"iron":0.05},"labor":{"carpenter":0.5}},
	"engines":{"name":"Marine Engines","unit":"engine assemblies","weight":4,"color":"#83a9ac","inputs":{"iron":10.0,"copper":2.0,"fuel":2.0,"supplies":2.0},"labor":{"mechanic":40.0,"engineer":5.0}},
	"guns":{"name":"Deck Guns & Launchers","unit":"weapon assemblies","weight":3,"color":"#b39b7c","inputs":{"iron":4.0,"copper":0.4,"timber":0.1},"labor":{"gunsmith":25.0,"engineer":3.0}}
}

static func labor_cost(labor: Dictionary) -> float:
	var result: float = 0.0
	for occupation in labor:
		result += float(labor[occupation]) * float(WAGES[occupation])
	return result

static func labor_days(labor: Dictionary) -> float:
	var result: float = 0.0
	for occupation in labor:
		result += float(labor[occupation])
	return result

static func cost(good: String) -> float:
	if not ITEMS.has(good):
		return 0.0
	var recipe: Dictionary = ITEMS[good]
	var value: float = labor_cost(recipe.labor)
	for ingredient in recipe.inputs:
		value += float(recipe.inputs[ingredient]) * cost(ingredient)
	return value

static func full_labor_days(good: String) -> float:
	var recipe: Dictionary = ITEMS[good]
	var days: float = labor_days(recipe.labor)
	for ingredient in recipe.inputs:
		days += float(recipe.inputs[ingredient]) * full_labor_days(ingredient)
	return days

static func definitions() -> Dictionary:
	var result: Dictionary = ITEMS.duplicate(true)
	for key in result:
		result[key].base = ceili(cost(key))
	return result
