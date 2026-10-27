class_name MissionSelect
extends Control
## Read-only choice of existing sources, with original building silhouettes.

signal selected(supply: MissionSupply)
signal cancelled

const Supplies: Array[MissionSupply] = [preload("res://src/features/camp/scavenge.tres"), preload("res://src/features/camp/supermarket.tres")]
const SHOP: Texture2D = preload("res://assets/candidates/shop_02.png")
const MARKET: Texture2D = preload("res://assets/m401/market.png")
var choices: Array[Button] = []
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
	column.add_child(CampStyle.label("行动地图 / 旧街", 32))
	column.add_child(CampStyle.label("选择此行的补给方向，准备好后出发。", 18, CampStyle.MUTED))
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	for index: int in range(Supplies.size()):
		var supply: MissionSupply = Supplies[index]
		var panel: PanelContainer = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL if index == 0 else CampStyle.AMBER))
		row.add_child(panel)
		var card: VBoxContainer = VBoxContainer.new()
		card.add_theme_constant_override("separation", 12)
		panel.add_child(card)
		card.add_child(CampStyle.label("%02d / %s" % [index + 1, supply.layout.display_name], 24))
		var picture: TextureRect = TextureRect.new()
		picture.texture = SHOP if index == 0 else MARKET
		picture.custom_minimum_size = Vector2(400,192)
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(picture)
		var text: Label = CampStyle.label(supply.description, 17, CampStyle.MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.y = 52
		card.add_child(text)
		var button: Button = Button.new()
		button.text = "出发搜集 →" if index == 0 else "前往超市 →"
		button.custom_minimum_size.y = 52
		button.pressed.connect(func() -> void: selected.emit(supply))
		card.add_child(button)
		choices.append(button)
	cancel_button = Button.new()
	cancel_button.text = "取消 / 返回营地"
	cancel_button.custom_minimum_size.y = 44
	cancel_button.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(cancel_button)
