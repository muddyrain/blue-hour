class_name SeasideTown
extends RefCounted
## First authored isometric level: 海边町·商店街路口.

const TITLE: String = "海边町·商店街路口"
const TILE: float = 64.0
const BOUNDS: Rect2 = Rect2(0, 0, 2112, 1664)
const ROUTE_HINT: String = "中央路口集合。东北过石桥是商店街（便利店、售货机、杂货铺）；运河只能从石桥或南面木桥通过。仓库在最远端。"


static func should_apply(value: Dictionary) -> bool:
	if value.is_empty() or value.has("finale_policy") or value.has("investigation"):
		return false
	if value.has("rare_policy") or value.get("type") == EventSortieV1.TYPE:
		return false
	if EconomyActions.hardware(value):
		return false
	if PumpStationAction.enabled(value):
		return false
	return int(value.get("day", 0)) == 2 and int(value.get("slot", -1)) == 0


static func is_layout(layout: StreetLayout) -> bool:
	return layout != null and bool(layout.world_data.get("seaside_town", false))


static func layout(generated: Dictionary) -> StreetLayout:
	var data: Dictionary = world_data(generated)
	var result: StreetLayout = StreetLayout.new()
	result.id = StringName(str(generated.layout.id))
	result.display_name = TITLE
	result.world_bounds = BOUNDS
	result.world_data = data
	result.bus_block = WorldLayout.rect(data.bus.rect)
	result.bus_door = WorldLayout.point(data.bus.door)
	for entity: Dictionary in data.entities:
		result.residences.append(WorldLayout.rect(entity.rect))
	for barrier: Array in data.barriers:
		result.fences.append(WorldLayout.rect(barrier))
	for road: Array in data.roads:
		result.roads.append(WorldLayout.rect(road))
	for arrival: Array in data.arrivals:
		result.arrivals.append(WorldLayout.point(arrival))
	for point: Array in data.enemy_points:
		result.enemy_points.append(WorldLayout.point(point))
	result.cash_block = WorldLayout.rect(data.entities[0].rect)
	result.food_block = WorldLayout.rect(data.entities[1].rect)
	result.cash_door = WorldLayout.point(data.entities[0].door)
	result.food_door = WorldLayout.point(data.entities[1].door)
	result.rescue_point = WorldLayout.point(data.rescue)
	result.camera_start = result.bus_door + Vector2(420, -40)
	result.route_hint = ROUTE_HINT
	for entity: Dictionary in data.entities:
		if String(entity.get("role", "")) == "cash_shop":
			result.cash_block = WorldLayout.rect(entity.rect)
			result.cash_door = WorldLayout.point(entity.door)
			result.cash_title = String(entity.title)
		elif String(entity.get("role", "")) == "food_main":
			result.food_block = WorldLayout.rect(entity.rect)
			result.food_door = WorldLayout.point(entity.door)
			result.food_title = String(entity.title)
	return result


static func world_data(generated: Dictionary) -> Dictionary:
	var shops: Array[Dictionary] = _shop_templates()
	var houses: Array[Dictionary] = _house_templates()
	_bind_sites(shops, houses, generated)
	var entities: Array = []
	entities.append_array(shops)
	entities.append_array(houses)
	return {
		"version": 5,
		"seaside_town": true,
		"authored": true,
		"id": generated.layout.id,
		"size": generated.layout.get("size", "medium"),
		"topology": generated.layout.get("topology", "commercial"),
		"bounds": [0, 0, 2112, 1664],
		"bus": {
			"rect": [800, 948, 140, 48],
			"door": [870, 936],
			"passenger_door": [870, 936],
			"entry": [-160, 996],
			"exit": [2272, 996],
			"stop": [870, 996],
			"facing": "right",
			"sweep": [0, 896, 2112, 192],
		},
		"entities": entities,
		"barriers": [
			[1216, 0, 128, 896],
			[1216, 1088, 128, 192],
			[1216, 1344, 128, 320],
		],
		"roads": [
			[768, 0, 192, 1664],
			[0, 896, 2112, 192],
			[1088, 1280, 448, 64],
		],
		"arrivals": [
			[850, 916],
			[890, 916],
			[834, 960],
			[910, 960],
		],
		"enemy_points": [
			[240, 1280],
			[160, 900],
			[560, 1500],
			[1104, 400],
			[1104, 1500],
			[1840, 1560],
			[2000, 1440],
			[1480, 400],
		],
		"rescue": [144, 1548],
		"objects": [],
		"parcels": [],
		"grounds": {
			"sidewalks": [
				[704, 0, 64, 1664],
				[960, 0, 256, 1664],
				[0, 832, 2112, 64],
				[0, 1088, 2112, 64],
			],
			"banks": [
				[1184, 0, 32, 896],
				[1184, 1088, 32, 192],
				[1184, 1344, 32, 320],
				[1344, 0, 32, 896],
				[1344, 1088, 32, 192],
				[1344, 1344, 32, 320],
			],
			"canal": [
				[1216, 0, 128, 896],
				[1216, 1088, 128, 192],
				[1216, 1344, 128, 320],
			],
			"crosswalks_ns": [
				[768, 896, 192, 64],
				[768, 1024, 192, 64],
			],
			"crosswalks_ew": [
				[768, 896, 64, 192],
				[896, 896, 64, 192],
			],
		},
		"props": _scenery(),
	}


