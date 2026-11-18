class_name PowerLoadoutPanel
extends VBoxContainer
## Real owned powers and independent slots; purchases remain confirmed camp edits.
signal requested(ability_id: String)
signal second_requested(ability_id: String)
signal third_requested(ability_id: String)
signal investment_requested(choice: String)
signal retry_requested
var choices: Dictionary[String, Button] = {}
var second_choices: Dictionary[String, Button] = {}
var third_choices: Dictionary[String, Button] = {}
var purchases: Dictionary[String, Button] = {}
var status: Label
var confirmation: ConfirmationDialog
var retry_button: Button
var _balance: Label
var _titles: Array[Label] = []
var _rows: Array[Control] = []
var _investment_grid: GridContainer
var _choice: String = ""
var _investment_value: String = ""
var _camp: Dictionary = {}
var _slot_boxes: HBoxContainer
var _power_columns: Dictionary[String, VBoxContainer] = {}
var _owned_labels: Dictionary[String, Label] = {}

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	PixelMenu.divider(self)
	_balance = CampStyle.label("特殊能力", 30)
	_balance.add_theme_font_override("font", CampStyle.BOLD_FONT)
	add_child(_balance)
	PixelMenu.divider(self)
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	add_child(body)
	_slot_boxes = HBoxContainer.new()
	_slot_boxes.custom_minimum_size.x = 300
	_slot_boxes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_boxes.add_theme_constant_override("separation", 12)
	body.add_child(_slot_boxes)
	for index: int in range(3):
		var panel: PanelContainer = PanelContainer.new()
		panel.custom_minimum_size.y = 136
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL if index == 0 else CampStyle.EDGE, 12))
		_slot_boxes.add_child(panel)
		_rows.append(panel)
		var content: VBoxContainer = VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(content)
		var title: Label = CampStyle.label("", 22)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_override("font", CampStyle.BOLD_FONT)
		content.add_child(title)
		_titles.append(title)
		var remove: Button = Button.new()
		remove.text = "卸下"
		remove.add_theme_font_size_override("font_size", 18)
		content.add_child(remove)
		if index == 0:
			choices[""] = remove
			remove.pressed.connect(func() -> void: requested.emit(""))
		elif index == 1:
			second_choices[""] = remove
			remove.pressed.connect(func() -> void: second_requested.emit(""))
		else:
			third_choices[""] = remove
			remove.pressed.connect(func() -> void: third_requested.emit(""))
	for choice: String in [PowerState.SECOND_SLOT, PowerState.THIRD_SLOT]:
		var button: Button = Button.new()
		button.custom_minimum_size.y = 136
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 22)
		button.icon = PixelSheet.symbol_texture("lock")
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", 36)
		button.add_theme_constant_override("h_separation", 4)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for button_state: String in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(button_state, CampStyle.box(CampStyle.PANEL, CampStyle.EDGE, 4))
		button.pressed.connect(_confirm.bind(choice))
		_slot_boxes.add_child(button)
		purchases[choice] = button
	_investment_grid = GridContainer.new()
	_investment_grid.columns = 4
	_investment_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_investment_grid.size_flags_stretch_ratio = 1.75
	_investment_grid.add_theme_constant_override("h_separation", 14)
	body.add_child(_investment_grid)
	var ids: Array[String] = [SpecialPowers.SPEED, SpecialPowers.FREEZE, SpecialPowers.SUPPRESSION, SpecialPowers.RADIO]
	var investment_keys: Array[String] = ["speed", PowerState.FREEZE, "suppression", "radio"]
	var symbols: Array[String] = ["sprint", "freeze", "pulse", "radio"]
	for index: int in range(ids.size()):
		var id: String = ids[index]
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 5)
		_investment_grid.add_child(column)
		_power_columns[id] = column
		var frame: PanelContainer = PanelContainer.new()
		frame.custom_minimum_size = Vector2(68, 68)
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		frame.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.EDGE, 5))
		column.add_child(frame)
		var art: TextureRect = TextureRect.new()
		art.texture = PixelSheet.symbol_texture(symbols[index])
		art.custom_minimum_size = Vector2(56, 56)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.add_child(art)
		var title: Label = CampStyle.label(PowerActions.name_for(id), 20)
		title.add_theme_font_override("font", CampStyle.BOLD_FONT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.clip_text = true
		column.add_child(title)
		for slot: int in range(3):
			var button: Button = Button.new()
			button.custom_minimum_size.y = 30
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.add_theme_font_size_override("font_size", 17)
			column.add_child(button)
			if slot == 0:
				choices[id] = button
				button.pressed.connect(func() -> void: requested.emit(id))
			elif slot == 1:
				second_choices[id] = button
				button.pressed.connect(func() -> void: second_requested.emit(id))
			else:
				third_choices[id] = button
				button.pressed.connect(func() -> void: third_requested.emit(id))
		var purchase: Button = Button.new()
		purchase.custom_minimum_size.y = 30
		purchase.add_theme_font_size_override("font_size", 17)
		purchase.pressed.connect(_confirm.bind(investment_keys[index]))
		column.add_child(purchase)
		purchases[investment_keys[index]] = purchase
	retry_button = Button.new()
	retry_button.text = "重试保存本次整备"
	retry_button.custom_minimum_size.y = 40
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	add_child(retry_button)
	status = CampStyle.label("", 18, CampStyle.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认能力投资"
	confirmation.borderless = true
	confirmation.dialog_autowrap = true
	confirmation.ok_button_text = "确认并保存"
	confirmation.cancel_button_text = "保留 / 返回"
	confirmation.confirmed.connect(func() -> void: investment_requested.emit(_investment_value))
	add_child(confirmation)
	confirmation.get_label().add_theme_font_size_override("font_size", 24)
	confirmation.get_cancel_button().custom_minimum_size = Vector2(220, 52)
	confirmation.get_ok_button().custom_minimum_size = Vector2(220, 52)
	PixelMenu.primary(confirmation.get_ok_button())

func present(camp: Dictionary, editable: bool, retry: bool = false) -> void:
	visible = PowerState.enabled(camp)
	if not visible: return
	_camp = camp.duplicate(true)
	var value: Dictionary = camp.journey.build.powers
	var catalog: Dictionary = SpecialPowers.policy(int(value.version))
	var progression: bool = PowerState.progression(value)
	var equipment: Dictionary = PowerState.loadout(value) if progression else {}
	var slots: Array = value.slots if progression else [value.slot]
	var lists: Array = [choices, second_choices, third_choices]
	for index: int in range(_rows.size()):
		_rows[index].visible = index < slots.size()
		for button: Button in lists[index].values(): button.visible = index < slots.size()
		if index >= slots.size(): continue
		var id: String = slots[index]
		var detail: String = "空槽" if id.is_empty() else PowerActions.name_for(id)
		if not id.is_empty():
			detail += "\n最多 %.0f HP" % SpecialPowers.radio_amount(equipment) if id == SpecialPowers.RADIO else "\n%.0f 秒" % SpecialPowers.effect_duration(equipment, id)
			if SpecialPowers.upgraded(equipment, id): detail += " · 已强化"
		_titles[index].text = detail if slots.size() == 1 else "槽 %d\n%s" % [index + 1, detail]
		_present_choices(lists[index], catalog, value.owned, slots, index, editable)
	_balance.text = "特殊能力   |   %d / %d 槽" % [slots.size(), 3 if value.version == SpecialPowers.M48_VERSION else 2 if progression else 1]
	status.text = "装备行动回收，归航确认后入库；每个已装能力每次出击一次。"
	status.tooltip_text = "已拥有 %d / %d" % [value.owned.size(), catalog.size()]
	retry_button.visible = retry
	var ids: Dictionary = {"speed":SpecialPowers.SPEED, "freeze":SpecialPowers.FREEZE, "suppression":SpecialPowers.SUPPRESSION, "radio":SpecialPowers.RADIO}
	for choice: String in purchases:
		var button: Button = purchases[choice]
		var slot_purchase: bool = choice in [PowerState.SECOND_SLOT, PowerState.THIRD_SLOT]
		button.visible = progression and choice in SpecialPowers.investment_keys(int(value.version))
		if slot_purchase:
			button.visible = button.visible and ((choice == PowerState.SECOND_SLOT and slots.size() == 1) or (choice == PowerState.THIRD_SLOT and slots.size() == 2))
		else:
			button.visible = button.visible and ids.get(choice, "") in value.owned
		var issue: String = PowerState.investment_problem(camp, choice)
		button.text = ("开启第 %d 特技槽\n%d 币" % [slots.size() + 1, PowerState.investment_cost(camp, choice)]) if slot_purchase else "强化 · %d 币" % PowerState.investment_cost(camp, choice)
		button.tooltip_text = _investment_effect(choice) if issue.is_empty() else issue
		if issue in ["已解锁", "已强化"]: button.text = issue
		_enable(button, editable and issue.is_empty())

func _present_choices(buttons: Dictionary, catalog: Dictionary, owned: Array, slots: Array, slot: int, editable: bool) -> void:
	for id: String in buttons:
		var button: Button = buttons[id]
		button.visible = (not slots[slot].is_empty()) if id.is_empty() else catalog.has(id)
		var available: bool = id.is_empty() or id in owned
		var elsewhere: bool = not id.is_empty() and id in slots and id != slots[slot]
		button.text = "卸下" if id.is_empty() else "未拥有" if not available else "已装备" if id == slots[slot] else "装入槽 %d" % (slot + 1)
		button.tooltip_text = (PowerActions.name_for(id) if not id.is_empty() else "卸下") + (" · 已装配" if id == slots[slot] and not id.is_empty() else " · 其他槽" if elsewhere else " · 未拥有" if not available else "")
		if id == SpecialPowers.RADIO: button.tooltip_text += "\n没有户外受伤目标时保留次数；恢复不超过生命上限。"
		_enable(button, editable and available and id != slots[slot] and not elsewhere)

func _investment_name(choice: String) -> String:
	return {PowerState.SECOND_SLOT:"开启第二槽", PowerState.THIRD_SLOT:"开启第三槽", "freeze":"强化全域冻结", "speed":"强化疾行号令", "suppression":"强化抑制脉冲", "radio":"强化急救广播"}.get(choice, choice)

func _investment_effect(choice: String) -> String:
	return {PowerState.SECOND_SLOT:"独立特殊槽 1 → 2", PowerState.THIRD_SLOT:"独立特殊槽 2 → 3", "freeze":"冻结 4 → 7 秒", "speed":"疾行 ×1.50，8 → 12 秒", "suppression":"适用直接近战伤害 ×0.50，12 → 16 秒", "radio":"单次最多恢复 24 → 40 HP"}.get(choice, "")

func _enable(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled: button.release_focus()

func _confirm(choice: String) -> void:
	if _camp.is_empty() or not PowerState.investment_problem(_camp, choice).is_empty(): return
	_choice = choice
	_investment_value = BuildState.investment_value(_camp, choice) if BuildState.m48_enabled(_camp) else choice
	var cost: int = PowerState.investment_cost(_camp, choice)
	confirmation.dialog_text = "%s\n\n%s\n花费 %d 币 · 保存后余 %d 币。" % [_investment_name(choice), _investment_effect(choice), cost, int(_camp.cash) - cost]
	confirmation.popup_centered(Vector2i(700, 300))
