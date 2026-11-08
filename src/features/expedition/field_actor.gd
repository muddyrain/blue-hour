class_name FieldActor
extends Node2D
## Per-instance intent/path/health. Navigation is supplied by the expedition.

enum Activity {
	IDLE,
	MOVING,
	SEARCHING,
	DOWN,
	RECOVERING, # Outdoor work stays visible and damageable; preserve legacy enum numbers.
}

var actor_id: int = 0
var member_id: int = 0
var definition_id: StringName = &""
var is_enemy: bool = false
var health: float = 200.0
var max_health: float = 200.0
var speed: float = 125.0
var power_move_factor: float = 1.0
var motion_locked: bool = false
var cooldown: float = 0.0
var trait_shot_factor: float = 1.0
var trait_search_factor: float = 1.0
var persona_work_factor: float = 1.0
var weapon_instance_id: String = ""
var combat_view: CombatWeaponVisualV1
var magazine: WeaponMagazine
var weapon_definition: WeaponDefinition
var call_sign: String = ""
var confirmed_kills: int = 0
var damage_received: float = 0.0
var damage_gate: Callable
var visual_contact: Callable
var permanent_death: bool = false
var permanent_death_enabled: bool = false
var activity: Activity = Activity.IDLE
var path: PackedVector2Array = PackedVector2Array()
var aim: Vector2 = Vector2.ZERO
var visual: ActorVisual
var enemy_behavior: EnemyBehavior
var enemy_theme: Theme
var _enemy_tag: Label
var _path_index: int = 0


func _ready() -> void:
	visual = ActorVisual.new()
	visual.is_enemy = is_enemy
	if enemy_behavior!=null:
		visual.enemy_kind = enemy_behavior.kind
	visual.variant = actor_id % 2 if is_enemy else int({&"crew_1":0,&"crew_2":1,&"crew_3":2,&"crew_4":3,&"crew_5":4}.get(definition_id,0))
	add_child(visual)
	if enemy_behavior!=null:
		_enemy_tag = Label.new()
		_enemy_tag.theme = enemy_theme
		_enemy_tag.position = Vector2(-48,-106 if enemy_behavior.kind==EnemyRules.HEAVY else -94)
		_enemy_tag.size = Vector2(96,24)
		_enemy_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_enemy_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_enemy_tag.add_theme_font_size_override("font_size",15)
		_enemy_tag.add_theme_color_override("font_color",Color("69e2d4") if enemy_behavior.kind==EnemyRules.RUSH else Color("ffc080") if enemy_behavior.kind==EnemyRules.HEAVY else Color("cad1cc"))
		add_child(_enemy_tag)
		sync_enemy_visual()


func _draw() -> void:
	if activity == Activity.DOWN:
		return
	if not is_enemy:
		if visual != null and visual.position != Vector2.ZERO:
			draw_line(Vector2.ZERO, visual.position, Color(ActorVisual.COLOURS[actor_id % 2], 0.5), 1.0)
		return
	var display: Vector2 = visual._body.position if visual != null else Vector2.ZERO
	var bar_y: float = -94.0 if enemy_behavior != null and enemy_behavior.kind == EnemyRules.HEAVY else -78.0
	draw_rect(Rect2(Vector2(-22, bar_y) + display, Vector2(44, 5)), Color("182b35"))
	draw_rect(Rect2(Vector2(-21, bar_y + 1) + display, Vector2(42 * clampf(health / max_health, 0.0, 1.0), 3)), Color("df9a70"))
	if enemy_behavior!=null and enemy_behavior.state=="windup":
		draw_circle(Vector2.ZERO,EnemyRules.POLICY.melee_range,Color(1,0.57,0.20,0.16))
		draw_arc(Vector2.ZERO,EnemyRules.POLICY.melee_range,-PI*0.5,-PI*0.5+TAU*(1.0-enemy_behavior.windup_remaining/EnemyRules.POLICY.windup),32,Color("ffb65f"),3,true)
	elif enemy_behavior!=null and enemy_behavior.state=="rush":
		var heading: Vector2 = visual._facing
		for offset: float in [17.0,25.0]:
			var tip: Vector2 = heading*offset
			draw_polyline(PackedVector2Array([tip-heading.rotated(0.65)*8,tip,tip-heading.rotated(-0.65)*8]),Color("69e2d4"),2,true)


