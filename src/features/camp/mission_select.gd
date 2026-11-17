class_name MissionSelect
extends Control
## Read-only choice of the original frozen missions.

signal selected(supply: MissionSupply)
signal cancelled
signal retry_requested
signal navigation_requested(action: StringName)

const Supplies: Array[MissionSupply] = [preload("res://src/features/camp/scavenge.tres"), preload("res://src/features/camp/supermarket.tres")]
const DESTINATIONS: String = "res://assets/menu_pixel/destinations.png"
var choices: Array[Button] = []
var daily_offers: Array[Dictionary] = []
var _active: Array[MissionSupply] = []
var _titles: Array[Label] = []
var _descriptions: Array[Label] = []
var _pictures: Array[TextureRect] = []
var _role_marks: Array[MissionCardMark] = []
var _card_panels: Array[PanelContainer] = []
var _description_scrolls: Array[ScrollContainer] = []
var _campaign_pressures: Array[Label] = []
var _heading: Label
var _subtitle: Label
var rescue_completed: bool = false
var cancel_button: Button
var depart_button: Button
var loading: bool = false
var review_enabled: bool = false
var _retry_button: Button
var _review_details: VBoxContainer
var _review_target: Label
var _selected_index: int = -1
var _review_nav: Array[Button] = []
var _resources: Label
var _review_summary: Label
var info_buttons: Array[Button] = []
var _summaries: Array[Label] = []
var _brief: MissionActionBrief
var _brief_index: int = -1
var _destination_atlas: Texture2D
var _preparation_button: Button
var _preparation_details: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = CampStyle.theme(theme)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background: ColorRect = ColorRect.new()
	background.color = CampStyle.INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	if ResourceLoader.exists(DESTINATIONS):
		_destination_atlas = load(DESTINATIONS) as Texture2D
	var page: VBoxContainer = VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 0)
	add_child(page)
	_resources = CampStyle.label("", 20)
	_heading = PixelMenu.masthead(page, "准备出击" if review_enabled else "选择行动", _resources)
	var margins: MarginContainer = MarginContainer.new()
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 20)
	for side: String in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 14)
	page.add_child(margins)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margins.add_child(column)
	_subtitle = CampStyle.label("比较目标、路线与风险；成功撤离后确认入账。", 18, CampStyle.MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subtitle)
	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	column.add_child(content)
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	if review_enabled:
		PixelMenu.divider(content, true).size_flags_vertical = Control.SIZE_EXPAND_FILL
		_build_departure_review(content)
	var available: Array[MissionSupply] = Supplies.duplicate()
	available.append(preload("res://src/features/camp/rescue.tres"))
	_active.assign(available)
	for index: int in range(available.size()):
		_build_action_card(row, index, available[index])
	PixelMenu.divider(column)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	if review_enabled:
		for action: StringName in [&"crew", &"weapons", &"workshop", &"supplies"]:
			var nav: Button = Button.new()
			nav.text = {&"crew":"队员", &"weapons":"装备仓", &"workshop":"工坊", &"supplies":"补给"}[action]
			nav.custom_minimum_size = Vector2(84, 52)
			nav.add_theme_font_size_override("font_size", 21)
			PixelMenu.tab(nav, false)
			nav.pressed.connect(navigation_requested.emit.bind(action))
			footer.add_child(nav)
			_review_nav.append(nav)
		_retry_button = Button.new()
		_retry_button.text = "重试生成"
		_retry_button.pressed.connect(retry_requested.emit)
		footer.add_child(_retry_button)
		_retry_button.hide()
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	cancel_button = Button.new()
	cancel_button.text = "返回营地 / Esc"
	cancel_button.custom_minimum_size = Vector2(200, 60)
	cancel_button.add_theme_font_size_override("font_size", 21)
	cancel_button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 10))
	cancel_button.pressed.connect(func() -> void: cancelled.emit())
	footer.add_child(cancel_button)
	if review_enabled:
		depart_button.custom_minimum_size = Vector2(340, 64)
		depart_button.add_theme_font_size_override("font_size", 30)
		footer.add_child(depart_button)
	_build_brief()
	visibility_changed.connect(func() -> void:
		if not visible and is_instance_valid(_brief):
			_brief.hide())
	_link_choices()


