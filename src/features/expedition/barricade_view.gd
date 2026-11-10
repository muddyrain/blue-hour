class_name BarricadeView
extends Node2D
## Read-only street marker. The passage itself is owned by the active navigation.

const BARRICADE_VAN: Texture2D = preload("res://assets/exploration/barricade_van.svg")
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
	var marker: Vector2 = Vector2(center.x, footprint.end.y + 26.0)
	if opened:
		_label(marker, "近路已通", TEAL)
		return
	var vertical: bool = footprint.size.y > footprint.size.x
	var art_size: Vector2 = Vector2(footprint.size.y, footprint.size.x) if vertical else footprint.size
	draw_set_transform(center, PI * 0.5 if vertical else 0.0)
	draw_texture_rect(BARRICADE_VAN, Rect2(-art_size * 0.5, art_size), false)
	draw_set_transform(Vector2.ZERO)
	_label(marker, "车辆路障 · 可绕行", AMBER)
	if aiming:
		draw_arc(landing, 13.0, 0.0, TAU, 24, AMBER, 2.0, true)
		draw_circle(landing, 4.0, AMBER, true, -1.0, true)


func _label(point: Vector2, title: String, colour: Color) -> void:
	var font: Font = label_font if label_font != null else ThemeDB.fallback_font
	var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var origin: Vector2 = point - Vector2(width * 0.5, 0)
	draw_rect(Rect2(origin + Vector2(-8, -21), Vector2(width + 16, 28)), Color(INK, 0.95))
	draw_string(font, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, colour)
