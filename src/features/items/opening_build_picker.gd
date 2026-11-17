class_name OpeningBuildPicker
extends VBoxContainer
## Read-only specialty selection inside the existing explicit new-run confirmation.

const PLAN_ORDER: Array[String] = SpecialtyPresentation.PLANS
const ITEMS: Texture2D = preload("res://assets/menu_pixel/specialties.png")
var selected_plan: String = ""
var choices: Dictionary[String, Button] = {}
var _availability: Dictionary[String, String] = {}
var _selection: Label
var _access: Label
var _marks: Dictionary[String, Label] = {}


func _ready() -> void:
	size = Vector2(1080, 520)
	add_theme_constant_override("separation", 12)
	PixelMenu.masthead(self, "选择旅程专精", CampStyle.label("新旅程", 19, CampStyle.MUTED))
	var detail: Label = CampStyle.label("两名队员，基础武器与钱粮相同。选择一种专精，带上它的开局装备。", 17, CampStyle.MUTED)
	detail.size.x = 1080
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(detail)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	for index: int in range(PLAN_ORDER.size()):
		var id: String = PLAN_ORDER[index]
		var plan: Dictionary = OpeningBuild.PLANS[id]
		var item: Dictionary = SpecialtyPresentation.definition(plan.item_id)
		var button: Button = Button.new()
		button.name = id.capitalize() + "Specialty"
		button.custom_minimum_size = Vector2(304, 362)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select.bind(id))
		button.tooltip_text = plan.title + " · " + item.name + "\n" + item.effect + "\n" + plan.advice
		row.add_child(button)
		choices[id] = button
		var margin: MarginContainer = MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 16)
		var content: VBoxContainer = VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 8)
		margin.add_child(content)
		var heading: HBoxContainer = HBoxContainer.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(heading)
		var title: Label = CampStyle.label(plan.title, 27)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		var mark: Label = CampStyle.label("", 17, CampStyle.TEAL)
		heading.add_child(mark)
		_marks[id] = mark
		var art: TextureRect = TextureRect.new()
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = ITEMS
		var width: float = ITEMS.get_width() / 3.0
		atlas.region = Rect2(index * width, 0, width, ITEMS.get_height())
		atlas.filter_clip = true
		art.texture = atlas
		art.custom_minimum_size.y = 126
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(art)
		content.add_child(CampStyle.label(item.name, 21))
		var effect: Label = CampStyle.label(item.effect, 18, CampStyle.TEAL)
		effect.size.x = 300
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.custom_minimum_size.y = 50
		content.add_child(effect)
		PixelMenu.divider(content)
		var advice: Label = CampStyle.label(plan.advice, 17, CampStyle.MUTED)
		advice.size.x = 300
		advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(advice)
	_selection = CampStyle.label("", 19)
	add_child(_selection)
	_access = CampStyle.label("", 15, CampStyle.MUTED)
	_access.size.x = 1080
	_access.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_access)
	reset_choice()


func present(catalog: Dictionary) -> void:
	for id: String in PLAN_ORDER:
		_availability[id] = SpecialtyPresentation.access_text(CatalogProgress.eligible_for(catalog, id)) if catalog.get("error", FAILED) == OK else "专精资料待同步"
	_select(selected_plan if not selected_plan.is_empty() else PLAN_ORDER[0])


func reset_choice() -> void:
	_select(PLAN_ORDER[0])


func link_focus(confirm: Button, cancel: Button) -> void:
	var stops: Array[Button] = []
	for id: String in PLAN_ORDER:
		stops.append(choices[id])
	stops.append_array([confirm, cancel])
	for index: int in range(stops.size()):
		var button: Button = stops[index]
		button.focus_next = button.get_path_to(stops[(index + 1) % stops.size()])
		button.focus_previous = button.get_path_to(stops[posmod(index - 1, stops.size())])
		button.focus_neighbor_right = button.focus_next
		button.focus_neighbor_left = button.focus_previous
		if index < PLAN_ORDER.size():
			button.focus_neighbor_bottom = button.get_path_to(confirm)
	stops[0].grab_focus()


func _select(plan_id: String) -> void:
	selected_plan = plan_id
	var plan: Dictionary = OpeningBuild.PLANS[plan_id]
	if _selection != null:
		_selection.text = "%s · %s将配到第一槽" % [plan.title, SpecialtyPresentation.reward_name(plan.item_id)]
		_access.text = _availability.get(plan_id, "") + "。确认后保存新旅程，原进度保留为历史。"
	for id: String in choices:
		var selected: bool = id == plan_id
		var button: Button = choices[id]
		button.add_theme_stylebox_override("normal", CampStyle.box(CampStyle.PANEL if selected else CampStyle.INK, CampStyle.TEAL if selected else CampStyle.EDGE, 0))
		button.add_theme_stylebox_override("hover", CampStyle.box(CampStyle.PANEL.lightened(0.05), CampStyle.TEAL, 0))
		button.add_theme_stylebox_override("pressed", CampStyle.box(CampStyle.PANEL, CampStyle.TEAL, 0))
		button.add_theme_stylebox_override("focus", CampStyle.box(Color.TRANSPARENT, CampStyle.TEXT, 0))
		_marks[id].text = "已选择" if selected else "选择"
