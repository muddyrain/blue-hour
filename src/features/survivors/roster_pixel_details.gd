class_name RosterPixelDetails
extends PersonaDetails
## Camp-only presentation of the shared read-only persona projection.

const TRAIT_SUMMARIES: Dictionary = {
	"枪械专长": "枪械伤害 +15%", "近战好手": "近战伤害 +20%",
	"轻盈步伐": "移动速度 +10%", "装填熟手": "换弹耗时 -15%",
	"搜寻敏锐": "搜刮 / 回收耗时 -15%", "步伐沉重": "移动速度 -10%",
	"装填生疏": "换弹耗时 +15%", "搜寻分心": "搜刮 / 回收耗时 +15%",
}

var _facts: Control
var _extra: VBoxContainer
var _experience: Label
var _experience_bar: ProgressBar
var _progress: Label
var _progress_title: Label
var _life_title: Label
var _growth_title: Label
var _history: Label
var _model: Dictionary = {}


func _build() -> void:
	if _built:
		return
	_built = true
	name = "RosterPixelDetails"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(470, 572)
	add_theme_stylebox_override("panel", CampStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	var canvas: Control = Control.new()
	add_child(canvas)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.mouse_force_pass_scroll_events = false
	canvas.add_child(scroll)
	PixelSheet.place(scroll, Rect2(0, 0, 470, 498))
	_facts = Control.new()
	_facts.custom_minimum_size = Vector2(456, 494)
	scroll.add_child(_facts)
	name_label = PixelSheet.label(_facts, "", Rect2(0, 0, 456, 44), 29)
	PixelSheet.line(_facts, Rect2(0, 48, 456, 1))
	_life_title = PixelSheet.label(_facts, "生命", Rect2(0, 54, 76, 30), 24)
	health_label = PixelSheet.label(_facts, "", Rect2(104, 54, 352, 30), 22)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_bar = _meter(_facts, Rect2(86, 86, 370, 10), CampStyle.TEAL)
	_growth_title = PixelSheet.label(_facts, "经验", Rect2(0, 102, 76, 30), 24)
	_experience = PixelSheet.label(_facts, "", Rect2(104, 102, 352, 30), 22)
	_experience.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_experience_bar = _meter(_facts, Rect2(86, 134, 370, 10), CampStyle.EDGE)
	PixelSheet.line(_facts, Rect2(0, 156, 456, 1))
	PixelSheet.label(_facts, "个人特性", Rect2(0, 162, 456, 38), 28)
	PixelSheet.panel(_facts, Rect2(0, 206, 456, 70), CampStyle.PANEL, CampStyle.EDGE)
	primary_label = PixelSheet.label(_facts, "", Rect2(14, 208, 298, 32), 24)
	trait_label = PixelSheet.label(_facts, "", Rect2(14, 242, 302, 28), 20)
	trait_label.clip_text = true
	PixelSheet.line(_facts, Rect2(322, 216, 1, 48))
	_progress_title = PixelSheet.label(_facts, "特性进度", Rect2(334, 210, 112, 26), 18)
	_progress_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress = PixelSheet.label(_facts, "", Rect2(334, 238, 112, 32), 23)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	positive_label = PixelSheet.label(_facts, "", Rect2(14, 282, 442, 32), 21)
	positive_label.clip_text = true
	PixelSheet.line(_facts, Rect2(0, 318, 456, 1))
	negative_label = PixelSheet.label(_facts, "", Rect2(14, 320, 442, 32), 21)
	negative_label.clip_text = true
	PixelSheet.line(_facts, Rect2(0, 359, 456, 1))
	PixelSheet.label(_facts, "当前装备", Rect2(0, 364, 220, 38), 28)
	sources_button = PixelSheet.button(_facts, "详情 ＋", Rect2(342, 368, 114, 30), 18)
	CampStyle.text_button(sources_button)
	sources_button.pressed.connect(_toggle_sources)
	PixelSheet.panel(_facts, Rect2(0, 410, 456, 82), CampStyle.PANEL, CampStyle.EDGE)
	_weapon = PixelSheet.art(_facts, null, Rect2(12, 420, 204, 60))
	PixelSheet.line(_facts, Rect2(224, 422, 1, 58))
	weapon_label = PixelSheet.label(_facts, "", Rect2(238, 414, 206, 72), 22)
	weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_label.max_lines_visible = 2
	weapon_label.clip_text = true
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 16)
	_facts.add_child(_extra)
	PixelSheet.place(_extra, Rect2(0, 514, 450, 0))
	reload_label = _extra_label(20)
	move_label = _extra_label(20)
	work_label = _extra_label(20)
	sources_label = _extra_label(18)
	_history = _extra_label(20)
	_extra.hide()
	_extra.resized.connect(func() -> void:
		if _sources_expanded: _facts.custom_minimum_size.y = 530 + _extra.size.y
	)
	# These inherited projection fields remain available without repeating them in the main view.
	portrait = PersonaPortrait.new()
	canvas.add_child(portrait)
	portrait.hide()
	recipe_label = Label.new()
	canvas.add_child(recipe_label)
	recipe_label.hide()
	scope_label = PixelSheet.label(canvas, "", Rect2(0, 506, 456, 62), 20, CampStyle.MUTED)
	scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_button = PixelSheet.button(canvas, "管理装备", Rect2(0, 512, 192, 60), 27)
	training_button = PixelSheet.button(canvas, "查看培养 →", Rect2(208, 512, 248, 60), 30)
	PixelMenu.primary(training_button)
	equipment_button.pressed.connect(_request_equipment)
	training_button.pressed.connect(_request_training)
	close_button = Button.new()
	canvas.add_child(close_button)
	close_button.hide()
	close_button.pressed.connect(close)


