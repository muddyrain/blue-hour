extends SceneTree
## Regressions for normal-only presentation discontinuities; native movies are separate.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor: FieldActor = FieldActor.new()
	actor.is_enemy = true
	actor.enemy_behavior = EnemyBehavior.new()
	actor.enemy_behavior.kind = EnemyRules.NORMAL
	root.add_child(actor)
	var visual: ActorVisual = actor.visual
	visual.advance(0.20, Vector2.RIGHT * 34.0, Vector2.ZERO)
	var clock: float = visual._walk_clock
	var frame: int = visual._body.frame
	visual.advance(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
	_expect(visual._walk_clock == clock and visual._body.frame == frame, "one-tick navigation stop preserves gait phase and drawn pose")
	visual.advance(0.20, Vector2.ZERO, Vector2.ZERO)
	_expect(visual.motion_state == &"idle" and visual._walk_clock == 0.0, "sustained stop returns to original idle")
	visual.advance(0.20, Vector2.RIGHT * 34.0, Vector2.ZERO)
	var switches: int = 0
	var previous: int = visual.presentation_state().body_octant
	for tick: int in range(120):
		var heading: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(22.5 + (0.75 if tick % 2 == 0 else -0.75)))
		visual.advance(1.0 / 60.0, heading * 34.0, Vector2.ZERO)
		var octant: int = visual.presentation_state().body_octant
		switches += int(octant != previous)
		previous = octant
	_expect(switches <= 1, "tiny boundary noise does not alternate normal direction every frame")
	for octant: int in range(8):
		var heading: Vector2 = Vector2.RIGHT.rotated(octant * PI / 4.0)
		visual.advance(0.2, heading * 34.0, Vector2.ZERO)
		_expect(visual.presentation_state().body_octant == octant, "real 45-degree turn still changes direction " + str(octant))
	visual.contact_vector = Vector2(24, 0)
	visual.advance(1.0 / 60.0, Vector2.ZERO, Vector2.RIGHT)
	var offset: Vector2 = visual._contact_offset()
	visual.contact_vector = Vector2(-24, 0)
	visual.advance(1.0 / 60.0, Vector2.ZERO, Vector2.RIGHT)
	_expect(offset.distance_to(visual._contact_offset()) <= 2.0, "contact side change is bounded instead of a36-pixel jump")
	for tick: int in range(60): visual.advance(1.0 / 60.0, Vector2.ZERO, Vector2.RIGHT)
	_expect(visual._contact_offset().is_equal_approx(Vector2(18, 0)), "contact spacing still reaches the original target")
	visual.show_attack(Vector2.RIGHT)
	_expect(visual.motion_state == &"attack" and visual._body.frame / 5 == 5, "original contact pose remains tied to attack event")
	visual.show_hit(Vector2.LEFT)
	_expect(visual.motion_state == &"hit" and visual._body.frame / 5 == 6, "original hit priority and frame retained")
	visual.advance(0.4, Vector2.RIGHT * 34.0, Vector2.ZERO)
	_expect(visual.motion_state == &"move", "attack and hit expire into movement")
	var survivor: ActorVisual = ActorVisual.new()
	root.add_child(survivor)
	survivor.advance(0.2, Vector2.RIGHT * 125.0, Vector2.ZERO)
	survivor.advance(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO)
	_expect(survivor._walk_clock == 0.0 and survivor.motion_state == &"idle", "survivor movement/weapon presentation follows the unchanged path")
	print("BH_NORMAL_STABILITY checks=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)


func _expect(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error("BH_NORMAL_STABILITY " + label)
