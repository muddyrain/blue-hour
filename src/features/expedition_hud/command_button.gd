class_name CommandButton
extends C1HudButton
## Rounded command keycap: title, shortcut, status, and an amber cooldown ring.

const CREAM := Color("e8dcc4")
const AMBER := Color("d9a24a")
const DIM := Color("e8dcc4", 0.28)

var command_id: String = ""
var command_key: String = ""
var command_title: String = ""
var cooldown_ratio: float = 0.0
var aiming: bool = false


func setup(id: String, key: String, title: String) -> void:
	command_id = id
	command_key = key
	command_title = title
	name = id.capitalize()
	icon = _icon(id)
	expand_icon = true
	add_theme_constant_override("icon_max_width", 22)
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(68, 68)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_disabled_color", Color("b8ac96"))
	add_theme_color_override("icon_disabled_color", Color("b8ac96"))
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	text = "%s  %s\n—" % [title, key]


func present(status: String, enabled: bool, remaining: float = 0.0, duration: float = 0.0, is_aiming: bool = false, tooltip: String = "") -> void:
	aiming = is_aiming
	cooldown_ratio = clampf(remaining / duration, 0.0, 1.0) if duration > 0.0 and remaining > 0.0 else 0.0
	var short := _short(status)
	if is_aiming:
		short = "瞄准"
	text = "%s  %s\n%s" % [command_title, command_key, short]
	tooltip_text = tooltip if not tooltip.is_empty() else "%s · %s\n%s" % [command_title, command_key, status]
	disabled = not enabled
	focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		release_focus()
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3.0
	if radius <= 0.0:
		return
	if aiming:
		draw_arc(center, radius, 0.0, TAU, 48, AMBER, 2.2, true)
	if cooldown_ratio > 0.0:
		var ready := TAU * (1.0 - cooldown_ratio)
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + ready, 48, AMBER, 3.0, true)
		draw_arc(center, radius, -PI * 0.5 + ready, -PI * 0.5 + TAU, 48, DIM, 3.0, true)


func _short(status: String) -> String:
	if status.ends_with("s") and status.contains("."):
		return status.get_slice(" · ", status.get_slice_count(" · ") - 1) if " · " in status else status
	if status.ends_with("s") and status.length() <= 8:
		return status
	if "瞄准" in status:
		return "瞄准"
	if status in ["无受伤存活者", "无需"]:
		return "无需"
	if status in ["当前阶段不可用", "—", "当前没有可释放的特技"]:
		return "—"
	if status in ["空槽", "营地装配"]:
		return "空槽"
	if status in ["已用", "今日已用"]:
		return "已用"
	if status.begins_with("持续"):
		return status
	if status.contains("就绪") or status.is_empty():
		return "就绪"
	if " · " in status:
		return status.get_slice(" · ", status.get_slice_count(" · ") - 1)
	return status


func _icon(kind: String) -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var ink := Color("e8dcc4")
	match kind:
		"rally":
			_dot(image, 8, 8, ink)
			_dot(image, 23, 8, ink)
			_dot(image, 16, 6, ink)
			_bar(image, 15, 12, 2, 10, ink)
			_bar(image, 11, 20, 10, 2, ink)
			_bar(image, 13, 23, 6, 2, ink)
			_bar(image, 15, 26, 2, 3, ink)
		"focus":
			_bar(image, 15, 4, 2, 8, ink)
			_bar(image, 15, 20, 2, 8, ink)
			_bar(image, 4, 15, 8, 2, ink)
			_bar(image, 20, 15, 8, 2, ink)
			_bar(image, 12, 12, 8, 2, ink)
			_bar(image, 12, 18, 8, 2, ink)
			_bar(image, 12, 12, 2, 8, ink)
			_bar(image, 18, 12, 2, 8, ink)
		"heal":
			_bar(image, 14, 6, 4, 20, ink)
			_bar(image, 6, 14, 20, 4, ink)
		"special":
			_bar(image, 15, 4, 2, 24, ink)
			_bar(image, 4, 15, 24, 2, ink)
			_bar(image, 8, 8, 16, 2, Color("d9a24a"))
			_bar(image, 8, 22, 16, 2, Color("d9a24a"))
			_bar(image, 8, 8, 2, 16, Color("d9a24a"))
			_bar(image, 22, 8, 2, 16, Color("d9a24a"))
	return ImageTexture.create_from_image(image)


func _dot(image: Image, x: int, y: int, colour: Color) -> void:
	_bar(image, x, y, 3, 3, colour)


func _bar(image: Image, x: int, y: int, w: int, h: int, colour: Color) -> void:
	for px in range(maxi(0, x), mini(32, x + w)):
		for py in range(maxi(0, y), mini(32, y + h)):
			image.set_pixel(px, py, colour)
