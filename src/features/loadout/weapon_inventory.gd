class_name WeaponInventory
extends RefCounted
## Pure ownership transactions. The app owns inventory; sorties receive deep copies.

const Definitions: Array[WeaponDefinition] = [preload("res://src/features/loadout/carbine.tres"),
	preload("res://src/features/loadout/long_rifle.tres")]


static func definition(id: String) -> WeaponDefinition:
	for item: WeaponDefinition in Definitions:
		if String(item.id) == id:
			return item
	return null


static func initialize(data: Dictionary, origin: String) -> void:
	data.weapons = []
	data.loadout = []
	data.camp_spending = 0
	for index: int in range(2):
		var identity: String = "%s:starter:%d" % [data.profile_id, index + 1]
		data.weapons.append({"instance_id":identity, "weapon_id":"carbine" if index == 0 else "long_rifle",
			"condition":"ready", "origin":origin, "acquired_sortie":""})
		for member: Dictionary in data.crew:
			if int(member.id) == index + 1 and float(member.health) > 0.0:
				data.loadout.append({"member_id":index + 1, "instance_id":identity})


static func reward(sortie_id: String) -> Dictionary:
	return {"instance_id":sortie_id + ":weapon:north-cache", "weapon_id":"long_rifle",
		"condition":"damaged", "origin":"north-cache", "acquired_sortie":sortie_id}


static func find(data: Dictionary, identity: String) -> Dictionary:
	for item: Dictionary in data.weapons:
		if item.instance_id == identity:
			return item
	return {}


static func owner(data: Dictionary, identity: String) -> int:
	for equipped: Dictionary in data.loadout:
		if equipped.instance_id == identity:
			return int(equipped.member_id)
	return 0


static func for_member(data: Dictionary, member_id: int) -> Dictionary:
	for equipped: Dictionary in data.loadout:
		if int(equipped.member_id) == member_id:
			return find(data, equipped.instance_id)
	return {}


static func snapshot(data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member: Dictionary in data.crew:
		var item: Dictionary = for_member(data, int(member.id))
		if not item.is_empty():
			result.append({"member_id":int(member.id), "instance":item.duplicate(true)})
	return result


static func validate(data: Dictionary) -> String:
	if not data.get("weapons") is Array or not data.get("loadout") is Array:
		return "武器库存或配装格式无效"
	if not RunSave._integer(data.get("camp_spending"), 0, RunSave.MAX_COUNTER):
		return "营地维修支出无效"
	var identities: Array[String] = []
	for value: Variant in data.weapons:
		if not value is Dictionary or value.size() != 5:
			return "武器实例字段无效"
		for key: String in ["instance_id", "weapon_id", "condition", "origin", "acquired_sortie"]:
			if not value.get(key) is String:
				return "武器实例缺少字符串字段：" + key
		if definition(value.weapon_id) == null or value.condition not in ["ready", "damaged"]:
			return "未知武器定义或状态"
		if value.instance_id in identities:
			return "武器实例身份重复"
		identities.append(value.instance_id)
		if value.origin in ["initial", "migration-v1", "migration-v2"]:
			var starter: int = 1 if value.weapon_id == "carbine" else 2
			if value.instance_id != "%s:starter:%d" % [data.profile_id, starter] or not value.acquired_sortie.is_empty() or value.condition != "ready":
				return "初始武器身份或来源无效"
		elif value.origin == "north-cache":
			var pieces: PackedStringArray = value.acquired_sortie.split(":")
			if pieces.size() != 2 or pieces[0] != data.profile_id or not pieces[1].is_valid_int():
				return "战利品出击身份无效"
			var count: int = int(pieces[1])
			if count < 1 or count > int(data.settled_sorties) or pieces[1] != str(count) or value != _with_condition(reward(value.acquired_sortie), value.condition):
				return "战利品实例与来源不一致"
		else:
			return "未知武器来源"
	var equipped_ids: Array[String] = []
	var members: Array[int] = []
	for value: Variant in data.loadout:
		if not value is Dictionary or value.size() != 2 or not RunSave._integer(value.get("member_id"), 1, 2) or not value.get("instance_id") is String:
			return "配装字段无效"
		var member_id: int = int(value.member_id)
		if member_id in members or value.instance_id in equipped_ids:
			return "同一成员或武器被重复配给"
		var item: Dictionary = find(data, value.instance_id)
		if item.is_empty() or item.condition != "ready":
			return "装备实例丢失或尚未维修"
		if not _living(data, member_id):
			return "不能给无效或倒地成员配装"
		members.append(member_id)
		equipped_ids.append(value.instance_id)
	for member: Dictionary in data.crew:
		if float(member.health) > 0.0 and int(member.id) not in members:
			return "存活成员缺少配装"
	return ""


static func equip(data: Dictionary, member_id: int, identity: String) -> Dictionary:
	if not _living(data, member_id):
		return {"message":"该成员无法装备。"}
	var selected: Dictionary = find(data, identity)
	if selected.is_empty():
		return {"message":"该武器已不存在。"}
	if selected.condition != "ready":
		return {"message":"武器损坏，请先维修。"}
	var previous_owner: int = owner(data, identity)
	if previous_owner == member_id:
		return {"message":"该成员已持有这件武器，未重复操作。"}
	var after: Dictionary = data.duplicate(true)
	var previous: Dictionary = for_member(data, member_id)
	for entry: Dictionary in after.loadout:
		if int(entry.member_id) == member_id:
			entry.instance_id = identity
		elif int(entry.member_id) == previous_owner:
			entry.instance_id = previous.instance_id
	return {"data":after, "message":"已交换两名队员的武器。" if previous_owner > 0 else "已配给队员%d；原武器转入闲置库存。" % member_id}


static func repair(data: Dictionary, identity: String) -> Dictionary:
	var selected: Dictionary = find(data, identity)
	if selected.is_empty() or selected.condition != "damaged":
		return {"message":"这件武器无需维修，未重复扣款。"}
	var cost: int = definition(selected.weapon_id).repair_cost
	if int(data.cash) < cost:
		return {"message":"货币不足，需要%d。" % cost}
	var after: Dictionary = data.duplicate(true)
	find(after, identity).condition = "ready"
	after.cash = int(data.cash) - cost
	after.camp_spending = int(data.camp_spending) + cost
	return {"data":after, "message":"维修完成，货币 −%d；现在可配装。" % cost}


static func bank(after: Dictionary, rewards: Array, identity: String) -> String:
	var seen: Array[String] = []
	for value: Variant in rewards:
		if not value is Dictionary or value != reward(identity):
			return "战利品账本与本次搜集来源不符"
		if value.instance_id in seen or not find(after, value.instance_id).is_empty():
			return "同一搜集来源不能重复入库"
		seen.append(value.instance_id)
		after.weapons.append(value.duplicate(true))
	for index: int in range(after.loadout.size() - 1, -1, -1):
		if not _living(after, int(after.loadout[index].member_id)):
			after.loadout.remove_at(index)
	return ""


static func short_id(item: Dictionary) -> String:
	return item.instance_id.trim_prefix(item.instance_id.get_slice(":", 0) + ":")


static func _living(data: Dictionary, member_id: int) -> bool:
	for member: Dictionary in data.crew:
		if int(member.id) == member_id:
			return float(member.health) > 0.0
	return false


static func _with_condition(item: Dictionary, condition: String) -> Dictionary:
	item.condition = condition
	return item