func _build_action_card(parent: VBoxContainer, index: int, supply: MissionSupply) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _card_style(false))
	parent.add_child(panel)
	_card_panels.append(panel)
	var horizontal: HBoxContainer = HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", 14)
	panel.add_child(horizontal)
	var picture: TextureRect = _texture(_destination_picture("supply" if index == 0 else "rescue" if index == 2 else "equipment"))
	picture.custom_minimum_size.x = 250 if review_enabled else 310
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal.add_child(picture)
	_pictures.append(picture)
	PixelMenu.divider(horizontal, true).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card: VBoxContainer = VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 4)
	horizontal.add_child(card)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	card.add_child(top)
	var mark: MissionCardMark = MissionCardMark.new()
	mark.custom_minimum_size = Vector2(24, 24)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(mark)
	_role_marks.append(mark)
	var title: Label = CampStyle.label(RescueTarget.ACTION_TITLE if supply.id == &"rescue" else supply.layout.display_name, 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title)
	_titles.append(title)
	var summary: Label = CampStyle.label("", 17)
	summary.autowrap_mode = TextServer.AUTOWRAP_OFF
	summary.clip_text = true
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(summary)
	_summaries.append(summary)
	var info: Button = Button.new()
	info.text = "行动详情"
	info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_theme_font_size_override("font_size", 15)
	CampStyle.text_button(info)
	info.add_theme_stylebox_override("normal", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 2))
	info.pressed.connect(_show_brief.bind(index))
	info_buttons.append(info)
	var pressure: Label = CampStyle.label("", 16, CampStyle.DANGER)
	pressure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_campaign_pressures.append(pressure)
	var description: Label = CampStyle.label(_rescue_card_text(supply) if supply.id == &"rescue" else supply.description, 21)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_descriptions.append(description)
	var actions: VBoxContainer = VBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 8)
	horizontal.add_child(actions)
	var button: Button = Button.new()
	button.text = "选择此行动"
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size = Vector2(132, 46)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 8))
	button.pressed.connect(_choose.bind(index))
	actions.add_child(button)
	info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	actions.add_child(info)
	choices.append(button)
	button.focus_entered.connect(_refresh_card_states)
	button.focus_exited.connect(_refresh_card_states)


func refresh_rescue(completed: bool, reason: String = "") -> void:
	rescue_completed = completed
	if choices.size() > 2:
		choices[2].disabled = completed
		choices[2].text = "救援已结束" if completed else "前往救援 →"
		if completed and not reason.is_empty():
			choices[2].text = reason
	_link_choices()


