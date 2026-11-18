class_name RosterPanel
extends PanelContainer
## Real camp identities, in the approved roster / portrait / facts composition.

signal call_sign_requested(member_id: int, call_sign: String)
signal equipment_requested(member_id: int)
signal growth_requested(member_id: int)
signal training_requested(member_id: int)
signal closed
signal navigation_requested(action: StringName)

var member_buttons: Array[Button] = []
var buttons_by_id: Dictionary[int, Button] = {}
var death_equipment: Dictionary = {}
var name_edit: LineEdit
var save_button: Button
var equipment_button: Button
var back_button: Button
var message: Label
var selected_member_id: int = 1
var growth_button: Button
var persona_details: PersonaDetails
var rename_button: Button
var _detail_host: ScrollContainer
var _data: Dictionary = {}
var _sheet: PixelSheet
var _portrait: TextureRect
var _identity: Label
var _call_sign: Label
var _gender: Label
var _condition: Label
var _members_list: VBoxContainer
var _member_scroll: ScrollContainer
var _history_link: Button
var _rename_editor: Control
var _rename_cancel: Button
var _member_names: Dictionary[int, Label] = {}
var _member_health: Dictionary[int, Label] = {}
var _member_bars: Dictionary[int, ProgressBar] = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	_sheet = PixelSheet.new()
	_sheet.page_title = "同行者档案"
	_sheet.active_tab = &"roster"
	add_child(_sheet)
	_sheet.closed.connect(closed.emit)
	_sheet.navigation_requested.connect(func(action: StringName) -> void:
		if action != &"roster": navigation_requested.emit(action)
	)
	back_button = _sheet.back_button
	var body: Control = _sheet.body
	PixelSheet.line(body, Rect2(302, 8, 1, 558))
	PixelSheet.line(body, Rect2(598, 8, 1, 558))
	_member_scroll = ScrollContainer.new()
	_member_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_member_scroll.follow_focus = true
	body.add_child(_member_scroll)
	PixelSheet.place(_member_scroll, Rect2(16, 24, 278, 526))
	_members_list = VBoxContainer.new()
	_members_list.add_theme_constant_override("separation", 12)
	_members_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_member_scroll.add_child(_members_list)
	_identity = PixelSheet.label(body, "", Rect2(322, 12, 206, 50), 36)
	_identity.clip_text = true
	PixelSheet.line(body, Rect2(532, 26, 1, 26))
	_gender = PixelSheet.label(body, "", Rect2(544, 20, 42, 38), 25)
	_call_sign = PixelSheet.label(body, "", Rect2(322, 66, 260, 30), 18, CampStyle.MUTED)
	_call_sign.clip_text = true
	_portrait = PixelSheet.art(body, null, Rect2(318, 116, 260, 360))
	_condition = PixelSheet.label(body, "", Rect2(322, 476, 260, 24), 18, CampStyle.MUTED)
	_condition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rename_button = PixelSheet.button(body, "修改呼号", Rect2(318, 512, 128, 48), 23)
	rename_button.pressed.connect(func() -> void: set_rename_open(true))
	_history_link = PixelSheet.button(body, "行动记录", Rect2(458, 512, 128, 48), 23)
	_history_link.pressed.connect(func() -> void: growth_requested.emit(selected_member_id))
	growth_button = _history_link
	_rename_editor = Control.new()
	body.add_child(_rename_editor)
	PixelSheet.place(_rename_editor, Rect2(310, 440, 282, 132))
	PixelSheet.panel(_rename_editor, Rect2(0, 0, 282, 132), CampStyle.INK)
	name_edit = LineEdit.new()
	name_edit.max_length = 12
	name_edit.placeholder_text = "自定义呼号（1–12字）"
	name_edit.add_theme_font_size_override("font_size", 20)
	_rename_editor.add_child(name_edit)
	PixelSheet.place(name_edit, Rect2(8, 0, 266, 48))
	save_button = PixelSheet.button(_rename_editor, "保存呼号", Rect2(8, 72, 128, 48), 22)
	save_button.pressed.connect(func() -> void: call_sign_requested.emit(selected_member_id, name_edit.text))
	_rename_cancel = PixelSheet.button(_rename_editor, "取消", Rect2(148, 72, 126, 48), 22)
	_rename_cancel.pressed.connect(func() -> void:
		var member: Dictionary = SurvivorRoster.member(_data.crew, selected_member_id)
		name_edit.text = member.call_sign
		set_rename_open(false)
	)
	_rename_editor.hide()
	_detail_host = ScrollContainer.new()
	_detail_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_host.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_detail_host)
	PixelSheet.place(_detail_host, Rect2(614, 8, 474, 572))
	var camp_details: RosterPixelDetails = RosterPixelDetails.new()
	persona_details = camp_details
	_detail_host.add_child(persona_details)
	persona_details.equipment_requested.connect(equipment_requested.emit)
	persona_details.training_requested.connect(training_requested.emit)
	persona_details.closed.connect(func() -> void:
		persona_details.show()
		closed.emit()
	)
	equipment_button = persona_details.equipment_button
	message = PixelSheet.label(body, "", Rect2(16, 448, 278, 128), 18, CampStyle.MUTED, false)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	message.hide()


