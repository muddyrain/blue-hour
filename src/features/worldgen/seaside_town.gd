class_name SeasideTown
extends RefCounted
## First authored isometric level: 海边町·商店街路口.

const TITLE: String = "海边町·商店街路口"
const TILE: float = 32.0
const ROAD_WIDTH: float = 64.0
const WALK_WIDTH: float = 32.0
const CANAL_WIDTH: float = 96.0
const BANK_WIDTH: float = 32.0
const WOOD_GAP: float = 144.0
const WOOD_WIDTH: float = 64.0
const NS_CENTER: float = 768.0
const EW_CENTER: float = 624.0
const BUS_LENGTH: float = 108.0
const BUS_WIDTH: float = 32.0
const BOUNDS: Rect2 = Rect2(0, 0, 1920, 1536)
# Town streets stay compact; grass padding around them leaves off-screen spawn room.
const PAD: float = 320.0
const ROUTE_HINT: String = "中央路口集合。东北过石桥是商店街（便利店、售货机、杂货铺）；运河只能从石桥或南面木桥通过。仓库在最远端。"



static func _nav_body(block: Rect2) -> Rect2:
	var a: Dictionary = _axis()
	var north: float = float(a.north_walk)
	var yard: float = float(a.south_walk) + WALK_WIDTH
	var inset: float = 16.0
	if absf(block.end.y - north) <= 1.0 and block.size.y > inset:
		return Rect2(block.position, Vector2(block.size.x, block.size.y - inset))
	if absf(block.position.y - yard) <= 1.0 and block.size.y > inset:
		return Rect2(Vector2(block.position.x, block.position.y + inset), Vector2(block.size.x, block.size.y - inset))
	return block


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
	var bus: Rect2 = WorldLayout.rect(data.bus.rect)
	# The 108x32 van stays centered in the 64-wide lane, leaving about 16px of
	# asphalt on each side. bus_block matches the visible body so the sprite
	# foot and shot blocker stay aligned; navigation insets the body in
	# StreetLayout.blockers() so those side strips remain walkable.
	result.bus_block = bus
	result.bus_door = WorldLayout.point(data.bus.door)
	for entity: Dictionary in data.entities:
		# Visual footprints stay flush to the curb; navigation bodies are inset
		# so the 32-wide sidewalk still has a corridor after footprint inflation.
		result.residences.append(_nav_body(WorldLayout.rect(entity.rect)))
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
	result.camera_start = result.bus_door + Vector2(200, 16)
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


static func _axis() -> Dictionary:
	var ns_x: float = NS_CENTER - ROAD_WIDTH * 0.5
	var ew_y: float = EW_CENTER - ROAD_WIDTH * 0.5
	var east_walk: float = ns_x + ROAD_WIDTH
	var west_bank: float = east_walk + WALK_WIDTH
	var canal_x: float = west_bank + BANK_WIDTH
	var east_bank: float = canal_x + CANAL_WIDTH
	var east_edge: float = east_bank + BANK_WIDTH
	var north_walk: float = ew_y - WALK_WIDTH
	var south_walk: float = ew_y + ROAD_WIDTH
	var wood_y: float = south_walk + WOOD_GAP
	return {
		"ns_x": ns_x,
		"ew_y": ew_y,
		"west_walk": ns_x - WALK_WIDTH,
		"east_walk": east_walk,
		"north_walk": north_walk,
		"south_walk": south_walk,
		"west_bank": west_bank,
		"canal_x": canal_x,
		"east_bank": east_bank,
		"east_edge": east_edge,
		"canal_mid": (canal_x + east_bank) * 0.5,
		"wood_y": wood_y,
		"wood_end": wood_y + WOOD_WIDTH,
		"bus_y": EW_CENTER - BUS_WIDTH * 0.5,
	}


