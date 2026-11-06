extends SceneTree
## Pure frozen-data and real post-collision navigation checks; no played journey claim.

var checks: int = 0
var failures: int = 0
var cases: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("EXPLORATION_GENERATION_FAIL " + label)


func _length(path: PackedVector2Array) -> float:
	var result: float = 0.0
	for index: int in range(1, path.size()):
		result += path[index - 1].distance_to(path[index])
	return result


func _reachable(nav: FieldNavigation, start: Vector2, point: Vector2) -> bool:
	if not nav.is_clear(point):
		return false
	var path: PackedVector2Array = nav.path_between(start, point)
	return not path.is_empty() and path[-1].distance_to(point) <= 14.0


func _case(size: String, topology: String, index: int) -> void:
	var seed: String = "exploration-generation:%s:%s:%d" % [size, topology, index]
	var label: String = "%s/%s/%d" % [size, topology, index]
	var started: int = Time.get_ticks_msec()
	var layout: Dictionary = ExplorationLayout.generate(seed, size, topology)
	expect(not layout.is_empty(), "finite same-scale generator succeeds " + label)
	if layout.is_empty():
		return
	var signature: String = RecordEncoding.fingerprint(layout)
	expect(layout.size() == 17 and layout.version == 4 and ExplorationLayout.is_map_id(layout.id)
		and ExplorationLayout.validate(layout, false).is_empty(), "complete canonical layout-four identity " + label)
	expect(signature == RecordEncoding.fingerprint(ExplorationLayout.generate(seed, size, topology)), "same seed never rerolls objects or geometry " + label)
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(layout))).payload
	expect(ExplorationLayout.validate(decoded).is_empty(), "exact codec retains canonical geometry and object identity " + label)
	var policy: Dictionary = ExplorationLayout.SIZES[size]
	expect(layout.bounds == policy.bounds and layout.entities.size() == policy.columns * policy.rows, "actual bounds and expanded physical grid " + label)
	var street: StreetLayout = ExplorationLayout.resource(layout)
	var routing: Dictionary = ExplorationLayout._routing(layout)
	var nav: FieldNavigation = routing.nav
	var start: Vector2 = street.bus_door
	var dmax: float = 0.0
	var doors_ok: bool = true
	for entity: Dictionary in layout.entities:
		var point: Vector2 = WorldLayout.point(entity.door)
		doors_ok = doors_ok and _reachable(nav, start, point)
		dmax = maxf(dmax, _length(nav.path_between(start, point)))
	expect(doors_ok and dmax > 0.0 and absf(dmax - float(routing.dmax)) < 0.0001, "all building entrances and Dmax use actual final blockers " + label)
	var targets_ok: bool = _reachable(nav, start, street.rescue_point)
	for point: Vector2 in street.arrivals + street.enemy_points:
		targets_ok = targets_ok and _reachable(nav, start, point)
	expect(targets_ok and street.enemy_points.size() >= layout.entities.size(), "arrival, rescue and dispersed spawn candidates remain reachable " + label)
	var counts: Dictionary = {"vehicle":0, "fruit_tree":0}
	var variants: Dictionary = {}
	var ids: Dictionary = {}
	var clearance_ok: bool = true
	var blockers: Array[Rect2] = street.blockers()
	for object: Dictionary in layout.objects:
		counts[object.kind] += 1
		if object.kind == "vehicle":
			variants[object.variant] = true
		ids[object.id] = true
		var collision: Rect2 = WorldLayout.rect(object.collision)
		var work: Vector2 = WorldLayout.point(object.work_point)
		clearance_ok = clearance_ok and blockers.has(collision) and not collision.grow(32.0).intersects(WorldLayout.rect(layout.bus.sweep))
		clearance_ok = clearance_ok and not collision.grow(40.0).intersects(street.bus_block) and _reachable(nav, start, work)
		clearance_ok = clearance_ok and not Rect2(start - Vector2(112, 112), Vector2(224, 224)).intersects(collision.grow(16.0))
		for gate: Array in layout.gates:
			clearance_ok = clearance_ok and not Rect2(WorldLayout.point(gate) - Vector2(56, 56), Vector2(112, 112)).intersects(collision.grow(16.0))
		for first: Array in layout.roads:
			var a: Rect2 = WorldLayout.rect(first)
			for second: Array in layout.roads:
				var b: Rect2 = WorldLayout.rect(second)
				if (a.size.x > a.size.y) != (b.size.x > b.size.y) and a.intersects(b):
					clearance_ok = clearance_ok and not a.intersection(b).grow(28.0).intersects(collision.grow(16.0))
	expect(counts.vehicle == policy.vehicles and counts.fruit_tree == policy.fruit_trees and ids.size() == layout.objects.size() and variants.has_all(["sedan", "van"]), "exact object counts, stable identities and two real vehicle variants " + label)
	expect(clearance_ok, "prop collisions preserve sweep, stop, gather, gate, junction and work-side paths " + label)
	expect(street.shot_obstacles().size() == layout.entities.size() + layout.barriers.size() + 1, "cars and tree trunks add movement obstacles without new LOS walls " + label)
	var type: String = TaskActions.TYPES[index]
	var budget: Dictionary = TaskActions.CONFIG[type]
	var cash: int = int(budget.cash[1])
	var food: int = int(budget.food[1])
	var weapons: int = int(budget.weapons[1])
	var action: String = ("exploration-action:" + seed).sha256_text()
	var value: Dictionary = ExplorationSites.generate(layout, type, cash, food, weapons, action)
	expect(not value.is_empty(), "bounded distributed site generation " + label + "/" + type)
	if value.is_empty():
		return
	expect(ExplorationSites.problem(layout, value, type, cash, food, weapons, action).is_empty()
		and RecordEncoding.fingerprint(value) == RecordEncoding.fingerprint(ExplorationSites.generate(layout, type, cash, food, weapons, action)), "full sites, budgets, targets and routes are reproducible " + label)
	var primary: Dictionary = {"cash":0, "food":0, "weapons":0}
	var extra: Dictionary = {"optional_building":0, "vehicle":0, "fruit_tree":0}
	var zones: Dictionary = {"near":0, "middle":0, "far":0}
	var all_ids: Dictionary = {}
	var sites_ok: bool = true
	var route_ok: bool = value.metrics.routes.size() == value.sites.size()
	var facts: Dictionary = {}
	for site: Dictionary in value.sites:
		all_ids[site.id] = true
		facts[site.id] = {"searched":false, "progress":0.0}
		if site.source == "primary":
			primary[site.kind] += int(site.amount)
			primary.weapons += int(site.weapon)
			sites_ok = sites_ok and site.seconds == (12.0 if type == "airdrop" and site.id == "cash" else 30.0)
		else:
			extra[site.source] += 1
			sites_ok = sites_ok and site.amount == 1 and not site.weapon and not site.has("drop")
			sites_ok = sites_ok and site.seconds == {"optional_building":18.0, "vehicle":8.0, "fruit_tree":6.0}[site.source]
			sites_ok = sites_ok and site.work_mode == ("indoor" if site.source == "optional_building" else "outdoor")
			sites_ok = sites_ok and (site.kind == "cash" if site.source == "vehicle" else site.kind == "food" if site.source == "fruit_tree" else site.kind in ["cash", "food"])
		var point: Vector2 = ExplorationSites.site_point(layout, site)
		var path: PackedVector2Array = nav.path_between(start, point)
		var length: float = _length(path)
		var zone: String = "near" if length <= dmax * 0.35 else "middle" if length <= dmax * 0.65 else "far"
		zones[zone] += 1
		var route: Dictionary = value.metrics.routes[site.id]
		route_ok = route_ok and _reachable(nav, start, point) and absf(length - float(route.length)) < 0.0001 and route.zone == zone and absf(float(route.base_walk_seconds) - length / 125.0) < 0.0001
		if site.weapon:
			sites_ok = sites_ok and site.id == "cash" and site.source == "primary"
	expect(primary.cash == cash and primary.food == food and primary.weapons == weapons and sites_ok, "original primary budgets plus exact bounded per-object rewards " + label)
	expect(extra.optional_building == policy.optional_buildings and extra.vehicle == policy.vehicles and extra.fruit_tree == policy.fruit_trees
		and value.sites.size() == 4 + policy.optional_buildings + policy.vehicles + policy.fruit_trees and value.sites.size() <= 15 and all_ids.size() == value.sites.size(), "exact bounded site count and unique source identities " + label)
	expect(route_ok and zones.near > 0 and zones.middle > 0 and zones.far >= (1 if size == "small" else 2), "real post-prop routes cover near, middle and required far targets " + label)
	var primary_away: bool = false
	if type == "rescue":
		primary_away = _length(nav.path_between(start, street.rescue_point)) > dmax * 0.35
	else:
		for id: String in value.objective.site_ids:
			primary_away = primary_away or value.metrics.routes[id].zone != "near"
	expect(primary_away, "actual task-matching primary target reaches middle or far " + label)
	var generated: Dictionary = value.duplicate(true)
	generated.type = type
	var before_facts: String = RecordEncoding.fingerprint(facts)
	var rows: Array[Dictionary] = ExplorationSites.objective_rows(generated, facts)
	expect(rows.size() == 3 and rows.all(func(row: Dictionary) -> bool: return row.total > 0 and row.done == 0 and not row.complete)
		and before_facts == RecordEncoding.fingerprint(facts), "one real primary and two nonempty optional objectives derive no hidden progress " + label)
	for site: Dictionary in value.sites:
		if site.source == "vehicle":
			facts[site.id].searched = true
			facts[site.id].progress = site.seconds
			break
	expect(ExplorationSites.objective_rows(generated, facts)[0].done == 0, "searching a cash vehicle never completes the primary cash objective " + label)
	for site: Dictionary in value.sites:
		facts[site.id] = {"searched":true, "progress":site.seconds}
	rows = ExplorationSites.objective_rows(generated, facts, true)
	expect(rows.all(func(row: Dictionary) -> bool: return row.complete and row.done == row.total)
		and value.optional_objectives[0].id != value.optional_objectives[1].id, "completion counts follow actual objects with two distinct optional categories " + label)
	cases.append({"size":size, "topology":topology, "seed_index":index, "type":type, "fallback":layout.fallback,
		"dmax":dmax, "buildings":layout.entities.size(), "sites":value.sites.size(), "zones":zones,
		"primary_routes":value.objective.site_ids.map(func(id: String) -> Dictionary: return {"id":id, "length":value.metrics.routes[id].length, "walk_seconds":value.metrics.routes[id].base_walk_seconds}),
		"elapsed_ms":Time.get_ticks_msec() - started})


