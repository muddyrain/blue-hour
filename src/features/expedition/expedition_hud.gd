class_name ExpeditionHud
extends CanvasLayer
## Maps existing sortie state to C1.1; owns no gameplay timer or audio service.

signal pause_requested
signal extraction_requested
signal help_changed(expanded: bool)

const HudScene: PackedScene = preload("res://src/features/expedition_hud/expedition_hud.tscn")
const BUS_ACTIVITY: Dictionary[String, String] = {
	"approaching_search":"前往搜集点", "searching":"搜集中",
	"recovering":"回收中", "gathering":"前往巴士",
}

var ui_theme: Theme
var view: C1ExpeditionHud
var _root: Control
var _time_bar: ProgressBar
var _time_fill: StyleBoxFlat
var _burst_warning: Label
var _base_help: String


func _ready() -> void:
	layer = 10
	view = HudScene.instantiate() as C1ExpeditionHud
	add_child(view)
	_root = view
	view.pause_requested.connect(func() -> void: pause_requested.emit())
	view.resume_requested.connect(func() -> void: pause_requested.emit())
	view.bus_start_requested.connect(func() -> void: extraction_requested.emit())
	view._help_button.pressed.connect(func() -> void: help_changed.emit(view._help.visible))
	_base_help = (view._help.get_node("HelpText") as Label).text
	_burst_warning = view._label(view._time_box, "BurstWarning", 14)
	_burst_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_burst_warning.add_theme_color_override("font_color", Color("ffb44b"))
	_burst_warning.hide()
	# Preserve M2-01's ratio and gradient beside C's independent sortie time text.
	_time_bar = ProgressBar.new()
	_time_bar.name = "SortieTimeRatio"
	_time_bar.custom_minimum_size.y = 8
	_time_bar.max_value = 1.0
	_time_bar.step = 0.0
	_time_bar.show_percentage = false
	_time_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color("13120f")
	_time_bar.add_theme_stylebox_override("background", track)
	_time_fill = StyleBoxFlat.new()
	_time_bar.add_theme_stylebox_override("fill", _time_fill)
	view._time_box.add_child(_time_bar)


func refresh(state: Dictionary) -> void:
	var seconds: int = state["seconds"]
	var bus_text: String = state["engine"]
	var enabled: bool = state["can_extract"]
	var gathering: bool = state.get("can_gather", false)
	var boarding: Dictionary = state.get("boarding", {})
	var threat: Dictionary = state.get("threat", {})
	var night: bool = threat.get("enabled",false) and int(threat.get("stage",0)) >= ThreatDirector.Stage.NIGHT
	var display_seconds: int = floori(float(threat.get("overtime",0.0))) if night else seconds
	var time_label: String = "夜间经过" if night else "出击时间"
	var compact_hint: String = ""
	if threat.get("enabled", false):
		time_label = "已入夜" if night else "距入夜"
		compact_hint = time_label
	var action: String = "发动巴士"
	var bus_waiting: PackedStringArray = []
	if not enabled:
		action = bus_text
	if gathering:
		action = "集合至巴士"
		bus_text = "已集合 %d/%d" % [boarding.arrived, boarding.required]
		for member: Dictionary in boarding.get("waiting", []):
			var activity: String = BUS_ACTIVITY.get(member.activity, "未集合")
			bus_waiting.append("等待%s · %s" % [SearchWorkView.short_call_sign(member.call_sign), activity])
		if boarding.get("rescue_waiting", false):
			bus_waiting.append("等待救援对象")
	elif state.get("engine_running", false):
		bus_waiting.append("请前往巴士旁集合")
	var resources: String = "货币 %d  ·  食物 %d\n携带：钱%d · 粮%d · 武器%d" % [
		state["cash"], state["food"], state["loot"], state["food_loot"], int(state.get("weapon_loot", 0))]
	if int(state.get("toolbox", -1)) >= 0:
		resources = "货币 %d · 食物 %d\n携带：钱%d 粮%d 武器%d 工具箱%d" % [state["cash"], state["food"],
			state["loot"], state["food_loot"], int(state.get("weapon_loot", 0)), int(state.toolbox)]
	view.refresh({
		"resource_text":resources,
		"objective":state.get("objective",""), "mission_title":state["mission_title"], "day_text":"第 %d 天" % state["day"],
		"search_progress_text":"%d / %d" % [state["sites_searched"],state["sites_total"]],
		"defeated_text":str(state["kills"]), "currency_text":str(state["cash"]),
		"currency_delta_text":"+%d 携带 · 食物 %d（携带+%d）· 武器+%d" % [state["loot"],state["food"],state["food_loot"],int(state.get("weapon_loot",0))], "paused":state["paused"],
		"survivors":state["members"],
		"exploration_objectives":state.get("exploration_objectives",[]),
		"time":{"label":time_label,
			"text":("+" if night else "") + "%02d:%02d" % [display_seconds / 60, display_seconds % 60],
			"compact_hint":compact_hint,
			"hint":threat.get("hint", "") if threat.get("enabled", false) else ""},
		"bus_status_text":"巴士就绪" if enabled else bus_text,
		"bus_waiting_text":"\n".join(bus_waiting), "bus_count_visible":gathering,
		"bus_action_label":action, "bus_action_enabled":enabled or gathering,
		"status_hint":state["notice"] if state["notice_visible"] else "",
	})
	_burst_warning.text = state.get("burst_warning", "")
	_burst_warning.visible = not _burst_warning.text.is_empty()
	var fraction: float = state["time_fraction"]
	# Existing TMP-114 interpolation is a display choice, not night rules.
	var colour: Color = ExpeditionHudTheme.AMBER.lerp(ExpeditionHudTheme.DANGER, clampf((0.2 - fraction) / 0.2, 0.0, 1.0))
	view._time_text.add_theme_color_override("font_color", colour)
	_time_fill = _time_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_time_fill.bg_color = colour
	_time_bar.value = fraction
	view._time_hint.add_theme_color_override("font_color", colour)
	view._time_box.tooltip_text = "Blue Hour候选：随时间增加普通敌人增援；精确原作阈值/倍率未校准。暂停冻结，无自动失败。"
	var help: Label = view._help.get_node("HelpText") as Label
	help.text = _base_help
	help.text += "\n敌种候选：疾奔者近处加速；重压者预警0.5秒后重击，移出脚底圆环可避。"
	help.text += "\n" + String(state.get("route_hint", ""))
	help.text += "\n先发动，等待时点「集合至巴士」；搜集完成后归队。"
	help.text += "\nEsc：暂停菜单、定位巴士与退出风险提示。"
	help.text += "\n威胁随时间上升；归零仍可撤离，原作夜间参数待校准。"
	view._time_box.tooltip_text = "威胁随时间增加；暂停会冻结计时。巴士就绪后须发动并集合队员。"
	help.text = help.text.replace("敌种候选：", "敌种：").replace("；归零仍可撤离，原作夜间参数待校准。", "；计时归零仍可撤离。")


func hide_screen() -> void:
	view.hide_screen()
