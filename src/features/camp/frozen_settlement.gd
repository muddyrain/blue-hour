class_name FrozenSettlement
extends RefCounted
## Opt-in value aggregation. No production caller, default hunger formula or new save schema.

const SCOPE: String = "ISOLATED_CANDIDATE"
const FOUNDATION: String = "PRODUCTION_FOUNDATION"
const BATTLE: String = "BATTLE_SURVIVAL_SLICE"
const SURVIVAL: String = "SURVIVAL_MIGRATION_ISOLATED"
const HUNGER_PILOT: String = "SURVIVAL_HUNGER_ISOLATED"
const DIRECT_RULESET: String = "BH_HUNGER_DIRECT_V1"
const INPUT_KEYS: Array[String] = ["before", "token", "participants", "rules", "report", "carried", "prior_deaths", "completion", "searching_member_ids"]
const STATE_KEYS: Array[String] = ["schema_version", "profile_id", "day", "cash", "food", "crew", "settled_sorties", "last_settlement_id", "last_day", "weapons", "loadout", "camp_spending"]
const REPORT_KEYS: Array[String] = ["contract_version", "sortie_id", "participants", "member_results", "mission_outcome", "evacuated", "member_records", "health", "kills", "loot", "food", "weapons", "searched", "food_searched", "sites_searched", "elapsed", "growth_inputs"]


