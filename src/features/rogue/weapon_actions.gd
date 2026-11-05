class_name WeaponActions
extends RefCounted
## V5 adds frozen site drops to the unchanged V4 geometry/budget generator.
const VERSION: int = 5

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for old: Dictionary in TaskActions.offers(base):result.append(_upgrade(old))
	return result

static func _upgrade(old: Dictionary) -> Dictionary:
	var value: Dictionary=old.duplicate(true);value.version=VERSION
	for site: Dictionary in value.sites:
		if site.weapon:site.drop={"version":1,"weapon_id":WeaponInventory.drop_weapon(value.seed,value.id,site.id)}
	return value

static func legacy(value: Dictionary) -> Dictionary:
	var old: Dictionary=value.duplicate(true);old.version=4
	for site: Dictionary in old.sites:site.erase("drop")
	return old

static func problem(value: Variant) -> String:
	if not value is Dictionary or value.get("version")!=VERSION or not value.get("sites") is Array:return "WEAPON_ACTION_FIELDS"
	for site: Variant in value.sites:
		if not site is Dictionary:return "WEAPON_ACTION_SITE"
	var old: Dictionary=legacy(value)
	var issue: String=TaskActions.problem(old)
	if not issue.is_empty():return issue
	return "" if TransactionReceipt.same(value,_upgrade(old)) else "WEAPON_ACTION_DROP"

static func matches(base: Dictionary, value: Variant) -> bool:
	return problem(value).is_empty() and TaskActions.matches(base,legacy(value))

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply=TaskActions.supply(legacy(value));result.generated=value.duplicate(true)
	var lines: PackedStringArray=result.description.split("\n")
	result.description="\n".join([lines[0],lines[1],lines[2],("首次回收最多引来2名普通感染者。" if value.type=="airdrop" else "夜间增援加密，请留出返程时间。")+(" 武器随机：卡宾枪/长管步枪。" if value.weapons>0 else "")])
	return result

static func mission_problem(mission: Dictionary) -> String:
	var issue: String=problem(mission.get("generated"))
	if not issue.is_empty():return issue
	var old: Dictionary=mission.duplicate(true);old.generated=legacy(mission.generated)
	return TaskActions.mission_problem(old)
