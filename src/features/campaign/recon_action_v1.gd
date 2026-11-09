class_name ReconActionV1
extends RefCounted
## PROJECT_TEMP. Extends a certified equipment action without changing its sites or rewards.

const VERSION: int = 1
const SITE_ID: String = "recon"
const PRIMARY_ID: String = "cash"
const SECONDS: float = 6.0
const CELL: int = 96
const RADIUS: float = 192.0
const REGION: float = 576.0
const MIN_DETOUR: float = 300.0
const WORK_RANGE: float = 14.0
const SEARCH_RADIUS: float = 672.0
const SEARCH_CELLS: int = 7
const ROUTE_LIMIT: int = 48
const SITE_CLEARANCE: float = 56.0
const KEYS: Array[String] = ["version", "point", "primary_id", "optional_id", "direct", "via_recon"]


static func enabled(action: Dictionary) -> bool:
	var marker: Variant = action.get("recon")
	if not marker is Dictionary or marker.size() != KEYS.size() or not marker.has_all(KEYS):
		return false
	var anchor: Variant = marker.point
	return SurvivalContracts.integer(marker.version, VERSION, VERSION) and marker.primary_id == PRIMARY_ID \
		and marker.optional_id is String and not marker.optional_id.is_empty() and marker.optional_id != PRIMARY_ID \
		and anchor is Array and anchor.size() == 2 and SurvivalContracts.number(anchor[0]) and SurvivalContracts.number(anchor[1]) \
		and SurvivalContracts.number(marker.direct) and marker.direct > 0.0 \
		and SurvivalContracts.number(marker.via_recon) and marker.via_recon >= marker.direct + MIN_DETOUR


static func point(action: Dictionary) -> Vector2:
	return WorldLayout.point(action.recon.point) if enabled(action) else Vector2.INF


static func cell_rect(bounds: Rect2, cell: Vector2i) -> Rect2:
	var origin: Vector2 = bounds.position + Vector2(cell) * CELL
	return Rect2(origin, (bounds.end - origin).min(Vector2.ONE * CELL))


static func freeze(action: Dictionary) -> Dictionary:
	if not _eligible(action):
		return action
	var toolbox: String = WorkshopSiteV1.site_id(action)
	var proof: Dictionary = ValueProofCache.lookup("recon-anchor", {"layout":action.layout, "sites":action.sites, "toolbox":toolbox})
	var marker: Dictionary = proof.result if proof.hit else _certify(action, toolbox)
	if marker.is_empty():
		return action
	ValueProofCache.remember(proof, marker)
	var result: Dictionary = action.duplicate(false)
	result.recon = marker
	return result


static func _eligible(action: Dictionary) -> bool:
	var layout: Variant = action.get("layout")
	# This predicate identifies the ordinary outdoor gear offer before any affix is applied.
	return WeaponInventory.affix_eligible(action) and not action.has("event_sortie") \
		and SurvivalContracts.integer(action.get("day"), 4, RunSave.MAX_COUNTER) \
		and layout.get("topology") == "industrial" and layout.get("size") in ["medium", "large"]


