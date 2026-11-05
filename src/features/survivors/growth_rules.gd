class_name GrowthRules
extends RefCounted
## PROJECT_TEMP only. Complete departure facts, never service totals, authorize an XP grant.

const RULESET: String = "BH_GROWTH_XP_V1"
const MAX_XP: int = RunSave.MAX_COUNTER * 10
const MAX_THRESHOLD_LEVEL: int = 30_000_000 # Safe JSON/integer arithmetic, not a gameplay level cap.
const MAX_EVENTS: int = 4096 # Fits the existing journal budget without truncating the XP evidence.


static func policy() -> Dictionary:
	return {"ruleset_id":RULESET,"source":"PROJECT_TEMP","scope":"GROWTH_PILOT",
		"xp_per_defeat":10,"health_per_level":5,"threshold":"10*(N*N-1)"}


static func threshold(level: int) -> int:
	if level < 1 or level > MAX_THRESHOLD_LEVEL:
		return -1
	return 10 * (level * level - 1)


static func level_for(total: int) -> int:
	if total < 0 or total > MAX_XP:
		return -1
	var lower: int = 1
	var upper: int = 2
	while threshold(upper) <= total:
		upper *= 2
	while lower + 1 < upper:
		var middle: int = (lower + upper) / 2
		if threshold(middle) <= total:
			lower = middle
		else:
			upper = middle
	return lower


static func maximum(member: Dictionary) -> float:
	var value: Variant = member.get("growth")
	if not value is Dictionary or not SurvivalContracts.integer(value.get("xp_total"),0,MAX_XP):
		return 200.0
	return 200.0 + 5.0 * (level_for(int(value.xp_total)) - 1)


static func initialize(crew: Array) -> void:
	for member: Dictionary in crew:
		member.growth = {"level":1,"xp_total":0,"trait":{"id":null,"level":null,"progress":null},
			"training_state":"unavailable","last_action":{}}


static func member_problem(member: Dictionary) -> String:
	var value: Variant = member.get("growth")
	if not value is Dictionary or value.size() != 5 or not value.has_all(["level","xp_total","trait","training_state","last_action"]):
		return "XP_MEMBER_FIELDS"
	if not SurvivalContracts.integer(value.xp_total,0,MAX_XP) or int(value.xp_total) % 10 != 0 or not SurvivalContracts.integer(value.level,1,MAX_THRESHOLD_LEVEL) or value.level != level_for(int(value.xp_total)):
		return "XP_LEVEL_OR_TOTAL"
	if not member.get("service") is Dictionary or not SurvivalContracts.integer(member.service.get("kills"),0,RunSave.MAX_COUNTER) or value.xp_total > int(member.service.kills) * 10:
		return "XP_UNEARNED_HISTORY"
	return ""


static func legacy_view(member: Dictionary) -> Dictionary:
	var projected: Dictionary = member.duplicate(true)
	projected.growth.erase("xp_total")
	projected.growth.level = null
	projected.growth.experience = null
	return projected


static func limits(crew: Array) -> Dictionary:
	var result: Dictionary = {}
	for member: Dictionary in crew:
		result[int(member.id)] = maximum(member)
	return result


static func member_row(rows: Array, id: int) -> Dictionary:
	for row: Variant in rows:
		if row is Dictionary and row.get("member_id") == id:
			return row
	return {}


