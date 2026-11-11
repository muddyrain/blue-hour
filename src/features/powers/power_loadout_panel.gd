class_name PowerLoadoutPanel
extends VBoxContainer
## Read-only camp controls. Purchases use the existing confirmed camp edit.
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

func _ready() -> void:
	_balance = CampStyle.label("", 16, CampStyle.TEAL)
	add_child(_balance)
	choices = _slot_row(0, requested)
	second_choices = _slot_row(1, second_requested)
	third_choices = _slot_row(2, third_requested)
	_investment_grid = GridContainer.new()
	_investment_grid.columns = 2
	_investment_grid.add_theme_constant_override("h_separation", 8)
	add_child(_investment_grid)
	for choice: String in [PowerState.SECOND_SLOT, PowerState.THIRD_SLOT, PowerState.FREEZE, "speed", "suppression", "radio"]:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(230, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(_confirm.bind(choice))
		purchases[choice] = button
		_investment_grid.add_child(button)
	retry_button = Button.new()
	retry_button.text = "重试保存本次整备"
	retry_button.custom_minimum_size.y = 40
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	add_child(retry_button)
	status = CampStyle.label("", 15, CampStyle.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认能力投资"
	confirmation.ok_button_text = "确认并保存"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(func() -> void: investment_requested.emit(_investment_value))
	add_child(confirmation)

func _slot_row(index: int, choice_requested: Signal) -> Dictionary[String, Button]:
	var buttons: Dictionary[String, Button] = {}
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	_rows.append(column)
	var title: Label = CampStyle.label("", 16)
	column.add_child(title)
	_titles.append(title)
	var row: GridContainer = GridContainer.new()
	row.columns = 5
	row.add_theme_constant_override("h_separation", 6)
	column.add_child(row)
	for id: String in [SpecialPowers.SPEED, SpecialPowers.FREEZE, SpecialPowers.SUPPRESSION, SpecialPowers.RADIO, ""]:
		var button: Button = Button.new()
		button.text = PowerActions.name_for(id) if not id.is_empty() else "卸下"
		button.custom_minimum_size = Vector2(96, 38)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if not id.is_empty():
			button.icon = preload("res://assets/powers/heal.svg") if id == SpecialPowers.RADIO else load("res://assets/powers/%s.svg" % id)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 22)
		button.pressed.connect(func() -> void: choice_requested.emit(id))
		row.add_child(button)
		buttons[id] = button
	column.name = "PowerSlot%d" % index
	return buttons

func present(camp: Dictionary, editable: bool, retry: bool = false) -> void:
	visible = PowerState.enabled(camp)
	if not visible:
		return
	_camp = camp.duplicate(true)
	var value: Dictionary = camp.journey.build.powers
	var catalog: Dictionary = SpecialPowers.policy(int(value.version))
	var progression: bool = PowerState.progression(value)
	var equipment: Dictionary = PowerState.loadout(value) if progression else {}
	var slots: Array = value.slots if progression else [value.slot]
	var lists: Array = [choices, second_choices, third_choices]
	for index: int in range(_rows.size()):
		_rows[index].visible = index < slots.size()
		if index >= slots.size():
			continue
		var id: String = slots[index]
		var detail: String = "空槽" if id.is_empty() else PowerActions.name_for(id)
		if not id.is_empty():
			detail += " · 最多 %.0f HP" % SpecialPowers.radio_amount(equipment) if id == SpecialPowers.RADIO else " · %.0f 秒" % SpecialPowers.effect_duration(equipment, id)
			if SpecialPowers.upgraded(equipment, id):
				detail += " · 已强化"
		_titles[index].text = "特殊槽 %d · %s" % [index + 1, detail]
		_present_choices(lists[index], catalog, value.owned, slots, index, editable)
	_balance.text = "特殊能力 %d/%d 槽 · 余额 %d 币" % [slots.size(), 3 if value.version == SpecialPowers.M48_VERSION else 2 if progression else 1, int(camp.cash)]
	status.text = "已拥有 %d/%d · 主点搜获并确认归航后入库；每个已装能力每次出击一次。" % [value.owned.size(), catalog.size()]
	retry_button.visible = retry
	_investment_grid.visible = progression
	for choice: String in purchases:
		var button: Button = purchases[choice]
		button.visible = progression and choice in SpecialPowers.investment_keys(int(value.version))
		if not button.visible:
			continue
		var issue: String = PowerState.investment_problem(camp, choice)
		button.text = "%s · %d 币" % [_investment_name(choice), PowerState.investment_cost(camp, choice)]
		button.tooltip_text = _investment_effect(choice) if issue.is_empty() else issue
		if issue in ["已解锁", "已强化"]:
			button.text = _investment_name(choice) + " · " + issue
		_enable(button, editable and issue.is_empty())

func _present_choices(buttons: Dictionary, catalog: Dictionary, owned: Array, slots: Array, slot: int, editable: bool) -> void:
	for id: String in buttons:
		var button: Button = buttons[id]
		button.visible = id.is_empty() or catalog.has(id)
		var available: bool = id.is_empty() or id in owned
		var elsewhere: bool = not id.is_empty() and id in slots and id != slots[slot]
		button.tooltip_text = (PowerActions.name_for(id) if not id.is_empty() else "卸下") + (" · 已装配" if id == slots[slot] and not id.is_empty() else " · 其他槽" if elsewhere else " · 未拥有" if not available else "")
		if id == SpecialPowers.RADIO:
			button.tooltip_text += "\n没有户外受伤目标时保留次数；恢复不超过生命上限。"
		_enable(button, editable and available and id != slots[slot] and not elsewhere)

func _investment_name(choice: String) -> String:
	return {PowerState.SECOND_SLOT:"开启第二槽", PowerState.THIRD_SLOT:"开启第三槽", "freeze":"强化全域冻结", "speed":"强化疾行号令", "suppression":"强化抑制脉冲", "radio":"强化急救广播"}.get(choice, choice)

func _investment_effect(choice: String) -> String:
	return {PowerState.SECOND_SLOT:"独立特殊槽 1 → 2", PowerState.THIRD_SLOT:"独立特殊槽 2 → 3", "freeze":"冻结 4 → 7 秒", "speed":"疾行 ×1.50，8 → 12 秒", "suppression":"适用直接近战伤害 ×0.50，12 → 16 秒", "radio":"单次最多恢复 24 → 40 HP"}.get(choice, "")

func _enable(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		button.release_focus()

func _confirm(choice: String) -> void:
	if _camp.is_empty() or not PowerState.investment_problem(_camp, choice).is_empty():
		return
	_choice = choice
	_investment_value = BuildState.investment_value(_camp, choice) if BuildState.m48_enabled(_camp) else choice
	var cost: int = PowerState.investment_cost(_camp, choice)
	confirmation.dialog_text = "%s\n%s\n花费 %d 币 · 保存后余 %d 币。" % [_investment_name(choice), _investment_effect(choice), cost, int(_camp.cash) - cost]
	confirmation.popup_centered(Vector2i(520, 210))
