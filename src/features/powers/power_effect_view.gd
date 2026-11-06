class_name PowerEffectView
extends Node2D
## Only derived foot effects. The original simulation supplies all positions/clocks.

var _actors: Array[Dictionary] = []
var _enemies: Array[Dictionary] = []
var _speed_active: bool = false
var _freeze_active: bool = false
var _clock: float = 0.0


func present(actors: Array[Dictionary], enemies: Array[Dictionary], speed_active: bool, freeze_active: bool, clock: float) -> void:
	_actors = actors.duplicate(true)
	_enemies = enemies.duplicate(true)
	_speed_active = speed_active
	_freeze_active = freeze_active
	_clock = clock
	queue_redraw()


func _draw() -> void:
	if _speed_active:
		for actor: Dictionary in _actors:
			if actor.get("alive", false) != true or actor.get("moving", false) != true or not actor.get("position") is Vector2:
				continue
			var point: Vector2 = actor.position
			var drift: float = fmod(_clock * 20.0, 10.0)
			var tint: Color = Color("b6f4e2")
			tint.a = 0.8
			for side: int in [-1, 1]:
				var start: Vector2 = point + Vector2(float(side) * 13.0, 2.0 + drift * 0.15)
				draw_line(start + Vector2(-12.0 - drift, 3.0), start, tint, 2.0, true)
				draw_line(start + Vector2(-7.0 - drift, -2.0), start + Vector2(4.0, -4.0), tint, 1.2, true)
			draw_arc(point + Vector2(0, 2), 15.0, PI * 0.15, PI * 0.85, 12, Color(0.5, 0.9, 0.8, 0.6), 1.4, true)
	if _freeze_active:
		for enemy: Dictionary in _enemies:
			if enemy.get("alive", false) != true or not enemy.get("position") is Vector2:
				continue
			var point: Vector2 = enemy.position
			var ice: Color = Color("c2f3ff")
			draw_arc(point, 18.0, PI * 0.05, PI * 0.95, 16, ice, 1.5, true)
			draw_arc(point, 18.0, PI * 1.1, PI * 1.9, 16, ice, 1.5, true)
			var mark: Vector2 = point + Vector2(20.0, -35.0)
			for spoke: int in range(3):
				var direction: Vector2 = Vector2.from_angle(float(spoke) * PI / 3.0)
				draw_line(mark - direction * 5.5, mark + direction * 5.5, ice, 1.5, true)
			# Open edge marks leave the enemy silhouette and attack telegraphs readable.
			draw_line(point + Vector2(-18, -12), point + Vector2(-21, -24), Color(0.6, 0.85, 1.0, 0.75), 2.0, true)
			draw_line(point + Vector2(18, -12), point + Vector2(21, -24), Color(0.6, 0.85, 1.0, 0.75), 2.0, true)
