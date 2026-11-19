class_name CampSupplyPanel
extends Control
## Facility quotes are read-only here. CampEdit owns both investments.

signal investment_requested(choice: String, upgrade: bool)
signal retry_requested
signal navigation_requested(action: StringName)

const NAMES: Dictionary[String, String] = {"supply": "补给设施", "workshop": "工坊", "planning": "规划室"}
const UPGRADES: Dictionary[String, String] = {"supply": "扩建补给架", "workshop": "校准台", "planning": "二级规划室"}
const EFFECTS: Dictionary[String, String] = {
	"supply": "每带回 2 粮加工出 1 粮，每趟最多加 1 粮。",
	"workshop": "每次维修减免 4 币，最低 1 币。可随出击回收工具箱并改装卡宾枪。",
	"planning": "成功归航后，向最终存活且特长未满的一名队员发放 1 点特长进度。",
}
const UPGRADE_EFFECTS: Dictionary[String, String] = {
	"supply": "每带回 2 粮加工出 1 粮，每趟最多加 2 粮。加工所得按剩余容量入库。",
	"workshop": "开放普通长管步枪的扩容与快拆方案。每件仅可改装一次，消耗 1 工具箱与 8 币。",
	"planning": "下一次出发后成功归航，向合格队员发放 2 点特长进度。",
}

