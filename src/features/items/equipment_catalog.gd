class_name EquipmentCatalog
extends Control
## Read-only archive. Inventory grants and specialty updates remain session-owned.

signal closed
signal retry_requested
signal navigation_requested(action: StringName)

const MASK_ICON: Texture2D = preload("res://assets/ui/m31/filter-mask.svg")
const PLAN_ART: Texture2D = preload("res://assets/menu_pixel/specialties.png")

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
var _sheet: PixelSheet
var _specialty_tab: Button
var _item_tab: Button
var _equipment_mode: bool = false
var _progress: ProgressBar
var _progress_text: Label
var _milestone_one: Label
var _milestone_two: Label
var _heading: Label
var _footnote: Label
var _armory_button: Button
var _plan_buttons: Array[Button] = []
var _plan_xp: Array[Label] = []
var _plan_separators: Array[ColorRect] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet = PixelSheet.new()
	_sheet.page_title = "专精与图鉴"
	_sheet.active_tab = &"catalog"
	add_child(_sheet)
	_sheet.closed.connect(closed.emit)
	_sheet.navigation_requested.connect(navigation_requested.emit)
	var body: Control = _sheet.body
	_specialty_tab = PixelSheet.button(body, "专精进度", Rect2(16, 12, 174, 44), 27)
	_item_tab = PixelSheet.button(body, "装备图鉴", Rect2(194, 12, 174, 44), 27)
	_specialty_tab.pressed.connect(_show_items.bind(false))
	_item_tab.pressed.connect(_show_items.bind(true))
	PixelSheet.line(body, Rect2(16, 68, 352, 1))
	PixelSheet.line(body, Rect2(384, 12, 1, 552))
	items = ItemList.new()
	items.add_theme_font_override("font", CampStyle.BOLD_FONT)
	items.add_theme_font_size_override("font_size", 28)
	items.add_theme_constant_override("v_separation", 12)
	items.add_theme_constant_override("h_separation", 18)
	items.add_theme_constant_override("icon_margin", 24)
	items.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.INK, Color.TRANSPARENT, 0))
	items.fixed_icon_size = Vector2i(120, 120)
	items.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	items.item_selected.connect(_select)
	body.add_child(items)
	PixelSheet.place(items, Rect2(16, 88, 352, 468))
	for index: int in SpecialtyPresentation.PLANS.size():
		var plan_button: Button = PixelSheet.button(body, "", Rect2(16, 88 + index * 148, 352, 136))
		PixelSheet.art(plan_button, _plan_art(index), Rect2(20, 10, 122, 116))
		PixelSheet.label(plan_button, OpeningBuild.PLANS[SpecialtyPresentation.PLANS[index]].title, Rect2(160, 20, 184, 44), 31)
		_plan_xp.append(PixelSheet.label(plan_button, "", Rect2(160, 70, 184, 42), 29))
		plan_button.pressed.connect(_select.bind(index))
		_plan_buttons.append(plan_button)
		_plan_separators.append(PixelSheet.line(body, Rect2(16, 232 + index * 148, 352, 1)))
	_icon = PixelSheet.art(body, null, Rect2(416, 32, 278, 184))
	PixelSheet.line(body, Rect2(716, 44, 1, 144))
	_name = PixelSheet.label(body, "", Rect2(740, 28, 348, 58), 36)
	status = PixelSheet.label(body, "", Rect2(740, 92, 348, 76), 22)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect = PixelSheet.label(body, "", Rect2(740, 164, 348, 64), 22)
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading = PixelSheet.label(body, "专精进度", Rect2(416, 236, 400, 42), 28)
	_progress_text = PixelSheet.label(body, "", Rect2(894, 236, 194, 42), 28)
	_progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	body.add_child(_progress)
	PixelSheet.place(_progress, Rect2(416, 284, 672, 20))
	_milestone_one = PixelSheet.label(body, "2 XP · 后续同专精旅程可回收", Rect2(432, 316, 656, 42), 26)
	_milestone_two = PixelSheet.label(body, "4 XP · 所有专精共享", Rect2(432, 360, 656, 42), 26)
	PixelSheet.line(body, Rect2(416, 412, 672, 1))
	_source = PixelSheet.label(body, "", Rect2(416, 426, 672, 72), 20)
	_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_footnote = PixelSheet.label(body, "解锁扩大后续装备池，不会立即获得物品。", Rect2(416, 487, 672, 28), 19, CampStyle.MUTED)
	var armory: Button = PixelSheet.button(body, "前往装备仓", Rect2(590, 524, 236, 52), 28)
	_armory_button = armory
	armory.pressed.connect(navigation_requested.emit.bind(&"weapons"))
	close_button = PixelSheet.button(body, "返回营地", Rect2(850, 524, 238, 52), 28)
	close_button.pressed.connect(closed.emit)
	retry_button = PixelSheet.button(body, "重试读取与同步", Rect2(416, 524, 284, 52), 22)
	retry_button.pressed.connect(retry_requested.emit)
	retry_button.hide()


func set_resources(data: Dictionary, in_camp: bool = true) -> void:
	_sheet.update_resources(data)
	_armory_button.disabled = not in_camp
	close_button.text = "返回营地" if in_camp else "返回"
	_sheet.back_button.text = "营地 / Esc" if in_camp else "返回 / Esc"
	for action: StringName in _sheet.tab_buttons:
		_sheet.tab_buttons[action].disabled = not in_camp and action != &"catalog"


