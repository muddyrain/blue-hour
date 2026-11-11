class_name CampArmoryView
extends MarginContainer
## Read-only equipment and workshop projection. Only confirmed requests leave this view.

signal equip_requested(member_id: int, instance_id: String)
signal repair_requested(instance_id: String)
signal workshop_requested(instance_id: String, mod: String)
signal navigation_requested(action: StringName)
signal selection_changed(instance_id: String)
signal economy_requested(request: Dictionary)

const YARD: Texture2D = preload("res://assets/ui/m20/camp-blue-hour.png")
const STATUS: Array[String] = ["全部", "闲置", "已装备", "待维修"]
const MODS: Array[String] = [WorkshopV1.EXTENDED, WorkshopV1.QUICK]

var items: ItemList
var repair_button: Button
var back_button: Button
var workshop_buttons: Dictionary[String, Button] = {}
var confirmation: ConfirmationDialog
var workshop_confirmation: ConfirmationDialog
var power_panel: PowerLoadoutPanel
var build_panel: BuildItemsPanel
var message: Label
var target: OptionButton
var status_filter: OptionButton
var type_filter: OptionButton
var search: LineEdit
var sort_order: OptionButton
var confirm_equip: Button
var cancel_preview: Button

var _camp: Dictionary = {}
var _selected: String = ""
var _target_id: int = 0
var _tab: StringName = &"inventory"
var _workshop_tab: StringName = &"repair"
var _workshop_return_id: String = ""
var _page_selection: Dictionary[StringName, String] = {}
var _scroll: Dictionary[StringName, float] = {}
var _plan: Dictionary = {}
var _preview_cancelled: bool = false
var _pending: bool = false
var _request: Dictionary = {}
var _header: Label
var _heading: Label
var _list_heading: Label
var _list_count: Label
var _filters: VBoxContainer
var _clear: Button
var _workshop_tabs: HBoxContainer
var _workshop_options: Dictionary[StringName, Button] = {}
var _banner: Control
var _split: HBoxContainer
var _support: ScrollContainer
var _title: Label
var _meta: Label
var _texture: TextureRect
var _comparison: GridContainer
var _current: Label
var _proposed: Label
var _target_row: HBoxContainer
var _detail: Label
var _preview: Label
var _empty: Label
var _detail_body: VBoxContainer
var _to_workshop: Button
var _to_inventory: Button
var _retry_button: Button
var _nav: Dictionary[StringName, Button] = {}
var economy_buttons: Dictionary[String, Button] = {}
var craft_buttons: Dictionary[String, Button] = {}
var _craft_row: HBoxContainer
var _economy_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		add_theme_constant_override("margin_" + side, 24)
	for side: String in ["top", "bottom"]:
		add_theme_constant_override("margin_" + side, 14)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	add_child(page)
	_header = CampStyle.label("", 18, CampStyle.AMBER)
	page.add_child(_header)
	page.add_child(HSeparator.new())
	_heading = CampStyle.label("", 28)
	page.add_child(_heading)
	_split = HBoxContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.add_theme_constant_override("separation", 14)
	page.add_child(_split)
	_build_list(_column(_split, 1.15))
	_build_detail(_column(_split, 1.0))
	_build_support(page)
	var feedback: HBoxContainer = HBoxContainer.new()
	page.add_child(feedback)
	message = _wrapped("", 15, CampStyle.TEAL)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback.add_child(message)
	_retry_button = _button(feedback, "重试保存本次整备", func() -> void: power_panel.retry_requested.emit())
	_retry_button.hide()
	page.add_child(HSeparator.new())
	_build_navigation(page)
	confirmation = _dialog("维修确认", "确认维修", _finish_repair)
	workshop_confirmation = _dialog("确认工坊改装", "安装并保存", _finish_workshop)
	_update_page()


func refresh(data: Dictionary, feedback: String, pending: bool) -> void:
	_save_scroll()
	_camp = data
	_pending = pending
	message.text = feedback
	_retry_button.visible = pending
	_header.text = "蓝时驿站   ·   第 %02d 天      口粮 %d    货币 %d    工具箱 %d" % [int(data.day), int(data.food), int(data.cash), WorkshopV1.tools(data)]
	var campaign: Dictionary = data.get("journey", {}).get("campaign", {})
	if CampaignRules.is_investigation(campaign):
		_header.text += "    线索 %d / %d" % [campaign.clues.size(), CampaignRules.CLUE_IDS.size()]
	power_panel.present(data, _editable(), pending)
	build_panel.visible = BuildState.enabled(data)
	if build_panel.visible:
		var build: Dictionary = data.journey.build
		build_panel.present(build.owned, build.slots, true, _editable(), build.get("opening", {}).get("plan", ""), BuildState.pool(data), data)
	_update_targets()
	_rebuild_list()


