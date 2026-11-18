class_name BuildItemsPanel
extends VBoxContainer
## Camp-only projection. Slot selection always waits for its owner's confirmed edit.

signal requested(slot: int, item_id: String)
signal investment_requested(choice: String)

const LINER_ICON: Texture2D = preload("res://assets/ui/m38/impact-liner.svg")
const ITEMS: Texture2D = preload("res://assets/menu_pixel/specialties.png")

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
var _pictures: Array[TextureRect] = []
var _names: Array[Label] = []
var _text_columns: Array[VBoxContainer] = []
var _unload: Array[Button] = []
var _locked: PanelContainer
var _upgrade_preview: Label

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
		for choice: OptionButton in slot_choices: choice.disabled = true
		return
	_owned = owned.duplicate(true)
	_slots = slots.duplicate(true)
	_pool = pool
	var definitions: Dictionary = BuildItems.definitions(pool)
	var available: Array[String] = BuildItems.ids(pool)
	inventory.text = "库存 %d / %d · 装备行动回收，归航确认后入库" % [owned.size(), available.size()]
	if OpeningBuild.PLANS.has(opening_plan): inventory.tooltip_text = "开局专精：" + OpeningBuild.PLANS[opening_plan].title
	status.text = "已保存 · 下次行动生效" if saved else "保存未确认 · 保持原配装"
	status.add_theme_color_override("font_color", CampStyle.TEXT if saved else CampStyle.AMBER)
	for slot: int in range(slot_choices.size()):
		_columns[slot].visible = slot < slots.size()
		if slot >= slots.size(): continue
		var id: String = slots[slot]
		var choice: OptionButton = slot_choices[slot]
		choice.clear()
		choice.add_item("空槽 / 卸下")
		choice.set_item_metadata(0, "")
		for candidate: String in available:
			if candidate not in owned: continue
			var index: int = choice.item_count
			choice.add_item(definitions[candidate].name)
			choice.set_item_metadata(index, candidate)
			choice.set_item_tooltip(index, BuildItems.effect_text(candidate, candidate in camp.get("journey", {}).get("build", {}).get("progression", {}).get("enhanced", []), pool))
			choice.set_item_disabled(index, candidate in slots and candidate != id)
		choice.select(_index_for(choice, id))
		choice.disabled = not enabled
		choice.tooltip_text = "选择库存道具替换本槽；保存成功后供下一行动使用。"
		_names[slot].text = "空槽" if id.is_empty() else definitions[id].name
		_effects[slot].text = "空槽也可出发" if id.is_empty() else BuildItems.effect_text(id, id in camp.get("journey", {}).get("build", {}).get("progression", {}).get("enhanced", []), pool)
		if id == "field_tools_v1":
			_effects[slot].text = _effects[slot].text.replace("回收工时", "搜刮 / 户外回收耗时")
		var featured: bool = slot == 0 and not id.is_empty() and slots.size() < 3
		_pictures[slot].custom_minimum_size = Vector2(136, 120) if featured else Vector2(72, 88)
		_text_columns[slot].custom_minimum_size.x = 280 if featured else 0
		_pictures[slot].texture = item_art(id)
		_pictures[slot].visible = _pictures[slot].texture != null
		_unload[slot].visible = not id.is_empty()
		_unload[slot].disabled = not enabled
		_columns[slot].size_flags_stretch_ratio = 1.8 if not id.is_empty() and slots.size() < 3 else 1.0
		(_columns[slot] as PanelContainer).add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL if not id.is_empty() else CampStyle.EDGE, 12))
	_present_investments(enabled)

