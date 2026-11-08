class_name ScreamerReleaseV1
extends RefCounted
## One immutable batch selected from actual map entrances and the original spawn safety rules.

static func plan(event: Dictionary, layout: StreetLayout, navigation: FieldNavigation, rules: ThreatRules) -> Dictionary:
	var occupied: Array[Vector2] = []
	for point: Array in event.occupied:
		occupied.append(SortieSnapshot._vec(point))
	var view: Array = event.view
	var visible: Rect2 = Rect2(view[0], view[1], view[2], view[3]).grow(rules.screen_margin)
	var spawned: Array[Dictionary] = []
	var free_slots: int = rules.enemy_cap - occupied.size()
	var limit: int = mini(ScreamerPolicyV1.MAX_REINFORCEMENTS, free_slots)
	for offset: int in range(layout.enemy_points.size()):
		if spawned.size() >= limit:
			break
		var index: int = (int(event.attempt) + offset) % layout.enemy_points.size()
		var point: Vector2 = layout.enemy_points[index]
		var nearest: Vector2 = Vector2.INF
		var distance: float = INF
		for pair: Array in event.party:
			var foot: Vector2 = SortieSnapshot._vec(pair)
			var candidate: float = point.distance_squared_to(foot)
			if candidate < distance:
				distance = candidate
				nearest = foot
		if not rules.spawn_point_legal(point, visible, navigation, nearest, occupied):
			continue
		occupied.append(point)
		spawned.append({"enemy_id":int(event.first_id) + spawned.size(), "entrance":index, "point":pair_for(point)})
	var reason: String = "complete"
	if spawned.size() < limit:
		reason = "no_safe_point"
	elif spawned.size() < ScreamerPolicyV1.MAX_REINFORCEMENTS:
		reason = "capacity"
	return {"spawned":spawned, "reason":reason}


static func pair_for(point: Vector2) -> Array[float]:
	return [point.x, point.y]


static func problem(event: Variant, state: Dictionary, world: Dictionary, layout: StreetLayout) -> String:
	if not event is Dictionary or event.size() != 12 or not event.has_all(["event_id", "source_id", "at", "stage",
			"first_id", "attempt", "view", "viewport", "party", "occupied", "spawned", "reason"]):
		return "SCREAMER_EVENT_FIELDS"
	if event.source_id != state.actor_id or event.event_id != "screamer:%d:1" % int(state.actor_id) \
			or not SurvivalContracts.number(event.at) or event.at + 0.0001 < state.armed_at + ScreamerPolicyV1.WINDUP \
			or event.at > world.sim.elapsed or not SurvivalContracts.integer(event.stage, ThreatDirector.Stage.LATE, world.threat.stage) \
			or not SurvivalContracts.integer(event.first_id, int(state.actor_id) + 1, int(world.sim._spawn_count)) \
			or not SurvivalContracts.integer(event.attempt, int(event.first_id), int(world.sim._spawn_attempts)):
		return "SCREAMER_EVENT_IDENTITY"
	var director: ThreatDirector = ThreatDirector.new()
	director.update(float(event.at), 105.0, 7.0)
	if event.stage != director.stage or not _view_valid(event.view, layout.world_bounds, event.viewport):
		return "SCREAMER_EVENT_TIMING_VIEW"
	if not _points_valid(event.party, layout.world_bounds, world.survivors.size()) \
			or not _points_valid(event.occupied, layout.world_bounds, ThreatRules.ENEMY_CAP) \
			or event.occupied.size() > int(event.first_id) \
			or not event.occupied.any(func(point: Array) -> bool: return SortieSnapshot._vec(point) == SortieSnapshot._vec(state.origin)):
		return "SCREAMER_EVENT_POSITIONS"
	var navigation: FieldNavigation = ExplorationLayout._routing(layout.world_data).nav
	var expected: Dictionary = plan(event, layout, navigation, director.rules)
	if not event.spawned is Array or event.spawned.size() + event.first_id > world.sim._spawn_count \
			or event.spawned.size() + event.attempt > world.sim._spawn_attempts \
			or RecordEncoding.fingerprint(expected) != RecordEncoding.fingerprint({"spawned":event.spawned, "reason":event.reason}):
		return "SCREAMER_EVENT_BATCH"
	return ""


static func _points_valid(points: Variant, bounds: Rect2, limit: int) -> bool:
	if not points is Array or points.size() > limit:
		return false
	for point: Variant in points:
		if not SortieSnapshot._vector(point) or not bounds.has_point(SortieSnapshot._vec(point)):
			return false
	return true


static func _view_valid(value: Variant, bounds: Rect2, viewport: Variant) -> bool:
	if not value is Array or value.size() != 4 or not value.all(SurvivalContracts.number) \
			or not SortieSnapshot._vector(viewport) or value[2] <= 0 or value[3] <= 0:
		return false
	var zoom: float = float(viewport[0]) / float(value[2])
	return zoom >= 0.6999 and zoom <= 1.2501 and is_equal_approx(zoom, float(viewport[1]) / float(value[3])) \
		and bounds.grow(maxf(float(value[2]), float(value[3]))).has_point(Vector2(value[0], value[1]))
