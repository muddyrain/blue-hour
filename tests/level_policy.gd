extends SceneTree
## Controlled post-collision routing fixtures; no played-flow or reward claims.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("LEVEL_POLICY_FAIL " + label)


func _entity(id: String, type: String, parcel: String, point: Vector2) -> Dictionary:
	return {"id":id, "archetype":type, "parcel":parcel, "door":[point.x, point.y]}


func _routing(nav: FieldNavigation, entities: Array[Dictionary]) -> Dictionary:
	var routes: Dictionary = {}
	var dmax: float = 0.0
	for entity: Dictionary in entities:
		var path: PackedVector2Array = nav.path_between(Vector2(56, 56), WorldLayout.point(entity.door))
		var distance: float = 0.0
		for index: int in range(1, path.size()):
			distance += path[index - 1].distance_to(path[index])
		routes[entity.id] = {"length":distance}
		dmax = maxf(dmax, distance)
	return {"nav":nav, "doors":routes, "dmax":dmax}


func _local_land_use() -> void:
	var original: Array = [
		{"id":"a", "kind":"homes", "rect":[0, 0, 1000, 600], "road_edges":[false, true, false, true]},
		{"id":"b", "kind":"parking", "rect":[1100, 0, 900, 600], "road_edges":[false, true, true, false]},
		{"id":"c", "kind":"homes", "rect":[0, 700, 1000, 600], "road_edges":[true, false, false, true]},
	]
	for type: String in ["supply", "equipment", "rescue"]:
		var first: Array = original.duplicate(true)
		var repeat: Array = original.duplicate(true)
		LevelPolicy.prepare(first, type, "policy-fixture")
		LevelPolicy.prepare(repeat, type, "policy-fixture")
		var changed: int = 0
		for index: int in range(first.size()):
			if first[index].kind != original[index].kind:
				changed += 1
			expect(first[index].rect == original[index].rect and first[index].road_edges == original[index].road_edges, "task leaves actual road/parcel bounds unchanged " + type)
		expect(first == repeat and changed <= 1, "one deterministic local use change " + type)
	var airdrop: Array = original.duplicate(true)
	LevelPolicy.prepare(airdrop, "airdrop", "policy-fixture")
	expect(airdrop == original, "airdrop land use is unchanged")


func _food_navigation() -> void:
	var nav: FieldNavigation = FieldNavigation.new()
	var blockers: Array[Rect2] = [Rect2(480, 128, 48, 800)]
	nav.configure(blockers, Rect2(0, 0, 1408, 1200))
	var foods: Array[Dictionary] = [
		_entity("west", "eatery", "west-block", Vector2(424, 728)),
		_entity("east", "convenience_store", "west-block", Vector2(584, 728)),
		_entity("west-next", "supermarket", "west-block", Vector2(248, 728)),
	]
	var routing: Dictionary = _routing(nav, foods)
	var layout: Dictionary = {"seed":"wall-fixture", "entities":foods, "bus":{"door":[56, 56]}, "rescue":[248, 728]}
	var first: Dictionary = LevelPolicy.choose(foods, routing, "supply", "food", 0, [], layout)
	expect(not first.is_empty() and first.id != "east", "food group avoids the Euclidean-near shop behind a long wall detour")
	var remaining: Array[Dictionary] = []
	for entity: Dictionary in foods:
		if entity.id != first.id:
			remaining.append(entity)
	var chosen: Array[Dictionary] = [first]
	var second: Dictionary = LevelPolicy.choose(remaining, routing, "supply", "food", 1, chosen, layout)
	expect(not second.is_empty() and second.id != "east" and second.id != first.id, "second food is a distinct actually adjacent work point")
	expect(float(routing.doors[first.id].length) > float(routing.dmax) * 0.35, "food pair retains a non-near primary")
	var reversed: Array[Dictionary] = foods.duplicate()
	reversed.reverse()
	expect(LevelPolicy.choose(reversed, routing, "supply", "food", 0, [], layout) == first, "candidate enumeration order does not reroll the primary group")


func _equipment_and_rescue() -> void:
	var nav: FieldNavigation = FieldNavigation.new()
	var blockers: Array[Rect2] = []
	nav.configure(blockers, Rect2(0, 0, 1600, 1008))
	var entities: Array[Dictionary] = [
		_entity("garage", "garage", "a", Vector2(840, 56)),
		_entity("deep", "warehouse", "b", Vector2(1384, 56)),
		_entity("far-food", "eatery", "c", Vector2(1480, 760)),
		_entity("branch", "convenience_store", "a", Vector2(424, 88)),
		_entity("remote", "supermarket", "d", Vector2(56, 824)),
	]
	var routing: Dictionary = _routing(nav, entities)
	var layout: Dictionary = {"seed":"gear-fixture", "entities":entities, "bus":{"door":[56, 56]}, "rescue":[1384, 56]}
	var gear: Array[Dictionary] = [entities[0], entities[1]]
	var primary: Dictionary = LevelPolicy.choose(gear, routing, "equipment", "cash", 0, [], layout)
	expect(primary.archetype in TaskActions.GEAR_TYPES and float(routing.doors[primary.id].length) > float(routing.dmax) * 0.5, "gear remains a real deep warehouse/workshop")
	var food: Array[Dictionary] = [entities[2], entities[3], entities[4]]
	var branch: Dictionary = LevelPolicy.choose(food, routing, "equipment", "food", 0, [], layout)
	expect(branch.id == "branch", "equipment route chooses a short real supply branch instead of arbitrary far food")
	var rescue_data: Dictionary = {"bus":{"door":[56, 56]}, "parcels":[
		{"id":"court", "kind":"courtyard", "buildings":["home", "row"]},
		{"id":"commerce", "kind":"shopfront", "buildings":["shop"]}],
		"entities":[_entity("home", "detached_home", "court", Vector2(900, 700)), _entity("row", "row_house", "court", Vector2(1100, 700)), _entity("shop", "eatery", "commerce", Vector2(1480, 920))]}
	expect(LevelPolicy.rescue_point(rescue_data) == [1100.0, 700.0], "rescue uses an actual residential-cluster door rather than the furthest commercial doorway")
	rescue_data.entities = [rescue_data.entities[-1]]
	expect(LevelPolicy.rescue_point(rescue_data).is_empty(), "missing housing cluster reports no fabricated rescue point")


func run() -> void:
	_local_land_use()
	_food_navigation()
	_equipment_and_rescue()
	print(JSON.stringify({"suite":"level_policy", "checks":checks, "failures":failures, "scope":"PURE_LOCAL_LAND_USE_AND_FINAL_NAVIGATION"}))
	quit(1 if failures else 0)
