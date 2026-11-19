class_name CampSceneView
extends Control
## Read-only scene adapter: emit original intentions, never edit campaign data.

signal action_requested(action: StringName, member_id: int)
signal facility_requested(choice: String)

const FACILITY_NAMES: Dictionary[String, String] = {"supply": "补给设施", "workshop": "工坊", "planning": "规划室"}

var scene_buttons: Dictionary[StringName, Button] = {}
var _scene_surface: Control
var _resource_values: Dictionary[String, Label] = {}

var input_allowed: Callable
var player_mode: bool = false
var world: CampSceneWorld
var hotspots: Dictionary[StringName, Button] = {}
var facility_buttons: Dictionary[String, Button] = {}
var member_buttons: Dictionary[int, Button] = {}
var footer_buttons: Dictionary[StringName, Button] = {}
var resource_text: Label
var eligibility_text: Label
var notice: Label
var info_close: Button
var _info: Control
var _info_title: Label
var _info_body: Label
var _data: Dictionary = {}
var _daily: Dictionary = {}
var _last_focus: String = "bus"
var _shortage_text: Label
var _return_close: Button
var _dismissed_return_id: String = ""
var _return_summary: PanelContainer
var _return_goods: Label
var _return_text: Label
var _return_advice: Label
var _return_objective: Label
var _team_scroll: ScrollContainer
var _team_count: Label
var _journey_caption: Label
var _atmosphere_caption: Label
var _departure_controls: VBoxContainer


func _ready() -> void:
	theme = CampSceneStyle.theme(theme)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "CampBackdrop"
	backdrop.color = CampStyle.INK
	# Keep the full-screen backing below the scene plate and all controls.
	backdrop.z_index = -20
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_surface = Control.new()
	_scene_surface.name = "CampSceneSurface"
	_scene_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_surface.clip_contents = true
	add_child(_scene_surface)
	CampStyle.place(_scene_surface, Rect2(0, 108, 976, 612))
	world = CampSceneWorld.new()
	world.name = "TransitYard"
	_scene_surface.add_child(world)
	resized.connect(_resize_world)
	_resize_world()
	_build_blue_hour_header()
	world.atmosphere_changed.connect(_update_atmosphere_caption)
	_build_facilities()
	_build_blue_hour_team()
	_build_blue_hour_footer()
	_build_scene_actions()
	_build_info()
	visibility_changed.connect(_shown)
	clear()


func _build_scene_actions() -> void:
	var captions: Dictionary[StringName, String] = {
		&"bus":"巴士 · 选择行动", &"crew":"集合棚 · 队员",
		&"weapons":"整备台 · 配装", &"training":"篝火 · 训练",
	}
	for action: StringName in captions:
		var button: Button = Button.new()
		button.name = "Scene" + String(action).capitalize()
		button.text = captions[action]
		_style_pin(button)
		button.pressed.connect(_request.bind(action, 0))
		button.focus_entered.connect(_announce.bind(button, button.text))
		add_child(button)
		scene_buttons[action] = button
	_position_scene_controls()


func _position_scene_controls() -> void:
	if world == null:
		return
	var fit: float = minf(size.x / 1280.0, size.y / 720.0)
	for id: String in facility_buttons:
		var at: Vector2 = get_global_transform().affine_inverse() * world.to_global(CampSceneLayout.facility_door(id))
		_place_pin(facility_buttons[id], at, Vector2(128, 26) * fit)
	for action: StringName in scene_buttons:
		var area: Rect2 = CampSceneLayout.AREAS[action]
		var point: Vector2 = Vector2(area.get_center().x, area.end.y)
		var at: Vector2 = get_global_transform().affine_inverse() * world.to_global(point)
		_place_pin(scene_buttons[action], at, Vector2(128, 26) * fit)


func _place_pin(button: Button, at: Vector2, extent: Vector2) -> void:
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	button.position = at - Vector2(extent.x * 0.5, 0)
	button.size = extent


func _style_pin(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 13)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# The scene remains artwork; labels appear only when a player points or tabs here.
	button.add_theme_color_override("font_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)
	for state: String in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, CampSceneStyle.AMBER)
	button.add_theme_stylebox_override("normal", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 2))
	button.add_theme_stylebox_override("hover", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 2))
	button.add_theme_stylebox_override("pressed", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL, 2))
	button.add_theme_stylebox_override("focus", CampStyle.box(CampStyle.INK, CampStyle.TEAL, 2))


