class_name CapeStation
extends RefCounted
## Destination only: signed source sites, rewards and nominal work remain canonical.

const LOCATION_ID: String = "cape_station"
const TITLE: String = "海边町·岬角车站"
const BOUNDS: Rect2 = Rect2(0, 0, 2048, 1536)
const ROUTE_HINT: String = "巴士停在站前路西端。广场北侧是站房，西侧面包铺、东侧小卖部可搜集；低站台可从两端绕行，短轨不能穿越。所有作业均在屋外，留足回车时间。"
const EXCLUSIONS: Array[String] = ["finale_policy", "investigation", "rare_policy", "event_sortie", "recon", "barricade", "billboard", "billboard_target", "sortie_risk"]


static func should_apply(value: Dictionary) -> bool:
	if value.get("version") != 9 or value.get("type") != "supply" or int(value.get("day", 0)) < 4 or int(value.get("day", 0)) % 2 != 0:
		return false
	if value.get("campaign", {}).get("is_finale", false):
		return false
	for key: String in EXCLUSIONS:
		if value.has(key):
			return false
	return true


static func is_layout(street: StreetLayout) -> bool:
	return street != null and street.world_data.get("location_id", "") == LOCATION_ID


static func layout(generated: Dictionary) -> StreetLayout:
	var data: Dictionary = world_data(generated)
	var street: StreetLayout = StreetLayout.new()
	street.id = StringName(generated.layout.id)
	street.display_name = TITLE
	street.world_bounds = BOUNDS
	street.world_data = data
	street.bus_block = WorldLayout.rect(data.bus.rect)
	street.bus_door = WorldLayout.point(data.bus.door)
	for entity: Dictionary in data.entities:
		street.residences.append(WorldLayout.rect(entity.rect))
	for row: Array in data.barriers:
		street.fences.append(WorldLayout.rect(row))
	for row: Array in data.roads:
		street.roads.append(WorldLayout.rect(row))
	for row: Array in data.arrivals:
		street.arrivals.append(WorldLayout.point(row))
	for row: Array in data.enemy_points:
		street.enemy_points.append(WorldLayout.point(row))
	street.cash_block = WorldLayout.rect(data.entities[0].rect)
	street.food_block = WorldLayout.rect(data.entities[1].rect)
	street.cash_door = site_point(generated, "cash")
	street.food_door = site_point(generated, "food")
	street.cash_title = "站前寄存处"
	street.food_title = "岬角面包铺"
	street.rescue_point = Vector2(592, 1008)
	street.camera_start = Vector2(624, 976)
	street.route_hint = ROUTE_HINT
	return street


static func site_point(generated: Dictionary, site_id: String) -> Vector2:
	for entity: Dictionary in world_data(generated).entities:
		if entity.site_id == site_id:
			return WorldLayout.point(entity.door)
	return Vector2.INF


static func world_data(generated: Dictionary) -> Dictionary:
	var entities: Array[Dictionary] = [
		_entity("station", "岬角站寄存处", "station", [864, 512, 480, 256], [1104, 816]),
		_entity("bakery", "岬角面包铺", "bakery", [480, 704, 224, 192], [592, 944]),
		_entity("kiosk", "站前小卖部", "kiosk", [1472, 480, 160, 128], [1552, 656]),
		_entity("house_east", "蓝瓦民居", "house", [1472, 736, 256, 160], [1600, 944]),
		_entity("bicycle_shed", "自行车保管棚", "shed", [896, 1280, 192, 128], [992, 1456]),
		_entity("house_south", "坡下旧宅", "house", [1216, 1248, 256, 160], [1344, 1456]),
	]
	# Food objectives occupy the two shops; other signed sources stay one-to-one.
	var spare: Array[int] = [0, 3, 4, 5]
	var overflow: int = 0
	for site: Dictionary in generated.sites:
		var index: int = -1
		if site.kind == "food" and String(entities[1].site_id).is_empty():
			index = 1
		elif site.kind == "food" and String(entities[2].site_id).is_empty():
			index = 2
		elif not spare.is_empty():
			index = spare.pop_front()
		if index >= 0:
			entities[index].site_id = site.id
		else:
			var x: int = 64 if overflow % 2 == 0 else 1856
			var y: int = 96 + (overflow / 2) * 144
			var extra: Dictionary = _entity("parcel_%d" % overflow, "站前周转箱", "", [x, y, 64, 48], [x + 32, y + 80])
			extra.art = "harbor/cargo.svg"
			extra.site_id = site.id
			entities.append(extra)
			overflow += 1
	return {
		"version":5, "authored":true, "location_id":LOCATION_ID, "id":generated.layout.id,
		"size":generated.layout["size"], "topology":"commercial", "bounds":[0, 0, 2048, 1536],
		"entities":entities, "objects":[], "parcels":[], "barriers_block_shots":false,
		"bus":{"rect":[128, 1120, 108, 32], "door":[182, 1032], "passenger_door":[182, 1080],
			"entry":[-160, 1152], "exit":[2208, 1152], "facing":"right", "sweep":[0, 1088, 2048, 96]},
		"roads":[[0, 1088, 2048, 96], [256, 0, 96, 1088]],
		"barriers":[[640, 192, 1152, 96]],
		"arrivals":[[160, 984], [208, 984], [128, 1016], [240, 1016]],
		"enemy_points":[[304, 48], [48, 640], [48, 1328], [752, 48], [1568, 48],
			[1984, 448], [1984, 992], [1984, 1456], [768, 1488]],
		"grounds":{"concrete":[[384, 448, 1472, 608], [384, 1216, 1472, 320]],
			"gravel":[[576, 128, 1280, 224]],
			"sidewalks":[[0, 1056, 2048, 32], [0, 1184, 2048, 32], [224, 0, 32, 1056], [352, 0, 32, 1056]],
			"crosswalks_ew":[[736, 1088, 64, 96]]},
		"props":[
			{"art":"props/lamp.png", "point":[416, 1008], "kind":"lamp"},
			{"art":"props/lamp.png", "point":[1376, 1008], "kind":"lamp"},
			{"art":"props/lamp.png", "point":[1744, 464], "kind":"lamp"},
			{"art":"props/vending_green.png", "point":[1376, 768], "kind":"vending"},
			{"art":"props/tree.png", "point":[768, 672], "kind":"tree"},
			{"art":"props/tree_b.png", "point":[1760, 1248], "kind":"tree"},
		],
	}


static func _entity(id: String, title: String, art: String, body: Array, door: Array) -> Dictionary:
	return {"id":id, "title":title, "art":"station/" + art + ".svg", "rect":body, "door":door, "site_id":""}