static func world_data(generated: Dictionary) -> Dictionary:
	var shops: Array[Dictionary] = _shop_templates()
	var houses: Array[Dictionary] = _house_templates()
	_bind_sites(shops, houses, generated)
	var entities: Array = []
	entities.append_array(shops)
	entities.append_array(houses)
	var a: Dictionary = _axis()
	var bus_y: float = float(a.bus_y)
	# Keep the gathering point at the previous lane center (x=684) so the
	# shorter van still sits mid-lane, just short of the north-south crossing.
	var bus_x: float = 684.0 - BUS_LENGTH * 0.5
	var bus_door_x: float = bus_x + BUS_LENGTH * 0.5
	var bus_door_y: float = bus_y - 8.0
	var mid: float = float(a.canal_mid)
	var wood_y: float = float(a.wood_y)
	var wood_end: float = float(a.wood_end)
	var south: float = float(a.south_walk)
	var ew_y: float = float(a.ew_y)
	var ns_x: float = float(a.ns_x)
	var west_walk: float = float(a.west_walk)
	var east_walk: float = float(a.east_walk)
	var west_bank: float = float(a.west_bank)
	var canal_x: float = float(a.canal_x)
	var east_bank: float = float(a.east_bank)
	var east_edge: float = float(a.east_edge)
	var north_walk: float = float(a.north_walk)
	return {
		"version": 5,
		"seaside_town": true,
		"authored": true,
		"id": generated.layout.id,
		"size": generated.layout.get("size", "medium"),
		"topology": generated.layout.get("topology", "commercial"),
		"bounds": [0, 0, 1920, 1536],
		"bus": {
			"rect": [bus_x, bus_y, BUS_LENGTH, BUS_WIDTH],
			"door": [bus_door_x, bus_door_y],
			"passenger_door": [bus_door_x, bus_door_y],
			"entry": [80, EW_CENTER],
			"exit": [1840, EW_CENTER],
			"stop": [bus_door_x, bus_y + BUS_WIDTH],
			"facing": "right",
			"sweep": [0, ew_y, 1920, ROAD_WIDTH],
		},
		"entities": entities,
		"barriers": [
			[canal_x, 0, CANAL_WIDTH, ew_y],
			[canal_x, south, CANAL_WIDTH, wood_y - south],
			[canal_x, wood_end, CANAL_WIDTH, BOUNDS.size.y - wood_end],
		],
		"roads": [
			[ns_x, 0, ROAD_WIDTH, BOUNDS.size.y],
			[0, ew_y, BOUNDS.size.x, ROAD_WIDTH],
			[east_walk + 16.0, wood_y, (east_edge + 16.0) - (east_walk + 16.0), WOOD_WIDTH],
		],
		"arrivals": [
			[660, north_walk + 24.0],
			[720, north_walk + 24.0],
			[570, EW_CENTER],
			[ns_x + 16.0, ew_y + 8.0],
		],
		"enemy_points": [
			[NS_CENTER, 80],
			[NS_CENTER, 1456],
			[80, EW_CENTER],
			[1840, EW_CENTER],
			[400, south + 16.0],
			[624, 920],
			[1080, 1088],
			[1360, 1088],
			[1360, north_walk + 16.0],
			[east_walk + 16.0, 80],
		],
		"rescue": [444, 1008],
		"objects": [],
		"parcels": [],
		"grounds": {
			"sidewalks": [
				[west_walk, 0, WALK_WIDTH, BOUNDS.size.y],
				[east_walk, 0, WALK_WIDTH, BOUNDS.size.y],
				[0, north_walk, BOUNDS.size.x, WALK_WIDTH],
				[0, south, BOUNDS.size.x, WALK_WIDTH],
			],
			"banks": [
				[west_bank, 0, BANK_WIDTH, ew_y],
				[west_bank, south, BANK_WIDTH, wood_y - south],
				[west_bank, wood_end, BANK_WIDTH, BOUNDS.size.y - wood_end],
				[east_bank, 0, BANK_WIDTH, ew_y],
				[east_bank, south, BANK_WIDTH, wood_y - south],
				[east_bank, wood_end, BANK_WIDTH, BOUNDS.size.y - wood_end],
			],
			"canal": [
				[canal_x, 0, CANAL_WIDTH, ew_y],
				[canal_x, south, CANAL_WIDTH, wood_y - south],
				[canal_x, wood_end, CANAL_WIDTH, BOUNDS.size.y - wood_end],
			],
			"crosswalks_ns": [
				[ns_x, ew_y, ROAD_WIDTH, 16.0],
				[ns_x, ew_y + ROAD_WIDTH - 16.0, ROAD_WIDTH, 16.0],
			],
			"crosswalks_ew": [
				[ns_x, ew_y, 16.0, ROAD_WIDTH],
				[ns_x + ROAD_WIDTH - 16.0, ew_y, 16.0, ROAD_WIDTH],
			],
		},
		"props": _scenery(),
	}


