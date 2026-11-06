class_name ExplorationProp
extends FieldProp
## Read-only object skin. Navigation, hit selection, work and rewards stay in Expedition.

const SEDAN: Texture2D = preload("res://assets/exploration/sedan.svg")
const VAN: Texture2D = preload("res://assets/exploration/van.svg")
const TREE: Texture2D = preload("res://assets/exploration/apple_tree.svg")
const EMPTY_TREE: Texture2D = preload("res://assets/exploration/apple_tree_empty.svg")
const TRUNK: Texture2D = preload("res://assets/exploration/tree_trunk.svg")

var object_id: String = ""
var kind: String = "vehicle"
var variant: String = "sedan"
var collision: Rect2
var work_point: Vector2
var _work_local: Vector2
var _worker_id: int = 0
var _worker_name: String = ""
var _fraction: float = 0.0
var _working: bool = false
var _progress: float = 0.0
var _occluded: bool = false
var _work_hint: String = ""


func configure(definition: Dictionary) -> void:
	# The caller supplies an already authenticated layout object; this is no validator.
	object_id = String(definition.id)
	kind = String(definition.kind)
	variant = String(definition.variant)
	position = _point(definition.point)
	var rect: Array = definition.collision
	collision = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	work_point = _point(definition.work_point)
	_work_local = work_point - position
	front_width = 148.0 if kind == "fruit_tree" else 160.0 if variant == "van" else 152.0
	title = _type_title()
	facade = TREE if kind == "fruit_tree" else VAN if variant == "van" else SEDAN
	if is_inside_tree():
		_refresh_art()
		_place_work()
		_refresh_text()
	queue_redraw()


func _ready() -> void:
	# Deliberately replace FieldProp's building slices/furniture with the object art.
	_wall = _sprite(TRUNK, Vector2(-80, -180))
	_wall.visible = kind == "fruit_tree"
	_roof = _sprite(TREE if kind == "fruit_tree" else VAN if variant == "van" else SEDAN, Vector2(-80, -180) if kind == "fruit_tree" else Vector2(-80, -96))
	_work = _label("", Vector2.ZERO, 12, 232)
	_work.size.y = 24
	_work.clip_text = true
	_work.add_theme_constant_override("outline_size", 3)
	_bar = ProgressBar.new()
	_bar.name = "ObjectWorkProgress"
	_bar.size = Vector2(96, 5)
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color("9adfc8")
	_bar.add_theme_stylebox_override("fill", fill)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color("25454d")
	_bar.add_theme_stylebox_override("background", track)
	add_child(_bar)
	_place_work()
	_refresh_art()
	_refresh_text()


func present(state: Dictionary, worker_id: int = 0, worker_name: String = "", occluded: bool = false) -> void:
	if state.get("searched") is bool:
		searched = state.searched
	if state.get("progress") is int or state.get("progress") is float:
		_progress = float(state.progress)
	_worker_id = worker_id
	_worker_name = worker_name
	if worker_id <= 0:
		_working = false
	_occluded = occluded
	_refresh_art()
	_refresh_text()
	queue_redraw()


func update_work(actor_id: int, fraction: float, inside: bool, call_sign: String = "", work_text: String = "") -> void:
	# present() supplies the stable member identity; actor_id is a transient index.
	if actor_id < 0: _worker_id = 0
	_worker_name = call_sign
	_fraction = clampf(fraction, 0.0, 1.0)
	_working = inside and actor_id >= 0
	_work_hint = work_text
	_refresh_art()
	_refresh_text()
	queue_redraw()


func obscures(world_point: Vector2) -> bool:
	if kind != "fruit_tree":
		return false
	var crown: Rect2 = Rect2(global_position + Vector2(-70, -172), Vector2(140, 135))
	for height: float in [0.0, 32.0, 64.0]:
		if crown.has_point(world_point - Vector2(0, height)):
			return true
	return false


func show_behind_roof(friend_behind: bool) -> void:
	_occluded = friend_behind
	_refresh_art()


func _draw() -> void:
	if not searchable:
		return
	var colour: Color = Color("9adfc8") if searched else Color("f2cf91")
	if searched:
		draw_arc(_work_local, 11.0, 0.0, TAU, 24, Color(0.5, 0.85, 0.75, 0.55), 1.4, true)
		draw_polyline(PackedVector2Array([_work_local + Vector2(-5, 0), _work_local + Vector2(-1, 4), _work_local + Vector2(7, -5)]), colour, 2.2, true)
	elif _worker_id > 0:
		draw_arc(_work_local, 14.0, 0.0, TAU, 28, Color(0.25, 0.4, 0.42, 0.85), 2.0, true)
		draw_arc(_work_local, 14.0, -PI * 0.5, -PI * 0.5 + maxf(_fraction, 0.04) * TAU, 28, colour, 2.5, true)
	else:
		draw_arc(_work_local, 10.0, PI * 0.15, PI * 0.85, 12, colour, 1.8, true)
		draw_arc(_work_local, 10.0, PI * 1.15, PI * 1.85, 12, colour, 1.8, true)
	if primary_target:
		draw_colored_polygon(PackedVector2Array([_work_local + Vector2(0, -19), _work_local + Vector2(-5, -28), _work_local + Vector2(5, -28)]), colour)


func _sprite(texture: Texture2D, point: Vector2) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = point
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	return sprite


func _place_work() -> void:
	if _work != null:
		_work.position = _work_local + Vector2(-116, 13)
	if _bar != null:
		_bar.position = _work_local + Vector2(-48, 38)


func _refresh_art() -> void:
	if _roof == null:
		return
	if _wall != null:
		_wall.visible = kind == "fruit_tree"
	if kind == "fruit_tree":
		_roof.position = Vector2(-80, -180)
		_roof.texture = EMPTY_TREE if searched else TREE
		_roof.modulate = Color(1.0, 1.0, 1.0, 0.38 if _occluded else 1.0)
	else:
		_roof.position = Vector2(-80, -96)
		_roof.texture = VAN if variant == "van" else SEDAN
		_roof.modulate = Color(0.75, 0.80, 0.82, 1.0) if searched else Color.WHITE


func _refresh_text() -> void:
	if _work != null:
		_work.visible = searchable
		var type_name: String = _type_title()
		if searched:
			_work.text = type_name + (" · 已采空" if kind == "fruit_tree" else " · 已清空")
		elif _worker_id > 0:
			var worker: String = _worker_name if not _worker_name.is_empty() else "队员"
			if worker.length() > 4:
				worker = worker.left(3) + "…"
			var action: String = "采集" if kind == "fruit_tree" else "搜车"
			_work.text = "%s · %02d%s · %s" % [type_name, _worker_id, worker, action if _working else "前往"]
			if _working:
				_work.text += " %d%%" % roundi(_fraction * 100.0)
		else:
			_work.text = type_name + " · " + reward_hint
			if _fraction > 0.0:
				_work.text += " · %d%%" % roundi(_fraction * 100.0)
			elif _progress > 0.0:
				_work.text += " · 进度%.1f秒" % _progress
		_work.tooltip_text = title + "\n" + reward_hint + "\n" + _work_hint
		_work.add_theme_color_override("font_color", Color("b4ebd8") if searched else Color("ffe0a4"))
	if _bar != null:
		_bar.visible = searchable and not searched and _fraction > 0.0
		_bar.value = _fraction * 100.0


func _type_title() -> String:
	var prefix: String = "果树" if kind == "fruit_tree" else "厢车" if variant == "van" else "轿车"
	var number: String = object_id.get_slice("_", 1)
	return prefix + number


static func _point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	return Vector2(float(value[0]), float(value[1]))
