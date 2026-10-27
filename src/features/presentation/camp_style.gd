class_name CampStyle
extends RefCounted
## Local presentation vocabulary. No campaign state or interaction policy.

const INK: Color = Color("0b1821")
const PANEL: Color = Color("142c36")
const TEXT: Color = Color("edf0df")
const MUTED: Color = Color("9aafb3")
const TEAL: Color = Color("80ddd8")
const AMBER: Color = Color("f2c37f")


static func box(colour: Color, edge: Color = Color("34535d"), padding: int = 16) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style


static func theme(base: Theme) -> Theme:
	var result: Theme = base.duplicate() as Theme
	result.default_font_size = 18
	result.set_color("font_color", "Label", TEXT)
	result.set_stylebox("normal", "Button", box(PANEL, Color("34535d"), 10))
	result.set_stylebox("hover", "Button", box(Color("244550"), TEAL, 10))
	result.set_stylebox("pressed", "Button", box(Color("305663"), TEAL, 10))
	result.set_stylebox("disabled", "Button", box(Color("11232c"), Color("243943"), 10))
	result.set_stylebox("focus", "Button", box(Color(0,0,0,0), TEAL, 0))
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_disabled_color", "Button", MUTED)
	result.set_stylebox("normal", "LineEdit", box(INK, Color("34535d"), 10))
	result.set_stylebox("focus", "LineEdit", box(INK, TEAL, 10))
	result.set_stylebox("panel", "ItemList", box(INK, Color("34535d"), 10))
	result.set_stylebox("selected", "ItemList", box(Color("254651"), TEAL))
	result.set_stylebox("selected_focus", "ItemList", box(Color("254651"), TEAL))
	result.set_stylebox("background", "ProgressBar", box(Color("0b1b24"), Color("34535d"), 0))
	result.set_stylebox("fill", "ProgressBar", box(TEAL, TEAL, 0))
	return result


static func label(value: String, font_size: int = 18, colour: Color = TEXT) -> Label:
	var node: Label = Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func place(control: Control, rect: Rect2) -> void:
	# Reference-canvas anchors preserve existing public control paths and KEEP scaling.
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.anchor_left = rect.position.x / 1280.0
	control.anchor_right = rect.end.x / 1280.0
	control.anchor_top = rect.position.y / 720.0
	control.anchor_bottom = rect.end.y / 720.0
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0