static func compute(input: Dictionary) -> Dictionary:
	var issue: String = input_problem(input)
	if not issue.is_empty():
		return _reject(issue)
	var before: Dictionary = FieldJoinRules.action_base(input.before,input.report.field_joins) if FieldJoinState.is_family(input.before) else input.before
	var report: Dictionary = input.report
	var growth: bool = GrowthState.is_family(before)
	var limits: Dictionary = GrowthRules.limits(before.crew) if growth else {}
	var identity: String = input.token.transaction_id
	var after: Dictionary = before.duplicate(true)
	after.day = int(before.day) + 1
	after.settled_sorties = int(before.settled_sorties) + 1
	after.last_settlement_id = identity
	after.camp_spending = 0
	var deaths: Array = input.prior_deaths.duplicate(true)
	for member: Dictionary in after.crew:
		var result: Dictionary = SurvivorRoster.member(report.member_results, int(member.id))
		if result.is_empty():
			continue
		var old: Dictionary = SurvivorRoster.member(before.crew, int(member.id))
		var proposal: Dictionary = DeathRules.propose(old, float(result.health), "BATTLE", identity,{},growth)
		if not proposal.get("error", "").is_empty():
			return _reject("BATTLE_DEATH: " + proposal.error)
		if not proposal.death.is_empty():
			deaths.append(proposal.death)
		member.health = result.health
	issue = SurvivorRoster.record(after, before, report, identity)
	if issue.is_empty():
		issue = SurvivorGrowth.bank(after, before, report, identity)
	if not issue.is_empty():
		return _reject("HISTORY: " + issue)
	for row: Dictionary in report.growth_inputs.members:
		var participant: Dictionary = SurvivorRoster.member(report.participants, int(row.member_id))
		var equipped: Dictionary = WeaponInventory.for_member(before, int(row.member_id))
		for event: Dictionary in row.recent:
			if event.instance_id != participant.weapon_instance_id or event.weapon_id != equipped.weapon_id:
				return _reject("GROWTH_EQUIPMENT_OWNER")
	var food: Dictionary = CampEconomy.post_battle_food(int(before.day), FieldJoinRules.meal_members(after.crew,input.before), int(before.food), int(report.food), int(input.rules.ration_per_member),growth)
	if food.is_empty():
		return _reject("FOOD_LEDGER")
	var hunger: Dictionary = HungerOutcome.settle(food, FieldJoinRules.meal_members(report.member_results,input.before), input.rules.hunger, input.token,limits)
	if not hunger.error.is_empty():
		return _reject(hunger.error + (":" + String(hunger.get("reason", "")) if hunger.has("reason") else ""))
	for effect: Dictionary in hunger.ledger.effects:
		var member: Dictionary = SurvivorRoster.member(after.crew, int(effect.id))
		var cause: String = "STARVATION" if hunger.ledger.ruleset_id == HungerOutcome.DIRECT else "HUNGER"
		var proposal: Dictionary = DeathRules.propose(member, float(effect.health_after), cause, identity,{},growth)
		if not proposal.get("error", "").is_empty():
			return _reject("HUNGER_DEATH: " + proposal.error)
		if not proposal.death.is_empty():
			deaths.append(proposal.death)
		member.health = effect.health_after
	for member: Dictionary in after.crew:
		member.condition = "active" if float(member.health) > 0.0 else "down"
	if deaths.size() > input.prior_deaths.size() and input.rules.dead_equipment.is_empty():
		return _reject("POLICY_REQUIRED:DEAD_EQUIPMENT")
	issue = WeaponInventory.bank(after, report.weapons, identity)
	if not issue.is_empty():
		return _reject("INVENTORY: " + issue)
	after.food = food.food_after
	after.cash = int(before.cash) + int(report.loot)
	after.last_day = food.duplicate(true)
	after.last_day.merge({"settlement_id":identity,"day":before.day,"cash_before":before.cash,
		"cash_gained":report.loot,"cash_after":after.cash,"evacuated":report.evacuated})
	var xp: Dictionary = {}
	if growth:
		var awarded: Dictionary = GrowthRules.bank(after,before,report,input.token)
		if not awarded.error.is_empty():
			return _reject(awarded.error)
		xp = awarded.ledger
	var traits: Dictionary = {}
	if TraitState.is_family(before):
		var awarded: Dictionary = TraitRules.bank(after,before,report,input.token)
		if not awarded.error.is_empty():
			return _reject(awarded.error)
		traits = awarded.ledger
	if FieldJoinState.is_family(input.before) and not report.field_joins.is_empty():
		after.recruits = input.before.recruits.duplicate(true)
		after.recruits.append(FieldJoinRules.record(input.before,report.field_joins[0],"RETURNED" if report.evacuated and SurvivorRoster.member(after.crew,int(report.field_joins[0].member_id)).health > 0 else "LOST"))
	if not FieldJoinState.is_family(before) and RescueState.is_family(before) and report.evacuated and report.rescue.status == "RESCUED" and before.recruits.is_empty():
		if growth:
			GrowthState.grant(after,identity)
		else:
			RescueState.grant(after,identity)
	if SurvivalState.is_extended(before):
		var meta: Dictionary = before.journey.duplicate(true)
		meta.deaths = deaths.duplicate(true)
		after = SurvivalState.rebuild(before,after,meta)
	issue = state_problem(after)
	if not issue.is_empty():
		return _reject("AFTER: " + issue)
	deaths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.member_id) < int(b.member_id))
	var journey: String = DeathRules.journey(after.crew, deaths, before.profile_id,growth)
	if journey == "REVIEW_REQUIRED":
		return _reject("DEATH_HISTORY")
	var result: Dictionary = {"settlement_version":1,"scope":input.rules.scope,"binding":input.token.duplicate(true),
		"input_hash":SurvivalContracts.fingerprint(input),"rules":input.rules.duplicate(true),
		"camp":after,"battle":report.duplicate(true),"food":food,"hunger":hunger.ledger,
		"allocation":hunger.allocation,"deaths":deaths,"mission_outcome":report.mission_outcome,
		"journey_outcome":journey,"production_enabled":false}
	if growth:
		result.xp = xp
	if TraitState.is_family(before):
		result.traits = traits
	var envelope: Dictionary = SurvivalContracts.transaction(input.before, result, identity)
	if envelope.is_empty():
		return _reject("ENVELOPE")
	return {"error":"", "reason":"", "packet":{"input":input.duplicate(true),"envelope":envelope}}


