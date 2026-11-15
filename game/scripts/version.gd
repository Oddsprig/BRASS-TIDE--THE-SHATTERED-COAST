extends RefCounted

const BUILD: int = 117

static func text() -> String:
	return "%d.%03d" % [BUILD / 1000, BUILD % 1000]
