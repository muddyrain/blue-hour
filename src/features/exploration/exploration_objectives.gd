class_name ExplorationObjectives
extends VBoxContainer
## Three read-only objective rows. Only the owner may move a camera or a survivor.

signal locate_requested(objective_id: String)

var labels: Array[Label] = []
var locate_buttons: Array[Button] = []
var _rows: Array[HBoxContainer] = []
var _ids: Array[String] = ["", "", ""]
var _built: bool = false


func _ready() -> void:
	_build()


func present(rows: Array[Dictionary]) -> void:
	_build()
	for index: int in range(3):
		_rows[index].visible = index < rows.size()
		if index >= rows.size():
			_ids[index] = ""
			continue
		var row: Dictionary = rows[index]
		_ids[index] = String(row.id)
		var optional: bool = row.optional == true
		var complete: bool = row.complete == true
		var title: String = String(row.title)
		var prefix: String = "可选" if optional else "主"
		labels[index].text = "%s%s %s %d/%d" % ["✓ " if complete else "", prefix, title, int(row.done), int(row.total)]
		var description: String = "%s目标：%s\n已完成 %d / %d%s\n%s" % ["可选" if optional else "主要", title, int(row.done), int(row.total), " · 已完成" if complete else "", String(row.hint)]
		labels[index].tooltip_text = description
		labels[index].add_theme_color_override("font_color", Color("b5ebd9") if complete else Color("edebd7") if not optional else Color("c8dbe0"))
		locate_buttons[index].tooltip_text = description + "\n定位只移动镜头；不改变队员命令或工作。"
		locate_buttons[index].disabled = _ids[index].is_empty()
		locate_buttons[index].focus_mode = Control.FOCUS_NONE if locate_buttons[index].disabled else Control.FOCUS_ALL
		if locate_buttons[index].disabled:
			locate_buttons[index].release_focus()


func _build() -> void:
	if _built:
		return
	_built = true
	name = "ExplorationObjectives"
	custom_minimum_size.x = 264
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	add_theme_constant_override("separation", 2)
	for index: int in range(3):
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Objective%d" % (index + 1)
		row.custom_minimum_size.y = 24
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		_rows.append(row)
		var label: Label = Label.new()
		label.name = "ObjectiveText"
		label.add_theme_font_size_override("font_size", 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		labels.append(label)
		var button: Button = C1HudButton.new()
		button.name = "LocateObjective"
		button.text = "定位"
		button.custom_minimum_size = Vector2(38, 24)
		button.add_theme_font_size_override("font_size", 12)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.mouse_force_pass_scroll_events = false
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var style: StyleBox = get_theme_stylebox(state, "Button").duplicate() as StyleBox
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 1
			style.content_margin_bottom = 1
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(func() -> void: _locate(index))
		row.add_child(button)
		locate_buttons.append(button)


func _locate(index: int) -> void:
	if index >= 0 and index < _ids.size() and not _ids[index].is_empty():
		locate_requested.emit(_ids[index])
