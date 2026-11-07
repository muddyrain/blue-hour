class_name PumpCharge
extends RefCounted
## PROJECT_TEMP. The locked rectangle is the warning and the damage footprint.

const DAMAGE: float = 38.0
const WINDUP: float = 1.5
const RANGE: float = 286.0
const HALF_WIDTH: float = 24.0
const COOLDOWN: float = 5.5
const RECOVERY: float = 0.65
const WALL_CLEARANCE: float = 20.0


static func initial() -> Dictionary:
	return {}


static func arm(from: Vector2, target: Vector2, walls: Array[Rect2]) -> Dictionary:
	var direction: Vector2 = (target - from).normalized()
	if not direction.is_finite() or direction == Vector2.ZERO:
		return initial()
	var side: Vector2 = direction.orthogonal()
	var first_wall: float = INF
	for wall: Rect2 in walls:
		first_wall = minf(first_wall, _first_wall_face(wall, from, direction, side))
	var travel: float = minf(RANGE, first_wall - WALL_CLEARANCE)
	if travel <= 1.0:
		return initial()
	return {"from": _pair(from), "target": _pair(target), "to": _pair(from + direction * travel)}


static func hit(state: Dictionary, point: Vector2) -> bool:
	if state.is_empty():
		return false
	var from: Vector2 = _vector(state.from)
	var direction: Vector2 = (_vector(state.target) - from).normalized()
	var delta: Vector2 = point - from
	var along: float = delta.dot(direction)
	return along >= 0.0 and along <= (_vector(state.to) - from).dot(direction) \
		and absf(delta.dot(direction.orthogonal())) <= HALF_WIDTH


static func problem(state: Variant, walls: Array[Rect2]) -> String:
	if not state is Dictionary:
		return "PUMP_CHARGE_FIELDS"
	if state.is_empty():
		return ""
	if state.size() != 3 or not state.has_all(["from", "target", "to"]):
		return "PUMP_CHARGE_FIELDS"
	for key: String in ["from", "target", "to"]:
		if not _valid_pair(state[key]):
			return "PUMP_CHARGE_POINT"
	var expected: Dictionary = arm(_vector(state.from), _vector(state.target), walls)
	if expected.is_empty() or RecordEncoding.fingerprint(expected) != RecordEncoding.fingerprint(state):
		return "PUMP_CHARGE_GEOMETRY"
	return ""


static func draw_warning(canvas: CanvasItem, state: Dictionary, offset: Vector2 = Vector2.ZERO) -> void:
	if state.is_empty():
		return
	var from: Vector2 = _vector(state.from) + offset
	var to: Vector2 = _vector(state.to) + offset
	var direction: Vector2 = (_vector(state.target) - _vector(state.from)).normalized()
	var side: Vector2 = direction.orthogonal() * HALF_WIDTH
	var boundary: PackedVector2Array = PackedVector2Array([from + side, to + side, to - side, from - side])
	canvas.draw_colored_polygon(boundary, Color(0.87, 0.17, 0.07, 0.24))
	for index: int in range(boundary.size()):
		canvas.draw_dashed_line(boundary[index], boundary[(index + 1) % boundary.size()], Color("ff9058"), 3.0, 12.0)
	var tip: Vector2 = from.lerp(to, 0.62)
	var tail: Vector2 = tip - direction * minf(16.0, from.distance_to(to) * 0.4)
	var chevron: PackedVector2Array = PackedVector2Array([tail + side * 0.47, tip, tail - side * 0.47])
	canvas.draw_polyline(chevron, Color("ffdfa3"), 3.0, true)


static func _first_wall_face(wall: Rect2, from: Vector2, direction: Vector2, side: Vector2) -> float:
	# Clip the real wall edges to the sweep's two parallel sides. The least
	# forward coordinate of that intersection is the first blocked cross-section.
	var corners: PackedVector2Array = PackedVector2Array([
		wall.position, Vector2(wall.end.x, wall.position.y), wall.end, Vector2(wall.position.x, wall.end.y),
	])
	var near: float = INF
	var far: float = -INF
	for index: int in range(corners.size()):
		var a: Vector2 = corners[index] - from
		var b: Vector2 = corners[(index + 1) % corners.size()] - from
		var cross_a: float = a.dot(side)
		var cross_delta: float = b.dot(side) - cross_a
		var enter: float = 0.0
		var leave: float = 1.0
		if is_zero_approx(cross_delta):
			if absf(cross_a) > HALF_WIDTH:
				continue
		else:
			var lower: float = (-HALF_WIDTH - cross_a) / cross_delta
			var upper: float = (HALF_WIDTH - cross_a) / cross_delta
			enter = maxf(0.0, minf(lower, upper))
			leave = minf(1.0, maxf(lower, upper))
			if enter > leave:
				continue
		var x_a: float = a.dot(direction)
		var x_b: float = b.dot(direction)
		var entry: float = lerpf(x_a, x_b, enter)
		var exit: float = lerpf(x_a, x_b, leave)
		near = minf(near, minf(entry, exit))
		far = maxf(far, maxf(entry, exit))
	return maxf(near, 0.0) if far >= 0.0 else INF


static func _pair(point: Vector2) -> Array:
	return [float(point.x), float(point.y)]


static func _vector(point: Array) -> Vector2:
	return Vector2(float(point[0]), float(point[1]))


static func _valid_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and SurvivalContracts.number(value[0]) \
		and SurvivalContracts.number(value[1]) and _vector(value).is_finite()
