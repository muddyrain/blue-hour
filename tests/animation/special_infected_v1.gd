extends SceneTree
## Real ActorVisual routing, authored cells, owner-clock projection and material isolation.

const KINDS: Array[String] = [ScreamerPolicyV1.KIND, ToxicV1.KIND, BurstRuntimeV1.KIND,
	NightHoundV1.KIND, BossDefinition.KIND]
const SHEETS: Array[Texture2D] = [ScreamerVisualV1.SHEET, ToxicCarrierVisualV1.SHEET,
	BurstInfectedVisualV1.SHEET, NightHoundVisualV1.ATLAS, BreacherVisualV1.SHEET]
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for index: int in range(KINDS.size()):
		_check_kind(KINDS[index], SHEETS[index])
	_check_sac_pigment()
	_check_footprints()
	_check_owner_bridge()
	await process_frame
	print("BH_SPECIAL_INFECTED_V1 checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _actor(kind: String) -> FieldActor:
	var actor: FieldActor = FieldActor.new()
	actor.is_enemy = true
	actor.enemy_behavior = EnemyBehavior.new()
	actor.enemy_behavior.kind = kind
	root.add_child(actor)
	return actor


func _check_kind(kind: String, sheet: Texture2D) -> void:
	var actor: FieldActor = _actor(kind)
	var day_actor: FieldActor = _actor(kind)
	var visual: ActorVisual = actor.visual
	for octant: int in range(8):
		var heading: Vector2 = Vector2.RIGHT.rotated(float(octant) * PI / 4.0)
		var source: int = InfectedSheetV1.SOURCE_FOR_OCTANT[octant]
		visual.advance(0.4, heading * 34.0, heading)
		_expect(visual._body.texture == sheet and visual._body.hframes == 5 and visual._body.vframes == 12,
			kind + " routes to its independent full-body atlas")
		_expect(visual._body.flip_h == (octant in [3, 4, 5]) and visual._body.frame % 5 == source,
			kind + " has five real views and only three declared mirrors")
		_expect(visual._body.offset == Vector2(0, -112), "fixed registered foot survives every direction")
		var gait: Array[int] = []
		var fps: float = 7.0 if kind == ToxicV1.KIND else 6.0 if kind == BossDefinition.KIND else 8.0
		for tick: int in range(4):
			visual.advance(1.0 / fps, heading * 34.0, heading)
			if visual._body.frame not in gait:
				gait.append(visual._body.frame)
		_expect(gait.size() == 4, "four articulated gait poses, not sprite rocking")
		_windup(visual, heading, 0.2)
		_expect(visual._body.frame == 25 + source, "windup begins on authored anticipation")
		_windup(visual, heading, 0.8)
		_expect(visual._body.frame == 30 + source, "owner progress selects full anticipation")
		_clear_skill(visual, heading)
		visual.show_attack(heading)
		_expect(visual._body.frame == 35 + source, "committed attack immediately shows contact")
		visual.advance(0.17, Vector2.ZERO, heading)
		_expect(visual._body.frame == 40 + source, "committed attack follows through")
		visual.advance(0.3, Vector2.ZERO, heading)
		visual.show_hit(-heading)
		_expect(visual._body.frame == 45 + source, "hit uses drawn recoil")
		visual.advance(0.3, Vector2.ZERO, heading)
		_expect(visual._body.frame == source, "idle returns to this direction's neutral")
	_check_night_profile(visual, day_actor.visual)
	var logical_foot: Vector2 = actor.position
	actor.take_damage(actor.health)
	_expect(visual._body.frame / 5 == 10, "real fatal damage starts authored collapse")
	visual.advance(0.20, Vector2.ZERO, Vector2.ZERO)
	_expect(visual._body.frame / 5 == 11 and visual._body.material == InfectedSheetV1.MATERIAL,
		"corpse retains independent art and night palette")
	_expect(is_equal_approx(float(visual._body.get_instance_shader_parameter("night_readability")), 1.0)
		and float(visual._body.get_instance_shader_parameter("special_night_lift")) > 0.0,
		"collapse keeps the sprite's night compensation")
	_expect(actor.position == logical_foot, "art never changes logical navigation feet")
	_check_cells(sheet)
	actor.queue_free()
	day_actor.queue_free()


func _check_night_profile(visual: ActorVisual, day_visual: ActorVisual) -> void:
	var kind: String = visual.enemy_kind
	var lift: float = NightHoundVisualV1.NIGHT_DETAIL_LIFT if kind == NightHoundV1.KIND else SpecialInfectedSheetV1.NIGHT_DETAIL_LIFT
	var sacs: float = BurstInfectedVisualV1.SAC_CONTRAST if kind == BurstRuntimeV1.KIND else 0.0
	day_visual.set_night_lighting(0.0)
	var day_pose: Dictionary = day_visual.presentation_state()
	for amount: float in [0.0, 0.45, 0.85, 1.0, 0.0, 1.0]:
		var pose: Dictionary = visual.presentation_state()
		visual.set_night_lighting(amount)
		var strength: float = smoothstep(0.45, 1.0, amount)
		_expect(visual.presentation_state() == pose, kind + " lighting never advances or replaces its pose")
		_expect(visual.modulate.is_equal_approx(Color.WHITE.lerp(ActorVisual.NIGHT_GAIN, strength))
			and is_equal_approx(float(visual._body.get_instance_shader_parameter("night_readability")), strength),
			kind + " receives PR #71 compensation at blue hour and deep night, and clears it by day")
		_expect(is_equal_approx(float(visual._body.get_instance_shader_parameter("special_night_lift")), lift)
			and is_equal_approx(float(visual._body.get_instance_shader_parameter("burst_sac_contrast")), sacs),
			kind + " keeps its own night detail and only burst enables sac contrast")
		_expect(is_zero_approx(float(day_visual._body.get_instance_shader_parameter("night_readability")))
			and day_visual.modulate == Color.WHITE and day_visual.presentation_state() == day_pose
			and is_equal_approx(float(day_visual._body.get_instance_shader_parameter("special_night_lift")), lift)
			and is_equal_approx(float(day_visual._body.get_instance_shader_parameter("burst_sac_contrast")), sacs),
			"a night actor cannot change another actor's daylight grade or pose")
	_expect(visual._body.material == InfectedSheetV1.MATERIAL and day_visual._body.material == visual._body.material,
		"specials share the palette resource while grades remain on sprite instances")
	# A different species sharing the resource must not inherit sacs or the hound's stronger lift.
	var basic: FieldActor = _actor(EnemyRules.NORMAL)
	var basic_lift: Variant = basic.visual._body.get_instance_shader_parameter("special_night_lift")
	var basic_sacs: Variant = basic.visual._body.get_instance_shader_parameter("burst_sac_contrast")
	_expect((basic_lift == null or is_zero_approx(float(basic_lift)))
		and (basic_sacs == null or is_zero_approx(float(basic_sacs))),
		"special detail/sac settings cannot leak into the basic infected")
	basic.queue_free()
	visual.advance(0.1, Vector2.RIGHT * 34.0, Vector2.RIGHT)
	_expect(is_equal_approx(float(visual._body.get_instance_shader_parameter("night_readability")), 1.0)
		and is_equal_approx(float(visual._body.get_instance_shader_parameter("special_night_lift")), lift)
		and is_equal_approx(float(visual._body.get_instance_shader_parameter("burst_sac_contrast")), sacs),
		"animation reposing preserves night grade and species traits")


func _windup(visual: ActorVisual, heading: Vector2, progress: float) -> void:
	if visual.enemy_kind == ScreamerPolicyV1.KIND:
		visual.present_screamer(heading, &"windup", progress)
	elif visual.enemy_kind == ToxicV1.KIND:
		visual.present_toxic_cast(heading, true, progress)
	else:
		visual.present_special(&"windup", progress, heading)


func _clear_skill(visual: ActorVisual, heading: Vector2) -> void:
	visual.present_screamer(heading, &"chase", 0.0)
	visual.present_toxic_cast(heading, false, 0.0)
	visual.present_special(&"chase", 0.0, heading)


func _check_cells(sheet: Texture2D) -> void:
	var image: Image = sheet.get_image()
	_expect(image.get_size() == Vector2i(1280, 3072) and image.detect_alpha() != Image.ALPHA_NONE,
		"five by twelve canvas has real transparency")
	for source: int in range(5):
		var previous: PackedByteArray = PackedByteArray()
		for row: int in range(12):
			var cell: Image = image.get_region(Rect2i(source * 256, row * 256, 256, 256))
			var bounds: Rect2i = cell.get_used_rect()
			_expect(bounds.has_area() and bounds.position.x >= 4 and bounds.position.y >= 4
				and bounds.end.x <= 252 and bounds.end.y <= 252, "every source/pose has padded nonempty pixels")
			if row in range(1, 5):
				_expect(cell.get_data() != previous, "successive walk poses contain different drawings")
			previous = cell.get_data()


func _check_sac_pigment() -> void:
	# Every source view/pose must contain enough warm highlights for the local sac grade.
	# This also guards against a future atlas replacement silently losing the trait.
	var image: Image = BurstInfectedVisualV1.SHEET.get_image()
	for source: int in range(5):
		for row: int in range(12):
			var highlights: int = 0
			for y: int in range(0, 256, 4):
				for x: int in range(0, 256, 4):
					var pixel: Color = image.get_pixel(source * 256 + x, row * 256 + y)
					var value: float = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
					if pixel.a > 0.94 and pixel.r - pixel.b > 0.16 and pixel.g - pixel.b > 0.08 and value > 0.55:
						highlights += 1
			_expect(highlights >= 16, "burst retains shaped sac highlights in every direction and action")


func _check_footprints() -> void:
	var center: Vector2 = Vector2(180, 320)
	for radius: float in [BurstRuntimeV1.RADIUS, float(ToxicV1.POLICY.radius), NightHoundV1.RANGE,
		float(BossDefinition.POLICY.slam_radius), float(BossDefinition.POLICY.melee_range)]:
		for view: Vector2 in InfectedDangerGeometry.circle(center, radius):
			_expect(is_equal_approx(IsoSpace.to_map(view).distance_to(center), radius),
				"displayed boundary inverse-projects to exact authoritative radius")
	var gas: ToxicVisualV1 = ToxicVisualV1.new()
	var boss: BossWarning = BossWarning.new()
	var feedback: SpecialInfectedFeedback = SpecialInfectedFeedback.new()
	for node: Node2D in [gas, boss, feedback]:
		_expect((node.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED,
			"danger edges retain contrast under deep-night CanvasModulate")
		node.free()


func _check_owner_bridge() -> void:
	# No _ready/world setup and no real save: only existing rule states are inputs.
	var world: Expedition = Expedition.new()
	var feedback: SpecialInfectedFeedback = SpecialInfectedFeedback.new()
	var burst: FieldActor = _actor(BurstRuntimeV1.KIND)
	burst.actor_id = 8
	world.enemies.append(burst)
	world.combat.burst = BurstRuntimeV1.new()
	world.combat.burst.state.merge({"actor_id":8, "phase":"windup", "remaining":0.18,
		"origin":[100.0, 100.0], "target":[110.0, 100.0]}, true)
	var hound: FieldActor = _actor(NightHoundV1.KIND)
	hound.actor_id = 9
	hound.enemy_behavior.state = "windup"
	hound.enemy_behavior.windup_remaining = NightHoundV1.WINDUP * 0.2
	world.enemies.append(hound)
	var toxic: FieldActor = _actor(ToxicV1.KIND)
	toxic.actor_id = 10
	world.enemies.append(toxic)
	world.combat.toxic = ToxicV1.initial()
	world.combat.toxic.zones.append({"source_id":10, "point":[40.0, 0.0],
		"source_point":[0.0, 0.0], "age":0.1})
	var boss: FieldActor = _actor(EnemyRules.HEAVY)
	boss.actor_id = 0
	world.enemies.append(boss)
	world.encounter = EncounterRuntime.new()
	world.encounter.definition = {"boss_id":"visual-contract"}
	world.encounter.actor = boss
	world.encounter.behavior.configure("visual-contract")
	var targets: Array[Dictionary] = [{"member_id":1, "position":Vector2(8, 0), "melee_legal":true, "slam_legal":true}]
	world.encounter.behavior.step(0.0, 1.0, true, targets, Vector2.ZERO)
	var before: Dictionary = world.combat.burst.state.duplicate(true)
	var boss_before: Dictionary = world.encounter.behavior.snapshot()
	feedback.refresh(world)
	_expect(burst.visual.motion_state == &"windup" and burst.visual._body.frame / 5 == 6,
		"burst gets exact progress from its durable 0.90 second owner")
	_expect(hound.visual.motion_state == &"windup" and hound.visual._body.frame / 5 == 6,
		"hound gets exact progress from its 0.45 second owner")
	_expect(boss.visual._body.texture == BreacherVisualV1.SHEET and boss.enemy_behavior.kind == EnemyRules.HEAVY,
		"boss routing changes only visual identity, preserving historical rule/snapshot kind")
	_expect(toxic.visual.motion_state == &"release" and toxic.visual._body.frame / 5 == 7,
		"toxic release starts only from an existing authoritative gas zone")
	feedback.refresh(world)
	_expect(TransactionReceipt.same(before, world.combat.burst.state)
		and TransactionReceipt.same(boss_before, world.encounter.behavior.snapshot()),
		"repeated paused refresh cannot advance or rewrite rule clocks")
	_expect(burst.visual._body.frame / 5 == 6, "paused warning does not drift")
	world.combat.toxic.zones[0].age = 0.25
	feedback.refresh(world)
	_expect(toxic.visual._body.frame / 5 == 8, "gas age drives release recovery")
	world.combat.burst.state.phase = "cancelled"
	hound.enemy_behavior.state = "chase"
	feedback.refresh(world)
	_expect(burst.visual._special_phase == &"chase" and hound.visual._special_phase == &"chase",
		"cancelled warnings return to original idle without residue")
	world.encounter.pump = PumpEncounter.new()
	world.encounter.pump.state.lane = PumpCharge.arm(Vector2.ZERO, Vector2(160, 0), [])
	world.encounter.pump.state.windup = PumpCharge.WINDUP * 0.2
	feedback.refresh(world)
	_expect(boss.visual._body.frame / 5 == 6, "pump boss uses the same art and exact 1.5 second charge owner")
	world.encounter.pump.state.lane = {}
	world.encounter.pump.state.recovery = PumpCharge.RECOVERY * 0.8
	feedback.refresh(world)
	_expect(boss.visual._body.frame / 5 == 7, "pump release follows the original resolved charge recovery")
	world.encounter.pump.free()
	feedback.free()
	world.free()
	burst.queue_free()
	hound.queue_free()
	toxic.queue_free()
	boss.queue_free()


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BH_SPECIAL_INFECTED_V1 " + label)
