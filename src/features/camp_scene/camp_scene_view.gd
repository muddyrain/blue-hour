class_name CampSceneView
extends Control
## Read-only scene adapter: emit original intentions, never edit campaign data.

signal action_requested(action: StringName, member_id: int)
signal facility_requested(choice: String)

const FACILITY_NAMES: Dictionary[String, String] = {"supply": "补给设施", "workshop": "工坊升级"}

const CAPTIONS: Dictionary[StringName, String] = {
	&"bus": "巴士停靠\n选择出击目标 →",
	&"crew": "同行者集合棚\n名册 / 等级档案 →",
	&"weapons": "武器整备\n仓库 / 维修 / 配装 →",
	&"supplies": "物资堆场\n查看钱粮与今日口粮",
	&"training": "篝火休憩\n训练尚未开放",
}
const BLUE_HOUR_YARD: Texture2D = preload("res://assets/ui/m20/camp-blue-hour.png")

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
var _return_summary: PanelContainer
var _return_goods: Label
var _return_text: Label
var _return_advice: Label
var _facilities: PanelContainer
var _facility_heading: Label
var _team_scroll: ScrollContainer
var _team_count: Label
var _journey_caption: Label


func _ready() -> void:
	world = CampSceneWorld.new()
	world.name = "TransitYard"
	add_child(world)
	resized.connect(_resize_world)
	_resize_world()
	if player_mode:
		world.hide()
		_build_blue_hour()
		return
	var header: PanelContainer = PanelContainer.new()
	header.name = "CampHud"
	header.add_theme_stylebox_override("panel", CampStyle.box(Color("102730"), Color("638983"), 12))
	CampStyle.place(header, Rect2(24, 16, 1232, 82))
	add_child(header)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	header.add_child(row)
	var title: VBoxContainer = VBoxContainer.new()
	title.custom_minimum_size.x = 344
	row.add_child(title)
	title.add_child(CampStyle.label("蓝时驿站 / 河岸停靠院", 24))
	title.add_child(CampStyle.label("开发试玩版" if player_mode else "营地场景原型 · PROJECT_TEMP", 16, CampStyle.TEAL))
	var state: VBoxContainer = VBoxContainer.new()
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(state)
	resource_text = CampStyle.label("", 20)
	state.add_child(resource_text)
	eligibility_text = CampStyle.label("", 17, CampStyle.AMBER)
	state.add_child(eligibility_text)
	for action: StringName in CampSceneLayout.AREAS:
		var button: Button = _hotspot(action, CampSceneLayout.AREAS[action], CAPTIONS[action])
		hotspots[action] = button
	for id: int in [1, 2, 3, 4, 5]:
		var point: Vector2 = CampSceneLayout.member_position(id)
		var button: Button = _hotspot(StringName("member%d" % id), Rect2(point + Vector2(-69, -99), Vector2(138, 173)), "")
		button.set_meta("member_id", id)
		member_buttons[id] = button
	var footer: PanelContainer = PanelContainer.new()
	footer.add_theme_stylebox_override("panel", CampStyle.box(Color("102730"), Color("34535d"), 8))
	CampStyle.place(footer, Rect2(24, 650, 1232, 54))
	add_child(footer)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	footer.add_child(actions)
	notice = CampStyle.label("Tab选设施 · Enter/Space确认 · Esc关闭当前页", 17)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.clip_text = true
	actions.add_child(notice)
	for action: StringName in [&"sound", &"legacy", &"home", &"quit"]:
		if player_mode and action==&"legacy": continue
		var button: Button = Button.new()
		button.name = String(action)
		button.text = {&"sound":"声音", &"legacy":"原营地入口", &"home":"返回首页", &"quit":"退出游戏"}[action]
		button.custom_minimum_size.x = 108 if action == &"legacy" else 96
		button.pressed.connect(_request.bind(action, 0))
		actions.add_child(button)
		footer_buttons[action] = button
	_build_info()
	visibility_changed.connect(_shown)
	clear()


func _build_blue_hour() -> void:
	var background: TextureRect = CampStyle.blue_hour_background(BLUE_HOUR_YARD)
	add_child(background)
	move_child(background, 0)
	_build_blue_hour_header()
	_build_facilities()
	_build_blue_hour_team()
	_build_blue_hour_footer()
	_build_info()
	visibility_changed.connect(_shown)
	clear()


