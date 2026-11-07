class_name TransactionReceipt
extends RefCounted
## Journal values wrap the frozen public envelope; they are not a new camp schema.

const VERSION: int = 2
const PHASES: Array[String] = ["CAMP_REGISTERED", "EDIT_READY", "EDIT_COMMITTED", "STARTED", "IN_PROGRESS", "DEATH_CONFIRMED", "SUSPEND_READY", "RESUME_CLAIMED", "RESULT_READY", "COMMITTED"]
const KEYS: Array[String] = ["receipt_version", "revision", "previous_hash", "phase", "base", "transaction_id",
	"participants", "rules", "health", "deaths", "envelope", "camp_key", "root_id"]


static func same(left: Dictionary, right: Dictionary) -> bool:
	# Preserve historical business equality; journal integrity uses the exact codec.
	var digest: String = legacy_fingerprint(left)
	return not digest.is_empty() and digest == legacy_fingerprint(right)


static func fingerprint(value: Dictionary) -> String:
	return RecordEncoding.fingerprint(value)


static func legacy_fingerprint(value: Dictionary) -> String:
	var stamp: int = FreezeProfile.enter("legacy.fingerprint")
	var result: String = _profiled_legacy_fingerprint(value)
	FreezeProfile.leave("legacy.fingerprint", stamp)
	return result


static func _profiled_legacy_fingerprint(value: Dictionary) -> String:
	# The receipt/envelope add two levels; the public result itself still has its full 64.
	var proof: Dictionary=ValueProofCache.lookup("legacy-fingerprint",value)
	if proof.hit:
		return proof.result
	if not SurvivalContracts.json_value(value, -2):
		return ""
	var normalized: Variant = JSON.parse_string(JSON.stringify(value, "", true, true))
	var digest: String=JSON.stringify(normalized, "", true, true).sha256_text() if normalized is Dictionary else ""
	if not digest.is_empty():
		ValueProofCache.remember(proof,digest)
	return digest


static func camp_problem(data: Dictionary) -> String:
	var proof: Dictionary=ValueProofCache.lookup("receipt-camp-problem",data)
	if proof.hit:
		return ""
	var issue: String=_camp_problem(data)
	if issue.is_empty():
		ValueProofCache.remember(proof,"")
	return issue


static func _camp_problem(data: Dictionary) -> String:
	if SurvivalState.is_extended(data):
		return SurvivalState.extended_problem(data)
	return RunSave.validate(data) if SurvivalContracts.integer(data.get("schema_version"),5,5) else "CAMP_FORMAT"


static func initial(base: Dictionary, identity: String, rules: Dictionary, previous: Dictionary) -> Dictionary:
	var participants: Array[Dictionary] = SurvivalContracts.participants(base.crew, WeaponInventory.snapshot(base),true,GrowthState.is_family(base))
	var health: Array[Dictionary] = []
	for member: Dictionary in participants:
		health.append({"id":member.id, "health":member.health_before})
	var value: Dictionary = {"receipt_version":VERSION, "revision":int(previous.get("revision", 0)) + 1, "previous_hash":"",
		"phase":"STARTED", "base":base.duplicate(true), "transaction_id":identity,
		"participants":participants, "rules":rules.duplicate(true), "health":health,
		"deaths":previous.get("deaths", []).duplicate(true), "envelope":{}, "camp_key":"", "root_id":previous.get("root_id", "")}
	if (rules.get("data_version")==8 or (rules.get("data_version")==9 or rules.get("data_version")==10)): value.support=[]
	if PowerAuthority.mode(rules): value.powers=[]
	if FieldJoinState.is_family(base):
		value.joins = []
	return value


static func registration(base: Dictionary, root_id: String) -> Dictionary:
	var value: Dictionary = initial(base, "", {"ruleset_id":"camp-registration", "data_version":1}, {"root_id":root_id})
	value.phase = "CAMP_REGISTERED"
	return value


static func camp(receipt: Dictionary) -> Dictionary:
	if receipt.phase == "CAMP_REGISTERED":
		return receipt.base
	var result: Dictionary = receipt.envelope.get("result", {})
	if receipt.camp_key.is_empty():
		return result
	var value: Variant = result.get(receipt.camp_key)
	return value if value is Dictionary else {}


static func problem(value: Variant) -> String:
	var stamp: int = FreezeProfile.enter("receipt.problem")
	# Successful shape/source proofs are pure. Invalid inputs never populate the cache.
	var proof: Dictionary=ValueProofCache.lookup("receipt-problem",value) if value is Dictionary else {"hit":false}
	var result: String = "" if proof.hit else _profiled_problem(value)
	if result.is_empty() and proof.has("input"):
		ValueProofCache.remember(proof,"")
	FreezeProfile.leave("receipt.problem", stamp)
	return result


