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
	accent.custom_minimum_size.x = 1
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
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	var stock_title: Label = hud._label(row, "StockTitle", 14)
	stock_title.text = "营地库存"
	stock_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for index: int in range(2):
		var chip: HBoxContainer = HBoxContainer.new()
		chip.name = "ResourceChip%d" % index
		chip.add_theme_constant_override("separation", 6)
		row.add_child(chip)
		var icon: TextureRect = TextureRect.new()
		icon.texture = load(["res://assets/camp_pixel/food.svg", "res://assets/camp_pixel/cash.svg"][index]) as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(22, 22)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		var label: Label = hud._label(chip, "Value", 20)
		_chips.append(label)
	_cargo = hud._label(column, "CarriedResources", 18)
	_cargo.add_theme_color_override("font_color", ExpeditionHudTheme.CREAM)
	_cargo.clip_text = true
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh(hud: C1ExpeditionHud, rows: Array[Dictionary], _state: Dictionary) -> void:
	var text: String = hud._currency.text
	var stock: String = text.get_slice("\n", 0)
	for index: int in range(_chips.size()):
		var key: String = ["食物", "货币"][index]
		var expression: RegEx = RegEx.new()
		expression.compile(key + "\\s*(\\d+)")
		var found: RegExMatch = expression.search(stock)
		_chips[index].text = key + " " + (found.get_string(1) if found != null else "—")
		_chips[index].tooltip_text = "营地库存 · " + key
	_cargo.text = text.get_slice("\n", 1).replace("携带：", "本次携带 · ")
	_cargo.visible = not _cargo.text.is_empty()
	_cargo.add_theme_color_override("font_color", ExpeditionHudTheme.CREAM)
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
