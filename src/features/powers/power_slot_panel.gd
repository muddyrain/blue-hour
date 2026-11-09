class_name PowerSlotPanel
extends VBoxContainer
## Read-only special-slot feedback; no gameplay clock or inventory ownership.

signal activation_requested

const ICONS: Dictionary = {
	"speed_boost_v1": preload("res://assets/powers/speed_boost_v1.svg"),
	"map_freeze_v1": preload("res://assets/powers/map_freeze_v1.svg"),
	"": preload("res://assets/powers/empty.svg"),
}

var activation_button: Button
var duration_bar: ProgressBar
var slot_index: int = 0


func _ready() -> void:
	_build()


func present(title: String, status: String, remaining: float, duration: float, enabled: bool, ability_id: String) -> void:
	_build()
	var key: String = str(3 + slot_index)
	var short_name: String = "冻结" if ability_id == SpecialPowers.FREEZE else "疾行"
	var state: String = "%.1fs" % remaining if remaining > 0.0 else status
	activation_button.text = key + "  空槽" if ability_id.is_empty() else "%s  %s\n%s" % [key,short_name,state]
	activation_button.icon = ICONS.get(ability_id, ICONS[""])
	var effect: String = "空槽：先完成装备行动并归航确认，再到营地装配。"
	if ability_id == "speed_boost_v1":
		effect = "全队有效移动速度 ×%s，持续 %s 秒；不加速攻击、换弹或工作。" % [str(SpecialPowers.POLICY[ability_id].move_factor), str(duration)]
	elif ability_id == "map_freeze_v1":
		effect = "全场活敌人暂停行动 %s 秒，期间新敌人同样受冻；已落地毒区继续生效。" % str(duration)
	activation_button.tooltip_text = title + "\n" + effect + "\n" + status + "\n每次出击一次；营地装配。\n" + key + " 或点击立即释放。"
	activation_button.disabled = not enabled
	activation_button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		activation_button.release_focus()
	duration_bar.visible = remaining > 0.0 and duration > 0.0
	duration_bar.value = clampf(remaining / duration, 0.0, 1.0) if duration > 0.0 else 0.0


func _build() -> void:
	if activation_button != null:
		return
	name = "PowerSlotPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 72
	add_theme_constant_override("separation", 3)
	activation_button = C1HudButton.new()
	activation_button.name = "ActivatePower"
	activation_button.custom_minimum_size = Vector2(72, 62)
	activation_button.icon = ICONS[""]
	activation_button.expand_icon = true
	activation_button.add_theme_constant_override("icon_max_width",28)
	activation_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	activation_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	activation_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	activation_button.add_theme_font_size_override("font_size", 12)
	activation_button.add_theme_color_override("font_disabled_color", Color("b8cbd2"))
	activation_button.add_theme_color_override("icon_disabled_color", Color("bddfe8"))
	activation_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	activation_button.mouse_filter = Control.MOUSE_FILTER_STOP
	activation_button.mouse_force_pass_scroll_events = false
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = get_theme_stylebox(state, "Button").duplicate() as StyleBox
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		activation_button.add_theme_stylebox_override(state, style)
	activation_button.pressed.connect(func() -> void: activation_requested.emit())
	add_child(activation_button)
	duration_bar = ProgressBar.new()
	duration_bar.name = "EffectRemaining"
	duration_bar.max_value = 1.0
	duration_bar.step = 0.0
	duration_bar.show_percentage = false
	duration_bar.custom_minimum_size.y = 5
	duration_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color("a7e7ed")
	duration_bar.add_theme_stylebox_override("fill", fill)
	add_child(duration_bar)
	duration_bar.hide()
