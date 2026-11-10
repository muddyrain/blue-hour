class_name BillboardActionV1
extends RefCounted
## PROJECT_TEMP. Certifies a roadside work point and the next day's real supermarket.

const VERSION: int = 1
const SLOT: int = 2
const SITE_ID: String = "billboard"
const DESTINATION: String = "supermarket"
const SECONDS: float = 4.0
const WORK_RANGE: float = 14.0
const MAX_ROUTES: int = 32
const TARGET_CACHE_SIZE: int = 12
const TARGET_SIZES: Array[String] = ["medium", "large"]
const TARGET_TOPOLOGIES: Array[String] = ["commercial", "residential"]

static var _targets: Dictionary[String, Dictionary] = {}


static func action_id(seed: String, day: int, slot: int) -> String:
	var original: String = ("daily-v4:%s:%d:%d" % [seed, day, slot]).sha256_text()
	return ("billboard-target-v1:" + original).sha256_text() if slot == SLOT else original


static func board_id(source_id: String) -> String:
	return "billboard_" + ("billboard-v1:" + source_id).sha256_text()


static func enabled(action: Dictionary) -> bool:
	var marker: Variant = action.get("billboard")
	if not _eligible(action) or not marker is Dictionary or marker.size() != 5 \
			or not marker.has_all(["version", "id", "point", "destination", "target"]):
		return false
	var anchor: Variant = marker.point
	return SurvivalContracts.integer(marker.version, VERSION, VERSION) \
		and marker.id is String and marker.id == board_id(action.id) \
		and marker.destination is String and marker.destination == DESTINATION \
		and anchor is Array and anchor.size() == 2 and SurvivalContracts.number(anchor[0]) and SurvivalContracts.number(anchor[1]) \
		and _strategy_valid(marker.target, int(action.day) + 1)


static func point(action: Dictionary) -> Vector2:
	return WorldLayout.point(action.billboard.point) if enabled(action) else Vector2.INF


static func face_rect(anchor: Vector2) -> Rect2:
	return Rect2(anchor + Vector2(-51, -86), Vector2(102, 47))


static func hit_rect(anchor: Vector2) -> Rect2:
	return Rect2(anchor + Vector2(-54, -89), Vector2(108, 103))


static func target(seed: String, day: int) -> Dictionary:
	return _certificate(seed, day).get("strategy", {}).duplicate(true)


static func target_map(seed: String, day: int, strategy: Dictionary) -> Dictionary:
	if not _strategy_valid(strategy, day):
		return {}
	var certified: Dictionary = _certificate(seed, day)
	if certified.is_empty() or not TransactionReceipt.same(certified.strategy, strategy):
		return {}
	return certified.map.duplicate(true)


static func target_offer(seed: String, day: int, context: Dictionary, strategy: Dictionary) -> Dictionary:
	if not _strategy_valid(strategy, day):
		return {}
	var task: Dictionary = TaskActions._make(seed, day, SLOT, "supply", strategy.topology, strategy["size"], 0)
	var source: Dictionary = ExplorationActions.source_from_task(task, context)
	return ExplorationActions.upgrade(source, true, true, 1, false, false, 0, strategy) if not source.is_empty() else {}


static func freeze(action: Dictionary) -> Dictionary:
	if not _eligible(action):
		return action
	var layout: Dictionary = action.layout
	var proof: Dictionary = ValueProofCache.lookup("billboard-anchor", {"layout":layout, "sites":action.sites,
		"barricade":action.get("barricade", {})})
	var anchor: Dictionary = proof.result if proof.hit else _certify_point(action)
	ValueProofCache.remember(proof, anchor)
	if anchor.is_empty():
		return action
	var strategy: Dictionary = target(action.seed, int(action.day) + 1)
	if strategy.is_empty():
		return action
	var result: Dictionary = action.duplicate(false)
	result.billboard = {"version":VERSION, "id":board_id(action.id), "point":anchor.point,
		"destination":DESTINATION, "target":strategy}
	return result


static func _eligible(action: Dictionary) -> bool:
	var layout: Variant = action.get("layout")
	var campaign: Variant = action.get("campaign")
	return SurvivalContracts.integer(action.get("version"), 9, 9) and SurvivalContracts.integer(action.get("mission_policy"), 1, 1) \
		and action.get("type") is String and action.type == "supply" \
		and SurvivalContracts.integer(action.get("day"), 3, RunSave.MAX_COUNTER - 1) \
		and action.get("id") is String and action.get("seed") is String \
		and SurvivalContracts.integer(action.get("slot"), 0, SLOT) \
		and (action.slot == 0 or (action.slot == SLOT and action.has("billboard_target"))) \
		and not action.has("rare_policy") and not action.has("event_sortie") and not action.has("investigation") \
		and campaign is Dictionary and campaign.get("is_finale") is bool and not campaign.is_finale \
		and layout is Dictionary and SurvivalContracts.integer(layout.get("version"), 5, 5) and layout.get("size") in ["medium", "large"]


static func _strategy_valid(value: Variant, day: int) -> bool:
	return value is Dictionary and value.size() == 7 \
		and value.has_all(["version", "day", "slot", "destination", "size", "topology", "layout_id"]) \
		and SurvivalContracts.integer(value.version, VERSION, VERSION) \
		and SurvivalContracts.integer(value.day, day, day) and SurvivalContracts.integer(value.slot, SLOT, SLOT) \
		and value.destination is String and value.destination == DESTINATION \
		and value["size"] in TARGET_SIZES and value.topology in TARGET_TOPOLOGIES \
		and WorldgenLayout.is_map_id(value.layout_id)