func present(model: Dictionary) -> void:
	super.present(model)
	_model = model.duplicate(true)
	name_label.text = "%s  |  人物 Lv%d" % [PersonaCard.text(model, "name"), int(model.get("level", 1))]
	name_label.clip_text = true
	name_label.tooltip_text = PersonaCard.text(model, "name")
	health_label.text = "%d / %d" % [ceili(float(model.get("hp", 0.0))), ceili(float(model.get("max_hp", 0.0)))]
	positive_label.text = _compact_trait(model.get("positive", {}))
	negative_label.text = _compact_trait(model.get("negative", {}))
	positive_label.tooltip_text = PersonaCard.trait_detail(model.get("positive", {}))
	negative_label.tooltip_text = PersonaCard.trait_detail(model.get("negative", {}))
	trait_label.tooltip_text = PersonaCard.text(model, "trait_detail")
	reload_label.text = PersonaCard.text(model, "weapon_detail") + "\n" + PersonaCard.text(model, "reload_detail")
	sources_label.text = PersonaCard.text(model, "trait_detail") + "\n\n" + PersonaCard.text(model, "sources_detail")
	scope_label.visible = not _editable
	if not _editable:
		scope_label.text = "阵亡档案 · 身份与特质保留\n只能查看历史，不能管理装备或训练。" if not model.get("alive", false) else scope_label.text


