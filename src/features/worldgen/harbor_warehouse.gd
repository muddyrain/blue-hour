class_name HarborWarehouse
extends RefCounted
## Authored destination projection, like SeasideTown. Frozen offers remain untouched.

const LOCATION_ID: String = "north_harbor"
const TITLE: String = "海边町·北港仓库"
const BOUNDS: Rect2 = Rect2(0, 0, 2560, 1792)
const ROAD_WIDTH: float = 96.0
const WALK_WIDTH: float = 32.0
# PROJECT_TEMP: sealed cargo and sorting nets take longer than street pickups.
# This scales elapsed work, not signed progress units, rewards or global tuning.
const WORK_FACTOR: float = 1.5
const ROUTE_HINT: String = "西南装卸路停靠。穿过集装箱窄巷到东侧货台回收工具与装备；北侧冷库和渔具仓可追加搜集。东岸栈桥尽头没有出口，入夜前留足回车时间。"
const CHOKES: Array[Rect2] = [Rect2(640, 736, 320, 64), Rect2(1024, 736, 320, 64)]
static var _maps: Dictionary = {}


static func should_apply(value: Dictionary) -> bool:
	if value.get("version") != 9 or int(value.get("day", 0)) < 3 or value.get("type") != "airdrop":
		return false
	if value.get("campaign", {}).get("is_finale", false):
		return false
	# Those actions carry independently signed spatial anchors and keep their map.
	for key: String in ["finale_policy", "investigation", "rare_policy", "event_sortie", "recon", "barricade", "billboard", "billboard_target", "sortie_risk"]:
		if value.has(key):
			return false
	return true


static func is_layout(street: StreetLayout) -> bool:
	return street != null and street.world_data.get("location_id", "") == LOCATION_ID


static func layout(generated: Dictionary) -> StreetLayout:
	var data: Dictionary = world_data(generated)
	var street: StreetLayout = StreetLayout.new()
	# Receipts bind the original map ID, not a second mission or save format.
	street.id = StringName(generated.layout.id)
	street.display_name = TITLE
	street.world_bounds = BOUNDS
	street.world_data = data
	street.bus_block = WorldLayout.rect(data.bus.rect)
	street.bus_door = WorldLayout.point(data.bus.door)
	for row: Dictionary in data.entities:
		street.residences.append(WorldLayout.rect(row.rect))
	for row: Array in data.barriers:
		street.fences.append(WorldLayout.rect(row))
	for row: Array in data.roads:
		street.roads.append(WorldLayout.rect(row))
	for row: Array in data.arrivals:
		street.arrivals.append(WorldLayout.point(row))
	for row: Array in data.enemy_points:
		street.enemy_points.append(WorldLayout.point(row))
	street.cash_block = WorldLayout.rect(data.entities[0].rect)
	street.cash_door = site_point(generated, "cash")
	street.food_block = WorldLayout.rect(data.entities[1].rect)
	street.food_door = WorldLayout.point(data.entities[1].door)
	street.cash_title = "港口器材货台"
	street.food_title = "冷库配货处"
	street.rescue_point = Vector2(160, 1104)
	street.camera_start = Vector2(480, 1200)
	street.route_hint = ROUTE_HINT
	return street


static func site_point(generated: Dictionary, site_id: String) -> Vector2:
	for entity: Dictionary in world_data(generated).entities:
		if entity.site_id == site_id:
			return WorldLayout.point(entity.door)
	return Vector2.INF


static func world_data(generated: Dictionary) -> Dictionary:
	var key: String = RecordEncoding.fingerprint({"id":generated.layout.id, "sites":generated.sites})
	var cached: Variant = ActionMemo.lookup(_maps, key)
	if cached != null:
		return cached.duplicate(true)
	var entities: Array[Dictionary] = [
		_entity("cargo", "港口器材货台", "cargo", [1584, 688, 64, 48], [1616, 768]),
		_entity("cold_store", "冷库配货处", "cold_store", [1120, 192, 384, 256], [1312, 480]),
		_entity("fishery", "渔具仓库", "fishery", [576, 128, 352, 240], [752, 400]),
		_entity("workshop", "机修棚", "workshop", [576, 1056, 256, 176], [704, 1264]),
		_entity("office", "港务小屋", "office", [64, 864, 192, 144], [160, 1040]),
		_entity("ice_shed", "保冷周转间", "office", [1040, 1088, 192, 144], [1136, 1264]),
		_entity("container_a", "青灰货柜", "container_teal", [640, 608, 320, 128], [800, 768]),
		_entity("container_b", "陶红货柜", "container_clay", [640, 800, 320, 128], [800, 960]),
		_entity("container_c", "雾蓝货柜", "container_blue", [1024, 608, 320, 128], [1184, 768]),
		_entity("container_d", "米色货柜", "container_cream", [1024, 800, 320, 128], [1184, 960]),
		_entity("container_e", "待装船货柜", "container_clay", [1408, 1088, 320, 128], [1568, 1248]),
	]
	_bind_sites(entities, generated)
	var data: Dictionary = {
		"version":5, "authored":true, "location_id":LOCATION_ID, "id":generated.layout.id,
		"size":generated.layout["size"], "topology":"industrial", "bounds":[0, 0, 2560, 1792],
		"entities":entities, "objects":[], "parcels":[], "barriers_block_shots":false,
		"bus":{"rect":[128, 1440, 108, 32], "door":[182, 1360], "passenger_door":[182, 1400],
			"entry":[-160, 1472], "exit":[2720, 1472], "facing":"right", "sweep":[0, 1408, 2560, 96]},
		"roads":[[0, 1408, 2560, ROAD_WIDTH], [320, 0, ROAD_WIDTH, 1408]],
		"barriers":[
			[1792, 0, 768, 384], [2176, 384, 384, 192], [1792, 576, 768, 448],
			[2304, 1024, 256, 160], [1792, 1184, 768, 128],
			# Crane foundation and parked forklift are solid; small gear is dressing.
			[1648, 256, 96, 92], [1444, 886, 64, 58],
		],
		"arrivals":[[160, 1312], [208, 1312], [128, 1344], [240, 1344]],
		"enemy_points":[[368, 48], [48, 768], [48, 1168], [752, 48], [1584, 80],
			[1744, 528], [1728, 976], [2080, 1136], [2520, 1456], [1280, 1744]],
		"rescue":[160, 1104],
		"grounds":{
			"concrete":[[0, 0, 1792, 1792], [0, 1312, 2560, 480]],
			"sidewalks":[[288, 0, WALK_WIDTH, 1376], [416, 0, WALK_WIDTH, 1376],
				[0, 1376, 2560, WALK_WIDTH], [0, 1504, 2560, WALK_WIDTH]],
			"harbor_water":[[1792, 0, 768, 1312]],
			"harbor_wood":[[1792, 384, 384, 192], [1792, 1024, 512, 160]],
			"harbor_steel":[[1504, 576, 256, 224], [960, 608, 64, 320]],
		},
		"props":_scenery(),
	}
	ActionMemo.store(_maps, key, data.duplicate(true), 8)
	return data


