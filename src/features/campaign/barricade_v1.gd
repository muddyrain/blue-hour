class_name BarricadeV1
extends RefCounted
## One immutable, navigation-certified vehicle on an ordinary supply action.

const VERSION: int = 1
const MIN_SAVING: float = 320.0
const MIN_GAP: float = 64.0
const MAX_GAP: float = 160.0
const VEHICLE_DEPTH: float = 36.0
const APPROACH: float = 72.0
const LANDING: float = 48.0
const MAX_TRIALS: int = 96
const CACHE_SIZE: int = 8
const KEYS: Array[String] = ["version", "id", "rect", "anchor", "landing", "near", "far",
	"site_id", "layout", "closed_length", "open_length"]

static var _closed: Dictionary[String, FieldNavigation] = {}


static func enabled(action: Dictionary) -> bool:
	var marker: Variant = action.get("barricade")
	if not _eligible(action) or not marker is Dictionary or marker.size() != KEYS.size() or not marker.has_all(KEYS):
		return false
	return SurvivalContracts.integer(marker.version, VERSION, VERSION) \
		and marker.id is String and marker.id.begins_with("barricade_") \
		and marker.layout is String and marker.layout.length() == 64 and marker.layout.is_valid_hex_number() \
		and marker.site_id is String and marker.site_id in action.objective.site_ids \
		and _coordinates(marker.rect, 4) and WorldLayout.rect(marker.rect).has_area() and _coordinates(marker.anchor, 2) \
		and _coordinates(marker.landing, 2) and _coordinates(marker.near, 2) and _coordinates(marker.far, 2) \
		and SurvivalContracts.number(marker.closed_length) and SurvivalContracts.number(marker.open_length) \
		and marker.open_length > 0.0 and marker.closed_length - marker.open_length >= MIN_SAVING


static func rect(action: Dictionary) -> Rect2:
	return WorldLayout.rect(action.barricade.rect)


static func freeze(action: Dictionary) -> Dictionary:
	if not _eligible(action):
		return action
	var proof: Dictionary = ValueProofCache.lookup("barricade-v1", {
		"id":action.id, "layout":action.layout, "sites":action.sites, "objective":action.objective})
	var marker: Dictionary = proof.result if proof.hit else _certify(action)
	ValueProofCache.remember(proof, marker)
	if marker.is_empty():
		return action
	var result: Dictionary = action.duplicate(false)
	result.barricade = marker.duplicate(true)
	return result


static func navigation(action: Dictionary, opened: bool) -> FieldNavigation:
	var original: FieldNavigation = ExplorationLayout._routing(action.layout).nav
	if opened or not enabled(action):
		return original
	var key: String = RecordEncoding.fingerprint(action)
	if not _closed.has(key):
		var stamp: int = FreezeProfile.enter("barricade.navigation_prepare")
		var closed: FieldNavigation = original.copy_navigation()
		closed.set_private_blocker(original, rect(action))
		if _closed.size() >= CACHE_SIZE:
			_closed.erase(_closed.keys()[0])
		_closed[key] = closed
		FreezeProfile.leave("barricade.navigation_prepare", stamp)
	return _closed[key]


static func _eligible(action: Dictionary) -> bool:
	var layout: Variant = action.get("layout")
	var objective: Variant = action.get("objective")
	var campaign: Variant = action.get("campaign")
	return action.get("version") == 9 and action.get("type") == "supply" and action.get("slot") == 0 \
		and SurvivalContracts.integer(action.get("day"), 4, RunSave.MAX_COUNTER) \
		and not action.has("rare_policy") and not action.has("sortie_risk") and not action.has("investigation") \
		and not action.has("event_sortie") and campaign is Dictionary and campaign.get("is_finale") == false \
		and layout is Dictionary and layout.get("version") == 5 and layout.get("size") == "medium" \
		and objective is Dictionary and objective.get("site_ids") is Array


static func _certify(action: Dictionary) -> Dictionary:
	var map: Dictionary = action.layout
	var routes: Dictionary = ExplorationLayout._routing(map)
	if routes.is_empty():
		return {}
	var original: FieldNavigation = routes.nav
	var street: StreetLayout = ExplorationLayout.resource(map)
	var bus: Vector2 = WorldLayout.point(map.bus.door)
	var reserved: PackedVector2Array = PackedVector2Array([bus, WorldLayout.point(map.bus.passenger_door)])
	var goals: PackedVector2Array = PackedVector2Array([bus])
	var targets: Dictionary[String, Vector2] = {}
	for site: Dictionary in action.sites:
		var point: Vector2 = TaskActions.site_point(action, site)
		reserved.append(point)
		goals.append(point)
		if site.kind == "food" and site.id in action.objective.site_ids:
			targets[site.id] = point
	if targets.is_empty():
		return {}
	for points: Array in [map.arrivals, map.enemy_points, map.gates]:
		for point: Array in points:
			reserved.append(WorldLayout.point(point))
	for points: Array in [map.arrivals, map.enemy_points]:
		for point: Array in points:
			goals.append(WorldLayout.point(point))
	for x: float in [-48.0, 0.0, 48.0]:
		for y: float in [-48.0, 0.0, 48.0]:
			goals.append(bus + Vector2(x, y))
			reserved.append(goals[-1])
	for entity: Dictionary in map.entities:
		reserved.append(WorldLayout.point(entity.door))
	var trials: Array[Dictionary] = _trials(original, street.roads, WorldLayout.rect(map.bus.sweep), reserved, bus)
	if trials.is_empty():
		return {}
	var closed: FieldNavigation = original.copy_navigation()
	var walls: Array[ShotObstacle] = street.shot_obstacles()
	for index: int in range(mini(MAX_TRIALS, trials.size())):
		var trial: Dictionary = trials[index]
		var box: Rect2 = trial.box
		closed.set_private_blocker(original, box)
		var center: Vector2 = box.get_center()
		var direction: Vector2 = trial.direction
		for side: float in [1.0, -1.0]:
			var near: Vector2 = _grid_center(original, center - direction * APPROACH * side)
			var far: Vector2 = _grid_center(original, center + direction * APPROACH * side)
			var landing: Vector2 = center - direction * LANDING * side
			if not _clear_strike(closed, walls, near, landing, center) or not closed.is_clear(far):
				continue
			var cross: PackedVector2Array = original.path_between(near, far)
			if not _reaches(cross, far) or not _crosses(cross, box) or not _reaches(closed.path_between(near, far), far):
				continue
			for site_id: String in targets:
				var target: Vector2 = targets[site_id]
				var short_path: PackedVector2Array = original.path_between(near, target)
				if not _reaches(short_path, target) or not _crosses(short_path, box):
					continue
				var detour: PackedVector2Array = closed.path_between(near, target)
				if not _reaches(detour, target) or _crosses(detour, box):
					continue
				var open_length: float = ExplorationLayout._length(short_path)
				var closed_length: float = ExplorationLayout._length(detour)
				if closed_length - open_length >= MIN_SAVING and _connected(closed, bus, near, goals):
					return {"version":VERSION, "id":"barricade_" + (action.id + "|" + str(box)).sha256_text().left(24),
						"rect":[box.position.x, box.position.y, box.size.x, box.size.y], "anchor":[center.x, center.y],
						"landing":[landing.x, landing.y], "near":[near.x, near.y], "far":[far.x, far.y], "site_id":site_id,
						"layout":RecordEncoding.fingerprint(map), "closed_length":closed_length, "open_length":open_length}
	return {}


