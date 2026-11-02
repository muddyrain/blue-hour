class_name TraitInputs
extends RefCounted
## Only actual completed searches; defeats retain the original complete XP event source.

var binding: Dictionary = {}
var events: Array[Dictionary] = []


func configure(token: Dictionary) -> void:
	binding = token.duplicate(true)
	events.clear()


func accept_search(world: Expedition, actor: FieldActor, site: StringName) -> bool:
	if not world.trait_mode or world.is_paused or world.phase == Expedition.Phase.FINISHED or actor != world.search_actor or not world.survivors.has(actor) or actor.health <= 0 or actor.activity != FieldActor.Activity.SEARCHING or actor.visible:
		return false
	if world._active_site == null or world._active_site.kind != site or world._active_site.progress < world.tuning.search_seconds or events.any(func(row: Dictionary) -> bool: return row.site == String(site)):
		return false
	events.append({"member_id":actor.member_id,"kind":"search_complete","site":String(site),"at_ms":floori(world.elapsed*1000.0)})
	return true


func snapshot(world: Expedition) -> Dictionary:
	return {"ruleset_id":TraitRules.RULESET,"binding":binding.duplicate(true),"diagnostic":world.xp_inputs.snapshot(world).diagnostic,"events":events.duplicate(true)}


func restore(value: Dictionary) -> void:
	binding = value.binding.duplicate(true)
	events.assign(value.events.duplicate(true))