func command_path(points: PackedVector2Array) -> void:
	if activity in [Activity.DOWN, Activity.RECOVERING] or points.is_empty():
		return
	path = points
	_path_index = 0
	activity = Activity.MOVING


func advance(delta: float, move_path: bool = true, animate: bool = true) -> void:
	sync_enemy_visual()
	if activity == Activity.DOWN:
		if animate: visual.advance(delta, Vector2.ZERO, Vector2.ZERO)
		return
	cooldown = maxf(cooldown - delta, 0.0)
	var previous: Vector2 = position
	var remaining: float = effective_speed() * delta
	while move_path and activity == Activity.MOVING and remaining > 0.0:
		if _path_index >= path.size():
			activity = Activity.IDLE
			break
		var destination: Vector2 = path[_path_index]
		var distance: float = position.distance_to(destination)
		if distance <= remaining:
			position = destination
			remaining -= distance
			_path_index += 1
		else:
			position = position.move_toward(destination, remaining)
			remaining = 0.0
	if animate: present_motion(delta,previous)


func path_motion(distance: float, navigation: FieldNavigation) -> Vector2:
	# Consume only reached/static-visible waypoints, never the blocked proposal.
	while activity == Activity.MOVING and _path_index < path.size():
		if position.distance_to(path[_path_index]) < 0.01:
			_path_index += 1
		elif _path_index+1 < path.size() and (_path_index == 0 or (position-path[_path_index]).dot(path[_path_index]-path[_path_index-1])>=0.0) and navigation._segment_is_clear(position,path[_path_index+1]):
			_path_index += 1
		else: break
	if activity != Activity.MOVING: return Vector2.ZERO
	if _path_index >= path.size():
		activity = Activity.IDLE
		return Vector2.ZERO
	return position.direction_to(path[_path_index]) * minf(distance,position.distance_to(path[_path_index]))


func present_motion(delta: float, previous: Vector2) -> void:
	visual.contact_vector = visual_contact.call() if visual_contact.is_valid() else Vector2.INF
	visual.advance(delta, (position - previous) / maxf(delta, 0.001), aim)
	if _enemy_tag != null:
		_enemy_tag.position = Vector2(-48, -120 if enemy_behavior.kind == EnemyRules.HEAVY else -94) + visual._body.position
	queue_redraw()


func clear_order() -> void:
	if activity == Activity.DOWN:
		return
	path.clear()
	_path_index = 0
	activity = Activity.IDLE
	show()


func damage_proposal(amount: float) -> Dictionary:
	return {"member_id":member_id, "health_before":health, "health_after":maxf(health - amount, 0.0)}


func take_damage(amount: float, hit_direction: Vector2 = Vector2.LEFT) -> bool:
	if activity == Activity.DOWN or activity == Activity.SEARCHING:
		return false
	var previous_health: float = health
	if not is_enemy and damage_gate.is_valid():
		var accepted: Variant = damage_gate.call(self, damage_proposal(amount))
		if not accepted is int or int(accepted) != OK or health != previous_health:
			return false
	health = maxf(health - amount, 0.0)
	if not is_enemy:
		damage_received += previous_health - health
	visual.show_hit(hit_direction)
	if health <= 0.0:
		activity = Activity.DOWN
		permanent_death = permanent_death_enabled and damage_gate.is_valid()
		path.clear()
		visual.show_defeat()
		if _enemy_tag!=null:
			_enemy_tag.hide()
	queue_redraw()
	return true


func sync_enemy_visual() -> void:
	if visual != null and not visual._is_defeated:
		visual.contact_vector = visual_contact.call() if visual_contact.is_valid() else Vector2.INF
	if enemy_behavior==null or visual==null:
		return
	var changed: bool = visual.enemy_windup!=(enemy_behavior.state=="windup") or visual.enemy_rushing!=(enemy_behavior.state=="rush")
	visual.enemy_windup = enemy_behavior.state=="windup"
	visual.enemy_rushing = enemy_behavior.state=="rush"
	if changed:
		visual._apply_pose()
	if _enemy_tag!=null:
		_enemy_tag.visible = health>0
		_enemy_tag.text = EnemyRules.name_for(enemy_behavior.kind)+(" 预备%.1fs" % enemy_behavior.windup_remaining if visual.enemy_windup else " 冲刺" if enemy_behavior.state=="rush" else "")

func effective_speed() -> float:
	return speed * power_move_factor
