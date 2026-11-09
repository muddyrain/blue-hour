class_name EventSortiePanel
extends PanelContainer
## Projects the two frozen offers. Expedition owns the lock and the work.

signal choice_confirmed(branch: String)

var generated: Dictionary
var quiet_button: Button
var force_button: Button
var cancel_button: Button


func _ready() -> void:
	CampStyle.place(self, Rect2(150, 270, 550, 200))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var surface: StyleBoxFlat = CampStyle.box(Color("102530"), Color("537981"), 16)
	surface.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", surface)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	add_child(column)
	column.add_child(CampStyle.label(EventSortieV1.TITLE, 27))
	column.add_child(CampStyle.label("已抵达 · 确认后锁定一条路线", 16, CampStyle.MUTED))

	var routes: HBoxContainer = HBoxContainer.new()
	routes.add_theme_constant_override("separation", 10)
	column.add_child(routes)
	quiet_button = _route_button(routes, EventSortieV1.QUIET, CampStyle.TEAL)
	force_button = _route_button(routes, EventSortieV1.FORCE, CampStyle.AMBER)

	var footer: HBoxContainer = HBoxContainer.new()
	column.add_child(footer)
	var time: Label = CampStyle.label("两路基础工时均为 %d 秒" % int(generated.event_sortie.seconds), 16, CampStyle.MUTED)
	time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(time)
	cancel_button = C1HudButton.new()
	cancel_button.text = "取消 / Esc"
	cancel_button.add_theme_font_size_override("font_size", 16)
	cancel_button.pressed.connect(hide)
	footer.add_child(cancel_button)

	var focus_order: Array[Button] = [quiet_button, force_button, cancel_button]
	for index: int in range(focus_order.size()):
		var button: Button = focus_order[index]
		button.focus_next = button.get_path_to(focus_order[(index + 1) % focus_order.size()])
		button.focus_previous = button.get_path_to(focus_order[posmod(index - 1, focus_order.size())])
	quiet_button.focus_neighbor_right = quiet_button.get_path_to(force_button)
	force_button.focus_neighbor_left = force_button.get_path_to(quiet_button)
	quiet_button.focus_neighbor_bottom = quiet_button.get_path_to(cancel_button)
	force_button.focus_neighbor_bottom = force_button.get_path_to(cancel_button)
	cancel_button.focus_neighbor_top = cancel_button.get_path_to(force_button)
	hide()


func present() -> void:
	if is_visible_in_tree():
		return
	show()
	cancel_button.grab_focus()


func _route_button(row: HBoxContainer, branch: String, colour: Color) -> Button:
	var button: Button = C1HudButton.new()
	button.text = branch_title(branch) + "\n" + offer_detail(generated, branch)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 64
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", colour)
	button.pressed.connect(_confirm.bind(branch))
	row.add_child(button)
	return button


func _confirm(branch: String) -> void:
	if not is_visible_in_tree():
		return
	choice_confirmed.emit(branch)


static func branch_title(branch: String) -> String:
	if branch == EventSortieV1.QUIET:
		return "A " + EventSortieV1.QUIET_TITLE
	if branch == EventSortieV1.FORCE:
		return "B " + EventSortieV1.FORCE_TITLE
	return "未确认路线"


static func offer_detail(action: Dictionary, branch: String) -> String:
	var reward: Dictionary = EventSortieV1.reward(action, branch)
	if branch == EventSortieV1.QUIET:
		return "%d 粮 · 无额外增援" % int(reward.food)
	return "%d 币 · 最多 %d 只额外增援" % [int(reward.cash), int(action.event_sortie.requests)]