func present(state: Dictionary) -> void:
	_state = state.duplicate(true)
	_show_items(_equipment_mode)
	if _equipment_mode: items.grab_focus()
	else: _plan_buttons[0].grab_focus()


func _show_items(equipment: bool) -> void:
	_equipment_mode = equipment
	PixelMenu.tab(_specialty_tab, not equipment)
	PixelMenu.tab(_item_tab, equipment)
	items.clear()
	items.visible = equipment
	for plan_button: Button in _plan_buttons: plan_button.visible = not equipment
	for separator: ColorRect in _plan_separators: separator.visible = not equipment
	items.fixed_icon_size = Vector2i(72, 72) if equipment else Vector2i(120, 120)
	items.add_theme_font_size_override("font_size", 23 if equipment else 28)
	if equipment:
		for id: String in _ids:
			items.add_item(_definitions[id].name, _item_art(id))
	else:
		for index: int in SpecialtyPresentation.PLANS.size():
			var plan: String = SpecialtyPresentation.PLANS[index]
			var xp: String = str(_state.get("specialties", {}).get(plan, 0)) if _state.get("error", FAILED) == OK else "—"
			_plan_xp[index].text = xp + " XP"
	if equipment: items.select(0)
	_select(0)


func _select(index: int) -> void:
	var available: bool = _state.get("error", FAILED) == OK
	retry_button.visible = not available
	_progress.visible = not _equipment_mode
	_progress_text.visible = not _equipment_mode
	_milestone_one.visible = not _equipment_mode
	_milestone_two.visible = not _equipment_mode
	_footnote.visible = not _equipment_mode
	if not _equipment_mode:
		for i: int in _plan_buttons.size():
			var style: StyleBoxFlat = CampStyle.box(CampStyle.SELECTED if i == index else Color.TRANSPARENT, CampStyle.EDGE if i == index else Color.TRANSPARENT, 0)
			_plan_buttons[i].add_theme_stylebox_override("normal", style)
		_select_specialty(SpecialtyPresentation.PLANS[index], available)
		return
	var id: String = _ids[index]
	_icon.texture = _item_art(id)
	_icon.show()
	_name.text = _definitions[id].name
	_effect.text = _definitions[id].effect
	status.text = "常规道具"
	_heading.text = "回收与收藏"
	_source.position.y = 302
	_source.size.y = 178
	_source.text = "可在符合条件的装备回收点取得，生还归航并确认后入库。\n\n图鉴用于查阅，当前库存与配装请前往装备仓。"
	if id != BuildItems.FILTER:
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


func _select_specialty(plan_id: String, available: bool) -> void:
	var plan: Dictionary = OpeningBuild.PLANS[plan_id]
	var id: String = plan.unlock_id
	_icon.show()
	_icon.texture = PixelSheet.object_texture("belt") if id == BuildItems.STRIDE_HARNESS else PixelSheet.object_texture("quick") if id == BuildItems.GUIDED_MAG else load("res://assets/powers/aid_broadcast_v1.svg")
	_name.text = SpecialtyPresentation.reward_name(id)
	_effect.text = SpecialPowers.RADIO_HELP if id == SpecialPowers.RADIO else "效果：" + str(SpecialtyPresentation.definition(id).get("effect", ""))
	_source.position.y = 426
	_source.size.y = 72
	_heading.text = "专精进度"
	_progress.max_value = 2
	if not available:
		status.text = "专精资料待同步"
		_source.text = "可重试读取与同步。已有旅程继续使用开局时保存的装备池。"
		_progress.value = 0
		_progress_text.text = "— / 2 XP"
		return
	var xp: int = int(_state.get("specialties", {}).get(plan_id, 0))
	var access: String = "全专精共享" if xp >= 4 else "本专精已开放" if xp >= 2 else "未解锁"
	var discovery: String = "已发现" if _state.get("specialty_discoveries", {}).has(id) else "未发现"
	status.text = "%s · %s" % [access, discovery]
	_progress.max_value = 4 if xp >= 2 else 2
	_progress.value = xp
	_progress_text.text = "%d / %d XP" % [xp, int(_progress.max_value)]
	_milestone_one.modulate = CampStyle.TEAL if xp >= 2 else Color.WHITE
	_milestone_two.modulate = CampStyle.TEAL if xp >= 4 else Color.WHITE
	_source.text = "至少完成两次已确认归航后，泵站胜利 +2 XP，全灭 +1 XP。"


static func _plan_art(index: int) -> Texture2D:
	var result: AtlasTexture = AtlasTexture.new()
	result.atlas = PLAN_ART
	var width: float = PLAN_ART.get_width() / 3.0
	result.region = Rect2(index * width, 0, width, PLAN_ART.get_height())
	result.filter_clip = true
	return result


static func _item_art(id: String) -> Texture2D:
	match id:
		"field_tools_v1": return _plan_art(0)
		"pressure_rounds_v1", "wide_blast_v1": return _plan_art(1)
		"medical_pack_v1": return _plan_art(2)
		"quick_loader_v1": return PixelSheet.object_texture("quick")
		"light_boots_v1": return PixelSheet.object_texture("belt")
	return MASK_ICON