func show_inventory() -> void:
	_show_page(&"inventory")
	items.grab_focus()


func show_workshop(instance_id: String = "") -> void:
	_workshop_return_id = instance_id
	if not instance_id.is_empty():
		var item: Dictionary = WeaponInventory.find(_camp, instance_id) if not _camp.is_empty() else {}
		var mode: StringName = &"mod" if item.get("condition") == "ready" else &"repair"
		_page_selection[mode] = instance_id
		if _tab == &"workshop":
			_set_workshop_tab(mode)
			_rebuild_list()
		else:
			_workshop_tab = mode
	_show_page(&"workshop")
	items.grab_focus()


func back_from_workshop() -> bool:
	if _tab == &"support":
		show_inventory()
		return true
	if _tab != &"workshop" or _workshop_return_id.is_empty():
		return false
	_return_to_inventory()
	return true


func cancel_swap_preview() -> bool:
	if _tab != &"inventory" or _plan.is_empty() or _preview_cancelled:
		return false
	_preview_cancelled = true
	_refresh_detail()
	items.grab_focus()
	return true


func select_inventory(instance_id: String, member_id: int = 0) -> void:
	if member_id > 0:
		_target_id = member_id
		_update_targets()
	if _tab != &"inventory":
		_show_page(&"inventory")
	if not instance_id.is_empty():
		_page_selection[&"inventory"] = instance_id
		var item: Dictionary = WeaponInventory.find(_camp, instance_id)
		if not item.is_empty() and not _matches_filter(item):
			_reset_filters()
	_preview_cancelled = false
	_rebuild_list()
	if _selected == instance_id:
		items.ensure_current_is_visible.call_deferred()


func matches_equip(data: Dictionary, member_id: int, instance_id: String) -> bool:
	return _tab == &"inventory" and not _preview_cancelled and not _plan.is_empty() \
		and _plan.target == member_id and _plan.instance_id == instance_id \
		and _plan == _equip_plan(data, member_id, instance_id)


func focus_retry() -> void:
	_retry_button.grab_focus()


func _column(parent: HBoxContainer, ratio: float) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, Color("44636c"), 12))
	parent.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column


func _build_list(column: VBoxContainer) -> void:
	_list_heading = CampStyle.label("武器库存", 20)
	column.add_child(_list_heading)
	_banner = PanelContainer.new()
	_banner.custom_minimum_size.y = 82
	_banner.add_child(CampStyle.blue_hour_background(YARD))
	column.add_child(_banner)
	_workshop_tabs = HBoxContainer.new()
	column.add_child(_workshop_tabs)
	_workshop_options[&"repair"] = _button(_workshop_tabs, "维修", _set_workshop_tab.bind(&"repair"))
	_workshop_options[&"mod"] = _button(_workshop_tabs, "改装", _set_workshop_tab.bind(&"mod"))
	_craft_row = HBoxContainer.new()
	column.add_child(_craft_row)
	for weapon_id: String in ["carbine", "long_rifle", "shotgun_v1"]:
		craft_buttons[weapon_id] = _button(_craft_row, "制作" + WeaponInventory.definition(weapon_id).display_name,
			_preview_economy.bind("craft", weapon_id, ""))
	_filters = VBoxContainer.new()
	column.add_child(_filters)
	var choices: HBoxContainer = HBoxContainer.new()
	_filters.add_child(choices)
	status_filter = _options(choices, STATUS, _filter_changed)
	status_filter.name = "InventoryStatus"
	type_filter = _options(choices, ["全部类型", "枪械", "近战"], _filter_changed)
	type_filter.name = "InventoryType"
	sort_order = _options(choices, ["按名称", "按实例编号"], _filter_changed)
	sort_order.name = "InventoryOrder"
	var query: HBoxContainer = HBoxContainer.new()
	_filters.add_child(query)
	search = LineEdit.new()
	search.name = "InventorySearch"
	search.placeholder_text = "搜索武器名称 / 实例编号"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_query: String) -> void: _filter_changed(0))
	query.add_child(search)
	_clear = _button(query, "清空筛选", _clear_filters)
	items = ItemList.new()
	items.name = "WeaponInventory"
	items.max_text_lines = 2
	items.fixed_icon_size = Vector2i(104, 38)
	items.add_theme_font_size_override("font_size", 16)
	items.add_theme_constant_override("v_separation", 8)
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.item_selected.connect(_select)
	column.add_child(items)
	_list_count = _wrapped("", 15, CampStyle.MUTED)
	column.add_child(_list_count)