var build_buttons: Dictionary[String, Button] = {}
var upgrade_buttons: Dictionary[String, Button] = {}
var back_button: Button
var _sheet: PixelSheet
var _resources: Label
var _status: Label
var _retry: Button
var _build_status: Dictionary[String, Label] = {}
var _upgrade_status: Dictionary[String, Label] = {}
var _facility_rows: Dictionary[String, Control] = {}
var _effects: Dictionary[String, Label] = {}
var _upgrade_effects: Dictionary[String, Label] = {}
var _costs: Dictionary[String, Label] = {}
var _levels: Dictionary[String, Label] = {}
var _reasons: Dictionary[String, Label] = {}
var _ledger: Label
var _tool_status: Label
var _camp: Dictionary = {}
var _pending: bool = false
var _detail_choice: String = ""
var _details: Control
var _detail_title: Label
var _detail_image: TextureRect
var _detail_text: Label
var _detail_action: Button
var _detail_back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet = PixelSheet.new()
	_sheet.page_title = "补给与设施"
	_sheet.active_tab = &"supplies"
	add_child(_sheet)
	_sheet.navigation_requested.connect(navigation_requested.emit)
	_sheet.closed.connect(navigation_requested.emit.bind(&"camp"))
	back_button = _sheet.back_button
	_resources = PixelSheet.label(_sheet.body, "", Rect2(24, 8, 784, 48), 28)
	_tool_status = PixelSheet.label(_sheet.body, "", Rect2(816, 8, 264, 48), 28, CampStyle.DANGER)
	_tool_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	PixelSheet.line(_sheet.body, Rect2(16, 62, 1072, 1))
	var index: int = 0
	for choice: String in NAMES:
		_build_route(choice, index)
		index += 1
	_status = PixelSheet.label(_sheet.body, "", Rect2(16, 546, 1072, 30), 18, CampStyle.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_retry = _button(_sheet.body, "重试保存", Rect2(924, 540, 164, 36), retry_requested.emit, 20)
	_retry.hide()
	_build_details()


func refresh(camp: Dictionary, rations: Dictionary, feedback: String, pending: bool) -> void:
	_camp = camp.duplicate(true)
	_pending = pending
	_sheet.update_resources(camp)
	var remaining: int = int(camp.food) - int(rations.required)
	var balance: String = "餐后余粮 %d" % remaining if remaining >= 0 else "口粮缺口 %d" % -remaining
	_resources.tooltip_text = "口粮 %d / 下餐需 %d · %s" % [camp.food, rations.required, balance]
	_resources.text = "选择设施，为下次出击做准备。"
	if camp.get("last_day", {}).get("evacuated") != true:
		_resources.text = "先完成一次成功归航并确认，才可建设。"
	_tool_status.text = "工具箱不足。" if WorkshopV1.tools(camp) == 0 else ""
	var current: String = CampFacilities.selected(camp)
	for choice: String in NAMES:
		_facility_rows[choice].visible = choice != "planning" or EconomyBuildV1.enabled(camp)
		var build: Button = build_buttons[choice]
		var upgrade: Button = upgrade_buttons[choice]
		if EconomyBuildV1.enabled(camp):
			var level: int = EconomyBuildV1.level(camp, choice)
			var build_offer: Dictionary = EconomyBuildV1.offer(camp, "build", choice)
			var upgrade_offer: Dictionary = EconomyBuildV1.offer(camp, "upgrade_facility", choice)
			var active_offer: Dictionary = build_offer if level == 0 else upgrade_offer
			_effects[choice].text = _short_effect(choice, maxi(1, level))
			_effects[choice].tooltip_text = EconomyBuildV1.facility_effect(choice, maxi(1, level))
			_upgrade_effects[choice].text = EconomyBuildV1.facility_effect(choice, 2)
			_build_status[choice].text = build_offer.summary if build_offer.available else build_offer.reason
			_upgrade_status[choice].text = upgrade_offer.summary if upgrade_offer.available else upgrade_offer.reason
			_levels[choice].text = "未建设" if level == 0 else "已建 Lv%d" % level
			_costs[choice].text = "%d 币 +\n%d 工具箱" % [active_offer.cost, active_offer.tools]
			build.disabled = pending or not build_offer.available
			build.visible = level == 0
			build.text = "建设"
			build.tooltip_text = _build_status[choice].text
			upgrade.disabled = pending or not upgrade_offer.available
			upgrade.visible = level > 0
			upgrade.text = "升级" if level < 2 else "已达上限"
			upgrade.tooltip_text = _upgrade_status[choice].text
			var reason: String = "保存待确认" if pending else str(active_offer.reason)
			_reasons[choice].text = "" if active_offer.available or reason == "先完成一次成功归航并确认" else (reason if reason.length() <= 10 else reason.left(9) + "…")
			_reasons[choice].tooltip_text = reason
			if level >= 2:
				_costs[choice].text = "二级设施\n已全部开放"
				_reasons[choice].text = ""
			continue
		var selected: bool = current == choice
		build.disabled = pending or not CampFacilities.can_build(camp, choice)
		build.visible = not selected
		if not current.is_empty():
			_build_status[choice].text = "已建成" if selected else "已选择另一条建设路线"
		elif not CampFacilities.enabled(camp):
			_build_status[choice].text = "此旅程未开放设施"
		elif not camp.last_day.get("evacuated", false):
			_build_status[choice].text = "先成功归航并确认结算"
		else:
			_build_status[choice].text = "一次旅程只能选择一条路线"
		var offer: Dictionary = CampFacilities.upgrade_offer(camp, choice)
		upgrade.disabled = pending or not offer.available
		upgrade.visible = selected
		_upgrade_status[choice].text = "可以升级" if offer.available else offer.reason
		_levels[choice].text = "已建设" if selected else "未建设"
		_costs[choice].text = "%d 币" % (CampFacilities.UPGRADE_COST if selected else CampFacilities.BUILD_COST)
		build.tooltip_text = _build_status[choice].text
		upgrade.tooltip_text = _upgrade_status[choice].text
		_effects[choice].text = EFFECTS[choice]
		_upgrade_effects[choice].text = UPGRADE_EFFECTS[choice]
	_status.text = feedback
	_status.size.x = 884 if pending else 1072
	_retry.visible = pending
	_ledger.text = "设施按出发前状态结算；建设和升级不会补发已完成的归航。"
	if EconomyBuildV1.enabled(camp):
		_ledger.text += "\n" + EconomyBuildV1.ledger_text(camp)
	if not _detail_choice.is_empty():
		_show_details(_detail_choice)


func _build_route(choice: String, index: int) -> void:
	var row: Control = Control.new()
	_sheet.body.add_child(row)
	PixelSheet.place(row, Rect2(16, 76 + index * 156, 1072, 146))
	_facility_rows[choice] = row
	var image: TextureRect = PixelSheet.art(row, PixelSheet.facility_texture(index), Rect2(0, 0, 330, 140))
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.clip_contents = true
	PixelSheet.label(row, NAMES[choice], Rect2(352, -2, 292, 40), 28)
	_effects[choice] = PixelSheet.label(row, "", Rect2(352, 40, 292, 64), 22)
	_effects[choice].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effects[choice].add_theme_constant_override("line_spacing", 0)
	var detail_button: Button = _button(row, "详情与升级 →", Rect2(352, 112, 292, 32), _show_details.bind(choice), 21)
	detail_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var colour: Color = CampStyle.SELECTED if state == "hover" else CampStyle.PANEL if state == "pressed" else CampStyle.SURFACE
		var style: StyleBoxFlat = CampStyle.box(colour, Color.TRANSPARENT, 0)
		style.content_margin_left = 8
		style.content_margin_right = 8
		detail_button.add_theme_stylebox_override(state, style)
	PixelSheet.line(row, Rect2(664, 6, 1, 128))
	PixelSheet.label(row, "费用：", Rect2(688, 0, 140, 34), 20)
	_costs[choice] = PixelSheet.label(row, "", Rect2(688, 35, 150, 90), 23)
	_levels[choice] = PixelSheet.label(row, "", Rect2(858, 2, 196, 40), 24, CampStyle.TEAL)
	_levels[choice].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_buttons[choice] = _button(row, "建设", Rect2(848, 62, 208, 60), investment_requested.emit.bind(choice, false), 30)
	upgrade_buttons[choice] = _button(row, "升级", Rect2(848, 62, 208, 60), investment_requested.emit.bind(choice, true), 30)
	_reasons[choice] = PixelSheet.label(row, "", Rect2(848, 122, 208, 22), 18, CampStyle.MUTED)
	_reasons[choice].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PixelSheet.line(_sheet.body, Rect2(16, 224 + index * 156, 1072, 1))
	# Full quotations remain separately available to the detail view and tooltips.
	_build_status[choice] = Label.new()
	_upgrade_status[choice] = Label.new()
	_upgrade_effects[choice] = Label.new()
	for label: Label in [_build_status[choice], _upgrade_status[choice], _upgrade_effects[choice]]:
		row.add_child(label)
		label.hide()


func _build_details() -> void:
	_details = Control.new()
	_sheet.body.add_child(_details)
	PixelSheet.place(_details, Rect2(0, 0, 1104, 584))
	_details.mouse_filter = Control.MOUSE_FILTER_STOP
	PixelSheet.panel(_details, Rect2(0, 0, 1104, 584), CampStyle.INK)
	_detail_title = PixelSheet.label(_details, "", Rect2(24, 12, 728, 52), 36)
	_detail_back = PixelSheet.button(_details, "返回设施", Rect2(892, 16, 188, 44), 22)
	_detail_back.pressed.connect(func() -> void:
		_details.hide()
		_detail_choice = "")
	PixelSheet.line(_details, Rect2(24, 76, 1056, 1))
	_detail_image = PixelSheet.art(_details, null, Rect2(24, 96, 384, 172))
	_detail_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_detail_image.clip_contents = true
	var ledger_scroll: ScrollContainer = ScrollContainer.new()
	ledger_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details.add_child(ledger_scroll)
	PixelSheet.place(ledger_scroll, Rect2(24, 286, 384, 270))
	_ledger = CampStyle.label("", 20, CampStyle.MUTED)
	_ledger.custom_minimum_size.x = 362
	_ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ledger_scroll.add_child(_ledger)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details.add_child(scroll)
	PixelSheet.place(scroll, Rect2(440, 96, 640, 382))
	_detail_text = CampStyle.label("", 22)
	_detail_text.custom_minimum_size.x = 616
	_detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_detail_text)
	_detail_action = _button(_details, "", Rect2(720, 508, 360, 60), _request_detail, 27)
	PixelMenu.primary(_detail_action)
	_details.hide()


