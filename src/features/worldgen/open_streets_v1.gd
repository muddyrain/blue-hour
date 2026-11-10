class_name OpenStreetsV1
extends RefCounted
## Versioned arterial routes. The parked body and the swept corridors are separate.

const WIDE_VERSION: int = 1
const COMPACT_VERSION: int = 2
const DISTRICT_VERSION: int = 3
const VERSION: int = 4
const BOUNDS: Array[int] = [0, 0, 12288, 8192]
const WIDE_ARTERIAL_WIDTH: int = 480
const ARTERIAL_WIDTH: int = 224
const SIDEWALK_WIDTH: int = 32
const BOARDING_SETBACK: float = 48.0
const HALF_LENGTH: float = 120.0
const HALF_BODY_WIDTH: float = 40.0
const TURN_RADIUS: float = 192.0
const TURN_STEPS: int = 12
const SWEEP_PADDING: float = 20.0
const OUTSIDE_BUFFER: float = 320.0
const STOP_JUNCTION_GAP: float = 80.0


static func supported(version: Variant) -> bool:
	return SurvivalContracts.integer(version, WIDE_VERSION, VERSION)


static func skeleton(seed: String, topology: String, attempt: int, fallback: bool, version: int) -> Dictionary:
	var identity: String = topology + ":fallback" if fallback else seed + ":" + str(attempt)
	var random: RandomNumberGenerator = RogueLayout.rng("BH_OPEN_STREETS_V1:" + identity)
	var size: Vector2 = Vector2(BOUNDS[2], BOUNDS[3])
	var center: Vector2 = Vector2(
		_grid(size.x * random.randf_range(0.15, 0.25) if topology == "industrial"
			else size.x * random.randf_range(0.49, 0.61)),
		_grid(size.y * random.randf_range(0.32, 0.41) if topology == "residential"
			else size.y * random.randf_range(0.42, 0.55)))
	var compact: bool = version >= COMPACT_VERSION
	var width: int = ARTERIAL_WIDTH if compact else WIDE_ARTERIAL_WIDTH
	var half_road: float = width * 0.5
	var horizontal: Rect2 = Rect2(0.0, center.y - half_road, size.x, width)
	var vertical: Rect2 = Rect2(center.x - half_road, 0.0, width, size.y)
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	var leaves: Array = []
	var corners: Array[Rect2] = _corners(horizontal, vertical, bounds)
	for index: int in range(corners.size()):
		var south: bool = index >= 2
		var east: bool = index % 2 == 1
		leaves.append({"rect":_rect(corners[index]), "edges":[south, not south, east, not east]})
	var segments: Array = [
		[0, center.y, BOUNDS[2], center.y, width],
		[center.x, 0, center.x, BOUNDS[3], width],
	]
	var lane_offset: float = half_road - HALF_BODY_WIDTH - SWEEP_PADDING - (4.0 if compact else 68.0)
	var bus: Dictionary = _bus(center, topology, bounds, float(random.randi_range(20, 35) * 32),
		lane_offset, half_road, compact)
	var direction: Vector2 = (WorldLayout.point(bus.stop) - WorldLayout.point(bus.entry)).normalized()
	var sidewalk: Vector2 = Vector2(-direction.y, direction.x)
	var gather: Vector2 = WorldLayout.point(bus.door)
	var arrivals: Array = [
		_point(gather - direction * 48.0 + sidewalk * 16.0),
		_point(gather + sidewalk * 16.0),
		_point(gather + direction * 48.0 + sidewalk * 16.0),
		_point(gather + sidewalk * 56.0),
	]
	var enemy_points: Array = [[24.0, center.y - lane_offset], [size.x - 24.0, center.y + lane_offset]]
	return {"segments":segments, "leaves":leaves, "bus":bus, "arrivals":arrivals, "enemy_points":enemy_points,
		"junction":turn_junction(horizontal, vertical) if compact and topology != "commercial" else Rect2()}


static func turn_junction(horizontal: Rect2, vertical: Rect2) -> Rect2:
	return horizontal.intersection(vertical).grow(80.0)


static func boarding_paving(bus: Dictionary) -> Rect2:
	var gather: Vector2 = WorldLayout.point(bus.door)
	var outward: Vector2 = (gather - WorldLayout.point(bus.passenger_door)).normalized()
	var along: Vector2 = outward.orthogonal() * 112.0
	return _between(gather - outward * BOARDING_SETBACK - along, gather + outward * 72.0 + along)


static func swept_rects(bus: Dictionary, margin: float = 0.0) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for value: Array in bus.get("sweeps", [bus.sweep]):
		result.append(WorldLayout.rect(value).grow(margin))
	return result


static func intersects_sweep(bus: Dictionary, block: Rect2, margin: float = 0.0) -> bool:
	for value: Array in bus.get("sweeps", [bus.sweep]):
		if WorldLayout.rect(value).grow(margin).intersects(block):
			return true
	return false