func _build_detail(column: VBoxContainer) -> void:
	_empty = _wrapped("", 18, CampStyle.MUTED)
	column.add_child(_empty)
	_title = CampStyle.label("", 24)
	column.add_child(_title)
	_meta = _wrapped("", 15, CampStyle.MUTED)
	column.add_child(_meta)
	var picture: PanelContainer = PanelContainer.new()
	picture.add_theme_stylebox_override("panel", CampStyle.box(Color("1a3642"), Color("44636c"), 3))
	column.add_child(picture)
	_texture = TextureRect.new()
	_texture.custom_minimum_size.y = 65
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_child(_texture)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_detail_body = VBoxContainer.new()
	_detail_body.add_theme_constant_override("separation", 8)
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail_body)
	_target_row = HBoxContainer.new()
	_detail_body.add_child(_target_row)
	_target_row.add_child(CampStyle.label("目标队员", 16, CampStyle.MUTED))
	target = _options(_target_row, [], _select_target)
	target.name = "EquipTarget"
	_comparison = GridContainer.new()
	_comparison.columns = 2
	_comparison.add_theme_constant_override("h_separation", 16)
	_detail_body.add_child(_comparison)
	_current = _wrapped("", 15, CampStyle.TEXT)
	_current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comparison.add_child(_current)
	_proposed = _wrapped("", 15, CampStyle.AMBER)
	_proposed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comparison.add_child(_proposed)
	_detail = _wrapped("", 15, CampStyle.MUTED)
	_detail_body.add_child(_detail)
	_economy_box = VBoxContainer.new()
	_economy_box.add_theme_constant_override("separation", 6)
	_detail_body.add_child(_economy_box)
	var operations: Array[Array] = [
		["sell", "", "预览出售"], ["upgrade_weapon", "", "升级自制武器"],
		["basic_component", "quick_v1", "安装轻快机件"], ["basic_component", "reach_v1", "安装延伸瞄具"],
		["combat_component", WeaponModifiers.PIERCE, "安装穿透弹"],
		["combat_component", WeaponModifiers.REFUND, "安装击倒补弹"],
		["magazine", WorkshopV1.EXTENDED, "安装扩容弹匣"], ["magazine", WorkshopV1.QUICK, "安装快拆弹匣"]]
	for operation: Array in operations:
		var key: String = String(operation[0]) + ":" + String(operation[1])
		economy_buttons[key] = _button(_economy_box, operation[2],
			_preview_economy.bind(operation[0], "", operation[1]))
	_preview = _wrapped("", 16, CampStyle.TEAL)
	column.add_child(_preview)
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	_to_workshop = _button(actions, "前往工坊", func() -> void: show_workshop(_selected))
	_to_inventory = _button(actions, "返回装备仓", _return_to_inventory)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(gap)
	for mod: String in MODS:
		workshop_buttons[mod] = _button(actions, WorkshopV1.name_for(mod), _confirm_workshop.bind(mod))
	repair_button = _button(actions, "确认维修…", _confirm_repair)
	CampStyle.blue_hour_primary(repair_button)
	cancel_preview = _button(actions, "取消预览", func() -> void: cancel_swap_preview())
	confirm_equip = _button(actions, "确认配给", _apply_equip)
	confirm_equip.name = "ConfirmEquip"
	CampStyle.blue_hour_primary(confirm_equip)


func _build_support(page: VBoxContainer) -> void:
	_support = ScrollContainer.new()
	_support.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_support.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_support.follow_focus = true
	page.add_child(_support)
	var support_body: VBoxContainer = VBoxContainer.new()
	support_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_support.add_child(support_body)
	build_panel = BuildItemsPanel.new()
	support_body.add_child(build_panel)
	power_panel = PowerLoadoutPanel.new()
	support_body.add_child(power_panel)


