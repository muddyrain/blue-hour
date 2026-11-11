class_name SpecialtyPresentation
extends RefCounted

const PLANS: Array[String] = ["scavenge", "firepower", "support"]


static func reward_name(id: String) -> String:
	return definition(id).get("name", id)


static func definition(id: String) -> Dictionary:
	return BuildItems.definitions(BuildItems.SPECIALTY_CATALOG_POOL).get(id, SpecialPowers.definition(id))


static func names(ids: Array) -> String:
	var labels: PackedStringArray = []
	for id: String in ids:
		labels.append(reward_name(id))
	return "、".join(labels)


static func access_text(ids: Array) -> String:
	return "后续普通装备行动可回收 · " + names(ids) if not ids.is_empty() else "当前无专精奖励进入装备池"


static func result_text(result: Dictionary) -> String:
	var title: String = OpeningBuild.PLANS[result.plan].title
	var text: String = "%s · +%d 经验 · %d → %d" % [title, result.delta, result.before, result.after]
	if not result.shared.is_empty():
		text += "\n共享 %s · 下局可从普通装备行动回收" % names(result.shared)
	elif not result.unlocked.is_empty():
		text += "\n解锁 %s · 下局同专精可回收" % names(result.unlocked)
	elif int(result.delta) == 0:
		text += "\n未达到两次已确认归航"
	return text
