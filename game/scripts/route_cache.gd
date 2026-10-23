extends RefCounted
## Compatibility adapter: fixed-coast campaign caches remain outside save data.
const Navigation=preload("res://scripts/navigation.gd")
static func path(c,a: Dictionary,b: Dictionary) -> Array:
	if c is Object and c.has_method("cached_path"):return c.cached_path(a,b)
	return Navigation.find_path(c.nav,a,b)
