class_name PowerActions
extends RefCounted
## Explicit capability extension; the full reviewed V8 projection stays unchanged.
static func drop(generated: Dictionary, owned: Array) -> String:
	if generated.type!="equipment" or generated.campaign.is_finale: return ""
	var missing: Array[String]=[]
	for id: String in SpecialPowers.POLICY:
		if id not in owned: missing.append(id)
	missing.sort()
	return missing[("BH_POWER_DROP_V1:%s:%s:cash"%[generated.seed,generated.id]).sha256_text().substr(0,8).hex_to_int()%missing.size()] if not missing.is_empty() else ""

static func upgrade(old: Dictionary, owned: Array, slot: String) -> Dictionary:
	var value: Dictionary=old.duplicate(true)
	value.powers={"version":1,"owned":owned.duplicate(),"slot":slot,"sample":drop(old,owned),"policy":SpecialPowers.POLICY}
	return value

static func legacy(value: Dictionary) -> Dictionary:
	var old: Dictionary=value.duplicate(true)
	old.erase("powers")
	return old

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for old: Dictionary in CombatActions.offers(base): result.append(upgrade(old,base.journey.build.powers.owned,base.journey.build.powers.slot))
	return result

static func problem(value: Variant) -> String:
	if not value is Dictionary or not value.get("powers") is Dictionary: return "POWER_ACTION_FIELDS"
	var power: Dictionary=value.powers
	if power.size()!=5 or not power.has_all(["version","owned","slot","sample","policy"]) or power.version!=1 or not PowerState.inventory_valid(power.owned,power.slot): return "POWER_ACTION_INVENTORY"
	var issue: String=CombatActions.problem(legacy(value))
	if not issue.is_empty(): return issue
	return "" if TransactionReceipt.same(value,upgrade(legacy(value),power.owned,power.slot)) else "POWER_ACTION_BINDING"

static func matches(base: Dictionary, value: Variant) -> bool:
	if not PowerState.enabled(base) or not problem(value).is_empty(): return false
	for offer: Dictionary in offers(base):
		if TransactionReceipt.same(value,offer): return true
	return false

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply=CombatActions.supply(legacy(value))
	result.generated=value.duplicate(true)
	if value.type=="equipment" and not value.campaign.is_finale: result.description+="\n特殊能力样本：%s（主装备点搜获、归航确认入库）"%SpecialPowers.POLICY[value.powers.sample].name if not value.powers.sample.is_empty() else "\n特殊能力已集齐，无额外补偿。"
	return result

static func mission_problem(mission: Dictionary) -> String:
	var issue: String=problem(mission.get("generated"))
	if not issue.is_empty(): return issue
	var old: Dictionary=mission.duplicate(true)
	old.generated=legacy(mission.generated)
	return CombatActions.mission_problem(old)
