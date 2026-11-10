class_name BillboardWorkV1
extends RefCounted
## Outdoor work evidence shared by suspension and the original return report.

const CLOCK_EPSILON: float = 0.0001
const MAX_PERIODS: int = 1024

var _periods: Array = []


func record(member_id: int, point: Vector2, start: float, end: float) -> void:
	if not _periods.is_empty():
		var previous: Array = _periods.back()
		if previous[0] == member_id and absf(float(previous[2]) - start) <= 0.000000001 \
				and previous[3] == point.x and previous[4] == point.y:
			previous[2] = end
			return
	_periods.append([member_id, start, end, point.x, point.y])


func snapshot(progress: float) -> Dictionary:
	return {"progress":progress, "completed":progress == BillboardActionV1.SECONDS,
		"work":_periods.duplicate(true)}


func restore(state: Dictionary) -> void:
	_periods = state.work.duplicate(true)


static func problem(generated: Dictionary, state: Variant, elapsed: float, crew: Array) -> String:
	if not BillboardActionV1.enabled(generated):
		return "" if state == null else "BILLBOARD_WORK_UNEXPECTED"
	if not state is Dictionary or state.size() != 3 or not state.has_all(["progress", "completed", "work"]) \
			or not state.completed is bool or not state.work is Array or state.work.size() > MAX_PERIODS:
		return "BILLBOARD_WORK_FIELDS"
	if not SurvivalContracts.number(state.progress) or state.progress < 0.0 \
			or state.progress > BillboardActionV1.SECONDS or state.progress > elapsed + CLOCK_EPSILON \
			or state.completed != (state.progress == BillboardActionV1.SECONDS):
		return "BILLBOARD_WORK_PROGRESS"
	if state.work.is_empty():
		return "" if state.progress == 0.0 else "BILLBOARD_WORK_SOURCE"
	var arrivals: Array = generated.layout.arrivals
	var living: Array = crew.filter(func(member: Dictionary) -> bool: return member.health > 0.0)
	living.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	if living.size() > arrivals.size():
		return "BILLBOARD_WORK_ARRIVALS"
	var starts: Dictionary[int, Vector2] = {}
	var speeds: Dictionary[int, float] = {}
	var loadout: Variant = PowerState.loadout(generated.powers)
	var speed_equipped: bool = SpecialPowers.SPEED in loadout.slots if loadout is Dictionary else loadout == SpecialPowers.SPEED
	var power_limit: float = float(SpecialPowers.POLICY[SpecialPowers.SPEED].move_factor) if speed_equipped else 1.0
	var build_move: float = BuildItems.frozen_factors(generated.build).move
	for index: int in range(living.size()):
		var member: Dictionary = living[index]
		var id: int = int(member.id)
		starts[id] = WorldLayout.point(arrivals[index])
		var speed: float = 125.0 * TraitRules.factor(member, "move") * PersonaState.factor(generated, id, "move") * build_move
		speeds[id] = speed * power_limit + FieldContacts.RECOVERY_SPEED + FieldContacts.YIELD_SPEED * (living.size() - 1)
	var station: Vector2 = BillboardActionV1.point(generated)
	# Work points may be reached after opening an M43 passage. Static obstacles
	# still apply and the original navigation is the least restrictive version.
	var navigation: FieldNavigation = ExplorationLayout._routing(generated.layout).nav
	var prior_end: float = 0.0
	var total: float = 0.0
	for row: Variant in state.work:
		if not row is Array or row.size() != 5 or not SurvivalContracts.integer(row[0], 1, SurvivalContracts.MAX_ID) \
				or not starts.has(int(row[0])):
			return "BILLBOARD_WORK_SOURCE"
		for index: int in range(1, 5):
			if not SurvivalContracts.number(row[index]):
				return "BILLBOARD_WORK_SOURCE"
		var id: int = int(row[0])
		var start: float = row[1]
		var end: float = row[2]
		var point: Vector2 = Vector2(row[3], row[4])
		if start < 0.0 or start < prior_end - CLOCK_EPSILON or end <= start or end > elapsed + CLOCK_EPSILON \
				or not point.is_finite() or point.distance_to(station) > BillboardActionV1.WORK_RANGE or not navigation.is_clear(point) \
				or point.distance_to(starts[id]) > speeds[id] * start + CLOCK_EPSILON:
			return "BILLBOARD_WORK_SOURCE"
		prior_end = end
		total += end - start
	return "" if state.progress > 0.0 and absf(total - float(state.progress)) <= CLOCK_EPSILON else "BILLBOARD_WORK_SOURCE"