static func _certificate(seed: String, day: int) -> Dictionary:
	if day < 4 or day > RunSave.MAX_COUNTER or seed.length() != 32 \
			or seed != seed.to_lower() or not seed.is_valid_hex_number(false):
		return {}
	var id: String = action_id(seed, day, SLOT)
	var cached: Variant = ActionMemo.lookup(_targets, id)
	if cached != null:
		return cached
	var certified: Dictionary = _certify_target(seed, day, id)
	ActionMemo.store(_targets, id, certified, TARGET_CACHE_SIZE, true)
	return certified


static func _certify_target(seed: String, day: int, id: String) -> Dictionary:
	for topology: String in TARGET_TOPOLOGIES:
		for size: String in TARGET_SIZES:
			var task: Dictionary = TaskActions._make(seed, day, SLOT, "supply", topology, size, 0)
			if task.is_empty():
				continue
			var map: Dictionary = ExplorationActions.level_map(task, id, 1, false, false, 0, true)
			if not map.is_empty():
				return {"strategy":{"version":VERSION, "day":day, "slot":SLOT, "destination":DESTINATION,
					"size":size, "topology":topology, "layout_id":map.layout.id}, "map":map}
	return {}


static func is_supermarket(layout: Dictionary, sites: Array) -> bool:
	for site: Dictionary in sites:
		if site.id != "food":
			continue
		for entity: Dictionary in layout.entities:
			if entity.id == site.building:
				return entity.archetype == DESTINATION
	return false


static func _certify_point(action: Dictionary) -> Dictionary:
	var layout: Dictionary = action.layout
	var routing: Dictionary = ExplorationLayout._routing(layout)
	if routing.is_empty():
		return {}
	var nav: FieldNavigation = BarricadeV1.navigation(action, false) if BarricadeV1.enabled(action) else routing.nav
	var bus: Vector2 = WorldLayout.point(layout.bus.door)
	var starts: PackedVector2Array = PackedVector2Array([bus])
	for arrival: Array in layout.arrivals:
		starts.append(WorldLayout.point(arrival))
	for start: Vector2 in starts:
		if not nav.is_clear(start):
			return {}
	var occupied: Array[Rect2] = ExplorationLayout._reserved(layout)
	occupied.append_array(nav.obstacles)
	for entity: Dictionary in layout.entities:
		var facade: Rect2 = WorldgenScale.visible_rect(entity)
		var art: Dictionary = StreetModuleArt.definition(entity.get("art", ""))
		if not art.is_empty():
			# The calibrated frame can overhang the measured building body.
			var scale: float = facade.size.x / float(art.reference_width)
			var foot: Vector2 = Vector2(facade.get_center().x, facade.end.y)
			facade = Rect2(foot - Vector2(art.origin) * scale, Vector2(art.native_size) * scale)
		occupied.append(facade.grow(12.0))
		var door: Vector2 = WorldLayout.point(entity.door)
		var base: Rect2 = WorldLayout.rect(entity.rect)
		occupied.append(Rect2(Vector2(door.x - 28.0, base.end.y), Vector2(56, 64)))
	for object: Dictionary in layout.objects:
		var origin: Vector2 = WorldLayout.point(object.point)
		occupied.append(Rect2(origin + Vector2(-80, -180), Vector2(160, 192))
			if object.kind == "fruit_tree" else Rect2(origin + Vector2(-80, -96), Vector2(160, 108)))
	for site: Dictionary in action.sites:
		var entrance: Vector2 = TaskActions.site_point(action, site)
		occupied.append(Rect2(entrance - Vector2(36, 36), Vector2(72, 72)))
	var candidates: Array[Vector2] = _roadside_points(layout, nav, occupied, bus)
	for index: int in range(mini(candidates.size(), MAX_ROUTES)):
		var anchor: Vector2 = candidates[index]
		var connected: bool = true
		for start: Vector2 in starts:
			var route: PackedVector2Array = nav.path_between(start, anchor)
			if route.is_empty() or route[-1].distance_to(anchor) > WORK_RANGE:
				connected = false
				break
		if connected:
			return {"point":[int(anchor.x), int(anchor.y)]}
	return {}


static func _roadside_points(layout: Dictionary, nav: FieldNavigation, occupied: Array[Rect2],
		bus: Vector2) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	for row: Array in layout.roads:
		var road: Rect2 = WorldLayout.rect(row)
		var axis: int = 0 if road.size.x > road.size.y else 1
		for side: float in [road.position[1 - axis] + 28.0, road.end[1 - axis] - 28.0]:
			for distance: int in range(64, int(road.size[axis]) - 64, 96):
				var point_on_edge: Vector2 = Vector2.ZERO
				point_on_edge[axis] = road.position[axis] + distance
				point_on_edge[1 - axis] = side
				var anchor: Vector2 = BarricadeV1._grid_center(nav, point_on_edge)
				if anchor in candidates or not road.has_point(anchor) or not nav.is_clear(anchor):
					continue
				var hit: Rect2 = hit_rect(anchor)
				if nav.bounds.encloses(hit) and not occupied.any(func(area: Rect2) -> bool: return area.intersects(hit)):
					candidates.append(anchor)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var first: float = a.distance_squared_to(bus)
		var second: float = b.distance_squared_to(bus)
		return first < second if first != second else a.y < b.y if a.y != b.y else a.x < b.x)
	return candidates