static func _entity(id: String, title: String, art: String, body: Array, door: Array) -> Dictionary:
	return {"id":id, "title":title, "art":"harbor/" + art + ".svg", "rect":body, "door":door, "site_id":""}


static func _bind_sites(entities: Array[Dictionary], generated: Dictionary) -> void:
	var assigned: Array[String] = []
	# Value is inherited from the signed action; the deep cargo pad owns the main work.
	for site: Dictionary in generated.sites:
		if site.id == "cash":
			entities[0].site_id = site.id
			assigned.append(site.id)
	# One exterior work point per container group. The southern partner in each
	# paired stack is dressing; remaining signed sites use the open apron crates.
	var spare: Array[int] = [2, 3, 4, 5, 6, 8, 10]
	var overflow: int = 0
	for site: Dictionary in generated.sites:
		if site.id in assigned:
			continue
		var index: int = -1
		if site.kind == "food" and String(entities[1].site_id).is_empty():
			index = 1
		elif not spare.is_empty():
			index = spare.pop_front()
		if index >= 0:
			entities[index].site_id = site.id
		else:
			# Extra signed vehicle/tree sites become small exterior supply crates.
			# Keep every source fact once, with clear 128-unit lanes on the south apron.
			var x: int = 480 + (overflow % 7) * 256
			var y: int = 1568 + (overflow / 7) * 112
			var extra: Dictionary = _entity("supply_%d" % overflow, "码头周转箱", "cargo", [x, y, 64, 48], [x + 32, y + 80])
			extra.site_id = site.id
			entities.append(extra)
			overflow += 1
		assigned.append(site.id)


static func _scenery() -> Array:
	var props: Array = [
		{"art":"harbor/crane.svg", "point":[1696, 348], "kind":"crane"},
		{"art":"harbor/forklift.svg", "point":[1476, 952], "kind":"forklift"},
		{"art":"harbor/pallets.svg", "point":[880, 1200], "kind":"crate"},
		{"art":"harbor/pallets.svg", "point":[1680, 816], "kind":"crate"},
		{"art":"harbor/nets.svg", "point":[640, 432], "kind":"crate"},
		{"art":"harbor/nets.svg", "point":[1760, 1088], "kind":"crate"},
		{"art":"harbor/buoys.svg", "point":[1904, 480], "kind":"crate"},
		{"art":"harbor/buoys.svg", "point":[2072, 1120], "kind":"crate"},
		{"art":"harbor/barrels.svg", "point":[976, 368], "kind":"crate"},
		{"art":"harbor/barrels.svg", "point":[1376, 1176], "kind":"crate"},
		{"art":"harbor/pallets.svg", "point":[1552, 544], "kind":"crate"},
		{"art":"harbor/work_lamp.svg", "point":[256, 1280], "kind":"lamp"},
		{"art":"harbor/work_lamp.svg", "point":[544, 992], "kind":"lamp"},
		{"art":"harbor/work_lamp.svg", "point":[992, 528], "kind":"lamp"},
		{"art":"harbor/work_lamp.svg", "point":[1728, 816], "kind":"lamp"},
		{"art":"harbor/work_lamp.svg", "point":[2000, 1136], "kind":"lamp"},
	]
	for y: int in [112, 592, 864, 1232]:
		props.append({"art":"harbor/bollard.svg", "point":[1776, y], "kind":"rail"})
	for point: Array in [[1920, 544], [2128, 544], [1952, 1152], [2256, 1152]]:
		props.append({"art":"harbor/bollard.svg", "point":point, "kind":"rail"})
	return props
