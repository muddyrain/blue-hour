class_name XpInputs
extends RefCounted
## One complete sortie ledger. A recent-action display is never the source of XP.

var events: Array[Dictionary] = []
var binding: Dictionary = {}
var diagnostic: bool = false
var _seen: Dictionary = {}


func configure(token: Dictionary) -> void:
	binding = token.duplicate(true)
	events.clear()
	_seen.clear()
	diagnostic = false


func has_capacity() -> bool:
	return events.size() < GrowthRules.MAX_EVENTS


func can_record(world: Expedition, shooter: FieldActor, enemy: FieldActor) -> bool:
	return not world.is_paused and world.phase!=Expedition.Phase.FINISHED and world.survivors.has(shooter) and world.enemies.has(enemy) and shooter.health>0 and shooter.visible and shooter.activity not in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING] and enemy.is_enemy and has_capacity() and not _seen.has(enemy.actor_id) and world.growth_inputs._counts.get(shooter.member_id)==shooter.confirmed_kills


func accept(world: Expedition, shooter: FieldActor, enemy: FieldActor, accepted: Dictionary) -> bool:
	if world.is_paused or world.phase == Expedition.Phase.FINISHED or not world.survivors.has(shooter) or not world.enemies.has(enemy):
		return false
	if shooter.health <= 0 or not shooter.visible or shooter.activity in [FieldActor.Activity.DOWN,FieldActor.Activity.SEARCHING,FieldActor.Activity.RECOVERING] or not enemy.is_enemy or enemy.health != 0 or enemy.activity != FieldActor.Activity.DOWN:
		return false
	if not enemy.has_meta(GrowthInputs.RECEIPT_META) or not TransactionReceipt.same(accepted,enemy.get_meta(GrowthInputs.RECEIPT_META)) or accepted.get("member_id") != shooter.member_id:
		return false
	if not has_capacity() or _seen.has(enemy.actor_id) or world.growth_inputs._counts.get(shooter.member_id) != shooter.confirmed_kills:
		return false
	var receipt: Dictionary = accepted.receipt.duplicate(true)
	if receipt.instance_id != shooter.weapon_instance_id or receipt.weapon_id != String(shooter.weapon_definition.id):
		return false
	receipt.member_id = shooter.member_id
	events.append(receipt)
	_seen[enemy.actor_id] = true
	diagnostic = diagnostic or world.is_practice or world.threat_rehearsal or world.los_setup != null
	return true


func snapshot(world: Expedition) -> Dictionary:
	return {"ruleset_id":GrowthRules.RULESET,"binding":binding.duplicate(true),"diagnostic":diagnostic or world.is_practice or world.threat_rehearsal or world.los_setup != null,
		"spawn_count":world._spawn_count,"events":events.duplicate(true)}


func restore(value: Dictionary) -> void:
	binding = value.binding.duplicate(true)
	diagnostic = value.diagnostic
	events.assign(value.events.duplicate(true))
	_seen.clear()
	for event: Dictionary in events:
		_seen[int(event.enemy_id)] = true


func pending(member_id: int) -> int:
	if diagnostic:
		return 0
	var count: int = 0
	for event: Dictionary in events:
		if int(event.member_id) == member_id:
			count += 1
	return count * 10
