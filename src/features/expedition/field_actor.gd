class_name FieldActor
extends Node2D
## Per-instance intent/path/health. Navigation is supplied by the expedition.

enum Activity {
	IDLE,
	MOVING,
	SEARCHING,
	DOWN,
}

var actor_id: int = 0
var is_enemy: bool = false
var health: float = 200.0
var max_health: float = 200.0
var speed: float = 125.0
var cooldown: float = 0.0
var weapon_instance_id: String = ""
var weapon_definition: WeaponDefinition
var call_sign: String = ""
var confirmed_kills: int = 0
var damage_received: float = 0.0
var activity: Activity = Activity.IDLE
var path: PackedVector2Array = PackedVector2Array()
var aim: Vector2 = Vector2.ZERO
var visual: ActorVisual
var _path_index: int = 0


func _ready() -> void:
	visual = ActorVisual.new()
	visual.is_enemy = is_enemy
	visual.variant = actor_id % 2
	add_child(visual)


func _draw() -> void:
	if activity == Activity.DOWN:
		return
	if not is_enemy:
		if visual != null and visual.position != Vector2.ZERO:
			draw_line(Vector2.ZERO, visual.position, Color(ActorVisual.COLOURS[actor_id % 2], 0.5), 1.0)
		return
	draw_rect(Rect2(-22, -78, 44, 5), Color("182b35"))
	draw_rect(Rect2(-21, -77, 42 * clampf(health / max_health, 0.0, 1.0), 3), Color("df9a70") if is_enemy else Color("8bd4b3"))


func command_path(points: PackedVector2Array) -> void:
	if activity == Activity.DOWN or points.is_empty():
		return
	path = points
	_path_index = 0
	activity = Activity.MOVING


func advance(delta: float) -> void:
	if activity == Activity.DOWN:
		visual.advance(delta, Vector2.ZERO, Vector2.ZERO)
		return
	cooldown = maxf(cooldown - delta, 0.0)
	var previous: Vector2 = position
	var remaining: float = speed * delta
	while activity == Activity.MOVING and remaining > 0.0:
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
	visual.advance(delta, (position - previous) / maxf(delta, 0.001), aim)
	queue_redraw()


func clear_order() -> void:
	if activity == Activity.DOWN:
		return
	path.clear()
	_path_index = 0
	activity = Activity.IDLE
	show()


func take_damage(amount: float, hit_direction: Vector2 = Vector2.LEFT) -> void:
	if activity == Activity.DOWN or activity == Activity.SEARCHING:
		return
	var previous_health: float = health
	health = maxf(health - amount, 0.0)
	if not is_enemy:
		damage_received += previous_health - health
	visual.show_hit(hit_direction)
	if health <= 0.0:
		activity = Activity.DOWN
		path.clear()
		visual.show_defeat()
	queue_redraw()
