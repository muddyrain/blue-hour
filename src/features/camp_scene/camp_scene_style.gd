class_name CampSceneStyle
extends RefCounted
## Camp panels share the approved cool pixel palette; world lighting stays local.

const PANEL: Color = CampStyle.PANEL
const TEXT: Color = CampStyle.TEXT
const MUTED: Color = CampStyle.MUTED
const AMBER: Color = CampStyle.TEAL # Existing camp accent API; now the mint status colour.
const EDGE: Color = CampStyle.EDGE


static func theme(base: Theme = null) -> Theme:
	var result: Theme = CampStyle.theme(base)
	result.default_font_size = 16
	return result


static func box() -> StyleBoxFlat:
	return CampStyle.box(PANEL, Color.TRANSPARENT, 10)


static func apply_to(root: Node) -> void:
	if _has_authored_sheet(root):
		if root is Control: root.theme = CampStyle.theme(root.theme)
		return
	if root is Control:
		root.theme = theme(root.theme)
	_recolour(root)


static func _has_authored_sheet(root: Node) -> bool:
	if root is PixelSheet: return true
	for child: Node in root.get_children():
		if _has_authored_sheet(child): return true
	return false


static func _recolour(root: Node) -> void:
	# Retain authored margins and minimum sizes in existing camp editors. Already
	# migrated controls keep their semantic status and primary-action colours.
	if root is Control:
		var control: Control = root as Control
		if control.theme != null:
			control.theme = theme(control.theme)
		for key: String in ["panel", "normal", "hover", "pressed", "disabled", "focus"]:
			if not control.has_theme_stylebox_override(key):
				continue
			var previous: StyleBoxFlat = control.get_theme_stylebox(key) as StyleBoxFlat
			if previous == null:
				continue
			var style: StyleBoxFlat = previous.duplicate() as StyleBoxFlat
			style.set_corner_radius_all(0)
			style.shadow_size = 0
			if not _current_colour(style.bg_color):
				if style.bg_color.a > 0.0:
					style.bg_color = CampStyle.SELECTED.darkened(0.16) if key == "hover" else CampStyle.SURFACE if key == "pressed" else PANEL
				style.set_border_width_all(1 if key == "focus" else 0)
				style.border_color = CampStyle.TEAL if key == "focus" else Color.TRANSPARENT
			control.add_theme_stylebox_override(key, style)
		if control is Label:
			var colour: Color = control.get_theme_color("font_color")
			if colour.is_equal_approx(Color("d9a24a")):
				control.add_theme_color_override("font_color", AMBER)
			elif colour.is_equal_approx(Color("e8dcc4")):
				control.add_theme_color_override("font_color", TEXT)
			elif colour.is_equal_approx(Color("b8ac96")):
				control.add_theme_color_override("font_color", MUTED)
		if control is ColorRect and control.color.is_equal_approx(Color("22201e")):
			control.color = CampStyle.INK
	elif root is Window:
		root.theme = theme(root.theme)
	for child: Node in root.get_children():
		_recolour(child)


static func _current_colour(colour: Color) -> bool:
	for current: Color in [CampStyle.INK, PANEL, CampStyle.SURFACE, CampStyle.SELECTED,
			CampStyle.SELECTED.darkened(0.16), CampStyle.TEAL, CampStyle.CORAL, CampStyle.CORAL.lightened(0.12),
			CampStyle.CORAL.darkened(0.08), Color("223b4d")]:
		if Color(colour, 1.0).is_equal_approx(current):
			return true
	return false
