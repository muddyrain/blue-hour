class_name BuildState
extends RefCounted
## New journey-only inventory; original camp edit and settlement own persistence.
static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey",{}).has("build")

static func initial() -> Dictionary:
	return {"version":1,"owned":[],"slots":["",""],"sources":[],"healing":{}}


static func pool(camp: Dictionary) -> int:
	var build: Dictionary = camp.get("journey", {}).get("build", {})
	var catalog: Dictionary = build.get("catalog", {})
	var catalog_unlocked: bool = not catalog.get("unlock", "").is_empty()
	# Pure legacy task projections retain the explicit build policy while replacing campaign.
	# Actual camps still require the campaign/build agreement in problem().
	var progression: Variant = build.get("progression")
	var m48_source: bool = progression is Dictionary and SurvivalContracts.integer(progression.get("version"),1,1) \
		and SurvivalContracts.integer(build.get("powers", {}).get("version"),SpecialPowers.M48_VERSION,SpecialPowers.M48_VERSION)
	if m48_enabled(camp) or m48_source:
		return BuildItems.M48_CATALOG_POOL if catalog_unlocked else BuildItems.M48_POOL
	if OpeningBuild.is_m47(camp):
		return BuildItems.SPECIALTY_CATALOG_POOL if catalog_unlocked else BuildItems.SPECIALTY_POOL
	if build.get("powers", {}).get("version") == SpecialPowers.WAVE_VERSION:
		return BuildItems.WAVE_CATALOG_POOL if catalog_unlocked else BuildItems.WAVE_POOL
	return BuildItems.CATALOG_POOL if catalog_unlocked else BuildItems.VERSION


static func _problem_base(camp: Dictionary) -> String:
	if not enabled(camp): return ""
	var build: Variant = camp.journey.build
	if not build is Dictionary:
		return "BUILD_FIELDS"
	if not build.has("opening"):
		return _problem(camp, "", pool(camp))
	var issue: String = OpeningBuild.problem(camp)
	if not issue.is_empty():
		return issue
	if build.has("catalog"):
		issue = CatalogProgress.policy_problem(build.catalog)
		if not issue.is_empty():
			return issue
	var projected: Dictionary = camp.duplicate(false)
	projected.journey = camp.journey.duplicate(false)
	projected.journey.build = build.duplicate(false)
	projected.journey.build.erase("opening")
	projected.journey.build.erase("catalog")
	return _problem(projected, build.opening.item_id, pool(camp), BuildActions.specialization_policy(camp))