static func input_problem(input: Dictionary) -> String:
	if not SurvivalContracts.json_value(input) or input.size() != INPUT_KEYS.size() or not input.has_all(INPUT_KEYS):
		return "INPUT_FIELDS"
	for key: String in ["before", "token", "rules", "report", "carried"]:
		if not input[key] is Dictionary:
			return "INPUT_TYPES"
	if not input.participants is Array or not input.prior_deaths is Array or not input.searching_member_ids is Array:
		return "INPUT_TYPES"
	if input.completion in ["TECHNICAL_INTERRUPTION", "PLAYER_ABANDONED"]:
		return "POLICY_REQUIRED:" + input.completion
	if input.completion != "COMPLETED":
		return "COMPLETION_KIND"
	var issue: String = state_problem(input.before)
	if not issue.is_empty():
		return "BEFORE: " + issue
	var token: Dictionary = input.token
	if token.size() != 5 or not token.get("root_id") is String or token.root_id.length() != 32 or not token.root_id.is_valid_hex_number(false):
		return "TOKEN"
	if token.get("run_id") != input.before.profile_id or token.get("transaction_id") != "%s:%d" % [input.before.profile_id,int(input.before.settled_sorties)+1] or token.get("base_hash") != SurvivalContracts.fingerprint(input.before) or token.get("rules_hash") != SurvivalContracts.fingerprint(input.rules):
		return "TOKEN_BINDING"
	issue = _rules_problem(input.rules)
	if not issue.is_empty():
		return issue
	if (input.rules.get("data_version")==2 or (input.rules.get("data_version")==3 or input.rules.get("data_version")==4) or input.rules.get("data_version")==4) and not DailyActions.matches(input.before,input.rules.mission.generated):
		return "DAILY_CAMP_BINDING"
	if RescuePoolState.is_family(input.before) and not TransactionReceipt.same(input.rules.get("candidate",{}),RescuePoolState.offer(input.before,token.transaction_id,String(input.rules.mission.mission_id))):
		return "POOL_CANDIDATE_BINDING"
	if SurvivalState.is_extended(input.before):
		var required_scope: String = RescuePoolState.SCOPE if RescuePoolState.is_family(input.before) else TraitState.SCOPE if TraitState.is_family(input.before) else FieldJoinState.SCOPE if FieldJoinState.is_family(input.before) else GrowthState.SCOPE if GrowthState.is_family(input.before) else (RescueState.SCOPE if RescueState.is_state(input.before) else (SURVIVAL if SurvivalState.is_state(input.before) else BATTLE))
		var allowed: bool = input.rules.scope == required_scope or (SurvivalState.is_state(input.before) and input.rules.scope == HUNGER_PILOT)
		if not allowed or token.root_id != input.before.journey.root_id or not TransactionReceipt.same({"v":input.prior_deaths},{"v":input.before.journey.deaths}):
			return "BATTLE_RULES_OR_HISTORY"
	elif input.rules.scope in [BATTLE, SURVIVAL, HUNGER_PILOT]:
		return "BATTLE_FORMAT_REQUIRED"
	if DeathRules.journey(input.before.crew, input.prior_deaths, input.before.profile_id,GrowthState.is_family(input.before)) == "REVIEW_REQUIRED":
		return "POLICY_REQUIRED:LEGACY_ZERO_HP_OR_DEATH_HISTORY"
	for death: Dictionary in input.prior_deaths:
		if int(death.transaction_id.get_slice(":",1)) > int(input.before.settled_sorties):
			return "FUTURE_DEATH_HISTORY"
	var expected: Array[Dictionary] = SurvivalContracts.participants(input.before.crew, WeaponInventory.snapshot(input.before),true,GrowthState.is_family(input.before))
	if expected.is_empty() or not TransactionReceipt.same({"v":expected}, {"v":input.participants}):
		return "DEPARTURE_PARTICIPANTS"
	var action: Dictionary = input.before
	if FieldJoinState.is_family(input.before):
		var field_issue: String = FieldJoinRules.problem(input.report.get("field_joins"),input.before,token.transaction_id)
		if not field_issue.is_empty():
			return field_issue
		action = FieldJoinRules.action_base(input.before,input.report.field_joins)
		expected = SurvivalContracts.participants(action.crew,WeaponInventory.snapshot(action),true,true)
	issue = SurvivalContracts.report_problem(action.crew, input.report,GrowthState.is_family(input.before))
	if not issue.is_empty():
		return "REPORT: " + issue
	if input.rules.scope == FOUNDATION:
		if not input.prior_deaths.is_empty():
			return "POLICY_REQUIRED:PRODUCTION_DEATH_HISTORY"
		for row: Dictionary in input.report.member_results:
			if row.health <= 0:
				return "POLICY_REQUIRED:PERMADEATH_NOT_ENABLED"
	if input.report.sortie_id != token.transaction_id:
		return "REPORT_TRANSACTION"
	for participant: Dictionary in input.report.participants:
		if not TransactionReceipt.same(participant, SurvivorRoster.member(expected, int(participant.id))):
			return "REPORT_EQUIPMENT"
	if input.report.size() != REPORT_KEYS.size() + (1 if RescueState.is_family(input.before) else 0) + (1 if GrowthState.is_family(input.before) else 0) + int(FieldJoinState.is_family(input.before)) + int(TraitState.is_family(input.before)) + int((input.rules.get("data_version")==3 or input.rules.get("data_version")==4)) or not input.report.has_all(REPORT_KEYS):
		return "REPORT_FIELDS"
	if RescueState.is_family(input.before):
		if not input.report.get("rescue") is Dictionary or not RescueTarget.fact_problem(input.report.rescue).is_empty() or (input.report.rescue.status == "RESCUED" and (input.rules.mission.mission_id != "rescue" or (RescuePoolState.available(input.before).is_empty() if RescuePoolState.is_family(input.before) else not input.before.recruits.is_empty()))):
			return "RESCUE_SOURCE"
		var available: bool = input.rules.mission.mission_id == "rescue" and (not RescuePoolState.available(input.before).is_empty() if RescuePoolState.is_family(input.before) else input.before.recruits.is_empty())
		if (available and input.report.rescue.status == "UNAVAILABLE") or (not available and input.report.rescue.status != "UNAVAILABLE") or (not input.report.evacuated and input.report.rescue.status == "RESCUED"):
			return "RESCUE_OUTCOME"
	if GrowthState.is_family(input.before):
		if not input.report.get("growth_inputs") is Dictionary:
			return "XP_ACTION_FIELDS"
		issue = GrowthRules.inputs_problem(input.report.get("xp_inputs"),input.token,input.report.growth_inputs,input.report.participants,action)
		if not issue.is_empty():
			return issue
	if FieldJoinState.is_family(input.before):
		issue = FieldJoinRules.report_problem(input.before,input.report,input.report.field_joins)
		if not issue.is_empty():
			return issue
	if TraitState.is_family(input.before):
		issue = TraitRules.inputs_problem(input.report.get("trait_inputs"),input.token,input.report,action)
		if not issue.is_empty():
			return issue
	issue = _facts_problem(input)
	if not issue.is_empty():
		return issue
	var searching: Array[int] = []
	for id: Variant in input.searching_member_ids:
		if not SurvivalContracts.integer(id,1,SurvivalContracts.MAX_ID) or int(id) in searching or SurvivorRoster.member(expected,int(id)).is_empty():
			return "SEARCHING_MEMBER"
		searching.append(int(id))
	if input.report.evacuated and not searching.is_empty():
		return "SEARCHER_NOT_EXTRACTED"
	if input.report.mission_outcome == "ABORTED":
		return "POLICY_REQUIRED:PLAYER_ABANDONED"
	if not input.report.evacuated:
		for member: Dictionary in input.report.member_results:
			if member.health > 0.0:
				return "POLICY_REQUIRED:FAILED_WITH_SURVIVORS"
	return ""


