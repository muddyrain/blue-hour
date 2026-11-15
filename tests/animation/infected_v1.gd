extends SceneTree
## Directional art contracts through real basic enemies and their existing events.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_expect(NormalInfectedV1.enabled(), "candidate uses V1 by default")
	_check_kind(EnemyRules.NORMAL, NormalInfectedV1.SHEETS, NormalInfectedV1.WALK_FPS)
	_check_kind(EnemyRules.RUSH, RushInfectedV1.SHEETS, RushInfectedV1.WALK_FPS)
	_check_kind(EnemyRules.HEAVY, HeavyInfectedV1.SHEETS, HeavyInfectedV1.WALK_FPS)
	_check_specials()
	await process_frame
	print("BH_INFECTED_V1 checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)


func _check_kind(kind: String, sheets: Array[Texture2D], walk_fps: float) -> void:
	var actor: FieldActor = FieldActor.new()
	actor.is_enemy = true
	actor.enemy_behavior = EnemyBehavior.new()
	actor.enemy_behavior.kind = kind
	root.add_child(actor)
	var visual: ActorVisual = actor.visual
	var folder: String = "rush" if kind == EnemyRules.RUSH else "heavy" if kind == EnemyRules.HEAVY else "normal"
	for octant: int in range(8):
		var heading: Vector2 = Vector2.RIGHT.rotated(octant*PI/4.0)
		visual.advance(0.4,heading*34.0,heading)
		var expected: String = ["e","se","s","se","e","ne","n","ne"][octant]
		_expect(visual._body.texture.resource_path.ends_with("/"+folder+"/"+expected+".png"), "kind and direction select independently drawn source "+folder+str(octant))
		_expect(visual._body.flip_h == (octant in [3,4,5]), "only disclosed three mirrors "+str(octant))
		_expect(visual._body.material == InfectedSheetV1.MATERIAL, "basic enemies share muted grey-green palette")
		_expect(visual._body.hframes == 4 and visual._body.vframes == 4 and visual._body.frame in range(1,7), "real walk frame stays in new layout")
		var frames: Array[int] = []
		for tick: int in range(6):
			visual.advance(1.0/walk_fps,heading*34.0,heading)
			if visual._body.frame not in frames: frames.append(visual._body.frame)
		_expect(frames.size() == 6, "six distinct drawn walk poses reached in one cycle")
		if kind == EnemyRules.RUSH:
			visual.enemy_rushing = true
			visual.advance(0.05, heading*58.0, heading)
			_expect(visual.motion_state == &"rush" and visual._body.frame in range(1,7), "real sprint uses articulated gait instead of idle")
			visual.enemy_rushing = false
		if kind == EnemyRules.HEAVY:
			visual.enemy_windup = true
			visual.advance(0.05, Vector2.ZERO, heading)
			_expect(visual.motion_state == &"windup" and visual._body.frame == 9, "heavy braces before the authoritative shove")
			visual.enemy_windup = false
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
	_expect(visual._body.material == InfectedSheetV1.MATERIAL, "falling body retains the same palette")
	var facing: Vector2 = visual._facing
	visual.show_attack(Vector2.UP)
	visual.show_hit(Vector2.LEFT)
	visual.show_fire(Vector2.DOWN)
	visual.advance(1.0,Vector2.ZERO,Vector2.UP)
	_expect(visual.motion_state == &"defeated" and visual._body.frame == 15 and visual._facing == facing, "terminal cannot revive or turn")
	_expect(actor.position == Vector2.ZERO, "art never changes logical feet")
	for texture: Texture2D in sheets:
		var image: Image = texture.get_image()
		var expected_size: int = 1254 if kind == EnemyRules.NORMAL else 1280
		_expect(image.get_size() == Vector2i(expected_size,expected_size) and image.detect_alpha() != Image.ALPHA_NONE, "registered canvas and real alpha")
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


func _check_specials() -> void:
	var kinds: Array[String] = [ScreamerVisualV1.KIND, CombatEnemyRules.TOXIC, NightHoundV1.KIND]
	var textures: Array[Texture2D] = [ScreamerVisualV1.SHEET, ToxicCarrierVisualV1.SHEET, NightHoundVisualV1.ATLAS]
	for index: int in range(kinds.size()):
		var actor: FieldActor = FieldActor.new()
		actor.is_enemy = true
		actor.enemy_behavior = EnemyBehavior.new()
		actor.enemy_behavior.kind = kinds[index]
		root.add_child(actor)
		var visual: ActorVisual = actor.visual
		for octant: int in range(8):
			var heading: Vector2 = Vector2.RIGHT.rotated(octant*PI/4.0)
			visual.advance(0.4, heading*34.0, heading)
			_expect(visual._body.texture == textures[index] and visual._body.material == null,
				"special species retains own art and palette "+kinds[index])
			visual.show_attack(heading)
			_expect(visual._body.texture == textures[index] and visual._body.hframes == 5,
				"special attack stays on its independent source")
		visual.show_defeat()
		visual.advance(0.4, Vector2.ZERO, Vector2.ZERO)
		_expect(visual._body.texture == textures[index] and visual._body.material == null,
			"special defeat retains independent presentation")
		actor.queue_free()

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BH_INFECTED_V1 "+label)
