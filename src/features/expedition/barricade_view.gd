class_name BarricadeView
extends Node2D
## Read-only street marker. The passage itself is owned by the active navigation.

const VAN: Texture2D = preload("res://assets/exploration/van.svg")
const AMBER: Color = Color("ffcf86")
const TEAL: Color = Color("8be4d2")
const INK: Color = Color("152b35")

var footprint: Rect2
var landing: Vector2
var label_font: Font
var opened: bool = false
var aiming: bool = false


func present(open_passage: bool, aim_active: bool) -> void:
	if opened == open_passage and aiming == aim_active:
		return
	opened = open_passage
	aiming = aim_active
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = footprint.get_center()
	if opened:
		var gate_tint: Color = Color(TEAL, 0.42)
		draw_rect(footprint, gate_tint, false, 2.0)
		_label(center - Vector2(0, footprint.size.y * 0.5 + 24.0), "路障已清除 · 近路可通行", TEAL)
		return
	draw_rect(footprint, Color(0.17, 0.13, 0.08, 0.55))
	draw_rect(footprint, Color(AMBER, 0.8), false, 2.0)
	var vertical: bool = footprint.size.y > footprint.size.x
	var long_side: float = maxf(footprint.size.x, footprint.size.y)
	var short_side: float = minf(footprint.size.x, footprint.size.y)
	draw_set_transform(center, PI * 0.5 if vertical else 0.0)
	draw_texture_rect(VAN, Rect2(-long_side * 0.53, -short_side * 1.12, long_side * 1.06, short_side * 1.78), false)
	draw_set_transform(Vector2.ZERO)
	_label(center - Vector2(0, footprint.size.y * 0.5 + 34.0), "车辆路障 · 可绕行", AMBER)
	if aiming:
		draw_arc(landing, 13.0, 0.0, TAU, 24, AMBER, 2.0, true)
		draw_circle(landing, 4.0, AMBER, true, -1.0, true)


func _label(point: Vector2, title: String, colour: Color) -> void:
	var font: Font = label_font if label_font != null else ThemeDB.fallback_font
	var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var origin: Vector2 = point - Vector2(width * 0.5, 0)
	draw_rect(Rect2(origin + Vector2(-8, -21), Vector2(width + 16, 28)), Color(INK, 0.95))
	draw_string(font, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, colour)