static func state_problem(state: Dictionary) -> String:
	if not SurvivalContracts.integer(state.get("schema_version"),1,EnemyState.SCHEMA):
		return "STATE_FORMAT"
	if SurvivalState.is_extended(state):
		return SurvivalState.extended_problem(state)
	return common_problem(state)


static func common_problem(state: Dictionary, generated_maps: bool = false) -> String:
	var rescued: bool = RescueState.is_family(state)
	if not SurvivalContracts.json_value(state) or state.size() != STATE_KEYS.size() + (3 if rescued else 0) or not state.has_all(STATE_KEYS) or (state.schema_version != 5 and not rescued):
		return "STATE_FIELDS"
	if not state.profile_id is String or state.profile_id.length() != 32 or not state.profile_id.is_valid_hex_number(false):
		return "STATE_PROFILE"
	if not SurvivalContracts.integer(state.day,2,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(state.settled_sorties,0,RunSave.MAX_COUNTER-2) or state.day != state.settled_sorties+2 or not SurvivalContracts.integer(state.cash,0,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(state.food,0,CampRules.FOOD_LIMIT):
		return "STATE_COUNTERS"
	var identity: String = "" if state.settled_sorties == 0 else "%s:%d" % [state.profile_id,int(state.settled_sorties)]
	if not state.last_settlement_id is String or state.last_settlement_id != identity or not state.crew is Array:
		return "STATE_IDENTITY"
	var issue: String = SurvivalContracts.identity_problem(state.crew,GrowthState.is_family(state))
	if not issue.is_empty():
		return issue
	for member: Dictionary in state.crew:
		issue = SurvivorRoster.validate(member, state, true)
		if issue.is_empty():
			issue = SurvivorGrowth.validate_member(member, state,generated_maps)
		if not issue.is_empty():
			return issue
	issue = WeaponInventory.validate(state, true)
	if issue.is_empty():
		issue = SurvivorGrowth.validate_crew(state.crew)
	return RunSave._validate_day(state, SurvivalContracts.MAX_ID) if issue.is_empty() else issue


static func validate(packet: Dictionary) -> String:
	if packet.size() != 2 or not packet.get("input") is Dictionary or not packet.get("envelope") is Dictionary:
		return "PACKET_FIELDS"
	var result: Dictionary = compute(packet.input)
	if not result.error.is_empty():
		return result.reason
	return "" if TransactionReceipt.same(result.packet.envelope, packet.envelope) else "FROZEN_RESULT_MISMATCH"


static func prepare_isolated(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction, packet, SCOPE)


static func prepare_foundation(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction, packet, FOUNDATION)


static func prepare_battle(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,BATTLE)


static func prepare_survival(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,SURVIVAL)


static func pool_rules(base: Dictionary, supply: MissionSupply) -> Dictionary:
	var value: Dictionary = trait_rules(supply)
	value.scope = RescuePoolState.SCOPE
	value.candidate = RescuePoolState.offer(base,"%s:%d" % [base.profile_id,int(base.settled_sorties)+1],String(supply.id))
	return value


static func prepare_pool(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,RescuePoolState.SCOPE)


static func trait_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = field_join_rules(supply)
	rules.scope = TraitState.SCOPE
	rules.traits = TraitRules.policy()
	return rules


static func prepare_traits(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,TraitState.SCOPE)


static func field_join_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = growth_rules(supply)
	rules.scope = FieldJoinState.SCOPE
	rules.field_join = FieldJoinRules.policy()
	return rules


static func prepare_field_join(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,FieldJoinState.SCOPE)


static func prepare_growth(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,GrowthState.SCOPE)


static func growth_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = rescue_rules(supply)
	rules.scope = GrowthState.SCOPE
	rules.growth = GrowthRules.policy()
	return rules


static func prepare_rescue(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,RescueState.SCOPE)


static func rescue_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = survival_hunger_rules(supply)
	rules.scope = RescueState.SCOPE
	return rules


static func prepare_survival_hunger(transaction: RunTransaction, packet: Dictionary) -> Dictionary:
	return _prepare(transaction,packet,HUNGER_PILOT)


static func survival_hunger_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = direct_hunger_rules(supply)
	rules.scope = HUNGER_PILOT
	return rules


static func battle_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = foundation_rules(supply)
	rules.ruleset_id = "BH_BATTLE_SLICE_V1"
	rules.scope = BATTLE
	rules.dead_equipment = {"policy_id":"IDLE_INVENTORY_V1","scope":SCOPE,"source":"PROJECT_TEMP"}
	return rules


static func survival_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = battle_rules(supply)
	rules.ruleset_id = "BH_SURVIVAL_ISOLATED_V1"
	rules.scope = SURVIVAL
	return rules


static func foundation_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = {"ruleset_id":"BH_FOUNDATION_V1","data_version":1,"scope":FOUNDATION,"ration_per_member":1,
		"mission":{"map_id":String(supply.layout.id),"mission_id":String(supply.id),"cash_reward":supply.cash_reward,
			"food_reward":supply.food_reward,"has_weapon_sample":supply.has_weapon_sample},"hunger":{},"dead_equipment":{}}
	if not supply.generated.is_empty():
		rules.data_version = 4 if supply.generated.get("version")==3 else 3 if supply.generated.get("version")==2 else 2
		rules.mission.generated = supply.generated.duplicate(true)
	return rules


static func direct_hunger_rules(supply: MissionSupply) -> Dictionary:
	var rules: Dictionary = battle_rules(supply)
	rules.ruleset_id = DIRECT_RULESET
	rules.scope = SCOPE
	rules.hunger = {"ruleset_id":HungerOutcome.DIRECT, "scope":SCOPE, "source":"PROJECT_TEMP"}
	return rules


static func _prepare(transaction: RunTransaction, packet: Dictionary, scope: String) -> Dictionary:
	if not packet.get("input") is Dictionary or not packet.get("envelope") is Dictionary or not packet.input.get("rules") is Dictionary or packet.input.rules.get("scope") != scope or not packet.input.get("token") is Dictionary or not packet.input.get("report") is Dictionary:
		return _blocked("ISOLATED_PACKET_REQUIRED")
	var current: Dictionary = transaction.recover()
	if current.error != OK:
		return current
	var receipt: Dictionary = current.receipt
	var token: Dictionary = packet.input.get("token", {})
	if not TransactionReceipt.same(RunTransaction.token_for(receipt), token):
		return _blocked("STALE_OR_FOREIGN_PACKET")
	# A published result is authoritative. Never invoke economic computation on this path.
	if receipt.phase in ["RESULT_READY", "COMMITTED"]:
		return transaction.prepare(token, packet.envelope, "camp")
	if FieldJoinState.is_family(receipt.base) and not TransactionReceipt.same({"v":packet.input.report.get("field_joins")},{"v":receipt.joins}):
		return _blocked("FIELD_JOIN_NOT_DURABLE")
	var issue: String = validate(packet)
	if not issue.is_empty():
		return _blocked(issue)
	var result: Dictionary = packet.envelope.result
	for confirmed: Dictionary in receipt.deaths:
		var found: Dictionary = {}
		for death: Dictionary in result.deaths:
			if int(death.member_id) == int(confirmed.death.member_id):
				found = death
		if not TransactionReceipt.same(confirmed.death, found):
			return _blocked("CONFIRMED_DEATH_CONFLICT")
	for death: Dictionary in result.deaths:
		if death.cause == "BATTLE" and death.transaction_id == token.transaction_id and _checkpoint_death(receipt, int(death.member_id)).is_empty():
			return _blocked("BATTLE_CHECKPOINT_REQUIRED")
	var health: Array[Dictionary] = []
	for row: Dictionary in result.battle.member_results:
		var confirmed: Dictionary = _checkpoint_death(receipt, int(row.id))
		health.append({"id":row.id,"health":0.0 if not confirmed.is_empty() else row.health})
	current = transaction.checkpoint(token, health)
	if current.error != OK:
		return current
	for death: Dictionary in result.deaths:
		if death.cause not in ["HUNGER", "STARVATION"] or death.transaction_id != token.transaction_id:
			continue
		var source: Dictionary = SurvivorRoster.member(result.battle.member_results, int(death.member_id))
		current = transaction.confirm_death(token, death, float(source.health))
		if current.error != OK:
			return current
	return transaction.prepare(token, packet.envelope, "camp")


static func interruption_candidates(receipt: Dictionary) -> Dictionary:
	if not TransactionReceipt.problem(receipt).is_empty() or receipt.phase not in ["STARTED", "IN_PROGRESS", "DEATH_CONFIRMED"]:
		return _reject("OPEN_RECEIPT_REQUIRED")
	return {"error":"POLICY_REQUIRED", "reason":"TECHNICAL_INTERRUPTION", "envelope":{},
		"confirmed_health":receipt.health.duplicate(true),"confirmed_deaths":receipt.deaths.duplicate(true),
		"candidates":[{"id":"HOLD_CONFIRMED_FACTS", "advance_day":false,"ration":"NOT_APPLIED","loot":"UNKNOWN_NOT_GRANTED","count_sortie":false,"mission":"UNRESOLVED"},
			{"id":"CLOSE_DAY_CANDIDATE", "advance_day":true,"ration":"POST_BATTLE_POLICY_REQUIRED","loot":"DISCARD_CANDIDATE","count_sortie":true,"mission":"FAILED_CANDIDATE"}],
		"scope":SCOPE,"source":"PROJECT_TEMP","approved":false}


static func _rules_problem(rules: Dictionary) -> String:
	if not rules.get("scope") is String:
		return "RULES_SCOPE_TYPE"
	if rules.get("scope")==RescuePoolState.SCOPE:
		if rules.size()!=11 or not rules.get("candidate") is Dictionary:
			return "POOL_RULES_FIELDS"
		var projected: Dictionary = rules.duplicate(true)
		projected.erase("candidate")
		projected.scope = TraitState.SCOPE
		return _rules_problem(projected)
	if (rules.get("data_version")==2 or rules.get("data_version")==3 or rules.get("data_version")==4):
		if rules.scope!=TraitState.SCOPE or not rules.get("mission") is Dictionary:
			return "DAILY_RULES_SCOPE"
		if not rules.mission.get("generated") is Dictionary or rules.mission.generated.get("version") != (3 if rules.data_version==4 else 2 if rules.data_version==3 else 1): return "DAILY_POLICY_VERSION_BINDING"
		var daily_issue: String = DailyActions.mission_problem(rules.mission)
		if not daily_issue.is_empty(): return daily_issue
		# Validate unchanged policies with the legacy shape; actual generated mission
		# identity/rewards/geometry are separately authenticated above and below.
		var legacy: Dictionary = rules.duplicate(true)
		legacy.data_version = 1
		legacy.mission.erase("generated")
		legacy.mission.map_id = "market_loop"
		return _rules_problem(legacy)
	if rules.size() != (10 if rules.get("scope") == TraitState.SCOPE else (9 if rules.get("scope") == FieldJoinState.SCOPE else (8 if rules.get("scope") == GrowthState.SCOPE else 7))) or not rules.get("ruleset_id") is String or rules.ruleset_id.is_empty() or not SurvivalContracts.integer(rules.get("data_version"),1,SurvivalContracts.MAX_ID) or rules.get("scope") not in [SCOPE,FOUNDATION,BATTLE,SURVIVAL,HUNGER_PILOT,RescueState.SCOPE,GrowthState.SCOPE,FieldJoinState.SCOPE,TraitState.SCOPE] or not SurvivalContracts.integer(rules.get("ration_per_member"),1,100):
		return "RULES_VERSION_OR_SCOPE"
	if not rules.get("mission") is Dictionary or not rules.get("hunger") is Dictionary or not rules.get("dead_equipment") is Dictionary:
		return "RULES_TYPES"
	if rules.scope in [HUNGER_PILOT,RescueState.SCOPE,GrowthState.SCOPE,FieldJoinState.SCOPE,TraitState.SCOPE] and rules.dead_equipment.is_empty():
		return "HUNGER_EQUIPMENT_POLICY_REQUIRED"
	if rules.scope in [HUNGER_PILOT,RescueState.SCOPE,GrowthState.SCOPE,FieldJoinState.SCOPE,TraitState.SCOPE] or rules.ruleset_id == DIRECT_RULESET or rules.hunger.get("ruleset_id") == HungerOutcome.DIRECT:
		if rules.ruleset_id != DIRECT_RULESET or rules.data_version != 1 or rules.scope not in [SCOPE,HUNGER_PILOT,RescueState.SCOPE,GrowthState.SCOPE,FieldJoinState.SCOPE,TraitState.SCOPE] or rules.ration_per_member != 1 or not TransactionReceipt.same(rules.hunger, {"ruleset_id":HungerOutcome.DIRECT, "scope":SCOPE, "source":"PROJECT_TEMP"}):
			return "DIRECT_POLICY_VERSION_OR_SCOPE"
	if rules.scope == FOUNDATION and (rules.ruleset_id != "BH_FOUNDATION_V1" or rules.data_version != 1 or rules.ration_per_member != 1 or not rules.hunger.is_empty() or not rules.dead_equipment.is_empty()):
		return "FOUNDATION_POLICY_NOT_APPROVED"
	if rules.scope == BATTLE and (rules.ruleset_id != "BH_BATTLE_SLICE_V1" or rules.data_version != 1 or rules.ration_per_member != 1 or not rules.hunger.is_empty() or rules.dead_equipment.is_empty()):
		return "BATTLE_POLICY_NOT_APPROVED"
	if rules.scope == SURVIVAL and (rules.ruleset_id != "BH_SURVIVAL_ISOLATED_V1" or rules.data_version != 1 or rules.ration_per_member != 1 or not rules.hunger.is_empty() or rules.dead_equipment.is_empty()):
		return "SURVIVAL_POLICY_NOT_APPROVED"
	if rules.scope in [GrowthState.SCOPE,FieldJoinState.SCOPE,TraitState.SCOPE] and (not rules.get("growth") is Dictionary or not TransactionReceipt.same(rules.growth,GrowthRules.policy())):
		return "GROWTH_POLICY_NOT_APPROVED"
	if rules.scope in [FieldJoinState.SCOPE,TraitState.SCOPE] and (not rules.get("field_join") is Dictionary or not TransactionReceipt.same(rules.field_join,FieldJoinRules.policy())):
		return "FIELD_JOIN_POLICY"
	if rules.scope == TraitState.SCOPE and (not rules.get("traits") is Dictionary or not TransactionReceipt.same(rules.traits,TraitRules.policy())):
		return "TRAIT_RULES"
	var mission: Dictionary = rules.mission
	if mission.size() != 5 or mission.get("map_id") not in SurvivorGrowth.MAPS or mission.get("mission_id") not in (["scavenge", "supermarket", "rescue"] if rules.scope in [RescueState.SCOPE,GrowthState.SCOPE,FieldJoinState.SCOPE,TraitState.SCOPE] else ["scavenge", "supermarket"]) or not SurvivalContracts.integer(mission.get("cash_reward"),0,1000) or not SurvivalContracts.integer(mission.get("food_reward"),0,1000) or not mission.get("has_weapon_sample") is bool:
		return "MISSION_SOURCE"
	var gear: Dictionary = rules.dead_equipment
	if not gear.is_empty() and (gear.size() != 3 or gear.get("policy_id") != "IDLE_INVENTORY_V1" or gear.get("scope") != SCOPE or gear.get("source") != "PROJECT_TEMP"):
		return "DEAD_EQUIPMENT_POLICY"
	return ""


static func _facts_problem(input: Dictionary) -> String:
	var report: Dictionary = input.report
	var source: Dictionary = input.rules.mission
	var multi: bool = (input.rules.get("data_version")==3 or input.rules.get("data_version")==4)
	if multi:
		if not report.searched is bool or not report.food_searched is bool or not SurvivalContracts.integer(report.sites_searched,0,6): return "SITE_REPORT_TYPES"
		var issue: String = WorldSites.problem(source.generated.sites,report.get("site_facts"))
		if not issue.is_empty(): return issue
		if report.searched != (WorldSites.completed(source.generated.sites,report.site_facts,"cash")>0) or report.food_searched != (WorldSites.completed(source.generated.sites,report.site_facts,"food")>0) or report.sites_searched != WorldSites.completed(source.generated.sites,report.site_facts): return "SITE_REPORT_ALIAS"
	if not multi and (not report.searched is bool or not report.food_searched is bool or not SurvivalContracts.integer(report.sites_searched,0,2) or report.sites_searched != int(report.searched)+int(report.food_searched) or (report.searched and source.cash_reward == 0) or (report.food_searched and source.food_reward == 0)):
		return "SEARCH_FACTS"
	if not SurvivalContracts.number(report.elapsed) or report.elapsed < 0 or report.elapsed*1000.0 > RunSave.MAX_COUNTER:
		return "REPORT_DURATION"
	var carry: Dictionary = input.carried
	if carry.size() != 3 or not SurvivalContracts.integer(carry.get("loot"),0,RunSave.MAX_COUNTER) or not SurvivalContracts.integer(carry.get("food"),0,RunSave.MAX_COUNTER) or not carry.get("weapons") is Array:
		return "CARRIED_FIELDS"
	var expected: Dictionary = {"loot":source.cash_reward if report.searched else 0,
		"food":source.food_reward if report.food_searched else 0,"weapons":[]}
	if report.searched and source.has_weapon_sample:
		expected.weapons.append(WeaponInventory.reward(input.token.transaction_id,WeaponState.is_family(input.before)))
	if multi: expected = WorldSites.carry(source.generated.sites,report.site_facts,input.token.transaction_id,WeaponState.is_family(input.before))
	if not TransactionReceipt.same(carry, expected):
		return "CARRIED_SOURCE_MISMATCH"
	var rewards: Dictionary = carry if report.evacuated else {"loot":0,"food":0,"weapons":[]}
	if not TransactionReceipt.same({"loot":report.loot,"food":report.food,"weapons":report.weapons}, rewards):
		return "REWARD_FACTS"
	if not report.member_records is Array or report.member_records.size() != report.member_results.size() or not report.health is Array or report.health.size() != report.member_results.size():
		return "LEGACY_ALIASES"
	var ids: Array[int] = []
	for row: Variant in report.member_records:
		if not row is Dictionary or row.size() != 3 or not SurvivalContracts.integer(row.get("id"),1,SurvivalContracts.MAX_ID) or int(row.id) in ids:
			return "SERVICE_ALIAS"
		var actual: Dictionary = SurvivorRoster.member(report.member_results, int(row.id))
		if actual.is_empty() or row.get("kills") != actual.kills or row.get("damage_received") != actual.damage_received:
			return "SERVICE_ALIAS"
		ids.append(int(row.id))
	ids.sort()
	for index: int in range(ids.size()):
		if not SurvivalContracts.number(report.health[index]) or float(report.health[index]) != float(SurvivorRoster.member(report.member_results,ids[index]).health):
			return "HEALTH_ALIAS"
	if not report.growth_inputs is Dictionary or report.growth_inputs.get("map_id") != source.map_id:
		return "GROWTH_SOURCE"
	return ""


static func _checkpoint_death(receipt: Dictionary, id: int) -> Dictionary:
	for row: Dictionary in receipt.deaths:
		if int(row.death.member_id) == id:
			return row.death
	return {}


static func _reject(reason: String) -> Dictionary:
	return {"error":"POLICY_REQUIRED" if reason.begins_with("POLICY_REQUIRED") else "INVALID_INPUT", "reason":reason,"packet":{}}


static func _blocked(reason: String) -> Dictionary:
	return {"error":ERR_INVALID_DATA,"reason":reason,"state":"BLOCKED","receipt":{}}