func refresh_daily(base: Dictionary, rations: Dictionary = {}, prepared: Dictionary = {}) -> void:
	if prepared.is_empty():
		daily_offers = DailyActions.offers(base)
	else:
		daily_offers.assign(prepared.offers)
	loading = false
	_brief.hide()
	_selected_index = -1
	if review_enabled:
		_retry_button.hide()
		depart_button.disabled = true
		for nav: Button in _review_nav:
			nav.disabled = false
		_review_target.text = "选择左侧一张行动卡"
		_refresh_departure_team(base, rations)
	var action_choices: bool = CampaignRules.action_choices_enabled(base.get("journey", {}).get("campaign"))
	var has_mission_cards: bool = daily_offers.any(func(offer: Dictionary) -> bool: return offer.get("mission_policy") == 1)
	_subtitle.text = "比较主收益、路线与风险。物资和线索随生还归航确认。" if has_mission_cards else "选择此行的补给方向，准备好后出发。"
	if RosterState.is_family(base) and RescuePoolState.available(base).is_empty():
		_subtitle.text += "\n" + RosterState.unavailable_reason(base)
	_heading.text = ("准备出击" if review_enabled else "选择行动") + " · 第%d天" % int(base.day)
	if CampaignState.is_short(base):
		var display: Dictionary = CampaignRules.display(base.journey.campaign)
		_subtitle.text = String(display.progress) + "  ·  " + _subtitle.text
	for index: int in range(choices.size()):
		var panel: PanelContainer = _card_panels[index]
		panel.visible = index < daily_offers.size()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size.x = 0
		if index>=daily_offers.size(): continue
		var supply: MissionSupply = DailyActions.supply(daily_offers[index]) if prepared.is_empty() else prepared.supplies[index]
		_active[index] = supply
		var pressure: Label = _campaign_pressures[index]
		pressure.visible = CampaignPressureV1.enabled(supply.generated)
		if pressure.visible:
			pressure.text = CampaignPressureV1.label(int(supply.generated.campaign_pressure.tier))
		var rescue: bool = supply.id == &"rescue"
		_titles[index].text = RescueTarget.ACTION_TITLE if rescue else supply.display_name
		_descriptions[index].text = _rescue_card_text(supply) if rescue else supply.description
		if _descriptions[index].has_theme_constant_override("line_spacing"):
			_descriptions[index].remove_theme_constant_override("line_spacing")
		var mission_card: bool = supply.generated.get("mission_policy") == 1
		var pump_card: bool = PumpStationAction.enabled(supply.generated)
		var rare_card: bool = supply.generated.has("rare_policy")
		var event_site: String = EventSortieV1.site_id(supply.generated)
		if EconomyActions.hardware(supply.generated):
			_titles[index].text = EconomyActions.HARDWARE_TITLE
			_descriptions[index].text = EconomyActions.card_text(supply.generated)
		elif not event_site.is_empty():
			_titles[index].text = EventSortieV1.TITLE
			_descriptions[index].text = _event_card_text(supply.generated)
		elif rare_card:
			_titles[index].text = "稀有行动 · " + supply.display_name
		elif pump_card:
			pass
		elif mission_card:
			var title: String = {"supply":"补给", "airdrop":"装备", "equipment":"调查", "rescue":RescueTarget.ACTION_TITLE}[supply.generated.type]
			if supply.generated.has("billboard_target"):
				title = "超市补给"
			if SortieRiskV1.enabled(supply.generated):
				title = "装备 · 深入回收" if supply.generated.sortie_risk.tier == SortieRiskV1.DEEP else "装备 · 常规回收"
			_titles[index].text = title
			_descriptions[index].text = _rescue_card_text(supply) if rescue else LevelSummary.mission_card_text(supply.generated, base if action_choices else {}, rations)
			if ReconActionV1.enabled(supply.generated):
				var lines: PackedStringArray = _descriptions[index].text.split("\n")
				lines.insert(1, "可侦察 · 标记装备点及 1 处可搜建筑")
				_descriptions[index].text = "\n".join(lines)
			elif BarricadeV1.enabled(supply.generated):
				var lines: PackedStringArray = _descriptions[index].text.split("\n")
				lines.insert(1, "有车辆路障 · 可绕行或用空袭开路")
				_descriptions[index].text = "\n".join(lines)
			if supply.generated.has("billboard_target"):
				var lines: PackedStringArray = _descriptions[index].text.split("\n")
				lines.insert(1, "广告牌情报 · 本次选卡有效")
				_descriptions[index].text = "\n".join(lines)
			_descriptions[index].add_theme_constant_override("line_spacing", 2 if action_choices else 8)
		elif supply.generated.get("worldgen",{}).get("version")==2:
			# The original resource description participates in existing in-flight world compatibility hashes.
			if not rescue:
				var frozen_description: String = LevelSummary.description(supply.generated)
				_descriptions[index].text = supply.description.trim_suffix(frozen_description) + LevelSummary.description(supply.generated, true)
		var investigation: Dictionary = supply.generated.get("investigation", {})
		if not mission_card and not investigation.is_empty():
			var clue_name: String = CampaignRules.CLUE_NAMES[investigation.clue_id]
			_titles[index].text = "%02d / 调查 · %s" % [index+1, clue_name]
			_descriptions[index].text = "搜索标记建筑：%s\n" % clue_name + _descriptions[index].text
		choices[index].disabled = false
		choices[index].text = "选择此行动"
		choices[index].tooltip_text = "只有真实搜集并成功撤离，确认结算才入账。"
		_refresh_blue_hour_card(index, supply.generated)
		if HarborWarehouse.is_layout(supply.layout):
			_titles[index].text = HarborWarehouse.TITLE
			_descriptions[index].text = supply.description

		elif CapeStation.is_layout(supply.layout):
			_titles[index].text = CapeStation.TITLE
			_descriptions[index].text = supply.description

		if CampaignPressureV1.blockade_night(supply.generated):
			_descriptions[index].text = CampaignPressureV1.BLOCKADE_WARNING + "\n" + _descriptions[index].text
		_present_card(index, supply.generated)
	_refresh_card_states()
	_link_choices()


