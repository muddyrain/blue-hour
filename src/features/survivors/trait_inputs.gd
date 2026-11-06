class_name TraitInputs
extends RefCounted
## Only actual completed searches; defeats retain the original complete XP event source.

var binding: Dictionary = {}
var events: Array[Dictionary] = []


func configure(token: Dictionary) -> void:
	binding = token.duplicate(true)
	events.clear()


func accept_search(world: Expedition, actor: FieldActor, site: StringName, site_id: StringName = &"") -> bool:
	var active: Expedition.SearchSite = world.search_site(site_id) if site_id != &"" else world._active_site
	if not world.trait_mode or world.is_paused or world.phase == Expedition.Phase.FINISHED or not world.has_search_job(actor.member_id) or not world.survivors.has(actor) or actor.health <= 0 or active == null or world.member_site(actor.member_id) != active or not world.work_state_matches(actor,active):
		return false
	if active == null or active.kind != site or active.progress < world._site_seconds(active) or events.any(func(row: Dictionary) -> bool: return row.site == String(site)):
		return false
	events.append({"member_id":actor.member_id,"kind":"search_complete","site":String(site),"at_ms":floori(world.elapsed*1000.0)})
	return true


func snapshot(world: Expedition) -> Dictionary:
	return {"ruleset_id":TraitRules.RULESET,"binding":binding.duplicate(true),"diagnostic":world.xp_inputs.snapshot(world).diagnostic,"events":events.duplicate(true)}


func restore(value: Dictionary) -> void:
	binding = value.binding.duplicate(true)
	events.assign(value.events.duplicate(true))