static func _problem(camp: Dictionary, opening_item: String, item_pool: int, specialty: Dictionary = {}) -> String:
	if ExplorationState.enabled(camp):
		if camp.journey.build.size()!=(10 if WorldgenState.enabled(camp) else 9): return "EXPLORATION_BUILD_FIELDS"
		var issue: String=WorldgenState.problem(camp) if WorldgenState.enabled(camp) else ""
		if not issue.is_empty(): return issue
		issue=ExplorationState.problem(camp)
		if not issue.is_empty(): return issue
		issue=PowerState.problem(camp, specialty)
		if not issue.is_empty(): return issue
		var old: Dictionary=camp.duplicate(true)
		old.journey.build.version=4
		old.journey.build.erase("exploration")
		old.journey.build.erase("worldgen")
		if specialty.is_empty():
			for source: Dictionary in old.journey.build.powers.sources: source.generated=ExplorationActions.origin(source.generated)
		return _problem(old, opening_item, item_pool, specialty)
	if PersonaState.enabled(camp):
		if camp.journey.build.size()!=8: return "PERSONA_BUILD_FIELDS"
		var issue: String=SurvivorPersona.problem(camp.journey.build.get("persona"),String(camp.journey.get("seed","")))
		if not issue.is_empty(): return issue
		if specialty.is_empty():
			issue=PowerState.problem(camp)
			if not issue.is_empty(): return issue
		var old: Dictionary=camp.duplicate(true)
		old.journey.build.version=3
		old.journey.build.erase("persona")
		# Only already-authenticated full sources are projected for the unchanged
		# old validator. Legacy camps still reject every persona-bearing source.
		if specialty.is_empty():
			for source: Dictionary in old.journey.build.powers.sources:
				source.generated=PersonaActions.legacy(source.generated)
		return _problem(old, opening_item, item_pool, specialty)
	if PowerState.enabled(camp):
		if camp.journey.build.size()!=7 or camp.journey.build.get("combat_version")!=1: return "POWER_BUILD_FIELDS"
		var old: Dictionary=camp.duplicate(true)
		old.journey.build.version=2
		old.journey.build.erase("powers")
		var issue: String=_problem(old, opening_item, item_pool, specialty)
		return PowerState.problem(camp) if specialty.is_empty() and issue.is_empty() else issue
	var v: Variant=camp.journey.build
	if not CampaignState.is_short(camp) or not v is Dictionary or v.size()!=(6 if v.get("version")==2 else 5) or not v.has_all(["version","owned","slots","sources","healing"]) or ((v.version!=1 and v.version!=2) or (v.version==2 and v.get("combat_version")!=1)) or not v.sources is Array: return "BUILD_FIELDS"
	var issue: String=BuildItems.problem(v.owned,v.slots,item_pool)
	if not issue.is_empty(): return issue
	if not v.healing is Dictionary or v.healing.size()>5: return "BUILD_HEALING_HISTORY"
	for id: Variant in v.healing:
		if not id is String or id not in ["1","2","3","4","5"] or not SurvivalContracts.number(v.healing[id]) or v.healing[id]<0 or v.healing[id]>RunSave.MAX_COUNTER: return "BUILD_HEALING_HISTORY"
	if v.sources.size() + int(not opening_item.is_empty()) != v.owned.size(): return "BUILD_ACQUISITION_COUNT"
	var seen: Array[String]=[]
	var prior: Array[String]=[]
	if not opening_item.is_empty():
		seen.append(opening_item)
		prior.append(opening_item)
	var group: String=""
	var context: Dictionary={}
	var group_owned: Array=[]
	for source: Variant in v.sources:
		if not source is Dictionary or not source.has_all(["item_id","transaction_id","context","owned"]) or source.item_id not in v.owned or source.item_id in seen or not source.context is Dictionary or not source.owned is Array: return "BUILD_ACQUISITION_FIELDS"
		var specialty_item: bool = source.item_id in [BuildItems.STRIDE_HARNESS, BuildItems.GUIDED_MAG]
		if source.size() != 4 + int(specialty_item) or (specialty_item and not source.get("generated") is Dictionary):
			return "BUILD_ACQUISITION_FIELDS"
		if not opening_item.is_empty() and v.owned[seen.size()] != source.item_id: return "BUILD_ACQUISITION_ORDER"
		if not source.transaction_id is String: return "BUILD_ACQUISITION_ID"
		var parts: PackedStringArray=source.transaction_id.split(":")
		if parts.size()!=2 or parts[0]!=camp.profile_id or not parts[1].is_valid_int() or int(parts[1])<1 or int(parts[1])>camp.settled_sorties or source.transaction_id!="%s:%d"%[camp.profile_id,int(parts[1])] or source.context.get("run_id")!=camp.profile_id or source.context.get("seed")!=camp.journey.seed or source.context.get("site_id")!="cash" or source.context.get("day")!=int(parts[1])+1: return "BUILD_ACQUISITION_ID"
		var action_ids: Array[String]=[]
		for slot: int in range(3): action_ids.append(("daily-v4:%s:%d:%d"%[camp.journey.seed,int(parts[1])+1,slot]).sha256_text())
		if source.context.get("action_id") not in action_ids: return "BUILD_ACQUISITION_ACTION"
		if source.context.has("liner") and source.context.action_id != action_ids[2]:
			return "BUILD_ACQUISITION_LINER_ACTION"
		if source.transaction_id!=group:
			if not group.is_empty() and int(parts[1])<=int(group.get_slice(":",1)): return "BUILD_ACQUISITION_ORDER"
			group=source.transaction_id
			context=source.context
			group_owned=prior.duplicate()
		if not TransactionReceipt.same(context,source.context) or not TransactionReceipt.same({"v":group_owned},{"v":source.owned}): return "BUILD_ACQUISITION_DEPARTURE_OWNED"
		if source.item_id not in BuildItems.drop(source.context,source.owned,item_pool): return "BUILD_ACQUISITION_SOURCE"
		if specialty_item and not _specialty_source_valid(source, specialty):
			return "BUILD_ACQUISITION_SPECIALTY_SOURCE"
		seen.append(source.item_id)
		prior.append(source.item_id)
	return ""