func _build_blue_hour_header() -> void:
	var header: PanelContainer = _blue_hour_panel("CampHud", Rect2(0, 0, 1280, 56), CampStyle.INK)
	var style: StyleBoxFlat = CampStyle.box(CampStyle.INK, CampStyle.EDGE, 14)
	style.set_border_width_all(0)
	style.border_width_bottom = 3
	style.content_margin_top = 1
	style.content_margin_bottom = 2
	header.add_theme_stylebox_override("panel", style)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 19)
	header.add_child(row)
	var logo: Label = CampStyle.label("蓝时归航", 34)
	var slant: FontVariation = FontVariation.new()
	slant.base_font = CampStyle.BOLD_FONT
	slant.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.16, 1), Vector2.ZERO)
	logo.add_theme_font_override("font", slant)
	logo.custom_minimum_size.x = 210
	row.add_child(logo)
	var divider: Label = CampStyle.label("│", 30, CampStyle.EDGE)
	row.add_child(divider)
	var hub: Label = CampStyle.label("蓝时驿站", 31)
	hub.custom_minimum_size.x = 220
	row.add_child(hub)
	var badge: PanelContainer = PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 5))
	row.add_child(badge)
	_resource_values["day"] = CampStyle.label("第 2 天", 24)
	badge.add_child(_resource_values["day"])
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for key: String in ["food", "cash", "tools", "required"]:
		var group: HBoxContainer = HBoxContainer.new()
		group.add_theme_constant_override("separation", 6)
		row.add_child(group)
		if key != "required":
			var icon: TextureRect = TextureRect.new()
			icon.texture = load("res://assets/camp_pixel/" + key + ".svg") as Texture2D
			icon.custom_minimum_size = Vector2(24, 28)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			group.add_child(icon)
		_resource_values[key] = CampStyle.label("", 25)
		group.add_child(_resource_values[key])
	resource_text = CampStyle.label("")
	resource_text.hide()
	add_child(resource_text)
	_atmosphere_caption = CampStyle.label("")
	_atmosphere_caption.name = "AtmosphereCaption"
	_atmosphere_caption.hide()
	add_child(_atmosphere_caption)
	_update_atmosphere_caption(world.atmosphere_name())
	_shortage_text = CampStyle.label("")
	_shortage_text.hide()
	add_child(_shortage_text)
	_return_summary = _blue_hour_panel("ReturnSummary", Rect2(20, 634, 936, 70), CampStyle.PANEL)
	_return_summary.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var return_row: HBoxContainer = HBoxContainer.new()
	return_row.add_theme_constant_override("separation", 20)
	_return_summary.add_child(return_row)
	var return_title: VBoxContainer = VBoxContainer.new()
	return_title.custom_minimum_size.x = 172
	return_title.add_theme_constant_override("separation", 2)
	return_row.add_child(return_title)
	return_title.add_child(CampStyle.label("上次归航 · 已入账", 17, CampStyle.TEAL))
	_return_goods = CampStyle.label("", 14, CampSceneStyle.MUTED)
	return_title.add_child(_return_goods)
	var return_details: VBoxContainer = VBoxContainer.new()
	return_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return_details.add_theme_constant_override("separation", 2)
	return_row.add_child(return_details)
	_return_close = Button.new()
	_return_close.text = "×"
	_return_close.tooltip_text = "收起归航记录"
	_return_close.custom_minimum_size = Vector2(30, 30)
	_return_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	CampStyle.text_button(_return_close)
	_return_close.pressed.connect(_dismiss_return_summary)
	return_row.add_child(_return_close)
	_return_text = CampStyle.label("", 16)
	_return_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return_details.add_child(_return_text)
	_return_objective = CampStyle.label("", 14, CampStyle.TEAL)
	return_details.add_child(_return_objective)
	_return_advice = CampStyle.label("", 14, CampStyle.MUTED)
	return_details.add_child(_return_advice)


func _build_facilities() -> void:
	for choice: String in FACILITY_NAMES:
		var button: Button = Button.new()
		button.name = "Facility" + choice.capitalize()
		_style_pin(button)
		button.pressed.connect(_activate_facility.bind(choice))
		button.focus_entered.connect(_announce.bind(button, ""))
		add_child(button)
		facility_buttons[choice] = button


