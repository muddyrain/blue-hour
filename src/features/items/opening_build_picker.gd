class_name OpeningBuildPicker
extends VBoxContainer
## Title dialog content. The parent confirms the selected plan through the new-run transaction.

const PLAN_ORDER: Array[String] = ["scavenge", "firepower"]
const ACCENTS: Array[Color] = [CampStyle.TEAL, CampStyle.AMBER]

var selected_plan: String = ""
var choices: Dictionary[String, Button] = {}
var _cards: Array[PanelContainer] = []
var _selection: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	add_child(CampStyle.label("出发前选一件小队道具", 25))
	var detail: Label = CampStyle.label("两名队员、基础武器和钱粮相同。确认后保存新旅程，原进度保留为历史。", 15, CampStyle.MUTED)
	add_child(detail)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for index: int in range(PLAN_ORDER.size()):
		var plan_id: String = PLAN_ORDER[index]
		var plan: Dictionary = OpeningBuild.PLANS[plan_id]
		var item: Dictionary = BuildItems.DEFINITIONS[plan.item_id]
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		_cards.append(card)
		var content: VBoxContainer = VBoxContainer.new()
		content.add_theme_constant_override("separation", 6)
		card.add_child(content)
		content.add_child(CampStyle.label("0%d  /  %s" % [index + 1, plan.title], 22, ACCENTS[index]))
		content.add_child(CampStyle.label(item.name, 19))
		content.add_child(CampStyle.label(item.effect, 16, ACCENTS[index]))
		var advice: Label = CampStyle.label(plan.advice, 15, CampStyle.MUTED)
		advice.custom_minimum_size.y = 38
		content.add_child(advice)
		var button: Button = Button.new()
		button.custom_minimum_size.y = 42
		button.pressed.connect(_select.bind(plan_id))
		content.add_child(button)
		choices[plan_id] = button
	_selection = CampStyle.label("", 16)
	add_child(_selection)
	reset_choice()


func reset_choice() -> void:
	_select(PLAN_ORDER[0])


func link_focus(confirm: Button, cancel: Button) -> void:
	var first: Button = choices[PLAN_ORDER[0]]
	var second: Button = choices[PLAN_ORDER[1]]
	first.focus_neighbor_right = first.get_path_to(second)
	second.focus_neighbor_left = second.get_path_to(first)
	var stops: Array[Button] = [first, second, confirm, cancel]
	for index: int in range(stops.size()):
		var button: Button = stops[index]
		button.focus_next = button.get_path_to(stops[(index + 1) % stops.size()])
		button.focus_previous = button.get_path_to(stops[posmod(index - 1, stops.size())])
	first.grab_focus()


func _select(plan_id: String) -> void:
	selected_plan = plan_id
	var plan: Dictionary = OpeningBuild.PLANS[plan_id]
	_selection.text = "已选 %s · %s将配到第一槽" % [plan.title, BuildItems.DEFINITIONS[plan.item_id].name]
	for index: int in range(PLAN_ORDER.size()):
		var id: String = PLAN_ORDER[index]
		var selected: bool = id == plan_id
		var colour: Color = ACCENTS[index] if selected else Color("48646d")
		_cards[index].add_theme_stylebox_override("panel", CampStyle.box(Color("102530"), colour, 14))
		choices[id].text = "已选 · %s" % OpeningBuild.PLANS[id].title if selected else "选择%s" % OpeningBuild.PLANS[id].title
