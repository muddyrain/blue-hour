class_name CombatActions
extends RefCounted
## V8 preserves the entire V7 projection, with a separately authenticated drop policy.
static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey",{}).get("build",{}).get("combat_version")==1

static func initial() -> Dictionary:
	var value: Dictionary=BuildState.initial()
	value.version=2
	value.combat_version=1
	return value

static func drop(seed: String, action: String, site: String, first: bool) -> String:
	var ids: Array[String]=[]
	ids.assign(["fire_axe_v1","shotgun_v1"] if first else ["carbine","long_rifle","fire_axe_v1","shotgun_v1"])
	return ids[("BH_COMBAT_DROP_V1:%s:%s:%s"%[seed,action,site]).sha256_text().substr(0,8).hex_to_int()%ids.size()]

static func upgrade(old: Dictionary) -> Dictionary:
	var value: Dictionary=old.duplicate(true)
	value.version=8
	value.combat={"version":1,"weapons":CombatEquipment.policy(),"toxic":ToxicV1.POLICY}
	for site: Dictionary in value.sites:
		if site.weapon: site.drop={"version":2,"weapon_id":drop(value.seed,value.id,site.id,value.day==2)}
	return value

static func legacy(value: Dictionary) -> Dictionary:
	var old: Dictionary=value.duplicate(true)
	old.version=7
	old.erase("combat")
	for site: Dictionary in old.sites:
		if site.weapon: site.drop={"version":1,"weapon_id":WeaponInventory.drop_weapon(old.seed,old.id,site.id)}
	return old

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for old: Dictionary in BuildActions.offers(base): result.append(upgrade(old))
	return result

static func problem(value: Variant) -> String:
	if not value is Dictionary or value.get("version")!=8 or not value.get("combat") is Dictionary or not value.get("sites") is Array: return "COMBAT_ACTION_FIELDS"
	for site: Variant in value.sites:
		if not site is Dictionary: return "COMBAT_SITE_FIELDS"
	var issue: String=BuildActions.problem(legacy(value))
	if not issue.is_empty(): return issue
	return "" if TransactionReceipt.same(value,upgrade(legacy(value))) else "COMBAT_ACTION_BINDING"

static func matches(base: Dictionary,value: Variant) -> bool:
	if not enabled(base) or not problem(value).is_empty(): return false
	for offer: Dictionary in offers(base):
		if TransactionReceipt.same(value,offer): return true
	return false

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply=BuildActions.supply(legacy(value))
	result.generated=value.duplicate(true)
	result.description+="\n消防斧：近身扇形；霰弹：5弹丸/4发。毒气预警后请离开危险区域。"
	return result

static func mission_problem(mission: Dictionary) -> String:
	var issue: String=problem(mission.get("generated"))
	if not issue.is_empty(): return issue
	var old: Dictionary=mission.duplicate(true)
	old.generated=legacy(mission.generated)
	return BuildActions.mission_problem(old)
