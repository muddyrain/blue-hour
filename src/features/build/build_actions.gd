class_name BuildActions
extends RefCounted
## Explicit V7; old V6 generators remain unchanged for historical authentication.
static func with_gear_drops(action: Dictionary) -> Dictionary:
	var value: Dictionary = action.duplicate(false)
	value.build = action.build.duplicate(false)
	var pool: int = int(value.build.version)
	value.gear_build_policy = pool
	value.build.drop_context = value.build.drop_context.duplicate(false)
	value.build.drop_context.version = pool
	value.build.drops = BuildItems.drop(value.build.drop_context, value.build.owned, pool)
	return value


static func specialization_policy(camp: Dictionary) -> Dictionary:
	if not OpeningBuild.is_m47(camp):
		return {}
	return {"plan":OpeningBuild.plan(camp), "eligible":OpeningBuild.eligible(camp)}


static func signed_specialization_policy(action: Dictionary) -> Dictionary:
	var build: Variant = action.get("build")
	var context: Variant = build.get("drop_context") if build is Dictionary else null
	var policy: Variant = context.get("specialty") if context is Dictionary else null
	if not policy is Dictionary:
		return {}
	return {"plan":policy.get("plan"), "eligible":policy.get("eligible")}


static func specialization_candidate(action: Dictionary) -> String:
	var drops: Array = action.get("build", {}).get("drops", [])
	for item: String in [BuildItems.STRIDE_HARNESS, BuildItems.GUIDED_MAG]:
		if item in drops:
			return item
	return SpecialPowers.RADIO if action.get("powers", {}).get("sample") == SpecialPowers.RADIO else ""


static func with_specialization_drop(action: Dictionary, policy: Dictionary) -> Dictionary:
	if policy.is_empty() or not _specialization_site(action) or BuildItems.replaceable_slot(action.build.drops) < 0:
		return action
	var frozen: Dictionary = policy.duplicate(true)
	frozen.radio_owned = SpecialPowers.RADIO in action.powers.owned
	var candidate: String = BuildItems.specialty_candidate(frozen, action.build.owned)
	if candidate.is_empty():
		return action
	# A radio uses the same cash work, carrying fact and settlement as an ordinary
	# ability sample. Release one passive position before occupying it as a power.
	var value: Dictionary = action.duplicate(false)
	value.build = action.build.duplicate(false)
	value.build.drop_context = action.build.drop_context.duplicate(false)
	value.build.drop_context.specialty = frozen
	value.build.drops = BuildItems.drop(value.build.drop_context, value.build.owned, int(value.build.version))
	if candidate == SpecialPowers.RADIO:
		value.powers = action.powers.duplicate(false)
		value.powers.sample = candidate
	return value


static func _specialization_site(action: Dictionary) -> bool:
	if action.get("type") != "airdrop" or action.get("mission_policy") != 1 or action.get("slot") != 2 \
			or action.get("campaign", {}).get("is_finale") != false or not action.has("gear_build_policy") \
			or not BuildItems.specialty_pool(int(action.build.version)) or action.powers.version != SpecialPowers.M47_VERSION \
			or not action.powers.sample.is_empty() or action.has("rare_policy") or action.has("event_sortie") \
			or action.has("investigation") or action.has("finale_policy") or action.has("billboard_target") \
			or action.layout.topology == "industrial" or action.layout.has("loading_yard") \
			or action.get("sortie_risk", {}).get("yard", false) or action.objective.site_ids != ["cash"]:
		return false
	for site: Dictionary in action.sites:
		if site.id == "cash" and site.get("source") == "primary" and site.get("weapon") == true \
				and site.get("work_mode") == "outdoor":
			return true
	return false


static func offers(base: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for old: Dictionary in CampaignActions.offers(base):
		# First action always exposes gear; use the existing seeded geometry generator.
		if base.settled_sorties==0 and not CampaignRules.context(base.journey.campaign).is_finale and old.slot==0 and not CampaignActions.offers(base).any(func(v:Dictionary)->bool:return v.type=="equipment"):
			var task: Dictionary=TaskActions._make(base.journey.seed,int(base.day),0,"equipment","industrial",old.layout["size"],0)
			old=CampaignActions._upgrade(WeaponActions._upgrade(task),base.profile_id,0)
		result.append(upgrade(old,base.journey.build.owned,base.journey.build.slots,BuildState.pool(base)))
	return result

static func upgrade(old: Dictionary, owned: Array, slots: Array, pool: int = BuildItems.VERSION) -> Dictionary:
	var v: Dictionary=old.duplicate(true)
	v.version=7
	var context: Dictionary={"version":1,"run_id":old.campaign.run_id,"seed":old.seed,"day":old.day,"action_id":old.id,"site_id":"cash"}
	v.build={"version":pool,"run_id":old.campaign.run_id,"owned":owned.duplicate(),"slots":slots.duplicate(),"drop_context":context,"drops":BuildItems.drop(context,owned,pool) if old.type=="equipment" and not old.campaign.is_finale else [],"policy":{"items":BuildItems.definitions(pool),"support":BasicSupport.POLICY}}
	return v

static func legacy(v: Dictionary) -> Dictionary:
	var old: Dictionary=v.duplicate(true)
	old.version=6
	old.erase("build")
	return old

static func problem(v: Variant) -> String:
	if not v is Dictionary or v.get("version")!=7 or not v.get("build") is Dictionary or not v.build.get("owned") is Array or not v.build.get("slots") is Array: return "BUILD_ACTION_FIELDS"
	if not BuildItems.valid_pool(v.build.get("version")): return "BUILD_ACTION_POOL"
	var pool: int = int(v.build.version)
	var issue: String=BuildItems.problem(v.build.owned,v.build.slots,pool)
	if not issue.is_empty(): return issue
	issue=CampaignActions.problem(legacy(v))
	if not issue.is_empty(): return issue
	return "" if TransactionReceipt.same(v,upgrade(legacy(v),v.build.owned,v.build.slots,pool)) else "BUILD_ACTION_BINDING"

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