func _build_blue_hour_header() -> void:
	var header: PanelContainer = _blue_hour_panel("CampHud", Rect2(42, 32, 1196, 77), Color(0.045, 0.10, 0.14, 0.94))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	header.add_child(row)
	var title: VBoxContainer = VBoxContainer.new()
	title.custom_minimum_size.x = 224
	title.add_theme_constant_override("separation", 1)
	row.add_child(title)
	title.add_child(CampStyle.label("蓝时驿站", 26))
	title.add_child(CampStyle.label("河岸停靠院", 14, CampStyle.TEAL))
	var stores: VBoxContainer = VBoxContainer.new()
	stores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stores.add_theme_constant_override("separation", 2)
	row.add_child(stores)
	resource_text = CampStyle.label("", 21)
	stores.add_child(resource_text)
	_shortage_text = CampStyle.label("", 15, CampStyle.MUTED)
	stores.add_child(_shortage_text)
	var investigation: VBoxContainer = VBoxContainer.new()
	investigation.custom_minimum_size.x = 218
	investigation.add_theme_constant_override("separation", 2)
	row.add_child(investigation)
	_journey_caption = CampStyle.label("旅程进度", 14, CampStyle.MUTED)
	investigation.add_child(_journey_caption)
	eligibility_text = CampStyle.label("", 17, CampStyle.TEAL)
	eligibility_text.clip_text = true
	eligibility_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	investigation.add_child(eligibility_text)
	_return_summary = _blue_hour_panel("ReturnSummary", Rect2(42, 505, 748, 78), Color(0.045, 0.10, 0.14, 0.93))
	var return_row: HBoxContainer = HBoxContainer.new()
	return_row.add_theme_constant_override("separation", 16)
	_return_summary.add_child(return_row)
	var return_title: VBoxContainer = VBoxContainer.new()
	return_title.custom_minimum_size.x = 160
	return_title.add_theme_constant_override("separation", 2)
	return_row.add_child(return_title)
	return_title.add_child(CampStyle.label("上次归航 · 已入账", 17, CampStyle.TEAL))
	_return_goods = CampStyle.label("", 14, CampStyle.MUTED)
	return_title.add_child(_return_goods)
	var return_details: VBoxContainer = VBoxContainer.new()
	return_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return_details.add_theme_constant_override("separation", 2)
	return_row.add_child(return_details)
	_return_text = CampStyle.label("", 16)
	return_details.add_child(_return_text)
	_return_advice = CampStyle.label("", 14, CampStyle.AMBER)
	return_details.add_child(_return_advice)


func _build_facilities() -> void:
	_facilities = _blue_hour_panel("FacilityChoices", Rect2(42, 370, 748, 103), Color(0.045, 0.10, 0.14, 0.96))
	_facilities.hide()
	var column: VBoxContainer = VBoxContainer.new()
	_facilities.add_child(column)
	_facility_heading = CampStyle.label("营地建设", 15, CampStyle.TEAL)
	column.add_child(_facility_heading)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for choice: String in FACILITY_NAMES:
		var button: Button = Button.new()
		button.name = "Facility" + choice.capitalize()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 55
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void:
			if not input_allowed.is_valid() or input_allowed.call():
				facility_requested.emit(choice))
		button.focus_entered.connect(_announce.bind(button, ""))
		row.add_child(button)
		facility_buttons[choice] = button


func _build_blue_hour_team() -> void:
	var panel: PanelContainer = _blue_hour_panel("TeamPanel", Rect2(794, 130, 444, 453), Color(0.045, 0.10, 0.14, 0.94))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(CampStyle.label("行动小队", 25))
	_team_count = CampStyle.label("", 15, CampStyle.MUTED)
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
	for id: int in [1, 2, 3, 4, 5]:
		var button: Button = _blue_hour_button(roster, StringName("member%d" % id), "")
		button.set_meta("member_id", id)
		button.custom_minimum_size.y = 77
		member_buttons[id] = button
		var padding: MarginContainer = MarginContainer.new()
		padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for edge: String in ["left", "right"]:
			padding.add_theme_constant_override("margin_" + edge, 11)
		button.add_child(padding)
		padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		padding.add_child(row)
		var portrait: TextureRect = TextureRect.new()
		portrait.name = "Portrait"
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(52, 56)
		row.add_child(portrait)
		var labels: VBoxContainer = VBoxContainer.new()
		labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		labels.alignment = BoxContainer.ALIGNMENT_CENTER
		labels.add_theme_constant_override("separation", 1)
		row.add_child(labels)
		var specialty: Label = CampStyle.label("", 20)
		specialty.name = "Trait"
		labels.add_child(specialty)
		var stats: HBoxContainer = HBoxContainer.new()
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_theme_constant_override("separation", 9)
		labels.add_child(stats)
		var call_sign: Label = CampStyle.label("", 15, CampStyle.MUTED)
		call_sign.name = "CallSign"
		call_sign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		call_sign.clip_text = true
		call_sign.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		stats.add_child(call_sign)
		var health: Label = CampStyle.label("", 15)
		health.name = "Health"
		stats.add_child(health)
		var weapon: Label = CampStyle.label("", 15, CampStyle.MUTED)
		weapon.name = "Weapon"
		stats.add_child(weapon)


