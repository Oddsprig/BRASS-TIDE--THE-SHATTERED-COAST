extends RefCounted
## Harbor training transactions. The UI must join pending economy jobs before calling.
const Training=preload("res://scripts/crew_training.gd")
const Politics=preload("res://scripts/politics.gd")
static func ensure(c) -> void:
	for p in c.state.get("ports",[]):Training.ensure(p)

static func enroll(c,count: int,role: String="sailor") -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var p: Dictionary=c.current_port()
	if p.is_empty():return c.fail("Visit a harbor to arrange paid training.")
	var result: Dictionary=Training.enroll(p,c.state,count,role)
	if result.ok:
		c.log_entry(str(result.get("message","Training commissioned.")))
		c.Economy.sync_workforce(p)
	return result

static func cancel(c,id: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var p: Dictionary=c.current_port()
	if p.is_empty():return c.fail("Visit the harbor holding this training account.")
	var result: Dictionary=Training.cancel(p,c.state,id)
	if result.ok:
		c.log_entry(str(result.get("message","Training cancelled; earned wages remain paid.")))
		c.Economy.sync_workforce(p)
	return result
