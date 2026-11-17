class_name CampArmoryView
extends MarginContainer
## Read-only equipment and workshop projection. Only confirmed requests leave this view.

signal equip_requested(member_id: int, instance_id: String)
signal repair_requested(instance_id: String)
signal workshop_requested(instance_id: String, mod: String)
signal navigation_requested(action: StringName)
signal selection_changed(instance_id: String)
signal economy_requested(request: Dictionary)

const YARD: Texture2D = preload("res://assets/camp_pixel/coast-yard.png")
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
var _comparison: VBoxContainer
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
var _detail_heading: Label
var _target_portrait: TextureRect
var _target_health: Label
var _target_bar: ProgressBar
var _current_art: TextureRect
var _proposed_art: TextureRect
var _stat_labels: Array[Label] = []
var _stat_current: Array[Label] = []
var _stat_proposed: Array[Label] = []
var _status_buttons: Array[Button] = []
var _status_tabs: HBoxContainer
var _feedback: HBoxContainer
var _display_textures: Dictionary[int, Texture2D] = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = CampStyle.theme(theme)
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 0)
	var backdrop: TextureRect = CampStyle.blue_hour_background(YARD)
	add_child(backdrop)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 0)
	add_child(page)
	_header = CampStyle.label("", 19)
	_heading = PixelMenu.masthead(page, "装备仓", _header)
	var inset: MarginContainer = MarginContainer.new()
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		inset.add_theme_constant_override("margin_" + side, 64)
	inset.add_theme_constant_override("margin_top", 12)
	inset.add_theme_constant_override("margin_bottom", 8)
	page.add_child(inset)
	var sheet: PanelContainer = PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, Color.TRANSPARENT, 16))
	inset.add_child(sheet)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	sheet.add_child(content)
	_split = HBoxContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.add_theme_constant_override("separation", 18)
	content.add_child(_split)
	_build_list(_column(_split, 1.0))
	var split_rule: ColorRect = PixelMenu.divider(_split, true)
	split_rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_detail(_column(_split, 1.0))
	_build_support(content)
	_feedback = HBoxContainer.new()
	content.add_child(_feedback)
	message = _wrapped("", 13, CampStyle.TEAL)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback.add_child(message)
	_retry_button = _button(_feedback, "重试保存本次整备", func() -> void: power_panel.retry_requested.emit())
	_retry_button.hide()
	_build_navigation(page)
	confirmation = _dialog("维修确认", "确认维修", _finish_repair)
	workshop_confirmation = _dialog("确认工坊改装", "安装并保存", _finish_workshop)
	_update_page()


func refresh(data: Dictionary, feedback: String, pending: bool) -> void:
	_save_scroll()
	_camp = data
	_pending = pending
	message.text = feedback
	_feedback.visible = pending or not feedback.is_empty()
	_retry_button.visible = pending
	_header.text = "第 %02d 天    口粮 %d    货币 %d    工具箱 %d" % [int(data.day), int(data.food), int(data.cash), WorkshopV1.tools(data)]
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
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = ratio
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	return column


