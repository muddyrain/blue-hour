class_name MissionSelect
extends Control
## Read-only choice of the original frozen missions.

signal selected(supply: MissionSupply)
signal cancelled

const Supplies: Array[MissionSupply] = [preload("res://src/features/camp/scavenge.tres"), preload("res://src/features/camp/supermarket.tres")]
const SHOP: Texture2D = preload("res://assets/candidates/shop_02.png")
const MARKET: Texture2D = preload("res://assets/m401/market.png")
const YARD: Texture2D = preload("res://assets/ui/m20/camp-blue-hour.png")
const BUS: Texture2D = preload("res://assets/candidates/bus_02.png")
var choices: Array[Button] = []
var daily_offers: Array[Dictionary] = []
var _active: Array[MissionSupply] = []
var _titles: Array[Label] = []
var _descriptions: Array[Label] = []
var _crates: Array[Node2D] = []
var _pictures: Array[TextureRect] = []
var _secondary_pictures: Array[TextureRect] = []
var _buses: Array[TextureRect] = []
var _role_marks: Array[CardMark] = []
var _map_marks: Array[CardMark] = []
var _card_panels: Array[PanelContainer] = []
var _description_scrolls: Array[ScrollContainer] = []
var _campaign_pressures: Array[Label] = []
var _heading: Label
var _subtitle: Label
var rescue_enabled: bool = false
var player_mode: bool = false
var field_join_mode: bool = false
var rescue_completed: bool = false
var cancel_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if player_mode:
		add_child(CampStyle.blue_hour_background(YARD))
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.023, 0.061, 0.09, 0.66) if player_mode else CampStyle.INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right"]:
		margins.add_theme_constant_override("margin_" + side, 48 if player_mode else 80)
	for side: String in ["top","bottom"]:
		var inset: int = 42 if player_mode else 104
		margins.add_theme_constant_override("margin_" + side, inset if side == "top" else (34 if player_mode else 32))
	add_child(margins)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12 if player_mode else 16)
	margins.add_child(column)
	_heading = CampStyle.label("选择行动" if player_mode else "行动地图 / 旧街", 34 if player_mode else 32)
	column.add_child(_heading)
	_subtitle = CampStyle.label("选择此行的补给方向，准备好后出发。", 18, CampStyle.MUTED)
	column.add_child(_subtitle)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if player_mode:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16 if player_mode else 24)
	column.add_child(row)
	var available: Array[MissionSupply] = Supplies.duplicate()
	if rescue_enabled: available.append(preload("res://src/features/camp/rescue.tres"))
	_active.assign(available)
	for index: int in range(available.size()):
		var supply: MissionSupply = available[index]
		var panel: PanelContainer = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if player_mode:
			panel.add_theme_stylebox_override("panel", _card_style(false))
		else:
			panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL if index == 0 else CampStyle.AMBER))
		row.add_child(panel)
		_card_panels.append(panel)
		var card: VBoxContainer = VBoxContainer.new()
		card.add_theme_constant_override("separation", 10 if player_mode else 12)
		panel.add_child(card)
		var rescue: bool = supply.id == &"rescue"
		var title: Label = CampStyle.label("%02d / %s" % [index + 1, RescueTarget.ACTION_TITLE if rescue else supply.layout.display_name], 24)
		if player_mode:
			var top: HBoxContainer = HBoxContainer.new()
			top.add_theme_constant_override("separation", 10)
			card.add_child(top)
			var mark: CardMark = CardMark.new()
			mark.custom_minimum_size = Vector2(34, 34)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(mark)
			_role_marks.append(mark)
			top.add_child(title)
		else:
			card.add_child(title)
		_titles.append(title)
		_build_thumbnail(card, SHOP if index == 0 else MARKET)
		var pressure: Label = CampStyle.label("", 15, CampStyle.TEAL)
		pressure.hide()
		card.add_child(pressure)
		_campaign_pressures.append(pressure)
		var description: String = _rescue_card_text(supply) if rescue else supply.description
		if player_mode:
			description += "\n搜完货币点可带回%d币；%s。武器以实际搜获为准。\n夜间敌人增援变密；阵亡不可恢复，归航需留足口粮。" % [supply.cash_reward,"食物点%d份" % supply.food_reward if supply.food_reward>0 else "此行没有食物点"]
		var text: Label = CampStyle.label(description, 17, CampStyle.MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.y = 52
		if player_mode:
			var scroll: ScrollContainer = ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.custom_minimum_size.y = 124
			card.add_child(scroll)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.add_theme_color_override("font_color", Color("d4e0dd"))
			text.mouse_filter = Control.MOUSE_FILTER_IGNORE
			scroll.add_child(text)
			_description_scrolls.append(scroll)
		else:
			card.add_child(text)
		_descriptions.append(text)
		var button: Button = Button.new()
		button.text = "前往救援 →" if index == 2 else ("出发搜集 →" if index == 0 else "前往超市 →")
		button.custom_minimum_size.y = 46 if player_mode else 52
		button.pressed.connect(func() -> void: selected.emit(_active[index]))
		card.add_child(button)
		choices.append(button)
		if player_mode:
			button.focus_entered.connect(func() -> void: panel.add_theme_stylebox_override("panel", _card_style(true)))
			button.focus_exited.connect(func() -> void: panel.add_theme_stylebox_override("panel", _card_style(false)))
	cancel_button = Button.new()
	cancel_button.text = "返回营地 / Esc" if player_mode else "取消 / 返回营地"
	cancel_button.custom_minimum_size.y = 44
	cancel_button.pressed.connect(func() -> void: cancelled.emit())
	if player_mode:
		cancel_button.custom_minimum_size.x = 184
		cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(cancel_button)
	if player_mode:
		_link_choices()


func refresh_rescue(completed: bool, reason: String = "") -> void:
	rescue_completed = completed
	if rescue_enabled and choices.size() > 2:
		choices[2].disabled = completed
		choices[2].text = "救援已结束" if completed else "前往救援 →"
		if completed and not reason.is_empty():
			choices[2].text = reason
	if player_mode:
		_link_choices()


func refresh_daily(base: Dictionary, rations: Dictionary = {}) -> void:
	daily_offers = DailyActions.offers(base)
	var action_choices: bool = CampaignRules.action_choices_enabled(base.get("journey", {}).get("campaign"))
	var has_mission_cards: bool = daily_offers.any(func(offer: Dictionary) -> bool: return offer.get("mission_policy") == 1)
	_subtitle.text = "比较主收益、路线与风险。物资和线索随生还归航确认。" if has_mission_cards else "选择此行的补给方向，准备好后出发。"
	_heading.text = "选择行动 · 第 %d 天" % int(base.day) if player_mode else "第%d天 · 选择一项行动" % int(base.day)
	if CampaignState.is_short(base):
		var display: Dictionary=CampaignRules.display(base.journey.campaign)
		_heading.text = ("选择行动" if player_mode else String(display.title)) + " · " + String(display.progress)
		if action_choices and player_mode:
			_heading.text = "选择行动 · 第 %d 天 · %s" % [int(base.day), display.progress]
	for index: int in range(choices.size()):
		var panel: PanelContainer = _card_panels[index]
		panel.visible = index < daily_offers.size()
		if player_mode:
			panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if daily_offers.size() == 1 else Control.SIZE_EXPAND_FILL
			panel.custom_minimum_size.x = 366 if daily_offers.size() == 1 else 0
		if index>=daily_offers.size(): continue
		var supply: MissionSupply = DailyActions.supply(daily_offers[index])
		_active[index] = supply
		var pressure: Label = _campaign_pressures[index]
		pressure.visible = CampaignPressureV1.enabled(supply.generated)
		if pressure.visible:
			pressure.text = CampaignPressureV1.label(int(supply.generated.campaign_pressure.tier))
		var rescue: bool = supply.id == &"rescue"
		_titles[index].text = "%02d / %s" % [index + 1, RescueTarget.ACTION_TITLE if rescue else supply.display_name]
		_descriptions[index].text = _rescue_card_text(supply) if rescue else supply.description
		_descriptions[index].custom_minimum_size.y = 52
		if _descriptions[index].has_theme_constant_override("line_spacing"):
			_descriptions[index].remove_theme_constant_override("line_spacing")
		_pictures[index].custom_minimum_size.y = 88
		var mission_card: bool = supply.generated.get("mission_policy") == 1
		var pump_card: bool = PumpStationAction.enabled(supply.generated)
		var rare_card: bool = supply.generated.has("rare_policy")
		var event_site: String = EventSortieV1.site_id(supply.generated)
		if not event_site.is_empty():
			_titles[index].text = "%02d / %s" % [index + 1, EventSortieV1.TITLE]
			_descriptions[index].text = _event_card_text(supply.generated)
			_descriptions[index].custom_minimum_size.y = 100
			_descriptions[index].add_theme_font_size_override("font_size", 16)
		elif rare_card:
			_titles[index].text = "%02d / 稀有行动 · %s" % [index + 1, supply.display_name]
			_descriptions[index].add_theme_font_size_override("font_size", 16)
		elif pump_card:
			_descriptions[index].add_theme_font_size_override("font_size", 16)
		elif mission_card:
			var title: String = {"supply":"补给", "airdrop":"装备", "equipment":"调查", "rescue":RescueTarget.ACTION_TITLE}[supply.generated.type]
			if SortieRiskV1.enabled(supply.generated):
				title = "装备 · 深入回收" if supply.generated.sortie_risk.tier == SortieRiskV1.DEEP else "装备 · 常规回收"
			_titles[index].text = "%02d / %s" % [index + 1, title]
			_descriptions[index].text = LevelSummary.mission_card_text(supply.generated, base if action_choices else {}, rations)
			if ReconActionV1.enabled(supply.generated):
				var lines: PackedStringArray = _descriptions[index].text.split("\n")
				lines.insert(1, "可侦察 · 标记装备点及 1 处可搜建筑")
				_descriptions[index].text = "\n".join(lines)
			elif BarricadeV1.enabled(supply.generated):
				var lines: PackedStringArray = _descriptions[index].text.split("\n")
				lines.insert(1, "有车辆路障 · 可绕行或用空袭开路")
				_descriptions[index].text = "\n".join(lines)
			_descriptions[index].custom_minimum_size.y = 100
			_descriptions[index].add_theme_font_size_override("font_size", 16)
			_descriptions[index].add_theme_constant_override("line_spacing", 2 if action_choices else 8)
		elif supply.generated.get("worldgen",{}).get("version")==2:
			# The original resource description participates in existing in-flight world compatibility hashes.
			if not rescue:
				var frozen_description: String = LevelSummary.description(supply.generated)
				_descriptions[index].text = supply.description.trim_suffix(frozen_description) + LevelSummary.description(supply.generated, true)
			_pictures[index].custom_minimum_size.y = 56
			_descriptions[index].add_theme_font_size_override("font_size",16)
		else:
			_descriptions[index].add_theme_font_size_override("font_size", 17)
		var investigation: Dictionary = supply.generated.get("investigation", {})
		if not mission_card and not investigation.is_empty():
			var clue_name: String = CampaignRules.CLUE_NAMES[investigation.clue_id]
			_titles[index].text = "%02d / 调查 · %s" % [index+1, clue_name]
			_descriptions[index].text = "搜索标记建筑：%s\n" % clue_name + _descriptions[index].text
			_pictures[index].custom_minimum_size.y = 40
		var outdoor: bool = not pump_card and TaskActions.outdoor_site(supply.generated,
			StringName(event_site) if not event_site.is_empty() else &"cash")
		var picture: Texture2D = MARKET if supply.id == &"supermarket" else SHOP
		if pump_card:
			picture = BuildingLibrary.definition("warehouse").texture
		elif mission_card or (player_mode and supply.generated.get("exploration", {}).has("level")):
			picture = _mission_picture(supply.generated, picture)
		elif outdoor:
			picture = null
		_pictures[index].texture = picture
		_crates[index].visible=outdoor
		choices[index].disabled = false
		choices[index].text = "选择此行动 →"
		choices[index].tooltip_text = "只有真实搜集并成功撤离，确认结算才入账。"
		if player_mode:
			_refresh_blue_hour_card(index, supply.generated)
	if player_mode:
		_link_choices()


static func _event_card_text(generated: Dictionary) -> String:
	var quiet: String = EventSortieV1.QUIET
	var force: String = EventSortieV1.FORCE
	return "备选行动 · 到站后现场二选一\n两路基础工时均为 %d 秒\n%s · %s\n%s · %s" % [
		int(generated.event_sortie.seconds), EventSortiePanel.branch_title(quiet), EventSortiePanel.offer_detail(generated, quiet),
		EventSortiePanel.branch_title(force), EventSortiePanel.offer_detail(generated, force)]


func _rescue_card_text(supply: MissionSupply) -> String:
	var size: String = {"small":"小型", "medium":"中型", "large":"大型"}.get(supply.generated.get("layout", {}).get("size"), "")
	var area: String = (size + "街区 · " if not size.is_empty() else "") + supply.layout.display_name
	var goal: String = "援救 10 秒后现场接纳，生还归航后登记入营。" if field_join_mode else "援救 10 秒，护送至巴士，生还归航后登记入营。"
	var route: String = LevelSummary.description(supply.generated, true)
	var text: String = "%s ×1\n%s\n%s" % [RescueTarget.ANONYMOUS_NAME, area, goal]
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
	_map_marks[index].visible = role == "investigation"
	_buses[index].visible = role == "supply" and not generated.has("rare_policy")
	var primary: Array = generated.get("exploration", {}).get("level", {}).get("primary", [])
	var second: TextureRect = _secondary_pictures[index]
	second.visible = role == "supply" and primary.size() > 1
	if second.visible:
		second.texture = _mission_picture(generated, MARKET, 1)
	_pictures[index].custom_minimum_size = Vector2.ZERO
	_description_scrolls[index].scroll_vertical = 0
	if type == "supply" and not generated.has("rare_policy") and _has_extra_weapon(generated):
		var lines: PackedStringArray = _descriptions[index].text.split("\n")
		lines.insert(1, "附带装备 · 需另搜")
		_descriptions[index].text = "\n".join(lines)
	choices[index].text = "出发 · 突破封锁 →" if role == "finale" else "选择此行动 →"


static func _has_extra_weapon(generated: Dictionary) -> bool:
	var main_sites: Array = generated.get("objective", {}).get("site_ids", [])
	for site: Dictionary in generated.get("sites", []):
		if site.get("weapon", false) and site.id not in main_sites:
			return true
	return false


func _build_thumbnail(card: VBoxContainer, source: Texture2D) -> void:
	var picture: TextureRect = _texture(source)
	var crate: Node2D = CrateThumbnail.new()
	crate.hide()
	_pictures.append(picture)
	_crates.append(crate)
	if not player_mode:
		picture.custom_minimum_size = Vector2(240 if rescue_enabled else 400, 192)
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(picture)
		picture.add_child(crate)
		picture.resized.connect(func() -> void: crate.position = picture.size * 0.5 + Vector2(-12, 28))
		return
	var well: ThumbnailPlate = ThumbnailPlate.new()
	well.custom_minimum_size.y = 160
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.clip_contents = true
	card.add_child(well)
	var skyline: HBoxContainer = HBoxContainer.new()
	skyline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skyline.add_theme_constant_override("separation", 0)
	well.add_child(skyline)
	skyline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skyline.offset_left = 7
	skyline.offset_right = -7
	skyline.offset_top = 6
	skyline.offset_bottom = -30
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skyline.add_child(picture)
	var second: TextureRect = _texture(MARKET)
	second.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second.hide()
	skyline.add_child(second)
	_secondary_pictures.append(second)
	var bus: TextureRect = _texture(BUS)
	well.add_child(bus)
	bus.anchor_left = 0.14
	bus.anchor_right = 0.47
	bus.anchor_top = 0.62
	bus.anchor_bottom = 0.98
	bus.hide()
	_buses.append(bus)
	well.add_child(crate)
	crate.scale = Vector2.ONE * 0.88
	well.resized.connect(func() -> void: crate.position = Vector2(well.size.x * 0.75, well.size.y * 0.84))
	var dossier: CardMark = CardMark.new()
	dossier.role = "investigation"
	dossier.large = true
	dossier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(dossier)
	dossier.anchor_left = 0.70
	dossier.anchor_right = 0.92
	dossier.anchor_top = 0.45
	dossier.anchor_bottom = 0.90
	dossier.hide()
	_map_marks.append(dossier)


static func _texture(source: Texture2D) -> TextureRect:
	var texture_rect: TextureRect = TextureRect.new()
	texture_rect.texture = source
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


static func _card_style(focused: bool) -> StyleBoxFlat:
	var color: Color = Color(0.06, 0.15, 0.19, 0.97) if focused else Color(0.045, 0.10, 0.14, 0.92)
	var edge: Color = CampStyle.AMBER if focused else Color("496971")
	var result: StyleBoxFlat = CampStyle.box(color, edge, 13)
	result.set_corner_radius_all(8)
	result.set_border_width_all(2 if focused else 1)
	return result


func _link_choices() -> void:
	var stops: Array[Button] = []
	for index: int in range(choices.size()):
		if _card_panels[index].visible and not choices[index].disabled:
			stops.append(choices[index])
	stops.append(cancel_button)
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


static func _mission_picture(generated: Dictionary, fallback: Texture2D, primary_index: int = 0) -> Texture2D:
	var primary: String = generated.exploration.level.primary[primary_index]
	var building: String = ""
	for site: Dictionary in generated.sites:
		if site.id == primary:
			building = site.object_id
			break
	for entity: Dictionary in generated.layout.entities:
		if entity.id == building or (primary == "rescue" and entity.door == generated.layout.rescue):
			# World sprites reserve transparent room above the facade for their foot anchor.
			var art: Dictionary = WorldgenArt.definition(entity)
			var texture: Texture2D = art.texture
			var height: float = WorldgenScale.visible_height(entity.archetype, int(entity.variant), entity.get("art", ""))
			var source_height: float = height * float(art.get("reference_width", 448.0)) / float(WorldgenScale.WIDTH[entity.archetype])
			var top: float = maxf(0.0, floorf(art.origin.y - source_height) - 16.0)
			var bottom: float = minf(texture.get_height(), ceilf(art.origin.y) + 16.0)
			var crop: AtlasTexture = AtlasTexture.new()
			crop.atlas = texture
			crop.region = Rect2(0, top, texture.get_width(), bottom - top)
			return crop
	return fallback


class CrateThumbnail extends Node2D:
	func _draw() -> void:
		AirdropProp.draw_crate(self, false)


class ThumbnailPlate extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var road_y: float = size.y * 0.76
		draw_rect(Rect2(Vector2.ZERO, size), Color("294653"))
		draw_rect(Rect2(0, size.y * 0.57, size.x, road_y - size.y * 0.57), Color("385052"))
		draw_rect(Rect2(0, road_y, size.x, size.y - road_y), Color("263641"))
		draw_line(Vector2(0, road_y), Vector2(size.x, road_y), Color("7e9393"), 2.0)
		draw_dashed_line(Vector2(0, size.y * 0.90), Vector2(size.x, size.y * 0.90), Color("777a67"), 1.0, 13.0)


class CardMark extends Control:
	var role: String = ""
	var large: bool = false

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var scale_factor: float = minf(size.x, size.y) / 34.0
		if scale_factor <= 0.0:
			return
		draw_set_transform(size * 0.5, -0.14 if large else 0.0, Vector2.ONE * scale_factor)
		var accent: Color = CampStyle.AMBER if role in ["equipment", "finale"] else CampStyle.TEAL
		if not large:
			draw_rect(Rect2(-16, -16, 32, 32), Color("173643"))
			draw_rect(Rect2(-16, -16, 32, 32), Color(accent, 0.58), false, 1.0)
		match role:
			"supply":
				draw_line(Vector2(-10, 0), Vector2(10, 0), accent, 1.6, true)
				draw_arc(Vector2(0, 0), 9, 0.12, PI - 0.12, 14, accent, 1.6, true)
				for x: float in [-5.0, 0.0, 5.0]:
					draw_line(Vector2(x, -3), Vector2(x + 1.5, -8), accent, 1.3, true)
			"equipment":
				draw_rect(Rect2(-10, -6, 20, 15), accent, false, 1.6)
				draw_line(Vector2(-10, -1), Vector2(10, -1), accent, 1.6)
				draw_line(Vector2(0, -6), Vector2(0, 9), accent, 2.6)
			"event":
				draw_line(Vector2(0, 10), Vector2(0, 0), accent, 2.0, true)
				draw_line(Vector2(0, 0), Vector2(-8, -8), accent, 2.0, true)
				draw_line(Vector2(0, 0), Vector2(8, -8), CampStyle.AMBER, 2.0, true)
				draw_circle(Vector2(-8, -8), 2.4, accent)
				draw_circle(Vector2(8, -8), 2.4, CampStyle.AMBER)
			"investigation":
				var edge: Color = Color("ecc591") if large else accent
				var paper: PackedVector2Array = PackedVector2Array([Vector2(-8, -12), Vector2(3, -12),
					Vector2(9, -6), Vector2(9, 12), Vector2(-8, 12), Vector2(-8, -12)])
				if large:
					draw_colored_polygon(PackedVector2Array([Vector2(-12, -7), Vector2(10, -10),
						Vector2(13, 11), Vector2(-10, 14)]), Color("3b5257"))
					draw_colored_polygon(paper, Color("d9b886"))
				draw_polyline(paper, edge, 1.5, true)
				draw_polyline(PackedVector2Array([Vector2(3, -12), Vector2(3, -6), Vector2(9, -6)]), edge, 1.5, true)
				for y: float in [-2.0, 3.0, 7.0]:
					draw_line(Vector2(-4, y), Vector2(5, y), Color("6f573e") if large else accent, 1.2, true)
			"rescue":
				draw_line(Vector2(-8, 0), Vector2(8, 0), accent, 3.0)
				draw_line(Vector2(0, -8), Vector2(0, 8), accent, 3.0)
			"finale":
				draw_line(Vector2(-6, -11), Vector2(-6, 11), accent, 1.8, true)
				draw_polyline(PackedVector2Array([Vector2(-6, -10), Vector2(10, -7), Vector2(-6, 0)]), accent, 1.8, true)
