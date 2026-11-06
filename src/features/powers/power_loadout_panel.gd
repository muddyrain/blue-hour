class_name PowerLoadoutPanel
extends VBoxContainer
## Camp-only choices. The existing edit transaction owns the result.
signal requested(ability_id: String)
var choices: Dictionary[String,Button]={}
var status: Label

func _ready() -> void:
	var row: HBoxContainer=HBoxContainer.new()
	add_child(row)
	var title: Label=Label.new()
	title.text="特殊能力 · 独立1槽"
	row.add_child(title)
	for id: String in ["speed_boost_v1","map_freeze_v1",""]:
		var button: Button=Button.new()
		button.text=SpecialPowers.POLICY[id].name if not id.is_empty() else "卸下"
		button.custom_minimum_size=Vector2(130,40)
		if not id.is_empty():
			button.icon=load("res://assets/powers/%s.svg"%id)
			button.expand_icon=true
			button.add_theme_constant_override("icon_max_width",28)
		button.pressed.connect(func()->void: requested.emit(id))
		row.add_child(button)
		choices[id]=button
	status=Label.new()
	status.add_theme_font_size_override("font_size",15)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(status)

func present(camp: Dictionary, editable: bool) -> void:
	visible=PowerState.enabled(camp)
	if not visible: return
	var value: Dictionary=camp.journey.build.powers
	for id: String in choices:
		var owned: bool=id.is_empty() or id in value.owned
		choices[id].disabled=not editable or not owned or value.slot==id
		choices[id].focus_mode=Control.FOCUS_NONE if choices[id].disabled else Control.FOCUS_ALL
		if choices[id].disabled: choices[id].release_focus()
		choices[id].text=(SpecialPowers.POLICY[id].name if not id.is_empty() else "卸下")+(" · 已装配" if value.slot==id and not id.is_empty() else " · 未拥有" if not owned else "")
	status.text="疾行号令：全队移动×%.1f / %d秒；全域冻结：敌人停止行动 / %d秒。每日共1次，出击中不可换装。\n已拥有 %d/2 · %s"%[SpecialPowers.POLICY.speed_boost_v1.move_factor,int(SpecialPowers.POLICY.speed_boost_v1.duration),int(SpecialPowers.POLICY.map_freeze_v1.duration),value.owned.size(),"装备行动主站点搜获，归航确认入库。" if value.owned.is_empty() else "当前："+(SpecialPowers.POLICY[value.slot].name if not value.slot.is_empty() else "未装配")]
