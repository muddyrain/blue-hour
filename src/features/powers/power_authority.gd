class_name PowerAuthority
extends RefCounted
## The original transaction owns publication; this module only proves proposals.
static func mode(rules: Variant) -> bool:
	return rules is Dictionary and (rules.get("data_version")==9 or rules.get("data_version")==10) and rules.get("mission") is Dictionary and rules.mission.get("generated") is Dictionary and rules.mission.generated.has("powers")

static func world_problem(world: Dictionary, receipt: Dictionary) -> String:
	if not SortieSnapshot.power_version(world.get("version")) or not mode(receipt.rules): return "POWER_WORLD_MODE"
	var issue: String=SpecialPowers.problem(world.get("powers"),RunTransaction.token_for(receipt),world.generated.powers.slot,float(world.sim.elapsed))
	if not issue.is_empty(): return issue
	return "" if TransactionReceipt.same({"v":world.powers.accepted},{"v":receipt.get("powers")}) else "POWER_NOT_DURABLE"

static func propose(before: Dictionary, request: Dictionary) -> Dictionary:
	if not SortieSnapshot.power_version(before.get("version")) or not before.get("powers") is Dictionary or not before.get("sim") is Dictionary or not SurvivalContracts.number(before.sim.get("elapsed")) or not SurvivalContracts.integer(before.sim.get("phase"),0,2) or not before.get("survivors") is Array or not before.get("generated") is Dictionary or not before.generated.get("powers") is Dictionary or not before.generated.powers.get("slot") is String: return {}
	var living: bool=false
	for row: Variant in before.survivors:
		if not row is Dictionary or not row.get("state") is Dictionary or not SurvivalContracts.number(row.state.get("health")): return {}
		living=living or row.state.health>0
	if not living: return {}
	if not SpecialPowers.problem(before.powers,before.powers.get("binding",{}),before.generated.powers.slot,float(before.sim.elapsed)).is_empty(): return {}
	if not TransactionReceipt.same(request,SpecialPowers.request(before.powers)): return {}
	var powers: Dictionary=SpecialPowers.accept(before.powers,request,float(before.sim.elapsed))
	if powers.is_empty(): return {}
	var after: Dictionary=before.duplicate(true)
	after.powers=powers
	return after

static func transition(previous: Dictionary, next: Dictionary) -> String:
	if not previous.get("powers") is Array or not next.get("powers") is Array: return "POWER_RECEIPT_FIELDS"
	if TransactionReceipt.same({"v":previous.powers},{"v":next.powers}): return ""
	if next.phase!="SUSPEND_READY" or not previous.powers.is_empty() or next.powers.size()!=1: return "POWER_RETRACTED_OR_PHASE"
	var proof: Variant=next.envelope.get("power_proposal")
	if not proof is Dictionary or proof.size()!=2 or not proof.get("before") is Dictionary or not proof.get("request") is Dictionary: return "POWER_PROOF_REQUIRED"
	var before: Dictionary=proof.before
	var checkpoint: Dictionary=previous.duplicate(true)
	if not before.get("survivors") is Array: return "POWER_BEFORE_FIELDS"
	for row: Variant in before.survivors:
		if not row is Dictionary or not row.get("state") is Dictionary or not SurvivalContracts.integer(row.state.get("member_id"),1,5) or not SurvivalContracts.number(row.state.get("health")): return "POWER_BEFORE_FIELDS"
		var old: Dictionary=SurvivorRoster.member(previous.health,int(row.state.member_id))
		if old.is_empty() or row.state.health>old.health: return "POWER_PREVIOUS_HEALTH"
		SurvivorRoster.member(checkpoint.health,int(row.state.member_id)).health=row.state.health
	var issue: String=SortieSnapshot.problem(before,checkpoint)
	if not issue.is_empty(): return "POWER_BEFORE:"+issue
	var after: Dictionary=propose(before,proof.request)
	return "" if not after.is_empty() and TransactionReceipt.same(after,next.envelope.world) else "POWER_AFTER_PROOF"
