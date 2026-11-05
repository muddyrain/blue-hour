class_name BuildState
extends RefCounted
## New journey-only inventory; original camp edit and settlement own persistence.
static func enabled(camp: Dictionary) -> bool:
	return camp.get("journey",{}).has("build")

static func initial() -> Dictionary:
	return {"version":1,"owned":[],"slots":["",""],"sources":[],"healing":{}}

static func problem(camp: Dictionary) -> String:
	if not enabled(camp): return ""
	var v: Variant=camp.journey.build
	if not CampaignState.is_short(camp) or not v is Dictionary or v.size()!=(6 if v.get("version")==2 else 5) or not v.has_all(["version","owned","slots","sources","healing"]) or ((v.version!=1 and v.version!=2) or (v.version==2 and v.get("combat_version")!=1)) or not v.sources is Array: return "BUILD_FIELDS"
	var issue: String=BuildItems.problem(v.owned,v.slots)
	if not issue.is_empty(): return issue
	if not v.healing is Dictionary or v.healing.size()>5: return "BUILD_HEALING_HISTORY"
	for id: Variant in v.healing:
		if not id is String or id not in ["1","2","3","4","5"] or not SurvivalContracts.number(v.healing[id]) or v.healing[id]<0 or v.healing[id]>RunSave.MAX_COUNTER: return "BUILD_HEALING_HISTORY"
	if v.sources.size()!=v.owned.size(): return "BUILD_ACQUISITION_COUNT"
	var seen: Array[String]=[]
	var prior: Array[String]=[]
	var group: String=""
	var context: Dictionary={}
	var group_owned: Array=[]
	for source: Variant in v.sources:
		if not source is Dictionary or source.size()!=4 or not source.has_all(["item_id","transaction_id","context","owned"]) or source.item_id not in v.owned or source.item_id in seen or not source.context is Dictionary or not source.owned is Array: return "BUILD_ACQUISITION_FIELDS"
		if not source.transaction_id is String: return "BUILD_ACQUISITION_ID"
		var parts: PackedStringArray=source.transaction_id.split(":")
		if parts.size()!=2 or parts[0]!=camp.profile_id or not parts[1].is_valid_int() or int(parts[1])<1 or int(parts[1])>camp.settled_sorties or source.transaction_id!="%s:%d"%[camp.profile_id,int(parts[1])] or source.context.get("run_id")!=camp.profile_id or source.context.get("seed")!=camp.journey.seed or source.context.get("site_id")!="cash" or source.context.get("day")!=int(parts[1])+1: return "BUILD_ACQUISITION_ID"
		var action_ids: Array[String]=[]
		for slot: int in range(3): action_ids.append(("daily-v4:%s:%d:%d"%[camp.journey.seed,int(parts[1])+1,slot]).sha256_text())
		if source.context.get("action_id") not in action_ids: return "BUILD_ACQUISITION_ACTION"
		if source.transaction_id!=group:
			if not group.is_empty() and int(parts[1])<=int(group.get_slice(":",1)): return "BUILD_ACQUISITION_ORDER"
			group=source.transaction_id
			context=source.context
			group_owned=prior.duplicate()
		if not TransactionReceipt.same(context,source.context) or not TransactionReceipt.same({"v":group_owned},{"v":source.owned}): return "BUILD_ACQUISITION_DEPARTURE_OWNED"
		if not BuildItems.problem(source.owned,["",""]).is_empty() or source.item_id not in BuildItems.drop(source.context,source.owned): return "BUILD_ACQUISITION_SOURCE"
		seen.append(source.item_id)
		prior.append(source.item_id)
	return ""

static func equip(before: Dictionary, slot: int, item: String) -> Dictionary:
	if not enabled(before) or slot not in [0,1]: return {}
	var after: Dictionary=before.duplicate(true)
	after.journey.build.slots[slot]=item
	return after if problem(after).is_empty() else {}

static func acquired(generated: Dictionary, sites: Dictionary, evacuated: bool) -> Array:
	return generated.build.drops.duplicate() if (generated.get("version")==7 or generated.get("version")==8) and evacuated and sites.get("cash",{}).get("searched",false) else []

static func settled(before: Dictionary, report: Dictionary, generated: Dictionary) -> Dictionary:
	var result: Dictionary=before.journey.build.duplicate(true)
	for event: Dictionary in report.support.accepted:
		if event.kind=="heal":
			var id: String=str(int(event.facts.member_id))
			result.healing[id]=float(result.healing.get(id,0.0))+float(event.facts.amount)
	for item: String in acquired(generated,report.site_facts,report.evacuated):
		result.owned.append(item)
		result.sources.append({"item_id":item,"transaction_id":report.sortie_id,"context":generated.build.drop_context.duplicate(true),"owned":generated.build.owned.duplicate()})
	return result
