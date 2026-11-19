class_name TraitRules
extends RefCounted
## PROJECT_TEMP passive abilities; no disk writes and no ordinary XP/HP changes.

const RULESET: String = "BH_PERSONAL_TRAIT_V1"
const IDS: Array[String] = ["steady_shot_v1", "scavenger_v1", "agile_v1"]
const NAMES: Array[String] = ["稳控射击", "熟练搜集", "轻捷行动"]
const MAX_SEARCH_POINTS_PER_SORTIE: int = 2
const THRESHOLDS: Array[int] = [0, 1, 3, 6, 10]


static func policy() -> Dictionary:
	return {"ruleset_id":RULESET, "source":"PROJECT_TEMP", "thresholds":THRESHOLDS.duplicate(),
		"shot":[0.95,0.925,0.90,0.875,0.85], "search":[0.90,0.85,0.80,0.75,0.70],
		"move":[1.08,1.12,1.16,1.20,1.24], "sources":["personal_defeats","personal_search_completions","personal_defeats"]}


static func level_for(progress: int) -> int:
	var level: int = 1
	for threshold: int in THRESHOLDS:
		if progress >= threshold:
			level += 1
	return mini(level - 1, THRESHOLDS.size())


static func role(member: Dictionary) -> int:
	var id: int = int(member.get("id", 0))
	return (id - 1) % IDS.size() + 1 if id >= 1 and id <= RosterState.MAX_HISTORY else 0


static func initialize(crew: Array) -> void:
	for member: Dictionary in crew:
		member.growth.trait = {"id":IDS[role(member)-1], "level":1, "progress":0}


