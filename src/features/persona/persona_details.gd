class_name PersonaDetails
extends PanelContainer
## Shared read-only details. The parent owns selection, editing, focus and pause policy.

signal closed
signal equipment_requested(member_id: int)
signal training_requested(member_id: int)

const POSITIVE_ICON: Texture2D = preload("res://assets/persona/positive.svg")
const NEGATIVE_ICON: Texture2D = preload("res://assets/persona/negative.svg")

var portrait: PersonaPortrait
var primary_label: Label
var name_label: Label
var health_label: Label
var health_bar: ProgressBar
var scope_label: Label
var recipe_label: Label
var trait_label: Label
var positive_label: Label
var negative_label: Label
var weapon_label: Label
var reload_label: Label
var move_label: Label
var work_label: Label
var sources_label: Label
var sources_button: Button
var equipment_button: Button
var training_button: Button
var close_button: Button
var scroll: ScrollContainer
var _weapon: TextureRect
var _member_id: int = 0
var _editable: bool = false
var _built: bool = false
var _sources_expanded: bool = false
var _last_scope: String = ""
var _last_member: int = 0


func _ready() -> void:
	_build()


func present(model: Dictionary) -> void:
	_build()
	_member_id = int(model.get("id", 0))
	var scope: String = PersonaCard.text(model, "scope")
	var alive: bool = model.get("alive", false) == true
	_editable = scope == "camp" and alive and model.get("editable", false) == true
	primary_label.text = PersonaCard.text(model, "primary", "主特长未提供")
	name_label.text = "%02d  %s" % [_member_id, PersonaCard.text(model, "name", "姓名未提供")]
	var hp: float = float(model.get("hp", 0.0))
	var maximum: float = float(model.get("max_hp", 0.0))
	health_label.text = "HP %d / %d · Lv%d · %s" % [ceili(hp), ceili(maximum), int(model.get("level", 0)), PersonaCard.text(model, "status", "状态未提供")] if maximum > 0.0 else "HP — / — · 状态未提供"
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = clampf(hp, 0.0, maxf(maximum, 0.0))
	portrait.present(model.get("portrait") as Texture2D, alive, primary_label.text)
	match scope:
		"field":
			scope_label.text = "行动继续，可空格暂停"
		"candidate":
			scope_label.text = "已揭示的救援对象 · 尚未接纳，只读预览"
		_:
			scope_label.text = "营地档案" if alive else "阵亡档案 · 身份与已知特质保留，只读"
	recipe_label.text="＋%s / －%s"%[PersonaCard.trait_name(model.get("positive","")),PersonaCard.trait_name(model.get("negative",""))]
	trait_label.text = PersonaCard.text(model, "trait_detail", "主特长成长未提供")
	positive_label.text = "＋" + PersonaCard.trait_name(model.get("positive", "")) + "\n" + PersonaCard.trait_detail(model.get("positive", ""))
	negative_label.text = "－" + PersonaCard.trait_name(model.get("negative", "")) + "\n" + PersonaCard.trait_detail(model.get("negative", ""))
	weapon_label.text = PersonaCard.text(model, "weapon_detail", "武器详情未提供")
	reload_label.text = PersonaCard.text(model, "reload_detail", PersonaCard.text(model, "ammo", "弹匣详情未提供"))
	move_label.text = PersonaCard.text(model, "move_detail", "移动详情未提供")
	work_label.text = PersonaCard.text(model, "work_detail", "工作详情未提供")
	sources_label.text = PersonaCard.text(model, "sources_detail", "计算来源未提供")
	_weapon.texture = model.get("weapon_texture") as Texture2D
	_weapon.visible = _weapon.texture != null
	for button: Button in [equipment_button, training_button]:
		button.visible = _editable
		button.disabled = not _editable
		button.focus_mode = Control.FOCUS_ALL if _editable else Control.FOCUS_NONE
		if not _editable:
			button.release_focus()
	if _last_scope != scope or _last_member != _member_id:
		scroll.scroll_vertical = 0
		_last_scope = scope
		_last_member = _member_id
	visible = true


