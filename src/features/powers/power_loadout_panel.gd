class_name PowerLoadoutPanel
extends VBoxContainer
## Camp-only choices. The existing edit transaction owns the result.
signal requested(ability_id: String)
signal second_requested(ability_id: String)
signal investment_requested(choice: String)
signal retry_requested
var choices: Dictionary[String,Button]={}
var second_choices: Dictionary[String, Button] = {}
var purchases: Dictionary[String, Button] = {}
var status: Label
var confirmation: ConfirmationDialog
var retry_button: Button
var _balance: Label
var _first: Label
var _second: Label
var _freeze: Label
var _second_row: HBoxContainer
var _investment_row: HBoxContainer
var _choice: String = ""

func _ready() -> void:
	_balance = CampStyle.label("", 16, CampStyle.TEAL)
	add_child(_balance)
	_first = CampStyle.label("特殊能力 · 独立1槽", 16)
	choices = _slot_row(_first, requested)
	_second = CampStyle.label("", 16)
	second_choices = _slot_row(_second, second_requested)
	_second_row = _second.get_parent()
	_investment_row = HBoxContainer.new()
	add_child(_investment_row)
	_freeze = CampStyle.label("", 16, CampStyle.TEAL)
	_freeze.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_investment_row.add_child(_freeze)
	for choice: String in [PowerState.SECOND_SLOT, PowerState.FREEZE]:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(154, 40)
		button.pressed.connect(_confirm.bind(choice))
		purchases[choice] = button
		if choice == PowerState.SECOND_SLOT:
			_second_row.add_child(button)
		else:
			_investment_row.add_child(button)
	retry_button = Button.new()
	retry_button.text = "重试保存本次整备"
	retry_button.custom_minimum_size.y = 40
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	add_child(retry_button)
	status=CampStyle.label("", 15, CampStyle.MUTED)
	add_child(status)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认能力投资"
	confirmation.ok_button_text = "确认购买"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(func() -> void: investment_requested.emit(_choice))
	add_child(confirmation)

func _slot_row(title: Label, choice_requested: Signal) -> Dictionary[String, Button]:
	var buttons: Dictionary[String, Button] = {}
	var row: HBoxContainer=HBoxContainer.new()
	add_child(row)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	for id: String in [SpecialPowers.SPEED, SpecialPowers.FREEZE, SpecialPowers.SUPPRESSION, SpecialPowers.RADIO, ""]:
		var button: Button=Button.new()
		button.text=PowerActions.name_for(id) if not id.is_empty() else "卸下"
		button.custom_minimum_size=Vector2(130,40)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if not id.is_empty():
			button.icon = preload("res://assets/powers/heal.svg") if id == SpecialPowers.RADIO \
				else load("res://assets/powers/%s.svg" % id)
			button.expand_icon=true
			button.add_theme_constant_override("icon_max_width",28)
		button.pressed.connect(func()->void: choice_requested.emit(id))
		row.add_child(button)
		buttons[id]=button
	return buttons

func present(camp: Dictionary, editable: bool, retry: bool = false) -> void:
	visible=PowerState.enabled(camp)
	if not visible: return
	var value: Dictionary=camp.journey.build.powers
	var catalog: Dictionary = SpecialPowers.policy(int(value.version))
	var progression: bool = PowerState.progression(value)
	var slots: Array = value.slots if progression else [value.slot]
	var upgraded: bool = progression and value.investments.freeze != 0
	retry_button.visible = retry
	_balance.visible = progression
	_second_row.visible = progression
	_investment_row.visible = progression
	_first.text = "第一槽 · " + _equipped(slots[0], upgraded) if progression else "特殊能力 · 独立1槽"
	_present_choices(choices, catalog, value.owned, slots[0], slots[1] if slots.size() == 2 else "", editable)
	status.text = "已拥有 %d/%d · 装备行动主点搜获，归航确认后入库。每个已装能力每次出击可用一次。" % [value.owned.size(),catalog.size()]
	if not progression:
		return
	var second_open: bool = slots.size() == 2
	_balance.text = "特殊能力  /  余额 %d 币" % int(camp.cash)
	_second.text = "第二槽 · " + (_equipped(slots[1], upgraded) if second_open else "未解锁")
	if second_open:
		_present_choices(second_choices, catalog, value.owned, slots[1], slots[0], editable)
	else:
		for button: Button in second_choices.values():
			button.hide()
	_freeze.text = "全域冻结 · %d 秒 → %d 秒" % [int(SpecialPowers.duration(SpecialPowers.FREEZE,false)), int(SpecialPowers.UPGRADED_FREEZE_SECONDS)]
	_present_purchase(camp, PowerState.SECOND_SLOT, "开启", editable)
	_present_purchase(camp, PowerState.FREEZE, "强化", editable)

func _present_choices(buttons: Dictionary[String, Button], catalog: Dictionary, owned: Array, equipped: String,
		other: String, editable: bool) -> void:
	var three_choices: bool = catalog.has(SpecialPowers.SUPPRESSION)
	for id: String in buttons:
		var button: Button = buttons[id]
		button.visible = id.is_empty() or catalog.has(id)
		button.custom_minimum_size.x = 104.0 if catalog.has(SpecialPowers.RADIO) else 130.0
		var available: bool = id.is_empty() or id in owned
		var elsewhere: bool = not id.is_empty() and id == other
		var caption: String = PowerActions.name_for(id) if not id.is_empty() else "卸下"
		var detail: String = caption + (" · 已装配" if id == equipped and not id.is_empty() else " · 另一槽" if elsewhere else " · 未拥有" if not available else "")
		button.text = caption if three_choices else detail
		button.tooltip_text = detail
		if id == SpecialPowers.SUPPRESSION:
			button.tooltip_text += "\n12 秒内普通、疾奔、重压感染者的直接近战伤害减半。"
		elif id == SpecialPowers.RADIO:
			button.tooltip_text += "\n" + SpecialPowers.RADIO_HELP
		_enable(button, editable and available and id != equipped and not elsewhere)

func _equipped(id: String, upgraded: bool) -> String:
	if id == SpecialPowers.RADIO:
		return PowerActions.name_for(id) + " · 瞬时治疗"
	return "空槽" if id.is_empty() else "%s · %d 秒" % [PowerActions.name_for(id),int(SpecialPowers.duration(id,upgraded))]

func _present_purchase(camp: Dictionary, choice: String, verb: String, editable: bool) -> void:
	var problem: String = PowerState.investment_problem(camp, choice)
	var button: Button = purchases[choice]
	button.text = "%s · %d 币" % [verb,PowerState.INVESTMENT_COST]
	if not problem.is_empty():
		button.text = problem if problem in ["已解锁", "已强化"] else button.text + " · " + problem
	_enable(button, editable and problem.is_empty())

func _enable(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		button.release_focus()

func _confirm(choice: String) -> void:
	_choice = choice
	var title: String = "开启第二槽" if choice == PowerState.SECOND_SLOT else "强化全域冻结"
	confirmation.dialog_text = "%s需要 %d 币，保存确认后生效。" % [title,PowerState.INVESTMENT_COST]
	confirmation.popup_centered(Vector2i(480, 190))
