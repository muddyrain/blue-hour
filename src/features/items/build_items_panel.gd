class_name BuildItemsPanel
extends VBoxContainer
## Camp-only view. A request never changes the displayed confirmed slots by itself.

signal requested(slot: int, item_id: String)
signal investment_requested(choice: String)

const LINER_ICON: Texture2D = preload("res://assets/ui/m38/impact-liner.svg")

var slot_choices: Array[OptionButton] = []
var status: Label
var inventory: Label
var _effects: Array[Label] = []
var _owned: Array = []
var _slots: Array = ["", ""]
var _pool: int = BuildItems.VERSION
var _built: bool = false
var _camp: Dictionary = {}
var _columns: Array[Control] = []
var _upgrade_row: HBoxContainer
var _upgrade_choice: OptionButton
var _upgrade_button: Button
var _slot_button: Button
var _confirmation: ConfirmationDialog
var _investment: String = ""
var _investment_value: String = ""


func _ready() -> void:
	_build()


func present(owned: Array, slots: Array, saved: bool, enabled: bool = true, opening_plan: String = "",
		pool: int = BuildItems.VERSION, camp: Dictionary = {}) -> void:
	_build()
	_camp = camp.duplicate(true)
	var issue: String = BuildItems.problem(owned, slots, pool)
	if not issue.is_empty():
		status.text = "道具配置无效 · 无法换装"
		status.add_theme_color_override("font_color", CampStyle.AMBER)
		inventory.text = ""
		for choice: OptionButton in slot_choices:
			choice.disabled = true
		return
	_owned = owned.duplicate(true)
	_slots = slots.duplicate(true)
	_pool = pool
	var names: PackedStringArray = []
	var definitions: Dictionary = BuildItems.definitions(pool)
	var available: Array[String] = BuildItems.ids(pool)
	for id: String in available:
		if id in owned:
			names.append(definitions[id].name)
	inventory.text = "库存 %d/%d%s" % [owned.size(), available.size(), " · 已集齐" if owned.size() == available.size() else ""]
	inventory.text += "：" + "、".join(names) if not names.is_empty() else " · 装备搜寻回收，归航确认后入库"
	if OpeningBuild.PLANS.has(opening_plan):
		inventory.text += "  ·  开局 %s" % OpeningBuild.PLANS[opening_plan].title
	status.text = "已保存 · 下一行动生效" if saved else "保存未确认 · 保持原配装"
	status.add_theme_color_override("font_color", CampStyle.TEAL if saved else CampStyle.AMBER)
	for slot: int in range(slot_choices.size()):
		_columns[slot].visible = slot < slots.size()
		if slot >= slots.size():
			continue
		var choice: OptionButton = slot_choices[slot]
		choice.clear()
		choice.add_item("槽 %d · 空槽 / 卸下" % (slot + 1))
		choice.set_item_metadata(0, "")
		for id: String in available:
			if id not in owned:
				continue
			var index: int = choice.item_count
			var title: String = "槽 %d · %s" % [slot + 1, definitions[id].name]
			if id == BuildItems.LINER:
				choice.add_icon_item(LINER_ICON, title)
			else:
				choice.add_item(title)
			choice.set_item_metadata(index, id)
			choice.set_item_tooltip(index, BuildItems.effect_text(id, id in camp.get("journey", {}).get("build", {}).get("progression", {}).get("enhanced", []), pool))
			choice.set_item_disabled(index, id in slots and id != slots[slot])
		choice.select(_index_for(choice, slots[slot]))
		choice.disabled = not enabled
		_effects[slot].text = "空槽也可出发" if slots[slot].is_empty() else BuildItems.effect_text(slots[slot], slots[slot] in camp.get("journey", {}).get("build", {}).get("progression", {}).get("enhanced", []), pool)
		choice.tooltip_text = "选择库存道具替换本槽；保存成功后供下一行动使用。"
	_present_investments(enabled)