static func _certify(action: Dictionary, toolbox: String) -> Dictionary:
	var layout: Dictionary = action.layout
	var routing: Dictionary = ExplorationLayout._routing(layout)
	if routing.is_empty():
		return {}
	var nav: FieldNavigation = routing.nav
	var bounds: Rect2 = nav.bounds
	var bus: Vector2 = WorldLayout.point(layout.bus.door)
	var starts: PackedVector2Array = PackedVector2Array([bus, WorldLayout.point(layout.bus.passenger_door)])
	for arrival: Array in layout.arrivals:
		starts.append(WorldLayout.point(arrival))
	var targets: Dictionary[String, Vector2] = {}
	var work_points: PackedVector2Array = PackedVector2Array()
	var primary: Vector2 = Vector2.INF
	for site: Dictionary in action.sites:
		var work_point: Vector2 = ExplorationSites.site_point(layout, site)
		work_points.append(work_point)
		var center: Vector2 = _cell_center(bounds, work_point)
		if _covered_by_path(center, starts, false, RADIUS):
			continue
		if site.id == PRIMARY_ID:
			primary = work_point
		elif site.source == "optional_building" and not site.building.is_empty() and not site.weapon and site.amount > 0:
			targets[site.id] = center
	if not primary.is_finite() or targets.is_empty():
		return {}
	var direct_path: PackedVector2Array = nav.path_between(bus, primary)
	if not _reaches(direct_path, primary):
		return {}
	var direct: float = ExplorationLayout._length(direct_path)
	var primary_center: Vector2 = _cell_center(bounds, primary)
	var ordered_targets: Array[String] = []
	ordered_targets.assign(targets.keys())
	ordered_targets.sort()
	if targets.has(toolbox):
		ordered_targets.erase(toolbox)
		ordered_targets.push_front(toolbox)
	else:
		toolbox = ""
	var anchors: Array[Vector2] = _anchors(layout, nav, bus, work_points, primary_center)
	var fallback: Dictionary = {}
	for index: int in range(mini(anchors.size(), ROUTE_LIMIT)):
		var anchor: Vector2 = anchors[index]
		var approach: PackedVector2Array = nav.path_between(bus, anchor)
		if not _reaches(approach, anchor) or _covered_by_path(primary_center, approach, true, RADIUS + WORK_RANGE):
			continue
		var onward: PackedVector2Array = nav.path_between(anchor, primary)
		if not _reaches(onward, primary):
			continue
		var via: float = ExplorationLayout._length(approach) + ExplorationLayout._length(onward)
		if via < direct + MIN_DETOUR:
			continue
		for optional: String in ordered_targets:
			if _covered_by_path(targets[optional], approach, true, RADIUS + WORK_RANGE):
				continue
			var marker: Dictionary = {"version":VERSION, "point":[anchor.x, anchor.y], "primary_id":PRIMARY_ID,
				"optional_id":optional, "direct":direct, "via_recon":via}
			if toolbox.is_empty() or optional == toolbox:
				return marker
			if fallback.is_empty():
				fallback = marker
			break
	return fallback


static func _anchors(layout: Dictionary, nav: FieldNavigation, bus: Vector2, work_points: PackedVector2Array,
		primary_center: Vector2) -> Array[Vector2]:
	var reserved: Array[Rect2] = ExplorationLayout._reserved(layout)
	var origin: Vector2i = Vector2i(((bus - nav.bounds.position) / CELL).floor())
	var result: Array[Vector2] = []
	for y: int in range(-SEARCH_CELLS, SEARCH_CELLS + 1):
		for x: int in range(-SEARCH_CELLS, SEARCH_CELLS + 1):
			# Put the anchor on the navigation grid rather than between two squares.
			var anchor: Vector2 = nav.bounds.position + Vector2(origin + Vector2i(x, y)) * CELL \
				+ Vector2.ONE * (CELL * 0.5 + FieldNavigation.CELL * 0.5)
			if anchor.distance_to(bus) > SEARCH_RADIUS or anchor.distance_to(primary_center) <= RADIUS + WORK_RANGE \
					or _covered_by_path(anchor, work_points, false, SITE_CLEARANCE) or not nav.is_clear(anchor):
				continue
			if not reserved.any(func(area: Rect2) -> bool: return area.has_point(anchor)):
				result.append(anchor)
	result.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var ad: float = a.distance_squared_to(bus)
		var bd: float = b.distance_squared_to(bus)
		return ad < bd if ad != bd else a.y < b.y if a.y != b.y else a.x < b.x)
	return result


static func _cell_center(bounds: Rect2, position: Vector2) -> Vector2:
	return cell_rect(bounds, Vector2i(((position - bounds.position) / CELL).floor())).get_center()


static func _covered_by_path(target: Vector2, path: PackedVector2Array, follow: bool, radius: float) -> bool:
	var limit: float = radius * radius
	for index: int in range(path.size()):
		var nearest: Vector2 = path[index]
		if follow and index > 0:
			nearest = Geometry2D.get_closest_point_to_segment(target, path[index - 1], nearest)
		if nearest.distance_squared_to(target) <= limit:
			return true
	return false


static func _reaches(path: PackedVector2Array, target: Vector2) -> bool:
	return not path.is_empty() and path[-1].distance_to(target) <= WORK_RANGE
