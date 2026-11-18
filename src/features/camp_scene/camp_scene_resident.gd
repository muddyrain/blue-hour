class_name CampSceneResident
extends Node2D
## Independent living resident on the camp plate; not a combat actor or saved simulation.

const SPEED: float = 13.0
const HEIGHT: float = 68.0
var member_id: int = 1
var map_position: Vector2
var activity: String = "休憩"
var body: Sprite2D
var _route: Array[Vector2] = []
var _route_index: int = 0
var _wait: float = 0.0
var _clock: float = 0.0
var _caption: Label
var _call_sign: String = ""
var _slot: int = -1


func _ready() -> void:
	_route = CampSceneLayout.resident_route(member_id)
	map_position = CampSceneLayout.member_position(member_id)
	_wait = 6.0 + member_id * 0.7
	body = Sprite2D.new()
	body.name = "Body"
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)
	_caption = CampStyle.label("", 13, CampSceneStyle.TEXT)
	_caption.position = Vector2(-64, -92)
	_caption.size = Vector2(128, 22)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_outline_color", CampStyle.INK)
	_caption.add_theme_constant_override("outline_size", 4)
	_caption.hide()
	add_child(_caption)
	position = map_position


func configure(member: Dictionary) -> void:
	var definition: SurvivorDefinition = SurvivorRoster.definition_for(member)
	body.texture = CampPixelArt.body(String(definition.id))
	body.scale = Vector2.ONE * HEIGHT / body.texture.get_height()
	body.position = Vector2(0, -HEIGHT * 0.5)
	_call_sign = String(member.call_sign)
	_caption.text = _call_sign
	set_meta("definition_id", definition.id)


func set_slot(slot: int) -> void:
	if _slot == slot:
		return
	_slot = slot
	_route = CampSceneLayout.resident_route(slot + 1)
	_route_index = 0
	map_position = _route[0]
	position = map_position.round()
	_wait = 6.0 + member_id * 0.7


func advance(delta: float) -> void:
	_clock += delta
	var moving: bool = false
	if _wait > 0.0:
		_wait = maxf(0.0, _wait - delta)
		activity = "篝火休憩" if member_id == 4 else "休憩"
	else:
		var target: Vector2 = _route[(_route_index + 1) % _route.size()]
		map_position = map_position.move_toward(target, SPEED * delta)
		moving = true
		activity = "散步"
		body.flip_h = target.x < map_position.x
		if map_position.is_equal_approx(target):
			_route_index = (_route_index + 1) % _route.size()
			_wait = 5.0 + float(posmod(member_id + _route_index, 5))
	position = map_position.round()
	body.position.y = -HEIGHT * 0.5 - (absf(sin(_clock * 7.0)) * 2.0 if moving else 0.0)
	queue_redraw()


func highlight(enabled: bool) -> void:
	_caption.visible = enabled
	body.self_modulate = Color(1.12, 1.12, 1.12) if enabled else Color.WHITE


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, 15, Color(0.04, 0.09, 0.14, 0.28))
	draw_set_transform(Vector2.ZERO)
