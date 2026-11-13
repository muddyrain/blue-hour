class_name ExpeditionHudReadouts
extends RefCounted
## Presentation of the existing resource strings and objective counts.
var _chips: Array[Label] = []
var _cargo: Label
var _objective_bar: ProgressBar

func build(hud: C1ExpeditionHud) -> void:
	var heading: HBoxContainer = hud._mission.get_parent() as HBoxContainer
	var accent: ColorRect = ColorRect.new()
	accent.color = ExpeditionHudTheme.AMBER
	accent.custom_minimum_size.x = 3
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(accent)
	heading.move_child(accent, 0)
	_objective_bar = ProgressBar.new()
	_objective_bar.name = "ObjectiveProgress"
	_objective_bar.custom_minimum_size.y = 4
	_objective_bar.max_value = 1.0
	_objective_bar.step = 0.0
	_objective_bar.show_percentage = false
	_objective_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._exploration_objectives.labels[0].add_child(_objective_bar)
	_objective_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_objective_bar.offset_top = -2
	_objective_bar.offset_bottom = 2
	var resources: Node = hud._currency.get_parent()
	hud._currency.hide()
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	resources.add_child(column)
	resources.move_child(column, 0)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	for index: int in range(3):
		var chip: PanelContainer = PanelContainer.new()
		chip.name = "ResourceChip%d" % index
		row.add_child(chip)
		var label: Label = hud._label(chip, "Value", 12)
		_chips.append(label)
	_cargo = hud._label(column, "CarriedResources", 11)
	_cargo.add_theme_color_override("font_color", ExpeditionHudTheme.SECONDARY)
	# Style after recursive HUD skinning so capsule radii stay local.
	_style_chips.call_deferred()

func _style_chips() -> void:
	for label: Label in _chips:
		var style: StyleBoxFlat = ExpeditionHudTheme.box(Color("e8dcc4", 0.55), 9)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		(label.get_parent() as PanelContainer).add_theme_stylebox_override("panel", style)
	(_objective_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = ExpeditionHudTheme.AMBER

func refresh(hud: C1ExpeditionHud, rows: Array[Dictionary], _state: Dictionary) -> void:
	var text: String = hud._currency.text
	var values: Array[String] = []
	for key: String in ["货币", "食物", "工具箱"]:
		var expression: RegEx = RegEx.new()
		expression.compile(key + "\\s*(\\d+)")
		var found: RegExMatch = expression.search(text)
		values.append(found.get_string(1) if found != null else "—")
	for index: int in range(_chips.size()):
		_chips[index].text = ["◆ ", "● ", "▣ "][index] + values[index]
		_chips[index].tooltip_text = ["货币", "食物", "工具箱"][index]
		_chips[index].add_theme_color_override("font_color", [ExpeditionHudTheme.AMBER, ExpeditionHudTheme.SAGE, ExpeditionHudTheme.CREAM][index])
	_cargo.text = text.get_slice("\n", 1)
	_cargo.visible = not _cargo.text.is_empty()
	# Keep the complete cargo string while fitting the existing top-right width.
	_cargo.custom_minimum_size.x = 170
	_cargo.clip_text = true
	_cargo.tooltip_text = text
	var total: float = 0.0
	var done: float = 0.0
	for row: Dictionary in rows:
		if not row.get("optional", false):
			total = float(row.get("total", 0))
			done = float(row.get("done", 0))
			break
	_objective_bar.visible = total > 0.0
	_objective_bar.value = clampf(done / total, 0.0, 1.0) if total > 0.0 else 0.0
