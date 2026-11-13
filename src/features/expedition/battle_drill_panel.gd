class_name BattleDrillPanel
extends PanelContainer
## Visible, opt-in rehearsal controls. Enemy attributes and attacks remain owned by Expedition.

var expedition: Expedition
var _status: Label
var _deployed: Array[int] = []


func _ready() -> void:
	position = Vector2(16,150)
	custom_minimum_size = Vector2(326,0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	add_theme_stylebox_override("panel",CampStyle.box(Color("10232d"),Color("f2c37f"),1))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	add_child(column)
	_status = Label.new()
	_status.custom_minimum_size.x = 310
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size",15)
	column.add_child(_status)
	refresh()


func refresh() -> void:
	if _status == null:
		return
	_status.text = "Blue Hour 暂行饥饿规则 / 隔离测试\nPROJECT_TEMP：缺一粮减员一人\n冻结哈希选人；死者原武器闲置"
	if expedition.battle_seed != "NONE":
		_status.text += "\n演练种子：初始两人4HP / 食物12"
