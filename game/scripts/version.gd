extends RefCounted

const BUILD: int = 20

static func text() -> String:
	return "%d.%03d" % [BUILD / 1000, BUILD % 1000]
