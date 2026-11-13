class_name LoadoutPanel
extends Control
## A camp-only view. Signals request transactions; controls never grant items.

signal equip_requested(member_id: int, instance_id: String)
signal repair_requested(instance_id: String)
signal workshop_requested(instance_id: String, mod: String)
signal economy_requested(request: Dictionary)
signal build_investment_requested(choice: String)
signal build_requested(slot: int, item_id: String)
signal power_requested(ability_id: String)
signal closed
signal navigation_requested(action: StringName)

var power_panel: PowerLoadoutPanel
var build_panel: BuildItemsPanel
var armory: CampArmoryView

var items: ItemList
var equip_buttons: Array[Button] = []
var equip_by_id: Dictionary[int,Button] = {}
var repair_button: Button
var back_button: Button
var confirmation: ConfirmationDialog
var workshop_buttons: Dictionary[String, Button] = {}
var workshop_confirmation: ConfirmationDialog
var message: Label
var _crew: Label
var _member_equipment: Dictionary[int,Label] = {}
var _crew_grid: GridContainer
var _actions: HBoxContainer
var _detail: Label
var _preview: TextureRect
var _data: Dictionary = {}
var _retry_power: bool = false
var _selected_id: String = ""
var _confirmation_id: String = ""
var _workshop: PanelContainer
var _workshop_heading: Label
var _workshop_status: Label
var _workshop_instance_id: String = ""
var _workshop_mod: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background: ColorRect = ColorRect.new()
	background.color = Color("10232d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_setup_armory()


func refresh(data: Dictionary, feedback: String = "", retry_power: bool = false) -> void:
	_data = data.duplicate(true)
	_retry_power = retry_power
	if is_instance_valid(armory):
		armory.refresh(_data, feedback, retry_power)
		return
	power_panel.present(data,not CampaignState.ended(data) and not retry_power,retry_power)
	build_panel.visible=BuildState.enabled(data)
	if build_panel.visible:
		var build: Dictionary = data.journey.build
		build_panel.present(build.owned, build.slots, true, not CampaignState.ended(data) and not retry_power, build.get("opening", {}).get("plan", ""), BuildState.pool(data), data)
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
		var mod: String = WorkshopV1.mod_for(_data, item.instance_id)
		if not mod.is_empty():
			items.set_item_text(index, items.get_item_text(index) + "\n工坊 · " + WorkshopV1.name_for(mod))
		items.set_item_metadata(index, item.instance_id)
		items.set_item_tooltip(index, "归属 " + ownership)
		if WeaponState.is_family(_data):
			items.set_item_tooltip(index,items.get_item_tooltip(index)+"\n"+WeaponModifiers.description(item)+("\n完整比较见右侧详情"))
		if not mod.is_empty():
			items.set_item_tooltip(index, items.get_item_tooltip(index) + "\n工坊 · " + WorkshopV1.name_for(mod))
		items.set_item_custom_fg_color(index, CampStyle.AMBER if item.condition == "damaged" else CampStyle.TEXT)
		if _selected_id == item.instance_id:
			items.select(index)
	if items.get_selected_items().is_empty() and items.item_count > 0:
		items.select(0)
	if not items.get_selected_items().is_empty():
		_select(items.get_selected_items()[0])
	else:
		_selected_id = ""
		_refresh_workshop({}, 0)
	for member: Dictionary in _data.crew:
		var item: Dictionary = WeaponInventory.for_member(_data, int(member.id))
		var label: Label = _member_equipment[int(member.id)]
		var mechanic: bool = int(member.id) == WeaponInventory.MECHANIC_ID and WeaponInventory.mechanic_available(_data)
		var call_sign: String = member.call_sign.left(4)+"…" if member.call_sign.length()>5 else member.call_sign
		if mechanic:
			call_sign = WeaponInventory.MECHANIC_TITLE + " " + call_sign
		label.text = "%02d  %s\n%s" % [int(member.id), call_sign,
			WeaponInventory.definition(item.weapon_id).display_name if not item.is_empty() else ("已阵亡，原实例在库" if member.condition == "dead" else "倒地，装备在库")]
		if not item.is_empty():
			var weapon: WeaponDefinition = WeaponModifiers.combat_definition(item)
			if not WeaponModifiers.combat_affix(item).is_empty():
				label.text += "\n" + WeaponModifiers.description(item)
			label.text += ("\n%.2f伤 · %.3fs · %.2f距" if WeaponState.is_family(_data) else "\n%.0f伤 · %.3fs · %.0f距") % [weapon.damage,weapon.shot_interval(1.0 if CombatEquipment.melee(item.weapon_id) else TraitRules.factor(member,"shot")),weapon.shot_range]
		var base: SurvivorDefinition = SurvivorRoster.definition(int(member.id))
		label.tooltip_text = "%s · %s\n呼号：%s" % [base.default_display_name, base.gender_text(), member.call_sign]
		if mechanic:
			label.tooltip_text = WeaponInventory.MECHANIC_TITLE + " · 武器维修减 3 币\n" + label.tooltip_text
	_crew.text = "货币 %d\n食物 %d" % [int(_data.cash),int(_data.food)]
	message.text = feedback if not feedback.is_empty() else "选择一件武器，再配给指定队员；已装备的武器可直接交换。"


func _setup_armory() -> void:
	armory = CampArmoryView.new()
	armory.name = "CampArmory"
	add_child(armory)
	items = armory.items
	message = armory.message
	back_button = armory.back_button
	confirmation = armory.confirmation
	workshop_confirmation = armory.workshop_confirmation
	workshop_buttons = armory.workshop_buttons
	repair_button = armory.repair_button
	power_panel = armory.power_panel
	build_panel = armory.build_panel
	armory.equip_requested.connect(equip_requested.emit)
	armory.repair_requested.connect(repair_requested.emit)
	armory.workshop_requested.connect(workshop_requested.emit)
	armory.economy_requested.connect(economy_requested.emit)
	armory.selection_changed.connect(func(identity: String) -> void: _selected_id = identity)
	armory.navigation_requested.connect(func(action: StringName) -> void:
		if action == &"camp":
			closed.emit()
		else:
			navigation_requested.emit(action))
	build_panel.requested.connect(build_requested.emit)
	build_panel.investment_requested.connect(build_investment_requested.emit)
	power_panel.requested.connect(power_requested.emit)


func show_inventory() -> void:
	if is_instance_valid(armory):
		armory.show_inventory()


func show_workshop(instance_id: String = "") -> void:
	if is_instance_valid(armory):
		armory.show_workshop(instance_id)


func back_from_workshop() -> bool:
	return is_instance_valid(armory) and armory.back_from_workshop()


func cancel_swap_preview() -> bool:
	return is_instance_valid(armory) and armory.cancel_swap_preview()


func select_for_member(member_id: int) -> void:
	var item: Dictionary = WeaponInventory.for_member(_data, member_id)
	if is_instance_valid(armory):
		armory.select_inventory(item.get("instance_id", ""), member_id)
	elif not item.is_empty():
		_selected_id = item.instance_id
		refresh(_data)


func focus_inventory() -> void:
	items.grab_focus()


func focus_retry() -> void:
	if is_instance_valid(armory):
		armory.focus_retry()
	else:
		power_panel.retry_button.grab_focus()


func matches_equip(data: Dictionary, member_id: int, instance_id: String) -> bool:
	return not is_instance_valid(armory) or armory.matches_equip(data, member_id, instance_id)


func _select(index: int) -> void:
	_selected_id = items.get_item_metadata(index)
	_detail.get_parent().set_deferred("scroll_vertical",0)
	var item: Dictionary = WeaponInventory.find(_data, _selected_id)
	var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	var repair_offer: Dictionary = WeaponInventory.repair_offer(_data, item)
	var repair_quote: int = int(repair_offer.cost)
	_preview.texture = weapon.presentation.texture
	var owner_id: int = WeaponInventory.owner(_data, _selected_id)
	var ownership: String = SurvivorRoster.member(_data.crew, owner_id).call_sign if owner_id > 0 else "装备仓"
	var mod: String = WorkshopV1.mod_for(_data, _selected_id)
	var magazine: Dictionary = WeaponMagazine.parameters(item.weapon_id, mod)
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
		_detail.text = "%s · PROJECT_TEMP\n%s\n%s · %s" % [weapon.display_name,WeaponModifiers.description(item),
			"损坏 · 须维修" if item.condition=="damaged" else "状态良好",ownership]
		var effect: String = WeaponModifiers.effect_description(item)
		if not effect.is_empty():
			_detail.text += "\n" + effect
		_detail.text += "\n\n武器基础：%.0f伤 · %.3f秒 · %.0f距" % [weapon.damage,weapon.interval,weapon.shot_range]
		var melee: Dictionary = CombatEquipment.melee_policy(item.weapon_id)
		if not melee.is_empty():
			_detail.text += "\n近战 · 正面%d° · 最多%d目标 · 起手%.2f秒" % [int(melee.angle_degrees), int(melee.max_targets), float(melee.windup)]
		elif WorkshopV1.enabled(_data):
			_detail.text += "\n%s · %d 发 · 基础换弹 %.2f 秒 · 备弹∞" % [WorkshopV1.name_for(mod), magazine.capacity, magazine.seconds]
		else:
			_detail.text += "\n弹匣 %d发 · 自动换弹 %.1f秒 · 备弹∞" % [weapon.magazine_capacity(), weapon.reload_seconds()]
		if item.weapon_id=="shotgun_v1": _detail.text+="\n每次扳机9×5弹丸 · 每条射线只命中首个目标 · 近距清群。"
		var stats: Dictionary = WeaponModifiers.effective(item,TraitRules.factor(SurvivorRoster.member(_data.crew,owner_id),"shot") if owner_id>0 else 1.0)
		if item.weapon_id=="shotgun_v1": _detail.text+="\n实例单颗 %.2f×5"%stats.damage
		_detail.text += "\n实例等级伤害：×%.2f\n%s：%.2f伤 · %.3f秒 · %.2f距\n%s" % [1.10 if item.weapon_level==2 else 1.0,"本人有效" if owner_id>0 else "未配装实例",stats.damage,stats.interval,stats.range,_repair_summary(repair_offer)]
		_detail.text += "\n\n与实际成员当前武器比较（同一本人Trait）："
		for member: Dictionary in _data.crew:
			if member.health<=0: continue
			var current: Dictionary = WeaponInventory.for_member(_data,int(member.id))
			var factor: float = TraitRules.factor(member,"shot")
			var before: Dictionary = WeaponModifiers.effective(current,factor)
			var proposed: Dictionary = WeaponModifiers.effective(item,factor)
			_detail.text += "\n%02d %s · 当前 %s → 所选\n伤%.2f→%.2f / 秒%.3f→%.3f / 距%.2f→%.2f" % [int(member.id),member.call_sign.left(5),
				WeaponInventory.definition(current.weapon_id).display_name,before.damage,proposed.damage,before.interval,proposed.interval,before.range,proposed.range]
	if BuildState.enabled(_data):
		var factors: Dictionary=BuildItems.camp_factors(_data)
		var values: Dictionary=WeaponModifiers.effective(item)
		if item.weapon_id=="shotgun_v1": _detail.text+="\n本局单颗 %.2f×5"%(values.damage*factors.damage)
		var damage: float = values.damage * (1.0 if CombatEquipment.melee(item.weapon_id) else factors.damage)
		if WorkshopV1.enabled(_data) and not magazine.is_empty():
			_detail.text += "\n本局道具有效：%.2f伤 · %s换弹 %.2f 秒" % [damage, "本人有效" if owner_id > 0 else "含道具", float(magazine.seconds) * _reload_factor(owner_id)]
		else:
			_detail.text += "\n本局道具有效：%.2f伤 · 换弹%.2f秒" % [damage, weapon.reload_seconds() * factors.reload]
		_detail.text += "\n小队移速×%.2f · 搜刮耗时×%.2f\n原属性保留；仅本局已保存两槽生效。" % [factors.move, factors.work]
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
		equip_by_id[member_id].disabled = _retry_power or item.condition != "ready" or not WeaponInventory._living(_data, member_id)
	repair_button.disabled = _retry_power or item.condition != "damaged"
	if BattleState.is_state(_data) and _data.journey.state == "FAILED":
		repair_button.disabled = true
	repair_button.text = "维修 %d 货币…" % repair_quote if item.condition == "damaged" else "无需维修"

	_detail.text = _detail.text.replace(" · PROJECT_TEMP", "")
	_detail.tooltip_text = "属性以右侧实际数值和当前持有者为准；维修不会重抽词条。"
	_refresh_workshop(item, owner_id, index)


func _build_workshop(column: VBoxContainer) -> void:
	_workshop = PanelContainer.new()
	_workshop.name = "Workshop"
	_workshop.add_theme_stylebox_override("panel", CampStyle.box(CampStyle.PANEL, Color("5c6863"), 8))
	column.add_child(_workshop)
	_workshop.hide()
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	_workshop.add_child(stack)
	var top: HBoxContainer = HBoxContainer.new()
	stack.add_child(top)
	_workshop_heading = CampStyle.label("工坊改装", 17, CampStyle.TEAL)
	_workshop_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workshop_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_workshop_heading)
	top.add_child(CampStyle.label("工具箱 ×1 + %d 币 / 次" % WorkshopV1.COST, 16, CampStyle.AMBER))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	for mod: String in [WorkshopV1.EXTENDED, WorkshopV1.QUICK]:
		var button: Button = Button.new()
		button.name = "WorkshopExtended" if mod == WorkshopV1.EXTENDED else "WorkshopQuick"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_confirm_workshop.bind(mod))
		row.add_child(button)
		workshop_buttons[mod] = button
	_workshop_status = CampStyle.label("", 15, CampStyle.MUTED)
	_workshop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_workshop_status)
	workshop_confirmation = ConfirmationDialog.new()
	workshop_confirmation.name = "WorkshopConfirmation"
	workshop_confirmation.title = "确认工坊改装"
	workshop_confirmation.ok_button_text = "安装并保存"
	workshop_confirmation.cancel_button_text = "取消"
	workshop_confirmation.confirmed.connect(func() -> void: workshop_requested.emit(_workshop_instance_id, _workshop_mod))
	add_child(workshop_confirmation)


