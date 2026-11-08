class_name ExplorationLayout
extends RefCounted
## PROJECT_TEMP V1. Frozen geometry and read-only route certificates; no world state owner.

const POLICY_ID: String = "BH_EXPLORATION_V1"
const VERSION: int = 4
const PREFIX: String = "explore_v1_"
const SIZES: Dictionary = {
	"small":{"bounds":[0, 0, 2560, 1920], "columns":4, "rows":3, "buildings":12, "optional_buildings":2, "vehicles":2, "fruit_trees":1},
	"medium":{"bounds":[0, 0, 3584, 2688], "columns":5, "rows":4, "buildings":20, "optional_buildings":3, "vehicles":3, "fruit_trees":2},
	"large":{"bounds":[0, 0, 4608, 3456], "columns":6, "rows":5, "buildings":30, "optional_buildings":4, "vehicles":4, "fruit_trees":3},
}
const KEYS: Array[String] = ["version", "seed", "size", "topology", "attempt", "fallback", "bounds", "entities", "roads", "barriers", "gates", "bus", "arrivals", "enemy_points", "rescue", "id", "objects"]
const MAX_CACHE: int = 48
static var _built: Dictionary = {}
static var _checked: Dictionary = {}
static var _certificates: Dictionary = {}


static func policy() -> Dictionary:
	return {"policy_id":POLICY_ID, "version":1, "status":"PROJECT_TEMP", "sizes":SIZES.duplicate(true),
		"near_max_fraction":0.35, "middle_max_fraction":0.65, "base_walk_speed":125.0,
		"attempts":3, "fallback":"same_size_same_topology", "object_los":false,
		"vehicle_collision":{"sedan":[128, 32], "van":[140, 40]}, "tree_trunk":[14, 14],
		"clearance":{"sweep":32, "bus":40, "gather":112, "junction":28, "gate":56, "door":28}}


static func is_map_id(value: Variant) -> bool:
	return value is String and value.length() == PREFIX.length() + 32 and value.begins_with(PREFIX) and value.substr(PREFIX.length()).is_valid_hex_number(false)


static func generate(seed: String, size: String, topology: String) -> Dictionary:
	if seed.is_empty() or seed.length() > 128 or not SIZES.has(size) or topology not in NeighborhoodLayout.TOPOLOGIES:
		return {}
	for attempt: int in range(3):
		var value: Dictionary = _assemble(seed, size, topology, attempt, false)
		if not value.is_empty():
			return value
	return _assemble(seed, size, topology, 0, true)


static func validate(value: Variant, cached: bool = true) -> String:
	if value is Dictionary and value.get("version")==5: return WorldgenLayout.validate(value,cached)
	if not value is Dictionary or value.size() != KEYS.size() or not value.has_all(KEYS) or not SurvivalContracts.json_value(value):
		return "EXPLORATION_LAYOUT_FIELDS"
	if not SurvivalContracts.integer(value.version, VERSION, VERSION) or not value.seed is String or value.seed.is_empty() or value.seed.length() > 128 or not value["size"] is String or not SIZES.has(value["size"]) or not value.topology is String or value.topology not in NeighborhoodLayout.TOPOLOGIES or not SurvivalContracts.integer(value.attempt, 0, 2) or not value.fallback is bool or not is_map_id(value.id):
		return "EXPLORATION_LAYOUT_IDENTITY"
	var signature: String = RecordEncoding.fingerprint(value)
	if cached and _checked.has(signature):
		return ""
	var expected: Dictionary = _assemble(value.seed, value["size"], value.topology, int(value.attempt), value.fallback)
	if expected.is_empty() or RecordEncoding.fingerprint(expected) != signature:
		return "EXPLORATION_LAYOUT_CANONICAL"
	_checked[signature] = true
	return ""


static func resource(data: Dictionary) -> StreetLayout:
	return NeighborhoodLayout.resource(data) if validate(data).is_empty() else null


