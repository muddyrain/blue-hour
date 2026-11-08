class_name BuildActions
extends RefCounted
## Explicit V7; old V6 generators remain unchanged for historical authentication.
const GEAR_POLICY_VERSION: int = 1


static func with_gear_drops(action: Dictionary) -> Dictionary:
	var value: Dictionary = action.duplicate(false)
	value.gear_build_policy = GEAR_POLICY_VERSION
	value.build = action.build.duplicate(false)
	value.build.drops = BuildItems.drop(value.build.drop_context, value.build.owned)
	return value


static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for old: Dictionary in CampaignActions.offers(base):
		# First action always exposes gear; use the existing seeded geometry generator.
		if base.settled_sorties==0 and not CampaignRules.context(base.journey.campaign).is_finale and old.slot==0 and not CampaignActions.offers(base).any(func(v:Dictionary)->bool:return v.type=="equipment"):
			var task: Dictionary=TaskActions._make(base.journey.seed,int(base.day),0,"equipment","industrial",old.layout["size"],0)
			old=CampaignActions._upgrade(WeaponActions._upgrade(task),base.profile_id,0)
		result.append(upgrade(old,base.journey.build.owned,base.journey.build.slots))
	return result

static func upgrade(old: Dictionary, owned: Array, slots: Array) -> Dictionary:
	var v: Dictionary=old.duplicate(true)
	v.version=7
	var context: Dictionary={"version":1,"run_id":old.campaign.run_id,"seed":old.seed,"day":old.day,"action_id":old.id,"site_id":"cash"}
	v.build={"version":1,"run_id":old.campaign.run_id,"owned":owned.duplicate(),"slots":slots.duplicate(),"drop_context":context,"drops":BuildItems.drop(context,owned) if old.type=="equipment" and not old.campaign.is_finale else [],"policy":{"items":BuildItems.definitions(),"support":BasicSupport.POLICY}}
	return v

static func legacy(v: Dictionary) -> Dictionary:
	var old: Dictionary=v.duplicate(true)
	old.version=6
	old.erase("build")
	return old

static func problem(v: Variant) -> String:
	if not v is Dictionary or v.get("version")!=7 or not v.get("build") is Dictionary or not v.build.get("owned") is Array or not v.build.get("slots") is Array: return "BUILD_ACTION_FIELDS"
	var issue: String=BuildItems.problem(v.build.owned,v.build.slots)
	if not issue.is_empty(): return issue
	issue=CampaignActions.problem(legacy(v))
	if not issue.is_empty(): return issue
	return "" if TransactionReceipt.same(v,upgrade(legacy(v),v.build.owned,v.build.slots)) else "BUILD_ACTION_BINDING"

static func matches(base: Dictionary, v: Variant) -> bool:
	if not BuildState.enabled(base) or not problem(v).is_empty(): return false
	for offer: Dictionary in offers(base):
		if TransactionReceipt.same(v,offer): return true
	return false

static func supply(v: Dictionary) -> MissionSupply:
	assert(problem(v).is_empty())
	var result: MissionSupply=CampaignActions.supply(legacy(v))
	result.generated=v.duplicate(true)
	if v.type=="equipment" and not v.campaign.is_finale:
		result.description+="\n枪械 + 被动道具最多%d件（完成主回收点、归航后入库）"%v.build.drops.size() if not v.build.drops.is_empty() else "\n被动道具已集齐；枪械奖励保留。"
	return result

static func mission_problem(mission: Dictionary) -> String:
	var issue: String=problem(mission.get("generated"))
	if not issue.is_empty(): return issue
	var old: Dictionary=mission.duplicate(true)
	old.generated=legacy(mission.generated)
	return CampaignActions.mission_problem(old)
