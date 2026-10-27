class_name FieldCamera
extends Camera2D
## Camera keeps running while the simulation is paused (DD-OBS-022/023).

const PAN_DIRECTIONS: Dictionary[StringName, Vector2] = {
	&"camera_left": Vector2.LEFT, &"camera_right": Vector2.RIGHT,
	&"camera_up": Vector2.UP, &"camera_down": Vector2.DOWN,
}

var bounds: Rect2 = StreetBlock.BOUNDS
var pan_speed: float = 480.0
var min_zoom: float = 0.70
var max_zoom: float = 1.25
var zoom_step: float = 1.10
var _last_pan: Vector2 = Vector2.ZERO
var _tap_pan: Vector2 = Vector2.ZERO


func _ready() -> void:
	position = Vector2(880, 580)
	zoom = Vector2.ONE * 0.82
	_clamp_position()
	force_update_scroll()


func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	# A complete press/release between frames must still move for one frame.
	if direction == Vector2.ZERO:
		direction = _tap_pan.normalized()
	_tap_pan = Vector2.ZERO
	if direction != Vector2.ZERO:
		pan_by(direction * pan_speed * delta / zoom.x)
	if direction != _last_pan:
		print("BH_CAMERA pan=%s position=%s zoom=%.2f" % [direction, position, zoom.x])
		_last_pan = direction


func _unhandled_input(event: InputEvent) -> void:
	for action: StringName in PAN_DIRECTIONS:
		if event.is_action_pressed(action):
			_tap_pan += PAN_DIRECTIONS[action]
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("camera_zoom_in"):
		zoom_at(get_viewport().get_mouse_position(), zoom_step)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		zoom_at(get_viewport().get_mouse_position(), 1.0 / zoom_step)
		get_viewport().set_input_as_handled()


func pan_by(offset: Vector2) -> void:
	position += offset
	_clamp_position()
	force_update_scroll()


func zoom_at(screen_point: Vector2, factor: float) -> void:
	var anchor: Vector2 = screen_to_world(screen_point)
	zoom = Vector2.ONE * clampf(zoom.x * factor, min_zoom, max_zoom)
	position = anchor - (screen_point - get_viewport_rect().size * 0.5) / zoom.x
	_clamp_position()
	force_update_scroll()
	print("BH_CAMERA zoom=%.2f position=%s" % [zoom.x, position])


func screen_to_world(point: Vector2) -> Vector2:
	return position + (point - get_viewport_rect().size * 0.5) / zoom.x


func _clamp_position() -> void:
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom.x
	var low: Vector2 = bounds.position + half_view
	var high: Vector2 = bounds.end - half_view
	position.x = clampf(position.x, low.x, high.x) if low.x <= high.x else bounds.get_center().x
	position.y = clampf(position.y, low.y, high.y) if low.y <= high.y else bounds.get_center().y
