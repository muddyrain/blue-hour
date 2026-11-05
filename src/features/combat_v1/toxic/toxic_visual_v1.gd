class_name ToxicVisualV1
extends Node2D
## Ground-only readout. No process callback, collision body or damage authority.

const FADE_SECONDS: float = 0.28
const WARNING: Color = Color("f2d596")
const GAS: Color = Color("b3d86d")

var _state: Dictionary = ToxicV1.initial()
var _fading: Array[Dictionary] = []


func _draw() -> void:
	for key: String in _state.casters:
		var intent: Dictionary = _state.casters[key]
		if intent.phase != "windup":
			continue
		var point: Vector2 = ToxicV1._vec(intent.point)
		var progress: float = 1.0 - float(intent.remaining) / float(ToxicV1.POLICY.windup)
		var radius: float = float(ToxicV1.POLICY.radius)
		# A dashed exact-radius boundary differs from the filled live gas field.
		draw_circle(point, radius, Color(WARNING, 0.035))
		for dash: int in range(16):
			var start: float = float(dash) * TAU / 16.0
			draw_arc(point, radius, start, start + TAU / 24.0, 5, Color(WARNING, 0.85), 1.7, true)
		draw_arc(point, radius - 4.0, -PI * 0.5, -PI * 0.5 + progress * TAU, 48, WARNING, 2.0, true)
		for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var tip: Vector2 = point + direction * (radius + 3.0)
			draw_line(tip, tip + direction * 7.0, WARNING, 2.0, true)
		draw_line(point + Vector2(-5.0, 0.0), point + Vector2(5.0, 0.0), Color(WARNING, 0.8), 1.5, true)
		draw_line(point + Vector2(0.0, -5.0), point + Vector2(0.0, 5.0), Color(WARNING, 0.8), 1.5, true)
	for zone: Dictionary in _state.zones:
		_gas(ToxicV1._vec(zone.point), float(zone.age), 1.0)
	for fading: Dictionary in _fading:
		var life: float = float(fading.remaining) / FADE_SECONDS
		var point: Vector2 = ToxicV1._vec(fading.point)
		var radius: float = float(ToxicV1.POLICY.radius)
		draw_arc(point, radius * (1.0 + 0.08 * (1.0 - life)), 0.0, TAU, 64, Color(GAS, 0.6 * life), 1.3, true)
		for index: int in range(6):
			var direction: Vector2 = Vector2.RIGHT.rotated(float(index) * TAU / 6.0)
			draw_line(point + direction * radius * 0.8, point + direction * radius, Color(GAS, life * 0.3), 1.3, true)


func present(state: Dictionary) -> void:
	if not ToxicV1.problem(state).is_empty():
		return
	for old: Dictionary in _state.zones:
		if not state.zones.any(func(zone: Dictionary) -> bool: return zone.id == old.id):
			_fading.append({"point":old.point.duplicate(), "remaining":FADE_SECONDS})
	_state = state.duplicate(true)
	queue_redraw()


func advance(delta: float, active: bool = true) -> void:
	if not active or not is_finite(delta) or delta < 0.0:
		return
	for index: int in range(_fading.size() - 1, -1, -1):
		_fading[index].remaining = maxf(0.0, float(_fading[index].remaining) - delta)
		if _fading[index].remaining == 0.0:
			_fading.remove_at(index)
	queue_redraw()


func _gas(point: Vector2, age: float, opacity: float) -> void:
	var radius: float = float(ToxicV1.POLICY.radius)
	var life: float = clampf((float(ToxicV1.POLICY.lifetime) - age) / 0.35, 0.0, 1.0)
	var alpha: float = opacity * maxf(0.28, life)
	draw_circle(point, radius, Color(GAS, 0.085 * alpha))
	draw_arc(point, radius, 0.0, TAU, 64, Color(GAS, 0.65 * alpha), 1.6, true)
	# Low-opacity wisps leave roads, actor feet and other telegraphs readable.
	for index: int in range(7):
		var angle: float = float(index) * TAU / 7.0 + age * 0.22
		var offset: Vector2 = Vector2.RIGHT.rotated(angle) * (21.0 + float(index % 3) * 7.0)
		var width: float = 9.0 + float(index % 3) * 3.0
		draw_arc(point + offset, width, -0.8 + age * 0.3, 2.1 + age * 0.3, 12, Color(GAS, 0.17 * alpha), 2.4, true)
	var since_tick: float = fmod(age, float(ToxicV1.POLICY.tick_seconds))
	if age >= float(ToxicV1.POLICY.tick_seconds) and since_tick < 0.12:
		draw_arc(point, radius - 5.0 * since_tick / 0.12, 0.0, TAU, 64, Color(GAS, 0.32 * (1.0 - since_tick / 0.12)), 2.0, true)
