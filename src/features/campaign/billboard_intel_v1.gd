class_name BillboardIntelV1
extends RefCounted
## One next-day opportunity, derived by the existing confirmed return.

const KEYS: Array[String] = ["destination", "source_day", "day", "slot", "action_id", "billboard_id", "transaction_id", "strategy"]


static func enabled(campaign: Variant) -> bool:
	return CampaignRules.action_choices_enabled(campaign) and SurvivalContracts.integer(
		campaign.get("billboard_policy"), BillboardActionV1.VERSION, BillboardActionV1.VERSION)


static func opportunity(camp: Dictionary) -> Dictionary:
	var value: Variant = camp.get("journey", {}).get("campaign", {}).get("billboard_intel")
	return value if value is Dictionary else {}


static func camp_problem(camp: Dictionary) -> String:
	var campaign: Dictionary = camp.journey.campaign
	if not campaign.has("billboard_intel"):
		return ""
	var value: Variant = campaign.billboard_intel
	if not enabled(campaign) or not value is Dictionary or value.size() != KEYS.size() or not value.has_all(KEYS):
		return "BILLBOARD_INTEL_FIELDS"
	if campaign.outcome != "ACTIVE" or CampaignRules.next_clue(campaign).is_empty() or not camp.last_day.get("evacuated", false) \
			or not value.destination is String or value.destination != BillboardActionV1.DESTINATION \
			or not SurvivalContracts.integer(value.day, int(camp.day), int(camp.day)) \
			or not SurvivalContracts.integer(value.source_day, 3, RunSave.MAX_COUNTER - 1) or value.source_day + 1 != value.day \
			or not SurvivalContracts.integer(value.slot, 0, BillboardActionV1.SLOT) or value.slot == InvestigationActions.INVESTIGATION_SLOT \
			or camp.settled_sorties < 2 or not value.transaction_id is String or value.transaction_id != camp.last_settlement_id \
			or value.transaction_id != "%s:%d" % [camp.profile_id, int(camp.settled_sorties)]:
		return "BILLBOARD_INTEL_CONTEXT"
	var action_id: String = BillboardActionV1.action_id(camp.journey.seed, int(value.source_day), int(value.slot))
	if not value.action_id is String or not value.billboard_id is String \
			or value.action_id != action_id or value.billboard_id != BillboardActionV1.board_id(action_id):
		return "BILLBOARD_INTEL_SOURCE"
	var target: Dictionary = BillboardActionV1.target(camp.journey.seed, int(camp.day))
	return "" if value.strategy is Dictionary and not target.is_empty() and TransactionReceipt.same(value.strategy, target) else "BILLBOARD_INTEL_TARGET"


static func earned(after: Dictionary, campaign: Dictionary, report: Dictionary, generated: Dictionary) -> Dictionary:
	if not enabled(campaign) or campaign.outcome != "ACTIVE" or CampaignRules.next_clue(campaign).is_empty() \
			or after.journey.state != "ACTIVE" or not report.get("evacuated", false) \
			or not BillboardActionV1.enabled(generated) or not report.get("billboard", {}).get("completed", false):
		return {}
	var board: Dictionary = generated.billboard
	return {"destination":board.destination, "source_day":int(generated.day), "day":int(generated.day) + 1,
		"slot":int(generated.slot), "action_id":generated.id, "billboard_id":board.id,
		"transaction_id":report.sortie_id, "strategy":board.target.duplicate(true)}


static func result_problem(receipt: Dictionary, after: Dictionary) -> String:
	var prior: Dictionary = receipt.base.get("journey", {}).get("campaign", {})
	var campaign: Dictionary = after.get("journey", {}).get("campaign", {})
	var battle: Variant = receipt.envelope.result.get("battle")
	if not prior.has("billboard_policy") and not campaign.has("billboard_policy"):
		return "BILLBOARD_RESULT_FIELDS" if battle is Dictionary and battle.has("billboard") else ""
	if prior.get("billboard_policy") != campaign.get("billboard_policy"):
		return "BILLBOARD_RESULT_POLICY"
	var generated: Dictionary = receipt.rules.get("mission", {}).get("generated", {})
	if not battle is Dictionary or not battle.get("sortie_id") is String or battle.sortie_id != receipt.transaction_id \
			or not battle.get("evacuated") is bool \
			or not SurvivalContracts.number(battle.get("elapsed")) or battle.elapsed < 0.0:
		return "BILLBOARD_RESULT_REPORT"
	if battle.has("billboard") != BillboardActionV1.enabled(generated):
		return "BILLBOARD_RESULT_FIELDS"
	if battle.has("billboard"):
		if battle.evacuated != after.last_day.get("evacuated") or not SurvivalContracts.report_problem(
				receipt.base.crew, battle, GrowthState.is_family(receipt.base), BuildState.enabled(receipt.base)).is_empty():
			return "BILLBOARD_RESULT_REPORT"
		var issue: String = BillboardWorkV1.problem(generated, battle.billboard, float(battle.elapsed), receipt.base.crew)
		if not issue.is_empty():
			return issue
	var expected: Dictionary = earned(after, campaign, battle, generated)
	return "" if TransactionReceipt.same(opportunity(after), expected) else "BILLBOARD_RESULT_SOURCE"


static func claimed(receipt: Dictionary) -> Dictionary:
	if receipt.get("phase") != "RESUME_CLAIMED" or not receipt.envelope.world.has("billboard"):
		return {}
	var world: Dictionary = receipt.envelope.world
	return {"state":world.billboard, "elapsed":world.sim.elapsed}


static func history_problem(before: Dictionary, next: Dictionary) -> String:
	if before.is_empty():
		return ""
	var state: Dictionary
	var elapsed: float
	if next.phase == "SUSPEND_READY":
		state = next.envelope.world.get("billboard", {})
		elapsed = next.envelope.world.sim.elapsed
	elif next.phase == "RESULT_READY":
		var report: Dictionary = next.envelope.result.get("battle", {})
		state = report.get("billboard", {})
		elapsed = report.get("elapsed", 0.0)
	else:
		return ""
	if state.is_empty() or state.progress < before.state.progress or elapsed < before.elapsed:
		return "BILLBOARD_HISTORY_PROGRESS"
	var work: Array = before.state.work
	var current: Array = state.work
	if before.state.completed:
		return "" if current == work else "BILLBOARD_HISTORY_PROGRESS"
	if current.size() < work.size():
		return "BILLBOARD_HISTORY_PROGRESS"
	const CLOCK_EPSILON: float = 0.0001
	if not work.is_empty():
		var last: int = work.size() - 1
		var previous: Array = work[last]
		var latest: Array = current[last]
		if current.slice(0, last) != work.slice(0, last) or latest[2] < previous[2]:
			return "BILLBOARD_HISTORY_PROGRESS"
		var original: Array = latest.duplicate()
		original[2] = previous[2]
		if original != previous or (latest[2] > previous[2] and absf(float(previous[2]) - before.elapsed) > CLOCK_EPSILON):
			return "BILLBOARD_HISTORY_PROGRESS"
	if current.size() > work.size() and current[work.size()][1] < before.elapsed - CLOCK_EPSILON:
		return "BILLBOARD_HISTORY_CLOCK"
	return ""
