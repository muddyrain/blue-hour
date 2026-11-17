class_name CampStyle
extends RefCounted
## Local presentation vocabulary. No campaign state or interaction policy.

const INK: Color = Color("0a2133")
const PANEL: Color = Color("163248")
const SURFACE: Color = Color("315773")
const SELECTED: Color = Color("4387b7")
const EDGE: Color = Color("527da0")
const TEXT: Color = Color("f5f7fa")
const MUTED: Color = Color("b8c6d4")
const TEAL: Color = Color("79edc7")
const CORAL: Color = Color("f36d60")
const AMBER: Color = Color("f2c37f") # Warnings, not the interface accent.
const DANGER: Color = Color("ff9388")


static func box(colour: Color, edge: Color = Color.TRANSPARENT, padding: int = 16) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = edge
	style.set_border_width_all(0 if edge.a == 0.0 else 1)
	style.set_corner_radius_all(0)
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style


static func theme(base: Theme = null) -> Theme:
	var result: Theme = base.duplicate() as Theme if base != null else Theme.new()
	result.default_font_size = 18
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "ItemList", "PopupMenu", "RichTextLabel"]:
		result.set_color("font_color", type, TEXT)
		result.set_color("font_hover_color", type, TEXT)
		result.set_color("font_pressed_color", type, TEXT)
		result.set_color("font_focus_color", type, TEXT)
		result.set_color("font_disabled_color", type, MUTED)
	for type: String in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, box(SURFACE, Color.TRANSPARENT, 10))
		result.set_stylebox("hover", type, box(SELECTED.darkened(0.16), Color.TRANSPARENT, 10))
		result.set_stylebox("pressed", type, box(PANEL, TEAL, 10))
		result.set_stylebox("disabled", type, box(Color("223b4d"), Color.TRANSPARENT, 10))
		result.set_stylebox("focus", type, box(Color.TRANSPARENT, TEAL, 0))
	for type: String in ["PanelContainer", "PopupPanel", "PopupMenu", "AcceptDialog"]:
		result.set_stylebox("panel", type, box(PANEL))
	result.set_stylebox("normal", "LineEdit", box(INK, EDGE, 10))
	result.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, TEAL, 0))
	result.set_color("caret_color", "LineEdit", TEAL)
	result.set_color("selection_color", "LineEdit", SELECTED)
	result.set_stylebox("panel", "ItemList", box(INK, Color.TRANSPARENT, 10))
	result.set_stylebox("selected", "ItemList", box(SELECTED.darkened(0.16)))
	result.set_stylebox("selected_focus", "ItemList", box(SELECTED.darkened(0.16), TEAL))
	result.set_stylebox("background", "ProgressBar", box(SURFACE, Color.TRANSPARENT, 0))
	result.set_stylebox("fill", "ProgressBar", box(TEAL, Color.TRANSPARENT, 0))
	result.set_stylebox("slider", "HSlider", box(SURFACE, Color.TRANSPARENT, 3))
	result.set_stylebox("grabber_area", "HSlider", box(TEAL, Color.TRANSPARENT, 3))
	result.set_stylebox("grabber_area_highlight", "HSlider", box(TEAL.lightened(0.1), Color.TRANSPARENT, 3))
	var knob: Image = Image.create(16, 20, false, Image.FORMAT_RGBA8)
	knob.fill(TEXT)
	var knob_texture: ImageTexture = ImageTexture.create_from_image(knob)
	result.set_icon("grabber", "HSlider", knob_texture)
	result.set_icon("grabber_highlight", "HSlider", knob_texture)
	result.set_icon("grabber_disabled", "HSlider", knob_texture)
	for type: String in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type, box(INK, Color.TRANSPARENT, 3))
		result.set_stylebox("grabber", type, box(SURFACE, Color.TRANSPARENT, 3))
		result.set_stylebox("grabber_highlight", type, box(SELECTED, Color.TRANSPARENT, 3))
		result.set_stylebox("grabber_pressed", type, box(TEAL, Color.TRANSPARENT, 3))
	return result


static func blue_hour_theme(base: Theme) -> Theme:
	return theme(base)


static func blue_hour_primary(button: Button) -> void:
	primary(button)


static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(CORAL, Color.TRANSPARENT, 12))
	button.add_theme_stylebox_override("hover", box(CORAL.lightened(0.12), Color.TRANSPARENT, 12))
	button.add_theme_stylebox_override("pressed", box(CORAL.darkened(0.08), Color.TRANSPARENT, 12))
	button.add_theme_stylebox_override("disabled", box(SURFACE, Color.TRANSPARENT, 12))
	button.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, TEXT, 0))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", MUTED)


static func text_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(Color.TRANSPARENT, Color.TRANSPARENT, 10))
	button.add_theme_stylebox_override("hover", box(PANEL, Color.TRANSPARENT, 10))
	button.add_theme_stylebox_override("pressed", box(SURFACE, Color.TRANSPARENT, 10))
	button.add_theme_stylebox_override("disabled", box(Color.TRANSPARENT, Color.TRANSPARENT, 10))
	button.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, TEAL, 0))


static func blue_hour_background(texture: Texture2D) -> TextureRect:
	var background: TextureRect = TextureRect.new()
	background.texture = texture
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return background


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