static func inputs_problem(value: Variant, token: Dictionary, action: Dictionary, participants: Array, inventory: Dictionary) -> String:
	if not value is Dictionary or value.size() != 5 or not value.has_all(["ruleset_id","binding","diagnostic","spawn_count","events"]):
		return "XP_INPUT_FIELDS"
	if value.ruleset_id != RULESET or not value.binding is Dictionary or not TransactionReceipt.same(value.binding,token) or not value.diagnostic is bool or not SurvivalContracts.integer(value.spawn_count,0,RunSave.MAX_COUNTER) or not value.events is Array or value.events.size() > MAX_EVENTS:
		return "XP_INPUT_BINDING"
	if not action.get("members") is Array or not SurvivalContracts.integer(action.get("duration_ms"),0,RunSave.MAX_COUNTER):
		return "XP_ACTION_FIELDS"
	var seen: Dictionary = {}
	var by_member: Dictionary = {}
	var previous: int = -1
	for participant: Dictionary in participants:
		by_member[int(participant.id)] = []
	for event: Variant in value.events:
		if not event is Dictionary or event.size() != 6 or not event.has_all(["member_id","kind","enemy_id","at_ms","weapon_id","instance_id"]):
			return "XP_EVENT_FIELDS"
		if not SurvivalContracts.integer(event.member_id,1,SurvivalContracts.MAX_ID) or not by_member.has(int(event.member_id)) or event.kind != "defeat" or not SurvivalContracts.integer(event.enemy_id,0,RunSave.MAX_COUNTER) or seen.has(int(event.enemy_id)):
			return "XP_EVENT_IDENTITY"
		if not value.diagnostic and event.enemy_id >= value.spawn_count:
			return "XP_EVENT_SPAWN"
		if not SurvivalContracts.integer(event.at_ms,0,int(action.duration_ms)) or event.at_ms < previous:
			return "XP_EVENT_TIME"
		var participant: Dictionary = SurvivorRoster.member(participants,int(event.member_id))
		var weapon: Dictionary = WeaponInventory.find(inventory,participant.weapon_instance_id)
		if weapon.is_empty() or event.instance_id != participant.weapon_instance_id or event.weapon_id != weapon.weapon_id:
			return "XP_EVENT_WEAPON_OWNER"
		seen[int(event.enemy_id)] = true
		previous = int(event.at_ms)
		var receipt: Dictionary = event.duplicate(true)
		receipt.erase("member_id")
		by_member[int(event.member_id)].append(receipt)
	for participant: Dictionary in participants:
		var row: Dictionary = member_row(action.members,int(participant.id))
		var events: Array = by_member[int(participant.id)]
		if row.is_empty() or row.get("total") != events.size() or not row.get("recent") is Array:
			return "XP_COMPLETE_EVENT_COUNTS"
		var recent: Array = events.slice(maxi(0,events.size()-SurvivorGrowth.RECENT_LIMIT))
		if not TransactionReceipt.same({"v":recent},{"v":row.recent}):
			return "XP_ACTION_SUFFIX"
	return ""


static func bank(after: Dictionary, before: Dictionary, report: Dictionary, token: Dictionary) -> Dictionary:
	if not report.get("growth_inputs") is Dictionary or not report.get("participants") is Array:
		return {"error":"XP_REPORT_FIELDS"}
	var issue: String = inputs_problem(report.get("xp_inputs"),token,report.growth_inputs,report.participants,before)
	if not issue.is_empty():
		return {"error":issue}
	var rows: Array[Dictionary] = []
	for participant: Dictionary in report.participants:
		var id: int = int(participant.id)
		var old: Dictionary = SurvivorRoster.member(before.crew,id)
		var member: Dictionary = SurvivorRoster.member(after.crew,id)
		var count: int = 0
		for event: Dictionary in report.xp_inputs.events:
			if int(event.member_id) == id:
				count += 1
		var eligible: bool = report.evacuated and member.health > 0 and not report.xp_inputs.diagnostic
		var gained: int = count * 10 if eligible else 0
		var total: int = int(old.growth.xp_total) + gained
		if total > MAX_XP:
			return {"error":"XP_TOTAL_CAPACITY"}
		var level: int = level_for(total)
		var increment: float = 5.0 * (level - int(old.growth.level))
		var health_before: float = float(member.health)
		member.growth.xp_total = total
		member.growth.level = level
		if eligible:
			member.health = minf(maximum(member),health_before+increment)
		rows.append({"member_id":id,"eligible":eligible,"defeats":count,"xp_before":old.growth.xp_total,
			"xp_gained":gained,"xp_after":total,"level_before":old.growth.level,"level_after":level,
			"max_before":maximum(old),"max_after":maximum(member),"health_before":health_before,"health_after":member.health})
	return {"error":"","ledger":{"ruleset_id":RULESET,"binding":token.duplicate(true),"members":rows}}