static func _assemble(seed: String, size: String, topology: String, attempt: int, fallback: bool) -> Dictionary:
	var data: Dictionary = NeighborhoodLayout._assemble(seed, size, topology, attempt, fallback, true)
	data.objects = []
	return complete(data)


static func complete(data: Dictionary) -> Dictionary:
	var size: String = data["size"]
	# Complete original geometry and policy form the cache identity, including all collisions.
	var origin_key: String = RecordEncoding.fingerprint({"geometry":data, "policy":policy()})
	if _built.has(origin_key):
		var prior: Dictionary = _built[origin_key]
		if _certificates.has(RecordEncoding.fingerprint(prior)):
			return prior.duplicate(true)
	if not _geometry_problem(data).is_empty():
		return {}
	var street: StreetLayout = NeighborhoodLayout.resource(data)
	var base_nav: FieldNavigation = FieldNavigation.new()
	base_nav.configure(street.blockers(), street.world_bounds)
	var before: Dictionary = _door_routes(data, base_nav)
	if before.is_empty():
		return {}
	var reserved: Array[Rect2] = _reserved(data)
	var occupied: Array[String] = []
	for kind: String in ["vehicle", "fruit_tree"]:
		var count: int = int(SIZES[size].vehicles if kind == "vehicle" else SIZES[size].fruit_trees)
		for index: int in range(count):
			var object: Dictionary = _place_object(data, kind, index, base_nav, street.blockers(), reserved, occupied, before)
			if object.is_empty():
				return {}
			occupied.append(object.anchor)
			object.erase("anchor")
			data.objects.append(object)
	# Only one final graph after all prop collisions have been selected.
	street = NeighborhoodLayout.resource(data)
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(street.blockers(), street.world_bounds)
	var certificate: Dictionary = _door_routes(data, nav)
	if certificate.is_empty() or not _all_routes(data, nav):
		return {}
	if data.version==5 and not WorldgenLayout.content_reachable(data,certificate):
		return {}
	if data.has("loading_yard") and not IndustrialYard.certified(data, nav):
		return {}
	data.enemy_points = _spawn_points(data, nav)
	if data.enemy_points.size() < data.entities.size():
		return {}
	data.erase("id")
	data.id = (WorldgenLayout.PREFIX if data.version==5 else PREFIX) + RecordEncoding.fingerprint(data).substr(0, 32)
	var signature: String = RecordEncoding.fingerprint(data)
	if _certificates.size() >= MAX_CACHE:
		_certificates.clear()
		_checked.clear()
		_built.clear()
	certificate.nav = nav
	_certificates[signature] = certificate
	_checked[signature] = true
	_built[origin_key] = data.duplicate(true)
	return data


static func _geometry_problem(data: Dictionary) -> String:
	var bounds: Rect2 = WorldLayout.rect(data.bounds)
	if (data.version==4 and data.entities.size() != SIZES[data["size"]].buildings) or not TransactionReceipt.same({"v":data.bounds}, {"v":SIZES[data["size"]].bounds}):
		return "EXPLORATION_DIMENSIONS"
	var blocks: Array[Rect2] = []
	var sweep: Rect2 = WorldLayout.rect(data.bus.sweep)
	for entity: Dictionary in data.entities:
		var block: Rect2 = WorldLayout.rect(entity.rect)
		if not bounds.encloses(block) or block.intersects(sweep):
			return "EXPLORATION_BUILDING_BOUNDS"
		for other: Rect2 in blocks:
			if block.grow(12.0).intersects(other):
				return "EXPLORATION_BUILDING_OVERLAP"
		blocks.append(block)
	for road: Array in data.roads:
		var area: Rect2 = WorldLayout.rect(road)
		if not bounds.encloses(area) or area.size.x <= 0.0 or area.size.y <= 0.0:
			return "EXPLORATION_ROAD_BOUNDS"
		for block: Rect2 in blocks:
			if area.intersects(block):
				return "EXPLORATION_ROAD_BUILDING"
	for wall: Array in data.barriers:
		var barrier: Rect2 = WorldLayout.rect(wall)
		if not bounds.encloses(barrier) or barrier.intersects(sweep):
			return "EXPLORATION_WALL_BOUNDS"
		for block: Rect2 in blocks:
			if barrier.grow(12.0).intersects(block):
				return "EXPLORATION_WALL_BUILDING"
	return ""