static func _shop_templates() -> Array[Dictionary]:
	var a: Dictionary = _axis()
	var edge: float = float(a.east_edge)
	var north: float = float(a.north_walk)
	var wood_end: float = float(a.wood_end)
	# Vendings sit on the bank-side plaza, off the 32-wide sidewalk so the
	# team can still pass the bus on the pavement.
	return [
		_entity("convenience", "food_main", "便利店", "buildings/convenience.png", [1080, north - 176.0, 224, 176], [1192, north + 16.0]),
		_entity("vending_a", "food_quick", "售货机", "props/vending_red.png", [edge + 8.0, north - 32.0, 32, 32], [edge + 24.0, north + 16.0]),
		_entity("vending_b", "food_quick", "售货机", "props/vending_blue.png", [edge + 48.0, north - 32.0, 32, 32], [edge + 64.0, north + 16.0]),
		_entity("grocery", "cash_shop", "杂货铺", "buildings/grocery.png", [1320, north - 160.0, 208, 160], [1424, north + 16.0]),
		_entity("bike_shelter", "optional", "自行车棚", "props/bike_shelter.png", [544, 880, 128, 80], [608, 984]),
		_entity("shrine", "optional", "小神社", "buildings/shrine.png", [400, 896, 88, 88], [444, 1008]),
		_entity("warehouse", "weapon", "渔具仓库", "buildings/warehouse.png", [edge + 32.0, wood_end, 288, 192], [edge + 176.0, wood_end + 208.0]),
	]


static func _house_templates() -> Array[Dictionary]:
	var a: Dictionary = _axis()
	var west: float = float(a.west_walk)
	var north: float = float(a.north_walk)
	var yard: float = float(a.south_walk) + WALK_WIDTH
	return [
		_entity("house_a", "house", "住宅", "buildings/house_a.png", [west - 312.0, north - 128.0, 160, 128], [west - 232.0, north + 16.0]),
		_entity("house_c2", "house", "住宅", "buildings/house_c.png", [west - 136.0, north - 160.0, 128, 160], [west - 72.0, north + 16.0]),
		_entity("house_c", "house", "住宅", "buildings/house_c.png", [400, yard, 128, 160], [464, yard + 184.0]),
		_entity("house_b", "house", "住宅", "buildings/house_b.png", [544, yard, 144, 144], [616, yard + 168.0]),
		_entity("house_a3", "house", "住宅", "buildings/house_a.png", [544, 1008, 128, 96], [608, 1128]),
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
		[1456, 416, 64, 64],
		[1456, 704, 64, 64],
		[1456, 992, 64, 64],
		[1008, 704, 64, 64],
		[1168, 704, 64, 64],
		[1360, 704, 64, 64],
		[1008, 1072, 64, 64],
		[1360, 1072, 64, 64],
		[400, 1056, 64, 64],
		[560, 1056, 64, 64],
		[400, 976, 64, 64],
		[672, 1056, 64, 64],
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
	var a: Dictionary = _axis()
	var west_mid: float = float(a.west_walk) + WALK_WIDTH * 0.5
	var east_mid: float = float(a.east_walk) + WALK_WIDTH * 0.5
	var north_mid: float = float(a.north_walk) + WALK_WIDTH * 0.5
	var south_mid: float = float(a.south_walk) + WALK_WIDTH * 0.5
	var mid: float = float(a.canal_mid)
	var south_road: float = float(a.south_walk)
	var wood_end: float = float(a.wood_end)
	return [
		{"art": "props/tram_stop.png", "point": [west_mid, north_mid], "kind": "tram"},
		{"art": "props/stone_bridge.png", "point": [mid, south_road], "kind": "bridge"},
		{"art": "props/wood_bridge.png", "point": [mid, wood_end], "kind": "bridge"},
		{"art": "props/lamp.png", "point": [west_mid, north_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [east_mid, north_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [west_mid, south_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [east_mid, south_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1016, north_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1192, north_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1320, north_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1424, north_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1192, south_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1424, south_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [632, north_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [632, south_mid], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1080, wood_end + 184.0], "kind": "lamp"},
		{"art": "props/lamp.png", "point": [1240, wood_end + 184.0], "kind": "lamp"},
		{"art": "props/tree.png", "point": [672, 1000], "kind": "tree"},
		{"art": "props/tree.png", "point": [east_mid, 464], "kind": "tree"},
		{"art": "props/tree.png", "point": [east_mid, south_mid + 64.0], "kind": "tree"},
		{"art": "props/tree.png", "point": [1488, 464], "kind": "tree"},
		{"art": "props/tree.png", "point": [1488, 992], "kind": "tree"},
		{"art": "props/tree.png", "point": [1224, 464], "kind": "tree"},
		{"art": "props/bike.png", "point": [west_mid - 8.0, north_mid], "kind": "bike"},
		{"art": "props/bike.png", "point": [float(a.west_walk), north_mid + 8.0], "kind": "bike"},
		{"art": "props/bike.png", "point": [568, 972], "kind": "bike"},
		{"art": "props/crate.png", "point": [1064, wood_end + 184.0], "kind": "crate"},
		{"art": "props/crate.png", "point": [1280, wood_end + 200.0], "kind": "crate"},
		{"art": "props/crate.png", "point": [1048, wood_end + 168.0], "kind": "crate"},
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
