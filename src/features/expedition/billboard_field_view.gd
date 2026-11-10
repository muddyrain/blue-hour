class_name BillboardFieldView
extends Node2D
## Read-only street art anchored to the authenticated outdoor work point.

const INK: Color = Color("142932")
const PAPER: Color = Color("d6e7e1")
const TEAL: Color = Color("8de5d0")
const AMBER: Color = Color("ffcf86")
const HINT: String = "派一人调查 · 下次可选超市补给\n替换一个随机候选"
const DONE: String = "已调查 · 下次选卡保证有超市补给"

var label_font: Font
var _progress: float = 0.0
var _phase: String = ""
var _worker: String = ""
var _hovered: bool = false


func present(progress: float, phase: String, worker: String) -> void:
	if progress == _progress and phase == _phase and worker == _worker:
		return
	_progress = progress
	_phase = phase
	_worker = worker
	queue_redraw()


func _process(_delta: float) -> void:
	var hovered: bool = BillboardActionV1.hit_rect(Vector2.ZERO).has_point(get_local_mouse_position())
	if hovered != _hovered:
		_hovered = hovered
		queue_redraw()


func _draw() -> void:
	var face: Rect2 = BillboardActionV1.face_rect(Vector2.ZERO)
	var finished: bool = _progress == BillboardActionV1.SECONDS
	var accent: Color = AMBER if not _phase.is_empty() or _hovered else TEAL
	for x: float in [-30.0, 30.0]:
		draw_line(Vector2(x, face.end.y - 2.0), Vector2(x, -13), INK, 10.0)
		draw_line(Vector2(x, face.end.y), Vector2(x, -15), Color("96afaa"), 5.0)
	draw_rect(face.grow(3.0), INK)
	draw_rect(face, PAPER)
	draw_rect(Rect2(face.position, Vector2(face.size.x, 4.0)), Color("579787") if finished else Color("bf795d"))
	if _hovered or not _phase.is_empty():
		draw_rect(face.grow(4.0), accent, false, 2.0)
	var basket: Vector2 = face.position + Vector2(22, 27)
	draw_polyline(PackedVector2Array([basket + Vector2(-11, -3), basket + Vector2(-7, 7),
		basket + Vector2(7, 7), basket + Vector2(11, -3), basket + Vector2(-11, -3)]), INK, 2.0, true)
	draw_polyline(PackedVector2Array([basket + Vector2(-7, -3), basket + Vector2(-4, -11),
		basket + Vector2(4, -11), basket + Vector2(7, -3)]), INK, 2.0, true)
	draw_string(_font(), face.position + Vector2(43, 34), "超市", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	draw_circle(Vector2.ZERO, BillboardActionV1.WORK_RANGE, Color(accent, 0.12), true, -1.0, true)
	draw_arc(Vector2.ZERO, BillboardActionV1.WORK_RANGE, 0, TAU, 32, accent, 2.0, true)
	if _progress > 0.0 and not finished:
		var fill: Rect2 = Rect2(face.position.x, face.end.y + 4, face.size.x, 5)
		draw_rect(fill, INK)
		fill.size.x *= _progress / BillboardActionV1.SECONDS
		draw_rect(fill, accent)
	var title: String = "可调查"
	if finished:
		title = DONE
	elif _phase == "approach":
		title = "%s · 前往调查 · 再点取消" % _worker
	elif _phase == "working":
		title = "%s · 调查中 %.1f/4 秒" % [_worker, _progress]
	elif _progress > 0.0:
		title = "可调查 · %.1f/4 秒" % _progress
	_label(face.position.y - 11.0, title, accent)
	if _hovered and not finished:
		var lines: PackedStringArray = HINT.split("\n")
		_label(face.position.y - 65.0, lines[0], PAPER)
		_label(face.position.y - 38.0, lines[1], PAPER)


func _font() -> Font:
	return label_font if label_font != null else ThemeDB.fallback_font


func _label(baseline: float, title: String, colour: Color) -> void:
	var font: Font = _font()
	var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var origin: Vector2 = Vector2(-width * 0.5, baseline)
	draw_rect(Rect2(origin + Vector2(-7, -18), Vector2(width + 14, 25)), Color(INK, 0.94))
	draw_string(font, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, colour)