static func _profiled_problem(value: Variant) -> String:
	if not value is Dictionary or not SurvivalContracts.json_value(value, -2):
		return "RECEIPT_FIELDS"
	var field: bool = value.get("base") is Dictionary and FieldJoinState.is_family(value.base)
	if value.size() != KEYS.size()+int(field)+int(PowerAuthority.mode(value.get("rules",{})))+int((value.get("rules",{}).get("data_version")==8 or (value.get("rules",{}).get("data_version")==9 or value.get("rules",{}).get("data_version")==10))) or (field and not value.get("joins") is Array):
		return "RECEIPT_FIELDS"
	for key: String in KEYS:
		if not value.has(key):
			return "RECEIPT_FIELDS"
	if not SurvivalContracts.integer(value.receipt_version, VERSION, VERSION) or not SurvivalContracts.integer(value.revision, 1, 4096):
		return "RECEIPT_VERSION"
	if not value.previous_hash is String or (not value.previous_hash.is_empty() and not _hash(value.previous_hash)) or value.phase not in PHASES:
		return "RECEIPT_PHASE"
	if not value.base is Dictionary or not camp_problem(value.base).is_empty():
		return "BASE_FORMAT"
	if not value.root_id is String or value.root_id.length() != 32 or not value.root_id.is_valid_hex_number(false):
		return "ROOT_ID"
	if SurvivalState.is_extended(value.base) and value.root_id != value.base.journey.root_id:
		return "BATTLE_ROOT_MISMATCH"
	if not value.transaction_id is String or not value.rules is Dictionary or not value.camp_key is String:
		return "RECEIPT_VALUE_TYPES"
	if RescuePoolState.is_family(value.base) and value.phase not in ["CAMP_REGISTERED","EDIT_READY","EDIT_COMMITTED"]:
		if not value.rules.get("scope") is String or value.rules.scope!=RescuePoolState.SCOPE or not FrozenSettlement._rules_problem(value.rules).is_empty() or not TransactionReceipt.same(value.rules.get("candidate",{}),RescuePoolState.offer(value.base,value.transaction_id,String(value.rules.mission.mission_id))):
			return "POOL_CANDIDATE_BINDING"
	if value.phase not in ["CAMP_REGISTERED","EDIT_READY","EDIT_COMMITTED"] and (value.rules.get("data_version")==2 or value.rules.get("data_version")==3 or value.rules.get("data_version")==4 or (value.rules.get("data_version")==5 or (value.rules.get("data_version")==6 or (value.rules.get("data_version")==7 or (value.rules.get("data_version")==8 or (value.rules.get("data_version")==9 or value.rules.get("data_version")==10)))))):
		if not value.rules.get("mission") is Dictionary or not DailyActions.matches(value.base,value.rules.mission.get("generated")):
			return "DAILY_RECEIPT_BINDING"
	if field and not FieldJoinRules.problem(value.joins,value.base,value.transaction_id).is_empty():
		return "FIELD_JOIN_RECEIPT"
	if field and not value.joins.is_empty() and (value.rules.get("scope") != (RescuePoolState.SCOPE if RescuePoolState.is_family(value.base) else TraitState.SCOPE if TraitState.is_family(value.base) else FieldJoinState.SCOPE) or not value.rules.get("mission") is Dictionary or value.rules.mission.get("mission_id") != "rescue"):
		return "FIELD_JOIN_MISSION"
	if field and value.phase == "STARTED" and not value.joins.is_empty():
		return "FIELD_JOIN_STARTED"
	if value.phase in ["CAMP_REGISTERED", "EDIT_READY", "EDIT_COMMITTED"]:
		if field and not value.joins.is_empty():
			return "FIELD_JOIN_CAMP_EVENT"
		return CampEdit.problem(value)
	if not value.transaction_id is String or SurvivalContracts.transaction(value.base, {"check":true}, value.transaction_id).is_empty():
		return "TRANSACTION_ID"
	if not value.rules is Dictionary or not SurvivalContracts.json_value(value.rules) or not value.rules.get("ruleset_id") is String or value.rules.ruleset_id.is_empty() or not SurvivalContracts.integer(value.rules.get("data_version"), 1, SurvivalContracts.MAX_ID):
		return "RULES_VERSION"
	var expected: Array[Dictionary] = SurvivalContracts.participants(value.base.crew, WeaponInventory.snapshot(value.base),true,GrowthState.is_family(value.base))
	if expected.is_empty() or not value.participants is Array or not same({"rows":expected}, {"rows":value.participants}):
		return "PARTICIPANT_SNAPSHOT"
	var action: Dictionary = FieldJoinRules.context(value)
	expected = FieldJoinRules.participants(value)
	if not value.health is Array or value.health.size() != expected.size() or not value.deaths is Array:
		return "CHECKPOINT_FIELDS"
	if (value.rules.get("data_version")==8 or (value.rules.get("data_version")==9 or value.rules.get("data_version")==10)):
		if not value.get("support") is Array: return "SUPPORT_RECEIPT_FIELDS"
		var component: Dictionary={"version":1,"binding":token_for_compat(value),"sequence":value.support.size(),"cooldowns":{"heal":0.0,"airstrike":0.0},"accepted":value.support}
		var support_issue: String=BuildAuthority.support_problem(component,token_for_compat(value),value.rules.mission.generated)
		if not support_issue.is_empty(): return support_issue
	if PowerAuthority.mode(value.rules):
		if not value.get("powers") is Array or (value.phase=="STARTED" and not value.powers.is_empty()): return "POWER_RECEIPT_FIELDS"
		var powers: Dictionary=SpecialPowers.initial(token_for_compat(value),value.rules.mission.generated.powers.slot)
		powers.accepted=value.powers
		var at: float=float(value.powers.back().get("at",-1)) if not value.powers.is_empty() and value.powers.back() is Dictionary and SurvivalContracts.number(value.powers.back().get("at")) else 0.0
		var power_issue: String=SpecialPowers.problem(powers,token_for_compat(value),powers.equipped,at)
		if not power_issue.is_empty(): return power_issue
	var ids: Array[int] = []
	for row: Variant in value.health:
		if not row is Dictionary or row.size() != 2 or not SurvivalContracts.integer(row.get("id"), 1, SurvivalContracts.MAX_ID):
			return "CHECKPOINT_MEMBER"
		var member: Dictionary = SurvivorRoster.member(expected, int(row.id))
		if member.is_empty() or int(row.id) in ids or not SurvivalContracts.number(row.get("health")) or row.health < 0 or row.health > member.health_before+BuildAuthority.healed(value.get("support",[]),int(row.id)):
			return "CHECKPOINT_HEALTH"
		ids.append(int(row.id))
	ids.clear()
	for checkpoint: Variant in value.deaths:
		if not checkpoint is Dictionary or checkpoint.size() != 2 or not checkpoint.get("death") is Dictionary or not SurvivalContracts.integer(checkpoint.death.get("member_id"),1,SurvivalContracts.MAX_ID) or not SurvivalContracts.number(checkpoint.get("health_before")) or checkpoint.health_before <= 0 or checkpoint.health_before > (GrowthRules.maximum(SurvivorRoster.member(action.crew,int(checkpoint.death.get("member_id",0)))) if GrowthState.is_family(value.base) else 200.0):
			return "DEATH_FIELDS"
		var death: Dictionary = checkpoint.death
		if not DeathRules.problem(death, value.base.profile_id).is_empty() or int(death.member_id) in ids:
			return "DEATH_ID"
		var member: Dictionary = SurvivorRoster.member(action.crew, int(death.member_id))
		if member.is_empty():
			return "DEATH_UNKNOWN_MEMBER"
		if death.transaction_id == value.transaction_id:
			var row: Dictionary = SurvivorRoster.member(value.health, int(death.member_id))
			if row.is_empty() or row.health != 0 or checkpoint.health_before > member.health+BuildAuthority.healed(value.get("support",[]),int(member.id)):
				return "DEATH_HEALTH"
		elif member.health != 0 or int(death.transaction_id.get_slice(":", 1)) > int(value.base.settled_sorties):
			return "DEATH_HISTORY"
		ids.append(int(death.member_id))
	for row: Dictionary in value.health:
		if row.health == 0 and int(row.id) not in ids:
			return "UNCONFIRMED_DEATH"
	if not value.envelope is Dictionary or not value.camp_key is String:
		return "RESULT_FIELDS"
	if value.phase in ["SUSPEND_READY","RESUME_CLAIMED"]:
		return SuspendRecord.problem(value)
	if value.phase in ["RESULT_READY", "COMMITTED"]:
		if not SurvivalContracts.transaction_problem(value.base, value.envelope).is_empty() or value.envelope.transaction_id != value.transaction_id:
			return "RESULT_ENVELOPE"
		return _result_problem(value)
	if not value.envelope.is_empty() or not value.camp_key.is_empty():
		return "EARLY_RESULT"
	return ""