static func _trials(nav: FieldNavigation, roads: Array[Rect2], sweep: Rect2,
		reserved: PackedVector2Array, bus: Vector2) -> Array[Dictionary]:
	var trials: Array[Dictionary] = []
	var seen: Dictionary[Rect2, bool] = {}
	for axis: int in range(2):
		for a: Rect2 in nav.obstacles:
			for b: Rect2 in nav.obstacles:
				var gap: float = b.position[axis] - a.end[axis]
				if gap < MIN_GAP or gap > MAX_GAP:
					continue
				var direction: Vector2 = Vector2.DOWN if axis == 0 else Vector2.RIGHT
				var start: float = maxf(a.position[1 - axis], b.position[1 - axis])
				var end: float = minf(a.end[1 - axis], b.end[1 - axis])
				if end - start < VEHICLE_DEPTH:
					continue
				for fraction: float in [0.25, 0.5, 0.75]:
					var center: Vector2 = Vector2.ZERO
					center[axis] = a.end[axis] + gap * 0.5
					center[1 - axis] = lerpf(start + VEHICLE_DEPTH * 0.5, end - VEHICLE_DEPTH * 0.5, fraction)
					var size: Vector2 = Vector2(gap, VEHICLE_DEPTH) if axis == 0 else Vector2(VEHICLE_DEPTH, gap)
					var box: Rect2 = Rect2(center - size * 0.5, size)
					if seen.has(box) or not _candidate_clear(box, nav, roads, sweep, reserved):
						continue
					seen[box] = true
					trials.append({"box":box, "direction":direction, "score":center.distance_squared_to(bus),
						"rank":trials.size()})
	trials.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.score < b.score if a.score != b.score else a.rank < b.rank)
	return trials


static func _candidate_clear(box: Rect2, nav: FieldNavigation, roads: Array[Rect2], sweep: Rect2,
		reserved: PackedVector2Array) -> bool:
	if not nav.bounds.encloses(box.grow(32.0)) or sweep.grow(48.0).intersects(box):
		return false
	if not roads.any(func(road: Rect2) -> bool: return road.grow(120.0).has_point(box.get_center())):
		return false
	for block: Rect2 in nav.obstacles:
		if box.intersects(block):
			return false
	var safety: Rect2 = box.grow(32.0)
	for point: Vector2 in reserved:
		if safety.has_point(point):
			return false
	return true


static func _clear_strike(nav: FieldNavigation, walls: Array[ShotObstacle], near: Vector2,
		landing: Vector2, center: Vector2) -> bool:
	return nav.is_clear(near) and nav.is_clear(landing) \
		and near.distance_to(landing) <= BasicSupport.POLICY.airstrike_range \
		and landing.distance_to(center) <= BasicSupport.POLICY.airstrike_radius \
		and ToxicV1.line_clear(near, landing, walls) and ToxicV1.line_clear(landing, center, walls) \
		and _reaches(nav.path_between(near, landing), landing)


static func _connected(nav: FieldNavigation, bus: Vector2, near: Vector2, goals: PackedVector2Array) -> bool:
	if not _reaches(nav.path_between(bus, near), near):
		return false
	for point: Vector2 in goals:
		# The grid is undirected, so this also certifies the return to the bus.
		if not nav.is_clear(point) or not _reaches(nav.path_between(bus, point), point):
			return false
	return true


static func _grid_center(nav: FieldNavigation, point: Vector2) -> Vector2:
	return nav.bounds.position + (((point - nav.bounds.position) / FieldNavigation.CELL).floor() + Vector2.ONE * 0.5) * FieldNavigation.CELL


static func _crosses(path: PackedVector2Array, box: Rect2) -> bool:
	for point: Vector2 in path:
		if box.has_point(point):
			return true
	return false


static func _reaches(path: PackedVector2Array, target: Vector2) -> bool:
	return not path.is_empty() and path[-1].distance_to(target) <= 14.0


static func _coordinates(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for component: Variant in value:
		if not SurvivalContracts.number(component):
			return false
	return true
