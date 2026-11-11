class_name EconomyActions
extends RefCounted
## PROJECT_TEMP M48 source adapter. The old descriptor is fully authenticated first.

const VERSION: int = 1
const HARDWARE_TITLE: String = "五金补给"
const MARKER_KEYS: Array[String] = ["version", "loot_grade", "tools", "hardware", "source_fields"]
const CHANGED_FIELDS: Array[String] = ["sites", "cash", "weapons", "build", "powers"]
static var _checked: Dictionary = {}


static func camp_enabled(camp: Dictionary) -> bool:
	return SurvivalContracts.integer(camp.get("journey", {}).get("campaign", {}).get("economy", {}).get("version"), VERSION, VERSION)


static func enabled(action: Dictionary) -> bool:
	return SurvivalContracts.integer(action.get("economy_source", {}).get("version"), VERSION, VERSION)


static func hardware(action: Dictionary) -> bool:
	return enabled(action) and action.economy_source.get("hardware") == true


static func grade(action: Dictionary) -> int:
	return int(action.get("economy_source", {}).get("loot_grade", 0))


static func tool_sources(action: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var marker: Variant = action.get("economy_source")
	if marker is Dictionary and marker.get("tools") is Array:
		for row: Variant in marker.tools:
			if row is Dictionary and row.size() == 2 and row.get("site_id") is String \
					and SurvivalContracts.integer(row.get("count"), 1, 2):
				result.append(row.duplicate(true))
	return result


static func count_at(action: Dictionary, site_id: String) -> int:
	for row: Dictionary in tool_sources(action):
		if row.site_id == site_id:
			return int(row.count)
	return 0


static func carried(action: Dictionary, facts: Dictionary) -> int:
	var total: int = 0
	for row: Dictionary in tool_sources(action):
		if facts.get(row.site_id, {}).get("searched") == true:
			total += int(row.count)
	return total


static func freeze(source: Dictionary, is_hardware: bool = false) -> Dictionary:
	if source.has("economy_source") or source.get("version") != 9:
		return {}
	if is_hardware and not _hardware_eligible(source):
		return {}
	var result: Dictionary = source.duplicate(false)
	var changed: Dictionary = {}
	var tools: Array[Dictionary] = []
	var optional: String = WorkshopSiteV1._optional_site(source)
	if is_hardware:
		for key: String in CHANGED_FIELDS:
			changed[key] = source[key].duplicate(true) if source[key] is Dictionary or source[key] is Array else source[key]
		result.sites = source.sites.duplicate(true)
		for site: Dictionary in result.sites:
			if site.id == "cash":
				result.cash = int(source.cash) - int(site.amount)
				site.amount = 0
				site.weapon = false
				site.seconds = 12.0
				site.erase("drop")
				break
		result.weapons = 0
		result.build = source.build.duplicate(true)
		result.build.drops = []
		result.powers = source.powers.duplicate(true)
		result.powers.sample = ""
		tools.append({"site_id":"cash", "count":2})
		if not optional.is_empty():
			tools.append({"site_id":optional, "count":1})
	elif NightHoundV1.enabled(source) and not optional.is_empty():
		tools.append({"site_id":optional, "count":1})
	result.economy_source = {"version":VERSION, "loot_grade":_grade(source), "tools":tools,
		"hardware":is_hardware, "source_fields":changed}
	return result


static func origin(action: Dictionary) -> Dictionary:
	var marker: Variant = action.get("economy_source")
	if not marker is Dictionary or not _marker_problem(marker).is_empty():
		return {}
	var source: Dictionary = action.duplicate(false)
	source.erase("economy_source")
	for key: String in marker.source_fields:
		source[key] = marker.source_fields[key]
	return source


static func problem(action: Dictionary, camp_source: bool = false) -> String:
	var marker: Variant = action.get("economy_source")
	var issue: String = _marker_problem(marker)
	if not issue.is_empty():
		return issue
	var identity: String = ("camp:" if camp_source else "receipt:") + RecordEncoding.fingerprint(action)
	if ActionMemo.lookup(_checked, identity) == true:
		return ""
	var source: Dictionary = origin(action)
	if source.is_empty():
		return "ECONOMY_ACTION_SOURCE"
	issue = ExplorationActions.problem(source, camp_source)
	if not issue.is_empty():
		return "ECONOMY_SOURCE:" + issue
	var expected: Dictionary = freeze(source, marker.hardware)
	if expected.is_empty():
		return "ECONOMY_ACTION_ELIGIBILITY"
	if not TransactionReceipt.same(action, expected):
		if not camp_source:
			return "ECONOMY_ACTION_CANONICAL"
		var projected: Dictionary = JSON.parse_string(JSON.stringify(expected, "", true, true))
		if not TransactionReceipt.same(action, projected):
			return "ECONOMY_ACTION_CANONICAL"
	ActionMemo.store(_checked, identity, true, 64)
	return ""


static func _marker_problem(marker: Variant) -> String:
	if not marker is Dictionary or marker.size() != MARKER_KEYS.size() or not marker.has_all(MARKER_KEYS) \
			or not SurvivalContracts.integer(marker.version, VERSION, VERSION) \
			or not SurvivalContracts.integer(marker.loot_grade, 1, 3) or not marker.tools is Array \
			or not marker.hardware is bool or not marker.source_fields is Dictionary:
		return "ECONOMY_ACTION_FIELDS"
	if marker.source_fields.size() != (CHANGED_FIELDS.size() if marker.hardware else 0) \
			or (marker.hardware and not marker.source_fields.has_all(CHANGED_FIELDS)):
		return "ECONOMY_ACTION_SOURCE_FIELDS"
	if marker.hardware and (not marker.source_fields.sites is Array or not marker.source_fields.build is Dictionary \
			or not marker.source_fields.powers is Dictionary \
			or not SurvivalContracts.integer(marker.source_fields.cash, 0, RunSave.MAX_COUNTER) \
			or not SurvivalContracts.integer(marker.source_fields.weapons, 1, 1)):
		return "ECONOMY_ACTION_SOURCE_FIELDS"
	if marker.tools.size() > (2 if marker.hardware else 1):
		return "ECONOMY_ACTION_TOOL_COUNT"
	var seen: Array[String] = []
	for row: Variant in marker.tools:
		if not row is Dictionary or row.size() != 2 or not row.has_all(["site_id", "count"]) \
				or not row.site_id is String or row.site_id.is_empty() or row.site_id in seen \
				or not SurvivalContracts.integer(row.count, 1, 2):
			return "ECONOMY_ACTION_TOOLS"
		seen.append(row.site_id)
	return ""


static func _grade(source: Dictionary) -> int:
	return 3 if source.has("rare_policy") else NeighborhoodLayout.SIZES.find(source.layout["size"]) + 1


static func _hardware_eligible(source: Dictionary) -> bool:
	if source.get("version") != 9 or source.get("mission_policy") != 1 or source.get("type") != "airdrop" \
			or source.get("slot") != 2 or not SurvivalContracts.integer(source.get("day"), 3, RunSave.MAX_COUNTER) \
			or int(source.day) % 3 != 0 or source.get("campaign", {}).get("is_finale") != false \
			or source.has("rare_policy") or source.has("event_sortie") or source.has("investigation") \
			or source.has("finale_policy") or source.has("billboard_target") \
			or source.get("layout", {}).get("topology") not in ["commercial", "industrial"]:
		return false
	for site: Dictionary in source.get("sites", []):
		if site.id == "cash":
			return site.get("work_mode") == "outdoor" and site.get("weapon") == true
	return false


static func card_text(action: Dictionary) -> String:
	var optional: bool = tool_sources(action).size() > 1
	var level: Dictionary = action.get("exploration", {}).get("level", {})
	var route: String = LevelSummary.description(action, true)
	var size: String = {"small":"小型", "medium":"中型", "large":"大型"}.get(action.layout["size"], "")
	if hardware(action):
		var extra: String = "合法副点另有工具 ×1，工时按原站点" if optional else "本图没有额外工具点"
		return "主收益 · 工具 ×2（门口工具柜，12 秒）\n%s街区 · %s\n附属回收上限 · 钱 %d / 粮 %d\n%s\n取舍 · 占用本日随机行动机会，原调查/终局保持\n风险 · 户外工作可受击，首次最多增援 %d 名" % [size, extra, int(action.cash), int(action.food), route, int(action.parameters.reinforcements)]
	return "可选工具 ×1 · 需完成对应绕路并生还归航确认" if not tool_sources(action).is_empty() else ""
