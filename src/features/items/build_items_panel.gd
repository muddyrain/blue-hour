class_name BuildItemsPanel
extends VBoxContainer
## Camp-only view. A request never changes the displayed confirmed slots by itself.

signal requested(slot: int, item_id: String)

var slot_choices: Array[OptionButton] = []
var status: Label
var inventory: Label
var _effects: Array[Label] = []
var _owned: Array = []
var _slots: Array = ["", ""]
var _pool: int = BuildItems.VERSION
var _built: bool = false


func _ready() -> void:
	_build()


func present(owned: Array, slots: Array, saved: bool, enabled: bool = true, opening_plan: String = "",
		pool: int = BuildItems.VERSION) -> void:
	_build()
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
	for slot: int in range(BuildItems.SLOT_COUNT):
		var choice: OptionButton = slot_choices[slot]
		choice.clear()
		choice.add_item("槽 %d · 空槽 / 卸下" % (slot + 1))
		choice.set_item_metadata(0, "")
		for id: String in available:
			if id not in owned:
				continue
			var index: int = choice.item_count
			choice.add_item("槽 %d · %s" % [slot + 1, definitions[id].name])
			choice.set_item_metadata(index, id)
			choice.set_item_tooltip(index, definitions[id].effect)
			choice.set_item_disabled(index, id == slots[1 - slot])
		choice.select(_index_for(choice, slots[slot]))
		choice.disabled = not enabled
		_effects[slot].text = "空槽也可出发" if slots[slot].is_empty() else definitions[slots[slot]].effect
		choice.tooltip_text = "选择库存道具替换本槽；保存成功后供下一行动使用。"


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
	inventory.tooltip_text = "仅两个槽中的道具生效；同一件不能同时占两槽。未装备道具保留在本局库存。"
	add_child(inventory)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for slot: int in range(BuildItems.SLOT_COUNT):
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0
		column.add_theme_constant_override("separation", 3)
		row.add_child(column)
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