func _build() -> void:
	if _built: return
	_built = true
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	add_child(heading)
	var title: Label = CampStyle.label("被动道具", 30)
	title.add_theme_font_override("font", CampStyle.BOLD_FONT)
	heading.add_child(title)
	status = CampStyle.label("", 22)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(status)
	PixelMenu.divider(self)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	for slot: int in range(4):
		var panel: PanelContainer = PanelContainer.new()
		panel.custom_minimum_size.y = 144
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		_columns.append(panel)
		var content: HBoxContainer = HBoxContainer.new()
		content.add_theme_constant_override("separation", 12)
		panel.add_child(content)
		var art: TextureRect = TextureRect.new()
		art.custom_minimum_size = Vector2(100, 108)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		content.add_child(art)
		_pictures.append(art)
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 5)
		content.add_child(column)
		_text_columns.append(column)
		var name_label: Label = CampStyle.label("", 25)
		name_label.clip_text = true
		name_label.add_theme_font_override("font", CampStyle.BOLD_FONT)
		column.add_child(name_label)
		_names.append(name_label)
		var effect: Label = CampStyle.label("", 22, CampStyle.TEXT)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(effect)
		_effects.append(effect)
		var actions: HBoxContainer = HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		column.add_child(actions)
		var choice: OptionButton = OptionButton.new()
		choice.custom_minimum_size.y = 36
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.fit_to_longest_item = false
		choice.clip_text = true
		choice.item_selected.connect(_selected.bind(slot))
		choice.add_theme_font_size_override("font_size", 18)
		actions.add_child(choice)
		_compact_slot_control(choice)
		slot_choices.append(choice)
		var unload: Button = Button.new()
		unload.text = "卸下"
		unload.add_theme_font_size_override("font_size", 18)
		unload.pressed.connect(_selected.bind(0, slot))
		actions.add_child(unload)
		_compact_slot_control(unload)
		_unload.append(unload)
	_locked = PanelContainer.new()
	_locked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locked.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.EDGE, 12))
	row.add_child(_locked)
	_slot_button = Button.new()
	_slot_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slot_button.add_theme_font_size_override("font_size", 24)
	CampStyle.text_button(_slot_button)
	_slot_button.icon = PixelSheet.symbol_texture("lock")
	_slot_button.expand_icon = true
	_slot_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	_slot_button.add_theme_constant_override("icon_max_width", 36)
	_slot_button.add_theme_constant_override("h_separation", 4)
	_slot_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for button_state: String in ["normal", "hover", "pressed", "disabled"]:
		_slot_button.add_theme_stylebox_override(button_state, CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 4))
	_slot_button.pressed.connect(_confirm_investment.bind("next_slot"))
	_locked.add_child(_slot_button)
	_upgrade_row = HBoxContainer.new()
	_upgrade_row.add_theme_constant_override("separation", 16)
	add_child(_upgrade_row)
	_upgrade_preview = CampStyle.label("强化预览", 21)
	_upgrade_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_row.add_child(_upgrade_preview)
	_upgrade_choice = OptionButton.new()
	_upgrade_choice.custom_minimum_size.x = 160
	_upgrade_choice.fit_to_longest_item = false
	_upgrade_choice.add_theme_font_size_override("font_size", 18)
	_upgrade_choice.item_selected.connect(func(_index: int) -> void: _refresh_upgrade())
	_upgrade_row.add_child(_upgrade_choice)
	_upgrade_button = Button.new()
	_upgrade_button.text = "强化 · 10 币"
	_upgrade_button.custom_minimum_size = Vector2(160, 38)
	_upgrade_button.add_theme_font_size_override("font_size", 22)
	_upgrade_button.pressed.connect(func() -> void:
		if _upgrade_choice.item_count > 0: _confirm_investment(_upgrade_choice.get_item_metadata(_upgrade_choice.selected)))
	_upgrade_row.add_child(_upgrade_button)
	inventory = CampStyle.label("", 18, CampStyle.MUTED)
	inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.tooltip_text = "仅已开启并装备的槽位生效；同一件不能占多个槽。未装备道具保留在本局库存。"
	inventory.hide()
	add_child(inventory)
	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "确认被动投资"
	_confirmation.borderless = true
	_confirmation.dialog_autowrap = true
	_confirmation.ok_button_text = "确认并保存"
	_confirmation.cancel_button_text = "保留 / 返回"
	_confirmation.confirmed.connect(func() -> void: investment_requested.emit(_investment_value))
	add_child(_confirmation)
	_confirmation.get_label().add_theme_font_size_override("font_size", 24)
	_confirmation.get_cancel_button().custom_minimum_size = Vector2(220, 52)
	_confirmation.get_ok_button().custom_minimum_size = Vector2(220, 52)
	PixelMenu.primary(_confirmation.get_ok_button())


func _compact_slot_control(button: Button) -> void:
	button.custom_minimum_size.y = 36
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		button.add_theme_stylebox_override(state, style)


