extends SceneTree
## Real frame landmarks, projected muzzle, authority phases and transient feedback.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	_check_holding()
	_check_authority()
	_check_impacts_and_falls()
	await process_frame
	print("BH_WEAPON_HOLDING checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_holding() -> void:
	var stage: Node2D = Node2D.new()
	root.add_child(stage)
	var definitions: Array[WeaponDefinition] = [WeaponInventory.definition("carbine"), WeaponInventory.definition("long_rifle"),
		CombatEquipment.definition("shotgun_v1"), CombatEquipment.definition("fire_axe_v1"), CombatEquipment.definition("rescue_hammer_v1")]
	for variant: int in range(5):
		var actor: FieldActor = FieldActor.new()
		actor.definition_id = StringName("crew_%d" % (variant + 1))
		root.add_child(actor)
		IsoSpace.attach_actor(actor, stage)
		var visual: ActorVisual = actor.visual
		var source: Image = SurvivorVisualV1.SHEETS[variant].get_image()
		for definition: WeaponDefinition in definitions:
			visual.set_weapon(definition.presentation)
			var weapon_ink: Image = definition.presentation.texture.get_image()
			for octant: int in range(8):
				# Convert the desired SCREEN direction to map intent, just as field orders do.
				var screen: Vector2 = Vector2.RIGHT.rotated(octant * PI / 4.0)
				var heading: Vector2 = IsoSpace.to_map(screen).normalized()
				visual.advance(0.5, Vector2.ZERO, heading)
				_expect(visual._body.frame / 8 == octant, "projected direction chooses the matching survivor frame")
				for tick: int in range(5):
					visual.advance(0.125, heading * 125.0 if tick < 4 else Vector2.ZERO, heading)
					var state: Dictionary = visual.presentation_state()
					_expect(state.grip.distance_to(state.hand) < 0.001, "walk and rest retain actual grip contact")
					_expect(visual._body.scale == Vector2.ONE * 0.22, "all five bodies keep locked scale")
					var walk_pixel: Vector2 = state.hand_pixel
					var walk_frame: int = visual._body.frame % 8
					_check_weapon_exposure(visual, source, weapon_ink)
					_expect(source.get_pixel(int(walk_pixel.x) + walk_frame * 256, int(walk_pixel.y) + octant * 256).a > 0.1,
						"walking grip belongs to drawn art %d/%d/%d" % [variant, octant, walk_frame])
				var legacy: Vector2 = visual.aimed_shot_offset(heading)
				visual.set_night_lighting(1.0)
				visual.show_fire(heading)
				_expect(legacy.distance_to(visual.muzzle_offset()) < 0.001, "hand rig cannot change predicted ballistic origin")
				_expect(visual._muzzle.visible == not CombatEquipment.melee(String(definition.id)), "only a committed firearm shows a muzzle flash")
				_expect(visual._weapon_rig.light_enabled() == visual._muzzle.visible, "night flash is a bounded local lamp")
				_expect((visual._hold.get_index() < visual._body.get_index()) == (octant in [5, 6, 7]), "back views put weapon behind the complete body")
				for elapsed: float in [0.0, 0.07, 0.09]:
					visual.advance(elapsed, Vector2.ZERO, heading)
					var frame: int = visual._body.frame % 8
					_check_weapon_exposure(visual, source, weapon_ink)
					var pixel: Vector2 = visual._weapon_rig.hand_pixel
					var alpha: float = source.get_pixel(int(pixel.x) + frame * 256, int(pixel.y) + octant * 256).a
					_expect(alpha > 0.1, "grip belongs to drawn art %d/%d/%d" % [variant, octant, frame])
					var drawn: Vector2 = visual._hold.transform * (visual._weapon.transform * (visual.weapon_view.muzzle_pixel - visual.weapon_view.grip_pixel))
					_expect(drawn.distance_to(visual.rendered_muzzle_offset()) < 0.001, "tracer and flash share the rendered muzzle during recoil")
				visual.advance(0.4, Vector2.ZERO, heading)
				_expect(not visual._muzzle.visible and not visual._weapon_rig.light_enabled(), "flash and lamp expire without recurring shots")
				visual.set_night_lighting(0.0)
		actor.free()
	stage.free()


func _check_weapon_exposure(visual: ActorVisual, body_ink: Image, weapon_ink: Image) -> void:
	# Measure actual opaque weapon pixels after the body/hair occluder, excluding fire FX.
	var body: Sprite2D = visual._body
	var weapon: Sprite2D = visual._weapon
	var to_body: Transform2D = body.transform.affine_inverse() * visual._hold.transform * weapon.transform
	var back: bool = visual._weapon_rig.render_octant in [5, 6, 7]
	var opaque: int = 0
	var exposed: int = 0
	for y: int in range(0, weapon_ink.get_height(), 2):
		for x: int in range(0, weapon_ink.get_width(), 2):
			if weapon_ink.get_pixel(x, y).a < 0.5:
				continue
			opaque += 1
			var pixel: Vector2 = to_body * (Vector2(x + 0.5, y + 0.5) + weapon.offset) - body.get_rect().position
			var covered: bool = false
			if body.get_rect().size.x > pixel.x and pixel.x >= 0.0 and pixel.y >= 0.0 and pixel.y < body.get_rect().size.y:
				var ink: Color = body_ink.get_pixel(int(pixel.x) + body.frame % 8 * 256, int(pixel.y) + body.frame / 8 * 256)
				covered = ink.a > 0.5 and (back or pixel.y < 104.0)
			if not covered:
				exposed += 1
	var area: float = exposed * 4.0 * absf(weapon.transform.determinant())
	_expect(weapon.visible and exposed > opaque * 0.12 and area >= 2.5,
		"weapon silhouette survives body occlusion %d/%s/%d/%d (%.2f px2, %d/%d)" % [visual.variant, visual.weapon_view.id,
			visual._weapon_rig.render_octant, body.frame % 8, area, exposed, opaque])


func _check_authority() -> void:
	var world: Expedition = Expedition.new()
	world.supply = MissionSupply.new()
	world.supply.generated = {"version":8, "build":{"slots":["", ""]}}
	world._effects = Node2D.new()
	root.add_child(world._effects)
	var actor: FieldActor = FieldActor.new()
	actor.member_id = 1
	actor.position = Vector2(400, 400)
	root.add_child(actor)
	var target: FieldActor = FieldActor.new()
	target.is_enemy = true
	target.actor_id = 2
	target.position = actor.position + Vector2(32, 0)
	root.add_child(target)
	world.survivors = [actor]
	world.enemies = [target]
	for id: String in ["fire_axe_v1", "rescue_hammer_v1", "shotgun_v1"]:
		actor.weapon_definition = CombatEquipment.definition(id)
		actor.visual.set_weapon(actor.weapon_definition.presentation)
		actor.cooldown = 0.0
		actor.magazine = null if CombatEquipment.melee(id) else WeaponMagazine.new("holding:test", id)
		world.combat.actions.clear()
		world.combat.attack(world, actor, 0.0)
		world.combat.present(actor)
		if CombatEquipment.melee(id):
			_expect(target.health == target.max_health and actor.visual._body.frame % 8 == 5, "authority windup prepares arms without premature damage")
			var before: Dictionary = world.combat.snapshot()
			var transform: Transform2D = actor.visual._weapon.transform
			world.combat.present(actor)
			world.combat.present(actor)
			_expect(transform.is_equal_approx(actor.visual._weapon.transform) and before == world.combat.snapshot(), "repeated presentation cannot accumulate twist or advance authority")
			world.combat.attack(world, actor, float(CombatEquipment.melee_policy(id).windup))
			world.combat.present(actor)
			_expect(target.health == target.max_health - actor.weapon_definition.damage and actor.visual._body.frame % 8 == 6,
				"actual melee commit produces contact frame on the same step")
			_expect(not actor.visual._muzzle.visible and actor.combat_view._phase == "recover", "real swing uses arc recovery and never gunfire")
		else:
			_expect(actor.magazine.rounds == actor.magazine.capacity() - 1 and actor.visual._muzzle.visible, "shotgun commits one shell with one fire event")
		target.health = target.max_health
		target.visual.advance(0.5, Vector2.ZERO, Vector2.ZERO)
		actor.visual.advance(0.5, Vector2.ZERO, Vector2.ZERO)
	# A closed damage gate must not manufacture a hit flash or change health.
	actor.damage_gate = func(_actor: FieldActor, _proposal: Dictionary) -> Error: return ERR_CANT_CREATE
	_expect(not actor.take_damage(5.0) and actor.health == actor.max_health and actor.visual._hit_clock == 0.0, "rejected hit creates no feedback")
	world._effects.free()
	actor.free()
	target.free()
	world.free()


func _check_impacts_and_falls() -> void:
	for kind: String in ["survivor", EnemyRules.NORMAL, EnemyRules.RUSH, EnemyRules.HEAVY]:
		var actor: FieldActor = FieldActor.new()
		actor.is_enemy = kind != "survivor"
		if actor.is_enemy:
			actor.enemy_behavior = EnemyBehavior.new()
			actor.enemy_behavior.kind = kind
		root.add_child(actor)
		var feet: Vector2 = actor.position
		actor.visual.set_night_lighting(1.0)
		actor.take_damage(1.0, Vector2.RIGHT)
		var flash: Sprite2D = actor.visual._weapon_rig._flash
		_expect(actor.visual._body.self_modulate.a == 1.0 and actor.visual.modulate.a == 1.0,
			"peak hit never fades the underlying actor")
		_expect(flash.texture == actor.visual._body.texture and flash.material == actor.visual._body.material
			and flash.self_modulate.a <= 0.22 and flash.self_modulate.r <= 1.5,
			"peak hit preserves source colour and species palette with a shallow overlay")
		actor.visual.advance(0.05, Vector2.ZERO, Vector2.ZERO)
		_expect(actor.position == feet and actor.visual._body.position.x > 0.0 and actor.visual._weapon_rig._flash.visible, "hit flashes and retreats visually without moving logical feet")
		_expect(flash.self_modulate.a < 0.12 and actor.visual._body.self_modulate.a == 1.0,
			"hit highlight falls quickly without making the body translucent")
		actor.visual.advance(0.13, Vector2.ZERO, Vector2.ZERO)
		_expect(not actor.visual._weapon_rig._flash.visible and actor.visual._body.position == Vector2.ZERO, "hit impulse fully settles")
		actor.take_damage(999.0)
		actor.visual.advance(0.4, Vector2.ZERO, Vector2.ZERO)
		if actor.is_enemy:
			_expect(actor.visual._body.material == InfectedSheetV1.MATERIAL
				and is_equal_approx(float(actor.visual._body.get_instance_shader_parameter("night_readability")), 1.0)
				and actor.visual.modulate.is_equal_approx(ActorVisual.NIGHT_GAIN), "fallen infected retain per-sprite and actor night compensation")
			var corpse: Color = actor.visual._body.self_modulate
			_expect(corpse.r >= 0.85 and is_equal_approx(corpse.r, corpse.g) and is_equal_approx(corpse.g, corpse.b) and corpse.a == 1.0,
				"fallen infected hold a neutral readable silhouette before the existing fade")
		_expect(actor.visual._body.frame == 15 if actor.is_enemy else actor.visual._body.self_modulate.a == 1.0, "basic infected reach existing fallen frame; survivor stays readable")
		actor.visual.advance(0.5, Vector2.ZERO, Vector2.ZERO)
		_expect(actor.visual._body.self_modulate.a < 0.2 if actor.is_enemy else actor.visual._body.self_modulate.a == 1.0, "infected fade after hold; downed squad member persists")
		var defeat_clock: float = actor.visual._defeat_clock
		actor.visual.show_defeat()
		_expect(actor.visual._defeat_clock == defeat_clock and not actor.visual._weapon.visible, "late defeat cannot restart fall or restore a weapon")
		actor.free()


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BH_WEAPON_HOLDING " + label)