func _negatives() -> void:
	var layout: Dictionary = ExplorationLayout.generate("exploration-negative-fixture", "small", "commercial")
	if layout.is_empty():
		expect(false, "negative fixture has a legal map")
		return
	for mutation: String in ["missing", "extra", "version", "object_id", "bus_collision", "duplicate"]:
		var bad: Dictionary = layout.duplicate(true)
		match mutation:
			"missing": bad.erase("objects")
			"extra": bad.new_spawn_cap = 999
			"version": bad.version = 3
			"object_id": bad.objects[0].id = "vehicle_99"
			"bus_collision": bad.objects[0].collision = bad.bus.sweep.duplicate()
			"duplicate": bad.objects.append(bad.objects[0].duplicate(true))
		expect(not ExplorationLayout.validate(bad).is_empty(), "complete canonical geometry rejects " + mutation)
	expect(ExplorationLayout.generate("seed", "tiny", "commercial").is_empty()
		and ExplorationLayout.generate("seed", "large", "unknown").is_empty(), "unsupported inputs cannot silently switch size or topology")
	var action: String = "exploration-negative-action".sha256_text()
	var value: Dictionary = ExplorationSites.generate(layout, "equipment", 7, 2, 1, action)
	if value.is_empty():
		expect(false, "negative fixture has legal distributed sites")
		return
	for mutation: String in ["amount", "bonus_weapon", "wrong_primary", "route", "extra"]:
		var bad: Dictionary = value.duplicate(true)
		match mutation:
			"amount": bad.sites[-1].amount += 1
			"bonus_weapon": bad.sites[-1].weapon = true
			"wrong_primary": bad.objective.site_ids = ["vehicle_01"]
			"route": bad.metrics.routes[bad.sites[-1].id].length += 1.0
			"extra": bad.bonus = 1
		expect(not ExplorationSites.problem(layout, bad, "equipment", 7, 2, 1, action).is_empty(), "frozen source, budget and route reject " + mutation)
	var original: String = RecordEncoding.fingerprint(value)
	value.sites[-1].amount = 77
	expect(RecordEncoding.fingerprint(ExplorationSites.generate(layout, "equipment", 7, 2, 1, action)) == original, "returned site views cannot mutate cached frozen rewards")


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	for size: String in NeighborhoodLayout.SIZES:
		for topology: String in NeighborhoodLayout.TOPOLOGIES:
			for index: int in range(4):
				_case(size, topology, index)
	_negatives()
	expect(cases.size() == 36, "all thirty-six size/topology/seed cases complete generation and navigation")
	print(JSON.stringify({"suite":"exploration_generation", "checks":checks, "failures":failures,
		"scope":"PURE_CANONICAL_DATA_AND_REAL_POST_COLLISION_NAVIGATION", "cases":cases}))
	quit(0 if failures == 0 else 1)
