class_name SearchWorkView
extends RefCounted
## Read-only text for the existing building label, member HUD and transient notice.

const TITLE_LIMIT: int = 4
const CALL_SIGN_LIMIT: int = 3
const MEMBER_LABEL_LIMIT: int = 8


static func short_site(title: String, number: int) -> String:
	# The owner supplies the stable, one-based building number, never a filtered index.
	return "%s%02d" % [_brief(title, TITLE_LIMIT, "站点"), number]


static func short_call_sign(call_sign: String) -> String:
	return _brief(call_sign, CALL_SIGN_LIMIT, "队员")


static func actor_status(phase: String, site_label: String, outdoor: bool) -> String:
	var action: String = _phase(phase, outdoor)
	if action.is_empty():
		return ""
	return "%s·%s" % [action, _site_label(site_label)]


static func building_text(member_id: int, call_sign: String, phase: String, outdoor: bool) -> String:
	var action: String = _phase(phase, outdoor)
	if member_id <= 0 or action.is_empty():
		return ""
	return "%02d %s·%s·再点取消" % [member_id, short_call_sign(call_sign), action]


static func notice(code: String, site_label: String, member_label: String = "") -> String:
	var site: String = _site_label(site_label)
	var member: String = _brief(member_label, MEMBER_LABEL_LIMIT, "队员")
	match code:
		"assigned":
			return "已派遣%s前往%s。" % [member, site]
		"cancelled":
			return "已取消%s的%s任务；进度保留。" % [member, site]
		"no_idle":
			return "暂无空闲队员，未派遣至%s。" % site
		"unreachable":
			return "无法到达%s，未派遣。" % site
		"completed":
			return "%s已完成，%s归队。" % [site, member]
	return ""


static func _phase(phase: String, outdoor: bool) -> String:
	match phase:
		"approach":
			return "前往"
		"working":
			return "回收" if outdoor else "搜寻"
	return ""


static func _site_label(value: String) -> String:
	var clean: String = _clean(value)
	if clean.is_empty():
		return "站点"
	# Preserve a supplied stable number when a caller passes a long title directly.
	var split: int = clean.length()
	while split > 0:
		var code: int = clean.unicode_at(split - 1)
		if code < 48 or code > 57:
			break
		split -= 1
	if split < clean.length():
		return _brief(clean.left(split), TITLE_LIMIT, "站点") + clean.substr(split)
	return _brief(clean, TITLE_LIMIT, "站点")


static func _brief(value: String, limit: int, fallback: String) -> String:
	var clean: String = _clean(value)
	if clean.is_empty():
		return fallback
	return clean if clean.length() <= limit else clean.left(limit - 1) + "…"


static func _clean(value: String) -> String:
	var result: String = ""
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code >= 32 and code != 127 and code != 0x2028 and code != 0x2029:
			result += value.substr(index, 1)
	return result.strip_edges()
