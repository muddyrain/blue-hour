class_name BattleDrillPanel
extends PanelContainer
## Visible, opt-in rehearsal controls. Enemy attributes and attacks remain owned by Expedition.

var expedition: Expedition
var buttons: Array[Button] = []
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
	if expedition.battle_drill:
		for actor: FieldActor in expedition.survivors:
			var id: int = actor.member_id
			var button: Button = C1HudButton.new()
			button.name = "Contact%d" % id
			button.text = "%02d 接敌演练（近敌36像素）" % id
			button.custom_minimum_size.y = 36
			button.pressed.connect(_deploy.bind(id))
			column.add_child(button)
			button.set_meta("member_id",id)
			buttons.append(button)
	refresh()


func refresh() -> void:
	if _status == null:
		return
	_status.text = "隔离生存测试版 · 阵亡不复活\n缺粮策略未定；死者装备保留为闲置候选"
	if expedition.hunger_trial:
		_status.text = "Blue Hour 暂行饥饿规则 / 隔离测试\nPROJECT_TEMP：缺一粮减员一人\n冻结哈希选人；死者原武器闲置"
	if expedition.battle_seed != "NONE":
		_status.text += "\n演练种子：初始两人4HP / 食物12"
	if expedition.battle_drill:
		if expedition.battle_seed == "NONE":
			_status.text += "\n演练保持来源HP/食物；由按钮明确部署"
		_status.text += "\n按钮仅部署近敌，之后是真实AI/原伤害"
	for button: Button in buttons:
		var id: int = int(button.get_meta("member_id"))
		var actor: FieldActor = _member(id)
		button.disabled = actor == null or actor.health <= 0 or not actor.visible or id in _deployed


func _member(id: int) -> FieldActor:
	for actor: FieldActor in expedition.survivors:
		if actor.member_id == id:
			return actor
	return null


func _deploy(id: int) -> void:
	var actor: FieldActor = _member(id)
	if not expedition.battle_drill or expedition.phase==Expedition.Phase.FINISHED or actor == null or actor.health <= 0 or not actor.visible or id in _deployed:
		return
	for offset: Vector2 in [Vector2(36,0),Vector2(-36,0),Vector2(0,36),Vector2(0,-36)]:
		var point: Vector2 = actor.position+offset
		if not expedition.navigation.is_clear(point) or expedition.navigation.path_between(point,actor.position).is_empty():
			continue
		var enemy: FieldActor = expedition._make_actor(true,10000+id,point)
		expedition.enemies.append(enemy)
		_deployed.append(id)
		print("BH_BATTLE_DRILL member=%d enemy=%d point=%s source=EXPLICIT_REHEARSAL" % [id,enemy.actor_id,point])
		refresh()
		return
