class_name LoadoutPanel
extends Control
## A camp-only view. Signals request transactions; controls never grant items.

signal equip_requested(member_id: int, instance_id: String)
signal repair_requested(instance_id: String)
signal build_requested(slot: int, item_id: String)
signal power_requested(ability_id: String)
signal closed

var power_panel: PowerLoadoutPanel
var build_panel: BuildItemsPanel
var player_mode: bool = false

var items: ItemList
var equip_buttons: Array[Button] = []
var equip_by_id: Dictionary[int,Button] = {}
var repair_button: Button
var back_button: Button
var confirmation: ConfirmationDialog
var message: Label
var _crew: Label
var _member_equipment: Dictionary[int,Label] = {}
var _crew_grid: GridContainer
var _actions: HBoxContainer
var _detail: Label
var _preview: TextureRect
var _data: Dictionary = {}
var _selected_id: String = ""
var _confirmation_id: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background: ColorRect = ColorRect.new()
	background.color = Color("10232d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 72)
	for side: String in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 24)
	add_child(margins)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var scroll: ScrollContainer=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	margins.add_child(scroll)
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var heading: Label = Label.new()
	heading.text = "武器整备 / 装备仓"
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)
	var crew_row: HBoxContainer = HBoxContainer.new()
	crew_row.add_theme_constant_override("separation", 24)
	column.add_child(crew_row)
	_crew = Label.new()
	_crew.add_theme_font_size_override("font_size", 16)
	_crew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crew.custom_minimum_size = Vector2(140, 56)
	_crew.add_theme_color_override("font_color", Color("a5dfce"))
	crew_row.add_child(_crew)
	_crew_grid = GridContainer.new()
	_crew_grid.columns = 2
	_crew_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew_row.add_child(_crew_grid)
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 28)
	column.add_child(row)
	items = ItemList.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.fixed_icon_size = Vector2i(112, 48)
	items.add_theme_font_size_override("font_size", 18)
	items.add_theme_constant_override("v_separation", 20)
	items.item_selected.connect(_select)
	row.add_child(items)
	var detail_column: VBoxContainer = VBoxContainer.new()
	detail_column.custom_minimum_size.x = 430
	detail_column.add_theme_constant_override("separation", 8)
	row.add_child(detail_column)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(400, 88)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_column.add_child(_preview)
	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_column.add_child(detail_scroll)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 18)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)
	build_panel=BuildItemsPanel.new()
	build_panel.requested.connect(func(slot:int,item:String)->void: build_requested.emit(slot,item))
	column.add_child(build_panel)
	power_panel=PowerLoadoutPanel.new()
	power_panel.requested.connect(func(id:String)->void:power_requested.emit(id))
	column.add_child(power_panel)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	_actions = actions
	repair_button = Button.new()
	repair_button.text = "维修…"
	repair_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_button.pressed.connect(_confirm_repair)
	actions.add_child(repair_button)
	var note: Label = Label.new()
	note.text = "损坏武器须先维修。配装会在营地保存，下次出击生效。"
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color("d9c390"))
	column.add_child(note)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 36
	message.add_theme_font_size_override("font_size", 17)
	column.add_child(message)
	back_button = Button.new()
	back_button.text = "返回营地 / Esc"
	back_button.custom_minimum_size.y = 44
	back_button.pressed.connect(func() -> void: closed.emit())
	column.add_child(back_button)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "维修确认"
	confirmation.ok_button_text = "确认维修"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(func() -> void: repair_requested.emit(_confirmation_id))
	add_child(confirmation)