static func member_problem(member: Dictionary, training_credit: int = 0, pool: bool = false) -> String:
	if not SurvivalContracts.integer(member.get("id"),1,RosterState.MAX_HISTORY if pool else 3) or not member.get("service") is Dictionary or not SurvivalContracts.integer(member.service.get("sorties"),0,RunSave.MAX_COUNTER):
		return "TRAIT_MEMBER_ID_OR_SERVICE"
	var issue: String = GrowthRules.member_problem(member)
	if not issue.is_empty():
		return issue
	var id: int = int(member.get("id",0))
	var value: Variant = member.growth.get("trait")
	if id < 1 or id > (RosterState.MAX_HISTORY if pool else 3) or not member.get("definition_id") is String or member.get("definition_id") != "crew_%d" % id or not value is Dictionary or value.size() != 3 or not value.has_all(["id","level","progress"]):
		return "TRAIT_MEMBER_FIELDS"
	if not value.id is String or value.id != IDS[role(member)-1] or not SurvivalContracts.integer(value.progress,0,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(value.level,1,5) or value.level != level_for(int(value.progress)):
		return "TRAIT_ID_OR_PROGRESS"
	var bound: int = int(member.service.sorties) * MAX_SEARCH_POINTS_PER_SORTIE if role(member) == 2 else int(member.service.kills)
	return "" if training_credit>=0 and value.progress>=training_credit and value.progress <= bound+training_credit else "TRAIT_UNEARNED_HISTORY"


static func factor(member: Dictionary, kind: String) -> float:
	var value: Variant = member.get("growth",{}).get("trait")
	if not value is Dictionary or not value.get("id") is String or value.id not in IDS or not SurvivalContracts.integer(value.get("level"),1,5):
		return 1.0
	var owner: int = IDS.find(value.id)+1
	if not SurvivalContracts.integer(member.get("id"),1,RosterState.MAX_HISTORY) or not member.get("definition_id") is String or role(member) != owner or member.definition_id != "crew_%d" % int(member.id):
		return 1.0
	if (kind == "shot" and owner == 1) or (kind == "search" and owner == 2) or (kind == "move" and owner == 3):
		return policy()[kind][int(value.level)-1]
	return 1.0


static func apply(actor: FieldActor, member: Dictionary, base_speed: float) -> void:
	actor.speed = base_speed * factor(member,"move")
	actor.trait_shot_factor = factor(member,"shot")
	actor.trait_search_factor = factor(member,"search")


static func description(member: Dictionary) -> String:
	var value: Dictionary = member.growth.trait
	var next: String = "%d / %d" % [int(value.progress),THRESHOLDS[int(value.level)]] if value.level < 5 else "%d · 本轮Lv5上限" % int(value.progress)
	var id: int = role(member)
	var effect: String = ["本人射击间隔缩短 %s%%" % String.num((1.0 - factor(member,"shot")) * 100.0, 1), "本人搜刮耗时减少 %.0f%%" % ((1.0 - factor(member,"search")) * 100.0), "本人移动速度提高 %.0f%%" % ((factor(member,"move") - 1.0) * 100.0)][id-1]
	var source: String = "本人击退记 1 点" if id != 2 else "本人每完成一处物资搜刮记 1 点，每趟最多 %d 点" % MAX_SEARCH_POINTS_PER_SORTIE
	return "%s · 特性等级 %d · 进度 %s\n%s · PROJECT_TEMP\n成长来源：%s，存活归航后结算；篝火训练每 1 粮增加 1 点。" % [NAMES[id-1],int(value.level),next,effect,source]


static func inputs_problem(value: Variant, token: Dictionary, report: Dictionary, context: Dictionary, task: Dictionary = {}) -> String:
	if not report.get("xp_inputs") is Dictionary or not report.get("growth_inputs") is Dictionary or not report.get("participants") is Array or not report.get("field_joins") is Array:
		return "TRAIT_REPORT_SOURCE"
	if not value is Dictionary or value.size() != 4 or not value.has_all(["ruleset_id","binding","diagnostic","events"]):
		return "TRAIT_INPUT_FIELDS"
	if not value.ruleset_id is String or value.ruleset_id != RULESET or not value.binding is Dictionary or not TransactionReceipt.same(value.binding,token) or not value.diagnostic is bool or value.diagnostic != report.get("xp_inputs",{}).get("diagnostic") or not value.events is Array:
		return "TRAIT_INPUT_BINDING"
	var completed: Dictionary[String, float] = {}
	var issue: String = _completed_searches(task, report, completed)
	if not issue.is_empty():
		return issue
	if value.events.size() != completed.size():
		return "TRAIT_SEARCH_COMPLETENESS"
	var previous: int = -1
	for row: Variant in value.events:
		if not row is Dictionary or row.size() != 4 or not row.has_all(["member_id", "kind", "site_id", "at_ms"]) or not row.kind is String or row.kind != "search_complete":
			return "TRAIT_SEARCH_IDENTITY"
		if not row.site_id is String or not completed.has(row.site_id) or not SurvivalContracts.integer(row.member_id, 1, RosterState.MAX_HISTORY if RescuePoolState.is_family(context) else 3):
			return "TRAIT_SEARCH_IDENTITY"
		if not SurvivalContracts.integer(row.at_ms, 0, int(report.growth_inputs.get("duration_ms", -1))) or row.at_ms < previous:
			return "TRAIT_SEARCH_SOURCE"
		var id: int = int(row.member_id)
		if SurvivorRoster.member(report.participants, id).is_empty() or SurvivorRoster.member(context.crew, id).is_empty():
			return "TRAIT_SEARCH_SOURCE"
		for join: Dictionary in report.field_joins:
			if join.member_id == id and row.at_ms < join.at_ms:
				return "TRAIT_SEARCH_BEFORE_JOIN"
		var minimum_ms: int = _minimum_search_ms(completed[row.site_id], int(row.at_ms), task, report, context)
		if minimum_ms < 0 or row.at_ms < minimum_ms:
			return "TRAIT_SEARCH_SOURCE"
		completed.erase(row.site_id)
		previous = int(row.at_ms)
	return ""


static func _completed_searches(task: Dictionary, report: Dictionary, completed: Dictionary[String, float]) -> String:
	if not report.get("searched") is bool or not report.get("food_searched") is bool:
		return "TRAIT_SEARCH_COMPLETENESS"
	if not task.has("sites"):
		# Fixed-layout missions identify their two resource sites by these names.
		if task.has("persona"):
			return "TRAIT_SEARCH_SITE_SOURCE"
		if report.searched:
			completed["cash"] = WorldSites.WORK_SECONDS
		if report.food_searched:
			completed["food"] = WorldSites.WORK_SECONDS
		return ""
	if not task.sites is Array or not report.get("site_facts") is Dictionary or report.site_facts.size() != task.sites.size():
		return "TRAIT_SEARCH_SITE_SOURCE"
	var kinds: Array[String] = []
	for definition: Variant in task.sites:
		if not definition is Dictionary or not definition.get("id") is String or definition.id.is_empty() or definition.get("kind") not in ["cash", "food"]:
			return "TRAIT_SEARCH_SITE_SOURCE"
		var state: Variant = report.site_facts.get(definition.id)
		if not state is Dictionary or not state.get("searched") is bool or not SurvivalContracts.number(definition.get("seconds")) or definition.seconds <= 0.0:
			return "TRAIT_SEARCH_SITE_SOURCE"
		if state.searched:
			completed[definition.id] = float(definition.seconds)
			kinds.append(definition.kind)
	if ("cash" in kinds) != report.searched or ("food" in kinds) != report.food_searched:
		return "TRAIT_SEARCH_COMPLETENESS"
	return ""


static func _minimum_search_ms(seconds: float, at_ms: int, task: Dictionary, report: Dictionary, context: Dictionary) -> int:
	if not task.has("persona"):
		var base_ms: int = floori(seconds * 700.0)
		if task.get("version") in [7, 8]:
			base_ms = floori(base_ms * BuildItems.frozen_factors(task.build).work)
		return base_ms
	# A later worker can finish progress left by a faster participant at this site.
	var fastest: float = INF
	for participant: Dictionary in report.participants:
		var id: int = int(participant.id)
		if report.field_joins.any(func(join: Dictionary) -> bool: return join.member_id == id and join.at_ms > at_ms):
			continue
		var member: Dictionary = SurvivorRoster.member(context.crew, id)
		if member.is_empty():
			return -1
		fastest = minf(fastest, factor(member, "search") * PersonaState.factor(task, id, "work"))
	if not is_finite(fastest) or fastest <= 0.0:
		return -1
	var work: float = BuildItems.frozen_factors(task.build).work
	var location: float = HarborWarehouse.WORK_FACTOR if HarborWarehouse.should_apply(task) else 1.0
	return floori(seconds * fastest * work * location * 1000.0)


static func bank(after: Dictionary, before: Dictionary, report: Dictionary, token: Dictionary, task: Dictionary = {}) -> Dictionary:
	var issue: String = inputs_problem(report.get("trait_inputs"),token,report,before,task)
	if not issue.is_empty():
		return {"error":issue}
	var rows: Array[Dictionary] = []
	for participant: Dictionary in report.participants:
		var id: int = int(participant.id)
		var old: Dictionary = SurvivorRoster.member(before.crew,id)
		var member: Dictionary = SurvivorRoster.member(after.crew,id)
		var count: int = 0
		var events: Array = report.trait_inputs.events if role(member) == 2 else report.xp_inputs.events
		for event: Dictionary in events:
			if event.member_id == id:
				count += 1
		var eligible: bool = report.evacuated and member.health > 0 and not report.trait_inputs.diagnostic
		var gained: int = count if eligible else 0
		if role(member) == 2:
			gained = mini(gained, MAX_SEARCH_POINTS_PER_SORTIE)
		var progress: int = int(old.growth.trait.progress)+gained
		if progress > RunSave.MAX_COUNTER:
			return {"error":"TRAIT_PROGRESS_CAPACITY"}
		var next: Dictionary = {"id":old.growth.trait.id,"level":level_for(progress),"progress":progress}
		member.growth.trait = next
		rows.append({"member_id":id,"eligible":eligible,"source_events":count,"gained":gained,
			"before":old.growth.trait.duplicate(true),"after":next.duplicate(true)})
	return {"error":"", "ledger":{"ruleset_id":RULESET,"binding":token.duplicate(true),"members":rows}}