static func _shop_templates() -> Array[Dictionary]:
	return [
		_entity("convenience", "food_main", "便利店", "buildings/convenience.png", [1440, 640, 224, 192], [1552, 848]),
		_entity("vending_a", "food_quick", "售货机", "props/vending_red.png", [1376, 848, 32, 32], [1392, 888]),
		_entity("vending_b", "food_quick", "售货机", "props/vending_blue.png", [1424, 848, 32, 32], [1440, 888]),
		_entity("grocery", "cash_shop", "杂货铺", "buildings/grocery.png", [1728, 656, 208, 176], [1832, 848]),
		_entity("bike_shelter", "optional", "自行车棚", "props/bike_shelter.png", [400, 1408, 128, 80], [464, 1504]),
		_entity("shrine", "optional", "小神社", "buildings/shrine.png", [96, 1440, 96, 96], [144, 1548]),
		_entity("warehouse", "weapon", "渔具仓库", "buildings/warehouse.png", [1664, 1408, 288, 192], [1808, 1616]),
	]


static func _house_templates() -> Array[Dictionary]:
	return [
		_entity("house_a", "house", "住宅", "buildings/house_a.png", [192, 640, 160, 160], [272, 816]),
		_entity("house_a2", "house", "住宅", "buildings/house_a.png", [32, 640, 128, 144], [96, 800]),
		_entity("house_b", "house", "住宅", "buildings/house_b.png", [192, 1184, 144, 144], [264, 1344]),
		_entity("house_c", "house", "住宅", "buildings/house_c.png", [480, 1200, 128, 160], [544, 1376]),
		_entity("house_b2", "house", "住宅", "buildings/house_b.png", [32, 1184, 128, 128], [96, 1328]),
		_entity("house_c2", "house", "住宅", "buildings/house_c.png", [480, 640, 128, 128], [544, 784]),
		_entity("house_a3", "house", "住宅", "buildings/house_a.png", [240, 1544, 128, 96], [304, 1656]),
	]


static func _entity(id: String, role: String, title: String, art: String, rect: Array, door: Array) -> Dictionary:
	return {
		"id": id,
		"role": role,
		"title": title,
		"art": art,
		"rect": rect,
		"door": door,
		"variant": 0,
		"site_id": "",
	}


static func _overflow_entity(site: Dictionary, index: int) -> Dictionary:
	var pads: Array = [
		[32, 480, 80, 80],
		[192, 480, 80, 80],
		[480, 480, 80, 80],
		[640, 700, 80, 80],
		[640, 1400, 80, 80],
		[1440, 400, 80, 80],
		[1728, 400, 80, 80],
		[1960, 400, 80, 80],
		[1440, 1184, 80, 80],
		[1960, 1184, 80, 80],
		[1480, 1544, 80, 80],
		[2000, 1280, 80, 80],
		[32, 1328, 80, 80],
		[640, 480, 80, 80],
		[960, 400, 80, 80],
		[2000, 700, 80, 80],
	]
	var rect: Array = pads[index % pads.size()].duplicate()
	if index >= pads.size():
		rect[0] = float(rect[0])
		rect[1] = float(rect[1]) + 96.0 * float(index / pads.size())
	var door: Array = [float(rect[0]) + float(rect[2]) * 0.5, float(rect[1]) + float(rect[3]) + 16.0]
	var food: bool = String(site.kind) == "food"
	var entity: Dictionary = _entity(
		"overflow_%s" % String(site.id),
		"overflow",
		"路边货箱" if not food else "行道树",
		"props/crate.png" if not food else "props/tree.png",
		rect,
		door,
	)
	entity.site_id = String(site.id)
	return entity