func show_waiting(base: Dictionary, rations: Dictionary, failed: bool = false) -> void:
	loading = not failed
	_brief.hide()
	daily_offers.clear()
	_selected_index = -1
	_heading.text = "准备出击 · 第 %d 天" % int(base.day)
	_subtitle.text = "正在核验今日路线与任务。可以返回营地。" if loading else "未取得可出击的行动。可以重试或返回营地。"
	for index: int in range(choices.size()):
		choices[index].disabled = true
		_card_panels[index].hide()
	depart_button.disabled = true
	for nav: Button in _review_nav:
		nav.disabled = loading
	_retry_button.visible = failed
	_review_target.text = "正在核验今日行动…" if loading else "行动生成失败 · 请重试"
	_refresh_departure_team(base, rations)
	_link_choices()
	cancel_button.grab_focus()


func _choose(index: int) -> void:
	if not review_enabled:
		selected.emit(_active[index])
		return
	if loading or _brief.visible or index >= daily_offers.size() or choices[index].disabled:
		return
	_selected_index = index
	_review_target.text = _titles[index].text
	for row: int in range(choices.size()):
		choices[row].text = "当前选择" if row == index else "选择此行动"
	_refresh_card_states()
	depart_button.disabled = false
	_link_choices()
	depart_button.grab_focus()


func _confirm_departure() -> void:
	if not loading and not _brief.visible and _selected_index >= 0 and _selected_index < daily_offers.size():
		selected.emit(_active[_selected_index])


func _build_departure_review(parent: Container) -> void:
	var body: VBoxContainer = VBoxContainer.new()
	body.custom_minimum_size.x = 340
	body.add_theme_constant_override("separation", 10)
	parent.add_child(body)
	body.add_child(CampStyle.label("出发复核", 28))
	PixelMenu.divider(body)
	_review_target = CampStyle.label("请选择一项行动", 23)
	_review_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_target.custom_minimum_size.y = 38
	body.add_child(_review_target)
	_review_summary = CampStyle.label("", 18, CampStyle.MUTED)
	_review_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_review_summary)
	PixelMenu.divider(body)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	body.add_child(scroll)
	_review_details = VBoxContainer.new()
	_review_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review_details.add_theme_constant_override("separation", 2)
	scroll.add_child(_review_details)
	_preparation_button = Button.new()
	_preparation_button.text = "整备详情 · 专精 / 设施 / 支援"
	_preparation_button.custom_minimum_size.y = 36
	_preparation_button.add_theme_font_size_override("font_size", 16)
	_preparation_button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 4))
	_preparation_button.pressed.connect(func() -> void:
		_brief_index = -1
		_brief.show_preparation())
	body.add_child(_preparation_button)
	depart_button = Button.new()
	depart_button.text = "确认出击 →"
	depart_button.disabled = true
	PixelMenu.primary(depart_button)
	depart_button.pressed.connect(_confirm_departure)