func refresh(data: Dictionary, feedback: String = "") -> void:
	_data = data.duplicate(true)
	power_panel.present(data,not CampaignState.ended(data))
	build_panel.visible=BuildState.enabled(data)
	if build_panel.visible:
		var build: Dictionary = data.journey.build
		build_panel.present(build.owned, build.slots, true, not CampaignState.ended(data), build.get("opening", {}).get("plan", ""))
	items.max_text_lines = 3 if WeaponState.is_family(_data) else 1
	_sync_members()
	for id: int in _member_equipment:
		var entry: Dictionary = SurvivorRoster.member(_data.crew,id)
		_member_equipment[id].get_parent().visible = not entry.is_empty() and entry.health>0
	items.clear()
	for item: Dictionary in _data.weapons:
		var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
		var owner_id: int = WeaponInventory.owner(_data, item.instance_id)
		var ownership: String = SurvivorRoster.member(_data.crew, owner_id).call_sign if owner_id > 0 else "库存"
		var list_owner: String = ownership if ownership.length() <= 6 else ownership.left(6) + "…"
		var index: int = items.add_item("%02d  %s  /  %s  /  %s" % [items.item_count + 1, weapon.display_name,
			"待维修" if item.condition == "damaged" else "可装备", list_owner], weapon.presentation.texture)
		if WeaponState.is_family(_data):
			items.set_item_text(index,items.get_item_text(index)+"\n"+WeaponModifiers.description(item))
		items.set_item_metadata(index, item.instance_id)
		items.set_item_tooltip(index, "归属 " + ownership + ("" if player_mode else "\n实例 " + item.instance_id))
		if WeaponState.is_family(_data):
			items.set_item_tooltip(index,items.get_item_tooltip(index)+"\n"+WeaponModifiers.description(item)+("\n完整比较见右侧详情" if player_mode else "\nPROJECT_TEMP；完整比较见右侧可滚动详情"))
		items.set_item_custom_fg_color(index, CampStyle.AMBER if item.condition == "damaged" else CampStyle.TEXT)
		if _selected_id == item.instance_id:
			items.select(index)
	if items.get_selected_items().is_empty() and items.item_count > 0:
		items.select(0)
	if not items.get_selected_items().is_empty():
		_select(items.get_selected_items()[0])
	for member: Dictionary in _data.crew:
		var item: Dictionary = WeaponInventory.for_member(_data, int(member.id))
		var label: Label = _member_equipment[int(member.id)]
		label.text = "%02d  %s\n%s" % [int(member.id), (member.call_sign.left(4)+"…" if member.call_sign.length()>5 else member.call_sign),
			WeaponInventory.definition(item.weapon_id).display_name if not item.is_empty() else ("已阵亡，原实例在库" if member.condition == "dead" else "倒地，装备在库")]
		if not item.is_empty():
			var weapon: WeaponDefinition = WeaponModifiers.combat_definition(item)
			label.text += ("\n%.2f伤 · %.3fs · %.2f距" if WeaponState.is_family(_data) else "\n%.0f伤 · %.3fs · %.0f距") % [weapon.damage,weapon.shot_interval(1.0 if CombatEquipment.melee(item.weapon_id) else TraitRules.factor(member,"shot")),weapon.shot_range]
		var base: SurvivorDefinition = SurvivorRoster.definition(int(member.id))
		label.tooltip_text = "%s · %s\n呼号：%s" % [base.default_display_name, base.gender_text(), member.call_sign]
	_crew.text = "货币 %d\n食物 %d" % [int(_data.cash),int(_data.food)]
	message.text = feedback if not feedback.is_empty() else "选择一件武器，再配给指定队员；已装备的武器可直接交换。"


