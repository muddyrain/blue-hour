class_name TrainingEffectProbe
extends RefCounted
## Explicit causal fixtures only, never a campaign grant or a save write.

static func run(tree: SceneTree, base: Dictionary, capture: Callable) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if base.get("recruits",[]).is_empty():
		return samples
	for control: int in [1,2,3,4]:
		var id: int = 2 if control==4 else control
		# Explicit same-condition causal fixture, separate from the natural campaign.
		var before: Dictionary = base.duplicate(true)
		if control<4:
			before.training = []
			before.food = before.last_day.food_after
			for member: Dictionary in before.crew:
				member.growth.trait.level = 1
				member.growth.trait.progress = 0
		var quote: Dictionary = TrainingRules.preview(before,id)
		if not quote.error.is_empty():
			return samples
		var after: Dictionary = CampEdit.propose(before,quote.request)
		if after.is_empty():
			return samples
		var pair: Array[Dictionary] = [before,after]
		for phase_index: int in range(2):
			var camp: Dictionary = pair[phase_index].duplicate(true)
			var level: int = int(SurvivorRoster.member(camp.crew,id).growth.trait.level)
			var world: Expedition = (load("res://src/features/expedition/expedition.tscn") as PackedScene).instantiate() as Expedition
			world.crew_snapshot.assign(camp.crew.duplicate(true))
			world.loadout_snapshot = WeaponInventory.snapshot(camp)
			world.growth_mode = true
			world.trait_mode = true
			world.training_mode = true
			tree.root.add_child(world)
			world.set_physics_process(false)
			await tree.process_frame
			world._show_notice("训练前后受控对照 · ID%d / %s · 非自然任务或存档" % [id,"训练前" if phase_index==0 else "训练后"])
			var actor: FieldActor
			for member: FieldActor in world.survivors:
				if member.member_id == id:
					actor = member
				else:
					member.activity = FieldActor.Activity.SEARCHING
			var shot_times: Array[float] = []
			var on_shot: Callable = func(event: Dictionary) -> void:
				if event.kind == "shot":
					shot_times.append(float(event.elapsed))
			world.combat_feedback.connect(on_shot)
			actor.position = world.layout.bus_door
			actor.clear_order()
			var enemy: FieldActor = world._make_actor(true,0,actor.position+Vector2(100,0))
			world.enemies.append(enemy)
			for tick: int in range(2000):
				world.elapsed = tick/1000.0
				actor.advance(0.001)
				world._update_combat()
				if shot_times.size() >= 2:
					break
			var interval: float = shot_times[1]-shot_times[0] if shot_times.size()==2 else -1
			var count: int = shot_times.size()
			actor.position = Vector2(world.layout.cash_block.get_center().x,world.layout.cash_block.end.y+50)
			enemy.position = Vector2(world.layout.cash_block.get_center().x,world.layout.cash_block.end.y-60)
			actor.cooldown = 0
			var blocked: bool = not world.evaluate_attack(actor,enemy).can_fire
			world._update_combat()
			blocked = blocked and shot_times.size()==count
			count = shot_times.size()
			actor.activity = FieldActor.Activity.DOWN
			world._update_combat()
			var down_stopped: bool = shot_times.size()==count
			actor.activity = FieldActor.Activity.IDLE
			world.combat_feedback.disconnect(on_shot)
			world.enemies.clear()
			enemy.queue_free()
			var from: Vector2 = world.layout.arrivals[0]
			var to: Vector2 = world.layout.cash_door
			var path: PackedVector2Array = world.navigation.path_between(from,to)
			var measured_path: PackedVector2Array = path.duplicate()
			actor.position = from
			actor.command_path(path)
			var ticks: int = 0
			var clear: bool = world.navigation.is_clear(from)
			while actor.activity == FieldActor.Activity.MOVING and ticks < 10000:
				actor.advance(1.0/120.0)
				clear = clear and world.navigation.is_clear(actor.position)
				ticks += 1
			var arrived: bool = not measured_path.is_empty() and actor.position.distance_to(measured_path[-1]) < 1
			actor.position = to
			actor.clear_order()
			world.threat_rehearsal = true
			world.request_search(&"cash")
			world.elapsed += 0.25
			world._update_search(0.25)
			var progress: float = world._cash_site.progress
			world.is_paused = true
			world._physics_process(1.0)
			var paused: bool = world._cash_site.progress == progress
			world.is_paused = false
			world.request_search(&"cash")
			var cancelled: bool = world.search_actor == null and not world.searched and world.loot==0 and world.trait_inputs.events.is_empty()
			world.request_search(&"cash")
			var search_ticks: int = 0
			while not world._cash_site.searched and search_ticks < 5000:
				world.elapsed += 0.01
				world._update_search(0.01)
				search_ticks += 1
				if search_ticks % 100 == 0:
					await tree.process_frame
			if capture.is_valid():
				await capture.call("training-effect-C%d-ID%d-%s.png" % [control,id,"before" if phase_index==0 else "after"])
			var diagnostic_report: Dictionary = {"trait_inputs":world.trait_inputs.snapshot(world),"xp_inputs":world.xp_inputs.snapshot(world),"participants":world.participants_snapshot,"growth_inputs":world.growth_inputs.snapshot(world.sortie_id,world.layout.id,world.elapsed),"field_joins":[],"searched":world.searched,"food_searched":false,"evacuated":true}
			var hypothetical: Dictionary = camp.duplicate(true)
			var diagnostic_award: Dictionary = TraitRules.bank(hypothetical,camp,diagnostic_report,{}) if level>0 else {}
			var diagnostic_stopped: bool = diagnostic_report.trait_inputs.diagnostic and world.xp_inputs.events.is_empty()
			if level>0:
				diagnostic_stopped = diagnostic_stopped and diagnostic_award.error.is_empty() and diagnostic_award.ledger.members.all(func(row: Dictionary) -> bool: return row.gained==0)
			samples.append({"member_id":id,"definition_id":String(actor.definition_id),"natural_checkpoint":control==4,"trait_level":level,"phase":"before" if phase_index==0 else "after","camp_hash":SurvivalContracts.fingerprint(camp),"training_food":camp.food,"training_progress":SurvivorRoster.member(camp.crew,id).growth.trait.progress,
				"instance_id":actor.weapon_instance_id,"weapon_id":String(actor.weapon_definition.id),"weapon_interval":actor.weapon_definition.interval,
				"interval":interval,"shot_times":shot_times,"speed":actor.speed,"path":Array(measured_path),"path_ticks":ticks,"path_seconds":ticks/120.0,
				"arrived":arrived,"path_clear":clear,"search_seconds":0.25+search_ticks/100.0,"searched":world.searched,
				"blocked_no_fire":blocked,"down_no_fire":down_stopped,"pause_freezes":paused,"cancel_no_reward":cancelled,
				"search_events":world.trait_inputs.events.duplicate(true),"zero_defeat_diagnostic":diagnostic_stopped,"rewards":world.loot,"source":"PROJECT_TEMP / explicit before-and-CampEdit-purchase causal fixture; no campaign state written"})
			world.queue_free()
			await tree.process_frame
	return samples
