class_name GrowthInputs
extends RefCounted
## Adapts actual fatal shots into factual inputs; does not award experience.

const RECEIPT_META: StringName = &"m503_defeat_input"

var _counts: Array[int] = [0,0]
var _recent: Dictionary[int, Array] = {1:[],2:[]}


func accept_defeat(shooter: FieldActor, enemy: FieldActor, at: float) -> Dictionary:
	if not is_instance_valid(shooter) or not is_instance_valid(enemy):
		return {}
	if shooter.is_enemy or not enemy.is_enemy or shooter.actor_id not in [0,1] or shooter.health <= 0.0:
		return {}
	if enemy.activity != FieldActor.Activity.DOWN or enemy.health != 0.0 or enemy.has_meta(RECEIPT_META):
		return {}
	if shooter.weapon_instance_id.is_empty() or shooter.weapon_definition == null or not is_finite(at) or at < 0.0:
		return {}
	var member_id: int = shooter.actor_id + 1
	# Integer milliseconds preserve journal timestamps across JSON; simulation time stays untouched.
	var receipt: Dictionary = {"kind":"defeat","enemy_id":enemy.actor_id,"at_ms":floori(at * 1000.0),
		"weapon_id":String(shooter.weapon_definition.id),"instance_id":shooter.weapon_instance_id}
	_counts[member_id - 1] += 1
	_recent[member_id].append(receipt)
	if _recent[member_id].size() > SurvivorGrowth.RECENT_LIMIT:
		_recent[member_id].pop_front()
	var event: Dictionary = {"member_id":member_id,"receipt":receipt.duplicate(true)}
	# The original corpse lifecycle owns this dedupe marker; no unbounded ID set.
	enemy.set_meta(RECEIPT_META,event.duplicate(true))
	return event


func snapshot(sortie_id: String, map_id: StringName, duration: float) -> Dictionary:
	return {"sortie_id":sortie_id,"map_id":String(map_id),"duration_ms":floori(duration * 1000.0),
		"members":[{"member_id":1,"total":_counts[0],"recent":_recent[1].duplicate(true)},
			{"member_id":2,"total":_counts[1],"recent":_recent[2].duplicate(true)}]}