static func result_problem(receipt: Dictionary) -> String:
	var result: Dictionary = receipt.envelope.result
	var report: Variant = result.get("battle")
	if not report is Dictionary or not report.get("growth_inputs") is Dictionary or not report.get("xp_inputs") is Dictionary:
		return "XP_RESULT_SOURCE"
	if report.size() != FrozenSettlement.REPORT_KEYS.size()+2+int((receipt.rules.get("data_version")==5 or receipt.rules.get("data_version")==6))+int(FieldJoinState.is_family(receipt.base))+int(TraitState.is_family(receipt.base))+int((receipt.rules.get("data_version")==3 or receipt.rules.get("data_version")==4 or (receipt.rules.get("data_version")==5 or receipt.rules.get("data_version")==6))) or not report.has_all(FrozenSettlement.REPORT_KEYS) or not report.has("rescue"):
		return "XP_RESULT_REPORT_FIELDS"
	if not FrozenSettlement._rules_problem(receipt.rules).is_empty() or receipt.rules.get("scope") != (RescuePoolState.SCOPE if RescuePoolState.is_family(receipt.base) else TraitState.SCOPE if TraitState.is_family(receipt.base) else (FieldJoinState.SCOPE if FieldJoinState.is_family(receipt.base) else GrowthState.SCOPE)) or not result.get("rules") is Dictionary or not TransactionReceipt.same(result.rules,receipt.rules):
		return "XP_RESULT_RULES"
	if FieldJoinState.is_family(receipt.base):
		var join_issue: String = FieldJoinRules.report_problem(receipt.base,report,receipt.joins)
		if not join_issue.is_empty():
			return join_issue
	var before: Dictionary = FieldJoinRules.context(receipt)
	var actual: Dictionary = result.camp
	if TrainingState.is_family(before) and not TransactionReceipt.same({"v":before.training},{"v":actual.get("training")}):
		return "TRAINING_HISTORY_CHANGED_IN_SORTIE"
	var issue: String = SurvivalContracts.report_problem(before.crew,report,true)
	if not issue.is_empty() or not TransactionReceipt.same({"v":report.participants},{"v":FieldJoinRules.participants(receipt)}):
		return "XP_RESULT_PARTICIPANTS"
	var source: Dictionary = receipt.rules.mission
	var carry: Dictionary = {"loot":source.cash_reward if report.searched else 0,
		"food":source.food_reward if report.food_searched else 0,
		"weapons":[WeaponInventory.reward(receipt.transaction_id,WeaponState.is_family(receipt.base))] if report.searched and source.has_weapon_sample else []}
	if (receipt.rules.get("data_version")==3 or receipt.rules.get("data_version")==4 or (receipt.rules.get("data_version")==5 or receipt.rules.get("data_version")==6)):
		var site_issue: String = WorldSites.problem(source.generated.sites,report.get("site_facts"))
		if not site_issue.is_empty(): return site_issue
		carry=WorldSites.carry(source.generated.sites,report.site_facts,receipt.transaction_id,WeaponState.is_family(receipt.base),source.generated)
	issue = FrozenSettlement._facts_problem({"before":receipt.base,"report":report,"rules":receipt.rules,"carried":carry,"token":RunTransaction.token_for(receipt)})
	if not issue.is_empty():
		return "XP_RESULT_FACTS:"+issue
	if (receipt.rules.get("data_version")==5 or receipt.rules.get("data_version")==6) and not TransactionReceipt.same(actual.last_day.get("task",{}),TaskActions.outcome(receipt.rules.mission.generated,report)):
		return "TASK_RESULT_SUMMARY"
	if receipt.rules.get("data_version")!=5 and receipt.rules.get("data_version")!=6 and actual.last_day.has("task"):
		return "TASK_RESULT_VERSION"
	if not result.get("food") is Dictionary or not result.get("hunger") is Dictionary:
		return "XP_RESULT_RATIONS"
	issue = SurvivalContracts.ledgers_problem(result.food,result.hunger,FieldJoinRules.meal_members(report.member_results,receipt.base),limits(before.crew))
	if not issue.is_empty():
		return issue
	var expected: Dictionary = actual.duplicate(true)
	for member: Dictionary in before.crew:
		var target: Dictionary = SurvivorRoster.member(expected.crew,int(member.id))
		var battle: Dictionary = SurvivorRoster.member(report.member_results,int(member.id))
		target.growth = member.growth.duplicate(true)
		target.service = member.service.duplicate(true)
		target.health = battle.health if not battle.is_empty() else member.health
	issue = SurvivorRoster.record(expected,before,report,receipt.transaction_id)
	if issue.is_empty():
		issue = SurvivorGrowth.bank(expected,before,report,receipt.transaction_id)
	if not issue.is_empty():
		return "XP_RESULT_HISTORY:"+issue
	for effect: Dictionary in result.hunger.effects:
		SurvivorRoster.member(expected.crew,int(effect.id)).health = effect.health_after
	var computed: Dictionary = bank(expected,before,report,RunTransaction.token_for(receipt))
	if not computed.error.is_empty() or not result.get("xp") is Dictionary or not TransactionReceipt.same(result.xp,computed.get("ledger",{})):
		return "XP_RESULT_LEDGER"
	if TraitState.is_family(receipt.base):
		var computed_traits: Dictionary = TraitRules.bank(expected,before,report,RunTransaction.token_for(receipt),receipt.rules.mission.get("generated",{}))
		if not computed_traits.error.is_empty() or not result.get("traits") is Dictionary or not TransactionReceipt.same(result.traits,computed_traits.get("ledger",{})):
			return "TRAIT_RESULT_LEDGER"
	for member: Dictionary in before.crew:
		var target: Dictionary = SurvivorRoster.member(expected.crew,int(member.id))
		var observed: Dictionary = SurvivorRoster.member(actual.crew,int(member.id))
		if target.health != observed.health or not TransactionReceipt.same(target.growth,observed.growth) or not TransactionReceipt.same(target.service,observed.service):
			return "XP_RESULT_EFFECT"
	return ""
