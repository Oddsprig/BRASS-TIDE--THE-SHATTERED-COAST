extends RefCounted
## Small read-only carrier policy; never clone a campaign for a route quote.
static func allowed(bans: Array,a: String,b: String,good: String,day: float) -> bool:
	if not is_finite(day) or day<0 or bans.size()>80:return false
	for row in bans:
		if not row is Dictionary or not row.get("good") is String or not row.get("issuer") is String or not row.get("target") is String:return false
		var expires=row.get("expires")
		if not (expires is int or expires is float) or not is_finite(float(expires)):return false
		if float(expires)<=day:continue
		if row.good==good and ((row.issuer==a and row.target==b) or (row.issuer==b and row.target==a)):return false
	return true
