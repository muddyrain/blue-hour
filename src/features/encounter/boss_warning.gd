class_name BossWarning
extends Node2D
## Read-only world-space warning. It never emits damage, spawning or victory facts.

var _state: Dictionary = {}
var _health: float = 0.0
var _maximum: float = BossDefinition.POLICY.health


func update_state(value: Dictionary, boss_position: Vector2, health: float, max_health: float) -> void:
	_state = value.duplicate(true)
	position = boss_position
	_health = health
	_maximum = max_health
	queue_redraw()


func _draw() -> void:
	if _state.is_empty(): return
	var dead: bool = _health<=0.0 or _state.state=="dead"
	var colour: Color = Color("f6b44e") if not dead else Color("98cda7")
	draw_arc(Vector2.ZERO,23.0,0.0,TAU,48,colour,3.0,true)
	for index: int in range(4):
		var direction: Vector2 = Vector2.RIGHT.rotated(float(index)*PI/2.0)
		draw_line(direction*24.0,direction*31.0,colour,3.0,true)
	if _state.state in ["melee_windup","slam_windup"] and not dead:
		var slam: bool = _state.state=="slam_windup"
		var center: Vector2 = Vector2(_state.point[0],_state.point[1])-position if slam else Vector2.ZERO
		var radius: float = BossDefinition.POLICY.slam_radius if slam else BossDefinition.POLICY.melee_range
		var duration: float = BossDefinition.POLICY.slam_windup if slam else BossDefinition.POLICY.melee_windup
		draw_circle(center,radius,Color(0.95,0.18,0.12,0.22))
		draw_arc(center,radius,0.0,TAU,64,Color("ff6b52"),2.5,true)
		draw_arc(center,radius-5.0,-PI/2.0,-PI/2.0+TAU*(1.0-float(_state.remaining)/duration),64,Color("ffe3a4"),3.0,true)
		draw_line(center+Vector2(-8,0),center+Vector2(8,0),Color("ffecda"),2.0,true)
		draw_line(center+Vector2(0,-8),center+Vector2(0,8),Color("ffecda"),2.0,true)
	var label: String = BossDefinition.DISPLAY_NAME+" · "+str(ceili(maxf(0.0,_health)))+" / "+str(ceili(_maximum))
	if dead: label = "首领已击败 · 返回巴士"
	elif _state.state=="slam_windup": label = "落击预警 · 离开红圈"
	elif _state.state=="melee_windup": label = "重击预警 · 拉开距离"
	draw_rect(Rect2(-70,-102,140,7),Color("241c22"))
	draw_rect(Rect2(-70,-102,140*clampf(_health/_maximum,0.0,1.0),7),colour)
	draw_string(ThemeDB.fallback_font,Vector2(-125,-110),label,HORIZONTAL_ALIGNMENT_CENTER,250,16,Color("fff0d5"))
