class_name PersistedDamageGate
extends RefCounted
## Opt-in only. Acknowledged death facts precede the existing Actor mutation/feedback chain.

var last_result: Dictionary = {}
var _transaction: RunTransaction
var _token: Dictionary
var _member_id: int
var _actor_instance: int


func _init(transaction: RunTransaction, token: Dictionary, actor: FieldActor) -> void:
	_transaction = transaction
	_token = token.duplicate(true)
	_member_id = actor.member_id
	_actor_instance = actor.get_instance_id()


func before_damage(actor: FieldActor, proposal: Dictionary) -> Error:
	if actor.get_instance_id() != _actor_instance or actor.member_id != _member_id or proposal.get("health_before") != actor.health:
		return ERR_INVALID_DATA
	last_result = _transaction.validate_action(_token)
	if last_result.error != OK:
		return last_result.error as Error
	if proposal.health_after > 0.0:
		var member: Dictionary = SurvivorRoster.member(last_result.receipt.health, _member_id)
		if member.is_empty() or actor.health > float(member.health):
			return ERR_INVALID_DATA
		return OK
	var member: Dictionary = {"id":actor.member_id, "definition_id":String(actor.definition_id),
		"health":actor.health, "call_sign":actor.call_sign}
	var growth: bool = GrowthState.is_family(last_result.receipt.base)
	if growth:
		member.growth = SurvivorRoster.member(FieldJoinRules.context(last_result.receipt).crew,_member_id).growth.duplicate(true)
		if actor.max_health != GrowthRules.maximum(member):
			return ERR_INVALID_DATA
	var proposed: Dictionary = DeathRules.propose(member, proposal.health_after, "BATTLE", String(_token.get("transaction_id", "")),{},growth)
	if not proposed.get("error", "").is_empty() or not proposed.has("death"):
		return ERR_INVALID_DATA
	last_result = _transaction.confirm_death(_token, proposed.death, actor.health)
	if last_result.error != OK:
		return last_result.error as Error
	for record: Dictionary in last_result.receipt.deaths:
		if TransactionReceipt.same(record.death, proposed.death) and SurvivorRoster.member(last_result.receipt.health, actor.member_id).health == 0.0:
			return OK
	return ERR_FILE_CORRUPT