static func _scenery() -> Array:
	return [
		{"art": "props/tram_stop.png", "point": [736, 820], "kind": "tram"},
		{"art": "props/stone_bridge.png", "point": [1280, 1088], "kind": "bridge"},
		{"art": "props/wood_bridge.png", "point": [1280, 1344], "kind": "bridge"},
		{"art": "props/lamp.png", "point": [736, 880], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [992, 880], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [736, 1116], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [992, 1116], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1400, 860], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1552, 860], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1680, 860], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1832, 860], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1980, 860], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1480, 1116], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1760, 1116], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [240, 860], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [560, 1116], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1600, 1580], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1960, 1580], "kind": "lamp"},
		{"art": "props/tree.png", "point": [400, 700], "kind": "tree"},
		{"art": "props/tree.png", "point": [120, 1000], "kind": "tree"},
		{"art": "props/tree.png", "point": [640, 1500], "kind": "tree"},
		{"art": "props/tree.png", "point": [1104, 360], "kind": "tree"},
		{"art": "props/tree.png", "point": [1104, 1500], "kind": "tree"},
		{"art": "props/tree.png", "point": [2000, 700], "kind": "tree"},
		{"art": "props/tree.png", "point": [1580, 400], "kind": "tree"},
		{"art": "props/bike.png", "point": [700, 800], "kind": "bike"},
		{"art": "props/bike.png", "point": [690, 840], "kind": "bike"},
		{"art": "props/bike.png", "point": [430, 1490], "kind": "bike"},
		{"art": "props/crate.png", "point": [1640, 1600], "kind": "crate"},
		{"art": "props/crate.png", "point": [1980, 1608], "kind": "crate"},
		{"art": "props/crate.png", "point": [1620, 1570], "kind": "crate"},
	]


static func _bind_sites(shops: Array[Dictionary], houses: Array[Dictionary], generated: Dictionary) -> void:
	var foods: Array[Dictionary] = []
	var weapons: Array[Dictionary] = []
	var cash: Array[Dictionary] = []
	var objective: Array = generated.get("objective", {}).get("site_ids", [])
	for site: Dictionary in generated.get("sites", []):
		if String(site.kind) == "food":
			foods.append(site)
		elif int(site.get("weapon", 0)) == 1:
			weapons.append(site)
		else:
			cash.append(site)
	foods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.id in objective) > int(b.id in objective)
	)
	var food_slots: Array[Dictionary] = []
	var cash_slots: Array[Dictionary] = []
	var weapon_slots: Array[Dictionary] = []
	var spare: Array[Dictionary] = []
	for shop: Dictionary in shops:
		match String(shop.role):
			"food_main", "food_quick":
				food_slots.append(shop)
			"cash_shop", "optional":
				cash_slots.append(shop)
			"weapon":
				weapon_slots.append(shop)
	spare.append_array(houses)
	_fill(food_slots, foods, spare)
	_fill(weapon_slots, weapons, spare)
	var leftover_cash: Array[Dictionary] = cash.duplicate()
	if weapons.is_empty() and not cash.is_empty() and not weapon_slots.is_empty() and String(weapon_slots[0].get("site_id", "")).is_empty():
		# High-value far warehouse still gets a loot point when the card has no weapon site.
		weapon_slots[0].site_id = String(cash[0].id)
		leftover_cash.remove_at(0)
	_fill(cash_slots, leftover_cash, spare)
	# Any remaining sites occupy leftover houses, then overflow pads, so settlement facts stay complete.
	var assigned: Dictionary = {}
	for entity: Dictionary in shops + houses:
		if not String(entity.site_id).is_empty():
			assigned[entity.site_id] = true
	var unused: Array[Dictionary] = []
	for entity: Dictionary in shops + houses:
		if String(entity.site_id).is_empty():
			unused.append(entity)
	var overflow_index: int = 0
	for site: Dictionary in generated.get("sites", []):
		if assigned.has(String(site.id)):
			continue
		if unused.is_empty():
			houses.append(_overflow_entity(site, overflow_index))
			overflow_index += 1
			assigned[String(site.id)] = true
			continue
		unused[0].site_id = String(site.id)
		assigned[String(site.id)] = true
		unused.remove_at(0)