func _build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 5)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	add_child(heading)
	var title: Label = CampStyle.label("本局道具 · 小队共享", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	status = CampStyle.label("", 14, CampStyle.TEAL)
	heading.add_child(status)
	inventory = CampStyle.label("", 14)
	inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.tooltip_text = "仅已开启并装备的槽位生效；同一件不能占多个槽。未装备道具保留在本局库存。"
	add_child(inventory)
	var row: GridContainer = GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 12)
	add_child(row)
	for slot: int in range(4):
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0
		column.add_theme_constant_override("separation", 3)
		row.add_child(column)
		_columns.append(column)
		var choice: OptionButton = OptionButton.new()
		choice.custom_minimum_size = Vector2(190, 34)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.fit_to_longest_item = false
		choice.item_selected.connect(_selected.bind(slot))
		choice.add_theme_font_size_override("font_size", 16)
		column.add_child(choice)
		slot_choices.append(choice)
		var effect: Label = CampStyle.label("", 14, CampStyle.TEAL)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(effect)
		_effects.append(effect)

	_upgrade_row = HBoxContainer.new()
	add_child(_upgrade_row)
	_slot_button = Button.new()
	_slot_button.custom_minimum_size.y = 38
	_slot_button.pressed.connect(_confirm_investment.bind("next_slot"))
	_upgrade_row.add_child(_slot_button)
	_upgrade_choice = OptionButton.new()
	_upgrade_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_choice.fit_to_longest_item = false
	_upgrade_choice.item_selected.connect(func(_index: int) -> void: _refresh_upgrade())
	_upgrade_row.add_child(_upgrade_choice)
	_upgrade_button = Button.new()
	_upgrade_button.text = "强化 · 10 币"
	_upgrade_button.pressed.connect(func() -> void:
		if _upgrade_choice.item_count > 0:
			_confirm_investment(_upgrade_choice.get_item_metadata(_upgrade_choice.selected)))
	_upgrade_row.add_child(_upgrade_button)
	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "确认被动投资"
	_confirmation.ok_button_text = "确认并保存"
	_confirmation.cancel_button_text = "取消"
	_confirmation.confirmed.connect(func() -> void: investment_requested.emit(_investment_value))
	add_child(_confirmation)


func _selected(index: int, slot: int) -> void:
	var choice: OptionButton = slot_choices[slot]
	var id: String = choice.get_item_metadata(index)
	# OptionButton selects before its signal; restore confirmation before calling the owner.
	choice.select(_index_for(choice, _slots[slot]))
	if id == _slots[slot] or choice.disabled:
		return
	var proposed: Array = _slots.duplicate(true)
	proposed[slot] = id
	if BuildItems.problem(_owned, proposed, _pool).is_empty():
		requested.emit(slot, id)


func _index_for(choice: OptionButton, id: String) -> int:
	for index: int in range(choice.item_count):
		if choice.get_item_metadata(index) == id:
			return index
	return 0


func _present_investments(editable: bool) -> void:
	_upgrade_row.visible = not _camp.is_empty() and BuildState.m48_enabled(_camp)
	if not _upgrade_row.visible:
		return
	var offer: Dictionary = BuildState.investment_offer(_camp, "next_slot")
	_slot_button.text = "开启第 %d 槽 · %d 币" % [_slots.size() + 1, int(offer.cost)] if _slots.size() < 4 else "被动槽已满"
	_slot_button.disabled = not editable or not offer.available
	_slot_button.tooltip_text = offer.reason if not offer.available else offer.summary
	_upgrade_choice.clear()
	for id: String in _owned:
		_upgrade_choice.add_item(BuildItems.definitions(_pool)[id].name + (" · 已强化" if id in _camp.journey.build.progression.enhanced else ""))
		_upgrade_choice.set_item_metadata(_upgrade_choice.item_count - 1, id)
	_upgrade_choice.disabled = not editable or _owned.is_empty()
	_upgrade_button.set_meta("editable", editable)
	_refresh_upgrade()


func _refresh_upgrade() -> void:
	if _camp.is_empty() or _upgrade_choice.item_count == 0:
		_upgrade_button.disabled = true
		return
	var id: String = _upgrade_choice.get_item_metadata(_upgrade_choice.selected)
	var offer: Dictionary = BuildState.investment_offer(_camp, id)
	_upgrade_button.disabled = not bool(_upgrade_button.get_meta("editable", true)) or not offer.available
	_upgrade_button.tooltip_text = offer.summary if offer.available else offer.reason
	_upgrade_choice.tooltip_text = BuildItems.effect_text(id, false, _pool) + " → " + BuildItems.effect_text(id, true, _pool)


func _confirm_investment(choice: String) -> void:
	var offer: Dictionary = BuildState.investment_offer(_camp, choice)
	if not offer.available:
		return
	_investment = choice
	_investment_value = BuildState.investment_value(_camp, choice)
	_confirmation.dialog_text = "%s\n花费 %d 币 · 保存后余 %d 币。" % [offer.summary, offer.cost, int(_camp.cash) - int(offer.cost)]
	_confirmation.popup_centered(Vector2i(610, 200))
