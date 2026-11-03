extends SceneTree
## All real atlas directions/actions, moving fire and canonical ballistic grip.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for family: int in range(8):
		var actor: FieldActor = FieldActor.new()
		actor.is_enemy = family >= 5
		actor.definition_id = StringName("crew_%d" % (family + 1)) if family < 5 else &""
		if actor.is_enemy:
			actor.enemy_behavior = EnemyBehavior.new()
			actor.enemy_behavior.kind = [EnemyRules.NORMAL, EnemyRules.RUSH, EnemyRules.HEAVY][family - 5]
		root.add_child(actor)
		var visual: ActorVisual = actor.visual
		var ordinary_v1: bool = family == 5 and NormalInfectedV1.enabled()
		for oct: int in range(8):
			var direction: Vector2 = Vector2.RIGHT.rotated(oct * PI / 4.0)
			visual.advance(0.4, direction * (34.0 if actor.is_enemy else 125.0), direction)
			_expect(visual.presentation_state().aim_octant == oct, "all eight actual aim selections")
			if ordinary_v1:
				var source_name: String = ["e", "se", "s", "se", "e", "ne", "n", "ne"][oct]
				_expect(visual._body.texture.resource_path.ends_with("/" + source_name + ".png"), "actual V1 directional source sheet")
			else:
				_expect(visual._body.frame % visual._body.hframes == (MotionAtlas.LEFT_COLUMNS[oct] if family < 5 and MotionAtlas.LEFT_COLUMNS.has(oct) else MotionAtlas.COLUMNS[oct]), "actual drawn directional frame")
			_expect(visual._body.flip_h == (family >= 5 and oct in [3, 4, 5]), "only disclosed enemy mirror")
			if not actor.is_enemy:
				visual.show_fire(direction)
				_expect(visual.motion_state == &"move_fire" and visual._upper.frame / visual._upper.hframes == 4, "separate firing upper pose while legs walk")
				_expect(visual.presentation_state().hand.distance_to(visual.presentation_state().grip) < 0.001, "drawn trigger hand reaches canonical grip")
				var prediction: Vector2 = visual.aimed_shot_offset(direction)
				visual.show_fire(direction)
				_expect(prediction.distance_to(visual.muzzle_offset()) < 0.001, "eight-direction prediction equals rendered muzzle")
			else:
				visual.show_attack(direction)
				_expect(visual._body.frame == 7 if ordinary_v1 else visual._body.frame / 5 == 5, "front back diagonal contact at authority event")
				visual.advance(0.2, Vector2.ZERO, direction)
				_expect(visual._body.frame == 9 if ordinary_v1 else visual._body.frame / 5 == 4, "contact transitions to recovery")
			actor.take_damage(1.0, direction)
			_expect(visual.motion_state == &"hit" and (visual._body.frame == 10 if ordinary_v1 else visual._body.frame / 5 == 6 if actor.is_enemy else visual._upper.frame / visual._upper.hframes == 5), "actual damage chooses dedicated hit pose")
			visual.advance(0.4, Vector2.ZERO, direction)
			_expect(visual.motion_state == &"idle", "events expire without stale pose")
		if actor.is_enemy:
			visual.contact_vector = Vector2(24, 0)
			visual._apply_pose()
			_expect(actor.position == Vector2.ZERO and visual._body.position.x < 0, "display contact never moves logical feet")
			visual.contact_vector = Vector2.ZERO
			visual._apply_pose()
			_expect(is_equal_approx(visual._body.position.length(), 18.0), "exact shared feet retain contact spacing using facing")
			var contact_before: Vector2 = visual._contact_offset()
			visual.show_defeat()
			_expect(visual._body.position == contact_before, "corpse retains contact display anchor without18px jump")
		actor.take_damage(999.0)
		var death_facing: Vector2 = visual._facing
		visual.show_attack(Vector2.UP)
		visual.show_fire(Vector2.DOWN)
		visual.show_hit(Vector2.RIGHT)
		_expect(visual.motion_state == &"defeated" and visual._facing == death_facing and not visual._weapon.visible, "late events cannot revive or turn corpse")
		actor.queue_free()
	await process_frame
	print("BH_MOTION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BH_MOTION " + label)
