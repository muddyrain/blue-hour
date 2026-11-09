class_name PowerActions
extends RefCounted
## Explicit capability extension; the full reviewed V8 projection stays unchanged.
static func drop(generated: Dictionary, owned: Array, version: int = 1) -> String:
	var field_gear: bool = version == SpecialPowers.WAVE_VERSION and generated.type == "airdrop" \
		and generated.day >= 3 and generated.layout.topology == "industrial"
	if (generated.type!="equipment" and not field_gear) or generated.campaign.is_finale: return ""
	var missing: Array[String]=[]
	for id: String in SpecialPowers.policy(version):
		if id not in owned: missing.append(id)
	missing.sort()
	var domain: String = "BH_POWER_DROP_V3" if version == SpecialPowers.WAVE_VERSION else "BH_POWER_DROP_V1"
	return missing[("%s:%s:%s:cash"%[domain,generated.seed,generated.id]).sha256_text().substr(0,8).hex_to_int()%missing.size()] if not missing.is_empty() else ""

static func name_for(id: String) -> String:
	return SpecialPowers.definition(id).get("name", "")

static func upgrade(old: Dictionary, owned: Array, loadout: Variant) -> Dictionary:
	var value: Dictionary=old.duplicate(true)
	value.powers=loadout.duplicate(true) if loadout is Dictionary else {"version":1,"slot":loadout}
	var version: int = int(value.powers.version)
	value.powers.merge({"owned":owned.duplicate(),"sample":drop(old,owned,version),"policy":SpecialPowers.policy(version)},true)
	return value

static func legacy(value: Dictionary) -> Dictionary:
	var old: Dictionary=value.duplicate(true)
	old.erase("powers")
	return old

static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var inventory: Dictionary = base.journey.build.powers
	for old: Dictionary in CombatActions.offers(base):
		result.append(upgrade(old,inventory.owned,PowerState.loadout(inventory)))
	return result

static func problem(value: Variant) -> String:
	if not value is Dictionary or not value.get("powers") is Dictionary: return "POWER_ACTION_FIELDS"
	var power: Dictionary=value.powers
	var loadout: Variant = PowerState.loadout(power)
	if PowerState.progression(power):
		if power.size() != 6 or not power.has_all(["version","owned","slots","investments","sample","policy"]) \
				or not SurvivalContracts.integer(value.get("day"),2,RunSave.MAX_COUNTER) \
				or not PowerState.action_inventory_valid(power.owned,loadout,int(value.day)):
			return "POWER_ACTION_INVENTORY"
	elif power.size()!=5 or not power.has_all(["version","owned","slot","sample","policy"]) or power.version!=1 or not PowerState.inventory_valid(power.owned,power.slot): return "POWER_ACTION_INVENTORY"
	var issue: String=CombatActions.problem(legacy(value))
	if not issue.is_empty(): return issue
	return "" if TransactionReceipt.same(value,upgrade(legacy(value),power.owned,loadout)) else "POWER_ACTION_BINDING"

static func matches(base: Dictionary, value: Variant) -> bool:
	if not PowerState.enabled(base) or not problem(value).is_empty(): return false
	for offer: Dictionary in offers(base):
		if TransactionReceipt.same(value,offer): return true
	return false

static func supply(value: Dictionary) -> MissionSupply:
	assert(problem(value).is_empty())
	var result: MissionSupply=CombatActions.supply(legacy(value))
	result.generated=value.duplicate(true)
	if value.type=="equipment" and not value.campaign.is_finale: result.description+="\n特殊能力样本：%s（主装备点搜获、归航确认入库）"%name_for(value.powers.sample) if not value.powers.sample.is_empty() else "\n特殊能力已集齐，无额外补偿。"
	return result

static func mission_problem(mission: Dictionary) -> String:
	var issue: String=problem(mission.get("generated"))
	if not issue.is_empty(): return issue
	var old: Dictionary=mission.duplicate(true)
	old.generated=legacy(mission.generated)
	return CombatActions.mission_problem(old)
