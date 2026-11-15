class_name CampSceneStyle
extends RefCounted
## Camp-local warm charcoal theme; expedition HUD and shared art remain untouched.

const PANEL: Color = Color(0.1333, 0.1255, 0.1176, 0.92)
const TEXT: Color = Color("e8dcc4")
const MUTED: Color = Color("b8ac96")
const AMBER: Color = Color("d9a24a")
const EDGE: Color = Color(0.91, 0.86, 0.77, 0.55)


static func theme(base: Theme) -> Theme:
	var result: Theme = base.duplicate() as Theme if base != null else Theme.new()
	result.default_font_size = 16
	for type: String in ["Label", "Button", "CheckButton", "LineEdit", "OptionButton"]:
		result.set_color("font_color", type, TEXT)
		result.set_color("font_hover_color", type, TEXT)
		result.set_color("font_focus_color", type, TEXT)
		result.set_color("font_disabled_color", type, MUTED)
	for type: String in ["PanelContainer", "PopupPanel", "AcceptDialog"]:
		result.set_stylebox("panel", type, box())
	for type: String in ["Button", "OptionButton", "LineEdit"]:
		result.set_stylebox("normal", type, box())
		result.set_stylebox("hover", type, CampStyle.box(Color("39342c"), AMBER, 8))
		result.set_stylebox("pressed", type, CampStyle.box(Color("493c2b"), AMBER, 8))
		result.set_stylebox("disabled", type, CampStyle.box(Color("26231f"), Color("61594d"), 8))
		result.set_stylebox("focus", type, CampStyle.box(Color.TRANSPARENT, AMBER, 0))
	result.set_stylebox("background", "ProgressBar", CampStyle.box(Color("302c27"), EDGE, 0))
	result.set_stylebox("fill", "ProgressBar", CampStyle.box(AMBER, AMBER, 0))
	return result


static func box() -> StyleBoxFlat:
	return CampStyle.box(PANEL, EDGE, 10)


static func apply_to(root: Node) -> void:
	if root is Control:
		root.theme = theme(root.theme)
	_recolour(root)


static func _recolour(root: Node) -> void:
	# Existing panels author their own overrides. Recolour copies while retaining
	# all margins/minimum sizes, so a palette change cannot change panel layout.
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
			if style.bg_color.a > 0.0:
				style.bg_color = PANEL
			style.border_color = AMBER if key in ["hover", "focus", "pressed"] else EDGE
			control.add_theme_stylebox_override(key, style)
		if control is Label:
			var colour: Color = control.get_theme_color("font_color")
			if colour.is_equal_approx(CampStyle.TEAL) or colour.is_equal_approx(CampStyle.AMBER):
				control.add_theme_color_override("font_color", AMBER)
			elif colour.is_equal_approx(CampStyle.TEXT):
				control.add_theme_color_override("font_color", TEXT)
			elif colour.is_equal_approx(CampStyle.MUTED):
				control.add_theme_color_override("font_color", MUTED)
		if control is ColorRect:
			control.color = Color("22201e")
	elif root is Window:
		root.theme = theme(root.theme)
	for child: Node in root.get_children():
		_recolour(child)
