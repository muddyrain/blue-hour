class_name ToxicVisualV1
extends Node2D
## Ground-only readout. No process callback, collision body or damage authority.

const WARNING: Color = Color("efbe73")
const GAS: Color = Color("c5db82")
const EDGE_SHADOW: Color = Color(0.07, 0.10, 0.09, 0.76)
const DASHES: int = 16

var _state: Dictionary = ToxicV1.initial()
var _mist: GradientTexture2D = _mist_texture()


func _draw() -> void:
	var radius: float = float(ToxicV1.POLICY.radius)
	for zone: Dictionary in _state.zones:
		_gas(ToxicV1._vec(zone.point), radius, float(zone.age))
	for intent: Dictionary in _state.casters.values():
		if intent.phase == "windup":
			_warning(ToxicV1._vec(intent.point), radius, float(intent.remaining))


func present(state: Dictionary) -> void:
	if not ToxicV1.problem(state).is_empty():
		return
	_state = state.duplicate(true)
	queue_redraw()


func _warning(point: Vector2, radius: float, remaining: float) -> void:
	# Windup stays visibly open between dashes, even in its last frame.
	var charge: float = 1.0 - clampf(remaining / float(ToxicV1.POLICY.windup), 0.0, 1.0)
	var colour: Color = Color(WARNING, lerpf(0.76, 1.0, charge))
	var spacing: float = TAU / float(DASHES)
	for index: int in range(DASHES):
		var start: float = float(index) * spacing
		var end: float = start + spacing * 0.61
		draw_arc(point, radius, start, end, 6, EDGE_SHADOW, 4.8, true)
		draw_arc(point, radius, start, end, 6, colour, 2.6, true)
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
		draw_line(point - axis * 5.0, point + axis * 5.0, colour, 1.5, true)


func _gas(point: Vector2, radius: float, age: float) -> void:
	var density: float = clampf((float(ToxicV1.POLICY.lifetime) - age) / 0.42, 0.32, 1.0)
	draw_circle(point, radius, Color(GAS, 0.055 * density), true, -1.0, true)
	# Soft-edged wisps stay within the rim and follow the authoritative gas age.
	var size: Vector2 = Vector2(0.94, 0.40) * radius
	for index: int in range(5):
		var angle: float = float(index) * TAU / 5.0 + age * 0.27
		var offset: Vector2 = Vector2.from_angle(angle) * radius * (0.26 + float(index % 3) * 0.12)
		draw_set_transform(point + offset, angle + PI * 0.5)
		draw_texture_rect(_mist, Rect2(-size * 0.5, size), false, Color(GAS, 0.24 * density))
	draw_set_transform(Vector2.ZERO)
	# A live rim stays continuous until the authoritative zone retires.
	draw_arc(point, radius, 0.0, TAU, 64, EDGE_SHADOW, 4.8, true)
	draw_arc(point, radius, 0.0, TAU, 64, Color(GAS, 0.88), 2.6, true)


static func _mist_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.92), Color(1, 1, 1, 0.66), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