static func item_art(id: String) -> Texture2D:
	if id == BuildItems.LINER: return LINER_ICON
	if id == BuildItems.FILTER: return preload("res://assets/ui/m31/filter-mask.svg")
	var index: int = -1
	if id == "field_tools_v1": index = 0
	elif id == "pressure_rounds_v1": index = 1
	elif id in ["medical_pack_v1", BuildItems.AID_KIT]: index = 2
	if index < 0: return null
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = ITEMS
	var width: float = ITEMS.get_width() / 3.0
	atlas.region = Rect2(62, 112, 626, 546) if id == "field_tools_v1" else Rect2(index * width, 0, width, ITEMS.get_height())
	atlas.filter_clip = true
	return atlas

func _selected(index: int, slot: int) -> void:
	var choice: OptionButton = slot_choices[slot]
	var id: String = choice.get_item_metadata(index)
	choice.select(_index_for(choice, _slots[slot]))
	if id == _slots[slot] or choice.disabled: return
	var proposed: Array = _slots.duplicate(true)
	proposed[slot] = id
	if BuildItems.problem(_owned, proposed, _pool).is_empty(): requested.emit(slot, id)

func _index_for(choice: OptionButton, id: String) -> int:
	for index: int in range(choice.item_count):
		if choice.get_item_metadata(index) == id: return index
	return 0

func _present_investments(editable: bool) -> void:
	_upgrade_row.visible = not _camp.is_empty() and BuildState.m48_enabled(_camp)
	_locked.visible = _upgrade_row.visible and _slots.size() < 4
	if not _upgrade_row.visible: return
	var offer: Dictionary = BuildState.investment_offer(_camp, "next_slot")
	_slot_button.text = "开启第 %d 槽\n%d 币" % [_slots.size() + 1, int(offer.cost)] if _slots.size() < 4 else "被动槽已满"
	_slot_button.disabled = not editable or not offer.available
	_slot_button.tooltip_text = offer.reason if not offer.available else offer.summary
	_upgrade_choice.clear()
	for id: String in _owned:
		_upgrade_choice.add_item(BuildItems.definitions(_pool)[id].name + (" · 已强化" if id in _camp.journey.build.progression.enhanced else ""))
		_upgrade_choice.set_item_metadata(_upgrade_choice.item_count - 1, id)
	_upgrade_choice.visible = _owned.size() > 1
	_upgrade_choice.disabled = not editable or _owned.is_empty()
	_upgrade_button.set_meta("editable", editable)
	_refresh_upgrade()

func _refresh_upgrade() -> void:
	if _camp.is_empty() or _upgrade_choice.item_count == 0:
		_upgrade_button.disabled = true
		_upgrade_preview.text = "回收被动道具后可强化"
		return
	var id: String = _upgrade_choice.get_item_metadata(_upgrade_choice.selected)
	var offer: Dictionary = BuildState.investment_offer(_camp, id)
	_upgrade_button.disabled = not bool(_upgrade_button.get_meta("editable", true)) or not offer.available
	_upgrade_button.tooltip_text = offer.summary if offer.available else offer.reason
	_upgrade_choice.tooltip_text = BuildItems.effect_text(id, false, _pool) + " → " + BuildItems.effect_text(id, true, _pool)
	var before: String = BuildItems.effect_text(id, false, _pool)
	var after: String = BuildItems.effect_text(id, true, _pool)
	_upgrade_preview.text = "强化预览   %s → %s" % [before.get_slice("×", 1), after.get_slice("×", 1)] if before.contains("×") else "强化预览 · " + after
	if before.contains("×"): _upgrade_preview.text = "强化预览   ×%s → ×%s" % [before.get_slice("×", 1), after.get_slice("×", 1)]

func _confirm_investment(choice: String) -> void:
	var offer: Dictionary = BuildState.investment_offer(_camp, choice)
	if not offer.available: return
	_investment = choice
	_investment_value = BuildState.investment_value(_camp, choice)
	_confirmation.dialog_text = "确认道具投资\n\n%s\n花费 %d 币 · 保存后余 %d 币。" % [offer.summary, offer.cost, int(_camp.cash) - int(offer.cost)]
	_confirmation.popup_centered(Vector2i(700, 300))
