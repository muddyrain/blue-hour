class_name ExplorationSites
extends RefCounted
## Frozen per-object budgets and read-only goals. Existing WorldSites owns carrying rewards.

const OPTIONAL_IDS: Array[String] = ["optional_buildings_all", "searchable_vehicles_all", "fruit_trees_all"]
const OPTIONAL_TITLES: Dictionary = {"optional_buildings_all":"搜完可选建筑", "searchable_vehicles_all":"搜完停放车辆", "fruit_trees_all":"采完本图果树"}
static var _generated: Dictionary = {}


static func generate(layout: Dictionary, type: String, cash: int, food: int, weapons: int, action_id: String,
		mission_policy: int = 0, rare_policy: int = 0) -> Dictionary:
	if not ExplorationLayout.validate(layout).is_empty() or type not in TaskActions.TYPES or not _action_id(action_id):
		return {}
	if mission_policy != 0 and (mission_policy != 1 or layout.get("level_task") != type):
		return {}
	var config: Dictionary = TaskActions.CONFIG[type]
	if cash < int(config.cash[0]) or cash > int(config.cash[1]) or food < int(config.food[0]) or food > int(config.food[1]) or weapons < int(config.weapons[0]) or weapons > int(config.weapons[1]):
		return {}
	var cold_store: bool = rare_policy == RareSortie.VERSION and type == "supply"
	var armory: bool = rare_policy == RareSortie.VERSION and type == "airdrop"
	var key: String = RecordEncoding.fingerprint({"layout":layout, "type":type, "cash":cash, "food":food, "weapons":weapons, "action_id":action_id, "policy":ExplorationLayout.policy(), "mission_policy":mission_policy, "rare_policy":rare_policy})
	if _generated.has(key):
		return _generated[key].duplicate(true)
	var routing: Dictionary = ExplorationLayout._routing(layout)
	var nav: FieldNavigation = routing.nav
	var routes: Dictionary = {}
	var objects: Array[Dictionary] = []
	for object: Dictionary in layout.objects:
		var tree: bool = object.kind == "fruit_tree"
		var site: Dictionary = {"id":object.id, "building":"", "kind":"food" if tree else "cash", "amount":1, "weapon":false,
			"seconds":6.0 if tree else 8.0, "source":"fruit_tree" if tree else "vehicle", "object_id":object.id,
			"work_mode":"outdoor", "point":object.work_point.duplicate()}
		objects.append(site)
		var route: Dictionary = _route(layout, site_point(layout, site), nav, float(routing.dmax))
		if route.is_empty():
			return {}
		routes[site.id] = route
	var sites: Array[Dictionary] = []
	var used: Array[String] = []
	var rescue_court: Dictionary = layout.get("rescue_court", {})
	if not rescue_court.is_empty():
		used.assign([rescue_court.home, rescue_court.optional_building])
	var chosen: Array[Dictionary] = []
	var supply_pair: Array[Dictionary] = []
	if mission_policy == 1 and type == "supply":
		var groceries: Array[Dictionary] = _candidates(layout, used, TaskActions.FOOD_TYPES)
		if cold_store and groceries.size() >= 2:
			var near: Dictionary = _choose(groceries, routing, "near", action_id)
			groceries.erase(near)
			var far: Dictionary = _choose(groceries, routing, "far", action_id)
			if routing.doors[far.id].length - routing.doors[near.id].length >= 750.0:
				supply_pair = [near, far]
		elif not cold_store:
			supply_pair = LevelPolicy.mission_supply_pair(groceries, routing)
		if supply_pair.size() != 2:
			return {}
	for kind: String in ["food", "cash"]:
		var budget: int = food if kind == "food" else cash
		var count: int = mini(budget, 2)
		for index: int in range(count):
			var allowed: Array = TaskActions.FOOD_TYPES if kind == "food" else TaskActions.GEAR_TYPES if index == 0 and (type == "equipment" or weapons > 0) else []
			var candidates: Array[Dictionary] = _candidates(layout, used, allowed)
			if candidates.is_empty():
				return {}
			var entity: Dictionary = _choose(candidates, routing, "far" if index == 0 else "near", action_id + ":primary:" + kind)
			if not supply_pair.is_empty() and kind == "food":
				entity = supply_pair[index]
			elif layout.has("loading_yard") and type == "airdrop" and kind == "cash" and (index == 0 or armory):
				entity = {}
				for candidate: Dictionary in candidates:
					if candidate.id == layout.loading_yard.warehouse:
						entity = candidate
						break
			elif mission_policy == 1 and type == "equipment" and kind == "cash" and index == 0:
				entity = LevelPolicy.mission_investigation_target(candidates, routing)
			elif layout.has("level_task") and type!="airdrop":
				entity=LevelPolicy.choose(candidates,routing,type,kind,index,chosen,layout)
			if entity.is_empty():
				return {}
			chosen.append(entity)
			var site: Dictionary = {"id":kind if index == 0 else kind + "_%d" % (index + 1), "building":entity.id,
				"kind":kind, "amount":budget / count + int(index < budget % count), "weapon":kind == "cash" and index == 0 and weapons == 1 and not (mission_policy == 1 and type == "equipment"),
				"seconds":30.0, "source":"primary", "object_id":entity.id, "work_mode":"indoor"}
			if type == "airdrop" and kind == "cash" and index == 0:
				var point: Array = _airdrop_point(layout, entity, nav)
				if point.is_empty():
					return {}
				site.building = ""
				site.point = point
				site.seconds = 12.0
				site.work_mode = "outdoor"
			if cold_store:
				site.weapon = false
				if kind == "food":
					site.amount = RareSortie.NEAR_FOOD if index == 0 else RareSortie.DEEP_FOOD
					site.seconds = 12.0 if index == 0 else WorldSites.WORK_SECONDS
			if armory and kind == "cash":
				site.amount = 0 if index == 0 else RareSortie.EQUIPMENT_CASH
			if not (armory and kind == "cash" and index == 0):
				used.append(entity.id)
			sites.append(site)
			var route: Dictionary = _route(layout, site_point(layout, site), nav, float(routing.dmax))
			if route.is_empty():
				return {}
			routes[site.id] = route
	if not rescue_court.is_empty():
		used.erase(rescue_court.optional_building)
	var desired_far: int = 1 if layout["size"] == "small" else 2
	for index: int in range(int(ExplorationLayout.SIZES[layout["size"]].optional_buildings)):
		var zones: Dictionary = _zone_counts(routes)
		var wanted: String = "near" if zones.near == 0 else "middle" if zones.middle == 0 else "far" if zones.far < desired_far else ["far", "near", "middle", "far"][index]
		var candidates: Array[Dictionary] = _candidates(layout, used, [])
		if candidates.is_empty():
			return {}
		var entity: Dictionary = _choose(candidates, routing, wanted, action_id + ":optional:" + str(index))
		if index == 0 and not rescue_court.is_empty():
			for candidate: Dictionary in candidates:
				if candidate.id == rescue_court.optional_building:
					entity = candidate
					break
		var kind: String = "food" if (ExplorationLayout.POLICY_ID + "|optional-reward|" + action_id + "|" + entity.id).sha256_text().substr(0, 8).hex_to_int() % 2 == 0 else "cash"
		var site: Dictionary = {"id":"optional_" + entity.id, "building":entity.id, "kind":kind, "amount":1, "weapon":false,
			"seconds":18.0, "source":"optional_building", "object_id":entity.id, "work_mode":"indoor"}
		used.append(entity.id)
		sites.append(site)
		routes[site.id] = _route(layout, site_point(layout, site), nav, float(routing.dmax))
		if routes[site.id].is_empty():
			return {}
	sites.append_array(objects)
	var zones: Dictionary = _zone_counts(routes)
	if zones.near < 1 or zones.middle < 1 or zones.far < desired_far:
		return {}
	var targets: Array[String] = []
	if type == "supply":
		for site: Dictionary in sites:
			if site.source == "primary" and site.kind == "food" and (not cold_store or site.id == "food"):
				targets.append(site.id)
	elif type != "rescue":
		targets.append("cash")
	var primary_away: bool = false
	for id: String in targets:
		primary_away = primary_away or routes[id].zone != "near"
	if type == "rescue":
		var rescue_route: Dictionary = _route(layout, WorldLayout.point(layout.rescue), nav, float(routing.dmax))
		primary_away = not rescue_route.is_empty() and rescue_route.zone != "near"
	if not primary_away and (mission_policy != 1 or type != "supply"):
		return {}
	var pool: Array[String] = OPTIONAL_IDS.duplicate()
	pool.sort_custom(func(a: String, b: String) -> bool:
		var ar: String = (ExplorationLayout.POLICY_ID + "|optional-objective|" + action_id + "|" + a).sha256_text()
		var br: String = (ExplorationLayout.POLICY_ID + "|optional-objective|" + action_id + "|" + b).sha256_text()
		return ar < br if ar != br else a < b
	)
	if not rescue_court.is_empty():
		pool.erase("optional_buildings_all")
		pool.push_front("optional_buildings_all")
	var objectives: Array[Dictionary] = []
	for index: int in range(2):
		var id: String = pool[index]
		var ids: Array[String] = []
		for site: Dictionary in sites:
			if (id == "optional_buildings_all" and site.source == "optional_building") or (id == "searchable_vehicles_all" and site.source == "vehicle") or (id == "fruit_trees_all" and site.source == "fruit_tree"):
				ids.append(site.id)
		objectives.append({"id":id, "title":OPTIONAL_TITLES[id], "site_ids":ids})
	if cold_store or armory:
		var extra_id: String = "food_2" if cold_store else "cash_2"
		objectives[0] = {"id":"rare_extra", "title":RareSortie.landmark(type, extra_id), "site_ids":[extra_id]}
	var result: Dictionary = {"sites":sites, "objective":{"task_id":action_id, "site_ids":targets, "member_id":0},
		"optional_objectives":objectives, "metrics":{"dmax":routing.dmax, "routes":routes}}
	if sites.size() > 15:
		return {}
	if _generated.size() >= 96:
		_generated.clear()
	_generated[key] = result.duplicate(true)
	return result


