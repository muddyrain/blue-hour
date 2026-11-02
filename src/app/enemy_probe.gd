class_name EnemyProbe
extends RefCounted
## Explicit disposable combat fixtures. No camp mutation or persisted synthetic enemies.


static func make_world(tree: SceneTree, base: Dictionary, gun_type: String = "carbine") -> Expedition:
	var camp: Dictionary = base.duplicate(true)
	camp.crew = camp.crew.slice(0,2)
	for member: Dictionary in camp.crew:
		member.health = 200.0
		member.growth.level = 1
		member.growth.xp_total = 0
		member.growth.trait.level = 1
		member.growth.trait.progress = 0
	var equipment: Array[Dictionary] = WeaponInventory.snapshot(camp)
	for item: Dictionary in equipment:
		if int(item.member_id)==1:
			item.instance = WeaponModifiers.baseline({"instance_id":"diagnostic-ordinary-lv1","weapon_id":gun_type,"condition":"ready","origin":"diagnostic","acquired_sortie":""})
	var world: Expedition = load("res://src/features/expedition/expedition.tscn").instantiate()
	world.is_practice = true
	world.enemy_mode = true
	world.growth_mode = true
	world.trait_mode = true
	world.field_departure = camp
	world.crew_snapshot.assign(camp.crew)
	world.loadout_snapshot = equipment
	world._practice_manual_waves = true
	tree.root.add_child(world)
	world.set_physics_process(false)
	world.survivors[0].position = Vector2(832,704)
	world.survivors[0].clear_order()
	world.survivors[1].activity = FieldActor.Activity.SEARCHING
	world.survivors[1].hide()
	world.camera.pan_by(Vector2(880,704)-world.camera.position)
	world.camera.force_update_scroll()
	return world


