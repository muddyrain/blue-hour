class_name BasicSupportPanel
extends VBoxContainer
## Read-only skill column. The expedition owns input, cooldowns and all effects.

signal heal_requested
signal airstrike_requested

const HEAL_ICON: Texture2D = preload("res://assets/powers/heal.svg")
const AIRSTRIKE_ICON: Texture2D = preload("res://assets/powers/airstrike.svg")

var heal_button: Button
var airstrike_button: Button


func _ready() -> void:
	_build()


func present(heal_text: String, airstrike_text: String, heal_enabled: bool, airstrike_enabled: bool) -> void:
	_build()
	heal_button.text = _caption("Q", "治疗", heal_text)
	airstrike_button.text = _caption("E", "空袭", airstrike_text)
	heal_button.tooltip_text = "治疗当前生命比例最低的存活队员。\n" + heal_text
	airstrike_button.tooltip_text = "E 进入瞄准；左键确认，右键 / Esc 取消。\n" + airstrike_text
	_enable(heal_button, heal_enabled)
	_enable(airstrike_button, airstrike_enabled)


func _build() -> void:
	if heal_button != null:
		return
	name = "BasicSupportPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 184
	add_theme_constant_override("separation", 8)
	heal_button = _button("Heal", HEAL_ICON)
	airstrike_button = _button("Airstrike", AIRSTRIKE_ICON)
	heal_button.pressed.connect(func() -> void: heal_requested.emit())
	airstrike_button.pressed.connect(func() -> void: airstrike_requested.emit())
	_enable(heal_button, false)
	_enable(airstrike_button, false)


func _button(node_name: String, picture: Texture2D) -> Button:
	var button: Button = C1HudButton.new()
	button.name = node_name
	button.icon = picture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width",32)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(184, 68)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_disabled_color", Color("b8cbd2"))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_force_pass_scroll_events = false
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = get_theme_stylebox(state, "Button").duplicate() as StyleBox
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, style)
	add_child(button)
	return button


func _caption(key: String, title: String, supplied: String) -> String:
	var status: String = supplied
	for prefix: String in [key + " " + title + " · ", title + " · "]:
		if status.begins_with(prefix):
			status = status.trim_prefix(prefix)
			break
	if status == "左键确认 · 右键/Esc取消":
		status = "瞄准中 · 左键确认"
	return key + "  " + title + "\n" + status


func _enable(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		button.release_focus()