static func stop_clear(bus: Dictionary, roads: Array) -> bool:
	var parked: Rect2 = WorldLayout.rect(bus.rect)
	var horizontal: bool = parked.size.x > parked.size.y
	var clear_area: Rect2 = parked.grow(STOP_JUNCTION_GAP)
	for value: Array in roads:
		var road: Rect2 = WorldLayout.rect(value)
		if (road.size.x > road.size.y) != horizontal and road.intersects(clear_area):
			return false
	return true


static func certify(data: Dictionary, blockers: Array[Rect2]) -> bool:
	# The first two roads are the continuous arterials. Subdivision only appends roads.
	var bus: Dictionary = data.bus
	var bounds: Rect2 = WorldLayout.rect(data.bounds)
	var horizontal: Rect2 = WorldLayout.rect(data.roads[0])
	var vertical: Rect2 = WorldLayout.rect(data.roads[1])
	var corners: Array[Rect2] = _corners(horizontal, vertical, bounds)
	if data.open_streets >= COMPACT_VERSION and data.topology != "commercial":
		var junction: Rect2 = turn_junction(horizontal, vertical)
		if _rect(junction) not in data.roads:
			return false
		# Clip the four inner corners against the same paved turning square.
		corners.clear()
		corners.append_array(_corners(junction, vertical, bounds))
		corners.append_array(_corners(horizontal, junction, bounds))
	var inbound: Array = bus.in_path
	var outbound: Array = bus.out_path
	if inbound.size() < 2 or outbound.size() < 2 or inbound[-1] != bus.stop or outbound[0] != bus.stop:
		return false
	if inbound[0] != bus.entry or outbound[-1] != bus.exit:
		return false
	var in_heading: Vector2 = (WorldLayout.point(inbound[-1]) - WorldLayout.point(inbound[-2])).normalized()
	var out_heading: Vector2 = (WorldLayout.point(outbound[1]) - WorldLayout.point(outbound[0])).normalized()
	if not in_heading.is_equal_approx(out_heading):
		return false
	var parked: Rect2 = WorldLayout.rect(bus.rect)
	if not bounds.encloses(parked) or not (horizontal.encloses(parked) or vertical.encloses(parked)) \
			or not stop_clear(bus, data.roads):
		return false
	if bounds.intersects(_pose_bounds(WorldLayout.point(bus.entry))) \
			or bounds.intersects(_pose_bounds(WorldLayout.point(bus.exit))):
		return false
	for path: Array in [inbound, outbound]:
		for index: int in range(1, path.size()):
			var first: Vector2 = WorldLayout.point(path[index - 1])
			var last: Vector2 = WorldLayout.point(path[index])
			var movement: Vector2 = last - first
			if movement.is_zero_approx():
				return false
			# A linear leg sweeps one elongated oriented rectangle. The padding
			# covers the heading blend between the short samples of the turn.
			var center: Vector2 = first.lerp(last, 0.5)
			var half: Vector2 = Vector2(HALF_LENGTH + movement.length() * 0.5, HALF_BODY_WIDTH)
			half += Vector2.ONE * SWEEP_PADDING
			for corner: Rect2 in corners:
				if _oriented_overlap(center, movement.normalized(), half, corner):
					return false
	var sweeps: Array[Rect2] = swept_rects(bus)
	# The boarding walk runs from the safe sidewalk to the door on this side.
	var boarding: Rect2 = _between(WorldLayout.point(bus.passenger_door), WorldLayout.point(bus.door)).grow(16.0)
	var parked_seen: bool = false
	for block: Rect2 in blockers:
		if not parked_seen and block == parked:
			parked_seen = true
			continue
		for sweep: Rect2 in sweeps:
			if block.intersects(sweep):
				return false
		if block.intersects(boarding):
			return false
	return true