static func transition(previous: Dictionary, next: Dictionary) -> String:
	var stamp: int = FreezeProfile.enter("receipt.transition")
	var result: String = _profiled_transition(previous,next)
	FreezeProfile.leave("receipt.transition", stamp)
	return result


static func _profiled_transition(previous: Dictionary, next: Dictionary) -> String:
	var issue: String = problem(next)
	if not issue.is_empty():
		return issue
	if previous.is_empty():
		return "" if next.revision == 1 and next.previous_hash == "" and next.phase == "CAMP_REGISTERED" else "FIRST_RECORD"
	if next.revision != previous.revision + 1:
		return "REVISION_ORDER"
	if next.root_id != previous.root_id or next.base.profile_id != previous.base.profile_id:
		return "RUN_ROOT_CHANGED"
	if next.phase == "EDIT_READY" or next.phase == "STARTED":
		if previous.phase not in ["CAMP_REGISTERED", "EDIT_COMMITTED", "COMMITTED"] or not same(next.base, camp(previous)) or not same({"v":next.deaths}, {"v":previous.deaths}):
			return "CAMP_HEAD_CONFLICT"
		return "" if next.phase == "EDIT_READY" or _initial_health(next) else "INITIAL_HEALTH"
	if previous.phase == "EDIT_READY" and next.phase == "EDIT_COMMITTED":
		return "" if _same_frozen(previous, next) else "EDIT_COMMIT_CHANGED"
	if previous.phase in ["CAMP_REGISTERED", "EDIT_READY", "EDIT_COMMITTED"]:
		return "CAMP_TRANSITION"
	if next.transaction_id != previous.transaction_id:
		if previous.phase != "COMMITTED" or next.phase != "STARTED" or not _initial_health(next) or next.base.profile_id != previous.base.profile_id or next.base.settled_sorties != previous.base.settled_sorties + 1 or not same({"rows":next.deaths}, {"rows":previous.deaths}):
			return "NEW_TRANSACTION_ORDER"
		return ""
	for key: String in ["base", "rules", "participants"]:
		if not same({"v":previous[key]}, {"v":next[key]}):
			return "FROZEN_INPUT_CHANGED"
	var joining: bool = false
	if FieldJoinState.is_family(next.base):
		joining = previous.joins.is_empty() and next.joins.size() == 1
		if not same({"v":previous.joins},{"v":next.joins}) and not (joining and next.phase in ["IN_PROGRESS","DEATH_CONFIRMED"] and previous.phase in ["STARTED","IN_PROGRESS","DEATH_CONFIRMED","RESUME_CLAIMED"] and same({"v":previous.deaths},{"v":next.deaths})):
			return "FIELD_JOIN_RETRACTED_OR_CHANGED"
	if (next.rules.get("data_version")==8 or (next.rules.get("data_version")==9 or next.rules.get("data_version")==10)):
		issue=BuildAuthority.transition(previous,next)
		if not issue.is_empty(): return issue
	if PowerAuthority.mode(next.rules):
		issue=PowerAuthority.transition(previous,next)
		if not issue.is_empty(): return issue
	if previous.phase == "SUSPEND_READY":
		return "" if next.phase == "RESUME_CLAIMED" and _same_frozen(previous,next) else "SUSPEND_MUST_BE_CLAIMED"
	if next.phase == "RESUME_CLAIMED":
		return "SUSPEND_NOT_READY"
	if next.phase == "SUSPEND_READY" and (previous.phase not in ["STARTED","IN_PROGRESS","DEATH_CONFIRMED","RESUME_CLAIMED"] or next.envelope.previous_head != next.previous_hash):
		return "SUSPEND_HEAD_OR_PHASE"
	if previous.phase == "COMMITTED" or (previous.phase == "RESULT_READY" and next.phase != "COMMITTED") or next.phase == "STARTED":
		return "ILLEGAL_TRANSITION"
	if next.deaths.size() < previous.deaths.size() or next.deaths.size() > previous.deaths.size() + 1:
		return "DEATH_ORDER"
	for index: int in range(previous.deaths.size()):
		if not same(next.deaths[index], previous.deaths[index]):
			return "DEATH_RETRACTED"
	for row: Dictionary in next.health:
		var old: Dictionary = SurvivorRoster.member(previous.health, int(row.id))
		if old.is_empty():
			if joining and row.id == next.joins[0].member_id and row.health == 200:
				continue
			return "FIELD_JOIN_HEALTH_SOURCE"
		if row.health > old.health + BuildAuthority.healed(next.get("support",[]),int(row.id))-BuildAuthority.healed(previous.get("support",[]),int(row.id)):
			return "HEALTH_RESTORED"
	if previous.phase == "RESULT_READY":
		var copy: Dictionary = next.duplicate(true)
		for key: String in ["revision", "previous_hash", "phase"]:
			copy[key] = previous[key]
		return "" if same(copy, previous) else "COMMITTED_RESULT_CHANGED"
	if next.phase == "COMMITTED":
		return "RESULT_NOT_READY"
	var added: bool = next.deaths.size() > previous.deaths.size()
	if added and next.phase != "DEATH_CONFIRMED":
		return "DEATH_NOT_CHECKPOINTED"
	if added:
		var checkpoint: Dictionary = next.deaths.back()
		var old: Dictionary = SurvivorRoster.member(previous.health, int(checkpoint.death.member_id))
		if old.is_empty() or checkpoint.health_before > old.health or checkpoint.death.transaction_id != next.transaction_id:
			return "DEATH_HEALTH_SOURCE"
	if not added and next.phase == "DEATH_CONFIRMED" and not _has_current_death(next):
		return "MISSING_DEATH"
	if previous.phase == "DEATH_CONFIRMED" and next.phase == "IN_PROGRESS":
		return "DEATH_PHASE_RETRACTED"
	return ""