func _build_blue_hour_footer() -> void:
	var panel: PanelContainer = _blue_hour_panel("CampActions", Rect2(42, 598, 1196, 88), Color(0.045, 0.10, 0.14, 0.96))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	column.add_child(row)
	var labels: Dictionary[StringName, String] = {&"home":"返回主菜单", &"crew":"队伍档案", &"weapons":"武器整备",
		&"supplies":"物资口粮", &"training":"篝火训练", &"sound":"声音", &"quit":"退出"}
	for action: StringName in labels:
		var button: Button = _blue_hour_button(row, action, labels[action])
		if action in [&"crew", &"weapons", &"supplies", &"training"]:
			hotspots[action] = button
		else:
			footer_buttons[action] = button
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var depart: Button = _blue_hour_button(row, &"bus", "选择行动 →")
	depart.custom_minimum_size = Vector2(216, 44)
	CampStyle.blue_hour_primary(depart)
	hotspots[&"bus"] = depart
	notice = CampStyle.label("", 13, CampStyle.MUTED)
	notice.clip_text = true
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(notice)


func _blue_hour_panel(node_name: String, rect: Rect2, colour: Color) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", CampStyle.box(colour, Color("48646d"), 10))
	add_child(panel)
	CampStyle.place(panel, rect)
	return panel


func _blue_hour_button(parent: Container, action: StringName, caption: String) -> Button:
	var button: Button = Button.new()
	button.name = String(action)
	button.text = caption
	button.add_theme_font_size_override("font_size", 17)
	button.custom_minimum_size.y = 42
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()


func refresh(data: Dictionary, daily: Dictionary, can_depart: bool, reason: String, feedback: String = "") -> void:
	_data = data.duplicate(true)
	_daily = daily.duplicate(true)
	world.refresh(data.crew)
	if player_mode:
		_refresh_blue_hour(data, daily, can_depart, reason, feedback)
		return
	resource_text.text = "第%d天   货币%d   食物%d   在营%d人" % [data.day, data.cash, data.food, world.visible_member_ids.size()]
	var pressure: String = _campaign_pressure(data)
	if not pressure.is_empty():
		resource_text.text += "   " + pressure
	eligibility_text.text = "%s · 今日需%d粮%s" % [reason, daily.required, " / 缺口%d" % int(daily.shortage) if daily.shortage > 0 else " / 库存足够"]
	if data.last_day.has("task"):
		var found: int = data.weapons.filter(func(item: Dictionary) -> bool:return item.get("acquired_sortie")==data.last_settlement_id).size()
		eligibility_text.text=TaskActions.summary_text(data.last_day.task)+" · 入库货币%d / 食物%d / 武器%d"%[data.last_day.cash_gained,data.last_day.food_stored,found]
	notice.text = feedback if not feedback.is_empty() else "Tab选设施 · Enter/Space确认 · Esc关闭当前页"
	hotspots[&"bus"].disabled = not can_depart
	if CampaignState.is_short(data):
		var display:Dictionary=CampaignRules.display(data.journey.campaign)
		eligibility_text.text=display.title+" · "+display.progress+"\n"+display.detail
	hotspots[&"bus"].tooltip_text = "选择出击目标" if can_depart else reason
	hotspots[&"crew"].set_meta("member_id", world.visible_member_ids[0] if not world.visible_member_ids.is_empty() else 0)
	for id: int in member_buttons:
		var button: Button = member_buttons[id]
		button.visible = id in world.visible_member_ids
		if not button.visible:
			continue
		if RescuePoolState.is_family(data):
			button.position = world.residents[id].position+Vector2(-50,-99)
			button.size = Vector2(100,173)
		var member: Dictionary = SurvivorRoster.member(data.crew, id)
		var caption: Label = button.get_node("Caption") as Label
		var short_name: String = member.call_sign if member.call_sign.length() <= 5 else member.call_sign.left(4) + "…"
		caption.text = "%02d %s\n生命%.0f%s" % [id, short_name, member.health, " · Lv%d" % int(member.growth.level) if GrowthState.is_family(data) else ""]
		if RescuePoolState.is_family(data):
			caption.text = "%02d %s\n生命%.0f\nLv%d" % [id,short_name.left(4),member.health,int(member.growth.level)]
			caption.add_theme_font_size_override("font_size",16)
			caption.offset_top = -70
		caption.add_theme_color_override("font_color", SurvivorRoster.definition_for(member).colour)
		button.tooltip_text = "%02d %s · %s\n点击查看档案" % [id, SurvivorRoster.definition_for(member).default_display_name, member.call_sign]
	var caption: Label = hotspots[&"training"].get_node("Caption") as Label
	caption.text = "篝火训练\n食物换个人Trait进度 →" if TrainingState.is_family(data) else "篝火休憩\n训练尚未开放"
	_link_focus()


