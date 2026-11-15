class_name SortieEvents
extends RefCounted
## Read-only projection of existing signed event/rare policies and durable facts.
## No random draw, timer, reward ledger or second save schema lives here.


static func cold_store(action: Dictionary) -> bool:
	return action.get("version") == 9 and action.has("rare_policy") and action.get("type") == "supply"


static func prepare(world: Expedition) -> void:
	var action: Dictionary = world.supply.generated
	if not EventSortieV1.site_id(action).is_empty():
		var site: Expedition.SearchSite = world.search_site(StringName(EventSortieV1.SITE))
		site.prop.title = EventSortieV1.TITLE
		site.prop.loot_landmark = "临时物资点 · 现场二选一"
		site.prop.reward_hint = "安静取粮 / 强开物资柜"
		site.prop.configure_loot_badge("事件", Vector2(0, 12))
	elif cold_store(action):
		for id: String in ["food", "food_2"]:
			var site: Expedition.SearchSite = world.search_site(StringName(id))
			if site == null or site.prop == null:
				continue
			site.prop.set_meta("power_outage", true)
			site.prop.loot_landmark = "断电冷库 · " + ("近处取粮" if id == "food" else "远端追加")
		# Keep street lamps and bus headlights: the two cold rooms lose window light.


static func field_hint(world: Expedition) -> String:
	var action: Dictionary = world.supply.generated
	if not EventSortieV1.site_id(action).is_empty():
		var site: Expedition.SearchSite = world.search_site(StringName(EventSortieV1.SITE))
		var branch: String = world.task_event.branch
		if branch.is_empty():
			return "临时物资点 · 点击事件标记，抵达后选择方案"
		if site.searched:
			return "临时物资已携带 · 集合归航后入账"
		return "临时物资点 · " + ("安静取粮，无额外增援" if branch == EventSortieV1.QUIET else "强开物资柜，开工警报引来增援")
	if cold_store(action):
		var deep: Expedition.SearchSite = world.search_site(&"food_2")
		return "断电冷库 · 远端补给已携带，尽快回车" if deep != null and deep.searched else "断电冷库 · 近处可先取粮；远端追加会压缩回程"
	return ""


static func night_hint(action: Dictionary, elapsed: float, daylight: float) -> String:
	if not CampaignPressureV1.blockade_night(action):
		return ""
	if elapsed < daylight:
		return "封锁夜预告 · 重压与疾奔来袭前回车"
	return "封锁夜 · 重压与疾奔结伴，优先集火并集合"


static func summary(action: Dictionary, battle: Dictionary, daylight: float) -> String:
	if action.is_empty() or battle.is_empty():
		return ""
	var lines: PackedStringArray = []
	if cold_store(action):
		var facts: Dictionary = battle.get("site_facts", {})
		lines.append("断电冷库 · 近处%s · 远端%s" % [_collected(facts, "food"), _collected(facts, "food_2")])
	if CampaignPressureV1.blockade_night(action):
		var before_night: String = "天黑前撤离" if battle.get("evacuated", false) else "天黑前结束"
		lines.append("封锁夜 · " + ("经历入夜增援" if float(battle.get("elapsed", 0.0)) >= daylight else before_night))
	return "\n".join(lines)


static func _collected(facts: Dictionary, id: String) -> String:
	return "已搜集" if facts.get(id, {}).get("searched", false) else "未搜集"