static func _reserved(data: Dictionary) -> Array[Rect2]:
	var zones: Array[Rect2] = [WorldLayout.rect(data.bus.sweep).grow(32.0), WorldLayout.rect(data.bus.rect).grow(40.0)]
	for value: Array in [data.bus.door, data.bus.passenger_door]:
		zones.append(Rect2(WorldLayout.point(value) - Vector2(112, 112), Vector2(224, 224)))
	for value: Array in data.arrivals:
		zones.append(Rect2(WorldLayout.point(value) - Vector2(40, 40), Vector2(80, 80)))
	for value: Array in data.gates:
		zones.append(Rect2(WorldLayout.point(value) - Vector2(56, 56), Vector2(112, 112)))
	if data.has("loading_yard"):
		zones.append_array(IndustrialYard.reserved_rects(data))
	if data.version==5:
		for parcel: Dictionary in data.parcels:
			zones.append(Rect2(WorldLayout.point(parcel.entrance)-Vector2(44,44),Vector2(88,88)))
			for court: Dictionary in parcel.courtyards:
				zones.append(Rect2(WorldLayout.point(court.entrance)-Vector2(36,36),Vector2(72,72)))
	for entity: Dictionary in data.entities:
		zones.append(Rect2(WorldLayout.point(entity.door) - Vector2(28, 28), Vector2(56, 56)))
	zones.append(Rect2(WorldLayout.point(data.rescue) - Vector2(52, 52), Vector2(104, 104)))
	for first: Array in data.roads:
		var a: Rect2 = WorldLayout.rect(first)
		for second: Array in data.roads:
			var b: Rect2 = WorldLayout.rect(second)
			if (a.size.x > a.size.y) == (b.size.x > b.size.y) or not a.intersects(b):
				continue
			zones.append(a.intersection(b).grow(28.0))
	return zones


static func _place_object(data: Dictionary, kind: String, index: int, nav: FieldNavigation, blocks: Array[Rect2], reserved: Array[Rect2], occupied: Array[String], routes: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var targets: Array[float] = []
	targets.assign([0.20, 0.90, 0.50, 0.85] if kind == "vehicle" else [0.85, 0.50, 0.20])
	for entity: Dictionary in data.entities:
		if entity.id in occupied:
			continue
		for side: int in [-1, 1]:
			var point: Vector2 = WorldLayout.point(entity.door) + Vector2(side * (144 if kind == "vehicle" else 200), 24)
			var variant: String = ("sedan" if index % 2 == 0 else "van") if kind == "vehicle" else "apple_tree"
			var dimensions: Vector2 = Vector2(128, 32) if variant == "sedan" else Vector2(140, 40) if variant == "van" else Vector2(14, 14)
			var collision: Rect2 = Rect2(point - Vector2(dimensions.x * 0.5, dimensions.y - 4.0), dimensions)
			var work: Vector2 = point + Vector2(side * (112 if kind == "vehicle" else 40), 0)
			if not _object_clear(data, collision, work, nav, blocks, reserved):
				continue
			var object: Dictionary = {"id":("vehicle_%02d" if kind == "vehicle" else "tree_%02d") % (index + 1),
				"kind":kind, "variant":variant, "point":[point.x, point.y],
				"collision":[collision.position.x, collision.position.y, collision.size.x, collision.size.y], "work_point":[work.x, work.y]}
			var rank: String = (POLICY_ID + "|props|" + data.seed + "|" + object.id + "|" + entity.id + "|" + str(side)).sha256_text()
			candidates.append({"object":object, "anchor":entity.id, "rank":rank,
				"score":absf(float(routes.doors[entity.id].length) / float(routes.dmax) - targets[index])})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score if a.score != b.score else a.rank < b.rank)
	var result: Dictionary = candidates[0].object
	result.anchor = candidates[0].anchor
	return result


