extends SceneTree
## Topology, visible blockers and presentation contracts. Native play verifies the pixels.

var _results: Array[Dictionary] = []
var _failures: int = 0
var _report_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bh-progress="):
			_report_dir = argument.trim_prefix("--bh-progress=").get_base_dir()
	var ordinary: MissionSupply = preload("res://src/features/camp/scavenge.tres")
	var market: MissionSupply = preload("res://src/features/camp/supermarket.tres")
	_expect(ordinary.layout.id != market.layout.id and ordinary.layout.blockers() != market.layout.blockers()
		and ordinary.layout.roads != market.layout.roads and ordinary.layout.bus_door != market.layout.bus_door
		and ordinary.layout.cash_door != market.layout.cash_door, "missions have different real topology, roads, arrival and targets")
	_expect(ordinary.cash_reward == 4 and ordinary.food_reward == 0 and market.cash_reward == 4 and market.food_reward == 3
		and ordinary.has_weapon_sample and market.has_weapon_sample, "existing reward values and unique weapon source remain unchanged")
	for supply: MissionSupply in [ordinary, market]:
		_check_routes(supply)
		var sortie: Expedition = Expedition.new()
		sortie.supply = supply
		root.add_child(sortie)
		sortie.set_physics_process(false)
		_expect(sortie.navigation.obstacles == supply.layout.blockers(), "navigation reads selected authored blockers: " + String(supply.id))
		_expect(sortie._buildings.size() == supply.layout.buildings().size(), "every authored building has a matching visible prop")
		_expect(sortie.search_site(&"cash").door == supply.layout.cash_door and sortie.search_site(&"food").door == supply.layout.food_door, "click and movement targets use layout entrances")
		_expect(sortie._food_site.prop.searchable == supply.supports(&"food"), "ordinary residential second point cannot supply food")
		var building: FieldProp = sortie._shop
		var behind: Vector2 = Vector2(supply.layout.cash_block.get_center().x, supply.layout.cash_block.position.y - 30)
		_expect(building.obscures(behind) and not building.obscures(supply.layout.cash_door), "roof mask covers rear approach, excludes front entrance")
		building.show_behind_roof(true)
		_expect(is_equal_approx(building._roof.modulate.a, 0.4) and building._wall.modulate.a == 1.0, "roof alone fades, front wall remains solid")
		building.show_behind_roof(false)
		_expect(building._roof.modulate.a == 1.0, "roof restores after leaving rear")
		var azure: ActorVisual = sortie.survivors[0].visual
		var amber: ActorVisual = sortie.survivors[1].visual
		_expect(amber._body.texture != azure._body.texture and amber._upper.texture != azure._upper.texture and amber._upper.material == null, "Amber has independent legs and upper textures without recolour shader")
		for view: WeaponPresentation in [ActorVisual.CarbineView, ActorVisual.LongRifleView]:
			amber.set_weapon(view)
			for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				amber.advance(0.2, Vector2.RIGHT * 125, direction * 180)
				amber.show_hit(Vector2.LEFT)
				amber.show_fire(direction)
				var pose: Dictionary = amber.presentation_state()
				_expect(pose.hand.distance_to(pose.grip) < 0.001, "Amber hand/weapon contact survives directional movement, hit and fire")
		_expect(sortie.survivors[0].speed == 125 and sortie.tuning.search_seconds == 30 and sortie.tuning.spawn_seconds == 7, "map content never adjusts speeds, search duration or enemy timing")
		sortie.queue_free()
		await process_frame
	var practice: Expedition = Expedition.new()
	practice.is_practice = true
	root.add_child(practice)
	practice.set_physics_process(false)
	_expect(practice.survivors.all(func(actor: FieldActor) -> bool: return practice.navigation.is_clear(actor.position)), "existing practice starts both members outside the new residential blockers")
	practice.queue_free()
	await process_frame
	DirAccess.make_dir_recursive_absolute(_report_dir)
	var file: FileAccess = FileAccess.open(_report_dir.path_join("street-content-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_results.size(),"failures":_failures,"results":_results},"\t"))
	file.close()
	print("BH_STREET_CONTENT checks=%d failures=%d" % [_results.size(),_failures])
	quit(0 if _failures == 0 else 1)


func _check_routes(supply: MissionSupply) -> void:
	var layout: StreetLayout = supply.layout
	var nav: FieldNavigation = FieldNavigation.new()
	nav.configure(layout.blockers())
	for block: Rect2 in layout.buildings():
		var clear_street: bool = true
		for road: Rect2 in layout.roads:
			clear_street = clear_street and not block.intersects(road)
		_expect(clear_street, "residences and shops do not occupy the painted roadway")
	var destinations: Array[Vector2] = [layout.bus_door, layout.cash_door]
	if supply.supports(&"food"):
		destinations.append(layout.food_door)
	for block: Rect2 in layout.buildings():
		destinations.append(Vector2(block.get_center().x, block.position.y - 30))
	destinations.append_array(layout.enemy_points)
	for start: Vector2 in layout.arrivals:
		_expect(nav.is_clear(start), "arrival is actually walkable")
		for destination: Vector2 in destinations:
			_expect(nav.is_clear(destination), "authored entrance, rear approach or enemy spawn is clear")
			var path: PackedVector2Array = nav.path_between(start, destination)
			var valid: bool = path.size() > 1 and path[-1].distance_to(destination) <= FieldNavigation.CELL
			for index: int in range(path.size() - 1):
				valid = valid and nav._segment_is_clear(path[index], path[index + 1])
			_expect(valid, "continuous collision-safe route connects arrival to actual destination")
	if supply.id == &"scavenge":
		_expect(nav.is_clear(Vector2(704, 824)) and not nav.is_clear(Vector2(600, 824)), "visible fence gap is open while adjacent fence blocks movement")


func _expect(value: bool, label: String) -> void:
	_results.append({"passed":value,"label":label})
	if not value:
		_failures += 1
		push_error("BH_STREET_CONTENT " + label)
