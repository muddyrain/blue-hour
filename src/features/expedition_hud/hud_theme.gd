class_name ExpeditionHudTheme
extends RefCounted
## Expedition-local styles; never mutate the shared camp theme.

const CREAM: Color = Color("e8dcc4")
const SECONDARY: Color = Color("b8ac96")
const AMBER: Color = Color("d9a24a")
const SAGE: Color = Color("8fbf7a")
const DANGER: Color = Color("c8553d")

static func box(accent: Color = Color("e8dcc4", 0.55), radius: int = 3) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("22201e", 0.80)
	style.border_color = accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style

static func skin(node: Node) -> void:
	if node is PanelContainer:
		var surface: StyleBoxFlat = box()
		if node.name == "ActionsPanel":
			surface.content_margin_top = 2
			surface.content_margin_bottom = 2
		node.add_theme_stylebox_override("panel", surface)
	if node is Label:
		node.add_theme_color_override("font_color", CREAM)
	if node is Button:
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style: StyleBoxFlat = box(AMBER if state in ["hover", "focus"] else Color("e8dcc4", 0.55), 7)
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 1 if node.name == "LocateObjective" else 4
			style.content_margin_bottom = 1 if node.name == "LocateObjective" else 4
			if state == "pressed": style.bg_color = Color("655039", 0.95)
			node.add_theme_stylebox_override(state, style)
		node.add_theme_color_override("font_color", CREAM)
		node.add_theme_color_override("font_hover_color", CREAM)
		node.add_theme_color_override("font_pressed_color", AMBER)
		node.add_theme_color_override("font_disabled_color", SECONDARY)
		node.add_theme_color_override("icon_disabled_color", SECONDARY)
	if node is ProgressBar:
		var track: StyleBoxFlat = StyleBoxFlat.new()
		track.bg_color = Color("13120f", 0.8)
		track.set_corner_radius_all(2)
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = AMBER if node.name == "SortieTimeRatio" else SAGE
		fill.set_corner_radius_all(2)
		node.add_theme_stylebox_override("background", track)
		node.add_theme_stylebox_override("fill", fill)
	for child: Node in node.get_children(): skin(child)