func _build_list(column: VBoxContainer) -> void:
	_list_heading = CampStyle.label("武器库存", 24)
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
	_filters.add_theme_constant_override("separation", 10)
	column.add_child(_filters)
	_status_tabs = HBoxContainer.new()
	_status_tabs.add_theme_constant_override("separation", 4)
	_filters.add_child(_status_tabs)
	for index: int in range(STATUS.size()):
		var button: Button = _button(_status_tabs, STATUS[index], _choose_status.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
		button.custom_minimum_size.y = 42
		_status_buttons.append(button)
	PixelMenu.divider(_filters)
	# Keep the public selection model used by the controller; the four tabs are its visible controls.
	status_filter = _options(_filters, STATUS, _filter_changed)
	status_filter.name = "InventoryStatus"
	status_filter.hide()
	var query: HBoxContainer = HBoxContainer.new()
	query.add_theme_constant_override("separation", 8)
	_filters.add_child(query)
	type_filter = _options(query, ["全部类型", "枪械", "近战"], _filter_changed)
	type_filter.name = "InventoryType"
	type_filter.size_flags_horizontal = Control.SIZE_FILL
	type_filter.custom_minimum_size.x = 116
	CampStyle.text_button(type_filter)
	search = LineEdit.new()
	search.name = "InventorySearch"
	search.placeholder_text = "搜索名称 / 编号"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 42
	search.add_theme_font_size_override("font_size", 17)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_query: String) -> void: _filter_changed(0))
	query.add_child(search)
	_clear = _button(query, "清空", _clear_filters)
	_clear.add_theme_font_size_override("font_size", 15)
	_clear.tooltip_text = "清空搜索与类型、状态筛选"
	CampStyle.text_button(_clear)
	items = ItemList.new()
	items.name = "WeaponInventory"
	items.max_text_lines = 1
	items.fixed_icon_size = Vector2i(164, 82)
	items.add_theme_font_size_override("font_size", 18)
	items.add_theme_font_override("font", CampStyle.BOLD_FONT)
	items.add_theme_constant_override("h_separation", 22)
	items.add_theme_constant_override("v_separation", 20)
	items.add_theme_constant_override("line_separation", 6)
	items.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 8))
	items.add_theme_stylebox_override("focus", CampStyle.box(Color.TRANSPARENT, CampStyle.EDGE, 0))
	items.add_theme_stylebox_override("selected", CampStyle.box(CampStyle.SELECTED.darkened(0.12), Color.TRANSPARENT, 8))
	items.add_theme_stylebox_override("selected_focus", CampStyle.box(CampStyle.SELECTED.darkened(0.12), CampStyle.TEAL, 8))
	items.same_column_width = true
	items.max_columns = 1
	items.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.item_selected.connect(_select)
	column.add_child(items)
	var list_footer: HBoxContainer = HBoxContainer.new()
	list_footer.add_theme_constant_override("separation", 8)
	column.add_child(list_footer)
	_list_count = _wrapped("", 13, CampStyle.MUTED)
	_list_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_footer.add_child(_list_count)
	sort_order = _options(list_footer, ["按名称", "按实例编号"], _filter_changed)
	sort_order.name = "InventoryOrder"
	sort_order.size_flags_horizontal = Control.SIZE_SHRINK_END
	sort_order.add_theme_font_size_override("font_size", 14)
	CampStyle.text_button(sort_order)


