class_name PersonaCard
extends VBoxContainer
## A stable-member selection view. Only the supplied confirmed model is shown.

signal selected(member_id: int)

var portrait: PersonaPortrait
var portrait_button: Button
var info_button: Button
var primary_label: Label
var name_label: Label
var health_label: Label
var health_bar: ProgressBar
var status_label: Label
var ammo_label: Label
var positive_label: Label
var negative_label: Label
var _panel: PanelContainer
var _content: VBoxContainer
var _identity: VBoxContainer
var _header: HBoxContainer
var _member_id: int = 0
var _built: bool = false


func _ready() -> void:
	_build()


func present(model: Dictionary, compact: bool = false) -> void:
	_build()
	_member_id = int(model.get("id", 0))
	var alive: bool = model.get("alive", false) == true
	var primary: String = text(model, "primary", "主特长未提供")
	primary_label.text = text(model, "primary_short", primary) if compact else primary
	primary_label.tooltip_text = primary
	name_label.text = "%02d  %s" % [_member_id, text(model, "name", "姓名未提供")]
	name_label.tooltip_text = name_label.text
	var hp: float = float(model.get("hp", 0.0))
	var maximum: float = float(model.get("max_hp", 0.0))
	health_label.text = "HP %d/%d · Lv%d" % [ceili(hp), ceili(maximum), int(model.get("level", 0))] if maximum > 0.0 else "HP — / — · 等级未提供"
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = clampf(hp, 0.0, maxf(maximum, 0.0))
	status_label.text = text(model, "status", "状态未提供")
	status_label.tooltip_text = status_label.text
	ammo_label.text = text(model, "ammo", "弹匣未提供")
	ammo_label.tooltip_text = ammo_label.text
	positive_label.text = "＋" + trait_name(model.get("positive", ""))
	negative_label.text = "－" + trait_name(model.get("negative", ""))
	positive_label.tooltip_text = trait_detail(model.get("positive", ""))
	negative_label.tooltip_text = trait_detail(model.get("negative", ""))
	var picture: Texture2D = model.get("portrait") as Texture2D
	portrait.present(picture, alive, primary)
	portrait_button.tooltip_text = primary + "\n" + name_label.text + "\n查看人物详情"
	info_button.tooltip_text = "查看" + text(model, "name", "该成员") + "的特长、属性与计算来源"
	_apply_size(compact)
	var colour: Color = Color("80ddd8") if alive else Color("a7b5bd")
	primary_label.add_theme_color_override("font_color", colour)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = colour
	health_bar.add_theme_stylebox_override("fill", fill)


func _build() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = true
	add_theme_constant_override("separation", 0)
	_panel = PanelContainer.new()
	_panel.name = "CardSurface"
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.mouse_force_pass_scroll_events = true
	var style: StyleBoxFlat = CampStyle.box(Color("102832"), Color("34535d"), 6)
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)
	_header = HBoxContainer.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_header)
	portrait_button = _button("Portrait", "", _select)
	_header.add_child(portrait_button)
	portrait = PersonaPortrait.new()
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_button.add_child(portrait)
	_identity = VBoxContainer.new()
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_identity)
	primary_label = _label(_identity, "Primary", 18)
	name_label = _label(_identity, "Name", 14)
	info_button = _button("Details", "详", _select)
	_header.add_child(info_button)
	health_label = _label(_content, "Health", 13)
	health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.max_value = 1.0
	health_bar.step = 0.0
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(health_bar)
	status_label = _label(_content, "Status", 13)
	ammo_label = _label(_content, "Ammo", 12)
	var traits: HBoxContainer = HBoxContainer.new()
	traits.add_theme_constant_override("separation", 8)
	traits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(traits)
	positive_label = _label(traits, "Positive", 13)
	positive_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	negative_label = _label(traits, "Negative", 13)
	negative_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	positive_label.add_theme_color_override("font_color", Color("b5eee0"))
	negative_label.add_theme_color_override("font_color", Color("ffd0b9"))
	_apply_size(false)


func _apply_size(compact: bool) -> void:
	custom_minimum_size.x = 224 if compact else 264
	_content.add_theme_constant_override("separation", 1 if compact else 4)
	_header.add_theme_constant_override("separation", 6 if compact else 10)
	_identity.add_theme_constant_override("separation", 0 if compact else 3)
	portrait_button.custom_minimum_size = Vector2.ONE * (36.0 if compact else 60.0)
	portrait_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_button.custom_minimum_size = Vector2(24, 24 if compact else 32)
	info_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	health_bar.custom_minimum_size.y = 3 if compact else 5
	for label: Label in [health_label, status_label, positive_label, negative_label]:
		label.add_theme_font_size_override("font_size", 12 if compact else 15)
	primary_label.add_theme_font_size_override("font_size", 15 if compact else 20)
	name_label.add_theme_font_size_override("font_size", 12 if compact else 15)
	ammo_label.add_theme_font_size_override("font_size", 12 if compact else 14)


func _select() -> void:
	if _member_id > 0:
		selected.emit(_member_id)


func _button(node_name: String, caption: String, action: Callable) -> Button:
	var button: Button = C1HudButton.new()
	button.name = node_name
	button.text = caption
	button.add_theme_font_size_override("font_size", 12)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_force_pass_scroll_events = true
	button.focus_mode = Control.FOCUS_ALL
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = get_theme_stylebox(state, "Button").duplicate() as StyleBox
		style.content_margin_left = 3
		style.content_margin_right = 3
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	return button


func _label(parent: Control, node_name: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(label)
	return label


static func text(model: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = model.get(key)
	return value if value is String and not value.is_empty() else fallback


static func trait_name(value: Variant) -> String:
	if value is Dictionary:
		return text(value, "name", "未提供")
	if value is String and not value.is_empty():
		return value.split("：", true, 1)[0].split("\n", true, 1)[0]
	return "未提供"


static func trait_detail(value: Variant) -> String:
	if value is Dictionary:
		return text(value, "detail", text(value, "name", "未提供"))
	return value if value is String and not value.is_empty() else "未提供"
