extends SceneTree
## New art contract through the real ordinary actor, not a synthetic pose counter.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_expect(NormalInfectedV1.enabled(), "candidate uses V1 by default")
	var actor: FieldActor = FieldActor.new()
	actor.is_enemy = true
	actor.enemy_behavior = EnemyBehavior.new()
	actor.enemy_behavior.kind = EnemyRules.NORMAL
	root.add_child(actor)
	var visual: ActorVisual = actor.visual
	for octant: int in range(8):
		var heading: Vector2 = Vector2.RIGHT.rotated(octant*PI/4.0)
		visual.advance(0.4,heading*34.0,heading)
		var expected: String = ["e","se","s","se","e","ne","n","ne"][octant]
		_expect(visual._body.texture.resource_path.ends_with("/"+expected+".png"), "direction selects independently drawn source "+str(octant))
		_expect(visual._body.flip_h == (octant in [3,4,5]), "only disclosed three mirrors "+str(octant))
		_expect(visual._body.hframes == 4 and visual._body.vframes == 4 and visual._body.frame in range(1,7), "real walk frame stays in new layout")
		var frames: Array[int] = []
		for tick: int in range(6):
			visual.advance(0.125,heading*34.0,heading)
			if visual._body.frame not in frames: frames.append(visual._body.frame)
		_expect(frames.size() == 6, "six distinct drawn walk poses reached in one cycle")
		visual.show_attack(heading)
		_expect(visual._body.frame == 7, "contact visible immediately at original event")
		visual.advance(0.10,Vector2.ZERO,heading)
		_expect(visual._body.frame == 8, "contact follows through")
		visual.advance(0.11,Vector2.ZERO,heading)
		_expect(visual._body.frame == 9, "contact recovers")
		visual.show_hit(-heading)
		_expect(visual._body.frame == 10, "real hit first pose")
		visual.advance(0.10,Vector2.ZERO,heading)
		_expect(visual._body.frame == 11, "hit settles in second pose")
		visual.advance(0.4,Vector2.ZERO,heading)
		_expect(visual.motion_state == &"idle" and visual._body.frame == 0, "events expire into stable idle")
	visual.contact_vector = Vector2(20,0)
	visual.advance(0.2,Vector2.ZERO,Vector2.RIGHT)
	var anchor: Vector2 = visual._body.position
	actor.take_damage(actor.health)
	_expect(actor.activity == FieldActor.Activity.DOWN and visual._body.frame == 12, "actual death begins fall at the original owner")
	visual.advance(0.09,Vector2.ZERO,Vector2.ZERO)
	_expect(visual._body.frame == 13, "death has falling articulation")
	visual.advance(0.10,Vector2.ZERO,Vector2.ZERO)
	_expect(visual._body.frame == 14, "death reaches ground")
	visual.advance(0.16,Vector2.ZERO,Vector2.ZERO)
	_expect(visual._body.frame == 15 and visual._body.position == anchor, "terminal body and ANIM02 death display anchor")
	var facing: Vector2 = visual._facing
	visual.show_attack(Vector2.UP)
	visual.show_hit(Vector2.LEFT)
	visual.show_fire(Vector2.DOWN)
	visual.advance(1.0,Vector2.ZERO,Vector2.UP)
	_expect(visual.motion_state == &"defeated" and visual._body.frame == 15 and visual._facing == facing, "terminal cannot revive or turn")
	_expect(actor.position == Vector2.ZERO, "art never changes logical feet")
	for texture: Texture2D in NormalInfectedV1.SHEETS:
		var image: Image = texture.get_image()
		_expect(image.get_size() == Vector2i(1254,1254) and image.detect_alpha() != Image.ALPHA_NONE, "selected original canvas and real alpha")
		var cell: Vector2 = Vector2(image.get_size())/4.0
		for frame: int in range(16):
			var left: int = ceili((frame%4)*cell.x)
			var top: int = ceili((frame/4)*cell.y)
			var right: int = floori((frame%4+1)*cell.x)-1
			var bottom: int = floori((frame/4+1)*cell.y)-1
			var clear: bool = true
			for x: int in range(left,right+1):
				if image.get_pixel(x,top).a >= 0.125 or image.get_pixel(x,bottom).a >= 0.125: clear = false
			for y: int in range(top,bottom+1):
				if image.get_pixel(left,y).a >= 0.125 or image.get_pixel(right,y).a >= 0.125: clear = false
			_expect(clear, "authored cell padding avoids limb clipping or neighbor bleed")
	actor.queue_free()
	await process_frame
	print("BH_INFECTED_V1 checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BH_INFECTED_V1 "+label)
