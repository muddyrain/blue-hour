class_name OpeningBuildPicker
extends VBoxContainer
## Title dialog content. The parent confirms the selected plan through the new-run transaction.

const PLAN_ORDER: Array[String] = SpecialtyPresentation.PLANS
const ACCENTS: Array[Color] = [CampStyle.TEAL, CampStyle.AMBER, Color("b9c6e9")]

var selected_plan: String = ""
var choices: Dictionary[String, Button] = {}
var _cards: Array[PanelContainer] = []
var _availability: Dictionary[String, Label] = {}
var _selection: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	add_child(CampStyle.label("选择本次旅程的专精", 28))
	var detail: Label = CampStyle.label("两名队员、基础武器和钱粮相同。确认后保存新旅程，原进度保留为历史。", 15, CampStyle.MUTED)
	add_child(detail)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for index: int in range(PLAN_ORDER.size()):
		var plan_id: String = PLAN_ORDER[index]
		var plan: Dictionary = OpeningBuild.PLANS[plan_id]
		var item: Dictionary = SpecialtyPresentation.definition(plan.item_id)
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size.x = 274
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		_cards.append(card)
		var content: VBoxContainer = VBoxContainer.new()
		content.add_theme_constant_override("separation", 6)
		card.add_child(content)
		content.add_child(CampStyle.label("0%d  /  %s" % [index + 1, plan.title], 22, ACCENTS[index]))
		content.add_child(CampStyle.label(item.name, 19))
		var effect: Label = CampStyle.label(item.effect, 16, ACCENTS[index])
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.custom_maximum_size.x = 246
		effect.custom_minimum_size.y = 44
		content.add_child(effect)
		var advice: Label = CampStyle.label(plan.advice, 15, CampStyle.MUTED)
		advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		advice.custom_maximum_size.x = 246
		advice.custom_minimum_size.y = 44
		content.add_child(advice)
		content.add_child(HSeparator.new())
		var available: Label = CampStyle.label("", 15, CampStyle.MUTED)
		available.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		available.custom_maximum_size.x = 246
		available.custom_minimum_size.y = 50
		content.add_child(available)
		_availability[plan_id] = available
		var button: Button = Button.new()
		button.custom_minimum_size.y = 42
		button.pressed.connect(_select.bind(plan_id))
		content.add_child(button)
		choices[plan_id] = button
	_selection = CampStyle.label("", 16)
	add_child(_selection)
	reset_choice()


func present(catalog: Dictionary) -> void:
	for id: String in PLAN_ORDER:
		if catalog.get("error", FAILED) == OK:
			_availability[id].text = SpecialtyPresentation.access_text(CatalogProgress.eligible_for(catalog, id))
		else:
			_availability[id].text = "专精资料待同步"


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
	_selection.text = "已选 %s · %s将配到第一槽" % [plan.title, SpecialtyPresentation.reward_name(plan.item_id)]
	for index: int in range(PLAN_ORDER.size()):
		var id: String = PLAN_ORDER[index]
		var selected: bool = id == plan_id
		var colour: Color = ACCENTS[index] if selected else Color("48646d")
		_cards[index].add_theme_stylebox_override("panel", CampStyle.box(Color("102530"), colour, 14))
		choices[id].text = "已选 · %s" % OpeningBuild.PLANS[id].title if selected else "选择%s" % OpeningBuild.PLANS[id].title