func _activate_facility(choice: String) -> void:
	if not _allows_input() or not FACILITY_NAMES.has(choice):
		return
	var tier: int = CampSceneLayout.facility_level(_data, choice)
	if tier == 0:
		var available: bool = false
		if EconomyBuildV1.enabled(_data):
			available = EconomyBuildV1.offer(_data, "build", choice).available
		else:
			available = CampFacilities.can_build(_data, choice)
		if available:
			facility_requested.emit(choice)
		else:
			_request(&"supplies", 0)
		return
	_request(&"workshop" if choice == "workshop" else &"planning" if choice == "planning" else &"supplies", 0)


func _build_blue_hour_team() -> void:
	var panel: PanelContainer = _blue_hour_panel("TeamPanel", Rect2(976, 108, 304, 364), CampStyle.INK)
	var style: StyleBoxFlat = CampStyle.box(CampStyle.INK, CampStyle.EDGE, 12)
	style.set_border_width_all(0)
	style.border_width_left = 1
	style.border_width_bottom = 2
	style.content_margin_top = 16
	panel.add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	_team_count = CampStyle.label("")
	_team_count.hide()
	column.add_child(_team_count)
	_team_scroll = ScrollContainer.new()
	_team_scroll.name = "TeamScroll"
	_team_scroll.follow_focus = true
	_team_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_team_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_team_scroll)
	_team_scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	var roster: VBoxContainer = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 8)
	_team_scroll.add_child(roster)
	for id: int in range(1, RosterState.MAX_HISTORY + 1):
		var button: Button = _blue_hour_button(roster, StringName("member%d" % id), "", true)
		button.set_meta("member_id", id)
		button.custom_minimum_size.y = 74
		CampStyle.text_button(button)
		member_buttons[id] = button
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		button.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_top = 7
		row.offset_bottom = -7
		var portrait: TextureRect = TextureRect.new()
		portrait.name = "Portrait"
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(62, 60)
		row.add_child(portrait)
		var labels: VBoxContainer = VBoxContainer.new()
		labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		labels.alignment = BoxContainer.ALIGNMENT_CENTER
		labels.add_theme_constant_override("separation", 7)
		row.add_child(labels)
		var heading: HBoxContainer = HBoxContainer.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(heading)
		var call_sign: Label = CampStyle.label("", 22)
		call_sign.name = "CallSign"
		call_sign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		call_sign.clip_text = true
		call_sign.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.add_child(call_sign)
		var health: Label = CampStyle.label("", 20)
		health.name = "Health"
		heading.add_child(health)
		var health_bar: ProgressBar = ProgressBar.new()
		health_bar.name = "HealthBar"
		health_bar.show_percentage = false
		health_bar.custom_minimum_size.y = 13
		health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(health_bar)
		for field: String in ["Trait", "Weapon"]:
			var label: Label = CampStyle.label("")
			label.name = field
			label.hide()
			labels.add_child(label)
	var departure: PanelContainer = _blue_hour_panel("DeparturePanel", Rect2(976, 472, 304, 248), CampStyle.INK)
	var departure_style: StyleBoxFlat = CampStyle.box(CampStyle.INK, Color.TRANSPARENT, 12)
	departure_style.content_margin_top = 36
	departure.add_theme_stylebox_override("panel", departure_style)
	_departure_controls = VBoxContainer.new()
	_departure_controls.add_theme_constant_override("separation", 38)
	departure.add_child(_departure_controls)
	_journey_caption = CampStyle.label("")
	_journey_caption.hide()
	_departure_controls.add_child(_journey_caption)
	var progress_panel: PanelContainer = PanelContainer.new()
	progress_panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, Color.TRANSPARENT, 4))
	progress_panel.custom_minimum_size.y = 48
	_departure_controls.add_child(progress_panel)
	eligibility_text = CampStyle.label("", 26)
	eligibility_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eligibility_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eligibility_text.max_lines_visible = 2
	eligibility_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progress_panel.add_child(eligibility_text)