static func _specialty_source_valid(source: Dictionary, specialty: Dictionary) -> bool:
	var generated: Dictionary = source.generated
	if specialty.is_empty() or not ExplorationActions.problem(generated, true).is_empty():
		return false
	return BuildActions.specialization_candidate(generated) == source.item_id \
		and TransactionReceipt.same(BuildActions.signed_specialization_policy(generated), specialty) \
		and TransactionReceipt.same(generated.build.drop_context, source.context) \
		and generated.build.owned == source.owned

static func equip(before: Dictionary, slot: int, item: String) -> Dictionary:
	if not enabled(before) or slot < 0 or slot >= before.journey.build.slots.size(): return {}
	var after: Dictionary=before.duplicate(true)
	after.journey.build.slots[slot]=item
	return after if problem(after).is_empty() else {}

static func acquired(generated: Dictionary, sites: Dictionary, evacuated: bool) -> Array:
	return generated.build.drops.duplicate() if (generated.get("version")==7 or (generated.get("version")==8 or generated.get("version")==9)) and evacuated and sites.get("cash",{}).get("searched",false) else []

static func settled(before: Dictionary, report: Dictionary, generated: Dictionary) -> Dictionary:
	var result: Dictionary=before.journey.build.duplicate(true)
	for event: Dictionary in report.support.accepted:
		if BuildAuthority.healing_kind(event.kind):
			var id: String=str(int(event.facts.member_id))
			result.healing[id]=float(result.healing.get(id,0.0))+float(event.facts.amount)
	for item: String in acquired(generated,report.site_facts,report.evacuated):
		result.owned.append(item)
		var source: Dictionary = {"item_id":item,"transaction_id":report.sortie_id,"context":generated.build.drop_context.duplicate(true),"owned":generated.build.owned.duplicate()}
		if item in [BuildItems.STRIDE_HARNESS, BuildItems.GUIDED_MAG]:
			source.generated = generated.duplicate(true)
		result.sources.append(source)
	if PowerState.enabled(before): result.powers=PowerState.settled(before,report,generated)
	return result


static func m48_enabled(camp: Dictionary) -> bool:
	var marker: Variant = camp.get("journey", {}).get("campaign", {}).get("economy")
	return marker is Dictionary and SurvivalContracts.integer(marker.get("version"), 1, 1)


static func enable_m48(build: Dictionary) -> void:
	build.progression = {"version":1, "enhanced":[], "purchases":[]}


static func problem(camp: Dictionary) -> String:
	if not enabled(camp):
		return ""
	var marked: bool = m48_enabled(camp)
	if camp.journey.build.has("progression") != marked:
		return "BUILD_PROGRESSION_MODE"
	if not marked:
		return _problem_base(camp)
	var issue: String = _progression_problem(camp)
	if not issue.is_empty():
		return issue
	var projected: Dictionary = camp.duplicate(false)
	projected.journey = camp.journey.duplicate(false)
	projected.journey.build = camp.journey.build.duplicate(false)
	projected.journey.build.erase("progression")
	return _problem_base(projected)


