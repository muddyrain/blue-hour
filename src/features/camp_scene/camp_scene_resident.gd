class_name CampSceneResident
extends Node2D
## Ambient route and official idle/walk clips. No combat actor or saved simulation.

const SPEED: float = 29.0
var member_id: int = 1
var map_position: Vector2
var activity: String = "休憩"
var body: Sprite2D
var _pose: SurvivorVisualV1 = SurvivorVisualV1.new()
var _variant: int = 0
var _route_index: int = 0
var _wait: float = 0.0
var _clock: float = 0.0
var _gait: float = 0.0
var _facing: Vector2 = Vector2.RIGHT
var _caption: Label
var _call_sign: String = ""


func _ready() -> void:
	_route_index = posmod((member_id - 1) * 2, CampSceneLayout.LOOP.size())
	map_position = CampSceneLayout.member_position(member_id)
	_wait = 1.0 + member_id * 0.7
	body = Sprite2D.new()
	body.name = "Body"
	body.scale = Vector2.ONE * ActorVisual.BODY_SCALE
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(body)
	_caption = CampStyle.label("", 14, CampSceneStyle.TEXT)
	_caption.position = Vector2(-72, -72)
	_caption.size = Vector2(144, 24)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_outline_color", Color("22201e"))
	_caption.add_theme_constant_override("outline_size", 4)
	add_child(_caption)
	_pose_body(Vector2.ZERO)


func configure(member: Dictionary) -> void:
	var definition: SurvivorDefinition = SurvivorRoster.definition_for(member)
	_variant = SurvivorRoster.Definitions.find(definition)
	assert(_variant >= 0 and _variant < SurvivorVisualV1.SHEETS.size())
	_call_sign = String(member.call_sign)
	set_meta("definition_id", definition.id)
	_pose_body(Vector2.ZERO)


func advance(delta: float) -> void:
	_clock += delta
	var velocity: Vector2 = Vector2.ZERO
	if _wait > 0.0:
		_wait = maxf(0.0, _wait - delta)
		activity = {0:"整理物资", 2:"检查工具", 4:"查看路线", 5:"篝火休憩"}.get(_route_index, "休憩")
	else:
		var target: Vector2 = CampSceneLayout.LOOP[(_route_index + 1) % CampSceneLayout.LOOP.size()]
		var before: Vector2 = map_position
		map_position = map_position.move_toward(target, SPEED * delta)
		velocity = (map_position - before) / maxf(delta, 0.001)
		_gait += velocity.length() / SPEED * delta * 9.0
		activity = "散步"
		if map_position.is_equal_approx(target):
			_route_index = (_route_index + 1) % CampSceneLayout.LOOP.size()
			_wait = 2.0 + float(posmod(member_id + _route_index, 5))
	_pose_body(velocity)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 14, Color(0.12, 0.11, 0.10, 0.26))
	draw_set_transform(Vector2.ZERO)


func _pose_body(velocity: Vector2) -> void:
	if body == null:
		return
	var projected: Vector2 = IsoSpace.to_view(velocity)
	if not projected.is_zero_approx():
		_facing = projected.normalized()
	_pose.pose(body, _variant, _facing, _facing, &"idle" if velocity.is_zero_approx() else &"move", _clock, _gait, 0.0, 0.0)
	IsoSpace.place(self, map_position)
	_caption.text = _call_sign
	queue_redraw()