func _build_navigation(page: VBoxContainer) -> void:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	page.add_child(footer)
	back_button = _button(footer, "营地 / Esc", func() -> void: navigation_requested.emit(&"camp"))
	_button(footer, "队员", func() -> void: navigation_requested.emit(&"crew"))
	_nav[&"inventory"] = _button(footer, "装备仓", show_inventory)
	_nav[&"workshop"] = _button(footer, "工坊", func() -> void: show_workshop())
	_button(footer, "补给", func() -> void: navigation_requested.emit(&"supplies"))
	_nav[&"support"] = _button(footer, "支援与道具", _show_page.bind(&"support"))
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	var depart: Button = _button(footer, "准备出击 →", func() -> void: navigation_requested.emit(&"bus"))
	CampStyle.blue_hour_primary(depart)


func _button(parent: Container, caption: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _options(parent: Container, choices: Array[String], action: Callable) -> OptionButton:
	var options: OptionButton = OptionButton.new()
	options.add_theme_font_size_override("font_size", 16)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value: String in choices:
		options.add_item(value)
	options.item_selected.connect(action)
	parent.add_child(options)
	return options


func _wrapped(caption: String, font_size: int, colour: Color) -> Label:
	var label: Label = CampStyle.label(caption, font_size, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dialog(title: String, caption: String, action: Callable) -> ConfirmationDialog:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.dialog_autowrap = true
	dialog.title = title
	dialog.ok_button_text = caption
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(action)
	dialog.canceled.connect(func() -> void: _request.clear())
	add_child(dialog)
	return dialog


func _show_page(page: StringName) -> void:
	if _tab != page:
		_save_scroll()
		_tab = page
		_preview_cancelled = false
		_update_page()
		_rebuild_list()


func _update_page() -> void:
	_heading.text = "工坊" if _tab == &"workshop" else "支援与道具" if _tab == &"support" else "装备仓"
	_split.visible = _tab != &"support"
	_support.visible = _tab == &"support"
	_filters.visible = _tab == &"inventory"
	_workshop_tabs.visible = _tab == &"workshop"
	_banner.visible = _workshop_tabs.visible
	for page: StringName in _nav:
		_nav[page].add_theme_color_override("font_color", CampStyle.AMBER if page == _tab else CampStyle.TEXT)


func _set_workshop_tab(tab: StringName) -> void:
	if _workshop_tab == tab:
		return
	_save_scroll()
	_workshop_tab = tab
	_rebuild_list()


func _return_to_inventory() -> void:
	var identity: String = _workshop_return_id if not _workshop_return_id.is_empty() else _selected
	_workshop_return_id = ""
	select_inventory(identity)
	items.grab_focus()


func _page_key() -> StringName:
	return _workshop_tab if _tab == &"workshop" else _tab


func _save_scroll() -> void:
	if _tab != &"support":
		_scroll[_page_key()] = items.get_v_scroll_bar().value


func _filter_changed(_index: int) -> void:
	_scroll[&"inventory"] = 0.0
	_preview_cancelled = false
	_rebuild_list()
	items.ensure_current_is_visible.call_deferred()


func _reset_filters() -> void:
	status_filter.select(0)
	type_filter.select(0)
	search.clear()


func _clear_filters() -> void:
	_reset_filters()
	_filter_changed(0)


func _status(item: Dictionary) -> int:
	if item.condition == "damaged":
		return 3
	return 2 if WeaponInventory.owner(_camp, item.instance_id) > 0 else 1


func _matches_filter(item: Dictionary) -> bool:
	var melee: bool = CombatEquipment.melee(item.weapon_id)
	var type: int = type_filter.selected
	var status: int = status_filter.selected
	var query: String = search.text.strip_edges().to_lower()
	var instance_query: String = query.trim_prefix("#")
	var matches_id: bool = not instance_query.is_empty() and (WeaponInventory.short_id(item).to_lower().contains(instance_query) or String(item.instance_id).to_lower().contains(instance_query))
	return (status == 0 or status == _status(item)) and (type == 0 or type == (2 if melee else 1)) \
		and (query.is_empty() or matches_id \
		or WeaponInventory.definition(item.weapon_id).display_name.to_lower().contains(query))


func _rebuild_list() -> void:
	if _tab == &"support":
		return
	var key: StringName = _page_key()
	var keep_id: String = _page_selection.get(key, "")
	var rows: Array[Dictionary] = []
	var counts: Array[int] = [0, 0, 0, 0]
	for item: Dictionary in _camp.get("weapons", []):
		var status: int = _status(item)
		counts[0] += 1
		counts[status] += 1
		if (_tab == &"inventory" and _matches_filter(item)) or (_tab == &"workshop" and (key == &"mod" or status == 3)):
			rows.append(item)
	for index: int in range(counts.size()):
		status_filter.set_item_text(index, "%s %d" % [STATUS[index], counts[index]])
	_workshop_options[&"repair"].text = "维修 · %d" % counts[3]
	for mode: StringName in _workshop_options:
		_workshop_options[mode].add_theme_color_override("font_color", CampStyle.AMBER if mode == key else CampStyle.TEXT)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if sort_order.selected == 0:
			var left: String = WeaponInventory.definition(a.weapon_id).display_name
			var right: String = WeaponInventory.definition(b.weapon_id).display_name
			if left != right:
				return left < right
		return String(a.instance_id) < String(b.instance_id))
	items.clear()
	var selected_index: int = 0
	for item: Dictionary in rows:
		var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
		var state: int = _status(item)
		var owner: int = WeaponInventory.owner(_camp, item.instance_id)
		var holder: String = _member_label(owner) if owner > 0 else "仓库"
		var mod: String = WorkshopV1.mod_for(_camp, item.instance_id)
		var quality: String = "稀有" if item.get("quality") == "rare" else "普通"
		var traits: String = "Lv%d %s" % [int(item.get("weapon_level", 1)), quality]
		if not mod.is_empty():
			traits += " · " + WorkshopV1.name_for(mod)
		var row: int = items.add_item("%s #%s  |  %s · %s · %s" % [weapon.display_name, WeaponInventory.short_id(item), STATUS[state], holder, traits], weapon.presentation.texture)
		items.set_item_metadata(row, item.instance_id)
		items.set_item_custom_fg_color(row, CampStyle.AMBER if state == 3 else CampStyle.TEXT)
		items.set_item_tooltip(row, "%s\n实例 %s\n%s · %s\n%s" % [weapon.display_name, item.instance_id, STATUS[state], holder, _item_attributes(item)])
		if item.instance_id == keep_id:
			selected_index = row
	_list_heading.text = "维修 · 待维修实例" if key == &"repair" else "改装 · 选择实例" if key == &"mod" else "武器库存"
	_list_count.text = "显示 %d / %d 件 · 滚动浏览" % [rows.size(), _camp.get("weapons", []).size()] if not rows.is_empty() else ("没有符合条件的武器。可清空筛选。" if key == &"inventory" else "没有待维修的武器。")
	if rows.is_empty():
		_selected = ""
		_page_selection[key] = ""
		selection_changed.emit("")
		_refresh_detail()
		return
	items.select(selected_index)
	_select(selected_index)
	items.get_v_scroll_bar().set_deferred("value", _scroll.get(key, 0.0))


func _select(index: int) -> void:
	var identity: String = String(items.get_item_metadata(index))
	if identity != _selected:
		_preview_cancelled = false
	_selected = identity
	_page_selection[_page_key()] = identity
	selection_changed.emit(identity)
	_refresh_detail()


func _update_targets() -> void:
	target.clear()
	for member: Dictionary in _camp.get("crew", []):
		if float(member.health) > 0.0:
			target.add_item(SurvivorRoster.display_label(member), int(member.id))
	var index: int = target.get_item_index(_target_id)
	if target.item_count == 0:
		_target_id = 0
		return
	target.select(maxi(index, 0))
	_target_id = target.get_selected_id()


func _select_target(index: int) -> void:
	_target_id = target.get_item_id(index)
	_preview_cancelled = false
	_refresh_detail()


func _item_attributes(item: Dictionary) -> String:
	var description: String = WeaponModifiers.description(item)
	var mod: String = WorkshopV1.mod_for(_camp, item.instance_id)
	return description if mod.is_empty() else description + " · " + WorkshopV1.name_for(mod)


func _member_label(member_id: int) -> String:
	return SurvivorRoster.display_label(SurvivorRoster.member(_camp.get("crew", []), member_id))


func _item_name(item: Dictionary) -> String:
	if item.is_empty():
		return "无装备"
	return "%s #%s" % [WeaponInventory.definition(item.weapon_id).display_name, WeaponInventory.short_id(item)]


func _editable() -> bool:
	return not _pending and not _camp.is_empty() and not CampaignState.ended(_camp) \
		and _camp.get("journey", {}).get("state", "ACTIVE") == "ACTIVE"


func _refresh_detail() -> void:
	var item: Dictionary = WeaponInventory.find(_camp, _selected) if not _camp.is_empty() else {}
	var valid: bool = not item.is_empty()
	var inventory: bool = _tab == &"inventory"
	var modification: bool = not inventory and _workshop_tab == &"mod"
	_empty.visible = not valid
	_empty.text = "选择可见武器以查看详情。" if inventory or modification else "待维修武器会在这里显示。"
	_title.visible = valid
	_meta.visible = valid
	_texture.get_parent().visible = valid
	_detail_body.visible = valid
	_target_row.visible = inventory
	_comparison.visible = inventory
	_to_workshop.visible = false
	_to_inventory.visible = not inventory
	_preview.visible = valid
	confirm_equip.visible = valid and inventory
	cancel_preview.hide()
	repair_button.visible = valid and not inventory and not modification
	for mod: String in MODS:
		workshop_buttons[mod].visible = valid and modification
	_plan = {}
	_refresh_economy(item)
	if not valid:
		return
	var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	var owner: int = WeaponInventory.owner(_camp, _selected)
	_title.text = weapon.display_name
	_meta.text = "#%s · %s · %s\n%s" % [WeaponInventory.short_id(item), STATUS[_status(item)], _member_label(owner) if owner > 0 else "仓库", _item_attributes(item)]
	_meta.tooltip_text = "完整实例编号：" + _selected
	_texture.texture = weapon.presentation.texture
	if inventory:
		_show_comparison(item, owner)
	elif modification:
		_show_modifications(item, owner)
	else:
		_show_repair(item)


func _show_comparison(item: Dictionary, owner: int) -> void:
	var current: Dictionary = WeaponInventory.for_member(_camp, _target_id)
	_current.text = "当前装备\n%s\n\n%s" % [_item_name(current), _stat_text(current, _target_id)]
	_proposed.text = "所选武器\n%s\n\n%s" % [_item_name(item), _stat_text(item, _target_id)]
	_detail.text = "上方比较使用目标队员的特长、特性与已装道具。\n所选实例参数：%s" % _stat_text(item, 0).replace("\n", " · ")
	var effect: String = WeaponModifiers.effect_description(item)
	if not effect.is_empty():
		_detail.text += "\n" + effect
	_plan = _equip_plan(_camp, _target_id, _selected) if _editable() else {}
	confirm_equip.disabled = _plan.is_empty()
	_to_workshop.visible = item.condition == "damaged"
	confirm_equip.visible = not _to_workshop.visible
	cancel_preview.visible = not _plan.is_empty() and not _preview_cancelled
	if _plan.is_empty():
		_preview.text = "营地整备暂不可提交。" if not _editable() else String(WeaponInventory.equip(_camp, _target_id, _selected).get("message", "配装已变化。"))
		confirm_equip.text = "确认配给"
		return
	var verb: String = "交换" if owner > 0 else "配给"
	confirm_equip.text = ("预览" if _preview_cancelled else "确认") + verb
	if _preview_cancelled:
		_preview.text = "已取消预览。装备归属保持当前记录。"
		return
	var current_name: String = _item_name(current)
	var chosen_name: String = _item_name(item)
	var receiver: String = _member_label(_target_id)
	var sender: String = _member_label(owner)
	_preview.text = "%s预览\n%s：%s → %s\n%s" % [verb, receiver, current_name, chosen_name,
		("%s：%s → %s" % [sender, chosen_name, current_name]) if owner > 0 else ("库存：%s 回库" % current_name)]


func _equip_plan(data: Dictionary, member_id: int, instance_id: String) -> Dictionary:
	var outcome: Dictionary = WeaponInventory.equip(data, member_id, instance_id)
	if not outcome.has("data"):
		return {}
	var owner: int = WeaponInventory.owner(data, instance_id)
	# Compare the reviewed loadout and all effective parameters' inputs at submission time.
	return {"instance_id":instance_id, "target":member_id, "owner":owner,
		"selected":WeaponInventory.find(data, instance_id), "replaced":WeaponInventory.for_member(data, member_id),
		"recipient":SurvivorRoster.member(data.crew, member_id), "source":SurvivorRoster.member(data.crew, owner),
		"build":data.get("journey", {}).get("build", {}),
		"mods":data.get("journey", {}).get("campaign", {}).get("workshop", {}),
		"state":data.get("journey", {}).get("state", "ACTIVE")}


func _apply_equip() -> void:
	if _preview_cancelled:
		_preview_cancelled = false
		_refresh_detail()
		return
	if _editable() and matches_equip(_camp, _target_id, _selected):
		equip_requested.emit(_target_id, _selected)


func _stat_text(item: Dictionary, member_id: int) -> String:
	if item.is_empty():
		return "—"
	var melee: bool = CombatEquipment.melee(item.weapon_id)
	var factor: float = TraitRules.factor(SurvivorRoster.member(_camp.crew, member_id), "shot") if member_id > 0 else 1.0
	var stats: Dictionary = WeaponModifiers.effective(item, factor)
	var passive: Dictionary = _passive_factors() if member_id > 0 else {}
	var personal: Dictionary = _personal_factors(member_id)
	var damage: float = float(stats.damage) * (float(personal.get("melee", 1.0)) if melee else float(personal.get("ranged", 1.0)) * float(passive.get("damage", 1.0)))
	var text: String = "%s %.2f\n间隔 %.3f 秒\n%s %.0f" % ["单弹丸伤害" if item.weapon_id == "shotgun_v1" else "伤害", damage, stats.interval, "距离" if melee else "射程", stats.range]
	var mod: String = WorkshopV1.mod_for(_camp, item.instance_id)
	var magazine: Dictionary = WeaponMagazine.parameters(item.weapon_id, mod)
	if not magazine.is_empty():
		text += "\n%d 发 · 换弹 %.3f 秒" % [magazine.capacity, float(magazine.seconds) * float(personal.get("reload", 1.0)) * float(passive.get("reload", 1.0))]
	return text


func _passive_factors() -> Dictionary:
	if not BuildState.enabled(_camp):
		return {}
	return BuildItems.camp_factors(_camp)


func _personal_factors(member_id: int) -> Dictionary:
	if member_id <= 0 or not PersonaState.enabled(_camp):
		return {}
	var member: Dictionary = SurvivorRoster.member(_camp.crew, member_id)
	var recipe: Dictionary = SurvivorPersona.member(_camp.journey.build.persona, member_id, member.get("definition_id", ""))
	return SurvivorPersona.factors(recipe)


func _show_repair(item: Dictionary) -> void:
	var quote: Dictionary = WeaponInventory.repair_offer(_camp, item)
	var balance: int = int(_camp.cash) - int(quote.cost)
	_detail.text = "维修报价\n\n标价 %d 币 · %s\n实付 %d 币\n当前 %d 币%s" % [quote.base,
		"无折扣" if quote.discount == 0 else "%s减 %d 币" % [quote.source, quote.discount], quote.cost,
		_camp.cash, " → 余额 %d 币" % balance if balance >= 0 else " · 尚差 %d 币" % -balance]
	_preview.text = "确认保存后，这件实例回到可分配库存。"
	repair_button.disabled = not _editable() or balance < 0 or item.condition != "damaged"


func _show_modifications(item: Dictionary, owner: int) -> void:
	var installed: String = WorkshopV1.mod_for(_camp, _selected)
	_detail.text = "每件符合条件的枪械仅可改装一次。方案随实例转配。\n已装：%s" % WorkshopV1.name_for(installed)
	for mod: String in MODS:
		var problem: String = WorkshopV1.mod_problem(_camp, _selected, mod)
		var button: Button = workshop_buttons[mod]
		button.disabled = not _editable() or not problem.is_empty()
		button.tooltip_text = problem
		var preview: String = _magazine_preview(item, owner, mod)
		_detail.text += "\n\n%s\n%s" % [WorkshopV1.name_for(mod), preview]
		if not problem.is_empty():
			_detail.text += "\n" + problem
	var coins: int = int(_camp.cash)
	var tools: int = WorkshopV1.tools(_camp)
	_preview.text = "安装消耗工具箱 ×1 与 %d 币。\n当前工具箱 %d，货币 %d%s。" % [WorkshopV1.COST, tools, coins,
		" · 安装后工具箱 %d，货币 %d" % [tools - 1, coins - WorkshopV1.COST] if tools > 0 and coins >= WorkshopV1.COST else ""]


func _magazine_preview(item: Dictionary, owner: int, mod: String) -> String:
	var stock: Dictionary = WeaponMagazine.parameters(item.weapon_id, WorkshopV1.mod_for(_camp, _selected))
	var option: Dictionary = WeaponMagazine.parameters(item.weapon_id, mod)
	if stock.is_empty() or option.is_empty():
		return "此型号没有对应改装方案。"
	var result: String = "%d → %d 发 · 基础换弹 %.2f → %.2f 秒" % [stock.capacity, option.capacity, stock.seconds, option.seconds]
	if owner > 0:
		var factor: float = float(_personal_factors(owner).get("reload", 1.0)) * float(_passive_factors().get("reload", 1.0))
		result += "\n%s 有效换弹 %.3f → %.3f 秒" % [_member_label(owner), float(stock.seconds) * factor, float(option.seconds) * factor]
	return result


func _confirm_repair() -> void:
	var item: Dictionary = WeaponInventory.find(_camp, _selected)
	if not _editable() or item.is_empty() or item.condition != "damaged":
		return
	var quote: int = WeaponInventory.repair_quote(_camp, item)
	if int(_camp.cash) < quote:
		return
	_request = {"instance_id":_selected, "quote":quote, "cash":int(_camp.cash)}
	confirmation.dialog_text = "维修 %s？\n支付 %d 币，保存后余额 %d 币。" % [_item_name(item), quote, int(_camp.cash) - quote]
	confirmation.popup_centered(Vector2i(550, 185))


func _finish_repair() -> void:
	var request: Dictionary = _request
	_request = {}
	if request.has("economy"):
		if _editable():
			economy_requested.emit(request.economy)
		return
	if request.get("instance_id", "") != _selected or not _editable():
		return
	var item: Dictionary = WeaponInventory.find(_camp, _selected)
	if item.get("condition") != "damaged" or request.get("quote") != WeaponInventory.repair_quote(_camp, item) or request.get("cash") != int(_camp.cash):
		message.text = "维修报价已变化，请重新确认。"
		return
	_workshop_return_id = _selected
	repair_requested.emit(_selected)


func _confirm_workshop(mod: String) -> void:
	if not _editable() or not WorkshopV1.mod_problem(_camp, _selected, mod).is_empty():
		return
	var item: Dictionary = WeaponInventory.find(_camp, _selected)
	var owner: int = WeaponInventory.owner(_camp, _selected)
	_request = {"instance_id":_selected, "mod":mod, "owner":owner, "cash":int(_camp.cash), "tools":WorkshopV1.tools(_camp)}
	workshop_confirmation.dialog_text = "%s · %s\n%s\n工具箱 %d → %d · 货币 %d → %d" % [
		_item_name(item), WorkshopV1.name_for(mod), _magazine_preview(item, owner, mod), _request.tools, int(_request.tools) - 1,
		_request.cash, int(_request.cash) - WorkshopV1.COST]
	workshop_confirmation.popup_centered(Vector2i(600, 205))


func _finish_workshop() -> void:
	var request: Dictionary = _request
	_request = {}
	if request.get("instance_id", "") != _selected or not _editable():
		return
	var mod: String = request.get("mod", "")
	if not WorkshopV1.mod_problem(_camp, _selected, mod).is_empty() or request.get("owner") != WeaponInventory.owner(_camp, _selected) \
			or request.get("cash") != int(_camp.cash) or request.get("tools") != WorkshopV1.tools(_camp):
		message.text = "改装条件已变化，请重新确认。"
		return
	workshop_requested.emit(_selected, mod)


func _refresh_economy(item: Dictionary) -> void:
	var enabled: bool = EconomyBuildV1.enabled(_camp)
	_craft_row.visible = enabled and _tab == &"workshop"
	_economy_box.visible = enabled and not item.is_empty()
	for weapon_id: String in craft_buttons:
		var offer: Dictionary = EconomyBuildV1.offer(_camp, "craft", weapon_id)
		craft_buttons[weapon_id].disabled = _pending or not offer.available
		craft_buttons[weapon_id].tooltip_text = offer.summary if offer.available else offer.reason
	for key: String in economy_buttons:
		var op: String = key.get_slice(":", 0)
		var choice: String = key.get_slice(":", 1)
		var button: Button = economy_buttons[key]
		button.visible = (op == "sell") == (_tab == &"inventory")
		var offer: Dictionary = EconomyBuildV1.offer(_camp, op, item.get("instance_id", ""), choice)
		button.disabled = _pending or not _editable() or not offer.available
		button.tooltip_text = offer.summary if offer.available else offer.reason
	if enabled:
		for button: Button in workshop_buttons.values():
			button.hide()


func _preview_economy(op: String, target_id: String, choice: String) -> void:
	if not _editable():
		return
	if target_id.is_empty():
		target_id = _selected
	var offer: Dictionary = EconomyBuildV1.offer(_camp, op, target_id, choice)
	if not offer.available:
		message.text = offer.reason
		return
	var identity: String = String(_camp.profile_id) + ":edit:" + RunSave.new_profile_id()
	_request = {"economy":EconomyBuildV1.request(_camp, op, target_id, choice, identity)}
	confirmation.title = "确认营地整备"
	confirmation.ok_button_text = "确认并保存"
	confirmation.dialog_text = offer.summary
	confirmation.popup_centered(Vector2i(660, 260))