func _refresh_workshop(item: Dictionary, owner_id: int, index: int = -1) -> void:
	_workshop.visible = WorkshopV1.enabled(_data)
	if not _workshop.visible:
		return
	var selection: String = "未选择武器" if item.is_empty() else "%02d %s" % [index + 1, WeaponInventory.definition(item.weapon_id).display_name]
	_workshop_heading.text = "工坊改装 · 工具箱 ×%d · %s" % [WorkshopV1.tools(_data), selection]
	var factor: float = _reload_factor(owner_id)
	var problem: String = _workshop_problem(WorkshopV1.EXTENDED)
	for mod: String in workshop_buttons:
		var button: Button = workshop_buttons[mod]
		button.text = WorkshopV1.name_for(mod) + " · " + _magazine_preview(mod, factor, owner_id)
		button.disabled = not problem.is_empty()
		button.tooltip_text = problem if button.disabled else "改装随当前枪械实例转配，每把只可安装一次。"
	var installed: String = WorkshopV1.mod_for(_data, _selected_id)
	if installed.is_empty():
		_workshop_status.text = problem if not problem.is_empty() else "安装后随所选实例转配，每把只可改装一次。"
	else:
		var magazine: Dictionary = WeaponMagazine.parameters(item.weapon_id, installed)
		_workshop_status.text = "已安装 %s · %d 发 · %s换弹 %.2f 秒" % [WorkshopV1.name_for(installed), magazine.capacity, "本人有效" if owner_id > 0 else "含道具", float(magazine.seconds) * factor]
		if _retry_power:
			_workshop_status.text += " · " + problem