func _refresh_departure_team(base: Dictionary, rations: Dictionary) -> void:
	for child: Node in _review_details.get_children():
		_review_details.remove_child(child)
		child.queue_free()
	for child: Node in _preparation_details.get_children():
		_preparation_details.remove_child(child)
		child.queue_free()
	var living: int = 0
	var armed: int = 0
	for member: Dictionary in base.crew:
		if float(member.health) > 0.0:
			living += 1
			if not WeaponInventory.for_member(base, int(member.id)).is_empty():
				armed += 1
	_resources.text = "食物 %d   货币 %d   工具箱 %d" % [int(base.food), int(base.cash), WorkshopV1.tools(base)]
	_review_summary.text = "同行 %d 人 · 已配装 %d 人\n今日需粮 %d · 库存 %d" % [living, armed, int(rations.get("required", 0)), int(base.food)]
	for member: Dictionary in base.crew:
		if float(member.health) <= 0.0:
			continue
		var item: Dictionary = WeaponInventory.for_member(base, int(member.id))
		var weapon: String = "未配装"
		if not item.is_empty():
			weapon = "%s %s" % [WeaponInventory.definition(item.weapon_id).display_name, WeaponInventory.short_id(item)]
			var mod: String = WorkshopV1.mod_for(base, item.instance_id)
			if not mod.is_empty():
				weapon += " · " + WorkshopV1.name_for(mod)
		var crew_label: Label = PersonaCard.HoverLabel.new()
		crew_label.text = SurvivorRoster.display_label(member)
		crew_label.add_theme_font_size_override("font_size", 20)
		crew_label.add_theme_font_override("font", CampStyle.BOLD_FONT)
		crew_label.clip_text = true
		crew_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var identity_style: StyleBoxFlat = CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0)
		identity_style.content_margin_left = 58
		identity_style.content_margin_right = 94
		crew_label.add_theme_stylebox_override("normal", identity_style)
		crew_label.custom_minimum_size.y = 30
		var portrait: TextureRect = _texture(null)
		var definition: SurvivorDefinition = SurvivorRoster.definition_for(member)
		portrait.texture = definition.portrait if definition != null else null
		portrait.position = Vector2.ZERO
		portrait.size = Vector2(48, 48)
		var hp: Label = CampStyle.label("%d / %.0f" % [ceili(member.health), GrowthRules.maximum(member)], 17)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		crew_label.add_child(hp)
		hp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		hp.position = Vector2(-92, 2)
		hp.size = Vector2(92, 26)
		crew_label.add_theme_color_override("font_color", CampStyle.TEXT)
		crew_label.tooltip_text = PersonaCard.camp_hover(base, int(member.id))
		crew_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_review_details.add_child(crew_label)
		# The portrait spans both text rows; keep it outside the name's text clipping.
		var portrait_layer: Node2D = Node2D.new()
		_review_details.add_child(portrait_layer)
		portrait_layer.add_child(portrait)
		portrait_layer.position = crew_label.position
		crew_label.item_rect_changed.connect(func() -> void:
			portrait_layer.position = crew_label.position)
		if not item.is_empty():
			weapon += " · 等级 %d" % int(item.get("weapon_level", 1))
		var weapon_label: Label = PersonaCard.HoverLabel.new()
		weapon_label.text = weapon
		weapon_label.clip_text = true
		weapon_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		weapon_label.add_theme_font_size_override("font_size", 13)
		weapon_label.add_theme_color_override("font_color", CampStyle.MUTED)
		var weapon_style: StyleBoxFlat = CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0)
		weapon_style.content_margin_left = 58
		weapon_label.add_theme_stylebox_override("normal", weapon_style)
		weapon_label.custom_minimum_size.y = 29
		weapon_label.tooltip_text = crew_label.tooltip_text
		weapon_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_review_details.add_child(weapon_label)
		var health: ProgressBar = ProgressBar.new()
		health.mouse_filter = Control.MOUSE_FILTER_IGNORE
		health.show_percentage = false
		health.max_value = GrowthRules.maximum(member)
		health.value = float(member.health)
		weapon_label.add_child(health)
		health.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		health.offset_left = 58
		health.offset_top = 23
		health.offset_bottom = 29
		PixelMenu.divider(_review_details)
	if OpeningBuild.is_m47(base):
		_preparation_details.add_child(CampStyle.label("本局专精 · " + OpeningBuild.PLANS[OpeningBuild.plan(base)].title, 24, CampStyle.TEAL))
		var eligible: Label = CampStyle.label(SpecialtyPresentation.access_text(OpeningBuild.eligible(base)), 20, CampStyle.MUTED)
		eligible.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preparation_details.add_child(eligible)
	if EconomyActions.camp_enabled(base):
		var levels: PackedStringArray = []
		for facility: String in ["supply", "workshop", "planning"]:
			levels.append("%s Lv%d" % [{"supply":"补给", "workshop":"工坊", "planning":"规划"}[facility], EconomyBuildV1.level(base, facility)])
		var rooms: Label = CampStyle.label("设施 · " + " / ".join(levels), 20, CampStyle.MUTED)
		rooms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for facility: String in EconomyBuildV1.FACILITIES:
			rooms.tooltip_text += EconomyBuildV1.facility_name(facility) + "：" + EconomyBuildV1.facility_effect(facility, EconomyBuildV1.level(base, facility)) + "\n"
		_preparation_details.add_child(rooms)
		_preparation_details.add_child(CampStyle.label("工具 %d" % EconomyBuildV1.tools(base), 20, CampStyle.TEAL))
	var build: Dictionary = base.get("journey", {}).get("build", {})
	var powers: Dictionary = build.get("powers", {})
	var equipped: PackedStringArray = []
	if OpeningBuild.is_m47(base):
		var passives: Array = build.get("slots", []).filter(func(id: String) -> bool: return not id.is_empty())
		var kit: Label = CampStyle.label("被动 · " + (SpecialtyPresentation.names(passives) if not passives.is_empty() else "空槽"), 20, CampStyle.TEAL)
		kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preparation_details.add_child(kit)
	for id: String in powers.get("slots", [powers.get("slot", "")]):
		if not id.is_empty():
			equipped.append(SpecialPowers.definition(id).get("name", id))
	var support: Label = CampStyle.label("支援 · %s" % ("、".join(equipped) if not equipped.is_empty() else "能力槽空置"), 20, CampStyle.TEAL)
	support.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preparation_details.add_child(support)
	_preparation_details.add_child(CampStyle.label("口粮 %d · 下餐需 %d" % [base.food, rations.get("required", 0)], 20, CampStyle.MUTED))


