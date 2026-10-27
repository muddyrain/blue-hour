class_name LoadoutPanel
extends Control
## A camp-only view. Signals request transactions; controls never grant items.

signal equip_requested(member_id: int, instance_id: String)
signal repair_requested(instance_id: String)
signal closed

var items: ItemList
var equip_buttons: Array[Button] = []
var repair_button: Button
var back_button: Button
var confirmation: ConfirmationDialog
var message: Label
var _crew: Label
var _member_equipment: Array[Label] = []
var _detail: Label
var _preview: TextureRect
var _data: Dictionary = {}
var _selected_id: String = ""
var _confirmation_id: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background: ColorRect = ColorRect.new()
	background.color = Color("10232d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 72)
	for side: String in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 24)
	add_child(margins)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margins.add_child(column)
	var heading: Label = Label.new()
	heading.text = "武器整备 / 装备仓"
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)
	var crew_row: HBoxContainer = HBoxContainer.new()
	crew_row.add_theme_constant_override("separation", 24)
	column.add_child(crew_row)
	_crew = Label.new()
	_crew.add_theme_font_size_override("font_size", 16)
	_crew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crew.custom_minimum_size = Vector2(140, 56)
	_crew.add_theme_color_override("font_color", Color("a5dfce"))
	crew_row.add_child(_crew)
	for member_id: int in [1, 2]:
		var member_row: HBoxContainer = HBoxContainer.new()
		member_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		member_row.add_theme_constant_override("separation", 10)
		crew_row.add_child(member_row)
		var portrait: TextureRect = TextureRect.new()
		portrait.texture = SurvivorRoster.definition(member_id).portrait
		portrait.custom_minimum_size = Vector2(52, 56)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		member_row.add_child(portrait)
		var equipment: Label = Label.new()
		equipment.add_theme_font_size_override("font_size", 16)
		equipment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		equipment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		member_row.add_child(equipment)
		_member_equipment.append(equipment)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 28)
	column.add_child(row)
	items = ItemList.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.fixed_icon_size = Vector2i(112, 48)
	items.add_theme_font_size_override("font_size", 18)
	items.add_theme_constant_override("v_separation", 20)
	items.item_selected.connect(_select)
	row.add_child(items)
	var detail_column: VBoxContainer = VBoxContainer.new()
	detail_column.custom_minimum_size.x = 430
	detail_column.add_theme_constant_override("separation", 8)
	row.add_child(detail_column)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(400, 88)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_column.add_child(_preview)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 18)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(_detail)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	for member_id: int in [1, 2]:
		var button: Button = Button.new()
		button.text = "配给队员 %d / 交换" % member_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.pressed.connect(func() -> void: equip_requested.emit(member_id, _selected_id))
		actions.add_child(button)
		equip_buttons.append(button)
	repair_button = Button.new()
	repair_button.text = "维修…"
	repair_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_button.pressed.connect(_confirm_repair)
	actions.add_child(repair_button)
	var note: Label = Label.new()
	note.text = "损坏武器须先维修。配装会在营地保存，下次出击生效。"
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color("d9c390"))
	column.add_child(note)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 36
	message.add_theme_font_size_override("font_size", 17)
	column.add_child(message)
	back_button = Button.new()
	back_button.text = "返回营地 / Esc"
	back_button.custom_minimum_size.y = 44
	back_button.pressed.connect(func() -> void: closed.emit())
	column.add_child(back_button)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "维修确认"
	confirmation.ok_button_text = "确认维修"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(func() -> void: repair_requested.emit(_confirmation_id))
	add_child(confirmation)


func refresh(data: Dictionary, feedback: String = "") -> void:
	_data = data.duplicate(true)
	items.clear()
	for item: Dictionary in _data.weapons:
		var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
		var owner_id: int = WeaponInventory.owner(_data, item.instance_id)
		var ownership: String = SurvivorRoster.member(_data.crew, owner_id).call_sign if owner_id > 0 else "库存"
		var list_owner: String = ownership if ownership.length() <= 6 else ownership.left(6) + "…"
		var index: int = items.add_item("%02d  %s  /  %s  /  %s" % [items.item_count + 1, weapon.display_name,
			"待维修" if item.condition == "damaged" else "可装备", list_owner], weapon.presentation.texture)
		items.set_item_metadata(index, item.instance_id)
		items.set_item_tooltip(index, "归属 " + ownership + "\n实例 " + item.instance_id)
		items.set_item_custom_fg_color(index, CampStyle.AMBER if item.condition == "damaged" else CampStyle.TEXT)
		if _selected_id == item.instance_id:
			items.select(index)
	if items.get_selected_items().is_empty() and items.item_count > 0:
		items.select(0)
	if not items.get_selected_items().is_empty():
		_select(items.get_selected_items()[0])
	for member: Dictionary in _data.crew:
		var item: Dictionary = WeaponInventory.for_member(_data, int(member.id))
		var label: Label = _member_equipment[int(member.id) - 1]
		label.text = "%02d  %s\n%s" % [int(member.id), member.call_sign,
			WeaponInventory.definition(item.weapon_id).display_name if not item.is_empty() else "倒地，装备在库"]
		var base: SurvivorDefinition = SurvivorRoster.definition(int(member.id))
		label.tooltip_text = "%s · %s\n呼号：%s" % [base.default_display_name, base.gender_text(), member.call_sign]
	_crew.text = "货币 %d\n食物 %d" % [int(_data.cash),int(_data.food)]
	message.text = feedback if not feedback.is_empty() else "选择一件武器，再配给指定队员；已装备的武器可直接交换。"


func _select(index: int) -> void:
	_selected_id = items.get_item_metadata(index)
	var item: Dictionary = WeaponInventory.find(_data, _selected_id)
	var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	_preview.texture = weapon.presentation.texture
	var owner_id: int = WeaponInventory.owner(_data, _selected_id)
	var ownership: String = SurvivorRoster.member(_data.crew, owner_id).call_sign if owner_id > 0 else "装备仓"
	_detail.text = "%s\n%s\n\n当前归属  /  %s\n来源  /  %s\n维修报价  /  %d 货币\n\n伤害 %.0f   ·   间隔 %.2f秒   ·   射程 %.0f\n战斗参数待校准" % [weapon.display_name,
		"损坏 · 须维修后装备" if item.condition == "damaged" else "状态良好 · 可装备", ownership,
		"街区补给点搜集" if item.origin == "north-cache" else "初始装备",weapon.repair_cost,weapon.damage,weapon.interval,weapon.shot_range]
	_detail.tooltip_text = "实例 " + item.instance_id + "\n现有样板固定维修报价，尚无随机词条。"
	for member_id: int in [1,2]:
		equip_buttons[member_id-1].text = "配给 %s / 交换" % SurvivorRoster.member(_data.crew,member_id).call_sign

	for member_id: int in [1, 2]:
		equip_buttons[member_id - 1].disabled = item.condition != "ready" or not WeaponInventory._living(_data, member_id)
	repair_button.disabled = item.condition != "damaged"
	repair_button.text = "维修 %d 货币…" % weapon.repair_cost if item.condition == "damaged" else "无需维修"


func _confirm_repair() -> void:
	_confirmation_id = _selected_id
	var item: Dictionary = WeaponInventory.find(_data, _confirmation_id)
	var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	confirmation.dialog_text = "维修%s，消耗%d货币？\n确认后保存营地；取消不会消耗资源。" % [weapon.display_name, weapon.repair_cost]
	confirmation.popup_centered(Vector2i(620, 230))
