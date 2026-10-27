class_name C1HudButton
extends Button
## Consume both confirm edges locally; BaseButton otherwise leaks the press to
## the world's Space shortcut on the pinned engine. Mouse activation stays native;
## its completed click releases focus so the next Space returns to the world.

var _confirm_armed: bool = false


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	focus_exited.connect(_cancel_confirm)
	visibility_changed.connect(_cancel_confirm)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_cancel_confirm()
		if not event.pressed:
			# Finish BaseButton activation before dropping only this button's focus.
			release_focus.call_deferred()
		return
	if not event.is_action("ui_accept"):
		return
	accept_event()
	if disabled or not is_visible_in_tree():
		_cancel_confirm()
		return
	if event.is_echo():
		return
	if event.is_pressed():
		_confirm_armed = true
		# button_pressed represents toggle state, not a momentary key press.
		# Use the same pressed theme style without turning this action into a toggle.
		var pressed_style: StyleBox = get_theme_stylebox("pressed")
		add_theme_stylebox_override("normal", pressed_style)
		add_theme_stylebox_override("hover", pressed_style)
	else:
		var activate: bool = _confirm_armed
		_cancel_confirm()
		if activate:
			pressed.emit()


func _cancel_confirm() -> void:
	if not _confirm_armed:
		return
	_confirm_armed = false
	remove_theme_stylebox_override("normal")
	remove_theme_stylebox_override("hover")