func _select(index: int) -> void:
	_selected_id = items.get_item_metadata(index)
	_detail.get_parent().set_deferred("scroll_vertical",0)
	var item: Dictionary = WeaponInventory.find(_data, _selected_id)
	var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	var repair_quote: int = WeaponInventory.repair_quote(_data, item)
	_preview.texture = weapon.presentation.texture
	var owner_id: int = WeaponInventory.owner(_data, _selected_id)
	var ownership: String = SurvivorRoster.member(_data.crew, owner_id).call_sign if owner_id > 0 else "装备仓"
	_detail.text = "%s · PROJECT_TEMP\n%s · %s\n\n基础伤害 %.0f · 间隔 %.3f秒 · 射程 %.0f" % [weapon.display_name,
		"损坏 · 须维修" if item.condition == "damaged" else "状态良好", ownership,
		weapon.damage,weapon.interval,weapon.shot_range]
	if owner_id > 0:
		var member: Dictionary = SurvivorRoster.member(_data.crew,owner_id)
		var factor: float = TraitRules.factor(member,"shot")
		_detail.text += "\n本人实际：%.0f伤 · %.3f秒 · %.0f距\n射击Trait倍率 ×%.3f；普通等级不加武器伤害" % [weapon.damage,weapon.shot_interval(factor),weapon.shot_range,factor]
	else:
		_detail.text += "\n未配装；配装后按持有者本人的射击Trait生效。"
	_detail.text += "\n\n理论持续 %.2f伤/秒（未计接敌与过量伤害）\n来源  /  %s\n维修报价  /  %d 货币" % [weapon.damage/weapon.interval,
		("救援同伴当场加入时自带" if item.origin == "rescue-first-contact" else ("街区补给点搜集" if item.origin == "north-cache" else "初始装备")),repair_quote]
	if WeaponState.is_family(_data):
		_detail.text = "%s · PROJECT_TEMP\n%s\n%s · %s\n\n武器基础：%.0f伤 · %.3f秒 · %.0f距" % [weapon.display_name,WeaponModifiers.description(item),"损坏 · 须维修" if item.condition=="damaged" else "状态良好",ownership,weapon.damage,weapon.interval,weapon.shot_range]
		_detail.text += "\n近战 · 正面110° · 最多3目标 · 起手0.18秒；靠近敌人有风险。" if CombatEquipment.melee(item.weapon_id) else "\n弹匣 %d发 · 自动换弹 %.1f秒 · 备弹∞"%[weapon.magazine_capacity(),weapon.reload_seconds()]
		if item.weapon_id=="shotgun_v1": _detail.text+="\n每次扳机9×5弹丸 · 每条射线只命中首个目标 · 近距清群。"
		var stats: Dictionary = WeaponModifiers.effective(item,TraitRules.factor(SurvivorRoster.member(_data.crew,owner_id),"shot") if owner_id>0 else 1.0)
		if item.weapon_id=="shotgun_v1": _detail.text+="\n实例单颗 %.2f×5"%stats.damage
		_detail.text += "\n实例等级伤害：×%.2f\n%s：%.2f伤 · %.3f秒 · %.2f距\n维修 %d 币，只改状态，不重抽词条。" % [1.10 if item.weapon_level==2 else 1.0,"本人有效" if owner_id>0 else "未配装实例",stats.damage,stats.interval,stats.range,repair_quote]
		if repair_quote < weapon.repair_cost:
			_detail.text += "\n工坊优惠 · 原价 %d 币" % weapon.repair_cost
		_detail.text += "\n\n与实际成员当前武器比较（同一本人Trait）："
		for member: Dictionary in _data.crew:
			if member.health<=0: continue
			var current: Dictionary = WeaponInventory.for_member(_data,int(member.id))
			var factor: float = TraitRules.factor(member,"shot")
			var before: Dictionary = WeaponModifiers.effective(current,factor)
			var proposed: Dictionary = WeaponModifiers.effective(item,factor)
			_detail.text += "\n%02d %s · 当前→所选\n伤%.2f→%.2f / 秒%.3f→%.3f / 距%.2f→%.2f" % [int(member.id),member.call_sign.left(5),before.damage,proposed.damage,before.interval,proposed.interval,before.range,proposed.range]
	if BuildState.enabled(_data):
		var factors: Dictionary=BuildItems.factors(_data.journey.build.slots)
		var values: Dictionary=WeaponModifiers.effective(item)
		if item.weapon_id=="shotgun_v1": _detail.text+="\n本局单颗 %.2f×5"%(values.damage*factors.damage)
		_detail.text+="\n本局道具有效：%.2f伤 · 换弹%.2f秒\n小队移速×%.2f · 搜刮耗时×%.2f\n原属性保留；仅本局已保存两槽生效。"%[values.damage*(1.0 if CombatEquipment.melee(item.weapon_id) else factors.damage),weapon.reload_seconds()*factors.reload,factors.move,factors.work]
	if CombatEquipment.melee(item.weapon_id): _detail.text=_detail.text.replace("本局道具有效：%.2f伤 · 换弹0.00秒"%WeaponModifiers.effective(item).damage,"本局有效：%.2f伤 · 近战无换弹"%WeaponModifiers.effective(item).damage)
	_detail.tooltip_text = "实例 " + item.instance_id + "\n现有样板固定维修报价，尚无随机词条。"
	if WeaponState.is_family(_data):
		_detail.tooltip_text = "实例 "+item.instance_id+"\n属性生成即冻结，维修只改状态；全部PROJECT_TEMP。"
	for member_id: int in equip_by_id:
		equip_by_id[member_id].visible = WeaponInventory._living(_data,member_id)
		var name: String = SurvivorRoster.member(_data.crew,member_id).get("call_sign", "")
		equip_by_id[member_id].tooltip_text = "配给 %s / 交换" % name
		equip_by_id[member_id].text = "配给 %s / 交换" % (name.left(4)+"…" if RescuePoolState.is_family(_data) and name.length()>5 else name)

	for member_id: int in equip_by_id:
		equip_by_id[member_id].disabled = item.condition != "ready" or not WeaponInventory._living(_data, member_id)
	repair_button.disabled = item.condition != "damaged"
	if BattleState.is_state(_data) and _data.journey.state == "FAILED":
		repair_button.disabled = true
	repair_button.text = "维修 %d 货币…" % repair_quote if item.condition == "damaged" else "无需维修"

	if player_mode:
		_detail.text = _detail.text.replace(" · PROJECT_TEMP", "")
		_detail.tooltip_text = "属性以右侧实际数值和当前持有者为准；维修不会重抽词条。"


func _confirm_repair() -> void:
	_confirmation_id = _selected_id
	var item: Dictionary = WeaponInventory.find(_data, _confirmation_id)
	var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	confirmation.dialog_text = "维修%s，消耗%d货币？\n确认后保存营地；取消不会消耗资源。" % [weapon.display_name, WeaponInventory.repair_quote(_data, item)]
	confirmation.popup_centered(Vector2i(620, 230))


func _sync_members() -> void:
	for member: Dictionary in _data.crew:
		var member_id: int = int(member.id)
		if _member_equipment.has(member_id): continue
		var member_row: HBoxContainer = HBoxContainer.new()
		member_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		member_row.add_theme_constant_override("separation", 10)
		_crew_grid.add_child(member_row)
		var portrait: TextureRect = TextureRect.new()
		portrait.texture = SurvivorRoster.definition(member_id).portrait
		portrait.custom_minimum_size = Vector2(52, 56)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		member_row.add_child(portrait)
		var equipment: Label = Label.new()
		equipment.add_theme_font_size_override("font_size", 16)
		equipment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		equipment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		member_row.add_child(equipment)
		_member_equipment[member_id] = equipment
		var button: Button = Button.new()
		button.text = "配给队员 %d / 交换" % member_id
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.pressed.connect(func() -> void: equip_requested.emit(member_id, _selected_id))
		_actions.add_child(button)
		_actions.move_child(button,equip_buttons.size())
		equip_buttons.append(button)
		equip_by_id[member_id] = button