func _build_blue_hour_footer() -> void:
	var panel: PanelContainer = _blue_hour_panel("CampActions", Rect2(0, 56, 1280, 52), CampStyle.INK)
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, Color.TRANSPARENT, 5))
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	var labels: Dictionary[StringName, String] = {&"crew":"队员", &"weapons":"装备", &"workshop":"工坊",
		&"supplies":"补给", &"training":"训练", &"specialties":"专精"}
	for action: StringName in labels:
		var button: Button = _blue_hour_button(row, action, labels[action])
		button.custom_minimum_size.x = 115
		button.add_theme_font_size_override("font_size", 25)
		CampStyle.text_button(button)
		button.add_theme_stylebox_override("normal", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 4))
		button.add_theme_stylebox_override("hover", CampStyle.box(CampStyle.PANEL, Color.TRANSPARENT, 4))
		button.add_theme_stylebox_override("pressed", CampStyle.box(CampStyle.SURFACE, Color.TRANSPARENT, 4))
		if action == &"crew":
			button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.SELECTED, Color.TRANSPARENT, 4))
		if action == &"specialties":
			footer_buttons[action] = button
		else:
			hotspots[action] = button
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var utilities: Dictionary[StringName, String] = {&"home":"主菜单", &"sound":"声音", &"quit":"退出"}
	for action: StringName in utilities:
		var button: Button = _blue_hour_button(row, action, utilities[action])
		button.add_theme_font_size_override("font_size", 15)
		CampStyle.text_button(button)
		footer_buttons[action] = button
	var depart: Button = _blue_hour_button(_departure_controls, &"bus", "选择行动 →")
	depart.custom_minimum_size.y = 80
	depart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	depart.add_theme_font_size_override("font_size", 35)
	CampStyle.primary(depart)
	depart.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.CORAL.darkened(0.08), Color.TRANSPARENT, 8))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		depart.add_theme_color_override(state, Color.WHITE)
	depart.reparent(self)
	CampStyle.place(depart, Rect2(988, 594, 280, 80))
	hotspots[&"bus"] = depart
	notice = CampStyle.label("", 14, CampSceneStyle.MUTED)
	notice.name = "CampNotice"
	notice.clip_text = true
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(notice)
	CampStyle.place(notice, Rect2(990, 688, 276, 24))
	notice.add_theme_font_size_override("font_size", 12)


func _blue_hour_panel(node_name: String, rect: Rect2, colour: Color) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", CampStyle.box(colour, Color.TRANSPARENT, 12))
	add_child(panel)
	CampStyle.place(panel, rect)
	return panel


func _blue_hour_button(parent: Container, action: StringName, caption: String, member_hover: bool = false) -> Button:
	var button: Button = PersonaCard.HoverButton.new() if member_hover else Button.new()
	button.name = String(action)
	button.text = caption
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size.y = 40
	parent.add_child(button)
	button.pressed.connect(func() -> void: _request(action, int(button.get_meta("member_id", 0))))
	button.mouse_entered.connect(_announce.bind(button, caption))
	button.focus_entered.connect(_announce.bind(button, caption))
	return button


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or (input_allowed.is_valid() and not input_allowed.call()):
		return
	if not event.is_action_pressed("ui_focus_next") and not event.is_action_pressed("ui_focus_prev") and not event.is_action_pressed("ui_accept"):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if info_visible():
		if focus != info_close:
			info_close.grab_focus()
			get_viewport().set_input_as_handled()
	elif focus == null or not is_ancestor_of(focus):
		restore_focus()
		get_viewport().set_input_as_handled()


func _allows_input() -> bool:
	return is_visible_in_tree() and not _data.is_empty() and not info_visible() and (not input_allowed.is_valid() or input_allowed.call())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _allows_input():
		world.highlight(world.to_local(get_global_mouse_position()))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _allows_input():
		activate_at(world.to_local(get_global_mouse_position()))
		accept_event()


func activate_at(view_point: Vector2) -> void:
	if not _allows_input():
		return
	var hit: Dictionary = world.pick(view_point)
	if hit.has("facility"):
		_activate_facility(hit.facility)
	elif hit.has("action"):
		_request(hit.action, int(hit.member_id))


func refresh(data: Dictionary, daily: Dictionary, can_depart: bool, reason: String, feedback: String = "") -> void:
	_data = data.duplicate(true)
	_daily = daily.duplicate(true)
	world.refresh_camp(data, can_depart)
	_refresh_blue_hour(data, daily, can_depart, reason, feedback)


