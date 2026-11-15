extends SceneTree
## Exercise real ActorVisual inputs, not just atlas index arithmetic.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for variant: int in range(5):
		var visual: ActorVisual = ActorVisual.new()
		visual.variant = variant
		root.add_child(visual)
		for octant: int in range(8):
			var direction: Vector2 = Vector2.RIGHT.rotated(octant * PI / 4.0)
			visual.advance(0.4, Vector2.ZERO, direction)
			_expect(visual._body.frame == octant * 8, "idle uses explicit octant")
			var frames: Array[int] = []
			for tick: int in range(4):
				visual.advance(0.125, direction * 125.0, direction)
				frames.append(visual._body.frame % 8)
				_expect(visual._body.texture == SurvivorVisualV1.SHEETS[variant], "correct survivor identity")
				_expect(visual._body.frame / 8 == octant and not visual._body.flip_h, "eight drawn directions without mirroring")
				_expect(visual._body.scale == Vector2.ONE * 0.22 and visual._body.offset == Vector2(0, -96), "original scale and feet root")
			frames.sort()
			_expect(frames == [1, 2, 3, 4], "walk reaches four different drawn poses")
			var prediction: Vector2 = visual.aimed_shot_offset(direction)
			visual.show_fire(direction)
			_expect(visual._body.frame == octant * 8 + 5, "fire event starts anticipation")
			_expect(visual.muzzle_offset().distance_to(prediction) < 0.001, "ballistic muzzle unchanged")
			visual.advance(0.07, Vector2.ZERO, direction)
			_expect(visual._body.frame == octant * 8 + 6, "attack extends arms")
			visual.advance(0.09, Vector2.ZERO, direction)
			_expect(visual._body.frame == octant * 8 + 7, "recovery outlasts muzzle flash")
			visual.advance(0.10, Vector2.ZERO, direction)
			_expect(visual._body.frame == octant * 8, "attack returns to idle")
			visual.show_attack(direction)
			_expect(visual._body.frame == octant * 8 + 5, "explicit attack input also connects")
			visual.advance(0.4, Vector2.ZERO, direction)
			visual.show_hit(direction)
			_expect(visual.motion_state == &"hit" and visual._body.material == null, "hit preserves complete authored pose")
			visual.advance(0.2, Vector2.ZERO, direction)
			_expect(visual._body.texture == SurvivorVisualV1.SHEETS[variant], "hit expires back to new atlas")
			_expect(not visual._upper.visible and not visual._arms.visible, "no duplicate static body parts")
			_expect(visual._head.texture == visual._body.texture and visual._head.frame == visual._body.frame, "hair occlusion follows the animated frame")
			_expect((visual._hold.transform * visual._head.transform).is_equal_approx(visual._body.transform), "hair mask cannot drift with gun bob")
		visual.show_defeat()
		visual.show_fire(Vector2.RIGHT)
		_expect(visual.motion_state == &"defeated" and not visual._weapon.visible, "fallen survivor stays down")
		visual.queue_free()
	await process_frame
	print("BH_SURVIVORS_V1 checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BH_SURVIVORS_V1 " + label)