func _build_detail(column: VBoxContainer) -> void:
	_detail_heading = CampStyle.label("配给预览", 26)
	_detail_heading.custom_minimum_size.y = 42
	column.add_child(_detail_heading)
	PixelMenu.divider(column)
	_empty = _wrapped("", 18, CampStyle.MUTED)
	column.add_child(_empty)
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
	_target_row.add_theme_constant_override("separation", 14)
	_detail_body.add_child(_target_row)
	_target_portrait = _equipment_picture(Vector2(64, 64))
	_target_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_target_row.add_child(_target_portrait)
	var person: VBoxContainer = VBoxContainer.new()
	person.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	person.add_theme_constant_override("separation", 4)
	_target_row.add_child(person)
	var person_top: HBoxContainer = HBoxContainer.new()
	person.add_child(person_top)
	target = _options(person_top, [], _select_target)
	target.name = "EquipTarget"
	target.fit_to_longest_item = false
	target.clip_text = true
	target.add_theme_font_size_override("font_size", 22)
	CampStyle.text_button(target)
	_target_health = CampStyle.label("", 18)
	_target_health.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	person_top.add_child(_target_health)
	_target_bar = ProgressBar.new()
	_target_bar.custom_minimum_size.y = 12
	_target_bar.show_percentage = false
	person.add_child(_target_bar)
	_title = CampStyle.label("", 24)
	_detail_body.add_child(_title)
	_meta = _wrapped("", 15, CampStyle.MUTED)
	_detail_body.add_child(_meta)
	var picture: PanelContainer = PanelContainer.new()
	picture.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 8))
	_detail_body.add_child(picture)
	_texture = _equipment_picture(Vector2(0, 82))
	picture.add_child(_texture)
	_comparison = VBoxContainer.new()
	_comparison.add_theme_constant_override("separation", 10)
	_detail_body.add_child(_comparison)
	var pair: HBoxContainer = HBoxContainer.new()
	pair.add_theme_constant_override("separation", 10)
	_comparison.add_child(pair)
	var current_box: VBoxContainer = _comparison_box(pair)
	_current = CampStyle.label("", 18)
	_current.clip_text = true
	_current.mouse_filter = Control.MOUSE_FILTER_PASS
	current_box.add_child(_current)
	_current_art = _equipment_picture(Vector2(0, 58))
	current_box.add_child(_current_art)
	var arrow: Label = CampStyle.label("→", 26)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.add_child(arrow)
	var proposed_box: VBoxContainer = _comparison_box(pair)
	_proposed = CampStyle.label("", 18)
	_proposed.clip_text = true
	_proposed.mouse_filter = Control.MOUSE_FILTER_PASS
	proposed_box.add_child(_proposed)
	_proposed_art = _equipment_picture(Vector2(0, 58))
	proposed_box.add_child(_proposed_art)
	var stats: GridContainer = GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 0)
	stats.add_theme_constant_override("v_separation", 0)
	_comparison.add_child(stats)
	for caption: String in ["", "当前", "拟配"]:
		var heading: Label = CampStyle.label(caption, 17)
		heading.add_theme_font_override("font", CampStyle.BOLD_FONT)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stat_cell(stats, heading, true)
	for caption: String in ["伤害", "攻击间隔", "射程 / 距离", "弹匣", "换弹"]:
		var stat: Label = CampStyle.label(caption, 17)
		_stat_labels.append(stat)
		_stat_cell(stats, stat)
		var current_value: Label = CampStyle.label("", 19)
		current_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stat_current.append(current_value)
		_stat_cell(stats, current_value)
		var proposed_value: Label = CampStyle.label("", 19)
		proposed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stat_proposed.append(proposed_value)
		_stat_cell(stats, proposed_value)
	_detail = _wrapped("", 13, CampStyle.MUTED)
	_detail_body.add_child(_detail)
	_economy_box = VBoxContainer.new()
	_economy_box.add_theme_constant_override("separation", 6)
	_detail_body.add_child(_economy_box)
	var operations: Array[Array] = [
		["sell", "", "预览出售"], ["upgrade_weapon", "", "强化枪械"],
		["basic_component", "quick_v1", "安装轻快机件"], ["basic_component", "reach_v1", "安装延伸瞄具"],
		["combat_component", WeaponModifiers.PIERCE, "安装穿透弹"],
		["combat_component", WeaponModifiers.REFUND, "安装击倒补弹"],
		["magazine", WorkshopV1.EXTENDED, "安装扩容弹匣"], ["magazine", WorkshopV1.QUICK, "安装快拆弹匣"]]
	for operation: Array in operations:
		var key: String = String(operation[0]) + ":" + String(operation[1])
		economy_buttons[key] = _button(_economy_box, operation[2],
			_preview_economy.bind(operation[0], "", operation[1]))
	_preview = _wrapped("", 14, CampStyle.TEAL)
	column.add_child(_preview)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var sale: Button = economy_buttons["sell:"]
	sale.reparent(actions)
	CampStyle.text_button(sale)
	_to_workshop = _button(actions, "前往工坊", func() -> void: show_workshop(_selected))
	_to_inventory = _button(actions, "返回装备仓", _return_to_inventory)
	CampStyle.text_button(_to_inventory)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(gap)
	for mod: String in MODS:
		workshop_buttons[mod] = _button(actions, WorkshopV1.name_for(mod), _confirm_workshop.bind(mod))
	repair_button = _button(actions, "确认维修…", _confirm_repair)
	PixelMenu.primary(repair_button)
	cancel_preview = _button(actions, "取消预览", func() -> void: cancel_swap_preview())
	cancel_preview.custom_minimum_size.y = 54
	cancel_preview.add_theme_font_size_override("font_size", 19)
	confirm_equip = _button(actions, "确认配给", _apply_equip)
	confirm_equip.name = "ConfirmEquip"
	confirm_equip.custom_minimum_size = Vector2(148, 54)
	confirm_equip.add_theme_font_size_override("font_size", 24)
	PixelMenu.primary(confirm_equip)