func _destination_picture(role: String) -> Texture2D:
	if _destination_atlas == null:
		return null
	var index: int = 0 if role == "supply" else 2 if role == "rescue" else 1
	var height: float = float(_destination_atlas.get_height()) / 3.0
	var texture: AtlasTexture = AtlasTexture.new()
	texture.atlas = _destination_atlas
	texture.region = Rect2(0, index * height, _destination_atlas.get_width(), height)
	texture.filter_clip = true
	return texture


func _present_card(index: int, generated: Dictionary) -> void:
	_pictures[index].texture = _destination_picture(String(generated.get("type", "equipment")))
	_pictures[index].tooltip_text = "地点插画；实际目标、路线与风险见行动详情。"
	var full_text: String = _descriptions[index].text
	var lines: PackedStringArray = full_text.split("\n", false)
	var overview: PackedStringArray = []
	for prefix: String in ["主收益 · ", "路线 · ", "风险 · "]:
		for line: String in lines:
			if line.begins_with(prefix):
				var value: String = line.trim_prefix(prefix).get_slice(" · ", 0)
				overview.append(prefix.replace(" · ", "：") + value)
				break
	if overview.size() < 3:
		overview.clear()
		for index_line: int in range(mini(3, lines.size())):
			overview.append(lines[index_line])
	_summaries[index].text = "\n".join(overview)
	_summaries[index].tooltip_text = full_text
	_titles[index].tooltip_text = _titles[index].text
	info_buttons[index].tooltip_text = "查看完整收益、路线、风险与附带目标"
	_descriptions[index].add_theme_font_size_override("font_size", 21)
	_descriptions[index].add_theme_constant_override("line_spacing", 10)
	_description_scrolls[index].scroll_vertical = 0


func _build_brief() -> void:
	_brief = MissionActionBrief.new()
	add_child(_brief)
	_brief.configure(_descriptions, _campaign_pressures)
	_preparation_details = _brief.preparation_details
	_description_scrolls.assign(_brief.description_scrolls)
	_brief.closed.connect(func() -> void:
		if _brief_index >= 0 and _brief_index < info_buttons.size():
			info_buttons[_brief_index].grab_focus()
		elif is_instance_valid(_preparation_button):
			_preparation_button.grab_focus())
	_brief.chosen.connect(_choose)


func _show_brief(index: int) -> void:
	if loading or index < 0 or index >= choices.size() or choices[index].disabled:
		return
	_brief_index = index
	_brief.show_action(index, _titles[index].text, _pictures[index].texture)


func _close_brief() -> void:
	_brief.dismiss()


static func _event_card_text(generated: Dictionary) -> String:
	var quiet: String = EventSortieV1.QUIET
	var force: String = EventSortieV1.FORCE
	return "备选行动 · 到站后现场二选一\n两路基础工时均为 %d 秒\n%s · %s\n%s · %s" % [
		int(generated.event_sortie.seconds), EventSortiePanel.branch_title(quiet), EventSortiePanel.offer_detail(generated, quiet),
		EventSortiePanel.branch_title(force), EventSortiePanel.offer_detail(generated, force)]


