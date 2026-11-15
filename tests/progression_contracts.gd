extends "res://tests/persona_runtime.gd"
## Directed runtime contracts. Synthetic facility/level inputs grant no saved rewards.


func run() -> void:
	for tier: int in range(3):
		var world: ClockWorld = _world(["quick_loader_v1", ""])
		world.field_departure = {"journey":{"campaign":{"economy":EconomyBuildV1.initial()}}}
		EconomyBuildV1.state(world.field_departure).facilities.workshop.level = tier
		var actor: FieldActor = _actor(world, _profile(1), "carbine", Vector2(400, 400))
		var expected: float = 1.6 * 0.75 * [1.0, 0.95, 0.90][tier]
		expect(near(actor.magazine.seconds(), expected), "workshop tier changes next-sortie reload with personal/passive factors once")
		world.apply_build(actor, _profile(1), _item(1, "carbine"))
		expect(near(actor.magazine.seconds(), expected), "reapplying loadout cannot stack workshop benefit")
		for shot: int in range(actor.magazine.capacity()):
			actor.magazine.commit_shot()
		actor.magazine.advance(expected - 0.001)
		expect(actor.magazine.reloading, "actual magazine respects reduced reload boundary")
		actor.magazine.advance(0.002)
		expect(not actor.magazine.reloading and actor.magazine.rounds == actor.magazine.capacity(), "actual reduced reload completes and refills")
		var repair: Dictionary = WeaponInventory.repair_offer(world.field_departure, _item(1, "carbine"))
		expect(repair.cost == WeaponInventory.definition("carbine").repair_cost - [0, 4, 6][tier], "tier-specific repair discount")
		world.free()
	for id: int in [1, 2, 3]:
		var old: Dictionary = _profile(id, 1)
		var trained: Dictionary = _profile(id, 2)
		var world: ClockWorld = _world(["", ""])
		var before: FieldActor = _actor(world, old, "carbine", Vector2(400, 400))
		var after: FieldActor = _actor(world, trained, "carbine", Vector2(400, 700))
		if id == 1:
			expect(after.weapon_definition.shot_interval(after.trait_shot_factor) < before.weapon_definition.shot_interval(before.trait_shot_factor), "trained steady-shot reduces actual firing cooldown")
		elif id == 2:
			var site: Expedition.SearchSite = Expedition.SearchSite.new(&"cash", before.position)
			site.seconds = 30.0
			world.sites.assign([site])
			world._cash_site = site
			var progress: Array[float] = []
			for actor: FieldActor in [before, after]:
				site.progress = 0.0
				world.search_assignments.assign(actor.member_id, "cash")
				world.search_assignments.begin(actor.member_id)
				actor.activity = FieldActor.Activity.SEARCHING
				actor.hide()
				world._update_search(1.0)
				progress.append(site.progress)
				world.search_assignments.release_member(actor.member_id)
				# Both directed actors share an identity; remove the first lookup after observing it.
				world.survivors.erase(actor)
			expect(progress[1] > progress[0], "trained scavenger advances actual work faster under same clock")
		else:
			expect(after.speed > before.speed, "trained agile member moves faster")
		world.free()
	var grown: Dictionary = _profile(1)
	grown.growth.xp_total = 30
	grown.growth.level = GrowthRules.level_for(30)
	expect(grown.growth.level == 2 and GrowthRules.maximum(grown) == 205.0, "earned level two grants five max HP")
	expect(GrowthRules.description(grown).contains("成长 +5"), "Chinese growth explanation names HP benefit")
	print("BH_PROGRESSION_CONTRACTS " + JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures == 0 else 1)