func _comparison_box(parent: HBoxContainer) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.EDGE, 8))
	parent.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	panel.add_child(body)
	return body


func _stat_cell(parent: GridContainer, label: Label, heading: bool = false) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = CampStyle.box(CampStyle.PANEL if heading else Color.TRANSPARENT, CampStyle.EDGE, 4)
	style.set_border_width_all(0)
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	panel.add_child(label)


func _display_art(texture: Texture2D) -> Texture2D:
	# UI framing removes transparent export margins; shared combat resources stay untouched.
	var identity: int = texture.get_instance_id()
	if _display_textures.has(identity):
		return _display_textures[identity]
	var source: Image = texture.get_image()
	if source == null or (source.is_compressed() and source.decompress() != OK):
		_display_textures[identity] = texture
		return texture
	var bounds: Rect2 = Rect2(source.get_used_rect())
	if not bounds.has_area():
		_display_textures[identity] = texture
		return texture
	var art: AtlasTexture = AtlasTexture.new()
	art.atlas = texture
	art.region = bounds.grow(2).intersection(Rect2(Vector2.ZERO, texture.get_size()))
	art.filter_clip = true
	_display_textures[identity] = art
	return art


func _equipment_picture(minimum: Vector2) -> TextureRect:
	var picture: TextureRect = TextureRect.new()
	picture.custom_minimum_size = minimum
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return picture


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
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = CampStyle.box(CampStyle.INK, CampStyle.EDGE, 8)
	style.set_border_width_all(0)
	style.border_width_top = 1
	style.content_margin_left = 64
	style.content_margin_right = 64
	panel.add_theme_stylebox_override("panel", style)
	page.add_child(panel)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	panel.add_child(footer)
	back_button = _button(footer, "营地 / Esc", func() -> void: navigation_requested.emit(&"camp"))
	CampStyle.text_button(back_button)
	var crew: Button = _button(footer, "队员", func() -> void: navigation_requested.emit(&"crew"))
	CampStyle.text_button(crew)
	_nav[&"inventory"] = _button(footer, "装备仓", show_inventory)
	_nav[&"workshop"] = _button(footer, "工坊", func() -> void: show_workshop())
	var supplies: Button = _button(footer, "补给", func() -> void: navigation_requested.emit(&"supplies"))
	CampStyle.text_button(supplies)
	_nav[&"support"] = _button(footer, "支援与道具", _show_page.bind(&"support"))
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	var depart: Button = _button(footer, "准备出击 →", func() -> void: navigation_requested.emit(&"bus"))
	depart.add_theme_font_size_override("font_size", 20)
	CampStyle.text_button(depart)


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
	_detail_heading.text = "工坊详情" if _tab == &"workshop" else "配给预览"
	_split.visible = _tab != &"support"
	_support.visible = _tab == &"support"
	_filters.visible = _tab == &"inventory"
	_workshop_tabs.visible = _tab == &"workshop"
	_banner.visible = _workshop_tabs.visible
	_list_heading.visible = _tab == &"workshop"
	for page: StringName in _nav:
		PixelMenu.tab(_nav[page], page == _tab)


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


