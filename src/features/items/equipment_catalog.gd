class_name EquipmentCatalog
extends Control
## Read-only catalog view. Buttons send intents to the progress-session owner.

signal closed
signal retry_requested

const MASK_ICON: Texture2D = preload("res://assets/ui/m31/filter-mask.svg")

var items: ItemList
var status: Label
var retry_button: Button
var close_button: Button
var _name: Label
var _effect: Label
var _source: Label
var _icon: TextureRect
var _state: Dictionary = {}
var _definitions: Dictionary = BuildItems.definitions(BuildItems.CATALOG_POOL)
var _ids: Array[String] = BuildItems.ids(BuildItems.CATALOG_POOL)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = CampStyle.INK
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CampStyle.box(Color("102530"), Color("48646d"), 22))
	add_child(panel)
	CampStyle.place(panel, Rect2(105, 67, 1070, 586))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(CampStyle.label("蓝时归航   /   驿站档案", 15, CampStyle.TEAL))
	column.add_child(CampStyle.label("装备图鉴", 32))
	column.add_child(CampStyle.label("图鉴记录跨旅程发现。当前库存与实际配装可在营地整备查看。", 17, CampStyle.MUTED))
	var spread: HBoxContainer = HBoxContainer.new()
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spread.add_theme_constant_override("separation", 18)
	column.add_child(spread)
	items = ItemList.new()
	items.custom_minimum_size.x = 286
	items.add_theme_constant_override("v_separation", 12)
	items.fixed_icon_size = Vector2i(25, 25)
	items.item_selected.connect(_select)
	spread.add_child(items)
	var detail: PanelContainer = PanelContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_stylebox_override("panel", CampStyle.box(Color("0c1e28"), Color("355763"), 20))
	spread.add_child(detail)
	var facts: VBoxContainer = VBoxContainer.new()
	facts.add_theme_constant_override("separation", 10)
	detail.add_child(facts)
	_icon = TextureRect.new()
	_icon.texture = MASK_ICON
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(104, 104)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	facts.add_child(_icon)
	_name = CampStyle.label("", 27)
	facts.add_child(_name)
	status = CampStyle.label("", 17, CampStyle.AMBER)
	facts.add_child(status)
	_effect = CampStyle.label("", 19, CampStyle.TEAL)
	facts.add_child(_effect)
	_source = CampStyle.label("", 17, CampStyle.MUTED)
	_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.add_child(_source)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	retry_button = Button.new()
	retry_button.text = "重试读取与同步"
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	actions.add_child(retry_button)
	close_button = Button.new()
	close_button.text = "返回 / Esc"
	close_button.custom_minimum_size = Vector2(140, 42)
	close_button.pressed.connect(func() -> void: closed.emit())
	actions.add_child(close_button)


func present(state: Dictionary) -> void:
	_state = state.duplicate(true)
	items.clear()
	for id: String in _ids:
		items.add_item(_definitions[id].name, MASK_ICON if id == BuildItems.FILTER else null)
	var last: int = _ids.size() - 1
	items.select(last)
	_select(last)
	items.grab_focus()


func _select(index: int) -> void:
	var id: String = _ids[index]
	var mask: bool = id == BuildItems.FILTER
	var available: bool = _state.get("error", FAILED) == OK
	retry_button.visible = not available
	_icon.visible = mask
	_name.text = _definitions[id].name
	_effect.text = _definitions[id].effect
	status.text = "常规道具"
	_source.text = "可在符合条件的装备回收点取得，生还归航并确认后入库。"
	if not mask:
		return
	if not available:
		status.text = "图鉴资料暂不可用"
		_source.text = "已保留进度与来源。可重试同步，已有旅程仍按原规则继续。"
	elif _state.unlock.is_empty():
		status.text = "未解锁"
		_source.text = "单局成功归航至少 2 次并结束旅程。"
	elif _state.discovery.is_empty():
		status.text = "已解锁 · 未发现"
		_source.text = "之后的新旅程可在普通装备行动中回收。"
	else:
		status.text = "已发现 · 已收藏"
		_source.text = "来源 · 普通装备回收。已生还归航并确认入库。\n配装后仅减少毒区周期伤害。"