func _refresh_blue_hour(data: Dictionary, daily: Dictionary, can_depart: bool, reason: String, feedback: String) -> void:
	resource_text.text = "第 %d 天     货币 %d     食物 %d     今日需粮 %d" % [data.day, data.cash, data.food, daily.required]
	if WorkshopV1.enabled(data):
		resource_text.text += "     工具箱 %d" % WorkshopV1.tools(data)
	resource_text.tooltip_text = resource_text.text
	_resource_values["day"].text = "第%d天" % data.day
	_resource_values["food"].text = "食物%d" % data.food
	_resource_values["cash"].text = "货币%d" % data.cash
	_resource_values["tools"].text = "工具箱%d" % (WorkshopV1.tools(data) if WorkshopV1.enabled(data) else 0)
	_resource_values["required"].text = "今日需粮%d" % daily.required
	_resource_values["required"].add_theme_color_override("font_color", CampStyle.DANGER if daily.shortage > 0 else CampStyle.TEXT)
	var pressure: String = _campaign_pressure(data)
	_journey_caption.text = "旅程进度" if pressure.is_empty() else pressure
	_shortage_text.text = "口粮缺口 %d · 可考虑先补给" % daily.shortage if daily.shortage > 0 else "口粮缺口 0 · 库存充足"
	var build: Dictionary = data.get("journey", {}).get("build", {})
	var specialty: String = OpeningBuild.plan(data)
	footer_buttons[&"specialties"].visible = OpeningBuild.is_m47(data)
	if not specialty.is_empty():
		_journey_caption.text += " · " + OpeningBuild.PLANS[specialty].title
	if build.has("opening"):
		var equipped: PackedStringArray = []
		for item: String in build.slots:
			if not item.is_empty():
				equipped.append(BuildItems.definitions(BuildState.pool(data))[item].name)
		_shortage_text.text += "   ·   已配 " + ("、".join(equipped) if not equipped.is_empty() else "空槽")
	_shortage_text.add_theme_color_override("font_color", CampStyle.DANGER if daily.shortage > 0 else CampSceneStyle.MUTED)
	_shortage_text.tooltip_text = _shortage_text.text
	var last: Dictionary = data.last_day
	for choice: String in FACILITY_NAMES:
		var button: Button = facility_buttons[choice]
		var level: int = CampSceneLayout.facility_level(data, choice)
		button.visible = choice != "planning" or EconomyBuildV1.enabled(data)
		button.text = "%s · %s" % [FACILITY_NAMES[choice], "待建" if level == 0 else "%d 级" % level]
		button.tooltip_text = "点击查看设施与建设" if level == 0 else "点击打开工坊" if choice == "workshop" else "点击打开特长训练" if choice == "planning" else "点击查看补给与升级"
		if EconomyBuildV1.enabled(data):
			button.tooltip_text += "\n" + EconomyBuildV1.facility_effect(choice, level)
		button.tooltip_text = button.text + "\n" + button.tooltip_text
		button.disabled = false
		scene_buttons[&"bus"].disabled = not can_depart
	_return_summary.visible = not last.is_empty() and String(data.last_settlement_id) != _dismissed_return_id
	if not last.is_empty():
		var task: Dictionary = last.get("task", {})
		var returned_weapons: Array = data.weapons.filter(func(item: Dictionary) -> bool:
			return item.get("acquired_sortie") == data.last_settlement_id)
		_return_goods.text = "入库 %d 币 · %d 件武器" % [last.cash_gained, returned_weapons.size()]
		_return_text.text = ReturnFeedback.food_text(last)
		var morning: String = ReturnFeedback.starvation_text(data.crew, data.journey.deaths, data.last_settlement_id)
		if not morning.is_empty():
			_return_text.text = "第 %d 天清晨 · %s\n%s" % [int(data.day), morning, _return_text.text]
		_return_objective.visible = not task.is_empty()
		_return_objective.text = TaskActions.summary_text(task) if not task.is_empty() else ""
		_return_advice.text = "损坏武器可先在武器整备中维修，再配装。"
		_return_advice.visible = returned_weapons.any(func(item: Dictionary) -> bool: return item.condition == "damaged")
	eligibility_text.text = reason
	eligibility_text.tooltip_text = reason
	if CampaignState.is_short(data):
		var progress: Dictionary = CampaignRules.display(data.journey.campaign)
		eligibility_text.text = progress.progress
		eligibility_text.tooltip_text = progress.title + " · " + progress.detail
	elif last.has("task"):
		eligibility_text.text = TaskActions.summary_text(last.task)
		eligibility_text.tooltip_text = eligibility_text.text
	eligibility_text.add_theme_font_size_override("font_size", 22 if eligibility_text.text.length() > 18 else 26)
	notice.text = feedback if not feedback.is_empty() else "点击院内设施或同行者   ·   Tab 切换   ·   Enter 确认   ·   Esc 返回"
	notice.tooltip_text = notice.text
	hotspots[&"bus"].disabled = not can_depart
	hotspots[&"bus"].tooltip_text = "选择出击目标" if can_depart else reason
	var active: Array[int] = world.visible_member_ids
	_team_count.text = "%d 人在营 · 点击查看档案" % active.size()
	hotspots[&"crew"].set_meta("member_id", active[0] if not active.is_empty() else 0)
	hotspots[&"training"].text = "训练" if TrainingState.is_family(data) else "休憩"
	for id: int in member_buttons:
		var button: Button = member_buttons[id]
		button.visible = id in active
		if button.visible:
			_refresh_blue_hour_member(button, data, id)
	_link_focus()
	_resize_world()