func _show_details(choice: String) -> void:
	if _camp.is_empty():
		return
	_detail_choice = choice
	_detail_title.text = NAMES[choice] + " · 设施详情"
	_detail_image.texture = PixelSheet.facility_texture(NAMES.keys().find(choice))
	var built: bool = EconomyBuildV1.level(_camp, choice) > 0 if EconomyBuildV1.enabled(_camp) else CampFacilities.selected(_camp) == choice
	var full_effect: String = EconomyBuildV1.facility_effect(choice, maxi(1, EconomyBuildV1.level(_camp, choice))) if EconomyBuildV1.enabled(_camp) else EFFECTS[choice]
	_detail_text.text = "当前 / 一级效果\n%s\n\n二级升级\n%s\n\n%s" % [full_effect, _upgrade_effects[choice].text, _upgrade_status[choice].text if built else _build_status[choice].text]
	_detail_action.disabled = upgrade_buttons[choice].disabled if built else build_buttons[choice].disabled
	_detail_action.text = "预览升级 →" if built else "预览建设 →"
	_details.show()
	_detail_back.grab_focus.call_deferred()


func _request_detail() -> void:
	if _detail_choice.is_empty() or _pending or _detail_action.disabled:
		return
	var built: bool = EconomyBuildV1.level(_camp, _detail_choice) > 0 if EconomyBuildV1.enabled(_camp) else CampFacilities.selected(_camp) == _detail_choice
	investment_requested.emit(_detail_choice, built)


func _short_effect(choice: String, level: int) -> String:
	match choice:
		"supply":
			return "每带回 2 粮加工 1 粮\n每趟最多加 %d 粮" % level
		"workshop":
			return "全队换弹耗时 −%d%%。\n每次维修减免 %d 币。" % [level * 5, 4 if level == 1 else 6]
		"planning":
			return "成功归航后，合格队员\n特性进度 +%d。" % level
	return ""


func _button(parent: Node, caption: String, bounds: Rect2, pressed: Callable, font: int = 24) -> Button:
	var button: Button = PixelSheet.button(parent, caption, bounds, font)
	button.pressed.connect(pressed)
	return button
