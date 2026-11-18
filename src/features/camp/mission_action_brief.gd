class_name MissionActionBrief
extends Control
## Large readable action notes. Selection remains an intention owned by MissionSelect.

signal closed
signal chosen(index: int)

var description_scrolls: Array[ScrollContainer] = []
var preparation_details: VBoxContainer
var _title: Label
var _picture: TextureRect
var _body: VBoxContainer
var _close: Button
var _choose: Button
var _note: Label
var _preparation_scroll: ScrollContainer
var _index: int = -1


func _ready() -> void:
	name = "ActionBrief"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.02, 0.07, 0.12, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 24))
	add_child(panel)
	CampStyle.place(panel, Rect2(100, 82, 1080, 556))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	column.add_child(heading)
	_title = CampStyle.label("行动详情", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	_close = Button.new()
	_close.text = "返回行动 / Esc"
	_close.add_theme_font_size_override("font_size", 18)
	CampStyle.text_button(_close)
	_close.pressed.connect(dismiss)
	heading.add_child(_close)
	PixelMenu.divider(column)
	var content: HBoxContainer = HBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.custom_minimum_size.x = 330
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_picture)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_body)
	_preparation_scroll = ScrollContainer.new()
	_preparation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_preparation_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preparation_scroll.focus_mode = Control.FOCUS_ALL
	_body.add_child(_preparation_scroll)
	preparation_details = VBoxContainer.new()
	preparation_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preparation_details.add_theme_constant_override("separation", 14)
	_preparation_scroll.add_child(preparation_details)
	_preparation_scroll.hide()
	var footer: HBoxContainer = HBoxContainer.new()
	column.add_child(footer)
	_note = CampStyle.label("物资和线索随生还归航确认。", 17, CampStyle.MUTED)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_note)
	_choose = Button.new()
	_choose.text = "选择此行动"
	_choose.custom_minimum_size = Vector2(230, 56)
	_choose.add_theme_font_size_override("font_size", 24)
	PixelMenu.primary(_choose)
	_choose.pressed.connect(func() -> void:
		dismiss()
		chosen.emit(_index))
	footer.add_child(_choose)
	hide()


func configure(descriptions: Array[Label], pressures: Array[Label]) -> void:
	for index: int in range(descriptions.size()):
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.name = "ActionDescription%d" % index
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.focus_mode = Control.FOCUS_ALL
		_body.add_child(scroll)
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 18)
		scroll.add_child(text)
		text.add_child(pressures[index])
		text.add_child(descriptions[index])
		scroll.hide()
		description_scrolls.append(scroll)


func show_action(index: int, title: String, picture: Texture2D) -> void:
	_index = index
	_title.text = title
	_picture.texture = picture
	_picture.show()
	_choose.show()
	_preparation_scroll.hide()
	_note.text = "物资和线索随生还归航确认。"
	for row: int in range(description_scrolls.size()):
		description_scrolls[row].visible = row == index
	show()
	_link_focus([_close, description_scrolls[index], _choose])


func show_preparation() -> void:
	_index = -1
	_title.text = "整备详情"
	_picture.hide()
	_choose.hide()
	for scroll: ScrollContainer in description_scrolls:
		scroll.hide()
	_preparation_scroll.show()
	_preparation_scroll.scroll_vertical = 0
	_note.text = "当前队伍的专精、设施与支援配置。"
	show()
	_link_focus([_close, _preparation_scroll])


func _link_focus(stops: Array[Control]) -> void:
	for row: int in range(stops.size()):
		stops[row].focus_next = stops[row].get_path_to(stops[(row + 1) % stops.size()])
		stops[row].focus_previous = stops[row].get_path_to(stops[posmod(row - 1, stops.size())])
		stops[row].focus_neighbor_left = stops[row].focus_previous
		stops[row].focus_neighbor_right = stops[row].focus_next
		stops[row].focus_neighbor_top = stops[row].focus_previous
		stops[row].focus_neighbor_bottom = stops[row].focus_next
	_close.grab_focus()


func dismiss() -> void:
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("return_to_title") and not event.is_echo():
		dismiss()
		get_viewport().set_input_as_handled()