func _rescue_card_text(supply: MissionSupply) -> String:
	var size: String = {"small":"小型", "medium":"中型", "large":"大型"}.get(supply.generated.get("layout", {}).get("size"), "")
	var area: String = (size + "街区 · " if not size.is_empty() else "") + supply.layout.display_name
	var goal: String = "援救 10 秒后现场接纳，生还归航后登记入营。"
	var route: String = LevelSummary.description(supply.generated, true)
	var text: String = "%s ×1\n%s\n%s" % [SurvivorRoster.definition(int(supply.generated.get("recruit", 3))).default_display_name, area, goal]
	if not route.is_empty():
		text += "\n" + route
	return text


func _refresh_blue_hour_card(index: int, generated: Dictionary) -> void:
	var type: String = generated.get("type", "")
	var role: String = "equipment" if type == "airdrop" else type
	if generated.has("investigation"):
		role = "investigation"
	if generated.get("campaign", {}).get("is_finale", false):
		role = "finale"
	_role_marks[index].role = role
	_role_marks[index].queue_redraw()
	if type == "supply" and not generated.has("rare_policy") and _has_extra_weapon(generated):
		var lines: PackedStringArray = _descriptions[index].text.split("\n")
		lines.insert(1, "附带装备 · 需另搜")
		_descriptions[index].text = "\n".join(lines)
	var specialty: String = BuildActions.specialization_candidate(generated)
	if not specialty.is_empty():
		var lines: PackedStringArray = _descriptions[index].text.split("\n")
		lines.insert(1, "专精装备 · %s · 回收后归航确认" % SpecialtyPresentation.reward_name(specialty))
		_descriptions[index].text = "\n".join(lines)
	choices[index].text = "选择终局行动" if role == "finale" else "选择此行动"


static func _has_extra_weapon(generated: Dictionary) -> bool:
	var main_sites: Array = generated.get("objective", {}).get("site_ids", [])
	for site: Dictionary in generated.get("sites", []):
		if site.get("weapon", false) and site.id not in main_sites:
			return true
	return false


static func _texture(source: Texture2D) -> TextureRect:
	var texture_rect: TextureRect = TextureRect.new()
	texture_rect.texture = source
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return texture_rect


static func _card_style(focused: bool) -> StyleBoxFlat:
	return CampStyle.box(Color("15384e") if focused else Color("0c293e"),
		CampStyle.TEAL if focused else CampStyle.EDGE, 8)


func _refresh_card_states() -> void:
	for index: int in range(choices.size()):
		var selected_card: bool = review_enabled and index == _selected_index
		var button: Button = choices[index]
		_card_panels[index].add_theme_stylebox_override("panel", _card_style(selected_card or button.has_focus()))
		if selected_card:
			button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.TEAL, Color.TRANSPARENT, 10))
			button.add_theme_stylebox_override("hover", CampStyle.box(CampStyle.TEAL.lightened(0.08), Color.TRANSPARENT, 10))
			button.add_theme_color_override("font_color", CampStyle.INK)
			button.add_theme_color_override("font_hover_color", CampStyle.INK)
		else:
			button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.INK, CampStyle.EDGE, 8))
			button.add_theme_stylebox_override("hover", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL, 8))
			for color: String in ["font_color", "font_hover_color"]:
				button.add_theme_color_override(color, CampStyle.TEXT)


func _link_choices() -> void:
	var stops: Array[Button] = []
	for index: int in range(choices.size()):
		if _card_panels[index].visible and not choices[index].disabled:
			stops.append(choices[index])
			stops.append(info_buttons[index])
	if review_enabled and not depart_button.disabled:
		stops.append(depart_button)
	stops.append(cancel_button)
	if review_enabled:
		stops.append(_preparation_button)
		for nav: Button in _review_nav:
			if not nav.disabled:
				stops.append(nav)
		if _retry_button.visible:
			stops.append(_retry_button)
	for index: int in range(stops.size()):
		var button: Button = stops[index]
		var previous: NodePath = stops[posmod(index - 1, stops.size())].get_path()
		var next: NodePath = stops[(index + 1) % stops.size()].get_path()
		button.focus_previous = previous
		button.focus_next = next
		button.focus_neighbor_left = previous
		button.focus_neighbor_right = next
		button.focus_neighbor_bottom = cancel_button.get_path()
		button.focus_neighbor_top = stops[0].get_path()
