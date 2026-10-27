class_name SurvivorGrowth
extends RefCounted
## Honest unknown progression plus real action inputs. No XP conversion or stat effects.

# Storage capacity only, never an experience threshold or gameplay reward.
const RECENT_LIMIT: int = 32
const MAPS: Array[String] = ["repair_lane", "market_loop"]


static func empty_state() -> Dictionary:
	return {"level":null, "experience":null, "trait":{"id":null,"level":null,"progress":null},
		"training_state":"unavailable", "last_action":{}}


static func initialize(crew: Array) -> void:
	for member: Dictionary in crew:
		member.growth = empty_state()


static func validate_member(member: Dictionary, data: Dictionary) -> String:
	var value: Variant = member.get("growth")
	if not value is Dictionary or value.size() != 5 or not value.has_all(["level","experience","trait","training_state","last_action"]):
		return "成长档案字段无效"
	if value.level != null or value.experience != null or value.training_state != "unavailable":
		return "正式经验、等级或训练规则尚未开放"
	if not value.trait is Dictionary or value.trait.size() != 3 or not value.trait.has_all(["id","level","progress"]):
		return "特性档案字段无效"
	if value.trait.id != null or value.trait.level != null or value.trait.progress != null:
		return "未经校准的特性或成长进度不能写入正式档"
	if not value.last_action is Dictionary:
		return "行动明细无效"
	if value.last_action.is_empty():
		return ""
	var action: Dictionary = value.last_action
	if action.size() != 6 or not action.has_all(["settlement_id","map_id","duration_ms","total","recent","evacuated"]):
		return "行动明细字段无效"
	if not action.settlement_id is String or not action.evacuated is bool or not action.map_id in MAPS:
		return "行动明细来源无效"
	var parts: PackedStringArray = action.settlement_id.split(":")
	if parts.size() != 2 or parts[0] != data.profile_id or not parts[1].is_valid_int() or not RunSave._integer(int(parts[1]),1,int(data.settled_sorties)):
		return "行动明细结算身份不属于此存档"
	if action.settlement_id != "%s:%d" % [data.profile_id,int(parts[1])] or int(member.service.sorties) == 0:
		return "未归航不能生成行动明细"
	if not RunSave._integer(action.duration_ms,0,RunSave.MAX_COUNTER):
		return "行动时长无效"
	if not RunSave._integer(action.total,0,int(member.service.kills)) or not action.recent is Array or action.recent.size() != mini(int(action.total),RECENT_LIMIT):
		return "个人行动总数与最近记录不一致"
	var seen: Array[int] = []
	var previous: int = -1
	for receipt: Variant in action.recent:
		if not receipt is Dictionary or receipt.size() != 5 or not receipt.has_all(["kind","enemy_id","at_ms","weapon_id","instance_id"]):
			return "击退输入字段无效"
		if receipt.kind != "defeat" or not RunSave._integer(receipt.enemy_id,0,RunSave.MAX_COUNTER) or int(receipt.enemy_id) in seen:
			return "击退输入重复或事件种类无效"
		if not RunSave._integer(receipt.at_ms,0,int(action.duration_ms)) or receipt.at_ms < previous:
			return "击退输入时间无效"
		if not receipt.instance_id is String or not receipt.weapon_id is String:
			return "击退输入武器身份无效"
		var item: Dictionary = WeaponInventory.find(data,receipt.instance_id)
		if item.is_empty() or item.weapon_id != receipt.weapon_id:
			return "击退输入没有对应的真实武器实例"
		seen.append(int(receipt.enemy_id))
		previous = int(receipt.at_ms)
	return ""


static func validate_crew(crew: Array) -> String:
	var seen: Dictionary[String, bool] = {}
	for member: Dictionary in crew:
		var action: Dictionary = member.growth.last_action
		if action.is_empty():
			continue
		for receipt: Dictionary in action.recent:
			var key: String = "%s:%d" % [action.settlement_id,int(receipt.enemy_id)]
			if seen.has(key):
				return "同一敌人不能给两位成员重复记入成长输入"
			seen[key] = true
	return ""


static func bank(after: Dictionary, before: Dictionary, report: Dictionary, identity: String) -> String:
	# Historical callers have only service totals; never synthesize their missing events.
	if not report.has("growth_inputs"):
		return ""
	var bundle: Variant = report.growth_inputs
	if not bundle is Dictionary or bundle.size() != 4 or not bundle.has_all(["sortie_id","map_id","duration_ms","members"]):
		return "成长输入包无效"
	if bundle.sortie_id != identity or not report.has("elapsed") or bundle.duration_ms != floori(float(report.elapsed) * 1000.0):
		return "成长输入来自另一出击或时间不符"
	if not bundle.members is Array or bundle.members.size() != 2 or not report.get("member_records") is Array:
		return "成长输入成员不完整"
	var ids: Array[int] = []
	for row: Variant in bundle.members:
		if not row is Dictionary or row.size() != 3 or not row.has_all(["member_id","total","recent"]) or not RunSave._integer(row.member_id,1,2):
			return "成长输入成员字段无效"
		var id: int = int(row.member_id)
		if not RunSave._integer(row.total,0,RunSave.MAX_COUNTER) or not row.recent is Array:
			return "成长输入成员数字或明细无效"
		if id in ids:
			return "成长输入成员重复"
		ids.append(id)
		var actual: Dictionary = SurvivorRoster.member(report.member_records,id)
		if actual.is_empty() or row.total != actual.kills:
			return "成长输入与真实个人击退不一致"
		var old: Dictionary = SurvivorRoster.member(before.crew,id)
		if float(old.health) <= 0.0:
			if row.total != 0 or not row.recent.is_empty():
				return "未出场成员不能生成成长输入"
			continue
		var current: Dictionary = SurvivorRoster.member(after.crew,id)
		current.growth.last_action = {"settlement_id":identity,"map_id":bundle.map_id,"duration_ms":bundle.duration_ms,
			"total":row.total,"recent":row.recent.duplicate(true),"evacuated":report.evacuated}
		var problem: String = validate_member(current,after)
		if not problem.is_empty():
			return problem
	return validate_crew(after.crew)


static func normalize(value: Dictionary) -> void:
	if value.last_action.is_empty():
		return
	value.last_action.total = int(value.last_action.total)
	value.last_action.duration_ms = int(value.last_action.duration_ms)
	for receipt: Dictionary in value.last_action.recent:
		receipt.enemy_id = int(receipt.enemy_id)
		receipt.at_ms = int(receipt.at_ms)