func close() -> void:
	var was_visible: bool = visible
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and (focus == self or is_ancestor_of(focus)):
		focus.release_focus()
	hide()
	if was_visible:
		closed.emit()


func _build() -> void:
	if _built:
		return
	_built = true
	name = "PersonaDetails"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size.x = 300
	add_theme_stylebox_override("panel", CampStyle.box(Color("102832"), Color("4b7079"), 14))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	portrait = PersonaPortrait.new()
	portrait.custom_minimum_size = Vector2(72, 76)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(portrait)
	var identity: VBoxContainer = VBoxContainer.new()
	identity.add_theme_constant_override("separation", 4)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(identity)
	primary_label = _label(identity, "Primary", 23)
	name_label = _label(identity, "Name", 16)
	health_label = _label(identity, "Health", 14)
	health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.custom_minimum_size.y = 5
	health_bar.show_percentage = false
	health_bar.step = 0.0
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color("80ddd8")
	health_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(health_bar)
	scope_label = _label(column, "Scope", 14)
	scope_label.add_theme_color_override("font_color", Color("f2c37f"))
	recipe_label = _label(column,"Recipe",14)
	scroll = ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.mouse_force_pass_scroll_events = false
	column.add_child(scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body)
	_section(body, "主特长与成长")
	trait_label = _label(body, "TraitDetail", 16)
	positive_label = _trait(body, "Positive", POSITIVE_ICON, Color("b5eee0"))
	negative_label = _trait(body, "Negative", NEGATIVE_ICON, Color("ffd0b9"))
	_section(body, "当前武器")
	var weapon_row: HBoxContainer = HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 10)
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(weapon_row)
	_weapon = TextureRect.new()
	_weapon.name = "WeaponPicture"
	_weapon.custom_minimum_size = Vector2(84, 54)
	_weapon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_weapon)
	weapon_label = _label(weapon_row, "WeaponDetail", 16)
	_section(body, "弹匣与换弹")
	reload_label = _label(body, "ReloadDetail", 16)
	_section(body, "移动与当前工作")
	move_label = _label(body, "MoveDetail", 16)
	work_label = _label(body, "WorkDetail", 16)
	sources_button = _button("Sources", "查看计算来源 ＋", _toggle_sources)
	body.add_child(sources_button)
	sources_label = _label(body, "SourcesDetail", 15)
	sources_label.hide()
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(actions)
	equipment_button = _button("Equipment", "管理装备 →", _request_equipment)
	training_button = _button("Training", "查看培养 →", _request_training)
	for button: Button in [equipment_button, training_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	close_button = _button("Close", "关闭详情 / Esc", close)
	column.add_child(close_button)
	hide()


func _toggle_sources() -> void:
	_sources_expanded = not _sources_expanded
	sources_label.visible = _sources_expanded
	sources_button.text = "收起计算来源 −" if _sources_expanded else "查看计算来源 ＋"


func _request_equipment() -> void:
	if _editable and _member_id > 0:
		equipment_requested.emit(_member_id)


func _request_training() -> void:
	if _editable and _member_id > 0:
		training_requested.emit(_member_id)


func _section(parent: Control, caption: String) -> void:
	var title: Label = _label(parent, "Section", 15)
	title.text = caption
	title.add_theme_color_override("font_color", Color("9acbdc"))


func _trait(parent: Control, node_name: String, picture: Texture2D, colour: Color) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.texture = picture
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var detail: Label = _label(row, node_name, 16)
	detail.add_theme_color_override("font_color", colour)
	return detail


func _label(parent: Control, node_name: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(node_name: String, caption: String, action: Callable) -> Button:
	var button: Button = C1HudButton.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 15)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_force_pass_scroll_events = false
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	return button