func _dismiss_return_summary() -> void:
	_dismissed_return_id = String(_data.get("last_settlement_id", ""))
	_return_summary.hide()
	_link_focus()
	restore_focus()


func _update_atmosphere_caption(atmosphere: String) -> void:
	_atmosphere_caption.text = "旧渔协院落 · " + atmosphere


func _campaign_pressure(data: Dictionary) -> String:
	var campaign: Dictionary = data.get("journey", {}).get("campaign", {})
	if not CampaignRules.campaign_pressure_enabled(campaign) or campaign.outcome != "ACTIVE":
		return ""
	return CampaignPressureV1.label(CampaignPressureV1.tier_for(int(data.settled_sorties)))


func _refresh_blue_hour_member(button: Button, data: Dictionary, id: int) -> void:
	var member: Dictionary = SurvivorRoster.member(data.crew, id)
	var definition: SurvivorDefinition = SurvivorRoster.definition_for(member)
	var portrait: TextureRect = button.find_child("Portrait", true, false) as TextureRect
	portrait.texture = definition.portrait
	var specialty: Label = button.find_child("Trait", true, false) as Label
	var trait_id: int = TraitRules.IDS.find(member.get("growth", {}).get("trait", {}).get("id", ""))
	specialty.text = TraitRules.NAMES[trait_id] if trait_id >= 0 else "同行队员"
	if id == FirstAidV1.SOURCE_ID and CampaignRules.first_aid_enabled(data.get("journey", {}).get("campaign")) \
			and FirstAidV1.qualified(data):
		specialty.text = FirstAidV1.TITLE
	elif id == WeaponInventory.MECHANIC_ID and WeaponInventory.mechanic_available(data):
		specialty.text = WeaponInventory.MECHANIC_TITLE
	specialty.add_theme_color_override("font_color", definition.colour)
	var call_sign: Label = button.find_child("CallSign", true, false) as Label
	call_sign.text = member.call_sign
	var health: Label = button.find_child("Health", true, false) as Label
	health.text = "%.0f/%.0f" % [member.health, GrowthRules.maximum(member)]
	var health_bar: ProgressBar = button.find_child("HealthBar", true, false) as ProgressBar
	health_bar.max_value = GrowthRules.maximum(member)
	health_bar.value = float(member.health)
	var weapon: Label = button.find_child("Weapon", true, false) as Label
	var equipped: Dictionary = WeaponInventory.for_member(data, id)
	weapon.text = WeaponInventory.definition(equipped.weapon_id).display_name if not equipped.is_empty() else "未装备"
	button.tooltip_text = PersonaCard.camp_hover(data, id) + "\n查看队员档案"


func clear() -> void:
	if world == null:
		return
	world.refresh([])
	for button: Button in member_buttons.values():
		button.hide()
	if is_instance_valid(_return_summary):
		_return_summary.hide()
	_info.hide()
	_data.clear()
	_daily.clear()


func info_visible() -> bool:
	return is_instance_valid(_info) and _info.visible