func _workshop_problem(mod: String) -> String:
	if _retry_power:
		return "本次整备待保存，请先重试。"
	return WorkshopV1.mod_problem(_data, _selected_id, mod)


func _magazine_preview(mod: String, factor: float, owner_id: int) -> String:
	var stock: Dictionary = WeaponMagazine.parameters("carbine")
	var option: Dictionary = WeaponMagazine.parameters("carbine", mod)
	var detail: String = "%d → %d 发\n基础换弹 %.2f → %.2f 秒" % [stock.capacity, option.capacity, stock.seconds, option.seconds]
	if not is_equal_approx(factor, 1.0):
		detail += " · %s %.2f → %.2f 秒" % ["本人有效" if owner_id > 0 else "含道具", float(stock.seconds) * factor, float(option.seconds) * factor]
	return detail


func _reload_factor(owner_id: int) -> float:
	var factor: float = 1.0
	if BuildState.enabled(_data):
		factor = float(BuildItems.camp_factors(_data).reload)
	if owner_id > 0 and PersonaState.enabled(_data):
		var recipe: Dictionary = SurvivorPersona.member(_data.journey.build.persona, owner_id)
		factor *= float(SurvivorPersona.factors(recipe).get("reload", 1.0))
	return factor


func _confirm_workshop(mod: String) -> void:
	if not _workshop_problem(mod).is_empty():
		return
	_workshop_instance_id = _selected_id
	_workshop_mod = mod
	var item: Dictionary = WeaponInventory.find(_data, _workshop_instance_id)
	var owner_id: int = WeaponInventory.owner(_data, _workshop_instance_id)
	var number: int = _data.weapons.find(item) + 1
	workshop_confirmation.dialog_text = "为 %02d %s 安装%s？\n%s\n消耗工具箱 ×1 和 %d 币。每把卡宾枪仅可安装一次。" % [
		number, WeaponInventory.definition(item.weapon_id).display_name, WorkshopV1.name_for(mod),
		_magazine_preview(mod, _reload_factor(owner_id), owner_id), WorkshopV1.COST]
	workshop_confirmation.popup_centered(Vector2i(620, 230))


func _confirm_repair() -> void:
	_confirmation_id = _selected_id
	var item: Dictionary = WeaponInventory.find(_data, _confirmation_id)
	var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
	confirmation.dialog_text = "维修%s？\n%s\n确认后保存营地，取消保留当前资源。" % [weapon.display_name, _repair_summary(WeaponInventory.repair_offer(_data, item))]
	confirmation.popup_centered(Vector2i(620, 230))


func _repair_summary(offer: Dictionary) -> String:
	var adjustment: String = "标准报价" if offer.discount == 0 else "%s减 %d 币" % [offer.source, int(offer.discount)]
	return "维修标价 %d 币 · %s · 实付 %d 币" % [int(offer.base), adjustment, int(offer.cost)]


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
