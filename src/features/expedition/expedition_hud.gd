class_name ExpeditionHud
extends CanvasLayer
## Maps existing sortie state to C1.1; owns no gameplay timer or audio service.

signal pause_requested
signal extraction_requested
signal help_changed(expanded: bool)

const HudScene: PackedScene = preload("res://src/features/expedition_hud/expedition_hud.tscn")

var ui_theme: Theme
var view: C1ExpeditionHud
var _root: Control
var _time_bar: ProgressBar
var _time_fill: StyleBoxFlat
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
	# Preserve M2-01's ratio and gradient beside C's independent sortie time text.
	_time_bar = ProgressBar.new()
	_time_bar.name = "SortieTimeRatio"
	_time_bar.custom_minimum_size.y = 4
	_time_bar.max_value = 1.0
	_time_bar.step = 0.0
	_time_bar.show_percentage = false
	_time_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color("344d54")
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
	var practice: bool = state["practice"]
	var threat: Dictionary = state.get("threat", {})
	var night: bool = threat.get("enabled",false) and int(threat.get("stage",0)) >= ThreatDirector.Stage.NIGHT
	var display_seconds: int = floori(float(threat.get("overtime",0.0))) if night else seconds
	var action: String = "结束交火练习" if practice else "发动巴士"
	if not enabled:
		action = bus_text
	if gathering:
		action = "集合至巴士"
		bus_text = "%s · %d / %d 已到" % ["集合中" if boarding.ordered else "等待集合", boarding.arrived, boarding.required]
	view.refresh({
		"mission_title":state["mission_title"], "day_text":"第 %d 天" % state["day"],
		"search_progress_text":"%d / %d" % [state["sites_searched"],state["sites_total"]],
		"defeated_text":str(state["kills"]), "currency_text":str(state["cash"]),
		"currency_delta_text":"+%d 携带 · 食物 %d（携带+%d）· 武器+%d" % [state["loot"],state["food"],state["food_loot"],int(state.get("weapon_loot",0))], "paused":state["paused"],
		"survivors":state["members"],
		"time":{"label":"夜间经过 · 候选" if night else ("出击时间 · 候选" if threat.get("enabled", false) else "出击时间"),
			"text":("+" if night else "") + "%02d:%02d" % [display_seconds / 60, display_seconds % 60],
			"hint":threat.get("hint", "") if threat.get("enabled", false) else ""},
		"bus_status_text":"交火练习" if practice else ("巴士就绪" if enabled else bus_text),
		"bus_action_label":action, "bus_action_enabled":enabled or gathering,
		"status_hint":state["notice"] if state["notice_visible"] else "",
	})
	var fraction: float = state["time_fraction"]
	# Existing TMP-114 interpolation is a display choice, not night rules.
	var colour: Color = Color("ed9682").lerp(Color("f1d18e"), fraction * 2.0) if fraction < 0.5 else Color("f1d18e").lerp(Color("9acbdc"), (fraction - 0.5) * 2.0)
	view._time_text.add_theme_color_override("font_color", colour)
	_time_fill.bg_color = colour
	_time_bar.value = fraction
	view._time_hint.add_theme_color_override("font_color", colour)
	view._time_box.tooltip_text = "Blue Hour候选：随时间增加普通敌人增援；精确原作阈值/倍率未校准。暂停冻结，无自动失败。"
	var help: Label = view._help.get_node("HelpText") as Label
	help.text = _base_help
	if not practice:
		help.text += "\n" + String(state.get("route_hint", ""))
		help.text += "\n先发动，等待时点「集合至巴士」；搜集完成后归队。"
		help.text += "\n威胁随时间上升；归零仍可撤离，原作夜间参数待校准。"
	if practice:
		help.text += "\n练习：1/2 换枪；I/J/K/L 来袭；H 交错；U 远距靶"


func hide_screen() -> void:
	view.hide_screen()