static func _object_clear(data: Dictionary, collision: Rect2, work: Vector2, nav: FieldNavigation, blocks: Array[Rect2], reserved: Array[Rect2]) -> bool:
	if not WorldLayout.rect(data.bounds).encloses(collision.grow(20.0)) or not nav.is_clear(work) or collision.grow(24.0).has_point(work):
		return false
	for block: Rect2 in blocks:
		if collision.grow(20.0).intersects(block):
			return false
	for zone: Rect2 in reserved:
		if collision.grow(16.0).intersects(zone) or zone.has_point(work):
			return false
	for object: Dictionary in data.objects:
		var prior: Rect2 = WorldLayout.rect(object.collision)
		if collision.grow(32.0).intersects(prior) or collision.grow(28.0).has_point(WorldLayout.point(object.work_point)) or prior.grow(28.0).has_point(work):
			return false
	return true


static func _door_routes(data: Dictionary, nav: FieldNavigation) -> Dictionary:
	var start: Vector2 = WorldLayout.point(data.bus.door)
	if not nav.is_clear(start):
		return {}
	var doors: Dictionary = {}
	var dmax: float = 0.0
	for entity: Dictionary in data.entities:
		var target: Vector2 = WorldLayout.point(entity.door)
		var path: PackedVector2Array = nav.path_between(start, target) if nav.is_clear(target) else PackedVector2Array()
		if path.is_empty() or path[-1].distance_to(target) > 14.0:
			return {}
		var length: float = _length(path)
		doors[entity.id] = {"point":entity.door.duplicate(), "length":length}
		dmax = maxf(dmax, length)
	return {"dmax":dmax, "doors":doors} if dmax > 0.0 else {}


static func _all_routes(data: Dictionary, nav: FieldNavigation) -> bool:
	var start: Vector2 = WorldLayout.point(data.bus.door)
	var goals: Array = data.arrivals.duplicate(true)
	goals.append(data.rescue)
	if data.version==5:
		for parcel: Dictionary in data.parcels:
			goals.append(parcel.entrance)
			for court: Dictionary in parcel.courtyards:goals.append(court.entrance)
	goals.append_array(data.enemy_points)
	for object: Dictionary in data.objects:
		goals.append(object.work_point)
	for x: float in [-48.0, 0.0, 48.0]:
		for y: float in [-48.0, 0.0, 48.0]:
			goals.append([start.x + x, start.y + y])
	for point: Array in goals:
		var target: Vector2 = WorldLayout.point(point)
		if not nav.is_clear(target):
			return false
		var path: PackedVector2Array = nav.path_between(start, target)
		if path.is_empty() or path[-1].distance_to(target) > 14.0:
			return false
	return true


static func _spawn_points(data: Dictionary, nav: FieldNavigation) -> Array:
	var result: Array = data.enemy_points.duplicate(true)
	for entity: Dictionary in data.entities:
		var point: Array = entity.door.duplicate()
		if point not in result and nav.is_clear(WorldLayout.point(point)):
			result.append(point)
	return result


static func _length(path: PackedVector2Array) -> float:
	var result: float = 0.0
	for index: int in range(1, path.size()):
		result += path[index - 1].distance_to(path[index])
	return result


static func _routing(data: Dictionary) -> Dictionary:
	# Shared navigation is read-only: never configure or mutate this graph in a caller.
	if not validate(data).is_empty():
		return {}
	var value: Dictionary = _certificates[RecordEncoding.fingerprint(data)]
	return {"nav":value.nav, "dmax":value.dmax, "doors":value.doors.duplicate(true)}
