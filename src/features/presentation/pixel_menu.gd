class_name PixelMenu
extends RefCounted
## Shared game-menu chrome. No state or gameplay decisions.


static func masthead(parent: VBoxContainer, title: String, resources: Label) -> Label:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = CampStyle.box(CampStyle.INK, CampStyle.EDGE, 14)
	style.set_border_width_all(0)
	style.border_width_bottom = 2
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.y = 56
	parent.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)
	var logo: Label = CampStyle.label("蓝时归航", 29)
	var slant: FontVariation = FontVariation.new()
	slant.base_font = CampStyle.BOLD_FONT
	slant.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.16, 1), Vector2.ZERO)
	logo.add_theme_font_override("font", slant)
	logo.custom_minimum_size.x = 180
	row.add_child(logo)
	divider(row, true)
	var heading: Label = CampStyle.label(title, 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	resources.add_theme_font_size_override("font_size", 19)
	resources.add_theme_color_override("font_color", CampStyle.TEXT)
	resources.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(resources)
	return heading


static func divider(parent: Node, vertical: bool = false) -> ColorRect:
	var line: ColorRect = ColorRect.new()
	line.color = CampStyle.EDGE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(1, 28) if vertical else Vector2(0, 1)
	if vertical:
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(line)
	return line


static func primary(button: Button) -> void:
	CampStyle.primary(button)
	button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.CORAL.darkened(0.08), Color.TRANSPARENT, 12))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)


static func tab(button: Button, selected: bool) -> void:
	CampStyle.text_button(button)
	button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.SELECTED if selected else Color.TRANSPARENT, Color.TRANSPARENT, 8))
	button.add_theme_color_override("font_color", CampStyle.TEXT)