func open_info(action: StringName) -> void:
	if _data.is_empty():
		return
	if action == &"training":
		_info_title.text = "营地训练尚未开放"
		_info_body.text = "这里暂时是休憩与集合的篝火。\n个人特性和食物训练将在后续阶段单独设计。\n查看此处不会消耗食物、增加经验或改变属性。"
		if TraitState.is_family(_data):
			_info_body.text = "这里暂时是休憩与集合的篝火。\n个人特性通过本人真实出击行动成长；食物训练尚未开放。\n查看此处不会消耗食物、增加经验或改变属性。"
	else:
		_info_title.text = "物资堆场 / 当前营地"
		_info_body.text = "食物 %d · 货币 %d · 武器 %d 件\n今日口粮需求 %d · %s\n实际搜集、归航与整备结果由原营地系统结算。" % [_data.food, _data.cash, _data.weapons.size(), _daily.required, "库存足够" if _daily.shortage == 0 else "缺口%d，建议出击搜集" % int(_daily.shortage)]
	_info.show()
	info_close.grab_focus()


func close_info() -> void:
	_info.hide()
	restore_focus()


func restore_focus() -> void:
	if not is_visible_in_tree() or info_visible():
		return
	var button: Button = find_child(_last_focus, true, false) as Button
	if button != null and button.is_visible_in_tree() and not button.disabled:
		button.grab_focus()
	elif not hotspots[&"bus"].disabled:
		hotspots[&"bus"].grab_focus()
	else:
		hotspots[&"crew"].grab_focus()


func _request(action: StringName, member_id: int) -> void:
	if not _allows_input():
		return
	if action == &"bus" and hotspots[&"bus"].disabled:
		return
	if String(action).begins_with("member"):
		action_requested.emit(&"crew", member_id)
	else:
		action_requested.emit(action, member_id)


func _announce(button: Button, text: String) -> void:
	_last_focus = String(button.name)
	if notice != null:
		notice.text = text.replace("\n", " · ") if not text.is_empty() else button.tooltip_text.replace("\n", " · ")
		notice.tooltip_text = notice.text


func _link_focus() -> void:
	var sequence: Array[Button] = []
	if is_instance_valid(_return_close) and _return_close.is_visible_in_tree():
		sequence.append(_return_close)
	for action: StringName in [&"bus", &"crew", &"weapons", &"workshop", &"supplies", &"training"]:
		if hotspots.has(action) and not hotspots[action].disabled:
			sequence.append(hotspots[action])
	for id: int in range(1, RosterState.MAX_HISTORY + 1):
		if member_buttons[id].visible:
			sequence.append(member_buttons[id])
	for button: Button in facility_buttons.values():
		if button.is_visible_in_tree() and not button.disabled:
			sequence.append(button)
	for button: Button in scene_buttons.values():
		if not button.disabled:
			sequence.append(button)
	for button: Button in footer_buttons.values():
		if button.visible:
			sequence.append(button)
	for index: int in range(sequence.size()):
		sequence[index].focus_next = sequence[(index + 1) % sequence.size()].get_path()
		sequence[index].focus_previous = sequence[(index - 1 + sequence.size()) % sequence.size()].get_path()


func _build_info() -> void:
	_info = Control.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.mouse_filter = Control.MOUSE_FILTER_STOP
	_info.mouse_force_pass_scroll_events = false
	add_child(_info)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.07, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_force_pass_scroll_events = false
	_info.add_child(dim)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(centre)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 680
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampSceneStyle.PANEL, Color.TRANSPARENT, 28))
	centre.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	panel.add_child(column)
	_info_title = CampStyle.label("", 28)
	column.add_child(_info_title)
	_info_body = CampStyle.label("", 20)
	_info_body.custom_minimum_size = Vector2(620, 126)
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_info_body)
	info_close = Button.new()
	info_close.text = "返回营地 / Esc"
	info_close.custom_minimum_size.y = 48
	CampStyle.primary(info_close)
	info_close.pressed.connect(close_info)
	column.add_child(info_close)
	info_close.focus_next = info_close.get_path()
	info_close.focus_previous = info_close.get_path()
	_info.hide()


func _shown() -> void:
	if is_visible_in_tree():
		restore_focus.call_deferred()


func _resize_world() -> void:
	if world == null or _scene_surface == null:
		return
	var extent: Vector2 = Vector2(size.x * 976.0 / 1280.0, size.y * 612.0 / 720.0)
	var fit: float = maxf(extent.x / CampSceneLayout.SCENE_SIZE.x, extent.y / CampSceneLayout.SCENE_SIZE.y)
	world.scale = Vector2.ONE * fit
	world.position = (extent - CampSceneLayout.SCENE_SIZE * fit) * 0.5
	_position_scene_controls()
