class_name MissionSelect
extends Control
## Read-only choice of existing sources, with original building silhouettes.

signal selected(supply: MissionSupply)
signal cancelled

const Supplies: Array[MissionSupply] = [preload("res://src/features/camp/scavenge.tres"), preload("res://src/features/camp/supermarket.tres")]
const SHOP: Texture2D = preload("res://assets/candidates/shop_02.png")
const MARKET: Texture2D = preload("res://assets/m401/market.png")
var choices: Array[Button] = []
var daily_offers: Array[Dictionary] = []
var _active: Array[MissionSupply] = []
var _titles: Array[Label] = []
var _descriptions: Array[Label] = []
class CrateThumbnail extends Node2D:
	func _draw() -> void:
		AirdropProp.draw_crate(self,false)

var _crates: Array[Node2D] = []
var _pictures: Array[TextureRect] = []
var _heading: Label
var rescue_enabled: bool = false
var player_mode: bool = false
var field_join_mode: bool = false
var rescue_completed: bool = false
var cancel_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background: ColorRect = ColorRect.new()
	background.color = CampStyle.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right"]:
		margins.add_theme_constant_override("margin_" + side, 80)
	for side: String in ["top","bottom"]:
		margins.add_theme_constant_override("margin_" + side, 104 if side == "top" else 32)
	add_child(margins)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margins.add_child(column)
	_heading = CampStyle.label("行动地图 / 旧街", 32)
	column.add_child(_heading)
	column.add_child(CampStyle.label("选择此行的补给方向，准备好后出发。", 18, CampStyle.MUTED))
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	var available: Array[MissionSupply] = Supplies.duplicate()
	if rescue_enabled: available.append(preload("res://src/features/camp/rescue.tres"))
	_active.assign(available)
	for index: int in range(available.size()):
		var supply: MissionSupply = available[index]
		var panel: PanelContainer = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL if index == 0 else CampStyle.AMBER))
		row.add_child(panel)
		var card: VBoxContainer = VBoxContainer.new()
		card.add_theme_constant_override("separation", 12)
		panel.add_child(card)
		var title: Label = CampStyle.label("%02d / %s" % [index + 1, supply.display_name if index == 2 else supply.layout.display_name], 24)
		card.add_child(title)
		_titles.append(title)
		var picture: TextureRect = TextureRect.new()
		picture.texture = SHOP if index == 0 else MARKET
		picture.custom_minimum_size = Vector2(240 if rescue_enabled else 400,112 if player_mode else 192)
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(picture)
		_pictures.append(picture)
		var crate: Node2D=CrateThumbnail.new()
		crate.visible=false
		picture.add_child(crate)
		picture.resized.connect(func() -> void: crate.position=picture.size*0.5+Vector2(-12,28))
		_crates.append(crate)
		var description: String = "援救10秒后立即加入行动；全员撤离后登记营地。新同行本餐不参食，下次按实际存活者计粮。" if field_join_mode and index == 2 else supply.description
		if player_mode:
			description = ("援助一位幸存者10秒后同行参战，存活归航后正式加入。" if index==2 else supply.description) + "\n搜完货币点可带回%d币；%s。武器以实际搜获为准。\n夜间敌人增援变密；阵亡不可恢复，归航需留足口粮。" % [supply.cash_reward,"食物点%d份" % supply.food_reward if supply.food_reward>0 else "此行没有食物点"]
		var text: Label = CampStyle.label(description, 17, CampStyle.MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.y = 52
		card.add_child(text)
		_descriptions.append(text)
		var button: Button = Button.new()
		button.text = "前往救援 →" if index == 2 else ("出发搜集 →" if index == 0 else "前往超市 →")
		button.custom_minimum_size.y = 52
		button.pressed.connect(func() -> void: selected.emit(_active[index]))
		card.add_child(button)
		choices.append(button)
	cancel_button = Button.new()
	cancel_button.text = "取消 / 返回营地"
	cancel_button.custom_minimum_size.y = 44
	cancel_button.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(cancel_button)


func refresh_rescue(completed: bool, reason: String = "") -> void:
	rescue_completed = completed
	if rescue_enabled and choices.size() > 2:
		choices[2].disabled = completed
		choices[2].text = ("救援已结束" if field_join_mode else "林知秋已加入") if completed else "前往救援 →"
		if completed and not reason.is_empty():
			choices[2].text = reason


func refresh_daily(base: Dictionary) -> void:
	daily_offers = DailyActions.offers(base)
	_heading.text = "第%d天 · 选择一项行动" % int(base.day)
	if CampaignState.is_short(base):
		var display: Dictionary=CampaignRules.display(base.journey.campaign)
		_heading.text=display.title+" · "+display.progress
	for index: int in range(3):
		choices[index].get_parent().get_parent().visible=index<daily_offers.size()
		if index>=daily_offers.size(): continue
		var supply: MissionSupply = DailyActions.supply(daily_offers[index])
		_active[index] = supply
		_titles[index].text = "%02d / %s" % [index+1,supply.display_name]
		_descriptions[index].text = supply.description
		_pictures[index].custom_minimum_size.y = 88
		if supply.generated.get("worldgen",{}).get("version")==2:
			_pictures[index].custom_minimum_size.y = 56
			_descriptions[index].add_theme_font_size_override("font_size",16)
		var outdoor: bool=TaskActions.outdoor_site(supply.generated,&"cash")
		_pictures[index].texture = null if outdoor else MARKET if supply.id==&"supermarket" else SHOP
		_crates[index].visible=outdoor
		choices[index].disabled = false
		choices[index].text = "选择此行动 →"
		choices[index].tooltip_text = "只有真实搜集并成功撤离，确认结算才入账。"
