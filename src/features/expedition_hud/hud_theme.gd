class_name ExpeditionHudTheme
extends RefCounted
## Field presentation shares the approved palette; every surface stays local.

const CREAM: Color = CampStyle.TEXT
const SECONDARY: Color = CampStyle.MUTED
const AMBER: Color = CampStyle.TEAL
const SAGE: Color = CampStyle.TEAL
const DANGER: Color = CampStyle.DANGER

static func box(accent: Color = CampStyle.EDGE, _radius: int = 0) -> StyleBoxFlat:
	var style: StyleBoxFlat = CampStyle.box(CampStyle.INK, accent, 8)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

static func skin(node: Node) -> void:
	if node is PanelContainer:
		var surface: StyleBoxFlat = box()
		if node.name == "CardSurface":
			surface = CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 4)
			surface.content_margin_top = 5
			surface.content_margin_bottom = 7
		if node.name in ["TimePanel", "ResourcesPanel"]:
			surface.border_color = Color.TRANSPARENT
		if node.name == "ActionsPanel":
			surface.content_margin_top = 4
			surface.content_margin_bottom = 4
		if node.name == "StatusHintPanel":
			surface.bg_color.a = 0.94
			surface.content_margin_top = 4
			surface.content_margin_bottom = 4
		node.add_theme_stylebox_override("panel", surface)
	if node is Label:
		node.add_theme_color_override("font_color", CREAM)
	if node is Button:
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var fill: Color = CampStyle.SURFACE
			if state == "hover": fill = CampStyle.SELECTED.darkened(0.16)
			if state == "pressed": fill = CampStyle.PANEL
			if state == "disabled": fill = Color("223b4d")
			if state == "focus": fill = Color.TRANSPARENT
			var style: StyleBoxFlat = CampStyle.box(fill, SAGE if state == "focus" else Color.TRANSPARENT, 4)
			style.content_margin_top = 1 if node.name == "LocateObjective" else 4
			style.content_margin_bottom = 1 if node.name == "LocateObjective" else 4
			node.add_theme_stylebox_override(state, style)
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			node.add_theme_color_override(state, CREAM)
		node.add_theme_color_override("font_disabled_color", SECONDARY)
		node.add_theme_color_override("icon_disabled_color", SECONDARY)
	if node is ProgressBar:
		node.add_theme_stylebox_override("background", CampStyle.box(CampStyle.SURFACE, Color.TRANSPARENT, 0))
		node.add_theme_stylebox_override("fill", CampStyle.box(SAGE, Color.TRANSPARENT, 0))
	for child: Node in node.get_children(): skin(child)
