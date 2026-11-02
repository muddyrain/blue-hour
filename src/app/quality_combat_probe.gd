class_name QualityCombatProbe
extends RefCounted
## Controlled original auto-combat; never publishes these diagnostic loadout fixtures.

static func run(tree: SceneTree, base: Dictionary, capture: Callable) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var specs: Array[Dictionary] = []
	for kind: String in ["carbine","long_rifle"]:
		for variant: String in ["base","level2","reach_v1","quick_v1"]:
			specs.append({"kind":kind,"variant":variant,"trait":1})
	specs.append({"kind":"long_rifle","variant":"quick_v1","trait":3})
	for spec: Dictionary in specs:
		var camp: Dictionary = base.duplicate(true)
		for member: Dictionary in camp.crew:
			member.health = 200.0
			member.growth.level = 1
			member.growth.xp_total = 0
			member.growth.trait.level = spec.trait
			member.growth.trait.progress = 0 if spec.trait==1 else 3
		var gun: Dictionary = WeaponModifiers.baseline({"instance_id":"diagnostic-instance","weapon_id":spec.kind,"condition":"ready","origin":"diagnostic","acquired_sortie":""})
		gun.weapon_level = 2 if spec.variant=="level2" else 1
		gun.quality = "rare" if spec.variant in ["reach_v1","quick_v1"] else "common"
		gun.affixes = [spec.variant] if gun.quality=="rare" else []
		var equipment: Array[Dictionary] = WeaponInventory.snapshot(camp)
		for row: Dictionary in equipment:
			if row.member_id==1: row.instance = gun
		var world: Expedition = load("res://src/features/expedition/expedition.tscn").instantiate()
		world.growth_mode = true
		world.trait_mode = true
		world.field_departure = camp
		world.crew_snapshot.assign(camp.crew)
		world.loadout_snapshot = equipment
		tree.root.add_child(world)
		world.set_physics_process(false)
		await tree.process_frame
		var actor: FieldActor
		for member: FieldActor in world.survivors:
			if member.member_id==1: actor=member
			else: member.activity=FieldActor.Activity.SEARCHING
		actor.position = world.layout.bus_door
		actor.clear_order()
		var enemy: FieldActor = world._make_actor(true,99,actor.position+Vector2(100,0))
		enemy.health = 10000.0
		enemy.max_health = 10000.0
		world.enemies.append(enemy)
		var shots: Array[Dictionary] = []
		world.combat_feedback.connect(func(event: Dictionary) -> void:
			if event.kind=="shot" and event.member_id==1: shots.append(event.duplicate(true)))
		world._show_notice("实例受控A/B · 普通Lv1 / 本人Trait Lv%d\n%s / %s；同10000HP敌/100距离/同LOS，不写营地" % [spec.trait,spec.kind,WeaponModifiers.description(gun)])
		for tick: int in range(10001):
			world.elapsed = tick/1000.0
			actor.advance(0.001)
			world._update_combat()
			if tick%100==0: await tree.process_frame
		var near: Array[Dictionary] = shots.duplicate(true)
		actor.cooldown = 0
		enemy.position = actor.position+Vector2(WeaponInventory.definition(spec.kind).shot_range+5,0)
		var count: int = shots.size()
		world._update_combat()
		var extension: bool = shots.size()==count+1
		actor.cooldown = 0
		enemy.position = actor.position+Vector2(260,0)
		count = shots.size()
		world._update_combat()
		var mid: bool = shots.size()==count+1
		var stats: Dictionary = WeaponModifiers.effective(gun,actor.trait_shot_factor)
		var intervals: Array[float] = []
		for index: int in range(1,near.size()): intervals.append(float(near[index].elapsed)-float(near[index-1].elapsed))
		samples.append({"spec":spec,"instance":gun,"expected":stats,"ordinary_level":1,"enemy_hp":10000,"distance":100,"los":"same bus clear line","shots":near,"intervals":intervals,"extension_fires":extension,"mid_260_fires":mid,"actual_definition":{"damage":actor.weapon_definition.damage,"interval":actor.weapon_definition.interval,"range":actor.weapon_definition.shot_range}})
		if spec.kind=="long_rifle" and spec.variant in ["level2","reach_v1","quick_v1"]: await capture.call("pair-"+String(spec.variant)+"-trait%d.png" % spec.trait)
		world.queue_free()
		await tree.process_frame
	return samples
