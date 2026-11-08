class_name BasicSupportAim
extends Node2D
## Read-only range and impact display; the owner supplies every simulation delta.

const IMPACT_SECONDS: float = 0.85
const READY_COLOR: Color = Color("80ddd8")
const BLOCKED_COLOR: Color = Color("ffaca7")
const IMPACT_EDGE: Color = Color("ffc573")
const IMPACT_CORE: Color = Color("fff0c0")

var _aiming: bool = false
var _legal: bool = false
var _point: Vector2 = Vector2.ZERO
var _radius: float = 90.0
var _caller: Vector2 = Vector2.ZERO
var _caller_visible: bool = false
var _impact_point: Vector2 = Vector2.ZERO
var _impact_radius: float = 90.0
var _impact_remaining: float = 0.0


func _draw() -> void:
	if _aiming:
		var colour: Color = READY_COLOR if _legal else BLOCKED_COLOR
		if _caller_visible:
			draw_arc(_caller, BasicSupport.POLICY.airstrike_range, 0.0, TAU, 96, Color(colour, 0.25), 1.0, true)
			draw_line(_caller, _point, Color(colour, 0.45), 1.0, true)
		draw_circle(_point, _radius, Color(colour, 0.12))
		draw_arc(_point, _radius, 0.0, TAU, 64, colour, 2.0, true)
		draw_line(_point + Vector2(-9, 0), _point + Vector2(9, 0), colour, 2.0, true)
		draw_line(_point + Vector2(0, -9), _point + Vector2(0, 9), colour, 2.0, true)
		var label: String = "左键确认 · 右键 / Esc 取消" if _legal else "不可落点 · 右键 / Esc 取消"
		draw_string(ThemeDB.fallback_font, _point + Vector2(-120, -_radius - 12), label, HORIZONTAL_ALIGNMENT_CENTER, 240, 15, colour)
	if _impact_remaining > 0.0:
		var life: float = _impact_remaining / IMPACT_SECONDS
		var wave: float = clampf((IMPACT_SECONDS - _impact_remaining) / 0.28, 0.0, 1.0)
		var wave_radius: float = _impact_radius * lerpf(0.18, 1.0, wave)
		draw_circle(_impact_point, _impact_radius, Color(IMPACT_EDGE, 0.22 * life))
		draw_arc(_impact_point, _impact_radius, 0.0, TAU, 64, Color(IMPACT_EDGE, life), 4.0, true)
		if wave < 1.0:
			var flash: float = 1.0 - wave
			draw_circle(_impact_point, 16.0, Color(IMPACT_CORE, 0.85 * flash), true, -1.0, true)
			draw_arc(_impact_point, wave_radius, 0.0, TAU, 48, Color(IMPACT_CORE, flash), 5.0, true)
			for index: int in range(8):
				var direction: Vector2 = Vector2.from_angle(TAU * float(index) / 8.0)
				draw_line(_impact_point + direction * wave_radius * 0.55,
					_impact_point + direction * wave_radius, Color(IMPACT_CORE, flash), 2.0, true)
		FreezeProfile.mark("impact_draw")


func present(point: Vector2, radius: float, legal: bool, aiming: bool) -> void:
	_aiming = aiming and point.is_finite() and is_finite(radius) and radius > 0.0
	_point = point
	_radius = radius
	_legal = legal
	if not _aiming:
		_caller_visible = false
	queue_redraw()


func present_caller(point: Vector2, shown: bool = true) -> void:
	_caller_visible = shown and point.is_finite()
	_caller = point
	queue_redraw()


func impact(point: Vector2, radius: float) -> void:
	if not point.is_finite() or not is_finite(radius) or radius <= 0.0:
		return
	_impact_point = point
	_impact_radius = radius
	_impact_remaining = IMPACT_SECONDS
	queue_redraw()


func advance(delta: float, active: bool = true) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	if not active or _impact_remaining == 0.0:
		return
	_impact_remaining = maxf(0.0, _impact_remaining - delta)
	queue_redraw()