func _refresh_blue_hour(data: Dictionary, daily: Dictionary, can_depart: bool, reason: String, feedback: String) -> void:
	resource_text.text = "第 %d 天     货币 %d     食物 %d     今日需粮 %d" % [data.day, data.cash, data.food, daily.required]
	var workshop_enabled: bool = WorkshopV1.enabled(data)
	if workshop_enabled:
		resource_text.text += "     工具箱 %d" % WorkshopV1.tools(data)
	var pressure: String = _campaign_pressure(data)
	_journey_caption.text = "旅程进度" if pressure.is_empty() else pressure
	_shortage_text.text = "口粮缺口 %d · 可考虑先补给" % daily.shortage if daily.shortage > 0 else "口粮缺口 0 · 库存充足"
	var build: Dictionary = data.get("journey", {}).get("build", {})
	if build.has("opening"):
		var equipped: PackedStringArray = []
		for item: String in build.slots:
			if not item.is_empty():
				equipped.append(BuildItems.definitions(BuildState.pool(data))[item].name)
		_shortage_text.text += "   ·   已配 " + ("、".join(equipped) if not equipped.is_empty() else "空槽")
	_shortage_text.add_theme_color_override("font_color", CampStyle.AMBER if daily.shortage > 0 else CampStyle.MUTED)
	var last: Dictionary = data.last_day
	_facilities.visible = CampFacilities.enabled(data)
	if _facilities.visible:
		var selected: String = CampFacilities.selected(data)
		_facility_heading.text = "营地建设 · 每个旅程只选一项" if last.get("evacuated", false) or not selected.is_empty() else "营地建设 · 首次确认归航后开放"
		for choice: String in FACILITY_NAMES:
			var button: Button = facility_buttons[choice]
			var condition: String = ("成功归航供 %d 粮，受库存上限" % CampFacilities.SUPPLY_FOOD if choice == "supply"
				else "维修少付 %d 币，最低 1 币" % CampFacilities.REPAIR_DISCOUNT)
			if choice == CampFacilities.WORKSHOP and workshop_enabled:
				condition = "维修少付 %d 币 · 回收工具箱 / 改装卡宾枪" % CampFacilities.REPAIR_DISCOUNT
			var state: String = "已建成" if choice == selected else "本旅程额度已用" if not selected.is_empty() else "%d 币" % CampFacilities.BUILD_COST
			button.text = "%s · %s\n%s" % [FACILITY_NAMES[choice], state, condition]
			button.disabled = not CampFacilities.can_build(data, choice)
			button.tooltip_text = condition
			if choice == CampFacilities.WORKSHOP and workshop_enabled:
				button.tooltip_text += " · 维修最低 1 币"
			if selected.is_empty() and button.disabled:
				button.tooltip_text = "先完成并确认一次成功归航" if not last.get("evacuated", false) else "货币不足"
	_return_summary.visible = not last.is_empty()
	if not last.is_empty():
		var facility_meal: bool = int(last.get("facility_food", 0)) > 0
		CampStyle.place(_return_summary, Rect2(42, 480, 748, 103) if facility_meal else Rect2(42, 505, 748, 78))
		var returned_weapons: Array = data.weapons.filter(func(item: Dictionary) -> bool:
			return item.get("acquired_sortie") == data.last_settlement_id)
		_return_goods.text = "入库 %d 币 · %d 件武器" % [last.cash_gained, returned_weapons.size()]
		_return_text.text = ReturnFeedback.food_text(last)
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
	notice.text = feedback if not feedback.is_empty() else "Tab 切换   ·   Enter 确认   ·   Esc 返回"
	notice.tooltip_text = notice.text
	hotspots[&"bus"].disabled = not can_depart
	hotspots[&"bus"].tooltip_text = "选择出击目标" if can_depart else reason
	var active: Array[int] = world.visible_member_ids
	_team_count.text = "%d 人在营 · 选择队员查看详情" % active.size()
	hotspots[&"crew"].set_meta("member_id", active[0] if not active.is_empty() else 0)
	hotspots[&"training"].text = "篝火训练" if TrainingState.is_family(data) else "篝火休憩"
	for id: int in member_buttons:
		var button: Button = member_buttons[id]
		button.visible = id in active
		if button.visible:
			_refresh_blue_hour_member(button, data, id)
	_link_focus()


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
	health.text = "生命 %.0f/%.0f" % [member.health, GrowthRules.maximum(member)]
	var weapon: Label = button.find_child("Weapon", true, false) as Label
	var equipped: Dictionary = WeaponInventory.for_member(data, id)
	weapon.text = WeaponInventory.definition(equipped.weapon_id).display_name if not equipped.is_empty() else "未装备"
	button.tooltip_text = "%s · %s\n%s · %s\n查看队员档案" % [specialty.text, call_sign.text, health.text, weapon.text]