func present_roster(data: Dictionary, member_id: int, archived_equipment: Dictionary) -> void:
	var member: Dictionary = SurvivorRoster.member(data.crew, member_id)
	var model: Dictionary = PersonaViewModel.camp(data, member_id)
	if model.is_empty():
		var definition: SurvivorDefinition = SurvivorRoster.definition(member_id)
		var item: Dictionary = WeaponInventory.for_member(data, member_id)
		model = {"id": member_id, "name": member.call_sign, "hp": member.health, "max_hp": SurvivorGrowth.maximum(data, member),
			"level": member.get("growth", {}).get("level", 1), "alive": member.health > 0, "scope": "camp", "editable": member.health > 0,
			"portrait": definition.portrait, "primary": "个人特性", "trait_detail": "特性尚未开放", "positive": {}, "negative": {},
			"weapon_name": "未装备", "weapon_detail": "无当前装备", "status": "存活" if member.health > 0 else "阵亡 · 只读历史"}
		if not item.is_empty():
			var weapon: WeaponDefinition = WeaponInventory.definition(item.weapon_id)
			model.weapon_name = weapon.display_name
			model.weapon_detail = weapon.display_name
			model.weapon_texture = weapon.presentation.texture
	present(model)
	var level: int = int(member.get("growth", {}).get("level", 1))
	var xp: int = int(member.get("growth", {}).get("xp_total", 0))
	var next_xp: int = GrowthRules.threshold(level + 1)
	_experience.text = "%d / %d" % [xp, next_xp]
	_experience_bar.max_value = maxi(next_xp, 1)
	_experience_bar.value = xp
	var trait_state: Dictionary = member.get("growth", {}).get("trait", {})
	var has_trait: bool = TraitState.is_family(data) and not trait_state.is_empty()
	primary_label.text = String(model.primary) + (" · Lv%d" % int(trait_state.level) if has_trait else "")
	if has_trait:
		var role: int = TraitRules.role(member)
		var factor: float = TraitRules.factor(member, {1:"shot", 2:"search", 3:"move"}[role])
		trait_label.text = {1:"射击间隔缩短 %s%%", 2:"搜刮耗时缩短 %s%%", 3:"移动速度提高 %s%%"}[role] % String.num(absf(1.0 - factor) * 100.0, 1).trim_suffix(".0")
		_progress.text = "%d / %d" % [int(trait_state.progress), TraitRules.THRESHOLDS[int(trait_state.level)]] if int(trait_state.level) < TraitRules.THRESHOLDS.size() else "已满级"
	else:
		trait_label.text = "特性尚未开放"
		_progress.text = "—"
	if not GrowthState.is_family(data):
		name_label.text = String(model.name)
		_experience.text = "成长尚未开放"
	var equipped: Dictionary = WeaponInventory.for_member(data, member_id)
	weapon_label.text = String(model.get("weapon_name", "未装备"))
	if not equipped.is_empty():
		var short_id: String = WeaponInventory.short_id(equipped)
		var caption: String = short_id if short_id.length() <= 18 else short_id.left(10) + "…" + short_id.right(5)
		weapon_label.text += "\n#" + caption
		var object_id: String = "rifle" if equipped.weapon_id == "long_rifle" else "carbine" if equipped.weapon_id == "carbine" else ""
		if not object_id.is_empty():
			_weapon.texture = PixelSheet.object_texture(object_id)
	weapon_label.tooltip_text = String(model.get("weapon_detail", ""))
	_history.text = "出击 %d 次 · 击退 %d\n累计受伤 %.0f" % [int(member.service.sorties), int(member.service.kills), float(member.service.damage_received)]
	if not equipped.is_empty():
		weapon_label.tooltip_text += "\n完整实例编号：" + String(equipped.instance_id)
		_history.text += "\n当前武器实例：\n" + String(equipped.instance_id)
	if member.condition == "dead":
		for death: Dictionary in data.journey.get("deaths", []):
			if int(death.member_id) == member_id:
				_history.text += "\n死亡：" + ("缺粮减员" if death.cause == "STARVATION" else "战斗阵亡")
		if not archived_equipment.is_empty():
			_history.text += "\n阵亡时装备：" + WeaponInventory.definition(archived_equipment.weapon_id).display_name
			weapon_label.tooltip_text += "\n阵亡时原武器已回库存，当前归属以库存为准。"


func _toggle_sources() -> void:
	_sources_expanded = not _sources_expanded
	_extra.visible = _sources_expanded
	sources_label.visible = true
	_facts.custom_minimum_size.y = 530 + _extra.size.y if _sources_expanded else 494
	sources_button.text = "收起 −" if _sources_expanded else "详情 ＋"
	if not _sources_expanded:
		scroll.scroll_vertical = 0


func _compact_trait(value: Variant) -> String:
	var title: String = PersonaCard.trait_name(value)
	return "%s · %s" % [title, TRAIT_SUMMARIES.get(title, PersonaCard.trait_detail(value))]


func _meter(parent: Control, bounds: Rect2, colour: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", CampStyle.box(colour, Color.TRANSPARENT, 0))
	parent.add_child(bar)
	PixelSheet.place(bar, bounds)
	return bar


func _extra_label(font: int) -> Label:
	var result: Label = Label.new()
	result.add_theme_font_size_override("font_size", font)
	result.add_theme_color_override("font_color", CampStyle.MUTED)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra.add_child(result)
	return result