static func problem(layout: Dictionary, value: Variant, type: String, cash: int, food: int, weapons: int, action_id: String) -> String:
	if not value is Dictionary or value.size() != 4 or not value.has_all(["sites", "objective", "optional_objectives", "metrics"]) or not SurvivalContracts.json_value(value):
		return "EXPLORATION_SITES_FIELDS"
	var expected: Dictionary = generate(layout, type, cash, food, weapons, action_id)
	return "" if not expected.is_empty() and RecordEncoding.fingerprint(expected) == RecordEncoding.fingerprint(value) else "EXPLORATION_SITES_CANONICAL"


static func site_point(layout: Dictionary, site: Dictionary) -> Vector2:
	if site.get("point") is Array:
		return WorldLayout.point(site.point)
	for entity: Dictionary in layout.entities:
		if entity.id == site.get("building"):
			return WorldLayout.point(entity.door)
	return Vector2.INF


static func objective_rows(generated: Dictionary, facts: Dictionary, rescue_done: bool = false,
		rescue_name: String = "") -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var primary: Dictionary = generated.objective
	var type: String = generated.type
	var names: Dictionary = {"supply":"搜集标记食品", "equipment":"搜寻主装备点", "airdrop":"回收主空投",
		"rescue":RescueTarget.ANONYMOUS_NAME}
	var hint: String = "主目标与实际站点绑定；未全部完成仍可按原条件撤离。"
	if type == "rescue":
		hint = "定位并援救，确认接纳后揭晓身份。"
		if not rescue_name.is_empty():
			names.rescue = rescue_name
			hint = "已接纳 · 生还归航后登记入营。" if rescue_done else "同行者已阵亡 · 可按原条件撤离。"
	var done: int = int(rescue_done) if type == "rescue" else _done(primary.site_ids, facts)
	var total: int = 1 if type == "rescue" else primary.site_ids.size()
	rows.append({"id":"primary", "title":names[type], "optional":false, "done":done, "total":total, "complete":done == total,
		"site_ids":primary.site_ids.duplicate(), "hint":hint})
	for objective: Dictionary in generated.optional_objectives:
		done = _done(objective.site_ids, facts)
		total = objective.site_ids.size()
		rows.append({"id":objective.id, "title":objective.title, "optional":true, "done":done, "total":total, "complete":done == total,
			"site_ids":objective.site_ids.duplicate(), "hint":"各对象本身提供物资；完成此目标不另发奖金，可随时归航。"})
	return rows