func refresh(data: Dictionary, feedback: String = "") -> void:
	_data = data.duplicate(true)
	_sheet.update_resources(data)
	if SurvivorRoster.member(_data.crew, selected_member_id).is_empty():
		selected_member_id = int(_data.crew[0].id)
	_sync_members()
	for member_id: int in buttons_by_id:
		var entry: Dictionary = SurvivorRoster.member(_data.crew, member_id)
		var button: Button = buttons_by_id[member_id]
		button.visible = not entry.is_empty()
		if entry.is_empty():
			continue
		var full_name: String = String(entry.call_sign)
		_member_names[member_id].text = full_name
		_member_names[member_id].tooltip_text = full_name
		var maximum: float = SurvivorGrowth.maximum(_data, entry)
		_member_health[member_id].text = "%.0f/%.0f" % [float(entry.health), maximum]
		_member_bars[member_id].max_value = maximum
		_member_bars[member_id].value = float(entry.health)
		button.tooltip_text = PersonaCard.camp_hover(_data, member_id) + "\n" + SurvivorRoster.definition(member_id).gender_text()
		var selected: bool = member_id == selected_member_id
		var normal: StyleBoxFlat = CampStyle.box(CampStyle.SELECTED.darkened(0.16) if selected else Color.TRANSPARENT, CampStyle.EDGE if selected else Color.TRANSPARENT, 0)
		if selected: normal.set_border_width_all(2)
		button.add_theme_stylebox_override("normal", normal)
	var member: Dictionary = SurvivorRoster.member(_data.crew, selected_member_id)
	var definition: SurvivorDefinition = SurvivorRoster.definition(selected_member_id)
	_portrait.texture = PixelSheet.body_texture(selected_member_id)
	_portrait.modulate = Color.WHITE if member.health > 0 else Color("8a9eae")
	_identity.text = definition.default_display_name
	_identity.tooltip_text = definition.default_display_name
	_gender.text = "男" if definition.gender == &"male" else "女" if definition.gender == &"female" else "—"
	_call_sign.text = "呼号：" + String(member.call_sign)
	_call_sign.visible = member.call_sign != definition.default_display_name
	_call_sign.tooltip_text = String(member.call_sign)
	_condition.text = "阵亡 · 只读历史" if member.condition == "dead" else "倒地" if member.condition != "active" else ""
	(persona_details as RosterPixelDetails).present_roster(_data, selected_member_id, death_equipment.get(selected_member_id, {}))
	name_edit.text = member.call_sign
	name_edit.editable = member.condition != "dead"
	save_button.disabled = member.condition == "dead"
	rename_button.disabled = member.condition == "dead"
	if member.condition == "dead": set_rename_open(false)
	message.text = feedback
	message.tooltip_text = feedback
	message.visible = not feedback.is_empty()
	_member_scroll.size.y = 416 if message.visible else 526
	if not feedback.is_empty() and member.call_sign == name_edit.text:
		set_rename_open(false)


func set_rename_open(open: bool) -> void:
	_rename_editor.visible = open
	rename_button.visible = not open
	_history_link.visible = not open
	if open:
		name_edit.grab_focus()
		name_edit.select_all()
	elif is_visible_in_tree():
		rename_button.grab_focus()


func _sync_members() -> void:
	for entry: Dictionary in _data.crew:
		var member_id: int = int(entry.id)
		if buttons_by_id.has(member_id):
			continue
		var button: Button = PersonaCard.HoverButton.new()
		button.custom_minimum_size = Vector2(264, 92)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			set_rename_open(false)
			selected_member_id = member_id
			refresh(_data)
		)
		_members_list.add_child(button)
		PixelSheet.art(button, SurvivorRoster.definition(member_id).portrait, Rect2(10, 12, 66, 64))
		var member_name: Label = PixelSheet.label(button, "", Rect2(84, 16, 94, 32), 24)
		member_name.clip_text = true
		_member_names[member_id] = member_name
		var hp: Label = PixelSheet.label(button, "", Rect2(174, 16, 88, 32), 20, CampStyle.TEXT, false)
		_member_health[member_id] = hp
		var bar: ProgressBar = ProgressBar.new()
		bar.show_percentage = false
		bar.step = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(bar)
		PixelSheet.place(bar, Rect2(84, 58, 178, 12))
		_member_bars[member_id] = bar
		member_buttons.append(button)
		buttons_by_id[member_id] = button