static func _fill(slots: Array[Dictionary], sites: Array[Dictionary], spare: Array[Dictionary]) -> void:
	var index: int = 0
	for site: Dictionary in sites:
		var slot: Dictionary
		if index < slots.size():
			slot = slots[index]
		elif not spare.is_empty():
			slot = spare[0]
			spare.remove_at(0)
		else:
			break
		slot.site_id = String(site.id)
		index += 1


static func populate(expedition: Expedition) -> void:
	var data: Dictionary = expedition.layout.world_data
	var props_by_site: Dictionary = {}
	for entity: Dictionary in data.entities:
		var block: Rect2 = WorldLayout.rect(entity.rect)
		var building: FieldProp = FieldProp.new()
		building.iso_art = String(entity.art)
		building.world_asset = true
		building.title = String(entity.title)
		building.front_width = block.size.x
		building.body_depth = block.size.y
		building.door_offset = WorldLayout.point(entity.door).x - block.get_center().x
		building.position = Vector2(block.get_center().x, block.end.y)
		building.ui_theme = expedition.ui_theme
		building.searchable = not String(entity.get("site_id", "")).is_empty()
		expedition._sort.add_child(building)
		expedition._buildings.append(building)
		if not String(entity.get("site_id", "")).is_empty():
			props_by_site[String(entity.site_id)] = {"prop": building, "entity": entity}
	for detail: Dictionary in data.get("props", []):
		var node: Node2D = Node2D.new()
		node.name = String(detail.kind)
		IsoAtlas.attach(node, String(detail.art))
		node.set_meta("iso_kind", String(detail.kind))
		node.position = WorldLayout.point(detail.point)
		expedition._sort.add_child(node)
	for def: Dictionary in expedition.supply.generated.sites:
		var site_id: String = String(def.id)
		var binding: Dictionary = props_by_site.get(site_id, {})
		if binding.is_empty():
			continue
		var entity: Dictionary = binding.entity
		var prop: FieldProp = binding.prop
		var site: Expedition.SearchSite = Expedition.SearchSite.new(StringName(def.kind), WorldLayout.point(entity.door))
		site.id = StringName(def.id)
		site.reward = int(def.amount)
		site.weapon = def.weapon
		site.seconds = float(def.seconds)
		site.prop = prop
		site.hit = prop.scaled_hit_bounds()
		prop.primary_target = expedition.supply.generated.get("objective", {}).get("site_ids", []).has(def.id)
		prop.reward_hint = ("货币" if site.kind == &"cash" else "食物") + " +%d" % site.reward + (" / 武器" if site.weapon else "")
		if expedition.exploration_mode():
			prop.primary_target = expedition.supply.generated.objective.site_ids.has(def.id)
			prop.reward_hint = ("货币" if site.kind == &"cash" else "食物") + " +%d" % site.reward
			var category: String = "售货机" if String(entity.role) == "food_quick" else "建筑"
			var tool_count: int = expedition._tools_at(String(site.id))
			if tool_count > 0:
				prop.loot_landmark = "工具 ×%d" % tool_count
				prop.reward_hint += " · 工具 ×%d" % tool_count
			prop.configure_loot_badge(category, Vector2(prop.door_offset, 28))
		if expedition._is_event_site(site):
			prop.loot_landmark = EventSortieV1.TITLE
			prop.reward_hint = "现场二选一"
		expedition.sites.append(site)
		if site.id == &"cash":
			expedition._cash_site = site
			expedition._shop = prop
		if site.id == &"food":
			expedition._food_site = site