static func _same_frozen(previous: Dictionary, next: Dictionary) -> bool:
	var copy: Dictionary = next.duplicate(true)
	for key: String in ["revision", "previous_hash", "phase"]:
		copy[key] = previous[key]
	return same(copy, previous)


static func _result_problem(receipt: Dictionary) -> String:
	var after: Dictionary = camp(receipt)
	if after.is_empty() or not camp_problem(after).is_empty() or after.schema_version != receipt.base.schema_version:
		return "RESULT_CAMP_FORMAT"
	if SurvivalState.is_extended(after):
		var deaths: Array = []
		for checkpoint: Dictionary in receipt.deaths:
			deaths.append(checkpoint.death)
		deaths.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.member_id) < int(b.member_id))
		if after.journey.root_id != receipt.root_id or not same({"deaths":deaths},{"deaths":after.journey.deaths}):
			return "RESULT_BATTLE_HISTORY"
		if SurvivalState.is_state(after) and not same(after.origin, receipt.base.origin):
			return "RESULT_MIGRATION_ORIGIN_CHANGED"
	var before: Dictionary = FieldJoinRules.context(receipt)
	if FieldJoinState.is_family(receipt.base):
		var field_issue: String = FieldJoinRules.transition_problem(receipt.base,after,receipt.envelope.result.get("battle",{}))
		if not field_issue.is_empty():
			return field_issue
	elif RescueState.is_family(before):
		var rescue_issue: String = RescueState.transition_problem(before,after,receipt.envelope.result.get("battle",{}))
		if not rescue_issue.is_empty():
			return rescue_issue
	if GrowthState.is_family(before):
		var xp_issue: String = GrowthRules.result_problem(receipt)
		if not xp_issue.is_empty():
			return xp_issue
	if after.profile_id != before.profile_id or after.settled_sorties != before.settled_sorties + 1 or after.last_settlement_id != receipt.transaction_id:
		return "RESULT_CAMP_ID"
	for member: Dictionary in before.crew:
		var result: Dictionary = SurvivorRoster.member(after.crew, int(member.id))
		var last: Dictionary = SurvivorRoster.member(receipt.health, int(member.id))
		var limit: float = float(member.health) if last.is_empty() else float(last.health)
		if GrowthState.is_family(before) and not result.is_empty():
			limit += GrowthRules.maximum(result) - GrowthRules.maximum(member)
		if result.is_empty() or result.definition_id != member.definition_id or result.health > limit:
			return "RESULT_MEMBER_CHANGED"
		if member.health > 0 and result.health == 0:
			var found: bool = false
			for checkpoint: Dictionary in receipt.deaths:
				found = found or int(checkpoint.death.member_id) == int(member.id)
			if not found:
				return "RESULT_UNCONFIRMED_DEATH"
	return ""


static func token_for_compat(value: Dictionary) -> Dictionary:
	return RunTransaction.token_for(value)


static func _initial_health(receipt: Dictionary) -> bool:
	for member: Dictionary in receipt.participants:
		if SurvivorRoster.member(receipt.health, int(member.id)).health != member.health_before:
			return false
	return true


static func _has_current_death(receipt: Dictionary) -> bool:
	for checkpoint: Dictionary in receipt.deaths:
		if checkpoint.death.transaction_id == receipt.transaction_id:
			return true
	return false


static func _hash(value: String) -> bool:
	return value.length() == 64 and value.is_valid_hex_number(false)
