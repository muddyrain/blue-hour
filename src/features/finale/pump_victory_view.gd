class_name PumpVictoryView
extends Control
## Read-only presentation. The caller supplies figures from a durable victory.

signal details_requested()
signal record_requested()
signal new_journey_requested()

const BACKGROUND: Color = Color("0c1822")
const PANEL: Color = Color("142531")
const LINE: Color = Color("344b57")
const WHITE: Color = Color("edf2ed")
const MUTED: Color = Color("9eb2bb")
const WARM: Color = Color("e6b47a")
const MINT: Color = Color("94d9c5")

var record_button: Button
var details_button: Button
var new_journey_button: Button

var _brand: Label
var _caption: Label
var _location: Label
var _heading: Label
var _stats: Label
var _objectives: Label
var _durability: Label
var _day: int
var _returned: int
var _art: Rect2
var _panel: Rect2
var _measure: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_brand = _make_label("BLUE HOUR  /  蓝时归航", WARM)
	_caption = _make_label("河堤泵站  /  巴士归航", MUTED)
	_location = _make_label("终局  /  河堤泵站", WARM)
	_heading = _make_label("旅程胜利", WHITE)
	_stats = _make_label("", WHITE)
	_objectives = _make_label("已停机 · 破阵者已击败", MUTED)
	_durability = _make_label("结算已保存", MINT)
	_durability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_button = _make_button("查看归航明细", details_requested)
	record_button = _make_button("查看旅程记录", record_requested, true)
	new_journey_button = _make_button("开始新旅程", new_journey_requested)
	record_button.focus_neighbor_bottom = record_button.get_path_to(details_button)
	details_button.focus_neighbor_top = details_button.get_path_to(record_button)
	details_button.focus_neighbor_right = details_button.get_path_to(new_journey_button)
	new_journey_button.focus_neighbor_left = new_journey_button.get_path_to(details_button)
	new_journey_button.focus_neighbor_top = new_journey_button.get_path_to(record_button)
	resized.connect(_layout)
	_update_stats()
	_layout()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if not _art.has_area():
		return
	var marker: Vector2 = _art.position - Vector2(0, 22.0 * _measure)
	draw_line(marker, marker + Vector2(_art.size.x, 0), LINE, 1.0)
	draw_line(marker, marker + Vector2(39.0 * _measure, 0), WARM, 2.0)
	PumpStationArt.draw_victory(self, _art)
	draw_rect(_art, LINE, false, 1.0)
	draw_rect(_panel, PANEL)
	draw_rect(_panel, LINE, false, 1.0)
	var left: float = _panel.position.x + 26.0 * _measure
	var rule_y: float = _panel.position.y + 194.0 * _measure
	draw_line(Vector2(left, rule_y), Vector2(_panel.end.x - 26.0 * _measure, rule_y), LINE, 1.0)


func present(day: int, returned: int, catalog_notice: String = "") -> void:
	_durability.text = "结算已保存" if catalog_notice.is_empty() else "结算已保存\n" + catalog_notice
	_day = day
	_returned = returned
	_update_stats()
	show()
	_focus_record.call_deferred()


func _focus_record() -> void:
	if is_visible_in_tree() and record_button != null:
		record_button.grab_focus()


func _update_stats() -> void:
	if _stats != null:
		_stats.text = "第 %d 天   /   %d 人归航" % [_day, _returned]


func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_measure = minf(size.x / 1280.0, size.y / 720.0)
	var margin: float = 52.0 * _measure
	var gap: float = 26.0 * _measure
	var panel_width: float = 386.0 * _measure
	var art_room: float = size.x - 2.0 * margin - gap - panel_width
	var art_width: float = minf(art_room, (size.y - 150.0 * _measure)
		* PumpStationArt.VICTORY_SIZE.x / PumpStationArt.VICTORY_SIZE.y)
	var art_height: float = art_width * PumpStationArt.VICTORY_SIZE.y / PumpStationArt.VICTORY_SIZE.x
	var art_x: float = margin + (art_room - art_width) * 0.5
	var panel_height: float = 512.0 * _measure
	_panel = Rect2(size.x - margin - panel_width, (size.y - panel_height) * 0.5, panel_width, panel_height)
	_art = Rect2(art_x, (size.y - art_height) * 0.5, art_width, art_height)
	_place(_brand, Vector2(art_x, _art.position.y - 60.0 * _measure), art_width, 27.0, 18)
	_place(_caption, Vector2(art_x, _art.end.y + 15.0 * _measure), art_width, 24.0, 15)
	var left: float = _panel.position.x + 26.0 * _measure
	var top: float = _panel.position.y
	var inner_width: float = panel_width - 52.0 * _measure
	_place(_location, Vector2(left, top + 27.0 * _measure), inner_width, 24.0, 16)
	_place(_heading, Vector2(left, top + 58.0 * _measure), inner_width, 72.0, 54)
	_place(_stats, Vector2(left, top + 145.0 * _measure), inner_width, 32.0, 24)
	_place(_objectives, Vector2(left, top + 214.0 * _measure), inner_width, 27.0, 19)
	_place(_durability, Vector2(left, top + 249.0 * _measure), inner_width, 112.0, 17)
	_place(record_button, Vector2(left, top + 376.0 * _measure), inner_width, 48.0, 20)
	var button_gap: float = 12.0 * _measure
	var small_width: float = (inner_width - button_gap) * 0.5
	var action_y: float = top + 438.0 * _measure
	_place(details_button, Vector2(left, action_y), small_width, 45.0, 17)
	_place(new_journey_button, Vector2(left + small_width + button_gap, action_y), small_width, 45.0, 17)
	queue_redraw()


func _place(control: Control, point: Vector2, width: float, height: float, font_size: int) -> void:
	control.add_theme_font_size_override("font_size", maxi(11, roundi(font_size * _measure)))
	control.position = point
	control.size = Vector2(width, height * _measure)


func _make_label(value: String, tone: Color) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_color_override("font_color", tone)
	add_child(label)
	return label


func _make_button(value: String, request: Signal, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = value
	if primary:
		var normal: StyleBoxFlat = StyleBoxFlat.new()
		normal.bg_color = Color("294e50")
		normal.border_color = Color("558c85")
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(6)
		button.add_theme_stylebox_override("normal", normal)
	button.pressed.connect(func() -> void: request.emit())
	add_child(button)
	return button
