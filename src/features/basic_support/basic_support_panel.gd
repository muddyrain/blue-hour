class_name BasicSupportPanel
extends HBoxContainer
## Compact read-only controls. Parent handles world shortcuts and authority requests.

signal heal_requested
signal airstrike_requested

var heal_button: Button
var airstrike_button: Button


func _ready() -> void:
	_build()


func present(heal_text: String, airstrike_text: String, heal_enabled: bool, airstrike_enabled: bool) -> void:
	_build()
	heal_button.text = "Q · 治疗\n" + heal_text
	airstrike_button.text = "E · 空袭\n" + airstrike_text
	heal_button.tooltip_text = "治疗当前生命比例最低的存活队员。\n" + heal_text
	airstrike_button.tooltip_text = "进入瞄准；左键确认，右键 / Esc 取消。\n" + airstrike_text
	_enable(heal_button, heal_enabled)
	_enable(airstrike_button, airstrike_enabled)


func _build() -> void:
	if heal_button != null:
		return
	name = "BasicSupportPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	heal_button = _button("Heal", "Q · 治疗\n不可用")
	airstrike_button = _button("Airstrike", "E · 空袭\n不可用")
	heal_button.pressed.connect(func() -> void: heal_requested.emit())
	airstrike_button.pressed.connect(func() -> void: airstrike_requested.emit())
	_enable(heal_button, false)
	_enable(airstrike_button, false)


func _button(node_name: String, label: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = label
	button.custom_minimum_size = Vector2(196, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(button)
	return button


func _enable(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		button.release_focus()
