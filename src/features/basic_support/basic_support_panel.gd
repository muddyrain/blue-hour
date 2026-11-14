class_name BasicSupportPanel
extends HBoxContainer
## Bottom command keycaps. The expedition owns input, cooldowns and all effects.

signal rally_requested
signal focus_requested
signal heal_requested
signal special_requested

var rally_button: CommandButton
var focus_button: CommandButton
var heal_button: CommandButton
var special_button: CommandButton


func _ready() -> void:
	_build()


func present(heal_text: String = "", special_text: String = "", heal_enabled: bool = false, special_enabled: bool = false) -> void:
	# Compatibility wrapper used by isolated HUD tests that only assert heal/special captions.
	_build()
	heal_button.present(heal_text, heal_enabled, _seconds(heal_text), 30.0, false, "治疗当前生命比例最低的存活队员。\n" + heal_text)
	special_button.present(special_text, special_enabled, 0.0, 0.0, false, special_text)
	rally_button.present("就绪", true)
	focus_button.present("就绪", true)


func present_commands(rally: Dictionary, focus: Dictionary, heal: Dictionary, special: Dictionary) -> void:
	_build()
	_apply(rally_button, rally)
	_apply(focus_button, focus)
	_apply(heal_button, heal)
	_apply(special_button, special)


func _apply(button: CommandButton, state: Dictionary) -> void:
	button.present(
		String(state.get("status", "就绪")),
		bool(state.get("enabled", false)),
		float(state.get("remaining", 0.0)),
		float(state.get("duration", 0.0)),
		bool(state.get("aiming", false)),
		String(state.get("tooltip", ""))
	)


func _build() -> void:
	if heal_button != null:
		return
	name = "BasicSupportPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	rally_button = _button("rally", "Q", "集合")
	focus_button = _button("focus", "W", "集火")
	heal_button = _button("heal", "E", "治疗")
	special_button = _button("special", "R", "特技")
	rally_button.pressed.connect(func() -> void: rally_requested.emit())
	focus_button.pressed.connect(func() -> void: focus_requested.emit())
	heal_button.pressed.connect(func() -> void: heal_requested.emit())
	special_button.pressed.connect(func() -> void: special_requested.emit())


func _button(id: String, key: String, title: String) -> CommandButton:
	var button := CommandButton.new()
	button.setup(id, key, title)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = get_theme_stylebox(state, "Button").duplicate() as StyleBox
		if style != null:
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			button.add_theme_stylebox_override(state, style)
	add_child(button)
	_enable(button, false)
	return button


func _enable(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		button.release_focus()


func _seconds(text: String) -> float:
	if not text.ends_with("s"):
		return 0.0
	var token := text.get_slice(" · ", text.get_slice_count(" · ") - 1)
	return float(token.trim_suffix("s")) if token.ends_with("s") else 0.0