static func _done(ids: Array, facts: Dictionary) -> int:
	var count: int = 0
	for id: String in ids:
		if facts.get(id) is Dictionary and facts[id].get("searched") == true:
			count += 1
	return count


static func _candidates(layout: Dictionary, used: Array[String], allowed: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity: Dictionary in layout.entities:
		if entity.id not in used and (allowed.is_empty() or entity.archetype in allowed):
			result.append(entity)
	return result


static func _choose(candidates: Array[Dictionary], routing: Dictionary, zone: String, identity: String) -> Dictionary:
	var ranked: Array[Dictionary] = candidates.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ad: float = float(routing.doors[a.id].length)
		var bd: float = float(routing.doors[b.id].length)
		var az: bool = _zone(ad, float(routing.dmax)) == zone
		var bz: bool = _zone(bd, float(routing.dmax)) == zone
		if az != bz: return az
		if ad != bd: return ad < bd if zone == "near" else ad > bd
		var ar: String = (ExplorationLayout.POLICY_ID + "|site|" + identity + "|" + a.id).sha256_text()
		var br: String = (ExplorationLayout.POLICY_ID + "|site|" + identity + "|" + b.id).sha256_text()
		return ar < br if ar != br else a.id < b.id
	)
	return ranked[0]


static func _airdrop_point(layout: Dictionary, entity: Dictionary, nav: FieldNavigation) -> Array:
	if layout.has("loading_yard"):
		return layout.loading_yard.work_point.duplicate()
	for offset: Vector2 in [Vector2(0, 16), Vector2(32, 16), Vector2(-32, 16), Vector2(0, 24)]:
		var point: Vector2 = WorldLayout.point(entity.door) + offset
		var clear: bool = not WorldLayout.rect(layout.bus.sweep).grow(40.0).has_point(point)
		for corner: Vector2 in [Vector2.ZERO, Vector2(-28, -28), Vector2(28, -28), Vector2(-28, 28), Vector2(28, 28)]:
			clear = clear and nav.is_clear(point + corner)
		if clear:
			return [point.x, point.y]
	return []


static func _route(layout: Dictionary, point: Vector2, nav: FieldNavigation, dmax: float) -> Dictionary:
	if not point.is_finite() or not nav.is_clear(point):
		return {}
	var path: PackedVector2Array = nav.path_between(WorldLayout.point(layout.bus.door), point)
	if path.is_empty() or path[-1].distance_to(point) > 14.0:
		return {}
	var length: float = ExplorationLayout._length(path)
	return {"length":length, "zone":_zone(length, dmax), "base_walk_seconds":length / 125.0}


static func _zone(length: float, dmax: float) -> String:
	return "near" if length <= dmax * 0.35 else "middle" if length <= dmax * 0.65 else "far"


static func _zone_counts(routes: Dictionary) -> Dictionary:
	var result: Dictionary = {"near":0, "middle":0, "far":0}
	for route: Dictionary in routes.values():
		result[route.zone] += 1
	return result


static func _action_id(value: String) -> bool:
	return value.length() == 64 and value.is_valid_hex_number(false) and value == value.to_lower()
