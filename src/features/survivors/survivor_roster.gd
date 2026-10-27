class_name SurvivorRoster
extends RefCounted
## Persistent identity and observed service records, never a substitute XP system.

const Definitions: Array[SurvivorDefinition] = [preload("res://src/features/survivors/crew_one.tres"),
	preload("res://src/features/survivors/crew_two.tres")]


static func definition(member_id: int) -> SurvivorDefinition:
	for item: SurvivorDefinition in Definitions:
		if item.member_id == member_id:
			return item
	return null


static func member(crew: Array, member_id: int) -> Dictionary:
	for entry: Dictionary in crew:
		if int(entry.id) == member_id:
			return entry
	return {}


static func new_crew() -> Array[Dictionary]:
	var crew: Array[Dictionary] = [{"id":1,"health":200.0},{"id":2,"health":200.0}]
	initialize(crew)
	return crew


static func initialize(crew: Array) -> void:
	for entry: Dictionary in crew:
		var base: SurvivorDefinition = definition(int(entry.id))
		entry.definition_id = String(base.id)
		entry.call_sign = base.default_display_name
		entry.condition = "active" if float(entry.health) > 0.0 else "down"
		entry.service = {"sorties":0,"kills":0,"damage_received":0.0,"last_settlement_id":""}
	SurvivorGrowth.initialize(crew)


static func name_problem(value: Variant) -> String:
	if not value is String or value.strip_edges() != value or value.length() < 1 or value.length() > 12:
		return "呼号须为1–12字，首尾不能有空格。"
	for index: int in range(value.length()):
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return "呼号不能含控制字符或换行。"
	return ""


static func validate(entry: Dictionary, data: Dictionary) -> String:
	var base: SurvivorDefinition = definition(int(entry.id))
	if entry.size() != (7 if int(data.schema_version) >= 5 else 6) or entry.get("definition_id") != String(base.id):
		return "队员档案字段或基础定义无效"
	if not name_problem(entry.get("call_sign")).is_empty():
		return name_problem(entry.get("call_sign"))
	var expected: String = "active" if float(entry.health) > 0.0 else "down"
	if entry.get("condition") != expected:
		return "队员生命与存活/倒地状态不一致；永久离队规则未启用"
	var service: Variant = entry.get("service")
	if not service is Dictionary or service.size() != 4:
		return "队员战绩字段无效"
	if not RunSave._integer(service.get("sorties"), 0, int(data.settled_sorties)) or not RunSave._integer(service.get("kills"), 0, RunSave.MAX_COUNTER):
		return "队员战绩次数无效"
	if not RunSave._number(service.get("damage_received")) or float(service.damage_received) < 0.0 or float(service.damage_received) > float(service.sorties) * 200.0 + 0.000001:
		return "队员累计受伤无效"
	if not service.get("last_settlement_id") is String:
		return "队员战绩结算身份无效"
	if int(service.sorties) == 0:
		if int(service.kills) != 0 or float(service.damage_received) != 0.0 or service.last_settlement_id != "":
			return "未记录出击不能捏造历史战绩"
	else:
		var parts: PackedStringArray = service.last_settlement_id.split(":")
		if parts.size() != 2 or parts[0] != data.profile_id or not parts[1].is_valid_int() or int(parts[1]) < int(service.sorties) or int(parts[1]) > int(data.settled_sorties):
			return "队员战绩结算不属于当前存档或来自未来"
	return ""


static func record(after: Dictionary, before: Dictionary, report: Dictionary, identity: String) -> String:
	for entry: Dictionary in after.crew:
		entry.condition = "active" if float(entry.health) > 0.0 else "down"
	# Legacy callers/fixtures have no per-actor record. Do not invent their history.
	if not report.has("member_records"):
		return ""
	if not report.member_records is Array or report.member_records.size() != 2:
		return "出击成员记录不完整"
	var ids: Array[int] = []
	var kill_total: int = 0
	for value: Variant in report.member_records:
		if not value is Dictionary or value.size() != 3 or not RunSave._integer(value.get("id"),1,2):
			return "出击成员记录字段无效"
		var member_id: int = int(value.id)
		if member_id in ids or not RunSave._integer(value.get("kills"),0,RunSave.MAX_COUNTER) or not RunSave._number(value.get("damage_received")):
			return "出击成员记录重复或数字无效"
		ids.append(member_id)
		var previous: Dictionary = member(before.crew, member_id)
		var current: Dictionary = member(after.crew, member_id)
		if float(value.damage_received) < 0.0 or not is_equal_approx(float(previous.health) - float(current.health), float(value.damage_received)):
			return "受伤记录与实际生命变化不符"
		if float(previous.health) <= 0.0:
			if int(value.kills) != 0 or float(value.damage_received) != 0.0:
				return "未出场队员不能产生战绩"
			continue
		current.service.sorties = int(previous.service.sorties) + 1
		current.service.kills = int(previous.service.kills) + int(value.kills)
		current.service.damage_received = float(previous.service.damage_received) + float(value.damage_received)
		current.service.last_settlement_id = identity
		kill_total += int(value.kills)
	if kill_total != int(report.get("kills", -1)):
		return "个人击退与实际出击总数不一致"
	return ""
