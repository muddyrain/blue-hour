class_name TrainingPanel
extends PanelContainer
## View and confirmation intentions only; the original camp transaction owns every write.

signal closed
signal confirmed(request: Dictionary)
signal retry_requested

var player_mode: bool = false

var selected_member_id: int = 0
var member_buttons: Dictionary[int,Button] = {}
var train_button: Button
var retry_button: Button
var back_button: Button
var confirmation: ConfirmationDialog
var detail: Label
var preview_text: Label
var risk_text: Label
var status: Label
var _members: VBoxContainer
var _data: Dictionary = {}
var _quote: Dictionary = {}
var _busy: bool = false
var _pending: bool = false
var _confirmation_armed: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 48
	offset_right = -48
	offset_top = 80
	offset_bottom = -24
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	add_theme_stylebox_override("panel",CampStyle.box(CampStyle.PANEL,CampStyle.AMBER,24))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	add_child(column)
	_label(column,"篝火训练 / 为下次出击做准备",30)
	_label(column,"1份食物 → 本人特质进度+1，不增加经验、生命或日期。" if player_mode else "1份食物 → 本人Trait累计进度+1 · PROJECT_TEMP · 不增加普通XP、生命或日期",17)
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",24)
	column.add_child(body)
	var list_scroll: ScrollContainer = ScrollContainer.new()
	list_scroll.custom_minimum_size.x = 270
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	body.add_child(list_scroll)
	_members = VBoxContainer.new()
	_members.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_members.add_theme_constant_override("separation",10)
	list_scroll.add_child(_members)
	var info_scroll: ScrollContainer = ScrollContainer.new()
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(info_scroll)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation",18)
	info_scroll.add_child(info)
	detail = _label(info,"",21)
	preview_text = _label(info,"",20)
	risk_text = _label(info,"",19)
	risk_text.add_theme_color_override("font_color",CampStyle.AMBER)
	status = _label(column,"",17)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation",16)
	column.add_child(actions)
	train_button = _button(actions,"训练预览 → 确认花费1粮",_open_confirmation)
	retry_button = _button(actions,"重试原训练保存 / 不再次购买",func() -> void: retry_requested.emit())
	back_button = _button(actions,"返回营地 / Esc",func() -> void: closed.emit())
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认用食物训练"
	confirmation.ok_button_text = "花费1粮，训练这名成员"
	confirmation.cancel_button_text = "保留食物 / 取消"
	confirmation.confirmed.connect(_confirm)
	confirmation.canceled.connect(func() -> void:
		_confirmation_armed = false
		train_button.grab_focus.call_deferred())
	add_child(confirmation)


func refresh(data: Dictionary, message: String = "", pending: bool = false) -> void:
	_data = data.duplicate(true)
	_busy = false
	_pending = pending
	_quote = {}
	for child: Node in _members.get_children():
		_members.remove_child(child)
		child.queue_free()
	member_buttons.clear()
	for member: Dictionary in _data.crew:
		if member.health<=0:
			continue
		var id: int = int(member.id)
		var button: Button = _button(_members,"%02d  %s\n普通Lv%d · Trait Lv%d" % [id,member.call_sign,int(member.growth.level),int(member.growth.trait.level)],func() -> void: _select(id))
		button.tooltip_text = member.call_sign
		if RescuePoolState.is_family(_data):
			button.text = "%02d %s\n普通Lv%d · Trait Lv%d" % [id,member.call_sign if member.call_sign.length()<=5 else member.call_sign.left(4)+"…",int(member.growth.level),int(member.growth.trait.level)]
		button.toggle_mode = true
		button.disabled = pending
		member_buttons[id] = button
	if not member_buttons.has(selected_member_id):
		selected_member_id = 0 if member_buttons.is_empty() else int(member_buttons.keys()[0])
	var member: Dictionary = SurvivorRoster.member(_data.crew,selected_member_id)
	if member.is_empty():
		detail.text = "没有可训练的存活幸存者。阵亡资料请在档案中查看。"
		preview_text.text = ""
		risk_text.text = ""
	else:
		member_buttons[selected_member_id].button_pressed = true
		detail.text = "%02d %s · 普通Lv%d / %d XP · 生命%.0f/%.0f\n%s" % [selected_member_id,member.call_sign,int(member.growth.level),int(member.growth.xp_total),member.health,GrowthRules.maximum(member),(TraitRules.description(member).replace(" · PROJECT_TEMP", "") if player_mode else TraitRules.description(member))]
		var quote: Dictionary = TrainingRules.preview(_data,selected_member_id) if not pending else {"error":"原训练保存尚未确认，请重试；不会再次购买。"}
		if not quote.error.is_empty():
			preview_text.text = quote.error
			risk_text.text = "当前食物 %d · 存活 %d人" % [_data.food,_data.journey.active_member_ids.size()]
		else:
			_quote = quote
			var next: Dictionary = SurvivorRoster.member(quote.after.crew,selected_member_id)
			preview_text.text = "消耗1份食物 → 本人累计进度 %d → %d\nTrait Lv%d → Lv%d%s\n训练后：%s" % [member.growth.trait.progress,next.growth.trait.progress,member.growth.trait.level,next.growth.trait.level,"（本次不升级）" if member.growth.trait.level==next.growth.trait.level else "（下次出击使用新效果）",(TraitRules.description(next).replace(" · PROJECT_TEMP", "") if player_mode else TraitRules.description(next)).get_slice("\n",1)]
			risk_text.text = "存活%d人 · 食物%d − 训练1 = 剩余%d\n假设下次归航零补给：需%d粮，可能缺%d粮。\n静态风险预估；未执行晚餐，不预定死亡人选。" % [_data.journey.active_member_ids.size(),_data.food,quote.after.food,quote.risk.required,quote.risk.shortage]
	train_button.disabled = _quote.is_empty() or pending
	retry_button.visible = pending
	status.text = message if not message.is_empty() else "浏览、切换成员、取消与Esc均不保存或扣粮。"
	_link_focus()


func _select(id: int) -> void:
	if _busy or _pending or confirmation.visible:
		return
	selected_member_id = id
	refresh(_data)
	member_buttons[id].grab_focus()


func _open_confirmation() -> void:
	if _busy or _pending or _quote.is_empty() or confirmation.visible:
		return
	confirmation.dialog_text = "%s\n\n%s\n\n%s\n确认只花1粮、给该成员Trait进度+1；不增加普通XP或HP。" % [detail.text,preview_text.text,risk_text.text]
	_confirmation_armed = true
	confirmation.popup_centered(Vector2i(720,430))
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
	status.text = "正在保存训练…" if player_mode else "正在保存并确认原训练事务…"
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
		sequence[index].focus_next = sequence[(index+1)%sequence.size()].get_path()
		sequence[index].focus_previous = sequence[(index-1+sequence.size())%sequence.size()].get_path()


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label: Label = CampStyle.label(text,font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_force_pass_scroll_events = false
	button.pressed.connect(action)
	parent.add_child(button)
	return button