func clear() -> void:
	if world == null:
		return
	world.refresh([])
	for button: Button in member_buttons.values():
		button.hide()
	if is_instance_valid(_return_summary):
		_return_summary.hide()
	if is_instance_valid(_facilities):
		_facilities.hide()
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


func _hotspot(action: StringName, rect: Rect2, text: String) -> Button:
	var button: Button = Button.new()
	button.name = String(action)
	button.mouse_force_pass_scroll_events = false
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", CampStyle.box(Color(0.1, 0.24, 0.25, 0.18), CampStyle.TEAL, 0))
	button.add_theme_stylebox_override("pressed", CampStyle.box(Color(0.3, 0.27, 0.15, 0.22), CampStyle.AMBER, 0))
	button.add_theme_stylebox_override("focus", CampStyle.box(Color(0, 0, 0, 0), CampStyle.AMBER, 0))
	CampStyle.place(button, rect)
	add_child(button)
	button.pressed.connect(func() -> void: _request(action, int(button.get_meta("member_id", 0))))
	button.mouse_entered.connect(_announce.bind(button, text))
	button.focus_entered.connect(_announce.bind(button, text))
	var label: Label = CampStyle.label(text, 18)
	label.name = "Caption"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -52
	label.offset_bottom = -4
	label.add_theme_color_override("font_outline_color", Color("142a31"))
	label.add_theme_constant_override("outline_size", 6)
	button.add_child(label)
	return button


func _request(action: StringName, member_id: int) -> void:
	if info_visible():
		return
	if String(action).begins_with("member"):
		action_requested.emit(&"crew", member_id)
	else:
		action_requested.emit(action, member_id)


func _announce(button: Button, text: String) -> void:
	_last_focus = String(button.name)
	if notice != null and not player_mode:
		notice.text = text.replace("\n", " · ") if not text.is_empty() else button.tooltip_text.replace("\n", " · ")
		notice.tooltip_text = notice.text


func _link_focus() -> void:
	var sequence: Array[Button] = []
	for action: StringName in [&"bus", &"crew", &"weapons", &"supplies", &"training"]:
		if not hotspots[action].disabled:
			sequence.append(hotspots[action])
	for id: int in [1, 2, 3, 4, 5]:
		if member_buttons[id].visible:
			sequence.append(member_buttons[id])
	for button: Button in facility_buttons.values():
		if button.is_visible_in_tree() and not button.disabled:
			sequence.append(button)
	for button: Button in footer_buttons.values():
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
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL, 28))
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
	info_close.pressed.connect(close_info)
	column.add_child(info_close)
	info_close.focus_next = info_close.get_path()
	info_close.focus_previous = info_close.get_path()
	_info.hide()


func _shown() -> void:
	if is_visible_in_tree():
		restore_focus.call_deferred()


func _resize_world() -> void:
	world.scale = size / CampSceneLayout.SIZE
