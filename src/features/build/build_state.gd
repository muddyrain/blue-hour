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
	if build.get("powers", {}).get("version") == SpecialPowers.WAVE_VERSION:
		return BuildItems.WAVE_CATALOG_POOL if catalog_unlocked else BuildItems.WAVE_POOL
	return BuildItems.CATALOG_POOL if catalog_unlocked else BuildItems.VERSION


static func problem(camp: Dictionary) -> String:
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
	return _problem(projected, build.opening.item_id, pool(camp))


static func _problem(camp: Dictionary, opening_item: String, item_pool: int) -> String:
	if ExplorationState.enabled(camp):
		if camp.journey.build.size()!=(10 if WorldgenState.enabled(camp) else 9): return "EXPLORATION_BUILD_FIELDS"
		var issue: String=WorldgenState.problem(camp) if WorldgenState.enabled(camp) else ""
		if not issue.is_empty(): return issue
		issue=ExplorationState.problem(camp)
		if not issue.is_empty(): return issue
		issue=PowerState.problem(camp)
		if not issue.is_empty(): return issue
		var old: Dictionary=camp.duplicate(true)
		old.journey.build.version=4
		old.journey.build.erase("exploration")
		old.journey.build.erase("worldgen")
		for source: Dictionary in old.journey.build.powers.sources: source.generated=ExplorationActions.origin(source.generated)
		return _problem(old, opening_item, item_pool)
	if PersonaState.enabled(camp):
		if camp.journey.build.size()!=8: return "PERSONA_BUILD_FIELDS"
		var issue: String=SurvivorPersona.problem(camp.journey.build.get("persona"),String(camp.journey.get("seed","")))
		if not issue.is_empty(): return issue
		issue=PowerState.problem(camp)
		if not issue.is_empty(): return issue
		var old: Dictionary=camp.duplicate(true)
		old.journey.build.version=3
		old.journey.build.erase("persona")
		# Only already-authenticated full sources are projected for the unchanged
		# old validator. Legacy camps still reject every persona-bearing source.
		for source: Dictionary in old.journey.build.powers.sources:
			source.generated=PersonaActions.legacy(source.generated)
		return _problem(old, opening_item, item_pool)
	if PowerState.enabled(camp):
		if camp.journey.build.size()!=7 or camp.journey.build.get("combat_version")!=1: return "POWER_BUILD_FIELDS"
		var old: Dictionary=camp.duplicate(true)
		old.journey.build.version=2
		old.journey.build.erase("powers")
		var issue: String=_problem(old, opening_item, item_pool)
		return PowerState.problem(camp) if issue.is_empty() else issue
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
		if not source is Dictionary or source.size()!=4 or not source.has_all(["item_id","transaction_id","context","owned"]) or source.item_id not in v.owned or source.item_id in seen or not source.context is Dictionary or not source.owned is Array: return "BUILD_ACQUISITION_FIELDS"
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
		seen.append(source.item_id)
		prior.append(source.item_id)
	return ""

static func equip(before: Dictionary, slot: int, item: String) -> Dictionary:
	if not enabled(before) or slot not in [0,1]: return {}
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
		result.sources.append({"item_id":item,"transaction_id":report.sortie_id,"context":generated.build.drop_context.duplicate(true),"owned":generated.build.owned.duplicate()})
	if PowerState.enabled(before): result.powers=PowerState.settled(before,report,generated)
	return result
