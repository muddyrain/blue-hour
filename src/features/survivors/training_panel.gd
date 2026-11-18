class_name TrainingPanel
extends PanelContainer
## View and confirmation intentions only; the original camp transaction owns every write.

signal closed
signal confirmed(request: Dictionary)
signal retry_requested
signal navigation_requested(action: StringName)

var selected_member_id: int = 0
var member_buttons: Dictionary[int, Button] = {}
var train_button: Button
var retry_button: Button
var back_button: Button
var confirmation: ConfirmationDialog
var detail: Label
var preview_text: Label
var risk_text: Label
var status: Label
var _sheet: PixelSheet
var _members: VBoxContainer
var _data: Dictionary = {}
var _quote: Dictionary = {}
var _busy: bool = false
var _pending: bool = false
var _confirmation_armed: bool = false
var _level_before: Label
var _level_after: Label
var _progress_before: Label
var _progress_after: Label
var _effect_name: Label
var _effect_before: Label
var _effect_after: Label
var _food_before: Label
var _food_after: Label
var _veil: ColorRect
var _confirm_portrait: TextureRect
var _confirm_title: Label
var _confirm_summary: Label
var _confirm_values: Array[Label] = []
var _confirm_effect_name: Label
var _confirm_rations: Label
var _rations_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	add_theme_stylebox_override("panel", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	_sheet = PixelSheet.new()
	_sheet.page_title = "篝火训练"
	_sheet.active_tab = &"training"
	add_child(_sheet)
	_sheet.closed.connect(closed.emit)
	_sheet.navigation_requested.connect(navigation_requested.emit)
	var body: Control = _sheet.body
	var list_scroll: ScrollContainer = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	body.add_child(list_scroll)
	PixelSheet.place(list_scroll, Rect2(16, 16, 324, 200))
	_members = VBoxContainer.new()
	_members.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_members.add_theme_constant_override("separation", 8)
	list_scroll.add_child(_members)
	PixelSheet.line(body, Rect2(16, 218, 324, 1))
	var fire: TextureRect = PixelSheet.art(body, load("res://assets/menu_pixel/training-fire.png"), Rect2(16, 234, 324, 334))
	fire.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fire.clip_contents = true
	PixelSheet.line(body, Rect2(356, 16, 1, 552))
	detail = PixelSheet.label(body, "", Rect2(380, 2, 708, 66), 40)
	PixelSheet.line(body, Rect2(380, 70, 708, 1))
	PixelSheet.label(body, "特性", Rect2(396, 78, 108, 48), 30)
	_level_before = PixelSheet.label(body, "", Rect2(508, 78, 116, 48), 32)
	PixelSheet.label(body, "→", Rect2(632, 78, 64, 48), 32)
	_level_after = PixelSheet.label(body, "", Rect2(708, 78, 136, 48), 32, CampStyle.TEAL)
	PixelSheet.panel(body, Rect2(380, 132, 708, 90), Color.TRANSPARENT, CampStyle.EDGE)
	PixelSheet.panel(body, Rect2(381, 133, 254, 88), CampStyle.PANEL)
	PixelSheet.line(body, Rect2(380, 177, 708, 1))
	PixelSheet.label(body, "特性进度", Rect2(398, 132, 238, 45), 26)
	_effect_name = PixelSheet.label(body, "", Rect2(398, 177, 238, 45), 25)
	_progress_before = PixelSheet.label(body, "", Rect2(664, 132, 130, 45), 28)
	_effect_before = PixelSheet.label(body, "", Rect2(664, 177, 130, 45), 28)
	for y: int in [132, 177]:
		PixelSheet.label(body, "→", Rect2(832, y, 60, 45), 28)
	_progress_after = PixelSheet.label(body, "", Rect2(944, 132, 128, 45), 28, CampStyle.TEAL)
	_effect_after = PixelSheet.label(body, "", Rect2(944, 177, 128, 45), 28, CampStyle.TEAL)
	PixelSheet.panel(body, Rect2(380, 240, 708, 56), CampStyle.SURFACE)
	PixelSheet.art(body, load("res://assets/camp_pixel/food.svg"), Rect2(400, 253, 30, 28))
	PixelSheet.label(body, "消耗食物 1份", Rect2(444, 240, 252, 56), 26)
	PixelSheet.line(body, Rect2(716, 254, 1, 28))
	PixelSheet.label(body, "库存", Rect2(738, 240, 80, 56), 26)
	_food_before = PixelSheet.label(body, "", Rect2(836, 240, 62, 56), 28)
	PixelSheet.label(body, "→", Rect2(904, 240, 60, 56), 28)
	_food_after = PixelSheet.label(body, "", Rect2(996, 240, 80, 56), 28, CampStyle.TEAL)
	PixelSheet.label(body, "不增加经验、生命或日期。", Rect2(380, 304, 708, 40), 22)
	PixelSheet.line(body, Rect2(380, 352, 708, 1))
	PixelSheet.label(body, "配给预估", Rect2(380, 364, 164, 84), 28)
	PixelSheet.line(body, Rect2(548, 368, 1, 68))
	risk_text = PixelSheet.label(body, "", Rect2(572, 360, 516, 88), 22)
	risk_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rations_note = PixelSheet.label(body, "实际餐耗在归航时结算。", Rect2(380, 450, 708, 32), 18, CampStyle.MUTED)
	PixelSheet.line(body, Rect2(380, 488, 708, 1))
	preview_text = PixelSheet.label(body, "", Rect2(380, 450, 708, 32), 18, CampStyle.DANGER)
	preview_text.hide()
	back_button = _button(body, "保留食物 / 返回", Rect2(380, 508, 390, 60), func() -> void: closed.emit())
	train_button = _button(body, "预览训练 →", Rect2(792, 508, 296, 60), _open_confirmation, 30)
	PixelMenu.primary(train_button)
	status = PixelSheet.label(body, "", Rect2(380, 442, 708, 44), 18, CampStyle.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retry_button = _button(body, "重试原训练保存", Rect2(792, 508, 296, 60), func() -> void: retry_requested.emit(), 24)
	retry_button.hide()
	_build_confirmation()


func refresh(data: Dictionary, message: String = "", pending: bool = false) -> void:
	_data = data.duplicate(true)
	_busy = false
	_pending = pending
	_quote = {}
	_sheet.update_resources(data)
	for child: Node in _members.get_children():
		_members.remove_child(child)
		child.queue_free()
	member_buttons.clear()
	for member: Dictionary in _data.crew:
		if member.health <= 0:
			continue
		_add_member(member, pending)
	if not member_buttons.has(selected_member_id):
		selected_member_id = 0 if member_buttons.is_empty() else int(member_buttons.keys()[0])
	var member: Dictionary = SurvivorRoster.member(_data.crew, selected_member_id)
	preview_text.hide()
	if member.is_empty():
		detail.text = "暂无可训练队员"
		preview_text.text = "阵亡资料请在同行者档案中查看。"
		preview_text.show()
		risk_text.text = ""
	else:
		member_buttons[selected_member_id].button_pressed = true
		member_buttons[selected_member_id].add_theme_stylebox_override("normal", CampStyle.box(CampStyle.SELECTED, CampStyle.EDGE, 0))
		var role: int = TraitRules.role(member) - 1
		detail.text = TraitRules.NAMES[role]
		detail.tooltip_text = TraitRules.description(member).replace(" · PROJECT_TEMP", "")
		_effect_name.text = _effect_caption(role)
		_level_before.text = "Lv%d" % int(member.growth.trait.level)
		_progress_before.text = str(int(member.growth.trait.progress))
		_effect_before.text = _effect_value(member)
		_food_before.text = str(_data.food)
		var quote: Dictionary = TrainingRules.preview(_data, selected_member_id) if not pending else {"error": "原训练保存尚未确认，请重试；不会再次购买。"}
		_level_after.text = "—"
		_progress_after.text = "—"
		_effect_after.text = "—"
		_food_after.text = "—"
		if not quote.error.is_empty():
			preview_text.text = quote.error
			preview_text.show()
			risk_text.text = "当前食物 %d 粮\n同行 %d 人" % [_data.food, _data.journey.active_member_ids.size()]
		else:
			_quote = quote
			var next: Dictionary = SurvivorRoster.member(quote.after.crew, selected_member_id)
			_level_after.text = "Lv%d" % int(next.growth.trait.level)
			_progress_after.text = str(int(next.growth.trait.progress))
			_effect_after.text = _effect_value(next)
			_food_after.text = str(quote.after.food)
			preview_text.text = "累计特性进度 %d → %d；下次出击使用新效果。" % [member.growth.trait.progress, next.growth.trait.progress]
			risk_text.text = "同行 %d 人 · 下餐需 %d 粮；\n训练后剩余 %d 粮%s" % [_data.journey.active_member_ids.size(), quote.risk.required, quote.after.food,
				"，零补给归航仍够用。" if int(quote.risk.shortage) == 0 else "，零补给归航缺 %d 粮。" % int(quote.risk.shortage)]
			risk_text.add_theme_color_override("font_color", CampStyle.TEXT if int(quote.risk.shortage) == 0 else CampStyle.DANGER)
	train_button.disabled = _quote.is_empty() or pending
	train_button.visible = not pending
	retry_button.visible = pending
	status.text = message
	if not message.is_empty():
		preview_text.hide()
	_rations_note.visible = message.is_empty() and not preview_text.visible
	_link_focus()


func _add_member(member: Dictionary, pending: bool) -> void:
	var id: int = int(member.id)
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(316, 96)
	button.toggle_mode = true
	button.disabled = pending
	button.mouse_force_pass_scroll_events = false
	button.tooltip_text = member.call_sign
	button.add_theme_stylebox_override("normal", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("pressed", CampStyle.box(CampStyle.SELECTED, CampStyle.EDGE, 0))
	button.pressed.connect(_select.bind(id))
	_members.add_child(button)
	PixelSheet.art(button, SurvivorRoster.definition(id).portrait, Rect2(12, 8, 66, 76))
	var call_sign: String = str(member.call_sign)
	PixelSheet.label(button, call_sign if call_sign.length() <= 4 else call_sign.left(4) + "…", Rect2(90, 14, 124, 38), 26 if call_sign.length() <= 4 else 22)
	var hp: Label = PixelSheet.label(button, "%.0f / %.0f" % [member.health, SurvivorGrowth.maximum(_data, member)], Rect2(210, 17, 94, 32), 18)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar: ProgressBar = ProgressBar.new()
	bar.max_value = SurvivorGrowth.maximum(_data, member)
	bar.value = float(member.health)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(bar)
	PixelSheet.place(bar, Rect2(90, 62, 212, 12))
	member_buttons[id] = button


func _select(id: int) -> void:
	if _busy or _pending or confirmation.visible:
		return
	selected_member_id = id
	refresh(_data)
	member_buttons[id].grab_focus()


func _build_confirmation() -> void:
	_veil = ColorRect.new()
	_veil.color = Color(0.015, 0.05, 0.08, 0.64)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_veil)
	_veil.hide()
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认训练"
	confirmation.borderless = true
	confirmation.wrap_controls = false
	confirmation.theme = CampStyle.theme()
	confirmation.theme.set_stylebox("panel", "AcceptDialog", CampStyle.box(CampStyle.INK, Color.TRANSPARENT, 24))
	confirmation.theme.set_constant("buttons_min_height", "AcceptDialog", 60)
	confirmation.theme.set_constant("buttons_min_width", "AcceptDialog", 340)
	confirmation.ok_button_text = "花费1粮并训练"
	confirmation.cancel_button_text = "保留食物 / 取消"
	confirmation.confirmed.connect(_confirm)
	confirmation.canceled.connect(func() -> void:
		_confirmation_armed = false
		train_button.grab_focus.call_deferred())
	confirmation.visibility_changed.connect(func() -> void: _veil.visible = confirmation.visible)
	add_child(confirmation)
	var content: Control = Control.new()
	content.custom_minimum_size = Vector2(720, 404)
	confirmation.add_child(content)
	_confirm_portrait = PixelSheet.art(content, null, Rect2(8, 0, 70, 70))
	_confirm_title = PixelSheet.label(content, "", Rect2(94, 0, 620, 70), 32)
	_confirm_summary = PixelSheet.label(content, "", Rect2(8, 80, 704, 42), 26)
	PixelSheet.label(content, "特性等级", Rect2(8, 134, 284, 42), 26)
	_confirm_effect_name = PixelSheet.label(content, "", Rect2(8, 180, 284, 42), 26)
	PixelSheet.label(content, "食物库存", Rect2(8, 226, 284, 42), 26)
	for y: int in [134, 180, 226]:
		_confirm_values.append(PixelSheet.label(content, "", Rect2(330, y, 130, 42), 28))
		PixelSheet.label(content, "→", Rect2(480, y, 64, 42), 28)
		_confirm_values.append(PixelSheet.label(content, "", Rect2(586, y, 128, 42), 28, CampStyle.TEAL if y != 226 else CampStyle.TEXT))
	PixelSheet.label(content, "不增加人物经验、生命或日期。\n新效果用于下次出击。", Rect2(8, 286, 704, 64), 22)
	PixelSheet.line(content, Rect2(0, 356, 720, 1))
	_confirm_rations = PixelSheet.label(content, "", Rect2(8, 362, 704, 40), 22)
	for button: Button in [confirmation.get_ok_button(), confirmation.get_cancel_button()]:
		button.add_theme_font_size_override("font_size", 26)
	PixelMenu.primary(confirmation.get_ok_button())
	confirmation.get_cancel_button().add_theme_stylebox_override("normal", CampStyle.box(CampStyle.SURFACE, CampStyle.EDGE, 12))


func _open_confirmation() -> void:
	if _busy or _pending or _quote.is_empty() or confirmation.visible:
		return
	var member: Dictionary = SurvivorRoster.member(_data.crew, selected_member_id)
	var next: Dictionary = SurvivorRoster.member(_quote.after.crew, selected_member_id)
	_confirm_portrait.texture = SurvivorRoster.definition(selected_member_id).portrait
	_confirm_title.text = "确认训练%s？" % member.call_sign
	_confirm_title.add_theme_font_size_override("font_size", 32 if str(member.call_sign).length() <= 5 else 26)
	_confirm_summary.text = "将消耗1份食物，提升%s。" % detail.text
	_confirm_effect_name.text = _effect_name.text
	var values: Array[String] = ["Lv%d" % int(member.growth.trait.level), "Lv%d" % int(next.growth.trait.level), _effect_value(member), _effect_value(next), str(_data.food), str(_quote.after.food)]
	for index: int in range(values.size()):
		_confirm_values[index].text = values[index]
	_confirm_rations.text = "同行 %d 人 · 下餐需 %d 粮 · 训练后余 %d 粮" % [_data.journey.active_member_ids.size(), _quote.risk.required, _quote.after.food]
	_confirm_rations.add_theme_color_override("font_color", CampStyle.TEXT if int(_quote.risk.shortage) == 0 else CampStyle.DANGER)
	confirmation.dialog_text = ""
	# The legacy camp theme pass runs before this view opens. Keep this dialog's
	# approved opaque ink surface instead of the older generic panel colour.
	confirmation.theme.set_stylebox("panel", "AcceptDialog", CampStyle.box(CampStyle.INK, Color.TRANSPARENT, 24))
	_confirmation_armed = true
	confirmation.content_scale_size = Vector2i(768, 520)
	confirmation.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var ratio: float = minf(1.0, minf(get_viewport_rect().size.x / 1280.0, get_viewport_rect().size.y / 720.0))
	confirmation.popup_centered(Vector2i(Vector2(768, 520) * ratio))
	confirmation.get_cancel_button().grab_focus.call_deferred()


func _confirm() -> void:
	if not _confirmation_armed or _busy or _pending or _quote.is_empty():
		return
	_confirmation_armed = false
	var request: Dictionary = _quote.request.duplicate(true)
	_quote = {}
	_busy = true
	train_button.disabled = true
	confirmation.hide()
	status.text = "正在保存训练…"
	confirmed.emit(request)
	# A held Enter must not focus the next purchase after this confirmation.
	back_button.grab_focus.call_deferred()


func _link_focus() -> void:
	var sequence: Array[Button] = []
	for button: Button in member_buttons.values():
		if not button.disabled:
			sequence.append(button)
	if not train_button.disabled:
		sequence.append(train_button)
	if retry_button.visible:
		sequence.append(retry_button)
	sequence.append(back_button)
	for index: int in range(sequence.size()):
		sequence[index].focus_next = sequence[(index + 1) % sequence.size()].get_path()
		sequence[index].focus_previous = sequence[(index - 1 + sequence.size()) % sequence.size()].get_path()


func _effect_caption(role: int) -> String:
	return ["射击间隔缩短", "搜刮耗时减少", "移动速度提高"][role]


func _effect_value(member: Dictionary) -> String:
	var role: int = TraitRules.role(member) - 1
	var kind: String = ["shot", "search", "move"][role]
	var factor: float = TraitRules.factor(member, kind)
	return "%.1f%%" % ((factor - 1.0 if role == 2 else 1.0 - factor) * 100.0)


func _button(parent: Node, caption: String, bounds: Rect2, action: Callable, font: int = 27) -> Button:
	var button: Button = PixelSheet.button(parent, caption, bounds, font)
	button.mouse_force_pass_scroll_events = false
	button.pressed.connect(action)
	return button
