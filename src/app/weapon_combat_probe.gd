class_name WeaponCombatProbe
extends RefCounted
## Explicit paired diagnostic worlds. Never mutate the campaign or publish their fixtures.


static func run(tree: SceneTree, base: Dictionary, capture: Callable = Callable()) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for level: int in [1,3]:
		for kind: String in ["carbine","long_rifle"]:
			var camp: Dictionary = base.duplicate(true)
			for member: Dictionary in camp.crew:
				member.health = 200.0
				member.growth.level = 1
				member.growth.xp_total = 0
				member.growth.trait.level = level
				member.growth.trait.progress = 0 if level == 1 else 3
			var selected: Dictionary = {}
			for item: Dictionary in camp.weapons:
				if item.weapon_id == kind and item.condition == "ready":
					selected = item
					break
			if selected.is_empty(): return []
			var equipped: Dictionary = WeaponInventory.equip(camp,1,selected.instance_id)
			camp = equipped.get("data",camp)
			var world: Expedition = (load("res://src/features/expedition/expedition.tscn") as PackedScene).instantiate() as Expedition
			world.threat_rehearsal = true
			world.growth_mode = true
			world.trait_mode = true
			world.crew_snapshot.assign(camp.crew.duplicate(true))
			world.loadout_snapshot = WeaponInventory.snapshot(camp)
			tree.root.add_child(world)
			world.set_physics_process(false)
			await tree.process_frame
			var actor: FieldActor
			for member: FieldActor in world.survivors:
				if member.member_id == 1: actor = member
				else: member.activity = FieldActor.Activity.SEARCHING
			actor.position = world.layout.bus_door
			actor.clear_order()
			var enemy: FieldActor = world._make_actor(true,99,actor.position+Vector2(100,0))
			enemy.health = 10000.0
			enemy.max_health = 10000.0
			world.enemies.append(enemy)
			var shots: Array[Dictionary] = []
			world.combat_feedback.connect(func(event: Dictionary) -> void:
				if event.kind == "shot" and event.member_id == 1: shots.append(event.duplicate(true)))
			world._show_notice("武器因果对照 · ID1 普通Lv1 / Trait Lv%d\n%s · 固定敌人10000HP/距离100；诊断加速步进，不写存档" % [level,actor.weapon_definition.display_name])
			for tick: int in range(10001):
				world.elapsed = tick/1000.0
				actor.advance(0.001)
				world._update_combat()
				if tick % 100 == 0: await tree.process_frame
			var near_shots: Array[Dictionary] = shots.duplicate(true)
			var paused: Dictionary = {"elapsed":world.elapsed,"cooldown":actor.cooldown,"hp":enemy.health,"shots":shots.size()}
			world.is_paused = true
			world.step(2.0)
			var pause_ok: bool = TransactionReceipt.same(paused,{"elapsed":world.elapsed,"cooldown":actor.cooldown,"hp":enemy.health,"shots":shots.size()})
			world.is_paused = false
			actor.cooldown = 0.0
			enemy.position = actor.position+Vector2(260,0)
			var count: int = shots.size()
			world._update_combat()
			var mid_fires: bool = shots.size() == count+1
			actor.cooldown = 0.0
			enemy.position = actor.position+Vector2(actor.weapon_definition.shot_range,0)
			count = shots.size()
			world._update_combat()
			var edge_refuses: bool = shots.size() == count
			enemy.position = actor.position+Vector2(actor.weapon_definition.shot_range-0.01,0)
			world._update_combat()
			var inside_fires: bool = shots.size() == count+1
			var intervals: Array[float] = []
			for index: int in range(1,near_shots.size()):
				intervals.append(float(near_shots[index].elapsed)-float(near_shots[index-1].elapsed))
			var damage: float = 0.0
			for shot: Dictionary in near_shots: damage += float(shot.applied_damage)
			var sample: Dictionary = {"member_id":1,"ordinary_level":1,"xp_total":0,"trait_level":level,
				"trait_id":"steady_shot_v1","trait_factor":actor.trait_shot_factor,"weapon_id":kind,
				"damage":actor.weapon_definition.damage,"base_interval":actor.weapon_definition.interval,
				"range":actor.weapon_definition.shot_range,"effective_interval":actor.weapon_definition.interval*actor.trait_shot_factor,
				"near_distance":100,"initial_enemy_hp":10000,"window_seconds":10.0,"step_seconds":0.001,
				"near_shots":near_shots,"observed_intervals":intervals,"damage_in_window":damage,
				"mid_distance":260,"mid_fires":mid_fires,"edge_refuses":edge_refuses,"inside_fires":inside_fires,"pause_freezes":pause_ok}
			samples.append(sample)
			if capture.is_valid(): await capture.call("weapon-%s-trait%d.png" % [kind,level])
			world.queue_free()
			await tree.process_frame
	return samples
