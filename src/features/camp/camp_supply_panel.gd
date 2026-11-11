class_name CampSupplyPanel
extends Control
## Facility quotes are read-only here. CampEdit owns both investments.

signal investment_requested(choice: String, upgrade: bool)
signal retry_requested
signal navigation_requested(action: StringName)

const NAMES: Dictionary[String, String] = {
	"supply": "补给设施",
	"workshop": "工坊",
	"planning": "规划室",
}
const UPGRADES: Dictionary[String, String] = {
	"supply": "扩建补给架",
	"workshop": "校准台",
	"planning": "二级规划室",
}
const EFFECTS: Dictionary[String, String] = {
	"supply": "成功归航应发 2 粮，按营地剩余容量入库。",
	"workshop": "每次维修减免 4 币，最低 1 币。可随出击回收工具箱并改装卡宾枪。",
	"planning": "成功归航后，向最终存活且特长未满的一名队员发放 1 点特长进度。",
}
const UPGRADE_EFFECTS: Dictionary[String, String] = {
	"supply": "升级后出发且成功归航，设施应发从 2 粮增至 3 粮，按营地剩余容量入库。",
	"workshop": "开放普通长管步枪的扩容与快拆方案。每件仅可改装一次，消耗 1 工具箱与 8 币。",
	"planning": "下一次出发后成功归航，向合格队员发放 2 点特长进度。",
}

var build_buttons: Dictionary[String, Button] = {}
var upgrade_buttons: Dictionary[String, Button] = {}
var back_button: Button
var _resources: Label
var _status: Label
var _retry: Button
var _build_status: Dictionary[String, Label] = {}
var _upgrade_status: Dictionary[String, Label] = {}
var _facility_rows: Dictionary[String, Control] = {}
var _ledger: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background: ColorRect = ColorRect.new()
	background.color = CampStyle.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 24)
	add_child(margins)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margins.add_child(column)
	column.add_child(CampStyle.label("蓝时驿站  /  补给与设施", 30))
	_resources = CampStyle.label("", 18, CampStyle.TEAL)
	_resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_resources)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	var routes: HBoxContainer = HBoxContainer.new()
	routes.add_theme_constant_override("separation", 12)
	body.add_child(routes)
	for choice: String in NAMES:
		_build_route(routes, choice)
	_ledger = _wrapped(body, "")
	_status = CampStyle.label("", 16, CampStyle.AMBER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	_retry = _button(body, "重试保存", retry_requested.emit)
	var footer: HBoxContainer = HBoxContainer.new()
	column.add_child(footer)
	back_button = _button(footer, "返回营地 / Esc", navigation_requested.emit.bind(&"camp"))
	_button(footer, "队员", navigation_requested.emit.bind(&"crew"))
	_button(footer, "装备仓", navigation_requested.emit.bind(&"weapons"))
	_button(footer, "工坊", navigation_requested.emit.bind(&"workshop"))
	_button(footer, "巴士", navigation_requested.emit.bind(&"bus"))


func refresh(camp: Dictionary, rations: Dictionary, feedback: String, pending: bool) -> void:
	var remaining: int = int(camp.food) - int(rations.required)
	var balance: String = "餐后余粮 %d" % remaining if remaining >= 0 else "口粮缺口 %d" % -remaining
	_resources.text = "第 %d 天  ·  口粮 %d / 所需 %d  ·  %s  ·  货币 %d  ·  工具箱 %d" % [
		camp.day, camp.food, rations.required, balance, camp.cash, WorkshopV1.tools(camp)]
	var current: String = CampFacilities.selected(camp)
	for choice: String in NAMES:
		_facility_rows[choice].visible = choice != "planning" or EconomyBuildV1.enabled(camp)
		if EconomyBuildV1.enabled(camp):
			var build_offer: Dictionary = EconomyBuildV1.offer(camp, "build", choice)
			var upgrade_offer: Dictionary = EconomyBuildV1.offer(camp, "upgrade_facility", choice)
			var level: int = EconomyBuildV1.level(camp, choice)
			_build_status[choice].text = "%s · %s" % ["未建" if level == 0 else "%d 级" % level,
				build_offer.summary if build_offer.available else build_offer.reason]
			build_buttons[choice].disabled = pending or not build_offer.available
			build_buttons[choice].text = "建设 · %d 币 + %d 工具" % [build_offer.cost, build_offer.tools]
			upgrade_buttons[choice].disabled = pending or not upgrade_offer.available
			upgrade_buttons[choice].text = "升级 · %d 币 + %d 工具" % [upgrade_offer.cost, upgrade_offer.tools]
			_upgrade_status[choice].text = upgrade_offer.summary if upgrade_offer.available else upgrade_offer.reason
			continue
		var build: Button = build_buttons[choice]
		build.disabled = pending or not CampFacilities.can_build(camp, choice)
		if not current.is_empty():
			_build_status[choice].text = "已建成" if current == choice else "已选择另一条建设路线"
		elif not CampFacilities.enabled(camp):
			_build_status[choice].text = "此旅程未开放设施"
		elif not camp.last_day.get("evacuated", false):
			_build_status[choice].text = "先成功归航并确认结算"
		else:
			_build_status[choice].text = "一次旅程只能选择一条路线"
		var offer: Dictionary = CampFacilities.upgrade_offer(camp, choice)
		upgrade_buttons[choice].disabled = pending or not offer.available
		_upgrade_status[choice].text = "可以升级" if offer.available else offer.reason
	_status.text = feedback
	_retry.visible = pending
	_ledger.text = "设施按出发前状态结算；建设和升级不会补发已完成的归航。"
	if EconomyBuildV1.enabled(camp):
		_ledger.text += "\n" + EconomyBuildV1.ledger_text(camp)


func _build_route(parent: Container, choice: String) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL))
	parent.add_child(panel)
	_facility_rows[choice] = panel
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	column.add_child(CampStyle.label(NAMES[choice], 24))
	_wrapped(column, EFFECTS[choice])
	_build_status[choice] = _wrapped(column, "")
	build_buttons[choice] = _button(column, "预览建设 · %d 币" % CampFacilities.BUILD_COST,
		investment_requested.emit.bind(choice, false))
	column.add_child(HSeparator.new())
	column.add_child(CampStyle.label(UPGRADES[choice], 22))
	_wrapped(column, UPGRADE_EFFECTS[choice])
	_upgrade_status[choice] = _wrapped(column, "")
	upgrade_buttons[choice] = _button(column, "预览升级 · %d 币" % CampFacilities.UPGRADE_COST,
		investment_requested.emit.bind(choice, true))


func _wrapped(parent: Container, caption: String) -> Label:
	var label: Label = CampStyle.label(caption, 17, CampStyle.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(parent: Container, caption: String, pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.custom_minimum_size.y = 42
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button
