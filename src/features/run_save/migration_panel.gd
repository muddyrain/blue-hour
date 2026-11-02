class_name MigrationPanel
extends Control
## Explicit, modal preview. No file operation is performed by the view.

signal preview_requested(choice: String)
signal confirmed
signal cancelled

var main_button: Button
var backup_button: Button
var confirm_button: Button
var cancel_button: Button
var body: Label
var status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	var background: Panel = Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", CampStyle.box(Color("07171f"), Color("527b87"), 1))
	add_child(background)
	var column: VBoxContainer = VBoxContainer.new()
	CampStyle.place(column, Rect2(112, 64, 1056, 592))
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var heading: Label = Label.new()
	heading.text = "旧存档转换 · 隔离测试版"
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)
	var choices: HBoxContainer = HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	column.add_child(choices)
	main_button = _button("预览当前主档", choices)
	backup_button = _button("明确选择备份", choices)
	main_button.pressed.connect(func() -> void: preview_requested.emit("MAIN"))
	backup_button.pressed.connect(func() -> void: preview_requested.emit("BACKUP"))
	body = Label.new()
	body.custom_minimum_size.y = 270
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	column.add_child(body)
	status = Label.new()
	status.custom_minimum_size.y = 76
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 18)
	column.add_child(status)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	confirm_button = _button("确认保留原档并转换", actions)
	cancel_button = _button("取消 / Esc", actions)
	confirm_button.pressed.connect(func() -> void: confirmed.emit())
	cancel_button.pressed.connect(func() -> void: cancelled.emit())


func show_preview(value: Dictionary, message: String = "") -> void:
	show()
	confirm_button.disabled = value.get("error") != OK
	confirm_button.text = "确认保留原档并转换"
	if value.get("error") != OK:
		body.text = "未执行转换。\n原主档、备份、声音设置与其它旅程保持。"
		status.text = message
		cancel_button.grab_focus()
		return
	var camp: Dictionary = value.initial
	body.text = "来源：严格 v5 · %s · 哈希 %s\n第%d天 · 货币%d · 食物%d · 武器%d件\n" % ["明确选定备份" if camp.origin.source_choice == "BACKUP" else "当前主档", String(camp.origin.selected_hash).substr(0,12), int(camp.day), int(camp.cash), int(camp.food), camp.weapons.size()]
	for member: Dictionary in camp.crew:
		body.text += "\n%02d %s · 生命 %.1f · 原身份/装备保留" % [int(member.id),member.call_sign,float(member.health)]
	body.text += "\n\n目标：独立 schema102 生存旅程。旧版本不能读取新格式。\n原主档与备份保留；不会扣粮、过日、补血或新增死亡。"
	status.text = "缺粮选人仍未开放；只有确认后才保存副本并创建目标。"
	if value.get("resume", false):
		status.text = "已找到上次明确确认的迁移；重试复用相同身份，不另建旅程。"
	if value.get("completed", false):
		status.text = "此来源已完成转换；只继续新旅程当前进度，不再次导入旧资源。"
		confirm_button.text = "继续已转换旅程"
	confirm_button.grab_focus()


func show_error(message: String, retryable: bool) -> void:
	status.text = message
	confirm_button.text = "重试同一次转换"
	confirm_button.disabled = not retryable


func _button(text: String, parent: Control) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(340, 48)
	button.add_theme_font_size_override("font_size", 20)
	parent.add_child(button)
	return button
