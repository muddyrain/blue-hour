class_name PixelSheet
extends Control
## A single logical canvas for camp editors. All values come from their owner.

signal closed
signal navigation_requested(action: StringName)

const BACKGROUND: Texture2D = preload("res://assets/camp_pixel/coast-yard.png")
const TABS: Dictionary = {&"roster": "队员", &"weapons": "装备仓", &"workshop": "工坊", &"supplies": "补给", &"training": "训练", &"catalog": "专精"}

var page_title: String = ""
var active_tab: StringName = &""
var stage: Control
var body: Control
var back_button: Button
var tab_buttons: Dictionary[StringName, Button] = {}
var heading: Label
var _day: Label
var _food: Label
var _cash: Label
var _tools: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = CampStyle.theme(theme)
	mouse_filter = Control.MOUSE_FILTER_STOP
	stage = Control.new()
	stage.size = Vector2(1280, 720)
	add_child(stage)
	var backdrop: TextureRect = art(stage, BACKGROUND, Rect2(0, 0, 1280, 720))
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	panel(stage, Rect2(0, 0, 1280, 56), CampStyle.INK)
	var logo: Label = label(stage, "蓝时归航", Rect2(24, 0, 212, 54), 36)
	var slant: FontVariation = FontVariation.new()
	slant.base_font = CampStyle.BOLD_FONT
	slant.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.14, 1), Vector2.ZERO)
	logo.add_theme_font_override("font", slant)
	art(stage, symbol_texture("ship"), Rect2(178, 26, 62, 24))
	line(stage, Rect2(254, 12, 1, 32))
	heading = label(stage, page_title, Rect2(278, 0, 336, 54), 36)
	panel(stage, Rect2(640, 7, 112, 40), CampStyle.INK, CampStyle.EDGE)
	_day = label(stage, "", Rect2(640, 7, 112, 40), 27)
	_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_food = _resource("food", 784, 140)
	_cash = _resource("cash", 938, 144)
	_tools = _resource("tools", 1098, 164)
	line(stage, Rect2(0, 54, 1280, 2))
	body = Control.new()
	stage.add_child(body)
	place(body, Rect2(88, 64, 1104, 584))
	panel(body, Rect2(0, 0, 1104, 584), CampStyle.INK)
	panel(stage, Rect2(0, 656, 1280, 64), CampStyle.INK)
	line(stage, Rect2(0, 656, 1280, 1))
	back_button = button(stage, "营地 / Esc", Rect2(24, 666, 160, 44), 25)
	CampStyle.text_button(back_button)
	back_button.pressed.connect(closed.emit)
	line(stage, Rect2(192, 672, 1, 32))
	var index: int = 0
	for action: StringName in TABS:
		var tab: Button = button(stage, TABS[action], Rect2(208 + index * 128, 666, 120, 44), 27)
		PixelMenu.tab(tab, action == active_tab)
		tab.pressed.connect(navigation_requested.emit.bind(action))
		tab_buttons[action] = tab
		index += 1
	resized.connect(_fit)
	_fit()


func update_resources(data: Dictionary) -> void:
	_day.text = "第%d天" % int(data.get("day", 1))
	_food.text = "食物%d" % int(data.get("food", 0))
	_cash.text = "货币%d" % int(data.get("cash", data.get("money", 0)))
	_tools.text = "工具箱%d" % WorkshopV1.tools(data)


func _resource(kind: String, x: float, width: float) -> Label:
	art(stage, load("res://assets/camp_pixel/%s.svg" % kind), Rect2(x, 17, 25, 24))
	return label(stage, "", Rect2(x + 34, 0, width - 34, 54), 22)


func _fit() -> void:
	var factor: float = minf(size.x / 1280.0, size.y / 720.0)
	stage.scale = Vector2.ONE * factor
	stage.position = (size - Vector2(1280, 720) * factor) / 2.0


static func place(control: Control, bounds: Rect2) -> Control:
	control.position = bounds.position
	control.size = bounds.size
	return control


static func label(parent: Node, text: String, bounds: Rect2, font: int = 22, colour: Color = CampStyle.TEXT, bold: bool = true) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font)
	result.add_theme_color_override("font_color", colour)
	if bold:
		result.add_theme_font_override("font", CampStyle.BOLD_FONT)
	parent.add_child(result)
	place(result, bounds)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func art(parent: Node, texture: Texture2D, bounds: Rect2) -> TextureRect:
	var result: TextureRect = TextureRect.new()
	result.texture = texture
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	place(result, bounds)
	return result


static func button(parent: Node, text: String, bounds: Rect2, font: int = 24) -> Button:
	var result: Button = Button.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var fill: Color = CampStyle.SURFACE if state == "normal" else CampStyle.SELECTED if state == "hover" else CampStyle.PANEL
		var style: StyleBoxFlat = CampStyle.box(fill, Color.TRANSPARENT, 8)
		style.content_margin_top = 2 if bounds.size.y <= 48 else 6
		style.content_margin_bottom = style.content_margin_top
		result.add_theme_stylebox_override(state, style)
	parent.add_child(result)
	place(result, bounds)
	return result


static func panel(parent: Node, bounds: Rect2, colour: Color, edge: Color = Color.TRANSPARENT) -> Panel:
	var result: Panel = Panel.new()
	result.add_theme_stylebox_override("panel", CampStyle.box(colour, edge, 0))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	place(result, bounds)
	return result


static func line(parent: Node, bounds: Rect2) -> ColorRect:
	var result: ColorRect = ColorRect.new()
	result.color = CampStyle.EDGE
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	place(result, bounds)
	return result


static func body_texture(member_id: int) -> Texture2D:
	return CampPixelArt.body(str(SurvivorRoster.definition(member_id).id))


static func facility_texture(index: int) -> Texture2D:
	var texture: Texture2D = load("res://assets/menu_pixel/facilities.png")
	var result: AtlasTexture = AtlasTexture.new()
	result.atlas = texture
	var height: float = texture.get_height() / 3.0
	result.region = Rect2(0, index * height, texture.get_width(), height)
	result.filter_clip = true
	return result


static func object_texture(kind: String) -> Texture2D:
	var bounds: Dictionary = {
		"carbine": Rect2(51, 236, 536, 213), "rifle": Rect2(663, 247, 541, 169),
		"extended": Rect2(116, 788, 209, 324), "quick": Rect2(345, 870, 162, 224),
		"belt": Rect2(667, 801, 522, 294),
	}
	var result: AtlasTexture = AtlasTexture.new()
	result.atlas = load("res://assets/menu_pixel/workshop-objects.png")
	result.region = bounds[kind]
	result.filter_clip = true
	return result


static func symbol_texture(kind: String) -> Texture2D:
	var bounds: Dictionary = {
		"sprint": Rect2(95, 151, 335, 262), "freeze": Rect2(629, 126, 288, 308),
		"pulse": Rect2(1086, 157, 340, 279), "radio": Rect2(116, 623, 292, 280),
		"lock": Rect2(659, 636, 212, 259), "ship": Rect2(1088, 701, 365, 132),
	}
	var result: AtlasTexture = AtlasTexture.new()
	result.atlas = load("res://assets/menu_pixel/menu-symbols.png")
	result.region = bounds[kind]
	result.filter_clip = true
	return result
