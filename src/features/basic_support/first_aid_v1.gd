class_name FirstAidV1
extends RefCounted
## PROJECT_TEMP role policy. Planning is read-only; support receipts own application.

const VERSION: int = 1
const SOURCE_ID: int = 4
const KIND: String = "first_aid"
const TITLE: String = "战地急救"
const RANGE: float = 96.0
const HEALTH_RATIO: float = 0.5
const HEAL_AMOUNT: float = 24.0


static func enabled(generated: Dictionary) -> bool:
	return generated.get("version") == 9 and SurvivalContracts.integer(generated.get("first_aid_policy"), VERSION, VERSION)


static func qualified(base: Dictionary) -> bool:
	if not base.get("crew") is Array or not base.get("recruits") is Array or not base.get("profile_id") is String \
			or not SurvivalContracts.integer(base.get("settled_sorties"), 1, RunSave.MAX_COUNTER):
		return false
	var member: Dictionary = {}
	for row: Variant in base.crew:
		if row is Dictionary and SurvivalContracts.integer(row.get("id"), SOURCE_ID, SOURCE_ID):
			if not member.is_empty():
				return false
			member = row
	if member.get("definition_id") != "crew_4" or not SurvivalContracts.number(member.get("health")) or member.health <= 0.0:
		return false
	for recruit: Variant in base.recruits:
		if not recruit is Dictionary or recruit.get("member_id") != SOURCE_ID or recruit.get("field_status") != "RETURNED" \
				or recruit.get("rescue_id") != RescueState.TARGET or recruit.get("recruit_id") != "%s:recruit:%d" % [base.profile_id, SOURCE_ID] \
				or not recruit.get("settlement_id") is String:
			continue
		var parts: PackedStringArray = recruit.settlement_id.split(":")
		if parts.size() == 2 and parts[0] == base.profile_id and parts[1].is_valid_int() \
				and SurvivalContracts.integer(int(parts[1]), 1, int(base.settled_sorties)) and parts[1] == str(int(parts[1])):
			return true
	return false


static func available(row: Dictionary) -> bool:
	var activity: Variant = row.get("activity")
	return SurvivalContracts.number(row.get("health")) and row.health > 0.0 and row.get("visible") == true \
		and SurvivalContracts.integer(activity, FieldActor.Activity.IDLE, FieldActor.Activity.RECOVERING) \
		and int(activity) in [FieldActor.Activity.IDLE, FieldActor.Activity.MOVING, FieldActor.Activity.RECOVERING]


static func plan(states: Array, layout: StreetLayout) -> Dictionary:
	if layout == null:
		return {}
	var members: Dictionary = {}
	for state: Variant in states:
		if not state is Dictionary or not SurvivalContracts.integer(state.get("member_id"), 1, SurvivalContracts.MAX_ID) \
				or members.has(int(state.member_id)) or not SortieSnapshot._vector(state.get("position")) \
				or not SurvivalContracts.number(state.get("health")) or not SurvivalContracts.number(state.get("max_health")) \
				or state.health < 0.0 or state.max_health <= 0.0 or state.health > state.max_health \
				or not state.get("visible") is bool or not SurvivalContracts.integer(state.get("activity"), 0, FieldActor.Activity.RECOVERING):
			return {}
		members[int(state.member_id)] = state
	var source: Dictionary = members.get(SOURCE_ID, {})
	if not available(source):
		return {}
	var start: Vector2 = SortieSnapshot._vec(source.position)
	var chosen: Dictionary = {}
	var lowest: float = INF
	for member_id: int in members:
		var member: Dictionary = members[member_id]
		if member_id == SOURCE_ID or not available(member):
			continue
		var ratio: float = float(member.health) / float(member.max_health)
		var target: Vector2 = SortieSnapshot._vec(member.position)
		if ratio > HEALTH_RATIO or not reach(layout, start, target):
			continue
		if ratio < lowest or (ratio == lowest and member_id < int(chosen.member_id)):
			chosen = member
			lowest = ratio
	if chosen.is_empty():
		return {}
	return {"source_id":SOURCE_ID, "member_id":int(chosen.member_id),
		"amount":minf(HEAL_AMOUNT, float(chosen.max_health) - float(chosen.health))}


static func reach(layout: StreetLayout, start: Vector2, target: Vector2) -> bool:
	return layout != null and layout.world_bounds.has_point(start) and layout.world_bounds.has_point(target) \
		and start.distance_squared_to(target) <= RANGE * RANGE and BuildAuthority.line_clear(layout, start, target)