func _choose_status(index: int) -> void:
	status_filter.select(index)
	_filter_changed(index)


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
		_status_buttons[index].text = STATUS[index]
		_status_buttons[index].tooltip_text = "%s · %d 件" % [STATUS[index], counts[index]]
		PixelMenu.tab(_status_buttons[index], index == status_filter.selected)
	_workshop_options[&"repair"].text = "维修 · %d" % counts[3]
	for mode: StringName in _workshop_options:
		_workshop_options[mode].add_theme_color_override("font_color", CampStyle.TEAL if mode == key else CampStyle.TEXT)
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
		var short_holder: String = String(SurvivorRoster.member(_camp.crew, owner).get("call_sign", "")) if owner > 0 else "仓库"
		var caption: String = "%s #%s · %s" % [weapon.display_name, WeaponInventory.short_id(item), STATUS[state]]
		if owner > 0:
			caption += " · " + short_holder
		var row: int = items.add_item(caption, weapon.presentation.texture)
		items.set_item_metadata(row, item.instance_id)
		items.set_item_custom_fg_color(row, CampStyle.DANGER if state == 3 else CampStyle.TEXT)
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
			target.add_item(String(member.call_sign), int(member.id))
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
	_title.visible = valid and not inventory
	_meta.visible = valid and not inventory
	_texture.get_parent().visible = valid and not inventory
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
	_texture.texture = _display_art(weapon.presentation.texture)
	if inventory:
		_show_comparison(item, owner)
	elif modification:
		_show_modifications(item, owner)
	else:
		_show_repair(item)


func _show_comparison(item: Dictionary, owner: int) -> void:
	var current: Dictionary = WeaponInventory.for_member(_camp, _target_id)
	_current.text = "当前 · " + ("无装备" if current.is_empty() else WeaponInventory.definition(current.weapon_id).display_name)
	_proposed.text = "拟配 · " + WeaponInventory.definition(item.weapon_id).display_name
	_current.tooltip_text = _item_name(current)
	_proposed.tooltip_text = _item_name(item)
	_current_art.texture = null if current.is_empty() else _display_art(WeaponInventory.definition(current.weapon_id).presentation.texture)
	_proposed_art.texture = _display_art(WeaponInventory.definition(item.weapon_id).presentation.texture)
	_refresh_target_preview()
	_refresh_stat_table(current, item)
	_detail.text = "含目标队员的特长、特性、已装道具与工坊加成。\n" + _item_attributes(item)
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


func _refresh_target_preview() -> void:
	var member: Dictionary = SurvivorRoster.member(_camp.get("crew", []), _target_id)
	var definition: SurvivorDefinition = SurvivorRoster.definition_for(member)
	_target_portrait.texture = definition.portrait if definition != null else null
	_target_health.text = "%d / %.0f" % [ceili(float(member.get("health", 0.0))), GrowthRules.maximum(member)] if not member.is_empty() else "没有可配给的存活队员"
	_target_bar.max_value = GrowthRules.maximum(member) if not member.is_empty() else 1.0
	_target_bar.value = float(member.get("health", 0.0))


func _refresh_stat_table(current: Dictionary, proposed: Dictionary) -> void:
	var before: Array[float] = _comparison_values(current)
	var after: Array[float] = _comparison_values(proposed)
	_stat_labels[0].text = "单弹丸伤害" if current.get("weapon_id") == "shotgun_v1" or proposed.get("weapon_id") == "shotgun_v1" else "伤害"
	for index: int in range(_stat_labels.size()):
		var left: float = before[index]
		var right: float = after[index]
		_stat_current[index].text = _comparison_value(index, left)
		_stat_proposed[index].text = _comparison_value(index, right)
		var color: Color = CampStyle.TEXT
		if left >= 0.0 and right >= 0.0 and not is_equal_approx(left, right):
			var better: bool = right < left if index in [1, 4] else right > left
			color = CampStyle.TEAL if better else CampStyle.DANGER
		_stat_proposed[index].add_theme_color_override("font_color", color)


