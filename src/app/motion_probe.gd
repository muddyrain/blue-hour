class_name MotionProbe
extends RefCounted
## Disposable visual fixtures: original Expedition.step, real shots and melee, no camp writes.


static func run(tree: SceneTree, base: Dictionary, capture: Callable) -> Dictionary:
	var samples: Array[Dictionary] = []
	for identity: int in range(5):
		for gun: String in ["carbine", "long_rifle"]:
			var camp: Dictionary = base.duplicate(true)
			var definition: SurvivorDefinition = SurvivorRoster.Definitions[identity]
			camp.crew[0].definition_id = String(definition.id)
			camp.crew[0].call_sign = definition.default_display_name
			var world: Expedition = EnemyProbe.make_world(tree, camp, gun)
			var actor: FieldActor = world.survivors[0]
			actor.cooldown = 999.0
			var heading: Vector2 = Vector2.DOWN if identity % 2 == 0 else Vector2.UP
			var foe: FieldActor = world._make_actor(true, 0, actor.position - heading * 24.0, {}, EnemyRules.NORMAL)
			world.enemies.append(foe)
			var events: Array[Dictionary] = []
			world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
			world._show_notice("动作受控实战 · %s / %s · 普通等级1 / Trait1 / 普通Lv1无词条\n原普通54HP/34速/4伤；先实际近战，再真实移动射击与击退；不写存档" % [definition.default_display_name, gun])
			var moving_fire: bool = false
			var hit: bool = false
			var dead_at: float = -1.0
			var frames: Array[Dictionary] = []
			for tick: int in range(360):
				world.step(1.0 / 30.0)
				if actor.health < 200.0 and not hit:
					hit = true
					await capture.call("%s-%s-contact.png" % [definition.id, gun])
					# Let the real .18s hit reaction finish before the first shot; otherwise
					# the valid moving shot is visually covered by the higher-priority hit.
					actor.cooldown = 0.22
					actor.command_path(world.navigation.path_between(actor.position, actor.position + Vector2(80, 80)))
				moving_fire = moving_fire or actor.visual.motion_state == &"move_fire"
				frames.append({"at": world.elapsed, "actor": actor.visual.presentation_state(), "enemy": foe.visual.presentation_state(), "hp": actor.health, "enemy_hp": foe.health, "feet": actor.position, "enemy_feet": foe.position, "body_offset": foe.visual._body.position})
				if foe.health <= 0.0 and dead_at < 0.0:
					dead_at = world.elapsed
					await capture.call("%s-%s-defeat.png" % [definition.id, gun])
				if dead_at >= 0.0 and world.elapsed - dead_at > 0.90:
					break
				await tree.process_frame
			samples.append({"identity": String(definition.id), "gun": gun, "ordinary_level": 1, "trait_level": 1, "quality": "common", "weapon_level": 1, "affixes": [], "actual_melee": hit, "moving_fire": moving_fire, "enemy_dead": foe.health <= 0.0, "events": events, "frames": frames})
			world.queue_free()
			await tree.process_frame
	var death: Dictionary = await _death(tree, base, capture)
	var heavy: Dictionary = await EnemyProbe.heavy_tell(tree, base, capture)
	var rush: Dictionary = await EnemyProbe.rush_tell(tree, base, capture)
	return {"samples": samples, "survivor_death": death, "heavy": heavy, "rush": rush, "fixture": "controlled combat, actual Expedition AI/LOS/damage; normalized level1/Trait1/common Lv1. Survivor death fixture explicitly starts at8HP, not progression evidence."}


static func _death(tree: SceneTree, base: Dictionary, capture: Callable) -> Dictionary:
	var world: Expedition = EnemyProbe.make_world(tree, base)
	var actor: FieldActor = world.survivors[0]
	actor.health = 8.0
	actor.cooldown = 999.0
	var foe: FieldActor = world._make_actor(true, 0, actor.position + Vector2(24, 0), {}, EnemyRules.NORMAL)
	world.enemies.append(foe)
	world._show_notice("动作死亡诊断 · 明确8HP初始夹具，不是正式进度\n原普通AI两次4伤真实击倒，验证受击→死亡→无幽灵开火")
	var events: Array[Dictionary] = []
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	var death_at: float = -1.0
	for tick: int in range(150):
		world.step(1.0 / 30.0)
		if actor.health <= 0.0 and death_at < 0.0:
			death_at = world.elapsed
			await capture.call("survivor-actual-death.png")
		if death_at >= 0.0 and world.elapsed - death_at > 0.9:
			break
		await tree.process_frame
	var result: Dictionary = {"initial_hp": 8, "health": actor.health, "events": events, "state": String(actor.visual.motion_state), "gun_visible": actor.visual._weapon.visible}
	world.queue_free()
	await tree.process_frame
	return result