static func pairs(tree: SceneTree, base: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for gun: String in ["carbine","long_rifle"]:
		for kind: String in [EnemyRules.NORMAL,EnemyRules.RUSH,EnemyRules.HEAVY]:
			var world: Expedition = make_world(tree,base,gun)
			var actor: FieldActor = world.survivors[0]
			var foe: FieldActor = world._make_actor(true,0,actor.position+Vector2(100,0),{},kind)
			world.enemies.append(foe)
			var events: Array[Dictionary] = []
			world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
			var path: Array[Dictionary] = []
			var initial_hp: float = foe.health
			for tick: int in range(1,10001):
				world.step(0.001)
				if tick%100==0:
					path.append({"at":world.elapsed,"hp":foe.health,"position":[foe.position.x,foe.position.y],"speed":foe.speed,"state":foe.enemy_behavior.state,"range":actor.position.distance_to(foe.position)})
					await tree.process_frame
				if foe.health<=0:
					break
			rows.append({"gun":gun,"enemy":kind,"initial_hp":initial_hp,"hp":foe.health,"ttk":world.elapsed,"actor_hp":actor.health,"ordinary_level":1,"trait_level":1,"quality":"common","weapon_level":1,"affixes":[],"distance":100,"events":events,"path":path})
			world.queue_free()
			await tree.process_frame
	return rows


static func animation(tree: SceneTree, base: Dictionary, capture: Callable) -> Dictionary:
	var world: Expedition = make_world(tree,base)
	var actor: FieldActor = world.survivors[0]
	actor.cooldown = 999.0
	var start: Vector2 = actor.position
	var foe: FieldActor = world._make_actor(true,0,start+Vector2(125,0),{},EnemyRules.NORMAL)
	world.enemies.append(foe)
	var events: Array[Dictionary] = []
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	var frames: Array[Dictionary] = []
	var armed: bool = false
	var death_at: float = -1.0
	world._show_notice("普通僵尸动作诊断 · 真实34速度/9fps/4伤/1.1秒\n追击→真实路径转向→近战→恢复射击→受击/死亡；不写营地")
	for tick: int in range(1,601):
		if tick==60:
			actor.command_path(world.navigation.path_between(actor.position,start+Vector2(48,-56)))
		world.step(1.0/30.0)
		if actor.health<200.0 and not armed:
			await capture.call("ordinary-attack.png")
			armed = true
			actor.cooldown = 0.0
		var pose: Dictionary = foe.visual.presentation_state()
		frames.append({"at":world.elapsed,"position":[foe.position.x,foe.position.y],"hp":foe.health,"actor_hp":actor.health,"pose":pose,"walk_clock":foe.visual._walk_clock,"attack_clock":foe.visual._attack_clock,"hit_clock":foe.visual._hit_clock})
		if foe.health<=0 and death_at<0:
			death_at = world.elapsed
			await capture.call("ordinary-death.png")
		if death_at>=0 and world.elapsed-death_at>0.9:
			break
		await tree.process_frame
	var result: Dictionary = {"frames":frames,"events":events,"actor_hp":actor.health,"enemy_hp":foe.health,"death_at":death_at,"ordinary_parameters":{"hp":54,"speed":34,"damage":4,"interval":1.1,"walk_fps":9},"art_limit":"PROJECT_TEMP five drawn views plus three enemy mirrors; dedicated front/back contact, recovery, hit and fallen poses. Ordinary authority has no windup; no gameplay tuning."}
	world.queue_free()
	await tree.process_frame
	return result


static func heavy_tell(tree: SceneTree, base: Dictionary, capture: Callable) -> Dictionary:
	var world: Expedition = make_world(tree,base,"long_rifle")
	var actor: FieldActor = world.survivors[0]
	actor.cooldown = 999.0
	var foe: FieldActor = world._make_actor(true,0,actor.position+Vector2(24,0),{},EnemyRules.HEAVY)
	world.enemies.append(foe)
	var events: Array[Dictionary] = []
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	world._show_notice("重压动作诊断 · 原96HP/23速度/6伤，0.5秒真前摇\n第一次留在圈内命中；第二次移动离圈取消；最后原枪击退")
	var moved: bool = false
	var shot: bool = false
	for tick: int in range(1,421):
		world.step(1.0/30.0)
		if tick==5:
			await capture.call("heavy-windup.png")
		if actor.health<200.0 and foe.enemy_behavior.state=="windup" and not moved:
			actor.command_path(world.navigation.path_between(actor.position,actor.position+Vector2(110,0)))
			moved = true
		if moved and foe.enemy_behavior.state!="windup" and not shot:
			shot = true
			actor.cooldown = 0.0
		if foe.health<=0:
			break
		await tree.process_frame
	var result: Dictionary = {"events":events,"actor_hp":actor.health,"enemy_hp":foe.health,"moved":moved,"shot":shot}
	world.queue_free()
	await tree.process_frame
	return result


static func safety(tree: SceneTree, base: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var world: Expedition = make_world(tree,base)
	var actor: FieldActor = world.survivors[0]
	actor.cooldown = 999.0
	var rush: FieldActor = world._make_actor(true,0,actor.position+Vector2(160,0),{},EnemyRules.RUSH)
	world.enemies.append(rush)
	var samples: Array[Dictionary] = []
	for tick: int in range(121):
		world.step(1.0/30.0)
		if tick%5==0:
			samples.append({"distance":actor.position.distance_to(rush.position),"speed":rush.speed,"state":rush.enemy_behavior.state,"walk_clock":rush.visual._walk_clock})
	actor.activity = FieldActor.Activity.SEARCHING
	actor.hide()
	world.step(1.0/30.0)
	result.rush = {"samples":samples,"hidden_state":rush.enemy_behavior.state,"hidden_speed":rush.speed,"hidden_target":rush.enemy_behavior.target_id}
	world.queue_free()
	await tree.process_frame
	world = make_world(tree,base)
	actor = world.survivors[0]
	actor.cooldown = 999.0
	var corner: Vector2 = world.layout.cash_block.end
	actor.position = corner+Vector2(20,-42)
	rush = world._make_actor(true,0,corner+Vector2(-42,20),{},EnemyRules.RUSH)
	world.enemies.append(rush)
	world.step(0.001)
	result.wall = {"target_clear":world.navigation.is_clear(actor.position),"enemy_clear":world.navigation.is_clear(rush.position),"path":world.navigation.path_between(rush.position,actor.position).size(),"distance":actor.position.distance_to(rush.position),"state":rush.enemy_behavior.state,"speed":rush.speed,"los":rush.enemy_behavior.legal(world,rush,actor,95)}
	world.queue_free()
	await tree.process_frame
	world = make_world(tree,base)
	actor = world.survivors[0]
	actor.cooldown = 999.0
	var heavy: FieldActor = world._make_actor(true,0,actor.position+Vector2(24,0),{},EnemyRules.HEAVY)
	world.enemies.append(heavy)
	world.step(1.0/30.0)
	var remaining: float = heavy.enemy_behavior.windup_remaining
	var clock: float = world.elapsed
	world.toggle_pause()
	for tick: int in range(20):
		world.step(1.0/30.0)
	result.pause = {"remaining_before":remaining,"remaining_after":heavy.enemy_behavior.windup_remaining,"clock_before":clock,"clock_after":world.elapsed,"health":actor.health}
	world.toggle_pause()
	actor.command_path(world.navigation.path_between(actor.position,actor.position+Vector2(0,-120)))
	for tick: int in range(20):
		world.step(1.0/30.0)
	result.dodge = {"health":actor.health,"state":heavy.enemy_behavior.state,"distance":actor.position.distance_to(heavy.position)}
	world.queue_free()
	await tree.process_frame
	world = make_world(tree,base,"long_rifle")
	actor = world.survivors[0]
	heavy = world._make_actor(true,0,actor.position+Vector2(76,0),{},EnemyRules.HEAVY)
	world.enemies.append(heavy)
	var warned: bool = false
	for tick: int in range(3000):
		world.step(0.001)
		warned = warned or heavy.enemy_behavior.state=="windup"
		if heavy.health<=0:
			break
	result.death = {"warned":warned,"enemy_hp":heavy.health,"health":actor.health,"state":heavy.enemy_behavior.state,"ttk":world.elapsed}
	world.queue_free()
	await tree.process_frame
	world = make_world(tree,base)
	actor = world.survivors[0]
	actor.cooldown = 999.0
	var accepted: Array[bool] = [false]
	var attempts: Array[Dictionary] = []
	actor.damage_gate = func(_victim: FieldActor,proposal: Dictionary) -> Error:
		attempts.append(proposal.duplicate(true))
		return OK if accepted[0] else ERR_CANT_CREATE
	heavy = world._make_actor(true,0,actor.position+Vector2(24,0),{},EnemyRules.HEAVY)
	world.enemies.append(heavy)
	for tick: int in range(20):
		world.step(1.0/30.0)
	result.gate_blocked = {"health":actor.health,"paused":world.is_paused,"state":heavy.enemy_behavior.state,"remaining":heavy.enemy_behavior.windup_remaining,"attempts":attempts.size()}
	accepted[0] = true
	world.toggle_pause()
	world.step(1.0/30.0)
	result.gate_retry = {"health":actor.health,"paused":world.is_paused,"cooldown":heavy.cooldown,"attempts":attempts}
	world.queue_free()
	await tree.process_frame
	return result


static func rush_tell(tree: SceneTree, base: Dictionary, capture: Callable) -> Dictionary:
	var world: Expedition = make_world(tree,base)
	var actor: FieldActor = world.survivors[0]
	actor.cooldown = 999.0
	var rush: FieldActor = world._make_actor(true,0,actor.position+Vector2(160,0),{},EnemyRules.RUSH)
	world.enemies.append(rush)
	var frames: Array[Dictionary] = []
	var turned: bool = false
	var hidden: bool = false
	world._show_notice("疾奔动作诊断 · 远处34速，合法近处58速\n原路径转向追逐；隐藏工人后失去目标；最后恢复原枪击退")
	for tick: int in range(1,241):
		world.step(1.0/30.0)
		if rush.enemy_behavior.state=="rush" and not turned:
			await capture.call("rush-active.png")
			actor.command_path(world.navigation.path_between(actor.position,actor.position+Vector2(0,-80)))
			turned = true
		if tick==135:
			actor.activity = FieldActor.Activity.SEARCHING
			actor.hide()
		if tick==165:
			hidden = rush.enemy_behavior.target_id==0 and rush.speed==34
			actor.clear_order()
			actor.cooldown = 0.0
		frames.append({"at":world.elapsed,"speed":rush.speed,"state":rush.enemy_behavior.state,"position":[rush.position.x,rush.position.y],"frame":rush.visual._body.frame,"walk_clock":rush.visual._walk_clock,"motion":String(rush.visual.motion_state)})
		if rush.health<=0:
			break
		await tree.process_frame
	var result: Dictionary = {"frames":frames,"turned":turned,"hidden_target_reset":hidden,"enemy_hp":rush.health,"actor_hp":actor.health}
	world.queue_free()
	await tree.process_frame
	return result