static func _progression_problem(camp: Dictionary) -> String:
	var value: Variant = camp.journey.build.get("progression")
	if not camp.journey.build.get("owned") is Array or not camp.journey.build.get("sources") is Array or not camp.journey.build.get("slots") is Array:
		return "BUILD_PROGRESSION_CONTAINER"
	if not value is Dictionary or value.size() != 3 or not value.has_all(["version", "enhanced", "purchases"]) \
			or value.version != 1 or not BuildItems.enhancements_valid(value.enhanced, pool(camp)) or not value.purchases is Array:
		return "BUILD_PROGRESSION_FIELDS"
	var enhanced: Array[String] = []
	var slots: int = 2
	var previous_day: int = 2
	var spending_today: int = 0
	for purchase: Variant in value.purchases:
		if not purchase is Dictionary or purchase.size() != 3 or not purchase.has_all(["choice", "day", "cost"]) \
				or not purchase.choice is String or not SurvivalContracts.integer(purchase.day, previous_day, int(camp.day)):
			return "BUILD_PROGRESSION_PURCHASE"
		var expected_cost: int = BuildItems.UPGRADE_COST
		if purchase.choice == "next_slot":
			if slots >= 4:
				return "BUILD_PROGRESSION_SLOT_COUNT"
			expected_cost = 16 if slots == 2 else 24
			slots += 1
		else:
			if purchase.choice not in camp.journey.build.owned or purchase.choice in enhanced:
				return "BUILD_PROGRESSION_OWNERSHIP"
			var acquired_day: int = 1
			for source: Variant in camp.journey.build.sources:
				if not source is Dictionary or not source.get("item_id") is String or not source.get("transaction_id") is String:
					return "BUILD_PROGRESSION_SOURCE"
				if source.item_id == purchase.choice:
					acquired_day = int(source.transaction_id.get_slice(":", 1)) + 1
			if purchase.day <= acquired_day:
				return "BUILD_PROGRESSION_BEFORE_ACQUISITION"
			enhanced.append(purchase.choice)
		if not SurvivalContracts.integer(purchase.cost, expected_cost, expected_cost):
			return "BUILD_PROGRESSION_PRICE"
		previous_day = int(purchase.day)
		if purchase.day == camp.day:
			spending_today += expected_cost
	if slots != camp.journey.build.slots.size() or enhanced != value.enhanced:
		return "BUILD_PROGRESSION_RESULT"
	if not SurvivalContracts.integer(camp.camp_spending, spending_today, RunSave.MAX_COUNTER):
		return "BUILD_PROGRESSION_SPENDING"
	return ""


static func investment_offer(camp: Dictionary, choice: String) -> Dictionary:
	var reason: String = ""
	var cost: int = 10
	var summary: String = ""
	if not m48_enabled(camp) or camp.journey.state != "ACTIVE" or CampaignState.ended(camp):
		reason = "当前旅程不可投资"
	elif choice == "next_slot":
		var count: int = camp.journey.build.slots.size()
		cost = 16 if count == 2 else 24
		summary = "被动槽 %d → %d" % [count, count + 1]
		if count >= 4:
			reason = "已开启四个被动槽"
	elif choice not in camp.journey.build.owned:
		reason = "先回收并确认拥有该道具"
	elif choice in camp.journey.build.progression.enhanced:
		reason = "该道具已强化"
	else:
		summary = BuildItems.effect_text(choice, false, pool(camp)) + " → " + BuildItems.effect_text(choice, true, pool(camp))
	if reason.is_empty() and int(camp.cash) < cost:
		reason = "还差 %d 币" % [cost - int(camp.cash)]
	return {"available":reason.is_empty(), "reason":reason, "cost":cost, "summary":summary}


static func invest(before: Dictionary, choice: String) -> Dictionary:
	choice = investment_intent(before, choice)
	if choice.is_empty():
		return {}
	var offer: Dictionary = investment_offer(before, choice)
	if not offer.available:
		return {}
	var after: Dictionary = before.duplicate(true)
	if choice == "next_slot":
		after.journey.build.slots.append("")
	else:
		after.journey.build.progression.enhanced.append(choice)
	after.journey.build.progression.purchases.append({"choice":choice, "day":int(before.day), "cost":int(offer.cost)})
	after.cash -= int(offer.cost)
	after.camp_spending += int(offer.cost)
	return after


static func registration_problem(camp: Dictionary) -> String:
	if not m48_enabled(camp):
		return ""
	return "" if TransactionReceipt.same(camp.journey.build.get("progression", {}), {"version":1, "enhanced":[], "purchases":[]}) else "BUILD_PROGRESSION_REGISTRATION"


static func investment_value(camp: Dictionary, choice: String) -> String:
	return JSON.stringify({"choice":choice, "before_hash":SurvivalContracts.fingerprint(camp)})


static func investment_intent(camp: Dictionary, value: String) -> String:
	var intent: Variant = JSON.parse_string(value)
	if not intent is Dictionary or intent.size() != 2 or not intent.has_all(["choice", "before_hash"]) \
			or not intent.choice is String or intent.before_hash != SurvivalContracts.fingerprint(camp):
		return ""
	return intent.choice