static func _bus(center: Vector2, topology: String, bounds: Rect2, upstream: float,
		lane_offset: float, half_road: float, compact: bool) -> Dictionary:
	var entry: Vector2
	var stop: Vector2
	var exit: Vector2
	var approach: Vector2
	var end_turn: Vector2
	var direction: Vector2
	var facing: String
	var turn: bool = topology != "commercial"
	var radius: float = 144.0 if compact else TURN_RADIUS
	match topology:
		"industrial":
			direction = Vector2.DOWN
			facing = "down"
			var crossing: Vector2 = center - Vector2.ONE * lane_offset
			stop = crossing - Vector2(0.0, upstream)
			entry = Vector2(stop.x, -OUTSIDE_BUFFER)
			exit = Vector2(-OUTSIDE_BUFFER, crossing.y)
			approach = crossing - Vector2(0.0, radius)
			end_turn = crossing - Vector2(radius, 0.0)
		"residential":
			direction = Vector2.LEFT
			facing = "left"
			var crossing: Vector2 = center + Vector2(lane_offset, -lane_offset)
			stop = crossing + Vector2(upstream, 0.0)
			entry = Vector2(bounds.end.x + OUTSIDE_BUFFER, stop.y)
			exit = Vector2(crossing.x, -OUTSIDE_BUFFER)
			approach = crossing + Vector2(radius, 0.0)
			end_turn = crossing - Vector2(0.0, radius)
		_:
			direction = Vector2.RIGHT
			facing = "right"
			stop = Vector2(center.x - upstream, center.y + lane_offset)
			entry = Vector2(-OUTSIDE_BUFFER, stop.y)
			exit = Vector2(bounds.end.x + OUTSIDE_BUFFER, stop.y)
	var parked_half: Vector2 = Vector2(HALF_LENGTH, HALF_BODY_WIDTH) if direction.y == 0.0 \
		else Vector2(HALF_BODY_WIDTH, HALF_LENGTH)
	var parked: Rect2 = Rect2(stop - parked_half, parked_half * 2.0)
	var sidewalk: Vector2 = Vector2(-direction.y, direction.x)
	var door_center: Vector2 = stop + direction * 72.0
	var passenger_door: Vector2 = door_center + sidewalk * HALF_BODY_WIDTH
	var gather: Vector2 = door_center + sidewalk * (half_road - lane_offset + (BOARDING_SETBACK if compact else 72.0))
	var inbound: Array = [_point(entry), _point(stop)]
	var outbound: Array = [_point(stop)]
	var sweeps: Array = []
	if turn:
		outbound.append(_point(approach))
		var circle_center: Vector2 = Vector2(end_turn.x, approach.y) if direction.y != 0.0 \
			else Vector2(approach.x, end_turn.y)
		var radial: Vector2 = approach - circle_center
		for step: int in range(1, TURN_STEPS):
			var angle: float = PI * 0.5 * float(step) / TURN_STEPS
			outbound.append(_point((circle_center + radial.rotated(angle)).round()))
		outbound.append(_point(end_turn))
		sweeps.append(_rect(_straight_sweep(entry, approach, direction).intersection(bounds)))
		sweeps.append(_rect(_between(approach, end_turn).grow(Vector2(HALF_LENGTH, HALF_BODY_WIDTH).length()
			+ SWEEP_PADDING).intersection(bounds)))
		sweeps.append(_rect(_straight_sweep(end_turn, exit, (exit - end_turn).normalized()).intersection(bounds)))
	else:
		sweeps.append(_rect(_straight_sweep(entry, exit, direction).intersection(bounds)))
	outbound.append(_point(exit))
	return {"rect":_rect(parked), "door":_point(gather), "passenger_door":_point(passenger_door),
		"entry":_point(entry), "exit":_point(exit), "facing":facing, "sweep":_rect(parked),
		"stop":_point(stop), "in_path":inbound, "out_path":outbound, "sweeps":sweeps}


static func _corners(horizontal: Rect2, vertical: Rect2, bounds: Rect2) -> Array[Rect2]:
	var west: float = vertical.position.x - bounds.position.x
	var east: float = bounds.end.x - vertical.end.x
	var north: float = horizontal.position.y - bounds.position.y
	var south: float = bounds.end.y - horizontal.end.y
	return [
		Rect2(bounds.position, Vector2(west, north)),
		Rect2(vertical.end.x, bounds.position.y, east, north),
		Rect2(bounds.position.x, horizontal.end.y, west, south),
		Rect2(vertical.end.x, horizontal.end.y, east, south),
	]


static func _straight_sweep(a: Vector2, b: Vector2, direction: Vector2) -> Rect2:
	var half: Vector2 = Vector2(HALF_LENGTH, HALF_BODY_WIDTH) if direction.y == 0.0 \
		else Vector2(HALF_BODY_WIDTH, HALF_LENGTH)
	var margin: Vector2 = half + Vector2.ONE * SWEEP_PADDING
	var span: Rect2 = _between(a, b)
	return Rect2(span.position - margin, span.size + margin * 2.0)


static func _oriented_overlap(center: Vector2, axis: Vector2, half: Vector2, block: Rect2) -> bool:
	var side: Vector2 = Vector2(-axis.y, axis.x)
	var delta: Vector2 = block.get_center() - center
	var block_half: Vector2 = block.size * 0.5
	var body_aabb: Vector2 = axis.abs() * half.x + side.abs() * half.y
	if absf(delta.x) >= block_half.x + body_aabb.x or absf(delta.y) >= block_half.y + body_aabb.y:
		return false
	return absf(delta.dot(axis)) < half.x + block_half.dot(axis.abs()) \
		and absf(delta.dot(side)) < half.y + block_half.dot(side.abs())


static func _pose_bounds(point: Vector2) -> Rect2:
	return Rect2(point - Vector2.ONE * HALF_LENGTH, Vector2.ONE * (2.0 * HALF_LENGTH))


static func _between(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(a.min(b), (b - a).abs())


static func _point(value: Vector2) -> Array:
	return [value.x, value.y]


static func _rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


static func _grid(value: float) -> float:
	return roundf(value / 32.0) * 32.0
