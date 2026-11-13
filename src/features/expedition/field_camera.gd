class_name FieldCamera
extends Camera2D
## Camera keeps running while the simulation is paused (DD-OBS-022/023).

const PAN_DIRECTIONS: Dictionary[StringName, Vector2] = {
	&"camera_left": Vector2.LEFT, &"camera_right": Vector2.RIGHT,
	&"camera_up": Vector2.UP, &"camera_down": Vector2.DOWN,
}

const HUD_INSET_LEFT: float = 172.0
const HUD_INSET_RIGHT: float = 224.0
const HUD_INSET_TOP: float = 88.0
const HUD_INSET_BOTTOM: float = 200.0

var bounds: Rect2 = StreetBlock.BOUNDS
var pan_speed: float = 480.0
var min_zoom: float = 0.70
var max_zoom: float = 1.25
var zoom_step: float = 1.10
var _tap_pan: Vector2 = Vector2.ZERO
var menu_blocked: bool = false
var _player_panning: bool = false


func _ready() -> void:
	position = Vector2(880, 580)
	zoom = Vector2.ONE * 0.82
	_clamp_position()
	force_update_scroll()


func _process(delta: float) -> void:
	if menu_blocked:
		_tap_pan = Vector2.ZERO
		_player_panning = false
		return
	var direction: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	# A complete press/release between frames must still move for one frame.
	if direction == Vector2.ZERO:
		direction = _tap_pan.normalized()
	_tap_pan = Vector2.ZERO
	_player_panning = direction != Vector2.ZERO
	if direction != Vector2.ZERO:
		pan_by(direction * pan_speed * delta / zoom.x)


func _unhandled_input(event: InputEvent) -> void:
	if menu_blocked:
		return
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
	# Vector2 uses float32; its nearest 0.7 is below the strict snapshot bound.
	var stored_min: float = maxf(min_zoom, 0.7000000476837158)
	zoom = Vector2.ONE * clampf(zoom.x * factor, stored_min, max_zoom)
	position = anchor - (screen_point - get_viewport_rect().size * 0.5) / zoom.x
	_clamp_position()
	force_update_scroll()


func screen_to_world(point: Vector2) -> Vector2:
	return position + (point - get_viewport_rect().size * 0.5) / zoom.x


func framed_position(focus: Vector2) -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return focus
	var safe_center: Vector2 = Vector2(
		(HUD_INSET_LEFT + view.x - HUD_INSET_RIGHT) * 0.5,
		(HUD_INSET_TOP + view.y - HUD_INSET_BOTTOM) * 0.5)
	return focus - (safe_center - view * 0.5) / zoom.x


func keep_points_visible(world_points: Array[Vector2]) -> void:
	if menu_blocked or _player_panning or _tap_pan != Vector2.ZERO:
		return
	var view: Vector2 = get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var left: float = HUD_INSET_LEFT + 16.0
	var right: float = view.x - HUD_INSET_RIGHT - 16.0
	var top: float = HUD_INSET_TOP + 16.0
	var bottom: float = view.y - HUD_INSET_BOTTOM - 16.0
	if right <= left or bottom <= top:
		return
	var need_x_neg: float = 0.0
	var need_x_pos: float = 0.0
	var need_y_neg: float = 0.0
	var need_y_pos: float = 0.0
	var screen_bounds: Rect2 = Rect2(Vector2(-40, -40), view + Vector2(80, 80))
	for point: Vector2 in world_points:
		var screen: Vector2 = (point - position) * zoom.x + view * 0.5
		if not screen_bounds.has_point(screen):
			continue
		if screen.x < left:
			need_x_neg = minf(need_x_neg, screen.x - left)
		elif screen.x > right:
			need_x_pos = maxf(need_x_pos, screen.x - right)
		if screen.y < top:
			need_y_neg = minf(need_y_neg, screen.y - top)
		elif screen.y > bottom:
			need_y_pos = maxf(need_y_pos, screen.y - bottom)
	var delta: Vector2 = Vector2.ZERO
	if need_x_neg >= 0.0 or need_x_pos <= 0.0:
		delta.x = need_x_neg + need_x_pos
	if need_y_neg >= 0.0 or need_y_pos <= 0.0:
		delta.y = need_y_neg + need_y_pos
	if delta != Vector2.ZERO:
		pan_by(delta / zoom.x)


func _clamp_position() -> void:
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom.x
	var low: Vector2 = bounds.position + half_view
	var high: Vector2 = bounds.end - half_view
	position.x = clampf(position.x, low.x, high.x) if low.x <= high.x else bounds.get_center().x
	position.y = clampf(position.y, low.y, high.y) if low.y <= high.y else bounds.get_center().y
