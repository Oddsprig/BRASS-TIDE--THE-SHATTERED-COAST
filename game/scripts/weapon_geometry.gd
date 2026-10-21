extends RefCounted
## Physical equipment dimensions shared by rendering and projectile launch.
static func unit(hull_size: float,tier: int) -> float:
	return (0.78+clampi(tier,1,3)*0.22)*minf(1.0,maxf(8.0,hull_size)/18.0)

static func muzzle(kind: String,hull_size: float,tier: int) -> float:
	return float({"gun":8.8,"cannon":14.2,"rocket":5.9,"torpedo":7.9}.get(kind,8.8))*unit(hull_size,tier)

static func height(kind: String,hull_size: float,tier: int) -> float:
	if kind=="torpedo":return 0.0
	return 9.7+float({"gun":4.8,"cannon":5.8,"rocket":6.0}.get(kind,4.8))*unit(hull_size,tier)