func _comparison_values(item: Dictionary) -> Array[float]:
	if item.is_empty():
		return [-1.0, -1.0, -1.0, -1.0, -1.0]
	var melee: bool = CombatEquipment.melee(item.weapon_id)
	var factor: float = TraitRules.factor(SurvivorRoster.member(_camp.crew, _target_id), "shot") if _target_id > 0 else 1.0
	var stats: Dictionary = WeaponModifiers.effective(item, factor)
	var passive: Dictionary = _passive_factors() if _target_id > 0 else {}
	var personal: Dictionary = _personal_factors(_target_id)
	var damage: float = float(stats.damage) * (float(personal.get("melee", 1.0)) if melee else float(personal.get("ranged", 1.0)) * float(passive.get("damage", 1.0)))
	var magazine: Dictionary = WeaponMagazine.parameters(item.weapon_id, WorkshopV1.mod_for(_camp, item.instance_id))
	var capacity: float = float(magazine.capacity) if not magazine.is_empty() else -1.0
	var reload: float = float(magazine.seconds) * float(personal.get("reload", 1.0)) * float(passive.get("reload", 1.0)) * EconomyBuildV1.reload_factor(_camp) if not magazine.is_empty() else -1.0
	return [damage, float(stats.interval), float(stats.range), capacity, reload]


func _comparison_value(index: int, value: float) -> String:
	if value < 0.0:
		return "—"
	if index in [1, 4]:
		return "%.3f 秒" % value
	if index == 3:
		return "%d 发" % int(value)
	return "%.2f" % value if index == 0 else "%.0f" % value


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
		text += "\n%d 发 · 换弹 %.3f 秒（含工坊）" % [magazine.capacity, float(magazine.seconds) * float(personal.get("reload", 1.0)) * float(passive.get("reload", 1.0)) * EconomyBuildV1.reload_factor(_camp)]
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
	_detail.text = ("强化与弹匣方案随同一实例保留；可付费更换方案。" if EconomyBuildV1.enabled(_camp) else "每件符合条件的枪械仅可改装一次。方案随实例转配。") + "\n已装：%s" % WorkshopV1.name_for(installed)
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
		var factor: float = float(_personal_factors(owner).get("reload", 1.0)) * float(_passive_factors().get("reload", 1.0)) * EconomyBuildV1.reload_factor(_camp)
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
		_feedback.show()
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
		_feedback.show()
		message.text = "改装条件已变化，请重新确认。"
		return
	workshop_requested.emit(_selected, mod)


func _refresh_economy(item: Dictionary) -> void:
	var enabled: bool = EconomyBuildV1.enabled(_camp)
	_craft_row.visible = enabled and _tab == &"workshop"
	_economy_box.visible = enabled and not item.is_empty() and _tab == &"workshop"
	for weapon_id: String in craft_buttons:
		var offer: Dictionary = EconomyBuildV1.offer(_camp, "craft", weapon_id)
		craft_buttons[weapon_id].disabled = _pending or not offer.available
		craft_buttons[weapon_id].tooltip_text = offer.summary if offer.available else offer.reason
	for key: String in economy_buttons:
		var op: String = key.get_slice(":", 0)
		var choice: String = key.get_slice(":", 1)
		var button: Button = economy_buttons[key]
		button.visible = enabled and not item.is_empty() and ((op == "sell") == (_tab == &"inventory"))
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
		_feedback.show()
		message.text = offer.reason
		return
	var identity: String = String(_camp.profile_id) + ":edit:" + RunSave.new_profile_id()
	_request = {"economy":EconomyBuildV1.request(_camp, op, target_id, choice, identity)}
	confirmation.title = "确认营地整备"
	confirmation.ok_button_text = "确认并保存"
	confirmation.dialog_text = offer.summary
	confirmation.popup_centered(Vector2i(660, 260))
